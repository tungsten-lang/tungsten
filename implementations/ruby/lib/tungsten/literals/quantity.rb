# frozen_string_literal: true

module Tungsten
  class Quantity
    include Comparable

    attr_reader :value, :unit, :role, :origin, :semantic_kind
    attr_accessor :display_format # nil (default), Integer (decimal places), :rational

    def initialize(value, unit, role: nil, origin: nil, semantic_kind: nil)
      @value = value
      @unit = unit
      @role = role
      @origin = origin&.to_sym
      @semantic_kind = semantic_kind&.to_sym
    end

    # Ordinary quantities are vectors. Point semantics are opt-in except for
    # affine temperature units, which are points by definition.
    def point(origin = :default)
      copy_with(role: :point, origin:)
    end

    def delta(origin = @origin)
      copy_with(role: :delta, origin:)
    end

    def point?
      return @role == :point unless @role.nil?
      temperature_point?
    end

    def delta?
      return @role == :delta unless @role.nil?
      temperature_delta?
    end

    def vector?
      !point?
    end

    def as_kind(name)
      copy_with(semantic_kind: name)
    end

    def calibrate(calibration)
      calibration.apply(self)
    end

    # Sorites: a heap is closer to infinity than to any finite quantity.
    # Adding or removing finite stuff doesn't change that — `1 heap - 3 heaps == 1 heap`.
    def heap?
      @unit.components.size == 1 &&
        @unit.components.keys.first == "heap" &&
        @unit.components.values.first == 1
    end

    # A hole is countable but indivisible: `½ hole = 1 hole`. Any arithmetic that produces
    # a positive non-integer count rounds UP via `hole_count`; zero stays zero; negative raises.
    def hole?
      @unit.components.size == 1 &&
        @unit.components.keys.first == "hole" &&
        @unit.components.values.first == 1
    end

    def self.hole_count(x)
      return 0 if x.zero?
      raise DimensionError, "negative count of holes is undefined" if x < 0
      x.is_a?(Integer) ? x : x.ceil
    end

    # Wraps an arithmetic result so that hole-typed quantities snap to integer counts.
    def self.snap_hole(q)
      return q unless q.is_a?(Quantity) && q.hole?
      q.__send__(:copy_with, value: hole_count(q.value))
    end

    def +(other)
      return self if heap?
      return other if other.is_a?(Quantity) && other.heap?
      result = case other
               when Quantity
                 return Sandwich.new if pbj_pair?(other)
                 return add_temperature(other) if temperature_quantity?(other)
                 ensure_compatible!(other)
                 converted = convert_value(other)
                 addition_result(other, @value + converted)
               when Percentage
                 copy_with(value: @value * (1 + other.ratio))
               when Duration
                 ensure_time_dimension!("add a Duration")
                 self + duration_as_seconds_quantity(other)
               else
                 raise DimensionError, "cannot add #{other.class} to Quantity"
               end
      self.class.snap_hole(result)
    end

    # ♫ It's peanut butter jelly time! ♫
    # Detects the PB+J pair via underlying components rather than display
    # symbols so aliases like `pb` and `j` resolve to their canonicals.
    def pbj_pair?(other)
      # The compiled/runtime spelling joke: petabyte + joule gives PB + J.
      symbols = [@unit.symbol, other.unit.symbol].sort
      return true if symbols == ["J", "PB"] && @value == 1 && other.value == 1

      pair = [@unit.components.keys.sort, other.unit.components.keys.sort].sort
      pair == [["jelly"], ["peanutbutter"]]
    end

    def -(other)
      return self if heap?
      return other if other.is_a?(Quantity) && other.heap?
      result = case other
               when Quantity
                 return subtract_temperature(other) if temperature_quantity?(other)
                 ensure_compatible!(other)
                 converted = convert_value(other)
                 subtraction_result(other, @value - converted)
               when Percentage
                 copy_with(value: @value * (1 - other.ratio))
               when Duration
                 ensure_time_dimension!("subtract a Duration")
                 self - duration_as_seconds_quantity(other)
               else
                 raise DimensionError, "cannot subtract #{other.class} from Quantity"
               end
      self.class.snap_hole(result)
    end

    def *(other)
      ensure_non_affine_arithmetic!(other, "multiply")
      ensure_not_point_arithmetic!(other, "multiply")
      if heap?
        return Quantity.new(0, @unit) if other.is_a?(Numeric) && other.zero?
        return Quantity.new(0, @unit) if other.is_a?(Quantity) && other.value.zero?
        return self
      end
      if other.is_a?(Quantity) && other.heap?
        return Quantity.new(0, other.unit) if @value.zero?
        return other
      end
      result = case other
               when Quantity
                 new_unit = @unit * other.unit
                 new_value, new_unit = self.class.normalize_prefix_factor(@value * other.value, new_unit)
                 Quantity.new(new_value, new_unit).rescale
               when Numeric
                 copy_with(value: @value * other).rescale
               when Duration
                 self * duration_as_seconds_quantity(other)
               else
                 raise DimensionError, "cannot multiply Quantity by #{other.class}"
               end
      self.class.snap_hole(result)
    end

    def /(other)
      ensure_non_affine_arithmetic!(other, "divide")
      ensure_not_point_arithmetic!(other, "divide")
      if heap?
        if (other.is_a?(Numeric) && other.zero?) || (other.is_a?(Quantity) && other.value.zero?)
          raise DimensionError, "cannot divide a heap by zero"
        end
        return self
      end
      if other.is_a?(Quantity) && other.heap?
        return Quantity.new(0, @unit) unless @value.zero?
        raise DimensionError, "cannot divide zero by a heap"  # 0/∞ ambiguous; punt
      end
      result = case other
               when Quantity
                 new_value = coerce_division(@value, other.value)
                 new_unit = @unit / other.unit
                 new_value, new_unit = self.class.normalize_prefix_factor(new_value, new_unit)
                 Quantity.new(new_value, new_unit).rescale
               when Numeric
                 new_value = coerce_division(@value, other)
                 copy_with(value: new_value).rescale
               when Duration
                 self / duration_as_seconds_quantity(other)
               else
                 raise DimensionError, "cannot divide Quantity by #{other.class}"
               end
      self.class.snap_hole(result)
    end

    def **(exp)
      raise DimensionError, "can only raise Quantity to an integer power" unless exp.is_a?(Integer)
      ensure_non_affine_arithmetic!(nil, "raise to a power") unless exp == 1
      new_components = @unit.components.transform_values { |e| e * exp }
      dim = Units::Dimension.zero
      factor = 1
      exp.abs.times { dim = dim * @unit.dimension; factor *= @unit.factor }
      if exp.negative?
        dim = Units::Dimension.zero / dim
        factor = factor.is_a?(Float) ? 1.0 / factor : Rational(1, factor)
      end
      new_unit = Units::CompoundUnit.simplify(
        Units::CompoundUnit.new(dimension: dim, factor: factor, components: new_components)
      )
      copy_with(value: @value**exp, unit: new_unit,
                role: exp == 1 ? @role : nil, origin: exp == 1 ? @origin : nil)
    end

    # After multiplication or division, the unit's stored factor can carry
    # leftover prefix-factors that no longer correspond to anything in
    # `components` — e.g. `1 MHz · 1 ms` cancels {ms: 1, s: -1} from the
    # components hash but leaves the 10⁶ × 10⁻³ = 10³ in factor. Rather
    # than show "1 cycle" with a hidden 10³ factor, fold the discrepancy
    # into the displayed value: result becomes value=1000, factor=1.
    # Skipped while the unit's canonical_symbol is still active (e.g.
    # standalone `1 MHz` keeps the prefix factor as part of the MHz symbol).
    def self.normalize_prefix_factor(value, unit)
      return [value, unit] if unit.canonical_active?
      naive = Units.naive_factor(unit.components)
      return [value, unit] if naive == 0 || unit.factor == naive
      ratio = unit.factor.is_a?(Float) || naive.is_a?(Float) ? unit.factor.to_f / naive : unit.factor / naive
      new_value = value * ratio
      new_unit = Units::CompoundUnit.new(
        dimension: unit.dimension,
        factor: naive,
        offset: unit.offset,
        components: unit.components,
        display_forms: unit.display_forms
      )
      [new_value, new_unit]
    end

    def -@
      copy_with(value: -@value)
    end

    def coerce(other)
      case other
      when Numeric
        [CoercedScalar.new(other), self]
      else
        raise TypeError, "#{other.class} can't be coerced into Quantity"
      end
    end

    def <=>(other)
      if heap?
        return 0 if other.is_a?(Quantity) && other.heap?  # all heaps tie
        return 1 if other.is_a?(Quantity) || other.is_a?(Numeric)  # heap > finite
      end
      if other.is_a?(Quantity) && other.heap?
        return -1
      end
      return nil unless other.is_a?(Quantity)
      return nil unless @unit.compatible?(other.unit)
      to_si <=> other.to_si
    end

    def ==(other)
      if heap?
        return other.is_a?(Quantity) && other.heap?
      end
      return false unless other.is_a?(Quantity)
      return false if other.heap?
      return false unless @unit.compatible?(other.unit)
      (to_si - other.to_si).abs < 1e-10
    end

    def convert_to(target_str)
      target = Units.parse(target_str)
      unless @unit.compatible?(target)
        left_dim = Units.dimension_name(@unit.dimension)
        right_dim = Units.dimension_name(target.dimension)
        msg = "cannot convert #{left_dim} (#{@unit}) to #{right_dim} (#{target_str})"
        # If either side is a custom-dim unit (likely a typo), suggest a close
        # match from the registered unit names.
        suggestion = Units.suggest_unit(@unit.symbol) if @unit.dimension.custom?
        suggestion ||= Units.suggest_unit(target_str) if target.dimension.custom?
        msg += " — did you mean '#{suggestion}'?" if suggestion
        raise DimensionError, msg
      end
      si_value = @value * @unit.factor + @unit.offset
      new_value = (si_value - target.offset) / target.factor
      copy_with(value: new_value, unit: target)
    end

    # Convert through an explicitly named physical equivalence. These are
    # deliberately separate from ordinary `to`, which remains dimensional.
    def equivalent_to(target_str, using)
      target = Units.parse(target_str)
      source_si = to_si.to_f
      target_si = case using.to_sym
                  when :mass_energy
                    mass_energy_equivalent(source_si, target.dimension)
                  when :spectral
                    spectral_equivalent(source_si, target.dimension)
                  when :thermal
                    thermal_equivalent(source_si, target.dimension)
                  else
                    raise ArgumentError, "unknown physical equivalence: #{using}"
                  end
      Quantity.new((target_si - target.offset) / target.factor, target)
    end

    alias_method :equivalent, :equivalent_to

    TEMPERATURE_DELTA_FOR_POINT = {
      "K" => "ΔK", "°C" => "Δ°C", "°F" => "Δ°F", "°R" => "Δ°R",
      "°De" => "Δ°De", "°N" => "Δ°N", "°Ré" => "Δ°Ré", "°Rø" => "Δ°Rø", "°W" => "Δ°W"
    }.freeze

    def temperature_point?
      @unit.dimension == Units::TEMPERATURE
    end

    def temperature_delta?
      @unit.dimension == Units::TEMPERATURE_DELTA
    end

    def temperature_quantity?(other = nil)
      mine = temperature_point? || temperature_delta?
      return mine unless other
      mine && (other.temperature_point? || other.temperature_delta?)
    end

    def add_temperature(other)
      if point? && other.point?
        raise DimensionError, "cannot add two absolute temperatures; add a temperature difference instead"
      end
      if point? && other.delta?
        return copy_with(value: @value + delta_value_in(other, @unit),
                         origin: @origin || other.origin)
      end
      if delta? && other.point?
        return other.__send__(:copy_with,
                              value: other.value + delta_value_in(self, other.unit),
                              origin: other.origin || @origin)
      end
      ensure_compatible!(other)
      Quantity.new(@value + convert_value(other), @unit)
    end

    def subtract_temperature(other)
      if point? && other.point?
        delta_symbol = TEMPERATURE_DELTA_FOR_POINT.fetch(@unit.symbol, "ΔK")
        delta_unit = Units.parse(delta_symbol)
        explicit_role = (@role == :point || other.role == :point) ? :delta : nil
        return copy_with(value: (to_si - other.to_si) / delta_unit.factor,
                         unit: delta_unit, role: explicit_role, origin: @origin || other.origin)
      end
      if point? && other.delta?
        return copy_with(value: @value - delta_value_in(other, @unit),
                         origin: @origin || other.origin)
      end
      if delta? && other.point?
        raise DimensionError, "cannot subtract an absolute temperature from a temperature difference"
      end
      ensure_compatible!(other)
      Quantity.new(@value - convert_value(other), @unit)
    end

    def delta_value_in(delta, point_unit)
      delta.value * delta.unit.factor / point_unit.factor
    end

    def ensure_non_affine_arithmetic!(other, operation)
      affine = point? && temperature_point? && !@unit.offset.zero?
      affine ||= other.is_a?(Quantity) && other.point? && other.temperature_point? && !other.unit.offset.zero?
      return unless affine
      raise DimensionError, "cannot #{operation} an affine absolute temperature; convert it to kelvin or use a temperature difference"
    end

    def ensure_not_point_arithmetic!(other, operation)
      return unless point? || (other.is_a?(Quantity) && other.point?)
      raise DimensionError, "cannot #{operation} an affine point; subtract points or operate on a delta"
    end

    def to_s
      # Easter egg: 1 microcentury ≈ 52.6 minutes ≈ length of a lecture
      if @unit.symbol == "microcentury" && @value == 1
        return "\u2248 length of a good lecture."
      end

      # Easter egg: barn·megaparsec ≈ π mL (famous physics joke — actual value ≈ 3.086 mL)
      if @unit.symbol&.include?("barn") && @unit.symbol&.include?("parsec")
        ml_value = (@value * @unit.factor) / 1e-6  # convert to mL
        if (ml_value - Math::PI).abs / Math::PI < 0.05
          return "\u2248\u03C0 mL"
        end
      end

      fmt = case @display_format
            when Integer then format_rounded(@value, @display_format)
            when :rational then format_as_fraction(@value)
            else format_value(@value)
            end
      rendered = "#{fmt} #{display_unit_symbol}"
      if @role == :point
        "(#{rendered}).point(:#{@origin || :default})"
      elsif @role == :delta
        @origin ? "(#{rendered}).delta(:#{@origin})" : "(#{rendered}).delta"
      elsif @semantic_kind
        "(#{rendered}).as_kind(:#{@semantic_kind})"
      else
        rendered
      end
    end

    # Pluralizes the unit symbol when the displayed value isn't ±1 and the
    # unit is a single noun-component (e.g. `6000 revolutions`, but not
    # `1 revolution`, `120 bpm` (canonical-acronym), or `1 cycle·m/s`
    # (compound)).
    def display_unit_symbol
      style = @display_compound || Tungsten.compound_display
      if style != :slash && !@unit.canonical_active? && !@unit.components.empty?
        # Skip single-component-with-exp-1 (regular "m", "kg" — bare name reads better
        # than slash/words/dot-negative form for those).
        single_simple = @unit.components.size == 1 && @unit.components.values.first == 1
        unless single_simple
          return Units::CompoundUnit.symbol_from_components(
            @unit.components, @unit.display_forms, style: style
          )
        end
      end

      base = @unit.symbol
      return base if @unit.canonical_active?
      return base unless @unit.components.size == 1
      name, exp = @unit.components.first
      return base unless exp == 1
      return base unless Units::PLURALIZABLE.include?(name)
      return base if @value == 1 || @value == -1
      # If the user typed an alias ("frames"/"revolutions"), they already
      # chose a display form — don't double-pluralize it.
      return base if @unit.display_forms.key?(name)
      "#{base}s"
    end

    # Returns a copy of this Quantity with the given display preferences attached.
    # `compound:` controls how compound units render: :slash (default), :dot_negative
    # (`m·s⁻¹`), or :words (`meters per second`). Doesn't mutate the original.
    def display(compound: nil)
      copy = copy_with
      copy.display_format = @display_format
      copy.instance_variable_set(:@display_compound, compound || @display_compound)
      copy
    end

    def inspect
      to_s
    end

    def rescale
      # Skip rescale on Measurement-valued Quantities — rescale's integer-rounding
      # heuristic would drop uncertainty.
      return self if @value.is_a?(Measurement)
      candidates = Units::SIMPLIFICATION_TABLE[@unit.dimension]
      return self unless candidates && !candidates.empty?
      si_value = @value * @unit.factor
      best = send(:rescale_candidate, si_value, candidates)
      return self unless best
      sym, factor, int_value = best
      copy_with(value: int_value, unit: Units::CompoundUnit.new(
        dimension: @unit.dimension, factor: factor, components: {sym => 1}
      ))
    end

    def to_si
      @value * @unit.factor + @unit.offset
    end

    # Multi-line introspection of this quantity's unit — description, defining source,
    # year defined, factor, aliases. Useful in REPL via `q.info` (or future `?` syntax).
    def info
      sym = @unit.canonical_symbol || @unit.symbol
      detail = Units.info(sym)
      header = "#{format_value(@value)} #{display_unit_symbol}"
      detail ? "#{header}\n#{detail}" : header
    end

    private

    def copy_with(value: @value, unit: @unit, role: @role, origin: @origin, semantic_kind: @semantic_kind)
      copy = Quantity.new(value, unit, role:, origin:, semantic_kind:)
      copy.display_format = @display_format
      copy.instance_variable_set(:@display_compound, @display_compound)
      copy
    end

    def ensure_origins_compatible!(other)
      return if @origin.nil? || other.origin.nil? || @origin == other.origin
      raise DimensionError, "cannot combine points/deltas with origins #{@origin.inspect} and #{other.origin.inspect}"
    end

    def addition_result(other, value)
      ensure_origins_compatible!(other)
      if point? && other.point?
        raise DimensionError, "cannot add two points; add a delta to a point instead"
      end
      if point?
        return copy_with(value:, role: :point, origin: @origin || other.origin)
      end
      if other.point?
        return other.__send__(:copy_with, value:, unit: @unit, role: :point, origin: other.origin || @origin)
      end
      role = (delta? || other.delta?) ? :delta : nil
      copy_with(value:, role:, origin: @origin || other.origin)
    end

    def subtraction_result(other, value)
      ensure_origins_compatible!(other)
      if point? && other.point?
        return copy_with(value:, role: :delta, origin: @origin || other.origin)
      end
      if point?
        return copy_with(value:, role: :point, origin: @origin || other.origin)
      end
      if other.point?
        raise DimensionError, "cannot subtract a point from a vector or delta"
      end
      role = (delta? || other.delta?) ? :delta : nil
      copy_with(value:, role:, origin: @origin || other.origin)
    end

    def mass_energy_equivalent(source_si, target_dimension)
      c2 = 299_792_458.0**2
      return source_si * c2 if @unit.dimension == Units::MASS && target_dimension == Units::ENERGY
      return source_si / c2 if @unit.dimension == Units::ENERGY && target_dimension == Units::MASS
      raise DimensionError, "mass_energy equivalence requires mass and energy"
    end

    def spectral_equivalent(source_si, target_dimension)
      c = 299_792_458.0
      h = 6.626_070_15e-34
      source_dimension = @unit.dimension
      if source_dimension == Units::LENGTH
        return c / source_si if frequency_dimension?(target_dimension)
        return h * c / source_si if target_dimension == Units::ENERGY
      elsif frequency_dimension?(source_dimension)
        return c / source_si if target_dimension == Units::LENGTH
        return h * source_si if target_dimension == Units::ENERGY
      elsif source_dimension == Units::ENERGY
        return h * c / source_si if target_dimension == Units::LENGTH
        return source_si / h if frequency_dimension?(target_dimension)
      end
      raise DimensionError, "spectral equivalence requires length, frequency, or photon energy"
    end

    def thermal_equivalent(source_si, target_dimension)
      boltzmann = 1.380_649e-23
      if temperature_dimension?(@unit.dimension) && target_dimension == Units::ENERGY
        return source_si * boltzmann
      end
      if @unit.dimension == Units::ENERGY && temperature_dimension?(target_dimension)
        return source_si / boltzmann
      end
      raise DimensionError, "thermal equivalence requires temperature and energy"
    end

    def frequency_dimension?(dimension)
      dimension == Units::FREQUENCY || dimension.customs.key?("cycle")
    end

    def temperature_dimension?(dimension)
      dimension == Units::TEMPERATURE || dimension == Units::TEMPERATURE_DELTA
    end

    # Convert a Duration to a Quantity[time] in seconds for arithmetic interop.
    # Rejects Durations with nominal months — month length depends on calendar
    # context, so callers should use Duration math directly when months matter.
    def duration_as_seconds_quantity(dur)
      if dur.months != 0
        raise DimensionError,
              "cannot mix a Duration with nominal months and a Quantity (months are calendar-dependent)"
      end
      s_unit = Units::CompoundUnit.new(dimension: Units::TIME, factor: 1, components: {"s" => 1})
      Quantity.new(dur.seconds, s_unit)
    end

    def ensure_time_dimension!(verb)
      return if @unit.dimension == Units::TIME
      raise DimensionError,
            "cannot #{verb} to a #{Units.dimension_name(@unit.dimension)} (#{@unit}) quantity"
    end

    # Use Rational division when integer division would lose precision.
    def coerce_division(a, b)
      if a.is_a?(Integer) && b.is_a?(Integer) && a % b != 0
        Rational(a, b)
      else
        a / b
      end
    end

    def ensure_compatible!(other)
      if @semantic_kind != other.semantic_kind && (@semantic_kind || other.semantic_kind)
        raise DimensionError, "cannot combine semantic kinds #{@semantic_kind || :unspecified} and #{other.semantic_kind || :unspecified}"
      end
      unless @unit.compatible?(other.unit)
        left_dim = Units.dimension_name(@unit.dimension)
        right_dim = Units.dimension_name(other.unit.dimension)
        raise DimensionError, "cannot combine #{left_dim} (#{@unit}) with #{right_dim} (#{other.unit})"
      end
    end

    def format_value(v)
      if v.is_a?(Rational)
        return v.to_i.to_s if v.denominator == 1
        return format_rational(v)
      end
      if v == v.to_i
        int = v.to_i
        if int.abs >= 1_000_000_000
          exp = Math.log10(int.abs).floor
          coeff = int.to_f / 10**exp
          rounded = coeff.round(3)
          rounded = rounded == rounded.to_i ? rounded.to_i : rounded
          "≈#{rounded}×10#{Units.exponent_to_superscript(exp)}"
        else
          int.to_s
        end
      else
        v.is_a?(BigDecimal) ? v.to_s("F") : v.to_s
      end
    end

    def format_rounded(v, places)
      r = v.is_a?(Rational) ? BigDecimal(v, 15) : BigDecimal(v.to_s)
      rounded = r.round(places)
      str = rounded.to_s("F")
      parts = str.split(".")
      parts[1] = (parts[1] || "0").ljust(places, "0")[0, places]
      places > 0 ? parts.join(".") : parts[0]
    end

    def format_as_fraction(v)
      return v.to_s if v.is_a?(Rational)
      v.is_a?(Integer) ? "#{v}/1" : v.to_s
    end

    # Cap on the number of fractional digits we'll grind through looking for
    # a repeating-decimal cycle. Denominators with large multiplicative order
    # of 10 (e.g. results of °F→°C conversions) can have astronomically long
    # periods; past this point the vinculum form is illegible anyway, so we
    # fall back to a rounded decimal.
    MAX_VINCULUM_CYCLE = 78

    # Format a Rational as a decimal, using vinculum (combining overline)
    # for repeating digits.  e.g. 1/3 → "0.3̅", 1/6 → "0.16̅"
    # Falls back to rounded decimal when the cycle exceeds MAX_VINCULUM_CYCLE.
    def format_rational(r)
      sign = r < 0 ? "-" : ""
      r = r.abs
      int_part = r.to_i
      num = (r - int_part).numerator
      den = (r - int_part).denominator

      return "#{sign}#{int_part}" if num.zero?

      digits = []
      remainders = {}

      while num != 0
        if remainders.key?(num)
          repeat_start = remainders[num]
          non_rep = digits[0...repeat_start].join
          rep = digits[repeat_start..].join
          rep_vinculum = rep.chars.map { |c| "#{c}\u0305" }.join
          return "#{sign}#{int_part}.#{non_rep}#{rep_vinculum}"
        end

        return format_rounded(sign == "-" ? -r : r, 6) if digits.length >= MAX_VINCULUM_CYCLE

        remainders[num] = digits.length
        num *= 10
        digits << (num / den).to_s
        num %= den
      end

      # Terminating decimal
      "#{sign}#{int_part}.#{digits.join}"
    end

    def rescale_candidate(si_value, candidates)
      best = nil
      candidates.each do |sym, factor|
        next if factor == @unit.factor
        next if factor.zero?
        # Only rescale to units in UNIT_TABLE with matching dimension
        next unless (u = Units::UNIT_TABLE[sym]) && u.dimension == @unit.dimension
        new_value = si_value / factor
        next if new_value.abs > 1e15 # Float precision insufficient for integer check
        next unless (new_value - new_value.round).abs < 1e-9
        int_value = new_value.round
        next if int_value == 0
        next if int_value.abs >= @value.abs # only simplify to smaller values
        best = [sym, factor, int_value] if best.nil? || int_value.abs < best[2].abs
      end
      best
    end

    public

    # Returns a new Quantity rescaled to the SI prefix that puts the displayed
    # value in a human-readable range (default: 1 ≤ |v| < 1000):
    #
    #   (1500.m).humanize     # => 1.5 km
    #   (0.001.g).humanize    # => 1 mg
    #   (1234567.Hz).humanize # => 1.234567 MHz
    #
    # Only considers SI-prefix variants of the same base unit — won't switch
    # `1500 m` to furlongs. Returns self if no better prefix exists or if the
    # current unit isn't prefixable.
    def humanize(lo: 1.0, hi: 1000.0)
      # Compound canonicals (Hz, V, J, etc.) carry an active canonical_symbol —
      # treat them as a single-symbol unit for prefix selection purposes.
      base_sym = if @unit.canonical_active?
                   @unit.canonical_symbol
                 elsif @unit.components.size == 1 && @unit.components.values.first == 1
                   @unit.components.keys.first
                 end
      return self unless base_sym

      # Base unit must be in PREFIXABLE — otherwise SI prefixes don't apply.
      bare_base = strip_si_prefix(base_sym)
      return self unless bare_base && Units::PREFIXABLE.include?(bare_base)
      base_unit = Units::UNIT_TABLE[bare_base]
      return self unless base_unit

      si_value = @value * @unit.factor
      return self if si_value.zero?

      best = nil
      best_score = Float::INFINITY

      # Try engineering-style SI prefixes (powers of 10³) on the bare base unit.
      # Skips deci/centi/deka/hecto since they're rarely how people quote magnitudes.
      Units::PREFIX_TABLE.merge("" => 1).each do |prefix, mult|
        # Engineering notation only: factors are powers of 10³.
        log_mult = Math.log10(mult.to_f).round
        next unless (log_mult % 3).zero?
        sym = "#{prefix}#{bare_base}"
        # Skip ambiguous cases — e.g., a single-letter prefix that creates a different real unit.
        next if !prefix.empty? && Units::UNIT_ALIASES.key?(sym) &&
                Units::UNIT_ALIASES[sym] != bare_base
        factor = base_unit.factor * mult
        new_value = si_value / factor.to_f
        abs_v = new_value.abs
        score = if abs_v >= lo && abs_v < hi
                  0.0
                elsif abs_v < lo
                  Math.log10(lo / abs_v)
                else
                  Math.log10(abs_v / hi)
                end
        if score < best_score
          best_score = score
          best = [sym, factor, new_value]
        end
      end

      return self unless best
      sym, factor, new_value = best
      copy_with(value: new_value, unit: Units::CompoundUnit.new(
        dimension: @unit.dimension, factor: factor, components: {sym => 1}
      ))
    end

    private

    # Strips a leading SI prefix from a unit symbol, returning the bare base if
    # the result is a registered unit. `km` → `m`, `MHz` → `Hz`. Returns the
    # input unchanged (as the bare form) if no prefix matches.
    def strip_si_prefix(sym)
      return sym if Units::UNIT_TABLE.key?(sym) && Units::PREFIXABLE.include?(sym)
      Units::PREFIX_TABLE.each_key do |p|
        next if p.empty?
        next unless sym.start_with?(p)
        rest = sym[p.length..]
        return rest if Units::UNIT_TABLE.key?(rest) && Units::PREFIXABLE.include?(rest)
      end
      nil
    end

    public

    def convert_value(other)
      if @unit.symbol == other.unit.symbol
        other.value
      else
        si = other.value * other.unit.factor + other.unit.offset
        (si - @unit.offset) / @unit.factor
      end
    end

    # Wrapper to enable `3 * 5.m` via coerce
    class CoercedScalar
      def initialize(value)
        @value = value
      end

      def *(quantity)
        if quantity.heap?
          return Quantity.new(0, quantity.unit) if @value.zero?
          return quantity
        end
        Quantity.snap_hole(Quantity.new(@value * quantity.value, quantity.unit))
      end

      def /(quantity)
        raise DimensionError, "cannot divide scalar by Quantity"
      end

      def +(quantity)
        raise DimensionError, "cannot add scalar to Quantity"
      end

      def -(quantity)
        raise DimensionError, "cannot subtract Quantity from scalar"
      end
    end
  end
end

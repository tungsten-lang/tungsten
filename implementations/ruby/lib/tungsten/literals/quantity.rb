# frozen_string_literal: true

module Tungsten
  class Quantity
    include Comparable

    attr_reader :value, :unit
    attr_accessor :display_format # nil (default), Integer (decimal places), :rational

    def initialize(value, unit)
      @value = value
      @unit = unit
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
      Quantity.new(hole_count(q.value), q.unit)
    end

    def +(other)
      return self if heap?
      return other if other.is_a?(Quantity) && other.heap?
      result = case other
               when Quantity
                 return Sandwich.new if pbj_pair?(other)
                 ensure_compatible!(other)
                 converted = convert_value(other)
                 Quantity.new(@value + converted, @unit)
               when Percentage
                 Quantity.new(@value * (1 + other.ratio), @unit)
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
      pair = [@unit.components.keys.sort, other.unit.components.keys.sort].sort
      pair == [["jelly"], ["peanutbutter"]]
    end

    def -(other)
      return self if heap?
      return other if other.is_a?(Quantity) && other.heap?
      result = case other
               when Quantity
                 ensure_compatible!(other)
                 converted = convert_value(other)
                 Quantity.new(@value - converted, @unit)
               when Percentage
                 Quantity.new(@value * (1 - other.ratio), @unit)
               when Duration
                 ensure_time_dimension!("subtract a Duration")
                 self - duration_as_seconds_quantity(other)
               else
                 raise DimensionError, "cannot subtract #{other.class} from Quantity"
               end
      self.class.snap_hole(result)
    end

    def *(other)
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
                 Quantity.new(@value * other, @unit).rescale
               when Duration
                 self * duration_as_seconds_quantity(other)
               else
                 raise DimensionError, "cannot multiply Quantity by #{other.class}"
               end
      self.class.snap_hole(result)
    end

    def /(other)
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
                 Quantity.new(new_value, @unit).rescale
               when Duration
                 self / duration_as_seconds_quantity(other)
               else
                 raise DimensionError, "cannot divide Quantity by #{other.class}"
               end
      self.class.snap_hole(result)
    end

    def **(exp)
      raise DimensionError, "can only raise Quantity to an integer power" unless exp.is_a?(Integer)
      new_components = @unit.components.transform_values { |e| e * exp }
      dim = Units::Dimension.zero
      factor = 1
      exp.times { dim = dim * @unit.dimension; factor *= @unit.factor }
      new_unit = Units::CompoundUnit.simplify(
        Units::CompoundUnit.new(dimension: dim, factor: factor, components: new_components)
      )
      Quantity.new(@value**exp, new_unit)
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
      Quantity.new(-@value, @unit)
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
      Quantity.new(new_value, target)
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
      "#{fmt} #{display_unit_symbol}"
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
      copy = Quantity.new(@value, @unit)
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
      Quantity.new(int_value, Units::CompoundUnit.new(
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
      Quantity.new(new_value, Units::CompoundUnit.new(
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

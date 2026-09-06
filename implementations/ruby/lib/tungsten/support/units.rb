# frozen_string_literal: true

require "set"
registry_reader = File.expand_path("../../../../../scripts/lib/unit_registry.rb", __dir__)
if File.file?(registry_reader)
  require registry_reader
else
  require_relative "../generated_unit_registry"
end

module Tungsten
  module Units
    Dimension = Struct.new(:length, :mass, :time, :current, :temperature, :substance, :luminosity, :information) do
      def self.zero
        new(0, 0, 0, 0, 0, 0, 0, 0)
      end

      # A Dimension is the eight SI base exponents PLUS a sparse hash of
      # custom-tag exponents (`{tag => exp}`). The custom hash supports two
      # kinds of work:
      #   • Symbolic-arithmetic carriers (π, c) where `2π · 3π = 6π²`.
      #   • Compositional unit numerators (revolution, cycle, decay) where
      #     `Hz = cycle/s` and `Hz · s = cycle` cleanly.
      # A custom tag and SI exponents coexist on the same Dimension, so
      # `cycle/s` is `customs={cycle: 1}, time: -1` — multiply by `s`, the
      # time exponent zeroes out, custom remains.
      def self.custom(name, exp = 1)
        dim = new(0, 0, 0, 0, 0, 0, 0, 0)
        dim.instance_variable_set(:@customs, { name => exp })
        dim
      end

      def customs
        instance_variable_get(:@customs) || {}
      end

      def custom?
        !customs.empty?
      end

      # Returns the single custom tag name if there's exactly one with exp 1.
      # Used by code that pre-dates multi-tag dimensions.
      def custom_name
        return nil unless customs.size == 1
        name, exp = customs.first
        exp == 1 ? name : nil
      end

      def custom_exp
        return 1 if customs.empty?
        customs.values.first
      end

      def +(other)
        raise DimensionError, "incompatible dimensions" unless self == other
        self
      end

      def -(other)
        raise DimensionError, "incompatible dimensions" unless self == other
        self
      end

      def *(other)
        return other if dimensionless?
        return self if other.dimensionless?

        merged_customs = {}
        (customs.keys | other.customs.keys).each do |k|
          sum = customs.fetch(k, 0) + other.customs.fetch(k, 0)
          merged_customs[k] = sum unless sum.zero?
        end

        result = self.class.new(
          length + other.length, mass + other.mass, time + other.time,
          current + other.current, temperature + other.temperature,
          substance + other.substance, luminosity + other.luminosity,
          information + other.information
        )
        result.instance_variable_set(:@customs, merged_customs) unless merged_customs.empty?
        result
      end

      def /(other)
        return self if other.dimensionless?

        merged_customs = customs.dup
        other.customs.each do |k, e|
          merged_customs[k] = (merged_customs[k] || 0) - e
          merged_customs.delete(k) if merged_customs[k].zero?
        end

        result = self.class.new(
          length - other.length, mass - other.mass, time - other.time,
          current - other.current, temperature - other.temperature,
          substance - other.substance, luminosity - other.luminosity,
          information - other.information
        )
        result.instance_variable_set(:@customs, merged_customs) unless merged_customs.empty?
        result
      end

      def dimensionless?
        customs.empty? && length == 0 && mass == 0 && time == 0 &&
          current == 0 && temperature == 0 && substance == 0 && luminosity == 0 &&
          information == 0
      end

      def ==(other)
        return false unless other.is_a?(Dimension)
        length == other.length && mass == other.mass && time == other.time &&
          current == other.current && temperature == other.temperature &&
          substance == other.substance && luminosity == other.luminosity &&
          information == other.information &&
          customs == other.customs
      end

      alias_method :eql?, :==

      def hash
        [length, mass, time, current, temperature, substance, luminosity, information, customs].hash
      end
    end

    # `measured` is true when the SI factor is an experimental measurement subject
    # to refinement (e.g. astronomy, particle masses pre-2019); false when the
    # factor is exact by definition (e.g. metre, second, all post-2019 SI bases).
    # `defining_source` and `year_defined` document the authority and date.
    #
    # `prefixable` controls which prefix systems can attach to this unit:
    #   :si      — SI metric prefixes (k, M, G, m, µ, n, …)
    #   :binary  — IEC binary prefixes (Ki, Mi, Gi, …) — for byte/bit
    #   :both    — accepts both SI and binary
    #   :none    — no prefixes (default)
    UnitDef = Struct.new(:symbol, :dimension, :factor, :offset,
                         :description, :measured, :year_defined, :defining_source,
                         :prefixable, :etymology, :history, :kind,
                         keyword_init: true) do
      def initialize(symbol:, dimension:, factor: 1, offset: 0,
                     description: nil, measured: false, year_defined: nil, defining_source: nil,
                     prefixable: :none, etymology: nil, history: nil, kind: :unit)
        super(symbol: symbol, dimension: dimension,
              factor: factor.is_a?(Float) ? factor.rationalize : factor,
              offset: offset.is_a?(Float) ? offset.rationalize : offset,
              description: description, measured: measured,
              year_defined: year_defined, defining_source: defining_source,
              prefixable: prefixable, etymology: etymology, history: history, kind: kind)
      end

      def si_prefixable?
        prefixable == :si || prefixable == :both
      end

      def binary_prefixable?
        prefixable == :binary || prefixable == :both
      end
    end

    class CompoundUnit
      attr_reader :dimension, :factor, :offset, :components, :display_forms, :canonical_symbol, :canonical_components

      def initialize(symbol: nil, dimension:, factor: 1, offset: 0, components: nil, display_forms: {},
                     canonical_symbol: nil, canonical_components: nil)
        @dimension = dimension
        @factor = factor.is_a?(Float) ? factor.rationalize : factor
        @offset = offset.is_a?(Float) ? offset.rationalize : offset
        @components = components || (symbol ? {symbol => 1} : {})
        @display_forms = display_forms
        # Compositional units (Hz = cycle/s, rpm = revolution/min) carry the
        # canonical symbol so `1 Hz` displays as "1 Hz" — but only while the
        # components match. Once arithmetic mutates them, canonical drops and
        # symbol_from_components takes over (so Hz·s renders as "cycle").
        @canonical_symbol = canonical_symbol
        @canonical_components = canonical_components
      end

      def symbol
        if canonical_active?
          return @canonical_symbol
        end
        self.class.symbol_from_components(@components, @display_forms)
      end

      def canonical_active?
        !!@canonical_symbol && @components == @canonical_components
      end

      def ==(other)
        return false unless other.is_a?(CompoundUnit)
        symbol == other.symbol
      end

      alias_method :eql?, :==

      def hash
        symbol.hash
      end

      def compatible?(other)
        dimension == other.dimension
      end

      def dimensionless?
        dimension.dimensionless?
      end

      def *(other)
        merged = @components.dup
        other.components.each { |u, e| merged[u] = (merged[u] || 0) + e }
        merged.delete_if { |_, e| e == 0 }
        self.class.cancel_cross_prefix!(merged)
        self.class.simplify(CompoundUnit.new(
          dimension: @dimension * other.dimension,
          factor: @factor * other.factor,
          components: merged,
          display_forms: @display_forms.merge(other.display_forms)
        ))
      end

      def /(other)
        merged = @components.dup
        other.components.each { |u, e| merged[u] = (merged[u] || 0) - e }
        merged.delete_if { |_, e| e == 0 }
        self.class.cancel_cross_prefix!(merged)
        self.class.simplify(CompoundUnit.new(
          dimension: @dimension / other.dimension,
          factor: @factor / other.factor,
          components: merged,
          display_forms: @display_forms.merge(other.display_forms)
        ))
      end

      # Cancels cross-prefix component pairs in place. After ordinary
      # exponent merging, looks for groups of components that share an
      # atomic identity (e.g. {ns: 1, s: -1} share atomic "s") and whose
      # signed exponents sum to zero — those collectively cancel.
      # The factor accounting in `*` and `/` already incorporated the
      # prefixes, so removing the components doesn't shift the SI value.
      # Only fully-cancelling groups are removed; partial overlaps
      # ({ms: 1, ns: 1} → atomic s, sum 2) are left alone since picking
      # one prefix-form as canonical would either drop info or shift factor.
      def self.cancel_cross_prefix!(components)
        by_atomic = Hash.new { |h, k| h[k] = [] }
        components.each { |name, exp| by_atomic[Units.atomic_of(name)] << name }
        by_atomic.each_value do |names|
          next if names.size < 2
          total = names.sum { |n| components[n] }
          names.each { |n| components.delete(n) } if total.zero?
        end
        components
      end

      def self.simplify(compound)
        return compound if compound.components.size == 1 && compound.components.values.first == 1
        # A pure power of a single SI base unit (m², m³, s²…) is already its
        # canonical form. Don't rename it to a same-factor alias such as "sqm"
        # (square metre) or "stere" (m³), which would shadow the natural m²/m³.
        # Prefixed/non-SI single bases (cm³ → mL) still simplify normally.
        if compound.components.size == 1 && Units.si_base_unit?(compound.components.keys.first)
          return compound
        end
        candidates = SIMPLIFICATION_TABLE[compound.dimension]
        return compound unless candidates
        candidates.each do |sym, factor|
          next if factor.zero?
          if (compound.factor - factor).abs < factor.abs * 1e-12
            return CompoundUnit.new(
              dimension: compound.dimension,
              factor: factor,
              components: {sym => 1}
            )
          end
        end
        compound
      end

      def to_s
        symbol
      end

      # Render this compound's components into a symbol. `style` controls the
      # display form for compounds with both positive and negative exponents:
      #   :slash         → `m/s`,  `kg·m/s²`,  `mol/L`              (default)
      #   :dot_negative  → `m·s⁻¹`, `kg·m·s⁻²`, `mol·L⁻¹`           (everything inline)
      #   :words         → `meters per second`, `kilogram-meters per second-squared per kelvin`
      def self.symbol_from_components(components, display_forms = {}, style: :slash)
        return "" if components.empty?
        disp = ->(u) { display_forms[u] || u }
        num = components.select { |_, e| e > 0 }.sort
        den = components.select { |_, e| e < 0 }.sort

        case style
        when :dot_negative
          parts = (num + den).map { |u, e| e == 1 ? disp.(u) : "#{disp.(u)}#{Units.exponent_to_superscript(e)}" }
          parts.join("·")
        when :words
          word_form_components(num, den, disp)
        else  # :slash
          sup = ->(n) { Units.exponent_to_superscript(n) }
          num_str = num.map { |u, e| e == 1 ? disp.(u) : "#{disp.(u)}#{sup.(e)}" }.join("·")
          den_str = den.map { |u, e| e == -1 ? disp.(u) : "#{disp.(u)}#{sup.(e.abs)}" }.join("·")
          if den_str.empty?
            num_str
          elsif num_str.empty?
            den.map { |u, e| "#{disp.(u)}#{sup.(e)}" }.join("·")
          else
            "#{num_str}/#{den_str}"
          end
        end
      end

      # Word-form rendering: "square meter per second", "cubic meter".
      # Used by symbol_from_components(style: :words). Powers 2 and 3 use the
      # English preposition prefix ("square X", "cubic X"); higher powers fall
      # back to "X to the Nth".
      def self.word_form_components(num, den, disp)
        word = ->(u, e) {
          name = disp.(u)
          e_abs = e.abs
          case e_abs
          when 1 then name
          when 2 then "square #{name}"
          when 3 then "cubic #{name}"
          else        "#{name} to the #{e_abs}"
          end
        }
        num_str = num.map { |u, e| word.(u, e) }.join("-")
        den_str = den.map { |u, e| word.(u, e) }.join("-")
        if den_str.empty?
          num_str
        elsif num_str.empty?
          # No numerator — `per square meter` reads naturally next to the value.
          "per #{den_str}"
        else
          "#{num_str} per #{den_str}"
        end
      end
    end


    SUPERSCRIPT_DIGITS = { "⁰" => "0", "¹" => "1", "²" => "2", "³" => "3", "⁴" => "4",
                           "⁵" => "5", "⁶" => "6", "⁷" => "7", "⁸" => "8", "⁹" => "9",
                           "⁻" => "-", "⁺" => "+" }.freeze
    DIGIT_SUPERSCRIPTS = { "0" => "⁰", "1" => "¹", "2" => "²", "3" => "³", "4" => "⁴",
                           "5" => "⁵", "6" => "⁶", "7" => "⁷", "8" => "⁸", "9" => "⁹",
                           "-" => "⁻", "+" => "⁺" }.freeze
    SUPERSCRIPT_RE = /[⁰¹²³⁴⁵⁶⁷⁸⁹⁻⁺]+/
    SUBSCRIPT_RE = /[₀₁₂₃₄₅₆₇₈₉ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓₔ]/

    def self.normalize_superscripts(str)
      str.gsub(SUPERSCRIPT_RE) { |m| "^" + m.chars.map { |c| SUPERSCRIPT_DIGITS[c] }.join }
    end

    def self.exponent_to_superscript(n)
      n.to_s.chars.map { |c| DIGIT_SUPERSCRIPTS[c] || c }.join
    end

    # SI base dimensions (8 fields: length, mass, time, current, temperature, substance, luminosity, information)
    # Definitions and names belong to the external registry, shared with the
    # compiler generator. This engine only adapts them to its value classes.
    # A checkout reads the authoritative data directly; gem builds package
    # byte-identical copies, never definitions generated by this interpreter.
    REGISTRY_DATA_DIR = ["../../../../../data", "../../../data"].map { |path| File.expand_path(path, __dir__) }
      .find { |path| File.file?(File.join(path, "unit_registry.json")) } ||
      raise(LoadError, "missing external Tungsten unit registry")
    REGISTRY_PATH = File.join(REGISTRY_DATA_DIR, "unit_registry.json")
    REGISTRY = TungstenUnitRegistry::Document.new(REGISTRY_PATH)

    def self.dimension_from_registry(record)
      dim = Dimension.new(*record.fetch("powers"))
      dim.instance_variable_set(:@customs, record.fetch("semantic").dup) unless record.fetch("semantic").empty?
      dim
    end

    REGISTRY.data.fetch("dimensions").each do |name, record|
      const_set(name, dimension_from_registry(record))
    end
    DIMENSION_NAMES = REGISTRY.data.fetch("dimension_names").to_h do |record|
      [dimension_from_registry(record), record.fetch("name")]
    end.freeze

    def self.dimension_name(dim)
      return DIMENSION_NAMES[dim] if DIMENSION_NAMES.key?(dim)
      return dim.custom_name if dim.custom?
      DIMENSION_NAMES[dim] || dim.to_s
    end

    PREFIX_TABLE = REGISTRY.prefixes.fetch("si").freeze
    LONG_PREFIX_TABLE = REGISTRY.prefixes.fetch("long").freeze
    UNIT_TABLE = REGISTRY.units.to_h do |symbol, row|
      [symbol, UnitDef.new(symbol: symbol, dimension: dimension_from_registry(row.fetch("dimension")),
                          factor: TungstenUnitRegistry.rational(row.fetch("factor")),
                          offset: TungstenUnitRegistry.rational(row.fetch("offset")),
                          prefixable: row.fetch("prefixable").to_sym, kind: row.fetch("kind").to_sym)]
    end.freeze

    UNIT_METADATA_PATH = File.join(REGISTRY_DATA_DIR, "unit_metadata.tsv")
    UNIT_METADATA = begin
      rows = {}
      if File.file?(UNIT_METADATA_PATH)
        File.foreach(UNIT_METADATA_PATH, encoding: "utf-8") do |line|
          line = line.chomp
          next if line.empty? || line.start_with?("#")
          symbol, description, etymology, history, source, year, status = line.split("\t", -1)
          rows[symbol] = {
            description: description, etymology: etymology, history: history,
            source: source, year: year.empty? ? nil : year.to_i,
            measured: status == "measured"
          }
        end
      end
      rows.freeze
    end

    # Documentation is deliberately external: both REPL implementations read
    # the same TSV, while unit arithmetic remains usable without it.
    UNIT_METADATA.each do |symbol, metadata|
      unit = UNIT_TABLE[symbol]
      next unless unit
      unit.description = metadata[:description]
      unit.etymology = metadata[:etymology]
      unit.history = metadata[:history]
      unit.defining_source = metadata[:source]
      unit.year_defined = metadata[:year]
      unit.measured = metadata[:measured]
    end

    UNIT_ALIASES = REGISTRY.aliases.freeze
    SI_PREFIXABLE_OVERRIDES = REGISTRY.data.fetch("si_prefixable_overrides").freeze
    PREFIXABLE = REGISTRY.prefixable.freeze
    NO_PREFIX = (Set.new(UNIT_TABLE.keys) - PREFIXABLE).freeze
    BINARY_PREFIX_TABLE = REGISTRY.prefixes.fetch("binary").freeze
    BINARY_PREFIXABLE = REGISTRY.binary_prefixable.freeze

    # Reverse lookup: dimension → [[symbol, factor]] for compound unit simplification.
    SIMPLIFY_DIMENSIONS = Set.new(
      [LENGTH, VOLUME, ENERGY, FORCE, POWER, PRESSURE, VOLTAGE, AREA, INFORMATION, VELOCITY, TIME]
    ).freeze
    SIMPLIFICATION_TABLE = Hash.new { |h, k| h[k] = [] }
    UNIT_TABLE.each do |sym, u|
      SIMPLIFICATION_TABLE[u.dimension] << [sym, u.factor] if SIMPLIFY_DIMENSIONS.include?(u.dimension)
    end
    # Add prefixed variants for all PREFIXABLE units in simplifiable dimensions
    PREFIX_TABLE.each do |prefix, mult|
      PREFIXABLE.each do |base|
        next unless UNIT_TABLE.key?(base)
        u = UNIT_TABLE[base]
        next unless SIMPLIFY_DIMENSIONS.include?(u.dimension)
        prefixed = "#{prefix}#{base}"
        SIMPLIFICATION_TABLE[u.dimension] << [prefixed, u.factor * mult]
      end
    end

    # Compositional unit definitions — parsed at first use, not eagerly.
    # The right-hand side is "[scale] expression" using only atomic UNIT_TABLE
    # symbols. Example: `Hz` is `cycle/s`, so 1 Hz·1 s = 1 cycle (cancellation
    # falls out of normal compound-unit arithmetic). Each compound preserves
    # its own display symbol via canonical_symbol/canonical_components on the
    # CompoundUnit.
    COMPOUND_DEFS = REGISTRY.compounds.to_h do |symbol, row|
      [symbol, [TungstenUnitRegistry.rational(row.fetch("scale")), row.fetch("expression")]]
    end.freeze

    def self.compound_units
      @compound_units ||= COMPOUND_DEFS.each_with_object({}) do |(sym, (scale, expr)), acc|
        parsed = parse_compound_expr(expr)
        scaled = CompoundUnit.new(
          dimension: parsed.dimension,
          factor: scale.is_a?(Float) ? (parsed.factor * scale).rationalize : parsed.factor * scale,
          offset: parsed.offset,
          components: parsed.components,
          display_forms: parsed.display_forms
        )
        acc[sym] = scaled
      end
    end

    # Parses a compound expression using only the atomic UNIT_TABLE — bypasses
    # COMPOUND_DEFS lookup so "Hz" inside a definition won't recurse.
    def self.parse_compound_expr(str)
      @inside_compound_def = true
      parse(str)
    ensure
      @inside_compound_def = false
    end

    def self.resolve_unit(str)
      UNIT_TABLE.key?(str) || UNIT_ALIASES.key?(str) || LONG_PREFIX_TABLE.key?(str) || COMPOUND_DEFS.key?(str)
    end

    # Runtime registration of new units. Lets user code add domain-specific units
    # without editing this file:
    #
    #   Tungsten::Units.register("widget_per_hour",
    #     dimension: Tungsten::Units::FREQUENCY,
    #     factor: 1.0 / 3600,
    #     aliases: %w[widgets_per_hour wph],
    #     description: "production rate")
    #
    # Mutates the frozen UNIT_TABLE / UNIT_ALIASES via instance_variable_set, since
    # those constants are exposed read-only. Existing entries are not overwritten —
    # raises if the name is already taken.
    def self.register(name, dimension:, factor: 1, offset: 0,
                      aliases: [], description: nil, measured: false,
                      year_defined: nil, defining_source: nil, prefixable: :none, kind: :unit)
      raise ArgumentError, "unit '#{name}' already registered" if UNIT_TABLE.key?(name)
      raise ArgumentError, "name '#{name}' is an existing alias" if UNIT_ALIASES.key?(name)

      def_obj = UnitDef.new(symbol: name, dimension: dimension,
                            factor: factor, offset: offset,
                            description: description, measured: measured,
                            year_defined: year_defined, defining_source: defining_source,
                            prefixable: prefixable, kind: kind)
      mutate_frozen_hash(UNIT_TABLE) { |h| h[name] = def_obj }
      mutate_frozen_hash(UNIT_ALIASES) do |h|
        aliases.each do |al|
          next if h.key?(al) || UNIT_TABLE.key?(al)
          h[al] = name
        end
      end
      # Invalidate compound-units cache so any new entries appear in lookups.
      @compound_units = nil
      def_obj
    end

    def self.mutate_frozen_hash(h)
      was_frozen = h.frozen?
      h.send(:remove_instance_variable, :@frozen) if was_frozen rescue nil
      # Ruby's Hash#freeze flag is intrinsic; we have to dup → mutate → swap pointer.
      copy = h.dup
      yield copy
      h.replace(copy) rescue (
        # If the original is truly frozen and #replace fails, swap the constant.
        const_name = constants.find { |c| const_get(c).equal?(h) }
        raise "cannot find constant for hash" unless const_name
        send(:remove_const, const_name)
        const_set(const_name, copy.freeze)
      )
    end
    private_class_method :mutate_frozen_hash

    # Multi-line human-readable info about a registered unit name. Returns nil if
    # the name doesn't resolve. Used by Quantity#info and by `?` introspection.
    def self.info(str)
      return nil unless str.is_a?(String)

      canonical = UNIT_ALIASES[str] || str
      def_obj = UNIT_TABLE[canonical]
      compound = COMPOUND_DEFS.key?(canonical) ? compound_units[canonical] : nil

      if def_obj.nil? && compound.nil?
        return nil unless resolve_unit(str)
        # Resolved via prefix only; describe abstractly.
        parsed = parse(str)
        lines = ["#{str}: #{dimension_name(parsed.dimension)}",
                 "  resolves via prefix path; SI factor = #{parsed.factor.to_f}"]
        return lines.join("\n")
      end

      base = def_obj || compound
      lines = []
      title = (str == canonical) ? "#{canonical}" : "#{str} → #{canonical}"
      title += " — #{dimension_name(base.dimension)}"
      lines << title
      lines << "  kind: #{base.kind.to_s.tr('_', ' ')}" if base.respond_to?(:kind) && base.kind != :unit

      lines << "  description: #{base.description}" if base.respond_to?(:description) && base.description
      lines << "  etymology: #{base.etymology}" if base.respond_to?(:etymology) && base.etymology
      lines << "  history: #{base.history}" if base.respond_to?(:history) && base.history

      factor_str = base.factor.is_a?(Rational) ? "#{base.factor.to_f} (#{base.factor})" : base.factor.to_s
      lines << "  SI factor: #{factor_str}"

      if base.respond_to?(:offset) && base.offset && base.offset != 0
        lines << "  offset: #{base.offset}"
      end

      if base.respond_to?(:measured) && !base.measured.nil?
        lines << "  measured: #{base.measured ? 'yes (experimental value)' : 'no (defined exact)'}"
      end
      if base.respond_to?(:year_defined) && base.year_defined
        lines << "  year defined: #{base.year_defined}"
      end
      if base.respond_to?(:defining_source) && base.defining_source
        lines << "  source: #{base.defining_source}"
      end

      aliases = UNIT_ALIASES.select { |_k, v| v == canonical }.keys
      lines << "  aliases: #{aliases.join(', ')}" unless aliases.empty?

      lines.join("\n")
    end

    # "Did you mean" suggestion for an unrecognized unit string. Scans the
    # registered names (atomic + aliases) for the closest match by
    # Levenshtein distance, capped at 2 edits. Returns nil if nothing close.
    SUGGESTION_THRESHOLD = 2
    def self.suggest_unit(str)
      return nil if str.nil? || str.empty?
      candidates = UNIT_TABLE.keys + UNIT_ALIASES.keys
      best = nil
      best_dist = SUGGESTION_THRESHOLD + 1
      candidates.each do |cand|
        # Length filter: skip pairs that can't be close enough.
        next if (cand.length - str.length).abs > SUGGESTION_THRESHOLD
        d = levenshtein(str, cand)
        if d < best_dist
          best = cand
          best_dist = d
        end
      end
      best_dist <= SUGGESTION_THRESHOLD ? best : nil
    end

    def self.levenshtein(a, b)
      return b.length if a.empty?
      return a.length if b.empty?
      m, n = a.length, b.length
      prev = (0..n).to_a
      curr = Array.new(n + 1)
      (1..m).each do |i|
        curr[0] = i
        (1..n).each do |j|
          cost = a[i - 1] == b[j - 1] ? 0 : 1
          curr[j] = [curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost].min
        end
        prev, curr = curr, prev
      end
      prev[n]
    end

    # Strips a metric prefix from a component symbol if applicable, so that
    # `ns`, `μs`, `ms`, `s` all map to atomic "s" — and likewise km/m,
    # MHz/Hz, etc. Used by component cross-prefix cancellation. Compounds
    # are atomic to themselves (e.g. "Hz" → "Hz", "rpm" → "rpm").
    def self.atomic_of(name)
      return name if UNIT_TABLE.key?(name)
      return name if COMPOUND_DEFS.key?(name)
      PREFIX_TABLE.each do |prefix, _|
        next unless name.start_with?(prefix)
        base = name[prefix.length..]
        next if base.empty?
        return base if UNIT_TABLE.key?(base) && !NO_PREFIX.include?(base)
        return base if COMPOUND_DEFS.key?(base)
      end
      name
    end

    # True when `name` is an SI base unit: an unprefixed, factor-1, offset-0
    # atomic unit whose dimension is a single base axis raised to +1 (m, s, kg,
    # A, K, mol, cd, bit). A pure power of such a unit (m², m³, s²) is already
    # in canonical form, so CompoundUnit.simplify must not rename it to a
    # same-factor alias like "sqm" (square metre) or "stere" (m³).
    def self.si_base_unit?(name)
      u = UNIT_TABLE[name]
      return false unless u
      return false unless u.factor == 1
      off = u.offset
      return false unless off.nil? || off.zero?
      dim = u.dimension
      return false if dim.custom?
      axes = [dim.length, dim.mass, dim.time, dim.current,
              dim.temperature, dim.substance, dim.luminosity, dim.information]
      axes.count { |e| !e.zero? } == 1 && axes.any? { |e| e == 1 }
    end

    # SI conversion factor of a single component name (handles atomic and
    # prefix-decomposed forms). Used by naive_factor.
    def self.factor_of_unit(name)
      return UNIT_TABLE[name].factor if UNIT_TABLE.key?(name)
      return compound_units[name].factor if COMPOUND_DEFS.key?(name)
      PREFIX_TABLE.each do |prefix, mult|
        next unless name.start_with?(prefix)
        base = name[prefix.length..]
        next if base.empty?
        return UNIT_TABLE[base].factor * mult if UNIT_TABLE.key?(base) && !NO_PREFIX.include?(base)
        return compound_units[base].factor * mult if COMPOUND_DEFS.key?(base)
      end
      1
    end

    # Naive factor of a components hash — product of each component's
    # SI conversion factor raised to its exponent. Differs from a
    # CompoundUnit's stored factor when prefix factors are baked into
    # `factor` but no longer reflected in `components` (this happens when
    # cross-prefix cancellation removes prefixed components).
    def self.naive_factor(components)
      components.inject(1) do |acc, (name, exp)|
        f = factor_of_unit(name)
        f.is_a?(Float) ? acc * f**exp : acc * (f**exp)
      end
    end

    # Set of unit-component names that pluralize with a trailing "s" when
    # the magnitude is not 1. Only applies when the displayed unit is a
    # single component with exponent 1 (e.g. `6000 revolutions`, but
    # NOT `6000 revolution·s`). Acronym/canonical displays (Hz, bpm, fps)
    # are skipped via the canonical_symbol path.
    PLURALIZABLE = Set.new(REGISTRY.data.fetch("pluralizable")).freeze

    def self.parse(str)
      # The multiplicative identity is useful as an explicit numerator in
      # compound units such as `1/mol`. It is not a custom count dimension.
      return CompoundUnit.new(dimension: DIMENSIONLESS, factor: 1, components: {}) if str == "1"

      # Parenthesized products commonly appear in denominators
      # (`J/(mol·K)`). Strip a balanced pair before the operator parser runs.
      if str.start_with?("(") && str.end_with?(")")
        depth = 0
        balanced_outer = str.chars.each_with_index.all? do |ch, i|
          depth += 1 if ch == "("
          depth -= 1 if ch == ")"
          depth >= 0 && (depth > 0 || i == str.length - 1)
        end
        return parse(str[1...-1]) if balanced_outer && depth.zero?
      end

      # Skip normalization for keys that are registered exactly as-is (e.g. `fb⁻¹`,
      # `g₀`, `m²` — atomic entries whose names contain superscripts). Without this,
      # `normalize_superscripts` rewrites them to `fb⁻^1`/`g_0`/`m^2` and they miss
      # their UNIT_TABLE entries.
      # COMPOUND_DEFS still wins over UNIT_TABLE for entries that live in both
      # (e.g. Hz appears in both for self-host bootstrap reasons).
      if SUPERSCRIPT_RE.match?(str) || SUBSCRIPT_RE.match?(str)
        if !@inside_compound_def && COMPOUND_DEFS.key?(str)
          base = compound_units[str]
          return CompoundUnit.new(
            dimension: base.dimension, factor: base.factor, offset: base.offset,
            components: base.components.dup, display_forms: base.display_forms.dup,
            canonical_symbol: str, canonical_components: base.components.dup
          )
        end
        if UNIT_TABLE.key?(str)
          u = UNIT_TABLE[str]
          return CompoundUnit.new(dimension: u.dimension, factor: u.factor, offset: u.offset, components: {str => 1})
        end
        if UNIT_ALIASES.key?(str)
          canonical = UNIT_ALIASES[str]
          if !@inside_compound_def && COMPOUND_DEFS.key?(canonical)
            cu = compound_units[canonical]
            return CompoundUnit.new(
              dimension: cu.dimension, factor: cu.factor, offset: cu.offset,
              components: cu.components.dup, display_forms: cu.display_forms.dup,
              canonical_symbol: canonical, canonical_components: cu.components.dup
            )
          end
          if UNIT_TABLE.key?(canonical)
            u = UNIT_TABLE[canonical]
            return CompoundUnit.new(
              dimension: u.dimension, factor: u.factor, offset: u.offset,
              components: {canonical => 1}, display_forms: {canonical => str}
            )
          end
        end
      end

      str = normalize_superscripts(str)

      # Handle "square X" and "cubic X" modifiers
      if str =~ /\Asquare\s+(.+)\z/
        base = parse($1)
        dim = base.dimension * base.dimension
        factor = base.factor * base.factor
        return CompoundUnit.new(dimension: dim, factor: factor, components: {str => 1})
      end
      if str =~ /\Acubic\s+(.+)\z/
        base = parse($1)
        dim = base.dimension * base.dimension * base.dimension
        factor = base.factor * base.factor * base.factor
        return CompoundUnit.new(dimension: dim, factor: factor, components: {str => 1})
      end

      # Compositional defs (Hz, rpm, Bq, mph, etc.) — preferred over atomic
      # entries so `1 Hz · 1 s` cancels through the cycle/s expansion.
      # Skipped while we're parsing a compound def to avoid recursion.
      if !@inside_compound_def && COMPOUND_DEFS.key?(str)
        base = compound_units[str]
        return CompoundUnit.new(
          dimension: base.dimension,
          factor: base.factor,
          offset: base.offset,
          components: base.components.dup,
          display_forms: base.display_forms.dup,
          canonical_symbol: str,
          canonical_components: base.components.dup
        )
      end

      # Resolve long-form aliases (e.g. "meters" → "m", "BPM" → "bpm")
      if UNIT_ALIASES.key?(str)
        canonical = UNIT_ALIASES[str]
        # Compound canonical (e.g. BPM → bpm → beat/min)
        if !@inside_compound_def && COMPOUND_DEFS.key?(canonical)
          cu = compound_units[canonical]
          return CompoundUnit.new(
            dimension: cu.dimension,
            factor: cu.factor,
            offset: cu.offset,
            components: cu.components.dup,
            display_forms: cu.display_forms.dup,
            canonical_symbol: canonical,
            canonical_components: cu.components.dup
          )
        end
        u = UNIT_TABLE[canonical]
        return CompoundUnit.new(
          dimension: u.dimension, factor: u.factor, offset: u.offset,
          components: {canonical => 1}, display_forms: {canonical => str}
        )
      end

      # Try exact match first
      if UNIT_TABLE.key?(str)
        u = UNIT_TABLE[str]
        return CompoundUnit.new(dimension: u.dimension, factor: u.factor, offset: u.offset, components: {str => 1})
      end

      # Try metric prefix + base unit (e.g. "km" → k + m, "MHz" → M + Hz)
      PREFIX_TABLE.each do |prefix, mult|
        next unless str.start_with?(prefix)
        base_str = str[prefix.length..]
        next if base_str.empty?
        # Compound base — apply prefix to the compound's factor while keeping
        # its components (so MHz = 10⁶ × cycle/s, not atomic frequency).
        if !@inside_compound_def && COMPOUND_DEFS.key?(base_str)
          cu = compound_units[base_str]
          return CompoundUnit.new(
            dimension: cu.dimension,
            factor: cu.factor * mult,
            offset: cu.offset,
            components: cu.components.dup,
            display_forms: cu.display_forms.dup,
            canonical_symbol: str,
            canonical_components: cu.components.dup
          )
        end
        next unless UNIT_TABLE.key?(base_str) && !NO_PREFIX.include?(base_str)
        base = UNIT_TABLE[base_str]
        return CompoundUnit.new(dimension: base.dimension, factor: base.factor * mult, components: {str => 1})
      end

      # Try long prefix + aliased base unit (e.g. "kilometers" → kilo + meters → k + m)
      # Also checks UNIT_TABLE directly so "microfortnight" = micro + fortnight works
      LONG_PREFIX_TABLE.each do |prefix, mult|
        next unless str.start_with?(prefix)
        base_str = str[prefix.length..]
        next if base_str.empty?
        canonical = UNIT_ALIASES[base_str] || (UNIT_TABLE.key?(base_str) ? base_str : nil)
        next unless canonical
        next unless UNIT_TABLE.key?(canonical) && !NO_PREFIX.include?(canonical)
        base = UNIT_TABLE[canonical]
        return CompoundUnit.new(dimension: base.dimension, factor: base.factor * mult, components: {str => 1})
      end

      # Try IEC binary prefix + base unit (e.g. "Kib" → Ki + b)
      BINARY_PREFIX_TABLE.each do |prefix, mult|
        next unless str.start_with?(prefix)
        base_str = str[prefix.length..]
        next if base_str.empty?
        next unless UNIT_TABLE.key?(base_str) && BINARY_PREFIXABLE.include?(base_str)
        base = UNIT_TABLE[base_str]
        return CompoundUnit.new(dimension: base.dimension, factor: base.factor * mult, components: {str => 1})
      end

      # Try compound: "m/s", "kg·m/s^2"
      if str.include?("/")
        parts = str.split("/", 2)
        # Re-enter the full parser for each side so a parenthesized product in
        # the denominator is unwrapped before product splitting.
        num = parse(parts[0])
        den = parse(parts[1])
        return num / den
      end

      if str.include?("*") || str.include?("·")
        return parse_product(str)
      end

      if str =~ /\A(.+)\^(-?\d+)\z/
        base = parse($1)
        exp = $2.to_i
        components = base.components.transform_values { |e| e * exp }
        dim = Dimension.zero
        factor = 1
        exp.abs.times { dim = dim * base.dimension; factor *= base.factor }
        if exp.negative?
          dim_zero = Dimension.zero
          inv_dim = dim_zero / dim
          inv_factor = factor.is_a?(Float) ? 1.0 / factor : Rational(1, factor)
          return CompoundUnit.new(dimension: inv_dim, factor: inv_factor, components: components)
        end
        return CompoundUnit.new(dimension: dim, factor: factor, components: components)
      end

      # Unknown unit — custom dimension
      CompoundUnit.new(dimension: Dimension.custom(str), factor: 1, components: {str => 1})
    end

    def self.parse_product(str)
      parts = str.split(/[*·]/)
      result = parse(parts[0])
      parts[1..].each { |p| result = result * parse(p) }
      result
    end

    # Substance densities in kg/m³ for "X of <substance>" calculations.
    # Lookup: downcase, strip, normalize underscores to spaces.
    SUBSTANCE_DENSITY = TungstenUnitRegistry.read(
      File.join(REGISTRY_DATA_DIR, "substance_densities.json")
    ).fetch("values").transform_values { |value| TungstenUnitRegistry.rational(value) }.freeze

    def self.lookup_density(name)
      SUBSTANCE_DENSITY[name.downcase.strip.gsub("_", " ")]
    end

    def self.known?(str)
      return true if UNIT_ALIASES.key?(str)
      return true if UNIT_TABLE.key?(str)
      PREFIX_TABLE.each do |prefix, _|
        base_str = str[prefix.length..]
        next if base_str.nil? || base_str.empty?
        return true if str.start_with?(prefix) && UNIT_TABLE.key?(base_str) && !NO_PREFIX.include?(base_str)
      end
      BINARY_PREFIX_TABLE.each do |prefix, _|
        next unless str.start_with?(prefix)
        base_str = str[prefix.length..]
        next if base_str.nil? || base_str.empty?
        return true if UNIT_TABLE.key?(base_str) && BINARY_PREFIXABLE.include?(base_str)
      end
      false
    end
  end
end

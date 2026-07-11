# frozen_string_literal: true

require "set"

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
                         :prefixable, :etymology, :history,
                         keyword_init: true) do
      def initialize(symbol:, dimension:, factor: 1, offset: 0,
                     description: nil, measured: false, year_defined: nil, defining_source: nil,
                     prefixable: :none, etymology: nil, history: nil)
        super(symbol: symbol, dimension: dimension,
              factor: factor.is_a?(Float) ? factor.rationalize : factor,
              offset: offset.is_a?(Float) ? offset.rationalize : offset,
              description: description, measured: measured,
              year_defined: year_defined, defining_source: defining_source,
              prefixable: prefixable, etymology: etymology, history: history)
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
    LENGTH      = Dimension.new(1, 0, 0, 0, 0, 0, 0, 0)
    MASS        = Dimension.new(0, 1, 0, 0, 0, 0, 0, 0)
    TIME        = Dimension.new(0, 0, 1, 0, 0, 0, 0, 0)
    CURRENT     = Dimension.new(0, 0, 0, 1, 0, 0, 0, 0)
    TEMPERATURE = Dimension.new(0, 0, 0, 0, 1, 0, 0, 0)
    SUBSTANCE   = Dimension.new(0, 0, 0, 0, 0, 1, 0, 0)
    LUMINOSITY  = Dimension.new(0, 0, 0, 0, 0, 0, 1, 0)
    INFORMATION = Dimension.new(0, 0, 0, 0, 0, 0, 0, 1)
    DIMENSIONLESS = Dimension.zero

    # Derived dimensions
    AREA                  = Dimension.new(2, 0, 0, 0, 0, 0, 0, 0)
    VOLUME                = Dimension.new(3, 0, 0, 0, 0, 0, 0, 0)
    VELOCITY              = Dimension.new(1, 0, -1, 0, 0, 0, 0, 0)
    FORCE                 = Dimension.new(1, 1, -2, 0, 0, 0, 0, 0)
    ENERGY                = Dimension.new(2, 1, -2, 0, 0, 0, 0, 0)
    POWER                 = Dimension.new(2, 1, -3, 0, 0, 0, 0, 0)
    PRESSURE              = Dimension.new(-1, 1, -2, 0, 0, 0, 0, 0)
    FREQUENCY             = Dimension.new(0, 0, -1, 0, 0, 0, 0, 0)
    VOLTAGE               = Dimension.new(2, 1, -3, -1, 0, 0, 0, 0)
    DATA_RATE             = Dimension.new(0, 0, -1, 0, 0, 0, 0, 1)    # information/time
    CHARGE                = Dimension.new(0, 0, 1, 1, 0, 0, 0, 0)     # A·s
    RESISTANCE            = Dimension.new(2, 1, -3, -2, 0, 0, 0, 0)   # V/A
    CAPACITANCE           = Dimension.new(-2, -1, 4, 2, 0, 0, 0, 0)   # C/V
    INDUCTANCE            = Dimension.new(2, 1, -2, -2, 0, 0, 0, 0)   # Wb/A
    MAGNETIC_FLUX         = Dimension.new(2, 1, -2, -1, 0, 0, 0, 0)   # V·s
    MAGNETIC_FLUX_DENSITY = Dimension.new(0, 1, -2, -1, 0, 0, 0, 0)   # Wb/m²
    CONDUCTANCE           = Dimension.new(-2, -1, 3, 2, 0, 0, 0, 0)   # 1/Ω
    ILLUMINANCE           = Dimension.new(-2, 0, 0, 0, 0, 0, 1, 0)    # lm/m²
    ABSORBED_DOSE         = Dimension.new(2, 0, -2, 0, 0, 0, 0, 0)    # J/kg
    CATALYTIC_ACTIVITY    = Dimension.new(0, 0, -1, 0, 0, 1, 0, 0)    # mol/s
    ACCELERATION          = Dimension.new(1, 0, -2, 0, 0, 0, 0, 0)    # m/s²
    DYNAMIC_VISCOSITY     = Dimension.new(-1, 1, -1, 0, 0, 0, 0, 0)   # Pa·s
    KINEMATIC_VISCOSITY   = Dimension.new(2, 0, -1, 0, 0, 0, 0, 0)    # m²/s
    INVERSE_LENGTH        = Dimension.new(-1, 0, 0, 0, 0, 0, 0, 0)    # m⁻¹ (wavenumber)
    INVERSE_AREA          = Dimension.new(-2, 0, 0, 0, 0, 0, 0, 0)    # m⁻² (integrated luminosity, fuel economy)
    MOLARITY              = Dimension.new(-3, 0, 0, 0, 0, 1, 0, 0)    # mol/m³ (concentration)
    MOLALITY              = Dimension.new(0, -1, 0, 0, 0, 1, 0, 0)    # mol/kg (molality)
    MAGNETIC_FIELD_H      = Dimension.new(-1, 0, 0, 1, 0, 0, 0, 0)    # A/m (oersted)
    ELECTRIC_DIPOLE       = Dimension.new(1, 0, 1, 1, 0, 0, 0, 0)     # C·m = A·s·m (debye)
    MAGNETIC_MOMENT       = Dimension.new(2, 0, 0, 1, 0, 0, 0, 0)     # A·m² = J/T (bohr magneton)

    # Semantic quantity kinds. SI exponent vectors remain available for
    # algebra, while the custom tag prevents same-vector concepts from being
    # silently interchangeable (angle/ratio, torque/energy, Gy/Sv, etc.).
    ANGLE                 = Dimension.custom("angle")
    SOLID_ANGLE           = Dimension.custom("solid_angle")
    RATIO                 = Dimension.custom("ratio")
    ABSORBED_DOSE_KIND    = ABSORBED_DOSE * Dimension.custom("absorbed_dose")
    EQUIVALENT_DOSE       = ABSORBED_DOSE * Dimension.custom("equivalent_dose")
    TORQUE                = ENERGY * Dimension.custom("torque")
    HEAT_CAPACITY_KIND    = (ENERGY / TEMPERATURE) * Dimension.custom("heat_capacity")
    ENTROPY_KIND          = (ENERGY / TEMPERATURE) * Dimension.custom("entropy")
    SPECIFIC_ENERGY_KIND  = (ENERGY / MASS) * Dimension.custom("specific_energy")
    MOMENTUM              = Dimension.new(1, 1, -1, 0, 0, 0, 0, 0) * Dimension.custom("momentum")
    IMPULSE               = Dimension.new(1, 1, -1, 0, 0, 0, 0, 0) * Dimension.custom("impulse")
    ILLUMINANCE_KIND      = ILLUMINANCE * Dimension.custom("illuminance")
    LUMINANCE             = ILLUMINANCE * Dimension.custom("luminance")
    LUMINOUS_FLUX         = LUMINOSITY * Dimension.custom("luminous_flux")
    LUMINOUS_INTENSITY    = LUMINOSITY * Dimension.custom("luminous_intensity")
    TEMPERATURE_DELTA     = TEMPERATURE * Dimension.custom("temperature_delta")

    DIMENSION_NAMES = {
      LENGTH                => "length",
      MASS                  => "mass",
      TIME                  => "time",
      CURRENT               => "current",
      TEMPERATURE           => "temperature",
      SUBSTANCE             => "substance",
      LUMINOSITY            => "luminosity",
      INFORMATION           => "information",
      AREA                  => "area",
      VOLUME                => "volume",
      VELOCITY              => "velocity",
      FORCE                 => "force",
      ENERGY                => "energy",
      POWER                 => "power",
      PRESSURE              => "pressure",
      FREQUENCY             => "frequency",
      VOLTAGE               => "voltage",
      DATA_RATE             => "data rate",
      CHARGE                => "charge",
      RESISTANCE            => "resistance",
      CAPACITANCE           => "capacitance",
      INDUCTANCE            => "inductance",
      MAGNETIC_FLUX         => "magnetic flux",
      MAGNETIC_FLUX_DENSITY => "magnetic flux density",
      CONDUCTANCE           => "conductance",
      ILLUMINANCE           => "illuminance",
      ABSORBED_DOSE         => "absorbed dose",
      CATALYTIC_ACTIVITY    => "catalytic activity",
      ACCELERATION          => "acceleration",
      DYNAMIC_VISCOSITY     => "dynamic viscosity",
      KINEMATIC_VISCOSITY   => "kinematic viscosity",
      INVERSE_LENGTH        => "wavenumber",
      INVERSE_AREA          => "inverse area",
      MOLARITY              => "molarity",
      MOLALITY              => "molality",
      MAGNETIC_FIELD_H      => "magnetic field strength",
      ELECTRIC_DIPOLE       => "electric dipole moment",
      MAGNETIC_MOMENT       => "magnetic moment",
      ANGLE                 => "angle",
      SOLID_ANGLE           => "solid angle",
      RATIO                 => "ratio",
      ABSORBED_DOSE_KIND    => "absorbed dose",
      EQUIVALENT_DOSE       => "equivalent dose",
      TORQUE                => "torque",
      HEAT_CAPACITY_KIND    => "heat capacity",
      ENTROPY_KIND          => "entropy",
      SPECIFIC_ENERGY_KIND  => "specific energy",
      MOMENTUM              => "momentum",
      IMPULSE               => "impulse",
      ILLUMINANCE_KIND      => "illuminance",
      LUMINANCE             => "luminance",
      LUMINOUS_FLUX         => "luminous flux",
      LUMINOUS_INTENSITY    => "luminous intensity",
      TEMPERATURE_DELTA     => "temperature difference",
    }.freeze

    def self.dimension_name(dim)
      return DIMENSION_NAMES[dim] if DIMENSION_NAMES.key?(dim)
      return dim.custom_name if dim.custom?
      DIMENSION_NAMES[dim] || dim.to_s
    end

    PREFIX_TABLE = {
      "Q"  => 10**30,             "R"  => 10**27,
      "Y"  => 10**24,             "Z"  => 10**21,
      "E"  => 10**18,             "P"  => 10**15,
      "T"  => 10**12,             "G"  => 10**9,
      "M"  => 10**6,              "k"  => 10**3,
      "h"  => 10**2,              "da" => 10,
      "d"  => Rational(1, 10),    "c"  => Rational(1, 100),
      "m"  => Rational(1, 10**3), "u"  => Rational(1, 10**6),
      # micro-prefix accepts both U+03BC (Greek small letter mu) and U+00B5
      # (micro sign). Different keyboards and input methods produce one or
      # the other; both `µs` and `μs` mean microsecond.
      "μ"  => Rational(1, 10**6), "µ"  => Rational(1, 10**6),
      "n"  => Rational(1, 10**9),  "p"  => Rational(1, 10**12),
      "f"  => Rational(1, 10**15), "a"  => Rational(1, 10**18),
      "z"  => Rational(1, 10**21), "y"  => Rational(1, 10**24),
      "r"  => Rational(1, 10**27), "q"  => Rational(1, 10**30),
    }.freeze

    LONG_PREFIX_TABLE = {
      "quetta" => 10**30,             "ronna"  => 10**27,
      "yotta"  => 10**24,             "zetta"  => 10**21,
      "exa"    => 10**18,             "peta"   => 10**15,
      "tera"   => 10**12,             "giga"   => 10**9,
      "mega"   => 10**6,              "kilo"   => 10**3,
      "hecto"  => 10**2,              "deca"   => 10,
      "deka"   => 10,
      "deci"   => Rational(1, 10),    "centi"  => Rational(1, 100),
      "milli"  => Rational(1, 10**3), "micro"  => Rational(1, 10**6),
      "nano"   => Rational(1, 10**9),  "pico"   => Rational(1, 10**12),
      "femto"  => Rational(1, 10**15), "atto"   => Rational(1, 10**18),
      "zepto"  => Rational(1, 10**21), "yocto"  => Rational(1, 10**24),
      "ronto"  => Rational(1, 10**27), "quecto" => Rational(1, 10**30),
    }.freeze

    UNIT_TABLE = {
      # SI base — all defined exact in the 2019 SI revision via fundamental constants.
      "m"   => UnitDef.new(symbol: "m",   dimension: LENGTH,      factor: 1.0,
        description: "metre — SI base unit of length, defined via the speed of light c",
        measured: false, year_defined: 1983, defining_source: "17th CGPM", prefixable: :si),
      "kg"  => UnitDef.new(symbol: "kg",  dimension: MASS,        factor: 1.0,
        description: "kilogram — SI base unit of mass, defined via the Planck constant h",
        measured: false, year_defined: 2019, defining_source: "26th CGPM"),
      "g"   => UnitDef.new(symbol: "g",   dimension: MASS,        factor: 0.001,
        description: "gram — kg / 1000",
        measured: false, year_defined: 2019, defining_source: "26th CGPM", prefixable: :si),
      "s"   => UnitDef.new(symbol: "s",   dimension: TIME,        factor: 1.0,
        description: "second — SI base unit of time, defined via the caesium-133 hyperfine transition",
        measured: false, year_defined: 1967, defining_source: "13th CGPM", prefixable: :si),
      "A"   => UnitDef.new(symbol: "A",   dimension: CURRENT,     factor: 1.0,
        description: "ampere — SI base unit of electric current, defined via the elementary charge e",
        measured: false, year_defined: 2019, defining_source: "26th CGPM", prefixable: :si),
      "K"   => UnitDef.new(symbol: "K",   dimension: TEMPERATURE, factor: 1.0,
        description: "kelvin — SI base unit of thermodynamic temperature, defined via the Boltzmann constant k",
        measured: false, year_defined: 2019, defining_source: "26th CGPM", prefixable: :si),
      "mol" => UnitDef.new(symbol: "mol", dimension: SUBSTANCE,   factor: 1.0,
        description: "mole — SI base unit of amount of substance, defined via the Avogadro constant Nₐ",
        measured: false, year_defined: 2019, defining_source: "26th CGPM", prefixable: :si),
      "cd"  => UnitDef.new(symbol: "cd",  dimension: LUMINOUS_INTENSITY, factor: 1.0,
        description: "candela — SI base unit of luminous intensity, defined via Kₒd (luminous efficacy of 540 THz radiation)",
        measured: false, year_defined: 1979, defining_source: "16th CGPM", prefixable: :si),

      # Temperature scales — factors and offsets are written as exact Rationals so that
      # round-trip conversions (e.g. °F → K → °C) preserve clean repeating decimals.
      # Float intermediates would .rationalize into long-period denominators.
      "°C"  => UnitDef.new(
        symbol: "°C", dimension: TEMPERATURE, factor: Rational(1), offset: Rational(5463, 20)
      ),
      "°F"  => UnitDef.new(
        symbol: "°F", dimension: TEMPERATURE, factor: Rational(5, 9), offset: Rational(45967, 180)
      ),
      "°R"  => UnitDef.new(symbol: "°R",  dimension: TEMPERATURE, factor: Rational(5, 9),  offset: Rational(0)),
      "°De" => UnitDef.new(
        symbol: "°De", dimension: TEMPERATURE, factor: Rational(-2, 3), offset: Rational(7463, 20)
      ),
      "°N"  => UnitDef.new(
        symbol: "°N", dimension: TEMPERATURE, factor: Rational(100, 33), offset: Rational(5463, 20)
      ),
      "°Ré" => UnitDef.new(
        symbol: "°Ré", dimension: TEMPERATURE, factor: Rational(5, 4), offset: Rational(5463, 20)
      ),
      "°Rø" => UnitDef.new(
        symbol: "°Rø", dimension: TEMPERATURE, factor: Rational(40, 21), offset: Rational(36241, 140)
      ),
      "°W"  => UnitDef.new(
        symbol: "°W", dimension: TEMPERATURE, factor: 72.222, offset: Rational(17063, 20)
      ),

      # Temperature differences are linear quantities. They deliberately do
      # not share a kind with absolute temperature points: 20 °C + 10 °C is
      # nonsensical, while 20 °C + 10 Δ°C and 30 °C - 20 °C are useful.
      "ΔK"  => UnitDef.new(symbol: "ΔK",  dimension: TEMPERATURE_DELTA, factor: Rational(1)),
      "Δ°C" => UnitDef.new(symbol: "Δ°C", dimension: TEMPERATURE_DELTA, factor: Rational(1)),
      "Δ°F" => UnitDef.new(symbol: "Δ°F", dimension: TEMPERATURE_DELTA, factor: Rational(5, 9)),
      "Δ°R" => UnitDef.new(symbol: "Δ°R", dimension: TEMPERATURE_DELTA, factor: Rational(5, 9)),
      "Δ°De" => UnitDef.new(symbol: "Δ°De", dimension: TEMPERATURE_DELTA, factor: Rational(-2, 3)),
      "Δ°N"  => UnitDef.new(symbol: "Δ°N",  dimension: TEMPERATURE_DELTA, factor: Rational(100, 33)),
      "Δ°Ré" => UnitDef.new(symbol: "Δ°Ré", dimension: TEMPERATURE_DELTA, factor: Rational(5, 4)),
      "Δ°Rø" => UnitDef.new(symbol: "Δ°Rø", dimension: TEMPERATURE_DELTA, factor: Rational(40, 21)),
      "Δ°W"  => UnitDef.new(symbol: "Δ°W",  dimension: TEMPERATURE_DELTA, factor: 72.222),

      # Derived SI
      "N"   => UnitDef.new(symbol: "N",   dimension: FORCE,     factor: 1.0,
        description: "newton — SI derived unit of force; 1 N = 1 kg·m/s²",
        measured: false, year_defined: 1948, defining_source: "9th CGPM"),
      "J"   => UnitDef.new(symbol: "J",   dimension: ENERGY,    factor: 1.0,
        description: "joule — SI derived unit of energy; 1 J = 1 N·m = 1 W·s",
        measured: false, year_defined: 1889, defining_source: "BIPM"),
      "W"   => UnitDef.new(symbol: "W",   dimension: POWER,     factor: 1.0,
        description: "watt — SI derived unit of power; 1 W = 1 J/s",
        measured: false, year_defined: 1889, defining_source: "BIPM"),
      "Pa"  => UnitDef.new(symbol: "Pa",  dimension: PRESSURE,  factor: 1.0,
        description: "pascal — SI derived unit of pressure; 1 Pa = 1 N/m²",
        measured: false, year_defined: 1971, defining_source: "14th CGPM"),
      "Hz"  => UnitDef.new(symbol: "Hz",  dimension: FREQUENCY, factor: 1.0,
        description: "hertz — SI derived unit of frequency; 1 Hz = 1 cycle/s",
        measured: false, year_defined: 1933, defining_source: "IEC"),
      "V"   => UnitDef.new(symbol: "V",   dimension: VOLTAGE,   factor: 1.0,
        description: "volt — SI derived unit of electric potential; 1 V = 1 W/A = 1 J/C",
        measured: false, year_defined: 1881, defining_source: "1st International Electrical Congress"),
      "C"   => UnitDef.new(symbol: "C",   dimension: CHARGE,              factor: 1.0),
      "Ω"   => UnitDef.new(symbol: "Ω",   dimension: RESISTANCE,          factor: 1.0),
      "F"   => UnitDef.new(symbol: "F",   dimension: CAPACITANCE,         factor: 1.0),
      "H"   => UnitDef.new(symbol: "H",   dimension: INDUCTANCE,          factor: 1.0),
      "S"   => UnitDef.new(symbol: "S",   dimension: CONDUCTANCE,         factor: 1.0),
      "Wb"  => UnitDef.new(symbol: "Wb",  dimension: MAGNETIC_FLUX,       factor: 1.0),
      "T"   => UnitDef.new(symbol: "T",   dimension: MAGNETIC_FLUX_DENSITY, factor: 1.0),
      "lm"  => UnitDef.new(symbol: "lm",  dimension: LUMINOUS_FLUX,       factor: 1.0),
      "lx"  => UnitDef.new(symbol: "lx",  dimension: ILLUMINANCE_KIND,    factor: 1.0),

      # Imperial length
      "in"  => UnitDef.new(symbol: "in",  dimension: LENGTH, factor: 0.0254),
      "ft"  => UnitDef.new(symbol: "ft",  dimension: LENGTH, factor: 0.3048),
      "yd"  => UnitDef.new(symbol: "yd",  dimension: LENGTH, factor: 0.9144),
      "mi"  => UnitDef.new(symbol: "mi",  dimension: LENGTH, factor: 1609.344),
      "nmi" => UnitDef.new(symbol: "nmi", dimension: LENGTH, factor: 1852.0),
      "fur" => UnitDef.new(symbol: "fur", dimension: LENGTH, factor: 201.168),
      "rod" => UnitDef.new(symbol: "rod", dimension: LENGTH, factor: 5.0292),
      "ch"  => UnitDef.new(symbol: "ch",  dimension: LENGTH, factor: 20.1168),
      "smoot" => UnitDef.new(symbol: "smoot", dimension: LENGTH, factor: 1.7018,
        description: "1 smoot = height of Oliver R. Smoot (5'7\"); famously used to measure the Harvard Bridge in 1958 — \"364.4 smoots ± 1 ear\"",
        measured: true, year_defined: 1958, defining_source: "MIT Lambda Chi Alpha pledge prank"),
      "hand"   => UnitDef.new(symbol: "hand",   dimension: LENGTH, factor: Rational(127, 1250)),     # 4 in exact
      "league" => UnitDef.new(symbol: "league", dimension: LENGTH, factor: Rational(603504, 125)),  # 3 mi exact
      # 1.75 in exact (rack unit)
      "RU"     => UnitDef.new(symbol: "RU",     dimension: LENGTH, factor: Rational(889, 20000)),
      "Å"      => UnitDef.new(symbol: "Å",      dimension: LENGTH, factor: Rational(1, 10**10)),    # Ångström

      # Nautical & Speed
      "fathom" => UnitDef.new(symbol: "fathom", dimension: LENGTH,   factor: 1.8288),
      "cable"  => UnitDef.new(symbol: "cable",  dimension: LENGTH,   factor: 185.2),
      "knot"   => UnitDef.new(symbol: "knot",   dimension: VELOCITY, factor: Rational(463, 900)),
      "mph"    => UnitDef.new(symbol: "mph",    dimension: VELOCITY, factor: Rational(1609344, 3600000)),
      "mi/h"   => UnitDef.new(symbol: "mi/h",   dimension: VELOCITY, factor: Rational(1609344, 3600000)),  # spelled-out mph
      "kph"    => UnitDef.new(symbol: "kph",    dimension: VELOCITY, factor: Rational(5, 18)),  # 1000 m / 3600 s exact
      "mach"   => UnitDef.new(symbol: "mach",   dimension: VELOCITY, factor: 331.46),

      # Astronomical length
      "au"  => UnitDef.new(symbol: "au",  dimension: LENGTH, factor: 1.495978707e11),
      "pc"  => UnitDef.new(symbol: "pc",  dimension: LENGTH, factor: 3.0856775814914e16),
      "ly"  => UnitDef.new(symbol: "ly",  dimension: LENGTH, factor: 9.4607304725808e15),
      # Light-time lengths — exact, since c is exact since 1983.
      "lightsecond" => UnitDef.new(symbol: "lightsecond", dimension: LENGTH, factor: 299_792_458),
      "lightminute" => UnitDef.new(symbol: "lightminute", dimension: LENGTH, factor: 17_987_547_480),
      "lighthour"   => UnitDef.new(symbol: "lighthour",   dimension: LENGTH, factor: 1_079_252_848_800),
      # Planck length: ℏ × G / c³, all measured constants → Float.
      "ℓₚ"  => UnitDef.new(symbol: "ℓₚ",  dimension: LENGTH, factor: 1.616255e-35),

      # Imperial mass
      # International avoirdupois pound, exact (1959): 1 lb = 0.45359237 kg.
      "lb"  => UnitDef.new(symbol: "lb",  dimension: MASS, factor: Rational(45359237, 100_000_000)),
      "oz"  => UnitDef.new(symbol: "oz",  dimension: MASS, factor: Rational(45359237, 1_600_000_000)),
      "gr"  => UnitDef.new(symbol: "gr",  dimension: MASS, factor: 6.479891e-5),
      "dr"  => UnitDef.new(symbol: "dr",  dimension: MASS, factor: 1.7718452e-3),
      "st"  => UnitDef.new(symbol: "st",  dimension: MASS, factor: 6.35029),
      "qr"  => UnitDef.new(symbol: "qr",  dimension: MASS, factor: 12.70058),
      "cwt" => UnitDef.new(symbol: "cwt", dimension: MASS, factor: 50.80235),
      "CWT" => UnitDef.new(symbol: "CWT", dimension: MASS, factor: 45.3592),
      "tn"  => UnitDef.new(symbol: "tn",  dimension: MASS, factor: 907.185),
      "LT"  => UnitDef.new(symbol: "LT",  dimension: MASS, factor: 1016.047),
      "t"   => UnitDef.new(symbol: "t",   dimension: MASS, factor: 1000.0),
      "Da"  => UnitDef.new(symbol: "Da",  dimension: MASS, factor: 1.66053906660e-27),
      "u"   => UnitDef.new(symbol: "u",   dimension: MASS, factor: 1.66053906660e-27),
      "slug" => UnitDef.new(symbol: "slug", dimension: MASS, factor: 14.593903),
      # Planck mass: √(ℏc/G)
      "mₚₗ"  => UnitDef.new(symbol: "mₚₗ",  dimension: MASS, factor: 2.176434e-8),

      # Apothecary mass
      "℈"   => UnitDef.new(symbol: "℈",   dimension: MASS, factor: 1.2959782e-3),
      "ʒ"   => UnitDef.new(symbol: "ʒ",   dimension: MASS, factor: 3.8879346e-3),
      "℥"   => UnitDef.new(symbol: "℥",   dimension: MASS, factor: 0.0311034768),
      "℔"   => UnitDef.new(symbol: "℔",   dimension: MASS, factor: 0.3732417216),

      # Mass extras
      "troyounce"  => UnitDef.new(symbol: "troyounce",  dimension: MASS, factor: 0.0311035),
      "pennyweight" => UnitDef.new(symbol: "pennyweight", dimension: MASS, factor: 0.00155517),
      "carat"      => UnitDef.new(symbol: "carat",      dimension: MASS, factor: 0.0002),
      "quintal"    => UnitDef.new(symbol: "quintal",    dimension: MASS, factor: 100.0),

      # Time
      "min" => UnitDef.new(symbol: "min", dimension: TIME, factor: 60.0),
      "h"   => UnitDef.new(symbol: "h",   dimension: TIME, factor: 3600.0),
      "d"   => UnitDef.new(symbol: "d",   dimension: TIME, factor: 86400.0),
      "week"       => UnitDef.new(symbol: "week",       dimension: TIME, factor: 604800.0),
      "month"      => UnitDef.new(symbol: "month",      dimension: TIME, factor: 2629746.0),    # avg Gregorian month (365.2425/12 days)
      "year"       => UnitDef.new(symbol: "year",       dimension: TIME, factor: 31556952.0),    # avg Gregorian year (365.2425 days)
      "decade"     => UnitDef.new(symbol: "decade",     dimension: TIME, factor: 315569520.0),
      "millennium" => UnitDef.new(symbol: "millennium", dimension: TIME, factor: 31556952000.0),
      "fortnight"  => UnitDef.new(symbol: "fortnight",  dimension: TIME, factor: 1209600.0),
      "century"    => UnitDef.new(symbol: "century",    dimension: TIME, factor: 3155695200.0),  # 100 Gregorian years
      "shake"      => UnitDef.new(symbol: "shake",      dimension: TIME, factor: 1e-8),
      # Astronomy: alternative year/day definitions.
      "siderealyear"  => UnitDef.new(symbol: "siderealyear",  dimension: TIME, factor: 31_558_149.504),    # IAU
      "tropicalyear"  => UnitDef.new(symbol: "tropicalyear",  dimension: TIME, factor: 31_556_925.216),
      "julianyear"    => UnitDef.new(symbol: "julianyear",    dimension: TIME, factor: 31_557_600.0),       # exact: 365.25 d
      "siderealday"   => UnitDef.new(symbol: "siderealday",   dimension: TIME, factor: 86_164.0905),
      "lunarmonth"    => UnitDef.new(symbol: "lunarmonth",    dimension: TIME, factor: 2_551_443.84),       # synodic
      "lustrum"       => UnitDef.new(symbol: "lustrum",       dimension: TIME, factor: 157_784_760.0),      # 5 Gregorian years
      "dogyear"       => UnitDef.new(symbol: "dogyear",       dimension: TIME, factor: Rational(31_556_952, 7)),  # exact 1/7 yr
      # Planck time: √(ℏG/c⁵)
      "tₚ"            => UnitDef.new(symbol: "tₚ",            dimension: TIME, factor: 5.391247e-44),

      # Area
      "ac"   => UnitDef.new(symbol: "ac",   dimension: AREA, factor: 4046.8564224),
      "ha"   => UnitDef.new(symbol: "ha",   dimension: AREA, factor: 10000.0),
      "barn" => UnitDef.new(symbol: "barn", dimension: AREA, factor: Rational(1, 10**28)),
      "sqft" => UnitDef.new(symbol: "sqft", dimension: AREA, factor: 0.09290304),
      "sqm"  => UnitDef.new(symbol: "sqm",  dimension: AREA, factor: 1.0),

      # Volume
      # US customary volumes are exact: 1 US gal = 231 in³, and 1 in = 127/5000 m exactly.
      # All sub-volumes are exact integer fractions of a gallon.
      "L"      => UnitDef.new(symbol: "L",      dimension: VOLUME, factor: Rational(1, 1000)),
      "l"      => UnitDef.new(symbol: "l",      dimension: VOLUME, factor: Rational(1, 1000)),
      "gal"    => UnitDef.new(symbol: "gal",    dimension: VOLUME, factor: Rational(473176473, 125_000_000_000)),
      "qt"     => UnitDef.new(symbol: "qt",     dimension: VOLUME, factor: Rational(473176473, 500_000_000_000)),
      "pt"     => UnitDef.new(symbol: "pt",     dimension: VOLUME, factor: Rational(473176473, 1_000_000_000_000)),
      "cup"    => UnitDef.new(symbol: "cup",    dimension: VOLUME, factor: Rational(473176473, 2_000_000_000_000)),
      "gill"   => UnitDef.new(symbol: "gill",   dimension: VOLUME, factor: Rational(473176473, 4_000_000_000_000)),
      "floz"   => UnitDef.new(symbol: "floz",   dimension: VOLUME, factor: Rational(473176473, 16_000_000_000_000)),
      "fldr"   => UnitDef.new(symbol: "fldr",   dimension: VOLUME, factor: Rational(473176473, 128_000_000_000_000)),
      "impgal" => UnitDef.new(symbol: "impgal", dimension: VOLUME, factor: Rational(454609, 100_000_000)),
      # US dry volumes — 1 bushel = 2150.42 in³ exactly.
      "bushel" => UnitDef.new(symbol: "bushel", dimension: VOLUME, factor: Rational(220244188543, 6_250_000_000_000)),
      "peck"   => UnitDef.new(symbol: "peck",   dimension: VOLUME, factor: Rational(220244188543, 25_000_000_000_000)),

      # Cooking — 1 tbsp = 1/256 gal, 1 tsp = 1/768 gal.
      "tbsp"    => UnitDef.new(symbol: "tbsp",    dimension: VOLUME, factor: Rational(473176473, 32_000_000_000_000)),
      "tsp"     => UnitDef.new(symbol: "tsp",     dimension: VOLUME, factor: Rational(157725491, 32_000_000_000_000)),
      "drop"    => UnitDef.new(symbol: "drop",    dimension: VOLUME, factor: 5e-8),
      "dash"    => UnitDef.new(symbol: "dash",    dimension: VOLUME, factor: 6.16115e-7),
      "pinch"   => UnitDef.new(symbol: "pinch",   dimension: VOLUME, factor: 3.080575e-7),
      "smidgen" => UnitDef.new(symbol: "smidgen", dimension: VOLUME, factor: 1.5402875e-7),
      "jigger"  => UnitDef.new(symbol: "jigger",  dimension: VOLUME, factor: 4.43603e-5),

      # Wine/beer casks
      "firkin"    => UnitDef.new(symbol: "firkin",    dimension: VOLUME, factor: 0.04091481),
      "rundlet"   => UnitDef.new(symbol: "rundlet",   dimension: VOLUME, factor: 0.06814),
      "tierce"    => UnitDef.new(symbol: "tierce",    dimension: VOLUME, factor: 0.15898),
      "hogshead"  => UnitDef.new(symbol: "hogshead",  dimension: VOLUME, factor: 0.23848),
      "puncheon"  => UnitDef.new(symbol: "puncheon",  dimension: VOLUME, factor: 0.31797),
      "pipe"      => UnitDef.new(symbol: "pipe",      dimension: VOLUME, factor: 0.47696),
      "tun"       => UnitDef.new(symbol: "tun",       dimension: VOLUME, factor: 0.95392),
      "kilderkin" => UnitDef.new(symbol: "kilderkin", dimension: VOLUME, factor: 0.08182962),

      # Wine & champagne bottle sizes — exact multiples of the 750 mL standard bottle.
      "split"          => UnitDef.new(
        symbol: "split", dimension: VOLUME, factor: Rational(3, 16_000)
      ), # 187.5 mL
      "bottle"         => UnitDef.new(
        symbol: "bottle", dimension: VOLUME, factor: Rational(3, 4_000)
      ), # 750 mL
      "magnum"         => UnitDef.new(
        symbol: "magnum", dimension: VOLUME, factor: Rational(3, 2_000)
      ), # 1.5 L
      "jeroboam"       => UnitDef.new(
        symbol: "jeroboam", dimension: VOLUME, factor: Rational(3, 1_000)
      ), # 3 L
      "methuselah"     => UnitDef.new(
        symbol: "methuselah", dimension: VOLUME, factor: Rational(3, 500)
      ), # 6 L
      "nebuchadnezzar" => UnitDef.new(
        symbol: "nebuchadnezzar", dimension: VOLUME, factor: Rational(3, 200)
      ), # 15 L
      "melchizedek"    => UnitDef.new(
        symbol: "melchizedek", dimension: VOLUME, factor: Rational(3, 100)
      ), # 30 L

      # Pressure
      "bar"  => UnitDef.new(symbol: "bar",  dimension: PRESSURE, factor: 1e5),
      "mbar" => UnitDef.new(symbol: "mbar", dimension: PRESSURE, factor: 100.0),  # milli-bar = 100 Pa
      "Ba"   => UnitDef.new(symbol: "Ba",   dimension: PRESSURE, factor: 0.1),
      "atm"  => UnitDef.new(symbol: "atm",  dimension: PRESSURE, factor: 101325.0),
      "at"   => UnitDef.new(symbol: "at",   dimension: PRESSURE, factor: 98066.5),
      "psi"  => UnitDef.new(symbol: "psi",  dimension: PRESSURE, factor: 6894.757),
      "torr" => UnitDef.new(symbol: "torr", dimension: PRESSURE, factor: Rational(20265, 152)),  # exactly 1 atm / 760
      "Torr" => UnitDef.new(symbol: "Torr", dimension: PRESSURE, factor: Rational(20265, 152)),  # capitalized form
      "mmHg" => UnitDef.new(symbol: "mmHg", dimension: PRESSURE, factor: 133.322),
      "inHg" => UnitDef.new(symbol: "inHg", dimension: PRESSURE, factor: 3386.389),
      "cmH2O" => UnitDef.new(symbol: "cmH2O", dimension: PRESSURE, factor: 98.0665),

      # Force
      # lb × g_n, exact
      "lbf" => UnitDef.new(
        symbol: "lbf", dimension: FORCE, factor: Rational(8_896_443_230_521, 2_000_000_000_000)
      ),
      "kgf" => UnitDef.new(symbol: "kgf", dimension: FORCE, factor: 9.80665),

      # Energy
      "eV"    => UnitDef.new(symbol: "eV",    dimension: ENERGY, factor: 1.602176634e-19),
      "erg"   => UnitDef.new(symbol: "erg",   dimension: ENERGY, factor: 1e-7),
      "cal"   => UnitDef.new(symbol: "cal",   dimension: ENERGY, factor: 4.1868),
      "kcal"  => UnitDef.new(symbol: "kcal",  dimension: ENERGY, factor: 4186.8),
      "BTU"   => UnitDef.new(symbol: "BTU",   dimension: ENERGY, factor: 1055.05585262),
      "therm" => UnitDef.new(symbol: "therm", dimension: ENERGY, factor: 105505585.262),
      "kWh"   => UnitDef.new(symbol: "kWh",   dimension: ENERGY, factor: 3600000.0),
      "ftlbf" => UnitDef.new(symbol: "ftlbf", dimension: ENERGY, factor: 1.3558179483314),
      # Appended after the core energy set (rather than wedged between kWh and
      # ftlbf) so the registry-ordered `?` conversion listing keeps the common
      # units (… kWh, ftlbf) adjacent. kWh×1000; parse target only.
      "MWh"   => UnitDef.new(symbol: "MWh",   dimension: ENERGY, factor: 3600000000.0),

      # Force (non-SI)
      "dyn" => UnitDef.new(symbol: "dyn", dimension: FORCE,  factor: 1e-5),

      # Power
      "hp" => UnitDef.new(symbol: "hp", dimension: POWER, factor: 745.69987158227),
      "PS" => UnitDef.new(symbol: "PS", dimension: POWER, factor: 735.49875),

      # Electromagnetism (non-SI)
      "Ga"  => UnitDef.new(symbol: "Ga",  dimension: MAGNETIC_FLUX_DENSITY, factor: 1e-4),

      # Radioactivity / Dosimetry
      "Bq"  => UnitDef.new(symbol: "Bq",  dimension: FREQUENCY,      factor: 1.0),
      "Ci"  => UnitDef.new(symbol: "Ci",  dimension: FREQUENCY,      factor: 3.7e10),
      "Gy"  => UnitDef.new(symbol: "Gy",  dimension: ABSORBED_DOSE_KIND, factor: 1.0),
      "Sv"  => UnitDef.new(symbol: "Sv",  dimension: EQUIVALENT_DOSE,    factor: 1.0),
      "rem" => UnitDef.new(symbol: "rem", dimension: EQUIVALENT_DOSE,    factor: 0.01),

      # Angle
      "deg"    => UnitDef.new(symbol: "deg",    dimension: ANGLE, factor: Math::PI / 180),
      "rad"    => UnitDef.new(symbol: "rad",    dimension: ANGLE,       factor: 1.0),
      "sr"     => UnitDef.new(symbol: "sr",     dimension: SOLID_ANGLE, factor: 1.0),
      "arcmin" => UnitDef.new(symbol: "arcmin", dimension: ANGLE, factor: Math::PI / 10800),
      "arcsec" => UnitDef.new(symbol: "arcsec", dimension: ANGLE, factor: Math::PI / 648000),
      "gon"    => UnitDef.new(symbol: "gon",    dimension: ANGLE, factor: Math::PI / 200),
      "turn"   => UnitDef.new(symbol: "turn",   dimension: ANGLE, factor: 2 * Math::PI),
      "mil"    => UnitDef.new(symbol: "mil",    dimension: ANGLE, factor: 2 * Math::PI / 6400),
      "brad"   => UnitDef.new(symbol: "brad",   dimension: ANGLE, factor: 2 * Math::PI / 256),

      # Catalytic activity
      "kat" => UnitDef.new(symbol: "kat", dimension: CATALYTIC_ACTIVITY, factor: 1.0),

      # Acceleration
      "Gal" => UnitDef.new(symbol: "Gal", dimension: ACCELERATION, factor: 0.01),

      # Information
      "b"      => UnitDef.new(symbol: "b",      dimension: INFORMATION, factor: 0.125),
      "nibble" => UnitDef.new(symbol: "nibble", dimension: INFORMATION, factor: 0.5),
      "o"      => UnitDef.new(symbol: "o",      dimension: INFORMATION, factor: 1.0),
      "B"      => UnitDef.new(symbol: "B",      dimension: INFORMATION, factor: 1.0),
      "KB"     => UnitDef.new(symbol: "KB",     dimension: INFORMATION, factor: 1e3),
      "PB"     => UnitDef.new(symbol: "PB",     dimension: INFORMATION, factor: 10**15),
      "KiB"    => UnitDef.new(symbol: "KiB",    dimension: INFORMATION, factor: 1024.0),
      "MiB"    => UnitDef.new(symbol: "MiB",    dimension: INFORMATION, factor: 1048576.0),
      "GiB"    => UnitDef.new(symbol: "GiB",    dimension: INFORMATION, factor: 1073741824.0),
      "TiB"    => UnitDef.new(symbol: "TiB",    dimension: INFORMATION, factor: 1024.0**4),
      "PiB"    => UnitDef.new(symbol: "PiB",    dimension: INFORMATION, factor: 1024.0**5),
      "EiB"    => UnitDef.new(symbol: "EiB",    dimension: INFORMATION, factor: 1024.0**6),

      # Data rate
      "bps"  => UnitDef.new(symbol: "bps",  dimension: DATA_RATE, factor: 0.125),
      "Bps"  => UnitDef.new(symbol: "Bps",  dimension: DATA_RATE, factor: 1.0),
      "baud" => UnitDef.new(symbol: "baud", dimension: DATA_RATE, factor: 0.125),

      # Viscosity
      "P"   => UnitDef.new(symbol: "P",   dimension: DYNAMIC_VISCOSITY,   factor: 0.1),
      "cP"  => UnitDef.new(symbol: "cP",  dimension: DYNAMIC_VISCOSITY,   factor: 0.001),
      "St"  => UnitDef.new(symbol: "St",  dimension: KINEMATIC_VISCOSITY, factor: 1e-4),
      "cSt" => UnitDef.new(symbol: "cSt", dimension: KINEMATIC_VISCOSITY, factor: 1e-6),

      # Astronomy
      "solarmass"   => UnitDef.new(symbol: "solarmass",   dimension: MASS,   factor: 1.98892e30),
      "earthmass"   => UnitDef.new(symbol: "earthmass",   dimension: MASS,   factor: 5.9722e24),
      "jupitermass" => UnitDef.new(symbol: "jupitermass", dimension: MASS,   factor: 1.8986e27),
      "moonmass"    => UnitDef.new(symbol: "moonmass",    dimension: MASS,   factor: 7.342e22),
      "solarradius" => UnitDef.new(symbol: "solarradius", dimension: LENGTH, factor: 6.96e8),
      "earthradius" => UnitDef.new(symbol: "earthradius", dimension: LENGTH, factor: 6.371e6),

      # Typography
      "point"  => UnitDef.new(symbol: "point",  dimension: LENGTH, factor: 0.000352778),
      "pica"   => UnitDef.new(symbol: "pica",   dimension: LENGTH, factor: 0.004233333),
      "texpt"  => UnitDef.new(symbol: "texpt",  dimension: LENGTH, factor: 0.0254 / 72.27),
      "didot"  => UnitDef.new(symbol: "didot",  dimension: LENGTH, factor: 3.76065e-4),
      "cicero" => UnitDef.new(symbol: "cicero", dimension: LENGTH, factor: 4.51278e-3),

      # Exotic length
      "altuve" => UnitDef.new(symbol: "altuve", dimension: LENGTH, factor: 1.65),

      # Exotic area
      "outhouse" => UnitDef.new(symbol: "outhouse", dimension: AREA, factor: 1e-34),
      "shed"     => UnitDef.new(symbol: "shed",     dimension: AREA, factor: 1e-52),

      # Exotic volume
      "barrel" => UnitDef.new(symbol: "barrel", dimension: VOLUME, factor: 0.11924),
      "stere"  => UnitDef.new(symbol: "stere",  dimension: VOLUME, factor: 1.0),
      "cord"   => UnitDef.new(symbol: "cord",   dimension: VOLUME, factor: 3.624556),

      # Exotic length
      "beard second" => UnitDef.new(symbol: "beard second", dimension: LENGTH, factor: 5e-9),

      # Exotic area/volume
      "barn megaparsec" => UnitDef.new(symbol: "barn megaparsec", dimension: VOLUME, factor: 3.0856775814914e-6),

      # Exotic dosimetry
      "banana" => UnitDef.new(symbol: "banana", dimension: EQUIVALENT_DOSE, factor: 1e-7,
        description: "banana equivalent dose — informal radiation dose from one average banana (potassium-40); ≈ 0.1 µSv",
        measured: true, year_defined: 1995, defining_source: "Gary Mansfield, Lawrence Livermore"),

      # Fame (minutes of fame; 1 warhol = 15 minutes of fame)
      "warhol"     => UnitDef.new(symbol: "warhol",     dimension: Dimension.custom("fame"), factor: 15),
      "kilowarhol" => UnitDef.new(symbol: "kilowarhol", dimension: Dimension.custom("fame"), factor: 15_000),

      # Frequency / rotation
      "rpm" => UnitDef.new(symbol: "rpm", dimension: FREQUENCY, factor: Rational(1, 60)),  # exact

      # Radioactivity (rutherford)
      "rd"  => UnitDef.new(symbol: "rd",  dimension: FREQUENCY, factor: 1e6),

      # Maxwell — CGS magnetic flux. (oersted/gilbert skipped: their dimension
      # A/m has no direct slot in our 8-axis SI Dimension struct.)
      "Mx"  => UnitDef.new(symbol: "Mx",  dimension: MAGNETIC_FLUX, factor: 1e-8),

      # (rad-the-radiation-unit collides with rad-the-radian; skipped — use Gy or rem instead.)

      # Beauty (custom dimension)
      "millihelen" => UnitDef.new(symbol: "millihelen", dimension: Dimension.custom("beauty"), factor: 1.0),

      # Luminance (photometric; distinct from illuminance/lux)
      "nit" => UnitDef.new(symbol: "nit", dimension: LUMINANCE, factor: 1.0),
      "sb"  => UnitDef.new(symbol: "sb",  dimension: LUMINANCE, factor: 10_000.0),
      "La"  => UnitDef.new(symbol: "La",  dimension: LUMINANCE, factor: 10_000.0 / Math::PI),
      "fL"  => UnitDef.new(symbol: "fL",  dimension: LUMINANCE, factor: 1.0 / (Math::PI * 0.3048**2)),
      "asb" => UnitDef.new(symbol: "asb", dimension: LUMINANCE, factor: 1.0 / Math::PI),
      "sk"  => UnitDef.new(symbol: "sk",  dimension: LUMINANCE, factor: 0.001 / Math::PI),

      # Typographic (custom dimension)
      "em"    => UnitDef.new(symbol: "em",    dimension: Dimension.custom("em"), factor: 1.0),
      "en"    => UnitDef.new(symbol: "en",    dimension: Dimension.custom("em"), factor: 0.5),
      "qquad" => UnitDef.new(symbol: "qquad", dimension: Dimension.custom("em"), factor: 2.0),

      # ♫ It's peanut butter jelly time! ♫ — see Quantity#+ for the easter egg.
      "peanutbutter" => UnitDef.new(symbol: "peanutbutter", dimension: Dimension.custom("peanutbutter"), factor: 1.0),
      "jelly"        => UnitDef.new(symbol: "jelly",        dimension: Dimension.custom("jelly"),        factor: 1.0),

      # Unconvertible time-like units (custom dimensions)
      "beat"    => UnitDef.new(symbol: "beat",    dimension: Dimension.custom("beat"),    factor: 1.0),
      "cycle"   => UnitDef.new(symbol: "cycle",   dimension: Dimension.custom("cycle"),   factor: 1.0),
      "frame"   => UnitDef.new(symbol: "frame",   dimension: Dimension.custom("frame"),   factor: 1.0),
      "instant" => UnitDef.new(symbol: "instant", dimension: Dimension.custom("instant"), factor: 1.0),
      "jiffy"   => UnitDef.new(symbol: "jiffy",   dimension: Dimension.custom("jiffy"),   factor: 1.0),
      "moment"  => UnitDef.new(symbol: "moment",  dimension: Dimension.custom("moment"),  factor: 1.0),
      "sample"  => UnitDef.new(symbol: "sample",  dimension: Dimension.custom("sample"),  factor: 1.0),
      "tick"    => UnitDef.new(symbol: "tick",    dimension: Dimension.custom("tick"),    factor: 1.0),

      # Compositional numerators — `Hz = cycle/s`, `rpm = revolution/min`, `Bq = decay/s`.
      # Each gets its own custom dimension so 60 rpm + 60 Hz raises (revolutions ≠ cycles)
      # and (3000 rpm)·(2 min) cleanly cancels to 6000 revolutions.
      "revolution" => UnitDef.new(symbol: "revolution", dimension: Dimension.custom("revolution"), factor: 1),
      "decay"      => UnitDef.new(symbol: "decay",      dimension: Dimension.custom("decay"),      factor: 1),
      "rotation"   => UnitDef.new(symbol: "rotation",   dimension: Dimension.custom("rotation"),   factor: 1),

      # Compute counts (custom-dimension count units; pair with /s in COMPOUND_DEFS for FLOPS, TOPS, etc.)
      "flop"        => UnitDef.new(symbol: "flop",        dimension: Dimension.custom("flop"),        factor: 1),
      "op"          => UnitDef.new(symbol: "op",          dimension: Dimension.custom("op"),          factor: 1),
      "mac"         => UnitDef.new(symbol: "mac",         dimension: Dimension.custom("mac"),         factor: 1),
      "instruction" => UnitDef.new(symbol: "instruction", dimension: Dimension.custom("instruction"), factor: 1),
      "tok"         => UnitDef.new(symbol: "tok",         dimension: Dimension.custom("token"),       factor: 1),
      "transfer"    => UnitDef.new(symbol: "transfer",    dimension: Dimension.custom("transfer"),    factor: 1),
      "query"       => UnitDef.new(symbol: "query",       dimension: Dimension.custom("query"),       factor: 1),
      "request"     => UnitDef.new(symbol: "request",     dimension: Dimension.custom("request"),     factor: 1),
      "txn"         => UnitDef.new(symbol: "txn",         dimension: Dimension.custom("transaction"), factor: 1),
      "packet"      => UnitDef.new(symbol: "packet",      dimension: Dimension.custom("packet"),      factor: 1),
      "io"          => UnitDef.new(symbol: "io",          dimension: Dimension.custom("io"),          factor: 1),

      # Information theory (alongside b/B in INFORMATION; factor is bytes since B is the SI canonical here)
      # 1 bit = 0.125 B; 1 nat = (1/ln 2) bits = 0.125/ln(2) B; 1 ban = log₂(10) bits.
      "nat"     => UnitDef.new(symbol: "nat",     dimension: INFORMATION, factor: 0.125 / Math.log(2)),
      "ban"     => UnitDef.new(symbol: "ban",     dimension: INFORMATION, factor: 0.125 * Math.log2(10)),
      "deciban" => UnitDef.new(symbol: "deciban", dimension: INFORMATION, factor: 0.125 * Math.log2(10) / 10),

      # Concentration (dimensionless ratios, alongside percent)
      "ppm"  => UnitDef.new(symbol: "ppm",  dimension: RATIO, factor: 1e-6),
      "ppb"  => UnitDef.new(symbol: "ppb",  dimension: RATIO, factor: 1e-9),
      "ppt"  => UnitDef.new(symbol: "ppt",  dimension: RATIO, factor: 1e-12),
      "pphm" => UnitDef.new(symbol: "pphm", dimension: RATIO, factor: 1e-8),

      # Acoustics (perceptual; custom dims so they don't compose with SI mass/time)
      "sone" => UnitDef.new(symbol: "sone", dimension: Dimension.custom("loudness"),       factor: 1),
      "phon" => UnitDef.new(symbol: "phon", dimension: Dimension.custom("loudness_level"), factor: 1),

      # Astronomy: spectral flux density
      # 1 Jy = 1e-26 W·m⁻²·Hz⁻¹. Custom dim so it doesn't blur into magnetic_flux_density (which has
      # the same SI exponents — kg·s⁻²) and trigger surprising compatibility.
      "Jy" => UnitDef.new(symbol: "Jy", dimension: Dimension.custom("spectral_flux_density"), factor: 1.0),

      # Magnitude (astronomy; logarithmic, reverse-direction; each variant is its own custom dim)
      "mag"   => UnitDef.new(symbol: "mag",   dimension: Dimension.custom("magnitude_apparent"),    factor: 1),
      "Mag"   => UnitDef.new(symbol: "Mag",   dimension: Dimension.custom("magnitude_absolute"),    factor: 1),
      "M_bol" => UnitDef.new(symbol: "M_bol", dimension: Dimension.custom("magnitude_bolometric"),  factor: 1),

      # Particle physics: barn extensions and integrated luminosity
      "femtobarn" => UnitDef.new(symbol: "femtobarn", dimension: AREA,         factor: 1e-43),
      "attobarn"  => UnitDef.new(symbol: "attobarn",  dimension: AREA,         factor: 1e-46),
      "picobarn"  => UnitDef.new(symbol: "picobarn",  dimension: AREA,         factor: 1e-40),
      "nanobarn"  => UnitDef.new(symbol: "nanobarn",  dimension: AREA,         factor: 1e-37),
      "fb⁻¹"      => UnitDef.new(symbol: "fb⁻¹",      dimension: INVERSE_AREA, factor: 1e43),
      "ab⁻¹"      => UnitDef.new(symbol: "ab⁻¹",      dimension: INVERSE_AREA, factor: 1e46),
      "pb⁻¹"      => UnitDef.new(symbol: "pb⁻¹",      dimension: INVERSE_AREA, factor: 1e40),
      "nb⁻¹"      => UnitDef.new(symbol: "nb⁻¹",      dimension: INVERSE_AREA, factor: 1e37),

      # EM legacy (oersted/gilbert reinstated — A/m and A both fit the 8-axis SI dimension)
      "Oe"    => UnitDef.new(symbol: "Oe",    dimension: MAGNETIC_FIELD_H, factor: 1000.0 / (4 * Math::PI)),  # 1 Oe = (10³/4π) A/m
      "Gb"    => UnitDef.new(symbol: "Gb",    dimension: CURRENT,          factor: 10.0 / (4 * Math::PI)),    # gilbert = (10/4π) A
      "D"     => UnitDef.new(symbol: "D",     dimension: ELECTRIC_DIPOLE,  factor: 3.33564e-30),               # debye
      "μ_B"   => UnitDef.new(symbol: "μ_B",   dimension: MAGNETIC_MOMENT,  factor: 9.2740100783e-24),          # bohr magneton

      # Risk
      "micromort" => UnitDef.new(symbol: "micromort", dimension: DIMENSIONLESS, factor: 1e-6),
      "microlife" => UnitDef.new(symbol: "microlife", dimension: TIME,          factor: 1800.0),  # 30 min

      # Wavenumber (spectroscopy)
      "kayser" => UnitDef.new(symbol: "kayser", dimension: INVERSE_LENGTH, factor: 100.0),  # 1 cm⁻¹ = 100 m⁻¹

      # Hardness (each scale incompatible — custom dim per scale)
      "mohs"     => UnitDef.new(symbol: "mohs",     dimension: Dimension.custom("hardness_mohs"),     factor: 1),
      "vickers"  => UnitDef.new(symbol: "vickers",  dimension: Dimension.custom("hardness_vickers"),  factor: 1),
      "rockwell" => UnitDef.new(symbol: "rockwell", dimension: Dimension.custom("hardness_rockwell"), factor: 1),
      "brinell"  => UnitDef.new(symbol: "brinell",  dimension: Dimension.custom("hardness_brinell"),  factor: 1),

      # Counting groupings (DIMENSIONLESS multipliers)
      "dozen"           => UnitDef.new(symbol: "dozen",           dimension: DIMENSIONLESS, factor: 12),
      "gross"           => UnitDef.new(symbol: "gross",           dimension: DIMENSIONLESS, factor: 144),
      "great_gross"     => UnitDef.new(symbol: "great_gross",     dimension: DIMENSIONLESS, factor: 1728),
      "score"           => UnitDef.new(symbol: "score",           dimension: DIMENSIONLESS, factor: 20),
      "bakers_dozen"    => UnitDef.new(symbol: "bakers_dozen",    dimension: DIMENSIONLESS, factor: 13),
      "googol"          => UnitDef.new(symbol: "googol",          dimension: DIMENSIONLESS, factor: 10**100),
      # 10**(10**100) is unrepresentable; we use 10**1000 as a placeholder bignum so the
      # registration is functional while honestly larger than anything you could otherwise spell.
      "googolplex"      => UnitDef.new(symbol: "googolplex",      dimension: DIMENSIONLESS, factor: 10**1000),

      # Talmudic / biblical — length
      "cubit"        => UnitDef.new(symbol: "cubit",        dimension: LENGTH, factor: 0.4572),    # ~18 in (R. Avraham Chaim Naeh)
      "span"         => UnitDef.new(symbol: "span",         dimension: LENGTH, factor: 0.2286),    # zeret = ½ cubit
      "handbreadth"  => UnitDef.new(symbol: "handbreadth",  dimension: LENGTH, factor: 0.0762),    # tefach = ⅙ cubit
      "fingerbreadth"=> UnitDef.new(symbol: "fingerbreadth",dimension: LENGTH, factor: 0.01905),   # etzba = ¼ tefach
      "biblical_mil" => UnitDef.new(symbol: "biblical_mil", dimension: LENGTH, factor: 914.4),     # 2000 cubits
      "parsa"        => UnitDef.new(symbol: "parsa",        dimension: LENGTH, factor: 3657.6),    # 4 mil
      "techum"       => UnitDef.new(symbol: "techum",       dimension: LENGTH, factor: 914.4),     # Sabbath day's journey = 2000 cubits

      # Talmudic — volume (log-the-volume-unit is omitted to avoid clashing with logarithm conventions)
      "omer"   => UnitDef.new(symbol: "omer",   dimension: VOLUME, factor: 0.00216),    # ~2.16 L
      "ephah"  => UnitDef.new(symbol: "ephah",  dimension: VOLUME, factor: 0.0216),     # 10 omer
      "hin"    => UnitDef.new(symbol: "hin",    dimension: VOLUME, factor: 0.0036),     # ⅙ ephah
      "bath"   => UnitDef.new(symbol: "bath",   dimension: VOLUME, factor: 0.0216),     # = ephah for liquid
      "seah"   => UnitDef.new(symbol: "seah",   dimension: VOLUME, factor: 0.0072),     # ⅓ ephah
      "kor"    => UnitDef.new(symbol: "kor",    dimension: VOLUME, factor: 0.216),      # 30 seah
      "kab"    => UnitDef.new(symbol: "kab",    dimension: VOLUME, factor: 0.0012),     # ⅙ seah

      # Talmudic — mass
      "shekel"      => UnitDef.new(symbol: "shekel",      dimension: MASS, factor: 0.0115),       # ~11.5 g
      "biblical_mina"=> UnitDef.new(symbol: "biblical_mina",dimension: MASS, factor: 0.575),       # 50 shekels
      "biblical_talent"=>UnitDef.new(symbol:"biblical_talent",dimension:MASS, factor: 34.5),       # 60 mina
      "gerah"       => UnitDef.new(symbol: "gerah",       dimension: MASS, factor: 0.000575),     # 1/20 shekel
      "beka"        => UnitDef.new(symbol: "beka",        dimension: MASS, factor: 0.00575),      # ½ shekel

      # Talmudic — time (helek = chelek = 1/1080 hour, used in lunar calendar calc)
      "helek"  => UnitDef.new(symbol: "helek",  dimension: TIME, factor: Rational(10, 3)),    # 3⅓ s exact
      "rega"   => UnitDef.new(symbol: "rega",   dimension: TIME, factor: Rational(76, 405)),  # 1/76 helek (Maimonides)
      "onah"   => UnitDef.new(symbol: "onah",   dimension: TIME, factor: 43200.0),            # 12 hours
      "yovel"  => UnitDef.new(symbol: "yovel",  dimension: TIME, factor: 1577847600.0),       # 50 Gregorian years
      "shmita" => UnitDef.new(symbol: "shmita", dimension: TIME, factor: 220898664.0),        # 7 Gregorian years

      # Standard gravity (distinct from `g` = gram)
      "g₀"  => UnitDef.new(symbol: "g₀",  dimension: ACCELERATION, factor: 9.80665),
      "g_n" => UnitDef.new(symbol: "g_n", dimension: ACCELERATION, factor: 9.80665),
      "gee" => UnitDef.new(symbol: "gee", dimension: ACCELERATION, factor: 9.80665),

      # Fuel economy and inverse-fuel-economy (mpg = m⁻², L/100km = m²)
      # 1 mpg = (1609.344 m) / (gal in m³). Use US gallon = 0.003785411784 m³ exactly.
      "mpg"  => UnitDef.new(symbol: "mpg",  dimension: INVERSE_AREA, factor: 1609.344 / 0.003785411784),
      "mpge" => UnitDef.new(symbol: "mpge", dimension: INVERSE_AREA, factor: 1609.344 / 0.003785411784),
      "L/100km" => UnitDef.new(symbol: "L/100km", dimension: AREA, factor: 1e-8),  # 1 L per 100 km = 1e-8 m²

      # Stick of butter — US: 1/4 lb = 4 oz mass
      "stick" => UnitDef.new(symbol: "stick", dimension: MASS, factor: Rational(45359237, 400_000_000)),  # ¼ lb exact

      # Tonne aliases spelled with "ton" — based on metric tonne, used for explosive yield.
      "kiloton" => UnitDef.new(symbol: "kiloton", dimension: MASS, factor: 1e6),    # 10³ tonnes
      "megaton" => UnitDef.new(symbol: "megaton", dimension: MASS, factor: 1e9),    # 10⁶ tonnes
      "gigaton" => UnitDef.new(symbol: "gigaton", dimension: MASS, factor: 1e12),   # 10⁹ tonnes

      # Petroleum/oil — 42 US gal "barrel of oil" (distinct from Tungsten's smaller `barrel`)
      "oil_barrel" => UnitDef.new(symbol: "oil_barrel", dimension: VOLUME, factor: 0.158987294928),
      # BOE = barrel of oil equivalent, standardized at 5.8 × 10⁶ BTU = 6.12 GJ
      "BOE"        => UnitDef.new(symbol: "BOE",        dimension: ENERGY, factor: 6.119e9),
      # TCE = tonne of coal equivalent, 29.31 GJ
      "TCE"        => UnitDef.new(symbol: "TCE",        dimension: ENERGY, factor: 29.31e9),

      # Sorites: a heap stays a heap when you add or remove finite amounts.
      # `heap` arithmetic is absorbing (see Quantity#+ and friends).
      "heap" => UnitDef.new(symbol: "heap", dimension: Dimension.custom("heap"), factor: 1),
      # A hole is countable but indivisible: half a hole rounds up to one whole hole.
      "hole" => UnitDef.new(symbol: "hole", dimension: Dimension.custom("hole"), factor: 1),

      # Japanese (shaku-kan system; values from Japanese Weights and Measures Act)
      "shaku"   => UnitDef.new(symbol: "shaku",   dimension: LENGTH, factor: Rational(10, 33)),       # 10/33 m exact
      "sun"     => UnitDef.new(symbol: "sun",     dimension: LENGTH, factor: Rational(1, 33)),        # shaku/10
      "ri"      => UnitDef.new(symbol: "ri",      dimension: LENGTH, factor: Rational(12_960, 33)),   # 36 chō ≈ 3.927 km
      "jo"      => UnitDef.new(symbol: "jo",      dimension: LENGTH, factor: Rational(100, 33)),      # 10 shaku
      "tsubo"   => UnitDef.new(symbol: "tsubo",   dimension: AREA,   factor: Rational(400, 121)),     # ≈ 3.306 m²
      "tatami"  => UnitDef.new(symbol: "tatami",  dimension: AREA,   factor: Rational(200, 121)),     # ½ tsubo, Kyōma
      "koku"    => UnitDef.new(symbol: "koku",    dimension: VOLUME, factor: 0.18039),                # ~180.39 L
      "gō"      => UnitDef.new(symbol: "gō",      dimension: VOLUME, factor: 0.00018039),             # koku/1000, ~180 mL
      "momme"   => UnitDef.new(symbol: "momme",   dimension: MASS,   factor: 0.00375),                # 3.75 g
      "kanme"   => UnitDef.new(symbol: "kanme",   dimension: MASS,   factor: 3.75),                   # 1000 momme

      # Chinese (modern shi system, post-1929 standardization)
      "chi"   => UnitDef.new(symbol: "chi",   dimension: LENGTH, factor: Rational(1, 3)),             # ⅓ m exact
      "cun"   => UnitDef.new(symbol: "cun",   dimension: LENGTH, factor: Rational(1, 30)),            # chi/10
      "fen"   => UnitDef.new(symbol: "fen",   dimension: LENGTH, factor: Rational(1, 300)),           # cun/10
      "zhang" => UnitDef.new(symbol: "zhang", dimension: LENGTH, factor: Rational(10, 3)),            # 10 chi
      "li_cn" => UnitDef.new(symbol: "li_cn", dimension: LENGTH, factor: 500),                        # 500 m exact (Chinese li)
      "mu"    => UnitDef.new(symbol: "mu",    dimension: AREA,   factor: Rational(2000, 3)),          # ≈ 666.67 m²
      "jin"   => UnitDef.new(symbol: "jin",   dimension: MASS,   factor: 0.5),                        # 500 g exact (modern)
      "liang" => UnitDef.new(symbol: "liang", dimension: MASS,   factor: 0.05),                       # jin/10
      "dan_cn"=> UnitDef.new(symbol: "dan_cn",dimension: MASS,   factor: 50),                         # 100 jin (Chinese)

      # Russian historical (pre-1924 metrication)
      "verst"    => UnitDef.new(symbol: "verst",    dimension: LENGTH, factor: 1066.8),               # 500 sazhen
      "arshin"   => UnitDef.new(symbol: "arshin",   dimension: LENGTH, factor: 0.7112),               # ⅓ sazhen, 28 in
      "sazhen"   => UnitDef.new(symbol: "sazhen",   dimension: LENGTH, factor: 2.1336),               # 3 arshin
      "vershok"  => UnitDef.new(symbol: "vershok",  dimension: LENGTH, factor: 0.04445),              # arshin/16
      "pud"      => UnitDef.new(symbol: "pud",      dimension: MASS,   factor: 16.3805),              # 40 funt
      "funt_ru"  => UnitDef.new(symbol: "funt_ru",  dimension: MASS,   factor: 0.40951241),           # Russian funt
      "chetvert" => UnitDef.new(symbol: "chetvert", dimension: VOLUME, factor: 0.20991),              # ~209.91 L

      # French historical (pre-revolutionary, "pied du roi" system)
      "pied"           => UnitDef.new(symbol: "pied",           dimension: LENGTH, factor: 0.3248406),  # pied du roi
      "pouce"          => UnitDef.new(symbol: "pouce",          dimension: LENGTH, factor: 0.02707),    # pied/12
      "toise"          => UnitDef.new(symbol: "toise",          dimension: LENGTH, factor: 1.949036),   # 6 pieds
      "arpent"         => UnitDef.new(symbol: "arpent",         dimension: AREA,   factor: 3418.89),    # arpent de Paris
      "lieue_de_poste" => UnitDef.new(symbol: "lieue_de_poste", dimension: LENGTH, factor: 3898.072),   # 2000 toises

      # Roman
      "pes"           => UnitDef.new(symbol: "pes",           dimension: LENGTH, factor: 0.296),      # Roman foot
      "passus"        => UnitDef.new(symbol: "passus",        dimension: LENGTH, factor: 1.48),       # 5 pedes
      "mille_passuum" => UnitDef.new(symbol: "mille_passuum", dimension: LENGTH, factor: 1480),       # Roman mile
      "iugerum"       => UnitDef.new(symbol: "iugerum",       dimension: AREA,   factor: 2519.43),    # ≈ ⅔ acre
      "libra_roma"    => UnitDef.new(symbol: "libra_roma",    dimension: MASS,   factor: 0.32894),    # Roman pound
      "uncia_roma"    => UnitDef.new(symbol: "uncia_roma",    dimension: MASS,   factor: 0.0274),     # libra/12
      "amphora"       => UnitDef.new(symbol: "amphora",       dimension: VOLUME, factor: 0.02624),    # ≈ 26.24 L

      # Ancient Egyptian (royal cubit system)
      "royal_cubit" => UnitDef.new(symbol: "royal_cubit", dimension: LENGTH, factor: 0.525),         # 7 palms
      "egypt_palm"  => UnitDef.new(symbol: "egypt_palm",  dimension: LENGTH, factor: 0.075),         # cubit/7
      "digit"       => UnitDef.new(symbol: "digit",       dimension: LENGTH, factor: 0.01875),       # palm/4
      "khet"        => UnitDef.new(symbol: "khet",        dimension: LENGTH, factor: 52.5),          # 100 cubits
      "aroura"      => UnitDef.new(symbol: "aroura",      dimension: AREA,   factor: 2756.25),       # khet²

      # Indian historical (commerce-era units)
      "hath"  => UnitDef.new(symbol: "hath",  dimension: LENGTH, factor: 0.4572),     # cubit, 18 in
      "gaz"   => UnitDef.new(symbol: "gaz",   dimension: LENGTH, factor: 0.9144),     # yard
      "kos"   => UnitDef.new(symbol: "kos",   dimension: LENGTH, factor: 3219.0),     # ≈ 2 mi (varies by region)
      "tola"  => UnitDef.new(symbol: "tola",  dimension: MASS,   factor: 0.011664),   # ~11.66 g
      "seer"  => UnitDef.new(symbol: "seer",  dimension: MASS,   factor: 0.93310),    # 80 tolas
      "maund" => UnitDef.new(symbol: "maund", dimension: MASS,   factor: 37.3242),    # 40 seers

      # Atomic / quantum constants (length, energy, mass)
      "hartree"        => UnitDef.new(symbol: "hartree",        dimension: ENERGY, factor: 4.3597447222071e-18,
        description: "hartree — atomic unit of energy; the energy of an electron in the ground state of hydrogen; 1 Eh ≈ 27.211 eV",
        measured: true, year_defined: 1928, defining_source: "Douglas Hartree; CODATA value"),
      "rydberg_unit"   => UnitDef.new(symbol: "rydberg_unit",   dimension: ENERGY, factor: 2.1798723611035e-18),
      "bohr_radius"    => UnitDef.new(symbol: "bohr_radius",    dimension: LENGTH, factor: 5.29177210903e-11,
        description: "Bohr radius — most probable distance of the electron from the nucleus in hydrogen ground state; the atomic unit of length",
        measured: true, year_defined: 1913, defining_source: "Niels Bohr; CODATA 2018 value"),
      "compton_e"      => UnitDef.new(symbol: "compton_e",      dimension: LENGTH, factor: 2.42631023867e-12),  # electron
      "compton_p"      => UnitDef.new(symbol: "compton_p",      dimension: LENGTH, factor: 1.32140985539e-15),  # proton
      "compton_n"      => UnitDef.new(symbol: "compton_n",      dimension: LENGTH, factor: 1.31959090581e-15),  # neutron
      "fine_structure" => UnitDef.new(symbol: "fine_structure", dimension: DIMENSIONLESS, factor: 7.2973525693e-3),

      # Particle masses
      "electron_mass" => UnitDef.new(symbol: "electron_mass", dimension: MASS, factor: 9.1093837015e-31,
        description: "rest mass of an electron; ≈ 1/1836 of the proton mass",
        measured: true, year_defined: 2018, defining_source: "CODATA 2018"),
      "proton_mass"   => UnitDef.new(symbol: "proton_mass",   dimension: MASS, factor: 1.67262192369e-27,
        description: "rest mass of a proton",
        measured: true, year_defined: 2018, defining_source: "CODATA 2018"),
      "neutron_mass"  => UnitDef.new(symbol: "neutron_mass",  dimension: MASS, factor: 1.67492749804e-27,
        description: "rest mass of a neutron",
        measured: true, year_defined: 2018, defining_source: "CODATA 2018"),
      "muon_mass"     => UnitDef.new(symbol: "muon_mass",     dimension: MASS, factor: 1.883531627e-28),

      # Power flavors (alongside hp, PS)
      "boiler_horsepower"   => UnitDef.new(symbol: "boiler_horsepower",   dimension: POWER, factor: 9809.5),
      "electric_horsepower" => UnitDef.new(symbol: "electric_horsepower", dimension: POWER, factor: 746.0),
      "water_horsepower"    => UnitDef.new(symbol: "water_horsepower",    dimension: POWER, factor: 746.043),
      "donkeypower"         => UnitDef.new(symbol: "donkeypower",         dimension: POWER, factor: 250.13),  # ≈ ⅓ hp

      # International cooking
      "metric_cup"      => UnitDef.new(symbol: "metric_cup",      dimension: VOLUME, factor: Rational(1, 4_000)),    # 250 mL exact
      "metric_tbsp"     => UnitDef.new(symbol: "metric_tbsp",     dimension: VOLUME, factor: Rational(15, 1_000_000)), # 15 mL exact
      "australian_tbsp" => UnitDef.new(symbol: "australian_tbsp", dimension: VOLUME, factor: Rational(20, 1_000_000)), # 20 mL exact
      "japanese_cup"    => UnitDef.new(symbol: "japanese_cup",    dimension: VOLUME, factor: Rational(1, 5_000)),    # 200 mL exact
      "imperial_pint"   => UnitDef.new(symbol: "imperial_pint",   dimension: VOLUME, factor: 0.000568261485),         # 568.26 mL

      # Storage primitives (computer architecture)
      "crumb"     => UnitDef.new(symbol: "crumb",     dimension: INFORMATION, factor: 0.25),       # 2 bits
      "dword"     => UnitDef.new(symbol: "dword",     dimension: INFORMATION, factor: 4),
      "qword"     => UnitDef.new(symbol: "qword",     dimension: INFORMATION, factor: 8),
      "paragraph" => UnitDef.new(symbol: "paragraph", dimension: INFORMATION, factor: 16),         # x86 paragraph
      "sector"    => UnitDef.new(symbol: "sector",    dimension: INFORMATION, factor: 512),        # traditional disk sector
      "page"      => UnitDef.new(symbol: "page",      dimension: INFORMATION, factor: 4096),       # typical VM page
      "block"     => UnitDef.new(symbol: "block",     dimension: INFORMATION, factor: 1024),       # 1 KiB block
      "cluster"   => UnitDef.new(symbol: "cluster",   dimension: INFORMATION, factor: 4096),       # filesystem allocation

      # Photography (custom dim — log-domain values, but flat for now)
      "EV"             => UnitDef.new(symbol: "EV",             dimension: Dimension.custom("exposure_value"),  factor: 1),
      "f_stop"         => UnitDef.new(symbol: "f_stop",         dimension: Dimension.custom("f_stop"),          factor: 1),
      "ISO_speed"      => UnitDef.new(symbol: "ISO_speed",      dimension: Dimension.custom("iso_sensitivity"), factor: 1),

      # Pitch (music — distinct dim from money)
      "cent_pitch" => UnitDef.new(symbol: "cent_pitch", dimension: Dimension.custom("pitch"),        factor: 1),       # 1/100 semitone
      "semitone"   => UnitDef.new(symbol: "semitone",   dimension: Dimension.custom("pitch"),        factor: 100),     # 100 cents
      "savart"     => UnitDef.new(symbol: "savart",     dimension: Dimension.custom("pitch"),        factor: Rational(1000, 301)),  # ≈ 3.32 cents
      "octave"     => UnitDef.new(symbol: "octave",     dimension: Dimension.custom("pitch"),        factor: 1200),    # 12 semitones

      # Money quanta (dimensionless ratios; multiply by a Currency to get a money amount)
      "basis_point" => UnitDef.new(symbol: "basis_point", dimension: DIMENSIONLESS, factor: 1e-4),
      "tenth_cent"  => UnitDef.new(symbol: "tenth_cent",  dimension: DIMENSIONLESS, factor: 1e-3),    # 0.001 dollar fractional, also "mill"
      "pip"         => UnitDef.new(symbol: "pip",         dimension: DIMENSIONLESS, factor: 1e-4),    # forex price increment

      # Old British / imperial — closing the gap
      "link_chain"   => UnitDef.new(symbol: "link_chain",   dimension: LENGTH, factor: 0.201168),    # 1/100 chain (Gunter)
      "rope"         => UnitDef.new(symbol: "rope",         dimension: LENGTH, factor: 6.096),       # 20 ft exact
      "perch"        => UnitDef.new(symbol: "perch",        dimension: LENGTH, factor: 5.0292),      # = rod
      "barleycorn"   => UnitDef.new(symbol: "barleycorn",   dimension: LENGTH, factor: Rational(127, 15_000)),  # 1/3 in exact
      "shaftment"    => UnitDef.new(symbol: "shaftment",    dimension: LENGTH, factor: Rational(381, 2_500)),   # 6 in exact
      "english_cubit"=> UnitDef.new(symbol: "english_cubit",dimension: LENGTH, factor: 0.4572),      # 18 in
      "nail_cloth"   => UnitDef.new(symbol: "nail_cloth",   dimension: LENGTH, factor: 0.05715),     # 2.25 in (cloth)
      "cable_length" => UnitDef.new(symbol: "cable_length", dimension: LENGTH, factor: 185.2),       # international, 1/10 nmi

      # Pressure water columns (compatible with cmH2O)
      "mH2O"  => UnitDef.new(symbol: "mH2O",  dimension: PRESSURE, factor: 9806.65),     # m of water column
      "inH2O" => UnitDef.new(symbol: "inH2O", dimension: PRESSURE, factor: 249.0889),    # inch of water
      "ftH2O" => UnitDef.new(symbol: "ftH2O", dimension: PRESSURE, factor: 2989.0669),   # foot of water
      "pieze" => UnitDef.new(symbol: "pieze", dimension: PRESSURE, factor: 1000.0),      # = 1 kPa exact (CGS-MTS)

      # Textile / fiber gauges
      "denier"       => UnitDef.new(symbol: "denier",       dimension: Dimension.custom("linear_density"), factor: Rational(1, 9_000_000)),  # g per 9000 m
      "tex"          => UnitDef.new(symbol: "tex",          dimension: Dimension.custom("linear_density"), factor: 1e-6),                    # g/km
      "decitex"      => UnitDef.new(symbol: "decitex",      dimension: Dimension.custom("linear_density"), factor: 1e-7),                    # tex/10
      "french_gauge" => UnitDef.new(symbol: "french_gauge", dimension: LENGTH,                              factor: Rational(1, 3_000)),     # 1 Fr = 1/3 mm

      # Joke / colorful units
      "mickey"           => UnitDef.new(symbol: "mickey",           dimension: LENGTH, factor: 0.000127),  # 5 thou inch (Apple mouse)
      "sagan"            => UnitDef.new(symbol: "sagan",            dimension: DIMENSIONLESS, factor: 4_000_000_000),  # "billions and billions"
      "light_nanosecond" => UnitDef.new(symbol: "light_nanosecond", dimension: LENGTH, factor: 0.299792458),  # ≈ 1 ft (Grace Hopper)
      "banana_for_scale" => UnitDef.new(symbol: "banana_for_scale", dimension: LENGTH, factor: 0.18),         # ~ avg banana

      # Frequently needed engineering quantities. These are registered names
      # (not parser-only examples), so they are discoverable and work in both
      # REPL implementations without users having to reconstruct the algebra.
      "kg/m³"       => UnitDef.new(symbol: "kg/m³",       dimension: Dimension.new(-3, 1, 0, 0, 0, 0, 0, 0), factor: 1),
      "m³/s"        => UnitDef.new(symbol: "m³/s",        dimension: Dimension.new(3, 0, -1, 0, 0, 0, 0, 0), factor: 1),
      "L/min"       => UnitDef.new(symbol: "L/min",       dimension: Dimension.new(3, 0, -1, 0, 0, 0, 0, 0), factor: Rational(1, 60_000)),
      "kg/s"        => UnitDef.new(symbol: "kg/s",        dimension: Dimension.new(0, 1, -1, 0, 0, 0, 0, 0), factor: 1),
      "J/K"         => UnitDef.new(symbol: "J/K",         dimension: ENERGY / TEMPERATURE, factor: 1),
      "heat_capacity" => UnitDef.new(symbol: "heat_capacity", dimension: HEAT_CAPACITY_KIND, factor: 1),
      "entropy"       => UnitDef.new(symbol: "entropy",       dimension: ENTROPY_KIND, factor: 1),
      "J/kg/K"      => UnitDef.new(symbol: "J/kg/K",      dimension: ENERGY / MASS / TEMPERATURE, factor: 1),
      "W/m/K"       => UnitDef.new(symbol: "W/m/K",       dimension: POWER / LENGTH / TEMPERATURE, factor: 1),
      "W/m²"        => UnitDef.new(symbol: "W/m²",        dimension: POWER / AREA, factor: 1),
      "V/m"         => UnitDef.new(symbol: "V/m",         dimension: VOLTAGE / LENGTH, factor: 1),
      "A/m²"        => UnitDef.new(symbol: "A/m²",        dimension: CURRENT / AREA, factor: 1),
      "Ω·m"         => UnitDef.new(symbol: "Ω·m",         dimension: RESISTANCE * LENGTH, factor: 1),
      "S/m"         => UnitDef.new(symbol: "S/m",         dimension: CONDUCTANCE / LENGTH, factor: 1),
      "C/m³"        => UnitDef.new(symbol: "C/m³",        dimension: CHARGE / VOLUME, factor: 1),
      "N/m"         => UnitDef.new(symbol: "N/m",         dimension: FORCE / LENGTH, factor: 1),
      "kg/m"        => UnitDef.new(symbol: "kg/m",        dimension: MASS / LENGTH, factor: 1),
      "kg/m²"       => UnitDef.new(symbol: "kg/m²",       dimension: MASS / AREA, factor: 1),
      "J/m³"        => UnitDef.new(symbol: "J/m³",        dimension: ENERGY / VOLUME, factor: 1),
      "J/kg"        => UnitDef.new(symbol: "J/kg",        dimension: ENERGY / MASS, factor: 1),
      "specific_energy" => UnitDef.new(symbol: "specific_energy", dimension: SPECIFIC_ENERGY_KIND, factor: 1),
      "mol/mol"     => UnitDef.new(symbol: "mol/mol",     dimension: RATIO, factor: 1),
      "kat/m³"      => UnitDef.new(symbol: "kat/m³",      dimension: CATALYTIC_ACTIVITY / VOLUME, factor: 1),
      "cd/m²"       => UnitDef.new(symbol: "cd/m²",       dimension: LUMINANCE, factor: 1),
      "lx·s"        => UnitDef.new(symbol: "lx·s",        dimension: ILLUMINANCE_KIND * TIME, factor: 1),
      "lm·s"        => UnitDef.new(symbol: "lm·s",        dimension: LUMINOUS_FLUX * TIME, factor: 1),
      "rad/s"       => UnitDef.new(symbol: "rad/s",       dimension: ANGLE / TIME, factor: 1),
      "rad/s²"      => UnitDef.new(symbol: "rad/s²",      dimension: ANGLE / (TIME * TIME), factor: 1),
      "m/s³"        => UnitDef.new(symbol: "m/s³",        dimension: Dimension.new(1, 0, -3, 0, 0, 0, 0, 0), factor: 1),
      "kg·m/s"      => UnitDef.new(symbol: "kg·m/s",      dimension: MOMENTUM, factor: 1),
      "N·s"         => UnitDef.new(symbol: "N·s",         dimension: IMPULSE, factor: 1),
      "N·m"         => UnitDef.new(symbol: "N·m",         dimension: TORQUE, factor: 1),

      # Computing and efficiency quantities. Counts remain semantic tags so,
      # for example, joules/token cannot accidentally convert to joules/op.
      "bit/s/Hz"    => UnitDef.new(symbol: "bit/s/Hz",   dimension: INFORMATION * Dimension.custom("spectral_efficiency"), factor: Rational(1, 8)),
      "J/op"        => UnitDef.new(symbol: "J/op",       dimension: ENERGY / Dimension.custom("op"), factor: 1),
      "J/tok"       => UnitDef.new(symbol: "J/tok",      dimension: ENERGY / Dimension.custom("token"), factor: 1),
      "B/flop"      => UnitDef.new(symbol: "B/flop",     dimension: INFORMATION / Dimension.custom("flop"), factor: 1),

      # Modern contextual and sustainability quantities. Context-dependent
      # units use explicit names instead of pretending there is one universal
      # conversion (for example, Mach depends on the medium and temperature).
      "kgCO₂e"       => UnitDef.new(symbol: "kgCO₂e",       dimension: MASS * Dimension.custom("co2e"), factor: 1),
      "gCO₂e"        => UnitDef.new(symbol: "gCO₂e",        dimension: MASS * Dimension.custom("co2e"), factor: Rational(1, 1000)),
      "gCO₂e/kWh"    => UnitDef.new(symbol: "gCO₂e/kWh",    dimension: (MASS / ENERGY) * Dimension.custom("co2e"), factor: Rational(1, 3_600_000_000)),
      "gCO₂e/pkm"    => UnitDef.new(symbol: "gCO₂e/pkm",    dimension: (MASS / LENGTH) * Dimension.custom("transport_co2e"), factor: Rational(1, 1_000_000)),
      "px"           => UnitDef.new(symbol: "px",           dimension: LENGTH, factor: Rational(127, 480_000)),
      "dpi"          => UnitDef.new(symbol: "dpi",          dimension: INVERSE_LENGTH, factor: Rational(5000, 127)),
      "dppx"         => UnitDef.new(symbol: "dppx",         dimension: INVERSE_LENGTH, factor: Rational(480_000, 127)),
      "rem_css"      => UnitDef.new(symbol: "rem_css",      dimension: Dimension.custom("css_root_font_size"), factor: 1),
      "vw"           => UnitDef.new(symbol: "vw",           dimension: Dimension.custom("viewport_width_percent"), factor: 1),
      "vh"           => UnitDef.new(symbol: "vh",           dimension: Dimension.custom("viewport_height_percent"), factor: 1),
      "person_hour"  => UnitDef.new(symbol: "person_hour",  dimension: TIME * Dimension.custom("person"), factor: 3600),
      "QALY"         => UnitDef.new(symbol: "QALY",         dimension: TIME * Dimension.custom("quality_adjusted_life"), factor: Rational(31_556_952)),
      "story_point"  => UnitDef.new(symbol: "story_point",  dimension: Dimension.custom("story_point"), factor: 1),
      "mg/dL_glucose"   => UnitDef.new(symbol: "mg/dL_glucose",   dimension: Dimension.custom("glucose_concentration"), factor: Rational(22_203, 400_000)),
      "mmol/L_glucose"  => UnitDef.new(symbol: "mmol/L_glucose",  dimension: Dimension.custom("glucose_concentration"), factor: 1),
      "mach_air_20C" => UnitDef.new(symbol: "mach_air_20C", dimension: VELOCITY, factor: 343),

      # Ordinal / discrete scales (each its own custom dim — incompatible with anything else)
      "bortle"          => UnitDef.new(symbol: "bortle",          dimension: Dimension.custom("bortle"),         factor: 1),  # 1-9 sky darkness
      "beaufort"        => UnitDef.new(symbol: "beaufort",        dimension: Dimension.custom("beaufort"),       factor: 1),  # 0-12 wind force
      "saffir_simpson"  => UnitDef.new(symbol: "saffir_simpson",  dimension: Dimension.custom("saffir_simpson"), factor: 1),  # 1-5 hurricane
      "fujita"          => UnitDef.new(symbol: "fujita",          dimension: Dimension.custom("fujita"),         factor: 1),  # F0-F5 tornado
      "EF"              => UnitDef.new(symbol: "EF",              dimension: Dimension.custom("ef"),             factor: 1),  # EF0-EF5 enhanced Fujita
      "richter"         => UnitDef.new(symbol: "richter",         dimension: Dimension.custom("magnitude"),      factor: 1),  # continuous earthquake (log)
      "moment_magnitude"=> UnitDef.new(symbol: "moment_magnitude",dimension: Dimension.custom("magnitude"),      factor: 1),  # Mw, modern replacement
      "apgar"           => UnitDef.new(symbol: "apgar",           dimension: Dimension.custom("apgar"),          factor: 1),  # 0-10 newborn
      "RBE"             => UnitDef.new(symbol: "RBE",             dimension: Dimension.custom("rbe"),            factor: 1),  # radiation biological effectiveness
      "hounsfield_unit" => UnitDef.new(symbol: "hounsfield_unit", dimension: Dimension.custom("hounsfield"),     factor: 1),  # CT scan density (continuous)
    }.freeze

    UNIT_METADATA_PATH = File.expand_path("../../../../../data/unit_metadata.tsv", __dir__)
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

    UNIT_ALIASES = {
      # SI base
      "meter" => "m", "meters" => "m",
      "kilogram" => "kg", "kilograms" => "kg",
      "gram" => "g", "grams" => "g",
      "second" => "s", "seconds" => "s",
      "ampere" => "A", "amperes" => "A",
      "kelvin" => "K",
      "mole" => "mol", "moles" => "mol",
      "candela" => "cd", "candelas" => "cd",

      # Derived SI
      "newton" => "N", "newtons" => "N",
      "joule" => "J", "joules" => "J",
      "watt" => "W", "watts" => "W",
      "pascal" => "Pa", "pascals" => "Pa",
      "hertz" => "Hz",
      "volt" => "V", "volts" => "V",

      # Imperial length
      "inch" => "in", "inches" => "in",
      "foot" => "ft", "feet" => "ft",
      "yard" => "yd", "yards" => "yd",
      "mile" => "mi", "miles" => "mi",
      "furlong" => "fur", "furlongs" => "fur",
      "rod" => "rod", "rods" => "rod",
      "chain" => "ch", "chains" => "ch",
      "smoots" => "smoot",
      "hands" => "hand",
      "leagues" => "league",
      "rack unit" => "RU", "rack units" => "RU",
      "angstrom" => "Å", "angstroms" => "Å", "ångström" => "Å",
      "lightyear" => "ly", "lightyears" => "ly", "light year" => "ly", "light years" => "ly",
      "light second" => "lightsecond", "light seconds" => "lightsecond", "lightseconds" => "lightsecond",
      "light minute" => "lightminute", "light minutes" => "lightminute", "lightminutes" => "lightminute",
      "light hour" => "lighthour", "light hours" => "lighthour", "lighthours" => "lighthour",
      "Planck length" => "ℓₚ", "planck length" => "ℓₚ",

      # Astronomical length (light year aliases live with the other light-time aliases above)
      "parsec" => "pc", "parsecs" => "pc",
      "nautical mile" => "nmi", "nautical miles" => "nmi",
      "astronomical unit" => "au", "astronomical units" => "au",

      # Mass
      "pound" => "lb", "pounds" => "lb", "lbs" => "lb",
      "ounce" => "oz", "ounces" => "oz",
      "tonne" => "t", "tonnes" => "t",
      "metric ton" => "t", "metric tons" => "t",
      "grain" => "gr", "grains" => "gr",
      "drachm" => "dr", "drams" => "dr",
      "stone" => "st", "stones" => "st",
      "quarter" => "qr", "quarters" => "qr",
      "short ton" => "tn", "short tons" => "tn",
      "long ton" => "LT", "long tons" => "LT",
      "ton" => "tn", "tons" => "tn",  # default: US short ton
      "grave" => "kg",
      "dalton" => "Da", "daltons" => "Da",
      "scruple" => "℈", "scruples" => "℈",
      "slugs" => "slug",

      # Mass extras
      "troy ounce" => "troyounce", "troy ounces" => "troyounce", "ozt" => "troyounce",
      "pennyweights" => "pennyweight", "dwt" => "pennyweight",
      "carats" => "carat", "ct" => "carat",
      "quintals" => "quintal",

      # Time
      "minute" => "min", "minutes" => "min",
      "hour" => "h", "hours" => "h",
      "day" => "d", "days" => "d",
      "wk" => "week", "weeks" => "week",
      "mo" => "month", "months" => "month",
      "yr" => "year", "years" => "year",
      "decades" => "decade",
      "millennia" => "millennium", "millenniums" => "millennium",
      "fortnights" => "fortnight",
      "centuries" => "century",
      "shakes" => "shake",
      "sidereal year" => "siderealyear", "sidereal years" => "siderealyear",
      "tropical year" => "tropicalyear", "tropical years" => "tropicalyear",
      "julian year" => "julianyear", "julian years" => "julianyear",
      "sidereal day" => "siderealday", "sidereal days" => "siderealday",
      "lunar month" => "lunarmonth", "lunar months" => "lunarmonth",
      "synodic month" => "lunarmonth", "synodic months" => "lunarmonth",
      "lustra" => "lustrum", "lustrums" => "lustrum",
      "dog year" => "dogyear", "dog years" => "dogyear",

      # Area
      "acre" => "ac", "acres" => "ac",
      "hectare" => "ha", "hectares" => "ha",
      "barns" => "barn",
      "sq ft" => "sqft", "square foot" => "sqft", "square feet" => "sqft",

      # Volume
      "l" => "L",
      "litre" => "L", "litres" => "L", "liter" => "L", "liters" => "L",
      "gallon" => "gal", "gallons" => "gal",
      "quart" => "qt", "quarts" => "qt",
      "pint" => "pt", "pints" => "pt",
      "cups" => "cup",
      "gills" => "gill",
      "fluid ounce" => "floz", "fluid ounces" => "floz", "fl oz" => "floz",
      "fluid dram" => "fldr", "fluid drams" => "fldr", "fl dr" => "fldr",
      "imperial gallon" => "impgal", "imperial gallons" => "impgal", "imp gal" => "impgal",
      "bushels" => "bushel", "bu" => "bushel",
      "pecks" => "peck", "pk" => "peck",

      # Wine bottle plurals & alternative names
      "magnums" => "magnum",
      "jeroboams" => "jeroboam", "rehoboam" => "jeroboam",  # rehoboam = 4.5L typically; close enough for sparkling
      "methuselahs" => "methuselah", "imperial bottle" => "methuselah",
      "nebuchadnezzars" => "nebuchadnezzar",
      "splits" => "split", "piccolo" => "split",
      "bottles" => "bottle",
      "melchizedeks" => "melchizedek",

      # Peanut butter & jelly — for the sandwich easter egg
      "pb" => "peanutbutter", "peanut butter" => "peanutbutter",
      "j" => "jelly", "jam" => "jelly", "grape jelly" => "jelly",

      # Cooking
      "tablespoon" => "tbsp", "tablespoons" => "tbsp",
      "teaspoon" => "tsp", "teaspoons" => "tsp",
      "drops" => "drop",
      "dashes" => "dash",
      "pinches" => "pinch",
      "smidgens" => "smidgen",
      "jiggers" => "jigger",

      # Cask plurals
      "firkins" => "firkin", "rundlets" => "rundlet", "tierces" => "tierce",
      "hogsheads" => "hogshead", "puncheons" => "puncheon", "pipes" => "pipe",
      "tuns" => "tun", "kilderkins" => "kilderkin",
      "butt" => "pipe", "tertian" => "puncheon",

      # Pressure
      "atmosphere" => "atm", "atmospheres" => "atm",
      "barye" => "Ba",
      "torrs" => "torr",

      # Force
      "pound-force" => "lbf", "pound force" => "lbf",
      "kilogram-force" => "kgf", "kilogram force" => "kgf",

      # Energy
      "calorie" => "cal", "calories" => "cal",
      "kilocalorie" => "kcal", "kilocalories" => "kcal",
      "kilowatt-hour" => "kWh", "kilowatt hour" => "kWh", "kilowatt-hours" => "kWh", "kilowatt hours" => "kWh",
      "foot-pound" => "ftlbf", "foot pound" => "ftlbf", "foot-pounds" => "ftlbf", "foot pounds" => "ftlbf",
      "therms" => "therm",
      "electronvolt" => "eV", "electronvolts" => "eV",
      "dyne" => "dyn", "dynes" => "dyn",

      # Power
      "horsepower" => "hp",

      # Electromagnetism
      "coulomb" => "C", "coulombs" => "C",
      "ohm" => "Ω", "ohms" => "Ω",
      "farad" => "F", "farads" => "F",
      "henry" => "H", "henrys" => "H", "henries" => "H",
      "siemens" => "S", "mho" => "S", "℧" => "S",
      "weber" => "Wb", "webers" => "Wb",
      "tesla" => "T", "teslas" => "T",
      "gauss" => "Ga",

      # Radioactivity / Dosimetry
      "becquerel" => "Bq", "becquerels" => "Bq",
      "curie" => "Ci", "curies" => "Ci",
      "gray" => "Gy", "grays" => "Gy",
      "sievert" => "Sv", "sieverts" => "Sv",
      "rems" => "rem",
      "maxwell" => "Mx", "maxwells" => "Mx",
      "rotations per minute" => "rpm", "revolutions per minute" => "rpm",
      "beats per minute" => "bpm", "BPM" => "bpm",
      "frames per second" => "fps", "FPS" => "fps",

      # Compositional-numerator aliases
      "rev" => "revolution", "revs" => "revolution", "revolutions" => "revolution",
      "rot" => "rotation", "rotations" => "rotation",
      "decays" => "decay",
      "cyc" => "cycle",
      "Planck mass" => "mₚₗ", "planck mass" => "mₚₗ",
      "Planck time" => "tₚ", "planck time" => "tₚ",

      # Angle
      "°" => "deg",
      "degree" => "deg", "degrees" => "deg",
      "radian" => "rad", "radians" => "rad",
      "steradian" => "sr", "steradians" => "sr",
      "gradian" => "gon", "gradians" => "gon", "grad" => "gon",
      "turns" => "turn",
      "mils" => "mil",
      "brads" => "brad",

      # Photometry
      "lumen" => "lm", "lumens" => "lm",
      "lux" => "lx",

      # Catalytic activity
      "katal" => "kat", "katals" => "kat",

      # Temperature scales
      "celsius" => "°C", "fahrenheit" => "°F",
      "delta kelvin" => "ΔK", "kelvin difference" => "ΔK",
      "delta celsius" => "Δ°C", "celsius difference" => "Δ°C",
      "delta fahrenheit" => "Δ°F", "fahrenheit difference" => "Δ°F",
      "delta rankine" => "Δ°R", "rankine difference" => "Δ°R",
      "℃" => "°C", "℉" => "°F",
      "°Ra" => "°R", "rankine" => "°R",
      "°Re" => "°Ré", "°r" => "°Ré", "réaumur" => "°Ré", "reaumur" => "°Ré",
      "rømer" => "°Rø", "romer" => "°Rø",
      "delisle" => "°De",
      "wedgwood" => "°W",

      # Information
      "byte" => "B", "bytes" => "B",
      "bit" => "b", "bits" => "b",
      "octet" => "o", "octets" => "o",
      "nibbles" => "nibble",
      "petabyte" => "PB", "petabytes" => "PB",

      # Nautical & Speed
      "fathoms" => "fathom",
      "cables" => "cable",
      "knots" => "knot", "kn" => "knot", "kt" => "knot",
      "miles per hour" => "mph", "mile per hour" => "mph",

      # Viscosity
      "poise" => "P",
      "centipoise" => "cP",
      "stokes" => "St",
      "centistokes" => "cSt",

      # Astronomy
      "solar mass" => "solarmass", "M☉" => "solarmass",
      "earth mass" => "earthmass", "M⊕" => "earthmass",
      "jupiter mass" => "jupitermass", "M♃" => "jupitermass",
      "moon mass" => "moonmass", "M☽" => "moonmass",
      "solar radius" => "solarradius", "R☉" => "solarradius",
      "earth radius" => "earthradius", "R⊕" => "earthradius",

      # Typography
      "points" => "point",
      "picas" => "pica",

      # Exotic units
      "㍳" => "au",
      "stère" => "stere", "stères" => "stere",
      "cords" => "cord",
      "barrels" => "barrel",
      "millihelens" => "millihelen",
      "warhols" => "warhol",
      "kilowarhols" => "kilowarhol",
      "altuves" => "altuve",
      "rutherford" => "rd", "rutherfords" => "rd",
      "stilb" => "sb", "stilbs" => "sb",
      "lambert" => "La", "lamberts" => "La",
      "apostilb" => "asb", "apostilbs" => "asb",
      "skot" => "sk", "skots" => "sk",
      "nits" => "nit",
      "foot-lambert" => "fL",

      # Exotic
      "beard-second" => "beard second", "beard seconds" => "beard second", "beard-seconds" => "beard second",
      "barn-megaparsec" => "barn megaparsec", "barn-megaparsecs" => "barn megaparsec",
      "bananas" => "banana",

      # Typographic
      "quad" => "em",

      # Unconvertible time plurals
      "beats" => "beat", "cycles" => "cycle", "frames" => "frame",
      "instants" => "instant", "jiffies" => "jiffy", "moments" => "moment",
      "samples" => "sample", "ticks" => "tick",

      # Compute counts
      "flops_count" => "flop", "ops" => "op", "macs" => "mac",
      "instructions" => "instruction",
      "token" => "tok", "tokens" => "tok",
      "transfers" => "transfer",
      "queries" => "query", "requests" => "request",
      "transaction" => "txn", "transactions" => "txn",
      "packets" => "packet",
      "ios" => "io", "io_op" => "io", "io_ops" => "io",

      # Concentration spelled out
      "parts per million" => "ppm", "parts-per-million" => "ppm",
      "parts per billion" => "ppb", "parts-per-billion" => "ppb",
      "parts per trillion" => "ppt", "parts-per-trillion" => "ppt",
      "parts per hundred million" => "pphm",

      # Info-theory aliases
      "nats" => "nat",
      "hartley" => "ban", "hartleys" => "ban", "dit" => "ban", "dits" => "ban",
      "decibans" => "deciban",

      # Acoustics
      "sones" => "sone", "phons" => "phon",

      # Astronomy
      "jansky" => "Jy", "janskys" => "Jy", "janskies" => "Jy",
      "magnitude" => "mag", "magnitudes" => "mag",
      "apparent magnitude" => "mag",
      "absolute magnitude" => "Mag",
      "bolometric magnitude" => "M_bol", "Mbol" => "M_bol",

      # Particle physics
      "fbarn" => "femtobarn", "femtobarns" => "femtobarn",
      "abarn" => "attobarn", "attobarns" => "attobarn",
      "pbarn" => "picobarn", "picobarns" => "picobarn",
      "nbarn" => "nanobarn", "nanobarns" => "nanobarn",
      "inverse femtobarn" => "fb⁻¹", "inv_fb" => "fb⁻¹", "fbinv" => "fb⁻¹", "fb-1" => "fb⁻¹", "fb^-1" => "fb⁻¹",
      "inverse attobarn" => "ab⁻¹", "inv_ab" => "ab⁻¹", "abinv" => "ab⁻¹", "ab-1" => "ab⁻¹", "ab^-1" => "ab⁻¹",
      "inverse picobarn" => "pb⁻¹", "inv_pb" => "pb⁻¹", "pb-1" => "pb⁻¹", "pb^-1" => "pb⁻¹",
      "inverse nanobarn" => "nb⁻¹", "inv_nb" => "nb⁻¹", "nb-1" => "nb⁻¹", "nb^-1" => "nb⁻¹",

      # EM legacy
      "oersted" => "Oe", "oersteds" => "Oe",
      "gilbert" => "Gb", "gilberts" => "Gb",
      "debye" => "D", "debyes" => "D",
      "bohr magneton" => "μ_B", "bohr_magneton" => "μ_B", "muB" => "μ_B",

      # Risk
      "micromorts" => "micromort", "μmort" => "micromort",
      "microlives" => "microlife", "μlife" => "microlife",

      # Wavenumber
      "kaysers" => "kayser", "cm⁻¹" => "kayser", "cm-1" => "kayser", "cm^-1" => "kayser",
      "wavenumber" => "kayser",

      # Hardness
      "Mohs" => "mohs", "HV" => "vickers", "HRC" => "rockwell", "HB" => "brinell",

      # Counting groupings
      "dozens" => "dozen",
      "scores" => "score",
      "baker's dozen" => "bakers_dozen", "bakers dozen" => "bakers_dozen",
      "great gross" => "great_gross",
      "googols" => "googol", "googolplexes" => "googolplex",

      # Talmudic length
      "amah" => "cubit", "amot" => "cubit", "cubits" => "cubit",
      "zeret" => "span", "spans" => "span",
      "tefach" => "handbreadth", "tefachim" => "handbreadth", "handbreadths" => "handbreadth",
      "etzba" => "fingerbreadth", "etzbaot" => "fingerbreadth",
      "talmudic mil" => "biblical_mil", "talmudic_mil" => "biblical_mil",
      "sabbath day's journey" => "techum", "techum shabbat" => "techum",

      # Talmudic volume
      "omers" => "omer", "issaron" => "omer", "isaron" => "omer",
      "ephahs" => "ephah", "ephas" => "ephah",
      "hins" => "hin",
      "baths" => "bath",
      "seahs" => "seah", "seim" => "seah",
      "kors" => "kor", "korim" => "kor",
      "kabim" => "kab", "kabs" => "kab",

      # Talmudic mass
      "shekels" => "shekel", "shekalim" => "shekel",
      "mina" => "biblical_mina", "minas" => "biblical_mina", "maneh" => "biblical_mina",
      "biblical talent" => "biblical_talent", "kikar" => "biblical_talent",
      "talent" => "biblical_talent", "talents" => "biblical_talent",
      "gerahs" => "gerah",
      "bekas" => "beka", "bekah" => "beka",

      # Talmudic time
      "halakim" => "helek", "chelek" => "helek", "chelakim" => "helek",
      "regaim" => "rega",
      "onot" => "onah",
      "yovels" => "yovel", "jubilee" => "yovel", "jubilees" => "yovel",
      "shmitas" => "shmita", "sabbatical" => "shmita", "shmitta" => "shmita",

      # Standard gravity
      "g0" => "g₀", "standard gravity" => "g₀", "ɡ" => "g₀",

      # Fuel economy
      "MPG" => "mpg", "miles per gallon" => "mpg",
      "MPGe" => "mpge", "miles per gallon equivalent" => "mpge",
      "L per 100 km" => "L/100km", "liters per 100 km" => "L/100km", "l/100km" => "L/100km",

      # Stick of butter
      "sticks" => "stick", "stick of butter" => "stick", "sticks of butter" => "stick",

      # Tonne aliases spelled with "ton"
      "kilotons" => "kiloton", "megatons" => "megaton", "gigatons" => "gigaton",

      # Petroleum
      "petroleum barrel" => "oil_barrel", "petroleum_barrel" => "oil_barrel",
      "oil barrel" => "oil_barrel", "oil barrels" => "oil_barrel",
      "barrel of oil equivalent" => "BOE", "boe" => "BOE",
      "tonne of coal equivalent" => "TCE", "tce" => "TCE",

      # Sorites
      "heaps" => "heap",
      "holes" => "hole",

      # Japanese
      "shakus" => "shaku", "suns" => "sun",
      "jos" => "jo", "tsubos" => "tsubo", "tatamis" => "tatami",
      "kokus" => "koku", "gos" => "gō",
      "mommes" => "momme", "kanmes" => "kanme",
      # Note: Japanese "ri" registered as `ri`; existing "rems" plural `rems` → `rem`.

      # Chinese
      "chis" => "chi", "cuns" => "cun", "fens" => "fen",
      "zhangs" => "zhang",
      "chinese li" => "li_cn", "chinese_li" => "li_cn",
      "mus" => "mu", "jins" => "jin", "liangs" => "liang",
      "chinese dan" => "dan_cn", "chinese_dan" => "dan_cn",

      # Russian
      "versts" => "verst", "arshins" => "arshin", "sazhens" => "sazhen", "vershoks" => "vershok",
      "puds" => "pud",
      "russian funt" => "funt_ru", "russian_funt" => "funt_ru", "funt" => "funt_ru",
      "chetverts" => "chetvert",

      # French historical
      "pieds" => "pied", "pieds du roi" => "pied", "pied du roi" => "pied",
      "pouces" => "pouce",
      "toises" => "toise",
      "arpents" => "arpent",
      "lieues de poste" => "lieue_de_poste", "lieue de poste" => "lieue_de_poste",

      # Roman
      "pedes" => "pes", "passus" => "passus", "passuses" => "passus",
      "mille passuum" => "mille_passuum", "roman mile" => "mille_passuum",
      "iugera" => "iugerum", "jugerum" => "iugerum",
      "roman libra" => "libra_roma", "libra romana" => "libra_roma",
      "roman uncia" => "uncia_roma",
      "amphorae" => "amphora", "amphoras" => "amphora",

      # Egyptian
      "royal cubit" => "royal_cubit", "royal cubits" => "royal_cubit",
      "egyptian palm" => "egypt_palm", "egyptian palms" => "egypt_palm",
      "digits" => "digit",
      "khets" => "khet",
      "arouras" => "aroura", "arourae" => "aroura",

      # Indian
      "haths" => "hath",
      "gazes" => "gaz",
      "kos_indian" => "kos", "indian kos" => "kos",
      "tolas" => "tola",
      "seers" => "seer",
      "maunds" => "maund",

      # Atomic constants
      "Eh" => "hartree", "hartrees" => "hartree",
      "Ry" => "rydberg_unit", "rydbergs" => "rydberg_unit", "rydberg" => "rydberg_unit",
      "a_0" => "bohr_radius", "a0" => "bohr_radius",
      "compton wavelength" => "compton_e", "compton_wavelength" => "compton_e",
      "compton wavelength electron" => "compton_e",
      "compton wavelength proton" => "compton_p",
      "compton wavelength neutron" => "compton_n",
      "α" => "fine_structure", "alpha" => "fine_structure", "fine structure constant" => "fine_structure",

      # Particle masses
      "m_e" => "electron_mass", "electron mass" => "electron_mass",
      "m_p" => "proton_mass",   "proton mass"   => "proton_mass",
      "m_n" => "neutron_mass",  "neutron mass"  => "neutron_mass",
      "m_μ" => "muon_mass",     "muon mass"     => "muon_mass",

      # Power flavors
      "boiler horsepower"   => "boiler_horsepower",
      "electric horsepower" => "electric_horsepower",
      "water horsepower"    => "water_horsepower",
      "donkey power" => "donkeypower", "donkey-power" => "donkeypower",

      # International cooking
      "metric cup"      => "metric_cup",      "metric cups"      => "metric_cup",
      "metric tbsp"     => "metric_tbsp",     "metric tablespoon"=> "metric_tbsp",
      "metric tablespoons" => "metric_tbsp",
      "australian tbsp" => "australian_tbsp", "australian tablespoon" => "australian_tbsp",
      "australian tablespoons" => "australian_tbsp", "AU tbsp" => "australian_tbsp",
      "japanese cup"    => "japanese_cup",    "japanese cups" => "japanese_cup",
      "imperial pint"   => "imperial_pint",   "imperial pints" => "imperial_pint",

      # Storage primitives
      "crumbs" => "crumb",
      "dwords" => "dword", "DWORD" => "dword",
      "qwords" => "qword", "QWORD" => "qword",
      "paragraphs" => "paragraph",
      "sectors" => "sector",
      "pages" => "page",
      "blocks" => "block",
      "clusters" => "cluster",

      # Photography
      "stop" => "EV", "stops" => "EV", "ev" => "EV",
      "f-stop" => "f_stop", "f stop" => "f_stop", "fstop" => "f_stop", "f-stops" => "f_stop",
      "ISO" => "ISO_speed", "iso" => "ISO_speed", "ISO sensitivity" => "ISO_speed",

      # Pitch (cent_pitch is canonical; users normally type `cent` or `cents`)
      "cent" => "cent_pitch", "cents" => "cent_pitch",
      "semitones" => "semitone", "halfstep" => "semitone", "half step" => "semitone",
      "savarts" => "savart",
      "octaves" => "octave",

      # Money quanta
      "basis_points" => "basis_point", "basis point" => "basis_point", "basis points" => "basis_point",
      "bp_finance" => "basis_point",
      "tenth cent" => "tenth_cent", "mill_finance" => "tenth_cent",
      "pips" => "pip",

      # Old British / imperial
      "links" => "link_chain", "link" => "link_chain",
      "ropes" => "rope",
      "perches" => "perch",
      "barleycorns" => "barleycorn",
      "shaftments" => "shaftment",
      "english cubit" => "english_cubit", "english cubits" => "english_cubit",
      "cloth nail" => "nail_cloth",
      "cable length" => "cable_length", "cable lengths" => "cable_length",

      # Pressure water columns
      "meter of water" => "mH2O", "meters of water" => "mH2O", "m of water" => "mH2O", "m H2O" => "mH2O",
      "inch of water" => "inH2O", "inches of water" => "inH2O", "in of water" => "inH2O", "in H2O" => "inH2O",
      "foot of water" => "ftH2O", "feet of water" => "ftH2O", "ft of water" => "ftH2O", "ft H2O" => "ftH2O",

      # Textile
      "deniers" => "denier",
      "decitex" => "decitex",
      "french gauge" => "french_gauge", "Fr_catheter" => "french_gauge",

      # Joke
      "mickeys" => "mickey",
      "sagans" => "sagan", "billions and billions" => "sagan",
      "light nanosecond" => "light_nanosecond", "light-nanosecond" => "light_nanosecond",
      "bananas for scale" => "banana_for_scale", "banana for scale" => "banana_for_scale",

      # Ordinal scales
      "Bortle" => "bortle",
      "Beaufort" => "beaufort",
      "Saffir-Simpson" => "saffir_simpson", "saffir simpson" => "saffir_simpson", "SS_category" => "saffir_simpson",
      "fujita scale" => "fujita", "F-scale" => "fujita",
      "EF-scale" => "EF", "enhanced fujita" => "EF",
      "Richter" => "richter", "richter scale" => "richter",
      "Mw" => "moment_magnitude", "moment magnitude" => "moment_magnitude",
      "Apgar" => "apgar", "apgar score" => "apgar",
      "rbe" => "RBE", "relative biological effectiveness" => "RBE",
      "hounsfield" => "hounsfield_unit", "HU" => "hounsfield_unit",

      # Engineering quantity names
      "mass density" => "kg/m³", "kilograms per cubic meter" => "kg/m³",
      "volumetric flow" => "m³/s", "cubic meters per second" => "m³/s",
      "liters per minute" => "L/min", "litres per minute" => "L/min",
      "mass flow" => "kg/s", "kilograms per second" => "kg/s",
      "heat capacity" => "heat_capacity", "joules per kelvin" => "J/K",
      "specific heat capacity" => "J/kg/K", "J/(kg·K)" => "J/kg/K",
      "thermal conductivity" => "W/m/K", "W/(m·K)" => "W/m/K",
      "heat flux" => "W/m²", "watts per square meter" => "W/m²",
      "electric field" => "V/m", "volts per meter" => "V/m",
      "current density" => "A/m²", "amperes per square meter" => "A/m²",
      "resistivity" => "Ω·m", "ohm meter" => "Ω·m",
      "conductivity" => "S/m", "siemens per meter" => "S/m",
      "charge density" => "C/m³", "coulombs per cubic meter" => "C/m³",
      "surface tension" => "N/m", "newtons per meter" => "N/m",
      "linear density" => "kg/m", "areal density" => "kg/m²",
      "energy density" => "J/m³", "specific energy" => "specific_energy",
      "mole fraction" => "mol/mol",
      "catalytic activity concentration" => "kat/m³",
      "candela per square meter" => "cd/m²",
      "luminous exposure" => "lx·s", "luminous energy" => "lm·s",
      "angular velocity" => "rad/s", "angular acceleration" => "rad/s²",
      "jerk" => "m/s³", "momentum" => "kg·m/s", "impulse" => "N·s", "torque" => "N·m",

      # Computing, sustainability, UI, planning, and health aliases
      "spectral efficiency" => "bit/s/Hz", "bits per second per hertz" => "bit/s/Hz", "bit/(s·Hz)" => "bit/s/Hz",
      "joules per operation" => "J/op", "joules per token" => "J/tok", "bytes per flop" => "B/flop",
      "kg CO2e" => "kgCO₂e", "kilograms CO2e" => "kgCO₂e",
      "g CO2e" => "gCO₂e", "grams CO2e" => "gCO₂e",
      "grid carbon intensity" => "gCO₂e/kWh", "transport carbon intensity" => "gCO₂e/pkm",
      "pixel" => "px", "pixels" => "px", "dots per inch" => "dpi", "dots per pixel" => "dppx",
      "css rem" => "rem_css", "viewport width" => "vw", "viewport height" => "vh",
      "person hour" => "person_hour", "person hours" => "person_hour",
      "quality-adjusted life year" => "QALY", "quality adjusted life year" => "QALY", "QALYs" => "QALY",
      "story point" => "story_point", "story points" => "story_point",
      "mg/dL glucose" => "mg/dL_glucose", "mmol/L glucose" => "mmol/L_glucose",
      "Mach at 20 C" => "mach_air_20C", "Mach in air at 20 C" => "mach_air_20C",

    }.freeze

    # SI-prefixable: units that opt in via UnitDef#prefixable. Backwards-compatible
    # global Set, derived from per-unit fields. Some entries (pc, fortnight, century)
    # opted in for fun rather than convention; they're declared explicitly below.
    SI_PREFIXABLE_OVERRIDES = %w[
      m g s A K mol cd
      N J W Pa Hz V C Ω F H S Wb T lm lx
      Bq Gy Sv kat L l eV Da t
      b B bps Bps
      pc fortnight century
    ].freeze

    PREFIXABLE = Set.new(
      UNIT_TABLE.select { |_, d| d.respond_to?(:si_prefixable?) && d.si_prefixable? }.keys +
      SI_PREFIXABLE_OVERRIDES.select { |k| UNIT_TABLE.key?(k) }
    ).freeze

    # Units whose symbols conflict with or should not take metric prefixes
    NO_PREFIX = (Set.new(UNIT_TABLE.keys) - PREFIXABLE).freeze

    # IEC binary prefixes for information units
    BINARY_PREFIX_TABLE = {
      "Ki" => 1024, "Mi" => 1024**2, "Gi" => 1024**3,
      "Ti" => 1024**4, "Pi" => 1024**5, "Ei" => 1024**6,
    }.freeze

    BINARY_PREFIXABLE = Set.new(
      UNIT_TABLE.select { |_, d| d.respond_to?(:binary_prefixable?) && d.binary_prefixable? }.keys +
      %w[b B].select { |k| UNIT_TABLE.key?(k) }
    ).freeze

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
    COMPOUND_DEFS = {
      # Frequency-shaped (X per time) — distinguished by the numerator tag.
      "Hz"   => [1, "cycle/s"],
      "rpm"  => [1, "revolution/min"],
      "bpm"  => [1, "beat/min"],
      "fps"  => [1, "frame/s"],
      "Bq"   => [1, "decay/s"],
      "Ci"   => [3.7e10, "decay/s"],
      "rd"   => [1e6, "decay/s"],

      # Data rate
      "bps"  => [1, "b/s"],
      "Bps"  => [1, "B/s"],
      "baud" => [1, "b/s"],

      # Velocity
      "mph"  => [1, "mi/h"],
      "kph"  => [1, "km/h"],
      "knot" => [1, "nmi/h"],

      # FLOPS family — floating-point operations per second
      "flops"  => [1, "flop/s"],   "FLOPS"  => [1, "flop/s"],
      "kflops" => [1e3, "flop/s"],  "kFLOPS" => [1e3, "flop/s"],
      "Mflops" => [1e6, "flop/s"],  "MFLOPS" => [1e6, "flop/s"],
      "Gflops" => [1e9, "flop/s"],  "GFLOPS" => [1e9, "flop/s"],
      "Tflops" => [1e12, "flop/s"], "TFLOPS" => [1e12, "flop/s"],
      "Pflops" => [1e15, "flop/s"], "PFLOPS" => [1e15, "flop/s"],
      "Eflops" => [1e18, "flop/s"], "EFLOPS" => [1e18, "flop/s"],
      "Zflops" => [1e21, "flop/s"], "ZFLOPS" => [1e21, "flop/s"],
      "Yflops" => [1e24, "flop/s"], "YFLOPS" => [1e24, "flop/s"],

      # TOPS — integer-ops/sec for AI accelerators
      "ops_per_s" => [1, "op/s"],
      "KOPS" => [1e3, "op/s"],
      "MOPS" => [1e6, "op/s"],
      "GOPS" => [1e9, "op/s"],
      "TOPS" => [1e12, "op/s"],
      "POPS" => [1e15, "op/s"],
      "EOPS" => [1e18, "op/s"],

      # MIPS — million instructions per second (also DMIPS = Dhrystone-MIPS, identical scaling)
      "MIPS"   => [1e6, "instruction/s"],
      "GIPS"   => [1e9, "instruction/s"],
      "DMIPS"  => [1e6, "instruction/s"],

      # MAC/s — multiply-accumulate rate (DSP and ML kernels)
      "MAC/s"  => [1, "mac/s"],
      "MMAC/s" => [1e6, "mac/s"],
      "GMAC/s" => [1e9, "mac/s"],
      "TMAC/s" => [1e12, "mac/s"],

      # Tokens per second (LLM throughput)
      "tok/s"  => [1, "tok/s"],
      "ktok/s" => [1e3, "tok/s"],
      "Mtok/s" => [1e6, "tok/s"],
      "Gtok/s" => [1e9, "tok/s"],

      # Memory bus transfer rates
      "T/s"  => [1, "transfer/s"],
      "MT/s" => [1e6, "transfer/s"],
      "GT/s" => [1e9, "transfer/s"],
      "TT/s" => [1e12, "transfer/s"],

      # Network rates
      "qps" => [1, "query/s"],   "QPS" => [1, "query/s"],
      "rps" => [1, "request/s"], "RPS" => [1, "request/s"],
      "tps" => [1, "txn/s"],     "TPS" => [1, "txn/s"],
      "pps" => [1, "packet/s"],  "PPS" => [1, "packet/s"],

      # Storage I/O
      "iops" => [1, "io/s"], "IOPS" => [1, "io/s"],

      # Concentration: molarity / molality (compound but commonly named)
      "molar"   => [1, "mol/L"],
      "molal"   => [1, "mol/kg"],
    }.freeze

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
                      year_defined: nil, defining_source: nil, prefixable: :none)
      raise ArgumentError, "unit '#{name}' already registered" if UNIT_TABLE.key?(name)
      raise ArgumentError, "name '#{name}' is an existing alias" if UNIT_ALIASES.key?(name)

      def_obj = UnitDef.new(symbol: name, dimension: dimension,
                            factor: factor, offset: offset,
                            description: description, measured: measured,
                            year_defined: year_defined, defining_source: defining_source,
                            prefixable: prefixable)
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
    PLURALIZABLE = Set.new(%w[
      revolution rotation decay cycle beat frame
      instant jiffy moment sample tick
      bottle magnum jeroboam methuselah nebuchadnezzar melchizedek split
      league fortnight lustrum dogyear lunarmonth
      hand smoot altuve
      peanutbutter jelly
    ]).freeze

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
    SUBSTANCE_DENSITY = {
      # Liquids
      "water" => 997, "seawater" => 1025, "milk" => 1030, "cream" => 1010,
      "honey" => 1420, "maple syrup" => 1370, "molasses" => 1400,
      "olive oil" => 920, "vegetable oil" => 920, "coconut oil" => 925, "canola oil" => 915,
      "gasoline" => 750, "diesel" => 832, "kerosene" => 804,
      "ethanol" => 789, "methanol" => 791, "acetone" => 784,
      "wine" => 990, "beer" => 1010, "blood" => 1060, "crude oil" => 870,
      "vinegar" => 1006, "soy sauce" => 1190,
      "liquid hydrogen" => 71, "liquid nitrogen" => 808, "liquid helium" => 125,
      "liquid oxygen" => 1141, "glycerin" => 1261, "turpentine" => 870,
      "lava" => 2700, "peanut butter" => 1090,

      # Metals
      "tungsten" => 19_300, "lead" => 11_340, "mercury" => 13_534,
      "gold" => 19_320, "osmium" => 22_590, "iron" => 7874, "steel" => 7850,
      "copper" => 8960, "aluminum" => 2700, "silver" => 10_490,
      "platinum" => 21_450, "titanium" => 4507, "uranium" => 19_050,
      "brass" => 8500, "bronze" => 8800, "zinc" => 7130, "tin" => 7265,
      "nickel" => 8908, "cobalt" => 8900, "chromium" => 7190,
      "lithium" => 534, "magnesium" => 1738, "sodium" => 971,
      "plutonium" => 19_840, "iridium" => 22_560,

      # Food/cooking (bulk densities)
      "flour" => 593, "sugar" => 845, "salt" => 1217, "rice" => 750,
      "jasmine rice" => 780, "basmati rice" => 760, "wild rice" => 620,
      "butter" => 911, "chocolate chips" => 720,
      "popcorn" => 35, "buttered popcorn" => 40,
      "ribeye" => 1050, "caviar" => 1050, "beef tallow" => 900, "bodyfat" => 900,
      "nerds" => 1500, "everlasting gobstoppers" => 1400, "skittles" => 1200,

      # Other solids
      "concrete" => 2300, "ice" => 917, "sand" => 1600, "glass" => 2500,
      "diamond" => 3510, "granite" => 2700, "marble" => 2710,
      "cork" => 120, "balsa" => 160, "oak" => 750, "pine" => 500,
      "rubber" => 1100, "bone" => 1900, "chalk" => 2350, "clay" => 1750,
      "coal" => 1400, "charcoal" => 250, "styrofoam" => 50, "paper" => 700,
      "cardboard" => 689, "aerogel" => 2,

      # Gases (at STP)
      "air" => Rational(1225, 1000), "helium" => Rational(1786, 10_000),
      "hydrogen" => Rational(899, 10_000), "nitrogen" => Rational(1251, 1000),
      "oxygen" => Rational(1429, 1000), "carbon dioxide" => Rational(1977, 1000),
      "argon" => Rational(1784, 1000), "neon" => Rational(9, 10),
      "propane" => Rational(1882, 1000),

      # Cooking extras
      "brake fluid" => 1050, "jam" => 1330, "ice cream" => 550,
      "ketchup" => 1100, "mustard" => 1050,
      "mayo" => 910, "mayonnaise" => 910,

      # Exotic
      "neutron star" => 400_000_000_000_000_000,
      "antimatter" => 1000,
      "white dwarf" => 1_000_000_000,
      "sun" => 1410,
      "steam" => Rational(598, 1000),
      "black hole" => 4e17.to_i,
      "golf balls" => 1130,
      "nothing" => 0,
      "vibranium" => 3990,
    }.freeze

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

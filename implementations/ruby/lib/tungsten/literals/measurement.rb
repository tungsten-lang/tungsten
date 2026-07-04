# frozen_string_literal: true

require "bigdecimal"

module Tungsten
  # A scalar measurement with Gaussian uncertainty: `5.0 ± 0.1`.
  #
  # Two surface syntaxes:
  #   `5.0 ± 0.1`        — explicit, two operands
  #   `2.1232442(2)`     — concise; (N) means ±N in the last given digit,
  #                        so this is 2.1232442 ± 0.0000002.
  #
  # Arithmetic propagates uncertainty by the standard rules:
  #   addition / subtraction: σ_z = √(σ_x² + σ_y²)
  #   multiplication / division: σ_z/|z| = √((σ_x/x)² + (σ_y/y)²)
  #   negation: σ unchanged
  #   power x^n: σ_z/|z| = |n| · σ_x/|x|
  #
  # These assume independent, Gaussian-distributed errors. For correlated or
  # non-Gaussian errors, use a full Monte-Carlo library.
  class Measurement
    include Comparable

    attr_reader :value, :uncertainty

    def initialize(value, uncertainty)
      @value = value
      @uncertainty = uncertainty.to_f.abs
    end

    # Concise notation: `2.1232442(2)` → value 2.1232442, uncertainty 2e-7.
    # The (N) is the uncertainty in the last given digit.
    def self.from_concise(num_str, paren_str)
      uncert_digits = paren_str.to_f
      if num_str.include?(".")
        decimal_places = num_str.split(".", 2)[1].length
        uncertainty = uncert_digits * 10.0**(-decimal_places)
      else
        uncertainty = uncert_digits
      end
      new(num_str.to_f, uncertainty)
    end

    def +(other)
      case other
      when Measurement
        Measurement.new(@value + other.value,
                        Math.sqrt(@uncertainty**2 + other.uncertainty**2))
      when Numeric
        Measurement.new(@value + other, @uncertainty)
      else
        raise TypeError, "cannot add #{other.class} to Measurement"
      end
    end

    def -(other)
      case other
      when Measurement
        Measurement.new(@value - other.value,
                        Math.sqrt(@uncertainty**2 + other.uncertainty**2))
      when Numeric
        Measurement.new(@value - other, @uncertainty)
      else
        raise TypeError, "cannot subtract #{other.class} from Measurement"
      end
    end

    def *(other)
      case other
      when Measurement
        new_val = @value * other.value
        return Measurement.new(0, 0) if new_val.zero?
        rel_var = (@uncertainty.to_f / @value)**2 + (other.uncertainty.to_f / other.value)**2
        Measurement.new(new_val, new_val.abs * Math.sqrt(rel_var))
      when Numeric
        Measurement.new(@value * other, @uncertainty * other.abs)
      else
        raise TypeError, "cannot multiply Measurement by #{other.class}"
      end
    end

    def /(other)
      case other
      when Measurement
        new_val = @value.to_f / other.value
        return Measurement.new(new_val, 0) if @value.zero?
        rel_var = (@uncertainty.to_f / @value)**2 + (other.uncertainty.to_f / other.value)**2
        Measurement.new(new_val, new_val.abs * Math.sqrt(rel_var))
      when Numeric
        Measurement.new(@value.to_f / other, @uncertainty / other.abs)
      else
        raise TypeError, "cannot divide Measurement by #{other.class}"
      end
    end

    def **(exp)
      raise TypeError, "Measurement exponent must be Numeric" unless exp.is_a?(Numeric)
      new_val = @value ** exp
      # σ_z/|z| = |n| · σ_x/|x|, only meaningful for non-zero base
      return Measurement.new(new_val, 0) if @value.zero?
      rel_unc = exp.abs * @uncertainty.to_f.abs / @value.abs
      Measurement.new(new_val, new_val.abs * rel_unc)
    end

    def -@
      Measurement.new(-@value, @uncertainty)
    end

    def +@
      self
    end

    def abs
      Measurement.new(@value.abs, @uncertainty)
    end

    # Rounding operations. These operate on the value and DROP uncertainty —
    # rounding a measurement is itself a measurement only if you carry the
    # uncertainty, but for purposes of "is this an integer" checks (used by
    # rescale logic) the value-only version is what callers want.
    def round(*args)   = @value.round(*args)
    def floor(*args)   = @value.floor(*args)
    def ceil(*args)    = @value.ceil(*args)
    def truncate(*args) = @value.truncate(*args)

    def zero?
      @value.zero? && @uncertainty.zero?
    end

    def <=>(other)
      case other
      when Measurement then @value <=> other.value
      when Numeric     then @value <=> other
      end
    end

    def ==(other)
      case other
      when Measurement
        @value == other.value && @uncertainty == other.uncertainty
      when Numeric
        @value == other && @uncertainty.zero?
      else
        false
      end
    end

    alias_method :eql?, :==

    def hash
      [@value, @uncertainty].hash
    end

    def coerce(other)
      case other
      when Numeric then [Measurement.new(other, 0), self]
      else raise TypeError, "#{other.class} can't be coerced into Measurement"
      end
    end

    def to_f
      @value.to_f
    end

    def to_i
      @value.to_i
    end

    # Display as `5.0 ± 0.1`. If the uncertainty is zero, drop the ±0 noise.
    def to_s
      return @value.to_s if @uncertainty.zero?
      "#{format_value(@value)} ± #{format_value(@uncertainty)}"
    end

    def inspect
      to_s
    end

    private

    def format_value(v)
      case v
      when Integer
        v.to_s
      when Rational
        v.denominator == 1 ? v.numerator.to_s : v.to_s
      when ::BigDecimal
        v == v.to_i ? v.to_i.to_s : v.to_s("F")
      when ::Float
        v == v.to_i && v.abs < 1e15 ? v.to_i.to_s : v.to_s
      else
        v.to_s
      end
    end
  end
end

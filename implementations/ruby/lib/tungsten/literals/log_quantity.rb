# frozen_string_literal: true

module Tungsten
  # A logarithmic-scale quantity: dB, dBV, dBm, dB SPL, etc.
  #
  # Logarithmic units are fundamentally different from linear units. The
  # value is stored in log space; arithmetic in log space corresponds to
  # multiplication in linear space. So `60 dB + 3 dB ≈ 63 dB` (log-additive)
  # but the underlying linear ratio doubles.
  #
  # Each logarithmic quantity has:
  #   - value (Float, in log units)
  #   - base (typically 10, sometimes e for nepers)
  #   - scale (10 for power-like, 20 for amplitude-like)
  #   - reference (a linear Quantity — what the dB value is *relative to*)
  #
  # Examples:
  #   LogQuantity.dB_SPL(60)     # 60 dB SPL  (relative to 20 µPa)
  #   LogQuantity.dBV(0)         # 0 dBV       (= 1 V)
  #   LogQuantity.dBm(30)        # 30 dBm      (= 1 W = 1000 mW)
  #
  # First-pass status: addition/subtraction work in log space, .linear
  # collapses to a physical Quantity, .to_s renders nicely. Full lexer
  # integration (`60 dB` as a literal) and unified arithmetic with linear
  # Quantities are deferred — see TODO.md.
  class LogQuantity
    attr_reader :value, :base, :scale, :reference, :unit_label

    def initialize(value, base:, scale:, reference: nil, unit_label: "dB")
      @value = value.to_f
      @base = base
      @scale = scale
      @reference = reference
      @unit_label = unit_label
    end

    # Log-space addition: 60 dB + 3 dB = 63 dB.
    # Underlying linear ratio: 10^(60/10) × 10^(3/10) = 10^(63/10).
    # When one side is a generic dB (no reference) and the other is referenced
    # (dB SPL, dBV, etc.), the generic side inherits the referenced side's
    # base/scale/reference so "boost SPL by 3 dB" works as expected.
    def +(other)
      raise TypeError, "can only add LogQuantity to LogQuantity" unless other.is_a?(LogQuantity)
      anchor = pick_anchor(other)
      LogQuantity.new(@value + other.value, base: anchor.base, scale: anchor.scale,
                      reference: anchor.reference, unit_label: anchor.unit_label)
    end

    def -(other)
      raise TypeError, "can only subtract LogQuantity from LogQuantity" unless other.is_a?(LogQuantity)
      anchor = pick_anchor(other)
      LogQuantity.new(@value - other.value, base: anchor.base, scale: anchor.scale,
                      reference: anchor.reference, unit_label: anchor.unit_label)
    end

    # Multiplication of dB by a scalar makes physical sense (it scales the
    # log value, equivalent to raising the linear ratio to a power).
    def *(other)
      raise TypeError, "can only multiply LogQuantity by Numeric" unless other.is_a?(Numeric)
      LogQuantity.new(
        @value * other,
        base: @base,
        scale: @scale,
        reference: @reference,
        unit_label: @unit_label
      )
    end

    def /(other)
      case other
      when Numeric
        LogQuantity.new(
          @value / other,
          base: @base,
          scale: @scale,
          reference: @reference,
          unit_label: @unit_label
        )
      when LogQuantity
        ensure_compatible!(other)
        # log_b(x/y) = log_b(x) - log_b(y) — so dividing in linear is subtracting in log.
        LogQuantity.new(
          @value - other.value,
          base: @base,
          scale: @scale,
          reference: @reference,
          unit_label: @unit_label
        )
      else
        raise TypeError, "cannot divide LogQuantity by #{other.class}"
      end
    end

    # Collapse to the linear quantity. For 0 dB SPL → 20 µPa; 60 dB SPL → 0.02 Pa; etc.
    def linear
      ratio = @base.to_f ** (@value / @scale)
      @reference.is_a?(Quantity) ? @reference * ratio : ratio
    end

    # The bare linear ratio (no reference applied). 60 dB power → 10^6.
    def ratio
      @base.to_f ** (@value / @scale)
    end

    def ==(other)
      return false unless other.is_a?(LogQuantity)
      compatible?(other) && @value == other.value
    end

    def to_s
      "#{format_value(@value)} #{@unit_label}"
    end

    def inspect
      to_s
    end

    # Convenience constructors — the standard dB flavors.

    # dB SPL: sound pressure level, reference 20 µPa.
    def self.dB_SPL(value)
      ref = Quantity.new(2e-5, Units.parse("Pa"))
      new(value, base: 10, scale: 20, reference: ref, unit_label: "dB SPL")
    end

    # dBV: voltage relative to 1 V.
    def self.dBV(value)
      ref = Quantity.new(1, Units.parse("V"))
      new(value, base: 10, scale: 20, reference: ref, unit_label: "dBV")
    end

    # dBu: voltage relative to 0.7746 V (≈ √(0.6) V, the voltage that
    # delivers 1 mW into 600 Ω).
    def self.dBu(value)
      ref = Quantity.new(0.7745966692414834, Units.parse("V"))
      new(value, base: 10, scale: 20, reference: ref, unit_label: "dBu")
    end

    # dBm: power relative to 1 mW.
    def self.dBm(value)
      ref = Quantity.new(1e-3, Units.parse("W"))
      new(value, base: 10, scale: 10, reference: ref, unit_label: "dBm")
    end

    # dBW: power relative to 1 W.
    def self.dBW(value)
      ref = Quantity.new(1, Units.parse("W"))
      new(value, base: 10, scale: 10, reference: ref, unit_label: "dBW")
    end

    # Generic ratio dB (no reference quantity — pure dimensionless ratio).
    def self.dB(value)
      new(value, base: 10, scale: 10, reference: nil, unit_label: "dB")
    end

    # Neper: natural-log version of dB. 1 Np ≈ 8.686 dB.
    def self.Np(value)
      new(value, base: Math::E, scale: 1, reference: nil, unit_label: "Np")
    end

    private

    # Pick which operand's "shape" (base/scale/reference/label) wins. The
    # referenced side wins if exactly one is referenced; otherwise self wins.
    # Errors if both are referenced and incompatible, or if bases differ
    # (a Np + dB mix would need explicit conversion).
    def pick_anchor(other)
      if @base != other.base
        raise TypeError,
              "incompatible logarithmic units: #{@unit_label} vs #{other.unit_label} (different bases)"
      end
      if @reference && other.reference && @reference != other.reference
        raise TypeError, "incompatible logarithmic units: #{@unit_label} vs #{other.unit_label} (different references)"
      end
      other.reference && !@reference ? other : self
    end

    def compatible?(other)
      return false unless @base == other.base && @scale == other.scale
      @reference.nil? || other.reference.nil? || @reference == other.reference
    end

    def ensure_compatible!(other)
      return if compatible?(other)
      raise TypeError, "incompatible logarithmic units: #{@unit_label} vs #{other.unit_label}"
    end

    def format_value(v)
      v == v.to_i && v.abs < 1e15 ? v.to_i.to_s : v.to_s
    end
  end
end

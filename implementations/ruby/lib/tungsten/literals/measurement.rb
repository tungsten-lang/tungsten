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
  # First-order arithmetic uses declared correlations when present. The
  # `.propagate` API provides deterministic-seed Monte-Carlo propagation for
  # nonlinear models; asymmetric bounds and random/systematic components are
  # retained as measurement metadata.
  class Measurement
    include Comparable

    attr_reader :value, :uncertainty, :lower_uncertainty, :upper_uncertainty,
                :confidence, :coverage_factor, :degrees_of_freedom, :components,
                :provenance

    alias_method :standard_uncertainty, :uncertainty

    def initialize(value, uncertainty, lower_uncertainty: nil, upper_uncertainty: nil,
                   confidence: nil, coverage_factor: 1.0, degrees_of_freedom: nil,
                   components: nil, provenance: nil)
      @value = value
      @uncertainty = uncertainty.to_f.abs
      @lower_uncertainty = (lower_uncertainty || @uncertainty).to_f.abs
      @upper_uncertainty = (upper_uncertainty || @uncertainty).to_f.abs
      @confidence = confidence
      @coverage_factor = coverage_factor.to_f
      @degrees_of_freedom = degrees_of_freedom
      @components = (components || {}).transform_keys(&:to_sym).freeze
      @provenance = Array(provenance).compact.freeze
      @identity_token = Object.new
      @source_terms = {@identity_token => @uncertainty}.freeze
      @correlation_peer = nil
    end

    def self.with_components(value, random: 0, systematic: 0, **options)
      components = {random: random.to_f.abs, systematic: systematic.to_f.abs}
      uncertainty = Math.sqrt(components.values.sum { |u| u**2 })
      new(value, uncertainty, components:, **options)
    end

    def self.asymmetric(value, lower:, upper:, **options)
      standard = (lower.to_f.abs + upper.to_f.abs) / 2.0
      new(value, standard, lower_uncertainty: lower, upper_uncertainty: upper, **options)
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
        derived(@value + other.value, 1, other, 1)
      when Numeric
        derived(@value + other, 1)
      else
        raise TypeError, "cannot add #{other.class} to Measurement"
      end
    end

    def -(other)
      case other
      when Measurement
        derived(@value - other.value, 1, other, -1)
      when Numeric
        derived(@value - other, 1)
      else
        raise TypeError, "cannot subtract #{other.class} from Measurement"
      end
    end

    def *(other)
      case other
      when Measurement
        new_val = @value * other.value
        derived(new_val, other.value.to_f, other, @value.to_f)
      when Numeric
        derived(@value * other, other.to_f)
      else
        raise TypeError, "cannot multiply Measurement by #{other.class}"
      end
    end

    def /(other)
      case other
      when Measurement
        raise ZeroDivisionError, "Measurement division by zero" if other.value.zero?
        new_val = @value.to_f / other.value
        dx = 1.0 / other.value
        dy = -@value.to_f / (other.value.to_f**2)
        derived(new_val, dx, other, dy)
      when Numeric
        raise ZeroDivisionError, "Measurement division by zero" if other.zero?
        derived(@value.to_f / other, 1.0 / other)
      else
        raise TypeError, "cannot divide Measurement by #{other.class}"
      end
    end

    def **(exp)
      raise TypeError, "Measurement exponent must be Numeric" unless exp.is_a?(Numeric)
      new_val = @value ** exp
      if @value.zero?
        derivative = 1 if exp == 1
        derivative = 0 if exp == 0 || exp > 1
        if derivative.nil?
          raise ArgumentError, "uncertain zero cannot be raised to this exponent"
        end
      else
        derivative = exp * (@value.to_f ** (exp - 1))
      end
      derived(new_val, derivative)
    end

    def sqrt
      raise ArgumentError, "Measurement.sqrt needs a nonnegative value" if @value.negative?
      if @value.zero?
        raise ArgumentError, "Measurement.sqrt is singular at uncertain zero" unless @uncertainty.zero?
        return derived(0.0, 0.0)
      end
      root = Math.sqrt(@value)
      derived(root, 0.5 / root)
    end

    def -@
      Measurement.new(-@value, @uncertainty,
                      lower_uncertainty: @upper_uncertainty,
                      upper_uncertainty: @lower_uncertainty,
                      confidence: @confidence, coverage_factor: @coverage_factor,
                      degrees_of_freedom: @degrees_of_freedom,
                      components: @components, provenance: @provenance).with_source_terms(@source_terms.transform_values(&:-@))
    end

    def +@
      self
    end

    def abs
      derived(@value.abs, @value.negative? ? -1 : 1)
    end

    # Declare a correlation between two input measurements. Correlation is
    # symmetric and is used by subsequent first-order propagation.
    def correlate(other, coefficient)
      raise TypeError, "can only correlate two Measurements" unless other.is_a?(Measurement)
      raise ArgumentError, "correlation needs a distinct Measurement" if equal?(other)
      rho = coefficient.to_f
      raise ArgumentError, "correlation must be between -1 and 1" unless rho.between?(-1, 1)
      detach_peer
      other.__send__(:detach_peer)
      shared = Object.new
      @source_terms = {shared => uncertainty}.freeze
      residual = Math.sqrt((1.0 - rho) * (1.0 + rho))
      other.with_source_terms({shared => rho * other.uncertainty, Object.new => residual * other.uncertainty})
      @correlation_peer = other
      other.__send__(:correlation_peer=, self)
      self
    end

    def correlation_with(other)
      return 1.0 if equal?(other)
      return 0.0 if uncertainty.zero? || other.uncertainty.zero?
      @source_terms.sum do |source, contribution|
        (contribution / uncertainty) * (other.source_terms.fetch(source, 0.0) / other.uncertainty)
      end.clamp(-1.0, 1.0)
    end

    def interval
      [@value - @lower_uncertainty * @coverage_factor,
       @value + @upper_uncertainty * @coverage_factor]
    end

    def expanded(coverage_factor = 2.0, confidence: nil)
      confidence = @confidence if confidence.nil?
      self.class.new(@value, @uncertainty,
                     lower_uncertainty: @lower_uncertainty,
                     upper_uncertainty: @upper_uncertainty,
                     confidence:, coverage_factor:,
                     degrees_of_freedom: @degrees_of_freedom,
                     components: @components, provenance: @provenance).with_source_terms(@source_terms)
    end

    def calibrate(calibration)
      calibration.apply(self)
    end

    # Monte-Carlo propagation for nonlinear measurement models. Inputs are
    # sampled as independent Gaussians; correlated models should draw their
    # own samples explicitly until a covariance-matrix sampler is added.
    def self.propagate(*inputs, samples: 10_000, seed: nil, &model)
      raise ArgumentError, "a propagation block is required" unless model
      rng = ::Random.new(seed || ::Random.new_seed)
      values = Array.new(samples) do
        draws = inputs.map { |m| gaussian(rng, m.value.to_f, m.uncertainty) }
        model.call(*draws).to_f
      end
      mean = values.sum / values.length
      variance = values.sum { |v| (v - mean)**2 } / [values.length - 1, 1].max
      new(mean, Math.sqrt(variance), provenance: ["Monte Carlo: #{samples} samples"])
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
      value_str, uncertainty_str = significant_pair
      suffix = @coverage_factor == 1.0 ? "" : " (k=#{format_value(@coverage_factor)})"
      if @lower_uncertainty != @upper_uncertainty
        "#{value_str} +#{format_value(@upper_uncertainty)}/-#{format_value(@lower_uncertainty)}#{suffix}"
      else
        "#{value_str} ± #{uncertainty_str}#{suffix}"
      end
    end

    def inspect
      to_s
    end

    attr_reader :source_terms, :identity_token

    def with_source_terms(terms)
      @source_terms = terms.freeze
      self
    end

    def covariance_with(other)
      @source_terms.sum { |source, weight| weight * other.source_terms.fetch(source, 0.0) }
    end

    private

    attr_writer :correlation_peer

    def detach_peer
      return unless @correlation_peer
      @correlation_peer.with_source_terms({Object.new => @correlation_peer.uncertainty})
      @correlation_peer.__send__(:correlation_peer=, nil)
      @correlation_peer = nil
    end

    def derived(new_value, dx, other = nil, dy = 0)
      terms = @source_terms.transform_values { |contribution| dx * contribution }
      other&.source_terms&.each do |input, contribution|
        terms[input] = terms.fetch(input, 0.0) + dy * contribution
      end
      sigma = terms.values.reduce(0.0) { |norm, weight| Math.hypot(norm, weight) }
      sources = @provenance + (other&.provenance || [])
      Measurement.new(new_value, sigma, provenance: sources).with_source_terms(terms)
    end

    def significant_pair
      return [format_value(@value), format_value(@uncertainty)] if @uncertainty.zero?
      exponent = Math.log10(@uncertainty).floor
      leading = (@uncertainty / (10.0**exponent)).floor
      significant_digits = leading <= 2 ? 2 : 1
      places = significant_digits - 1 - exponent
      rounded_uncertainty = @uncertainty.round(places)
      rounded_value = @value.to_f.round(places)
      if places.positive?
        [format("%.#{places}f", rounded_value), format("%.#{places}f", rounded_uncertainty)]
      else
        [rounded_value.to_i.to_s, rounded_uncertainty.to_i.to_s]
      end
    end

    def self.gaussian(rng, mean, sigma)
      return mean if sigma.zero?
      u1 = [rng.rand, Float::MIN].max
      u2 = rng.rand
      mean + sigma * Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
    end

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

# frozen_string_literal: true

module Tungsten
  # Metadata carried by a calibration result. The fields follow VIM/GUM
  # vocabulary and the information normally needed to support an ISO/IEC
  # 17025-style traceability claim; this object does not itself certify one.
  CalibrationCertificate = Struct.new(
    :id, :laboratory, :issued_at, :valid_until, :reference, :method,
    :conditions, :traceability_chain, keyword_init: true
  )

  # Polynomial measurement model y = c0 + c1*x + c2*x² + ... with an
  # uncertainty budget and optional calibration-certificate metadata.
  class Calibration
    attr_reader :coefficients, :coefficient_uncertainties, :input_unit,
                :output_unit, :standard_uncertainty, :valid_range, :certificate

    def initialize(coefficients:, input_unit: nil, output_unit: nil,
                   coefficient_uncertainties: nil, coefficient_covariance: nil,
                   standard_uncertainty: 0, valid_range: nil, certificate: nil)
      raise ArgumentError, "calibration needs at least one coefficient" if coefficients.empty?
      @coefficients = coefficients.map(&:to_f).freeze
      @coefficient_uncertainties = Array(coefficient_uncertainties || Array.new(coefficients.length, 0.0)).map(&:to_f).freeze
      raise ArgumentError, "coefficient uncertainty count must match coefficients" unless @coefficient_uncertainties.length == @coefficients.length
      @coefficient_covariance = coefficient_covariance
      @input_unit = input_unit
      @output_unit = output_unit
      @standard_uncertainty = standard_uncertainty.to_f.abs
      @valid_range = valid_range
      @certificate = certificate
    end

    def self.linear(slope, intercept = 0, input_unit = nil, output_unit = nil,
                    standard_uncertainty = 0, certificate_id = nil)
      certificate = certificate_id && CalibrationCertificate.new(id: certificate_id)
      new(coefficients: [intercept, slope], input_unit:, output_unit:,
          standard_uncertainty:, certificate:)
    end

    def apply(input)
      measurement, source_unit = normalize_input(input)
      if @input_unit && source_unit && Units.parse(@input_unit).dimension != source_unit.dimension
        raise DimensionError, "calibration expects #{@input_unit}, got #{source_unit}"
      end
      x = measurement.value.to_f
      validate_range!(x)
      y = polynomial(x)
      input_variance = (derivative(x) * measurement.uncertainty)**2
      coefficient_variance = coefficient_variance_at(x)
      uncertainty = Math.sqrt(input_variance + coefficient_variance + @standard_uncertainty**2)
      provenance = measurement.provenance.dup
      provenance << "calibration #{@certificate.id}" if @certificate&.id
      result = Measurement.new(y, uncertainty, provenance:)
      @output_unit ? Quantity.new(result, Units.parse(@output_unit)) : result
    end

    private

    def normalize_input(input)
      if input.is_a?(Quantity)
        value = input.value.is_a?(Measurement) ? input.value : Measurement.new(input.value, 0)
        return [value, input.unit]
      end
      [input.is_a?(Measurement) ? input : Measurement.new(input, 0), nil]
    end

    def polynomial(x)
      @coefficients.reverse_each.reduce(0.0) { |acc, coefficient| acc * x + coefficient }
    end

    def derivative(x)
      return 0.0 if @coefficients.length == 1
      (1...@coefficients.length).reverse_each.reduce(0.0) do |acc, index|
        acc * x + index * @coefficients[index]
      end
    end

    def coefficient_variance_at(x)
      powers = Array.new(@coefficients.length) { |index| x**index }
      variance = powers.each_index.sum { |index| (powers[index] * @coefficient_uncertainties[index])**2 }
      return variance unless @coefficient_covariance
      powers.each_index do |i|
        (i + 1...powers.length).each do |j|
          variance += 2 * powers[i] * powers[j] * @coefficient_covariance.fetch(i, {}).fetch(j, 0).to_f
        end
      end
      variance
    end

    def validate_range!(x)
      return unless @valid_range && !@valid_range.cover?(x)
      raise RangeError, "calibration input #{x} is outside #{@valid_range}"
    end
  end
end

# frozen_string_literal: true

require "tungsten"

RSpec.describe "Advanced measurements and quantity semantics" do
  describe "point and delta annotations" do
    it "keeps ordinary quantities as vectors" do
      expect(Tungsten.run("10 m + 10 m").to_s).to eq("20 m")
    end

    it "permits point plus delta and point minus point" do
      expect(Tungsten.run("(10 m).point(:map) + (2 m).delta(:map)").to_s)
        .to eq("(12 m).point(:map)")
      expect(Tungsten.run("(10 m).point(:map) - (2 m).point(:map)").to_s)
        .to eq("(8 m).delta(:map)")
    end

    it "rejects point plus point and mismatched origins" do
      expect { Tungsten.run("(10 m).point(:map) + (2 m).point(:map)") }
        .to raise_error(Tungsten::DimensionError, /two points/)
      expect { Tungsten.run("(10 m).point(:map) - (2 m).point(:screen)") }
        .to raise_error(Tungsten::DimensionError, /origins/)
    end
  end

  describe "semantic dimensions" do
    it "keeps angle explicit without changing the definition of energy" do
      expect(Tungsten::Units.parse("rad").dimension).to eq(Tungsten::Units::ANGLE)
      expect(Tungsten::Units.parse("J").dimension).to eq(Tungsten::Units::ENERGY)
      expect(Tungsten::Units.parse("N·m").dimension).to eq(Tungsten::Units::TORQUE)
    end

    it "distinguishes same-vector concepts when a semantic kind is named" do
      expect { Tungsten.run("1 heat_capacity + 1 entropy") }
        .to raise_error(Tungsten::DimensionError)
      expect { Tungsten.run("1 Gy + 1 specific_energy") }
        .to raise_error(Tungsten::DimensionError)
    end

    it "keeps frequency, rates, and activity compositional" do
      expect(Tungsten.run("1 Hz * 1 s").unit.components).to eq("cycle" => 1)
      expect(Tungsten.run("60 bpm * 1 min").unit.components).to eq("beat" => 1)
      expect(Tungsten.run("60 rpm * 1 min").unit.components).to eq("revolution" => 1)
      expect(Tungsten.run("1 Bq * 1 s").unit.components).to eq("decay" => 1)
      expect { Tungsten.run("1 Hz + 1 Bq") }.to raise_error(Tungsten::DimensionError)
    end

    it "preserves symbolic algebra for undefined units" do
      expect(Tungsten.run("2x + 3x").to_s).to eq("5 x")
      expect(Tungsten.run("2π * 3π").unit.dimension.customs).to eq("π" => 2)
    end
  end

  describe Tungsten::Measurement do
    it "parses the uncertainty literal and rounds value/uncertainty together" do
      measurement = Tungsten.run("10.0 ± 0.2")
      expect(measurement).to be_a(described_class)
      expect(measurement.to_s).to eq("10.00 ± 0.20")
    end

    it "supports asymmetric and expanded uncertainty" do
      measurement = described_class.asymmetric(10, lower: 0.1, upper: 0.3,
                                                 confidence: 0.95).expanded(2)
      expect(measurement.to_s).to include("+0.3/-0.1", "k=2")
      expect(measurement.interval).to eq([9.8, 10.6])
      expect(measurement.confidence).to eq(0.95)
    end

    it "tracks random/systematic components and declared correlation" do
      a = described_class.with_components(10, random: 0.3, systematic: 0.4)
      b = described_class.new(2, 0.2)
      a.correlate(b, 1)
      expect((a + b).uncertainty).to be_within(1e-12).of(0.7)
      expect(a.components).to eq(random: 0.3, systematic: 0.4)
    end

    it "offers seeded Monte Carlo propagation for nonlinear models" do
      input = described_class.new(2, 0.1)
      result = described_class.propagate(input, samples: 20_000, seed: 7) { |x| x**2 }
      expect(result.value).to be_within(0.03).of(4.01)
      expect(result.uncertainty).to be_within(0.03).of(0.4)
    end
  end

  describe Tungsten::Calibration do
    it "propagates input, coefficient, and calibration uncertainty" do
      certificate = Tungsten::CalibrationCertificate.new(
        id: "CAL-42", laboratory: "example", traceability_chain: ["SI"]
      )
      calibration = described_class.new(
        coefficients: [1, 2], coefficient_uncertainties: [0.1, 0.05],
        standard_uncertainty: 0.2, valid_range: 0..10, certificate:
      )
      result = calibration.apply(Tungsten::Measurement.new(3, 0.4))
      expected = Math.sqrt(0.8**2 + 0.1**2 + (3 * 0.05)**2 + 0.2**2)
      expect(result.value).to eq(7.0)
      expect(result.uncertainty).to be_within(1e-12).of(expected)
      expect(result.provenance).to include("calibration CAL-42")
    end
  end

  describe "physical equivalencies" do
    it "requires an explicit named bridge" do
      expect { Tungsten.run("1 kg | J") }.to raise_error(Tungsten::DimensionError)
      energy = Tungsten.run("1 kg").equivalent("J", :mass_energy)
      expect(energy.value.to_f).to be_within(1).of(299_792_458.0**2)
    end

    it "supports spectral and thermal bridges" do
      frequency = Tungsten.run("500 nm").equivalent("Hz", :spectral)
      expect(frequency.value.to_f).to be_within(1e6).of(599_584_916_000_000.0)
      energy = Tungsten.run("300 K").equivalent("J", :thermal)
      expect(energy.value.to_f).to be_within(1e-32).of(300 * 1.380_649e-23)
    end
  end
end

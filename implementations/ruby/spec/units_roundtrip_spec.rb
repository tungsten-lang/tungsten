# frozen_string_literal: true

require "tungsten"

# Property-style test: for every atomic unit in UNIT_TABLE, the canonical
# string form (`1 <unit>`.to_s) must lex and parse back to an equal Quantity.
# This locks in the contract between the formatter and the lexer/parser.
RSpec.describe "Unit round-trip stability" do
  # Easter-egg outputs that intentionally don't round-trip — display a
  # human-readable approximation rather than the literal value.
  EXEMPT_FROM_ROUNDTRIP = Set.new(%w[
    barn\ megaparsec
  ]).freeze

  Tungsten::Units::UNIT_TABLE.each_key do |sym|
    next if EXEMPT_FROM_ROUNDTRIP.include?(sym)

    it "round-trips '1 #{sym}'" do
      q = Tungsten.run("1 #{sym}")
      next unless q.is_a?(Tungsten::Quantity)

      s = q.to_s
      q2 = Tungsten.run(s)
      expect(q2).to be_a(Tungsten::Quantity), "could not re-parse #{s.inspect}"
      expect(q).to eq(q2), "1 #{sym} → #{s.inspect} → re-parsed to #{q2.inspect}"
    end
  end

  describe "easter eggs (exempted)" do
    it "barn megaparsec displays as ≈π mL and is not expected to round-trip" do
      q = Tungsten.run("1 barn megaparsec")
      expect(q.to_s).to eq("≈π mL")
    end
  end

  describe "compound dimension parsing" do
    it "parses parenthesized denominator products" do
      gas_constant = Tungsten::Units.parse("J/(mol·K)")
      stefan_boltzmann = Tungsten::Units.parse("W/(m²·K⁴)")

      expect(gas_constant.dimension.to_a).to eq([2, 1, -2, 0, -1, -1, 0, 0])
      expect(stefan_boltzmann.dimension.to_a).to eq([0, 1, -3, 0, -4, 0, 0, 0])
    end

    it "keeps negative quantity powers dimensionful" do
      inverse_area = Tungsten.run("(2 m) ** -2")

      expect(inverse_area.unit.dimension.to_a).to eq([-2, 0, 0, 0, 0, 0, 0, 0])
      expect(inverse_area.value).to eq(Rational(1, 4))
    end
  end

  describe "semantic quantity kinds" do
    it "does not conflate equal SI exponent vectors" do
      expect { Tungsten.run("1 rad | ppm") }.to raise_error(Tungsten::DimensionError)
      expect { Tungsten.run("1 Gy | Sv") }.to raise_error(Tungsten::DimensionError)
      expect { Tungsten.run("1 N·m | J") }.to raise_error(Tungsten::DimensionError)
      expect { Tungsten.run("1 nit | lx") }.to raise_error(Tungsten::DimensionError)
    end

    it "keeps compatible members of a semantic kind convertible" do
      expect(Tungsten.run("180 deg | rad").value.to_f).to be_within(1e-12).of(Math::PI)
      expect(Tungsten.run("100 rem | Sv").value.to_f).to be_within(1e-12).of(1)
      expect(Tungsten.run("1 nit | cd/m²").value.to_f).to eq(1)
    end
  end

  describe "absolute temperatures and differences" do
    it "subtracts points into a matching difference unit" do
      result = Tungsten.run("30 °C - 68 °F")
      expect(result.value.to_f).to be_within(1e-12).of(10)
      expect(result.unit.symbol).to eq("Δ°C")
    end

    it "adds a difference to a point in either order" do
      expect(Tungsten.run("20 °C + 18 Δ°F").to_s).to eq("30 °C")
      expect(Tungsten.run("18 Δ°F + 20 °C").to_s).to eq("30 °C")
    end

    it "rejects point addition and affine multiplication" do
      expect { Tungsten.run("20 °C + 10 °C") }.to raise_error(Tungsten::DimensionError, /absolute temperatures/)
      expect { Tungsten.run("20 °C * 2") }.to raise_error(Tungsten::DimensionError, /affine/)
    end
  end

  describe "new practical and contextual quantities" do
    it "converts analyte-scoped glucose concentrations" do
      result = Tungsten.run("100 mg/dL_glucose | mmol/L_glucose")
      expect(result.value.to_f).to be_within(1e-8).of(5.55075)
    end

    it "uses explicit context for Mach and CSS resolution" do
      expect(Tungsten.run("1 mach_air_20C | m/s").value.to_f).to eq(343)
      expect(Tungsten.run("1 dppx | dpi").value.to_f).to eq(96)
    end

    it "keeps distinct compute denominators incompatible" do
      expect { Tungsten.run("1 J/op | J/tok") }.to raise_error(Tungsten::DimensionError)
    end
  end

  describe "shared external documentation" do
    it "loads descriptions, etymology, and history from the TSV" do
      unit = Tungsten::Units::UNIT_TABLE.fetch("N·m")
      expect(unit.description).to include("torque")
      expect(unit.etymology).to include("torquere")
      expect(unit.history).to include("joules")
    end
  end

  describe "PB + J" do
    it "turns one petabyte plus one joule into a sandwich" do
      result = Tungsten.run("1 PB + 1 J")
      expect(result).to be_a(Tungsten::Sandwich)
      expect(result.to_s).to include("It's peanut butter jelly time!")
    end
  end
end

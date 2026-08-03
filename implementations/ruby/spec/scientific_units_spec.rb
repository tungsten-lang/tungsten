# frozen_string_literal: true

require "tungsten"

RSpec.describe "Cross-domain scientific units" do
  it "supports the complete symbolic SI and IEC prefix surfaces" do
    units = Tungsten::Units
    si_names = units::PREFIX_TABLE.keys.product(units::PREFIXABLE.to_a).map { |prefix, base| "#{prefix}#{base}" }
    binary_names = units::BINARY_PREFIX_TABLE.keys.product(units::BINARY_PREFIXABLE.to_a)
      .map { |prefix, base| "#{prefix}#{base}" }

    expect((si_names | binary_names).all? { |name| units.known?(name) }).to be(true)
    expect(units.parse("Qm").factor).to eq(10**30)
    expect(units.parse("qHz").factor).to eq(Rational(1, 10**30))
    expect(units.parse("Kib").factor).to eq(128)
  end

  it "covers chemistry and laboratory concentrations without erasing semantics" do
    expect(Tungsten.run('1 M | "mmol/L"').value).to eq(1_000)
    expect(Tungsten.run("1 mg/dL | g/L").value).to eq(Rational(1, 100))
    expect(Tungsten.run("1 U_enzyme | kat").value).to eq(Rational(1, 60_000_000))
    expect(Tungsten.run("1 cal_IT | J").value).to eq(Rational(10_467, 2_500))
    expect(Tungsten.run("1 cal_th | J").value).to eq(Rational(523, 125))
    expect { Tungsten.run("1 M + 1 mEq/L") }.to raise_error(Tungsten::DimensionError)
    expect { Tungsten.run("1 CFU/mL + 1 PFU/mL") }.to raise_error(Tungsten::DimensionError)
  end

  it "keeps symbol rate distinct from information rate" do
    expect(Tungsten.run("1 baud * 1 s").unit.components).to eq("symbol" => 1)
    expect { Tungsten.run("1 baud + 1 bps") }.to raise_error(Tungsten::DimensionError)
  end

  it "converts electromagnetic and optical conventions exactly" do
    expect(Tungsten.run("1 statV | V").value).to eq(Rational(149_896_229, 500_000))
    expect(Tungsten.run("1 Ah | C").value).to eq(3_600)
    expect(Tungsten.run("1 phot | lx").value).to eq(10_000)
    expect(Tungsten.run("1 Jy | W/m²/Hz").value).to eq(Rational(1, 10**26))
  end

  it "distinguishes radiation quantities and detector counts" do
    expect(Tungsten.run("1 rad_dose | Gy").value).to eq(Rational(1, 100))
    expect(Tungsten.run("60 dpm * 1 min").unit.components).to eq("decay" => 1)
    expect(Tungsten.run("60 cpm * 1 min").unit.components).to eq("count" => 1)
    expect { Tungsten.run("1 Gy + 1 Sv") }.to raise_error(Tungsten::DimensionError)
  end

  it "covers astronomy, geoscience, biomedicine, and research throughput" do
    expect(Tungsten.run("1 sverdrup | m³/s").value).to eq(1_000_000)
    expect(Tungsten.run("1 mGal | m/s²").value).to eq(Rational(1, 100_000))
    expect(Tungsten.run("1 GUPS * 1 s").value).to eq(1_000_000_000)
    expect(Tungsten.run("1 TEPS * 1 s").value).to eq(1_000_000_000_000)
    expect { Tungsten.run("1 ppmv + 1 ppmw") }.to raise_error(Tungsten::DimensionError)
  end

  it "labels physical constants, measured references, and nominal units separately" do
    units = Tungsten::Units::UNIT_TABLE

    expect(units.fetch("electron_mass").kind).to eq(:physical_constant)
    expect(units.fetch("solarmass").kind).to eq(:reference_quantity)
    expect(units.fetch("R_sun_nominal").kind).to eq(:nominal_unit)
    expect(units.fetch("IU").kind).to eq(:contextual_unit)
    expect(Tungsten::Units.info("electron_mass")).to include("kind: physical constant")
  end
end

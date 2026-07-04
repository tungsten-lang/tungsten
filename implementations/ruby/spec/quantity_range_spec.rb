# frozen_string_literal: true

require "tungsten"

# Range literals with Quantity bounds — `1 m..10 m` produces a Range whose
# endpoints are Quantities. The standard Range API (cover?, min/max, clamp)
# flows units through automatically since Quantity implements <=>.
RSpec.describe "Range literals with units" do
  def run(src) = Tungsten.run(src)

  describe "construction" do
    it "produces a Range with Quantity endpoints" do
      r = run("1 m..10 m")
      expect(r).to be_a(Range)
      expect(r.first).to eq(run("1 m"))
      expect(r.last).to eq(run("10 m"))
    end

    it "accepts cross-unit endpoints" do
      r = run("5 m..10 km")
      expect(r).to be_a(Range)
    end
  end

  describe "cover?" do
    it "returns true for in-range quantities" do
      expect(run("(1 m..10 m).cover?(5 m)")).to eq(true)
    end

    it "returns false for out-of-range quantities" do
      expect(run("(1 m..10 m).cover?(50 m)")).to eq(false)
    end

    it "auto-converts units when checking membership" do
      expect(run("(1 m..10 m).cover?(500 cm)")).to eq(true)
      expect(run("(1 km..10 km).cover?(5500 m)")).to eq(true)
    end
  end

  describe "clamp" do
    it "leaves in-range values unchanged" do
      expect(run("(5 m).clamp(1 m, 10 m)")).to eq(run("5 m"))
    end

    it "clamps to upper bound" do
      expect(run("(50 m).clamp(1 m, 10 m)")).to eq(run("10 m"))
    end

    it "clamps to lower bound" do
      expect(run("(0.5 m).clamp(1 m, 10 m)")).to eq(run("1 m"))
    end

    it "auto-converts when clamping across units" do
      expect(run("(50 cm).clamp(1 m, 10 m)")).to eq(run("1 m"))
    end
  end

  describe "min/max" do
    it "returns range endpoints" do
      expect(run("(1 m..10 m).min")).to eq(run("1 m"))
      expect(run("(1 m..10 m).max")).to eq(run("10 m"))
    end
  end
end

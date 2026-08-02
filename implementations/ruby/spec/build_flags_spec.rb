# frozen_string_literal: true

require "tungsten/build_flags"

RSpec.describe Tungsten::BuildFlags do
  describe ".target_mode" do
    it "keeps the native default and the portable bare-release compatibility default" do
      expect(described_class.target_mode(release: false, native: false, portable: false)).to eq(:native)
      expect(described_class.target_mode(release: true, native: false, portable: false)).to eq(:portable)
    end

    it "lets an explicit native target override the release default" do
      expect(described_class.target_mode(release: true, native: true, portable: false)).to eq(:native)
    end

    it "rejects conflicting explicit targets" do
      expect do
        described_class.target_mode(release: true, native: true, portable: true)
      end.to raise_error(ArgumentError, "--native and --portable are mutually exclusive")
    end
  end

  describe ".march_for" do
    let(:custom) { "-march=x86-64-v3 -mtune=generic" }

    it "honors an environment override when no target is explicit" do
      expect(described_class.march_for(
        release: true, native: false, portable: false, override: custom
      )).to eq(custom.split)
    end

    it "lets explicit native and portable targets override the environment" do
      native = described_class.march_for(
        release: true, native: true, portable: false, override: custom
      )
      portable = described_class.march_for(
        release: false, native: false, portable: true, override: custom
      )

      expect(native).to eq(%w[-march=native -mtune=native])
      expect(portable).to eq(described_class.march(:portable))
    end
  end
end

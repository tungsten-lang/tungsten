# frozen_string_literal: true

require "tungsten/build_flags"
require "tmpdir"

RSpec.describe Tungsten::BuildFlags do
  describe ".resolve_cpu" do
    it "defaults local builds to the configured CPU or native" do
      expect(described_class.resolve_cpu(configured: "apple-m5")).to eq("apple-m5")
      allow(described_class).to receive(:configured_cpu).and_return(nil)
      expect(described_class.resolve_cpu).to eq("native")
    end

    it "does not leak a local CPU into a cross target" do
      expect(described_class.resolve_cpu(target: "aarch64-linux-gnu", configured: "apple-m5")).to be_nil
      expect(described_class.resolve_cpu(cpu: "neoverse-v2", target: "aarch64-linux-gnu")).to eq("neoverse-v2")
    end

    it "rejects conflicting --native and --cpu values" do
      expect do
        described_class.resolve_cpu(cpu: "apple-m5", native: true)
      end.to raise_error(ArgumentError, "--native conflicts with --cpu apple-m5")
    end
  end

  describe ".march_for" do
    let(:custom) { "-march=x86-64-v3 -mtune=generic" }

    it "honors the legacy environment override when no CPU is explicit" do
      expect(described_class.march_for(
        override: custom, configured: nil
      )).to eq(custom.split)
    end

    it "uses -mcpu for Arm CPU names and aliases x86 levels to -march" do
      native = described_class.march_for(
        cpu: "native", target: "arm64-apple-macos", override: custom
      )
      apple = described_class.march_for(
        cpu: "apple-m5", target: "arm64-apple-macos", override: custom
      )
      v3 = described_class.march_for(cpu: "v3", target: "x86_64-linux-gnu")

      expect(native).to eq(%w[-mcpu=native])
      expect(apple).to eq(%w[-mcpu=apple-m5])
      expect(v3).to eq(%w[-march=x86-64-v3 -mtune=generic])
    end

    it "uses the target baseline when cross-compiling without --cpu" do
      expect(described_class.march_for(target: "x86_64-linux-gnu", configured: "apple-m5")).to eq([])
    end
  end

  describe ".configured_cpu" do
    it "reads build.cpu from the user config" do
      Dir.mktmpdir("tungsten-config") do |dir|
        path = File.join(dir, "config")
        File.write(path, "[build]\ncpu = v3\n")
        expect(described_class.configured_cpu(path: path, env: {})).to eq("x86-64-v3")
      end
    end
  end
end

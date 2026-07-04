require "spec_helper"

RSpec.describe "Forge file parsing" do
  forge_dir = File.expand_path("../../../bits/tungsten-forge/lib", __dir__)

  Dir[File.join(forge_dir, "**/*.w")].sort.each do |path|
    relative = path.sub("#{forge_dir}/", "")

    it "parses #{relative} without error" do
      source = File.read(path)
      expect { Tungsten::Parser.parse(source) }.not_to raise_error
    end
  end
end

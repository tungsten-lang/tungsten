# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "Embedded example expectations" do
  let(:repo_root) { File.expand_path("../../..", __dir__) }
  let(:cli_path) { File.join(repo_root, "implementations", "ruby", "exe", "ruby-tungsten") }

  example_paths = Dir[
    File.expand_path("../../../doc/examples/**/*.w", __dir__),
    File.expand_path("../../../doc/rosetta_code/**/*.w", __dir__)
  ].sort.select { |path| File.read(path).include?("## expect") }

  example_paths.each do |path|
    relative_path = path.delete_prefix("#{File.expand_path("../../..", __dir__)}/")

    it "matches embedded expectations for #{relative_path}" do
      expectation, stdout, stderr, status = Tungsten::ExampleExpectations.run_file(
        path,
        cli_path:,
        repo_root:
      )

      skip(expectation.skip_reason) if expectation.skip?

      expect(status.exitstatus).to eq(expectation.exit_status)
      expect(Tungsten::ExampleExpectations.output_mismatch(expectation.stdout, stdout)).to be_nil
      expect(Tungsten::ExampleExpectations.output_mismatch(expectation.stderr, stderr)).to be_nil
    end
  end
end

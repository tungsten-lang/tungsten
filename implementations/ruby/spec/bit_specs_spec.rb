# frozen_string_literal: true

require_relative "spec_helper"
require "tmpdir"
require "open3"

# Bridge spec: exercises the tungsten-json bit's SIMD walker end-to-end
# through compile + run, asserting that `JSON.parse` dispatches through
# the class vtable to the bit's .parse after Phase 0c removed the
# intrinsic bypass and Phase 2a wrote the walker body.
#
# The bit's own describe/it-style spec at bits/tungsten-json/spec/json_spec.w
# is not yet wired to any runner, so this file takes its place for
# automated regression coverage until a proper bit-spec harness lands.
RSpec.describe "tungsten-json bit walker" do
  PROJECT_ROOT_BIT = File.expand_path("../../..", __dir__)
  TUNGSTEN_BOOTSTRAP_BIT = File.join(PROJECT_ROOT_BIT, "bin/tungsten-compiler")
  RUNTIME_ARCHIVE_BIT = File.join(PROJECT_ROOT_BIT, "runtime/runtime.a")
  JSON_SIMD_C = File.join(PROJECT_ROOT_BIT, "bits/tungsten-json/runtime/json_simd.c")

  before(:all) do
    skip "compiled compiler not available" unless File.executable?(TUNGSTEN_BOOTSTRAP_BIT)
    skip "json_simd.c not found" unless File.exist?(JSON_SIMD_C)
  end

  around do |example|
    skip "compiled compiler not available" unless File.executable?(TUNGSTEN_BOOTSTRAP_BIT)
    Dir.mktmpdir("bit-json-run") do |dir|
      @tmpdir = dir
      example.run
    end
  end

  it "parses an empty object via the walker" do
    expect(run_json_fixture('{}')).to eq("{}")
  end

  it "parses an empty array via the walker" do
    expect(run_json_fixture('\[\]')).to eq("[]")
  end

  it "parses a simple object via the walker" do
    out = run_json_fixture('{\"a\":1}')
    expect(out).to eq("{a: 1}")
  end

  it "parses an integer array via the walker" do
    source = <<~W
      use tungsten-json
      r = JSON.parse("\\[1,2,3\\]")
      << r.size.to_s
      << r[0].to_s
      << r[1].to_s
      << r[2].to_s
    W
    out = compile_and_run("int_array.w", source)
    expect(out).to eq("3\n1\n2\n3\n")
  end

  it "parses nested object with string and number values via the walker" do
    source = <<~W
      use tungsten-json
      r = JSON.parse("{\\"name\\":\\"Alice\\",\\"age\\":30}")
      << r["name"]
      << r["age"].to_s
    W
    out = compile_and_run("nested_obj.w", source)
    expect(out).to eq("Alice\n30\n")
  end

  it "parses literals (true, false, null) via the walker" do
    source = <<~W
      use tungsten-json
      << JSON.parse("true").to_s
      << JSON.parse("false").to_s
      << JSON.parse("null").to_s
    W
    out = compile_and_run("literals.w", source)
    expect(out).to eq("true\nfalse\n\n")
  end

  private

  def run_json_fixture(escaped_json)
    source = <<~W
      use tungsten-json
      << JSON.parse("#{escaped_json}").to_s
    W
    compile_and_run("fixture.w", source).chomp
  end

  def compile_and_run(name, source)
    source_path = File.join(@tmpdir, name)
    bin_path = File.join(@tmpdir, File.basename(name, ".w"))
    File.write(source_path, source)

    env = {"TUNGSTEN_C_INCLUDES" => JSON_SIMD_C}
    compile_args = [TUNGSTEN_BOOTSTRAP_BIT, "compile", source_path, "--out", bin_path]
    compile_args += ["--runtime", RUNTIME_ARCHIVE_BIT] if File.exist?(RUNTIME_ARCHIVE_BIT)

    _out, err, status = Open3.capture3(env, *compile_args, chdir: PROJECT_ROOT_BIT)
    expect(status.success?).to be(true), err

    run_out, run_err, run_status = Open3.capture3(bin_path)
    expect(run_status.success?).to be(true), run_err
    run_out
  end
end

# frozen_string_literal: true

require_relative "spec_helper"
require "tmpdir"
require "open3"

RSpec.describe "Class extension / re-open semantics" do
  PROJECT_ROOT_EXT = File.expand_path("../../..", __dir__)
  TUNGSTEN_BOOTSTRAP_EXT = File.join(PROJECT_ROOT_EXT, "bin/tungsten-compiler")
  RUNTIME_ARCHIVE_EXT = File.join(PROJECT_ROOT_EXT, "runtime/runtime.a")

  before(:all) do
    skip "compiled compiler not available" unless File.executable?(TUNGSTEN_BOOTSTRAP_EXT)
  end

  around do |example|
    skip "compiled compiler not available" unless File.executable?(TUNGSTEN_BOOTSTRAP_EXT)
    Dir.mktmpdir("class-extension-run") do |dir|
      @tmpdir = dir
      example.run
    end
  end

  it "honors last-wins when a class is re-opened with an overlapping static method" do
    out = compile_and_run("reopen_override.w", <<~W)
      + Foo
        -> .shared
          "A"

      + Foo
        -> .shared
          "B"

      << Foo.shared
    W

    expect(out).to eq("B\n")
  end

  it "preserves non-overlapping methods across a re-open" do
    out = compile_and_run("reopen_additive.w", <<~W)
      + Foo
        -> .a
          "a"

      + Foo
        -> .b
          "b"

      << Foo.a
      << Foo.b
    W

    expect(out).to eq("a\nb\n")
  end

  it "applies last-wins across a chain of three overrides" do
    out = compile_and_run("reopen_chain.w", <<~W)
      + Foo
        -> .n
          1

      + Foo
        -> .n
          2

      + Foo
        -> .n
          3

      << Foo.n.to_s
    W

    expect(out).to eq("3\n")
  end

  it "keeps methods from both halves of a reopen available" do
    out = compile_and_run("reopen_mixed.w", <<~W)
      + Foo
        -> .first
          "A.first"
        -> .shared
          "A.shared"

      + Foo
        -> .second
          "B.second"
        -> .shared
          "B.shared"

      << Foo.first
      << Foo.second
      << Foo.shared
    W

    expect(out).to eq("A.first\nB.second\nB.shared\n")
  end

  private

  def compile_and_run(name, source)
    source_path = File.join(@tmpdir, name)
    bin_path = File.join(@tmpdir, File.basename(name, ".w"))
    File.write(source_path, source)

    compile_args = [TUNGSTEN_BOOTSTRAP_EXT, "compile", source_path, "--out", bin_path]
    compile_args += ["--runtime", RUNTIME_ARCHIVE_EXT] if File.exist?(RUNTIME_ARCHIVE_EXT)

    _out, err, status = Open3.capture3(*compile_args, chdir: PROJECT_ROOT_EXT)
    expect(status.success?).to be(true), err

    run_out, run_err, run_status = Open3.capture3(bin_path)
    expect(run_status.success?).to be(true), run_err
    run_out
  end
end

# frozen_string_literal: true

require_relative "spec_helper"
require "tmpdir"
require "open3"

RSpec.describe "primitive type-class inline caching" do
  around do |example|
    skip "compiled compiler not available" unless File.executable?(TUNGSTEN_BOOTSTRAP)

    Dir.mktmpdir("primitive-type-cache") do |dir|
      @tmpdir = dir
      example.run
    end
  end

  it "keeps Closure#call's dedicated path after a Closure reopen and cache reuse" do
    out = compile_and_run("closure_call_priority.w", <<~W)
      + Closure
        -> call
          "wrong"

      -> invoke_twice(callback)
        i = 0
        while i < 2
          << callback.call
          i += 1

      callback = -> ()
        "right"
      invoke_twice(callback)
    W

    expect(out).to eq("right\nright\n")
  end

  it "keeps UUID#to_s's formatter ahead of a reopened type-class method" do
    out = compile_and_run("uuid_to_s_priority.w", <<~W)
      + UUID
        -> to_s
          "wrong"

      -> render_twice(value)
        i = 0
        while i < 2
          << value.to_s
          i += 1

      render_twice(UUID.parse("550e8400-e29b-41d4-a716-446655440000"))
    W

    expect(out).to eq("550e8400-e29b-41d4-a716-446655440000\n" * 2)
  end

  it "dispatches native Integer leaf methods exactly across i48 promotion" do
    out = compile_and_run("integer_leaf_boundaries.w", <<~W)
      -> boundary(value)
        << value.prev
        << value.succ
        << value.next
        << value.zero?
        << value.even?
        << value.odd?
        << value.negative?
        << value.positive?
        << value.sq

      boundary(140_737_488_355_327)
      boundary(-140_737_488_355_328)
    W

    expect(out).to eq(<<~OUT)
      140737488355326
      140737488355328
      140737488355328
      false
      false
      true
      false
      true
      19807040628565802923409276929
      -140737488355329
      -140737488355327
      -140737488355327
      false
      true
      false
      true
      false
      19807040628566084398385987584
    OUT
  end

  private

  def compile_and_run(name, source)
    source_path = File.join(@tmpdir, name)
    bin_path = File.join(@tmpdir, File.basename(name, ".w"))
    File.write(source_path, source)

    _out, err, status = Open3.capture3(
      TUNGSTEN_BOOTSTRAP, "compile", source_path, "--out", bin_path,
      chdir: PROJECT_ROOT
    )
    expect(status.success?).to be(true), err

    out, run_err, run_status = Open3.capture3(bin_path)
    expect(run_status.success?).to be(true), run_err
    out
  end
end

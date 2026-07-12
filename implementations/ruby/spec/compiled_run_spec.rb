# frozen_string_literal: true

require_relative "spec_helper"
require "tmpdir"
require "open3"

RSpec.describe "Compiled run" do
  around do |example|
    Dir.mktmpdir("compiled-run") do |dir|
      @tmpdir = dir
      example.run
    end
  end

  it "runs a small range loop through the compiled interpreter" do
    path = write_program("range_sum.w", <<~W)
      sum = 0
      1..10 ->
        sum = sum + i
      << sum
    W

    out, err, status = Open3.capture3(TUNGSTEN_BIN, "run", path, chdir: PROJECT_ROOT)

    expect(status.success?).to be(true), err
    expect(out).to eq("55\n")
  end

  it "evaluates call arguments inside loops through the compiled interpreter" do
    path = write_program("array_push_loop.w", <<~W)
      arr = []
      bi = 0
      while bi < 2
        arr.push(bi)
        bi += 1
      << arr
    W

    out, err, status = Open3.capture3(TUNGSTEN_BIN, "run", path, chdir: PROJECT_ROOT)

    expect(status.success?).to be(true), err
    expect(out).to eq("[0, 1]\n")
  end

  it "autoloads native Date methods for literal eval and preserves calendar edges" do
    source = <<~W
      leap_day = 2024-02-29
      << leap_day.year
      << leap_day.month
      << leap_day.day
      << leap_day.quarter
      << leap_day.leap?
      << leap_day.days_in_month
      << leap_day.day_of_year
      << leap_day.cwday
      << leap_day.cweek
      << leap_day.jd
      << 2016-01-01.cweek
      << 2016-01-01.cwyear
      << 2018-12-31.cweek
      << 2018-12-31.cwyear
    W

    out, err, status = Open3.capture3(TUNGSTEN_BIN, "-e", source, chdir: PROJECT_ROOT)

    expect(status.success?).to be(true), err
    expect(out).to eq("2024\n2\n29\n1\ntrue\n29\n60\n4\n9\n2460370\n53\n2015\n1\n2019\n")
  end

  it "keeps Hash keys and values on their semantic dispatch path" do
    source = <<~W
      h = {a: 1}
      << h.keys
      << h.values
    W

    out, err, status = Open3.capture3(TUNGSTEN_BIN, "-e", source, chdir: PROJECT_ROOT)

    expect(status.success?).to be(true), err
    expect(out).to eq("[a]\n[1]\n")
  end

  it "reports a formatted runtime error when compiled run raises" do
    path = write_program("undefined_method.w", <<~W)
      1.nope
    W

    _out, err, status = Open3.capture3(TUNGSTEN_BIN, "run", path, chdir: PROJECT_ROOT)

    expect(status.success?).to be(false)
    expect(err).to include("error: undefined method 'nope' for 1")
    expect(err).to include("undefined_method.w")
    expect(err).not_to include("__wy_")
  end

  it "runs an unbounded range that exits via break" do
    # `0..` is a right-unbounded range (no upper bound). The loop iterates
    # forever until `break` exits. The block has no explicit param, so the
    # iteration variable is picked up as a free var (`i` here).
    path = write_program("unbounded_range.w", <<~W)
      0.. ->
        i == 10 ? break : << i
    W

    out, err, status = Open3.capture3(TUNGSTEN_BIN, "run", path, chdir: PROJECT_ROOT)

    expect(status.success?).to be(true), err
    expect(out).to eq("0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n")
  end

  private

  def write_program(name, source)
    path = File.join(@tmpdir, name)
    File.write(path, source)
    path
  end
end

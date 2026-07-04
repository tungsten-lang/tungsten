require_relative "spec_helper"
require "stringio"

# Golden-file pin on the flame.w FLAME_MODE=display analyzer output.
#
# This gates upcoming refactors (analyzer extraction to analyzer.w, runner port
# to pure Tungsten). The fixture is a synthetic folded-stacks file designed to
# exercise: idle-stack filtering (kevent/poll), infrastructure-frame skip
# (start/main/dyld), library-prefix and offset-suffix cleanup, auto-focus on a
# function above 40% self time, caller-side breakdown, and category bars.
#
# To refresh the golden after intentional output changes, run:
#   UPDATE_FLAME_GOLDEN=1 bundle exec rspec spec/flame_analyzer_spec.rb

RSpec.describe "FlameAnalyzer.display" do
  ANALYZER_W = File.join(PROJECT_ROOT, "bits/tungsten-flame/lib/analyzer.w")
  FIXTURE    = File.join(__dir__, "fixtures/flame/synthetic.folded")
  GOLDEN     = File.join(__dir__, "fixtures/flame/synthetic.expected.txt")

  def run_analyzer(stacks_path:, top_n: 10, category_set: "general", focus: "")
    saved_stdout = $stdout
    captured = StringIO.new
    $stdout = captured

    src = File.read(ANALYZER_W) +
          "\nTungsten:Flame:FlameAnalyzer.display(#{stacks_path.inspect}, #{top_n}, " \
          "#{category_set.inspect}, #{focus.inspect}, false)\n"

    begin
      Tungsten::Interpreter.new.run(src, file_path: ANALYZER_W)
    rescue SystemExit
    ensure
      $stdout = saved_stdout
    end

    captured.string
  end

  it "produces the expected breakdown for the synthetic fixture" do
    actual = run_analyzer(stacks_path: FIXTURE)

    if ENV["UPDATE_FLAME_GOLDEN"] == "1"
      File.write(GOLDEN, actual)
      skip "golden file refreshed at #{GOLDEN}"
    end

    expect(File.exist?(GOLDEN)).to be(true),
      "Golden file missing. Generate with: UPDATE_FLAME_GOLDEN=1 bundle exec rspec #{__FILE__}"
    expect(actual).to eq(File.read(GOLDEN))
  end
end

# Pure-Tungsten replacement for inferno-collapse-perf. Test by concatenating
# the module source with a tiny driver that reads a fixture and prints the
# collapsed result, then comparing to a checked-in golden file.

RSpec.describe "PerfScript.collapse" do
  PERF_SCRIPT_W = File.join(PROJECT_ROOT, "bits/tungsten-flame/lib/perf_script.w")
  PERF_INPUT    = File.join(__dir__, "fixtures/flame/perf_script_input.txt")
  PERF_GOLDEN   = File.join(__dir__, "fixtures/flame/perf_script_expected.folded")

  def run_collapse(input_path)
    src = File.read(PERF_SCRIPT_W) +
          "\n\n<< Tungsten:Flame:PerfScript.collapse(read_file(argv()[0]))\n"

    saved_argv = ARGV.dup
    saved_stdout = $stdout
    captured = StringIO.new
    $stdout = captured
    ARGV.replace([input_path])
    begin
      Tungsten::Interpreter.new.run(src, file_path: PERF_SCRIPT_W)
    rescue SystemExit
    ensure
      $stdout = saved_stdout
      ARGV.replace(saved_argv)
    end
    captured.string
  end

  it "collapses perf-script output into folded format" do
    actual = run_collapse(PERF_INPUT)

    if ENV["UPDATE_FLAME_GOLDEN"] == "1"
      File.write(PERF_GOLDEN, actual)
      skip "perf-script golden refreshed at #{PERF_GOLDEN}"
    end

    expect(actual).to eq(File.read(PERF_GOLDEN))
  end
end

# tungsten-flame counter-mode specs — pure logic only (no profiling, no atos).
#
# Run: bin/tungsten bits/tungsten-flame/spec/counter_rates_spec.w

use spec
use builder
use perf_script
use xctrace_xml
use sidemap
use counter_rates

describe "XctraceXml.collapse_counter_profile" ->
  it "attributes per-row deltas to target-thread stacks and resolves refs" ->
    rows = []
    rows.push("<row><sample-time id=\"1\" fmt=\"00:00.1\">100</sample-time><thread id=\"2\" fmt=\"Main Thread (0x1) (prog, pid: 42)\"><tid id=\"3\" fmt=\"0x1\">1</tid></thread><tagged-backtrace id=\"8\" fmt=\"x\"><backtrace id=\"9\"><frame id=\"10\" name=\"0xf1\" addr=\"0xf1\"/><frame id=\"11\" name=\"0xa1\" addr=\"0xa0\"/></backtrace></tagged-backtrace><pmc-events id=\"12\" fmt=\"x\">100 50 10</pmc-events></row>")
    rows.push("<row><thread id=\"20\" fmt=\"Main Thread (0x2) (other, pid: 43)\"/><tagged-backtrace ref=\"8\"/><pmc-events id=\"21\" fmt=\"x\">7 7 7</pmc-events></row>")
    rows.push("<row><thread ref=\"2\"/><tagged-backtrace ref=\"8\"/><pmc-events id=\"22\" fmt=\"x\">50 25 5</pmc-events></row>")
    xml = rows.join("")
    metrics = ["instructions", "cycles", "L1"]
    result = Tungsten:Flame:XctraceXml.collapse_counter_profile(xml, "", "", metrics, "(prog, pid:")
    expect(result["instructions"]).to eq("0xa0;0xf1 150")
    expect(result["cycles"]).to eq("0xa0;0xf1 75")
    expect(result["L1"]).to eq("0xa0;0xf1 15")

  it "returns empty folded text for metrics with no positive deltas" ->
    xml = "<row><thread id=\"2\" fmt=\"T (0x1) (prog, pid: 42)\"/><tagged-backtrace id=\"8\" fmt=\"x\"><backtrace id=\"9\"><frame id=\"10\" name=\"0xf1\" addr=\"0xf1\"/></backtrace></tagged-backtrace><pmc-events id=\"12\" fmt=\"x\">5 0</pmc-events></row>"
    result = Tungsten:Flame:XctraceXml.collapse_counter_profile(xml, "", "", ["a", "b"], "(prog, pid:")
    expect(result["a"]).to eq("0xf1 5")
    expect(result["b"]).to eq("")

describe "XctraceXml.row_thread_is_target" ->
  it "memoizes inline thread definitions and resolves later refs" ->
    memo = {}
    def_row = "<thread id=\"5\" fmt=\"W (0x3) (prog, pid: 7)\"/><pmc-events id=\"1\" fmt=\"x\">1</pmc-events>"
    ref_row = "<thread ref=\"5\"/><pmc-events id=\"2\" fmt=\"x\">1</pmc-events>"
    expect(Tungsten:Flame:XctraceXml.row_thread_is_target(def_row, memo, "(prog, pid:")).to eq(true)
    expect(Tungsten:Flame:XctraceXml.row_thread_is_target(ref_row, memo, "(prog, pid:")).to eq(true)
    expect(Tungsten:Flame:XctraceXml.row_thread_is_target("<thread ref=\"9\"/>", memo, "(prog, pid:")).to eq(false)

describe "XctraceXml.row_profile_stack" ->
  it "reads frame addr attributes leaf-first and resolves backtrace refs" ->
    memo = {}
    def_row = "<tagged-backtrace id=\"3\" fmt=\"x\"><backtrace id=\"4\"><frame id=\"5\" name=\"0xleaf\" addr=\"0x10\"/><frame id=\"6\" name=\"0xcaller\" addr=\"0x20\"/></backtrace></tagged-backtrace>"
    frames = Tungsten:Flame:XctraceXml.row_profile_stack(def_row, memo)
    expect(frames.join(",")).to eq("0x10,0x20")
    ref_frames = Tungsten:Flame:XctraceXml.row_profile_stack("<tagged-backtrace ref=\"3\"/>", memo)
    expect(ref_frames.join(",")).to eq("0x10,0x20")
    expect(Tungsten:Flame:XctraceXml.row_profile_stack("<pmc-events id=\"1\">1</pmc-events>", memo)).to be_nil

describe "CounterRates" ->
  it "computes per-function IPC and misses per kilo-instruction" ->
    folded = {}
    folded["instructions"] = "main;hot 9000\nmain;cold 1000"
    folded["cycles"] = "main;hot 3000\nmain;cold 1000"
    folded["L1-dcache-load-misses"] = "main;hot 90\nmain;cold 1"
    out = Tungsten:Flame:CounterRates.report(folded, 5, false)
    expect(out.include?("hot")).to eq(true)
    # hot: IPC 9000/3000 = 3.00, L1d 90*100000/9000 = 10.00/KI, 90.0% of inst
    expect(out.include?("3.00")).to eq(true)
    expect(out.include?("10.00")).to eq(true)
    expect(out.include?("90.0")).to eq(true)
    # totals: IPC 10000/4000 = 2.50
    expect(out.include?("2.50")).to eq(true)
    expect(out.include?("L1d-ld/KI")).to eq(true)

  it "returns empty output without the instructions and cycles metrics" ->
    folded = {}
    folded["L1-dcache-load-misses"] = "main;hot 90"
    expect(Tungsten:Flame:CounterRates.report(folded, 5, false)).to eq("")

  it "normalizes leaves the way the analyzer does" ->
    sc = Tungsten:Flame:CounterRates.self_counts("a;libfoo`bar + 3 10\nb;libfoo`bar 5")
    expect(sc[0]["bar"]).to eq(15)
    expect(sc[1]).to eq(15)

  it "formats fixed-point columns" ->
    expect(Tungsten:Flame:CounterRates.fmt_x100(250)).to eq("2.50")
    expect(Tungsten:Flame:CounterRates.fmt_x100(5)).to eq("0.05")
    expect(Tungsten:Flame:CounterRates.fmt_x10(900)).to eq("90.0")

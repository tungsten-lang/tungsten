# tungsten-flame parsing specs — pure logic only (no profiling, no atos).
#
# Run: bin/tungsten bits/tungsten-flame/spec/parsing_spec.w

use spec_helper
use builder
use perf_script
use xctrace_xml

describe "PerfScript" ->
  it "collapses perf script samples into sorted folded stacks" ->
    lines = []
    lines.push("prog 100 c1 1.0: 1 cycles:")
    lines.push("\t0000f0 leaf_fn+0x10 (/bin/prog)")
    lines.push("\t0000e0 mid_fn+0x20 (/bin/prog)")
    lines.push("\t0000d0 main+0x30 (/bin/prog)")
    lines.push("")
    lines.push("prog 100 c1 1.1: 1 cycles:")
    lines.push("\t0000f0 leaf_fn+0x10 (/bin/prog)")
    lines.push("\t0000e0 mid_fn+0x20 (/bin/prog)")
    lines.push("\t0000d0 main+0x30 (/bin/prog)")
    lines.push("")
    lines.push("prog 100 c1 1.2: 1 cycles:")
    lines.push("\t0000a0 other_fn+0x1 (/bin/prog)")
    lines.push("\t0000d0 main+0x30 (/bin/prog)")
    folded = Tungsten:Flame:PerfScript.collapse(lines.join("\n"))
    expect(folded).to eq("main;mid_fn;leaf_fn 2\nmain;other_fn 1")

  it "strips the +offset suffix from frames" ->
    expect(Tungsten:Flame:PerfScript.parse_frame("0000f0 do_work+0x44 (/bin/prog)")).to eq("do_work")

  it "keeps frames that have no offset" ->
    expect(Tungsten:Flame:PerfScript.parse_frame("0000f0 do_work (/bin/prog)")).to eq("do_work")

  it "returns nil for malformed frames" ->
    expect(Tungsten:Flame:PerfScript.parse_frame("justanaddress")).to be_nil

describe "XctraceXml" ->
  it "converts decimal strings to hex" ->
    expect(Tungsten:Flame:XctraceXml.dec_to_hex("255")).to eq("ff")
    expect(Tungsten:Flame:XctraceXml.dec_to_hex("4096")).to eq("1000")
    expect(Tungsten:Flame:XctraceXml.dec_to_hex("0")).to eq("0")

  it "parses pmc-events values from a row" ->
    row = "<pmc-events id=\"7\" fmt=\"x\">100 10 100 10</pmc-events>"
    vals = Tungsten:Flame:XctraceXml.extract_pmc_values(row)
    expect(vals.join(",")).to eq("100,10,100,10")

  it "builds leaf-first stacks from inline kperf-bt blocks" ->
    xml = "<kperf-bt id=\"4\" fmt=\"PC:0x1000, 2 frames\"><text-addresses id=\"5\" fmt=\"frag 1\">8192 0</text-addresses><text-address id=\"6\" fmt=\"0x1000\">4096</text-address></kperf-bt>"
    bts = Tungsten:Flame:XctraceXml.parse_kperf_bts(xml)
    expect(bts["4"].join(";")).to eq("0x1000;0x2000")

  it "resolves shared text-addresses refs and drops a duplicated PC" ->
    parts = []
    parts.push("<kperf-bt id=\"4\" fmt=\"PC:0x1000, 2 frames\"><text-addresses id=\"5\" fmt=\"frag 1\">8192 0</text-addresses><text-address id=\"6\" fmt=\"0x1000\">4096</text-address></kperf-bt>")
    parts.push("<kperf-bt id=\"8\" fmt=\"PC:0x1004, 2 frames\"><text-addresses ref=\"5\"/><text-address id=\"9\" fmt=\"0x1004\">4100</text-address></kperf-bt>")
    parts.push("<kperf-bt id=\"20\" fmt=\"PC:0x2000, 1 frames\"><text-addresses id=\"21\" fmt=\"frag 2\">8192</text-addresses><text-address id=\"22\" fmt=\"0x2000\">8192</text-address></kperf-bt>")
    bts = Tungsten:Flame:XctraceXml.parse_kperf_bts(parts.join(""))
    expect(bts["8"].join(";")).to eq("0x1004;0x2000")
    expect(bts["20"].join(";")).to eq("0x2000")

  it "folds per-metric counter deltas across rows" ->
    rows = []
    rows.push("<row><thread id=\"2\" fmt=\"t\">t</thread><core id=\"3\" fmt=\"c\">0</core><thread-state id=\"1\" fmt=\"Running\">Running</thread-state><kperf-bt id=\"4\" fmt=\"PC:0x1000, 2 frames\"><text-addresses id=\"5\" fmt=\"frag 1\">8192 0</text-addresses><text-address id=\"6\" fmt=\"0x1000\">4096</text-address></kperf-bt><pmc-events id=\"7\" fmt=\"x\">100 10</pmc-events></row>")
    rows.push("<row><thread ref=\"2\"/><core ref=\"3\"/><thread-state ref=\"1\"/><kperf-bt id=\"8\" fmt=\"PC:0x1004, 2 frames\"><text-addresses ref=\"5\"/><text-address id=\"9\" fmt=\"0x1004\">4100</text-address></kperf-bt><pmc-events id=\"10\" fmt=\"x\">250 17</pmc-events></row>")
    rows.push("<row><thread ref=\"2\"/><core ref=\"3\"/><thread-state ref=\"1\"/><kperf-bt ref=\"8\"/><pmc-events id=\"11\" fmt=\"x\">400 20</pmc-events></row>")
    metrics = Tungsten:Flame:XctraceXml.collapse_counters(rows.join(""), "", "", ["m1", "m2"])
    expect(metrics["m1"]).to eq("0x2000;0x1004 300")
    expect(metrics["m2"]).to eq("0x2000;0x1004 10")

spec_summary

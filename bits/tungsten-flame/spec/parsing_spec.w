# tungsten-flame parsing specs — pure logic only (no profiling, no atos).
#
# Run: bin/tungsten bits/tungsten-flame/spec/parsing_spec.w

use spec
use builder
use perf_script
use xctrace_xml
use sample_collapse
use sidemap
use analyzer
use flame_svg
use flame_diff
use speedscope
use trace_event
use hot_frames
use flame_filter
use flame_threshold

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

  it "converts hex strings to integers" ->
    expect(Tungsten:Flame:XctraceXml.hex_to_int("0xff")).to eq(255)
    expect(Tungsten:Flame:XctraceXml.hex_to_int("0x180000000")).to eq(6442450944)
    expect(Tungsten:Flame:XctraceXml.hex_to_int("nothex")).to eq(0)

  it "classifies only dyld-shared-region addresses as shared-cache" ->
    expect(Tungsten:Flame:XctraceXml.shared_cache_addr?("0x18f09d834")).to eq(true)
    expect(Tungsten:Flame:XctraceXml.shared_cache_addr?("0x100d3750c")).to eq(false)
    expect(Tungsten:Flame:XctraceXml.shared_cache_addr?("0xfffffe0007ab1234")).to eq(false)

  it "parses atos system lines into lib-backtick-symbol frames" ->
    expect(Tungsten:Flame:XctraceXml.parse_atos_system_line("kevent (in libsystem_kernel.dylib) + 8")).to eq("libsystem_kernel.dylib`kevent")
    expect(Tungsten:Flame:XctraceXml.parse_atos_system_line("_platform_strlen (in libsystem_platform.dylib) + 0")).to eq("libsystem_platform.dylib`_platform_strlen")
    expect(Tungsten:Flame:XctraceXml.parse_atos_system_line("bare_symbol")).to eq("bare_symbol")

  it "returns nil for unresolved atos echoes" ->
    expect(Tungsten:Flame:XctraceXml.parse_atos_system_line("0x18f09d834")).to be_nil
    expect(Tungsten:Flame:XctraceXml.parse_atos_system_line("")).to be_nil

  it "folds per-metric counter deltas across rows" ->
    rows = []
    rows.push("<row><thread id=\"2\" fmt=\"t\">t</thread><core id=\"3\" fmt=\"c\">0</core><thread-state id=\"1\" fmt=\"Running\">Running</thread-state><kperf-bt id=\"4\" fmt=\"PC:0x1000, 2 frames\"><text-addresses id=\"5\" fmt=\"frag 1\">8192 0</text-addresses><text-address id=\"6\" fmt=\"0x1000\">4096</text-address></kperf-bt><pmc-events id=\"7\" fmt=\"x\">100 10</pmc-events></row>")
    rows.push("<row><thread ref=\"2\"/><core ref=\"3\"/><thread-state ref=\"1\"/><kperf-bt id=\"8\" fmt=\"PC:0x1004, 2 frames\"><text-addresses ref=\"5\"/><text-address id=\"9\" fmt=\"0x1004\">4100</text-address></kperf-bt><pmc-events id=\"10\" fmt=\"x\">250 17</pmc-events></row>")
    rows.push("<row><thread ref=\"2\"/><core ref=\"3\"/><thread-state ref=\"1\"/><kperf-bt ref=\"8\"/><pmc-events id=\"11\" fmt=\"x\">400 20</pmc-events></row>")
    metrics = Tungsten:Flame:XctraceXml.collapse_counters(rows.join(""), "", "", ["m1", "m2"])
    expect(metrics["m1"]).to eq("0x2000;0x1004 300")
    expect(metrics["m2"]).to eq("0x2000;0x1004 10")

describe "Sidemap" ->
  it "parses sidemap hash lines into wy-to-display-name mappings" ->
    lines = []
    lines.push("{")
    lines.push("  \"version\": 1,")
    lines.push("  \"hash_algorithm\": \"wyhash64\",")
    lines.push("  \"prefix_hex\": 8,")
    lines.push("  \"hashes\": {")
    lines.push("    \"00d9a18dc98a604e\": {\"symbol\": \"__wy_00d9a18d\", \"originals\": \[{\"symbol\":\"__w_Headers_new__a2\",\"class\":\"Headers\",\"method\":\"new\",\"kind\":\"method\",\"file\":\"/x/forge.w\",\"line\":134,\"arity\":2}\]},")
    lines.push("    \"01bcfc8790459705\": {\"symbol\": \"__wy_01bcfc87\", \"originals\": \[{\"symbol\":\"__w_JSON_S_parse_value_b\",\"class\":\"JSON\",\"method\":\"parse_value_b\",\"kind\":\"static_method\",\"file\":\"/x/forge.w\",\"line\":120,\"arity\":5}\]},")
    lines.push("    \"022044c880693872\": {\"symbol\": \"__wy_022044c8\", \"originals\": \[{\"symbol\":\"__w_Array_count__a2\",\"class\":\"Array\",\"method\":\"count\",\"kind\":\"method\",\"file\":\"/x/forge.w\",\"line\":191,\"arity\":2}, {\"symbol\":\"__w_Hash_count__a2\",\"class\":\"Hash\",\"method\":\"count\",\"kind\":\"method\",\"file\":\"/x/forge.w\",\"line\":191,\"arity\":2}, {\"symbol\":\"__w_Range_count__a2\",\"class\":\"Range\",\"method\":\"count\",\"kind\":\"method\",\"file\":\"/x/forge.w\",\"line\":191,\"arity\":2}\]},")
    lines.push("    \"fd278cb267950fc0\": {\"symbol\": \"__wy_fd278cb2\", \"originals\": \[{\"symbol\":\"__w_fib\",\"class\":null,\"method\":\"fib\",\"kind\":\"method_def\",\"file\":\"/x/fib.w\",\"line\":2,\"arity\":1}\]},")
    lines.push("    \"07dc0c19683a2a50\": {\"symbol\": \"__wy_07dc0c19\", \"originals\": \[{\"symbol\":\"__block_112\",\"class\":\"Array\",\"method\":\"tally\",\"kind\":\"block\",\"file\":\"/x/forge.w\",\"line\":null,\"arity\":1}\]},")
    lines.push("    \"00f6361434a6a2aa\": {\"symbol\": \"__wy_00f63614\", \"originals\": \[{\"symbol\":\"__w_Integer_next__a1\",\"class\":\"Integer\",\"method\":\"next\",\"kind\":\"method\",\"file\":\"/x/forge.w\",\"line\":29,\"arity\":1}, {\"symbol\":\"__w_Integer_succ__a1\",\"class\":\"Integer\",\"method\":\"succ\",\"kind\":\"method\",\"file\":\"/x/forge.w\",\"line\":19,\"arity\":1}\]}")
    lines.push("  }")
    lines.push("}")
    map = Tungsten:Flame:Sidemap.parse(lines.join("\n"))
    expect(map["__wy_00d9a18d"]).to eq("Headers#new")
    expect(map["__wy_01bcfc87"]).to eq("JSON.parse_value_b")
    expect(map["__wy_022044c8"]).to eq("Array#count (+2)")
    expect(map["__wy_fd278cb2"]).to eq("fib")
    expect(map["__wy_07dc0c19"]).to eq("block in Array#tally")
    expect(map["__wy_00f63614"]).to eq("Integer#next (+1)")

  it "parses empty text to an empty map" ->
    expect(Tungsten:Flame:Sidemap.parse("").keys().size()).to eq(0)

  it "rewrites mapped wy frames in folded text and keeps counts" ->
    map = {}
    map["__wy_aa"] = "fib"
    folded = "main;__wy_aa;w_add 10\nmain;__wy_bb 5"
    expect(Tungsten:Flame:Sidemap.rewrite_folded(folded, map)).to eq("main;fib;w_add 10\nmain;__wy_bb 5")

  it "returns folded text unchanged for an empty map" ->
    expect(Tungsten:Flame:Sidemap.rewrite_folded("a;b 3", {})).to eq("a;b 3")

describe "FlameAnalyzer" ->
  it "drops sub-threshold hex-only leaves and tallies them" ->
    pairs = []
    pairs.push(["main", 1500])
    pairs.push(["0x18f09d834", 400])
    pairs.push(["w_add", 1])
    pairs.push(["0x18ef015d0", 1])
    pairs.push(["0x1900aa000", 1])
    res = Tungsten:Flame:FlameAnalyzer.noise_split(pairs, 2000)
    kept = res[0]
    expect(kept.size()).to eq(3)
    expect(kept[0][0]).to eq("main")
    expect(kept[1][0]).to eq("0x18f09d834")
    expect(kept[2][0]).to eq("w_add")
    expect(res[1]).to eq(2)

  it "keeps hex leaves at or above 0.1%" ->
    pairs = []
    pairs.push(["0xbeef", 2])
    res = Tungsten:Flame:FlameAnalyzer.noise_split(pairs, 2000)
    expect(res[0].size()).to eq(1)
    expect(res[1]).to eq(0)

describe "FlameSvg" ->
  it "merges shared prefixes and accumulates inclusive counts" ->
    root = Tungsten:Flame:FlameSvg.build_tree("main;a;b 10\nmain;a;c 5\nmain;d 3")
    expect(root[:count]).to eq(18)
    expect(root[:children].size()).to eq(1)
    main = root[:children][0]
    expect(main[:name]).to eq("main")
    expect(main[:count]).to eq(18)
    a = Tungsten:Flame:FlameSvg.find_child(main, "a")
    expect(a[:count]).to eq(15)
    d = Tungsten:Flame:FlameSvg.find_child(main, "d")
    expect(d[:count]).to eq(3)

  it "reports the deepest stack depth" ->
    root = Tungsten:Flame:FlameSvg.build_tree("main;a;b 10\nmain;d 3")
    expect(Tungsten:Flame:FlameSvg.max_depth(root)).to eq(2)

  it "ignores lines with no positive count" ->
    root = Tungsten:Flame:FlameSvg.build_tree("main;a 5\nbroken\nmain;b 0")
    expect(root[:count]).to eq(5)

  it "formats percentages with one decimal via integer math" ->
    expect(Tungsten:Flame:FlameSvg.fmt_pct(1, 3)).to eq("33.3")
    expect(Tungsten:Flame:FlameSvg.fmt_pct(18, 18)).to eq("100.0")

  it "encodes sample-space bounds as parseable fractions" ->
    expect(Tungsten:Flame:FlameSvg.frac_str(0, 18)).to eq("0")
    expect(Tungsten:Flame:FlameSvg.frac_str(18, 18)).to eq("1")
    expect(Tungsten:Flame:FlameSvg.frac_str(15, 18)).to eq("0.833333")

  it "escapes XML metacharacters" ->
    expect(Tungsten:Flame:FlameSvg.xml_escape("a<b>&\"c")).to eq("a&lt;b&gt;&amp;&quot;c")

  it "truncates labels to the frame width" ->
    expect(Tungsten:Flame:FlameSvg.fit_label("main", 1180)).to eq("main")
    expect(Tungsten:Flame:FlameSvg.fit_label("verylongfunctionname", 100)).to eq("verylongfun..")
    expect(Tungsten:Flame:FlameSvg.fit_label("x", 8)).to eq("")

  it "gives each frame name a stable warm color" ->
    c1 = Tungsten:Flame:FlameSvg.color_for("main")
    c2 = Tungsten:Flame:FlameSvg.color_for("main")
    expect(c1).to eq(c2)
    expect(c1.starts_with?("rgb(")).to eq(true)

  it "renders a self-contained interactive SVG document" ->
    svg = Tungsten:Flame:FlameSvg.render("main;a;b 10\nmain;a;c 5\nmain;d 3", "T")
    expect(svg.include?("<svg xmlns=\"http://www.w3.org/2000/svg\"")).to eq(true)
    expect(svg.include?("</svg>")).to eq(true)
    expect(svg.include?("<title>main (18 samples, 100.0%)</title>")).to eq(true)
    expect(svg.include?("<title>b (10 samples, 55.5%)</title>")).to eq(true)
    expect(svg.include?("data-name=\"a\"")).to eq(true)
    expect(svg.include?("<script>")).to eq(true)
    expect(svg.include?("function zoom(")).to eq(true)

  it "escapes markup in the title and shows the sample total" ->
    svg = Tungsten:Flame:FlameSvg.render("main 4", "P<0> & Q")
    expect(svg.include?(">P&lt;0&gt; &amp; Q</text>")).to eq(true)
    expect(svg.include?("4 samples</text>")).to eq(true)

  it "handles empty input without crashing" ->
    svg = Tungsten:Flame:FlameSvg.render("", "Empty")
    expect(svg.include?("no samples")).to eq(true)
    expect(svg.include?("</svg>")).to eq(true)

describe "FlameDiff" ->
  it "parses folded text into a stack map with a total" ->
    p = Tungsten:Flame:FlameDiff.parse_folded("main;a 3\nmain;b 2")
    expect(p[:total]).to eq(5)
    expect(p[:map]["main;a"]).to eq(3)
    expect(p[:map]["main;b"]).to eq(2)

  it "sums duplicate stacks and ignores non-positive or countless lines" ->
    p = Tungsten:Flame:FlameDiff.parse_folded("a 2\na 3\nb 0\njustaframe")
    expect(p[:total]).to eq(5)
    expect(p[:map]["a"]).to eq(5)
    expect(p[:map].keys().size()).to eq(1)

  it "computes inclusive per-frame counts, counting recursion once" ->
    incl = Tungsten:Flame:FlameDiff.frame_inclusive("main;a;a;b 4\nmain;c 6")
    expect(incl["main"]).to eq(10)
    expect(incl["a"]).to eq(4)
    expect(incl["b"]).to eq(4)
    expect(incl["c"]).to eq(6)

  it "diffs two profiles into signed per-stack deltas" ->
    d = Tungsten:Flame:FlameDiff.diff("main;a 10\nmain;b 5", "main;a 4\nmain;c 7")
    expect(d).to eq("main;a -6\nmain;b -5\nmain;c 7")

  it "normalizes before-counts to the after total when diffing" ->
    d = Tungsten:Flame:FlameDiff.diff_normalized("x 50\ny 50", "x 200")
    expect(d).to eq("x 100\ny -100")

  it "ranks frames by absolute inclusive change, hottest first" ->
    ranked = Tungsten:Flame:FlameDiff.rank_frames("main;slow 10\nmain;fast 90", "main;slow 60\nmain;fast 40", true)
    expect(ranked[0][0]).to eq("fast")
    expect(ranked[0][3]).to eq(-50)
    expect(ranked[1][0]).to eq("slow")
    expect(ranked[1][3]).to eq(50)
    expect(ranked[2][0]).to eq("main")
    expect(ranked[2][3]).to eq(0)

  it "reports regressions and improvements in a plain-text summary" ->
    r = Tungsten:Flame:FlameDiff.report("main;slow 10\nmain;fast 90", "main;slow 60\nmain;fast 40", 5, false)
    expect(r.include?("Differential Profile")).to eq(true)
    expect(r.include?("before 100")).to eq(true)
    expect(r.include?("after 100")).to eq(true)
    expect(r.include?("Regressed (hotter)")).to eq(true)
    expect(r.include?("+50.0%")).to eq(true)
    expect(r.include?("Improved (cooler)")).to eq(true)
    expect(r.include?("-50.0%")).to eq(true)

  it "marks an empty section (none) and survives a zero-total baseline" ->
    r = Tungsten:Flame:FlameDiff.report("", "a 5", 5, false)
    expect(r.include?("before 0")).to eq(true)
    expect(r.include?("after 5")).to eq(true)
    expect(r.include?("Improved (cooler)")).to eq(true)
    expect(r.include?("(none)")).to eq(true)

describe "Speedscope" ->
  it "exports a valid speedscope sampled profile document" ->
    ss = Tungsten:Flame:Speedscope.export("main;a;b 10\nmain;a;c 5\nmain;d 3", "demo")
    expect(ss.include?("\"$schema\":\"https://www.speedscope.app/file-format-schema.json\"")).to eq(true)
    expect(ss.include?("\"type\":\"sampled\"")).to eq(true)
    expect(ss.include?("\"unit\":\"none\"")).to eq(true)

  it "builds a deduped, sorted, first-seen frame table" ->
    ss = Tungsten:Flame:Speedscope.export("main;a;b 10\nmain;a;c 5\nmain;d 3", "demo")
    expect(ss.include?("\"frames\":\[{\"name\":\"main\"},{\"name\":\"a\"},{\"name\":\"b\"},{\"name\":\"c\"},{\"name\":\"d\"}\]")).to eq(true)

  it "emits index-array samples with parallel weights, root to leaf" ->
    ss = Tungsten:Flame:Speedscope.export("main;a;b 10\nmain;a;c 5\nmain;d 3", "demo")
    expect(ss.include?("\"samples\":\[\[0,1,2\],\[0,1,3\],\[0,4\]\]")).to eq(true)
    expect(ss.include?("\"weights\":\[10,5,3\]")).to eq(true)

  it "sums the total sample weight into endValue" ->
    ss = Tungsten:Flame:Speedscope.export("main;a;b 10\nmain;a;c 5\nmain;d 3", "demo")
    expect(ss.include?("\"endValue\":18")).to eq(true)

  it "sums duplicate stacks into one weighted sample" ->
    ss = Tungsten:Flame:Speedscope.export("foo;bar 3\nfoo;bar 2\nfoo;baz 5", "d")
    expect(ss.include?("\"samples\":\[\[0,1\],\[0,2\]\]")).to eq(true)
    expect(ss.include?("\"weights\":\[5,5\]")).to eq(true)
    expect(ss.include?("\"endValue\":10")).to eq(true)

  it "JSON-escapes quotes and backslashes in frame names" ->
    ss = Tungsten:Flame:Speedscope.export("a\"b\\c 4", "t")
    expect(ss.include?("{\"name\":\"a\\\"b\\\\c\"}")).to eq(true)

  it "ignores lines with no positive count" ->
    ss = Tungsten:Flame:Speedscope.export("main;a 5\nbroken\nmain;b 0", "x")
    expect(ss.include?("\"endValue\":5")).to eq(true)
    expect(ss.include?("\"frames\":\[{\"name\":\"main\"},{\"name\":\"a\"}\]")).to eq(true)

  it "handles empty input as a valid empty profile" ->
    ss = Tungsten:Flame:Speedscope.export("", "empty")
    expect(ss.include?("\"frames\":\[\]")).to eq(true)
    expect(ss.include?("\"samples\":\[\]")).to eq(true)
    expect(ss.include?("\"weights\":\[\]")).to eq(true)
    expect(ss.include?("\"endValue\":0")).to eq(true)

describe "HotFrames" ->
  it "computes self (leaf-only) counts per frame" ->
    map = Tungsten:Flame:HotFrames.parse_folded("main;a;b 10\nmain;a;c 5\nmain;d 3")[:map]
    sc = Tungsten:Flame:HotFrames.self_from_map(map)
    expect(sc["b"]).to eq(10)
    expect(sc["c"]).to eq(5)
    expect(sc["d"]).to eq(3)
    expect(sc.has_key?("main")).to eq(false)
    expect(sc.has_key?("a")).to eq(false)

  it "computes inclusive (total) counts, counting recursion once" ->
    map = Tungsten:Flame:HotFrames.parse_folded("main;a;a;b 4\nmain;c 6")[:map]
    incl = Tungsten:Flame:HotFrames.inclusive_from_map(map)
    expect(incl["main"]).to eq(10)
    expect(incl["a"]).to eq(4)
    expect(incl["b"]).to eq(4)
    expect(incl["c"]).to eq(6)

  it "sums duplicate stacks so concatenated runs aggregate" ->
    p = Tungsten:Flame:HotFrames.parse_folded("f;g 2\nf;g 3")
    expect(p[:total]).to eq(5)
    expect(p[:map]["f;g"]).to eq(5)

  it "ranks frames by total desc, showing self alongside" ->
    ranked = Tungsten:Flame:HotFrames.rank("main;a;b 10\nmain;a;c 5\nmain;d 3")
    expect(ranked[0][0]).to eq("main")
    expect(ranked[0][1]).to eq(0)
    expect(ranked[0][2]).to eq(18)
    expect(ranked[1][0]).to eq("a")
    expect(ranked[1][2]).to eq(15)
    expect(ranked[2][0]).to eq("b")
    expect(ranked[2][1]).to eq(10)
    expect(ranked[2][2]).to eq(10)

  it "breaks equal-total ties by self descending" ->
    ranked = Tungsten:Flame:HotFrames.rank("r;hi;lo 8\nr;hi 2")
    expect(ranked[0][0]).to eq("hi")
    expect(ranked[0][1]).to eq(2)
    expect(ranked[0][2]).to eq(10)
    expect(ranked[1][0]).to eq("r")
    expect(ranked[1][1]).to eq(0)
    expect(ranked[1][2]).to eq(10)
    expect(ranked[2][0]).to eq("lo")

  it "breaks equal-total-and-self ties by frame name ascending" ->
    ranked = Tungsten:Flame:HotFrames.rank("x;p 5\nx;q 5")
    expect(ranked[0][0]).to eq("x")
    expect(ranked[1][0]).to eq("p")
    expect(ranked[2][0]).to eq("q")

  it "normalizes offset and library-prefix decorations" ->
    expect(Tungsten:Flame:HotFrames.normalize_frame("libsystem_kernel.dylib`kevent + 8")).to eq("kevent")
    expect(Tungsten:Flame:HotFrames.normalize_frame("do_work + 44")).to eq("do_work")
    expect(Tungsten:Flame:HotFrames.normalize_frame("Array#count")).to eq("Array#count")

  it "merges decorated variants of one symbol into a single frame" ->
    map = Tungsten:Flame:HotFrames.parse_folded("a`foo + 8;bar 2\nfoo;bar 3")[:map]
    incl = Tungsten:Flame:HotFrames.inclusive_from_map(map)
    expect(incl["foo"]).to eq(5)
    expect(incl["bar"]).to eq(5)

  it "renders a flat self-vs-total report with percentages" ->
    r = Tungsten:Flame:HotFrames.report("main;a;b 10\nmain;a;c 5\nmain;d 3", 3, false)
    expect(r.include?("Hot Frames")).to eq(true)
    expect(r.include?("18 samples")).to eq(true)
    expect(r.include?("TOTAL")).to eq(true)
    expect(r.include?("SELF")).to eq(true)
    expect(r.include?("FUNCTION")).to eq(true)
    expect(r.include?("100.0%")).to eq(true)
    expect(r.include?("main")).to eq(true)

  it "handles empty input as a no-samples report" ->
    r = Tungsten:Flame:HotFrames.report("", 5, false)
    expect(r.include?("no samples")).to eq(true)
    expect(Tungsten:Flame:HotFrames.rank("").size()).to eq(0)

describe "FlameFilter" ->
  it "matches a stack when any frame contains the pattern as a substring" ->
    expect(Tungsten:Flame:FlameFilter.stack_matches("main;parse;lex", "parse")).to eq(true)
    expect(Tungsten:Flame:FlameFilter.stack_matches("main;libsystem_kernel.dylib`kevent + 8", "kevent")).to eq(true)
    expect(Tungsten:Flame:FlameFilter.stack_matches("main;run;emit", "parse")).to eq(false)

  it "keeps only whole stacks passing through the pattern (grep/include)" ->
    kept = Tungsten:Flame:FlameFilter.keep("main;parse;lex 10\nmain;run;gc 5\nmain;parse;fold 3", "parse")
    expect(kept).to eq("main;parse;fold 3\nmain;parse;lex 10")

  it "drops whole stacks touching the pattern (prune/exclude)" ->
    pruned = Tungsten:Flame:FlameFilter.drop("main;parse;lex 10\nmain;run;gc 5\nmain;parse;gc 3", "gc")
    expect(pruned).to eq("main;parse;lex 10")

  it "re-roots the profile at the pattern and sums the subtree (zoom)" ->
    focused = Tungsten:Flame:FlameFilter.focus("main;a;parse;lex 10\nmain;b;parse;fold 4\nmain;run 7", "parse")
    expect(focused).to eq("parse;fold 4\nparse;lex 10")

  it "sums distinct callers that collapse onto the same subtree when zooming" ->
    focused = Tungsten:Flame:FlameFilter.focus("root;x;work 6\nroot;y;work 4", "work")
    expect(focused).to eq("work 10")

  it "aggregates duplicate stacks and sorts output deterministically" ->
    kept = Tungsten:Flame:FlameFilter.keep("z;hot 2\na;hot 3\nz;hot 4", "hot")
    expect(kept).to eq("a;hot 3\nz;hot 6")

  it "chains include then exclude, subtree winning over grep, via apply" ->
    text = "main;parse;lex 10\nmain;parse;gc 5\nmain;run;gc 8"
    expect(Tungsten:Flame:FlameFilter.apply(text, "parse", "gc", "")).to eq("main;parse;lex 10")
    expect(Tungsten:Flame:FlameFilter.apply(text, "", "", "parse")).to eq("parse;gc 5\nparse;lex 10")
    expect(Tungsten:Flame:FlameFilter.apply(text, "parse", "", "run")).to eq("run;gc 8")

  it "counts non-empty folded stacks and treats empty input as zero" ->
    expect(Tungsten:Flame:FlameFilter.stack_count("a;b 3\nc;d 4")).to eq(2)
    expect(Tungsten:Flame:FlameFilter.stack_count("")).to eq(0)
    expect(Tungsten:Flame:FlameFilter.keep("", "x")).to eq("")

describe "SampleCollapse" ->
  it "extracts a symbol name from decorated sample and spindump frames" ->
    expect(Tungsten:Flame:SampleCollapse.extract_symbol("start (in dyld) + 462  \[0x18a0b5f50\]")).to eq("start")
    expect(Tungsten:Flame:SampleCollapse.extract_symbol("start + 462 (dyld + 25627) \[0x100\]")).to eq("start")
    expect(Tungsten:Flame:SampleCollapse.extract_symbol("Thread_2b0e   DispatchQueue_1: com.apple.main-thread  (serial)")).to eq("Thread_2b0e")
    expect(Tungsten:Flame:SampleCollapse.extract_symbol("plainname")).to eq("plainname")

  it "measures indent depth from leading spaces and tree markers" ->
    expect(Tungsten:Flame:SampleCollapse.leading_indent("    + 2276 start")).to eq(6)
    expect(Tungsten:Flame:SampleCollapse.leading_indent("2276 main")).to eq(0)
    expect(Tungsten:Flame:SampleCollapse.leading_indent("        30 work")).to eq(8)

  it "recognizes only non-empty decimal count runs" ->
    expect(Tungsten:Flame:SampleCollapse.all_digits?("2276")).to eq(true)
    expect(Tungsten:Flame:SampleCollapse.all_digits?("22a")).to eq(false)
    expect(Tungsten:Flame:SampleCollapse.all_digits?("")).to eq(false)
    expect(Tungsten:Flame:SampleCollapse.is_digit?("7")).to eq(true)
    expect(Tungsten:Flame:SampleCollapse.is_digit?("")).to eq(false)

  it "collapses a sample call graph into per-leaf folded stacks" ->
    lines = []
    lines.push("Call graph:")
    lines.push("    2276 Thread_2b0e   DispatchQueue_1: com.apple.main-thread  (serial)")
    lines.push("    + 2276 start (in dyld) + 462  \[0x1\]")
    lines.push("    +   2276 main (in demo) + 40  \[0x2\]")
    lines.push("    +     2000 compute (in demo) + 20  \[0x3\]")
    lines.push("    +       2000 inner (in demo) + 8  \[0x4\]")
    lines.push("    +     276 helper (in demo) + 12  \[0x5\]")
    lines.push("Total number in stack (recursive counted multiple, when >=5):")
    folded = Tungsten:Flame:SampleCollapse.collapse(lines.join("\n"))
    expect(folded).to eq("Thread_2b0e;start;main;compute;inner 2000\nThread_2b0e;start;main;helper 276")

  it "derives self time as inclusive minus children, emitting parent-self stacks" ->
    lines = []
    lines.push("  12 main (in x) + 0  \[0x1\]")
    lines.push("    6 foo (in x) + 0  \[0x2\]")
    lines.push("    4 bar (in x) + 0  \[0x3\]")
    folded = Tungsten:Flame:SampleCollapse.collapse(lines.join("\n"))
    expect(folded).to eq("main 2\nmain;bar 4\nmain;foo 6")

  it "separates threads as distinct folded roots" ->
    lines = []
    lines.push("Call graph:")
    lines.push("    30 Thread_1   DispatchQueue_1: main  (serial)")
    lines.push("    + 30 start (in dyld) + 0  \[0x1\]")
    lines.push("    +   30 work (in x) + 0  \[0x2\]")
    lines.push("    5 Thread_2")
    lines.push("    + 5 spin (in y) + 0  \[0x3\]")
    lines.push("Total number in stack (recursive counted multiple, when >=5):")
    folded = Tungsten:Flame:SampleCollapse.collapse(lines.join("\n"))
    expect(folded).to eq("Thread_1;start;work 30\nThread_2;spin 5")

  it "stops at trailing sections and treats empty input as no stacks" ->
    lines = []
    lines.push("Call graph:")
    lines.push("  5 foo (in x) + 0  \[0x1\]")
    lines.push("Binary Images:")
    lines.push("  0x1 - 0x2 demo (in demo)")
    expect(Tungsten:Flame:SampleCollapse.collapse(lines.join("\n"))).to eq("foo 5")
    expect(Tungsten:Flame:SampleCollapse.collapse("")).to eq("")

describe "FlameThreshold" ->
  it "parses percentage strings into tenths of a percent" ->
    expect(Tungsten:Flame:FlameThreshold.parse_pct_x10("2")).to eq(20)
    expect(Tungsten:Flame:FlameThreshold.parse_pct_x10("0.5")).to eq(5)
    expect(Tungsten:Flame:FlameThreshold.parse_pct_x10("1.5")).to eq(15)
    expect(Tungsten:Flame:FlameThreshold.parse_pct_x10("10")).to eq(100)
    expect(Tungsten:Flame:FlameThreshold.parse_pct_x10("")).to eq(0)
    expect(Tungsten:Flame:FlameThreshold.parse_pct_x10(nil)).to eq(0)

  it "computes inclusive weight for every call-tree node path" ->
    map = Tungsten:Flame:FlameThreshold.parse_folded("main;a;b 10\nmain;a;c 5\nmain;d 3")[:map]
    incl = Tungsten:Flame:FlameThreshold.prefix_inclusive(map)
    expect(incl["main"]).to eq(18)
    expect(incl["main;a"]).to eq(15)
    expect(incl["main;a;b"]).to eq(10)
    expect(incl["main;a;c"]).to eq(5)
    expect(incl["main;d"]).to eq(3)

  it "folds sub-threshold frames into an (other) node under their parent" ->
    folded = Tungsten:Flame:FlameThreshold.collapse("a;b;c 10\na;b;d 3\na;b;e 2\na;f 1", 200)
    expect(folded).to eq("a;(other) 1\na;b;(other) 5\na;b;c 10")

  it "preserves the grand total when folding (nothing dropped)" ->
    folded = Tungsten:Flame:FlameThreshold.collapse("a;b;c 10\na;b;d 3\na;b;e 2\na;f 1", 200)
    expect(Tungsten:Flame:FlameThreshold.parse_folded(folded)[:total]).to eq(16)

  it "folds a sub-threshold root into a bare (other) node" ->
    folded = Tungsten:Flame:FlameThreshold.collapse("big;work 97\ntiny 3", 50)
    expect(folded).to eq("(other) 3\nbig;work 97")

  it "keeps everything at a zero threshold, re-aggregated and sorted" ->
    folded = Tungsten:Flame:FlameThreshold.collapse("z;b 2\na;b 3\nz;b 4", 0)
    expect(folded).to eq("a;b 3\nz;b 6")

  it "treats empty input as no stacks" ->
    expect(Tungsten:Flame:FlameThreshold.collapse("", 200)).to eq("")

describe "TraceEvent" ->
  it "merges shared prefixes into a tree with inclusive counts" ->
    root = Tungsten:Flame:TraceEvent.build_tree("main;a;b 10\nmain;a;c 5\nmain;d 3")
    expect(root[:count]).to eq(18)
    expect(root[:children].size()).to eq(1)
    main = root[:children][0]
    expect(main[:name]).to eq("main")
    expect(main[:count]).to eq(18)
    a = Tungsten:Flame:TraceEvent.find_child(main, "a")
    expect(a[:count]).to eq(15)
    d = Tungsten:Flame:TraceEvent.find_child(main, "d")
    expect(d[:count]).to eq(3)

  it "ignores lines with no positive count" ->
    root = Tungsten:Flame:TraceEvent.build_tree("main;a 5\nbroken\nmain;b 0")
    expect(root[:count]).to eq(5)

  it "exports a valid Trace Event Format object with a timeline unit" ->
    te = Tungsten:Flame:TraceEvent.export("main;a;b 10\nmain;a;c 5\nmain;d 3", "demo")
    expect(te.include?("\"displayTimeUnit\":\"ns\"")).to eq(true)
    expect(te.include?("\"traceEvents\":\[")).to eq(true)
    expect(te.starts_with?("{")).to eq(true)
    expect(te.ends_with?("}")).to eq(true)

  it "labels the process and thread tracks with metadata events" ->
    te = Tungsten:Flame:TraceEvent.export("main 4", "demo")
    expect(te.include?("{\"name\":\"process_name\",\"ph\":\"M\",\"pid\":1,\"args\":{\"name\":\"demo\"}}")).to eq(true)
    expect(te.include?("{\"name\":\"thread_name\",\"ph\":\"M\",\"pid\":1,\"tid\":1,\"args\":{\"name\":\"samples\"}}")).to eq(true)

  it "lays merged frames out as nested slices left-to-right by inclusive count" ->
    te = Tungsten:Flame:TraceEvent.export("main;a;b 10\nmain;a;c 5\nmain;d 3", "demo")
    expect(te.include?("{\"name\":\"main\",\"ph\":\"X\",\"ts\":0,\"dur\":18,\"pid\":1,\"tid\":1}")).to eq(true)
    expect(te.include?("{\"name\":\"a\",\"ph\":\"X\",\"ts\":0,\"dur\":15,\"pid\":1,\"tid\":1}")).to eq(true)
    expect(te.include?("{\"name\":\"b\",\"ph\":\"X\",\"ts\":0,\"dur\":10,\"pid\":1,\"tid\":1}")).to eq(true)
    expect(te.include?("{\"name\":\"c\",\"ph\":\"X\",\"ts\":10,\"dur\":5,\"pid\":1,\"tid\":1}")).to eq(true)
    expect(te.include?("{\"name\":\"d\",\"ph\":\"X\",\"ts\":15,\"dur\":3,\"pid\":1,\"tid\":1}")).to eq(true)

  it "lays sibling roots out consecutively along the timeline" ->
    te = Tungsten:Flame:TraceEvent.export("a 3\nb 2", "t")
    expect(te.include?("{\"name\":\"a\",\"ph\":\"X\",\"ts\":0,\"dur\":3,\"pid\":1,\"tid\":1}")).to eq(true)
    expect(te.include?("{\"name\":\"b\",\"ph\":\"X\",\"ts\":3,\"dur\":2,\"pid\":1,\"tid\":1}")).to eq(true)

  it "sums duplicate stacks into one slice span" ->
    te = Tungsten:Flame:TraceEvent.export("foo;bar 3\nfoo;bar 2\nfoo;baz 5", "d")
    expect(te.include?("{\"name\":\"foo\",\"ph\":\"X\",\"ts\":0,\"dur\":10,\"pid\":1,\"tid\":1}")).to eq(true)
    expect(te.include?("{\"name\":\"bar\",\"ph\":\"X\",\"ts\":0,\"dur\":5,\"pid\":1,\"tid\":1}")).to eq(true)
    expect(te.include?("{\"name\":\"baz\",\"ph\":\"X\",\"ts\":5,\"dur\":5,\"pid\":1,\"tid\":1}")).to eq(true)

  it "JSON-escapes quotes and backslashes in frame names" ->
    te = Tungsten:Flame:TraceEvent.export("a\"b\\c 4", "t")
    expect(te.include?("{\"name\":\"a\\\"b\\\\c\",\"ph\":\"X\"")).to eq(true)

  it "handles empty input as a valid slice-less trace" ->
    te = Tungsten:Flame:TraceEvent.export("", "empty")
    expect(te.include?("\"traceEvents\":\[")).to eq(true)
    expect(te.include?("\"ph\":\"X\"")).to eq(false)
    expect(te.ends_with?("}")).to eq(true)

spec_summary

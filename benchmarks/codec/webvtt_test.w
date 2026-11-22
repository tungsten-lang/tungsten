# webvtt_test — unit checks for core/codec/text/webvtt plus the W3C web-platform-tests WebVTT parsing suite.
#
#   bin/tungsten benchmarks/codec/webvtt_test.w -- [wpt-root] [work-dir]
#
# wpt-root is a checkout holding webvtt/parsing (a sparse clone of web-platform-tests/wpt).
# Cue-text tests (cue-text-parsing/tests/*.html) are compared natively: the cue's node tree is
# serialized the way WPT's test_serializer prints getCueAsHTML(). File-parsing tests carry
# JavaScript assertions, so each parsed track is dumped as TextTrackCue-like JSON and the
# assertions run against it in node's vm module (a fresh context holding only cues + asserts).

use core/codec/text/webvtt

SCRATCH = "benchmarks/codec/corpus"
VT_STATS = [0, 0]

-> check(name, ok)
  if ok
    VT_STATS[0] = VT_STATS[0] + 1
  else
    VT_STATS[1] = VT_STATS[1] + 1
    << "FAIL unit: [name]"
  ok

-> eq(name, got, want)
  ok = got == want
  check(name, ok)
  << "  got:  [vt_show(got)]\n  want: [vt_show(want)]" if !ok
  ok

-> near(a, b)
  d = a - b
  d = ~0.0 - d if d < ~0.0
  d < ~0.01

# Printable form of a value: strings quoted with control characters escaped.
-> vt_show(v)
  return v.to_s if !v.is_a?(String)
  "\"" + vt_json_safe(v) + "\""

# JSON.encode leaves U+0001..U+001F other than \b\t\n\f\r raw (bugs/json-encode-control-chars);
# raw control bytes can only sit inside strings, so escape them after encoding.
-> vt_json_safe(s)
  sb = StringBuffer()
  st = 0
  i = 0
  while i < s.size
    b = s.byte_at(i)
    if b < 32
      sb.append(s.slice(st, i - st)) if i > st
      hx = "0123456789abcdef"
      sb.append("\\u00" + hx.slice(b / 16, 1) + hx.slice(b % 16, 1))
      st = i + 1
    i += 1
  sb.append(s.slice(st, s.size - st)) if s.size > st
  sb.to_s

MEASURE = ->(s, size, bold, italic) s.size * size * ~0.5

# ---- serializer matching WPT's test_serializer over getCueAsHTML() ----

-> vt_tag(n)
  k = n.kind
  return "span" if k == :c || k == :v || k == :lang
  k.to_s

-> vt_ser(node, depth, out)
  sp = " " * (2 * depth - 1)
  if node.kind == :text
    out.push("|" + sp + "\"" + node.text + "\"")
  elsif node.kind == :timestamp
    out.push("|" + sp + "<?timestamp " + vtt_format_time(node.time) + ">")
  else
    out.push("|" + sp + "<" + vt_tag(node) + ">")
    asp = " " * (2 * depth + 1)
    out.push("|" + asp + "class=\"" + node.classes.join(" ") + "\"") if node.classes.size > 0
    out.push("|" + asp + "lang=\"" + node.annotation + "\"") if node.kind == :lang
    out.push("|" + asp + "title=\"" + node.annotation + "\"") if node.kind == :v
    node.children.each ->(c)
      vt_ser(c, depth + 1, out)
  out

-> vt_serialize(root)
  out = ["#document-fragment"]
  root.children.each ->(c)
    vt_ser(c, 1, out)
  out.join("\n")

-> vt_hexval(b)
  return b - 48 if b >= 48 && b <= 57
  return b - 55 if b >= 65 && b <= 70
  return b - 87 if b >= 97 && b <= 102
  -1

-> vt_unpercent(s)
  b = ByteArray.new(0)
  i = 0
  while i < s.size
    c = s.byte_at(i)
    if c == 37 && i + 2 < s.size + 0 && vt_hexval(s.byte_at(i + 1)) >= 0 && vt_hexval(s.byte_at(i + 2)) >= 0
      b.push(vt_hexval(s.byte_at(i + 1)) * 16 + vt_hexval(s.byte_at(i + 2)))
      i += 3
    else
      b.push(c)
      i += 1
  return "" if b.size == 0
  ccall("w_string_from_byte_array", b)

# Value of `key:'...'` starting the search at pos: [value, end] or nil.
-> vt_field(s, key, pos)
  k = s.index(key + ":'", pos)
  return nil if k == nil
  a = k + key.size + 2
  e = s.index("'", a)
  [s.slice(a, e - a), e + 1]

-> vt_tree_of(input)
  tr = vtt_parse("WEBVTT\n\n00:00.000 --> 00:01.000\n" + input)
  return "(no cue)" if tr.cues.size == 0
  vt_serialize(tr.cues[0].nodes)

-> run_cue_text_tests(dir)
  pass = 0
  fail = 0
  Dir.children(dir).sort.each ->(f)
    if f.ends_with?(".html")
      src = File.read(dir + "/" + f)
      pos = 0
      while true
        nm = vt_field(src, "name", pos)
        break if nm == nil
        inp = vt_field(src, "input", nm[1])
        exp = vt_field(src, "expected", inp[1])
        pos = exp[1]
        input = vt_unpercent(inp[0])
        want = vt_unpercent(exp[0])
        got = vt_tree_of(input)
        if got == want
          pass += 1
        else
          fail += 1
          << "FAIL cue-text [f] [nm[0]]: input [vt_show(input)]\n  got:  [vt_show(got)]\n  want: [vt_show(want)]"
  [pass, fail]

# ---- TextTrackCue-like JSON for the file-parsing assertions ----

VT_ALIGN = {start: "start", center: "center", end: "end", left: "left", right: "right"}
VT_PALIGN = {auto: "auto", line_left: "line-left", center: "center", line_right: "line-right"}

-> vt_region_json(r)
  h = {}
  h["id"] = r.id
  h["width"] = r.width
  h["lines"] = r.lines
  h["regionAnchorX"] = r.anchor_x
  h["regionAnchorY"] = r.anchor_y
  h["viewportAnchorX"] = r.viewport_x
  h["viewportAnchorY"] = r.viewport_y
  h["scroll"] = r.scroll == :up ? "up" : ""
  h

-> vt_track_json(tr)
  regs = tr.region_list.map(->(r) vt_region_json(r))
  cues = []
  tr.cues.each ->(c)
    ri = nil
    k = 0
    while k < tr.region_list.size
      ri = k if tr.region_list[k] == c.region
      k += 1
    h = {}
    h["id"] = c.id
    h["startTime"] = c.start
    h["endTime"] = c.end
    h["text"] = c.text
    h["pauseOnExit"] = false
    h["vertical"] = c.vertical == :horizontal ? "" : c.vertical.to_s
    h["snapToLines"] = c.snap
    h["line"] = c.line == nil ? "auto" : c.line
    h["lineAlign"] = c.line_align.to_s
    h["position"] = c.position == nil ? "auto" : c.position
    h["positionAlign"] = VT_PALIGN[c.position_align]
    h["size"] = c.size
    h["align"] = VT_ALIGN[c.align]
    h["region"] = ri
    cues.push(h)
  [cues, regs]

-> vt_between(s, a, b, from)
  i = s.index(a, from)
  return nil if i == nil
  i += a.size
  j = s.index(b, i)
  return nil if j == nil
  s.slice(i, j - i)

VT_HARNESS = [
  "const fs = require('fs'), vm = require('vm');",
  "const data = JSON.parse(fs.readFileSync(process.argv.at(2), 'utf8'));",
  "function same(x, y) { if (y !== y) return x !== x; if (x === 0 && y === 0) return 1 / x === 1 / y; return x === y; }",
  "function fail(m) { throw new Error(m); }",
  "let pass = 0, nfail = 0;",
  "for (const t of data) {",
  "  const regions = t.regions.map(r => Object.assign({}, r));",
  "  const cues = t.cues.map(c => { const o = Object.assign({}, c); o.region = c.region === null ? null : regions.at(c.region); return o; });",
  "  const ctx = { cues, document: { styleSheets: \[] },",
  "    assert_equals: (a, b, m) => { if (!same(a, b)) fail('assert_equals got ' + JSON.stringify(a) + ' want ' + JSON.stringify(b) + ' ' + (m || '')); },",
  "    assert_not_equals: (a, b, m) => { if (same(a, b)) fail('assert_not_equals ' + (m || '')); },",
  "    assert_true: (a, m) => { if (a !== true) fail('assert_true ' + (m || '')); },",
  "    assert_false: (a, m) => { if (a !== false) fail('assert_false ' + (m || '')); },",
  "    assert_unreached: (m) => fail('unreached ' + (m || '')) };",
  "  try {",
  "    if (t.expect_error) { if (t.ok) fail('track should fail to load'); }",
  "    else { if (!t.ok) fail('track failed to load'); vm.runInNewContext(t.prelude + '\\n' + t.js, ctx, { timeout: 5000 }); }",
  "    pass++;",
  "  } catch (e) { nfail++; console.log('FAIL ' + t.name + ': ' + e.message); }",
  "}",
  "console.log('TOTAL ' + pass + ' ' + nfail);"
].join("\n")

-> run_file_tests(root, work)
  tdir = root + "/tests"
  items = []
  Dir.children(tdir).sort.each ->(f)
    if f.ends_with?(".html")
      src = File.read(tdir + "/" + f)
      vtt = vt_between(src, "src = 'support/", "'", 0)
      js = vt_between(src, "var cues = video.textTracks\[0].cues;\n    {", "\n    }\n    this.done();", 0)
      prelude = ""
      if js == nil && f == "header-regions.html"
        prelude = vt_between(src, "<script>\n", "async_test(", src.index("testharnessreport"))
        js = vt_between(src, "var track = testTrack.track;", "checkCueRegions(track.cues);", 0) + "checkCueRegions(track.cues);"
        js = js.gsub("track.cues", "cues")
      if vtt != nil && js != nil
        tr = vtt_parse(File.read(tdir + "/support/" + vtt))
        cr = vt_track_json(tr)
        items.push({"name" => f, "ok" => tr.ok, "expect_error" => false, "cues" => cr[0], "regions" => cr[1], "js" => js, "prelude" => prelude})
      else
        << "SKIP file-parsing [f] (no assertions found)"
  # signature-invalid.html: every listed file must fail to load
  inv = File.read(root + "/signature-invalid.html")
  pos = 0
  while true
    q = inv.index(".vtt']", pos)
    break if q == nil
    a = q
    while a > 0 && inv.byte_at(a - 1) != 39
      a -= 1
    name = inv.slice(a, q + 4 - a)
    pos = q + 5
    tr = vtt_parse(File.read(root + "/support/" + name))
    items.push({"name" => "signature-invalid " + name, "ok" => tr.ok, "expect_error" => true, "cues" => [], "regions" => [], "js" => "", "prelude" => ""})
  Dir.mkdir_p(work)
  File.write(work + "/dump.json", vt_json_safe(JSON.encode(items)))
  File.write(work + "/harness.js", VT_HARNESS)
  out = OS.capture("node '" + work + "/harness.js' '" + work + "/dump.json' 2>&1")
  pass = 0
  fail = 0
  out.split("\n").each ->(l)
    if l.starts_with?("TOTAL ")
      p = l.split(" ")
      pass = p[1].to_i
      fail = p[2].to_i
    elsif l.size > 0
      << l
  [pass, fail]


# ---- unit checks ----

-> unit_parser
  # signature, BOM, line endings
  check("bare WEBVTT ok", vtt_parse("WEBVTT").ok)
  check("WEBVTT + text ok", vtt_parse("WEBVTT - title\n\n00:01.000 --> 00:02.000\nx").cues.size == 1)
  check("WEBVTTX fails", !vtt_parse("WEBVTTX\n").ok)
  check("lowercase fails", !vtt_parse("webvtt\n").ok)
  check("empty fails", !vtt_parse("").ok)
  bom = 0xFEFF.chr + "WEBVTT\n\n00:01.000 --> 00:02.000\nhi"
  check("BOM skipped", vtt_parse(bom).cues.size == 1)
  check("two BOMs fail", !vtt_parse(0xFEFF.chr + bom).ok)
  crlf = vtt_parse("WEBVTT\r\n\r\n00:01.000 --> 00:02.000\r\na\r\nb\r\n\r\n00:03.000 --> 00:04.000\rc\r\rd")
  eq("CRLF cues", crlf.cues.size, 2)
  eq("CRLF text", crlf.cues[0].text, "a\nb")
  eq("CR text", crlf.cues[1].text, "c")
  # header, NOTE, ids, timestamps
  t = vtt_parse("WEBVTT\nKind: captions\n\nNOTE a comment\nspanning lines\n\nid-1\n00:00:01.250 --> 00:01:02.500\nfirst\n\n01:02:03.004 --> 123:00:00.000\nsecond\n\nNOTE\n\n00:05.000 --> 00:06.000\n")
  eq("cue count", t.cues.size, 3)
  eq("id", t.cues[0].id, "id-1")
  check("start", near(t.cues[0].start, ~1.25))
  check("end mm:ss", near(t.cues[0].end, ~62.5))
  check("hh start", near(t.cues[2].start, ~3723.004))
  check("100+ hours", near(t.cues[2].end, ~442800.0))
  eq("empty cue text", t.cues[1].text, "")
  check("bad minutes rejected", vtt_parse("WEBVTT\n\n00:60.000 --> 00:61.000\nx").cues.size == 0)
  check("short ms rejected", vtt_parse("WEBVTT\n\n00:01.00 --> 00:02.000\nx").cues.size == 0)
  check("arrow on line 3 ends block", vtt_parse("WEBVTT\n\na\nb\n00:01.000 --> 00:02.000\nx").cues.size == 1)
  # sort order
  s = vtt_parse("WEBVTT\n\n00:05.000 --> 00:06.000\nb\n\n00:01.000 --> 00:02.000\na\n\n00:01.000 --> 00:09.000\nlong")
  eq("sorted", s.cues.map(->(c) c.text).join(","), "long,a,b")
  # settings
  c = vtt_parse("WEBVTT\n\n00:01.000 --> 00:02.000 vertical:rl line:-2 position:30%,line-right size:40% align:end\nx").cues[0]
  eq("vertical", c.vertical, :rl)
  check("line -2", c.line == ~-2.0 && c.snap)
  check("position", near(c.position, ~30.0) && c.position_align == :line_right)
  check("size", near(c.size, ~40.0))
  eq("align end", c.align, :end)
  c = vtt_parse("WEBVTT\n\n00:01.000 --> 00:02.000 line:25%,center vertical:lr align:left\nx").cues[0]
  check("line %", near(c.line, ~25.0) && !c.snap && c.line_align == :center)
  eq("vertical lr", c.vertical, :lr)
  eq("align left", c.align, :left)
  c = vtt_parse("WEBVTT\n\n00:01.000 --> 00:02.000 line:1.5 position:101% size:-5% align:middle vertical:x line:5,bogus\nx").cues[0]
  check("line 1.5", near(c.line, ~1.5))
  check("bad settings ignored", c.position == nil && near(c.size, ~100.0) && c.align == :center && c.vertical == :horizontal)
  c = vtt_parse("WEBVTT\n\n00:01.000 --> 00:02.000 align:right position:10%,center line:0,end\nx").cues[0]
  check("align right / pos center / line end", c.align == :right && c.position_align == :center && c.line_align == :end && c.line == ~0.0)
  # regions and styles
  r = vtt_parse("WEBVTT\n\nSTYLE\n::cue { color: lime }\n\nREGION\nid:fred width:40% lines:3 regionanchor:0%,100%\nviewportanchor:10%,90% scroll:up\n\n00:01.000 --> 00:02.000 region:fred\nx\n\nSTYLE\n::cue { color: red }\n")
  eq("style kept", r.styles.size, 1)
  eq("style text", r.styles[0], "::cue { color: lime }")
  check("STYLE after cue is not a style", r.cues.size == 1)
  reg = r.regions["fred"]
  check("region parsed", reg != nil)
  check("region width", near(reg.width, ~40.0) && reg.lines == 3)
  check("region anchors", near(reg.anchor_y, ~100.0) && near(reg.viewport_x, ~10.0) && near(reg.viewport_y, ~90.0))
  eq("region scroll", reg.scroll, :up)
  check("cue region", r.cues[0].region == reg)
  check("unknown region nil", vtt_parse("WEBVTT\n\n00:01.000 --> 00:02.000 region:nope\nx").cues[0].region == nil)
  # STYLE parsing per the block rules (WPT stylesheets.test, whose JS can't see cue CSS)
  st = vtt_parse("WEBVTT\n\nSTYLE\n::cue(#foo) {\n  width: 20px;\n} /*\nNOTE hello\n00:00:00.000 -- > 00:00:01.000\n*/\n.foo {}\n\n.bar {}\n\nfoo\n00:00:00.000 --> 00:00:01.000\ntext\n\nSTYLE\n::cue(::bar) {}\n\nbar\n00:00:00.000 --> 00:00:01.000\ntext")
  check("stylesheet block", st.styles.size == 1 && st.styles[0].index("NOTE hello") != nil && st.styles[0].index(".foo") != nil)
  eq("stylesheet cues", st.cues.map(->(q) q.id), ["foo", "bar"])
  # errors are recorded, parsing continues
  e = vtt_parse("WEBVTT\n\n00:01.000 --> xx\nbad\n\n00:03.000 --> 00:04.000\ngood")
  check("bad timing skipped", e.cues.size == 1 && e.cues[0].text == "good" && e.errors.size == 1)

-> unit_cue_text
  eq("tags", vt_tree_of("<c.yellow.big>a</c><i>b</i><b>c</b><u>d</u>"), "#document-fragment\n| <span>\n|   class=\"yellow big\"\n|   \"a\"\n| <i>\n|   \"b\"\n| <b>\n|   \"c\"\n| <u>\n|   \"d\"")
  root = vtt_cue_nodes("<v.loud Esme Smith>Hi <lang en-GB>there</lang></v><ruby>漢<rt>kan</rt></ruby>")
  v = root.children[0]
  eq("voice kind", v.kind, :v)
  eq("voice name", v.annotation, "Esme Smith")
  eq("voice class", v.classes, ["loud"])
  eq("lang", v.children[1].annotation, "en-GB")
  eq("ruby", root.children[1].kind, :ruby)
  eq("rt", root.children[1].children[1].kind, :rt)
  eq("rt text", root.children[1].children[1].children[0].text, "kan")
  ts = vtt_cue_nodes("a<00:00:01.500>b<00:02.000>c<1:00.000>d")
  eq("timestamps", ts.children.size, 6)
  check("timestamp time", near(ts.children[1].time, ~1.5) && near(ts.children[3].time, ~2.0))
  eq("entities", vtt_cue_nodes("&amp;&lt;&gt;&lrm;&rlm;&nbsp;&#65;&#x42;&bogus;").plain_text, "&<>" + 0x200E.chr + 0x200F.chr + 0xA0.chr + "AB&bogus;")
  eq("plain", vtt_parse("WEBVTT\n\n00:01.000 --> 00:02.000\n<v Bob>Hello</v> <i>you</i>").cues[0].plain_text, "Hello you")
  eq("unknown tags dropped", vt_tree_of("<font color=red>x</font>"), "#document-fragment\n| \"x\"")
  eq("format time", vtt_format_time(~3723.004), "01:02:03.004")

-> unit_active
  t = vtt_parse("WEBVTT\n\n00:01.000 --> 00:02.000\na\n\n00:01.500 --> 00:03.000\nb")
  eq("active 0.5", vtt_active(t, ~0.5).size, 0)
  eq("active 1.0", vtt_active(t, ~1.0).size, 1)
  eq("active 1.7", vtt_active(t, ~1.7).size, 2)
  eq("active end exclusive", vtt_active(t, ~2.0).map(->(c) c.text), ["b"])

-> lay(src, t)
  tr = vtt_parse(src)
  vtt_layout(vtt_active(tr, t), t, 0, 0, 1000, 500, MEASURE)

-> unit_layout
  # default cue: bottom line, centered, 5vh font, white on 80% black
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000\nHello", ~1.0)
  eq("one box", b.size, 1)
  r = b[0].lines[0][0]
  check("font 5vh", near(r.size, ~25.0))
  check("bottom line", near(b[0].y + b[0].h, ~500.0))
  check("centered", near(r.x + r.w / ~2.0, ~500.0))
  check("colors", r.color == "#ffffff" && r.background == "rgba(0,0,0,0.8)")
  check("baseline inside line", r.y > b[0].y && r.y < b[0].y + b[0].h)
  # auto stacking: second cue goes above the first
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000\nfirst\n\n00:00.000 --> 00:05.000\nsecond", ~1.0)
  check("stack two", b.size == 2 && near(b[1].y + b[1].h, b[0].y))
  # line numbers
  lh = ~30.0
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 line:0\ntop", ~1.0)
  check("line 0 top", near(b[0].y, ~0.0))
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 line:2\nthird", ~1.0)
  check("line 2", near(b[0].y, lh * ~2.0))
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 line:-2\nup one", ~1.0)
  check("line -2", near(b[0].y, ~500.0 - lh * ~2.0))
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 line:-1\ntwo\nlines", ~1.0)
  check("line -1 two lines fits", near(b[0].y, ~500.0 - lh * ~2.0) && b[0].lines.size == 2)
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 line:999\nclamped", ~1.0)
  check("huge line stays inside", b[0].y >= ~0.0 && b[0].y + b[0].h <= ~500.01)
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 line:0\na\n\n00:00.000 --> 00:05.000 line:0\nb", ~1.0)
  check("line 0 collision moves down", near(b[1].y, lh))
  # percentages
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 line:50%,center\nmid", ~1.0)
  check("line 50% center", near(b[0].y + b[0].h / ~2.0, ~250.0))
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 line:10%\nten", ~1.0)
  check("line 10% start", near(b[0].y, ~50.0))
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 line:100%,end\nend", ~1.0)
  check("line 100% end", near(b[0].y + b[0].h, ~500.0))
  # position / size / align
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 position:10%,line-left size:30% align:left\nleft", ~1.0)
  check("box x/w", near(b[0].x, ~100.0) && near(b[0].w, ~300.0))
  check("left aligned", near(b[0].lines[0][0].x, ~100.0))
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 position:90% size:50% align:right\nright", ~1.0)
  check("right: size clamped", near(b[0].x + b[0].w, ~900.0) && near(b[0].w, ~500.0))
  r = b[0].lines[0][0]
  check("right aligned", near(r.x + r.w, ~900.0))
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 align:start\nstart", ~1.0)
  check("align start -> x 0", near(b[0].lines[0][0].x, ~0.0))
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 position:20%\nc", ~1.0)
  check("center position 20% -> size 40", near(b[0].w, ~400.0) && near(b[0].x, ~0.0))
  # wrapping: 12.5px per byte at 25px font, box 200px -> 16 chars per line
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 size:20%\naaaa bbbb cccc dddd eeee", ~1.0)
  check("wrapped lines", b[0].lines.size == 2)
  check("wrapped width", b[0].lines.all?(->(l) l.map(->(q) q.w).sum <= ~200.01))
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 size:10%\nabcdefghijklmnopqrstuvwxyz", ~1.0)
  check("long word broken", b[0].lines.size == 4)
  # styled runs
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000\nplain <b>bold</b> <i>it</i> <u>un</u> <c.yellow>y</c>", ~1.0)
  rs = b[0].lines[0]
  check("bold run", rs.any?(->(q) q.text == "bold" && q.bold))
  check("italic run", rs.any?(->(q) q.text == "it" && q.italic))
  check("underline run", rs.any?(->(q) q.text == "un" && q.underline))
  check("class color", rs.any?(->(q) q.text == "y" && q.color == "#ffff00"))
  check("runs contiguous", rs.size > 1 && near(rs[1].x, rs[0].x + rs[0].w))
  # karaoke timestamps
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000\nnow <00:00:02.000>later <00:00:04.000>much", ~3.0)
  rs = b[0].lines[0]
  check("past not future", rs.any?(->(q) q.text.index("now") != nil && !q.future))
  check("past timestamp text", rs.any?(->(q) q.text.index("later") != nil && !q.future))
  check("future text", rs.any?(->(q) q.text == "much" && q.future && q.color != "#ffffff"))
  # forced line breaks
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000\none\ntwo\nthree", ~1.0)
  eq("explicit lines", b[0].lines.size, 3)
  # regions
  src = "WEBVTT\n\nREGION\nid:r width:40% lines:2 regionanchor:0%,100% viewportanchor:10%,90%\n\n00:00.000 --> 00:05.000 region:r\none\n\n00:00.000 --> 00:05.000 region:r\ntwo\n\n00:00.000 --> 00:05.000 region:r\nthree"
  b = lay(src, ~1.0)
  check("region clips to lines", b.size == 2)
  check("region rect", near(b[0].x, ~100.0) && near(b[0].w, ~400.0) && near(b[1].y + b[1].h, ~450.0))
  check("region newest at bottom", b[1].lines[0][0].text == "three" && b[0].lines[0][0].text == "two")
  b = lay("WEBVTT\n\nREGION\nid:r\n\n00:00.000 --> 00:05.000 region:r line:0\nnot in region", ~1.0)
  check("line setting overrides region", b[0].region == nil && near(b[0].y, ~0.0))
  # vertical
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 vertical:rl\n縦書き", ~1.0)
  check("vertical box", b[0].vertical == :rl && b[0].lines.size == 1 && b[0].lines[0].size == 3)
  check("vertical rl auto at left", near(b[0].x, ~0.0))
  r0 = b[0].lines[0][0]
  r1 = b[0].lines[0][1]
  check("vertical stacks down", r1.y > r0.y && near(r0.x, r1.x))
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 vertical:lr\nab", ~1.0)
  check("vertical lr auto at right", near(b[0].x + b[0].w, ~1000.0))
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000 vertical:rl line:0\nab", ~1.0)
  check("vertical rl line 0 at right", near(b[0].x + b[0].w, ~1000.0))
  # ruby
  b = lay("WEBVTT\n\n00:00.000 --> 00:05.000\n<ruby>base<rt>ann</rt></ruby>", ~1.0)
  rs = b[0].lines[0]
  check("ruby base + annotation", rs.any?(->(q) q.text == "base" && !q.ruby) && rs.any?(->(q) q.text == "ann" && q.ruby && q.size < ~25.0 && q.y < b[0].y + ~10.0))
  # offset video rect
  tr = vtt_parse("WEBVTT\n\n00:00.000 --> 00:05.000 line:0 align:start\nx")
  b = vtt_layout(tr.cues, ~1.0, 50, 70, 400, 200, MEASURE)
  check("offset rect", near(b[0].x, ~50.0) && near(b[0].y, ~70.0) && near(b[0].lines[0][0].size, ~10.0))

-> unit_srt
  t = vtt_srt_parse("1\r\n00:00:01,000 --> 00:00:04,250\r\nHello <i>there</i>\r\nline two\r\n\r\n2\r\n00:00:05,500 --> 00:00:06,000\r\n{\\an8}Top\r\n")
  eq("srt cues", t.cues.size, 2)
  eq("srt id", t.cues[0].id, "1")
  check("srt times", near(t.cues[0].start, ~1.0) && near(t.cues[0].end, ~4.25) && near(t.cues[1].start, ~5.5))
  eq("srt text", t.cues[0].text, "Hello <i>there</i>\nline two")
  eq("srt plain", t.cues[0].plain_text, "Hello there\nline two")
  check("srt an8 -> top", t.cues[1].text == "Top" && t.cues[1].line == ~0.0)


unit_parser()
unit_cue_text()
unit_active()
unit_layout()
unit_srt()
<< "unit checks: [VT_STATS[0]] passed, [VT_STATS[1]] failed"

args = ARGV
root = args.size > 0 ? args[0] : SCRATCH + "/wpt-webvtt"
work = args.size > 1 ? args[1] : "/tmp/webvtt-run"
base = root + "/webvtt/parsing"
if Dir.directory?(base)
  ct = run_cue_text_tests(base + "/cue-text-parsing/tests")
  << "WPT cue-text-parsing: [ct[0]] passed, [ct[1]] failed"
  fp = run_file_tests(base + "/file-parsing", work)
  << "WPT file-parsing: [fp[0]] passed, [fp[1]] failed"
else
  << "WPT checkout not found at [base] (skipped)"

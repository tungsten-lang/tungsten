# Cases for lib/metaflip/gf2/jsonx.w. Python's json module and Ruby's
# JSON.pretty_generate are the oracles: their output for random nested
# structures (fixtures/gf2_support/json/*.jsonl, made by gen_json_goldens.py)
# and for the real lineage manifests must be reproduced byte for byte.
#
# Environment (all optional):
#   GF2_JSON_GOLDENS     directory made by `gen_json_goldens.py DIR 2000`: run that
#                        larger parity set instead of the committed 250 structures
#   GF2_RECORD_HUNT_WORK the record-hunt campaign's work directory (default under
#                        $HOME); its release-0929/ JSON and JSONL files must
#                        round-trip exactly like Python's. Skipped when absent.
#   GF2_RELEASE_DIR      names release-0929 directly
use ../../lib/metaflip/gf2/jsonx

# A String holding exactly these bytes.
-> gf2_bytes_string(values)
  bytes = u8[values.size]
  values.each_with_index -> (b, i)
    bytes[i] = b
  ccall("w_string_from_byte_array", bytes)

# The json.dumps call an option-set name stands for.
-> gf2_dump_with(name, value)
  return Jsonx.dumps(value) if name == "default"
  return Jsonx.dumps(value, indent: 1) if name == "indent1"
  return Jsonx.dumps(value, indent: 2, sort_keys: true) if name == "indent2_sorted"
  return Jsonx.dumps(value, separators: [",", ":"], ensure_ascii: false) if name == "compact_utf8"
  return Jsonx.dumps(value, indent: 4, ensure_ascii: false, sort_keys: true) if name == "indent4_utf8_sorted"
  return Jsonx.dumps(value, indent: "\t") if name == "tab"
  raise "unknown option set " + name

-> gf2_lines(path)
  rows = []
  read_file(path).split("\n").each -> (line)
    rows.push(line) if line.size > 0
  rows

# Random structures: every option set against Python's json.dumps.
-> gf2_json_golden_cases(t, dir)
  lines = gf2_lines(dir + "/structs.jsonl")
  structs = lines.map -> (line)
    Jsonx.loads(line)
  t.eq("structs.jsonl: " + lines.size.to_s + " structures parse", structs.size, lines.size)
  bad = 0
  lines.each_with_index -> (line, i)
    bad += 1 if Jsonx.dumps(structs[i]) != line
  t.eq("dumps(loads(line)) == line for every structure", bad, 0)
  ["default", "indent1", "indent2_sorted", "compact_utf8", "indent4_utf8_sorted", "tab"].each -> (name)
    golden = gf2_lines(dir + "/dumps_" + name + ".jsonl")
    bad = 0
    golden.each_with_index -> (line, i)
      want = Jsonx.loads(line)
      got = gf2_dump_with(name, structs[i])
      if got != want
        bad += 1
        << "  " + name + " #" + i.to_s + ": got " + Check.clip(got) + " want " + Check.clip(want) if bad < 4
    t.eq("dumps " + name + ": " + golden.size.to_s + " structures identical to Python", bad, 0)

  # Ruby's JSON.pretty_generate; structures holding a float are refused
  # (see JsonWriter.emit_float)
  compared = 0
  refused = 0
  bad = 0
  gf2_lines(dir + "/ruby_pretty.jsonl").each -> (line)
    row = Jsonx.loads(line)
    got = nil
    begin
      got = Jsonx.pretty_generate(structs[row["i"]])
    rescue e: JsonError
      refused += 1
    if got != nil
      compared += 1
      if got != row["out"]
        bad += 1
        << "  pretty_generate #" + row["i"].to_s + ": got " + Check.clip(got) + " want " + Check.clip(row["out"]) if bad < 4
  t.eq("pretty_generate: " + compared.to_s + " structures identical to Ruby (" + refused.to_s + " holding floats refused)", bad, 0)
  t.ok("pretty_generate compared a useful number of structures", compared > 100)

# json.loads on malformed and unusual documents: same value or same message.
-> gf2_json_parse_cases(t, dir)
  rows = gf2_lines(dir + "/parse_cases.jsonl")
  bad = 0
  rows.each -> (line)
    row = Jsonx.loads(line)
    got = nil
    begin
      got = Jsonx.dumps(Jsonx.loads(row["input"]))
    rescue e: JsonError
      got = e.message
    want = row.key?("dumps") ? row["dumps"] : row["error"]
    if got != want
      bad += 1
      << "  parse " + Check.clip(row["input"]) + ": got " + Check.clip(got) + " want " + Check.clip(want)
  t.eq("parse_cases.jsonl: " + rows.size.to_s + " documents give Python's value or error message", bad, 0)

# Randomly spelled documents (odd whitespace, \\u escapes of plain letters, exponent
# spellings) and the same documents with one character deleted, inserted or replaced.
-> gf2_json_fuzz_cases(t, dir)
  rows = gf2_lines(dir + "/fuzz_cases.jsonl")
  bad = 0
  malformed = 0
  rows.each -> (line)
    row = Jsonx.loads(line)
    malformed += 1 if row.key?("error")
    got = nil
    begin
      got = Jsonx.dumps(Jsonx.loads(row["input"]))
    rescue e: JsonError
      got = e.message
    want = row.key?("dumps") ? row["dumps"] : row["error"]
    if got != want
      bad += 1
      << "  fuzz " + Check.clip(row["input"]) + ": got " + Check.clip(got) + " want " + Check.clip(want) if bad < 4
  t.eq("fuzz_cases.jsonl: " + rows.size.to_s + " documents (" + malformed.to_s + " malformed) give Python's value or error message", bad, 0)

-> gf2_json_unit_cases(t)
  # values
  t.eq("scalars", [Jsonx.loads("1"), Jsonx.loads("-7"), Jsonx.loads("true"), Jsonx.loads("false"), Jsonx.loads("null"), Jsonx.loads("\"s\"")], [1, 0 - 7, true, false, nil, "s"])
  t.eq("empty containers", [Jsonx.loads("\[\]"), Jsonx.loads("{}")], [[], {}])
  t.eq("nested", Jsonx.loads("{\"a\": \[1, {\"b\": \[\]}\], \"c\": null}"), {"a" => [1, {"b" => []}], "c" => nil})
  t.eq("integers of any size", Jsonx.loads("\[123456789012345678901234567890, -170141183460469231731687303715884105728, 9223372036854775807, 9223372036854775808\]"), [123456789012345678901234567890, 0 - 170141183460469231731687303715884105728, 9223372036854775807, 9223372036854775808])
  t.eq("integers at the 48-bit and 63-bit edges", Jsonx.loads("\[140737488355327, 140737488355328, -140737488355328, -140737488355329, -9223372036854775808, 4611686018427387904\]"), [140737488355327, 140737488355328, 0 - 140737488355328, 0 - 140737488355329, 0 - 9223372036854775807 - 1, 4611686018427387904])
  t.eq("a 200-bit integer survives", Jsonx.dumps(Jsonx.loads("1606938044258990275541962092341162602522202993782792835301376")), "1606938044258990275541962092341162602522202993782792835301376")
  t.eq("floats are Floats, integers are not", [type(Jsonx.loads("1.5")), type(Jsonx.loads("1e2")), type(Jsonx.loads("100")), type(Jsonx.loads("-0.0"))], ["Float", "Float", "Int", "Float"])
  t.eq("float values", Jsonx.dumps(Jsonx.loads("\[0.1, 1e22, 1E-5, 5e-324, 1.7976931348623157e308, 123456789.125, -2.5e-3\]")), "\[0.1, 1e+22, 1e-05, 5e-324, 1.7976931348623157e+308, 123456789.125, -0.0025\]")
  t.eq("-0 is the integer 0, -0.0 the float -0.0", Jsonx.dumps(Jsonx.loads("\[-0, -0.0\]")), "\[0, -0.0\]")
  t.eq("overflow and underflow", Jsonx.dumps(Jsonx.loads("\[1e400, -1e400, 1e-400\]")), "\[Infinity, -Infinity, 0.0\]")
  t.eq("NaN and the infinities", Jsonx.dumps(Jsonx.loads("\[NaN, Infinity, -Infinity\]")), "\[NaN, Infinity, -Infinity\]")
  t.eq("a float that is a whole number keeps its .0", Jsonx.dumps(Jsonx.loads("\[1.0, 100.0, 1e2\]")), "\[1.0, 100.0, 100.0\]")

  # strings
  t.eq("escapes", Jsonx.loads("\"a\\nb\\t\\\"q\\\" \\\\ \\/ \\b\\f\\r\""), "a\nb\t\"q\" \\ / " + 8.chr + 12.chr + "\r")
  t.eq("\\u escapes", Jsonx.loads("\"\\u00e9\\u4e2d\\u0041\""), "é中A")
  t.eq("a surrogate pair is one astral character", Jsonx.loads("\"\\ud83d\\ude00\""), "😀")
  t.eq("raw UTF-8 passes through", Jsonx.loads("\"é中😀\""), "é中😀")
  t.eq("a lone surrogate is written back unchanged", Jsonx.dumps(Jsonx.loads("\"\\ud800 \\udc00\\ud83d\"")), "\"\\ud800 \\udc00\\ud83d\"")
  t.eq("NUL", Jsonx.dumps(Jsonx.loads("\"\\u0000\"")), "\"\\u0000\"")
  t.eq("a string that looks like an interpolation is data", Jsonx.loads("\"\\u005b1\\u005d\""), "\[1\]")

  # objects
  t.eq("key order is insertion order", Jsonx.loads("{\"b\": 1, \"a\": 2, \"c\": 3}").keys, ["b", "a", "c"])
  t.eq("a repeated key keeps its first position and its last value", Jsonx.dumps(Jsonx.loads("{\"b\": 1, \"a\": 2, \"b\": 3}")), "{\"b\": 3, \"a\": 2}")
  t.eq("whitespace is free", Jsonx.dumps(Jsonx.loads(" \n\t{ \"a\" : \[ 1 , 2 \] } \r\n")), "{\"a\": \[1, 2\]}")

  # errors carry Python's message and position
  t.raises("trailing comma in an array", "Illegal trailing comma before end of array: line 1 column 6 (char 5)") ->
    Jsonx.loads("\[1, 2,\]")
  t.raises("position counts lines and columns", "Expecting value: line 3 column 3 (char 9)") ->
    Jsonx.loads("\[1,\n2,\n  x\]")
  t.raises("position counts characters, not bytes", "Extra data: line 1 column 6 (char 5)") ->
    Jsonx.loads("\"éé\" x")
  t.raises("trailing garbage", "Extra data") ->
    Jsonx.loads("{} 1")
  t.raises("a BOM", "Unexpected UTF-8 BOM") ->
    Jsonx.loads(0xFEFF.chr + "1")
  t.raises("the error is a JsonError with an offset", "Expecting value") ->
    Jsonx.loads("")
  offset = nil
  begin
    Jsonx.loads("\[1, x\]")
  rescue e: JsonError
    offset = e.offset
  t.eq("JsonError#offset is the byte offset", offset, 4)

  # nesting: Python stops at its recursion limit, a deeper document must not crash
  t.eq("1000 levels of nesting parse", Jsonx.dumps(Jsonx.loads("\[" * 999 + "1" + "\]" * 999)).size, 1999)
  t.raises("2000 levels of nesting are refused", "maximum recursion depth exceeded") ->
    Jsonx.loads("\[" * 2000 + "\]" * 2000)
  t.raises("deeply nested objects are refused", "maximum recursion depth exceeded") ->
    Jsonx.loads("{\"a\":" * 2000 + "1" + "}" * 2000)

  # writer options
  value = {"b" => [1, {"z" => nil, "a" => []}], "a" => "é"}
  t.eq("indent 0 puts each item on its own line", Jsonx.dumps(value, indent: 0), "{\n\"b\": \[\n1,\n{\n\"z\": null,\n\"a\": \[\]\n}\n\],\n\"a\": \"\\u00e9\"\n}")
  t.eq("sort_keys sorts at every level", Jsonx.dumps(value, sort_keys: true), "{\"a\": \"\\u00e9\", \"b\": \[1, {\"a\": \[\], \"z\": null}\]}")
  t.eq("separators replace both", Jsonx.dumps(value, separators: [";", "="]), "{\"b\"=\[1;{\"z\"=null;\"a\"=\[\]}\];\"a\"=\"\\u00e9\"}")
  t.eq("ensure_ascii false keeps the character", Jsonx.dumps("é😀", ensure_ascii: false), "\"é😀\"")
  t.eq("ensure_ascii escapes astral characters as pairs", Jsonx.dumps("é😀"), "\"\\u00e9\\ud83d\\ude00\"")
  t.eq("DEL is escaped with ensure_ascii only", [Jsonx.dumps(127.chr), Jsonx.dumps(127.chr, ensure_ascii: false)], ["\"\\u007f\"", "\"" + 127.chr + "\""])
  t.eq("control characters", Jsonx.dumps(1.chr + 31.chr + "\n\r\t" + 8.chr + 12.chr), "\"\\u0001\\u001f\\n\\r\\t\\b\\f\"")
  t.eq("Symbol keys and values, Decimal values", Jsonx.dumps({a: :b, c: 0.5}), "{\"a\": \"b\", \"c\": 0.5}")
  t.eq("non-string keys become text like Python's", Jsonx.dumps({1 => "a", true => "b", nil => "c", 2.5 => "d"}), "{\"1\": \"a\", \"true\": \"b\", \"null\": \"c\", \"2.5\": \"d\"}")
  t.raises("other key types are refused", "keys must be str, int, float, bool or None, not Array") ->
    Jsonx.dumps({[1] => 2})
  t.eq("a top-level scalar", [Jsonx.dumps(nil), Jsonx.dumps(true), Jsonx.dumps(0 - 5), Jsonx.dumps("x")], ["null", "true", "-5", "\"x\""])
  t.raises("an unserialisable value", "is not JSON serializable") ->
    Jsonx.dumps(1..3)
  [[128], [195], [224, 128, 128], [244, 144, 128, 128], [226, 130], [192, 128], [255]].each -> (bytes)
    t.raises("invalid UTF-8 " + bytes.to_s + " is refused with ensure_ascii", "invalid UTF-8") ->
      Jsonx.dumps(gf2_bytes_string(bytes))
  t.eq("valid UTF-8 of every length is escaped", Jsonx.dumps(gf2_bytes_string([195, 169, 226, 130, 172, 240, 159, 152, 128, 237, 160, 128])), "\"\\u00e9\\u20ac\\ud83d\\ude00\\ud800\"")

  # Ruby
  t.eq("pretty_generate", Jsonx.pretty_generate([{"exact" => true, "shape" => "2x2x2", "rank" => 7, "path" => "/a/b é"}, [], {}]), "\[\n  {\n    \"exact\": true,\n    \"shape\": \"2x2x2\",\n    \"rank\": 7,\n    \"path\": \"/a/b é\"\n  },\n  \[\],\n  {}\n\]")
  t.eq("pretty_generate keeps DEL and writes controls in lowercase hex", Jsonx.pretty_generate(127.chr + 31.chr), "\"" + 127.chr + "\\u001f\"")
  t.raises("pretty_generate refuses floats", "does not support floats") ->
    Jsonx.pretty_generate([0.5])

-> gf2_json_files_cases(t, dir)
  scratch = capture("mktemp -d").strip
  path = scratch + "/a.jsonl"
  write_file(path, "{\"a\": 1}\n\n  \n\[2, 3\]\n{\"b\": \"x\"}")
  t.eq("loads_lines skips blank lines", Jsonx.loads_lines(read_file(path)), [{"a" => 1}, [2, 3], {"b" => "x"}])
  t.eq("load reads a file", Jsonx.load(dir + "/real_comparators.json")["scored_on"], "2026-09-29")
  t.raises("load of a missing file", "cannot read") ->
    Jsonx.load(scratch + "/absent.json")
  tree = Jsonx.loads_lines(read_file(path))
  Jsonx.release(tree)
  t.ok("release accepts a parsed tree", true)
  system("rm -rf '" + scratch + "'")

# The real lineage manifests and comparators, re-dumped exactly as
# build_gf2_lineage_bundle.py writes them (json.dumps(indent=1) + "\n").
-> gf2_json_manifest_cases(t, dir)
  ["real_comparators.json", "real_manifest_walks.json", "real_manifest_block47.json", "real_manifest_closure_head.json", "real_manifest_searched_head.json"].each -> (name)
    raw = read_file(dir + "/" + name)
    tree = Jsonx.loads(raw)
    t.ok(name + ": indent=1 plus newline reproduces the file (" + raw.size.to_s + " bytes)", Jsonx.dumps(tree, indent: 1) + "\n" == raw || Jsonx.dumps(tree, indent: 1) == raw)

# Every JSON / JSONL file of the campaign release tree.
-> gf2_json_release_cases(t, release, table)
  formats = gf2_lines(table)
  matched = 0
  lines_total = 0
  lines_same = 0
  bad = 0
  formats.each -> (row)
    c = row.split("\t")
    path = release + "/" + c[0]
    if c[1] == "json"
      raw = read_file(path)
      tree = Jsonx.loads(raw)
      label = "none"
      label = "indent1_nl" if Jsonx.dumps(tree, indent: 1) + "\n" == raw
      label = "indent1" if label == "none" && Jsonx.dumps(tree, indent: 1) == raw
      label = "indent2_nl" if label == "none" && Jsonx.dumps(tree, indent: 2) + "\n" == raw
      label = "default" if label == "none" && Jsonx.dumps(tree) == raw
      if label == c[2]
        matched += 1
      else
        bad += 1
        << "  " + c[0] + ": format " + label + " want " + c[2]
      Jsonx.release(tree)
    else
      same = 0
      count = 0
      gf2_lines(path).each -> (line)
        count += 1
        same += 1 if Jsonx.dumps(Jsonx.loads(line)) == line
      lines_total += count
      lines_same += same
      if same == c[2].to_i && count == c[3].to_i
        matched += 1
      else
        bad += 1
        << "  " + c[0] + ": " + same.to_s + " of " + count.to_s + " lines, want " + c[2] + " of " + c[3]
  t.eq("release tree: " + matched.to_s + " of " + formats.size.to_s + " files behave exactly like Python (" + lines_same.to_s + " of " + lines_total.to_s + " JSONL lines round-trip)", bad, 0)

-> gf2_json_cases(t)
  dir = __DIR__ + "/../fixtures/gf2_support/json"
  goldens = env("GF2_JSON_GOLDENS")
  goldens = dir if goldens == nil || goldens == ""
  gf2_json_unit_cases(t)
  gf2_json_files_cases(t, dir)
  gf2_json_manifest_cases(t, dir)
  gf2_json_parse_cases(t, goldens)
  gf2_json_fuzz_cases(t, goldens)
  gf2_json_golden_cases(t, goldens)
  release = env("GF2_RELEASE_DIR")
  work = Check.work_dir
  release = work + "/release-0929" if (release == nil || release == "") && work != nil
  if release != nil && release != "" && File.directory?(release)
    gf2_json_release_cases(t, release, dir + "/release_formats.tsv")
  else
    << "SKIP release-tree cases (no record-hunt work directory; set GF2_RECORD_HUNT_WORK)"

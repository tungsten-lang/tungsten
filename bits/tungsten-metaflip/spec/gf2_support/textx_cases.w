# Cases for lib/metaflip/gf2/textx.w, run by spec/gf2_support_test.w through
# `gf2_textx_cases(t)`. The goldens in spec/fixtures/gf2_support/textx/ come
# from Python itself (gen_textx_goldens.py there): format specs, repr,
# splitlines/split, sorted/min/max, Counter, zlib.crc32 and the csv module.
# Strings that may hold control characters travel as base64 of their bytes.
# The real-data cases read the record-hunt files and are skipped when those
# files are absent (GF2_RECORD_HUNT_WORK names the work directory). Base64 and File
# come from the stdlib autoload table: an explicit `use core/base64` resolves to the
# worktree's core/ and clashes with the autoloaded copy (duplicate definition of
# base64_encode).
use ../../lib/metaflip/gf2/textx
use ../../lib/metaflip/gf2/jsonx

# Fixture directory: `__DIR__` is this file's own directory in compiled code;
# the relative candidates serve a run started from the bit root or the checkout
# root.
-> tx_fixture_dir
  candidates = [__DIR__ + "/../fixtures/gf2_support/textx", "spec/fixtures/gf2_support/textx", "bits/tungsten-metaflip/spec/fixtures/gf2_support/textx"]
  i = 0
  while i < candidates.size
    return candidates[i] if File.exist?(candidates[i] + "/format_cases.tsv")
    i += 1
  candidates[0]

# The String whose bytes are the base64 text `text` (any bytes, NUL included).
-> tx_unb64(text)
  ccall("w_string_from_byte_array", Base64.decode(text))

# Lines of a fixture file without the final empty one.
-> tx_fixture_lines(dir, name)
  lines = read_file(dir + "/" + name).split("\n")
  lines.pop if lines.size > 0 && lines[lines.size - 1] == ""
  lines

# The String made of the code points listed as hex words.
-> tx_from_code_points(words)
  buffer = StringBuffer(16)
  words.each -> (word)
    buffer << Textx.parse_hex(word).chr
  buffer.to_s

# Compare one golden case; only a mismatch reports (with the case's label),
# the group's verdict is one aggregate check.
-> tx_same(t, label, actual, expected, tally)
  if actual == expected
    tally[0] += 1
  else
    t.eq(label, actual, expected)

-> tx_verdict(t, group, tally, total)
  t.eq(group + ": " + total.to_s + " cases agree with Python", tally[0], total)

# Whether Textx.parse_hex rejects `text` with a TextxError.
-> tx_parse_hex_raises?(text)
  raised = false
  begin
    Textx.parse_hex(text)
  rescue e: TextxError
    raised = true
  raised

# ---------------------------------------------------------------------------
# padding and integer formats
# ---------------------------------------------------------------------------
-> gf2_textx_format_cases(t, dir)
  lines = tx_fixture_lines(dir, "format_cases.tsv")
  tally = [0]
  lines.each -> (line)
    f = line.split("\t")
    op = f[0]
    if op == "pad_left" || op == "pad_right"
      value = f[1] == "i" ? f[2].to_i : f[2]
      actual = op == "pad_left" ? Textx.pad_left(value, f[3].to_i, f[4]) : Textx.pad_right(value, f[3].to_i, f[4])
      tx_same(t, op + " " + f[1] + " " + f[2] + " " + f[3] + " fill " + f[4], actual, f[5], tally)
    elsif op == "zero_pad"
      tx_same(t, "zero_pad " + f[1] + " " + f[2], Textx.zero_pad(f[1].to_i, f[2].to_i), f[3], tally)
    elsif op == "thousands"
      tx_same(t, "thousands " + f[1], Textx.thousands(f[1].to_i), f[2], tally)
    elsif op == "signed"
      tx_same(t, "signed " + f[1], Textx.signed(f[1].to_i), f[2], tally)
    elsif op == "hex"
      tx_same(t, "hex " + f[1], Textx.hex(f[1].to_i), f[2], tally)
    elsif op == "parse_hex" && f[2] == "ERR"
      tx_same(t, "parse_hex rejects " + f[1], tx_parse_hex_raises?(f[1]), true, tally)
    elsif op == "parse_hex"
      tx_same(t, "parse_hex " + f[1], Textx.parse_hex(f[1]).to_s, f[2], tally)
    else
      t.ok("known format op " + op, false)
  tx_verdict(t, "format specs (pad_left pad_right zero_pad thousands signed hex parse_hex)", tally, lines.size)

  t.eq("char_count counts code points", [Textx.char_count(""), Textx.char_count("abc"), Textx.char_count("é日😀"), Textx.char_count("é")], [0, 3, 3, 2])
  t.eq("hex of a 2^200 BigInt", Textx.hex(1 << 200), "1" + ("0" * 50))
  t.eq("parse_hex above 2^63 (String#to_i(16) saturates)", Textx.parse_hex("c0ef6e5800000000"), 13902451898952187904)
  t.eq("parse_hex 2^64", Textx.parse_hex("10000000000000000"), 18446744073709551616)
  t.eq("parse_hex round trip of 2^200 + 12345", Textx.parse_hex(Textx.hex((1 << 200) + 12345)), (1 << 200) + 12345)
  t.raises("pad fill of two characters", "one character") ->
    Textx.pad_left("x", 4, "ab")
  t.raises("pad fill of no character", "one character") ->
    Textx.pad_left("x", 4, "")
  t.raises("pad_left of a Float", "got Float") ->
    Textx.pad_left(~1.5, 6)
  t.raises("pad_left of nil", "got Nil") ->
    Textx.pad_left(nil, 6)
  t.raises("thousands of a String", "got String") ->
    Textx.thousands("12")
  t.raises("hex of a Decimal", "got Decimal") ->
    Textx.hex(0.5)
  t.raises("zero_pad of a String", "got String") ->
    Textx.zero_pad("5", 3)
  t.raises("signed of nil", "got Nil") ->
    Textx.signed(nil)
  t.raises("parse_hex message quotes the input", "'zz'") ->
    Textx.parse_hex("zz")

# ---------------------------------------------------------------------------
# repr
# ---------------------------------------------------------------------------
-> gf2_textx_repr_cases(t, dir)
  lines = tx_fixture_lines(dir, "repr_cases.tsv")
  tally = [0]
  lines.each -> (line)
    at = line.index("\t")
    subject = tx_from_code_points(line.slice(0, at).split(" "))
    tx_same(t, "repr_str " + line.slice(0, at), Textx.repr_str(subject), line.slice(at + 1, line.size - at - 1), tally)
  tx_verdict(t, "repr_str", tally, lines.size)
  t.eq("repr_str of the empty string", Textx.repr_str(""), "''")
  t.eq("repr_str picks double quotes for a lone apostrophe", Textx.repr_str("it's"), "\"it's\"")
  t.eq("repr_str escapes the apostrophe when both quotes occur", Textx.repr_str("it's \"x\""), "'it\\'s \"x\"'")
  t.raises("repr_str rejects a stray byte", "invalid UTF-8") ->
    Textx.repr_str(tx_unb64("YcOh/w=="))
  t.raises("repr_str rejects an overlong 3-byte sequence", "invalid UTF-8") ->
    Textx.repr_str(tx_unb64("4ICA"))
  t.raises("repr_str rejects a code point above U+10FFFF", "invalid UTF-8") ->
    Textx.repr_str(tx_unb64("9JCAgA=="))
  t.raises("repr_str rejects a C0 lead byte", "invalid UTF-8") ->
    Textx.repr_str(tx_unb64("wIA="))
  t.raises("repr_str rejects a truncated sequence", "invalid UTF-8") ->
    Textx.repr_str(tx_unb64("YeKC"))

# ---------------------------------------------------------------------------
# splitlines and words
# ---------------------------------------------------------------------------
-> gf2_textx_split_cases(t, dir)
  lines = tx_fixture_lines(dir, "split_cases.tsv")
  tally = [0]
  lines.each -> (line)
    f = line.split("\t")
    subject = tx_unb64(f[1])
    expect = []
    parts = f[2].split(",")
    i = 1
    while i < parts.size
      expect.push(tx_unb64(parts[i]))
      i += 1
    actual = f[0] == "splitlines" ? Textx.splitlines(subject) : Textx.words(subject)
    tx_same(t, f[0] + " of " + f[1], actual, expect, tally)
  tx_verdict(t, "splitlines and words", tally, lines.size)
  t.eq("splitlines keeps interior blank lines", Textx.splitlines("a\n\nb"), ["a", "", "b"])
  t.eq("splitlines treats \\r\\n as one break", Textx.splitlines("a\r\nb\r\n"), ["a", "b"])
  t.eq("words of a tab and newline separated line", Textx.words("  MFW1\t3 3 3\n23 "), ["MFW1", "3", "3", "3", "23"])

# ---------------------------------------------------------------------------
# crc32
# ---------------------------------------------------------------------------
-> gf2_textx_crc32_cases(t, dir)
  lines = tx_fixture_lines(dir, "crc32_cases.tsv")
  tally = [0]
  lines.each -> (line)
    f = line.split("\t")
    if f[0] == "BIG"
      tx_same(t, "crc32 of 1 MiB", Textx.crc32("0123456789abcdef" * 65536), f[1].to_i, tally)
    else
      tx_same(t, "crc32 of " + f[0], Textx.crc32(tx_unb64(f[0])), f[1].to_i, tally)
  tx_verdict(t, "crc32", tally, lines.size)
  t.eq("crc32 as the walk nonce term for a shape", Textx.crc32("13x14x16") % 1000003, 3803376106 % 1000003)

# ---------------------------------------------------------------------------
# sorting, minimum and maximum
# ---------------------------------------------------------------------------
-> gf2_textx_sort_cases(t, dir)
  cases = Jsonx.loads(read_file(dir + "/sort_cases.json"))
  tally = [0]
  total = 0
  cases.each -> (c)
    keys = c["keys"]
    order = []
    i = 0
    while i < keys.size
      order.push(i)
      i += 1
    tag = c["shape"] + "/" + keys.size.to_s
    forward = Textx.sort_by(order) -> (i)
      keys[i]
    backward = Textx.sort_by(order, reverse: true) -> (i)
      keys[i]
    first_min = Textx.min_by(order) -> (i)
      keys[i]
    first_max = Textx.max_by(order) -> (i)
      keys[i]
    tx_same(t, "sort_by " + tag, forward, c["forward"], tally)
    tx_same(t, "sort_by reverse " + tag, backward, c["reverse"], tally)
    tx_same(t, "min_by " + tag, first_min, c["first_min"], tally)
    tx_same(t, "max_by " + tag, first_max, c["first_max"], tally)
    total += 4
  tx_verdict(t, "sort_by, min_by, max_by", tally, total)

  pairs = [["b", 2], ["a", 2], ["c", 1], ["d", 2]]
  ascending = Textx.sort_by(pairs) -> (p)
    p[1]
  descending = Textx.sort_by(pairs, reverse: true) -> (p)
    p[1]
  t.eq("sort_by ties keep input order", ascending, [["c", 1], ["b", 2], ["a", 2], ["d", 2]])
  t.eq("sort_by reverse ties keep input order", descending, [["b", 2], ["a", 2], ["d", 2], ["c", 1]])
  t.eq("sorted of tuples", Textx.sorted([[2, "b"], [1, "z"], [2, "a"], [1]]), [[1], [1, "z"], [2, "a"], [2, "b"]])
  t.eq("sorted reverse", Textx.sorted([3, 1, 2], reverse: true), [3, 2, 1])
  t.eq("sorted of BigInts and Ints", Textx.sorted([(1 << 100), 5, 0 - (1 << 90), 7]), [0 - (1 << 90), 5, 7, (1 << 100)])
  t.eq("sorted strings order by code point", Textx.sorted(["b", "B", "é", "a", "日"]), ["B", "a", "b", "é", "日"])
  t.eq("sorted of an empty list", Textx.sorted([]), [])
  t.eq("sorted of Floats", Textx.sorted([~2.5, ~0.5, ~1.5]), [~0.5, ~1.5, ~2.5])
  unsorted = [3, 1, 2]
  Textx.sorted(unsorted)
  t.eq("sorted leaves its argument alone", unsorted, [3, 1, 2])
  nothing = Textx.min_by([]) -> (x)
    x
  t.eq("min_by of an empty list is nil", nothing, nil)
  nothing = Textx.max_by([]) -> (x)
    x
  t.eq("max_by of an empty list is nil", nothing, nil)
  smallest = Textx.min_by([0.5, 0.25, 0.75]) -> (x)
    x
  t.eq("min_by orders Decimal keys correctly", smallest, 0.25)
  t.eq("compare of tuples", [Textx.compare([1, 2], [1, 3]), Textx.compare([1, 2], [1, 2]), Textx.compare([1, 2, 0], [1, 2]), Textx.compare(3, 2), Textx.compare("a", "b")], [0 - 1, 0, 1, 1, 0 - 1])
  t.eq("compare puts false before true", [Textx.compare(false, true), Textx.compare(true, true)], [0 - 1, 0])
  t.raises("compare of unlike types", "cannot order") ->
    Textx.compare(1, "a")
  t.raises("sort_by refuses a Decimal key", "Decimal") ->
    Textx.sort_by([1, 2]) -> (x)
      0.5 * x
  t.raises("sort_by refuses a Decimal inside a tuple key", "Decimal") ->
    Textx.sort_by([1, 2]) -> (x)
      [x, 0.5]

# ---------------------------------------------------------------------------
# counting, dictionaries of lists, median
# ---------------------------------------------------------------------------
-> gf2_textx_count_cases(t, dir)
  doc = Jsonx.loads(read_file(dir + "/count_cases.json"))
  tally = [0]
  total = 0
  doc["counts"].each -> (c)
    items = c["items"]
    counts = Textx.tally(items)
    tag = items.size.to_s + " items"
    tx_same(t, "tally " + tag, Textx.pairs_of(counts), c["tally"], tally)
    tx_same(t, "most_common " + tag, Textx.most_common(counts), c["most_common"], tally)
    tx_same(t, "most_common(2) " + tag, Textx.most_common(counts, 2), c["most_common_2"], tally)
    tx_same(t, "most_common(0) " + tag, Textx.most_common(counts, 0), c["most_common_0"], tally)
    tx_same(t, "sorted_items " + tag, Textx.sorted_items(counts), c["sorted_items"], tally)
    order = []
    i = 0
    while i < items.size
      order.push(i)
      i += 1
    groups = Textx.group_by(order) -> (i)
      items[i]
    tx_same(t, "group_by " + tag, Textx.pairs_of(groups), c["groups"], tally)
    total += 6
  doc["medians"].each -> (m)
    values = m["values"]
    tx_same(t, "median_pair of " + values.size.to_s + " values", Textx.median_pair(values), [m["lower"], m["upper"]], tally)
    total += 1
    if values.size % 2 == 1
      tx_same(t, "median of " + values.size.to_s + " values", Textx.median(values), m["lower"], tally)
      total += 1
  tx_verdict(t, "tally, most_common, sorted_items, group_by, median", tally, total)

  t.eq("median_pair orders Decimals correctly", Textx.median_pair([0.5, 0.25, 0.75, 0.1]), [0.25, 0.5])
  t.eq("median_pair of mixed Int and Decimal", Textx.median_pair([3, 0.5, 2]), [2, 2])
  t.raises("median of nothing", "no median for empty data") ->
    Textx.median([])
  t.raises("median_pair of nothing", "no median for empty data") ->
    Textx.median_pair([])
  t.eq("median of an even count is the Float mean", [Floatx.repr(Textx.median([1, 2])), Floatx.repr(Textx.median([1, 3])), Floatx.repr(Textx.median([~2.5, 1, 4, ~10.5]))], ["1.5", "2.0", "3.25"])
  t.eq("median of an even count of huge integers rounds like int / int", Floatx.repr(Textx.median([1 << 100, (1 << 100) + 1])), Floatx.repr(Floatx.ratio((1 << 101) + 1, 2)))
  t.eq("median of an odd count keeps the type", [Textx.median([3, 1, 2]), type(Textx.median([3, 1, 2]))], [2, "Int"])
  counts = {}
  t.eq("add_to starts at the amount", Textx.add_to(counts, "a"), 1)
  t.eq("add_to accumulates", Textx.add_to(counts, "a", 4), 5)
  t.eq("add_to with a BigInt total", Textx.add_to(counts, "big", (1 << 100)), (1 << 100))
  t.eq("a missing key counts 0", counts.fetch("zzz", 0), 0)
  bag = {}
  t.eq("setdefault stores the default", Textx.setdefault(bag, "k", [0, 0]), [0, 0])
  stored = Textx.setdefault(bag, "k", [9])
  stored[1] += 1
  t.eq("setdefault returns the stored value, not the new default", bag["k"], [0, 1])
  bag["n"] = nil
  t.eq("setdefault keeps a stored nil", Textx.setdefault(bag, "n", 5), nil)
  lists = {}
  Textx.push_to(lists, "x", 1)
  Textx.push_to(lists, "y", 2)
  t.eq("push_to returns the list", Textx.push_to(lists, "x", 3), [1, 3])
  t.eq("push_to keeps first-seen key order", lists.keys, ["x", "y"])
  t.eq("tally of BigInt items counts by value", Textx.pairs_of(Textx.tally([(1 << 100), (1 << 100), 7])), [[(1 << 100), 2], [7, 1]])
  t.raises("tally refuses Array items", "identity") ->
    Textx.tally([[1, 2], [1, 2]])
  t.raises("push_to refuses an Array key", "identity") ->
    Textx.push_to({}, [1, 2], 1)
  t.raises("setdefault refuses an Array key", "identity") ->
    Textx.setdefault({}, [1], 1)
  t.raises("add_to refuses an Array key", "identity") ->
    Textx.add_to({}, [1], 1)
  t.raises("group_by refuses Array keys", "identity") ->
    Textx.group_by([1, 2]) -> (x)
      [x]

# ---------------------------------------------------------------------------
# tab-separated values
# ---------------------------------------------------------------------------
-> gf2_textx_tsv_cases(t, dir)
  reads = Jsonx.loads(read_file(dir + "/tsv_read_cases.json"))
  tally = [0]
  total = 0
  reads.each -> (c)
    tx_same(t, "tsv_rows of " + Textx.repr_str(c["text"]), Textx.tsv_rows(c["text"]), c["rows"], tally)
    total += 1
    if c["records"] == "ERR"
      raised = false
      begin
        Textx.tsv_records(c["text"])
      rescue e: TextxError
        raised = true
      tx_same(t, "tsv_records rejects " + Textx.repr_str(c["text"]), raised, true, tally)
      total += 1
    elsif c["records"] != "SKIP"
      tx_same(t, "tsv_records of " + Textx.repr_str(c["text"]), Textx.tsv_records(c["text"]), c["records"], tally)
      total += 1
  writes = Jsonx.loads(read_file(dir + "/tsv_write_cases.json"))
  writes.each -> (c)
    tx_same(t, "tsv_text of " + Textx.repr_str(c["text"]), Textx.tsv_text(c["rows"], eol: c["eol"]), c["text"], tally)
    total += 1
  tx_verdict(t, "tsv_rows, tsv_records, tsv_text", tally, total)

  t.eq("tsv_text defaults to CRLF", Textx.tsv_text([["a", "b"]]), "a\tb\r\n")
  t.eq("tsv_text quotes a lone empty field", Textx.tsv_text([[""], [nil]]), "\"\"\r\n\"\"\r\n")
  t.eq("tsv_text writes an empty row as the terminator", Textx.tsv_text([[]], eol: "\n"), "\n")
  t.eq("tsv_text quotes a CR even when the terminator is LF", Textx.tsv_text([["a\rb"]], eol: "\n"), "\"a\rb\"\n")
  t.eq("tsv_text doubles quotes", Textx.tsv_text([["say \"hi\"", "x"]], eol: "\n"), "\"say \"\"hi\"\"\"\tx\n")
  t.eq("tsv_text of a BigInt", Textx.tsv_text([[1 << 100]], eol: "\n"), "1267650600228229401496703205376\n")
  t.raises("tsv_text refuses a Float", "got Float") ->
    Textx.tsv_text([[~1.5]])
  t.raises("tsv_text refuses a Boolean", "got Boolean") ->
    Textx.tsv_text([[true]])
  t.eq("tsv_rows of nothing", Textx.tsv_rows(""), [])
  t.eq("tsv_records of a header only", Textx.tsv_records("a\tb\n"), [])
  t.eq("tsv_records fills short rows with nil", Textx.tsv_records("a\tb\n1\n"), [{"a" => "1", "b" => nil}])
  t.raises("tsv_records refuses a long row", "has 3 fields") ->
    Textx.tsv_records("a\tb\n1\t2\t3\n")
  t.eq("a duplicated header name keeps the last value", Textx.tsv_records("h\th\n1\t2\n"), [{"h" => "2"}])

# ---------------------------------------------------------------------------
# real data: the record-hunt release index and the paper-data tables
# ---------------------------------------------------------------------------
-> gf2_textx_real_data_cases(t)
  work = env("GF2_RECORD_HUNT_WORK")
  work = env("HOME") + "/.tungsten/metaflip/experiments/record-hunt-20260926/work" if work == nil || work == ""
  records_path = work + "/release-0929/gf2-campaign-records/records.tsv"
  if File.exist?(records_path)
    raw = read_file(records_path)
    rows = Textx.tsv_rows(raw)
    t.eq("records.tsv: 796 rows (header and 795 records)", rows.size, 796)
    t.eq("records.tsv survives tsv_rows and tsv_text byte for byte", Textx.tsv_text(rows) == raw, true)
    records = Textx.tsv_records(raw)
    t.eq("records.tsv: 795 DictReader records", records.size, 795)
    t.eq("records.tsv: first record's shape", records[0]["shape"], "2x4x17")
    largest = Textx.max_by(records) -> (r)
      r["rank"].to_i
    t.eq("records.tsv: the highest rank is 27x32x32 at 13999", [largest["shape"], largest["rank"]], ["27x32x32", "13999"])
    smallest = Textx.min_by(records) -> (r)
      r["rank"].to_i
    t.eq("records.tsv: the lowest rank is 4x4x8 at 94", [smallest["shape"], smallest["rank"]], ["4x4x8", "94"])
  flags_path = work + "/paper-data/prior_art_flags.tsv"
  if File.exist?(flags_path)
    raw = read_file(flags_path)
    t.eq("prior_art_flags.tsv survives a round trip with LF terminators", Textx.tsv_text(Textx.tsv_rows(raw), eol: "\n") == raw, true)

# ---------------------------------------------------------------------------
-> gf2_textx_cases(t)
  dir = tx_fixture_dir
  gf2_textx_format_cases(t, dir)
  gf2_textx_repr_cases(t, dir)
  gf2_textx_split_cases(t, dir)
  gf2_textx_crc32_cases(t, dir)
  gf2_textx_sort_cases(t, dir)
  gf2_textx_count_cases(t, dir)
  gf2_textx_tsv_cases(t, dir)
  gf2_textx_real_data_cases(t)

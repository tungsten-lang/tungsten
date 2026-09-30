# Golden tests of the GF(2) scheme library (lib/metaflip/gf2/{bits,packed,scheme}.w).
#
# Every expectation comes from the ORIGINAL Python/Ruby tooling, captured in
# spec/fixtures/gf2_scheme/ by generate.py (bits/popcount/T/remap of
# mmc_gf2_alg.py, blob/read_blob/exact of the MFW1 tooling, the messages and
# coordinates of tools/verify_tensor.rb, the orientations of mmc_gf2_alg.py).
# Prints FAIL lines and exits 1 on any failure, else PASS.
use ../lib/metaflip/gf2/scheme

fixtures = __DIR__ + "/fixtures/gf2_scheme"
failures = 0

-> check(label, ok)
  if ok
    return 0
  << "FAIL " + label
  1

# Rows of a fixture table: tab-separated columns, `#` lines and blanks skipped.
-> table(name)
  rows = []
  read_file(__DIR__ + "/fixtures/gf2_scheme/" + name).split("\n").each -> (line)
    if line != "" && !line.starts_with?("#")
      rows.push(line.split("\t"))
  rows

-> hex(x)
  Metaflip:Gf2:Bits.to_hex(x)

-> raised(label, expected_part, call)
  message = ""
  begin
    call.call
  rescue e
    message = "[e]"
  ok = message != "" && message.index(expected_part) != nil
  return 0 if ok
  << "FAIL " + label + ": expected an error containing '" + expected_part + "', got '" + message + "'"
  1

# ---- Bits against mmc_gf2_alg.py -------------------------------------------------
rows = table("bits.tsv")
rows.each -> (row)
  x = Metaflip:Gf2:Bits.from_hex(row[0])
  name = "bits " + row[0].slice(0, 24)
  failures += check(name + " popcount", Metaflip:Gf2:Bits.popcount(x) == row[1].to_i)
  failures += check(name + " low_bit", Metaflip:Gf2:Bits.low_bit_index(x) == row[2].to_i)
  failures += check(name + " high_bit", Metaflip:Gf2:Bits.high_bit_index(x) == row[3].to_i)
  failures += check(name + " to_hex", hex(x) == row[0])
  failures += check(name + " transpose", hex(Metaflip:Gf2:Bits.transpose(x, row[4].to_i, row[5].to_i)) == row[6])
  table_ = (0...(x == 0 ? 1 : Metaflip:Gf2:Bits.high_bit_index(x) + 1)).map -> (b) (b * 7 + 3) % 1500
  failures += check(name + " remap", hex(Metaflip:Gf2:Bits.remap(x, table_)) == row[7])
  positions = Metaflip:Gf2:Bits.positions(x)
  golden = row[8] == "-" ? [] : row[8].split(",").map -> (s) s.to_i
  failures += check(name + " positions", positions.size == golden.size)
  same = true
  (0...golden.size).each -> (i)
    same = false if positions[i] != golden[i]
  failures += check(name + " positions values", same)
  failures += check(name + " from_positions", Metaflip:Gf2:Bits.from_positions(positions) == x)
  words = Metaflip:Gf2:Bits.limbs_for(x == 0 ? 1 : Metaflip:Gf2:Bits.high_bit_index(x) + 1)
  limbs = i64[words + 1]
  used = Metaflip:Gf2:Bits.to_limbs(x, limbs, 0, words + 1)
  failures += check(name + " limbs used", used <= words)
  failures += check(name + " limb round trip", Metaflip:Gf2:Bits.from_limbs(limbs, 0, words + 1) == x)
  failures += check(name + " parse_hex", Metaflip:Gf2:Bits.parse_hex(row[0], 0, row[0].size) == x)

# limb layout: limb j holds bits 64j..64j+63, high bit set means a negative slot
limbs = i64[3]
Metaflip:Gf2:Bits.to_limbs((1 << 127) | (1 << 63) | 5, limbs, 0, 3)
failures += check("limb 0 keeps bit 63 as the sign bit", limbs[0] == -9223372036854775803)
failures += check("limb 1 keeps bit 127 as the sign bit", limbs[1] == -9223372036854775808)
failures += check("limb 2 is empty", limbs[2] == 0)
padded = i64[4]
padded[1] = 7
failures += check("to_limbs at an offset", Metaflip:Gf2:Bits.to_limbs(9, padded, 2, 2) == 1 && padded[2] == 9 && padded[1] == 7)

failures += raised("negative mask", "non-negative", ->() Metaflip:Gf2:Bits.popcount(-1))
failures += raised("mask too wide for its limbs", "wider than 64", ->() Metaflip:Gf2:Bits.to_limbs(1 << 64, i64[1], 0, 1))
failures += raised("from_hex uppercase", "lowercase hexadecimal", ->() Metaflip:Gf2:Bits.from_hex("FF"))
failures += check("parse_hex empty", Metaflip:Gf2:Bits.parse_hex("", 0, 0) == -1)
failures += check("parse_hex junk", Metaflip:Gf2:Bits.parse_hex("12g4", 0, 4) == -1)
failures += check("parse_hex ignores bytes outside the range", Metaflip:Gf2:Bits.parse_hex("zz1fzz", 2, 4) == 31)
failures += check("parse_hex keeps leading zeros harmless", Metaflip:Gf2:Bits.parse_hex("000000000000000000ff", 0, 20) == 255)
failures += check("limbs_for", Metaflip:Gf2:Bits.limbs_for(0) == 1 && Metaflip:Gf2:Bits.limbs_for(64) == 1 && Metaflip:Gf2:Bits.limbs_for(65) == 2 && Metaflip:Gf2:Bits.limbs_for(1024) == 16)

# ---- fixtures: the originals' verdicts ------------------------------------------------
cases = table("cases.tsv")
bases = ["strassen_2x2x2", "rank23_3x3x3", "rank47_4x4x4", "wide68_2x4x17", "wide145_2x5x29", "wide264_4x11x24", "wide529_3x23x23"]
base_rows = {}
cases.each -> (row)
  base_rows[row[0]] = row if row[2] == "base"

bases.each -> (name)
  path = fixtures + "/" + name + ".mfw"
  row = base_rows[name + ".mfw"]
  text = read_file(path)
  scheme = Metaflip:Gf2:Scheme.parse(text)
  dims = row[1].split("x").map -> (s) s.to_i
  failures += check(name + " shape", scheme.n == dims[0] && scheme.m == dims[1] && scheme.p == dims[2])
  failures += check(name + " rank", scheme.rank == row[5].to_i)
  failures += check(name + " density", scheme.density == row[6].to_i)
  failures += check(name + " blob is the file", scheme.blob == text)
  failures += check(name + " sha256", scheme.sha256 == row[7])
  failures += check(name + " sorted is the identity", scheme.sorted.equal_terms?(scheme))
  failures += check(name + " read", Metaflip:Gf2:Scheme.read(path, dims).equal_terms?(scheme))
  failures += check(name + " terms", scheme.terms.size == scheme.rank && scheme.term(0)[0] == scheme.us[0])
  failures += check(name + " dense gate", scheme.defect(:dense) == nil)
  failures += check(name + " sparse gate", scheme.defect(:sparse) == nil)
  failures += check(name + " both gates", scheme.defect(:both) == nil && scheme.exact? && scheme.verify.equal_terms?(scheme))
  packed = scheme.pack
  failures += check(name + " packed density", packed.density == scheme.density)
  back = packed.masks
  same = true
  (0...scheme.rank).each -> (t)
    same = false if back[0][t] != scheme.us[t] || back[1][t] != scheme.vs[t] || back[2][t] != scheme.ws[t]
  failures += check(name + " packed round trip", same)
  failures += check(name + " unshuffled copy sorts back", Metaflip:Gf2:Scheme.from_terms(scheme.n, scheme.m, scheme.p, scheme.terms.reverse).sorted.equal_terms?(scheme))

# ---- mutants: strict parse and the two gates --------------------------------------------
# Rejected by the strict reader, with the cause named (read_blob's acceptance rule).
parse_causes = {
  "wrong_term_count": "wrong term count", "short_file": "wrong term count",
  "no_final_newline": "wrong term count", "extra_blank_at_end": "wrong term count",
  "bad_tag": "malformed MFW1 header", "bad_header_fields": "malformed MFW1 header",
  "zero_dimension": "malformed MFW1 header", "header_double_space": "malformed MFW1 header",
  "comment_line": "malformed MFW1 header", "trailing_space": "malformed MFW1 header",
  "empty_file": "malformed MFW1 header", "comments_only": "malformed MFW1 header",
  "non_canonical_order": "terms out of canonical order", "duplicated_term": "duplicate term",
  "cancelling_pair": "duplicate term", "uppercase_hex": "uppercase hexadecimal",
  "leading_zero": "leading zero", "blank_line": "blank line", "crlf": "carriage return",
  "tab_separator": "unexpected byte", "four_words": "unexpected byte",
  "junk_row": "non-canonical MFW1 text", "r_prefix_in_mfw1": "non-canonical MFW1 text"
}
defects = {}
table("defects.tsv").each -> (row)
  defects[row[0]] = row

cases.each -> (row)
  kind = row[2]
  file = row[0]
  if file.starts_with?("mutants/")
    text = read_file(fixtures + "/" + file)
    dims = row[1].split("x").map -> (s) s.to_i
    if kind == "shape_mismatch"
      failures += raised(file + " parse", "MFW1 shape mismatch", ->() Metaflip:Gf2:Scheme.parse(text, dims))
    elsif parse_causes[kind] != nil
      cause = parse_causes[kind]
      failures += raised(file + " parse", cause, ->() Metaflip:Gf2:Scheme.parse(text))
    else
      scheme = Metaflip:Gf2:Scheme.parse(text)
      message = row[5]
      [:dense, :sparse, :both].each -> (gate)
        found = scheme.defect(gate)
        failures += check(file + " " + gate.to_s + " gate rejects", found != nil)
        if found != nil
          failures += check(file + " " + gate.to_s + " message", found.message == message)
      failures += check(file + " not exact?", !scheme.exact?)
      if defects[file] != nil
        golden = defects[file]
        found = scheme.defect(:sparse)
        failures += check(file + " coefficient a", found.a == golden[1].to_i && found.b == golden[2].to_i)
        failures += check(file + " expected mask", found.expected == Metaflip:Gf2:Bits.from_hex(golden[3]))
        failures += check(file + " actual mask", found.actual == Metaflip:Gf2:Bits.from_hex(golden[4]))
        failures += check(file + " kind", found.kind == :coefficient)
      else
        failures += check(file + " kind", scheme.defect(:dense).kind == :range)
      failures += raised(file + " verify", message, ->() scheme.verify)

# Legacy certificate formats are not canonical MFW1.
["3x3x3_rank23_checkpoint.txt", "strassen_2x2x2_R.txt", "wide68_2x4x17_R.txt", "strassen_2x2x2_commented.txt"].each -> (name)
  failures += raised(name + " strict parse", "malformed MFW1 header", ->() Metaflip:Gf2:Scheme.parse(read_file(fixtures + "/" + name)))

# ---- orientation against mmc_gf2_alg.py --------------------------------------------------------
orient = {}
table("orient.tsv").each -> (row)
  orient[row[0] + "/" + row[1]] = row

bases.each -> (name)
  scheme = Metaflip:Gf2:Scheme.parse(read_file(fixtures + "/" + name + ".mfw"))
  shape_label = -> (s) s == nil ? "none" : "[s.n]x[s.m]x[s.p]"
  digest = -> (s) s == nil ? "-" : s.sha256
  moves = {
    "cyclic_shift": scheme.cyclic_shift, "transpose": scheme.transpose,
    "perm012": scheme.oriented([0, 1, 2]), "perm120": scheme.oriented([1, 2, 0]),
    "perm201": scheme.oriented([2, 0, 1]), "perm210": scheme.oriented([2, 1, 0]),
    "perm102": scheme.oriented([1, 0, 2]), "perm021": scheme.oriented([0, 2, 1]),
    "orient_as_sorted": scheme.orient_as(scheme.sorted_shape),
    "orient_as_impossible": scheme.orient_as([scheme.n + 1, scheme.m, scheme.p])
  }
  moves.each -> (move, result)
    golden = orient[name + "/" + move.to_s]
    failures += check(name + " " + move.to_s + " shape", shape_label.call(result) == golden[2])
    failures += check(name + " " + move.to_s + " digest", digest.call(result) == golden[3])
  # the S3 moves compose: three cyclic shifts are the identity, a double transpose too
  failures += check(name + " cyclic order 3", scheme.cyclic_shift.cyclic_shift.cyclic_shift.sorted.equal_terms?(scheme.sorted))
  failures += check(name + " transpose involution", scheme.transpose.transpose.sorted.equal_terms?(scheme.sorted))
  failures += check(name + " orientations stay exact", scheme.cyclic_shift.exact?(:dense) && scheme.transpose.exact?(:sparse))

failures += check("sorted_shape", Metaflip:Gf2:Scheme.naive(5, 2, 3).sorted_shape[0] == 2 && Metaflip:Gf2:Scheme.naive(5, 2, 3).sorted_shape[2] == 5)
failures += check("permuted_shape", Metaflip:Gf2:Scheme.permuted_shape([7, 8, 9], [1, 2, 0]) == [8, 9, 7])
failures += check("orient_perms", Metaflip:Gf2:Scheme.orient_perms.size == 6 && Metaflip:Gf2:Scheme.orient_perms[3][0] == 2)
failures += raised("oriented rejects a non-permutation", "not an orientation", ->() Metaflip:Gf2:Scheme.naive(2, 2, 2).oriented([0, 0, 1]))

# ---- naive schemes, against mmc_gf2_alg.naive ---------------------------------------------------
table("naive.tsv").each -> (row)
  dims = row[0].split("x").map -> (s) s.to_i
  scheme = Metaflip:Gf2:Scheme.naive(dims[0], dims[1], dims[2])
  failures += check("naive " + row[0] + " rank", scheme.rank == row[1].to_i)
  failures += check("naive " + row[0] + " density", scheme.density == row[2].to_i)
  failures += check("naive " + row[0] + " sha256", scheme.sha256 == row[3])
  failures += check("naive " + row[0] + " exact", scheme.exact?)
  # 1,024-bit masks: knock out the last term, then swap one bit of a middle factor
  if scheme.rank == 1024
    short = Metaflip:Gf2:Scheme.from_terms(dims[0], dims[1], dims[2], scheme.terms.slice(0, 1023))
    failures += check("naive " + row[0] + " short dense", short.defect(:dense) != nil && short.defect(:dense).message == short.defect(:sparse).message)
    bent_vs = scheme.vs.map -> (v) v
    bent_vs[500] = bent_vs[500] ^ (1 << 1023) if dims[1] * dims[2] == 1024
    bent = Metaflip:Gf2:Scheme.new(dims[0], dims[1], dims[2], scheme.us, bent_vs, scheme.ws)
    failures += check("naive " + row[0] + " bent", dims[1] * dims[2] != 1024 || bent.defect(:both) != nil)

# ---- cleaned, against mmc_gf2_alg.clean --------------------------------------------------------------------
dirty_us = []
dirty_vs = []
dirty_ws = []
want = []
table("clean.tsv").each -> (row)
  triple = [Metaflip:Gf2:Bits.from_hex(row[1]), Metaflip:Gf2:Bits.from_hex(row[2]), Metaflip:Gf2:Bits.from_hex(row[3])]
  if row[0] == "in"
    dirty_us.push(triple[0])
    dirty_vs.push(triple[1])
    dirty_ws.push(triple[2])
  else
    want.push(triple)
dirty = Metaflip:Gf2:Scheme.new(3, 3, 3, dirty_us, dirty_vs, dirty_ws)
clean = dirty.cleaned
failures += check("cleaned rank", clean.rank == want.size)
same_order = clean.rank == want.size
(0...want.size).each -> (t)
  same_order = false if t < clean.rank && (clean.us[t] != want[t][0] || clean.vs[t] != want[t][1] || clean.ws[t] != want[t][2])
failures += check("cleaned keeps first-occurrence order", same_order)
failures += check("a zero factor is a range defect until cleaned", dirty.defect(:dense).kind == :range)
failures += check("cleaned is idempotent", clean.cleaned.equal_terms?(clean))
real = Metaflip:Gf2:Scheme.parse(read_file(fixtures + "/rank23_3x3x3.mfw"))
padding = real.terms
padding.push([1, 2, 4])
padding.push([0, 1, 1])
padding.push([1, 2, 4])
padding.push([5, 0, 1])
padded = Metaflip:Gf2:Scheme.from_terms(3, 3, 3, padding)
failures += check("foreign pairs and zero factors clean away, leaving the scheme exact", padded.cleaned.equal_terms?(real) && padded.cleaned.exact?)

# ---- very short and empty texts (no stable string storage behind them) ----------------------------------------------------
failures += raised("empty text", "malformed MFW1 header", ->() Metaflip:Gf2:Scheme.parse(""))
failures += raised("one byte", "malformed MFW1 header", ->() Metaflip:Gf2:Scheme.parse("M"))
failures += raised("no newline", "malformed MFW1 header", ->() Metaflip:Gf2:Scheme.parse("MFW1 1 1 1 1"))
failures += raised("header only, rows missing", "wrong term count", ->() Metaflip:Gf2:Scheme.parse("MFW1 1 1 1 1\n"))
failures += check("a one-term scheme", Metaflip:Gf2:Scheme.parse("MFW1 1 1 1 1\n1 1 1\n").exact?)
failures += check("a rank-zero header", Metaflip:Gf2:Scheme.parse("MFW1 1 1 1 0\n").rank == 0)
failures += check("parse_hex of a short string", Metaflip:Gf2:Bits.parse_hex("f", 0, 1) == 15 && Metaflip:Gf2:Bits.parse_hex("abcde", 1, 3) == 188)

# ---- class contracts ----------------------------------------------------------------------------------
failures += raised("dimensions", "positive", ->() Metaflip:Gf2:Scheme.new(0, 2, 2, [], [], []))
failures += raised("array lengths", "equal lengths", ->() Metaflip:Gf2:Scheme.new(2, 2, 2, [1], [1, 2], [1]))
failures += raised("unknown gate", "unknown gate", ->() Metaflip:Gf2:Scheme.naive(2, 2, 2).defect(:third))
empty = Metaflip:Gf2:Scheme.new(2, 2, 2, [], [], [])
failures += check("empty scheme parses and is inexact", Metaflip:Gf2:Scheme.parse(empty.blob).rank == 0 && empty.defect(:both) != nil)
failures += check("empty blob", empty.blob == "MFW1 2 2 2 0\n")
odd = Metaflip:Gf2:Scheme.new(2, 2, 2, [1, 1, 1], [1, 1, 1], [1, 1, 1])
failures += check("blob keeps duplicates, sorted", odd.blob == "MFW1 2 2 2 3\n1 1 1\n1 1 1\n1 1 1\n")
failures += check("release is safe on a fresh scheme", Metaflip:Gf2:Scheme.naive(2, 2, 2).release == nil)

# A scheme with a term repeated three times in the middle is exact (odd cancels), non-canonical, gate-clean.
naive = Metaflip:Gf2:Scheme.naive(2, 2, 2)
extra = naive.terms
extra.push(naive.term(3))
extra.push(naive.term(3))
padded_scheme = Metaflip:Gf2:Scheme.from_terms(2, 2, 2, extra)
failures += check("duplicate pairs cancel in both gates", padded_scheme.exact?(:dense) && padded_scheme.exact?(:sparse))
failures += raised("but the strict reader refuses them", "duplicate term", ->() Metaflip:Gf2:Scheme.parse(padded_scheme.blob))

if failures > 0
  << "gf2 scheme: " + failures.to_s + " failure(s)"
  exit(1)
<< "PASS gf2 scheme library"

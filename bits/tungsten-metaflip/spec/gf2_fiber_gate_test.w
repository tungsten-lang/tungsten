# Tests of the independent second exactness gate (lib/metaflip/gf2/fiber_gate.w)
# and of the way Scheme#defect(:both) and TensorVerifier.verify_text combine it
# with the packed gates.
#
#   1. fixtures: every golden scheme and every mutant of spec/fixtures/gf2_scheme
#      gets the verdict of the original Python/Ruby tooling on all three routes
#      (Integer masks, canonical text, certificate text);
#   2. a brute-force reference that shares no code with any gate decides 500
#      random schemes; the fiber gate must agree on each;
#   3. the two readers of each pair (Scheme.parse / ffpk_parse, TensorVerifier.read
#      / FiberGate.read_certificate) are run over randomly damaged copies of every
#      certificate format: whatever the first accepts, the second must read as
#      the same factors, bit for bit;
#   4. fault injection: when the two paths are handed different data (what a
#      reader or limb-conversion fault on one side amounts to) the combination
#      raises "gate disagreement" instead of accepting or rejecting;
#   5. schemes beyond the fiber gate's slab are reported as such and left to
#      the packed gates.
#
# Prints FAIL lines and exits 1 on any failure, else PASS.
use ../lib/metaflip/gf2/tensor_verifier

fixtures = __DIR__ + "/fixtures/gf2_scheme"
counts = {"checks" => 0, "failures" => 0}

-> check(counts, label, ok)
  counts["checks"] += 1
  if !ok
    counts["failures"] += 1
    << "FAIL " + label

# The message of the error `call` raises, or "" when it returns.
-> message_of(call)
  message = ""
  begin
    call.call
  rescue e
    message = "[e]"
  message

-> raises(counts, label, expected_part, call)
  message = message_of(call)
  counts["checks"] += 1
  if message == "" || message.index(expected_part) == nil
    counts["failures"] += 1
    << "FAIL " + label + ": expected an error containing '" + expected_part + "', got '" + message + "'"

-> table(name)
  rows = []
  read_file(__DIR__ + "/fixtures/gf2_scheme/" + name).split("\n").each -> (line)
    if line != "" && !line.starts_with?("#")
      rows.push(line.split("\t"))
  rows

-> dims_of(text)
  text.split("x").map -> (s) s.to_i

# The Integer in the 32-bit limbs slab[base, base + stride).
-> slab_mask(slab, base, stride)
  x = 0
  j = stride - 1
  while j >= 0
    x = (x << 32) | slab[base + j]
    j -= 1
  x

# True when the fiber gate's certificate reader fills its slab with exactly the
# factors of `packed` (what TensorVerifier.read made of the same text).
-> same_factors?(text, packed)
  stride = ffpk_stride(packed.n, packed.m, packed.p)
  words = 3 * stride * packed.rank
  slab = i64[words]
  return false if Metaflip:Gf2:FiberGate.read_certificate(text, packed.n, packed.m, packed.p, slab, words) != packed.rank
  masks = packed.masks
  same = true
  (0...packed.rank).each -> (t)
    (0...3).each -> (axis)
      same = false if slab_mask(slab, (3 * t + axis) * stride, stride) != masks[axis][t]
  same

# ---- 1. fixtures -----------------------------------------------------------------
bases = ["strassen_2x2x2", "rank23_3x3x3", "rank47_4x4x4", "repeated94_4x4x8", "wide68_2x4x17", "wide145_2x5x29", "wide264_4x11x24", "wide529_3x23x23"]
texts = {}
bases.each -> (name)
  text = read_file(fixtures + "/" + name + ".mfw")
  texts[name] = text
  scheme = Metaflip:Gf2:Scheme.parse(text)
  n = scheme.n
  m = scheme.m
  p = scheme.p
  check(counts, name + " is within the slab", Metaflip:Gf2:FiberGate.applicable?(n, m, p, scheme.rank))
  check(counts, name + " masks route", Metaflip:Gf2:FiberGate.masks_verdict(n, m, p, scheme.us, scheme.vs, scheme.ws) == 1)
  check(counts, name + " canonical text route", Metaflip:Gf2:FiberGate.text_verdict(text, n, m, p, scheme.rank) == 1)
  check(counts, name + " certificate route", Metaflip:Gf2:FiberGate.certificate_verdict(text, n, m, p, scheme.rank) == 1)
  check(counts, name + " both paths, from the masks", scheme.defect(:both) == nil && scheme.exact?)
  check(counts, name + " both paths, from the text", scheme.defect(:both, text) == nil && scheme.exact?(:both, text) && scheme.verify(:both, text).equal_terms?(scheme))
  reversed = Metaflip:Gf2:Scheme.from_terms(n, m, p, scheme.terms.reverse)
  check(counts, name + " term order does not matter to the masks route", Metaflip:Gf2:FiberGate.masks_verdict(n, m, p, reversed.us, reversed.vs, reversed.ws) == 1)
  check(counts, name + " another rank is not the same reading", Metaflip:Gf2:FiberGate.text_verdict(text, n, m, p, scheme.rank + 1) == -2)
  check(counts, name + " another shape is not the same reading", Metaflip:Gf2:FiberGate.text_verdict(text, n, m, p + 1, scheme.rank) == -2 && Metaflip:Gf2:FiberGate.certificate_verdict(text, n, m, p + 1, scheme.rank) == -2)
  record = Metaflip:Gf2:TensorVerifier.verify_text(text, n, m, p)
  check(counts, name + " verifier record", record[:exact] == true && record[:rank] == scheme.rank)
  strict = Metaflip:Gf2:TensorVerifier.verify_text(text, nil, nil, nil, :both, true)
  check(counts, name + " strict verifier record", strict[:exact] == true && strict[:rank] == scheme.rank && strict[:sha256] == record[:sha256])
  packed = Metaflip:Gf2:TensorVerifier.read(text, n, m, p)
  check(counts, name + " both readers store the same factors", same_factors?(text, packed))

# Mutants the strict reader accepts: the original tooling's verdict is "inexact"
# (a wrong coefficient, or a zero or out-of-range factor) for every one.
cases = table("cases.tsv")
inexact_mutants = 0
cases.each -> (row)
  file = row[0]
  if file.starts_with?("mutants/")
    text = read_file(fixtures + "/" + file)
    scheme = nil
    begin
      scheme = Metaflip:Gf2:Scheme.parse(text)
    rescue e
      scheme = nil
    if scheme != nil && scheme.rank > 0
      inexact_mutants += 1
      check(counts, file + " masks route rejects", Metaflip:Gf2:FiberGate.masks_verdict(scheme.n, scheme.m, scheme.p, scheme.us, scheme.vs, scheme.ws) == 0)
      if scheme.range_defect == nil
        check(counts, file + " canonical text route rejects", Metaflip:Gf2:FiberGate.text_verdict(text, scheme.n, scheme.m, scheme.p, scheme.rank) == 0)
        check(counts, file + " certificate route rejects", Metaflip:Gf2:FiberGate.certificate_verdict(text, scheme.n, scheme.m, scheme.p, scheme.rank) == 0)
      # The golden message is the original tooling's. A shape_mismatch mutant
      # has no such message here: read without an expected shape it is a
      # well-formed scheme of the shape its header names, and simply inexact.
      want = row[2] == "shape_mismatch" ? "inexact GF(2) tensor at coefficients" : row[5]
      check(counts, file + " both paths reject, from the masks", message_of(->() scheme.verify(:both)).starts_with?(want))
      check(counts, file + " both paths reject, from the text", message_of(->() scheme.verify(:both, text)).starts_with?(want))
      check(counts, file + " verifier message", message_of(->() Metaflip:Gf2:TensorVerifier.verify_text(text, nil, nil, nil, :both, true)).starts_with?(want))
check(counts, "the fixtures hold inexact mutants (" + inexact_mutants.to_s + ")", inexact_mutants >= 5)

# Mutants the Ruby verifier accepts (double spaces, tabs, CRLF, comments, blank
# lines, leading zeros, any term order, cancelling pairs, no final newline):
# the lenient reader accepts them, so the fiber gate's reader has to as well.
lenient_mutants = 0
cases.each -> (row)
  if row[0].starts_with?("mutants/") && row[3] == "0"
    lenient_mutants += 1
    text = read_file(fixtures + "/" + row[0])
    shape = dims_of(row[1])
    packed = Metaflip:Gf2:TensorVerifier.read(text, shape[0], shape[1], shape[2])
    check(counts, row[0] + " rank", packed.rank == row[5].to_i)
    check(counts, row[0] + " both readers store the same factors", same_factors?(text, packed))
    check(counts, row[0] + " certificate route", Metaflip:Gf2:FiberGate.certificate_verdict(text, shape[0], shape[1], shape[2], packed.rank) == 1)
    check(counts, row[0] + " verifier record", Metaflip:Gf2:TensorVerifier.verify_text(text, shape[0], shape[1], shape[2])[:rank] == packed.rank)
check(counts, "the fixtures hold leniently accepted mutants (" + lenient_mutants.to_s + ")", lenient_mutants >= 20)

# The other certificate formats: a checkpoint, R-prefixed rows, comments.
legacy = [["3x3x3_rank23_checkpoint.txt", [3, 3, 3]], ["strassen_2x2x2_R.txt", [2, 2, 2]], ["wide68_2x4x17_R.txt", [2, 4, 17]], ["strassen_2x2x2_commented.txt", [2, 2, 2]]]
legacy.each -> (entry)
  name = entry[0]
  shape = entry[1]
  text = read_file(fixtures + "/" + name)
  texts[name] = text
  packed = Metaflip:Gf2:TensorVerifier.read(text, shape[0], shape[1], shape[2])
  check(counts, name + " certificate route", Metaflip:Gf2:FiberGate.certificate_verdict(text, shape[0], shape[1], shape[2], packed.rank) == 1)
  check(counts, name + " both readers store the same factors", same_factors?(text, packed))
  check(counts, name + " verifier record", Metaflip:Gf2:TensorVerifier.verify_text(text, shape[0], shape[1], shape[2])[:rank] == packed.rank)
  check(counts, name + " is not canonical text", Metaflip:Gf2:FiberGate.text_verdict(text, shape[0], shape[1], shape[2], packed.rank) == -2)

# Decimal factors of several limbs: the 529-bit scheme as a checkpoint and as corpus rows.
wide = Metaflip:Gf2:Scheme.parse(texts["wide529_3x23x23"])
checkpoint = StringBuffer()
rows_only = StringBuffer()
checkpoint.append(wide.rank.to_s + "\n")
(0...wide.rank).each -> (t)
  line = wide.us[t].to_s + " " + wide.vs[t].to_s + " " + wide.ws[t].to_s + "\n"
  checkpoint.append(t % 2 == 0 ? "R " + line : line)
  rows_only.append("R\t" + line)
[["decimal checkpoint", checkpoint.to_s], ["decimal corpus rows", rows_only.to_s]].each -> (entry)
  packed = Metaflip:Gf2:TensorVerifier.read(entry[1], 3, 23, 23)
  check(counts, entry[0] + " certificate route", Metaflip:Gf2:FiberGate.certificate_verdict(entry[1], 3, 23, 23, packed.rank) == 1)
  check(counts, entry[0] + " both readers store the same factors", same_factors?(entry[1], packed))
  check(counts, entry[0] + " verifier record", Metaflip:Gf2:TensorVerifier.verify_text(entry[1], 3, 23, 23)[:rank] == wide.rank)
texts["decimal checkpoint"] = checkpoint.to_s

# ---- 2. random schemes against a brute-force reference -----------------------------
-> lcg(state) (i64) i64
  (state * 6364136223846793005 + 1442695040888963407) & 9223372036854775807 ## i64

-> rand(rng, bound)
  rng[0] = lcg(rng[0])
  (rng[0] >> 20) % bound

-> random_mask(rng, width, percent)
  x = 0
  (0...width).each -> (b)
    x = x | (1 << b) if rand(rng, 100) < percent
  x = 1 << rand(rng, width) if x == 0
  x

# True when every coefficient of the scheme is that of the matrix-multiplication
# tensor, straight from the definition with Integer shifts.
-> brute_exact?(scheme)
  n = scheme.n
  m = scheme.m
  p = scheme.p
  a = 0
  while a < n * m
    b = 0
    while b < m * p
      actual = 0
      (0...scheme.rank).each -> (t)
        actual = actual ^ scheme.ws[t] if ((scheme.us[t] >> a) & 1) == 1 && ((scheme.vs[t] >> b) & 1) == 1
      expected = 0
      expected = 1 << ((a / m) * p + b % p) if a % m == b / p
      return false if actual != expected
      b += 1
    a += 1
  true

# The naive scheme after `steps` random flips (exactness-preserving).
-> flipped_scheme(rng, n, m, p, steps)
  rows = Metaflip:Gf2:Scheme.naive(n, m, p).terms
  steps.times ->
    i = rand(rng, rows.size)
    j = rand(rng, rows.size)
    axis = rand(rng, 3)
    x = (axis + 1) % 3
    y = (axis + 2) % 3
    if i != j && rows[i][axis] == rows[j][axis] && rows[i][x] != rows[j][x] && rows[i][y] != rows[j][y]
      rows[i][x] = rows[i][x] ^ rows[j][x]
      rows[j][y] = rows[i][y] ^ rows[j][y]
  Metaflip:Gf2:Scheme.from_terms(n, m, p, rows)

# Checks the fiber gate on the masks, on the canonical text when the scheme has
# one (no repeated term), and the combination with the packed gates.
-> agree_with_brute(counts, label, scheme)
  want = brute_exact?(scheme) ? 1 : 0
  check(counts, label + " masks route", Metaflip:Gf2:FiberGate.masks_verdict(scheme.n, scheme.m, scheme.p, scheme.us, scheme.vs, scheme.ws) == want)
  check(counts, label + " both paths", (scheme.defect(:both) == nil) == (want == 1))
  text = scheme.blob
  parsed = nil
  begin
    parsed = Metaflip:Gf2:Scheme.parse(text)
  rescue e
    parsed = nil
  if parsed != nil
    check(counts, label + " canonical text route", Metaflip:Gf2:FiberGate.text_verdict(text, scheme.n, scheme.m, scheme.p, scheme.rank) == want)
    check(counts, label + " certificate route", Metaflip:Gf2:FiberGate.certificate_verdict(text, scheme.n, scheme.m, scheme.p, scheme.rank) == want)
    check(counts, label + " both paths, from the text", (parsed.defect(:both, text) == nil) == (want == 1))
  want

rng = [20261112]
shapes = [[1, 9, 9], [2, 8, 9], [3, 9, 4], [1, 13, 5], [4, 4, 5], [2, 3, 3], [5, 2, 7], [3, 7, 3], [1, 1, 1], [1, 2, 3], [2, 2, 2], [3, 3, 3], [7, 1, 9], [2, 11, 3]]
exact_seen = 0
inexact_seen = 0
shapes.each -> (shape)
  widths = [shape[0] * shape[1], shape[1] * shape[2], shape[0] * shape[2]]
  12.times ->
    walked = flipped_scheme(rng, shape[0], shape[1], shape[2], rand(rng, 80))
    exact_seen += agree_with_brute(counts, "flip walk " + walked.shape_key, walked)
    terms = walked.terms
    axis = rand(rng, 3)
    terms[rand(rng, terms.size)][axis] = random_mask(rng, widths[axis], 40)
    damaged = Metaflip:Gf2:Scheme.from_terms(shape[0], shape[1], shape[2], terms)
    inexact_seen += 1 - agree_with_brute(counts, "damaged walk " + damaged.shape_key, damaged)
    random_terms = (0...(1 + rand(rng, 9))).map -> (t) [random_mask(rng, widths[0], 30), random_mask(rng, widths[1], 30), random_mask(rng, widths[2], 30)]
    randoms = Metaflip:Gf2:Scheme.from_terms(shape[0], shape[1], shape[2], random_terms)
    inexact_seen += 1 - agree_with_brute(counts, "random " + randoms.shape_key, randoms)
check(counts, "the random schemes include exact ones (" + exact_seen.to_s + ")", exact_seen > 100)
check(counts, "the random schemes include inexact ones (" + inexact_seen.to_s + ")", inexact_seen > 200)

# A term repeated three times is the term once: exact on every in-memory route.
naive = Metaflip:Gf2:Scheme.naive(2, 2, 2)
extra = naive.terms
extra.push(naive.term(3))
extra.push(naive.term(3))
tripled = Metaflip:Gf2:Scheme.from_terms(2, 2, 2, extra)
check(counts, "repeated terms cancel in pairs in the fiber gate too", Metaflip:Gf2:FiberGate.masks_verdict(2, 2, 2, tripled.us, tripled.vs, tripled.ws) == 1 && tripled.exact?)
doubled = Metaflip:Gf2:Scheme.from_terms(2, 2, 2, extra.slice(0, 9))
check(counts, "an even repeat is a missing term", Metaflip:Gf2:FiberGate.masks_verdict(2, 2, 2, doubled.us, doubled.vs, doubled.ws) == 0 && !doubled.exact?)

# ---- 3. the readers, over damaged certificates ---------------------------------------
# One random edit of a text: a byte replaced, removed or inserted.
-> damaged_text(rng, text)
  pieces = ["0", "1", "2", "9", "a", "f", "g", "A", "R", " ", "  ", "\t", "\n", "\r", "#", "-", "x", "M", ""]
  at = rand(rng, text.size)
  piece = pieces[rand(rng, pieces.size)]
  keep = rand(rng, 3) == 0 ? at : at + 1
  head = at == 0 ? "" : text.slice(0, at)
  tail = keep >= text.size ? "" : text.slice(keep, text.size - keep)
  head + piece + tail

accepted = 0
accepted_exact = 0
strict_accepted = 0
shapes_of = {"strassen_2x2x2" => [2, 2, 2], "rank23_3x3x3" => [3, 3, 3], "wide68_2x4x17" => [2, 4, 17], "3x3x3_rank23_checkpoint.txt" => [3, 3, 3], "strassen_2x2x2_R.txt" => [2, 2, 2], "wide68_2x4x17_R.txt" => [2, 4, 17], "strassen_2x2x2_commented.txt" => [2, 2, 2], "decimal checkpoint" => [3, 23, 23]}
shapes_of.keys.each -> (name)
  shape = shapes_of[name]
  300.times ->
    text = damaged_text(rng, texts[name])
    text = damaged_text(rng, text) if rand(rng, 4) == 0
    # the lenient pair
    packed = nil
    begin
      packed = Metaflip:Gf2:TensorVerifier.read(text, shape[0], shape[1], shape[2])
    rescue e
      packed = nil
    if packed != nil
      accepted += 1
      check(counts, name + " damaged: the second reader stores what the first accepted", same_factors?(text, packed))
      first = packed.defect(:both)
      accepted_exact += 1 if first == nil
      verdict = Metaflip:Gf2:FiberGate.certificate_verdict(text, shape[0], shape[1], shape[2], packed.rank)
      check(counts, name + " damaged: the two paths give one verdict", verdict == (first == nil ? 1 : 0))
    # the strict pair
    scheme = nil
    begin
      scheme = Metaflip:Gf2:Scheme.parse(text)
    rescue e
      scheme = nil
    if scheme != nil && scheme.range_defect == nil && Metaflip:Gf2:FiberGate.applicable?(scheme.n, scheme.m, scheme.p, scheme.rank)
      strict_accepted += 1
      second = Metaflip:Gf2:FiberGate.text_verdict(text, scheme.n, scheme.m, scheme.p, scheme.rank)
      check(counts, name + " damaged: ffpk_parse reads what Scheme.parse accepted", second == (scheme.defect(:dense) == nil ? 1 : 0))
check(counts, "damaged certificates the lenient reader accepts (" + accepted.to_s + ", " + accepted_exact.to_s + " still exact)", accepted > 300 && accepted_exact > 20 && accepted_exact < accepted)
check(counts, "damaged certificates the strict reader accepts (" + strict_accepted.to_s + ")", strict_accepted > 50)

# ---- 4. fault injection: the two paths handed different data ------------------------------
good_text = texts["rank23_3x3x3"]
good = Metaflip:Gf2:Scheme.parse(good_text)
# Another canonical text of the same shape and rank: one bit of the first w factor flipped.
bent_terms = good.terms
bent_terms[0][2] = bent_terms[0][2] ^ 1
bent_terms[0][2] = 6 if bent_terms[0][2] == 0
bent = Metaflip:Gf2:Scheme.from_terms(3, 3, 3, bent_terms).sorted
bent_text = bent.blob
check(counts, "the bent scheme is canonical, same shape, same rank, and inexact", Metaflip:Gf2:Scheme.parse(bent_text).rank == good.rank && !bent.exact?(:dense) && !bent.exact?)
raises(counts, "exact masks, inexact bytes", "gate disagreement: the packed gates say exact, the fiber gate says inexact", ->() good.defect(:both, bent_text))
raises(counts, "inexact masks, exact bytes", "the fiber gate says exact", ->() bent.defect(:both, good_text))
raises(counts, "bytes of another rank", "gate disagreement: the fiber gate's reader does not read the scheme", ->() good.defect(:both, texts["strassen_2x2x2"]))
raises(counts, "bytes that are not canonical", "gate disagreement: the fiber gate's reader does not read the scheme", ->() good.defect(:both, good_text + "\n"))
check(counts, "exact? does not swallow a disagreement", message_of(->() good.exact?(:both, bent_text)).index("gate disagreement") != nil)
check(counts, "a single packed gate does not consult the text", good.defect(:dense, bent_text) == nil && good.defect(:sparse, bent_text) == nil)
check(counts, "require_agreement lets agreement through", Metaflip:Gf2:FiberGate.require_agreement(nil, 1) == nil && Metaflip:Gf2:FiberGate.require_agreement(bent.defect(:dense), 0) == nil)
check(counts, "require_agreement lets a scheme beyond the slab through", Metaflip:Gf2:FiberGate.require_agreement(nil, -1) == nil)
raises(counts, "require_agreement, exact against inexact", "gate disagreement", ->() Metaflip:Gf2:FiberGate.require_agreement(nil, 0))
raises(counts, "require_agreement, inexact against exact", "gate disagreement", ->() Metaflip:Gf2:FiberGate.require_agreement(bent.defect(:dense), 1))
raises(counts, "require_agreement, unreadable", "gate disagreement", ->() Metaflip:Gf2:FiberGate.require_agreement(nil, -2))

# ---- 5. beyond the slab --------------------------------------------------------------------
too_wide = Metaflip:Gf2:Scheme.naive(1, 33, 32)
check(counts, "a 1,056-bit factor is beyond the slab", !Metaflip:Gf2:FiberGate.applicable?(1, 33, 32, too_wide.rank) && Metaflip:Gf2:FiberGate.masks_verdict(1, 33, 32, too_wide.us, too_wide.vs, too_wide.ws) == -1)
check(counts, "and is left to the packed gates", too_wide.exact? && too_wide.defect(:both, too_wide.blob) == nil)
short = Metaflip:Gf2:Scheme.from_terms(1, 33, 32, too_wide.terms.slice(0, too_wide.rank - 1))
check(counts, "which still reject", !short.exact?)
check(counts, "the widest and longest schemes of the slab", Metaflip:Gf2:FiberGate.applicable?(32, 32, 32, 16384) && Metaflip:Gf2:FiberGate.applicable?(1, 32, 32, 1024))
check(counts, "one term more is beyond it", !Metaflip:Gf2:FiberGate.applicable?(32, 32, 32, 16385) && !Metaflip:Gf2:FiberGate.applicable?(2, 2, 2, 0))
edge = Metaflip:Gf2:Scheme.naive(1, 32, 32)
check(counts, "1,024-bit factors, masks route", Metaflip:Gf2:FiberGate.masks_verdict(1, 32, 32, edge.us, edge.vs, edge.ws) == 1)
edge_text = edge.blob
check(counts, "1,024-bit factors, text routes", Metaflip:Gf2:FiberGate.text_verdict(edge_text, 1, 32, 32, 1024) == 1 && Metaflip:Gf2:FiberGate.certificate_verdict(edge_text, 1, 32, 32, 1024) == 1)
edge_vs = edge.vs.map -> (v) v
edge_vs[500] = edge_vs[500] ^ (1 << 1023)
edge_bent = Metaflip:Gf2:Scheme.new(1, 32, 32, edge.us, edge_vs, edge.ws)
check(counts, "1,024-bit factors, top bit flipped", Metaflip:Gf2:FiberGate.masks_verdict(1, 32, 32, edge_bent.us, edge_bent.vs, edge_bent.ws) == 0 && edge_bent.defect(:both) != nil)

if counts["failures"] > 0
  << "FAIL " + counts["failures"].to_s + " of " + counts["checks"].to_s + " fiber gate checks"
  exit(1)
<< "PASS gf2 fiber gate: " + counts["checks"].to_s + " checks"

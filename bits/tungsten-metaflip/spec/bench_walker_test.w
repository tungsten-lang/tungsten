# The ablation switches and stop conditions of the directed walker
# (lib/metaflip/wide/directed.w): campaign defaults, validation, equivalence of
# the uniform-proposal configuration with the packed fleet walker, target and
# report stops, and exactness under every switch. Prints FAIL lines and exits 1
# on a mismatch, else PASS.
use ../lib/metaflip/wide/directed
use ../lib/metaflip/bench/start

counts = {"checks" => 0, "failures" => 0}

-> expect(counts, label, got, want)
  counts["checks"] += 1
  if got != want
    counts["failures"] += 1
    << "FAIL " + label + ": got " + got.to_s + " want " + want.to_s

# A walker on the standard algorithm of n x m x p: [state, control, scratch, stop].
-> walker(n, m, p, nonce, mode)
  raw = Start.standard(n, m, p)
  stride = ffpk_stride(n, m, p) ## i64
  data = i64[3 * stride * 512]
  meta = i64[4]
  rank = ffpk_parse(raw, data, data.size, meta, 4) ## i64
  cap = rank + 64 ## i64
  st = i64[ffws_words_rect(n, m, p, cap)]
  ffws_init_rect(st, n, m, p, cap, data, rank, nonce)
  control = i64[ffwd_words(st, 4096)]
  ffwd_init(st, control, mode, 4096)
  [st, control, i64[12 * stride], i64[1]]

-> exact_state(st, n, m, p, best)
  stride = ffpk_stride(n, m, p) ## i64
  out = i64[3 * stride * 600]
  parity = i64[m * p * ((n * p + 31) / 32)]
  rank = ffws_export(st, out, best) ## i64
  ffpk_exact(out, out.size, rank, n, m, p, parity, parity.size, 0)

-> run(w, steps)
  ffwd_work(w[0], w[2], w[1], steps, w[3], 8)

-> snapshot(w)
  st = w[0]
  out = i64[3 * 600]
  ffws_export(st, out, 0)
  [st[4], st[5], st[6], st[7], st[8], st[9], st[10], st[11], st[23], out.to_s]

# 1. ffwd_init installs the campaign values.
w = walker(3, 3, 3, 19071, 2)
c = w[1]
expect(counts, "split period", c[46], 2000)
expect(counts, "stall threshold", c[47], 256)
expect(counts, "split on no pair", c[48], 1)
expect(counts, "split slack", c[49], 8)
expect(counts, "no target", c[50], 0)
expect(counts, "no report threshold", c[51], 0)
expect(counts, "directed proposals", c[52], 0)

# 2. ffwd_policy rejects nonsense and installs valid settings.
expect(counts, "negative period", ffwd_policy(c, -1, 256, 1, 8, 0), 0)
expect(counts, "negative stall", ffwd_policy(c, 2000, -1, 1, 8, 0), 0)
expect(counts, "no-pair flag range", ffwd_policy(c, 2000, 256, 2, 8, 0), 0)
expect(counts, "negative slack", ffwd_policy(c, 2000, 256, 1, -1, 0), 0)
expect(counts, "proposal mode range", ffwd_policy(c, 2000, 256, 1, 8, 3), 0)
expect(counts, "rejected settings change nothing", c[46] == 2000 && c[47] == 256 && c[49] == 8 && c[52] == 0, true)
expect(counts, "valid settings", ffwd_policy(c, 500, 0, 0, 2, 1), 1)
expect(counts, "settings installed", [c[46], c[47], c[48], c[49], c[52]].to_s, [500, 0, 0, 2, 1].to_s)

# In the naive 2x3x4 tensor the factors repeat with three different
# multiplicities. Every unordered (axis, slot, slot) must occur exactly once.
-> check_rect_pairs(counts, st, index) (Hash i64[] i64[])
  pairs = {}
  valid = true
  bucket = 0 ## i64
  while bucket < index[2]
    id = index[index[24]+bucket] ## i64
    axis = id / index[1] ## i64
    count = ffwd_bucket_pairs(st, index, id, -1) ## i64
    ordinal = 0 ## i64
    while ordinal < count
      ffwd_bucket_pairs(st, index, id, ordinal)
      first_slot = index[54] ## i64
      second_slot = index[55] ## i64
      key = [axis, first_slot < second_slot ? first_slot : second_slot, first_slot < second_slot ? second_slot : first_slot].to_s
      valid = false if first_slot == second_slot || pairs.key?(key) || st[st[14]+3*first_slot+axis] != st[st[14]+3*second_slot+axis]
      pairs[key] = true
      ordinal += 1
    bucket += 1
  expect(counts, "enumeration contains only unique legal pairs", valid, true)
  expect(counts, "all legal pairs of the rectangular start", pairs.size, 6*6 + 12*1 + 8*3)

rect = walker(2, 3, 4, 42, 2)
check_rect_pairs(counts, rect[0], rect[1])

# 3. Uniform proposals without a guard or extra triggers replay the packed fleet walker.
fleet = walker(3, 3, 3, 4242, 2)
ffws_work(fleet[0], fleet[2], 30000, fleet[3], 8)
same = walker(3, 3, 3, 4242, 1)
ffwd_policy(same[1], 2000, 0, 0, 8, 1)
run(same, 30000)
a = snapshot(fleet)
b = snapshot(same)
["current rank", "best rank", "rng", "proposals", "accepted", "rejected", "bits", "best bits", "void proposals", "scheme"].each_with_index -> (label, i)
  expect(counts, "uniform matches fleet: " + label, b[i], a[i])

# 4. The report threshold returns at each new best rank, the target stops exactly there.
scan = walker(3, 3, 3, 777, 2)
events = []
seen = scan[0][5]
ffwd_watch(scan[1], 0, seen)
while events.size < 40 && scan[0][7] < 400000
  run(scan, 100000)
  if scan[0][5] < seen
    seen = scan[0][5]
    events.push([seen, scan[0][7]])
    ffwd_watch(scan[1], 0, seen)
expect(counts, "walk descends", events.size > 0, true)
tail = events[events.size - 1]
stop_at = walker(3, 3, 3, 777, 2)
ffwd_watch(stop_at[1], tail[0], 0)
run(stop_at, 400000)
expect(counts, "target stop: rank", stop_at[0][5], tail[0])
expect(counts, "target stop: at the event", stop_at[0][7], tail[1])
untouched = walker(3, 3, 3, 777, 2)
run(untouched, tail[1])
expect(counts, "watching does not change the walk", snapshot(untouched).to_s, snapshot(stop_at).to_s)

# 5. Every switch keeps the walk exact and the counters consistent.
settings = [[2000, 256, 1, 8, 2, 2], [2000, 256, 1, 8, 0, 2], [2000, 256, 1, 8, 1, 2], [2000, 256, 1, 8, 0, 1], [2000, 256, 1, 8, 0, 3], [500, 256, 1, 8, 0, 2], [8000, 256, 1, 8, 0, 2], [0, 0, 1, 8, 0, 2], [2000, 0, 1, 8, 0, 2], [0, 0, 0, 8, 0, 2], [2000, 256, 1, 0, 0, 2], [2000, 256, 1, 2, 0, 2], [2000, 256, 1, 16, 0, 2], [2000, 256, 1, 8, 1, 3]]
settings.each -> (s)
  label = s.to_s
  x = walker(3, 3, 3, 31337, s[5])
  expect(counts, "policy accepted " + label, ffwd_policy(x[1], s[0], s[1], s[2], s[3], s[4]), 1)
  run(x, 40000)
  expect(counts, "current scheme exact " + label, exact_state(x[0], 3, 3, 3, 0), 1)
  expect(counts, "best scheme exact " + label, exact_state(x[0], 3, 3, 3, 1), 1)
  expect(counts, "proposals accounted " + label, x[1][9] + x[1][16], x[0][7])
  expect(counts, "flips accounted " + label, x[0][8] + x[0][9], x[0][7])
  expect(counts, "rank never above best+slack " + label, x[0][4] <= x[0][5] + s[3] + 1, true)

# 6. No split policy, no escapes; the defaults do escape.
quiet = walker(3, 3, 3, 5, 2)
ffwd_policy(quiet[1], 0, 0, 0, 8, 0)
run(quiet, 40000)
expect(counts, "no rank-raising split when disabled", quiet[1][17], 0)
zero = walker(3, 3, 3, 5, 2)
ffwd_policy(zero[1], 2000, 256, 1, 0, 0)
run(zero, 40000)
expect(counts, "slack 0 never splits", zero[1][17], 0)
campaign = walker(3, 3, 3, 5, 2)
run(campaign, 40000)
expect(counts, "the campaign policy splits", campaign[1][17] > 0, true)

# 7. Guards: none blocks nothing, nonbacktracking blocks inverses, tabu blocks repeats.
none = walker(3, 3, 3, 9, 1)
run(none, 40000)
expect(counts, "guard none blocks nothing", none[1][10] + none[1][11], 0)
inverse = walker(3, 3, 3, 9, 2)
run(inverse, 40000)
expect(counts, "nonbacktracking blocks inverses", inverse[1][10] > 0, true)
tabu = walker(3, 3, 3, 9, 3)
run(tabu, 40000)
expect(counts, "tabu blocks repeats", tabu[1][11] > 0, true)

# 8. Determinism: same nonce, same walk; another nonce, another walk.
one = walker(3, 3, 3, 100, 2)
two = walker(3, 3, 3, 100, 2)
three = walker(3, 3, 3, 101, 2)
run(one, 20000)
run(two, 20000)
run(three, 20000)
expect(counts, "same nonce", snapshot(one).to_s, snapshot(two).to_s)
expect(counts, "another nonce", snapshot(one).to_s != snapshot(three).to_s, true)

if counts["failures"] > 0
  << "FAIL " + counts["failures"].to_s + " of " + counts["checks"].to_s + " walker checks"
  exit(1)
<< "PASS bench walker: " + counts["checks"].to_s + " checks"

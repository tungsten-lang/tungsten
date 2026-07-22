# Pure-Tungsten regression for the rectangular GPU's exact +1 split-door
# portfolio. The production workers keep this small host-side enumerator inline
# so their Metal source stays self-contained; this twin pins its algebra,
# distinct-door count, epoch rotation, and source consistency.

use ../lib/metaflip/rect

-> ffrse_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL rectangular GPU split escapes: " + label
    return 1
  0

# out = [axis,target,oldfactor,part]. This mirrors the inline worker formula.
-> ffrse_door(us, vs, ws, rank, n, m, p, lanes, round, sid, out) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  axis = sid % 3 ## i64
  escape_index = sid / 3 ## i64
  target = (escape_index + round * 17) % rank ## i64
  choice = escape_index / rank ## i64
  oldfactor = us[target] ## i64
  factor_width = n * m ## i64
  if axis == 1
    oldfactor = vs[target]
    factor_width = m * p
  if axis == 2
    oldfactor = ws[target]
    factor_width = n * p
  choices_per_target = (lanes + 3 * rank - 1) / (3 * rank) ## i64
  mode = choice % 4 ## i64
  part = 0 ## i64
  if mode == 0
    donor_choice = choice / 4 ## i64
    donor = (target + 1 + donor_choice * 13 + axis * 5 + round * 7) % rank ## i64
    if axis == 0
      part = us[donor]
    if axis == 1
      part = vs[donor]
    if axis == 2
      part = ws[donor]
    tries = 0 ## i64
    while (part == 0 || part == oldfactor) && tries < rank
      donor = (donor + 1) % rank
      if axis == 0
        part = us[donor]
      if axis == 1
        part = vs[donor]
      if axis == 2
        part = ws[donor]
      tries += 1
  if mode > 0
    factor_limit = (1 << factor_width) - 1 ## i64
    valid_parts = factor_limit - 1 ## i64
    generic_choice = (choice / 4) * 3 + mode - 1 ## i64
    generic_span = ((choices_per_target + 3) / 4) * 3 ## i64
    part_ordinal = (generic_choice + round * generic_span) % valid_parts ## i64
    part = part_ordinal + 1
    if part >= oldfactor
      part += 1
  if part == 0 || part == oldfactor
    part = oldfactor ^ 1
    if part == 0
      part = 2
  out[0] = axis
  out[1] = target
  out[2] = oldfactor
  out[3] = part
  1

-> ffrse_insert(keys, key) (i64[] i64) i64
  slot = key % keys.size() ## i64
  while keys[slot] != 0
    if keys[slot] == key
      return 0
    slot = (slot + 1) % keys.size()
  keys[slot] = key
  1

-> ffrse_load(root, p, state, us, vs, ws) (String i64 i64[] i64[] i64[] i64[]) i64
  n = 2 ## i64
  m = 2 ## i64
  cap = ffr_default_capacity(n, m, p) ## i64
  seed = root + "/" + ffrp_seed_rel(n, m, p) ## String
  rank = ffr_load_scheme_cap(state, seed, n, m, p, cap, 98101 + p, 4, 4, 1000, 250) ## i64
  if rank < 1 || ffr_verify_best_exact(state, n, m, p) != 1
    return 0
  if ffw_export_best(state, us, vs, ws) != rank
    return 0
  rank

-> ffrse_exact_sample(root, p, round, sid) (String i64 i64 i64) i64
  n = 2 ## i64
  m = 2 ## i64
  cap = ffr_default_capacity(n, m, p) ## i64
  state = i64[ffr_state_size(cap)]
  us = i64[cap]
  vs = i64[cap]
  ws = i64[cap]
  rank = ffrse_load(root, p, state, us, vs, ws) ## i64
  if rank < 1
    return 0
  door = i64[4]
  z = ffrse_door(us, vs, ws, rank, n, m, p, 8192, round, sid, door) ## i64
  axis = door[0] ## i64
  target = door[1] ## i64
  oldfactor = door[2] ## i64
  part = door[3] ## i64
  if part == 0 || part == oldfactor || (oldfactor ^ part) == 0
    return 0
  outu = i64[cap]
  outv = i64[cap]
  outw = i64[cap]
  i = 0 ## i64
  while i < rank
    outu[i] = us[i]
    outv[i] = vs[i]
    outw[i] = ws[i]
    i += 1
  outu[rank] = us[target]
  outv[rank] = vs[target]
  outw[rank] = ws[target]
  if axis == 0
    outu[target] = part
    outu[rank] = oldfactor ^ part
  if axis == 1
    outv[target] = part
    outv[rank] = oldfactor ^ part
  if axis == 2
    outw[target] = part
    outw[rank] = oldfactor ^ part
  candidate = i64[ffr_state_size(cap)]
  loaded = ffr_init_terms_cap(candidate, outu, outv, outw, rank + 1, n, m, p, cap, 98201 + p + round * 31 + sid, 0, 1, 1, 1) ## i64
  if loaded != rank + 1
    return 0
  ffr_verify_best_exact(candidate, n, m, p)

-> ffrse_unique_count(root, p, round) (String i64 i64) i64
  n = 2 ## i64
  m = 2 ## i64
  cap = ffr_default_capacity(n, m, p) ## i64
  state = i64[ffr_state_size(cap)]
  us = i64[cap]
  vs = i64[cap]
  ws = i64[cap]
  rank = ffrse_load(root, p, state, us, vs, ws) ## i64
  if rank < 1
    return 0
  keys = i64[32768]
  door = i64[4]
  unique = 0 ## i64
  sid = 0 ## i64
  while sid < 8192
    z = ffrse_door(us, vs, ws, rank, n, m, p, 8192, round, sid, door)
    # Axes and targets occupy disjoint high ranges; factor masks are <= 30 bits.
    key = 1 + (door[0] * rank + door[1]) * 1073741824 + door[3] ## i64
    unique += ffrse_insert(keys, key)
    sid += 1
  unique

failed = 0 ## i64
root = __DIR__ + "/../lib/metaflip" ## String

u70 = ffrse_unique_count(root, 7, 0) ## i64
u71 = ffrse_unique_count(root, 7, 1) ## i64
u80 = ffrse_unique_count(root, 8, 0) ## i64
u81 = ffrse_unique_count(root, 8, 1) ## i64
failed += ffrse_expect("2x2x7 covers over five thousand distinct doors", u70 > 5000 && u71 > 5000)
failed += ffrse_expect("2x2x8 covers over five thousand distinct doors", u80 > 5300 && u81 > 5300)

sample_sids = [0, 1, 2, 75, 76, 77, 4095, 8191]
p = 7 ## i64
while p <= 8
  round = 0 ## i64
  while round <= 1
    i = 0 ## i64
    while i < sample_sids.size()
      failed += ffrse_expect("exact sample p=" + p.to_s() + " round=" + round.to_s() + " sid=" + sample_sids[i].to_s(), ffrse_exact_sample(root, p, round, sample_sids[i]) == 1)
      i += 1
    round += 1
  p += 1

# All specialized workers must retain the same portfolio mapping. This catches
# a newly cloned shape silently falling back to the old O(rank) affine doors.
tags = ["225","226","227","228","229","234","235","245","256","334","335","344","345","346","347","355","356","445","446","456","457","467"]
i = 0
while i < tags.size()
  path = __DIR__ + "/../lib/metaflip/kernels/rectangular/cal2zone_" + tags[i] + ".w"
  body = read_file(path)
  ok = body != nil
  if ok
    ok = body.include?("choice = escape_index / baserank") && body.include?("mode = choice % 4")
  if ok
    ok = body.include?("generic_choice = (choice / 4) * 3 + mode - 1") && body.include?("part >= oldfactor")
  if ok
    ok = body.include?("donor_choice = choice / 4") && body.include?("one quarter of the doors")
  if ok
    ok = !body.include?("escape_index * 37 + axis * 13")
  failed += ffrse_expect("worker " + tags[i] + " uses mixed split-door enumeration", ok)
  i += 1

if failed != 0
  exit(1)
<< "PASS rectangular GPU split escapes unique227=" + u70.to_s() + "/" + u71.to_s() + " unique228=" + u80.to_s() + "/" + u81.to_s() + " exact_samples=" + (sample_sids.size() * 4).to_s() + " workers=" + tags.size().to_s()

# Pure-Tungsten regression for the division-free rectangular GPU factor
# sampler. The GPU source keeps this output permutation inline so Metal can
# optimize it; this host twin pins the arithmetic and diversity behavior.

use ../lib/metaflip/kernels/bundles/rect

-> rect_sampler_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    return 1
  0

-> rect_sampler_pcg(state) (u32) u32
  sample = state ## u32
  # Host integer temporaries do not implicitly truncate after arithmetic as a
  # Metal `uint` does, so model that one multiply wrap explicitly here.
  sample = (((sample >> ((sample >> 28) + 4)) ^ sample) * 277803737) & 0xffffffff
  sample = (sample >> 22) ^ sample
  sample

-> rect_sampler_nonnegative_remainder(value, modulus) (i64 i64) i64
  remainder = value % modulus ## i64
  if remainder < 0
    remainder += modulus
  remainder

failed = 0 ## i64

# Every hot random coordinate used to normalize a signed remainder with a
# second remainder operation.  One conditional addition is algebraically
# identical for a positive modulus.  Exercise all nearby quotient/remainder
# classes through the largest rectangular worker rank.
modulus = 1 ## i64
while modulus <= 168
  value = 0 - modulus*3 - 1 ## i64
  while value <= modulus*3 + 1
    legacy = ((value % modulus) + modulus) % modulus ## i64
    normalized = rect_sampler_nonnegative_remainder(value,modulus) ## i64
    failed += rect_sampler_expect("single signed remainder matches legacy normalization", normalized == legacy)
    value += 1
  modulus += 1

# Known RXS-M-XS vectors catch signed shifts, missing u32 wraparound, constant
# changes, or a reordered output permutation.
vectors = u32[8]
expected = u32[8]
vectors[0] = 0x00000000
vectors[1] = 0x00000001
vectors[2] = 0x00003039
vectors[3] = 0x7fffffff
vectors[4] = 0x80000000
vectors[5] = 0xffffffff
vectors[6] = 0x12345678
vectors[7] = 0xdeadbeef
expected[0] = 0x00000000
expected[1] = 0x108ef29b
expected[2] = 0x3ac440c1
expected[3] = 0x52700149
expected[4] = 0x16c8005b
expected[5] = 0x21a4e086
expected[6] = 0x28ae66b1
expected[7] = 0xf635a409
i = 0 ## i64
while i < vectors.size()
  failed += rect_sampler_expect("PCG known vector " + i.to_s(), rect_sampler_pcg(vectors[i]) == expected[i])
  i += 1

# Every production factor width is a power-of-two mask. This first audit checks
# the permutation's masked range independently of the rejection loop below.
masks = u32[5]
masks[0] = 15
masks[1] = 1023
masks[2] = 262143
masks[3] = 16777215
masks[4] = 1073741823
state = 12345 ## u32
step = 0 ## i64
while step < 100000
  state = (state * 1103515245 + 12345) & 0xffffffff
  sample = rect_sampler_pcg(state) ## u32
  i = 0
  while i < masks.size()
    value = sample & masks[i] ## u32
    if value == 0
      value = 1
    if value < 1 || value > masks[i]
      failed += rect_sampler_expect("masked factor remains in range", false)
      step = 100000
      i = masks.size()
    i += 1
  step += 1

# Rejection removes the zero->one remap bias. Over this deterministic 300k
# sample audit the fifteen accepted four-bit values should remain tightly
# balanced, while the retry count stays near the expected 300000/15.
counts = i64[16]
accepted = 0 ## i64
draws = 0 ## i64
state = 12345
while accepted < 300000
  state = (state * 1103515245 + 12345) & 0xffffffff
  value = rect_sampler_pcg(state) & 15 ## u32
  draws += 1
  if value != 0
    counts[value] += 1
    accepted += 1
minimum = counts[1] ## i64
maximum = counts[1] ## i64
i = 2
while i < 16
  if counts[i] < minimum
    minimum = counts[i]
  if counts[i] > maximum
    maximum = counts[i]
  i += 1
failed += rect_sampler_expect("four-bit rejection frequencies stay balanced", maximum - minimum < 1000)
failed += rect_sampler_expect("four-bit rejection rate matches one zero in sixteen", draws - accepted > 18000 && draws - accepted < 22000)

# GPU lanes start from an arithmetic progression (`tid * 9973 + 12345`). A raw
# LCG mask exposes only 16 adjacent pairs at width four; the PCG permutation
# covers all 15*15 possible nonzero pairs across one 8192-lane launch. This is
# a lattice/correlation regression, not a claim that pair coverage proves
# uniformity; the bounded frequency audit above checks the remap bias directly.
seen_pairs = i64[256]
seen_values = i64[16]
pair_count = 0 ## i64
value_count = 0 ## i64
previous = 0 ## u32
tid = 0 ## i64
while tid < 8192
  lane_state = ((tid * 9973 + 12345) & 0xffffffff) ## u32
  jump = 0 ## i64
  while jump < 3
    lane_state = (lane_state * 1103515245 + 12345) & 0xffffffff
    jump += 1
  value = rect_sampler_pcg(lane_state) & 15 ## u32
  while value == 0
    lane_state = (lane_state * 1103515245 + 12345) & 0xffffffff
    value = rect_sampler_pcg(lane_state) & 15
  if seen_values[value] == 0
    seen_values[value] = 1
    value_count += 1
  if tid > 0
    pair = (previous << 4) | value ## u32
    if seen_pairs[pair] == 0
      seen_pairs[pair] = 1
      pair_count += 1
  previous = value
  tid += 1
failed += rect_sampler_expect("all nonzero four-bit values occur across lanes", value_count == 15)
failed += rect_sampler_expect("all nonzero four-bit adjacent pairs occur across lanes", pair_count == 225)

# The low ten bits of the bare LCG repeat exactly after 1024 states. Mixing the
# high state into the output should make almost every corresponding PCG value
# differ between consecutive 1024-state blocks.
first_block = u32[1024]
state = 12345
i = 0
while i < 1024
  state = (state * 1103515245 + 12345) & 0xffffffff
  first_block[i] = rect_sampler_pcg(state) & 1023
  i += 1
different = 0 ## i64
i = 0
while i < 1024
  state = (state * 1103515245 + 12345) & 0xffffffff
  value = rect_sampler_pcg(state) & 1023 ## u32
  if value != first_block[i]
    different += 1
  i += 1
failed += rect_sampler_expect("PCG breaks the bare LCG low-bit repeat", different > 1000)

# The wide 4x5x7 worker combines two independently permuted states.  Audit the
# exact 35-bit construction used by Metal and require both halves of the V
# mask, including bit 34, to be exercised frequently.
wide_state = 12345 ## u32
wide_hi = 0 ## i64
wide_lo = 0 ## i64
wide_value = 0 ## i64
wide_high_count = 0 ## i64
i = 0
while i < 100000
  wide_state = (wide_state * 1103515245 + 12345) & 0xffffffff
  wide_hi = rect_sampler_pcg(wide_state)
  wide_state = (wide_state * 1103515245 + 12345) & 0xffffffff
  wide_lo = rect_sampler_pcg(wide_state)
  wide_value = ((wide_hi << 32) ^ wide_lo) & 34359738367
  if wide_value < 0 || wide_value > 34359738367
    failed += rect_sampler_expect("wide sample stays in the 35-bit envelope", false)
    i = 100000
  if (wide_value & 17179869184) != 0
    wide_high_count += 1
  i += 1
failed += rect_sampler_expect("wide sampler reaches V bit 34", wide_high_count > 45000 && wide_high_count < 55000)

# A no-change step can skip only cleanup whose answer is already implied by
# the prior-step invariant.  It must not skip the scheduled density observer:
# model a density-improving flip on step 63 followed by an unmatched step 64.
# The legacy schedule first sees and records that improvement on the idle step.
model_rank = 23 ## i64
model_best = 23 ## i64
model_bestden = 141 ## i64
model_currentden = 139 ## i64
model_step = 64 ## i64
model_didplus = 0 ## i64
model_fj = 0 - 1 ## i64
model_skip_cleanup = model_didplus == 0 && model_fj < 0 ## bool
model_docap = false ## bool
if model_rank < model_best
  model_docap = true
if model_rank == model_best && (model_step % 64) == 0
  model_docap = true
if model_docap && model_currentden < model_bestden
  model_bestden = model_currentden
failed += rect_sampler_expect("unmatched move skips only local cleanup", model_skip_cleanup)
failed += rect_sampler_expect("unmatched step 64 preserves density capture", model_docap && model_bestden == 139)

# The factor-match scan walks a cyclic permutation of [0, rank).  Its hot GPU
# form replaces `(off + scan) % rank` with one conditional subtraction.  Pin
# that equivalence exhaustively across every rank the rectangular workers can
# hold, so the division removal cannot alter deterministic move replay.
rank = 1 ## i64
while rank <= 168
  off = 0 ## i64
  while off < rank
    scan = 0 ## i64
    while scan < rank
      wrapped = off + scan ## i64
      if wrapped >= rank
        wrapped -= rank
      failed += rect_sampler_expect("single-wrap scan matches remainder", wrapped == (off + scan) % rank)
      scan += 1
    off += 1
  rank += 1

# Every generated rectangular worker must use the same inline permutation and
# must agree with the profile geometry used by the coordinator.
tags = ["225","226","227","228","229","234","235","245","256","334","335","344","345","346","347","355","356","445","446","456","457","467"]
i = 0
while i < tags.size()
  path = __DIR__ + "/../lib/metaflip/kernels/rectangular/cal2zone_" + tags[i] + ".w"
  body = read_file(path)
  ok = body != nil
  if ok
    ok = body.include?("sample = state ## u32")
  if ok
    ok = body.include?("sample = ((sample >> ((sample >> 28) + 4)) ^ sample) * 277803737")
  if ok
    ok = body.include?("sample = (sample >> 22) ^ sample")
  wide = tags[i] == "457" || tags[i] == "467"
  if ok && wide
    ok = body.split("277803737").size() == 5 && body.split("sample2 = (state ^ wide_salt) ## u32").size() == 3 && body.include?("wide_salt = (mv * 747796405) ^ (tid * 289133645)") && body.split("u1 = sample\n").size() == 3 && !body.include?("u1 = sample ## i64")
  if ok && tags[i] == "457"
    ok = body.split("u1 = (((u1 & 7) << 32) ^ (sample2 ## i64)) & 34359738367").size() == 3
  if ok && tags[i] == "467"
    ok = body.split("u1 = (((u1 & 1023) << 32) ^ (sample2 ## i64)) & 4398046511103").size() == 3
  if ok && !wide
    ok = body.split("277803737").size() == 3 && !body.include?("wide_salt")
  if ok
    ok = body.include?("while u1 == 0")
  if ok
    ok = !body.include?("u1 = (((state %")
  if ok
    ok = !body.include?("u1 = 1")
  if ok
    ok = body.include?("cand = off + scan") && body.include?("if cand >= rank") && body.include?("cand = cand - rank")
  if ok
    ok = !body.include?("cand = (off + scan) % rank")
  if ok
    ok = body.include?("roll = state % 6\n    if roll < 0\n      roll = roll + 6")
  if ok
    ok = body.include?("pt = state % rank\n          if pt < 0\n            pt = pt + rank")
  if ok
    ok = body.include?("paxis = state % 3\n          if paxis < 0\n            paxis = paxis + 3")
  if ok
    ok = body.include?("fi = state % rank\n      if fi < 0\n        fi = fi + rank")
  if ok
    ok = body.include?("axis = state % 3\n      if axis < 0\n        axis = axis + 3")
  if ok
    ok = body.include?("off = state % rank\n      if off < 0\n        off = off + rank")
  if ok
    ok = !body.include?("((state % 6) + 6) % 6") && !body.include?("((state % rank) + rank) % rank") && !body.include?("((state % 3) + 3) % 3")
  if ok
    ok = body.include?("t = 0\n    if didplus == 0\n      if fj < 0\n        t = rank\n    while t < rank")
  if ok
    ok = body.include?("if didplus == 0\n      # Use rank as an out-of-range sentinel when the factor scan found no\n      # partner; both touched-slot checks then become constant-time no-ops.\n      a = rank\n      if fj >= 0\n        a = fi")
  if ok
    ok = body.split("first observed on an unmatched step 64").size() == 2
  # The defensive full audit and scheduled density observation deliberately
  # remain byte-for-byte in their original control flow.
  if ok
    ok = body.include?("dchk = step % 4096\n    if dchk == 0")
  if ok
    ok = body.include?("docap = 0\n    if rank < best\n      docap = 1\n    if rank == best\n      if (step % 64) == 0\n        docap = 1")
  n = tags[i].slice(0, 1).to_i() ## i64
  m = tags[i].slice(1, 1).to_i() ## i64
  p = tags[i].slice(2, 1).to_i() ## i64
  cap = ffrp_gpu_cap(n, m, p) ## i64
  wpg = ffrp_gpu_wpg(n, m, p) ## i64
  mask_bytes = ffrgb_mask_bytes(n, m, p) ## i64
  shared = cap * wpg ## i64
  shared_kind = "i32"
  if mask_bytes == 8
    shared_kind = "i64"
  if ok
    ok = body.include?("CAP = " + cap.to_s()) && body.include?("WPG = " + wpg.to_s())
  if ok
    ok = body.split("gpu.shared_" + shared_kind + "(" + shared.to_s() + ")").size() == 4
  if ok
    ok = ffrgb_cap(n, m, p) == cap && ffrgb_shared_bytes(n, m, p) == shared * mask_bytes * 3 && ffrgb_geometry_valid(n, m, p) == 1
  failed += rect_sampler_expect("worker " + tags[i] + " sampler and geometry match profile", ok)
  i += 1

if failed != 0
  exit(1)
<< "PASS rectangular GPU sampler retries=" + (draws - accepted).to_s() + " frequency_range=" + (maximum - minimum).to_s() + " lane_pairs=" + pair_count.to_s() + " workers=" + tags.size().to_s()

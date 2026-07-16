use ../lib/metaflip/kernels/rect_kxor

-> ffrxsc_fail(label) (String) i64
  << "FAIL rectangular kxor selection coverage: " + label
  exit(1)
  0

root = __DIR__ + "/../lib/metaflip"
seed_path = root + "/seeds/gf2/matmul_2x2x7_rank25_catalog_gf2.txt"
state = ffrx_load_exact(seed_path, 2, 2, 7, 6)
if state == nil
  z = ffrxsc_fail("exact rank-25 seed")
rank = ffr_best_rank(state) ## i64
cap = ffr_default_capacity(2, 2, 7) ## i64
us = i64[cap]
vs = i64[cap]
ws = i64[cap]
if ffw_export_best(state, us, vs, ws) != rank
  z = ffrxsc_fail("seed export")

requested = 256 ## i64
k = 6 ## i64
processed = i64[requested * k]
covered = 0 ## i64
attempts = 0 ## i64
attempt_cap = ffrx_selection_attempt_cap(requested) ## i64
while covered < requested && attempts < attempt_cap
  selected = i64[7]
  if ffrx_choose_subset(us, vs, ws, rank, k, attempts * 17, selected) == k
    z = ffrx_sort_subset(selected, k) ## i64
    if ffrx_subset_seen(processed, covered, k, selected) == 0
      i = 0 ## i64
      while i < k
        processed[covered * k + i] = selected[i]
        i += 1
      covered += 1
  attempts += 1

if attempt_cap != requested * 64
  z = ffrxsc_fail("bounded retry policy")
if covered != requested
  z = ffrxsc_fail("requested=256 covered=" + covered.to_s() + " attempts=" + attempts.to_s())

<< "PASS rectangular kxor selection coverage requested=" + requested.to_s() + " covered=" + covered.to_s() + " attempts=" + attempts.to_s() + " cap=" + attempt_cap.to_s()

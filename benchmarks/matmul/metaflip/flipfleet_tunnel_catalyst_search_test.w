use flipfleet_tunnel_catalyst_search

-> fftcst_expect(label, condition)
  if !condition
    << "FAIL " + label
    exit(1)

-> fftcst_set3(values, a, b, c) (i64[] i64 i64 i64) i64
  values[0] = a
  values[1] = b
  values[2] = c
  1

# The target-free tunnel scanner must recover a real 5x5 three-flip endpoint,
# classify it as beyond one flip, and identify its span-3 duplication.
real_u = i64[3]
real_v = i64[3]
real_w = i64[3]
z = fftcst_set3(real_u, 524288, 11337728, 16777216) ## i64
z = fftcst_set3(real_v, 5406720, 168965, 5248005)
z = fftcst_set3(real_w, 32768, 32768, 1048577)
selected = i64[3]
out_u = i64[3]
out_v = i64[3]
out_w = i64[3]
path = i64[3]
meta = i64[8]
tunnel = fftcs_search_tunnels(real_u, real_v, real_w, 3, 1, 10000, selected, out_u, out_v, out_w, path, meta) ## i64
fftcst_expect("target-free tunnel hit", tunnel == 3)
fftcst_expect("tunnel beyond one flip", fftcs_one_flip(real_u, real_v, real_w, out_u, out_v, out_w) == 0)
fftcst_expect("tunnel is span3 duplicate", fftcs_span3_duplicate(real_u, real_v, real_w, out_u, out_v, out_w) == 1)

# The target-free catalyst DFS and deeper beam must recover the planted braid;
# this guards the real-frontier negative result against a dead enumerator.
cat_u = i64[3]
cat_v = i64[3]
cat_w = i64[3]
z = fftcst_set3(cat_u, 1, 6, 1)
z = fftcst_set3(cat_v, 2, 2, 7)
z = fftcst_set3(cat_w, 2, 5, 2)
cat_out_u = i64[3]
cat_out_v = i64[3]
cat_out_w = i64[3]
cat_path = i64[4]
cat_meta = i64[4]
cat_hit = fftcs_find_catalyst_endpoint4(cat_u, cat_v, cat_w, 6, 7, 7, 1000000, cat_out_u, cat_out_v, cat_out_w, cat_path, cat_meta) ## i64
fftcst_expect("target-free catalyst hit", cat_hit == 3)
fftcst_expect("target-free catalyst exact", fftc_local_exact(cat_u, cat_v, cat_w, 3, cat_out_u, cat_out_v, cat_out_w, 3) == 1)
fftcst_expect("target-free catalyst changes endpoint", fftc_terms_same_set(cat_u, cat_v, cat_w, 3, cat_out_u, cat_out_v, cat_out_w, 3) == 0)

beam_out_u = i64[3]
beam_out_v = i64[3]
beam_out_w = i64[3]
beam_path = i64[6]
beam_meta = i64[7]
beam_hit = fftcs_find_catalyst_beam(cat_u, cat_v, cat_w, 6, 7, 7, 6, 256, 1000000, beam_out_u, beam_out_v, beam_out_w, beam_path, beam_meta) ## i64
fftcst_expect("catalyst beam planted hit", beam_hit == 3)
fftcst_expect("catalyst beam exact", fftc_local_exact(cat_u, cat_v, cat_w, 3, beam_out_u, beam_out_v, beam_out_w, 3) == 1)

<< "flipfleet_tunnel_catalyst_search_test: all checks passed"

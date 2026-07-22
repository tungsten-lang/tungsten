use flipfleet_fixed_rank_pocket

-> fffrpwt_expect(label, condition) (String bool) i64
  if !condition
    << "FIXED_RANK_POCKET_WORD_TEST_FAIL " + label
    exit(1)
  1

-> fffrpwt_density(scheme) (FFBCScheme) i64
  total = 0 ## i64
  term = i64[3]
  i = 0 ## i64
  while i < scheme.rank()
    if fffrp_scalar_term(scheme, i, term) != 1
      return 0 - 1
    total += fffrp_popcount(term[0]) + fffrp_popcount(term[1]) + fffrp_popcount(term[2])
    i += 1
  total

-> fffrpwt_distance(left, right) (FFBCScheme FFBCScheme) i64
  common = 0 ## i64
  term = i64[3]
  i = 0 ## i64
  while i < left.rank()
    if fffrp_scalar_term(left, i, term) != 1
      return 0 - 1
    common += fffrp_scheme_has_scalar(right, term[0], term[1], term[2])
    i += 1
  left.rank() + right.rank() - common - common

-> fffrpwt_autonomous_step(source, ticket, expected_gain) (FFBCScheme i64 i64)
  rank = source.rank() ## i64
  us = i64[rank]
  vs = i64[rank]
  ws = i64[rank]
  if fffrp_scalar_scheme(source, us, vs, ws) != rank
    return nil
  endpoint_u = i64[5]
  endpoint_v = i64[5]
  endpoint_w = i64[5]
  origins = i64[5]
  stats = i64[32]
  gain = fffrp_autonomous_ticket(us, vs, ws, rank, ticket, 5, 5, 512, 12, endpoint_u, endpoint_v, endpoint_w, origins, stats) ## i64
  if gain != expected_gain || stats[8] > 12
    return nil
  fffrp_materialize_selected(source, origins, endpoint_u, endpoint_v, endpoint_w, stats[7])

-> fffrpwt_direct_step(source, ticket, expected_delta) (FFBCScheme i64 i64)
  rank = source.rank() ## i64
  us = i64[rank]
  vs = i64[rank]
  ws = i64[rank]
  if fffrp_scalar_scheme(source, us, vs, ws) != rank
    return nil
  info = i64[3]
  if fffrp_ticket(us, vs, ws, rank, ticket, info) != 1
    return nil
  input_u = i64[2]
  input_v = i64[2]
  input_w = i64[2]
  input_u[0] = us[info[0]]
  input_v[0] = vs[info[0]]
  input_w[0] = ws[info[0]]
  input_u[1] = us[info[1]]
  input_v[1] = vs[info[1]]
  input_w[1] = ws[info[1]]
  endpoint_u = i64[2]
  endpoint_v = i64[2]
  endpoint_w = i64[2]
  if fffrp_flip_neighbor(input_u, input_v, input_w, 0, 2, 0, 1, info[2], endpoint_u, endpoint_v, endpoint_w) != 2
    return nil
  delta = fffrp_density(endpoint_u, endpoint_v, endpoint_w, 0, 2) - fffrp_density(input_u, input_v, input_w, 0, 2) ## i64
  if delta != expected_delta || delta > 12
    return nil
  origins = i64[2]
  origins[0] = info[0]
  origins[1] = info[1]
  fffrp_sort_origins(origins, 2)
  fffrp_materialize_selected(source, origins, endpoint_u, endpoint_v, endpoint_w, 2)

root = "bits/tungsten-metaflip/lib/metaflip/seeds/gf2/"
bench = "benchmarks/matmul/metaflip/"
c013 = ffbc_load_exact(root + "matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt", 7, 7, 7, 260)
child = ffbc_load_exact(root + "matmul_7x7_rank247_d3546_autonomous_flip_pocket_gf2.txt", 7, 7, 7, 260)
saved3524 = ffbc_load_exact(bench + "matmul_7x7_rank247_d3524_fixed_rank_pocket_word_gf2.txt", 7, 7, 7, 260)
saved3516 = ffbc_load_exact(bench + "matmul_7x7_rank247_d3516_fixed_rank_pocket_word_gf2.txt", 7, 7, 7, 260)
fffrpwt_expect("load exact controls", c013 != nil && child != nil && saved3524 != nil && saved3516 != nil)
fffrpwt_expect("pinned densities", fffrpwt_density(c013) == 3554 && fffrpwt_density(child) == 3546 && fffrpwt_density(saved3524) == 3524 && fffrpwt_density(saved3516) == 3516)

# Productive three-ticket word.  Ticket ordinals are deliberately resolved
# afresh at every exact intermediate; this is the fleet-replay contract.
cursor = c013
expected = 3544 ## i64
step = 0 ## i64
while step < 3
  cursor = fffrpwt_autonomous_step(cursor, 1, 10)
  fffrpwt_expect("C013 productive step " + step.to_s(), cursor != nil && fffrpwt_density(cursor) == expected)
  expected -= 10
  step += 1
fffrpwt_expect("C013 productive certificate", fffrpwt_distance(cursor, saved3524) == 0 && fffrpwt_distance(c013, cursor) == 12)

cursor = child
expected = 3536
step = 0
while step < 3
  cursor = fffrpwt_autonomous_step(cursor, 1, 10)
  fffrpwt_expect("child productive step " + step.to_s(), cursor != nil && fffrpwt_density(cursor) == expected)
  expected -= 10
  step += 1
fffrpwt_expect("child productive certificate", fffrpwt_distance(cursor, saved3516) == 0 && fffrpwt_distance(child, cursor) == 12)

# A genuine tunnel-only word: the final neutral ticket would be rejected by
# an endpoint-only density improver, but the complete three-ticket word still
# closes twenty bits below C013 in a distinct support basin.
tunnel = fffrpwt_autonomous_step(c013, 1, 10)
tunnel = fffrpwt_autonomous_step(tunnel, 1, 10)
tunnel = fffrpwt_direct_step(tunnel, 10, 0)
fffrpwt_expect("neutral-prefix tunnel", tunnel != nil && fffrpwt_density(tunnel) == 3534 && fffrpwt_distance(c013, tunnel) == 12)

<< "FIXED_RANK_POCKET_WORD_TEST_PASS C013=3554->3524 child=3546->3516 tunnel=3534 distance=12"

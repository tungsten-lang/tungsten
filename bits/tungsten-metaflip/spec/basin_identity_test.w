use fixtures/basin_reference
use ../lib/metaflip/seeds/catalog

-> basin_expect(ok, label) (bool String) i64
  if !ok
    << "FAIL basin identity: " + label
    exit(1)
  1

# Exhaust all small matrices, then basis vectors, dense complements and
# deterministic full-width masks for every supported narrow dimension.
n = 1 ## i64
checks = 0 ## i64
while n <= 7
  width = n * n ## i64
  mask = (1 << width) - 1 ## i64
  count = 10000 ## i64
  if n <= 4
    count = 1 << width
  i = 0 ## i64
  rng = 19331 ## i64
  while i < count + 2 * width
    value = i ## i64
    if n > 4
      rng = (rng * 1103515245 + 12345) & 2147483647
      value = rng << 24
      rng = (rng * 1103515245 + 12345) & 2147483647
      value = (value ^ rng) & mask
    if i >= count
      value = 1 << ((i - count) / 2)
      if (i - count) % 2 != 0
        value = mask ^ value
    z = basin_expect(ffbi_transpose_factor(value, n) == ffe_transpose(value, n), "transpose n=" + n.to_s())
    z = basin_expect(ffbi_reverse_factor(value, n) == ffbr_reverse_factor(value, n), "reverse n=" + n.to_s())
    checks += 1
    i += 1
  n += 1

root = __DIR__ + "/../lib/metaflip/"
n = 2
while n <= 7
  capacity = n * n * n + 64 ## i64
  state = i64[ffw_state_size(capacity)]
  paths = ffp_frontier_seed_paths(n)
  p = 0 ## i64
  while p < paths.size()
    loaded = ffw_load_scheme_cap(state, root + paths[p], n, capacity, 919 + p, 0, 1, 3, 5) ## i64
    z = basin_expect(loaded > 0 && ffw_verify_best_exact(state, n) == 1, "seed")
    round = 0 ## i64
    while round < 4
      z = basin_expect(ffbi_best_id(state) == ffbr_identity_view(state, 0), "best digest")
      z = basin_expect(ffbi_current_id(state) == ffbr_identity_view(state, 1), "current digest")
      z = ffw_work(state, 2000)
      round += 1
    p += 1
  n += 1

# Snapshot parity includes equal states, symmetry images, in-place mutation,
# rank changes, leader changes, empty/one-island fleets and smaller reuses.
n = 7
capacity = 400 ## i64
leader = i64[ffw_state_size(capacity)]
paths = ffp_frontier_seed_paths(n)
z = ffw_load_scheme_cap(leader, root + paths[0], n, capacity, 991, 0, 1, 3, 5)
leader_id = ffbi_best_id(leader) ## i64
image = i64[ffw_state_size(capacity)]
us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
code = 0 ## i64
while code < 12
  i = 0 ## i64
  rank = ffw_best_rank(leader) ## i64
  while i < rank
    u = ffw_read_best_u(leader, i) ## i64
    v = ffw_read_best_v(leader, i) ## i64
    w = ffw_read_best_w(leader, i) ## i64
    # Reverse term order too; digest equality must not depend on live slots.
    us[rank - 1 - i] = ffbr_transform_factor(u, v, w, n, code % 6, code / 6, 0)
    vs[rank - 1 - i] = ffbr_transform_factor(u, v, w, n, code % 6, code / 6, 1)
    ws[rank - 1 - i] = ffbr_transform_factor(u, v, w, n, code % 6, code / 6, 2)
    i += 1
  z = ffw_init_terms_cap(image, us, vs, ws, rank, n, capacity, 911, 0, 1, 3, 5)
  z = basin_expect(ffw_verify_best_exact(image, n) == 1 && ffbi_best_id(image) == leader_id, "D3/reversal/reordering")
  code += 1
states = []
stats = i64[ffn_basin_stats_words(16)]
expected = i64[4]
round = 0
while round <= 16
  z = ffbr_active_basin_stats(states, leader, expected)
  z = ffn_active_basin_stats(states, leader, stats)
  k = 0 ## i64
  while k < 4
    z = basin_expect(stats[k] == expected[k], "summary " + k.to_s())
    k += 1
  k = 0
  while k < states.size()
    z = basin_expect(stats[4 + k] == ffbr_identity_view(states[k], 1), "snapshot id")
    z = basin_expect(stats[4 + states.size() + k] == ffn_current_to_best_distance(states[k], leader), "snapshot distance")
    z = ffw_work(states[k], 500)
    k += 1
  if round < 16
    state = i64[ffw_state_size(capacity)]
    z = ffw_load_scheme_cap(state, root + paths[round % paths.size()], n, capacity, 99 + round, 0, 1, 3, 5)
    states.push(state)
  round += 1
# Changing the leader in place cannot reuse the previous snapshot's ID.
z = ffw_init_naive_cap(leader, n, capacity, 811, 0, 1, 3, 5)
z = ffbr_active_basin_stats(states, leader, expected)
z = ffn_active_basin_stats(states, leader, stats)
k = 0
while k < 4
  z = basin_expect(stats[k] == expected[k], "changed leader/rank")
  k += 1
states = []
z = ffn_active_basin_stats(states, leader, stats)
z = basin_expect(stats[0] == 0 && stats[1] == -1 && stats[2] == 0 && stats[3] == 0, "empty reuse")
<< "PASS basin parity transforms=" + checks.to_s() + " all 2..7 frontier identities and 0..16-island snapshots"

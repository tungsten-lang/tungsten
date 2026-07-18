use ../lib/metaflip/rect/portfolio

-> ffrdvt_expect(label, condition)
  if !condition
    << "FAIL " + label
    exit(1)
  1

-> ffrdvt_contains(bank, candidate) i64
  i = 0 ## i64
  while i < bank.size()
    if ffrda_same_best(bank[i], candidate) == 1
      return 1
    i += 1
  0

-> ffrdvt_has_delta(bank, leader, delta) i64
  wanted = ffr_best_rank(leader) + delta ## i64
  i = 0 ## i64
  while i < bank.size()
    if ffr_best_rank(bank[i]) == wanted
      return 1
    i += 1
  0

# Make a deterministic exact shoulder by replacing one term factor f with
# a + (f+a).  Try canonical term/axis/single-bit choices until both replacement
# terms are absent, which makes the symmetric-difference rank rise by exactly
# one. Repeating constructs the R+2 band without relying on a random walk.
-> ffrdvt_split_shoulder(src, n, m, p, capacity, splits, variant, dslack, cycles, workq, wanderq) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
  work = ffrc_clone_exact(src, n, m, p, capacity, 97001 + variant * 17, dslack, cycles, workq, wanderq)
  if work == nil
    return nil
  made = 0 ## i64
  while made < splits
    before = ffr_current_rank(work) ## i64
    max_width = n * m ## i64
    if m * p > max_width
      max_width = m * p
    if n * p > max_width
      max_width = n * p
    search_limit = before * 3 * max_width ## i64
    search = 0 ## i64
    found = 0 ## i64
    while search < search_limit && found == 0
      rotated = variant * 37 + made * 53 + search ## i64
      rank_index = rotated % before ## i64
      axis = (rotated / before) % 3 ## i64
      slot = work[work[50] + rank_index] ## i64
      u = work[work[44] + slot] ## i64
      v = work[work[45] + slot] ## i64
      w = work[work[46] + slot] ## i64
      factor = u ## i64
      width = n * m ## i64
      if axis == 1
        factor = v
        width = m * p
      if axis == 2
        factor = w
        width = n * p
      bit = (rotated / (before * 3)) % width ## i64
      part = 1 << bit ## i64
      if part == factor
        part = 1 << ((bit + 1) % width)
      other = factor ^ part ## i64
      if other != 0
        au = u ## i64
        av = v ## i64
        aw = w ## i64
        bu = u ## i64
        bv = v ## i64
        bw = w ## i64
        if axis == 0
          au = part
          bu = other
        if axis == 1
          av = part
          bv = other
        if axis == 2
          aw = part
          bw = other
        rank = before ## i64
        rank = ffw_toggle(work, u, v, w, rank)
        rank = ffw_toggle(work, au, av, aw, rank)
        rank = ffw_toggle(work, bu, bv, bw, rank)
        if rank == before + 1
          work[6] = rank
          found = 1
        if rank != before + 1
          rank = ffw_toggle(work, bu, bv, bw, rank)
          rank = ffw_toggle(work, au, av, aw, rank)
          rank = ffw_toggle(work, u, v, w, rank)
          work[6] = rank
      search += 1
    if found == 0
      return nil
    made += 1
  ffrda_clone_current_exact(work, n, m, p, capacity, 98001 + variant * 19 + splits, dslack, cycles, workq, wanderq)

n = 2 ## i64
m = 2 ## i64
p = 5 ## i64
capacity = ffr_default_capacity(n, m, p) ## i64
dslack = 4 ## i64
cycles = 4 ## i64
workq = 1000 ## i64
wanderq = 500 ## i64
root = __DIR__ + "/../lib/metaflip/seeds/gf2/"

leader = i64[ffr_state_size(capacity)]
rank = ffr_load_scheme_cap(leader, root + "matmul_2x2x5_rank18_d84_gf2.txt", n, m, p, capacity, 96001, dslack, cycles, workq, wanderq) ## i64
z = ffrdvt_expect("exact rank-18 leader", rank == 18 && ffr_verify_best_exact(leader, n, m, p) == 1)

prior = i64[ffr_state_size(capacity)]
prior_rank = ffr_load_scheme_cap(prior, root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt", n, m, p, capacity, 96003, dslack, cycles, workq, wanderq) ## i64
z = ffrdvt_expect("exact distinct prior door", prior_rank == rank && ffr_verify_best_exact(prior, n, m, p) == 1 && ffrda_same_best(prior, leader) == 0)
z = ffrdvt_expect("eight persisted side doors", ffrda_cap() == 8)

# Four independently materialized current endpoints lie one local split from
# the leader. The old door is split into the same rank band but remains far
# from the leader, reproducing the former first-four truncation failure.
near = []
variant = 0 ## i64
while near.size() < 4 && variant < 128
  candidate = ffrdvt_split_shoulder(leader, n, m, p, capacity, 1, variant, dslack, cycles, workq, wanderq)
  action = ffrda_collect_unique(near, candidate, leader, n, m, p) ## i64
  variant += 1
z = ffrdvt_expect("four unique near current endpoints", near.size() == 4)

far_prior = ffrdvt_split_shoulder(prior, n, m, p, capacity, 1, 211, dslack, cycles, workq, wanderq)
z = ffrdvt_expect("prior shoulder exact and in +1 band", far_prior != nil && ffr_best_rank(far_prior) == rank + 1 && ffr_verify_best_exact(far_prior, n, m, p) == 1)
near_max_distance = 0 ## i64
i = 0 ## i64
while i < near.size()
  distance = ffrda_best_distance(near[i], leader) ## i64
  if distance > near_max_distance
    near_max_distance = distance
  i += 1
far_distance = ffrda_best_distance(far_prior, leader) ## i64
z = ffrdvt_expect("prior door is farther than all four current doors", far_distance > near_max_distance)

same_band = []
i = 0
while i < near.size()
  same_band.push(near[i])
  i += 1
same_band.push(far_prior)
same_band_selected = []
selected_count = ffrda_select_diverse(same_band, leader, ffrda_cap(), same_band_selected) ## i64
z = ffrdvt_expect("far prior survives four near current doors", selected_count == same_band.size() && ffrdvt_contains(same_band_selected, far_prior) == 1)

# Expand the pool beyond the production cap. This models a wide child whose
# exit barrier sees more exact endpoints than it can persist and ensures all
# eight slots participate in the deterministic diversity selection.
while near.size() < ffrda_cap() + 2 && variant < 512
  candidate = ffrdvt_split_shoulder(leader, n, m, p, capacity, 1, variant, dslack, cycles, workq, wanderq)
  action = ffrda_collect_unique(near, candidate, leader, n, m, p) ## i64
  variant += 1
z = ffrdvt_expect("wide child supplies more candidates than slots", near.size() > ffrda_cap())

# Present every allowed band. Coverage consumes three slots; the remaining
# five are normal max-min fills. Reversing arrival order must produce identical
# slots.
plus_two = ffrdvt_split_shoulder(leader, n, m, p, capacity, 2, 307, dslack, cycles, workq, wanderq)
z = ffrdvt_expect("exact +2 shoulder", plus_two != nil && ffr_best_rank(plus_two) == rank + 2 && ffr_verify_best_exact(plus_two, n, m, p) == 1)

pool_forward = []
i = 0
while i < near.size()
  pool_forward.push(near[i])
  i += 1
pool_forward.push(far_prior)
pool_forward.push(prior)
pool_forward.push(plus_two)
pool_reverse = []
i = pool_forward.size() - 1
while i >= 0
  pool_reverse.push(pool_forward[i])
  i -= 1

selected_forward = []
selected_reverse = []
forward_count = ffrda_select_diverse(pool_forward, leader, ffrda_cap(), selected_forward) ## i64
reverse_count = ffrda_select_diverse(pool_reverse, leader, ffrda_cap(), selected_reverse) ## i64
z = ffrdvt_expect("selector fills cap", forward_count == ffrda_cap() && reverse_count == ffrda_cap())
z = ffrdvt_expect("rank band zero covered", ffrdvt_has_delta(selected_forward, leader, 0) == 1)
z = ffrdvt_expect("rank band one covered", ffrdvt_has_delta(selected_forward, leader, 1) == 1)
z = ffrdvt_expect("rank band two covered", ffrdvt_has_delta(selected_forward, leader, 2) == 1)
i = 0
while i < selected_forward.size()
  z = ffrdvt_expect("order-independent slot " + i.to_s(), ffrda_same_best(selected_forward[i], selected_reverse[i]) == 1)
  i += 1

# Treat one checked-in frontier presentation as a fixed anchor.  The same
# exact term set is deliberately left in both arrival orders: it must be
# excluded rather than consuming a persisted slot under a second role name.
fixed_anchors = []
fixed_anchors.push(near[0])
anchored_forward = []
anchored_reverse = []
anchored_forward_count = ffrda_select_diverse_anchored(pool_forward, leader, fixed_anchors, ffrda_cap(), anchored_forward) ## i64
anchored_reverse_count = ffrda_select_diverse_anchored(pool_reverse, leader, fixed_anchors, ffrda_cap(), anchored_reverse) ## i64
z = ffrdvt_expect("anchored selector fills cap", anchored_forward_count == ffrda_cap() && anchored_reverse_count == ffrda_cap())
z = ffrdvt_expect("fixed anchor excluded from saved roles", ffrdvt_contains(anchored_forward, near[0]) == 0)
i = 0
while i < anchored_forward.size()
  z = ffrdvt_expect("anchored order-independent slot " + i.to_s(), ffrda_same_best(anchored_forward[i], anchored_reverse[i]) == 1)
  i += 1

# The selected +1 door must be max-min optimal relative to the leader, the
# fixed built-in, and the already-reserved rank-R door.  This checks the
# intended metric independently of the selector's tie-breaking path.
anchored_plus_one = nil
i = 0
while i < anchored_forward.size()
  if ffr_best_rank(anchored_forward[i]) == rank + 1
    anchored_plus_one = anchored_forward[i]
  i += 1
z = ffrdvt_expect("anchored +1 band covered", anchored_plus_one != nil)
rank_zero_selected = []
rank_zero_selected.push(anchored_forward[0])
anchored_plus_one_distance = ffrda_min_anchor_distance_anchored(anchored_plus_one, leader, fixed_anchors, rank_zero_selected) ## i64
i = 0
while i < pool_forward.size()
  candidate = pool_forward[i]
  if ffr_best_rank(candidate) == rank + 1 && ffrda_already_selected(fixed_anchors, candidate) == 0
    candidate_distance = ffrda_min_anchor_distance_anchored(candidate, leader, fixed_anchors, rank_zero_selected) ## i64
    z = ffrdvt_expect("anchored max-min +1 candidate " + i.to_s(), anchored_plus_one_distance >= candidate_distance)
  i += 1

# Persist a deliberately dirty bank containing the fixed anchor, then reload
# through the anchored gate.  A second save/reload proves the on-disk archive
# converges to a pairwise-distinct union of built-ins and saved doors.
archive_path = "/tmp/metaflip_rect_side_archive_anchor_test_best.txt"
z = ffrdvt_expect("clear anchored archive fixture", ffrda_clear(archive_path, "anchor-test", 1) == 1)
dirty_bank = []
dirty_bank.push(near[0])
dirty_bank.push(far_prior)
dirty_bank.push(prior)
dirty_bank.push(plus_two)
save_stats = i64[4]
saved_dirty = ffrda_save(archive_path, dirty_bank, "anchor-test", 100, save_stats) ## i64
z = ffrdvt_expect("dirty archive saved", saved_dirty == 4 && save_stats[3] == 0)
reloaded = []
load_stats = i64[4]
reloaded_count = ffrda_load_anchored(archive_path, leader, fixed_anchors, n, m, p, capacity, 99001, dslack, cycles, workq, wanderq, reloaded, load_stats) ## i64
z = ffrdvt_expect("builtin duplicate rejected on load", reloaded_count == 3 && load_stats[0] == 3 && load_stats[1] == 1 && ffrdvt_contains(reloaded, near[0]) == 0)
clean_selected = []
z = ffrda_select_diverse_anchored(reloaded, leader, fixed_anchors, ffrda_cap(), clean_selected)
clean_stats = i64[4]
z = ffrda_save(archive_path, clean_selected, "anchor-test", 200, clean_stats)
roundtrip = []
roundtrip_stats = i64[4]
roundtrip_count = ffrda_load_anchored(archive_path, leader, fixed_anchors, n, m, p, capacity, 99101, dslack, cycles, workq, wanderq, roundtrip, roundtrip_stats) ## i64
z = ffrdvt_expect("clean archive roundtrip", roundtrip_count == clean_selected.size() && roundtrip_stats[1] == 0)
i = 0
while i < roundtrip.size()
  z = ffrdvt_expect("roundtrip differs from fixed anchor " + i.to_s(), ffrda_already_selected(fixed_anchors, roundtrip[i]) == 0)
  j = i + 1 ## i64
  while j < roundtrip.size()
    z = ffrdvt_expect("roundtrip pairwise distinct " + i.to_s() + "/" + j.to_s(), ffrda_same_best(roundtrip[i], roundtrip[j]) == 0)
    j += 1
  i += 1
z = ffrdvt_expect("clear anchored archive output", ffrda_clear(archive_path, "anchor-test", 300) == 1)

# Keep a small repeatable cold-path benchmark in the focused test. This is not
# a throughput target; it exposes regressions in the exit-only O(cap*N*R^2)
# selector without adding timing logic to the campaign.
bench_pool = []
variant = 0
while bench_pool.size() < 20 && variant < 512
  candidate = ffrdvt_split_shoulder(leader, n, m, p, capacity, 1, 401 + variant, dslack, cycles, workq, wanderq)
  action = ffrda_collect_unique(bench_pool, candidate, leader, n, m, p)
  variant += 1
bench_pool.push(prior)
bench_pool.push(plus_two)
z = ffrdvt_expect("representative benchmark pool", bench_pool.size() >= 20)
iterations = 200 ## i64
t0 = ccall("__w_clock_ms") ## i64
i = 0
while i < iterations
  bench_selected = []
  z = ffrda_select_diverse(bench_pool, leader, ffrda_cap(), bench_selected)
  i += 1
elapsed_ms = ccall("__w_clock_ms") - t0 ## i64
selector_us = elapsed_ms * 1000 / iterations ## i64

<< "PASS rectangular side archive diversity near_d=" + near_max_distance.to_s() + " prior_d=" + far_distance.to_s() + " selector_us=" + selector_us.to_s()

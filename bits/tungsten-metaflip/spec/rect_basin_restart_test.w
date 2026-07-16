use ../lib/metaflip/rect/campaign
use ../lib/metaflip/strategies/global_isotropy

-> ffrcbt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

-> ffrcbt_current_distance(left, right, capacity) (i64[] i64[] i64) i64
  lu = i64[capacity]
  lv = i64[capacity]
  lw = i64[capacity]
  ru = i64[capacity]
  rv = i64[capacity]
  rw = i64[capacity]
  left_rank = ffw_export_current(left, lu, lv, lw) ## i64
  right_rank = ffw_export_current(right, ru, rv, rw) ## i64
  ffgir_term_set_distance(lu, lv, lw, left_rank, ru, rv, rw, right_rank)

n = 2 ## i64
m = 5 ## i64
p = 6 ## i64
capacity = ffr_default_capacity(n, m, p) ## i64
dslack = 4 ## i64
cycles = 4 ## i64
workq = 10000 ## i64
wanderq = 2500 ## i64
root = __DIR__ + "/../lib/metaflip"
seed_path = root + "/seeds/gf2/matmul_2x5x6_rank47_catalog_gf2.txt"

anchor = i64[ffr_state_size(capacity)]
rank = ffr_load_scheme_cap(anchor, seed_path, n, m, p, capacity, 91001, dslack, cycles, workq, wanderq) ## i64
z = ffrcbt_expect("exact 256 anchor", rank == 47 && ffr_verify_best_exact(anchor, n, m, p) == 1)

nonce0 = ffrcb_portfolio_nonce(0, 0, 0) ## i64
nonce1 = ffrcb_portfolio_nonce(1, 0, 0) ## i64
nonce_fill = ffrcb_portfolio_nonce(0, 0, 1) ## i64
z = ffrcbt_expect("stable standalone stream", ffrcb_seed(82001, 0, 0, 0) == 82001)
z = ffrcbt_expect("epochs receive distinct nonces", nonce0 > 0 && nonce1 > 0 && nonce0 != nonce1)
z = ffrcbt_expect("fill receives a distinct nonce", nonce_fill != nonce0 && nonce_fill != nonce1)
z = ffrcbt_expect("lanes receive distinct streams", ffrcb_seed(82001, nonce0, 0, 0) != ffrcb_seed(82001, nonce0, 1, 0))

# Every reconstructed portfolio child intentionally receives a fresh zone
# lifecycle: move count and deadline reset, while the configured work/wander
# quotas are preserved. Sticky rounds within that child continue the same
# counters rather than replaying their first tranche.
budget_state = ffrc_clone_exact(anchor, n, m, p, capacity, ffrcb_seed(82001, nonce_fill, 0, 0), dslack, cycles, workq, wanderq)
z = ffrcbt_expect("restart resets zone move counter", budget_state[13] == 0)
z = ffrcbt_expect("restart restores work/wander quotas", budget_state[18] == workq && budget_state[19] == wanderq && budget_state[14] == workq)
z = ffr_work(budget_state, 37)
z = ffrcbt_expect("sticky tranche advances zone counter", budget_state[13] == 37)
z = ffr_walk(budget_state, 53)
z = ffrcbt_expect("next tranche continues without replay", budget_state[13] == 90)
fresh_budget_state = ffrc_clone_exact(anchor, n, m, p, capacity, ffrcb_seed(82001, nonce1, 0, 0), dslack, cycles, workq, wanderq)
z = ffrcbt_expect("next child resets lifecycle again", fresh_budget_state[13] == 0 && fresh_budget_state[18] == workq && fresh_budget_state[19] == wanderq)

# The historical restart reused one seed, so equal inputs replay exactly.
legacy_left = ffrc_clone_exact(anchor, n, m, p, capacity, 82001, dslack, cycles, workq, wanderq)
legacy_right = ffrc_clone_exact(anchor, n, m, p, capacity, 82001, dslack, cycles, workq, wanderq)
z = ffr_wander(legacy_left, 5000)
z = ffr_wander(legacy_right, 5000)
legacy_distance = ffrcbt_current_distance(legacy_left, legacy_right, capacity) ## i64
z = ffrcbt_expect("legacy restart replays", legacy_distance == 0)

# Epoch-salted restarts retain exactness but take different deterministic paths.
epoch_left = ffrc_clone_exact(anchor, n, m, p, capacity, ffrcb_seed(82001, nonce0, 0, 0), dslack, cycles, workq, wanderq)
epoch_right = ffrc_clone_exact(anchor, n, m, p, capacity, ffrcb_seed(82001, nonce1, 0, 0), dslack, cycles, workq, wanderq)
z = ffrcbt_expect("salted restarts initialize distinct RNG streams", epoch_left[8] != epoch_right[8] && epoch_left[9] != epoch_right[9])
z = ffr_wander(epoch_left, 5000)
z = ffr_wander(epoch_right, 5000)
epoch_distance = ffrcbt_current_distance(epoch_left, epoch_right, capacity) ## i64
z = ffrcbt_expect("salted restart remains exact", ffr_verify_current_exact(epoch_left, n, m, p) == 1 && ffr_verify_current_exact(epoch_right, n, m, p) == 1)
z = ffrcbt_expect("salted restart opens another proposal stream", epoch_left[8] != epoch_right[8])
z = ffrcbt_expect("salted restart changes accepted path", epoch_left[21] != epoch_right[21])

<< "PASS rectangular basin restart legacy-distance=" + legacy_distance.to_s() + " salted-distance=" + epoch_distance.to_s() + " accepted=" + epoch_left[21].to_s() + "/" + epoch_right[21].to_s()

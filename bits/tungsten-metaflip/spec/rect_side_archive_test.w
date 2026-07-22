use ../lib/metaflip/rect/portfolio

-> ffrdat_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

n = 2 ## i64
m = 5 ## i64
p = 6 ## i64
capacity = ffr_default_capacity(n, m, p) ## i64
dslack = 4 ## i64
cycles = 4 ## i64
steps = 5000000 ## i64
workq = ffrp_work_quota(steps) ## i64
wanderq = ffrp_wander_quota(steps) ## i64
root = __DIR__ + "/../lib/metaflip"
seed_path = root + "/seeds/gf2/matmul_2x5x6_rank47_catalog_gf2.txt"

leader = i64[ffr_state_size(capacity)]
rank = ffr_load_scheme_cap(leader, seed_path, n, m, p, capacity, 91001, dslack, cycles, workq, wanderq) ## i64
z = ffrdat_expect("exact leader", rank == 47 && ffr_verify_best_exact(leader, n, m, p) == 1)

nonce0 = ffrcb_portfolio_nonce(0, 0, 0) ## i64
island = ffrc_clone_exact(leader, n, m, p, capacity, ffrcb_seed(82001, nonce0, 0, 0), dslack, cycles, workq, wanderq)
z = ffr_work(island, steps * 5 / 8)
z = ffr_walk(island, steps / 4)
z = ffr_wander(island, steps - steps * 5 / 8 - steps / 4)
door = ffrda_clone_current_exact(island, n, m, p, capacity, 92001, dslack, cycles, workq, wanderq)
z = ffrdat_expect("live endpoint snapshots exactly", door != nil && ffr_verify_best_exact(door, n, m, p) == 1)
z = ffrdat_expect("snapshot stays in +0..+2 near band", ffr_best_rank(door) >= ffr_best_rank(leader) && ffr_best_rank(door) <= ffr_best_rank(leader) + 2)
z = ffrdat_expect("snapshot is a distinct door", ffrda_same_best(door, leader) == 0)

bank = []
action = ffrda_add_unique(bank, door, leader, ffrda_cap(), n, m, p) ## i64
z = ffrdat_expect("door admitted", action == 1 && bank.size() == 1)
action = ffrda_add_unique(bank, door, leader, ffrda_cap(), n, m, p)
z = ffrdat_expect("duplicate rejected", action == 0 && bank.size() == 1)

best_path = "/tmp/metaflip_rect_side_archive_test_best.txt"
slot = 0 ## i64
while slot < ffrda_cap()
  z = ffrda_atomic_write(ffrda_path(best_path, slot), "", "rect-side-test-pre", slot)
  slot += 1
stats = i64[4]
saved = ffrda_save(best_path, bank, "rect-side-test", 100, stats) ## i64
z = ffrdat_expect("one exact slot saved atomically", saved == 1 && stats[2] == 1 && stats[3] == 0)

loaded_bank = []
loaded_stats = i64[4]
loaded = ffrda_load(best_path, leader, n, m, p, capacity, 93001, dslack, cycles, workq, wanderq, loaded_bank, loaded_stats) ## i64
z = ffrdat_expect("saved slot exact-loads", loaded == 1 && loaded_stats[0] == 1 && loaded_stats[1] == 0)
z = ffrdat_expect("saved term set round-trips", ffrda_same_best(door, loaded_bank[0]) == 1)

# A malformed auxiliary slot is ignored and counted; it cannot poison the
# exact leader or make the campaign unusable.
bad = write_file(ffrda_path(best_path, 1), "not-a-scheme\n")
bad_bank = []
bad_stats = i64[4]
loaded = ffrda_load(best_path, leader, n, m, p, capacity, 94001, dslack, cycles, workq, wanderq, bad_bank, bad_stats)
z = ffrdat_expect("malformed slot rejected independently", loaded == 1 && bad_stats[0] == 1 && bad_stats[1] == 1)

empty_bank = []
clear_stats = i64[4]
saved = ffrda_save(best_path, empty_bank, "rect-side-test-clear", 200, clear_stats)
slot0_body = read_file(ffrda_path(best_path, 0))
slot1_body = read_file(ffrda_path(best_path, 1))
z = ffrdat_expect("stale slots clear atomically", saved == 0 && clear_stats[3] == 0 && slot0_body != nil && slot0_body.size() == 0 && slot1_body != nil && slot1_body.size() == 0)

# A long standalone/spot campaign checkpoints barrier-stable island bests
# before graceful exit.  The helper must reconstruct existing slots, retain a
# distinct live basin, and publish it without mutating the source state.
z = ffrdat_expect("side checkpoint cadence waits", ffrc_side_checkpoint_due(1, 1000, 899999, 0) == 0)
z = ffrdat_expect("side checkpoint cadence fifteen minutes", ffrc_side_checkpoint_due(1, 1000, 901000, 0) == 1)
z = ffrdat_expect("leader adoption checkpoint after one minute", ffrc_side_checkpoint_due(1, 1000, 61000, 1) == 1)
live_states = []
live_states.push(door)
prior = []
anchors = []
checkpoint_stats = i64[4]
checkpointed = ffrda_checkpoint_live(best_path, leader, anchors, live_states, prior, n, m, p, capacity, 94501, dslack, cycles, workq, wanderq, "rect-side-test-live", 225, checkpoint_stats) ## i64
z = ffrdat_expect("live side checkpoint writes one door", checkpointed == 1 && checkpoint_stats[2] == 1 && checkpoint_stats[3] == 0)
checkpoint_bank = []
checkpoint_load_stats = i64[4]
loaded = ffrda_load(best_path, leader, n, m, p, capacity, 94601, dslack, cycles, workq, wanderq, checkpoint_bank, checkpoint_load_stats)
z = ffrdat_expect("live side checkpoint reloads exactly", loaded == 1 && ffrda_same_best(door, checkpoint_bank[0]) == 1 && ffr_verify_best_exact(door, n, m, p) == 1)

# Reset is a durable boundary, not merely an in-process load guard. Repopulate
# a record-rank side door, reset to schoolbook, and prove a fresh process would
# see empty side slots and the naive checkpoint.
repopulate_stats = i64[4]
saved = ffrda_save(best_path, bank, "rect-side-test-repopulate", 250, repopulate_stats)
z = ffrdat_expect("record door repopulated", saved == 1)
reset_metrics = i64[2]
reset = ffrpo_reset_naive_checkpoint("2x5x6", best_path, "rect-side-test-naive", 300, reset_metrics, 0) ## i64
z = ffrdat_expect("naive reset succeeds", reset == 1 && reset_metrics[0] == 60)
slot0_body = read_file(ffrda_path(best_path, 0))
z = ffrdat_expect("naive reset physically clears side knowledge", slot0_body != nil && slot0_body.size() == 0)
naive_state = i64[ffr_state_size(capacity)]
naive_rank = ffr_load_scheme_cap(naive_state, best_path, n, m, p, capacity, 95001, dslack, cycles, workq, wanderq) ## i64
z = ffrdat_expect("naive checkpoint is durable", naive_rank == 60 && ffr_verify_best_exact(naive_state, n, m, p) == 1)

choice0 = ffrcb_door_choice(ffrcb_portfolio_nonce(0, 0, 0), 3) ## i64
choice1 = ffrcb_door_choice(ffrcb_portfolio_nonce(1, 0, 0), 3) ## i64
z = ffrdat_expect("door scheduler remains bounded", choice0 >= 0 && choice0 < 3 && choice1 >= 0 && choice1 < 3)

<< "PASS rectangular side archive rank=" + ffr_best_rank(door).to_s() + " bits=" + ffr_best_bits(door).to_s() + " choices=" + choice0.to_s() + "/" + choice1.to_s()

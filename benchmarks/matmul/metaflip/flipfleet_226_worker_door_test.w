# Independent runtime-worker replay of both <2,2,6> CPU doors.

use metaflip_rect_worker

-> ff226wdt_expect(label, condition)
  if condition == 0
    << "FAIL " + label
    exit(1)
  1

cap = ffr_default_capacity(2, 2, 6) ## i64
z = ff226wdt_expect("two-door profile", ffrp_frontier_seed_count(2, 2, 6) == 2) ## i64
slot = 0 ## i64
while slot < 2
  state = i64[ffr_state_size(cap)]
  rank = ffr_load_scheme_cap(state, ffrp_frontier_seed_rel(2, 2, 6, slot), 2, 2, 6, cap, 22601 + slot * 97, 4, 3, 1000, 250) ## i64
  z = ff226wdt_expect("door rank", rank == 21)
  z = ff226wdt_expect("door density", ffr_best_bits(state) == 108)
  z = ff226wdt_expect("door exact", ffr_verify_best_exact(state, 2, 2, 6) == 1)
  z = ffr_walk(state, 2000)
  z = ff226wdt_expect("door walk exact", ffr_verify_current_exact(state, 2, 2, 6) == 1 && ffr_verify_best_exact(state, 2, 2, 6) == 1)
  slot += 1

<< "PASS flipfleet 226 runtime worker doors"

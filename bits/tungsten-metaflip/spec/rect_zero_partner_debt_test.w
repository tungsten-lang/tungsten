use ../lib/metaflip/rect
use ../lib/metaflip/rect/basins

-> ffrzp_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL rectangular zero-partner debt: " + label
    exit(1)
  1

-> ffrzp_load(path, capacity, seed) (String i64 i64)
  state = i64[ffr_state_size(capacity)]
  rank = ffr_load_scheme_cap(state, path, 3, 4, 6, capacity, seed, 4, 4, 10000, 2500) ## i64
  if rank != 54
    return nil
  state

-> ffrzp_current_digest(st, capacity) (i64[] i64) i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_current(st, us, vs, ws) ## i64
  digest = rank * 2862933555777941757 ## i64
  i = 0 ## i64
  while i < rank
    digest = digest ^ ffw_term_zobrist(us[i], vs[i], ws[i])
    i += 1
  digest

root = __DIR__ + "/../lib/metaflip/seeds/gf2/" ## String
paths = [
  root + "matmul_3x4x6_rank54_d488_gl_frontier_gf2.txt",
  root + "matmul_3x4x6_rank54_catalog_gf2.txt"
]
capacity = ffr_default_capacity(3, 4, 6) ## i64

i = 0 ## i64
while i < paths.size()
  control = ffrzp_load(paths[i], capacity, 91001 + i * 1009)
  z = ffrzp_expect("r54 door loads exactly " + i.to_s(), control != nil && ffr_verify_best_exact(control,3,4,6) == 1)
  z = ffrzp_expect("r54 door has zero partnerable incidences " + i.to_s(), ffr_partnerable_incidences(control) == 0)

  before_misses = ffw_partner_misses(control) ## i64
  before_accepted = ffw_accepted(control) ## i64
  z = ffr_work(control, 10000)
  z = ffrzp_expect("focused control is all partner misses " + i.to_s(), ffw_partner_misses(control) - before_misses == 10000)
  z = ffrzp_expect("focused control accepts nothing " + i.to_s(), ffw_accepted(control) == before_accepted)
  z = ffrzp_expect("focused control remains exact " + i.to_s(), ffr_verify_current_exact(control,3,4,6) == 1)

  plus1 = ffrzp_load(paths[i], capacity, 92003 + i * 1013)
  rank1 = ffr_seed_braided_debt(plus1, 1, 170003 + i * 10007) ## i64
  z = ffrzp_expect("braided +1 has r55 current/r54 best " + i.to_s(), rank1 == 55 && ffr_current_rank(plus1) == 55 && ffr_best_rank(plus1) == 54)
  z = ffrzp_expect("braided +1 is exact " + i.to_s(), ffr_verify_current_exact(plus1,3,4,6) == 1)
  z = ffrzp_expect("braided +1 opens multiple incidences " + i.to_s(), ffr_partnerable_incidences(plus1) >= 4)

  plus2 = ffrzp_load(paths[i], capacity, 93007 + i * 1019)
  rank2 = ffr_seed_braided_debt(plus2, 2, 270007 + i * 10009) ## i64
  z = ffrzp_expect("braided +2 has r56 current/r54 best " + i.to_s(), rank2 == 56 && ffr_current_rank(plus2) == 56 && ffr_best_rank(plus2) == 54)
  z = ffrzp_expect("braided +2 is exact " + i.to_s(), ffr_verify_current_exact(plus2,3,4,6) == 1)
  z = ffrzp_expect("braided +2 fits its starting band " + i.to_s(), ffw_band(plus2) >= 2)
  z = ffrzp_expect("debt depths create distinct doors " + i.to_s(), ffrzp_current_digest(plus1,capacity) != ffrzp_current_digest(plus2,capacity))

  alternate = ffrzp_load(paths[i], capacity, 94009 + i * 1021)
  alt_rank = ffr_seed_braided_debt(alternate, 1, 370009 + i * 10037) ## i64
  z = ffrzp_expect("alternate +1 is exact " + i.to_s(), alt_rank == 55 && ffr_verify_current_exact(alternate,3,4,6) == 1)
  z = ffrzp_expect("nonce selects another +1 door " + i.to_s(), ffrzp_current_digest(plus1,capacity) != ffrzp_current_digest(alternate,capacity))
  i += 1

# Three adjacent nonces retain one ordered source/donor pair while selecting
# the cyclic U/V/W identities. Their exact shoulders must not alias.
orient0 = ffrzp_load(paths[0], capacity, 94501)
orient1 = ffrzp_load(paths[0], capacity, 94501)
orient2 = ffrzp_load(paths[0], capacity, 94501)
orank0 = ffr_seed_braided_debt(orient0, 1, 0) ## i64
orank1 = ffr_seed_braided_debt(orient1, 1, 1) ## i64
orank2 = ffr_seed_braided_debt(orient2, 1, 2) ## i64
od0 = ffrzp_current_digest(orient0,capacity) ## i64
od1 = ffrzp_current_digest(orient1,capacity) ## i64
od2 = ffrzp_current_digest(orient2,capacity) ## i64
z = ffrzp_expect("all cyclic orientations are exact r55 doors", orank0 == 55 && orank1 == 55 && orank2 == 55 && ffr_verify_current_exact(orient0,3,4,6) == 1 && ffr_verify_current_exact(orient1,3,4,6) == 1 && ffr_verify_current_exact(orient2,3,4,6) == 1)
z = ffrzp_expect("cyclic orientations have distinct endpoints", od0 != od1 && od0 != od2 && od1 != od2)

# Insufficient shoulder capacity fails closed on the exact rank-R best.
tight = ffrzp_load(paths[0], 54, 95003)
z = ffrzp_expect("tight-capacity fixture loads", tight != nil)
tight_result = ffr_seed_braided_debt(tight, 1, 470017) ## i64
z = ffrzp_expect("tight capacity rejects debt", tight_result == 0 && ffr_current_rank(tight) == 54 && ffr_best_rank(tight) == 54)
z = ffrzp_expect("tight rejection remains exact", ffr_verify_current_exact(tight,3,4,6) == 1 && ffr_verify_best_exact(tight,3,4,6) == 1)

# Scheduling is a pure low-discrepancy alternation, and never touches a door
# that already exposes an ordinary flip edge.
z = ffrzp_expect("partnerable door receives no debt", ffrcb_initial_debt_depth(1,0,0) == 0)
z = ffrzp_expect("standalone lanes alternate +1/+2", ffrcb_initial_debt_depth(0,0,0-1) == 1 && ffrcb_initial_debt_depth(0,1,0-1) == 2)
z = ffrzp_expect("next portfolio ticket reverses depths", ffrcb_initial_debt_depth(0,0,1) == 2 && ffrcb_initial_debt_depth(0,1,1) == 1)

<< "PASS rectangular zero-partner braided debt doors=2 control_misses=20000 exact=1 schedule=alternating"

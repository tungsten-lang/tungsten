use ../lib/metaflip/strategies/delta_components
use ../lib/metaflip/fleet/intake

-> ffdc_test_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL delta component peel: " + label
    exit(1)
  1

-> ffdc_test_toggle(us, vs, ws, rank, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  result = ffnd_toggle_plain(us, vs, ws, rank, capacity, u, v, w) ## i64
  if result < 0
    << "FAIL delta component peel: fixture toggle overflow"
    exit(1)
  result

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
n = 7 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
parent = i64[state_size]
expected = i64[state_size]
candidate = i64[state_size]
winner = i64[state_size]

parent_path = root + "matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt"
expected_path = root + "matmul_7x7_rank247_d3094_three_flip_density_gf2.txt"
parent_rank = ffw_load_scheme_cap(parent, parent_path, n, capacity, 7001, 0, 1, 1, 1) ## i64
expected_rank = ffw_load_scheme_cap(expected, expected_path, n, capacity, 7003, 0, 1, 1, 1) ## i64
z = ffdc_test_expect("packaged fixtures load", parent_rank == 247 && expected_rank == 247)
z = ffdc_test_expect("packaged fixtures exact", ffw_verify_best_exact(parent,n) == 1 && ffw_verify_best_exact(expected,n) == 1)
z = ffdc_test_expect("fixture densities", ffw_best_bits(parent) == 3096 && ffw_best_bits(expected) == 3094)

# Reconstruct the raw d3095 live result without packaging it as a restart seed.
# These are exactly the five removals and five insertions in its d10 symmetric
# difference from d3096; all constants remain decimal scheme-format masks.
us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
rank = ffw_export_best(parent, us, vs, ws) ## i64

rank = ffdc_test_toggle(us,vs,ws,rank,capacity,16777216,87961234317378,278921216)
rank = ffdc_test_toggle(us,vs,ws,rank,capacity,2199023255552,17592186044416,467197129033448)
rank = ffdc_test_toggle(us,vs,ws,rank,capacity,2164278273,35651650,269484032)
rank = ffdc_test_toggle(us,vs,ws,rank,capacity,2199023255552,422212532174880,141836999987232)
rank = ffdc_test_toggle(us,vs,ws,rank,capacity,2203335041024,87961198665728,269484032)
rank = ffdc_test_toggle(us,vs,ws,rank,capacity,2199023255552,439804718219296,141836999987232)
rank = ffdc_test_toggle(us,vs,ws,rank,capacity,2203318263808,87961198665728,269484032)
rank = ffdc_test_toggle(us,vs,ws,rank,capacity,16777216,87961234317378,11534336)
rank = ffdc_test_toggle(us,vs,ws,rank,capacity,2199023255552,17592186044416,327559152309960)
rank = ffdc_test_toggle(us,vs,ws,rank,capacity,2147501057,35651650,269484032)

loaded = ffw_init_terms_cap(candidate,us,vs,ws,rank,n,capacity,7005,0,1,1,1) ## i64
z = ffdc_test_expect("d3095 reconstruction rank", loaded == 247)
z = ffdc_test_expect("d3095 reconstruction exact", ffw_verify_best_exact(candidate,n) == 1)
z = ffdc_test_expect("d3095 reconstruction density", ffw_best_bits(candidate) == 3095)

meta = i64[12]
started = ccall("__w_clock_ms") ## i64
peeled = ffdc_crossover_best_states(parent,candidate,n,64,winner,capacity,7011,0,1,1,1,meta) ## i64
elapsed = ccall("__w_clock_ms") - started ## i64
z = ffdc_test_expect("peel returns rank 247", peeled == 247)
z = ffdc_test_expect("d10 splits 6+4", meta[0] == 10 && meta[1] == 2 && meta[10] == 6)
z = ffdc_test_expect("all components independently exact", meta[2] == 2 && meta[3] == 2)
z = ffdc_test_expect("all four children independently gated", meta[4] == 4 && meta[5] == 4 && meta[11] == 1)
z = ffdc_test_expect("peel recovers d3094", ffw_best_bits(winner) == 3094)

winner_u = i64[capacity]
winner_v = i64[capacity]
winner_w = i64[capacity]
expected_u = i64[capacity]
expected_v = i64[capacity]
expected_w = i64[capacity]
winner_rank = ffw_export_best(winner,winner_u,winner_v,winner_w) ## i64
expected_rank = ffw_export_best(expected,expected_u,expected_v,expected_w) ## i64
diff_u = i64[capacity * 2]
diff_v = i64[capacity * 2]
diff_w = i64[capacity * 2]
owners = i64[capacity * 2]
remaining = ffnd_build_difference(winner_u,winner_v,winner_w,winner_rank,expected_u,expected_v,expected_w,expected_rank,diff_u,diff_v,diff_w,owners) ## i64
z = ffdc_test_expect("winner is packaged d3094 term set", remaining == 0)

# Production intake mutates only a qualifying same-rank density improvement.
intake_candidate = i64[state_size]
intake_loaded = ffw_reseed_from(intake_candidate,candidate,7015) ## i64
intake_meta = i64[12]
intake_rank = ffci_try_component_peel(parent,intake_candidate,n,capacity,7016,0,1,1,1,intake_meta) ## i64
z = ffdc_test_expect("intake hook loads fixture", intake_loaded == 247)
z = ffdc_test_expect("intake hook adopts exact d3094", intake_rank == 247 && ffw_best_bits(intake_candidate) == 3094 && ffw_verify_best_exact(intake_candidate,n) == 1)

# The pre-existing generic archive nullspace can incidentally expose this
# relation when called directly.  Record its cost as a comparison; unlike the
# component helper it neither names support components nor receives this d10
# pair from the production differential selector's former d12 threshold.
null_u = i64[capacity]
null_v = i64[capacity]
null_w = i64[capacity]
null_meta = i64[9]
null_started = ccall("__w_clock_ms") ## i64
null_rank = ffnd_crossover_states(parent,candidate,n,64,4096,null_u,null_v,null_w,null_meta) ## i64
null_elapsed = ccall("__w_clock_ms") - null_started ## i64
null_state = i64[state_size]
null_loaded = ffw_init_terms_cap(null_state,null_u,null_v,null_w,null_rank,n,capacity,7017,0,1,1,1) ## i64
z = ffdc_test_expect("legacy nullspace comparison exact", null_rank == 247 && null_loaded == 247 && ffw_verify_best_exact(null_state,n) == 1)

# The d3096->d3094 difference is the single six-term relation.  It must not be
# mistaken for a proper hybrid, and too-small bounds must fail closed.
negative_meta = i64[12]
negative = ffdc_crossover_best_states(parent,expected,n,64,winner,capacity,7021,0,1,1,1,negative_meta) ## i64
z = ffdc_test_expect("one-component parent delta rejected", negative == 0 && negative_meta[0] == 6 && negative_meta[1] == 1)
bounded_meta = i64[12]
bounded = ffdc_crossover_best_states(parent,candidate,n,8,winner,capacity,7023,0,1,1,1,bounded_meta) ## i64
z = ffdc_test_expect("difference bound rejects before graph", bounded == 0 && bounded_meta[0] == 10)

corrupt = i64[state_size]
corrupt_loaded = ffw_reseed_from(corrupt,candidate,7025) ## i64
corrupt[corrupt[47]] = corrupt[corrupt[47]] ^ 1
corrupt_meta = i64[12]
corrupt_result = ffdc_crossover_best_states(parent,corrupt,n,64,winner,capacity,7027,0,1,1,1,corrupt_meta) ## i64
z = ffdc_test_expect("inexact parent fails closed", corrupt_loaded == 247 && corrupt_result == 0)

iterations = 100 ## i64
bench_meta = i64[12]
bench_started = ccall("__w_clock_ms") ## i64
iteration = 0 ## i64
while iteration < iterations
  bench_rank = ffdc_crossover_best_states(parent,candidate,n,64,winner,capacity,8001 + iteration,0,1,1,1,bench_meta) ## i64
  if bench_rank != 247 || ffw_best_bits(winner) != 3094
    << "FAIL delta component peel: repeated benchmark result"
    exit(1)
  iteration += 1
bench_elapsed = ccall("__w_clock_ms") - bench_started ## i64
bench_us = bench_elapsed * 1000 / iterations ## i64

<< "PASS delta component peel d3096+d3095 -> d3094 exact_ms=" + elapsed.to_s() + " nullspace_ms=" + null_elapsed.to_s() + " mean_us=" + bench_us.to_s() + " components=" + meta[1].to_s() + " children=" + meta[5].to_s()

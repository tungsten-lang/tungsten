# Reproducible real-frontier audit for rank-one matroid-circuit exchange.
#
# Usage:
#   flipfleet_matroid_circuit_bench [three_pair_cap] [four_pair_cap] [four_probe_cap]

use flipfleet_matroid_circuit

-> ffmcb_run(label, path, n, three_pair_cap, four_pair_cap, four_probe_cap) (String String i64 i64 i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  size = ffw_state_size(capacity) ## i64
  state = i64[size]
  rank = ffw_load_scheme_cap(state, path, n, capacity, 96001 + n, 0, 1, 1, 1) ## i64
  if rank < 4 || ffw_verify_current_exact(state, n) == 0
    << "MATROID_CIRCUIT_BENCH tensor=" + label + " error=load"
    return 0 - 1
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if ffw_export_current(state, us, vs, ws) != rank
    return 0 - 1
  source_density = fftc_density(us, vs, ws, rank) ## i64

  out3_u = i64[capacity]
  out3_v = i64[capacity]
  out3_w = i64[capacity]
  meta3 = i64[13]
  started = ccall("__w_clock_ms") ## i64
  found3 = ffmc_search3_bounded(us, vs, ws, rank, n * n, three_pair_cap, out3_u, out3_v, out3_w, meta3) ## i64
  elapsed3 = ccall("__w_clock_ms") - started ## i64
  full3 = 0 ## i64
  endpoint3_density = 0 - 1 ## i64
  if found3 > 0
    endpoint3 = i64[size]
    loaded3 = ffw_init_terms_cap(endpoint3, out3_u, out3_v, out3_w, found3, n, capacity, 96101 + n, 0, 1, 1, 1) ## i64
    if loaded3 == found3 && ffw_verify_current_exact(endpoint3, n) == 1
      full3 = 1
      endpoint3_density = ffw_current_bits(endpoint3)
  << "MATROID_CIRCUIT3 tensor=" + label + " rank=" + rank.to_s() + " density=" + source_density.to_s() + " edits=" + meta3[0].to_s() + " pairs=" + meta3[1].to_s() + " sketch=" + meta3[2].to_s() + " circuits=" + meta3[3].to_s() + " valid=" + meta3[4].to_s() + " one_flip=" + meta3[5].to_s() + " span3=" + meta3[6].to_s() + " beyond_span3=" + meta3[7].to_s() + " best_delta=" + meta3[8].to_s() + " endpoint_rank=" + found3.to_s() + " endpoint_density=" + endpoint3_density.to_s() + " full_exact=" + full3.to_s() + " ms=" + elapsed3.to_s()

  out4_u = i64[capacity]
  out4_v = i64[capacity]
  out4_w = i64[capacity]
  meta4 = i64[13]
  started = ccall("__w_clock_ms")
  found4 = ffmc_search4_improving_bounded(us, vs, ws, rank, n * n, four_pair_cap, four_probe_cap, out4_u, out4_v, out4_w, meta4) ## i64
  elapsed4 = ccall("__w_clock_ms") - started ## i64
  full4 = 0 ## i64
  endpoint4_density = 0 - 1 ## i64
  if found4 > 0
    endpoint4 = i64[size]
    loaded4 = ffw_init_terms_cap(endpoint4, out4_u, out4_v, out4_w, found4, n, capacity, 96201 + n, 0, 1, 1, 1) ## i64
    if loaded4 == found4 && ffw_verify_current_exact(endpoint4, n) == 1
      full4 = 1
      endpoint4_density = ffw_current_bits(endpoint4)
  << "MATROID_CIRCUIT4 tensor=" + label + " rank=" + rank.to_s() + " density=" + source_density.to_s() + " edits=" + meta4[0].to_s() + " negative=" + meta4[1].to_s() + " positive=" + meta4[2].to_s() + " nn_pairs=" + meta4[3].to_s() + " np_probes=" + meta4[4].to_s() + " sketch=" + meta4[5].to_s() + " circuits=" + meta4[6].to_s() + " valid=" + meta4[7].to_s() + " span4=" + meta4[8].to_s() + " beyond_span4=" + meta4[9].to_s() + " best_delta=" + meta4[10].to_s() + " endpoint_rank=" + found4.to_s() + " endpoint_density=" + endpoint4_density.to_s() + " full_exact=" + full4.to_s() + " ms=" + elapsed4.to_s()
  1

args = argv()
three_pair_cap = 0 ## i64
four_pair_cap = 700000 ## i64
four_probe_cap = 7000000 ## i64
if args.size() > 0
  three_pair_cap = args[0].to_i()
if args.size() > 1
  four_pair_cap = args[1].to_i()
if args.size() > 2
  four_probe_cap = args[2].to_i()
if three_pair_cap < 0 || four_pair_cap < 1 || four_probe_cap < 0
  << "invalid benchmark bounds"
  exit(2)

z = ffmcb_run("4x4-d450", "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt", 4, three_pair_cap, four_pair_cap, four_probe_cap) ## i64
z = ffmcb_run("5x5-d1155", "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", 5, three_pair_cap, four_pair_cap, four_probe_cap)
z = ffmcb_run("5x5-d968", "benchmarks/matmul/metaflip/matmul_5x5_rank93_d968_global_isotropy_gf2.txt", 5, three_pair_cap, four_pair_cap, four_probe_cap)
seven_three_cap = three_pair_cap ## i64
if seven_three_cap == 0
  seven_three_cap = 10000000
z = ffmcb_run("7x7-r247-d3098", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt", 7, seven_three_cap, four_pair_cap, four_probe_cap)

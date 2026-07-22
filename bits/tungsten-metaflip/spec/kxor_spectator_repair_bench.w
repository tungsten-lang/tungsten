# Bounded real-frontier decision screen for one-spectator k-XOR repair.
#
# Each ticket builds the production-style connectivity pool for one five-term
# window, enumerates every canonical four-term replacement with the same
# projected tensor fingerprint, rejects already-exact 5->4 joins, and offers
# only the remaining exact-local near misses to spectator repair.  Every
# accepted endpoint is reconstructed and fully verified by the strategy.

use ../lib/metaflip/strategies/kxor_spectator_repair

-> ffksb_add(total, meta) (i64[] i64[]) i64
  i = 0 ## i64
  while i < 10
    total[i] += meta[i]
    i += 1
  1

-> ffksb_run(label, path, n, windows, pool, nearby, offset, total) (String String i64 i64 i64 i64 i64 i64[]) i64
  capacity = ffw_default_capacity(n) ## i64
  source = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(source, path, n, capacity, 99201 + offset, 0, 1, 1, 1) ## i64
  if rank < 5 || ffw_verify_current_exact(source, n) != 1
    << "KXOR_SPECTATOR tensor=" + label + " error=load rank=" + rank.to_s()
    return 0
  endpoint = i64[ffw_state_size(capacity)]
  meta = i64[12]
  started = ccall("__w_clock_ms") ## i64
  hit = ffks_screen_frontier(source, windows, pool, nearby, offset, endpoint, capacity, meta) ## i64
  elapsed = ccall("__w_clock_ms") - started ## i64
  z = ffksb_add(total, meta) ## i64
  if hit > 0
    output = "/tmp/metaflip_kxor_spectator_" + label + "_r" + hit.to_s() + ".txt" ## String
    dumped = ffw_dump_best(endpoint, output) ## i64
    << "KXOR_SPECTATOR tensor=" + label + " rank=" + rank.to_s() + " windows=" + meta[0].to_s() + " pool_avg=" + (meta[10] / meta[0]).to_s() + " tuples=" + meta[1].to_s() + " projected=" + meta[2].to_s() + " exact=" + meta[3].to_s() + " near=" + meta[4].to_s() + " spectator_tickets=" + meta[5].to_s() + " repairable=" + meta[6].to_s() + " gates=" + meta[7].to_s() + " hit=" + hit.to_s() + " ms=" + elapsed.to_s() + " path=" + output + " dumped=" + dumped.to_s()
    return 1
  << "KXOR_SPECTATOR tensor=" + label + " rank=" + rank.to_s() + " windows=" + meta[0].to_s() + " pool_avg=" + (meta[10] / meta[0]).to_s() + " tuples=" + meta[1].to_s() + " projected=" + meta[2].to_s() + " exact=" + meta[3].to_s() + " near=" + meta[4].to_s() + " spectator_tickets=" + meta[5].to_s() + " repairable=" + meta[6].to_s() + " gates=" + meta[7].to_s() + " hit=0 ms=" + elapsed.to_s()
  1

root = __DIR__ + "/../lib/metaflip/seeds/gf2/" ## String
windows = 128 ## i64
pool = 96 ## i64
nearby = 8 ## i64
total = i64[10]
started = ccall("__w_clock_ms") ## i64
z = ffksb_run("3x3-d139", root + "matmul_3x3_rank23_d139_gf2.txt", 3, windows, pool, nearby, 301, total) ## i64
z = ffksb_run("3x3-d159", root + "matmul_3x3_rank23_d159_gf2.txt", 3, windows, pool, nearby, 401, total)
z = ffksb_run("4x4-d450", root + "matmul_4x4_rank47_d450_gf2.txt", 4, windows, pool, nearby, 501, total)
z = ffksb_run("4x4-d677", root + "matmul_4x4_rank47_d677_flips_gf2.txt", 4, windows, pool, nearby, 601, total)
z = ffksb_run("5x5-d967", root + "matmul_5x5_rank93_d967_four_split_control_gf2.txt", 5, windows, pool, nearby, 701, total)
z = ffksb_run("5x5-d983", root + "matmul_5x5_rank93_d983_global_isotropy_gf2.txt", 5, windows, pool, nearby, 801, total)
z = ffksb_run("5x5-d1155", root + "matmul_5x5_rank93_d1155_gf2.txt", 5, windows, pool, nearby, 901, total)
z = ffksb_run("7x7-d3094", root + "matmul_7x7_rank247_d3094_three_flip_density_gf2.txt", 7, windows, pool, nearby, 1001, total)
z = ffksb_run("7x7-d3096", root + "matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt", 7, windows, pool, nearby, 1101, total)
z = ffksb_run("7x7-c013-d3492", root + "matmul_7x7_rank247_d3492_outer_isotropy_c013_cuda_epoch67_gf2.txt", 7, windows, pool, nearby, 1201, total)
elapsed = ccall("__w_clock_ms") - started ## i64
<< "KXOR_SPECTATOR_SUMMARY doors=10 windows=" + total[0].to_s() + " tuples=" + total[1].to_s() + " projected=" + total[2].to_s() + " exact=" + total[3].to_s() + " near=" + total[4].to_s() + " spectator_tickets=" + total[5].to_s() + " repairable=" + total[6].to_s() + " gates=" + total[7].to_s() + " hits=" + total[8].to_s() + " ms=" + elapsed.to_s()

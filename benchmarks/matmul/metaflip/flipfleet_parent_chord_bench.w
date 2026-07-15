use metaflip_worker
use flipfleet_parent_chord

-> ffpcb_probe(label, path_a, path_b, n) (String String String i64) i64
  cap = ffw_default_capacity(n) ## i64
  size = ffw_state_size(cap) ## i64
  a = i64[size]
  b = i64[size]
  arank = ffw_load_scheme_cap(a, path_a, n, cap, 701, 0, 1, 1, 1) ## i64
  brank = ffw_load_scheme_cap(b, path_b, n, cap, 703, 0, 1, 1, 1) ## i64
  if arank < 1 || brank < 1
    << label + " load-failed"
    return 0
  au = i64[cap]
  av = i64[cap]
  aw = i64[cap]
  bu = i64[cap]
  bv = i64[cap]
  bw = i64[cap]
  z = ffw_export_best(a, au, av, aw) ## i64
  z = ffw_export_best(b, bu, bv, bw) ## i64
  started = ccall("__w_clock_ms") ## i64
  opportunities = ffpc_count(au, av, aw, arank, bu, bv, bw, brank) ## i64
  elapsed = ccall("__w_clock_ms") - started ## i64
  samples = opportunities ## i64
  if samples > 32
    samples = 32
  exact = 0 ## i64
  rank_neutral = 0 ## i64
  shoulders = 0 ## i64
  best_distance = 999999999 ## i64
  i = 0 ## i64
  while i < samples
    candidate = i64[size]
    rank = ffpc_state_into(candidate, a, b, (i * opportunities) / samples, 709 + i) ## i64
    if rank > 0 && ffw_verify_current_exact(candidate, n) == 1
      exact += 1
      if rank <= arank
        rank_neutral += 1
      if rank == arank + 1
        shoulders += 1
      out_u = i64[cap]
      out_v = i64[cap]
      out_w = i64[cap]
      z = ffw_export_current(candidate, out_u, out_v, out_w) ## i64
      common = 0 ## i64
      j = 0 ## i64
      while j < rank
        if ffpc_contains(bu, bv, bw, brank, out_u[j], out_v[j], out_w[j]) == 1
          common += 1
        j += 1
      distance = rank + brank - 2 * common ## i64
      if distance < best_distance
        best_distance = distance
    i += 1
  if best_distance == 999999999
    best_distance = 0 - 1
  << label + " ranks=" + arank.to_s() + "/" + brank.to_s() + " opportunities=" + opportunities.to_s() + " count-ms=" + elapsed.to_s() + " sampled=" + samples.to_s() + " exact=" + exact.to_s() + " neutral=" + rank_neutral.to_s() + " shoulders=" + shoulders.to_s() + " best-distance=" + best_distance.to_s()
  opportunities

root = "benchmarks/matmul/metaflip/"
total = 0 ## i64
total += ffpcb_probe("4x4-frontier", root + "matmul_4x4_rank47_d450_gf2.txt", root + "matmul_4x4_rank47_d677_flips_gf2.txt", 4)
total += ffpcb_probe("5x5-frontier", root + "matmul_5x5_rank93_d1155_gf2.txt", root + "matmul_5x5_rank93_d1168_gf2.txt", 5)
if total < 1
  exit(1)

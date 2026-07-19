use ../lib/metaflip/strategies/rect_block_interior

budget = 150 ## i64
if ARGV.size() > 0
  parsed = ARGV[0].to_i() ## i64
  if parsed > 0
    budget = parsed

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
paths = [
  "matmul_2x2x5_rank18_d84_gf2.txt",
  "matmul_2x2x6_rank21_d108_block_local_gl_gf2.txt",
  "matmul_3x3x5_rank36_d287_gf2.txt",
  "matmul_3x5x5_rank58_d518_gf2.txt"
]
ns = i64[4]
ms = i64[4]
ps = i64[4]
ns[0] = 2
ms[0] = 2
ps[0] = 5
ns[1] = 2
ms[1] = 2
ps[1] = 6
ns[2] = 3
ms[2] = 3
ps[2] = 5
ns[3] = 3
ms[3] = 5
ps[3] = 5

failures = 0 ## i64
case_id = 0 ## i64
while case_id < paths.size()
  n = ns[case_id] ## i64
  m = ms[case_id] ## i64
  p = ps[case_id] ## i64
  capacity = ffr_default_capacity(n, m, p) ## i64
  source = i64[ffr_state_size(capacity)]
  rank = ffr_load_scheme_cap(source, root + paths[case_id], n, m, p, capacity, 17001 + case_id, 4, 4, 10000, 2500) ## i64
  if rank < 1 || ffr_verify_best_exact(source, n, m, p) == 0
    << "RECT_BLOCK_BENCH load-failed path=" + paths[case_id]
    failures += 1
  else
    stats = i64[7]
    accepted = 0 ## i64
    best_rank = rank ## i64
    best_bits = ffr_best_bits(source) ## i64
    start_ms = ccall("__w_clock_ms") ## i64
    attempt = 0 ## i64
    while attempt < budget
      candidate = ffrbi_try(source, n, m, p, attempt, stats)
      if candidate != nil
        accepted += 1
        candidate_rank = ffr_current_rank(candidate) ## i64
        candidate_bits = ffr_current_bits(candidate) ## i64
        if candidate_rank < best_rank || (candidate_rank == best_rank && candidate_bits < best_bits)
          best_rank = candidate_rank
          best_bits = candidate_bits
      attempt += 1
    elapsed_ms = ccall("__w_clock_ms") - start_ms ## i64
    << "RECT_BLOCK_BENCH shape=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " rank=" + rank.to_s() + " attempts=" + stats[0].to_s() + " local=" + stats[1].to_s() + " exact=" + stats[2].to_s() + " drops=" + stats[3].to_s() + " density=" + stats[4].to_s() + " neutral=" + stats[5].to_s() + " rejects=" + stats[6].to_s() + " best=" + best_rank.to_s() + "/" + best_bits.to_s() + " elapsed_ms=" + elapsed_ms.to_s()
    if stats[6] != 0
      failures += 1
  case_id += 1

if failures > 0
  exit(1)

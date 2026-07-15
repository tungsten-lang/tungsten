# One end-to-end, five-second exact SAT probe.  Kept separate from the window
# benchmark so routine profiling never launches an external solver by accident.

use metaflip_worker
use flipfleet_frozen_fringe_sat

n = 4 ## i64
args = argv()
nonce = 8111 ## i64
timeout_s = 5 ## i64
if args.size() > 0
  nonce = args[0].to_i()
if args.size() > 1
  timeout_s = args[1].to_i()
if timeout_s < 1
  timeout_s = 1
cap = ffw_default_capacity(n) ## i64
size = ffw_state_size(cap) ## i64
candidate = i64[size]
rank = ffw_load_scheme_cap(candidate, "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt", n, cap, 8001, 0, 1, 1, 1) ## i64
if rank != 47 || ffw_verify_current_exact(candidate, n) == 0
  exit(1)
meta = i64[13]
started = ccall("__w_clock_ms") ## i64
hit = fffsat_attempt(candidate, 16, nonce, 1, "cryptominisat5 --verb 0", timeout_s, "/tmp/flipfleet_frozen_fringe_sat_solver_bench_" + nonce.to_s(), meta) ## i64
elapsed = ccall("__w_clock_ms") - started ## i64
<< "solver-probe nonce=" + nonce.to_s() + " ms=" + elapsed.to_s() + " status=" + meta[9].to_s() + " replacement=" + meta[10].to_s() + " hit=" + hit.to_s() + " cells=" + meta[6].to_s() + " vars=" + meta[7].to_s() + " clauses=" + meta[8].to_s()

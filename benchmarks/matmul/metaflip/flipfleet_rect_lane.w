# Standalone pure-Tungsten rectangular CPU campaign lane.
#
# ABI:
#   flipfleet_rect_lane <tensor> <seed|record> <steps> <rng-seed> <out>
#
# A successful invocation always exhaustively verifies and writes its best
# scheme, then emits machine-parseable RECT_STATUS and RECT_RESULT records.

use metaflip_rect_worker

args = argv()
if args.size() != 5
  << "RECT_ERROR code=usage expected=5 got=" + args.size().to_s()
  << "usage: flipfleet_rect_lane <2x2x5|2x2x6|2x3x4|2x3x5|2x4x5|2x5x6|3x3x4|3x3x5|3x4x4|3x4x5|3x4x6|3x4x7|3x5x5|3x5x6|3x5x7|4x4x5|4x4x6|4x5x5|4x5x6|4x5x7|4x5x8|4x6x6|4x6x7|4x6x8|5x6x7> <seed|record> <steps> <rng-seed> <out>"
  exit(2)

tensor = args[0]
seed_path = args[1]
steps = args[2].to_i() ## i64
rng_seed = args[3].to_i() ## i64
output_path = args[4]
n = ffrp_n(tensor) ## i64
m = ffrp_m(tensor) ## i64
p = ffrp_p(tensor) ## i64
if ffr_supported(n, m, p) == 0
  << "RECT_ERROR code=tensor tensor=" + tensor
  exit(2)
if seed_path == "record"
  seed_path = ffrp_seed_rel(n, m, p)
if steps < 1
  << "RECT_ERROR code=steps steps=" + steps.to_s()
  exit(2)

cap = ffr_default_capacity(n, m, p) ## i64
st = i64[ffr_state_size(cap)]
workq = ffrp_work_quota(steps) ## i64
wanderq = ffrp_wander_quota(steps) ## i64
seed_rank = ffr_load_scheme_cap(st, seed_path, n, m, p, cap, rng_seed, 4, 8, workq, wanderq) ## i64
if seed_rank < 1
  << "RECT_ERROR code=load tensor=" + tensor + " path=" + seed_path
  exit(2)
seed_bits = ffw_best_bits(st) ## i64
phase_moves = i64[3]
z = ffrp_campaign_budgets(steps, phase_moves)
t0 = ccall("__w_clock_ms") ## i64
rank = ffr_work(st, phase_moves[0]) ## i64
rank = ffr_walk(st, phase_moves[1])
rank = ffr_wander(st, phase_moves[2])
t1 = ccall("__w_clock_ms") ## i64
exact = ffr_verify_best_exact(st, n, m, p) ## i64
if exact != 1
  << "RECT_ERROR code=verify tensor=" + tensor + " rank=" + rank.to_s()
  exit(2)
written = ffr_dump_best(st, output_path) ## i64
if written != rank
  << "RECT_ERROR code=dump tensor=" + tensor + " rank=" + rank.to_s() + " written=" + written.to_s()
  exit(2)
bits = ffw_best_bits(st) ## i64
improved = 0 ## i64
if rank < seed_rank || (rank == seed_rank && bits < seed_bits)
  improved = 1
elapsed = t1 - t0 ## i64
<< "RECT_STATUS tensor=" + tensor + " seed_rank=" + seed_rank.to_s() + " target_rank=" + ffrp_target_rank(n, m, p).to_s() + " rank=" + rank.to_s() + " bits=" + bits.to_s() + " moves=" + ffw_moves(st).to_s() + " work_moves=" + ffw_work_moves(st).to_s() + " wander_moves=" + ffw_wander_moves(st).to_s() + " accepted=" + ffw_accepted(st).to_s() + " split_attempts=" + ffw_split_attempts(st).to_s() + " splits=" + ffw_split_accepted(st).to_s() + " exact=" + exact.to_s() + " elapsed_ms=" + elapsed.to_s()
<< "RECT_RESULT tensor=" + tensor + " rank=" + rank.to_s() + " improved=" + improved.to_s() + " exact=" + exact.to_s() + " path=" + output_path

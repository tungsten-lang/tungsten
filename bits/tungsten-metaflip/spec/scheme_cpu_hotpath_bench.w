# Fixed-trajectory decision benchmark for the pure-Tungsten CPU flip engine.
#
#   scheme_cpu_hotpath_bench [229|256|346|446|456|457|5] [work|wander|walk] [moves]
#
# Each invocation loads one exact bundled seed, performs a short untimed warmup,
# resets to the same seed, and reports enough deterministic state to compare an
# optimized binary against a baseline as well as its single-core throughput.

use ../lib/metaflip/rect

args = argv()
shape = "229"
mode = "work"
moves = 50000000 ## i64
if args.size() > 0
  shape = args[0]
if args.size() > 1
  mode = args[1]
if args.size() > 2
  moves = args[2].to_i()
if moves < 1
  moves = 1

root = "lib/metaflip/seeds/gf2/"
state = i64[1]
rank = 0 - 1 ## i64
is_rect = 0 ## i64
n = 0 ## i64
m = 0 ## i64
p = 0 ## i64
seed_name = "" ## String

if shape == "229"
  n=2
  m=2
  p=9
  seed_name="matmul_2x2x9_rank32_d156_perminov_2025_gf2.txt"
if shape == "256"
  n=2
  m=5
  p=6
  seed_name="matmul_2x5x6_rank47_d438_orbit_door_gf2.txt"
if shape == "346"
  n=3
  m=4
  p=6
  seed_name="matmul_3x4x6_rank54_d488_gl_frontier_gf2.txt"
if shape == "446"
  n=4
  m=4
  p=6
  seed_name="matmul_4x4x6_rank73_d690_gl_frontier_gf2.txt"
if shape == "456"
  n=4
  m=5
  p=6
  seed_name="matmul_4x5x6_rank90_d906_rect_portfolio_gf2.txt"
if shape == "457"
  n=4
  m=5
  p=7
  seed_name="matmul_4x5x7_rank104_d1089_gl_frontier_gf2.txt"
if n > 0
  capacity = ffr_default_capacity(n,m,p) ## i64
  state = i64[ffr_state_size(capacity)]
  rank = ffr_load_scheme_cap(state,root+seed_name,n,m,p,capacity,19071,8,7,500000000,100000000)
  is_rect=1
if shape == "5"
  capacity = ffw_default_capacity(5) ## i64
  state = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(state,root+"matmul_5x5_rank93_d967_four_split_control_gf2.txt",5,capacity,19071,8,7,500000000,100000000)

if rank < 1
  << "FAIL scheme_cpu_hotpath_bench load shape=" + shape
  exit(1)

# Fault in code/data without perturbing the measured trajectory.
if is_rect != 0
  z = ffr_work(state,10000) ## i64
  rank = ffr_load_scheme_cap(state,root+seed_name,n,m,p,capacity,19071,8,7,500000000,100000000)
if is_rect == 0
  z = ffw_work(state,10000) ## i64
  rank = ffw_load_scheme_cap(state,root+"matmul_5x5_rank93_d967_four_split_control_gf2.txt",5,capacity,19071,8,7,500000000,100000000)

started = ccall_nobox("__w_clock_ns_raw") ## i64
if is_rect != 0
  if mode == "work"
    z = ffr_work(state,moves)
  if mode == "wander"
    z = ffr_wander(state,moves)
  if mode == "walk"
    z = ffr_walk(state,moves)
if is_rect == 0
  if mode == "work"
    z = ffw_work(state,moves)
  if mode == "wander"
    z = ffw_wander(state,moves)
  if mode == "walk"
    z = ffw_walk(state,moves)
elapsed_ns = ccall_nobox("__w_clock_ns_raw") - started ## i64
if elapsed_ns < 1
  elapsed_ns = 1

exact = 0 ## i64
if is_rect != 0
  exact = ffr_verify_current_exact(state,n,m,p)
if is_rect == 0
  exact = ffw_verify_current_exact(state,5)
actual_bits = ffw_view_bits(state,state[44],state[45],state[46],state[50],state[6]) ## i64
tracked_bits = state[36] + state[64] ## i64
rate_milli_mps = moves * 1000000 / elapsed_ns ## i64

body = "CPU_HOTPATH shape=" + shape + " mode=" + mode ## String
body += " moves=" + moves.to_s() + " ns=" + elapsed_ns.to_s()
body += " rate_milli_mps=" + rate_milli_mps.to_s()
body += " current=" + state[6].to_s() + "/" + actual_bits.to_s()
body += " tracked=" + tracked_bits.to_s() + " best=" + state[7].to_s() + "/" + state[36].to_s()
body += " accepted=" + state[21].to_s() + " rejected=" + state[22].to_s()
body += " misses=" + state[23].to_s() + " rng=" + state[8].to_s()
body += " exact=" + exact.to_s()
<< body

if exact == 0 || actual_bits != tracked_bits
  exit(1)

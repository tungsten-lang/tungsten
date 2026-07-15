# Standalone support-clustered frozen-fringe SAT worker.
# ABI: seed output timeout-seconds nonce

use flipfleet_frozen_fringe_sat_pool_lib

args = argv()
if args.size() < 4
  << "usage: flipfleet_frozen_fringe_sat_pool seed output timeout-seconds nonce"
  exit(2)
if fffsp_solver_available() == 0
  << "CPU_POOL_FROZEN_SAT_ERROR code=-3 reason=cryptominisat5-not-on-PATH"
  exit(2)
meta = i64[16]
result = fffsp_run(args[0], args[1], args[2].to_i(), args[3].to_i(), meta) ## i64
if result < 0
  << "CPU_POOL_FROZEN_SAT_ERROR code=" + result.to_s()
  exit(2)

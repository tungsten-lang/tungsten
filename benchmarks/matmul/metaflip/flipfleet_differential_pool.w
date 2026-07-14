# Standalone single-CPU cross-parent differential worker.
# ABI: parent-a parent-b output n pool offset min-distance

use flipfleet_differential_pool_lib

args = argv()
if args.size() < 7
  << "usage: flipfleet_differential_pool parent-a parent-b output n pool offset min-distance"
  exit(2)
result = ffpd_search(args[0], args[1], args[2], args[3].to_i(), args[4].to_i(), args[5].to_i(), args[6].to_i()) ## i64
if result < 0
  << "CPU_POOL_PARENT_DIFF_ERROR code=" + result.to_s()
  exit(2)

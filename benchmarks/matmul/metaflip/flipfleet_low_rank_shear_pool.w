# Standalone exact q=2 low-rank absorbed-shear GPU worker.
# ABI: seed output n pair_limit nonce [metal] [metallib]

use flipfleet_low_rank_shear_pool_lib

args = argv()
if args.size() < 5
  << "usage: flipfleet_low_rank_shear_pool seed output n pair_limit nonce [metal] [metallib]"
  exit(2)
metal_path = "benchmarks/matmul/metaflip/flipfleet_low_rank_shear_pool.metal"
if args.size() > 5
  metal_path = args[5]
metallib_path = ""
if args.size() > 6
  metallib_path = args[6]
result = fflrsp_search(args[0], args[1], args[2].to_i(), args[3].to_i(), args[4].to_i(), metal_path, metallib_path) ## i64
if result < 0
  << "GPU_POOL_LOW_RANK_SHEAR_ERROR code=" + result.to_s()
  exit(2)

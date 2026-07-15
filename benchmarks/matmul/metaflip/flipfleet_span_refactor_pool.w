# Standalone complete factor-span refactor worker.
# ABI: seed output n k want subsets offset [metal] [metallib] [collision_only]
#   k=3: want=2,3,4
#   k=4: want=3,4 (one subset per child because the pair table is large)

use flipfleet_span_refactor_pool_lib

args = argv()
if args.size() < 7
  << "usage: flipfleet_span_refactor_pool seed output n k want subsets offset [metal] [metallib]"
  exit(2)
metal_path = "benchmarks/matmul/metaflip/flipfleet_span_refactor_pool.metal"
if args.size() > 7
  metal_path = args[7]
metallib_path = ""
if args.size() > 8
  metallib_path = args[8]
collision_only = 0 ## i64
if args.size() > 9
  collision_only = args[9].to_i()
result = ffsrp_search(args[0], args[1], args[2].to_i(), args[3].to_i(), args[4].to_i(), args[5].to_i(), args[6].to_i(), metal_path, metallib_path, collision_only) ## i64
if result < 0
  << "GPU_POOL_SPAN_ERROR code=" + result.to_s()
  exit(2)

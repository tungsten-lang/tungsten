# Standalone generalized XOR/circuit pool worker.
# ABI: seed output n k subsets pool nearby offset [metal] [metallib]
#   k=5    primitive five/six-term zero-circuit mining
#   k=6..9 exact k -> k-1 local surgery

use ../kxor
use core/system

args = argv()
if args.size() < 8
  << "usage: metaflip_kxor_pool seed output n k subsets pool nearby offset"
  exit(2)
metal_path = System.executable_path() + ".metal"
if args.size() > 8
  metal_path = args[8]
metallib_path = ""
if args.size() > 9
  metallib_path = args[9]
result = ffx_search(args[0], args[1], args[2].to_i(), args[3].to_i(), args[4].to_i(), args[5].to_i(), args[6].to_i(), args[7].to_i(), metal_path, metallib_path) ## i64
if result < 0
  << "GPU_POOL_KXOR_ERROR code=" + result.to_s()
  exit(2)

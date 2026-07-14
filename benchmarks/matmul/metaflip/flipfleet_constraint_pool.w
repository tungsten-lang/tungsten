# Standalone pure-Tungsten entry point for rotating constraint-pool kernels.
# ABI: seed output n mode lanes steps epoch [metal] [metallib]

use flipfleet_constraint_pool_lib

args = argv()
if args.size() < 7
  << "usage: flipfleet_constraint_pool seed output n mode lanes steps epoch"
  exit(2)
seed = args[0]
output = args[1]
n = args[2].to_i() ## i64
mode = args[3].to_i() ## i64
lanes = args[4].to_i() ## i64
steps = args[5].to_i() ## i64
epoch = args[6].to_i() ## i64
if n < 3 || n > 7 || mode < 0 || mode > 2
  << "GPU_POOL_CONSTRAINT_ERROR invalid arguments"
  exit(2)
metal_path = "benchmarks/matmul/metaflip/flipfleet_constraint_pool.metal"
if args.size() > 7
  metal_path = args[7]
metallib_path = ""
if args.size() > 8
  metallib_path = args[8]
result = ffpc_run(seed, output, n, mode, lanes, steps, epoch, metal_path, metallib_path) ## i64
if result < 0
  << "GPU_POOL_CONSTRAINT_ERROR code=" + result.to_s()
  exit(2)

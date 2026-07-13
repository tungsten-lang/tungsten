# Standalone pure-Tungsten entry point for the native FlipFleet MITM lane.
#
# ABI:
#   flipfleet_mitm_lane seed out n [subsets=4] [pool=180] [nearby=2]
#                       [offset=0] [i0,i1,i2,i3,i4]
#
# The optional explicit subset is intended for reproducible diagnostics and
# planted tests.  Fleet campaigns omit it and advance `offset` across epochs.

use flipfleet_mitm_lane_lib

-> ffm_parse_subset(text) (String)
  parts = text.split(",")
  out = nil
  if parts.size() == 5
    values = i64[5]
    i = 0 ## i64
    while i < 5
      values[i] = parts[i].to_i()
      i += 1
    out = values
  out

args = argv()
if args.size() < 3
  << "usage: flipfleet_mitm_lane seed out n [subsets=4] [pool=180] [nearby=2] [offset=0] [i0,i1,i2,i3,i4]"
  exit(2)

seed_path = args[0]
output_path = args[1]
n = args[2].to_i() ## i64
subsets = 4 ## i64
pool = 180 ## i64
nearby = 2 ## i64
offset = 0 ## i64
if args.size() > 3
  subsets = args[3].to_i()
if args.size() > 4
  pool = args[4].to_i()
if args.size() > 5
  nearby = args[5].to_i()
if args.size() > 6
  offset = args[6].to_i()

metal_path = "benchmarks/matmul/metaflip/flipfleet_mitm_lane.metal"
result = 0 ## i64
if args.size() > 7
  selected = ffm_parse_subset(args[7])
  if selected == nil
    << "GPU_MITM_NATIVE_ERROR invalid explicit subset"
    exit(2)
  result = ffm_search_exact_subset(seed_path, output_path, n, pool, nearby, selected, metal_path)
else
  result = ffm_search(seed_path, output_path, n, subsets, pool, nearby, offset, metal_path)

if result < 0
  << "GPU_MITM_NATIVE_ERROR code=" + result.to_s()
  exit(2)

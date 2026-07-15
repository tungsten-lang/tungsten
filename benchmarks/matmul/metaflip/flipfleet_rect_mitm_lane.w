# Standalone pure-Tungsten entry point for rectangular exact 5 -> 4 surgery.
#
# ABI:
#   flipfleet_rect_mitm_lane seed out tensor [subsets=4] [pool=180]
#                            [nearby=2] [offset=0] [i0,...,i4] [metallib]

use flipfleet_rect_mitm_lane_lib

-> ffrm_parse_subset(text) (String)
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
  << "usage: flipfleet_rect_mitm_lane seed out tensor [subsets=4] [pool=180] [nearby=2] [offset=0] [i0,i1,i2,i3,i4] [metallib]"
  exit(2)

seed_path = args[0]
output_path = args[1]
tensor = args[2]
n = ffrp_n(tensor) ## i64
m = ffrp_m(tensor) ## i64
p = ffrp_p(tensor) ## i64
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

metal_path = "benchmarks/matmul/metaflip/flipfleet_rect_mitm_lane.metal"
metallib_path = ""
if args.size() > 8
  metallib_path = args[8]
result = 0 ## i64
if args.size() > 7 && args[7] != ""
  selected = ffrm_parse_subset(args[7])
  if selected == nil
    << "GPU_RECT_MITM_ERROR invalid explicit subset"
    exit(2)
  result = ffrm_search_exact_subset(seed_path, output_path, n, m, p, pool, nearby, selected, metal_path, metallib_path)
else
  result = ffrm_search(seed_path, output_path, n, m, p, subsets, pool, nearby, offset, metal_path, metallib_path)

if result < 0
  << "GPU_RECT_MITM_ERROR code=" + result.to_s()
  exit(2)

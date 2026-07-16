# Standalone offline rectangular generalized XOR-surgery worker.
# ABI: seed output tensor selected subsets pool nearby offset [metallib]
#      [exclude] [replacement]
#
# selected=5, replacement=3: single/pair join (direct net-rank-two mode)
# selected=6, replacement=4: pair/pair join (direct net-rank-two mode)
# selected=6, replacement=5: pair/triple join
# selected=7, replacement=5: pair/triple join (direct net-rank-two mode)
# selected=7, replacement=6: triple/triple join
#
# The imported kernel builds collision-preserving bucket chains on the GPU and
# probes successive same-fingerprint ordinals until an exact local rewrite is
# found or every candidate is exhausted.  This worker remains offline-only.

use ../rect_kxor
use core/system

args = argv()
if args.size() < 8
  << "usage: metaflip_rect_kxor seed output tensor selected subsets pool nearby offset [metallib] [exclude] [replacement]"
  exit(2)

seed_path = args[0]
output_path = args[1]
tensor = args[2]
n = ffrp_n(tensor) ## i64
m = ffrp_m(tensor) ## i64
p = ffrp_p(tensor) ## i64
k = args[3].to_i() ## i64
subsets = args[4].to_i() ## i64
pool = args[5].to_i() ## i64
nearby = args[6].to_i() ## i64
offset = args[7].to_i() ## i64
metal_path = System.executable_path() + ".metal"
metallib_path = ""
if args.size() > 8
  metallib_path = args[8]
exclude_path = ""
if args.size() > 9
  exclude_path = args[9]
replacement_count = 0 ## i64
if args.size() > 10
  replacement_count = args[10].to_i()

result = ffrx_search(seed_path, output_path, n, m, p, k, subsets, pool, nearby, offset, metal_path, metallib_path, exclude_path, replacement_count) ## i64
if result < 0
  << "GPU_RECT_KXOR_ERROR code=" + result.to_s()
  exit(2)

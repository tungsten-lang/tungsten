# Command-line driver for bounded offline rectangular k-XOR record screens.
#
# Usage:
#   rect_kxor_campaign SEED N M P K REPLACEMENT SUBSETS POOL NEARBY OFFSET OUT
#
# The engine exact-gates the input, every local hash collision, and any full
# output certificate.  An empty OUT file is the normal no-hit result.

use ../lib/metaflip/kernels/rect_kxor
use core/system

args = argv()
if args.size() != 11
  << "usage: rect_kxor_campaign SEED N M P K REPLACEMENT SUBSETS POOL NEARBY OFFSET OUT"
  exit(2)

seed_path = args[0]
n = args[1].to_i() ## i64
m = args[2].to_i() ## i64
p = args[3].to_i() ## i64
k = args[4].to_i() ## i64
replacement = args[5].to_i() ## i64
subsets = args[6].to_i() ## i64
pool = args[7].to_i() ## i64
nearby = args[8].to_i() ## i64
offset = args[9].to_i() ## i64
output_path = args[10]
metal_path = System.executable_path() + ".metal"

result = ffrx_search(seed_path,output_path,n,m,p,k,subsets,pool,nearby,offset,metal_path,"","",replacement) ## i64
if result < 0
  << "FAIL rect_kxor_campaign code="+result.to_s()
  exit(1)
if result == 0
  << "PASS rect_kxor_campaign no-hit"
if result > 0
  << "PASS rect_kxor_campaign hit output="+output_path

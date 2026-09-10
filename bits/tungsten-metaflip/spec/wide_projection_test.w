use ../lib/metaflip/composition/projection
use core/file

if ARGV.size() == 3 && ARGV[0] == "--verify"
  raw = File.read_prefix(ARGV[1], 12632129)
  if raw == nil
    exit(2)
  source = i64[3*32*16384]
  meta = i64[4]
  parity = i64[32768]
  rank = ffpk_parse(raw, source, 3*32*16384, meta, 4) ## i64
  budget = ffpk_decimal(ARGV[2]) ## i64
  if rank < 1 || budget < 0 || budget > 1000000000
    exit(2)
  checked = ffpk_exact(source, 3*32*16384, rank, meta[0], meta[1], meta[2], parity, 32768, budget) ## i64
  << "WIDE_VERIFY " + checked.to_s()
  if checked != 1
    exit(1)
  exit(0)
if ARGV.size() == 5 && ARGV[0] == "--project"
  raw = File.read_prefix(ARGV[1], 12632129)
  if raw == nil
    exit(2)
  source = i64[3*32*16384]
  target = i64[3*32*16384]
  meta = i64[4]
  rank = ffpk_parse(raw, source, 3*32*16384, meta, 4) ## i64
  if rank < 1
    exit(2)
  axis = ffpk_decimal(ARGV[3]) ## i64
  removed = ffpk_decimal(ARGV[4]) ## i64
  reduced = ffwp_project(source, 3*32*16384, rank, meta[0], meta[1], meta[2], axis, removed, target, 3*32*16384) ## i64
  if reduced < 0
    exit(2)
  meta[axis] -= 1
  if !write_file(ARGV[2], ffpk_blob(target, reduced, meta[0], meta[1], meta[2]))
    exit(1)
  << "WIDE_PROJECT " + rank.to_s() + " " + reduced.to_s()
  exit(0)
if ARGV.size() != 0
  exit(2)

# Exact 1x2x512 naive tensor covers 1,024-bit factors and a 32->16 limb
# stride change. Negative calls must leave the destination untouched.
rank = 1024 ## i64
source = i64[3*rank*32]
output = i64[3*rank*32]
j = 0 ## i64
while j < 2
  k = 0 ## i64
  while k < 512
    t = 512*j+k ## i64
    source[3*t*32] = 1 << j
    source[(3*t+1)*32+t/32] = 1 << (t%32)
    source[(3*t+2)*32+k/32] = 1 << (k%32)
    k += 1
  j += 1
parity = i64[32768]
if ffpk_exact(source, 3*rank*32, rank, 1, 2, 512, parity, 32768, 0) != 1
  exit(1)
output[0] = 987
if ffwp_project(source, 3*rank*32, rank, 1, 2, 512, 1, 0, output, 3*rank*16-1) >= 0 || output[0] != 987
  exit(1)
if ffwp_project(source, 3*rank*32-1, rank, 1, 2, 512, 1, 0, output, 3*rank*32) >= 0 || output[0] != 987
  exit(1)
if ffwp_project(source, 3*rank*32, rank, 1, 2, 512, 0, 0, output, 3*rank*32) >= 0 || output[0] != 987
  exit(1)
if ffwp_project(source, 3*rank*32, rank, 1, 2, 512, 1, 2, output, 3*rank*32) >= 0 || output[0] != 987
  exit(1)
if ffwp_project(source, 3*rank*32, rank, 1, 2, 512, 3, 0, output, 3*rank*32) >= 0 || output[0] != 987
  exit(1)
if ffwp_project(source, 3*rank*32, rank, 1, 2, 512, 1, 0, output, 3*rank*32) != 512 || ffpk_exact(output, 3*rank*32, 512, 1, 1, 512, parity, 32768, 0) != 1
  exit(1)
if ffpk_exact(source, 3*rank*32, rank, 1, 2, 512, parity, 32768, 0) != 1
  exit(1)
<< "PASS wide projection: full identities, 1,024-bit boundary, stride contraction and nonmutation gates"

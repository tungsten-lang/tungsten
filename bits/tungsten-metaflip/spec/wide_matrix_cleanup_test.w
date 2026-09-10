use ../lib/metaflip/composition/matrix_cleanup
use core/file

-> wm_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL wide matrix: " + label
    return 1
  0

if (ARGV.size() == 4 && ARGV[0] == "--clean") || (ARGV.size() == 6 && ARGV[0] == "--basis")
  raw = File.read_prefix(ARGV[1], 12632129)
  if raw == nil
    exit(2)
  data = i64[3*32*16384]
  meta = i64[4]
  rank = ffpk_parse(raw, data, 3*32*16384, meta, 4) ## i64
  budget = ffpk_decimal(ARGV[3]) ## i64
  if rank < 1 || budget < 0
    exit(2)
  words = ffwm_scratch_words(rank, ffpk_stride(meta[0], meta[1], meta[2])) ## i64
  scratch = i64[words]
  stats = i64[6]
  reduced = 0-1 ## i64
  tag = "WIDE_CLEAN "
  if ARGV[0] == "--basis"
    reduced = ffwm_refactor(data, 3*32*16384, rank, meta[0], meta[1], meta[2], scratch, words, ffpk_decimal(ARGV[4]), ffpk_decimal(ARGV[5]), budget, stats, 6)
    tag = "WIDE_BASIS "
  else
    reduced = ffwm_reduce(data, 3*32*16384, rank, meta[0], meta[1], meta[2], scratch, words, budget, stats, 6)
  if reduced < 0 || !write_file(ARGV[2], ffpk_blob(data, reduced, meta[0], meta[1], meta[2]))
    exit(1)
  << tag + rank.to_s() + " " + reduced.to_s() + " " + stats[0].to_s() + " " + stats[2].to_s() + " " + stats[3].to_s() + " " + stats[4].to_s() + " " + stats[5].to_s()
  exit(0)
if ARGV.size() != 0
  exit(2)

failures = 0 ## i64
p = 31 ## i64
while p <= 1024
  stride = ffpk_stride(1, 1, p) ## i64
  capacity = p+1 ## i64
  data = i64[3*stride*capacity]
  # I_2 = (e1,e0)+(e0,e1)+(e0+e1,e0+e1), embedded at
  # coordinates 0 and p-1 so every limb boundary is exercised.
  data[0] = 1
  data[stride+(p-1)/32] = 1 << ((p-1)%32)
  data[2*stride] = 1
  data[3*stride] = 1
  data[4*stride] = 1
  data[5*stride+(p-1)/32] = 1 << ((p-1)%32)
  data[6*stride] = 1
  data[7*stride] = 1
  data[7*stride+(p-1)/32] = data[7*stride+(p-1)/32] | (1 << ((p-1)%32))
  data[8*stride] = 1
  data[8*stride+(p-1)/32] = data[8*stride+(p-1)/32] | (1 << ((p-1)%32))
  i = 1 ## i64
  while i < p-1
    t = i+2 ## i64
    data[3*t*stride] = 1
    data[(3*t+1)*stride+i/32] = 1 << (i%32)
    data[(3*t+2)*stride+i/32] = 1 << (i%32)
    i += 1
  words = ffwm_scratch_words(capacity, stride) ## i64
  scratch = i64[words]
  parity = i64[p*stride]
  stats = i64[6]
  stats[0] = 987
  failures += wm_expect("source identity", ffpk_exact(data, 3*stride*capacity, capacity, 1, 1, p, parity, p*stride, 0) == 1)
  failures += wm_expect("short scratch rejected", ffwm_reduce(data, 3*stride*capacity, capacity, 1, 1, p, scratch, words-1, 0, stats, 6) < 0 && stats[0] == 987)
  failures += wm_expect("short source rejected", ffwm_reduce(data, 3*stride*capacity-1, capacity, 1, 1, p, scratch, words, 0, stats, 6) < 0)
  failures += wm_expect("short stats rejected", ffwm_reduce(data, 3*stride*capacity, capacity, 1, 1, p, scratch, words, 0, stats, 5) < 0)
  failures += wm_expect("budget preserves tensor", ffwm_reduce(data, 3*stride*capacity, capacity, 1, 1, p, scratch, words, 1, stats, 6) == capacity && stats[2] == 1 && stats[0] <= 1)
  rank = ffwm_reduce(data, 3*stride*capacity, capacity, 1, 1, p, scratch, words, 0, stats, 6) ## i64
  failures += wm_expect("wide rank reduction", rank == p && stats[2] == 0 && stats[4] == 1 && stats[5] == 1)
  failures += wm_expect("result identity", ffpk_exact(data, 3*stride*capacity, rank, 1, 1, p, parity, p*stride, 0) == 1)
  failures += wm_expect("fixed point", ffwm_reduce(data, 3*stride*capacity, rank, 1, 1, p, scratch, words, 0, stats, 6) == rank && stats[4] == 0)
  blob = ffpk_blob(data, rank, 1, 1, p)
  stats[0] = 987
  failures += wm_expect("basis short scratch rejected", ffwm_refactor(data, 3*stride*capacity, capacity, 1, 1, p, scratch, words-1, 0, 0, 0, stats, 6) < 0 && stats[0] == 987)
  failures += wm_expect("basis short source rejected", ffwm_refactor(data, 3*stride*rank-1, rank, 1, 1, p, scratch, words, 0, 0, 0, stats, 6) < 0)
  failures += wm_expect("basis short stats rejected", ffwm_refactor(data, 3*stride*capacity, rank, 1, 1, p, scratch, words, 0, 0, 0, stats, 5) < 0)
  failures += wm_expect("basis invalid axis rejected", ffwm_refactor(data, 3*stride*capacity, rank, 1, 1, p, scratch, words, 3, 0, 0, stats, 6) < 0)
  failures += wm_expect("basis invalid direction rejected", ffwm_refactor(data, 3*stride*capacity, rank, 1, 1, p, scratch, words, 0, 2, 0, stats, 6) < 0)
  failures += wm_expect("basis overlarge budget rejected", ffwm_refactor(data, 3*stride*capacity, rank, 1, 1, p, scratch, words, 0, 0, 1000000001, stats, 6) < 0)
  failures += wm_expect("basis rejections are nonmutating", ffpk_blob(data, rank, 1, 1, p) == blob && stats[0] == 987)
  copy = i64[3*stride*rank]
  meta = i64[4]
  failures += wm_expect("strict packed round trip", ffpk_parse(blob, copy, 3*stride*rank, meta, 4) == rank && ffpk_blob(copy, rank, 1, 1, p) == blob)
  failures += wm_expect("trailing bytes rejected", ffpk_parse(blob+"\n", copy, 3*stride*rank, meta, 4) < 0)
  failures += wm_expect("short parse slab", ffpk_parse(blob, copy, 3*stride*rank-1, meta, 4) < 0)
  if p == 31
    p = 32
  elsif p == 32
    p = 63
  elsif p == 63
    p = 64
  elsif p == 64
    p = 65
  elsif p == 65
    p = 1024
  else
    p = 1025
if failures > 0
  exit(1)
<< "PASS wide matrix: limb boundaries, exact identities, strict parser, budgets and scratch gates"

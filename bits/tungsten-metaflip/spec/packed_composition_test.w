use ../lib/metaflip/fleet/refinement_worker
use ../lib/metaflip/composition/pairs

if ARGV.size() == 2 && ARGV[0] == "--pages-test"
  queue = ARGV[1] + "/"
  kinds = ["tasks", "results"]
  k = 0 ## i64
  while k < 2
    kind = kinds[k]
    if !File.mkdir_p(queue + kind) || !File.mkdir_p(queue + kind + "-pages")
      exit(1)
    k += 1
  # New pages cross both 64-record boundaries. Legacy records end midway
  # through a page; the new suffix must not shadow or rewrite that evidence.
  if ffbq_put(queue, "tasks", 2, "gap\n") != 0 || ffbq_put(queue, "tasks", 65, "gap\n") != 0
    exit(1)
  i = 1 ## i64
  while i <= 130
    record = "record-" + i.to_s() + "\n"
    if ffbq_put(queue, "tasks", i, record) != 1 || ffbq_put(queue, "tasks", i, record) != 1 || ffbq_put(queue, "tasks", i, "conflict\n") != 0
      exit(1)
    if i < 38
      if !write_file(queue + "results/" + i.to_s(), record)
        exit(1)
    elsif ffbq_put(queue, "results", i, record) != 1
      exit(1)
    i += 1
  i = 1
  while i <= 130
    record = "record-" + i.to_s() + "\n"
    if ffbq_read(queue, "tasks", i) != record || ffbq_read(queue, "results", i) != record
      exit(1)
    i += 1
  long = ""
  i = 0
  while i < 255
    long = long + "x"
    i += 1
  if ffbq_read(queue, "tasks", 131) != nil || ffbq_put(queue, "tasks", 132, "gap\n") != 0 || ffbq_put(queue, "tasks", 193, "gap\n") != 0 || ffbq_put(queue, "tasks", 131, long + "\n") != 1
    exit(1)
  if ffbq_put(queue, "tasks", 132, long + "x\n") != 0 || ffbq_put(queue, "tasks", 132, "two\nlines\n") != 0 || ffbq_put(queue, "tasks", 132, "\n") != 0 || ffbq_put(queue, "tasks", 132, "unterminated") != 0
    exit(1)
  if ffbq_put(queue, "tasks", 0, "invalid\n") != 0 || ffbq_put(queue, "tasks", 1000000000001, "invalid\n") != 0
    exit(1)
  if !write_file(queue + "results/1", "two\nlines\n") || ffbq_read(queue, "results", 1) != "" || ffbq_put(queue, "results", 1, "record-1\n") != 0
    exit(1)
  if !write_file(queue + "results/1", "record-1\n")
    exit(1)
  if !write_file(queue + "stop", "stop\n") || ffbc_prepare(ARGV[1], "runtime", "unused", []) != 0-1
    exit(1)
  ccall("__w_unlink", queue + "stop")
  << "PASS record pages: 64/65, 128/129, legacy prefix, idempotence, length/gap rejection"
  exit(0)
if ARGV.size() == 4 && ARGV[0] == "--prepare"
  if ffbc_prepare(ARGV[1], ARGV[2], ARGV[3], []) != 1
    exit(1)
  exit(0)
if ARGV.size() == 5 && ARGV[0] == "--refine-batch"
  exit(ffrf_batch_with_composition(ARGV[1], ffw_parse_decimal_i64(ARGV[2]), ffw_parse_decimal_i64(ARGV[3]), ARGV[4]))
if ARGV.size() == 3 && ARGV[0] == "--compose-batch"
  exit(ffbc_drain(ARGV[1], ffw_parse_decimal_i64(ARGV[2])))
if ARGV.size() == 7 && ARGV[0] == "--compose"
  cap = 4096 ## i64
  parent = i64[3*cap]
  leaf = i64[3*cap]
  meta = i64[4]
  lm = i64[4]
  parity = i64[4096]
  axis = ffw_parse_decimal_i64(ARGV[4]) ## i64
  scale = ffw_parse_decimal_i64(ARGV[5]) ## i64
  if ffrf_load(ARGV[1], ARGV[2], parent, cap, meta, parity) != 1 || ffrf_load(ARGV[1], ARGV[3], leaf, cap, lm, parity) != 1 || lm[0] != 2 || lm[1] != scale || lm[2] != scale
    exit(2)
  mates = i64[cap]
  out = i64[3*32*16384]
  rank = ffbd_compose(parent, 3*cap, cap, meta[3], meta[0], meta[1], meta[2], axis, scale, leaf, 3*cap, cap, lm[3], mates, cap, out, 3*32*16384) ## i64
  n = meta[0]*ffbd_scale(axis, 0, scale) ## i64
  m = meta[1]*ffbd_scale(axis, 1, scale) ## i64
  p = meta[2]*ffbd_scale(axis, 2, scale) ## i64
  scratch = i64[32768]
  if rank < 1 || ffpk_exact(out, 3*32*16384, rank, n, m, p, scratch, 32768, 0) != 1
    << "FAIL composed tensor"
    exit(1)
  if !write_file(ARGV[6], ffpk_blob(out, rank, n, m, p))
    exit(1)
  << "PASS composition " + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " rank=" + rank.to_s()
  exit(0)
if ARGV.size() != 0
  exit(2)

# Exact naive <1,1,p> crosses limb and old signed-word boundaries.
p = 31 ## i64
while p <= 1024
  stride = ffpk_stride(1, 1, p) ## i64
  data = i64[3*stride*p]
  scratch = i64[p*stride]
  i = 0 ## i64
  while i < p
    data[3*i*stride] = 1
    data[(3*i+1)*stride+i/32] = 1 << (i%32)
    data[(3*i+2)*stride+i/32] = 1 << (i%32)
    i += 1
  if ffpk_exact(data, 3*stride*p, p, 1, 1, p, scratch, p*stride, 0) != 1 || ffpk_exact(data, 3*stride*p, p, 1, 1, p, scratch, p*stride, 1) != 0-1
    << "FAIL packed limb/budget gate"
    exit(1)
  if ffpk_exact(data, 3*stride*p-1, p, 1, 1, p, scratch, p*stride, 0) != 0 || ffpk_exact(data, 3*stride*p, p, 1, 1, p, scratch, p*stride-1, 0) != 0
    << "FAIL packed slab length gate"
    exit(1)
  data[0] = 4294967296
  if ffpk_exact(data, 3*stride*p, p, 1, 1, p, scratch, p*stride, 0) != 0
    << "FAIL invalid limb gate"
    exit(1)
  data[0] = 1
  data[1*stride] = data[1*stride] ^ 2
  if ffpk_exact(data, 3*stride*p, p, 1, 1, p, scratch, p*stride, 0) != 0
    << "FAIL off-support mutation"
    exit(1)
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
data = i64[18]
data[0] = 9
data[1] = 2
data[2] = 4
data[3] = 1
data[4] = 1
data[5] = 1
data[6] = 9
data[7] = 2
data[8] = 4
data[9] = 2
data[10] = 3
data[11] = 4
data[12] = 9
data[13] = 2
data[14] = 4
# Final term has a zero factor and disappears.
data[15] = 0
data[16] = 5
data[17] = 6
rank = ffpk_canonicalize(data, 18, 6, 1) ## i64
if rank != 3 || data[0] != 1 || data[3] != 2 || data[6] != 9 || ffpk_stride(33,33,33) != 0
  << "FAIL canonical parity/width gate"
  exit(1)
if ffpk_blob(data, rank, 4,4,4) != "MFW1 4 4 4 3\n1 1 1\n2 3 4\n9 2 4\n"
  << "FAIL packed canonical encoding"
  exit(1)
<< "PASS packed tensors: limb boundaries, full identity, parity, bounds, exhausted budget"

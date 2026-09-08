# Optional externally supplied corpus: no catalog tensor is redistributed here.
use ../lib/metaflip/fleet/pair_cleanup
use ../lib/metaflip/fleet/projection

-> rp_gate(work, capacity, rank, n, m, p) (i64[] i64 i64 i64 i64 i64) i64
  words = ffw_verify_scratch_words(n, m, p) ## i64
  parity = i64[words]
  ffw_support_tensor_error_scratch(work, 0, capacity, 2 * capacity, 0 - 1, rank, n, m, p, parity, words)

capacity = 4096 ## i64
words = ffmc_scratch_words(capacity) ## i64
work = i64[words]
source = i64[3 * capacity]
n = 3 ## i64
m = 4 ## i64
p = 5 ## i64
rank = 0 ## i64
if ARGV.size() == 0
  i = 0 ## i64
  while i < n
    j = 0 ## i64
    while j < m
      k = 0 ## i64
      while k < p
        source[rank] = 1 << (i*m+j)
        source[capacity+rank] = 1 << (j*p+k)
        source[2*capacity+rank] = 1 << (i*p+k)
        rank += 1
        k += 1
      j += 1
    i += 1
  axis = 0 ## i64
  while axis < 3
    size = n ## i64
    if axis == 1
      size = m
    if axis == 2
      size = p
    removed = 0 ## i64
    while removed < size
      projected = ffmp_project(source, 3*capacity, capacity, rank, n, m, p, axis, removed, work, words, capacity) ## i64
      nn = n ## i64
      mm = m ## i64
      pp = p ## i64
      if axis == 0
        nn -= 1
      if axis == 1
        mm -= 1
      if axis == 2
        pp -= 1
      if projected != nn*mm*pp || rp_gate(work, capacity, projected, nn, mm, pp) != 0
        << "FAIL coordinate projection"
        exit(1)
      removed += 1
    axis += 1
  work[0] = 991
  if ffmp_project(source, 3*capacity, capacity, rank, n, m, p, 1, m, work, words, capacity) != 0-1 || work[0] != 991
    << "FAIL projection validation"
    exit(1)
  << "PASS projection: every axis/coordinate, full tensors, invalid cut transaction"
else
  if ARGV.size() != 4 && ARGV.size() != 6
    << "usage: refinement_replay_test N M P TENSOR (optional: AXIS COORDINATE)"
    exit(1)
  n = ffw_parse_decimal_i64(ARGV[0])
  m = ffw_parse_decimal_i64(ARGV[1])
  p = ffw_parse_decimal_i64(ARGV[2])
  if n < 1 || m < 1 || p < 1 || n > 63 || m > 63 || p > 63 || n*m > 63 || m*p > 63 || n*p > 63
    exit(1)
  raw = read_file(ARGV[3])
  if raw == nil
    exit(1)
  lines = raw.strip().split("\n")
  rank = ffw_parse_decimal_i64(lines[0])
  if rank < 1 || rank > capacity || lines.size() != rank+1
    exit(1)
  i = 0 ## i64
  while i < rank
    fields = lines[i+1].split(" ")
    if fields.size() != 3
      exit(1)
    source[i] = ffw_parse_decimal_i64(fields[0])
    source[capacity+i] = ffw_parse_decimal_i64(fields[1])
    source[2*capacity+i] = ffw_parse_decimal_i64(fields[2])
    i += 1
  if rp_gate(source, capacity, rank, n, m, p) != 0
    << "FAIL source tensor"
    exit(1)
  if ARGV.size() == 6
    axis = ffw_parse_decimal_i64(ARGV[4]) ## i64
    removed = ffw_parse_decimal_i64(ARGV[5]) ## i64
    rank = ffmp_project(source, 3*capacity, capacity, rank, n, m, p, axis, removed, work, words, capacity)
    if axis == 0
      n -= 1
    if axis == 1
      m -= 1
    if axis == 2
      p -= 1
  else
    i = 0
    while i < rank
      work[i] = source[i]
      work[capacity+i] = source[capacity+i]
      work[2*capacity+i] = source[2*capacity+i]
      i += 1
  if rank < 1
    exit(1)
  pair_rank = ffpc_reduce(work, words, capacity, rank, 0, 1, 2) ## i64
  final_rank = ffmc_reduce(work, words, capacity, pair_rank) ## i64
  if final_rank < 1 || rp_gate(work, capacity, final_rank, n, m, p) != 0
    << "FAIL refined tensor"
    exit(1)
  << "TENSOR " + n.to_s() + " " + m.to_s() + " " + p.to_s() + " " + rank.to_s() + " " + pair_rank.to_s() + " " + final_rank.to_s()
  i = 0
  while i < final_rank
    << "TERM " + work[i].to_s() + " " + work[capacity+i].to_s() + " " + work[2*capacity+i].to_s()
    i += 1

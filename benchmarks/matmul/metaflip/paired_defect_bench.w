# Bounded real-certificate screen for paired nonzero-defect cancellation.
# This is a standalone decision benchmark, not fleet integration.

use paired_defect

-> pdcb_load(path, packed) (String i64[]) i64
  content = read_file(path)
  if content == nil
    return 0
  lines = content.split("\n")
  if lines.size() < 2
    return 0
  first = lines[0].split(" ")
  rank = first[0].to_i() ## i64
  line_base = 1 ## i64
  if first.size() >= 4
    line_base = 0
  if rank < 1 || packed.size() < rank*3 || lines.size() < rank+line_base
    return 0
  i = 0 ## i64
  while i < rank
    fields = lines[i+line_base].split(" ")
    base = 0 ## i64
    if fields.size() >= 4
      base = 1
    if fields.size() < base+3
      return 0
    packed[i*3] = fields[base].to_i()
    packed[i*3+1] = fields[base+1].to_i()
    packed[i*3+2] = fields[base+2].to_i()
    i += 1
  rank

-> pdcb_mmt_exact(packed, rank, n, m, p) (i64[] i64 i64 i64 i64) i64
  ubits = n*m ## i64
  vbits = m*p ## i64
  wbits = n*p ## i64
  words = i64[pdc_tensor_words(ubits,vbits,wbits)]
  if pdc_xor_packed(words,packed,rank,ubits,vbits,wbits) == 0
    return 0
  row = 0 ## i64
  while row < n
    inner = 0 ## i64
    while inner < m
      column = 0 ## i64
      while column < p
        u = 1 << (row*m+inner) ## i64
        v = 1 << (inner*p+column) ## i64
        w = 1 << (row*p+column) ## i64
        if pdc_xor_outer(words,u,v,w,ubits,vbits,wbits) == 0
          return 0
        column += 1
      inner += 1
    row += 1
  pdc_all_zero(words)

-> pdcb_selected(indices, value) (i64[] i64) i64
  i = 0 ## i64
  while i < 6
    if indices[i] == value
      return 1
    i += 1
  0

-> pdcb_toggle(packed, count, capacity, u, v, w) (i64[] i64 i64 i64 i64 i64) i64
  if u == 0 || v == 0 || w == 0
    return 0-count-1
  i = 0 ## i64
  while i < count
    if packed[i*3] == u && packed[i*3+1] == v && packed[i*3+2] == w
      last = count-1 ## i64
      packed[i*3] = packed[last*3]
      packed[i*3+1] = packed[last*3+1]
      packed[i*3+2] = packed[last*3+2]
      return last
    i += 1
  if count >= capacity
    return 0-count-1
  packed[count*3] = u
  packed[count*3+1] = v
  packed[count*3+2] = w
  count+1

-> pdcb_splice(source, rank, indices, replacement, out, capacity) (i64[] i64 i64[] i64[] i64[] i64) i64
  count = 0 ## i64
  i = 0 ## i64
  while i < rank
    if pdcb_selected(indices,i) == 0
      count = pdcb_toggle(out,count,capacity,source[i*3],source[i*3+1],source[i*3+2])
      if count < 0
        return 0
    i += 1
  i = 0
  while i < 4
    count = pdcb_toggle(out,count,capacity,replacement[i*3],replacement[i*3+1],replacement[i*3+2])
    if count < 0
      return 0
    i += 1
  count

n = 2 ## i64
m = 2 ## i64
p = 5 ## i64
attempt_budget = 128 ## i64
pool_cap = 32 ## i64
if ARGV.size() > 0
  parsed = ARGV[0].to_i() ## i64
  if parsed > 0
    attempt_budget = parsed
if ARGV.size() > 1
  parsed = ARGV[1].to_i() ## i64
  if parsed >= 4 && parsed <= 96
    pool_cap = parsed

path = __DIR__ + "/../../../bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_2x2x5_rank18_d84_gf2.txt"
source = i64[256*3]
rank = pdcb_load(path,source) ## i64
if rank != 18 || pdcb_mmt_exact(source,rank,n,m,p) == 0
  << "PAIRED_DEFECT_BENCH load-or-gate-failed path=" + path
  exit(1)

shape = i64[3]
shape[0] = n*m
shape[1] = m*p
shape[2] = n*p
indices = i64[6]
source_a = i64[9]
source_b = i64[9]
pool_a = i64[pool_cap*3]
pool_b = i64[pool_cap*3]
replacement = i64[12]
join_stats = i64[12]
candidate = i64[256*3]

total_a = 0 ## i64
total_b = 0 ## i64
hash_hits = 0 ## i64
defect_hits = 0 ## i64
full_hits = 0 ## i64
rank_hits = 0 ## i64
best_rank = rank ## i64
start_ms = ccall("__w_clock_ms") ## i64
attempt = 0 ## i64
while attempt < attempt_budget
  ticket_ok = pdc_window_ticket(rank,attempt+1,indices) ## i64
  if ticket_ok == 1
    i = 0 ## i64
    while i < 3
      z = pdc_copy_term(source,indices[i],source_a,i) ## i64
      z = pdc_copy_term(source,indices[i+3],source_b,i)
      i += 1
    pool_a_count = pdc_span_pool(source_a,pool_cap,attempt*2+1,pool_a) ## i64
    pool_b_count = pdc_span_pool(source_b,pool_cap,attempt*2+2,pool_b) ## i64
    found = pdc_join_3to2(source_a,source_b,pool_a,pool_a_count,pool_b,pool_b_count,shape,replacement,join_stats) ## i64
    total_a += join_stats[0]
    total_b += join_stats[1]
    hash_hits += join_stats[2]
    defect_hits += join_stats[3]
    if found == 1
      candidate_rank = pdcb_splice(source,rank,indices,replacement,candidate,256) ## i64
      if candidate_rank > 0 && pdcb_mmt_exact(candidate,candidate_rank,n,m,p) == 1
        full_hits += 1
        if candidate_rank < rank
          rank_hits += 1
          if candidate_rank < best_rank
            best_rank = candidate_rank
      else
        << "PAIRED_DEFECT_BENCH exact-intake-failure attempt=" + attempt.to_s()
        exit(1)
  attempt += 1
elapsed_ms = ccall("__w_clock_ms") - start_ms ## i64

<< "PAIRED_DEFECT_BENCH shape=2x2x5 rank=18 attempts=" + attempt_budget.to_s() + " pool=" + pool_cap.to_s() + " proposals=" + total_a.to_s() + "/" + total_b.to_s() + " hash_hits=" + hash_hits.to_s() + " exact_defects=" + defect_hits.to_s() + " full_exact=" + full_hits.to_s() + " rank_hits=" + rank_hits.to_s() + " best=" + best_rank.to_s() + " elapsed_ms=" + elapsed_ms.to_s()

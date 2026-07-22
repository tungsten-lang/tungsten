use ../lib/metaflip/strategies/rank_one_completion

-> ffroct_expect(label, condition) (String bool) i64
  if condition == false
    << "FAIL rank-one completion: " + label
    exit(1)
  1

-> ffroct_position(st, u, v, w) (i64[] i64 i64 i64) i64
  position = 0 ## i64
  while position < st[6]
    slot = st[st[50] + position] ## i64
    if st[st[44]+slot] == u && st[st[45]+slot] == v && st[st[46]+slot] == w
      return position
    position += 1
  0 - 1

n = 2 ## i64
dim = n * n ## i64
rows = i64[ffroc_slice_words(n)]
factors = i64[3]
z = ffroct_expect("zero slice", ffroc_classify_slice(rows,n,factors) == 0) ## i64
z = ffroc_toggle_slice(rows,9,10,12,dim)
z = ffroct_expect("one-pass rank-one factors", ffroc_classify_slice(rows,n,factors) == 1 && factors[0] == 9 && factors[1] == 10 && factors[2] == 12)
z = ffroc_toggle_slice(rows,1,1,1,dim)
z = ffroct_expect("rank-two slice rejected", ffroc_classify_slice(rows,n,factors) == 2)

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
capacity = ffw_default_capacity(n) ## i64
base = i64[ffw_state_size(capacity)]
base_rank = ffw_load_scheme_cap(base,root+"matmul_2x2_rank7_strassen_gf2.txt",n,capacity,81001,0,1,1,1) ## i64
z = ffroct_expect("Strassen source", base_rank == 7 && ffw_verify_current_exact(base,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
z = ffw_export_current(base,base_u,base_v,base_w)

# Rank-one completion plant: replace q=(9,9,9) with its U split.  Select the
# two children plus two unchanged terms.  The candidate pool contains those
# unchanged terms and distractors, but deliberately omits q.  Completion must
# compute q rather than look it up.
split_u = i64[capacity]
split_v = i64[capacity]
split_w = i64[capacity]
split_rank = 0 ## i64
i = 0 ## i64
while i < base_rank
  if base_u[i] != 9 || base_v[i] != 9 || base_w[i] != 9
    split_u[split_rank] = base_u[i]
    split_v[split_rank] = base_v[i]
    split_w[split_rank] = base_w[i]
    split_rank += 1
  i += 1
split_u[split_rank] = 1
split_v[split_rank] = 9
split_w[split_rank] = 9
split_rank += 1
split_u[split_rank] = 8
split_v[split_rank] = 9
split_w[split_rank] = 9
split_rank += 1
split = i64[ffw_state_size(capacity)]
loaded = ffw_init_terms_cap(split,split_u,split_v,split_w,split_rank,n,capacity,81003,0,1,1,1) ## i64
z = ffroct_expect("split shoulder exact", loaded == 8 && ffw_verify_current_exact(split,n) == 1)

selected = i64[4]
selected[0] = ffroct_position(split,1,9,9)
selected[1] = ffroct_position(split,8,9,9)
selected[2] = ffroct_position(split,12,1,12)
selected[3] = ffroct_position(split,1,10,10)
z = ffroct_expect("selected plant positions", selected[0] >= 0 && selected[1] >= 0 && selected[2] >= 0 && selected[3] >= 0)
pool_u = i64[4]
pool_v = i64[4]
pool_w = i64[4]
pool_u[0] = 12
pool_v[0] = 1
pool_w[0] = 12
pool_u[1] = 1
pool_v[1] = 10
pool_w[1] = 10
pool_u[2] = 8
pool_v[2] = 5
pool_w[2] = 5
pool_u[3] = 3
pool_v[3] = 8
pool_w[3] = 3
i = 0
while i < 4
  z = ffroct_expect("computed q absent from pool", pool_u[i] != 9 || pool_v[i] != 9 || pool_w[i] != 9)
  i += 1
before_digest = split[37] ## i64
out = i64[ffw_state_size(capacity)]
meta = i64[13]
hit = ffroc_search(split,selected,4,pool_u,pool_v,pool_w,4,6,out,capacity,81007,meta) ## i64
z = ffroct_expect("missing parent reconstructed", hit == 7 && meta[2] == 1 && meta[4] == 1 && meta[5] == 1)
z = ffroct_expect("computed parent factors", meta[7] == 9 && meta[8] == 9 && meta[9] == 9)
z = ffroct_expect("rank-one completion full gate", ffw_verify_current_exact(out,n) == 1 && ffw_verify_best_exact(out,n) == 1)
z = ffroct_expect("source immutable after rank-one hit", split[6] == 8 && split[37] == before_digest && ffw_verify_current_exact(split,n) == 1)

# Zero-residual plant: split q into three same-(V,W) terms whose U masks XOR
# to q.  Supplying q as the single B candidate proves the exact 3->1 branch.
three_u = i64[capacity]
three_v = i64[capacity]
three_w = i64[capacity]
three_rank = 0 ## i64
i = 0
while i < base_rank
  if base_u[i] != 9 || base_v[i] != 9 || base_w[i] != 9
    three_u[three_rank] = base_u[i]
    three_v[three_rank] = base_v[i]
    three_w[three_rank] = base_w[i]
    three_rank += 1
  i += 1
child_masks = i64[3]
child_masks[0] = 1
child_masks[1] = 2
child_masks[2] = 10
i = 0
while i < 3
  three_u[three_rank] = child_masks[i]
  three_v[three_rank] = 9
  three_w[three_rank] = 9
  three_rank += 1
  i += 1
three = i64[ffw_state_size(capacity)]
loaded = ffw_init_terms_cap(three,three_u,three_v,three_w,three_rank,n,capacity,81009,0,1,1,1)
z = ffroct_expect("three-way shoulder exact", loaded == 9 && ffw_verify_current_exact(three,n) == 1)
selected3 = i64[3]
selected3[0] = ffroct_position(three,1,9,9)
selected3[1] = ffroct_position(three,2,9,9)
selected3[2] = ffroct_position(three,10,9,9)
zero_pool_u = i64[3]
zero_pool_v = i64[3]
zero_pool_w = i64[3]
zero_pool_u[0] = 9
zero_pool_v[0] = 9
zero_pool_w[0] = 9
zero_pool_u[1] = 12
zero_pool_v[1] = 1
zero_pool_w[1] = 12
zero_pool_u[2] = 1
zero_pool_v[2] = 10
zero_pool_w[2] = 10
zero_out = i64[ffw_state_size(capacity)]
zero_meta = i64[13]
hit = ffroc_search(three,selected3,3,zero_pool_u,zero_pool_v,zero_pool_w,3,3,zero_out,capacity,81011,zero_meta)
z = ffroct_expect("zero residual 3-to-1", hit == 7 && zero_meta[1] == 1 && zero_meta[2] == 0 && zero_meta[5] == 1)
z = ffroct_expect("zero branch full gate and immutable source", ffw_verify_current_exact(zero_out,n) == 1 && three[6] == 9 && ffw_verify_current_exact(three,n) == 1)

# Duplicate source positions and duplicate candidate triples are rejected
# before enumeration and cannot trigger a full gate.
bad_selected = i64[4]
i = 0
while i < 4
  bad_selected[i] = selected[i]
  i += 1
bad_selected[3] = bad_selected[2]
bad_meta = i64[13]
bad_out = i64[ffw_state_size(capacity)]
hit = ffroc_search(split,bad_selected,4,pool_u,pool_v,pool_w,4,6,bad_out,capacity,81013,bad_meta)
z = ffroct_expect("duplicate selected rejected", hit == 0 && bad_meta[0] == 0 && bad_meta[4] == 0)
pool_u[3] = pool_u[2]
pool_v[3] = pool_v[2]
pool_w[3] = pool_w[2]
hit = ffroc_search(split,selected,4,pool_u,pool_v,pool_w,4,6,bad_out,capacity,81015,bad_meta)
z = ffroct_expect("duplicate pool rejected", hit == 0 && bad_meta[0] == 0 && bad_meta[4] == 0)
z = ffroct_expect("source immutable after adversaries", split[6] == 8 && split[37] == before_digest && ffw_verify_current_exact(split,n) == 1)

# Exhaustive recall at the intended largest bounded shape: a 3x3 record term
# is split, then its seven unchanged companions are hidden in the last seven
# positions of a 16-term pool.  Lexicographic C(16,7) enumeration must reach
# the final combination and reconstruct the omitted parent.
n3 = 3 ## i64
cap3 = ffw_default_capacity(n3) ## i64
base3 = i64[ffw_state_size(cap3)]
rank3 = ffw_load_scheme_cap(base3,root+"matmul_3x3_rank23_d139_gf2.txt",n3,cap3,81101,0,1,1,1) ## i64
z = ffroct_expect("3x3 recall source", rank3 == 23 && ffw_verify_current_exact(base3,n3) == 1)
b3u = i64[cap3]
b3v = i64[cap3]
b3w = i64[cap3]
z = ffw_export_current(base3,b3u,b3v,b3w)
shoulder3u = i64[cap3]
shoulder3v = i64[cap3]
shoulder3w = i64[cap3]
shoulder3rank = 0 ## i64
i = 0
while i < rank3
  if b3u[i] != 25 || b3v[i] != 6 || b3w[i] != 16
    shoulder3u[shoulder3rank] = b3u[i]
    shoulder3v[shoulder3rank] = b3v[i]
    shoulder3w[shoulder3rank] = b3w[i]
    shoulder3rank += 1
  i += 1
shoulder3u[shoulder3rank] = 1
shoulder3v[shoulder3rank] = 6
shoulder3w[shoulder3rank] = 16
shoulder3rank += 1
shoulder3u[shoulder3rank] = 24
shoulder3v[shoulder3rank] = 6
shoulder3w[shoulder3rank] = 16
shoulder3rank += 1
shoulder3 = i64[ffw_state_size(cap3)]
loaded = ffw_init_terms_cap(shoulder3,shoulder3u,shoulder3v,shoulder3w,shoulder3rank,n3,cap3,81103,0,1,1,1)
z = ffroct_expect("3x3 split shoulder", loaded == 24 && ffw_verify_current_exact(shoulder3,n3) == 1)
selected9 = i64[9]
selected9[0] = ffroct_position(shoulder3,1,6,16)
selected9[1] = ffroct_position(shoulder3,24,6,16)
i = 0
while i < 7
  selected9[i+2] = ffroct_position(shoulder3,b3u[i+1],b3v[i+1],b3w[i+1])
  i += 1
p16u = i64[16]
p16v = i64[16]
p16w = i64[16]
i = 0
while i < 9
  p16u[i] = ((i*37+3) & 511) | 1
  p16v[i] = ((i*53+69) & 511) | 1
  p16w[i] = ((i*71+131) & 511) | 1
  i += 1
i = 0
while i < 7
  p16u[i+9] = b3u[i+1]
  p16v[i+9] = b3v[i+1]
  p16w[i+9] = b3w[i+1]
  i += 1
recall_out = i64[ffw_state_size(cap3)]
recall_meta = i64[13]
hit = ffroc_search(shoulder3,selected9,9,p16u,p16v,p16w,16,11440,recall_out,cap3,81107,recall_meta)
z = ffroct_expect("C(16,7) last-leaf recall", hit == 23 && recall_meta[0] == 11440 && recall_meta[2] == 1 && recall_meta[5] == 1)
z = ffroct_expect("large recall computed parent", recall_meta[7] == 25 && recall_meta[8] == 6 && recall_meta[9] == 16)
z = ffroct_expect("large recall full gate", ffw_verify_current_exact(recall_out,n3) == 1 && ffw_verify_best_exact(recall_out,n3) == 1)
z = ffroct_expect("large recall source immutable", shoulder3[6] == 24 && ffw_verify_current_exact(shoulder3,n3) == 1)

<< "PASS rank-one completion planted-rankone=1 exhaustive-recall=11440 zero=1 ranktwo=1 duplicate=2 immutable=1"

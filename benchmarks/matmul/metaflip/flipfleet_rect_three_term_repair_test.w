use flipfleet_rect_three_term_repair
use flipfleet_block_composer

-> ffr3trt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

-> ffr3trt_check(label, u, v, w, terms, expected_dimension, expected_case, expected_rank) (String i64[] i64[] i64[] i64 i64 i64 i64) i64
  carrier = i64[ffrrw_tensor_words(2, 2, 5)]
  z = ffrrw_build_term_target(u, v, w, terms, 2, 2, 5, carrier) ## i64
  du = i64[3]
  dv = i64[3]
  dw = i64[3]
  meta = i64[6]
  rank = ffr3tr_decompose(carrier, 2, 2, 5, du, dv, dw, meta) ## i64
  ffr3trt_expect(label, rank == expected_rank && meta[0] == expected_dimension && meta[1] == expected_case && ffr3tr_rebuild(du, dv, dw, rank, 2, 2, 5, carrier) == 1)

# d=1: one U factor times a matrix of rank three.
u = i64[6]
v = i64[6]
w = i64[6]
u[0] = 9
u[1] = 9
u[2] = 9
v[0] = 1
v[1] = 2
v[2] = 4
w[0] = 1
w[1] = 2
w[2] = 4
z = ffr3trt_check("d1 matrix rank three", u, v, w, 3, 1, 10, 3) ## i64

# d=2, weight-two U relation.  The first selected slice basis obscures the
# useful 2+1 split; the A+B variant exposes it.
u[0] = 3
u[1] = 3
u[2] = 5
v[0] = 1
v[1] = 2
v[2] = 4
w[0] = 1
w[1] = 2
w[2] = 4
carrier = i64[ffrrw_tensor_words(2, 2, 5)]
z = ffrrw_build_term_target(u, v, w, 3, 2, 2, 5, carrier)
du = i64[3]
dv = i64[3]
dw = i64[3]
meta = i64[6]
rank = ffr3tr_decompose(carrier, 2, 2, 5, du, dv, dw, meta) ## i64
z = ffr3trt_expect("d2 weight-two relation", rank == 3 && meta[0] == 2 && meta[1] >= 20 && meta[1] <= 22 && meta[3] == 3)

# d=2, weight-three relation.  X+Y, X+Z, and Y+Z all have matrix rank two,
# so none of the 2+1 bases works.  The nine-candidate Z enumeration must.
u[0] = 3
u[1] = 5
u[2] = 6
v[0] = 1
v[1] = 2
v[2] = 4
w[0] = 1
w[1] = 2
w[2] = 4
z = ffrrw_build_term_target(u, v, w, 3, 2, 2, 5, carrier)
rank = ffr3tr_decompose(carrier, 2, 2, 5, du, dv, dw, meta)
z = ffr3trt_expect("d2 weight-three relation", rank == 3 && meta[0] == 2 && meta[1] == 29 && meta[4] >= 1 && meta[4] <= 9 && meta[5] == 2 && ffr3tr_rebuild(du, dv, dw, rank, 2, 2, 5, carrier) == 1)

# Exercise the complete shared-left/shared-right branch directly.  The first
# nontrivial shared-left candidate is the completing rectangle.
a = i64[10]
b = i64[10]
a[0] = 1
b[1] = 2
zmeta = i64[2]
rank = ffr3tr_d2_weight3(a, b, 3, 5, 10, 10, du, dv, dw, zmeta)
z = ffr3trt_expect("d2 rank-one anchor enumeration", rank == 3 && zmeta[1] == 1 && zmeta[0] == 1)

# The same cross-rectangle identity is width-independent.  The historical
# exponential mask scan failed closed above width twenty even though only the
# two algebraic cross products are needed.
large_a = i64[25]
large_b = i64[25]
large_a[0] = 1 << 24
large_b[24] = 1
rank = ffr3tr_d2_weight3(large_a, large_b, 3, 5, 25, 25, du, dv, dw, zmeta)
z = ffr3trt_expect("d2 rank-one cross at width 25", rank == 3 && zmeta[1] == 1 && zmeta[0] == 1)

# d=3: the first slice is the sum of all three matrices.  Recovering the
# planted terms therefore requires a nontrivial GL(3,2) basis change.
u[0] = 3
u[1] = 5
u[2] = 9
v[0] = 1
v[1] = 2
v[2] = 4
w[0] = 1
w[1] = 2
w[2] = 4
z = ffrrw_build_term_target(u, v, w, 3, 2, 2, 5, carrier)
rank = ffr3tr_decompose(carrier, 2, 2, 5, du, dv, dw, meta)
z = ffr3trt_expect("d3 GL basis", rank == 3 && meta[0] == 3 && meta[1] == 30 && meta[3] >= 1 && meta[3] <= 168 && ffr3tr_rebuild(du, dv, dw, rank, 2, 2, 5, carrier) == 1)

# The three-dimensional alternating 3x3 matrix space has matrix rank two for
# every nonzero member.  It forces the full 168-basis rejection path.
u[0] = 1
v[0] = 1
w[0] = 2
u[1] = 1
v[1] = 2
w[1] = 1
u[2] = 2
v[2] = 1
w[2] = 4
u[3] = 2
v[3] = 4
w[3] = 1
u[4] = 4
v[4] = 2
w[4] = 4
u[5] = 4
v[5] = 4
w[5] = 2
z = ffrrw_build_term_target(u, v, w, 6, 2, 2, 5, carrier)
rank = ffr3tr_decompose(carrier, 2, 2, 5, du, dv, dw, meta)
z = ffr3trt_expect("d3 complete rejection", rank < 0 && meta[0] == 3 && meta[3] == 168)

# Flattening rank four is an immediate lower bound of four.
u[0] = 1
u[1] = 2
u[2] = 4
u[3] = 8
v[0] = 1
v[1] = 2
v[2] = 4
v[3] = 8
w[0] = 1
w[1] = 2
w[2] = 4
w[3] = 8
z = ffrrw_build_term_target(u, v, w, 4, 2, 2, 5, carrier)
rank = ffr3tr_decompose(carrier, 2, 2, 5, du, dv, dw, meta)
z = ffr3trt_expect("d4 flattening rejection", rank < 0 && meta[0] == 4)

# Independently gate a materialized replacement in a real exact scheme.  This
# exercises the same full-tensor admission boundary as the offline scanner.
source = ffbc_load_exact("benchmarks/matmul/metaflip/matmul_2x2x5_rank18_d84_gf2.txt", 2, 2, 5, 32)
z = ffr3trt_expect("load exact d84", source != nil && source.rank() == 18)
source_u = i64[3]
source_v = i64[3]
source_w = i64[3]
term = 0 ## i64
while term < 3
  source_u[term] = source.us()[term]
  source_v[term] = source.vs()[term]
  source_w[term] = source.ws()[term]
  term += 1
z = ffrrw_build_term_target(source_u, source_v, source_w, 3, 2, 2, 5, carrier)
rank = ffr3tr_decompose(carrier, 2, 2, 5, du, dv, dw, meta)
materialized = FFBCScheme.new(2, 2, 5, 15 + rank)
at = 0 ## i64
term = 3
while term < 18
  materialized.us()[at] = source.us()[term]
  materialized.vs()[at] = source.vs()[term]
  materialized.ws()[at] = source.ws()[term]
  at += 1
  term += 1
term = 0
while term < rank
  materialized.us()[at] = du[term]
  materialized.vs()[at] = dv[term]
  materialized.ws()[at] = dw[term]
  at += 1
  term += 1
materialized.set_rank(at)
z = ffr3trt_expect("real FFBC materialization gate", rank >= 0 && rank <= 3 && ffr3tr_rebuild(du, dv, dw, rank, 2, 2, 5, carrier) == 1 && ffbc_verify_exact(materialized) == 1)

# Exhaustive oracle on the complete 4x2x2 tensor space.  This shape has 2^16
# carriers and 135 distinct nonzero rank-one tensors.  Mark every sum of zero
# through three distinct terms, then require the recognizer to agree on all
# 65,536 carriers.  This covers all d=0..4 cases independently of the planted
# examples above.
term_masks = i64[135]
one_u = i64[1]
one_v = i64[1]
one_w = i64[1]
one_carrier = i64[1]
count = 0 ## i64
umask = 1 ## i64
while umask < 16
  vmask = 1 ## i64
  while vmask < 4
    wmask = 1 ## i64
    while wmask < 4
      one_u[0] = umask
      one_v[0] = vmask
      one_w[0] = wmask
      z = ffrrw_build_term_target(one_u, one_v, one_w, 1, 2, 2, 1, one_carrier)
      term_masks[count] = one_carrier[0]
      count += 1
      wmask += 1
    vmask += 1
  umask += 1
z = ffr3trt_expect("4x2x2 rank-one catalogue", count == 135)
reference = i64[65536]
reference[0] = 1
i = 0 ## i64
while i < count
  reference[term_masks[i]] = 1
  j = i + 1 ## i64
  while j < count
    reference[term_masks[i] ^ term_masks[j]] = 1
    k = j + 1 ## i64
    while k < count
      reference[term_masks[i] ^ term_masks[j] ^ term_masks[k]] = 1
      k += 1
    j += 1
  i += 1
mask = 0 ## i64
while mask < 65536
  one_carrier[0] = mask
  oracle_u = i64[3]
  oracle_v = i64[3]
  oracle_w = i64[3]
  oracle_meta = i64[6]
  oracle_rank = ffr3tr_decompose(one_carrier, 2, 2, 1, oracle_u, oracle_v, oracle_w, oracle_meta) ## i64
  if reference[mask] == 1
    if oracle_rank < 0 || oracle_rank > 3 || ffr3tr_rebuild(oracle_u, oracle_v, oracle_w, oracle_rank, 2, 2, 1, one_carrier) != 1
      << "FAIL exhaustive 4x2x2 positive mask=" + mask.to_s()
      exit(1)
  else
    if oracle_rank >= 0
      << "FAIL exhaustive 4x2x2 negative mask=" + mask.to_s()
      exit(1)
  mask += 1

<< "PASS flipfleet rectangular three-term repair"

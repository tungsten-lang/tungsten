use flipfleet_projection_replacement
use flipfleet_block_composer

-> ffprt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

# Naive 3x3 with a Strassen 2x2 core gives a small, deterministic exact test.
capacity = 128 ## i64
source_u = i64[capacity]
source_v = i64[capacity]
source_w = i64[capacity]
source_rank = 0 ## i64
i = 0 ## i64
while i < 3
  j = 0 ## i64
  while j < 3
    k = 0 ## i64
    while k < 3
      source_u[source_rank] = 1 << (i * 3 + j)
      source_v[source_rank] = 1 << (j * 3 + k)
      source_w[source_rank] = 1 << (i * 3 + k)
      source_rank += 1
      k += 1
    j += 1
  i += 1
ffprt_expect("naive source exact", source_rank == 27 && ffpbr_verify_exact(source_u, source_v, source_w, source_rank, 3, 3, 3) == 1)

lower = ffbc_load_exact("benchmarks/matmul/metaflip/matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
ffprt_expect("lower exact", lower != nil && lower.rank() == 7)
lower_u = i64[capacity]
lower_v = i64[capacity]
lower_w = i64[capacity]
t = 0 ## i64
while t < lower.rank()
  lower_u[t] = lower.us()[t * lower.uw()]
  lower_v[t] = lower.vs()[t * lower.vw()]
  lower_w[t] = lower.ws()[t * lower.ww()]
  t += 1

out_u = i64[capacity]
out_v = i64[capacity]
out_w = i64[capacity]
meta = i64[8]
rank = ffpr_splice(source_u, source_v, source_w, source_rank, lower_u, lower_v, lower_w, lower.rank(), 3, 2, out_u, out_v, out_w, capacity, meta) ## i64
ffprt_expect("replacement exact", rank > 0 && meta[7] == 1 && ffpbr_verify_exact(out_u, out_v, out_w, rank, 3, 3, 3) == 1)
ffprt_expect("rank accounting", rank == meta[3] && meta[4] == rank - source_rank && meta[6] == source_rank + meta[1] + lower.rank() - rank)

# The indexed variant chooses a non-prefix 2x2 core and must retain the same
# exact replace-naive-by-Strassen accounting.
indexed_project_u = i64[capacity]
indexed_project_v = i64[capacity]
indexed_project_w = i64[capacity]
indexed_u = i64[capacity]
indexed_v = i64[capacity]
indexed_w = i64[capacity]
indexed_meta = i64[8]
indexed_rank = ffpr_splice2_indexed(source_u, source_v, source_w, source_rank, lower_u, lower_v, lower_w, lower.rank(), 3, 0, 2, 0, 2, 0, 2, indexed_project_u, indexed_project_v, indexed_project_w, indexed_u, indexed_v, indexed_w, capacity, 1, indexed_meta) ## i64
ffprt_expect("indexed replacement exact", indexed_rank == 26 && indexed_meta[4] == -1 && indexed_meta[7] == 1 && ffpbr_verify_exact(indexed_u, indexed_v, indexed_w, indexed_rank, 3, 3, 3) == 1)

# The general d-dimensional helper must agree on the same non-prefix core.
indices = i64[2]
indices[0] = 0
indices[1] = 2
general_project_u = i64[capacity]
general_project_v = i64[capacity]
general_project_w = i64[capacity]
general_u = i64[capacity]
general_v = i64[capacity]
general_w = i64[capacity]
general_meta = i64[8]
general_rank = ffpr_splice_indexed(source_u, source_v, source_w, source_rank, lower_u, lower_v, lower_w, lower.rank(), 3, 2, indices, indices, indices, general_project_u, general_project_v, general_project_w, general_u, general_v, general_w, capacity, 1, general_meta) ## i64
ffprt_expect("general indexed replacement exact", general_rank == 26 && general_meta[4] == -1 && general_meta[7] == 1 && ffpbr_verify_exact(general_u, general_v, general_w, general_rank, 3, 3, 3) == 1)
<< "flipfleet_projection_replacement_test: all checks passed rank=" + rank.to_s() + " debt=" + meta[4].to_s()

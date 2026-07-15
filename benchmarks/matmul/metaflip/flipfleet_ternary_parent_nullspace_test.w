use flipfleet_ternary_parent_nullspace

-> fftpnt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

prime1 = 1000003 ## i64
prime2 = 1000033 ## i64
n = 2 ## i64
capacity = fft_default_capacity(n) ## i64
base = i64[fft_state_size(capacity)]
z = fftpnt_expect("Strassen exact", fft_init_strassen(base, capacity, 2026072101, 4) == 7 && fft_verify_current_exact(base) == 1) ## i64

# Signed-column comparison includes the overall tensor sign carried by W.
negated = i64[fft_state_size(capacity)]
z = fftpnt_expect("clone for signed key", fft_clone_gated_seed(negated, base, 2026072102, 4) == 7)
tmp = negated[negated[36]] ## i64
negated[negated[36]] = negated[negated[37]]
negated[negated[37]] = tmp
z = fftpnt_expect("collision-free equal signed column", fftpns_term_equal(base, 0, base, 0) == 1)
z = fftpnt_expect("opposite signed column", fftpns_term_opposite(base, 0, negated, 0) == 1 && fftpns_term_equal(base, 0, negated, 0) == 0)

# One exact split leaves a three-column reduced difference with only the full
# parent relation.
single = i64[fft_state_size(capacity)]
z = fftpnt_expect("single clone", fft_clone_gated_seed(single, base, 2026072103, 4) == 7)
z = fftpnt_expect("single split exact", fft_split_partition(single, 0, 0, 1) == 1 && single[5] == 8 && fft_verify_current_exact(single) == 1)
left_indices = i64[base[5]]
right_indices = i64[single[5]]
union_meta = i64[4]
columns = fftpns_reduced_union(base, single, left_indices, right_indices, union_meta) ## i64
z = fftpnt_expect("single reduced union", columns == 3 && union_meta[0] == 1 && union_meta[1] == 2 && union_meta[2] == 6)
z = fftpnt_expect("single integer relation", fftpns_union_exact(base, single, left_indices, 1, right_indices, 2, n) == 1)
basis1 = i64[columns * columns]
have1 = i64[columns]
rank_meta1 = i64[4]
rank1 = fftpns_modular_rank(base, single, left_indices, 1, right_indices, 2, n, prime1, basis1, have1, rank_meta1) ## i64
basis2 = i64[columns * columns]
have2 = i64[columns]
rank_meta2 = i64[4]
rank2 = fftpns_modular_rank(base, single, left_indices, 1, right_indices, 2, n, prime2, basis2, have2, rank_meta2) ## i64
z = fftpnt_expect("single full-only modular nullity", rank1 == 2 && rank2 == 2 && rank_meta1[2] == 0 && rank_meta2[2] == 0)

# Two disjoint exact splits produce two independent local relations.  Their
# union has nullity two: two proper binary splices plus the full difference.
double = i64[fft_state_size(capacity)]
z = fftpnt_expect("double clone", fft_clone_gated_seed(double, base, 2026072104, 4) == 7)
z = fftpnt_expect("first double split", fft_split_partition(double, 0, 0, 1) == 1)
second = 0 ## i64
target = 1 ## i64
while target < 7 && second == 0
  axis = 0 ## i64
  while axis < 3 && second == 0
    second = fft_split_partition(double, target, axis, 1)
    axis += 1
  target += 1
z = fftpnt_expect("second disjoint split exact", second == 1 && double[5] == 9 && fft_verify_current_exact(double) == 1)

left_indices = i64[base[5]]
right_indices = i64[double[5]]
columns = fftpns_reduced_union(base, double, left_indices, right_indices, union_meta)
z = fftpnt_expect("double reduced union", columns == 6 && union_meta[0] == 2 && union_meta[1] == 4 && union_meta[2] == 5)
z = fftpnt_expect("double integer relation", fftpns_union_exact(base, double, left_indices, 2, right_indices, 4, n) == 1)
basis1 = i64[columns * columns]
have1 = i64[columns]
rank1 = fftpns_modular_rank(base, double, left_indices, 2, right_indices, 4, n, prime1, basis1, have1, rank_meta1)
basis2 = i64[columns * columns]
have2 = i64[columns]
rank2 = fftpns_modular_rank(base, double, left_indices, 2, right_indices, 4, n, prime2, basis2, have2, rank_meta2)
z = fftpnt_expect("double modular nullity two", rank1 == 4 && rank2 == 4)

# The bounded archive audit uses stacked deterministic weighted Gram rows.
# On the planted two-relation example they recover the complete rank over
# both primes while retaining the all-ones parent relation.
up = i64[columns]
un = i64[columns]
vp = i64[columns]
vn = i64[columns]
wp = i64[columns]
wn = i64[columns]
signs = i64[columns]
z = fftpnt_expect("compact signed union", fftpns_union_factor_arrays(base, double, left_indices, 2, right_indices, 4, up, un, vp, vn, wp, wn, signs) == columns)
gram_basis1 = i64[columns * columns]
gram_have1 = i64[columns]
gram_meta1 = i64[4]
gram_rank1 = fftpns_stacked_gram_rank(up, un, vp, vn, wp, wn, signs, columns, n * n, prime1, 4, gram_basis1, gram_have1, gram_meta1) ## i64
gram_basis2 = i64[columns * columns]
gram_have2 = i64[columns]
gram_meta2 = i64[4]
gram_rank2 = fftpns_stacked_gram_rank(up, un, vp, vn, wp, wn, signs, columns, n * n, prime2, 4, gram_basis2, gram_have2, gram_meta2) ## i64
z = fftpnt_expect("stacked Gram proof-safe rank", gram_rank1 == 4 && gram_rank2 == 4 && gram_meta1[2] == 0 && gram_meta2[2] == 0)

proper = 0 ## i64
full = 0 ## i64
assignment = 1 ## i64
while assignment < 4
  relation = i64[columns]
  nullity = fftpns_null_vector(basis1, have1, columns, prime1, assignment, relation) ## i64
  z = fftpnt_expect("null vector dimension", nullity == 2)
  if fftpns_binary_vector(relation) == 1
    if fftpns_all_ones(relation) == 1
      full += 1
    else
      z = fftpnt_expect("proper relation integer exact", fftpns_subset_exact(base, double, left_indices, 2, right_indices, 4, relation, n) == 1)
      child_meta = i64[6]
      child = fftpns_materialize(base, double, left_indices, 2, right_indices, 4, relation, 2026072200 + assignment, child_meta)
      z = fftpnt_expect("proper strict child exact", child != nil && child[5] == 8 && child_meta[0] == 1 && child_meta[1] == 2 && child_meta[5] == 1 && fft_verify_current_exact(child) == 1)
      proper += 1
  assignment += 1
z = fftpnt_expect("all planted relations enumerated", proper == 2 && full == 1)

<< "PASS ternary two-parent nullspace: signed canonical columns, two-prime ranks, proper strict splices"

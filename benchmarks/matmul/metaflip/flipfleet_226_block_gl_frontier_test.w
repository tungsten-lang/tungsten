use flipfleet_226_block_gl_parent_lib
use flipfleet_rect_archive_nullspace

-> ff226bgft_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

root = "benchmarks/matmul/metaflip/"
leaf = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
baseline = ffbc_load_exact(root + "matmul_2x2x6_rank21_strassen_blocks_gf2.txt", 2, 2, 6, 32)
door = ffbc_load_exact(root + "matmul_2x2x6_rank21_d108_block_local_gl_gf2.txt", 2, 2, 6, 32)
outer = ff226gl_outer()
z = ff226bgft_expect("exact seeds", leaf != nil && baseline != nil && door != nil && outer != nil && ffbc_verify_exact(baseline) == 1 && ffbc_verify_exact(door) == 1) ## i64
z = ff226bgft_expect("rank and density", baseline.rank() == 21 && door.rank() == 21 && fflc_density(baseline) == 108 && fflc_density(door) == 108)
z = ff226bgft_expect("zero-overlap door", fflc_term_set_distance(baseline, door) == 42 && fflc_equal_factor_pairs(door) == 21)

alloc_n = ff226gl_alloc_n()
alloc_m = ff226gl_alloc_m()
alloc_p = ff226gl_alloc_p()
reproduced = ff226gl_parent(leaf, outer, alloc_n, alloc_m, alloc_p, 7)
replayed = ff226gl_parent(leaf, outer, alloc_n, alloc_m, alloc_p, 7)
z = ff226bgft_expect("deterministic index-7 replay", reproduced != nil && replayed != nil && fflc_term_set_distance(reproduced, door) == 0 && fflc_term_set_distance(reproduced, replayed) == 0)

du = i64[42]
dv = i64[42]
dw = i64[42]
owners = i64[42]
difference = ffnd_build_difference(door.us(), door.vs(), door.ws(), 21, baseline.us(), baseline.vs(), baseline.ws(), 21, du, dv, dw, owners) ## i64
combo_words = ffnd_combo_words(difference) ## i64
basis = i64[difference * combo_words]
elimination = i64[5]
nullity = ffran_build_nullspace(du, dv, dw, difference, 2, 2, 6, basis, elimination) ## i64
z = ff226bgft_expect("three independent leaf relations", difference == 42 && nullity == 3 && elimination[2] == 39)

relations = 0 ## i64
proper = 0 ## i64
rank20 = 0 ## i64
exact21 = 0 ## i64
relation = i64[combo_words]
code = 1 ## i64
while code < (1 << nullity)
  z = ffnd_clear(relation, 0, combo_words)
  bit = 0 ## i64
  while bit < nullity
    if ((code >> bit) & 1) != 0
      z = ffnd_xor(basis, bit * combo_words, relation, 0, combo_words)
    bit += 1
  relations += 1
  z = ff226bgft_expect("basis relation exact", ffran_relation_exact(du, dv, dw, difference, 2, 2, 6, relation, 0) == 1)
  score = i64[3]
  projected = ffnd_score_mask(relation, 0, owners, difference, 21, score) ## i64
  if projected > 0
    proper += 1
    if projected <= 20
      rank20 += 1
    out_u = i64[42]
    out_v = i64[42]
    out_w = i64[42]
    child_rank = ffnd_materialize(door.us(), door.vs(), door.ws(), 21, du, dv, dw, difference, relation, out_u, out_v, out_w) ## i64
    child = FFBCScheme.new(2, 2, 6, child_rank)
    i = 0 ## i64
    while i < child_rank
      child.us()[i] = out_u[i]
      child.vs()[i] = out_v[i]
      child.ws()[i] = out_w[i]
      i += 1
    child.set_rank(child_rank)
    if child_rank == 21 && ffbc_verify_exact(child) == 1
      exact21 += 1
  code += 1

z = ff226bgft_expect("complete baseline-door hull", relations == 7 && proper == 6 && exact21 == 6 && rank20 == 0)
<< "PASS flipfleet 226 block-local GL frontier relations=" + relations.to_s() + " proper=" + proper.to_s() + " rank20=" + rank20.to_s()

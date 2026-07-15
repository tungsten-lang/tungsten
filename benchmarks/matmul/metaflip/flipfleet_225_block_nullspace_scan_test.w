use flipfleet_225_block_gl_parent_lib
use flipfleet_rect_archive_nullspace

-> ff225nst_expect(label, condition)
  if condition == 0
    << "FAIL " + label
    exit(1)
  1

root = "benchmarks/matmul/metaflip/"
leaf3 = ffbc_load_exact(root + "matmul_2x2x3_rank11_catalog_gf2.txt", 2, 2, 3, 16)
leaf2 = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
outer = ff225gl_outer()
z = ff225nst_expect("generator seeds", leaf3 != nil && leaf2 != nil && outer != nil) ## i64
alloc_n = ff225gl_alloc_n()
alloc_m = ff225gl_alloc_m()
alloc_p = ff225gl_alloc_p()
parent = ff225gl_parent(leaf3, leaf2, outer, alloc_n, alloc_m, alloc_p, 0)
parent_replay = ff225gl_parent(leaf3, leaf2, outer, alloc_n, alloc_m, alloc_p, 0)
z = ff225nst_expect("deterministic exact parent", parent != nil && parent_replay != nil && parent.rank() == 18 && ffbc_verify_exact(parent) == 1 && fflc_term_set_distance(parent, parent_replay) == 0)

doors = []
paths = []
paths.push(root + "matmul_2x2x5_rank18_d84_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d88_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d84_block_splice_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt")
i = 0 ## i64
while i < paths.size()
  door = ffbc_load_exact(paths[i], 2, 2, 5, 32)
  z = ff225nst_expect("door exact", door != nil && door.rank() == 18 && ffbc_verify_exact(door) == 1)
  doors.push(door)
  i += 1

expected_nullity = i64[5]
expected_nullity[0] = 2
expected_nullity[1] = 1
expected_nullity[2] = 2
expected_nullity[3] = 2
expected_nullity[4] = 2
relations = 0 ## i64
proper = 0 ## i64
rank17 = 0 ## i64
door_index = 0 ## i64
while door_index < doors.size()
  door = doors[door_index]
  du = i64[36]
  dv = i64[36]
  dw = i64[36]
  owners = i64[36]
  difference = ffnd_build_difference(parent.us(), parent.vs(), parent.ws(), 18, door.us(), door.vs(), door.ws(), 18, du, dv, dw, owners) ## i64
  combo_words = ffnd_combo_words(difference) ## i64
  basis = i64[difference * combo_words]
  elimination = i64[5]
  nullity = ffran_build_nullspace(du, dv, dw, difference, 2, 2, 5, basis, elimination) ## i64
  z = ff225nst_expect("known nullity", nullity == expected_nullity[door_index] && elimination[2] + nullity == difference)
  limit = 1 << nullity ## i64
  relation = i64[combo_words]
  code = 1 ## i64
  pair_proper = 0 ## i64
  while code < limit
    z = ffnd_clear(relation, 0, combo_words)
    bit = 0 ## i64
    while bit < nullity
      if ((code >> bit) & 1) != 0
        z = ffnd_xor(basis, bit * combo_words, relation, 0, combo_words)
      bit += 1
    relations += 1
    z = ff225nst_expect("basis relation exact", ffran_relation_exact(du, dv, dw, difference, 2, 2, 5, relation, 0) == 1)
    score = i64[3]
    projected = ffnd_score_mask(relation, 0, owners, difference, 18, score) ## i64
    if projected > 0
      proper += 1
      pair_proper += 1
      z = ff225nst_expect("proper hybrid rank", projected == 18)
      if projected == 17
        rank17 += 1
    code += 1
  meta = i64[9]
  child = ffran_crossover(parent, door, limit - 1 + nullity + nullity * (nullity - 1) / 2, meta)
  if nullity == 1
    z = ff225nst_expect("full relation only", pair_proper == 0 && child == nil)
  else
    z = ff225nst_expect("proper child exact", pair_proper == 2 && child != nil && child.rank() == 18 && meta[8] == 1 && ffbc_verify_exact(child) == 1)
  door_index += 1

z = ff225nst_expect("complete one-parent hull", relations == 13 && proper == 8 && rank17 == 0)
<< "PASS flipfleet 225 block nullspace scan relations=" + relations.to_s() + " proper=" + proper.to_s() + " rank17=" + rank17.to_s()

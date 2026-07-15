# Bounded proof audit for the closest strict-ternary archive lineages.
#
# These are exactly the parent pairs whose reduced signed differences have
# 4/6/32 columns at 5x5, 12/16/48 columns at 6x6, and 64 columns at 7x7.
# The full parent difference is always a relation.  Deterministic stacked
# weighted Gram matrices provide a lower bound on the true modular column
# rank; a rank of columns-1 therefore proves that no proper rational relation
# exists.  Any larger screened kernel is exhaustively enumerated over binary
# free coordinates and admitted only after a full integer coefficient gate.

use flipfleet_ternary_parent_nullspace

-> fftpnla_fail(label) (String) i64
  << "TERNARY_PARENT_LOCAL_FAIL " + label
  exit(1)
  0

-> fftpnla_no_duplicate_terms(st) (i64[]) i64
  i = 0 ## i64
  while i < st[5]
    j = i + 1 ## i64
    while j < st[5]
      if fftpns_term_equal(st, i, st, j) == 1
        return 0
      j += 1
    i += 1
  1

-> fftpnla_load(st, path, n, expected_rank, seed) (i64[] String i64 i64 i64) i64
  rank = fft_load_seed(st, path, n, fft_default_capacity(n), seed, 4) ## i64
  if rank != expected_rank || st[19] != 0 || fftpnla_no_duplicate_terms(st) != 1
    return 0
  term = 0 ## i64
  while term < rank
    if fft_first_sign(st[st[32] + term], st[st[33] + term]) != 1 || fft_first_sign(st[st[34] + term], st[st[35] + term]) != 1
      return 0
    term += 1
  1

# If the union of both parent archives contains no opposite signed columns,
# the materialized rank is exactly R-|selected A|+|selected B|: the compacting
# phase has nothing it can cancel.  This lets a large disjoint relation cube
# be rank-audited without constructing every child.
-> fftpnla_opposite_free(left, right) (i64[] i64[]) i64
  i = 0 ## i64
  while i < left[5]
    j = i + 1 ## i64
    while j < left[5]
      if fftpns_term_opposite(left, i, left, j) == 1
        return 0
      j += 1
    j = 0
    while j < right[5]
      if fftpns_term_opposite(left, i, right, j) == 1
        return 0
      j += 1
    i += 1
  i = 0
  while i < right[5]
    j = i + 1
    while j < right[5]
      if fftpns_term_opposite(right, i, right, j) == 1
        return 0
      j += 1
    i += 1
  1

# Short continuation test for a materialized representative.  Exact reduced
# unions record its signed term-set distance from both parents before walking.
# meta receives tested, rank wins, child-density wins, and wins over both
# parent densities.
-> fftpnla_continue(child, left, right, steps, pair_id, tag, meta) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  if steps <= 0
    return 1
  child_indices = i64[child[5]]
  parent_indices = i64[left[5]]
  distance_meta = i64[4]
  distance_left = fftpns_reduced_union(child, left, child_indices, parent_indices, distance_meta) ## i64
  left_left = distance_meta[0] ## i64
  left_right = distance_meta[1] ## i64
  child_indices = i64[child[5]]
  parent_indices = i64[right[5]]
  distance_meta = i64[4]
  distance_right = fftpns_reduced_union(child, right, child_indices, parent_indices, distance_meta) ## i64
  right_left = distance_meta[0] ## i64
  right_right = distance_meta[1] ## i64
  if distance_left == 0 || distance_right == 0
    return 0
  start_rank = child[6] ## i64
  start_density = child[21] ## i64
  parent_density = left[21] ## i64
  if right[21] < parent_density
    parent_density = right[21]
  drops = fft_walk(child, steps) ## i64
  if drops < 0 || fft_verify_best_exact(child) != 1
    return 0
  meta[0] = meta[0] + 1
  if child[6] < start_rank
    meta[1] = meta[1] + 1
  if child[6] == start_rank && child[21] < start_density
    meta[2] = meta[2] + 1
  if child[6] < start_rank || (child[6] == start_rank && child[21] < parent_density)
    meta[3] = meta[3] + 1
  if child[6] < start_rank || child[21] < start_density
    output = "/tmp/ternary-parent-local-cont-p" + pair_id.to_s() + "-t" + tag.to_s() + "-r" + child[6].to_s() + "-d" + child[21].to_s() + ".txt"
    if fft_dump_best(child, output) != child[6]
      return 0
  << "TERNARY_PARENT_LOCAL_CONT pair=" + pair_id.to_s() + " tag=" + tag.to_s() + " signed_distance=" + left_left.to_s() + "/" + left_right.to_s() + "," + right_left.to_s() + "/" + right_right.to_s() + " parent_density=" + left[21].to_s() + "/" + right[21].to_s() + " start=r" + start_rank.to_s() + "/d" + start_density.to_s() + " best=r" + child[6].to_s() + "/d" + child[21].to_s()
  1

# meta: columns, common, rank p1/p2, selected nullity bound, proper exact,
# materialized strict children, rank drops, continuation tests/rank/density.
-> fftpnla_audit_pair(left, right, n, expected_columns, pair_id, profiles, max_nullity, continuation_steps, meta) (i64[] i64[] i64 i64 i64 i64 i64 i64 i64[]) i64
  left_indices = i64[left[5]]
  right_indices = i64[right[5]]
  union_meta = i64[4]
  columns = fftpns_reduced_union(left, right, left_indices, right_indices, union_meta) ## i64
  if columns != expected_columns || union_meta[0] + union_meta[2] != left[5] || union_meta[1] + union_meta[2] != right[5]
    return 0
  if fftpns_union_exact(left, right, left_indices, union_meta[0], right_indices, union_meta[1], n) != 1
    return 0

  up = i64[columns]
  un = i64[columns]
  vp = i64[columns]
  vn = i64[columns]
  wp = i64[columns]
  wn = i64[columns]
  signs = i64[columns]
  if fftpns_union_factor_arrays(left, right, left_indices, union_meta[0], right_indices, union_meta[1], up, un, vp, vn, wp, wn, signs) != columns
    return 0

  prime1 = 1000003 ## i64
  prime2 = 1000033 ## i64
  basis1 = i64[columns * columns]
  have1 = i64[columns]
  rank_meta1 = i64[4]
  rank1 = fftpns_stacked_gram_rank(up, un, vp, vn, wp, wn, signs, columns, n * n, prime1, profiles, basis1, have1, rank_meta1) ## i64
  basis2 = i64[columns * columns]
  have2 = i64[columns]
  rank_meta2 = i64[4]
  rank2 = fftpns_stacked_gram_rank(up, un, vp, vn, wp, wn, signs, columns, n * n, prime2, profiles, basis2, have2, rank_meta2) ## i64
  if rank1 < 0 || rank2 < 0 || rank_meta1[2] != 0 || rank_meta2[2] != 0
    return 0

  reference_basis = basis1
  reference_have = have1
  reference_prime = prime1 ## i64
  reference_rank = rank1 ## i64
  if rank2 > rank1
    reference_basis = basis2
    reference_have = have2
    reference_prime = prime2
    reference_rank = rank2
  nullity = columns - reference_rank ## i64
  proper_exact = 0 ## i64
  materialized = 0 ## i64
  rank_drops = 0 ## i64
  cube_proof = 0 ## i64
  continuation_meta = i64[4]

  if reference_rank < columns - 1 && nullity <= max_nullity
    limit = 1 << nullity ## i64
    full = i64[columns]
    solved = fftpns_null_vector(reference_basis, reference_have, columns, reference_prime, limit - 1, full) ## i64
    if solved != nullity || fftpns_all_ones(full) != 1
      return 0
    if fftpnla_opposite_free(left, right) != 1
      return 0

    # Prove a direct-sum relation cube when the free-coordinate basis consists
    # of disjoint binary exact relations covering the complete signed union.
    # Then every one of its 2^k subsets is an exact integer relation; checking
    # the k basis identities is an exhaustive certificate, not sampling.
    basis_vectors = i64[nullity * columns]
    basis_delta = i64[nullity]
    basis_support = i64[nullity]
    support_hits = i64[columns]
    cube_proof = 1
    free = 0 ## i64
    while free < nullity
      relation = i64[columns]
      solved = fftpns_null_vector(reference_basis, reference_have, columns, reference_prime, 1 << free, relation)
      if solved != nullity || fftpns_binary_vector(relation) != 1 || fftpns_subset_exact(left, right, left_indices, union_meta[0], right_indices, union_meta[1], relation, n) != 1
        cube_proof = 0
      selected_left = 0 ## i64
      selected_right = 0 ## i64
      column = 0 ## i64
      while column < columns
        basis_vectors[free * columns + column] = relation[column]
        support_hits[column] = support_hits[column] + relation[column]
        if relation[column] == 1
          if column < union_meta[0]
            selected_left += 1
          else
            selected_right += 1
        column += 1
      basis_delta[free] = selected_right - selected_left
      basis_support[free] = selected_right + selected_left
      free += 1
    column = 0
    while column < columns
      if support_hits[column] != 1
        cube_proof = 0
      column += 1

    if cube_proof == 1
      proper_exact = limit - 2
      drop_assignment = 0 ## i64
      balanced_assignment = 0 ## i64
      balanced_score = 0 ## i64
      assignment = 1 ## i64
      while assignment < limit - 1
        delta = 0 ## i64
        support = 0 ## i64
        free = 0
        while free < nullity
          if ((assignment >> free) & 1) != 0
            delta += basis_delta[free]
            support += basis_support[free]
          free += 1
        other_support = columns - support ## i64
        score = support ## i64
        if other_support < score
          score = other_support
        if score > balanced_score || (score == balanced_score && balanced_assignment == 1 && assignment != 1)
          balanced_score = score
          balanced_assignment = assignment
        if delta < 0
          rank_drops += 1
          if drop_assignment == 0
            drop_assignment = assignment
        assignment += 1

      # Materialize one local basis splice and one maximally balanced splice,
      # plus the first predicted rank drop if one exists.  Opposite-freedom
      # makes the rank formula exact for every other member of the cube.
      free = 0
      while free < nullity && materialized < 1
        relation = i64[columns]
        column = 0
        while column < columns
          relation[column] = basis_vectors[free * columns + column]
          column += 1
        if fftpns_all_ones(relation) == 0
          child_meta = i64[6]
          child = fftpns_materialize(left, right, left_indices, union_meta[0], right_indices, union_meta[1], relation, 2026081000 + pair_id * 100000 + (1 << free), child_meta)
          if child == nil || child_meta[5] != 1 || child[5] != left[5] + basis_delta[free]
            return 0
          materialized += 1
          output = "/tmp/ternary-parent-local-p" + pair_id.to_s() + "-basis" + free.to_s() + "-r" + child[5].to_s() + ".txt"
          if fft_dump_current(child, output) != child[5]
            return 0
          if fftpnla_continue(child, left, right, continuation_steps, pair_id, 1 << free, continuation_meta) != 1
            return 0
        free += 1
      if balanced_assignment != 0
        relation = i64[columns]
        solved = fftpns_null_vector(reference_basis, reference_have, columns, reference_prime, balanced_assignment, relation)
        selected_left = 0 ## i64
        selected_right = 0 ## i64
        column = 0
        while column < columns
          if relation[column] == 1
            if column < union_meta[0]
              selected_left += 1
            else
              selected_right += 1
          column += 1
        child_meta = i64[6]
        child = fftpns_materialize(left, right, left_indices, union_meta[0], right_indices, union_meta[1], relation, 2026087000 + pair_id, child_meta)
        if child == nil || child_meta[5] != 1 || child[5] != left[5] + selected_right - selected_left
          return 0
        materialized += 1
        output = "/tmp/ternary-parent-local-p" + pair_id.to_s() + "-balanced" + balanced_assignment.to_s() + "-r" + child[5].to_s() + ".txt"
        if fft_dump_current(child, output) != child[5]
          return 0
        if fftpnla_continue(child, left, right, continuation_steps, pair_id, balanced_assignment, continuation_meta) != 1
          return 0
      if drop_assignment != 0
        relation = i64[columns]
        solved = fftpns_null_vector(reference_basis, reference_have, columns, reference_prime, drop_assignment, relation)
        child_meta = i64[6]
        child = fftpns_materialize(left, right, left_indices, union_meta[0], right_indices, union_meta[1], relation, 2026089000 + pair_id, child_meta)
        if child == nil || child_meta[5] != 1 || child[5] >= left[5]
          return 0
        materialized += 1
        output = "/tmp/ternary-parent-local-p" + pair_id.to_s() + "-rankdrop-r" + child[5].to_s() + ".txt"
        if fft_dump_current(child, output) != child[5]
          return 0
        if fftpnla_continue(child, left, right, continuation_steps, pair_id, drop_assignment, continuation_meta) != 1
          return 0
    else
      assignment = 1
      while assignment < limit
        relation = i64[columns]
        solved = fftpns_null_vector(reference_basis, reference_have, columns, reference_prime, assignment, relation)
        if solved != nullity
          return 0
        if fftpns_binary_vector(relation) == 1 && fftpns_all_ones(relation) == 0
          if fftpns_subset_exact(left, right, left_indices, union_meta[0], right_indices, union_meta[1], relation, n) == 1
            proper_exact += 1
            selected_left = 0 ## i64
            selected_right = 0 ## i64
            column = 0
            while column < columns
              if relation[column] == 1
                if column < union_meta[0]
                  selected_left += 1
                else
                  selected_right += 1
              column += 1
            delta = selected_right - selected_left ## i64
            if delta < 0
              rank_drops += 1
            if materialized < 2 || (delta < 0 && rank_drops == 1)
              child_meta = i64[6]
              child = fftpns_materialize(left, right, left_indices, union_meta[0], right_indices, union_meta[1], relation, 2026081000 + pair_id * 100000 + assignment, child_meta)
              if child == nil || child_meta[5] != 1 || child[5] != left[5] + delta
                return 0
              materialized += 1
              output = "/tmp/ternary-parent-local-p" + pair_id.to_s() + "-a" + assignment.to_s() + "-r" + child[5].to_s() + ".txt"
              if fft_dump_current(child, output) != child[5]
                return 0
              if fftpnla_continue(child, left, right, continuation_steps, pair_id, assignment, continuation_meta) != 1
                return 0
        assignment += 1
  if reference_rank < columns - 1 && nullity > max_nullity
    return 0

  meta[0] = columns
  meta[1] = union_meta[2]
  meta[2] = rank1
  meta[3] = rank2
  meta[4] = nullity
  meta[5] = proper_exact
  meta[6] = materialized
  meta[7] = rank_drops
  meta[8] = continuation_meta[0]
  meta[9] = continuation_meta[1]
  meta[10] = continuation_meta[2]
  meta[11] = continuation_meta[3]
  << "TERNARY_PARENT_LOCAL_PAIR id=" + pair_id.to_s() + " n=" + n.to_s() + " columns=" + columns.to_s() + " common=" + union_meta[2].to_s() + " gram_ranks=" + rank1.to_s() + "/" + rank2.to_s() + " nullity_bound=" + nullity.to_s() + " cube_proof=" + cube_proof.to_s() + " proper_exact=" + proper_exact.to_s() + " materialized=" + materialized.to_s() + " rank_drops=" + rank_drops.to_s() + " continuation=" + continuation_meta[0].to_s() + "/" + continuation_meta[1].to_s() + "/" + continuation_meta[2].to_s() + "/" + continuation_meta[3].to_s()
  1

root = "benchmarks/matmul/metaflip/"
profiles = 12 ## i64
max_nullity = 20 ## i64
continuation_steps = 1000000 ## i64

cap5 = fft_default_capacity(5) ## i64
s5_walk = i64[fft_state_size(cap5)]
s5_gl3 = i64[fft_state_size(cap5)]
s5_shear = i64[fft_state_size(cap5)]
s5_shear_gpu = i64[fft_state_size(cap5)]
s5_gpu = i64[fft_state_size(cap5)]
z = fftpnla_load(s5_walk, root + "matmul_5x5_rank93_d1249_ternary_walk.txt", 5, 93, 2026081101) ## i64
z *= fftpnla_load(s5_gl3, root + "matmul_5x5_rank93_d1248_gl3_ternary.txt", 5, 93, 2026081102)
z *= fftpnla_load(s5_shear, root + "matmul_5x5_rank93_d997_index_shear_ternary.txt", 5, 93, 2026081103)
z *= fftpnla_load(s5_shear_gpu, root + "matmul_5x5_rank93_d967_index_shear_gpu_ternary.txt", 5, 93, 2026081104)
z *= fftpnla_load(s5_gpu, root + "matmul_5x5_rank93_d1245_ternary_gpu.txt", 5, 93, 2026081105)

cap6 = fft_default_capacity(6) ## i64
s6_kauers = i64[fft_state_size(cap6)]
s6_walk = i64[fft_state_size(cap6)]
s6_shear = i64[fft_state_size(cap6)]
s6_shear_gpu = i64[fft_state_size(cap6)]
s6_symmetry = i64[fft_state_size(cap6)]
z *= fftpnla_load(s6_kauers, root + "matmul_6x6_rank153_kauers_ternary.txt", 6, 153, 2026081106)
z *= fftpnla_load(s6_walk, root + "matmul_6x6_rank153_d2502_ternary_walk.txt", 6, 153, 2026081107)
z *= fftpnla_load(s6_shear, root + "matmul_6x6_rank153_d1938_index_shear_ternary.txt", 6, 153, 2026081108)
z *= fftpnla_load(s6_shear_gpu, root + "matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt", 6, 153, 2026081109)
z *= fftpnla_load(s6_symmetry, root + "matmul_6x6_rank153_d1931_symmetry_escape_ternary.txt", 6, 153, 2026081110)

cap7 = fft_default_capacity(7) ## i64
s7_base = i64[fft_state_size(cap7)]
s7_door = i64[fft_state_size(cap7)]
z *= fftpnla_load(s7_base, root + "matmul_7x7_rank250_dronperminov_ternary.txt", 7, 250, 2026081111)
z *= fftpnla_load(s7_door, root + "matmul_7x7_rank250_d3069_ternary_door.txt", 7, 250, 2026081112)
if z != 1
  fftpnla_fail("archive load/canonical multiset gate")

total_proper = 0 ## i64
total_materialized = 0 ## i64
total_drops = 0 ## i64
total_continuations = 0 ## i64
total_continuation_rank_wins = 0 ## i64
total_continuation_density_wins = 0 ## i64
total_parent_density_wins = 0 ## i64
pairs = 0 ## i64

pair_meta = i64[12]
z = fftpnla_audit_pair(s5_walk, s5_gpu, 5, 4, 1, profiles, max_nullity, continuation_steps, pair_meta)
if z != 1
  fftpnla_fail("5x5 union4 walk/gpu")
total_proper += pair_meta[5]
total_materialized += pair_meta[6]
total_drops += pair_meta[7]
total_continuations += pair_meta[8]
total_continuation_rank_wins += pair_meta[9]
total_continuation_density_wins += pair_meta[10]
total_parent_density_wins += pair_meta[11]
pairs += 1

pair_meta = i64[12]
z = fftpnla_audit_pair(s5_gl3, s5_gpu, 5, 4, 2, profiles, max_nullity, continuation_steps, pair_meta)
if z != 1
  fftpnla_fail("5x5 union4 gl3/gpu")
total_proper += pair_meta[5]
total_materialized += pair_meta[6]
total_drops += pair_meta[7]
total_continuations += pair_meta[8]
total_continuation_rank_wins += pair_meta[9]
total_continuation_density_wins += pair_meta[10]
total_parent_density_wins += pair_meta[11]
pairs += 1

pair_meta = i64[12]
z = fftpnla_audit_pair(s5_walk, s5_gl3, 5, 6, 3, profiles, max_nullity, continuation_steps, pair_meta)
if z != 1
  fftpnla_fail("5x5 union6")
total_proper += pair_meta[5]
total_materialized += pair_meta[6]
total_drops += pair_meta[7]
total_continuations += pair_meta[8]
total_continuation_rank_wins += pair_meta[9]
total_continuation_density_wins += pair_meta[10]
total_parent_density_wins += pair_meta[11]
pairs += 1

pair_meta = i64[12]
z = fftpnla_audit_pair(s5_shear, s5_shear_gpu, 5, 32, 4, profiles, max_nullity, continuation_steps, pair_meta)
if z != 1
  fftpnla_fail("5x5 union32")
total_proper += pair_meta[5]
total_materialized += pair_meta[6]
total_drops += pair_meta[7]
total_continuations += pair_meta[8]
total_continuation_rank_wins += pair_meta[9]
total_continuation_density_wins += pair_meta[10]
total_parent_density_wins += pair_meta[11]
pairs += 1

pair_meta = i64[12]
z = fftpnla_audit_pair(s6_shear, s6_shear_gpu, 6, 12, 5, profiles, max_nullity, continuation_steps, pair_meta)
if z != 1
  fftpnla_fail("6x6 union12 shear/gpu")
total_proper += pair_meta[5]
total_materialized += pair_meta[6]
total_drops += pair_meta[7]
total_continuations += pair_meta[8]
total_continuation_rank_wins += pair_meta[9]
total_continuation_density_wins += pair_meta[10]
total_parent_density_wins += pair_meta[11]
pairs += 1

pair_meta = i64[12]
z = fftpnla_audit_pair(s6_shear_gpu, s6_symmetry, 6, 12, 6, profiles, max_nullity, continuation_steps, pair_meta)
if z != 1
  fftpnla_fail("6x6 union12 gpu/symmetry")
total_proper += pair_meta[5]
total_materialized += pair_meta[6]
total_drops += pair_meta[7]
total_continuations += pair_meta[8]
total_continuation_rank_wins += pair_meta[9]
total_continuation_density_wins += pair_meta[10]
total_parent_density_wins += pair_meta[11]
pairs += 1

pair_meta = i64[12]
z = fftpnla_audit_pair(s6_shear, s6_symmetry, 6, 16, 7, profiles, max_nullity, continuation_steps, pair_meta)
if z != 1
  fftpnla_fail("6x6 union16")
total_proper += pair_meta[5]
total_materialized += pair_meta[6]
total_drops += pair_meta[7]
total_continuations += pair_meta[8]
total_continuation_rank_wins += pair_meta[9]
total_continuation_density_wins += pair_meta[10]
total_parent_density_wins += pair_meta[11]
pairs += 1

pair_meta = i64[12]
z = fftpnla_audit_pair(s6_kauers, s6_walk, 6, 48, 8, profiles, max_nullity, continuation_steps, pair_meta)
if z != 1
  fftpnla_fail("6x6 union48")
total_proper += pair_meta[5]
total_materialized += pair_meta[6]
total_drops += pair_meta[7]
total_continuations += pair_meta[8]
total_continuation_rank_wins += pair_meta[9]
total_continuation_density_wins += pair_meta[10]
total_parent_density_wins += pair_meta[11]
pairs += 1

pair_meta = i64[12]
z = fftpnla_audit_pair(s7_base, s7_door, 7, 64, 9, profiles, max_nullity, continuation_steps, pair_meta)
if z != 1
  fftpnla_fail("7x7 union64")
total_proper += pair_meta[5]
total_materialized += pair_meta[6]
total_drops += pair_meta[7]
total_continuations += pair_meta[8]
total_continuation_rank_wins += pair_meta[9]
total_continuation_density_wins += pair_meta[10]
total_parent_density_wins += pair_meta[11]
pairs += 1

<< "TERNARY_PARENT_LOCAL_SUMMARY pairs=" + pairs.to_s() + " proper_exact=" + total_proper.to_s() + " materialized=" + total_materialized.to_s() + " rank_drops=" + total_drops.to_s() + " continuation=" + total_continuations.to_s() + "/" + total_continuation_rank_wins.to_s() + "/" + total_continuation_density_wins.to_s() + "/" + total_parent_density_wins.to_s() + " continuation_steps=" + continuation_steps.to_s() + " profiles=" + profiles.to_s() + " primes=1000003/1000033"

# Shared deterministic parent generator for the <2,2,5> block-local GL audit.
# The nonces and move schedules intentionally match
# `flipfleet_225_block_gl_bank.w` byte for byte.

use flipfleet_leaf_conjugation

-> ff225gl_outer()
  outer = FFBCScheme.new(1, 1, 2, 2)
  outer.us()[0] = 1
  outer.vs()[0] = 1
  outer.ws()[0] = 1
  outer.us()[1] = 1
  outer.vs()[1] = 2
  outer.ws()[1] = 2
  outer.set_rank(2)
  if ffbc_verify_exact(outer) != 1
    return nil
  outer

-> ff225gl_parent(leaf3, leaf2, outer, alloc_n, alloc_m, alloc_p, index) (FFBCScheme FFBCScheme FFBCScheme i64[] i64[] i64[] i64)
  if leaf3 == nil || leaf2 == nil || outer == nil || index < 0
    return nil
  moves3 = 2 + (index % 11) ## i64
  moves2 = 2 + ((index / 11) % 11) ## i64
  image3 = fflc_sparse_leaf_image(leaf3, 2250001 + index * 104729, moves3)
  image2 = fflc_sparse_leaf_image(leaf2, 2257001 + index * 130363, moves2)
  if image3 == nil || image2 == nil
    return nil
  leaves = []
  leaves.push(image3)
  leaves.push(image2)
  candidate = ffbc_compose(outer, alloc_n, alloc_m, alloc_p, leaves)
  if candidate == nil || candidate.rank() != 18 || ffbc_verify_exact(candidate) != 1
    return nil
  candidate

-> ff225gl_alloc_n()
  values = i64[1]
  values[0] = 2
  values

-> ff225gl_alloc_m()
  values = i64[1]
  values[0] = 2
  values

-> ff225gl_alloc_p()
  values = i64[2]
  values[0] = 3
  values[1] = 2
  values

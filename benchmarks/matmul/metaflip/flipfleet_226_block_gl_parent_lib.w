# Shared deterministic parent generator for the <2,2,6> three-Strassen
# block-local GL campaign.
#
# Each parent independently conjugates all three exact rank-7 <2,2,2>
# Strassen leaves and embeds them into disjoint output-column blocks.  The
# resulting rank-21 scheme is exact by construction and is independently
# verified before it is returned.

use flipfleet_leaf_conjugation

-> ff226gl_outer()
  outer = FFBCScheme.new(1, 1, 3, 3)
  i = 0 ## i64
  while i < 3
    outer.us()[i] = 1
    outer.vs()[i] = 1 << i
    outer.ws()[i] = 1 << i
    i += 1
  outer.set_rank(3)
  if ffbc_verify_exact(outer) != 1
    return nil
  outer

-> ff226gl_alloc_n()
  values = i64[1]
  values[0] = 2
  values

-> ff226gl_alloc_m()
  values = i64[1]
  values[0] = 2
  values

-> ff226gl_alloc_p()
  values = i64[3]
  values[0] = 2
  values[1] = 2
  values[2] = 2
  values

-> ff226gl_parent(leaf, outer, alloc_n, alloc_m, alloc_p, index) (FFBCScheme FFBCScheme i64[] i64[] i64[] i64)
  if leaf == nil || outer == nil || index < 0
    return nil

  moves0 = 2 + (index % 11) ## i64
  moves1 = 2 + ((index / 11) % 11) ## i64
  moves2 = 2 + ((index / 121) % 11) ## i64
  image0 = fflc_sparse_leaf_image(leaf, 2260003 + index * 104729, moves0)
  image1 = fflc_sparse_leaf_image(leaf, 2269003 + index * 130363, moves1)
  image2 = fflc_sparse_leaf_image(leaf, 2278003 + index * 155921, moves2)
  if image0 == nil || image1 == nil || image2 == nil
    return nil

  leaves = []
  leaves.push(image0)
  leaves.push(image1)
  leaves.push(image2)
  candidate = ffbc_compose(outer, alloc_n, alloc_m, alloc_p, leaves)
  if candidate == nil || candidate.rank() != 21 || ffbc_verify_exact(candidate) != 1
    return nil
  candidate

# Certify that every term in the complete deterministic <2,2,6> block-local
# bank belongs to exactly one of the three disjoint two-column output blocks.
# Together with checked R_GF(2)(<2,2,2>)=7, this proves that no subset of this
# entire term dictionary can represent <2,2,6> with fewer than 21 terms.

use flipfleet_226_block_gl_parent_lib

-> ff226blt_expect(label, condition)
  if !condition
    << "FAIL " + label
    exit(1)
  1

-> ff226blt_factor_mask(block) (i64) i64
  mask = 0 ## i64
  row = 0 ## i64
  while row < 2
    column = block * 2 ## i64
    while column < block * 2 + 2
      mask = mask | (1 << (row * 6 + column))
      column += 1
    row += 1
  mask

-> ff226blt_term_block(v, w) (i64 i64) i64
  found = 0 - 1 ## i64
  block = 0 ## i64
  while block < 3
    mask = ff226blt_factor_mask(block) ## i64
    if v != 0 && w != 0 && (v & mask) == v && (w & mask) == w
      if found >= 0
        return 0 - 2
      found = block
    block += 1
  found

root = "benchmarks/matmul/metaflip/"
leaf = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
outer = ff226gl_outer()
z = ff226blt_expect("seeds", leaf != nil && outer != nil && ffbc_verify_exact(leaf) == 1 && ffbc_verify_exact(outer) == 1) ## i64
counts = i64[3]
parents = 4096 ## i64
index = 0 ## i64
while index < parents
  parent = ff226gl_parent(leaf, outer, ff226gl_alloc_n(), ff226gl_alloc_m(), ff226gl_alloc_p(), index)
  z = ff226blt_expect("parent exact", parent != nil && parent.rank() == 21 && ffbc_verify_exact(parent) == 1)
  slot = 0 ## i64
  while slot < parent.rank()
    block = ff226blt_term_block(parent.vs()[slot], parent.ws()[slot]) ## i64
    z = ff226blt_expect("term has one block", block >= 0 && block < 3)
    counts[block] += 1
    slot += 1
  index += 1

z = ff226blt_expect("seven terms per block per parent", counts[0] == parents * 7 && counts[1] == parents * 7 && counts[2] == parents * 7)
<< "PASS flipfleet 226 block locality parents=" + parents.to_s() + " terms=" + (counts[0] + counts[1] + counts[2]).to_s() + " blocks=" + counts[0].to_s() + "/" + counts[1].to_s() + "/" + counts[2].to_s()

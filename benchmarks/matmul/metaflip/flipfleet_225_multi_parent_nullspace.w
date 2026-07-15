# Complete affine-kernel search over the union of the retained <2,2,5>
# rank-18 doors. Unlike a pairwise crossover, a relation here may draw terms
# from three or more exact parents. Every subset in the affine coset of one
# known decomposition is another exact decomposition of the same tensor.
#
# Usage:
#   flipfleet_225_multi_parent_nullspace [PROVISIONAL_OUTPUT [BLOCK_PARENT]]

use flipfleet_rect_archive_nullspace
use flipfleet_225_block_gl_parent_lib

-> ff225mp_fail(message)
  << "FF225_MULTI_ERROR " + message
  exit(1)
  0

-> ff225mp_find(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if us[i] == u && vs[i] == v && ws[i] == w
      return i
    i += 1
  0 - 1

-> ff225mp_add_scheme(us, vs, ws, count, capacity, scheme) (i64[] i64[] i64[] i64 i64 FFBCScheme) i64
  i = 0 ## i64
  while i < scheme.rank()
    if ff225mp_find(us, vs, ws, count, scheme.us()[i], scheme.vs()[i], scheme.ws()[i]) < 0
      if count >= capacity
        return 0 - 1
      us[count] = scheme.us()[i]
      vs[count] = scheme.vs()[i]
      ws[count] = scheme.ws()[i]
      count += 1
    i += 1
  count

-> ff225mp_weight(mask, count) (i64[] i64) i64
  weight = 0 ## i64
  i = 0 ## i64
  while i < count
    if ffnd_mask_bit(mask, 0, i) != 0
      weight += 1
    i += 1
  weight

-> ff225mp_materialize(us, vs, ws, count, mask, rank) (i64[] i64[] i64[] i64 i64[] i64)
  if rank < 1
    return nil
  child = FFBCScheme.new(2, 2, 5, rank)
  slot = 0 ## i64
  i = 0 ## i64
  while i < count
    if ffnd_mask_bit(mask, 0, i) != 0
      if slot >= rank
        return nil
      child.us()[slot] = us[i]
      child.vs()[slot] = vs[i]
      child.ws()[slot] = ws[i]
      slot += 1
    i += 1
  if slot != rank
    return nil
  child.set_rank(rank)
  child

arguments = argv()
if arguments.size() > 2
  << "usage: flipfleet_225_multi_parent_nullspace OUTPUT BLOCK_PARENT"
  exit(2)
output_path = "/tmp/flipfleet_225_multi_parent_best.txt"
if arguments.size() >= 1
  output_path = arguments[0]

root = "benchmarks/matmul/metaflip/"
paths = []
paths.push(root + "matmul_2x2x5_rank18_d84_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d88_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d84_block_splice_gf2.txt")
paths.push(root + "matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt")
doors = []
i = 0 ## i64
while i < paths.size()
  door = ffbc_load_exact(paths[i], 2, 2, 5, 32)
  if door == nil || door.rank() != 18 || ffbc_verify_exact(door) != 1
    ff225mp_fail("door=" + i.to_s())
  doors.push(door)
  i += 1

if arguments.size() == 2
  parent_index = arguments[1].to_i() ## i64
  if parent_index < 0 || parent_index >= 16384
    ff225mp_fail("parent-index")
  leaf3 = ffbc_load_exact(root + "matmul_2x2x3_rank11_catalog_gf2.txt", 2, 2, 3, 16)
  leaf2 = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
  outer = ff225gl_outer()
  if leaf3 == nil || leaf2 == nil || outer == nil
    ff225mp_fail("parent-seeds")
  generated = ff225gl_parent(leaf3, leaf2, outer, ff225gl_alloc_n(), ff225gl_alloc_m(), ff225gl_alloc_p(), parent_index)
  if generated == nil || generated.rank() != 18 || ffbc_verify_exact(generated) != 1
    ff225mp_fail("parent")
  doors.push(generated)

capacity = 128 ## i64
us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
count = 0 ## i64
i = 0
while i < doors.size()
  count = ff225mp_add_scheme(us, vs, ws, count, capacity, doors[i])
  if count < 1
    ff225mp_fail("union")
  i += 1

combo_words = ffnd_combo_words(count) ## i64
anchor = i64[combo_words]
i = 0
while i < doors[0].rank()
  index = ff225mp_find(us, vs, ws, count, doors[0].us()[i], doors[0].vs()[i], doors[0].ws()[i]) ## i64
  if index < 0
    ff225mp_fail("anchor-term")
  z = ffnd_set_mask_bit(anchor, 0, index) ## i64
  i += 1
if ff225mp_weight(anchor, count) != 18
  ff225mp_fail("anchor-weight")

basis = i64[count * combo_words]
elimination = i64[5]
nullity = ffran_build_nullspace(us, vs, ws, count, 2, 2, 5, basis, elimination) ## i64
if nullity < 1 || elimination[2] + nullity != count
  ff225mp_fail("elimination")
if nullity > 24
  << "FF225_MULTI_SUMMARY union=" + count.to_s() + " column_rank=" + elimination[2].to_s() + " nullity=" + nullity.to_s() + " exhaustive=0 reason=nullity-cap"
  exit(3)

limit = 1 << nullity ## i64
histogram = i64[capacity + 1]
candidate = i64[combo_words]
best = nil
best_rank = 0x7fffffff ## i64
best_density = 0x7fffffff ## i64
best_code = 0 ## i64
gated = 0 ## i64
gate_failures = 0 ## i64
rank17 = 0 ## i64
rank18 = 0 ## i64
code = 0 ## i64
while code < limit
  z = ffnd_copy(anchor, 0, candidate, 0, combo_words) ## i64
  bit = 0 ## i64
  while bit < nullity
    if ((code >> bit) & 1) != 0
      z = ffnd_xor(basis, bit * combo_words, candidate, 0, combo_words)
    bit += 1
  weight = ff225mp_weight(candidate, count) ## i64
  if weight >= 0 && weight < histogram.size()
    histogram[weight] += 1
  if weight <= 18
    child = ff225mp_materialize(us, vs, ws, count, candidate, weight)
    gated += 1
    if child == nil || ffbc_verify_exact(child) != 1
      gate_failures += 1
      ff225mp_fail("gate code=" + code.to_s())
    density = fflc_density(child) ## i64
    if weight == 17
      rank17 += 1
    if weight == 18
      rank18 += 1
    if weight < best_rank || (weight == best_rank && density < best_density)
      best = fflc_clone(child)
      best_rank = weight
      best_density = density
      best_code = code
  code += 1

if best == nil || gate_failures != 0
  ff225mp_fail("best")
if ffbc_write(output_path, best) != best_rank
  ff225mp_fail("write")
replay = ffbc_load_exact(output_path, 2, 2, 5, 32)
if replay == nil || replay.rank() != best_rank || ffbc_verify_exact(replay) != 1 || fflc_term_set_distance(replay, best) != 0
  ff225mp_fail("replay")

histogram_text = ""
i = 0
while i < histogram.size()
  if histogram[i] > 0
    if histogram_text.size() > 0
      histogram_text = histogram_text + ","
    histogram_text = histogram_text + i.to_s() + ":" + histogram[i].to_s()
  i += 1
<< "FF225_MULTI_SUMMARY doors=" + doors.size().to_s() + " union=" + count.to_s() + " column_rank=" + elimination[2].to_s() + " nullity=" + nullity.to_s() + " affine_solutions=" + limit.to_s() + " exhaustive=1 histogram=" + histogram_text + " gated_le18=" + gated.to_s() + " rank17=" + rank17.to_s() + " rank18=" + rank18.to_s() + " gate_failures=" + gate_failures.to_s()
<< "FF225_MULTI_BEST rank=" + best_rank.to_s() + " density=" + best_density.to_s() + " relation_code=" + best_code.to_s() + " distances=" + fflc_term_set_distance(best,doors[0]).to_s() + "/" + fflc_term_set_distance(best,doors[1]).to_s() + "/" + fflc_term_set_distance(best,doors[2]).to_s() + "/" + fflc_term_set_distance(best,doors[3]).to_s() + "/" + fflc_term_set_distance(best,doors[4]).to_s() + " exact=1 output=" + output_path

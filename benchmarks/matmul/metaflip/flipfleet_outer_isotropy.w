# Exact GL(2,2)^3 images and 4/3 placements for weighted Strassen-outer
# composition.  These helpers are intentionally separate from the exhaustive
# benchmark so the record recipe has a small deterministic regression test.

use flipfleet_leaf_conjugation

# The two elementary transvections generate GL(2,2).  Codes 0--5 are a
# duplicate-free list of its six elements: I, A, B, AB, BA, and ABA.
-> ffois_gl2_image(source, axis, code) (FFBCScheme i64 i64)
  if source == nil || axis < 0 || axis > 2 || code < 0 || code > 5
    return nil
  result = fflc_clone(source)
  if code == 0
    return result
  if code == 1
    return fflc_transvection(result, axis, 1, 0)
  if code == 2
    return fflc_transvection(result, axis, 0, 1)
  if code == 3
    result = fflc_transvection(result, axis, 1, 0)
    return fflc_transvection(result, axis, 0, 1)
  if code == 4
    result = fflc_transvection(result, axis, 0, 1)
    return fflc_transvection(result, axis, 1, 0)
  result = fflc_transvection(result, axis, 1, 0)
  result = fflc_transvection(result, axis, 0, 1)
  fflc_transvection(result, axis, 1, 0)

-> ffois_image(source, ci, cj, ck) (FFBCScheme i64 i64 i64)
  result = ffois_gl2_image(source, 0, ci)
  if result == nil
    return nil
  result = ffois_gl2_image(result, 1, cj)
  if result == nil
    return nil
  ffois_gl2_image(result, 2, ck)

-> ffois_alloc(mask, axis) (i64 i64)
  result = i64[2]
  if ((mask >> axis) & 1) == 0
    result[0] = 4
    result[1] = 3
  else
    result[0] = 3
    result[1] = 4
  result

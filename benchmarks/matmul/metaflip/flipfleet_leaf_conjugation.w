# Exact leaf-local general-linear actions for support-aware block composition.
#
# A matrix-multiplication tensor has three contracted index spaces I, J, K.
# If a transvection P sends coordinate `dst ^= src` on one occurrence of an
# index, the paired occurrence must receive P^-T, i.e. `src ^= dst`.  Applied
# to every term this is an exact tensor automorphism:
#
#   I: U rows dst^=src, W rows src^=dst
#   J: U cols dst^=src, V rows src^=dst
#   K: V cols dst^=src, W cols src^=dst
#
# Performing the action on a rectangular leaf before embedding keeps every
# changed bit inside that leaf's declared dimensions.  The ordinary composer
# can consequently reuse the transformed leaf without changing its rank or
# crossing a block boundary.

use flipfleet_block_composer

-> fflc_clone(scheme) (FFBCScheme)
  if scheme == nil
    return nil
  result = FFBCScheme.new(scheme.n(), scheme.m(), scheme.p(), scheme.rank())
  ffbc_copy(scheme.us(), 0, result.us(), 0, scheme.rank() * scheme.uw())
  ffbc_copy(scheme.vs(), 0, result.vs(), 0, scheme.rank() * scheme.vw())
  ffbc_copy(scheme.ws(), 0, result.ws(), 0, scheme.rank() * scheme.ww())
  result.set_rank(scheme.rank())
  result

-> fflc_equal(left, right) (FFBCScheme FFBCScheme) i64
  if left == nil || right == nil
    return 0
  if left.n() != right.n() || left.m() != right.m() || left.p() != right.p() || left.rank() != right.rank()
    return 0
  if ffbc_words_equal(left.us(), 0, right.us(), 0, left.rank() * left.uw()) != 1
    return 0
  if ffbc_words_equal(left.vs(), 0, right.vs(), 0, left.rank() * left.vw()) != 1
    return 0
  ffbc_words_equal(left.ws(), 0, right.ws(), 0, left.rank() * left.ww())

# dimension=0 acts on matrix rows; dimension=1 acts on columns.  src is never
# modified, so the operation is safely in-place even though it is GF(2) XOR.
-> fflc_factor_transvection(data, base, rows, cols, dimension, dst, src) (i64[] i64 i64 i64 i64 i64 i64) i64
  if dimension < 0 || dimension > 1 || dst < 0 || src < 0 || dst == src
    return 0
  if dimension == 0
    if dst >= rows || src >= rows
      return 0
    c = 0 ## i64
    while c < cols
      if ffbc_bit(data, base, src * cols + c) == 1
        ffbc_toggle_bit(data, base, dst * cols + c)
      c += 1
    return 1
  if dst >= cols || src >= cols
    return 0
  r = 0 ## i64
  while r < rows
    if ffbc_bit(data, base, r * cols + src) == 1
      ffbc_toggle_bit(data, base, r * cols + dst)
    r += 1
  1

# Return a separately allocated, exact leaf.  axis is I=0, J=1, or K=2.
# Invalid actions and non-exact inputs are rejected rather than partially
# mutating caller-owned storage.
-> fflc_transvection(leaf, axis, dst, src) (FFBCScheme i64 i64 i64)
  if leaf == nil || ffbc_verify_exact(leaf) != 1 || axis < 0 || axis > 2 || dst < 0 || src < 0 || dst == src
    return nil
  extent = leaf.n() ## i64
  if axis == 1
    extent = leaf.m()
  if axis == 2
    extent = leaf.p()
  if dst >= extent || src >= extent
    return nil

  result = fflc_clone(leaf)
  t = 0 ## i64
  while t < result.rank()
    if axis == 0
      # P on I in U, P^-T on I in W.
      fflc_factor_transvection(result.us(), t * result.uw(), result.n(), result.m(), 0, dst, src)
      fflc_factor_transvection(result.ws(), t * result.ww(), result.n(), result.p(), 0, src, dst)
    elsif axis == 1
      # Q on J in U, Q^-T on J in V.
      fflc_factor_transvection(result.us(), t * result.uw(), result.n(), result.m(), 1, dst, src)
      fflc_factor_transvection(result.vs(), t * result.vw(), result.m(), result.p(), 0, src, dst)
    else
      # R on K in V, R^-T on K in W.
      fflc_factor_transvection(result.vs(), t * result.vw(), result.m(), result.p(), 1, dst, src)
      fflc_factor_transvection(result.ws(), t * result.ww(), result.n(), result.p(), 1, src, dst)
    t += 1

  # This simultaneously checks exactness and that no high/boundary bit leaked.
  if ffbc_verify_exact(result) != 1
    return nil
  result

# A deterministic, shape-dependent ensemble member.  Multiple sparse basis
# actions make it substantially different from a mere coordinate permutation,
# while applying it twice in reverse order still has a cheap exact inverse.
-> fflc_default_leaf_image(leaf) (FFBCScheme)
  if leaf == nil || leaf.n() < 2 || leaf.m() < 2 || leaf.p() < 2
    return nil
  a = fflc_transvection(leaf, 0, 1, 0)
  if a == nil
    return nil
  b = fflc_transvection(a, 1, 0, 1)
  if b == nil
    return nil
  c = fflc_transvection(b, 2, leaf.p() - 1, 0)
  if c == nil
    return nil
  # Rectangular leaves with a longer middle space get a second, independent
  # middle-axis shear.  This changes the embedded support layout by shape.
  if leaf.m() > 3
    d = fflc_transvection(c, 1, leaf.m() - 1, 0)
    if d == nil
      return nil
    return d
  c

# Deterministic sparse member of the leaf-isotropy orbit.  The seed chooses a
# short word in elementary transvections; every step uses `fflc_transvection`,
# so malformed programs fail closed and every returned image is independently
# exact.  This is deliberately a seed generator rather than an inner-loop
# move: composing a handful of such leaves is cheap, while repeatedly proving
# leaf exactness inside a walker would only rediscover a rank-zero orbit.
-> fflc_sparse_leaf_image(leaf, seed, moves) (FFBCScheme i64 i64)
  if leaf == nil || moves < 1 || moves > 32
    return nil
  result = fflc_clone(leaf)
  state = (seed ^ (leaf.n() * 73856093) ^ (leaf.m() * 19349663) ^ (leaf.p() * 83492791)) & 2147483647 ## i64
  step = 0 ## i64
  while step < moves
    state = (state * 1103515245 + 12345) & 2147483647
    axis = state % 3 ## i64
    extent = leaf.n() ## i64
    if axis == 1
      extent = leaf.m()
    if axis == 2
      extent = leaf.p()
    if extent < 2
      return nil
    state = (state * 1103515245 + 12345) & 2147483647
    src = state % extent ## i64
    state = (state * 1103515245 + 12345) & 2147483647
    dst = state % (extent - 1) ## i64
    if dst >= src
      dst += 1
    updated = fflc_transvection(result, axis, dst, src)
    if updated == nil
      return nil
    result = updated
    step += 1

  # Sparse words can occasionally cancel to the identity.  Keep ensemble
  # slots useful by adding one deterministic nontrivial generator in that
  # case.  Exactness remains guarded by `fflc_transvection`.
  if fflc_equal(result, leaf) == 1
    axis = seed % 3 ## i64
    if axis < 0
      axis = 0 - axis
    result = fflc_transvection(result, axis, 1, 0)
  result

-> fflc_popcount(value) (i64) i64
  count = 0 ## i64
  x = value ## i64
  while x != 0
    x = x & (x - 1)
    count += 1
  count

-> fflc_density(scheme) (FFBCScheme) i64
  if scheme == nil
    return 0
  total = 0 ## i64
  i = 0 ## i64
  while i < scheme.rank() * scheme.uw()
    total += fflc_popcount(scheme.us()[i])
    i += 1
  i = 0
  while i < scheme.rank() * scheme.vw()
    total += fflc_popcount(scheme.vs()[i])
    i += 1
  i = 0
  while i < scheme.rank() * scheme.ww()
    total += fflc_popcount(scheme.ws()[i])
    i += 1
  total

# Ordinary-flip connectivity proxy used by FlipFleet: count equal factor
# pairs on each of the three axes.  Leaf-local actions can alter equality
# across separately embedded occurrences even though each leaf remains exact.
-> fflc_equal_factor_pairs(scheme) (FFBCScheme) i64
  if scheme == nil
    return 0
  pairs = 0 ## i64
  left = 0 ## i64
  while left < scheme.rank()
    right = left + 1 ## i64
    while right < scheme.rank()
      if ffbc_words_equal(scheme.us(), left * scheme.uw(), scheme.us(), right * scheme.uw(), scheme.uw()) == 1
        pairs += 1
      if ffbc_words_equal(scheme.vs(), left * scheme.vw(), scheme.vs(), right * scheme.vw(), scheme.vw()) == 1
        pairs += 1
      if ffbc_words_equal(scheme.ws(), left * scheme.ww(), scheme.ws(), right * scheme.ww(), scheme.ww()) == 1
        pairs += 1
      right += 1
    left += 1
  pairs

# Number of terms whose complete factor triple changed at the same slot.
-> fflc_slot_distance(left, right) (FFBCScheme FFBCScheme) i64
  if left == nil || right == nil || left.rank() != right.rank() || left.n() != right.n() || left.m() != right.m() || left.p() != right.p()
    return 0 - 1
  changed = 0 ## i64
  i = 0 ## i64
  while i < left.rank()
    same = ffbc_words_equal(left.us(), i * left.uw(), right.us(), i * right.uw(), left.uw()) ## i64
    same = same & ffbc_words_equal(left.vs(), i * left.vw(), right.vs(), i * right.vw(), left.vw())
    same = same & ffbc_words_equal(left.ws(), i * left.ww(), right.ws(), i * right.ww(), left.ww())
    if same == 0
      changed += 1
    i += 1
  changed

-> fflc_term_same_at(left, left_term, right, right_term) (FFBCScheme i64 FFBCScheme i64) i64
  same = 0 ## i64
  if left != nil && right != nil && left.n() == right.n() && left.m() == right.m() && left.p() == right.p()
    if left_term >= 0 && left_term < left.rank() && right_term >= 0 && right_term < right.rank()
      same = ffbc_words_equal(left.us(), left_term * left.uw(), right.us(), right_term * right.uw(), left.uw()) ## i64
      same = same & ffbc_words_equal(left.vs(), left_term * left.vw(), right.vs(), right_term * right.vw(), left.vw())
      same = same & ffbc_words_equal(left.ws(), left_term * left.ww(), right.ws(), right_term * right.ww(), left.ww())
  same

# Permutation-invariant symmetric term-set distance.  Slot distance is useful
# for replay diagnostics, but this metric does not mistake a term reordering
# for a new basin representative.
-> fflc_term_set_distance(left, right) (FFBCScheme FFBCScheme) i64
  if left == nil || right == nil || left.n() != right.n() || left.m() != right.m() || left.p() != right.p()
    return 0 - 1
  used = i64[right.rank()]
  matches = 0 ## i64
  i = 0 ## i64
  while i < left.rank()
    j = 0 ## i64
    found = 0 ## i64
    while j < right.rank() && found == 0
      if used[j] == 0 && fflc_term_same_at(left, i, right, j) == 1
        used[j] = 1
        matches += 1
        found = 1
      j += 1
    i += 1
  left.rank() + right.rank() - 2 * matches

# Descriptor used by the bounded ensemble benchmark:
#   [0] density (minimize), [1] equal-factor pairs (maximize),
#   [2] term-set distance from the reference (maximize).
-> fflc_descriptor(reference, candidate, out) (FFBCScheme FFBCScheme i64[]) i64
  if reference == nil || candidate == nil || out.size() < 3
    return 0
  if reference.n() != candidate.n() || reference.m() != candidate.m() || reference.p() != candidate.p()
    return 0
  out[0] = fflc_density(candidate)
  out[1] = fflc_equal_factor_pairs(candidate)
  out[2] = fflc_term_set_distance(reference, candidate)
  1

-> fflc_pareto_dominates(ld, lp, ln, rd, rp, rn) (i64 i64 i64 i64 i64 i64) i64
  dominates = 0 ## i64
  if ld <= rd && lp >= rp && ln >= rn
    if ld < rd || lp > rp || ln > rn
      dominates = 1
  dominates

# Mark the nondominated candidates in `keep`; ties remain as distinct orbit
# representatives because callers may attach different replay programs.
-> fflc_pareto_mark(densities, pairs, novelties, count, keep) (i64[] i64[] i64[] i64 i64[]) i64
  if count < 0 || densities.size() < count || pairs.size() < count || novelties.size() < count || keep.size() < count
    return 0
  front = 0 ## i64
  i = 0 ## i64
  while i < count
    dominated = 0 ## i64
    j = 0 ## i64
    while j < count && dominated == 0
      if i != j
        dominated = fflc_pareto_dominates(densities[j], pairs[j], novelties[j], densities[i], pairs[i], novelties[i])
      j += 1
    keep[i] = 0
    if dominated == 0
      keep[i] = 1
      front += 1
    i += 1
  front

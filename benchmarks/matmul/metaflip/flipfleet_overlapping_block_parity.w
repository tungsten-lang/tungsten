# Exact algebra and bounded substitution for overlapping rectangular blocks.
#
# B(I,J,K) denotes the restriction of the matrix-multiplication tensor to
# i in I, j in J, k in K.  Its canonical support is exactly I x J x K, so an
# XOR-zero identity between index-mask boxes lifts to an XOR-zero identity
# between the corresponding multiplication tensors.  Each block may then be
# replaced by any exact rectangular algorithm before the two sides are spliced
# into a live decomposition.

use flipfleet_block_composer

+ FFOBPIdentity
  -> new(n, m, p, capacity)
    @meta = i64[5]
    @meta[0] = n
    @meta[1] = m
    @meta[2] = p
    @meta[3] = capacity
    @meta[4] = 0
    @imasks = i64[capacity]
    @jmasks = i64[capacity]
    @kmasks = i64[capacity]

  -> n()
    @meta[0]
  -> m()
    @meta[1]
  -> p()
    @meta[2]
  -> capacity()
    @meta[3]
  -> count()
    @meta[4]
  -> imask(index)
    @imasks[index]
  -> jmask(index)
    @jmasks[index]
  -> kmask(index)
    @kmasks[index]
  -> add(imask, jmask, kmask)
    if @meta[4] >= @meta[3]
      return 0
    @imasks[@meta[4]] = imask
    @jmasks[@meta[4]] = jmask
    @kmasks[@meta[4]] = kmask
    @meta[4] = @meta[4] + 1
    1

-> ffobp_mask_valid(mask, extent) (i64 i64) i64
  if mask <= 0 || extent < 1 || extent >= 63
    return 0
  if (mask >> extent) != 0
    return 0
  1

-> ffobp_popcount(mask) (i64) i64
  count = 0 ## i64
  value = mask ## i64
  while value != 0
    value = value & (value - 1)
    count += 1
  count

-> ffobp_identity_valid(identity) (FFOBPIdentity) i64
  if identity == nil || identity.count() < 1
    return 0
  block = 0 ## i64
  while block < identity.count()
    if ffobp_mask_valid(identity.imask(block), identity.n()) != 1
      return 0
    if ffobp_mask_valid(identity.jmask(block), identity.m()) != 1
      return 0
    if ffobp_mask_valid(identity.kmask(block), identity.p()) != 1
      return 0
    block += 1
  1

# Exact index-mask verifier.  Each cell is one canonical scalar-multiplication
# tensor entry, so this is a complete check, not a random fingerprint.
-> ffobp_subset_zero(identity, subset) (FFOBPIdentity i64) i64
  if ffobp_identity_valid(identity) != 1 || subset <= 0 || (subset >> identity.count()) != 0
    return 0
  i = 0 ## i64
  while i < identity.n()
    j = 0 ## i64
    while j < identity.m()
      k = 0 ## i64
      while k < identity.p()
        parity = 0 ## i64
        block = 0 ## i64
        while block < identity.count()
          if ((subset >> block) & 1) == 1
            if ((identity.imask(block) >> i) & 1) == 1 && ((identity.jmask(block) >> j) & 1) == 1 && ((identity.kmask(block) >> k) & 1) == 1
              parity = parity ^ 1
          block += 1
        if parity != 0
          return 0
        k += 1
      j += 1
    i += 1
  1

-> ffobp_identity_zero(identity) (FFOBPIdentity) i64
  if identity == nil || identity.count() >= 63
    return 0
  ffobp_subset_zero(identity, (1 << identity.count()) - 1)

# A primitive four-block cycle in either of the two axes not held fixed.
# In the fixed-I orientation its masks are
#
#   (I,J0,K0) + (I,J0,K1)
# + (I,J1,K0+K1) + (I,J0+J1,K0+K1) = 0.
#
# The other orientations are coordinate rotations of the same identity.
-> ffobp_four_cycle(n, m, p, fixed_axis, fixed_mask, a0, a1, b0, b1) (i64 i64 i64 i64 i64 i64 i64 i64 i64)
  identity = FFOBPIdentity.new(n, m, p, 4)
  if fixed_axis == 0
    identity.add(fixed_mask, a0, b0)
    identity.add(fixed_mask, a0, b1)
    identity.add(fixed_mask, a1, b0 ^ b1)
    identity.add(fixed_mask, a0 ^ a1, b0 ^ b1)
  elsif fixed_axis == 1
    identity.add(a0, fixed_mask, b0)
    identity.add(a0, fixed_mask, b1)
    identity.add(a1, fixed_mask, b0 ^ b1)
    identity.add(a0 ^ a1, fixed_mask, b0 ^ b1)
  elsif fixed_axis == 2
    identity.add(a0, b0, fixed_mask)
    identity.add(a0, b1, fixed_mask)
    identity.add(a1, b0 ^ b1, fixed_mask)
    identity.add(a0 ^ a1, b0 ^ b1, fixed_mask)
  else
    return nil
  if ffobp_identity_zero(identity) != 1
    return nil
  identity

# Enumerate coordinate-lifted primitive cycles in deterministic order.  The
# caller-supplied limit makes this suitable for a rotating pool lane; for 3^3
# there are 81 such circuits before the limit is applied.
-> ffobp_enumerate_bounded(n, m, p, limit, identities) (i64 i64 i64 i64 Array) i64
  if n < 2 || m < 2 || p < 2 || limit < 1
    return 0
  axis = 0 ## i64
  while axis < 3 && identities.size() < limit
    fixed_extent = n ## i64
    a_extent = m ## i64
    b_extent = p ## i64
    if axis == 1
      fixed_extent = m
      a_extent = n
      b_extent = p
    if axis == 2
      fixed_extent = p
      a_extent = n
      b_extent = m
    fixed = 0 ## i64
    while fixed < fixed_extent && identities.size() < limit
      ai = 0 ## i64
      while ai < a_extent && identities.size() < limit
        aj = ai + 1 ## i64
        while aj < a_extent && identities.size() < limit
          bi = 0 ## i64
          while bi < b_extent && identities.size() < limit
            bj = bi + 1 ## i64
            while bj < b_extent && identities.size() < limit
              identity = ffobp_four_cycle(n, m, p, axis, 1 << fixed, 1 << ai, 1 << aj, 1 << bi, 1 << bj)
              if identity != nil
                identities.push(identity)
              bj += 1
            bi += 1
          aj += 1
        ai += 1
      fixed += 1
    axis += 1
  identities.size()

# Native-friendly indexed form of the same catalogue.  Keeping custom identity
# objects out of a generic Array avoids boxing in hot/GPU-host builds.
-> ffobp_bounded_count(n, m, p, limit) (i64 i64 i64 i64) i64
  if n < 2 || m < 2 || p < 2 || limit < 1
    return 0
  count = n * (m * (m - 1) / 2) * (p * (p - 1) / 2) ## i64
  count += m * (n * (n - 1) / 2) * (p * (p - 1) / 2)
  count += p * (n * (n - 1) / 2) * (m * (m - 1) / 2)
  if count > limit
    count = limit
  count

-> ffobp_bounded_at(n, m, p, wanted) (i64 i64 i64 i64)
  if n < 2 || m < 2 || p < 2 || wanted < 0
    return nil
  seen = 0 ## i64
  axis = 0 ## i64
  while axis < 3
    fixed_extent = n ## i64
    a_extent = m ## i64
    b_extent = p ## i64
    if axis == 1
      fixed_extent = m
      a_extent = n
      b_extent = p
    if axis == 2
      fixed_extent = p
      a_extent = n
      b_extent = m
    fixed = 0 ## i64
    while fixed < fixed_extent
      ai = 0 ## i64
      while ai < a_extent
        aj = ai + 1 ## i64
        while aj < a_extent
          bi = 0 ## i64
          while bi < b_extent
            bj = bi + 1 ## i64
            while bj < b_extent
              if seen == wanted
                return ffobp_four_cycle(n, m, p, axis, 1 << fixed, 1 << ai, 1 << aj, 1 << bi, 1 << bj)
              seen += 1
              bj += 1
            bi += 1
          aj += 1
        ai += 1
      fixed += 1
    axis += 1
  nil

-> ffobp_copy_term(source, source_term, target, target_term) (FFBCScheme i64 FFBCScheme i64) i64
  ffbc_copy(source.us(), source_term * source.uw(), target.us(), target_term * target.uw(), target.uw())
  ffbc_copy(source.vs(), source_term * source.vw(), target.vs(), target_term * target.vw(), target.vw())
  ffbc_copy(source.ws(), source_term * source.ww(), target.ws(), target_term * target.ww(), target.ww())
  1

-> ffobp_terms_equal(left, left_term, right, right_term) (FFBCScheme i64 FFBCScheme i64) i64
  if left.n() != right.n() || left.m() != right.m() || left.p() != right.p()
    return 0
  if ffbc_words_equal(left.us(), left_term * left.uw(), right.us(), right_term * right.uw(), left.uw()) != 1
    return 0
  if ffbc_words_equal(left.vs(), left_term * left.vw(), right.vs(), right_term * right.vw(), left.vw()) != 1
    return 0
  ffbc_words_equal(left.ws(), left_term * left.ww(), right.ws(), right_term * right.ww(), left.ww())

-> ffobp_set_scalar_term(scheme, term, i, j, k) (FFBCScheme i64 i64 i64 i64) i64
  ffbc_clear(scheme.us(), term * scheme.uw(), scheme.uw())
  ffbc_clear(scheme.vs(), term * scheme.vw(), scheme.vw())
  ffbc_clear(scheme.ws(), term * scheme.ww(), scheme.ww())
  ffbc_toggle_bit(scheme.us(), term * scheme.uw(), i * scheme.m() + j)
  ffbc_toggle_bit(scheme.vs(), term * scheme.vw(), j * scheme.p() + k)
  ffbc_toggle_bit(scheme.ws(), term * scheme.ww(), i * scheme.p() + k)
  1

-> ffobp_raw_side_rank(identity, block_mask) (FFOBPIdentity i64) i64
  total = 0 ## i64
  block = 0 ## i64
  while block < identity.count()
    if ((block_mask >> block) & 1) == 1
      total += ffobp_popcount(identity.imask(block)) * ffobp_popcount(identity.jmask(block)) * ffobp_popcount(identity.kmask(block))
    block += 1
  total

# Materialise selected B(I,J,K) blocks using their schoolbook rectangular
# decompositions.  This is deliberately a reference backend: a production
# macro lane can substitute a lower-rank exact rectangular leaf at this point.
-> ffobp_materialize_naive(identity, block_mask) (FFOBPIdentity i64)
  if ffobp_identity_valid(identity) != 1 || block_mask <= 0 || (block_mask >> identity.count()) != 0
    return nil
  capacity = ffobp_raw_side_rank(identity, block_mask) ## i64
  result = FFBCScheme.new(identity.n(), identity.m(), identity.p(), capacity)
  rank = 0 ## i64
  block = 0 ## i64
  while block < identity.count()
    if ((block_mask >> block) & 1) == 1
      i = 0 ## i64
      while i < identity.n()
        if ((identity.imask(block) >> i) & 1) == 1
          j = 0 ## i64
          while j < identity.m()
            if ((identity.jmask(block) >> j) & 1) == 1
              k = 0 ## i64
              while k < identity.p()
                if ((identity.kmask(block) >> k) & 1) == 1
                  ffobp_set_scalar_term(result, rank, i, j, k)
                  rank += 1
                k += 1
            j += 1
        i += 1
    block += 1
  result.set_rank(rank)
  result

-> ffobp_concat(left, right) (FFBCScheme FFBCScheme)
  if left == nil || right == nil || left.n() != right.n() || left.m() != right.m() || left.p() != right.p()
    return nil
  result = FFBCScheme.new(left.n(), left.m(), left.p(), left.rank() + right.rank())
  i = 0 ## i64
  while i < left.rank()
    ffobp_copy_term(left, i, result, i)
    i += 1
  j = 0 ## i64
  while j < right.rank()
    ffobp_copy_term(right, j, result, left.rank() + j)
    j += 1
  result.set_rank(left.rank() + right.rank())
  result

# Complete zero-tensor reconstruction for a CP scheme.  Unlike
# ffbc_verify_exact this expects every A/B slice to vanish.
-> ffobp_verify_scheme_zero(scheme) (FFBCScheme) i64
  if scheme == nil || scheme.rank() < 1
    return 0
  ab = scheme.n() * scheme.m() ## i64
  bc = scheme.m() * scheme.p() ## i64
  ac = scheme.n() * scheme.p() ## i64
  term = 0 ## i64
  while term < scheme.rank()
    if ffbc_factor_valid(scheme.us(), term * scheme.uw(), scheme.uw(), ab) != 1 || ffbc_factor_valid(scheme.vs(), term * scheme.vw(), scheme.vw(), bc) != 1 || ffbc_factor_valid(scheme.ws(), term * scheme.ww(), scheme.ww(), ac) != 1
      return 0
    term += 1
  slices = i64[ab * bc * scheme.ww()]
  term = 0
  while term < scheme.rank()
    ai = 0 ## i64
    while ai < ab
      if ffbc_bit(scheme.us(), term * scheme.uw(), ai) == 1
        bi = 0 ## i64
        while bi < bc
          if ffbc_bit(scheme.vs(), term * scheme.vw(), bi) == 1
            ffbc_xor_into(slices, (ai * bc + bi) * scheme.ww(), scheme.ws(), term * scheme.ww(), scheme.ww())
          bi += 1
      ai += 1
    term += 1
  i = 0
  while i < slices.size()
    if slices[i] != 0
      return 0
    i += 1
  1

-> ffobp_same_tensor(left, right) (FFBCScheme FFBCScheme) i64
  combined = ffobp_concat(left, right)
  if combined == nil
    return 0
  ffobp_verify_scheme_zero(combined)

-> ffobp_nth_set(mask, wanted) (i64 i64) i64
  seen = 0 ## i64
  bit = 0 ## i64
  while bit < 63
    if ((mask >> bit) & 1) == 1
      if seen == wanted
        return bit
      seen += 1
    bit += 1
  0 - 1

-> ffobp_naive_block(n, m, p, imask, jmask, kmask) (i64 i64 i64 i64 i64 i64)
  if ffobp_mask_valid(imask, n) != 1 || ffobp_mask_valid(jmask, m) != 1 || ffobp_mask_valid(kmask, p) != 1
    return nil
  rank = ffobp_popcount(imask) * ffobp_popcount(jmask) * ffobp_popcount(kmask) ## i64
  result = FFBCScheme.new(n, m, p, rank)
  term = 0 ## i64
  i = 0 ## i64
  while i < n
    if ((imask >> i) & 1) == 1
      j = 0 ## i64
      while j < m
        if ((jmask >> j) & 1) == 1
          k = 0 ## i64
          while k < p
            if ((kmask >> k) & 1) == 1
              ffobp_set_scalar_term(result, term, i, j, k)
              term += 1
            k += 1
        j += 1
    i += 1
  result.set_rank(term)
  result

# Embed an arbitrary exact rectangular leaf into non-contiguous target masks.
# The complete comparison against the corresponding schoolbook block is the
# boundary/exactness gate.  This is the hook through which catalog leaves (not
# just the reference naive backend) enter a block-parity macro.
-> ffobp_embed_leaf(leaf, target_n, target_m, target_p, imask, jmask, kmask) (FFBCScheme i64 i64 i64 i64 i64 i64)
  if leaf == nil || ffbc_verify_exact(leaf) != 1
    return nil
  if ffobp_mask_valid(imask, target_n) != 1 || ffobp_mask_valid(jmask, target_m) != 1 || ffobp_mask_valid(kmask, target_p) != 1
    return nil
  if ffobp_popcount(imask) != leaf.n() || ffobp_popcount(jmask) != leaf.m() || ffobp_popcount(kmask) != leaf.p()
    return nil
  result = FFBCScheme.new(target_n, target_m, target_p, leaf.rank())
  term = 0 ## i64
  while term < leaf.rank()
    ffbc_clear(result.us(), term * result.uw(), result.uw())
    ffbc_clear(result.vs(), term * result.vw(), result.vw())
    ffbc_clear(result.ws(), term * result.ww(), result.ww())
    bit = 0 ## i64
    while bit < leaf.n() * leaf.m()
      if ffbc_bit(leaf.us(), term * leaf.uw(), bit) == 1
        local_i = bit / leaf.m() ## i64
        local_j = bit % leaf.m() ## i64
        global_i = ffobp_nth_set(imask, local_i) ## i64
        global_j = ffobp_nth_set(jmask, local_j) ## i64
        ffbc_toggle_bit(result.us(), term * result.uw(), global_i * target_m + global_j)
      bit += 1
    bit = 0
    while bit < leaf.m() * leaf.p()
      if ffbc_bit(leaf.vs(), term * leaf.vw(), bit) == 1
        local_j = bit / leaf.p() ## i64
        local_k = bit % leaf.p() ## i64
        global_j = ffobp_nth_set(jmask, local_j) ## i64
        global_k = ffobp_nth_set(kmask, local_k) ## i64
        ffbc_toggle_bit(result.vs(), term * result.vw(), global_j * target_p + global_k)
      bit += 1
    bit = 0
    while bit < leaf.n() * leaf.p()
      if ffbc_bit(leaf.ws(), term * leaf.ww(), bit) == 1
        local_i = bit / leaf.p() ## i64
        local_k = bit % leaf.p() ## i64
        global_i = ffobp_nth_set(imask, local_i) ## i64
        global_k = ffobp_nth_set(kmask, local_k) ## i64
        ffbc_toggle_bit(result.ws(), term * result.ww(), global_i * target_p + global_k)
      bit += 1
    term += 1
  result.set_rank(leaf.rank())
  reference = ffobp_naive_block(target_n, target_m, target_p, imask, jmask, kmask)
  if reference == nil || ffobp_same_tensor(result, reference) != 1
    return nil
  result

# Cancel duplicate rank-one terms in GF(2), preserving the exact represented
# tensor.  This separates a macro's nominal rectangular-rank sum from the rank
# remaining after cross-block parity cancellation.
-> ffobp_parity_compact(scheme) (FFBCScheme)
  if scheme == nil
    return nil
  result = FFBCScheme.new(scheme.n(), scheme.m(), scheme.p(), scheme.rank())
  rank = 0 ## i64
  term = 0 ## i64
  while term < scheme.rank()
    found = 0 - 1 ## i64
    i = 0 ## i64
    while i < rank
      if ffobp_terms_equal(scheme, term, result, i) == 1
        found = i
        i = rank
      else
        i += 1
    if found < 0
      ffobp_copy_term(scheme, term, result, rank)
      rank += 1
    else
      rank -= 1
      if found < rank
        ffobp_copy_term(result, rank, result, found)
    term += 1
  result.set_rank(rank)
  result

-> ffobp_parity_rank(scheme) (FFBCScheme) i64
  compact = ffobp_parity_compact(scheme)
  if compact == nil
    return 0 - 1
  compact.rank()

# Find the most unbalanced side/complement split of a zero identity under raw
# block volume.  For the primitive coordinate four-cycle this chooses the two
# overlapping blocks of volumes 2+4 over the two singleton blocks of 1+1.
-> ffobp_best_partition(identity, result) (FFOBPIdentity i64[]) i64
  if ffobp_identity_zero(identity) != 1 || result.size() < 3
    return 0
  full = (1 << identity.count()) - 1 ## i64
  best_gain = 0 ## i64
  best_mask = 0 ## i64
  best_source = 0 ## i64
  best_target = 0 ## i64
  mask = 1 ## i64
  while mask < full
    complement = full ^ mask ## i64
    source = ffobp_raw_side_rank(identity, mask) ## i64
    target = ffobp_raw_side_rank(identity, complement) ## i64
    if source - target > best_gain
      best_gain = source - target
      best_mask = mask
      best_source = source
      best_target = target
    mask += 1
  result[0] = best_mask
  result[1] = best_source
  result[2] = best_target
  best_gain

-> ffobp_contains_multiset(scheme, subset) (FFBCScheme FFBCScheme) i64
  if scheme == nil || subset == nil || scheme.n() != subset.n() || scheme.m() != subset.m() || scheme.p() != subset.p() || subset.rank() > scheme.rank()
    return 0
  used = i64[scheme.rank()]
  wanted = 0 ## i64
  while wanted < subset.rank()
    found = 0 - 1 ## i64
    have = 0 ## i64
    while have < scheme.rank()
      if used[have] == 0 && ffobp_terms_equal(scheme, have, subset, wanted) == 1
        found = have
        have = scheme.rank()
      else
        have += 1
    if found < 0
      return 0
    used[found] = 1
    wanted += 1
  1

# Splice tensor-equivalent term multisets into an exact full MMT scheme and
# optionally parity-compact the result.  Full reconstruction is the admission
# gate, so a malformed macro or boundary embedding cannot escape this helper.
-> ffobp_replace(scheme, remove, add, compact_result) (FFBCScheme FFBCScheme FFBCScheme i64)
  if scheme == nil || remove == nil || add == nil || ffbc_verify_exact(scheme) != 1 || ffobp_same_tensor(remove, add) != 1
    return nil
  if ffobp_contains_multiset(scheme, remove) != 1
    return nil
  used = i64[scheme.rank()]
  wanted = 0 ## i64
  while wanted < remove.rank()
    have = 0 ## i64
    while have < scheme.rank()
      if used[have] == 0 && ffobp_terms_equal(scheme, have, remove, wanted) == 1
        used[have] = 1
        have = scheme.rank()
      else
        have += 1
    wanted += 1
  raw_rank = scheme.rank() - remove.rank() + add.rank() ## i64
  raw = FFBCScheme.new(scheme.n(), scheme.m(), scheme.p(), raw_rank)
  rank = 0 ## i64
  term = 0 ## i64
  while term < scheme.rank()
    if used[term] == 0
      ffobp_copy_term(scheme, term, raw, rank)
      rank += 1
    term += 1
  term = 0
  while term < add.rank()
    ffobp_copy_term(add, term, raw, rank)
    rank += 1
    term += 1
  raw.set_rank(rank)
  result = raw
  if compact_result != 0
    result = ffobp_parity_compact(raw)
  if result == nil || result.rank() < 1 || ffbc_verify_exact(result) != 1
    return nil
  result

-> ffobp_append_zero(scheme, zero_scheme) (FFBCScheme FFBCScheme)
  if scheme == nil || zero_scheme == nil || ffbc_verify_exact(scheme) != 1 || ffobp_verify_scheme_zero(zero_scheme) != 1
    return nil
  result = ffobp_concat(scheme, zero_scheme)
  if result == nil || ffbc_verify_exact(result) != 1
    return nil
  result

# Reference schoolbook target used by the planted regression.
-> ffobp_naive(n, m, p) (i64 i64 i64)
  result = FFBCScheme.new(n, m, p, n * m * p)
  rank = 0 ## i64
  i = 0 ## i64
  while i < n
    j = 0 ## i64
    while j < m
      k = 0 ## i64
      while k < p
        ffobp_set_scalar_term(result, rank, i, j, k)
        rank += 1
        k += 1
      j += 1
    i += 1
  result.set_rank(rank)
  result

# Bounded CPU reference search.  A Metal lane can parallelize the same cheap
# mask enumeration and multiset probes, while the host retains this exact
# materialization/reconstruction gate.
-> ffobp_find_bounded_reduction(scheme, limit) (FFBCScheme i64)
  if scheme == nil || ffbc_verify_exact(scheme) != 1 || limit < 1
    return nil
  count = ffobp_bounded_count(scheme.n(), scheme.m(), scheme.p(), limit) ## i64
  i = 0 ## i64
  while i < count
    identity = ffobp_bounded_at(scheme.n(), scheme.m(), scheme.p(), i)
    partition = i64[3]
    if identity != nil && ffobp_best_partition(identity, partition) > 0
      source = ffobp_materialize_naive(identity, partition[0])
      target = ffobp_materialize_naive(identity, ((1 << identity.count()) - 1) ^ partition[0])
      if source != nil && target != nil && ffobp_contains_multiset(scheme, source) == 1
        candidate = ffobp_replace(scheme, source, target, 1)
        if candidate != nil && candidate.rank() < scheme.rank()
          return candidate
    i += 1
  nil

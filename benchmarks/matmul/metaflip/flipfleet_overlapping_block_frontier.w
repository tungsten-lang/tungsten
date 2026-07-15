# Bounded real-frontier search for overlapping block-parity identities.
#
# A four-cycle is a zero identity between four restricted matrix-
# multiplication tensors.  This file substitutes the cheapest exact 2--8
# rectangular leaf available for each restriction, parity-compacts the four
# term lists, and scores the resulting zero macro against a live exact scheme.
# Endpoint allocation and the full tensor gate are deliberately deferred until
# the exact term-set rank estimate is rank-neutral or better.

use flipfleet_overlapping_block_parity
use flipfleet_block_leaf_pool

+ FFOBPBlockCache
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
    @schemes = []

  -> count()
    @meta[4]
  -> n()
    @meta[0]
  -> m()
    @meta[1]
  -> p()
    @meta[2]
  -> find(imask, jmask, kmask)
    i = 0 ## i64
    while i < @meta[4]
      if @imasks[i] == imask && @jmasks[i] == jmask && @kmasks[i] == kmask
        return i
      i += 1
    0 - 1
  -> scheme(index)
    @schemes[index]
  -> add(imask, jmask, kmask, scheme)
    if scheme == nil || @meta[4] >= @meta[3]
      return 0 - 1
    index = @meta[4] ## i64
    @imasks[index] = imask
    @jmasks[index] = jmask
    @kmasks[index] = kmask
    @schemes.push(scheme)
    @meta[4] += 1
    index

-> ffobpf_pool_rank(leaves, n, m, p) (Array i64 i64 i64) i64
  volume = n * m * p ## i64
  choice = i64[2]
  if ffbc_find_leaf(leaves, n, m, p, choice) == 1
    rank = leaves[choice[0]].rank() ## i64
    if rank <= volume
      return rank
  volume

-> ffobpf_pool_local(leaves, n, m, p) (Array i64 i64 i64)
  volume = n * m * p ## i64
  choice = i64[2]
  if ffbc_find_leaf(leaves, n, m, p, choice) == 1
    leaf = leaves[choice[0]]
    if leaf.rank() <= volume
      return ffbc_orient_scheme(leaf, choice[1])
  ffobp_naive(n, m, p)

# Complete the min-dimension-two part of the pool by exact disjoint splits.
# Increasing a+b guarantees that every proper 2xa xb child has already been
# loaded or generated.  This is a tensor direct sum, not zero-padding.
-> ffobpf_complete_min2(leaves, maximum) (Array i64) i64
  added = 0 ## i64
  sum = 4 ## i64
  while sum <= maximum * 2
    a = 2 ## i64
    while a <= maximum
      b = sum - a ## i64
      if b >= a && b <= maximum
        current = ffobpf_pool_rank(leaves, 2, a, b) ## i64
        best = current ## i64
        best_axis = 0 - 1 ## i64
        best_split = 0 ## i64
        split = 1 ## i64
        while split < a
          score = ffobpf_pool_rank(leaves, 2, split, b) + ffobpf_pool_rank(leaves, 2, a - split, b) ## i64
          if score < best
            best = score
            best_axis = 1
            best_split = split
          split += 1
        split = 1
        while split < b
          score = ffobpf_pool_rank(leaves, 2, a, split) + ffobpf_pool_rank(leaves, 2, a, b - split) ## i64
          if score < best
            best = score
            best_axis = 2
            best_split = split
          split += 1
        if best_axis >= 0
          ifull = 3 ## i64
          jfull = (1 << a) - 1 ## i64
          kfull = (1 << b) - 1 ## i64
          if best_axis == 1
            left_mask = (1 << best_split) - 1 ## i64
            right_mask = jfull ^ left_mask ## i64
            left_local = ffobpf_pool_local(leaves, 2, best_split, b)
            right_local = ffobpf_pool_local(leaves, 2, a - best_split, b)
            left = ffobp_embed_leaf(left_local, 2, a, b, ifull, left_mask, kfull)
            right = ffobp_embed_leaf(right_local, 2, a, b, ifull, right_mask, kfull)
          else
            left_mask = (1 << best_split) - 1
            right_mask = kfull ^ left_mask
            left_local = ffobpf_pool_local(leaves, 2, a, best_split)
            right_local = ffobpf_pool_local(leaves, 2, a, b - best_split)
            left = ffobp_embed_leaf(left_local, 2, a, b, ifull, jfull, left_mask)
            right = ffobp_embed_leaf(right_local, 2, a, b, ifull, jfull, right_mask)
          candidate = ffobp_concat(left, right)
          if candidate == nil || candidate.rank() != best || ffbc_verify_exact(candidate) != 1
            return 0 - 1
          leaves.push(candidate)
          added += 1
      a += 1
    sum += 1
  added

# Complete checked-in exact pool for sorted shapes 2--8.  The older DP
# completion remains below as a regression oracle and as a fallback for
# experiments above eight, but the live frontier no longer pays a rank penalty
# for a missing two-wide atom.
-> ffobpf_leaf_pool_2_to_8(root) (String)
  ffbcp_stable_2_to_8(root)

-> ffobpf_with_frontier_leaf(frontier, leaves) (FFBCScheme Array)
  result = []
  if frontier != nil
    result.push(frontier)
  i = 0 ## i64
  while i < leaves.size()
    result.push(leaves[i])
    i += 1
  result

-> ffobpf_add_mask(bank, count, mask, extent) (i64[] i64 i64 i64) i64
  if ffobp_mask_valid(mask, extent) != 1
    return count
  i = 0 ## i64
  while i < count
    if bank[i] == mask
      return count
    i += 1
  if count >= bank.size()
    return count
  bank[count] = mask
  count + 1

# Minimal coordinate mask on one MMT index axis that contains all three
# factors of a live rank-one term.  This is the useful support guide: a block
# missing any of these coordinates cannot possibly contribute that term.
-> ffobpf_term_axis_mask(scheme, term, axis) (FFBCScheme i64 i64) i64
  if scheme == nil || term < 0 || term >= scheme.rank() || axis < 0 || axis > 2
    return 0
  mask = 0 ## i64
  if axis == 0
    bit = 0 ## i64
    while bit < scheme.n() * scheme.m()
      if ffbc_bit(scheme.us(), term * scheme.uw(), bit) == 1
        mask = mask | (1 << (bit / scheme.m()))
      bit += 1
    bit = 0
    while bit < scheme.n() * scheme.p()
      if ffbc_bit(scheme.ws(), term * scheme.ww(), bit) == 1
        mask = mask | (1 << (bit / scheme.p()))
      bit += 1
  elsif axis == 1
    bit = 0
    while bit < scheme.n() * scheme.m()
      if ffbc_bit(scheme.us(), term * scheme.uw(), bit) == 1
        mask = mask | (1 << (bit % scheme.m()))
      bit += 1
    bit = 0
    while bit < scheme.m() * scheme.p()
      if ffbc_bit(scheme.vs(), term * scheme.vw(), bit) == 1
        mask = mask | (1 << (bit / scheme.p()))
      bit += 1
  else
    bit = 0
    while bit < scheme.m() * scheme.p()
      if ffbc_bit(scheme.vs(), term * scheme.vw(), bit) == 1
        mask = mask | (1 << (bit % scheme.p()))
      bit += 1
    bit = 0
    while bit < scheme.n() * scheme.p()
      if ffbc_bit(scheme.ws(), term * scheme.ww(), bit) == 1
        mask = mask | (1 << (bit % scheme.p()))
      bit += 1
  mask

# Singleton/full masks make the boundary reproducible.  Live term supports,
# complements, and a bounded AND/OR/XOR closure then expose overlapping masks
# that are invisible to the old coordinate-only catalogue.
-> ffobpf_support_bank(scheme, axis, bank) (FFBCScheme i64 i64[]) i64
  if scheme == nil || axis < 0 || axis > 2 || bank.size() < 1
    return 0
  extent = scheme.n() ## i64
  if axis == 1
    extent = scheme.m()
  if axis == 2
    extent = scheme.p()
  full = (1 << extent) - 1 ## i64
  count = 0 ## i64
  bit = 0 ## i64
  while bit < extent
    count = ffobpf_add_mask(bank, count, 1 << bit, extent)
    bit += 1
  # One canonical representative of every mask cardinality makes the
  # full-block branch complete modulo global coordinate permutations.  In a
  # full-block four-cycle the complement is forced, so cardinality is the only
  # orbit invariant of each free mask.
  width = 2 ## i64
  while width < extent
    count = ffobpf_add_mask(bank, count, (1 << width) - 1, extent)
    width += 1
  count = ffobpf_add_mask(bank, count, full, extent)
  term = 0 ## i64
  while term < scheme.rank() && count < bank.size()
    mask = ffobpf_term_axis_mask(scheme, term, axis) ## i64
    count = ffobpf_add_mask(bank, count, mask, extent)
    count = ffobpf_add_mask(bank, count, full ^ mask, extent)
    term += 1
  base_count = count ## i64
  i = 0 ## i64
  while i < base_count && count < bank.size()
    j = i + 1 ## i64
    while j < base_count && count < bank.size()
      count = ffobpf_add_mask(bank, count, bank[i] ^ bank[j], extent)
      count = ffobpf_add_mask(bank, count, bank[i] & bank[j], extent)
      count = ffobpf_add_mask(bank, count, bank[i] | bank[j], extent)
      j += 1
    i += 1
  count

-> ffobpf_pair_count(count) (i64) i64
  if count < 2
    return 0
  count * (count - 1) / 2

-> ffobpf_pair_at(bank, count, wanted, result) (i64[] i64 i64 i64[]) i64
  if wanted < 0 || wanted >= ffobpf_pair_count(count) || result.size() < 2
    return 0
  seen = 0 ## i64
  i = 0 ## i64
  while i < count
    j = i + 1 ## i64
    while j < count
      if seen == wanted
        result[0] = bank[i]
        result[1] = bank[j]
        return 1
      seen += 1
      j += 1
    i += 1
  0

# Deterministic even sampling of the complete
# fixed-mask x C(A,2) x C(B,2) support-bank catalogue for one orientation.
-> ffobpf_support_identity_at(n, m, p, axis, fixed_bank, fixed_count, a_bank, a_count, b_bank, b_count, ordinal, samples) (i64 i64 i64 i64 i64[] i64 i64[] i64 i64[] i64 i64 i64)
  apairs = ffobpf_pair_count(a_count) ## i64
  bpairs = ffobpf_pair_count(b_count) ## i64
  total = fixed_count * apairs * bpairs ## i64
  if total < 1 || ordinal < 0 || samples < 1 || ordinal >= samples
    return nil
  if samples > total
    samples = total
    if ordinal >= samples
      return nil
  linear = ordinal * total / samples ## i64
  bp = linear % bpairs ## i64
  linear = linear / bpairs
  ap = linear % apairs ## i64
  fi = linear / apairs ## i64
  av = i64[2]
  bv = i64[2]
  if ffobpf_pair_at(a_bank, a_count, ap, av) != 1 || ffobpf_pair_at(b_bank, b_count, bp, bv) != 1
    return nil
  ffobp_four_cycle(n, m, p, axis, fixed_bank[fi], av[0], av[1], bv[0], bv[1])

-> ffobpf_choice_rank(leaves, n, m, p) (Array i64 i64 i64) i64
  ffobpf_pool_rank(leaves, n, m, p)

# Trusted embedding hot path.  Every pool leaf was fully gated when loaded;
# the planted tests below compare this mapping with the independent schoolbook
# block tensor, and every retained live endpoint receives a fresh full gate.
-> ffobpf_embed_choice(leaf, code, target_n, target_m, target_p, imask, jmask, kmask) (FFBCScheme i64 i64 i64 i64 i64 i64 i64)
  ln = ffobp_popcount(imask) ## i64
  lm = ffobp_popcount(jmask) ## i64
  lp = ffobp_popcount(kmask) ## i64
  if leaf == nil || ffbc_orientation_matches(code, leaf.n(), leaf.m(), leaf.p(), ln, lm, lp) != 1
    return nil
  result = FFBCScheme.new(target_n, target_m, target_p, leaf.rank())
  local_u = i64[ffbc_words(ln * lm)]
  local_v = i64[ffbc_words(lm * lp)]
  local_w = i64[ffbc_words(ln * lp)]
  term = 0 ## i64
  while term < leaf.rank()
    ffbc_orient_term(leaf, term, code, local_u, local_v, local_w)
    bit = 0 ## i64
    while bit < ln * lm
      if ffbc_bit(local_u, 0, bit) == 1
        gi = ffobp_nth_set(imask, bit / lm) ## i64
        gj = ffobp_nth_set(jmask, bit % lm) ## i64
        ffbc_toggle_bit(result.us(), term * result.uw(), gi * target_m + gj)
      bit += 1
    bit = 0
    while bit < lm * lp
      if ffbc_bit(local_v, 0, bit) == 1
        gj = ffobp_nth_set(jmask, bit / lp) ## i64
        gk = ffobp_nth_set(kmask, bit % lp) ## i64
        ffbc_toggle_bit(result.vs(), term * result.vw(), gj * target_p + gk)
      bit += 1
    bit = 0
    while bit < ln * lp
      if ffbc_bit(local_w, 0, bit) == 1
        gi = ffobp_nth_set(imask, bit / lp) ## i64
        gk = ffobp_nth_set(kmask, bit % lp) ## i64
        ffbc_toggle_bit(result.ws(), term * result.ww(), gi * target_p + gk)
      bit += 1
    term += 1
  result.set_rank(leaf.rank())
  result

-> ffobpf_materialize_block(leaves, target_n, target_m, target_p, imask, jmask, kmask) (Array i64 i64 i64 i64 i64 i64)
  ln = ffobp_popcount(imask) ## i64
  lm = ffobp_popcount(jmask) ## i64
  lp = ffobp_popcount(kmask) ## i64
  volume = ln * lm * lp ## i64
  choice = i64[2]
  if ffbc_find_leaf(leaves, ln, lm, lp, choice) == 1
    leaf = leaves[choice[0]]
    if leaf.rank() <= volume
      return ffobpf_embed_choice(leaf, choice[1], target_n, target_m, target_p, imask, jmask, kmask)
  ffobp_naive_block(target_n, target_m, target_p, imask, jmask, kmask)

-> ffobpf_cached_block(cache, leaves, imask, jmask, kmask) (FFOBPBlockCache Array i64 i64 i64)
  found = cache.find(imask, jmask, kmask) ## i64
  if found >= 0
    return cache.scheme(found)
  scheme = ffobpf_materialize_block(leaves, cache.n(), cache.m(), cache.p(), imask, jmask, kmask)
  if scheme == nil
    return nil
  z = cache.add(imask, jmask, kmask, scheme) ## i64
  scheme

# Hash-parity merge.  Unlike the older quadratic planted helper, this remains
# cheap when a four-cycle contains a full 7x7 rank-247 leaf.
-> ffobpf_toggle_scheme(source, result, slots, active, unique_rank) (FFBCScheme FFBCScheme i64[] i64[] i64) i64
  if source == nil || result == nil
    return 0 - unique_rank - 1
  u = i64[result.uw()]
  v = i64[result.vw()]
  w = i64[result.ww()]
  term = 0 ## i64
  rank = unique_rank ## i64
  while term < source.rank()
    ffbc_copy(source.us(), term * source.uw(), u, 0, result.uw())
    ffbc_copy(source.vs(), term * source.vw(), v, 0, result.vw())
    ffbc_copy(source.ws(), term * source.ww(), w, 0, result.ww())
    rank = ffbc_toggle_term(result, u, v, w, slots, active, rank)
    if rank < 0
      return rank
    term += 1
  rank

-> ffobpf_parity4(a, b, c, d) (FFBCScheme FFBCScheme FFBCScheme FFBCScheme)
  if a == nil || b == nil || c == nil || d == nil
    return nil
  if a.n() != b.n() || a.m() != b.m() || a.p() != b.p() || a.n() != c.n() || a.m() != c.m() || a.p() != c.p() || a.n() != d.n() || a.m() != d.m() || a.p() != d.p()
    return nil
  nominal = a.rank() + b.rank() + c.rank() + d.rank() ## i64
  result = FFBCScheme.new(a.n(), a.m(), a.p(), nominal)
  table_capacity = 16 ## i64
  while table_capacity < nominal * 4
    table_capacity *= 2
  slots = i64[table_capacity]
  active = i64[nominal]
  rank = ffobpf_toggle_scheme(a, result, slots, active, 0) ## i64
  rank = ffobpf_toggle_scheme(b, result, slots, active, rank)
  rank = ffobpf_toggle_scheme(c, result, slots, active, rank)
  rank = ffobpf_toggle_scheme(d, result, slots, active, rank)
  if rank < 0
    return nil
  ffbc_compact(result, active, rank)
  result

-> ffobpf_parity2(a, b) (FFBCScheme FFBCScheme)
  if a == nil || b == nil || a.n() != b.n() || a.m() != b.m() || a.p() != b.p()
    return nil
  empty = FFBCScheme.new(a.n(), a.m(), a.p(), 0)
  empty.set_rank(0)
  ffobpf_parity4(a, b, empty, empty)

-> ffobpf_identity_macro(identity, cache, leaves) (FFOBPIdentity FFOBPBlockCache Array)
  if ffobp_identity_valid(identity) != 1 || identity.count() != 4
    return nil
  blocks = []
  i = 0 ## i64
  while i < 4
    block = ffobpf_cached_block(cache, leaves, identity.imask(i), identity.jmask(i), identity.kmask(i))
    if block == nil
      return nil
    blocks.push(block)
    i += 1
  ffobpf_parity4(blocks[0], blocks[1], blocks[2], blocks[3])

-> ffobpf_overlap_count(left, right) (FFBCScheme FFBCScheme) i64
  if left == nil || right == nil || left.n() != right.n() || left.m() != right.m() || left.p() != right.p()
    return 0 - 1
  overlap = 0 ## i64
  i = 0 ## i64
  while i < right.rank()
    j = 0 ## i64
    while j < left.rank()
      if ffobp_terms_equal(left, j, right, i) == 1
        overlap += 1
        j = left.rank()
      else
        j += 1
    i += 1
  overlap

# Exact rank of the term-set XOR, without allocating an endpoint.  Both inputs
# are parity-compact, so every shared term cancels once.
-> ffobpf_xor_rank(left, right) (FFBCScheme FFBCScheme) i64
  overlap = ffobpf_overlap_count(left, right) ## i64
  if overlap < 0
    return 0 - 1
  left.rank() + right.rank() - 2 * overlap

-> ffobpf_apply_gated(frontier, zero_macro, rank_limit) (FFBCScheme FFBCScheme i64)
  estimated = ffobpf_xor_rank(frontier, zero_macro) ## i64
  if estimated < 1 || estimated > rank_limit
    return nil
  candidate = ffobpf_parity2(frontier, zero_macro)
  if candidate == nil || candidate.rank() != estimated || ffbc_verify_exact(candidate) != 1
    return nil
  candidate

-> ffobpf_identity_nominal(identity, leaves, skip_block) (FFOBPIdentity Array i64) i64
  total = 0 ## i64
  block = 0 ## i64
  while block < identity.count()
    if block != skip_block
      total += ffobpf_choice_rank(leaves, ffobp_popcount(identity.imask(block)), ffobp_popcount(identity.jmask(block)), ffobp_popcount(identity.kmask(block)))
    block += 1
  total

-> ffobpf_full_block_index(identity) (FFOBPIdentity) i64
  if identity == nil
    return 0 - 1
  ifull = (1 << identity.n()) - 1 ## i64
  jfull = (1 << identity.m()) - 1 ## i64
  kfull = (1 << identity.p()) - 1 ## i64
  i = 0 ## i64
  while i < identity.count()
    if identity.imask(i) == ifull && identity.jmask(i) == jfull && identity.kmask(i) == kfull
      return i
    i += 1
  0 - 1

-> ffobpf_without_block(identity, skip, cache, leaves) (FFOBPIdentity i64 FFOBPBlockCache Array)
  blocks = []
  i = 0 ## i64
  while i < identity.count()
    if i != skip
      block = ffobpf_cached_block(cache, leaves, identity.imask(i), identity.jmask(i), identity.kmask(i))
      if block == nil
        return nil
      blocks.push(block)
    i += 1
  if blocks.size() != 3
    return nil
  empty = FFBCScheme.new(identity.n(), identity.m(), identity.p(), 0)
  empty.set_rank(0)
  ffobpf_parity4(blocks[0], blocks[1], blocks[2], empty)

# Construct one of four targeted identities containing the complete tensor as
# a block.  These are the only four-cycle candidates capable of cancelling an
# entire live certificate, so they receive a complete support-bank audit after
# the much cheaper nominal-rank filter.
-> ffobpf_full_identity(n, m, p, axis, mode, amask, bmask) (i64 i64 i64 i64 i64 i64 i64)
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
  fixed = (1 << fixed_extent) - 1 ## i64
  afull = (1 << a_extent) - 1 ## i64
  bfull = (1 << b_extent) - 1 ## i64
  if amask <= 0 || amask >= afull || bmask <= 0 || bmask >= bfull
    return nil
  if mode == 0
    return ffobp_four_cycle(n, m, p, axis, fixed, afull, amask, bfull, bmask)
  if mode == 1
    return ffobp_four_cycle(n, m, p, axis, fixed, afull, amask, bmask, bfull)
  if mode == 2
    return ffobp_four_cycle(n, m, p, axis, fixed, amask, afull, bmask, bfull ^ bmask)
  if mode == 3
    return ffobp_four_cycle(n, m, p, axis, fixed, amask, afull ^ amask, bmask, bfull ^ bmask)
  nil

# Result fields:
#   0 identities, 1 formula-pass, 2 exact endpoints, 3 best rank,
#   4 best nominal, 5 best axis, 6 best mode.
-> ffobpf_scan_full_replacements(frontier, leaves, ibank, icount, jbank, jcount, kbank, kcount, formula_slack, cache, result) (FFBCScheme Array i64[] i64 i64[] i64 i64[] i64 i64 FFOBPBlockCache i64[]) i64
  if result.size() < 7
    return 0
  result[3] = 0x7fffffff
  result[4] = 0x7fffffff
  axis = 0 ## i64
  while axis < 3
    abank = jbank
    acount = jcount ## i64
    bbank = kbank
    bcount = kcount ## i64
    if axis == 1
      abank = ibank
      acount = icount
      bbank = kbank
      bcount = kcount
    if axis == 2
      abank = ibank
      acount = icount
      bbank = jbank
      bcount = jcount
    ai = 0 ## i64
    while ai < acount
      bi = 0 ## i64
      while bi < bcount
        mode = 0 ## i64
        while mode < 4
          identity = ffobpf_full_identity(frontier.n(), frontier.m(), frontier.p(), axis, mode, abank[ai], bbank[bi])
          if identity != nil
            result[0] += 1
            full_block = ffobpf_full_block_index(identity) ## i64
            nominal = ffobpf_identity_nominal(identity, leaves, full_block) ## i64
            if nominal < result[4]
              result[4] = nominal
            if nominal <= frontier.rank() + formula_slack
              result[1] += 1
              candidate = ffobpf_without_block(identity, full_block, cache, leaves)
              if candidate != nil && candidate.rank() < result[3] && ffbc_verify_exact(candidate) == 1
                result[3] = candidate.rank()
                result[5] = axis
                result[6] = mode
              if candidate != nil && candidate.rank() <= frontier.rank() && ffbc_verify_exact(candidate) == 1
                result[2] += 1
              # Candidate publication is intentionally outside this scanner:
              # callers retain only a fully gated rank-neutral/lower endpoint.
          mode += 1
        bi += 1
      ai += 1
    axis += 1
  if result[3] == 0x7fffffff
    result[3] = 0 - 1
  result[2]

# Bounded generic support audit plus a pair-XOR pass over the best individual
# zero macros.  `result`: sampled, non-noop, best-single-rank, best-single-
# macro, best-single-overlap, pairs, best-pair-rank, useful-gated.
-> ffobpf_scan_support(frontier, leaves, ibank, icount, jbank, jcount, kbank, kcount, samples_per_axis, top_capacity, cache, result) (FFBCScheme Array i64[] i64 i64[] i64 i64[] i64 i64 i64 FFOBPBlockCache i64[]) i64
  if result.size() < 8 || samples_per_axis < 1 || top_capacity < 1
    return 0
  result[2] = 0x7fffffff
  result[6] = 0x7fffffff
  top = []
  top_scores = i64[top_capacity]
  axis = 0 ## i64
  while axis < 3
    fbank = ibank
    fcount = icount ## i64
    abank = jbank
    acount = jcount ## i64
    bbank = kbank
    bcount = kcount ## i64
    if axis == 1
      fbank = jbank
      fcount = jcount
      abank = ibank
      acount = icount
      bbank = kbank
      bcount = kcount
    if axis == 2
      fbank = kbank
      fcount = kcount
      abank = ibank
      acount = icount
      bbank = jbank
      bcount = jcount
    total = fcount * ffobpf_pair_count(acount) * ffobpf_pair_count(bcount) ## i64
    samples = samples_per_axis ## i64
    if samples > total
      samples = total
    sample = 0 ## i64
    while sample < samples
      identity = ffobpf_support_identity_at(frontier.n(), frontier.m(), frontier.p(), axis, fbank, fcount, abank, acount, bbank, bcount, sample, samples)
      result[0] += 1
      if identity != nil
        macro = ffobpf_identity_macro(identity, cache, leaves)
        if macro != nil && macro.rank() > 0
          result[1] += 1
          overlap = ffobpf_overlap_count(frontier, macro) ## i64
          score = frontier.rank() + macro.rank() - 2 * overlap ## i64
          if score < result[2]
            result[2] = score
            result[3] = macro.rank()
            result[4] = overlap
          slot = top.size() ## i64
          if slot < top_capacity
            top.push(macro)
            top_scores[slot] = score
          else
            worst = 0 ## i64
            ti = 1 ## i64
            while ti < top_capacity
              if top_scores[ti] > top_scores[worst]
                worst = ti
              ti += 1
            if score < top_scores[worst]
              top[worst] = macro
              top_scores[worst] = score
          if score <= frontier.rank()
            gated = ffobpf_apply_gated(frontier, macro, frontier.rank())
            if gated != nil
              result[7] += 1
      sample += 1
    axis += 1

  i = 0 ## i64
  while i < top.size()
    j = i + 1 ## i64
    while j < top.size()
      pair_macro = ffobpf_parity2(top[i], top[j])
      if pair_macro != nil && pair_macro.rank() > 0
        result[5] += 1
        pair_score = ffobpf_xor_rank(frontier, pair_macro) ## i64
        if pair_score < result[6]
          result[6] = pair_score
        if pair_score <= frontier.rank()
          gated = ffobpf_apply_gated(frontier, pair_macro, frontier.rank())
          if gated != nil
            result[7] += 1
      j += 1
    i += 1
  if result[2] == 0x7fffffff
    result[2] = 0 - 1
  if result[6] == 0x7fffffff
    result[6] = 0 - 1
  result[7]

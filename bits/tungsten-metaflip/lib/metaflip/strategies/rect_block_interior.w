# Low-cadence block-interior escape for rectangular CPU islands.
#
# The square span-refactor worker already uses the rectangular-aware seam
# selector, but its state splice deliberately calls the square n^3 verifier.
# This adapter keeps the shared local algebra and performs the splice on a flat
# copy of one rectangular island, with the full n*m*p coefficient gate before
# returning it.  A coordinator can therefore replace one rotating island
# without pausing or homogenizing the rest of the CPU fleet.

use ../rect
use block_interior
use span_refactor

# Telemetry layout (caller-owned i64[7]):
#   0 attempts, 1 local replacements, 2 exact accepts, 3 rank drops,
#   4 density improvements, 5 neutral escapes, 6 exact rejects.

# Keep one resident probe from becoming the portfolio barrier.  The probe runs
# beside the ordinary workers; only work that exceeds the slowest CPU tranche
# consumes join time.  Cadence changes by at most 2x after an observation and
# remains bounded, so a temporarily expensive span cannot silently retire the
# strategy forever.
-> ffrbi_next_period(current, probe_ms, cpu_ms) (i64 i64 i64) i64
  period = current ## i64
  if period < 1
    period = 1
  if period > 16
    period = 16
  if cpu_ms < 1 || probe_ms < 0
    return period
  if probe_ms > cpu_ms * 2
    period *= 2
    if period > 16
      period = 16
    return period
  if probe_ms * 2 < cpu_ms && period > 1
    period /= 2
    if period < 1
      period = 1
  period

-> ffrbi_copy_state(source)
  candidate = i64[source.size()]
  i = 0 ## i64
  while i < source.size()
    candidate[i] = source[i]
    i += 1
  candidate

# Keep the natural composition seam in one quarter of attempts and enumerate
# every legal off-center cut in the other three quarters.  The mixed radix is
# deterministic and gives rectangular axes independent phases.
-> ffrbi_cut(size, nonce, divisor) (i64 i64 i64) i64
  if size < 2
    return 0
  if nonce % 4 == 0
    return ffbir_default_cut(size)
  # Remove the reserved natural-seam tickets before mixed-radix decoding so
  # the nondefault subsequence starts at zero and does not skip cut one.
  ordinal = nonce ## i64
  if ordinal > 0
    ordinal = ordinal - 1 - ordinal / 4
  ticket = ordinal / divisor ## i64
  if ticket < 0
    ticket = 0 - ticket
  1 + (ticket % (size - 1))

-> ffrbi_pair_hash(us, vs, ws, left, right, nonce) (i64[] i64[] i64[] i64 i64 i64) i64
  left_hash = ffbir_term_hash(us[left], vs[left], ws[left], nonce) ## i64
  right_hash = ffbir_term_hash(us[right], vs[right], ws[right], nonce + 1009) ## i64
  (left_hash ^ (right_hash >> 1) ^ (right_hash << 1)) & 9223372036854775807

-> ffrbi_fill_window(us, vs, ws, rank, n, m, p, cut_n, cut_m, cut_p, k, nonce, selected, chosen) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64) i64
  while chosen < k
    best = 0 - 1 ## i64
    best_score = 0 - 1000000000 ## i64
    candidate = 0 ## i64
    while candidate < rank
      if ffbir_selected(selected, chosen, candidate) == 0
        score = ffbir_term_seam_score(us[candidate], vs[candidate], ws[candidate], n, m, p, cut_n, cut_m, cut_p) * 64 ## i64
        i = 0 ## i64
        while i < chosen
          other = selected[i] ## i64
          score += ffbir_overlap_score(us[candidate], vs[candidate], ws[candidate], us[other], vs[other], ws[other])
          i += 1
        if score > best_score || (score == best_score && ffbir_term_before(us, vs, ws, candidate, best, nonce + chosen * 1009) != 0)
          best = candidate
          best_score = score
      candidate += 1
    if best < 0
      return 0
    selected[chosen] = best
    chosen += 1
  chosen

# Rotate three complementary selectors: the strict composition seam, the
# strongest shared-factor pair (which deterministically exposes planted split
# debt), and a content-hash anchor that samples the rest of the presentation.
-> ffrbi_choose_window(us, vs, ws, rank, n, m, p, cut_n, cut_m, cut_p, k, nonce, selected) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  mode = nonce % 3 ## i64
  if mode < 0
    mode = 0 - mode
  if mode == 0
    return ffbir_choose_window(us, vs, ws, rank, n, m, p, cut_n, cut_m, cut_p, k, nonce, selected)
  if mode == 1
    best_left = 0 - 1 ## i64
    best_right = 0 - 1 ## i64
    best_score = 0 - 1000000000 ## i64
    best_hash = 9223372036854775807 ## i64
    left = 0 ## i64
    while left < rank
      right = left + 1 ## i64
      while right < rank
        score = ffbir_overlap_score(us[left], vs[left], ws[left], us[right], vs[right], ws[right]) ## i64
        score += 8 * (ffbir_term_seam_score(us[left], vs[left], ws[left], n, m, p, cut_n, cut_m, cut_p) + ffbir_term_seam_score(us[right], vs[right], ws[right], n, m, p, cut_n, cut_m, cut_p))
        pair_hash = ffrbi_pair_hash(us, vs, ws, left, right, nonce) ## i64
        if score > best_score || (score == best_score && pair_hash < best_hash)
          best_left = left
          best_right = right
          best_score = score
          best_hash = pair_hash
        right += 1
      left += 1
    if best_left < 0
      return 0
    selected[0] = best_left
    selected[1] = best_right
    return ffrbi_fill_window(us, vs, ws, rank, n, m, p, cut_n, cut_m, cut_p, k, nonce, selected, 2)

  anchor = 0 - 1 ## i64
  candidate = 0 ## i64
  while candidate < rank
    if ffbir_term_before(us, vs, ws, candidate, anchor, nonce) != 0
      anchor = candidate
    candidate += 1
  if anchor < 0
    return 0
  selected[0] = anchor
  ffrbi_fill_window(us, vs, ws, rank, n, m, p, cut_n, cut_m, cut_p, k, nonce, selected, 1)

-> ffrbi_apply(source, n, m, p, selected, k, out_u, out_v, out_w, out_count, seed, stats) (i64[] i64 i64 i64 i64[] i64 i64[] i64[] i64[] i64 i64 i64[])
  old_rank = ffr_current_rank(source) ## i64
  old_bits = ffr_current_bits(source) ## i64
  source_u = i64[4]
  source_v = i64[4]
  source_w = i64[4]
  if ffsr_capture_current(source, selected, k, source_u, source_v, source_w) == 0
    return nil
  if ffsr_output_well_formed(out_u, out_v, out_w, out_count) == 0
    return nil
  if ffsr_terms_same_set(source_u, source_v, source_w, k, out_u, out_v, out_w, out_count) != 0
    return nil

  candidate = ffrbi_copy_state(source)
  z = ffw_seed_rng(candidate, seed) ## i64
  rank = old_rank ## i64
  i = 0 ## i64
  valid = 1 ## i64
  while i < k
    next_rank = ffw_toggle(candidate, source_u[i], source_v[i], source_w[i], rank) ## i64
    if next_rank != rank - 1
      valid = 0
    rank = next_rank
    i += 1
  i = 0
  while i < out_count
    next_rank = ffw_toggle(candidate, out_u[i], out_v[i], out_w[i], rank) ## i64
    if next_rank == rank
      valid = 0
    rank = next_rank
    i += 1
  candidate[6] = rank
  if valid == 0 || rank < 1 || rank > candidate[4]
    return nil
  if ffr_verify_current_exact(candidate, n, m, p) == 0
    stats[6] += 1
    return nil

  # Besides adopting a strict local improvement, this call synchronizes the
  # O(1) current-density accumulator.  A neutral/higher-density endpoint stays
  # in the current view while the copied island retains its previous best.
  adopted = ffr_adopt_current(candidate, 1) ## i64
  if adopted < 0
    stats[6] += 1
    return nil
  stats[2] += 1
  current_bits = ffr_current_bits(candidate) ## i64
  if rank < old_rank
    stats[3] += 1
  elsif rank == old_rank && current_bits < old_bits
    stats[4] += 1
  else
    stats[5] += 1
  candidate

# Try one complete local neighborhood.  The caller rotates the island and
# nonce once per ordinary CPU round; this routine itself never loops over a
# hidden budget.  Rank-closing k->k-1 is preferred, followed by a changed
# rank-neutral k->k endpoint that can open a new ordinary-flip basin.
-> ffrbi_try(source, n, m, p, nonce, stats) (i64[] i64 i64 i64 i64 i64[])
  if stats.size() < 7
    return nil
  stats[0] += 1
  if source == nil || ffr_valid(source) == 0
    return nil
  rank = ffr_current_rank(source) ## i64
  if rank < 3
    return nil
  if ffr_verify_current_exact(source, n, m, p) == 0
    stats[6] += 1
    return nil

  capacity = source[4] ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if ffw_export_current(source, us, vs, ws) != rank
    return nil

  k = 3 ## i64
  if rank >= 4 && (nonce & 1) != 0
    k = 4
  cut_n = ffrbi_cut(n, nonce, 2) ## i64
  cut_m = ffrbi_cut(m, nonce, 2 * n) ## i64
  cut_p = ffrbi_cut(p, nonce, 2 * n * m) ## i64
  selected = i64[4]
  if ffrbi_choose_window(us, vs, ws, rank, n, m, p, cut_n, cut_m, cut_p, k, nonce, selected) != k
    return nil

  source_u = i64[4]
  source_v = i64[4]
  source_w = i64[4]
  i = 0 ## i64
  while i < k
    source_u[i] = us[selected[i]]
    source_v[i] = vs[selected[i]]
    source_w[i] = ws[selected[i]]
    i += 1

  pass = 0 ## i64
  while pass < 2
    want = k - 1 ## i64
    if pass == 1
      want = k
    if ffsr_move_supported(k, want) != 0
      out_u = i64[4]
      out_v = i64[4]
      out_w = i64[4]
      meta = i64[12]
      found = ffsr_find_terms(source_u, source_v, source_w, k, want, out_u, out_v, out_w, meta) ## i64
      if found == want
        stats[1] += 1
        if ffsr_verify_local_replacement(source_u, source_v, source_w, k, out_u, out_v, out_w, found) != 0
          candidate = ffrbi_apply(source, n, m, p, selected, k, out_u, out_v, out_w, found, nonce + 104729 * (pass + 1), stats)
          if candidate != nil
            return candidate
    pass += 1
  nil

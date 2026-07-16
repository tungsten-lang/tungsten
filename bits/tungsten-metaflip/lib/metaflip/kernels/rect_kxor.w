# Offline generalized exact GPU XOR surgery for rectangular Metaflip schemes.
#
# This deliberately does not participate in the production kernel pool yet.
# It adapts the square k-XOR join machinery to unequal U/V/W factor widths and
# insists on three progressively stronger gates:
#
#   1. a linear 128-bit fingerprint join on the GPU,
#   2. exhaustive equality of the selected and replacement local tensors, and
#   3. exhaustive reconstruction of the complete rectangular multiplication
#      tensor before writing a certificate.
#
# Supported experiments are 5 -> 3 (single/pair), 6 -> 4 (pair/pair),
# 6 -> 5 and 7 -> 5 (pair/triple), plus 7 -> 6 (triple/triple). Both table sides are constructed directly on the GPU
# as bucket chains.  A canonical tuple thread performs exactly one atomic head
# exchange and stores its predecessor in `links`; no large tuple-fingerprint
# staging arrays or serial host insertion pass are required.

## i32[]: heads
@gpu fn ffrx_clear_chain_heads(heads)
  tid = gpu.thread_position_in_grid.x ## i32
  heads[tid] = -1

## u32[]: fps0, fps1, fps2, fps3
## i32[]: heads, links, params
@gpu fn ffrx_build_canonical_tuple_chains(fps0, fps1, fps2, fps3, heads, links, params)
  tid = gpu.thread_position_in_grid.x ## i32
  count = params[0] ## i32
  tuple_size = params[1] ## i32
  table_mask = params[2] ## u32
  remaining = tid ## i32
  a = 0 ## i32
  b = -1 ## i32
  c = -1 ## i32
  finding = 0 ## i32
  if tuple_size == 1
    a = tid
  if tuple_size == 2
    finding = 1
    while finding == 1
      if a >= count - 1
        finding = 0
      else
        choices = count - a - 1 ## i32
        if remaining < choices
          finding = 0
        else
          remaining = remaining - choices
          a = a + 1
    b = a + 1 + remaining
  if tuple_size == 3
    finding = 1
    while finding == 1
      if a >= count - 2
        finding = 0
      else
        choices = (count - a - 1) * (count - a - 2) / 2 ## i32
        if remaining < choices
          finding = 0
        else
          remaining = remaining - choices
          a = a + 1
    b = a + 1
    finding = 1
    while finding == 1
      if b >= count - 1
        finding = 0
      else
        choices2 = count - b - 1 ## i32
        if remaining < choices2
          finding = 0
        else
          remaining = remaining - choices2
          b = b + 1
    c = b + 1 + remaining
  p0 = fps0[a] ## u32
  p1 = fps1[a] ## u32
  p2 = fps2[a] ## u32
  p3 = fps3[a] ## u32
  if tuple_size >= 2
    p0 = p0 ^ fps0[b]
    p1 = p1 ^ fps1[b]
    p2 = p2 ^ fps2[b]
    p3 = p3 ^ fps3[b]
  if tuple_size == 3
    p0 = p0 ^ fps0[c]
    p1 = p1 ^ fps1[c]
    p2 = p2 ^ fps2[c]
    p3 = p3 ^ fps3[c]
  mixed = p0 ^ (p1 >> 7) ^ (p2 >> 13) ^ (p3 >> 19) ## u32
  slot = mixed & table_mask ## u32
  previous = gpu.atomic_exchange_i32(heads, slot, tid) ## i32
  links[tid] = previous

## u32[]: fps0, fps1, fps2, fps3, target, matches, match_counts
## i32[]: heads, links, params
@gpu fn ffrx_probe_canonical_triples(fps0, fps1, fps2, fps3, heads, links, target, matches, match_counts, params)
  tid = gpu.thread_position_in_grid.x ## i32
  count = params[0] ## i32
  table_mask = params[1] ## u32
  tuple_size = params[2] ## i32
  wanted_ordinal = params[3] ## i32
  remaining = tid ## i32
  a = 0 ## i32
  finding = 1 ## i32
  while finding == 1
    if a >= count - 2
      finding = 0
    else
      choices = (count - a - 1) * (count - a - 2) / 2 ## i32
      if remaining < choices
        finding = 0
      else
        remaining = remaining - choices
        a = a + 1
  b = a + 1 ## i32
  finding = 1
  while finding == 1
    if b >= count - 1
      finding = 0
    else
      choices2 = count - b - 1 ## i32
      if remaining < choices2
        finding = 0
      else
        remaining = remaining - choices2
        b = b + 1
  c = b + 1 + remaining ## i32
  matches[tid] = 0
  want0 = target[0] ^ fps0[a] ^ fps0[b] ^ fps0[c] ## u32
  want1 = target[1] ^ fps1[a] ^ fps1[b] ^ fps1[c] ## u32
  want2 = target[2] ^ fps2[a] ^ fps2[b] ^ fps2[c] ## u32
  want3 = target[3] ^ fps3[a] ^ fps3[b] ^ fps3[c] ## u32
  mixed = want0 ^ (want1 >> 7) ^ (want2 >> 13) ^ (want3 >> 19) ## u32
  slot = mixed & table_mask ## u32
  node = heads[slot] ## i32
  seen = 0 ## i32
  while node >= 0
    table_remaining = node ## i32
    x = 0 ## i32
    y = 0 ## i32
    z = -1 ## i32
    table_finding = 0 ## i32
    if tuple_size == 2
      table_finding = 1
      while table_finding == 1
        if x >= count - 1
          table_finding = 0
        else
          table_choices = count - x - 1 ## i32
          if table_remaining < table_choices
            table_finding = 0
          else
            table_remaining = table_remaining - table_choices
            x = x + 1
      y = x + 1 + table_remaining
    if tuple_size == 3
      table_finding = 1
      while table_finding == 1
        if x >= count - 2
          table_finding = 0
        else
          table_choices = (count - x - 1) * (count - x - 2) / 2 ## i32
          if table_remaining < table_choices
            table_finding = 0
          else
            table_remaining = table_remaining - table_choices
            x = x + 1
      y = x + 1
      table_finding = 1
      while table_finding == 1
        if y >= count - 1
          table_finding = 0
        else
          table_choices2 = count - y - 1 ## i32
          if table_remaining < table_choices2
            table_finding = 0
          else
            table_remaining = table_remaining - table_choices2
            y = y + 1
      z = y + 1 + table_remaining
    got0 = fps0[x] ^ fps0[y] ## u32
    got1 = fps1[x] ^ fps1[y] ## u32
    got2 = fps2[x] ^ fps2[y] ## u32
    got3 = fps3[x] ^ fps3[y] ## u32
    if tuple_size == 3
      got0 = got0 ^ fps0[z]
      got1 = got1 ^ fps1[z]
      got2 = got2 ^ fps2[z]
      got3 = got3 ^ fps3[z]
    same = 0 ## i32
    if got0 == want0
      if got1 == want1
        if got2 == want2
          if got3 == want3
            same = 1
    if same == 1
      overlap = 0 ## i32
      if x == a
        overlap = 1
      if x == b
        overlap = 1
      if x == c
        overlap = 1
      if y == a
        overlap = 1
      if y == b
        overlap = 1
      if y == c
        overlap = 1
      if z == a
        overlap = 1
      if z == b
        overlap = 1
      if z == c
        overlap = 1
      if overlap == 0
        if seen == wanted_ordinal
          matches[tid] = node + 1
          if wanted_ordinal > 0
            node = -1
        seen = seen + 1
    if node >= 0
      node = links[node]
  if wanted_ordinal == 0
    match_counts[tid] = seen

# Pair-query companion for the direct 6 -> 4 objective. The table side is
# also canonical pairs, so each thread covers one unordered 2+2 partition and
# the same chain ordinal protocol remains collision-complete.
## u32[]: fps0, fps1, fps2, fps3, target, matches, match_counts
## i32[]: heads, links, params
@gpu fn ffrx_probe_canonical_pairs(fps0, fps1, fps2, fps3, heads, links, target, matches, match_counts, params)
  tid = gpu.thread_position_in_grid.x ## i32
  count = params[0] ## i32
  table_mask = params[1] ## u32
  tuple_size = params[2] ## i32
  wanted_ordinal = params[3] ## i32
  remaining = tid ## i32
  a = 0 ## i32
  finding = 1 ## i32
  while finding == 1
    if a >= count - 1
      finding = 0
    else
      choices = count - a - 1 ## i32
      if remaining < choices
        finding = 0
      else
        remaining = remaining - choices
        a = a + 1
  b = a + 1 + remaining ## i32
  matches[tid] = 0
  want0 = target[0] ^ fps0[a] ^ fps0[b] ## u32
  want1 = target[1] ^ fps1[a] ^ fps1[b] ## u32
  want2 = target[2] ^ fps2[a] ^ fps2[b] ## u32
  want3 = target[3] ^ fps3[a] ^ fps3[b] ## u32
  mixed = want0 ^ (want1 >> 7) ^ (want2 >> 13) ^ (want3 >> 19) ## u32
  slot = mixed & table_mask ## u32
  node = heads[slot] ## i32
  seen = 0 ## i32
  while node >= 0
    table_remaining = node ## i32
    x = 0 ## i32
    y = -1 ## i32
    if tuple_size == 1
      x = node
    if tuple_size == 2
      table_finding = 1 ## i32
      while table_finding == 1
        if x >= count - 1
          table_finding = 0
        else
          table_choices = count - x - 1 ## i32
          if table_remaining < table_choices
            table_finding = 0
          else
            table_remaining = table_remaining - table_choices
            x = x + 1
      y = x + 1 + table_remaining
    got0 = fps0[x] ## u32
    got1 = fps1[x] ## u32
    got2 = fps2[x] ## u32
    got3 = fps3[x] ## u32
    if tuple_size == 2
      got0 = got0 ^ fps0[y]
      got1 = got1 ^ fps1[y]
      got2 = got2 ^ fps2[y]
      got3 = got3 ^ fps3[y]
    same = 0 ## i32
    if got0 == want0
      if got1 == want1
        if got2 == want2
          if got3 == want3
            same = 1
    if same == 1
      overlap = 0 ## i32
      if x == a
        overlap = 1
      if x == b
        overlap = 1
      if y == a
        overlap = 1
      if y == b
        overlap = 1
      if overlap == 0
        if seen == wanted_ordinal
          matches[tid] = node + 1
          if wanted_ordinal > 0
            node = -1
        seen = seen + 1
    if node >= 0
      node = links[node]
  if wanted_ordinal == 0
    match_counts[tid] = seen

# The join space is intentionally large while exact fingerprint hits are
# sparse. Compact the nonzero match-count rows on Metal so the host does not
# reread every C(pool,3) row merely to discover a few candidate ordinals.
# summary[0] is the number of active queries. The host then scans only those
# compact rows to obtain the exact hit total and maximum ordinal; keeping those
# wider aggregates on the host avoids 32-bit atomic overflow in adversarial
# collision controls.
## i32[]: match_counts, active_queries, summary
@gpu fn ffrx_compact_match_counts(match_counts, active_queries, summary)
  tid = gpu.thread_position_in_grid.x ## i32
  count = match_counts[tid] ## i32
  if count > 0
    slot = gpu.atomic_fetch_add_i32(summary, 0, 1) ## i32
    active_queries[slot] = tid

use kxor
use ../rect

-> ffrx_unrank_pair(index, count, out) (i64 i64 i64[]) i64
  remaining = index ## i64
  a = 0 ## i64
  finding = 1 ## i64
  while a < count - 1 && finding == 1
    choices = count - a - 1 ## i64
    if remaining < choices
      finding = 0
    else
      remaining -= choices
      a += 1
  out[0] = a
  out[1] = a + 1 + remaining
  1

-> ffrx_unrank_triple(index, count, out) (i64 i64 i64[]) i64
  remaining = index ## i64
  a = 0 ## i64
  finding = 1 ## i64
  while a < count - 2 && finding == 1
    choices = (count - a - 1) * (count - a - 2) / 2 ## i64
    if remaining < choices
      finding = 0
    else
      remaining -= choices
      a += 1
  b = a + 1 ## i64
  finding = 1
  while b < count - 1 && finding == 1
    choices = count - b - 1
    if remaining < choices
      finding = 0
    else
      remaining -= choices
      b += 1
  out[0] = a
  out[1] = b
  out[2] = b + 1 + remaining
  1

# Preserve the square chooser's factor-affinity bias while making repeated
# passes over a rank explore different doors.  The first anchor is offset
# modulo rank. At every subsequent step, consume a different base-eight digit
# of the offset quotient to choose one of the eight best affine neighbors.
# Using one digit per step matters: reusing the same quotient modulo eight for
# every step capped the rank-25 frontier at only 163 distinct sorted subsets.
# The mixed-radix walk keeps the same affinity bias while spanning independent
# secondary choices at successive steps.
-> ffrx_choose_subset(us, vs, ws, rank, k, offset, selected) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  selected[0] = offset % rank
  count = 1 ## i64
  variant_seed = offset / rank ## i64
  variant_stride = 1 ## i64
  while count < k
    top_indices = i64[8]
    top_scores = i64[8]
    top_count = 0 ## i64
    candidate = 0 ## i64
    while candidate < rank
      if ffm_selected_index(selected, count, candidate) == 0
        score = 0 ## i64
        i = 0 ## i64
        while i < count
          other = selected[i] ## i64
          if us[candidate] == us[other]
            score += 4
          if vs[candidate] == vs[other]
            score += 4
          if ws[candidate] == ws[other]
            score += 4
          score -= ffw_popcount(us[candidate] ^ us[other])
          score -= ffw_popcount(vs[candidate] ^ vs[other])
          score -= ffw_popcount(ws[candidate] ^ ws[other])
          i += 1
        insert = 0 ## i64
        while insert < top_count
          better = 0 ## i64
          if score > top_scores[insert]
            better = 1
          if score == top_scores[insert] && candidate < top_indices[insert]
            better = 1
          if better == 1
            break
          insert += 1
        if insert < 8
          new_count = top_count + 1 ## i64
          if new_count > 8
            new_count = 8
          move = new_count - 1 ## i64
          while move > insert
            top_scores[move] = top_scores[move - 1]
            top_indices[move] = top_indices[move - 1]
            move -= 1
          top_scores[insert] = score
          top_indices[insert] = candidate
          top_count = new_count
      candidate += 1
    if top_count == 0
      return 0
    variant = ((variant_seed / variant_stride) + count * 3) % top_count ## i64
    selected[count] = top_indices[variant]
    variant_stride *= 8
    count += 1
  count

-> ffrx_sort_subset(selected, count) (i64[] i64) i64
  i = 1 ## i64
  while i < count
    value = selected[i] ## i64
    j = i ## i64
    while j > 0 && selected[j - 1] > value
      selected[j] = selected[j - 1]
      j -= 1
    selected[j] = value
    i += 1
  1

-> ffrx_subset_seen(processed, processed_count, width, selected) (i64[] i64 i64 i64[]) i64
  row = 0 ## i64
  while row < processed_count
    same = 1 ## i64
    i = 0 ## i64
    while i < width
      if processed[row * width + i] != selected[i]
        same = 0
      i += 1
    if same == 1
      return 1
    row += 1
  0

# Affinity-biased subset selection intentionally maps many offsets to the same
# sorted door.  On the rank-25 2x2x7 frontier, the old 16x retry allowance
# produced only 163 of 256 requested doors.  Selection is host-only and tiny
# beside a single cubic GPU probe, so use a wider bounded retry window rather
# than silently leaving a nominal full screen one third empty.
-> ffrx_selection_attempt_cap(subsets) (i64) i64
  subsets * 64

-> ffrx_plan_valid(n, m, p, k, subsets, pool, nearby, offset) (i64 i64 i64 i64 i64 i64 i64 i64) i64
  ffrx_plan_valid_objective(n, m, p, k, k - 1, subsets, pool, nearby, offset)

-> ffrx_plan_valid_objective(n, m, p, selected_count, replacement_count, subsets, pool, nearby, offset) (i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ok = ffr_supported(n, m, p) ## i64
  if n * m > 63 || m * p > 63 || n * p > 63
    ok = 0
  if selected_count != 5 && selected_count != 6 && selected_count != 7
    ok = 0
  if replacement_count != 3 && replacement_count != 4 && replacement_count != 5 && replacement_count != 6
    ok = 0
  if selected_count - replacement_count < 1 || selected_count - replacement_count > 2
    ok = 0
  if subsets < 1 || subsets > 256
    ok = 0
  if pool < selected_count
    ok = 0
  if replacement_count <= 5 && pool > 384
    ok = 0
  if replacement_count == 6 && pool > 192
    ok = 0
  if nearby < 0 || nearby > 8
    ok = 0
  if offset < 0
    ok = 0
  ok

-> ffrx_target_fingerprint_shape(us, vs, ws, selected, selected_count, udim, vdim, wdim, out) (i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  out[0] = 0
  out[1] = 0
  out[2] = 0
  out[3] = 0
  words = i64[4]
  i = 0 ## i64
  while i < selected_count
    source = selected[i] ## i64
    z = ffm_fingerprint_shape(us[source], vs[source], ws[source], udim, vdim, wdim, words) ## i64
    j = 0 ## i64
    while j < 4
      out[j] = out[j] ^ words[j]
      j += 1
    i += 1
  1

-> ffrx_local_exact_shape(us, vs, ws, selected, selected_count, cu, cv, cw, indices, replacement_count, udim, vdim, wdim) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  ok = 1 ## i64
  ai = 0 ## i64
  while ai < udim && ok == 1
    bi = 0 ## i64
    while bi < vdim && ok == 1
      ci = 0 ## i64
      while ci < wdim && ok == 1
        parity = 0 ## i64
        t = 0 ## i64
        while t < selected_count
          source = selected[t] ## i64
          if ((us[source] >> ai) & 1) == 1
            if ((vs[source] >> bi) & 1) == 1
              if ((ws[source] >> ci) & 1) == 1
                parity = parity ^ 1
          t += 1
        t = 0
        while t < replacement_count
          source = indices[t] ## i64
          if ((cu[source] >> ai) & 1) == 1
            if ((cv[source] >> bi) & 1) == 1
              if ((cw[source] >> ci) & 1) == 1
                parity = parity ^ 1
          t += 1
        if parity != 0
          ok = 0
        ci += 1
      bi += 1
    ai += 1
  ok

# Exact order-independent equality for logical XOR term sets.  The matched-row
# mask keeps this correct even for a synthetic multiset control; ordinary
# Metaflip schemes have already parity-cancelled duplicate terms.
-> ffrx_term_sets_equal(left_u, left_v, left_w, left_rank, right_u, right_v, right_w, right_rank) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  if left_rank != right_rank
    return 0
  matched = i64[right_rank]
  i = 0 ## i64
  while i < left_rank
    found = 0 ## i64
    j = 0 ## i64
    while j < right_rank && found == 0
      if matched[j] == 0 && left_u[i] == right_u[j] && left_v[i] == right_v[j] && left_w[i] == right_w[j]
        matched[j] = 1
        found = 1
      j += 1
    if found == 0
      return 0
    i += 1
  1

# Reject the already-explored immediate shoulder neighborhood as well as the
# literal parent.  Equal-rank logical term sets at symmetric difference <= 4
# differ by at most two removals and two additions: this includes every single
# ordinary two-term flip while leaving genuinely longer k-XOR endpoints live.
-> ffrx_term_set_distance_at_most_four(left_u, left_v, left_w, left_rank, right_u, right_v, right_w, right_rank) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  if left_rank != right_rank
    return 0
  matched = i64[right_rank]
  unmatched = 0 ## i64
  i = 0 ## i64
  while i < left_rank
    found = 0 ## i64
    j = 0 ## i64
    while j < right_rank && found == 0
      if matched[j] == 0 && left_u[i] == right_u[j] && left_v[i] == right_v[j] && left_w[i] == right_w[j]
        matched[j] = 1
        found = 1
      j += 1
    if found == 0
      unmatched += 1
      if unmatched > 2
        return 0
    i += 1
  1

# endpoint_status[0]=1 means the reconstructed endpoint is in the known
# parent's distance-four neighborhood. It is deliberately returned as a
# no-hit so the caller continues through later query rows and collision
# ordinals, looking for a rewrite beyond one ordinary flip.
-> ffrx_accept_and_dump(us, vs, ws, rank, selected, selected_count, cu, cv, cw, indices, replacement_count, n, m, p, output_path, exclude_u, exclude_v, exclude_w, exclude_rank, endpoint_status) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64[] i64 i64 i64 i64 String i64[] i64[] i64[] i64 i64[]) i64
  endpoint_status[0] = 0
  cap = ffr_default_capacity(n, m, p) ## i64
  outu = i64[cap]
  outv = i64[cap]
  outw = i64[cap]
  out_rank = 0 ## i64
  i = 0 ## i64
  while i < rank
    if ffm_selected_index(selected, selected_count, i) == 0
      outu[out_rank] = us[i]
      outv[out_rank] = vs[i]
      outw[out_rank] = ws[i]
      out_rank += 1
    i += 1
  i = 0
  while i < replacement_count && out_rank >= 0
    source = indices[i] ## i64
    out_rank = ffm_toggle_plain(outu, outv, outw, out_rank, cap, cu[source], cv[source], cw[source])
    i += 1
  if out_rank < 1 || out_rank >= rank
    return 0
  if exclude_rank > 0 && out_rank == exclude_rank
    if ffrx_term_set_distance_at_most_four(outu, outv, outw, out_rank, exclude_u, exclude_v, exclude_w, exclude_rank) == 1
      endpoint_status[0] = 1
      return 0
  candidate = i64[ffr_state_size(cap)]
  loaded = ffr_init_terms_cap(candidate, outu, outv, outw, out_rank, n, m, p, cap, 91337, 0, 1, 1, 1) ## i64
  if loaded != out_rank
    return 0
  # Keep the complete rectangular gate explicit. ffr_dump_best repeats it so
  # a certificate cannot be published on the strength of local equality or a
  # single reconstruction implementation alone.
  if ffr_verify_best_exact(candidate, n, m, p) != 1
    return 0
  dumped = ffr_dump_best(candidate, output_path) ## i64
  if dumped != out_rank
    return 0
  out_rank

# metrics:
# [0] candidates
# [1] canonical table tuples
# [2] canonical query triples
# [3] dispatched canonical query threads
# [4] hash capacity
# [5] GPU chain clear/build ms
# [6] host hash-table build ms (always zero for the chained implementation)
# [7] GPU probe ms
# [8] non-overlapping 128-bit fingerprint matches
# [9] exhaustive local checks
# [10] complete-certificate gate attempts
# [11] output rank
# [12] known-parent distance-four neighborhood exclusions
-> ffrx_gpu_subset_objective_with_scratch(device, queue, clear_pipeline, build_pipeline, probe_pipeline, probe_pair_pipeline, compact_pipeline, us, vs, ws, rank, selected, selected_count, replacement_count, cu, cv, cw, count, n, m, p, output_path, exclude_u, exclude_v, exclude_w, exclude_rank, metrics, fps0, fps1, fps2, fps3, target, heads, links, build_params, matches, match_counts, probe_params, active_queries, match_summary)
  udim = n * m ## i64
  vdim = m * p ## i64
  wdim = n * p ## i64

  words = i64[4]
  i = 0 ## i64
  while i < count
    z = ffm_fingerprint_shape(cu[i], cv[i], cw[i], udim, vdim, wdim, words) ## i64
    fps0[i] = words[0]
    fps1[i] = words[1]
    fps2[i] = words[2]
    fps3[i] = words[3]
    i += 1

  target_words = i64[4]
  z = ffrx_target_fingerprint_shape(us, vs, ws, selected, selected_count, udim, vdim, wdim, target_words) ## i64
  i = 0
  while i < 4
    target[i] = target_words[i]
    i += 1

  table_tuple_size = 2 ## i64
  entries = count * (count - 1) / 2 ## i64
  if replacement_count == 3
    table_tuple_size = 1
    entries = count
  if replacement_count == 6
    table_tuple_size = 3
    entries = count * (count - 1) * (count - 2) / 6
  query_tuple_size = 3 ## i64
  query_entries = count * (count - 1) * (count - 2) / 6 ## i64
  if replacement_count == 3 || replacement_count == 4
    query_tuple_size = 2
    query_entries = count * (count - 1) / 2
  hcap = 1 ## i64
  while hcap < entries * 3
    hcap *= 2

  build_params[0] = count
  build_params[1] = table_tuple_size
  build_params[2] = hcap - 1
  build_start = ccall("__w_clock_ms") ## i64
  metal_dispatch_n(queue, clear_pipeline, [metal_buffer_for(device, heads)], hcap)
  metal_dispatch_n(queue, build_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, heads), metal_buffer_for(device, links), metal_buffer_for(device, build_params)], entries)
  build_end = ccall("__w_clock_ms") ## i64

  probe_params[0] = count
  probe_params[1] = hcap - 1
  probe_params[2] = table_tuple_size
  probe_params[3] = 0
  match_summary[0] = 0
  probe_start = ccall("__w_clock_ms") ## i64
  if query_tuple_size == 2
    metal_dispatch_n(queue, probe_pair_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, heads), metal_buffer_for(device, links), metal_buffer_for(device, target), metal_buffer_for(device, matches), metal_buffer_for(device, match_counts), metal_buffer_for(device, probe_params)], query_entries)
  if query_tuple_size == 3
    metal_dispatch_n(queue, probe_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, heads), metal_buffer_for(device, links), metal_buffer_for(device, target), metal_buffer_for(device, matches), metal_buffer_for(device, match_counts), metal_buffer_for(device, probe_params)], query_entries)
  metal_dispatch_n(queue, compact_pipeline, [metal_buffer_for(device, match_counts), metal_buffer_for(device, active_queries), metal_buffer_for(device, match_summary)], query_entries)
  probe_end = ccall("__w_clock_ms") ## i64

  indices = i64[7]
  active_count = match_summary[0] ## i64
  fingerprint_hits = 0 ## i64
  max_matches = 0 ## i64
  active_index = 0 ## i64
  while active_index < active_count
    query_index = active_queries[active_index] ## i64
    count_here = match_counts[query_index] ## i64
    fingerprint_hits += count_here
    if count_here > max_matches
      max_matches = count_here
    active_index += 1
  local_checks = 0 ## i64
  full_checks = 0 ## i64
  excluded_endpoints = 0 ## i64
  hit_rank = 0 ## i64
  probe_rounds = 1 ## i64
  ordinal = 0 ## i64
  table_tuple = i64[3]
  query_tuple = i64[3]
  total_probe_ms = probe_end - probe_start ## i64
  while ordinal < max_matches && hit_rank == 0
    if ordinal > 0
      probe_params[3] = ordinal
      probe_start = ccall("__w_clock_ms")
      if query_tuple_size == 2
        metal_dispatch_n(queue, probe_pair_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, heads), metal_buffer_for(device, links), metal_buffer_for(device, target), metal_buffer_for(device, matches), metal_buffer_for(device, match_counts), metal_buffer_for(device, probe_params)], query_entries)
      if query_tuple_size == 3
        metal_dispatch_n(queue, probe_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, heads), metal_buffer_for(device, links), metal_buffer_for(device, target), metal_buffer_for(device, matches), metal_buffer_for(device, match_counts), metal_buffer_for(device, probe_params)], query_entries)
      probe_end = ccall("__w_clock_ms")
      total_probe_ms += probe_end - probe_start
      probe_rounds += 1
    active_index = 0 ## i64
    while active_index < active_count && hit_rank == 0
      query_index = active_queries[active_index] ## i64
      if match_counts[query_index] > ordinal
        packed_table = matches[query_index] ## i64
        if packed_table > 0
          table_index = packed_table - 1 ## i64
          if table_tuple_size == 1
            table_tuple[0] = table_index
          if table_tuple_size == 2
            z = ffrx_unrank_pair(table_index, count, table_tuple)
          if table_tuple_size == 3
            z = ffrx_unrank_triple(table_index, count, table_tuple)
          j = 0 ## i64
          while j < table_tuple_size
            indices[j] = table_tuple[j]
            j += 1
          if query_tuple_size == 2
            z = ffrx_unrank_pair(query_index, count, query_tuple)
          if query_tuple_size == 3
            z = ffrx_unrank_triple(query_index, count, query_tuple)
          j = 0
          while j < query_tuple_size
            indices[table_tuple_size + j] = query_tuple[j]
            j += 1
          local_checks += 1
          if ffrx_local_exact_shape(us, vs, ws, selected, selected_count, cu, cv, cw, indices, replacement_count, udim, vdim, wdim) == 1
            endpoint_status = i64[1]
            hit_rank = ffrx_accept_and_dump(us, vs, ws, rank, selected, selected_count, cu, cv, cw, indices, replacement_count, n, m, p, output_path, exclude_u, exclude_v, exclude_w, exclude_rank, endpoint_status)
            excluded_endpoints += endpoint_status[0]
            if endpoint_status[0] == 0
              full_checks += 1
      active_index += 1
    ordinal += 1

  metrics[0] = count
  metrics[1] = entries
  metrics[2] = query_entries
  metrics[3] = query_entries * probe_rounds
  metrics[4] = hcap
  metrics[5] = build_end - build_start
  metrics[6] = 0
  metrics[7] = total_probe_ms
  metrics[8] = fingerprint_hits
  metrics[9] = local_checks
  metrics[10] = full_checks
  metrics[11] = hit_rank
  metrics[12] = excluded_endpoints
  hit_rank

# Single-dispatch convenience wrapper used by deterministic controls. Long
# screens allocate the same arrays once in ffrx_search and call the scratch
# entry point directly, avoiding linear RSS growth.
-> ffrx_gpu_subset_objective_excluding(device, library, queue, us, vs, ws, rank, selected, selected_count, replacement_count, cu, cv, cw, count, n, m, p, output_path, exclude_u, exclude_v, exclude_w, exclude_rank, metrics)
  entries = count * (count - 1) / 2 ## i64
  if replacement_count == 3
    entries = count
  if replacement_count == 6
    entries = count * (count - 1) * (count - 2) / 6
  query_entries = count * (count - 1) * (count - 2) / 6 ## i64
  if replacement_count == 3 || replacement_count == 4
    query_entries = count * (count - 1) / 2
  hcap = 1 ## i64
  while hcap < entries * 3
    hcap *= 2
  fps0 = metal_array(32, count)
  fps1 = metal_array(32, count)
  fps2 = metal_array(32, count)
  fps3 = metal_array(32, count)
  target = metal_array(32, 4)
  heads = metal_array(32, hcap)
  links = metal_array(32, entries)
  build_params = metal_array(32, 3)
  matches = metal_array(32, query_entries)
  match_counts = metal_array(32, query_entries)
  probe_params = metal_array(32, 4)
  active_queries = metal_array(32, query_entries)
  match_summary = metal_array(32, 1)
  clear_pipeline = metal_pipeline(library, "ffrx_clear_chain_heads")
  build_pipeline = metal_pipeline(library, "ffrx_build_canonical_tuple_chains")
  probe_pipeline = metal_pipeline(library, "ffrx_probe_canonical_triples")
  probe_pair_pipeline = metal_pipeline(library, "ffrx_probe_canonical_pairs")
  compact_pipeline = metal_pipeline(library, "ffrx_compact_match_counts")
  ffrx_gpu_subset_objective_with_scratch(device, queue, clear_pipeline, build_pipeline, probe_pipeline, probe_pair_pipeline, compact_pipeline, us, vs, ws, rank, selected, selected_count, replacement_count, cu, cv, cw, count, n, m, p, output_path, exclude_u, exclude_v, exclude_w, exclude_rank, metrics, fps0, fps1, fps2, fps3, target, heads, links, build_params, matches, match_counts, probe_params, active_queries, match_summary)

-> ffrx_gpu_subset_excluding(device, library, queue, us, vs, ws, rank, selected, k, cu, cv, cw, count, n, m, p, output_path, exclude_u, exclude_v, exclude_w, exclude_rank, metrics)
  ffrx_gpu_subset_objective_excluding(device, library, queue, us, vs, ws, rank, selected, k, k - 1, cu, cv, cw, count, n, m, p, output_path, exclude_u, exclude_v, exclude_w, exclude_rank, metrics)

-> ffrx_gpu_subset(device, library, queue, us, vs, ws, rank, selected, k, cu, cv, cw, count, n, m, p, output_path, metrics)
  no_exclusion = i64[1]
  ffrx_gpu_subset_excluding(device, library, queue, us, vs, ws, rank, selected, k, cu, cv, cw, count, n, m, p, output_path, no_exclusion, no_exclusion, no_exclusion, 0, metrics)

-> ffrx_load_exact(seed_path, n, m, p, k)
  cap = ffr_default_capacity(n, m, p) ## i64
  state = i64[ffr_state_size(cap)]
  rank = ffr_load_scheme_cap(state, seed_path, n, m, p, cap, 91601 + k, 0, 1, 1, 1) ## i64
  if rank < k
    return nil
  if ffr_verify_best_exact(state, n, m, p) != 1
    return nil
  state

-> ffrx_dump_plain_exact(us, vs, ws, rank, n, m, p, output_path) (i64[] i64[] i64[] i64 i64 i64 i64 String) i64
  cap = ffr_default_capacity(n, m, p) ## i64
  state = i64[ffr_state_size(cap)]
  loaded = ffr_init_terms_cap(state, us, vs, ws, rank, n, m, p, cap, 91731, 0, 1, 1, 1) ## i64
  if loaded != rank || ffr_verify_best_exact(state, n, m, p) != 1
    return 0
  ffr_dump_best(state, output_path)

# Materialize the exact R endpoint hidden inside an artificial R+1 split
# shoulder. The two children must agree on two factors and differ on exactly
# one; their XOR on that factor is the unique trivial parent term.
-> ffrx_materialize_merged_parent(seed_path, output_path, n, m, p, left, right) (String String i64 i64 i64 i64 i64) i64
  state = ffrx_load_exact(seed_path, n, m, p, 2)
  if state == nil
    return 0
  rank = ffr_best_rank(state) ## i64
  if left < 0 || right < 0 || left >= rank || right >= rank || left == right
    return 0
  cap = ffr_default_capacity(n, m, p) ## i64
  us = i64[cap]
  vs = i64[cap]
  ws = i64[cap]
  if ffw_export_best(state, us, vs, ws) != rank
    return 0
  merged_u = 0 ## i64
  merged_v = 0 ## i64
  merged_w = 0 ## i64
  if us[left] != us[right] && vs[left] == vs[right] && ws[left] == ws[right]
    merged_u = us[left] ^ us[right]
    merged_v = vs[left]
    merged_w = ws[left]
  if us[left] == us[right] && vs[left] != vs[right] && ws[left] == ws[right]
    merged_u = us[left]
    merged_v = vs[left] ^ vs[right]
    merged_w = ws[left]
  if us[left] == us[right] && vs[left] == vs[right] && ws[left] != ws[right]
    merged_u = us[left]
    merged_v = vs[left]
    merged_w = ws[left] ^ ws[right]
  if merged_u == 0 || merged_v == 0 || merged_w == 0
    return 0
  out_u = i64[cap]
  out_v = i64[cap]
  out_w = i64[cap]
  out_rank = 0 ## i64
  i = 0 ## i64
  while i < rank
    if i != left && i != right
      out_u[out_rank] = us[i]
      out_v[out_rank] = vs[i]
      out_w[out_rank] = ws[i]
      out_rank += 1
    i += 1
  out_rank = ffm_toggle_plain(out_u, out_v, out_w, out_rank, cap, merged_u, merged_v, merged_w)
  if out_rank != rank - 1
    return 0
  ffrx_dump_plain_exact(out_u, out_v, out_w, out_rank, n, m, p, output_path)

# Create an exact artificial R+1 shoulder in /tmp for an endpoint compiler.
# `first` is one nonzero XOR part of the chosen factor; the complementary part
# is derived from the parent so no caller-supplied tensor claim is trusted.
-> ffrx_materialize_split_shoulder(parent_path, output_path, n, m, p, term_index, axis, first) (String String i64 i64 i64 i64 i64 i64) i64
  state = ffrx_load_exact(parent_path, n, m, p, 2)
  if state == nil
    return 0
  rank = ffr_best_rank(state) ## i64
  if term_index < 0 || term_index >= rank || axis < 0 || axis > 2 || first <= 0
    return 0
  cap = ffr_default_capacity(n, m, p) ## i64
  us = i64[cap]
  vs = i64[cap]
  ws = i64[cap]
  if ffw_export_best(state, us, vs, ws) != rank
    return 0
  factor = us[term_index] ## i64
  if axis == 1
    factor = vs[term_index]
  if axis == 2
    factor = ws[term_index]
  second = factor ^ first ## i64
  if second <= 0
    return 0
  out_u = i64[cap]
  out_v = i64[cap]
  out_w = i64[cap]
  out_rank = 0 ## i64
  i = 0 ## i64
  while i < rank
    if i != term_index
      out_u[out_rank] = us[i]
      out_v[out_rank] = vs[i]
      out_w[out_rank] = ws[i]
      out_rank += 1
    i += 1
  child_u = us[term_index] ## i64
  child_v = vs[term_index] ## i64
  child_w = ws[term_index] ## i64
  if axis == 0
    child_u = first
  if axis == 1
    child_v = first
  if axis == 2
    child_w = first
  out_rank = ffm_toggle_plain(out_u, out_v, out_w, out_rank, cap, child_u, child_v, child_w)
  child_u = us[term_index]
  child_v = vs[term_index]
  child_w = ws[term_index]
  if axis == 0
    child_u = second
  if axis == 1
    child_v = second
  if axis == 2
    child_w = second
  out_rank = ffm_toggle_plain(out_u, out_v, out_w, out_rank, cap, child_u, child_v, child_w)
  if out_rank != rank + 1
    return 0
  ffrx_dump_plain_exact(out_u, out_v, out_w, out_rank, n, m, p, output_path)

-> ffrx_search(seed_path, output_path, n, m, p, k, subsets, pool, nearby, offset, metal_path, metallib_path = "", exclude_path = "", replacement_count = 0)
  if replacement_count == 0
    replacement_count = k - 1
  if ffrx_plan_valid_objective(n, m, p, k, replacement_count, subsets, pool, nearby, offset) == 0
    return 0 - 1
  if seed_path == output_path
    return 0 - 3
  if exclude_path != "" && exclude_path == output_path
    return 0 - 8
  cleared = write_file(output_path, "")
  if cleared == false
    return 0 - 4
  state = ffrx_load_exact(seed_path, n, m, p, k)
  if state == nil
    return 0 - 2

  rank = ffr_best_rank(state) ## i64
  cap = ffr_default_capacity(n, m, p) ## i64
  us = i64[cap]
  vs = i64[cap]
  ws = i64[cap]
  exported = ffw_export_best(state, us, vs, ws) ## i64
  if exported != rank
    return 0 - 5

  exclude_u = i64[cap]
  exclude_v = i64[cap]
  exclude_w = i64[cap]
  exclude_rank = 0 ## i64
  if exclude_path != ""
    exclude_state = ffrx_load_exact(exclude_path, n, m, p, k)
    if exclude_state == nil
      return 0 - 9
    exclude_rank = ffw_export_best(exclude_state, exclude_u, exclude_v, exclude_w)
    if exclude_rank < 1
      return 0 - 9

  device = metal_device()
  library = nil
  if metallib_path != ""
    library = metal_load_library(device, metallib_path)
  if library == nil
    msl = read_file(metal_path)
    if msl == nil || msl.size() == 0
      return 0 - 6
    library = metal_compile_source(device, msl)
  queue = metal_queue(device)
  scratch_entries = pool * (pool - 1) / 2 ## i64
  if replacement_count == 3
    scratch_entries = pool
  if replacement_count == 6
    scratch_entries = pool * (pool - 1) * (pool - 2) / 6
  scratch_queries = pool * (pool - 1) * (pool - 2) / 6 ## i64
  if replacement_count == 3 || replacement_count == 4
    scratch_queries = pool * (pool - 1) / 2
  scratch_hcap = 1 ## i64
  while scratch_hcap < scratch_entries * 3
    scratch_hcap *= 2
  scratch_fps0 = metal_array(32, pool)
  scratch_fps1 = metal_array(32, pool)
  scratch_fps2 = metal_array(32, pool)
  scratch_fps3 = metal_array(32, pool)
  scratch_target = metal_array(32, 4)
  scratch_heads = metal_array(32, scratch_hcap)
  scratch_next = metal_array(32, scratch_entries)
  scratch_build_params = metal_array(32, 3)
  scratch_matches = metal_array(32, scratch_queries)
  scratch_match_counts = metal_array(32, scratch_queries)
  scratch_probe_params = metal_array(32, 4)
  scratch_active_queries = metal_array(32, scratch_queries)
  scratch_match_summary = metal_array(32, 1)
  clear_pipeline = metal_pipeline(library, "ffrx_clear_chain_heads")
  build_pipeline = metal_pipeline(library, "ffrx_build_canonical_tuple_chains")
  probe_pipeline = metal_pipeline(library, "ffrx_probe_canonical_triples")
  probe_pair_pipeline = metal_pipeline(library, "ffrx_probe_canonical_pairs")
  compact_pipeline = metal_pipeline(library, "ffrx_compact_match_counts")

  << "GPU_RECT_KXOR_START tensor=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " rank=" + rank.to_s() + " objective=" + k.to_s() + "to" + replacement_count.to_s() + " subsets=" + subsets.to_s() + " pool=" + pool.to_s() + " nearby=" + nearby.to_s() + " offset=" + offset.to_s()
  tested = 0 ## i64
  total_candidates = 0 ## i64
  total_table_entries = 0 ## i64
  total_query_entries = 0 ## i64
  total_query_threads = 0 ## i64
  total_build_ms = 0 ## i64
  total_host_table_ms = 0 ## i64
  total_probe_ms = 0 ## i64
  total_fp_hits = 0 ## i64
  total_local_checks = 0 ## i64
  total_full_checks = 0 ## i64
  total_excluded_endpoints = 0 ## i64
  hit_rank = 0 ## i64
  wall_start = ccall("__w_clock_ms") ## i64
  processed = i64[subsets * k]
  selection_attempts = 0 ## i64
  attempt_cap = ffrx_selection_attempt_cap(subsets) ## i64
  while tested < subsets && selection_attempts < attempt_cap && hit_rank == 0
    selected = i64[7]
    chosen = ffrx_choose_subset(us, vs, ws, rank, k, offset + selection_attempts * 17, selected) ## i64
    if chosen == k
      z = ffrx_sort_subset(selected, k) ## i64
      if ffrx_subset_seen(processed, tested, k, selected) == 0
        j = 0 ## i64
        while j < k
          processed[tested * k + j] = selected[j]
          j += 1
        cu = i64[pool]
        cv = i64[pool]
        cw = i64[pool]
        count = ffx_candidates(us, vs, ws, rank, selected, k, pool, nearby, cu, cv, cw) ## i64
        metrics = i64[13]
        hit_rank = ffrx_gpu_subset_objective_with_scratch(device, queue, clear_pipeline, build_pipeline, probe_pipeline, probe_pair_pipeline, compact_pipeline, us, vs, ws, rank, selected, k, replacement_count, cu, cv, cw, count, n, m, p, output_path, exclude_u, exclude_v, exclude_w, exclude_rank, metrics, scratch_fps0, scratch_fps1, scratch_fps2, scratch_fps3, scratch_target, scratch_heads, scratch_next, scratch_build_params, scratch_matches, scratch_match_counts, scratch_probe_params, scratch_active_queries, scratch_match_summary) ## i64
        tested += 1
        total_candidates += metrics[0]
        total_table_entries += metrics[1]
        total_query_entries += metrics[2]
        total_query_threads += metrics[3]
        total_build_ms += metrics[5]
        total_host_table_ms += metrics[6]
        total_probe_ms += metrics[7]
        total_fp_hits += metrics[8]
        total_local_checks += metrics[9]
        total_full_checks += metrics[10]
        total_excluded_endpoints += metrics[12]
        indices_text = selected[0].to_s() ## String
        j = 1
        while j < k
          indices_text = indices_text + "," + selected[j].to_s()
          j += 1
        << "GPU_RECT_KXOR_SUBSET ordinal=" + tested.to_s() + " indices=" + indices_text + " candidates=" + count.to_s() + " table_tuples=" + metrics[1].to_s() + " query_tuples=" + metrics[2].to_s() + " fingerprint_hits=" + metrics[8].to_s() + " local_checks=" + metrics[9].to_s() + " excluded_endpoints=" + metrics[12].to_s() + " full_checks=" + metrics[10].to_s() + " hit_rank=" + hit_rank.to_s()
    selection_attempts += 1
  wall_end = ccall("__w_clock_ms") ## i64
  hit = 0 ## i64
  if hit_rank > 0
    hit = 1
  << "GPU_RECT_KXOR_RESULT tensor=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " rank=" + rank.to_s() + " selected=" + k.to_s() + " replacement=" + replacement_count.to_s() + " objective=" + k.to_s() + "to" + replacement_count.to_s() + " tested=" + tested.to_s() + " unique_subsets=" + tested.to_s() + " selection_attempts=" + selection_attempts.to_s() + " candidates=" + total_candidates.to_s() + " table_tuples=" + total_table_entries.to_s() + " query_tuples=" + total_query_entries.to_s() + " gpu_threads=" + total_query_threads.to_s() + " build_ms=" + total_build_ms.to_s() + " host_table_ms=" + total_host_table_ms.to_s() + " probe_ms=" + total_probe_ms.to_s() + " wall_ms=" + (wall_end - wall_start).to_s() + " fingerprint_hits=" + total_fp_hits.to_s() + " local_checks=" + total_local_checks.to_s() + " excluded_endpoints=" + total_excluded_endpoints.to_s() + " full_checks=" + total_full_checks.to_s() + " hit=" + hit.to_s() + " output_rank=" + hit_rank.to_s()
  hit

# Deterministic one-subset entry point for positive controls and endpoint-first
# experiments.  This is intentionally not exposed through the production
# scheduler: it exists so a real-frontier no-hit cannot conceal a broken join.
-> ffrx_search_exact_subset(seed_path, output_path, n, m, p, k, pool, nearby, selected, metal_path, metallib_path = "", exclude_path = "", replacement_count = 0)
  if replacement_count == 0
    replacement_count = k - 1
  if ffrx_plan_valid_objective(n, m, p, k, replacement_count, 1, pool, nearby, 0) == 0
    return 0 - 1
  if seed_path == output_path
    return 0 - 3
  if exclude_path != "" && exclude_path == output_path
    return 0 - 8
  state = ffrx_load_exact(seed_path, n, m, p, k)
  if state == nil
    return 0 - 2
  rank = ffr_best_rank(state) ## i64
  valid = 1 ## i64
  i = 0 ## i64
  while i < k
    if selected[i] < 0 || selected[i] >= rank
      valid = 0
    j = 0 ## i64
    while j < i
      if selected[j] == selected[i]
        valid = 0
      j += 1
    i += 1
  if valid == 0
    return 0 - 7
  cleared = write_file(output_path, "")
  if cleared == false
    return 0 - 4

  cap = ffr_default_capacity(n, m, p) ## i64
  us = i64[cap]
  vs = i64[cap]
  ws = i64[cap]
  exported = ffw_export_best(state, us, vs, ws) ## i64
  if exported != rank
    return 0 - 5
  exclude_u = i64[cap]
  exclude_v = i64[cap]
  exclude_w = i64[cap]
  exclude_rank = 0 ## i64
  if exclude_path != ""
    exclude_state = ffrx_load_exact(exclude_path, n, m, p, k)
    if exclude_state == nil
      return 0 - 9
    exclude_rank = ffw_export_best(exclude_state, exclude_u, exclude_v, exclude_w)
    if exclude_rank < 1
      return 0 - 9
  device = metal_device()
  library = nil
  if metallib_path != ""
    library = metal_load_library(device, metallib_path)
  if library == nil
    msl = read_file(metal_path)
    if msl == nil || msl.size() == 0
      return 0 - 6
    library = metal_compile_source(device, msl)
  queue = metal_queue(device)
  cu = i64[pool]
  cv = i64[pool]
  cw = i64[pool]
  count = ffx_candidates(us, vs, ws, rank, selected, k, pool, nearby, cu, cv, cw) ## i64
  metrics = i64[13]
  hit_rank = ffrx_gpu_subset_objective_excluding(device, library, queue, us, vs, ws, rank, selected, k, replacement_count, cu, cv, cw, count, n, m, p, output_path, exclude_u, exclude_v, exclude_w, exclude_rank, metrics) ## i64
  << "GPU_RECT_KXOR_CONTROL tensor=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " rank=" + rank.to_s() + " objective=" + k.to_s() + "to" + replacement_count.to_s() + " candidates=" + count.to_s() + " table_tuples=" + metrics[1].to_s() + " query_tuples=" + metrics[2].to_s() + " fingerprint_hits=" + metrics[8].to_s() + " local_checks=" + metrics[9].to_s() + " excluded_endpoints=" + metrics[12].to_s() + " full_checks=" + metrics[10].to_s() + " output_rank=" + hit_rank.to_s()
  hit_rank

# Exact rank-debt ladder search for FlipFleet.
#
# This is a standalone controller experiment.  It deliberately does not alter
# the production pool: two independently measured +1 factor splits open an
# exact R+2 shoulder, after which every admitted edge is rank-neutral or
# rank-decreasing.  Exact one-opener reversals and the original term set are
# blocked.  Complete n^6 reconstruction gates every admitted state.
#
# The closing alphabet reuses the existing exact implementations:
#   * direct 2->1 factor-line closure (the reverse of `ffe_split_with_part`),
#   * complete 3->2 and 4->3 factor-span refactors,
#   * complete 3->3 neutral span refactors, and
#   * rank-neutral low-rank absorbed shears.
#
# The production GPU 5->4 through 9->8 joins can consume these same R+2 seeds
# if the bounded experiment earns a pool slot; they are intentionally not
# launched by this pure-Tungsten host reference.
#
# telemetry[0..23]:
#   0 opener attempts             1 exact R+2 openers
#   2 non-+2/debt opener rejects  3 complete tensor gates
#   4 closing searches/proposals  5 admitted closing states
#   6 rank-increase rejects       7 one-opener reversal rejects
#   8 exact-origin rejects        9 duplicate/no-op rejects
#  10 exact-gate failures        11 frontier returns (rank == origin)
#  12 novel frontier returns     13 strict improvements
#  14 neutral states admitted    15 reducing states admitted
#  16 direct-merge searches      17 span 3->2 searches
#  18 span 4->3 searches         19 span 3->3 searches
#  20 absorbed-shear searches    21 best admitted rank
#  22 best raw term distance     23 opened rank ceiling

use metaflip_worker
use flipfleet_escape
use flipfleet_span_refactor
use flipfleet_low_rank_shear_search
use flipfleet_tunnel_catalyst

-> ffrl_stats_init(stats, origin_rank) (i64[] i64) i64
  i = 0 ## i64
  while i < 32
    stats[i] = 0
    i += 1
  stats[21] = origin_rank + 3
  stats[23] = origin_rank + 2
  1

-> ffrl_axis_value(us, vs, ws, position, axis) (i64[] i64[] i64[] i64 i64) i64
  value = us[position] ## i64
  if axis == 1
    value = vs[position]
  if axis == 2
    value = ws[position]
  value

-> ffrl_term_at(st, position, term) (i64[] i64 i64[]) i64
  if ffw_valid(st) != 1 || position < 0 || position >= st[6]
    return 0
  slot = st[st[50] + position] ## i64
  term[0] = st[st[44] + slot]
  term[1] = st[st[45] + slot]
  term[2] = st[st[46] + slot]
  1

-> ffrl_find_term(us, vs, ws, rank, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  found = 0 - 1 ## i64
  i = 0 ## i64
  while i < rank && found < 0
    if us[i] == u && vs[i] == v && ws[i] == w
      found = i
    i += 1
  found

-> ffrl_clone_state(source, target, seed) (i64[] i64[] i64) i64
  if ffw_valid(source) != 1
    return 0
  capacity = source[4] ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_current(source, us, vs, ws) ## i64
  loaded = ffw_init_terms_cap(target, us, vs, ws, rank, source[2], capacity, seed, 0, 1, 1, 1) ## i64
  if loaded == rank && ffw_verify_current_exact(target, source[2]) == 1
    return rank
  0

-> ffrl_common_terms(left, right) (i64[] i64[]) i64
  if ffw_valid(left) != 1 || ffw_valid(right) != 1
    return 0
  lcap = left[4] ## i64
  rcap = right[4] ## i64
  lu = i64[lcap]
  lv = i64[lcap]
  lw = i64[lcap]
  ru = i64[rcap]
  rv = i64[rcap]
  rw = i64[rcap]
  lrank = ffw_export_current(left, lu, lv, lw) ## i64
  rrank = ffw_export_current(right, ru, rv, rw) ## i64
  common = 0 ## i64
  i = 0 ## i64
  while i < lrank
    if ffrl_find_term(ru, rv, rw, rrank, lu[i], lv[i], lw[i]) >= 0
      common += 1
    i += 1
  common

-> ffrl_distance(left, right) (i64[] i64[]) i64
  left[6] + right[6] - 2 * ffrl_common_terms(left, right)

-> ffrl_same_state(left, right) (i64[] i64[]) i64
  if left[6] != right[6]
    return 0
  if ffrl_common_terms(left, right) == left[6]
    return 1
  0

-> ffrl_choose_part(us, vs, ws, rank, source, axis, ordinal) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  if rank < 2 || source < 0 || source >= rank || axis < 0 || axis > 2
    return 0
  old = ffrl_axis_value(us, vs, ws, source, axis) ## i64
  step = 0 ## i64
  while step < rank
    candidate_index = (source + 1 + ordinal + step) % rank ## i64
    candidate = ffrl_axis_value(us, vs, ws, candidate_index, axis) ## i64
    if candidate != 0 && candidate != old
      return candidate
    step += 1
  0

# Store parent,left,right triples for one exact factor split.
-> ffrl_split_identity(u, v, w, axis, part, identities, offset) (i64 i64 i64 i64 i64 i64[] i64) i64
  if part == 0 || axis < 0 || axis > 2
    return 0
  old = u ## i64
  if axis == 1
    old = v
  if axis == 2
    old = w
  if part == old
    return 0
  identities[offset] = u
  identities[offset + 1] = v
  identities[offset + 2] = w
  identities[offset + 3] = u
  identities[offset + 4] = v
  identities[offset + 5] = w
  identities[offset + 6] = u
  identities[offset + 7] = v
  identities[offset + 8] = w
  if axis == 0
    identities[offset + 3] = part
    identities[offset + 6] = old ^ part
  if axis == 1
    identities[offset + 4] = part
    identities[offset + 7] = old ^ part
  if axis == 2
    identities[offset + 5] = part
    identities[offset + 8] = old ^ part
  if identities[offset + 6] == 0 || identities[offset + 7] == 0 || identities[offset + 8] == 0
    return 0
  1

# Open exactly two measured +1 identities.  Source positions refer to the
# origin view, so the second source is relocated after the first toggle.
# meta: origin rank, rank after split 1, final rank, actual debt, exact gate,
#       first eligible, second eligible, accepted +2.
-> ffrl_open2(origin, source0, axis0, part0, source1, axis1, part1, out_state, identities, meta) (i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < 8
    meta[i] = 0
    i += 1
  if ffw_valid(origin) != 1 || source0 < 0 || source1 < 0 || source0 >= origin[6] || source1 >= origin[6] || source0 == source1
    return 0
  n = origin[2] ## i64
  if ffw_verify_current_exact(origin, n) != 1
    return 0
  capacity = origin[4] ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  base_rank = ffw_export_current(origin, us, vs, ws) ## i64
  meta[0] = base_rank
  second_u = us[source1] ## i64
  second_v = vs[source1] ## i64
  second_w = ws[source1] ## i64
  if ffrl_split_identity(us[source0], vs[source0], ws[source0], axis0, part0, identities, 0) == 0
    return 0
  split_meta = i64[8]
  rank1 = ffe_split_with_part(us, vs, ws, base_rank, capacity, source0, axis0, part0, split_meta) ## i64
  meta[1] = rank1
  meta[5] = split_meta[7]
  meta[3] = rank1 - base_rank
  if split_meta[7] != 1 || rank1 != base_rank + 1
    return 0
  relocated = ffrl_find_term(us, vs, ws, rank1, second_u, second_v, second_w) ## i64
  if relocated < 0
    return 0
  if ffrl_split_identity(second_u, second_v, second_w, axis1, part1, identities, 9) == 0
    return 0
  split_meta2 = i64[8]
  rank2 = ffe_split_with_part(us, vs, ws, rank1, capacity, relocated, axis1, part1, split_meta2) ## i64
  meta[2] = rank2
  meta[6] = split_meta2[7]
  meta[3] = rank2 - base_rank
  if split_meta2[7] != 1 || rank2 != base_rank + 2
    return 0
  loaded = ffw_init_terms_cap(out_state, us, vs, ws, rank2, n, capacity, 51001 + source0 * 17 + source1, 0, 1, 1, 1) ## i64
  if loaded == rank2 && ffw_verify_current_exact(out_state, n) == 1
    meta[4] = 1
    meta[7] = 1
    return rank2
  0

# Toggle one recorded zero identity into `opened`.  In the intended R+2
# construction this produces the exact R+1 state that merely reverses one of
# the two openers; those two states remain forbidden throughout closure.
-> ffrl_make_forbidden(opened, identities, offset, out_state, seed) (i64[] i64[] i64 i64[] i64) i64
  rank = ffrl_clone_state(opened, out_state, seed) ## i64
  if rank < 1
    return 0
  i = 0 ## i64
  while i < 3
    base = offset + i * 3 ## i64
    rank = ffw_toggle(out_state, identities[base], identities[base + 1], identities[base + 2], rank)
    i += 1
  out_state[6] = rank
  if rank == opened[6] - 1 && ffw_verify_current_exact(out_state, opened[2]) == 1
    return rank
  0

-> ffrl_selected_valid(selected, count, rank) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if selected[i] < 0 || selected[i] >= rank
      return 0
    j = i + 1 ## i64
    while j < count
      if selected[i] == selected[j]
        return 0
      j += 1
    i += 1
  1

# Generic exact local splice used for direct 2->1 closure.  Span and shear
# moves use their stricter existing apply helper below.
-> ffrl_apply_replacement(parent, selected, selected_count, out_u, out_v, out_w, out_count, candidate, seed) (i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64) i64
  if ffw_valid(parent) != 1 || ffrl_selected_valid(selected, selected_count, parent[6]) == 0
    return 0
  local_u = i64[4]
  local_v = i64[4]
  local_w = i64[4]
  i = 0 ## i64
  while i < selected_count
    term = i64[3]
    if ffrl_term_at(parent, selected[i], term) == 0
      return 0
    local_u[i] = term[0]
    local_v[i] = term[1]
    local_w[i] = term[2]
    i += 1
  if fftc_local_exact(local_u, local_v, local_w, selected_count, out_u, out_v, out_w, out_count) != 1
    return 0
  rank = ffrl_clone_state(parent, candidate, seed) ## i64
  if rank < 1
    return 0
  i = 0
  while i < selected_count
    rank = ffw_toggle(candidate, local_u[i], local_v[i], local_w[i], rank)
    i += 1
  i = 0
  while i < out_count
    if out_u[i] == 0 || out_v[i] == 0 || out_w[i] == 0
      return 0
    rank = ffw_toggle(candidate, out_u[i], out_v[i], out_w[i], rank)
    i += 1
  candidate[6] = rank
  expected = parent[6] - selected_count + out_count ## i64
  if rank != expected
    return 0
  if ffw_verify_current_exact(candidate, parent[2]) != 1
    return 0
  rank

-> ffrl_record_endpoint(origin, candidate, stats) (i64[] i64[] i64[]) i64
  rank = candidate[6] ## i64
  distance = ffrl_distance(origin, candidate) ## i64
  if rank == origin[6]
    stats[11] = stats[11] + 1
    if distance > 0
      stats[12] = stats[12] + 1
  if rank < origin[6]
    stats[13] = stats[13] + 1
  if rank < stats[21] || (rank == stats[21] && distance > stats[22])
    stats[21] = rank
    stats[22] = distance
  rank

# Complete admission policy for the closing phase.  This function is public so
# planted tests can prove each safety boundary independently.
-> ffrl_admit_candidate(origin, opened, parent, candidate, forbidden0, forbidden1, stats) (i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  stats[3] = stats[3] + 1
  if ffw_valid(candidate) != 1 || ffw_verify_current_exact(candidate, origin[2]) != 1
    stats[10] = stats[10] + 1
    return 0
  if candidate[6] > parent[6] || candidate[6] > opened[6]
    stats[6] = stats[6] + 1
    return 0
  if ffrl_same_state(parent, candidate) == 1
    stats[9] = stats[9] + 1
    return 0
  if ffrl_same_state(origin, candidate) == 1
    stats[8] = stats[8] + 1
    return 0
  if ffrl_same_state(forbidden0, candidate) == 1 || ffrl_same_state(forbidden1, candidate) == 1
    stats[7] = stats[7] + 1
    return 0
  stats[5] = stats[5] + 1
  if candidate[6] == parent[6]
    stats[14] = stats[14] + 1
  if candidate[6] < parent[6]
    stats[15] = stats[15] + 1
  z = ffrl_record_endpoint(origin, candidate, stats) ## i64
  1

-> ffrl_state_in(states, candidate) i64
  i = 0 ## i64
  while i < states.size()
    if ffrl_same_state(states[i], candidate) == 1
      return 1
    i += 1
  0

-> ffrl_better(origin, left, right) (i64[] i64[] i64[]) i64
  if left[6] < right[6]
    return 1
  if left[6] == right[6]
    if ffrl_distance(origin, left) > ffrl_distance(origin, right)
      return 1
  0

-> ffrl_beam_add(states, candidate, width, origin, stats) i64
  if ffrl_state_in(states, candidate) == 1
    stats[9] = stats[9] + 1
    return 0
  if states.size() < width
    states.push(candidate)
    return 1
  worst = 0 ## i64
  i = 1 ## i64
  while i < states.size()
    if ffrl_better(origin, states[worst], states[i]) == 1
      worst = i
    i += 1
  if ffrl_better(origin, candidate, states[worst]) == 1
    states[worst] = candidate
    return 1
  0

-> ffrl_offer(origin, opened, parent, candidate, forbidden0, forbidden1, beam, winners, beam_width, stats) i64
  if ffrl_admit_candidate(origin, opened, parent, candidate, forbidden0, forbidden1, stats) == 0
    return 0
  added = ffrl_beam_add(beam, candidate, beam_width, origin, stats) ## i64
  if candidate[6] <= origin[6]
    z = ffrl_beam_add(winners, candidate, beam_width, origin, stats) ## i64
  added

# Deterministic local-neighborhood selector, matching the production k-XOR
# preference for shared factors and nearby masks without importing Metal into
# this standalone reference.
-> ffrl_choose_subset(st, count, offset, selected) (i64[] i64 i64 i64[]) i64
  rank = st[6] ## i64
  if count < 1 || count > 4 || rank < count
    return 0
  capacity = st[4] ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  z = ffw_export_current(st, us, vs, ws) ## i64
  selected[0] = offset % rank
  made = 1 ## i64
  while made < count
    best = 0 - 1 ## i64
    best_score = 0 - 1000000000 ## i64
    candidate = 0 ## i64
    while candidate < rank
      used = 0 ## i64
      i = 0 ## i64
      while i < made
        if selected[i] == candidate
          used = 1
        i += 1
      if used == 0
        score = 0 ## i64
        i = 0
        while i < made
          other = selected[i] ## i64
          if us[candidate] == us[other]
            score += 128
          if vs[candidate] == vs[other]
            score += 128
          if ws[candidate] == ws[other]
            score += 128
          score -= ffw_popcount(us[candidate] ^ us[other])
          score -= ffw_popcount(vs[candidate] ^ vs[other])
          score -= ffw_popcount(ws[candidate] ^ ws[other])
          i += 1
        if score > best_score
          best_score = score
          best = candidate
      candidate += 1
    if best < 0
      return 0
    selected[made] = best
    made += 1
  made

-> ffrl_generate_merges(parent, origin, opened, forbidden0, forbidden1, budget, beam_width, beam, winners, stats, seed_base) i64
  if budget < 1
    return 0
  capacity = parent[4] ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_current(parent, us, vs, ws) ## i64
  proposals = 0 ## i64
  added = 0 ## i64
  left = 0 ## i64
  while left < rank && proposals < budget
    right = left + 1 ## i64
    while right < rank && proposals < budget
      out_u = i64[1]
      out_v = i64[1]
      out_w = i64[1]
      compatible = 0 ## i64
      if vs[left] == vs[right] && ws[left] == ws[right]
        out_u[0] = us[left] ^ us[right]
        out_v[0] = vs[left]
        out_w[0] = ws[left]
        compatible = 1
      if us[left] == us[right] && ws[left] == ws[right]
        out_u[0] = us[left]
        out_v[0] = vs[left] ^ vs[right]
        out_w[0] = ws[left]
        compatible = 1
      if us[left] == us[right] && vs[left] == vs[right]
        out_u[0] = us[left]
        out_v[0] = vs[left]
        out_w[0] = ws[left] ^ ws[right]
        compatible = 1
      if compatible == 1 && out_u[0] != 0 && out_v[0] != 0 && out_w[0] != 0
        proposals += 1
        stats[4] = stats[4] + 1
        stats[16] = stats[16] + 1
        selected = i64[2]
        selected[0] = left
        selected[1] = right
        candidate = i64[ffw_state_size(parent[4])]
        made = ffrl_apply_replacement(parent, selected, 2, out_u, out_v, out_w, 1, candidate, seed_base + proposals) ## i64
        if made > 0
          added += ffrl_offer(origin, opened, parent, candidate, forbidden0, forbidden1, beam, winners, beam_width, stats)
      right += 1
    left += 1
  added

-> ffrl_generate_span(parent, origin, opened, forbidden0, forbidden1, k, want, budget, kind_slot, offset_base, beam_width, beam, winners, stats, seed_base) i64
  added = 0 ## i64
  attempt = 0 ## i64
  while attempt < budget
    stats[4] = stats[4] + 1
    stats[kind_slot] = stats[kind_slot] + 1
    selected = i64[4]
    chosen = ffrl_choose_subset(parent, k, offset_base + attempt * 17, selected) ## i64
    if chosen == k
      out_u = i64[4]
      out_v = i64[4]
      out_w = i64[4]
      meta = i64[12]
      found = ffsr_find_current(parent, selected, k, want, out_u, out_v, out_w, meta) ## i64
      if found == want
        candidate = i64[ffw_state_size(parent[4])]
        copied = ffrl_clone_state(parent, candidate, seed_base + attempt) ## i64
        if copied == parent[6]
          made = ffsr_apply_current(candidate, selected, k, out_u, out_v, out_w, found) ## i64
          if made > 0
            added += ffrl_offer(origin, opened, parent, candidate, forbidden0, forbidden1, beam, winners, beam_width, stats)
          if made <= 0
            stats[10] = stats[10] + 1
    attempt += 1
  added

-> ffrl_generate_shears(parent, origin, opened, forbidden0, forbidden1, budget, offset_base, beam_width, beam, winners, stats, seed_base) i64
  if budget < 1
    return 0
  capacity = parent[4] ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_current(parent, us, vs, ws) ## i64
  added = 0 ## i64
  attempt = 0 ## i64
  while attempt < budget
    stats[4] = stats[4] + 1
    stats[20] = stats[20] + 1
    selected = i64[4]
    out_u = i64[4]
    out_v = i64[4]
    out_w = i64[4]
    meta = i64[8]
    made = fflrs_find_pair_absorb(us, vs, ws, rank, offset_base + attempt, selected, out_u, out_v, out_w, meta) ## i64
    if made == 3 || made == 4
      candidate = i64[ffw_state_size(parent[4])]
      copied = ffrl_clone_state(parent, candidate, seed_base + attempt) ## i64
      if copied == rank
        applied = ffsr_apply_current(candidate, selected, made, out_u, out_v, out_w, made) ## i64
        if applied == rank
          added += ffrl_offer(origin, opened, parent, candidate, forbidden0, forbidden1, beam, winners, beam_width, stats)
        if applied != rank
          stats[10] = stats[10] + 1
    attempt += 1
  added

# Deterministic opener schedule shared by the CPU reference and the optional
# GPU k-XOR benchmark.  Keeping this public makes the two closure engines race
# exactly the same measured R+2 seeds.
-> ffrl_open_trial_k2(origin, trial, opened, identities, meta) (i64[] i64 i64[] i64[] i64[]) i64
  if ffw_valid(origin) != 1 || origin[6] < 2
    return 0
  capacity = origin[4] ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_current(origin, us, vs, ws) ## i64
  source0 = (trial * 13 + trial / 3) % rank ## i64
  source1 = (trial * 29 + 7) % rank ## i64
  if source1 == source0
    source1 = (source1 + 1) % rank
  axis0 = trial % 3 ## i64
  axis1 = ((trial / 3) + 1) % 3 ## i64
  part0 = ffrl_choose_part(us, vs, ws, rank, source0, axis0, trial / 9) ## i64
  part1 = ffrl_choose_part(us, vs, ws, rank, source1, axis1, trial / 5 + 1) ## i64
  ffrl_open2(origin, source0, axis0, part0, source1, axis1, part1, opened, identities, meta)

# Run a bounded k=2 ladder.  Neutral refactors/shears are admitted only at the
# first closure depth; later depths must reduce rank.  Returns the best strict
# improvement or novel frontier-return rank, or zero if the ladder never pays
# back all debt without returning to the exact origin.
-> ffrl_run_k2(origin, opener_budget, max_depth, beam_width, merge_budget, span3_budget, span4_budget, neutral_budget, shear_budget, out_best, stats) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[]) i64
  if ffw_valid(origin) != 1 || opener_budget < 1 || max_depth < 1 || beam_width < 1
    return 0
  if ffw_verify_current_exact(origin, origin[2]) != 1
    return 0
  z = ffrl_stats_init(stats, origin[6]) ## i64
  capacity = origin[4] ## i64
  origin_rank = origin[6] ## i64
  winners = []
  trial = 0 ## i64
  while trial < opener_budget
    stats[0] = stats[0] + 1
    opened = i64[ffw_state_size(capacity)]
    identities = i64[18]
    open_meta = i64[8]
    opened_rank = ffrl_open_trial_k2(origin, trial, opened, identities, open_meta) ## i64
    stats[3] = stats[3] + 1
    if opened_rank == origin_rank + 2 && open_meta[3] == 2 && open_meta[4] == 1
      stats[1] = stats[1] + 1
      forbidden0 = i64[ffw_state_size(capacity)]
      forbidden1 = i64[ffw_state_size(capacity)]
      rank0 = ffrl_make_forbidden(opened, identities, 0, forbidden0, 52001 + trial * 2) ## i64
      rank1 = ffrl_make_forbidden(opened, identities, 9, forbidden1, 52002 + trial * 2) ## i64
      if rank0 == origin_rank + 1 && rank1 == origin_rank + 1
        frontier = []
        frontier.push(opened)
        depth = 0 ## i64
        while depth < max_depth && frontier.size() > 0
          next_states = []
          fi = 0 ## i64
          while fi < frontier.size()
            parent = frontier[fi]
            base = 60000 + trial * 10000 + depth * 1000 + fi * 100 ## i64
            z = ffrl_generate_merges(parent, origin, opened, forbidden0, forbidden1, merge_budget, beam_width, next_states, winners, stats, base) ## i64
            z = ffrl_generate_span(parent, origin, opened, forbidden0, forbidden1, 3, 2, span3_budget, 17, trial * 31 + depth * 7, beam_width, next_states, winners, stats, base + 100)
            z = ffrl_generate_span(parent, origin, opened, forbidden0, forbidden1, 4, 3, span4_budget, 18, trial * 37 + depth * 11, beam_width, next_states, winners, stats, base + 200)
            if depth == 0
              z = ffrl_generate_span(parent, origin, opened, forbidden0, forbidden1, 3, 3, neutral_budget, 19, trial * 41, beam_width, next_states, winners, stats, base + 300)
              z = ffrl_generate_shears(parent, origin, opened, forbidden0, forbidden1, shear_budget, trial * 43, beam_width, next_states, winners, stats, base + 400)
            fi += 1
          frontier = next_states
          depth += 1
    if opened_rank != origin_rank + 2 || open_meta[3] != 2 || open_meta[4] != 1
      stats[2] = stats[2] + 1
    trial += 1
  if winners.size() < 1
    return 0
  best = 0 ## i64
  i = 1 ## i64
  while i < winners.size()
    if ffrl_better(origin, winners[i], winners[best]) == 1
      best = i
    i += 1
  copied = ffrl_clone_state(winners[best], out_best, 99001) ## i64
  if copied == winners[best][6] && copied <= origin_rank && ffw_verify_current_exact(out_best, origin[2]) == 1
    return copied
  0

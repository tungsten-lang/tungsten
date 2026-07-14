# Additive escape-bank construction from every exact same-rank frontier.
#
# The native coordinator historically rebuilt near1/near2 from the density
# leader only.  This helper deliberately never clears a bank: callers first
# build the leader family, then append families derived from the other exact
# frontier seeds.  The ordinary structural-signature quota and max-min
# replacement policy remain authoritative, so adding more source basins does
# not make the shoulder banks unbounded.

use metaflip_worker
use flipfleet_escape
use flipfleet_bank_policy

# Construct one exact algebraic escape.  Exactness of the source is checked by
# fffeb_append_source before this helper is reached; ffe_apply then preserves
# the represented tensor by construction.
-> fffeb_escape_state(source, kind, nonce, n, capacity, state_size, seed, dslack, cycles, workq, wanderq)
  result = nil
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_best(source, us, vs, ws) ## i64
  if rank > 0
    meta = i64[8]
    escaped = ffe_apply(us, vs, ws, rank, capacity, n, kind, nonce, meta) ## i64
    if escaped > 0 && meta[7] == 1
      candidate = i64[state_size]
      loaded = ffw_init_terms_cap(candidate, us, vs, ws, escaped, n, capacity, seed, dslack, cycles, workq, wanderq) ## i64
      if loaded == escaped
        result = candidate
  result

# Append all generic escape kinds for one source frontier.  Return the number
# of states admitted after capacity, structural-family, duplicate, and max-min
# diversity filtering.
#
# counters: considered sources, eligible sources, constructed escapes,
#           near1 admissions, near2 admissions, rejected sources.
-> fffeb_append_source(source, leader_rank, source_key, n, capacity, state_size, dslack, cycles, workq, wanderq, nonces_per_kind, near1, near1_signatures, near1_uses, near1_successes, near1_capacity, near2, near2_signatures, near2_uses, near2_successes, near2_capacity, signature_quota, min_distance, near_counters, counters) i64
  counters[0] = counters[0] + 1
  if source == nil
    counters[5] = counters[5] + 1
    return 0
  if ffw_best_rank(source) != leader_rank
    counters[5] = counters[5] + 1
    return 0
  if ffw_verify_best_exact(source, n) == 0
    counters[5] = counters[5] + 1
    return 0

  count = nonces_per_kind ## i64
  if count < 1
    count = 1
  if count > 64
    count = 64
  counters[1] = counters[1] + 1
  admitted = 0 ## i64
  kind = 1 ## i64
  while kind <= 5
    nonce = 0 ## i64
    while nonce < count
      seed = 70001 + source_key * 4099 + kind * 97 + nonce ## i64
      candidate = fffeb_escape_state(source, kind, nonce, n, capacity, state_size, seed, dslack, cycles, workq, wanderq)
      if candidate != nil
        counters[2] = counters[2] + 1
        rank = ffw_best_rank(candidate) ## i64
        if rank == leader_rank + 1
          if ffbp_near_add(near1, near1_signatures, near1_uses, near1_successes, candidate, near1_capacity, signature_quota, min_distance, near_counters) == 1
            counters[3] = counters[3] + 1
            admitted += 1
        if rank == leader_rank + 2
          if ffbp_near_add(near2, near2_signatures, near2_uses, near2_successes, candidate, near2_capacity, signature_quota, min_distance, near_counters) == 1
            counters[4] = counters[4] + 1
            admitted += 1
      nonce += 1
    kind += 1
  admitted

# Load and exact-gate every configured frontier path, accepting only schemes at
# the live leader rank.  Existing near1/near2 entries and their replay metadata
# are preserved.  One admission count is appended per input path so focused
# tests and optional telemetry can prove which source families contributed.
-> fffeb_append_frontier_paths(repo_root, paths, leader, n, capacity, state_size, dslack, cycles, workq, wanderq, nonces_per_kind, near1, near1_signatures, near1_uses, near1_successes, near1_capacity, near2, near2_signatures, near2_uses, near2_successes, near2_capacity, signature_quota, min_distance, near_counters, source_admissions, counters) i64
  leader_rank = ffw_best_rank(leader) ## i64
  total = 0 ## i64
  index = 0 ## i64
  while index < paths.size()
    state = i64[state_size]
    path = repo_root + "/" + paths[index]
    rank = ffw_load_scheme_cap(state, path, n, capacity, 60013 + index * 131, dslack, cycles, workq, wanderq) ## i64
    admitted = 0 ## i64
    if rank > 0
      admitted = fffeb_append_source(state, leader_rank, index, n, capacity, state_size, dslack, cycles, workq, wanderq, nonces_per_kind, near1, near1_signatures, near1_uses, near1_successes, near1_capacity, near2, near2_signatures, near2_uses, near2_successes, near2_capacity, signature_quota, min_distance, near_counters, counters)
    if rank <= 0
      counters[0] = counters[0] + 1
      counters[5] = counters[5] + 1
    source_admissions.push(admitted)
    total += admitted
    index += 1
  total

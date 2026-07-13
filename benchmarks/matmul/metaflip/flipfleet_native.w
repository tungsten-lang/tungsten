# Pure-Tungsten FlipFleet coordinator.
#
# This is the authoritative in-process CPU coordinator.  It owns sticky
# islands, variable-rank exact escape banks, exact adoption, durable status,
# and the native TUI.  Dimension-specialized Metal engines attach through the
# native GPU policy module; there is no Python in the campaign runtime.

use core/system
use metaflip_worker
use flipfleet_escape
use flipfleet_bank_policy
use flipfleet_profiles
use flipfleet_tui
use flipfleet_gpu_policy
use flipfleet_kernel_pool
use flipfleet_map_elites
use flipfleet_rank_debt
use flipfleet_gpu_bundle
use flipfleet_c3_bundle
use flipfleet_simd_bundle

-> ffn_parse_tensor(text) (String) i64
  normalized = text.downcase
  parts = normalized.split("x")
  n = 0 ## i64
  if parts.size() == 2
    left = parts[0].to_i() ## i64
    right = parts[1].to_i() ## i64
    if left == right
      n = left
  n

-> ffn_parse_scaled_moves(text) (String) i64
  normalized = text.strip().downcase
  factor = 1 ## i64
  number = normalized
  if normalized.ends_with?("k")
    factor = 1000
    number = normalized.slice(0, normalized.size() - 1)
  if normalized.ends_with?("m")
    factor = 1000000
    number = normalized.slice(0, normalized.size() - 1)
  if normalized.ends_with?("b")
    factor = 1000000000
    number = normalized.slice(0, normalized.size() - 1)
  parts = number.split(".")
  if parts.size() < 1 || parts.size() > 2
    return 0 - 1
  whole = parts[0].to_i() ## i64
  if whole < 0
    return 0 - 1
  value = whole * factor ## i64
  if parts.size() == 2
    fraction_text = parts[1]
    if fraction_text.size() < 1 || fraction_text.size() > 3
      return 0 - 1
    denominator = 1 ## i64
    i = 0 ## i64
    while i < fraction_text.size()
      denominator *= 10
      i += 1
    fraction = fraction_text.to_i() ## i64
    value += fraction * factor / denominator
  if value < 1
    return 0 - 1
  value

-> ffn_parse_move_portfolio(text, output) (String i64[]) i64
  parts = text.split(",")
  if parts.size() != 4
    return 0
  i = 0 ## i64
  while i < 4
    value = ffn_parse_scaled_moves(parts[i]) ## i64
    if value < 1
      return 0
    output[i] = value
    i += 1
  1

-> ffn_better(rank, bits, best_rank, best_bits) (i64 i64 i64 i64) i64
  better = 0 ## i64
  if rank < best_rank
    better = 1
  if rank == best_rank
    if bits < best_bits
      better = 1
  better

-> ffn_gpu_retry_delay(failure_count) (i64) i64
  delay = 2 ## i64
  count = failure_count ## i64
  if count > 5
    count = 5
  i = 1 ## i64
  while i < count
    delay *= 2
    i += 1
  delay

# Locate the repository independently of the fleet's launch directory.  GPU
# workers compile checked-in Tungsten sources and the default record seeds are
# repository assets, so treating `.` as the repository root silently selected
# naive seeds and made every retry run `bin/tungsten` from the wrong directory.
-> ffn_repo_marker(root) (String) i64
  marker = read_file(root + "/benchmarks/matmul/metaflip/flipfleet.w")
  if marker != nil
    compiler_ok = system("test -x " + ffg_shell_quote(root + "/bin/tungsten"))
    if compiler_ok
      return 1
  0

-> ffn_discover_repo_root(configured) (String)
  if configured != ""
    if ffn_repo_marker(configured) == 1
      return configured
    return ""
  candidate = capture("pwd").strip()
  depth = 0 ## i64
  while depth < 12
    if ffn_repo_marker(candidate) == 1
      return candidate
    candidate = candidate + "/.."
    depth += 1
  ""

-> ffn_clone_exact(src, n, capacity, state_size, seed, dslack, cycles, workq, wanderq) (i64[] i64 i64 i64 i64 i64 i64 i64 i64)
  out = nil
  if ffw_verify_best_exact(src, n) == 1
    candidate = i64[state_size]
    loaded = ffw_reseed_from(candidate, src, seed) ## i64
    if loaded > 0
      candidate[17] = dslack
      candidate[15] = cycles
      candidate[18] = workq
      candidate[19] = wanderq
      candidate[14] = candidate[13] + workq
      out = candidate
  out

# Clone a state that has already crossed the coordinator's exhaustive gate.
# ffw_reseed_from copies only algebraic bests and deliberately does not repeat
# n^6 reconstruction; use this only after an explicit exact check or from an
# existing exact bank.
-> ffn_clone_trusted(src, state_size, seed) (i64[] i64 i64)
  out = nil
  candidate = i64[state_size]
  loaded = ffw_reseed_from(candidate, src, seed) ## i64
  if loaded > 0
    out = candidate
  out

-> ffn_atomic_write(path, body, run_tag) (String String String) i64
  tmp = path + ".tmp." + run_tag
  wrote = write_file(tmp, body)
  result = 0 ## i64
  if wrote
    moved = ccall("__w_rename", tmp, path)
    if moved
      result = 1
  result

-> ffn_dump_trusted(state, path, run_tag) (i64[] String String) i64
  rank = ffw_best_rank(state) ## i64
  body = rank.to_s() + "\n"
  i = 0 ## i64
  while i < rank
    body = body + ffw_read_best_u(state, i).to_s() + " " + ffw_read_best_v(state, i).to_s() + " " + ffw_read_best_w(state, i).to_s() + "\n"
    i += 1
  stored = ffn_atomic_write(path, body, run_tag) ## i64
  if stored == 1
    return rank
  0 - 1

-> ffn_escape_state(src, kind, nonce, n, capacity, state_size, seed, dslack, cycles, workq, wanderq, require_c3)
  out = nil
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_best(src, us, vs, ws) ## i64
  if rank > 0
    meta = i64[8]
    escaped = ffe_apply(us, vs, ws, rank, capacity, n, kind, nonce, meta) ## i64
    eligible = meta[7] ## i64
    if escaped <= 0
      eligible = 0
    if require_c3 != 0
      if eligible == 1
        if ffe_is_c3(us, vs, ws, escaped, n) == 0
          eligible = 0
    if eligible == 1
      candidate = i64[state_size]
      loaded = ffw_init_terms_cap(candidate, us, vs, ws, escaped, n, capacity, seed, dslack, cycles, workq, wanderq) ## i64
      if loaded == escaped
        out = candidate
  out

-> ffn_term_in(state, u, v, w) (i64[] i64 i64 i64) i64
  found = 0 ## i64
  rank = ffw_best_rank(state) ## i64
  i = 0 ## i64
  while i < rank
    if ffw_read_best_u(state, i) == u
      if ffw_read_best_v(state, i) == v
        if ffw_read_best_w(state, i) == w
          found = 1
          i = rank
        else
          i += 1
      else
        i += 1
    else
      i += 1
  found

-> ffn_distance(a, b) (i64[] i64[]) i64
  arank = ffw_best_rank(a) ## i64
  brank = ffw_best_rank(b) ## i64
  common = 0 ## i64
  i = 0 ## i64
  while i < arank
    common += ffn_term_in(b, ffw_read_best_u(a, i), ffw_read_best_v(a, i), ffw_read_best_w(a, i))
    i += 1
  arank + brank - common - common

-> ffn_current_term_in(state, u, v, w) (i64[] i64 i64 i64) i64
  found = 0 ## i64
  rank = ffw_current_rank(state) ## i64
  i = 0 ## i64
  while i < rank
    if ffw_read_current_u(state, i) == u && ffw_read_current_v(state, i) == v && ffw_read_current_w(state, i) == w
      found = 1
      i = rank
    else
      i += 1
  found

# Raw term-set distance between two live working states. Unlike the personal
# best rank shown historically by the TUI, this distinguishes active basins.
-> ffn_current_distance(left, right) (i64[] i64[]) i64
  left_rank = ffw_current_rank(left) ## i64
  right_rank = ffw_current_rank(right) ## i64
  common = 0 ## i64
  i = 0 ## i64
  while i < left_rank
    common += ffn_current_term_in(right, ffw_read_current_u(left, i), ffw_read_current_v(left, i), ffw_read_current_w(left, i))
    i += 1
  left_rank + right_rank - common - common

-> ffn_current_to_best_distance(state, best) (i64[] i64[]) i64
  current_rank = ffw_current_rank(state) ## i64
  best_rank = ffw_best_rank(best) ## i64
  common = 0 ## i64
  i = 0 ## i64
  while i < current_rank
    common += ffn_term_in(best, ffw_read_current_u(state, i), ffw_read_current_v(state, i), ffw_read_current_w(state, i))
    i += 1
  current_rank + best_rank - common - common

-> ffn_best_to_current_distance(candidate, active) (i64[] i64[]) i64
  candidate_rank = ffw_best_rank(candidate) ## i64
  active_rank = ffw_current_rank(active) ## i64
  common = 0 ## i64
  i = 0 ## i64
  while i < candidate_rank
    common += ffn_current_term_in(active, ffw_read_best_u(candidate, i), ffw_read_best_v(candidate, i), ffw_read_best_w(candidate, i))
    i += 1
  candidate_rank + active_rank - common - common

# Order-independent digest of the live term set. It is telemetry and a seed
# selection aid, never an exactness or equality proof.
-> ffn_current_basin_id(state) (i64[]) i64
  modulus = 2147483647 ## i64
  sum = 0 ## i64
  squares = 0 ## i64
  rank = ffw_current_rank(state) ## i64
  i = 0 ## i64
  while i < rank
    term = (ffw_read_current_u(state, i) % modulus) * 1009 + (ffw_read_current_v(state, i) % modulus) ## i64
    term = (term % modulus) * 9176 + (ffw_read_current_w(state, i) % modulus)
    term = term % modulus
    sum = (sum + term) % modulus
    squares = (squares + (term * term) % modulus) % modulus
    i += 1
  ((sum * 65537) % modulus + squares + rank * 8191) % modulus

# stats: unique live digests, minimum pair distance, states exactly on the
# fleet leader term set, mean distance from the fleet leader.
-> ffn_active_basin_stats(states, best, stats)
  count = states.size() ## i64
  unique = 0 ## i64
  on_leader = 0 ## i64
  distance_sum = 0 ## i64
  min_distance = 0 - 1 ## i64
  if count > 1
    min_distance = 999999999
  i = 0 ## i64
  while i < count
    seen = 0 ## i64
    j = 0 ## i64
    while j < i
      pair_distance = ffn_current_distance(states[i], states[j]) ## i64
      if pair_distance < min_distance
        min_distance = pair_distance
      if pair_distance == 0
        seen = 1
      j += 1
    if seen == 0
      unique += 1
    distance = ffn_current_to_best_distance(states[i], best) ## i64
    if distance == 0
      on_leader += 1
    distance_sum += distance
    i += 1
  stats[0] = unique
  stats[1] = min_distance
  stats[2] = on_leader
  stats[3] = 0
  if count > 0
    stats[3] = distance_sum / count
  unique

-> ffn_seed_min_active_distance(candidate, active) i64
  if active.size() == 0
    return 999999999
  minimum = 999999999 ## i64
  compared = 0 ## i64
  i = 0 ## i64
  while i < active.size()
    distance = ffn_best_to_current_distance(candidate, active[i]) ## i64
    if distance < minimum
      minimum = distance
    compared += 1
    i += 1
  if compared == 0
    return 999999999
  minimum

# Least-used first, max-min distance second. At startup every use count ties,
# so this explicitly keeps different doors from selecting the same basin.
-> ffn_select_diverse_seed(pool, uses, active, stable_key) i64
  if pool == nil || pool.size() == 0
    return 0 - 1
  start = stable_key % pool.size() ## i64
  best_index = 0 - 1 ## i64
  best_uses = 999999999 ## i64
  best_distance = 0 - 1 ## i64
  offset = 0 ## i64
  while offset < pool.size()
    index = (start + offset) % pool.size() ## i64
    use_count = 0 ## i64
    if uses != nil && index < uses.size()
      use_count = uses[index]
    distance = ffn_seed_min_active_distance(pool[index], active) ## i64
    if use_count < best_uses || (use_count == best_uses && distance > best_distance)
      best_index = index
      best_uses = use_count
      best_distance = distance
    offset += 1
  if best_index >= 0 && uses != nil && best_index < uses.size()
    uses[best_index] = uses[best_index] + 1
  best_index

-> ffn_clone_current_exact(src, n, capacity, state_size, seed, dslack, cycles, workq, wanderq)
  rank = ffw_current_rank(src) ## i64
  if rank < 1
    return nil
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  exported = ffw_export_current(src, us, vs, ws) ## i64
  if exported != rank
    return nil
  candidate = i64[state_size]
  loaded = ffw_init_terms_cap(candidate, us, vs, ws, rank, n, capacity, seed, dslack, cycles, workq, wanderq) ## i64
  if loaded != rank || ffw_verify_best_exact(candidate, n) != 1
    return nil
  candidate

-> ffn_state_is_c3(state, n, capacity) (i64[] i64 i64) i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_best(state, us, vs, ws) ## i64
  result = 0 ## i64
  if rank > 0
    result = ffe_is_c3(us, vs, ws, rank, n)
  result

-> ffn_replacement_min_distance(items, replace, candidate)
  result = 0 - 1 ## i64
  if items.size() > 1
    result = 999999999
    i = 0 ## i64
    while i < items.size()
      left = items[i]
      if i == replace
        left = candidate
      j = i + 1 ## i64
      while j < items.size()
        right = items[j]
        if j == replace
          right = candidate
        d = ffn_distance(left, right) ## i64
        if d < result
          result = d
        j += 1
      i += 1
  result

-> ffn_archive_add(archive, candidate, capacity, min_distance, counters)
  accepted = 0 ## i64
  duplicate = 0 ## i64
  closest = 999999999 ## i64
  i = 0 ## i64
  while i < archive.size()
    distance = ffn_distance(archive[i], candidate) ## i64
    if distance == 0
      duplicate = 1
    if distance < closest
      closest = distance
    i += 1
  if archive.size() == 0
    closest = 999999999
  if duplicate == 0
    if closest >= min_distance
      if archive.size() < capacity
        archive.push(candidate)
        counters[0] = counters[0] + 1
        accepted = 1
      if archive.size() >= capacity
        if accepted == 0
          current_min = ffn_archive_min_distance(archive) ## i64
          replace = 0 - 1 ## i64
          best_min = current_min ## i64
          i = 0
          while i < archive.size()
            trial_min = ffn_replacement_min_distance(archive, i, candidate) ## i64
            if trial_min > best_min
              best_min = trial_min
              replace = i
            i += 1
          if replace >= 0
            archive[replace] = candidate
            counters[1] = counters[1] + 1
            counters[0] = counters[0] + 1
            accepted = 1
  if accepted == 0
    counters[2] = counters[2] + 1
  accepted

-> ffn_archive_min_distance(archive)
  result = 0 - 1 ## i64
  if archive.size() > 1
    result = 999999999
    i = 0 ## i64
    while i < archive.size()
      j = i + 1 ## i64
      while j < archive.size()
        d = ffn_distance(archive[i], archive[j]) ## i64
        if d < result
          result = d
        j += 1
      i += 1
  result

-> ffn_bank_add(bank, candidate, capacity, min_distance)
  accepted = 0 ## i64
  closest = 999999999 ## i64
  i = 0 ## i64
  while i < bank.size()
    d = ffn_distance(bank[i], candidate) ## i64
    if d < closest
      closest = d
    i += 1
  if closest >= min_distance
    if bank.size() < capacity
      bank.push(candidate)
      accepted = 1
    if bank.size() >= capacity && accepted == 0
      current_min = ffn_archive_min_distance(bank) ## i64
      replace = 0 - 1 ## i64
      best_min = current_min ## i64
      i = 0
      while i < bank.size()
        trial_min = ffn_replacement_min_distance(bank, i, candidate) ## i64
        if trial_min > best_min
          best_min = trial_min
          replace = i
        i += 1
      if replace >= 0
        bank[replace] = candidate
        accepted = 1
  accepted

-> ffn_build_escape_banks(base, n, capacity, state_size, dslack, cycles, near1, near2, near1_signatures, near1_uses, near1_successes, near2_signatures, near2_uses, near2_successes, symmetry, mixed, orbit_bank, polar_bank, near1_capacity, near2_capacity, signature_quota, symmetry_capacity, near_counters)
  near1.clear
  near2.clear
  near1_signatures.clear
  near1_uses.clear
  near1_successes.clear
  near2_signatures.clear
  near2_uses.clear
  near2_successes.clear
  symmetry.clear
  mixed.clear
  orbit_bank.clear
  polar_bank.clear
  base_rank = ffw_best_rank(base) ## i64
  kind = 1 ## i64
  while kind <= 5
    nonce = 0 ## i64
    while nonce < 6
      c = ffn_escape_state(base, kind, nonce, n, capacity, state_size, 1009 + kind * 97 + nonce, dslack, cycles, ffp_work_moves(n, 1), ffp_wander_moves(n, 1), 0)
      if c != nil
        rank = ffw_best_rank(c) ## i64
        z = ffn_bank_add(mixed, c, 32, 2) ## i64
        if rank == base_rank + 1
          z = ffbp_near_add(near1, near1_signatures, near1_uses, near1_successes, c, near1_capacity, signature_quota, 2, near_counters)
        if rank == base_rank + 2
          z = ffbp_near_add(near2, near2_signatures, near2_uses, near2_successes, c, near2_capacity, signature_quota, 2, near_counters)
      if kind == 3 || kind == 4
        s = ffn_escape_state(base, kind, nonce, n, capacity, state_size, 4001 + kind * 97 + nonce, dslack, cycles, ffp_work_moves(n, 1), ffp_wander_moves(n, 1), 1)
        if s != nil
          z = ffn_bank_add(symmetry, s, symmetry_capacity, 2)
          if kind == 3
            z = ffn_bank_add(orbit_bank, s, 8, 2)
          if kind == 4
            z = ffn_bank_add(polar_bank, s, 8, 2)
      nonce += 1
    kind += 1
  mixed.size()

# Add a separately retained C3 component without disturbing the generic banks.
# The base and every derived state are already exact-gated by the loader or the
# escape constructor; the explicit C3 checks keep the three algebraic GPU roles
# from silently falling back to an asymmetric component after a fleet drop.
-> ffn_add_c3_family(base, n, capacity, state_size, dslack, cycles, workq, wanderq, symmetry, orbit_bank, polar_bank, symmetry_capacity)
  added = 0 ## i64
  if base != nil
    if ffn_state_is_c3(base, n, capacity) == 1
      if ffn_bank_add(symmetry, base, symmetry_capacity, 2) == 1
        added += 1
      kind = 3 ## i64
      while kind <= 4
        nonce = 0 ## i64
        while nonce < 6
          escaped = ffn_escape_state(base, kind, nonce, n, capacity, state_size, 5003 + kind * 71 + nonce, dslack, cycles, workq, wanderq, 1)
          if escaped != nil
            if ffn_bank_add(symmetry, escaped, symmetry_capacity, 2) == 1
              added += 1
            if kind == 3
              z = ffn_bank_add(orbit_bank, escaped, 8, 2) ## i64
            if kind == 4
              z = ffn_bank_add(polar_bank, escaped, 8, 2) ## i64
          nonce += 1
        kind += 1
  added

-> ffn_pick_seed(door, best, anchor, archive, near1, near2, near1_uses, near2_uses, symmetry, mixed, active, cursor, stable_key)
  chosen = best
  pool = nil
  uses = nil
  seed_door = ffp_seed_door(door) ## i64
  if seed_door == 1
    pool = archive
  if seed_door == 2
    pool = near1
    uses = near1_uses
  if seed_door == 3
    pool = near2
    uses = near2_uses
  if seed_door == 4
    pool = symmetry
  if seed_door == 5
    pool = mixed
  if seed_door == 6
    chosen = anchor
  if pool != nil
    if pool.size() > 0
      index = ffn_select_diverse_seed(pool, uses, active, stable_key + cursor[seed_door]) ## i64
      if index >= 0
        chosen = pool[index]
      cursor[seed_door] = cursor[seed_door] + 1
  chosen

-> ffn_door_has_native_seed(door, archive, near1, near2, symmetry, mixed)
  available = 1 ## i64
  seed_door = ffp_seed_door(door) ## i64
  if seed_door == 1
    if archive.size() == 0
      available = 0
  if seed_door == 2
    if near1.size() == 0
      available = 0
  if seed_door == 3
    if near2.size() == 0
      available = 0
  if seed_door == 4
    if symmetry.size() == 0
      available = 0
  if seed_door == 5
    if mixed.size() == 0
      available = 0
  available

-> ffn_gpu_role_seed(role, epoch, best, archive, near1, near2, mixed, c3_base, orbit_bank, polar_bank, pareto_states, pareto_bits, pareto_pairs, pareto_novelties, pareto_uses, n, capacity, state_size, dslack, cycles, workq, wanderq)
  seed = best
  # Keep the frontier-specific density/split roles on the record, but do not
  # make every independent GPU engine knock on that same door at startup.
  # These banks contain exact rank+1/rank+2 algebraic escapes with distinct
  # structural signatures and are rebuilt whenever the frontier drops.
  if role == 0
    if near2.size() > 0
      seed = near2[epoch % near2.size()]
    if near2.size() == 0 && near1.size() > 0
      seed = near1[epoch % near1.size()]
  if role == 2 || role == 4 || role == 5 || role == 6 || role == 7
    seed = nil
  if role == 4
    break_base = c3_base
    if break_base == nil
      break_base = best
    escaped = ffn_escape_state(break_base, 2, epoch, n, capacity, state_size, 31001 + epoch * 17, dslack, cycles, workq, wanderq, 0)
    if escaped != nil
      seed = escaped
  if role == 2
    if c3_base != nil
      seed = c3_base
  if role == 5
    if orbit_bank.size() > 0
      seed = orbit_bank[epoch % orbit_bank.size()]
  if role == 6
    if polar_bank.size() > 0
      seed = polar_bank[epoch % polar_bank.size()]
  if role == 7
    escaped = ffn_escape_state(best, 5, epoch, n, capacity, state_size, 33001 + epoch * 19, dslack, cycles, workq, wanderq, 0)
    if escaped != nil
      seed = escaped
  if role == 8
    pareto_index = ffbp_pareto_select(pareto_states, pareto_bits, pareto_pairs, pareto_novelties, pareto_uses, epoch) ## i64
    if pareto_index >= 0
      seed = pareto_states[pareto_index]
    if pareto_index < 0 && mixed.size() > 0
      seed = mixed[epoch % mixed.size()]
    if pareto_index < 0 && mixed.size() == 0 && archive.size() > 0
      seed = archive[epoch % archive.size()]
  if role == 9
    if near1.size() > 0
      seed = near1[epoch % near1.size()]
    if near1.size() == 0 && mixed.size() > 0
      seed = mixed[epoch % mixed.size()]
  seed

-> ffn_core_fringe_state(best, archive, near1, near2, mixed, n, capacity, state_size, seed, dslack, cycles, workq, wanderq, core_out)
  rank = ffw_best_rank(best) ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  z = ffw_export_best(best, us, vs, ws) ## i64
  if z != rank
    return nil
  support = i64[rank]
  i = 0 ## i64
  while i < rank
    support[i] = 1
    bank = 0 ## i64
    while bank < 4
      pool = archive
      if bank == 1
        pool = near1
      if bank == 2
        pool = near2
      if bank == 3
        pool = mixed
      p = 0 ## i64
      while p < pool.size()
        support[i] = support[i] + ffbp_term_in(pool[p], us[i], vs[i], ws[i])
        p += 1
      bank += 1
    i += 1
  # Stable descending support order: consensus terms receive low slot IDs and
  # are therefore protected by ffw_walk_fringe.
  i = 1
  while i < rank
    su = us[i] ## i64
    sv = vs[i] ## i64
    sw = ws[i] ## i64
    ss = support[i] ## i64
    j = i ## i64
    while j > 0 && support[j - 1] < ss
      us[j] = us[j - 1]
      vs[j] = vs[j - 1]
      ws[j] = ws[j - 1]
      support[j] = support[j - 1]
      j -= 1
    us[j] = su
    vs[j] = sv
    ws[j] = sw
    support[j] = ss
    i += 1
  fringe = n * n ## i64
  if fringe < 8
    fringe = 8
  core = rank - fringe ## i64
  if core < 0
    core = 0
  core_out[0] = core
  candidate = i64[state_size]
  loaded = ffw_init_terms_cap(candidate, us, vs, ws, rank, n, capacity, seed, dslack, cycles, workq, wanderq) ## i64
  if loaded != rank || ffw_verify_best_exact(candidate, n) != 1
    return nil
  candidate

# Separate spawn helpers keep ordinary and core/fringe timing explicit and give
# each worker one unique elapsed-time slot.  Tungsten snapshots the array and
# scalar captures correctly; spec/core/thread_loop_capture_spec.w protects that
# contract for loop-created threads.
-> ffn_spawn_cpu_walk(state, steps, elapsed_ms, slot) (i64[] i64 i64[] i64)
  Thread.new ->
    t0 = ccall("__w_clock_ms") ## i64
    result = ffw_walk(state, steps) ## i64
    elapsed_ms[slot] = ccall("__w_clock_ms") - t0
    result

-> ffn_spawn_cpu_fringe(state, steps, core_slots, elapsed_ms, slot) (i64[] i64 i64 i64[] i64)
  Thread.new ->
    t0 = ccall("__w_clock_ms") ## i64
    result = ffw_walk_fringe(state, steps, core_slots) ## i64
    elapsed_ms[slot] = ccall("__w_clock_ms") - t0
    result

-> ffn_pool_seed(mode, epoch, best, map_states, map_uses, c3_base, orbit_bank, polar_bank, n, capacity, state_size, dslack, cycles, workq, wanderq)
  seed = best
  if mode == 1 || mode == 2 || mode == 3 || mode == 4
    picked = ffme_select(map_states, map_uses, epoch) ## i64
    if picked >= 0
      seed = map_states[picked]
  if mode == 4
    lifted = ffkp_lifted_state(seed, n, capacity, state_size, epoch, dslack, cycles, workq, wanderq)
    if lifted != nil
      seed = lifted
  if mode == 7
    break_base = c3_base
    if break_base == nil
      break_base = best
    escaped = ffn_escape_state(break_base, 2, epoch, n, capacity, state_size, 61001 + epoch * 17, dslack, cycles, workq, wanderq, 0)
    if escaped != nil
      seed = escaped
  if mode == 8 && orbit_bank.size() > 0
    seed = orbit_bank[epoch % orbit_bank.size()]
  if mode == 9 && polar_bank.size() > 0
    seed = polar_bank[epoch % polar_bank.size()]
  if mode == 10
    escaped = ffn_escape_state(best, 5, epoch, n, capacity, state_size, 63001 + epoch * 19, dslack, cycles, workq, wanderq, 0)
    if escaped != nil
      seed = escaped
  seed

-> ffn_fill_pool_readiness(ready, generic_ready, mitm_ready, constraint_ready, kxor_ready, orbit_bank, polar_bank)
  mode = 0 ## i64
  while mode < ffkp_mode_count()
    ready[mode] = 0
    mode += 1
  ready[0] = constraint_ready
  ready[1] = mitm_ready
  ready[2] = kxor_ready
  ready[3] = kxor_ready
  ready[4] = generic_ready
  ready[5] = constraint_ready
  ready[6] = constraint_ready
  ready[7] = generic_ready
  if generic_ready != 0 && orbit_bank.size() > 0
    ready[8] = 1
  if generic_ready != 0 && polar_bank.size() > 0
    ready[9] = 1
  ready[10] = generic_ready
  count = 0 ## i64
  mode = 0
  while mode < ffkp_mode_count()
    count += ready[mode]
    mode += 1
  count

-> ffn_gpu_seed_path(run_tag, n, role) (String i64 i64)
  "/tmp/flipfleet_gpu_seed_" + run_tag + "_" + n.to_s() + "_" + role.to_s() + ".txt"

-> ffn_gpu_output_path(run_tag, n, role) (String i64 i64)
  "/tmp/flipfleet_gpu_best_" + run_tag + "_" + n.to_s() + "_" + role.to_s() + ".txt"

-> ffn_gpu_log_path(run_tag, n, role) (String i64 i64)
  "/tmp/flipfleet_gpu_log_" + run_tag + "_" + n.to_s() + "_" + role.to_s() + ".txt"

-> ffn_executable_exists(path) (String) i64
  checked = system("test -x " + ffg_shell_quote(path))
  exists = 0 ## i64
  if checked
    exists = 1
  exists

-> ffn_binary_fresh(binary, source, sidecar) (String String String) i64
  fresh = 0 ## i64
  if ffn_executable_exists(binary) == 1
    binary_mtime = file_mtime_ns(binary)
    source_mtime = file_mtime_ns(source)
    sidecar_mtime = file_mtime_ns(sidecar)
    if binary_mtime != nil && source_mtime != nil && sidecar_mtime != nil
      if binary_mtime >= source_mtime && binary_mtime >= sidecar_mtime
        fresh = 1
  fresh

-> ffn_gpu_launch(root, binary, run_tag, n, role, lanes, steps, rounds, seed_state, elapsed_ms)
  seed_path = ffn_gpu_seed_path(run_tag, n, role)
  output_path = ffn_gpu_output_path(run_tag, n, role)
  log_path = ffn_gpu_log_path(run_tag, n, role)
  z = ffn_dump_trusted(seed_state, seed_path, run_tag) ## i64
  if z < 1
    return nil
  write_ok = write_file(output_path, "")
  if write_ok == false
    return nil
  escapes = 1 ## i64
  if role == 3
    escapes = lanes
  command = ffb_epoch_command(root, binary, n, seed_path, output_path, "", 0, steps, ffp_gpu_reseed(role), ffp_gpu_margin(role), ffg_cal2zone_workq(role), ffg_cal2zone_wanderq(role), ffg_cal2zone_wthr(role), lanes, "", escapes, rounds)
  if command == ""
    return nil
  command = command + " > " + ffg_shell_quote(log_path) + " 2>&1"
  Thread.new ->
    t0 = ccall("__w_clock_ms") ## i64
    ok = system(command)
    elapsed_ms[role] = ccall("__w_clock_ms") - t0
    ok

-> ffn_gpu_launch_c3(root, binary, run_tag, n, lanes, seed_state, elapsed_ms)
  role = 2 ## i64
  seed_path = ffn_gpu_seed_path(run_tag, n, role)
  output_path = ffn_gpu_output_path(run_tag, n, role)
  log_path = ffn_gpu_log_path(run_tag, n, role)
  z = ffn_dump_trusted(seed_state, seed_path, run_tag) ## i64
  if z < 1
    return nil
  write_ok = write_file(output_path, "")
  if write_ok == false
    return nil
  command = ffc3_epoch_command(root, binary, n, seed_path, output_path, lanes, ffg_symmetry_steps(), ffg_symmetry_dispatches(), ffg_symmetry_band(), ffg_symmetry_plus_period())
  if command == ""
    return nil
  command = command + " > " + ffg_shell_quote(log_path) + " 2>&1"
  Thread.new ->
    t0 = ccall("__w_clock_ms") ## i64
    ok = system(command)
    elapsed_ms[role] = ccall("__w_clock_ms") - t0
    ok

-> ffn_gpu_launch_simd(root, binary, run_tag, n, lanes, seed_state, elapsed_ms)
  role = 9 ## i64
  seed_path = ffn_gpu_seed_path(run_tag, n, role)
  output_path = ffn_gpu_output_path(run_tag, n, role)
  log_path = ffn_gpu_log_path(run_tag, n, role)
  z = ffn_dump_trusted(seed_state, seed_path, run_tag) ## i64
  if z < 1
    return nil
  write_ok = write_file(output_path, "")
  if write_ok == false
    return nil
  command = ffsimd_epoch_command(root, binary, n, seed_path, output_path, lanes, ffg_simd_steps(), ffg_simd_dispatches(), ffg_simd_margin())
  if command == ""
    return nil
  command = command + " > " + ffg_shell_quote(log_path) + " 2>&1"
  Thread.new ->
    t0 = ccall("__w_clock_ms") ## i64
    ok = system(command)
    elapsed_ms[role] = ccall("__w_clock_ms") - t0
    ok

-> ffn_mitm_build(root, binary) (String String) i64
  source = "benchmarks/matmul/metaflip/flipfleet_mitm_lane.w"
  command = "cd " + ffg_shell_quote(root) + " && TUNGSTEN_LL_PATH=" + ffg_shell_quote(binary + ".ll") + " bin/tungsten -o " + ffg_shell_quote(binary) + " " + ffg_shell_quote(source) + " --release --native --fast --lto"
  built = system(command)
  result = 0 ## i64
  if built
    result = 1
  result

-> ffn_pool_worker_build(root, binary, source) (String String String) i64
  command = "cd " + ffg_shell_quote(root) + " && TUNGSTEN_LL_PATH=" + ffg_shell_quote(binary + ".ll") + " bin/tungsten -o " + ffg_shell_quote(binary) + " " + ffg_shell_quote(source) + " --release --native --fast --lto"
  built = system(command)
  if built
    return 1
  0

-> ffn_gpu_launch_mitm(root, binary, run_tag, n, slot, lanes, steps, launch_number, seed_state, elapsed_ms)
  seed_path = ffn_gpu_seed_path(run_tag, n, slot)
  output_path = ffn_gpu_output_path(run_tag, n, slot)
  log_path = ffn_gpu_log_path(run_tag, n, slot)
  z = ffn_dump_trusted(seed_state, seed_path, run_tag) ## i64
  if z < 1
    return nil
  write_ok = write_file(output_path, "")
  if write_ok == false
    return nil
  plan = i64[4]
  work = ffg_mitm_plan(lanes, steps, 700, 16, plan) ## i64
  subsets = plan[1] ## i64
  if subsets > 16
    subsets = 16
  pool = plan[2] ## i64
  nearby = ffg_mitm_nearby(launch_number) ## i64
  offset = launch_number % 256 ## i64
  command = "cd " + ffg_shell_quote(root) + " && " + ffg_mitm_command(binary, seed_path, output_path, n, subsets, pool, nearby, offset)
  command = command + " >> " + ffg_shell_quote(log_path) + " 2>&1"
  Thread.new ->
    t0 = ccall("__w_clock_ms") ## i64
    ok = system(command)
    elapsed_ms[slot] = ccall("__w_clock_ms") - t0
    ok

-> ffn_gpu_launch_pool(root, generic_binary, mitm_binary, constraint_binary, kxor_binary, run_tag, n, slot, mode, lanes, steps, rounds, launch_number, seed_state, elapsed_ms)
  if mode == 1
    return ffn_gpu_launch_mitm(root, mitm_binary, run_tag, n, slot, lanes, steps, launch_number, seed_state, elapsed_ms)
  seed_path = ffn_gpu_seed_path(run_tag, n, slot)
  output_path = ffn_gpu_output_path(run_tag, n, slot)
  log_path = ffn_gpu_log_path(run_tag, n, slot)
  z = ffn_dump_trusted(seed_state, seed_path, run_tag) ## i64
  if z < 1
    return nil
  write_ok = write_file(output_path, "")
  if write_ok == false
    return nil
  command = ""
  if mode == 0 || mode == 5 || mode == 6
    constraint_mode = 0 ## i64
    if mode == 5
      constraint_mode = 1
    if mode == 6
      constraint_mode = 2
    constraint_metal = root + "/benchmarks/matmul/metaflip/flipfleet_constraint_pool.metal"
    command = ffg_shell_quote(constraint_binary) + " " + ffg_shell_quote(seed_path) + " " + ffg_shell_quote(output_path) + " " + n.to_s() + " " + constraint_mode.to_s() + " " + lanes.to_s() + " " + steps.to_s() + " " + launch_number.to_s() + " " + ffg_shell_quote(constraint_metal)
  if mode == 2 || mode == 3
    k = 6 ## i64
    # Keep bounded joins inside the empirically safe shared-buffer envelope;
    # breadth comes from rotating subsets, not one oversized allocation.
    pool = 32 ## i64
    if mode == 3
      k = 7
      pool = 24
    subsets = lanes / 64 ## i64
    if subsets < 1
      subsets = 1
    if subsets > 4
      subsets = 4
    kxor_metal = root + "/benchmarks/matmul/metaflip/flipfleet_kxor_pool.metal"
    command = ffg_shell_quote(kxor_binary) + " " + ffg_shell_quote(seed_path) + " " + ffg_shell_quote(output_path) + " " + n.to_s() + " " + k.to_s() + " " + subsets.to_s() + " " + pool.to_s() + " 2 " + (launch_number % 256).to_s() + " " + ffg_shell_quote(kxor_metal)
  if mode == 4
    command = ffb_epoch_command(root, generic_binary, n, seed_path, output_path, "", 0, steps, ffp_gpu_reseed(7), ffp_gpu_margin(7), ffg_cal2zone_workq(7), ffg_cal2zone_wanderq(7), ffg_cal2zone_wthr(7), lanes, "", lanes, rounds)
  if mode == 7 || mode == 8 || mode == 9 || mode == 10
    profile_role = 4 ## i64
    if mode == 8
      profile_role = 5
    if mode == 9
      profile_role = 6
    if mode == 10
      profile_role = 7
    command = ffb_epoch_command(root, generic_binary, n, seed_path, output_path, "", 0, steps, ffp_gpu_reseed(profile_role), ffp_gpu_margin(profile_role), ffg_cal2zone_workq(profile_role), ffg_cal2zone_wanderq(profile_role), ffg_cal2zone_wthr(profile_role), lanes, "", lanes, rounds)
  if command == ""
    return nil
  command = "cd " + ffg_shell_quote(root) + " && " + command + " >> " + ffg_shell_quote(log_path) + " 2>&1"
  Thread.new ->
    t0 = ccall("__w_clock_ms") ## i64
    ok = system(command)
    elapsed_ms[slot] = ccall("__w_clock_ms") - t0
    ok

-> ffn_status(path, run_tag, producer_state, updated_ms, sequence, n, record, record_known, best, moves, elapsed_s, archive, near1, near2, symmetry, gpu_enabled, gpu_degraded)
  body = "schema=4 producer_state=" + producer_state + " updated_ms=" + updated_ms.to_s() + " sequence=" + sequence.to_s()
  body = body + " tensor=" + n.to_s() + "x" + n.to_s()
  body = body + " record=" + record.to_s() + " record_known=" + record_known.to_s()
  body = body + " best_rank=" + ffw_best_rank(best).to_s() + " best_bits=" + ffw_best_bits(best).to_s()
  body = body + " moves=" + moves.to_s() + " elapsed=" + elapsed_s.to_s()
  body = body + " archive=" + archive.size().to_s() + " near1=" + near1.size().to_s()
  body = body + " near2=" + near2.size().to_s() + " symmetry=" + symmetry.size().to_s()
  body = body + " gpu=" + gpu_enabled.to_s() + " gpu_degraded=" + gpu_degraded.to_s() + "\n"
  ffn_atomic_write(path, body, run_tag)

-> ffn_render(n, threads_count, round, elapsed_s, total_moves, record, record_known, recovered, best, states, island_best_ranks, doors, zones, sources, last_rates, last_ages, cpu_work_moves, cpu_wander_moves, archive, archive_capacity, near1, near1_capacity, near2, near2_capacity, symmetry, symmetry_capacity, archive_counters, archive_min_distance, cohort_moves, cohort_drops, cohort_ties, cohort_near, timeline_times, timeline_ranks, timeline_count, timeline_elapsed_s, gpu_enabled, gpu_policy, gpu_degraded, gpu_lanes, gpu_candidates, gpu_rank_drops, gpu_density, gpu_rewards, gpu_epochs, gpu_wall_ms, gpu_failures, gpu_disabled, gpu_retry_round, gpu_seed_ranks, gpu_pareto, gpu_pareto_archive, gpu_pareto_capacity, gpu_pareto_counters, symmetry_cpu_uses, gpu_launch_number, pool_active_modes, pool_mode_ready, last_status_ms, sequence, now_ms, rank_levels, rank_ticks, rank_level_count, bits_levels, bits_ticks, bits_level_count, new_bests_count, tie_bests_count, cycleouts_count, exact_rejects, dslack, flash_text, flash_until_ms)
  width = ccall("w_term_cols") ## i64
  if width < 60
    width = 60
  inner = width - 2 ## i64
  rows = []
  state = ff_tui_health(0, 0, 0, gpu_degraded, last_status_ms, now_ms, 5000)
  age_ms = ff_tui_heartbeat_age_ms(last_status_ms, now_ms) ## i64
  age_text = "?"
  if age_ms >= 0
    age_text = ff_tui_duration_ms(age_ms)
  age_text = ff_tui_pad_left(age_text, 5)
  objective = ff_tui_objective(ffw_best_rank(best), record, record_known, recovered)
  record_badge = ff_tui_record_badge(record, record_known)
  record_plain = ""
  record_paint = ""
  if record_badge != ""
    record_plain = "  " + record_badge
    if record_known != 0
      record_paint = "  " + ff_tui_paint(record_badge, "1;36")
    if record_known == 0
      record_paint = "  " + ff_tui_dim(record_badge)

  dims = n.to_s() + "," + n.to_s() + "," + n.to_s()
  title_plain = "  flipfleet  <" + dims + "> GF(2)" + record_plain + "   " + state + " age " + age_text + "   seq " + sequence.to_s()
  title_paint = "  " + ff_tui_paint("flipfleet", "1;33") + "  ⟨" + dims + "⟩ GF(2)" + record_paint + "   " + ff_tui_paint(state, ff_tui_health_code(state)) + ff_tui_dim(" age " + age_text + "   seq " + sequence.to_s())
  rows.push(ff_tui_fit(title_plain, title_paint, width))

  best_bits_text = ffw_best_bits(best).to_s()
  moves_text = ff_tui_compact_fixed(total_moves, 6)
  stat_plains = ["  " + objective, "   density " + best_bits_text, "   moves " + moves_text, "   elapsed " + ff_tui_duration(elapsed_s), "   threads " + threads_count.to_s(), "   round " + round.to_s()]
  stat_painteds = ["  " + ff_tui_paint(objective, "1;32"), "   " + ff_tui_dim("density") + " " + best_bits_text, "   " + ff_tui_dim("moves") + " " + moves_text, "   " + ff_tui_dim("elapsed") + " " + ff_tui_duration(elapsed_s), "   " + ff_tui_dim("threads") + " " + threads_count.to_s(), "   " + ff_tui_dim("round") + " " + round.to_s()]
  rows.push(ff_tui_join_fit(stat_plains, stat_painteds, width))

  if rank_level_count >= 1
    spark_w = width - 24 ## i64
    if spark_w < 16
      spark_w = 16
    if spark_w > 120
      spark_w = 120
    rows.push("  " + ff_tui_dim("rank    ") + ff_tui_paint(ff_tui_spark_runs(rank_levels, rank_ticks, rank_level_count, spark_w), "32") + ff_tui_dim(" " + rank_levels[0].to_s() + "→" + ffw_best_rank(best).to_s()))
    rows.push("  " + ff_tui_dim("density ") + ff_tui_paint(ff_tui_spark_runs(bits_levels, bits_ticks, bits_level_count, spark_w), "33") + ff_tui_dim(" " + bits_levels[0].to_s() + "→" + best_bits_text))

  counter_plains = ["  new-bests " + new_bests_count.to_s(), "   ties " + tie_bests_count.to_s(), "   cycleouts " + cycleouts_count.to_s(), "   exact-rejects " + exact_rejects.to_s(), "   density-slack " + dslack.to_s()]
  counter_painteds = ["  " + ff_tui_dim("new-bests") + " " + new_bests_count.to_s(), "   " + ff_tui_dim("ties") + " " + tie_bests_count.to_s(), "   " + ff_tui_dim("cycleouts") + " " + cycleouts_count.to_s(), "   " + ff_tui_dim("exact-rejects") + " " + exact_rejects.to_s(), "   " + ff_tui_dim("density-slack") + " " + dslack.to_s()]
  rows.push(ff_tui_join_fit(counter_plains, counter_painteds, width))
  if flash_text != ""
    if now_ms < flash_until_ms
      rows.push("  " + ff_tui_paint(ff_tui_clip(flash_text, inner), "1;33"))

  rows.push("")
  rows.push(ff_tui_paint(ff_tui_rule("CPU islands (sticky doors; independent work/wander zones)", width), "36"))
  i = 0 ## i64
  while i < threads_count
    door_name = ffp_door_name(doors[i])
    if sources[i].starts_with?("core-fringe")
      door_name = "core"
    zone_name = ffp_zone_name(zones[i])
    basin_id = ffn_current_basin_id(states[i]) ## i64
    basin_distance = ffn_current_to_best_distance(states[i], best) ## i64
    island_row = ff_tui_cpu_island_row(i, door_name, zone_name, ffw_best_rank(best), island_best_ranks[i], ffw_current_rank(states[i]), ffw_band(states[i]), basin_id, basin_distance, ffw_moves(states[i]), last_rates[i], last_ages[i], sources[i], "running", cpu_work_moves[zones[i]], cpu_wander_moves[zones[i]], inner)
    island_code = ""
    if island_best_ranks[i] > 0 && island_best_ranks[i] == ffw_best_rank(best)
      island_code = "32"
    if last_ages[i] > 300
      island_code = "33"
    rows.push("  " + ff_tui_paint(island_row, island_code))
    i += 1
  rows.push("")
  if gpu_enabled == 0
    rows.push(ff_tui_paint(ff_tui_rule("CPU strategy portfolio (no GPU)", width), "35"))
    lanes = ffp_cpu_strategy_lane_count(n) ## i64
    pool = ffp_cpu_strategy_pool_count() ## i64
    rows.push("  " + ff_tui_dim("lanes " + lanes.to_s() + " (min 4 / max 10 continuous roles)  pool " + pool.to_s() + " cores  sticky doors on remaining walkers"))
  if gpu_enabled != 0
    rows.push(ff_tui_paint(ff_tui_rule("GPU " + gpu_policy + " mixed portfolio", width), "35"))
    role = 0 ## i64
    while role < 11
      if gpu_lanes[role] > 0 || gpu_failures[role] > 0 || gpu_disabled[role] != 0
        retrying = 0 ## i64
        if gpu_disabled[role] != 0 && gpu_retry_round[role] > round
          retrying = 1
        recipe = ffg_engine_name(role) + "@" + ff_tui_duration_ms(gpu_wall_ms[role])
        if gpu_disabled[role] != 0
          recipe = recipe + "/disabled"
        role_row = ff_tui_gpu_role_row(ffp_gpu_role_name(role), gpu_lanes[role], gpu_seed_ranks[role], recipe, gpu_candidates[role], gpu_pareto[role], gpu_rank_drops[role], gpu_density[role], gpu_rewards[role], gpu_epochs[role], gpu_failures[role], retrying, inner)
        role_code = ""
        if gpu_failures[role] > 0
          role_code = "33"
        if gpu_disabled[role] != 0
          role_code = "31"
          if retrying == 1
            role_code = "2"
        rows.push("  " + ff_tui_paint(role_row, role_code))
        if role == 10
          pool_child = 0 ## i64
          while pool_child < ffkp_mode_count()
            right_child = pool_child + 1 ## i64
            right_name = ""
            right_active = 0 ## i64
            right_ready = 0 ## i64
            if right_child < ffkp_mode_count()
              right_name = ffkp_mode_name(right_child)
              right_ready = pool_mode_ready[right_child]
              if pool_active_modes[right_child] != 0 && gpu_disabled[10] == 0 && gpu_lanes[10] > 0
                right_active = 1
            left_active = 0 ## i64
            if pool_active_modes[pool_child] != 0 && gpu_disabled[10] == 0 && gpu_lanes[10] > 0
              left_active = 1
            rows.push("  " + ff_tui_gpu_pool_pair(ffkp_mode_name(pool_child), left_active, pool_mode_ready[pool_child], right_name, right_active, right_ready, inner))
            pool_child += 2
      role += 1
  rows.push("")
  rows.push(ff_tui_paint(ff_tui_rule("Diversity", width), "36"))
  basin_stats = i64[4]
  z = ffn_active_basin_stats(states, best, basin_stats)
  basin_line = "cpu active " + basin_stats[0].to_s() + "/" + threads_count.to_s() + " term-sets · min d " + basin_stats[1].to_s() + " · on leader " + basin_stats[2].to_s() + " · mean d " + basin_stats[3].to_s()
  rows.push("  " + ff_tui_clip(basin_line, inner))
  rows.push("  " + ff_tui_clip(ff_tui_frontier_diversity(archive.size(), archive_capacity, archive_min_distance, archive_counters[1], archive_counters[2]), inner))
  rows.push("  " + ff_tui_clip(ff_tui_shoulder_diversity(near1.size(), near1_capacity, ffn_archive_min_distance(near1), near2.size(), near2_capacity, ffn_archive_min_distance(near2), 0 - 1, 0 - 1), inner))
  symmetry_gpu_uses = gpu_launch_number[2] + gpu_launch_number[5] + gpu_launch_number[6] ## i64
  rows.push("  " + ff_tui_clip(ff_tui_symmetry_diversity(symmetry.size(), symmetry_cpu_uses, symmetry_gpu_uses), inner))
  rows.push("  " + ff_tui_clip(ff_tui_gpu_pareto_diversity(gpu_pareto_archive.size(), gpu_pareto_capacity, gpu_pareto_counters[0], gpu_pareto_counters[2], gpu_pareto_counters[1]), inner))
  rows.push("")
  rows.push(ff_tui_paint(ff_tui_rule("Effectiveness (exposure-normalized)", width), "36"))
  door = 0 ## i64
  while door < 7
    zone = 0 ## i64
    while zone < 4
      idx = door * 4 + zone ## i64
      moves = cohort_moves[idx] ## i64
      if moves > 0
        cohort_name = ffp_door_name(door) + "/" + ffp_zone_name(zone)
        rows.push("  " + ff_tui_cpu_effectiveness(cohort_name, moves, cohort_drops[idx], cohort_ties[idx], cohort_near[idx], inner))
      zone += 1
    door += 1
  rows.push("")
  rows.push(ff_tui_paint(ff_tui_rule("Rank timeline (wall-time; lower rank is up; * density-only)", width), "36"))
  lines = ff_tui_timeline(timeline_times, timeline_ranks, timeline_count, timeline_elapsed_s, inner)
  i = 0
  while i < lines.size()
    line_code = "32"
    if i == lines.size() - 1
      line_code = "2"
    if lines.size() == 1
      line_code = "2"
    rows.push("  " + ff_tui_paint(lines[i], line_code))
    i += 1
  if timeline_count <= 1
    rows.push("  " + ff_tui_dim("no adoptions yet this run — a new best rank plots o, a density-only best plots *"))
  rows.push("")
  rows.push("  " + ff_tui_dim("rank → asymptotic exponent (want ↓) · density → base-case ops (want ↓) · space=reset naive · w=reseed record · q/Ctrl-C stops"))

  # One atomic write per frame: home + erase-to-EOL per row + erase-below,
  # wrapped in DEC 2026 synchronized update.  No full-screen clear, no flicker.
  frame = "\e[?2026h\e[H"
  i = 0
  while i < rows.size()
    frame = frame + rows[i] + "\e[K\n"
    i += 1
  frame = frame + "\e[J\e[?2026l"
  << frame
  flush()
  1

# ---- CLI -----------------------------------------------------------------
N = 5 ## i64
J = 0 ## i64
J_EXPLICIT = 0 ## i64
STEPS = 500000 ## i64
MAX_ROUNDS = 2000000000 ## i64
MAX_SECS = 0 ## i64
DSLACK = 4 ## i64
CYCLES = 4 ## i64
GPU = 1 ## i64
GPU_POLICY = "adaptive"
GPU_WALKERS = 4096 ## i64
GPU_STEPS = 20000 ## i64
GPU_EPOCH_ROUNDS = 1 ## i64
GPU_BINARY = ""
GPU_REBUILD = 0 ## i64
REPO_ROOT = ""
TUI = 1 ## i64
QUIET = 0 ## i64
STRATEGY = "islands"
MIGRATE = 1 ## i64
STOP_ON_RECORD = 0 ## i64
ARCHIVE_CAP = 16 ## i64
NEAR_CAP = 64 ## i64
NEAR_SIGNATURE_QUOTA = 8 ## i64
SYMMETRY_CAP = 24 ## i64
GPU_NOVELTY_CAP = 32 ## i64
CPU_WORK_SPEC = ""
CPU_WANDER_SPEC = ""
SEED_PATH = ""
RECORD_OVERRIDE = 0 ## i64
STATUS_PATH = "flipfleet_status.txt"
BEST_PATH = "flipfleet_best.txt"
STATUS_EXPLICIT = 0 ## i64
BEST_EXPLICIT = 0 ## i64
RUN_TAG = ""

av = argv()
value_options = ["--tensor", "-J", "--walkers", "--steps", "--rounds", "--secs", "-d", "--density", "--cycles", "--seed", "--record", "--gpu-walkers", "--gpu-policy", "--gpu-steps", "--gpu-epoch-rounds", "--gpu-binary", "--gpu-novelty-size", "--repo-root", "--strategy", "--migrate", "--archive-size", "--cpu-near-size", "--cpu-near-signature-quota", "--cpu-symmetry-seeds", "--cpu-work-moves", "--cpu-wander-moves", "--status", "--best", "--run-tag"]
switch_options = ["--rebuild-gpu", "--no-gpu", "--gpu", "--no-tui", "--tui", "--quiet", "--stop-on-record", "--self-test"]
ai = 0 ## i64
while ai < av.size()
  arg = av[ai]
  needs_value = 0 ## i64
  known_switch = 0 ## i64
  if value_options.include?(arg)
    needs_value = 1
  if switch_options.include?(arg)
    known_switch = 1
  if needs_value == 0 && known_switch == 0
    << "flipfleet: unknown option " + arg
    exit(2)
  if needs_value == 1 && ai + 1 >= av.size()
    << "flipfleet: missing value for " + arg
    exit(2)
  if arg == "--tensor" && ai + 1 < av.size()
    N = ffn_parse_tensor(av[ai + 1])
    ai += 1
  if (arg == "-J" || arg == "--walkers") && ai + 1 < av.size()
    J = av[ai + 1].to_i()
    J_EXPLICIT = 1
    ai += 1
  if arg == "--steps" && ai + 1 < av.size()
    STEPS = av[ai + 1].to_i()
    ai += 1
  if arg == "--rounds" && ai + 1 < av.size()
    MAX_ROUNDS = av[ai + 1].to_i()
    ai += 1
  if arg == "--secs" && ai + 1 < av.size()
    MAX_SECS = av[ai + 1].to_i()
    ai += 1
  if (arg == "-d" || arg == "--density") && ai + 1 < av.size()
    DSLACK = av[ai + 1].to_i()
    ai += 1
  if arg == "--cycles" && ai + 1 < av.size()
    CYCLES = av[ai + 1].to_i()
    ai += 1
  if arg == "--seed" && ai + 1 < av.size()
    SEED_PATH = av[ai + 1]
    ai += 1
  if arg == "--record" && ai + 1 < av.size()
    RECORD_OVERRIDE = av[ai + 1].to_i()
    ai += 1
  if arg == "--gpu-walkers" && ai + 1 < av.size()
    GPU_WALKERS = av[ai + 1].to_i()
    ai += 1
  if arg == "--gpu-policy" && ai + 1 < av.size()
    GPU_POLICY = av[ai + 1]
    ai += 1
  if arg == "--gpu-steps" && ai + 1 < av.size()
    GPU_STEPS = av[ai + 1].to_i()
    ai += 1
  if arg == "--gpu-epoch-rounds" && ai + 1 < av.size()
    GPU_EPOCH_ROUNDS = av[ai + 1].to_i()
    ai += 1
  if arg == "--gpu-binary" && ai + 1 < av.size()
    GPU_BINARY = av[ai + 1]
    ai += 1
  if arg == "--gpu-novelty-size" && ai + 1 < av.size()
    GPU_NOVELTY_CAP = av[ai + 1].to_i()
    ai += 1
  if arg == "--repo-root" && ai + 1 < av.size()
    REPO_ROOT = av[ai + 1]
    ai += 1
  if arg == "--rebuild-gpu"
    GPU_REBUILD = 1
  if arg == "--no-gpu"
    GPU = 0
  if arg == "--gpu"
    GPU = 1
  if arg == "--no-tui"
    TUI = 0
  if arg == "--tui"
    TUI = 1
  if arg == "--quiet"
    QUIET = 1
    TUI = 0
  if arg == "--strategy" && ai + 1 < av.size()
    STRATEGY = av[ai + 1]
    ai += 1
  if arg == "--migrate" && ai + 1 < av.size()
    MIGRATE = av[ai + 1].to_i()
    ai += 1
  if arg == "--archive-size" && ai + 1 < av.size()
    ARCHIVE_CAP = av[ai + 1].to_i()
    ai += 1
  if arg == "--cpu-near-size" && ai + 1 < av.size()
    NEAR_CAP = av[ai + 1].to_i()
    ai += 1
  if arg == "--cpu-near-signature-quota" && ai + 1 < av.size()
    NEAR_SIGNATURE_QUOTA = av[ai + 1].to_i()
    ai += 1
  if arg == "--cpu-symmetry-seeds" && ai + 1 < av.size()
    SYMMETRY_CAP = av[ai + 1].to_i()
    ai += 1
  if arg == "--cpu-work-moves" && ai + 1 < av.size()
    CPU_WORK_SPEC = av[ai + 1]
    ai += 1
  if arg == "--cpu-wander-moves" && ai + 1 < av.size()
    CPU_WANDER_SPEC = av[ai + 1]
    ai += 1
  if arg == "--stop-on-record"
    STOP_ON_RECORD = 1
  if arg == "--status" && ai + 1 < av.size()
    STATUS_PATH = av[ai + 1]
    STATUS_EXPLICIT = 1
    ai += 1
  if arg == "--best" && ai + 1 < av.size()
    BEST_PATH = av[ai + 1]
    BEST_EXPLICIT = 1
    ai += 1
  if arg == "--run-tag" && ai + 1 < av.size()
    RUN_TAG = av[ai + 1]
    ai += 1
  if arg == "--self-test"
    GPU = 0
    TUI = 0
    QUIET = 0
    STEPS = 200
    MAX_ROUNDS = 2
    J = 2
    J_EXPLICIT = 1
  ai += 1

if N < 3 || N > 7
  << "flipfleet: --tensor must be 3x3 through 7x7"
  exit(2)
HOST_THREADS = System.cpu_count ## i64
if J_EXPLICIT == 0
  # Default: host cores minus four. With no GPU those four (plus strategy
  # slots inside J) host the continuous-role / pool CPU strategy layout.
  J = ffp_default_cpu_walkers(HOST_THREADS, GPU)
if J < 1
  J = 1
if STEPS < 1
  STEPS = 1
if GPU_STEPS < 1
  GPU_STEPS = 1
if GPU_STEPS > 1000000
  GPU_STEPS = 1000000
if GPU_EPOCH_ROUNDS < 1
  GPU_EPOCH_ROUNDS = 1
if GPU_EPOCH_ROUNDS > 64
  GPU_EPOCH_ROUNDS = 64
if GPU_WALKERS < 32
  GPU_WALKERS = 32
if GPU_WALKERS > 65536
  GPU_WALKERS = 65536
if MIGRATE < 0
  MIGRATE = 0
if MIGRATE > J
  MIGRATE = J
if ARCHIVE_CAP < 2 || ARCHIVE_CAP > 64
  << "flipfleet: --archive-size must be 2 through 64"
  exit(2)
if NEAR_CAP < 2 || NEAR_CAP > 256
  << "flipfleet: --cpu-near-size must be 2 through 256"
  exit(2)
if NEAR_SIGNATURE_QUOTA < 1 || NEAR_SIGNATURE_QUOTA > NEAR_CAP
  << "flipfleet: --cpu-near-signature-quota must be positive and no larger than the near bank"
  exit(2)
if SYMMETRY_CAP < 1 || SYMMETRY_CAP > 64
  << "flipfleet: --cpu-symmetry-seeds must be 1 through 64"
  exit(2)
if GPU_NOVELTY_CAP < 2 || GPU_NOVELTY_CAP > 128
  << "flipfleet: --gpu-novelty-size must be 2 through 128"
  exit(2)
if GPU_POLICY != "adaptive" && GPU_POLICY != "single"
  << "flipfleet: --gpu-policy must be adaptive or single"
  exit(2)
if STRATEGY != "islands" && STRATEGY != "independent" && STRATEGY != "converge"
  << "flipfleet: --strategy must be islands, independent, or converge"
  exit(2)

REPO_ROOT = ffn_discover_repo_root(REPO_ROOT)
if REPO_ROOT == ""
  << "flipfleet: cannot locate the Tungsten repository; launch from inside it or pass --repo-root PATH"
  exit(2)

if RUN_TAG == ""
  RUN_TAG = capture("printf '%s' $$").strip() + "_" + ccall("__w_clock_ms").to_s()
if RUN_TAG.include?("/") || RUN_TAG.include?("..")
  << "flipfleet: --run-tag may not contain '/' or '..'"
  exit(2)
if STATUS_EXPLICIT == 0
  STATUS_PATH = "flipfleet_" + N.to_s() + "x" + N.to_s() + "_" + RUN_TAG + "_status.txt"
if BEST_EXPLICIT == 0
  BEST_PATH = "flipfleet_" + N.to_s() + "x" + N.to_s() + "_best.txt"

RECORD = ffp_record(N) ## i64
RECORD_KNOWN = ffp_record_known(N) ## i64
if RECORD_OVERRIDE > 0
  RECORD = RECORD_OVERRIDE
  RECORD_KNOWN = 0

CAPACITY = ffw_default_capacity(N) ## i64
STATE_SIZE = ffw_state_size(CAPACITY) ## i64
cpu_work_moves = i64[4]
cpu_wander_moves = i64[4]
zone_index = 0 ## i64
while zone_index < 4
  cpu_work_moves[zone_index] = ffp_work_moves(N, zone_index)
  cpu_wander_moves[zone_index] = ffp_wander_moves(N, zone_index)
  zone_index += 1
if CPU_WORK_SPEC != ""
  if ffn_parse_move_portfolio(CPU_WORK_SPEC, cpu_work_moves) == 0
    << "flipfleet: --cpu-work-moves requires four positive comma-separated budgets"
    exit(2)
if CPU_WANDER_SPEC != ""
  if ffn_parse_move_portfolio(CPU_WANDER_SPEC, cpu_wander_moves) == 0
    << "flipfleet: --cpu-wander-moves requires four positive comma-separated budgets"
    exit(2)
balanced_work = cpu_work_moves[1] ## i64
balanced_wander = cpu_wander_moves[1] ## i64
near1_capacity = (NEAR_CAP + 1) / 2 ## i64
near2_capacity = NEAR_CAP / 2 ## i64

# Exact anchor and monotonic fleet best.
anchor = i64[STATE_SIZE]
path = SEED_PATH
if path == ""
  profile_path = ffp_seed_path(N)
  if profile_path != ""
    path = REPO_ROOT + "/" + profile_path
loaded = 0 - 1 ## i64
if path != ""
  loaded = ffw_load_scheme_cap(anchor, path, N, CAPACITY, 17, DSLACK, CYCLES, balanced_work, balanced_wander)
if SEED_PATH != "" && loaded < 1
  << "flipfleet: explicit --seed is missing, malformed, inexact, or for a different tensor"
  exit(2)
if SEED_PATH == "" && loaded < 1
  loaded = ffw_init_naive_cap(anchor, N, CAPACITY, 17, DSLACK, CYCLES, balanced_work, balanced_wander)
if loaded < 1 || ffw_verify_best_exact(anchor, N) != 1
  << "flipfleet: exact anchor initialization failed"
  exit(2)

best = ffn_clone_exact(anchor, N, CAPACITY, STATE_SIZE, 23, DSLACK, CYCLES, balanced_work, balanced_wander)
if best == nil
  << "flipfleet: exact best clone failed"
  exit(2)
recovered = 0 ## i64
durable = i64[STATE_SIZE]
durable_text = read_file(BEST_PATH)
durable_rank = ffw_load_scheme_cap(durable, BEST_PATH, N, CAPACITY, 31, DSLACK, CYCLES, balanced_work, balanced_wander) ## i64
if durable_text != nil && durable_rank < 1
  << "flipfleet: refusing to overwrite malformed, inexact, or wrong-tensor --best checkpoint"
  exit(2)
if durable_rank > 0
  if ffn_better(durable_rank, ffw_best_bits(durable), ffw_best_rank(best), ffw_best_bits(best)) == 1
    best = durable
    recovered = durable_rank

# Native exact banks.
archive = []
near1 = []
near2 = []
near1_signatures = []
near1_uses = []
near1_successes = []
near2_signatures = []
near2_uses = []
near2_successes = []
near_counters = i64[5]
symmetry = []
mixed = []
orbit_bank = []
polar_bank = []
c3_base = nil
archive_counters = i64[3] # admissions, evictions, rejections
gpu_pareto_archive = []
gpu_pareto_ranks = []
gpu_pareto_bits = []
gpu_pareto_pairs = []
gpu_pareto_novelties = []
gpu_pareto_roles = []
gpu_pareto_uses = []
gpu_pareto_counters = i64[4]
map_states = []
map_keys = []
map_uses = []
map_sources = []
MAP_CAPACITY = 64 ## i64
first_archive = ffn_clone_trusted(best, STATE_SIZE, 29)
if first_archive != nil
  archive.push(first_archive)

# The repository contains structurally distant exact schemes at the same
# tracked rank. Load all of them through the ordinary exhaustive gate instead
# of making every CPU island derive from the density leader.
frontier_paths = ffp_frontier_seed_paths(N)
frontier_index = 0 ## i64
while frontier_index < frontier_paths.size()
  frontier_candidate = i64[STATE_SIZE]
  frontier_path = REPO_ROOT + "/" + frontier_paths[frontier_index]
  frontier_rank = ffw_load_scheme_cap(frontier_candidate, frontier_path, N, CAPACITY, 3001 + frontier_index * 17, DSLACK, CYCLES, balanced_work, balanced_wander) ## i64
  if frontier_rank == ffw_best_rank(best)
    if ffw_verify_best_exact(frontier_candidate, N) == 1
      z = ffn_archive_add(archive, frontier_candidate, ARCHIVE_CAP, 4, archive_counters)
  frontier_index += 1
archive_min_cache = ffn_archive_min_distance(archive) ## i64
bank_count = ffn_build_escape_banks(best, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, near1, near2, near1_signatures, near1_uses, near1_successes, near2_signatures, near2_uses, near2_successes, symmetry, mixed, orbit_bank, polar_bank, near1_capacity, near2_capacity, NEAR_SIGNATURE_QUOTA, SYMMETRY_CAP, near_counters) ## i64
mi = 0 ## i64
while mi < archive.size()
  z = ffme_add(map_states, map_keys, map_uses, map_sources, archive[mi], ffw_best_rank(best), N, MAP_CAPACITY, 0)
  mi += 1
map_pool = near1
map_source = 1 ## i64
while map_source <= 4
  if map_source == 2
    map_pool = near2
  if map_source == 3
    map_pool = mixed
  if map_source == 4
    map_pool = symmetry
  mi = 0 ## i64
  while mi < map_pool.size()
    z = ffme_add(map_states, map_keys, map_uses, map_sources, map_pool[mi], ffw_best_rank(best), N, MAP_CAPACITY, map_source)
    mi += 1
  map_source += 1

# Pick the best exact C3 member from the complete frontier archive. This also
# recovers older, structurally distant symmetry seeds when the density leader
# itself is asymmetric for another tensor size.
archive_index = 0 ## i64
while archive_index < archive.size()
  c3 = archive[archive_index]
  if ffn_state_is_c3(c3, N, CAPACITY) == 1
    choose_c3 = 0 ## i64
    if c3_base == nil
      choose_c3 = 1
    if c3_base != nil
      if ffn_better(ffw_best_rank(c3), ffw_best_bits(c3), ffw_best_rank(c3_base), ffw_best_bits(c3_base)) == 1
        choose_c3 = 1
    if choose_c3 == 1
      c3_base = ffn_clone_trusted(c3, STATE_SIZE, 37 + archive_index)
  archive_index += 1

z = ffn_add_c3_family(c3_base, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, symmetry, orbit_bank, polar_bank, SYMMETRY_CAP) ## i64

# Sticky CPU islands.
states = []
doors = i64[J]
zones = i64[J]
sources = []
active_near_seeds = []
active_seed_ranks = i64[J]
active_seed_start_moves = i64[J]
active_seed_finished = i64[J]
island_best_ranks = i64[J]
debt_launches = i64[4]
debt_returns = i64[4]
debt_failures = i64[4]
debt_exposure = i64[4]
cursor = i64[7]
last_seen_rank = i64[J]
last_seen_bits = i64[J]
last_moves = i64[J]
last_rates = i64[J]
cpu_elapsed_ms = i64[J]
last_ages = i64[J]
last_progress_ms = i64[J]
symmetry_cpu_uses = 0 ## i64
i = 0 ## i64
while i < J
  doors[i] = ffp_door_gpu(N, i, GPU)
  if STRATEGY == "converge"
    doors[i] = 0
  zones[i] = ffp_zone(i)
  st = i64[STATE_SIZE]
  z = ffw_init_naive_cap(st, N, CAPACITY, 101 + i * 97, DSLACK, CYCLES, cpu_work_moves[zones[i]], cpu_wander_moves[zones[i]]) ## i64
  selected = ffn_pick_seed(doors[i], best, anchor, archive, near1, near2, near1_uses, near2_uses, symmetry, mixed, states, cursor, i)
  active_near_seed = nil
  seed_door0 = ffp_seed_door(doors[i]) ## i64
  if seed_door0 == 2 && near1.size() > 0
    active_near_seed = selected
  if seed_door0 == 3 && near2.size() > 0
    active_near_seed = selected
  if seed_door0 == 4 && symmetry.size() > 0
    symmetry_cpu_uses += 1
  z = ffw_reseed_from(st, selected, 1009 + i * 131)
  if z < 1
    z = ffw_reseed_from(st, anchor, 2003 + i * 131)
    active_near_seed = nil
  states.push(st)
  active_near_seeds.push(active_near_seed)
  active_seed_ranks[i] = ffw_best_rank(selected)
  active_seed_start_moves[i] = ffw_moves(st)
  active_seed_finished[i] = 0
  island_best_ranks[i] = ffw_best_rank(st)
  seed_debt = active_seed_ranks[i] - ffw_best_rank(best) ## i64
  if seed_debt > 0
    z = ffrd_launch(seed_debt, debt_launches)
  source_name = ffp_door_name(doors[i])
  source_name = source_name + "/seed" + (ffn_current_basin_id(selected) % 100000).to_s()
  if ffn_door_has_native_seed(doors[i], archive, near1, near2, symmetry, mixed) == 0
    source_name = source_name + "/leader-fallback"
  sources.push(source_name)
  last_seen_rank[i] = ffw_best_rank(st)
  last_seen_bits[i] = ffw_best_bits(st)
  last_moves[i] = ffw_moves(st)
  last_rates[i] = 0
  last_ages[i] = 0
  last_progress_ms[i] = ccall("__w_clock_ms")
  i += 1

# One CPU control lane freezes the consensus core and mutates only an n^2-term
# fringe. It replaces the redundant anchor walker; the anchor itself remains
# retained and available to every restart path.
core_fringe_index = 0 - 1 ## i64
core_fringe_slots = 0 ## i64
if STRATEGY == "islands" && J > 1
  core_fringe_index = J - 1
  # The 12-slot profile reserves slot 11 as its anchor/marathon control.
  # Hardware-derived J may add workers beyond that pattern; keep the control
  # on slot 11 so extra breadth does not accidentally turn it into a short
  # frontier lane.
  if J >= 12
    core_fringe_index = 11
  core_out = i64[1]
  core_state = ffn_core_fringe_state(best, archive, near1, near2, mixed, N, CAPACITY, STATE_SIZE, 41003, DSLACK, CYCLES, cpu_work_moves[zones[core_fringe_index]], cpu_wander_moves[zones[core_fringe_index]], core_out)
  if core_state != nil
    states[core_fringe_index] = core_state
    core_fringe_slots = core_out[0]
    active_near_seeds[core_fringe_index] = nil
    active_seed_ranks[core_fringe_index] = ffw_best_rank(core_state)
    active_seed_start_moves[core_fringe_index] = 0
    active_seed_finished[core_fringe_index] = 1
    sources[core_fringe_index] = "core-fringe/frozen-" + core_fringe_slots.to_s()

# The constrained core/fringe move is substantially more expensive than an
# ordinary flip.  Give the control lane an initially time-balanced quota, then
# adapt it from measured per-thread wall time so it never becomes a barrier for
# the productive islands.
core_round_steps = STEPS ## i64
if core_fringe_index >= 0
  core_round_steps = STEPS / 5
  if core_round_steps < 1
    core_round_steps = 1

# Cohort exposure counters, indexed door*4+zone.
cohort_moves = i64[28]
cohort_drops = i64[28]
cohort_ties = i64[28]
cohort_near = i64[28]

# GPU role telemetry and initial evidence-guided allocation.  The dedicated
# native engine bundle owns process/device execution; these arrays are the ABI
# consumed by the TUI and adaptive policy.
gpu_lanes = i64[11]
gpu_candidates = i64[11]
gpu_rank_drops = i64[11]
gpu_density = i64[11]
gpu_rewards = i64[11]
gpu_epochs = i64[11]
gpu_lane_epochs = i64[11]
gpu_epoch_rewards = i64[11]
gpu_pareto = i64[11]
gpu_failures = i64[11]
gpu_disabled = i64[11]
gpu_retry_round = i64[11]
gpu_seed_ranks = i64[11]
# Physical execution slots 10..12 are independent children of logical role 10.
# Keeping launch-local state physical prevents concurrent pool workers from
# sharing paths, elapsed time, seed debt, or reward attribution.
gpu_launch_lanes = i64[13]
gpu_launch_debt = i64[13]
gpu_elapsed_ms = i64[13]
gpu_launch_generation = i64[13]
fleet_generation = 0 ## i64
gpu_wall_ms = i64[11]
gpu_eligible = i64[11]
gpu_weights = i64[11]
gpu_launch_number = i64[11]
gpu_transition_exposure = i64[11 * ffkp_context_count()]
gpu_transition_rewards = i64[11 * ffkp_context_count()]
pool_stat_slots = ffkp_mode_count() * ffkp_context_count() ## i64
pool_pulls = i64[pool_stat_slots]
pool_rewards = i64[pool_stat_slots]
pool_exposure = i64[pool_stat_slots]
pool_mode_ready = i64[ffkp_mode_count()]
pool_active_modes = i64[ffkp_mode_count()]
pool_modes = i64[3]
pool_slot_lanes = i64[3]
pool_slot_groups = i64[3]
pool_slot_retry_round = i64[3]
pool_slot_launch_numbers = i64[3]
pool_group_epochs = i64[3]
pool_drain_anchors = i64[3]
pool_drain_active = 0 ## i64
pool_slot = 0 ## i64
while pool_slot < 3
  pool_modes[pool_slot] = 0 - 1
  pool_slot_groups[pool_slot] = 0 - 1
  pool_slot += 1
pool_last_modes = i64[3]
pool_last_modes[0] = 6
pool_last_modes[1] = 3
pool_last_modes[2] = 10
pool_selection_epoch = 0 ## i64
gpu_threads = []
gpu_role = 0 ## i64
while gpu_role < 13
  gpu_threads.push(nil)
  gpu_role += 1
gpu_degraded = 0 ## i64
gpu_ready = 0 ## i64
if GPU == 1
  has_c3 = 0 ## i64
  if c3_base != nil
    has_c3 = 1
  active_gpu_roles = ffg_fill_profile(N, has_c3, gpu_eligible, gpu_weights) ## i64
  if orbit_bank.size() == 0
    gpu_eligible[5] = 0
  if polar_bank.size() == 0
    gpu_eligible[6] = 0
  if GPU_POLICY == "single"
    single_role = 1 ## i64
    while single_role < 11
      gpu_eligible[single_role] = 0
      single_role += 1
  gpu_generic_ready = 0 ## i64
  gpu_c3_ready = 0 ## i64
  gpu_simd_ready = 0 ## i64
  gpu_mitm_ready = 0 ## i64
  gpu_constraint_ready = 0 ## i64
  gpu_kxor_ready = 0 ## i64
  gpu_pool_ready = 0 ## i64
  gpu_degraded = 0

  if GPU_BINARY == ""
    GPU_BINARY = "/tmp/flipfleet_gpu_cal2zone_" + N.to_s()
  needs_build = GPU_REBUILD ## i64
  if needs_build == 0 && ffn_binary_fresh(GPU_BINARY, ffb_source_path(REPO_ROOT, N), ffb_metal_path(REPO_ROOT, N)) == 0
    needs_build = 1
  if needs_build == 1
    if QUIET == 0
      << "flipfleet: compiling checked-in Tungsten/Metal GPU bundle for " + N.to_s() + "x" + N.to_s()
      flush()
    gpu_generic_ready = ffb_build(REPO_ROOT, N, GPU_BINARY)
  if needs_build == 0
    gpu_generic_ready = 1

  C3_BINARY = "/tmp/flipfleet_gpu_c3_" + N.to_s()
  if gpu_eligible[2] != 0
    c3_needs_build = GPU_REBUILD ## i64
    if c3_needs_build == 0 && ffn_binary_fresh(C3_BINARY, ffc3_source_path(REPO_ROOT, N), ffc3_metal_path(REPO_ROOT, N)) == 0
      c3_needs_build = 1
    if c3_needs_build == 1
      gpu_c3_ready = ffc3_build(REPO_ROOT, N, C3_BINARY)
    if c3_needs_build == 0
      gpu_c3_ready = 1
    if gpu_c3_ready == 0
      gpu_eligible[2] = 0
      gpu_disabled[2] = 1
      gpu_failures[2] = gpu_failures[2] + 1
      gpu_retry_round[2] = 1
      gpu_degraded = 1

  SIMD_BINARY = "/tmp/flipfleet_gpu_simd_" + N.to_s()
  if gpu_eligible[9] != 0
    simd_needs_build = GPU_REBUILD ## i64
    if simd_needs_build == 0 && ffn_binary_fresh(SIMD_BINARY, ffsimd_source_path(REPO_ROOT, N), ffsimd_metal_path(REPO_ROOT, N)) == 0
      simd_needs_build = 1
    if simd_needs_build == 1
      gpu_simd_ready = ffsimd_build(REPO_ROOT, N, SIMD_BINARY)
    if simd_needs_build == 0
      gpu_simd_ready = 1
    if gpu_simd_ready == 0
      gpu_eligible[9] = 0
      gpu_disabled[9] = 1
      gpu_failures[9] = gpu_failures[9] + 1
      gpu_retry_round[9] = 1
      gpu_degraded = 1

  MITM_BINARY = "/tmp/flipfleet_gpu_mitm"
  if gpu_eligible[10] != 0
    mitm_needs_build = GPU_REBUILD ## i64
    mitm_source = REPO_ROOT + "/benchmarks/matmul/metaflip/flipfleet_mitm_lane.w"
    mitm_sidecar = REPO_ROOT + "/benchmarks/matmul/metaflip/flipfleet_mitm_lane.metal"
    if mitm_needs_build == 0 && ffn_binary_fresh(MITM_BINARY, mitm_source, mitm_sidecar) == 0
      mitm_needs_build = 1
    if mitm_needs_build == 1
      gpu_mitm_ready = ffn_mitm_build(REPO_ROOT, MITM_BINARY)
    if mitm_needs_build == 0
      gpu_mitm_ready = 1

    CONSTRAINT_BINARY = "/tmp/flipfleet_gpu_constraint_pool"
    constraint_source = REPO_ROOT + "/benchmarks/matmul/metaflip/flipfleet_constraint_pool_lib.w"
    constraint_needs_build = GPU_REBUILD ## i64
    constraint_sidecar = REPO_ROOT + "/benchmarks/matmul/metaflip/flipfleet_constraint_pool.metal"
    if constraint_needs_build == 0 && ffn_binary_fresh(CONSTRAINT_BINARY, constraint_source, constraint_sidecar) == 0
      constraint_needs_build = 1
    if constraint_needs_build == 1
      gpu_constraint_ready = ffn_pool_worker_build(REPO_ROOT, CONSTRAINT_BINARY, "benchmarks/matmul/metaflip/flipfleet_constraint_pool.w")
    if constraint_needs_build == 0
      gpu_constraint_ready = 1

    KXOR_BINARY = "/tmp/flipfleet_gpu_kxor_pool"
    kxor_source = REPO_ROOT + "/benchmarks/matmul/metaflip/flipfleet_kxor_pool_lib.w"
    kxor_needs_build = GPU_REBUILD ## i64
    kxor_sidecar = REPO_ROOT + "/benchmarks/matmul/metaflip/flipfleet_kxor_pool.metal"
    if kxor_needs_build == 0 && ffn_binary_fresh(KXOR_BINARY, kxor_source, kxor_sidecar) == 0
      kxor_needs_build = 1
    if kxor_needs_build == 1
      gpu_kxor_ready = ffn_pool_worker_build(REPO_ROOT, KXOR_BINARY, "benchmarks/matmul/metaflip/flipfleet_kxor_pool.w")
    if kxor_needs_build == 0
      gpu_kxor_ready = 1

    gpu_pool_ready = ffn_fill_pool_readiness(pool_mode_ready, gpu_generic_ready, gpu_mitm_ready, gpu_constraint_ready, gpu_kxor_ready, orbit_bank, polar_bank)
    if gpu_pool_ready == 0
      gpu_eligible[10] = 0
      gpu_disabled[10] = 1
      gpu_failures[10] = gpu_failures[10] + 1
      gpu_retry_round[10] = 1
      gpu_degraded = 1

  if gpu_generic_ready == 0
    gpu_role = 0
    while gpu_role < 11
      if ffg_engine_kind(gpu_role) == 0
        gpu_eligible[gpu_role] = 0
        gpu_disabled[gpu_role] = 1
        gpu_failures[gpu_role] = gpu_failures[gpu_role] + 1
        gpu_retry_round[gpu_role] = 1
      gpu_role += 1
    gpu_degraded = 1
  if gpu_generic_ready == 1 || gpu_c3_ready == 1 || gpu_simd_ready == 1 || gpu_pool_ready > 0
    gpu_ready = 1

  pool_count = 0 ## i64
  if gpu_eligible[10] != 0
    pool_count = ffkp_select_group_modes_ready(pool_selection_epoch, N, ffw_best_rank(best), 0, GPU_WALKERS, pool_mode_ready, pool_last_modes, pool_pulls, pool_rewards, pool_modes)
  pool_budget = ffkp_allocate_selected_lanes(GPU_WALKERS, pool_modes, pool_count, pool_slot_lanes) ## i64
  pool_selection_epoch += 1
  floors_covered = ffg_initial_allocate_pool(GPU_WALKERS, pool_budget, gpu_eligible, gpu_weights, gpu_lanes) ## i64
  if gpu_ready == 0
    gpu_role = 0
    while gpu_role < 11
      gpu_eligible[gpu_role] = 0
      gpu_lanes[gpu_role] = 0
      gpu_role += 1
  if floors_covered == 0
    gpu_degraded = 1
  if gpu_ready == 1
    gpu_role = 0
    while gpu_role < 10
      if gpu_eligible[gpu_role] != 0 && gpu_lanes[gpu_role] > 0
        gpu_seed = ffn_gpu_role_seed(gpu_role, gpu_launch_number[gpu_role], best, archive, near1, near2, mixed, c3_base, orbit_bank, polar_bank, gpu_pareto_archive, gpu_pareto_bits, gpu_pareto_pairs, gpu_pareto_novelties, gpu_pareto_uses, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander)
        if gpu_seed == nil
          gpu_eligible[gpu_role] = 0
          gpu_lanes[gpu_role] = 0
          gpu_disabled[gpu_role] = 1
          gpu_failures[gpu_role] = gpu_failures[gpu_role] + 1
          gpu_retry_round[gpu_role] = 1
          gpu_degraded = 1
        else
          gpu_seed_ranks[gpu_role] = ffw_best_rank(gpu_seed)
          gpu_launch_debt[gpu_role] = gpu_seed_ranks[gpu_role] - ffw_best_rank(best)
          gpu_launch_lanes[gpu_role] = gpu_lanes[gpu_role]
          gpu_elapsed_ms[gpu_role] = 0
          gpu_launch_generation[gpu_role] = fleet_generation
          engine_kind = ffg_engine_kind(gpu_role) ## i64
          if engine_kind == 0
            gpu_threads[gpu_role] = ffn_gpu_launch(REPO_ROOT, GPU_BINARY, RUN_TAG, N, gpu_role, gpu_lanes[gpu_role], GPU_STEPS, GPU_EPOCH_ROUNDS, gpu_seed, gpu_elapsed_ms)
          if engine_kind == 1
            gpu_threads[gpu_role] = ffn_gpu_launch_c3(REPO_ROOT, C3_BINARY, RUN_TAG, N, gpu_lanes[gpu_role], gpu_seed, gpu_elapsed_ms)
          if engine_kind == 2
            gpu_threads[gpu_role] = ffn_gpu_launch_simd(REPO_ROOT, SIMD_BINARY, RUN_TAG, N, gpu_lanes[gpu_role], gpu_seed, gpu_elapsed_ms)
          if gpu_threads[gpu_role] == nil
            gpu_eligible[gpu_role] = 0
            gpu_lanes[gpu_role] = 0
            gpu_disabled[gpu_role] = 1
            gpu_failures[gpu_role] = gpu_failures[gpu_role] + 1
            gpu_retry_round[gpu_role] = 1
            gpu_degraded = 1
          else
            gpu_launch_number[gpu_role] = gpu_launch_number[gpu_role] + 1
      gpu_role += 1

    # The aggregate pool role owns three physical workers.  Each child has a
    # distinct strategy family, seed/output/log namespace, launch ordinal,
    # rank-debt context, and elapsed-time cell.
    pool_drain_active = 0
    pool_slot = 0
    while pool_slot < 3
      pool_drain_anchors[pool_slot] = 0
      pool_slot += 1
    pool_launched_lanes = 0 ## i64
    pool_launched_count = 0 ## i64
    pool_slot = 0
    while pool_slot < pool_count
      pool_mode = pool_modes[pool_slot] ## i64
      pool_lanes = pool_slot_lanes[pool_slot] ## i64
      gpu_slot = 10 + pool_slot ## i64
      if pool_mode >= 0 && pool_lanes > 0 && gpu_eligible[10] != 0
        pool_group = ffkp_mode_group(pool_mode) ## i64
        pool_slot_groups[pool_slot] = pool_group
        pool_launch_number = gpu_launch_number[10] ## i64
        pool_slot_launch_numbers[pool_slot] = pool_launch_number
        gpu_seed = ffn_pool_seed(pool_mode, pool_launch_number, best, map_states, map_uses, c3_base, orbit_bank, polar_bank, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander)
        if gpu_seed != nil
          gpu_seed_rank = ffw_best_rank(gpu_seed) ## i64
          if pool_launched_count == 0 || gpu_seed_rank < gpu_seed_ranks[10]
            gpu_seed_ranks[10] = gpu_seed_rank
          gpu_launch_debt[gpu_slot] = gpu_seed_rank - ffw_best_rank(best)
          gpu_launch_lanes[gpu_slot] = pool_lanes
          gpu_elapsed_ms[gpu_slot] = 0
          gpu_launch_generation[gpu_slot] = fleet_generation
          gpu_threads[gpu_slot] = ffn_gpu_launch_pool(REPO_ROOT, GPU_BINARY, MITM_BINARY, CONSTRAINT_BINARY, KXOR_BINARY, RUN_TAG, N, gpu_slot, pool_mode, pool_lanes, GPU_STEPS, GPU_EPOCH_ROUNDS, pool_launch_number, gpu_seed, gpu_elapsed_ms)
        if gpu_seed == nil || gpu_threads[gpu_slot] == nil
          gpu_failures[10] = gpu_failures[10] + 1
          gpu_degraded = 1
          pool_modes[pool_slot] = 0 - 1
          pool_slot_retry_round[pool_slot] = 1
        else
          pool_active_modes[pool_mode] = 1
          z = ffkp_record_launch(pool_mode, N, gpu_launch_debt[gpu_slot], pool_lanes / 32, pool_pulls, pool_exposure)
          pool_last_modes[pool_group] = pool_mode
          pool_group_epochs[pool_group] = pool_group_epochs[pool_group] + 1
          pool_slot_retry_round[pool_slot] = 0
          gpu_launch_number[10] = gpu_launch_number[10] + 1
          pool_launched_lanes += pool_lanes
          pool_launched_count += 1
      pool_slot += 1
    gpu_lanes[10] = pool_launched_lanes
    if gpu_eligible[10] != 0 && pool_budget > 0 && pool_launched_count == 0
      gpu_eligible[10] = 0
      gpu_disabled[10] = 1
      gpu_retry_round[10] = 1

timeline_times = i64[256]
timeline_ranks = i64[256]
timeline_count = 1 ## i64
timeline_times[0] = 0
timeline_ranks[0] = ffw_best_rank(best)
timeline_start_s = 0 ## i64

# Run-length best rank/density history feeding the header sparklines: one
# entry per distinct level plus how many render ticks it was held, so a long
# plateau compresses to at most three glyphs instead of flattening the line.
rank_levels = i64[256]
rank_ticks = i64[256]
rank_level_count = 0 ## i64
bits_levels = i64[256]
bits_ticks = i64[256]
bits_level_count = 0 ## i64

start_ms = ccall("__w_clock_ms") ## i64
last_status_ms = 0 - 1 ## i64
last_render_ms = 0 - 1 ## i64
sequence = 0 ## i64
# First Ctrl-C latches a cooperative stop (drain GPU epochs, save state);
# the second hard-exits inside the runtime latch.
trap_ok = ccall("__w_trap_interrupts")
interrupted = 0 ## i64
# Raw keyboard for TUI controls (no-op when stdin is not a tty).  Raw mode
# clears ISIG, so Ctrl-C arrives as byte 3 and is handled in the key loop.
stop_key = 0 ## i64
flash_text = ""
flash_until_ms = 0 ## i64
if TUI == 1
  ccall("w_term_raw_enable")
round = 0 ## i64
total_moves = 0 ## i64
new_bests = 0 ## i64
tie_bests = 0 ## i64
invalid_candidates = 0 ## i64
cycleouts = 0 ## i64
basin_rotations = 0 ## i64
running = 1 ## i64

if QUIET == 0 && TUI == 0
  << "flipfleet native: tensor=" + N.to_s() + "x" + N.to_s() + " walkers=" + J.to_s() + " strategy=" + STRATEGY + " gpu=" + GPU.to_s() + " policy=" + GPU_POLICY + " banks=" + mixed.size().to_s()
  flush()

while running == 1
  threads = []
  i = 0
  while i < J
    worker_state = states[i]
    cpu_elapsed_ms[i] = 0
    t = nil
    if i != core_fringe_index
      t = ffn_spawn_cpu_walk(worker_state, STEPS, cpu_elapsed_ms, i)
    if i == core_fringe_index
      t = ffn_spawn_cpu_fringe(worker_state, core_round_steps, core_fringe_slots, cpu_elapsed_ms, i)
    threads.push(t)
    i += 1
  i = 0
  while i < J
    threads[i].join
    i += 1

  if core_fringe_index >= 0 && cpu_elapsed_ms[core_fringe_index] > 0
    ordinary_ms = 0 ## i64
    ordinary_count = 0 ## i64
    i = 0
    while i < J
      if i != core_fringe_index && cpu_elapsed_ms[i] > 0
        ordinary_ms += cpu_elapsed_ms[i]
        ordinary_count += 1
      i += 1
    if ordinary_count > 0
      target_ms = ordinary_ms / ordinary_count ## i64
      proposed_core_steps = core_round_steps * target_ms / cpu_elapsed_ms[core_fringe_index] ## i64
      min_core_steps = STEPS / 64 ## i64
      if min_core_steps < 1
        min_core_steps = 1
      if proposed_core_steps < min_core_steps
        proposed_core_steps = min_core_steps
      if proposed_core_steps > STEPS
        proposed_core_steps = STEPS
      core_round_steps = (core_round_steps * 3 + proposed_core_steps) / 4
      if core_round_steps < 1
        core_round_steps = 1

  now_ms = ccall("__w_clock_ms") ## i64
  elapsed_s = (now_ms - start_ms) / 1000 ## i64
  strict_drop = 0 ## i64
  demoted_frontiers = []
  preserved_shoulders = []

  # TUI controls, polled between rounds while every walker thread is joined
  # (states are safe to mutate here).  Space starts a fresh naive frontier and
  # rank timeline; q / Ctrl-C (byte 3 in raw mode) = cooperative stop, twice = force.
  if TUI == 1
    key = ccall("w_input_poll", 0) ## i64
    keys_seen = 0 ## i64
    while key >= 0 && keys_seen < 8
      if key == 32
        rw = 0 ## i64
        while rw < J
          z = ffw_init_naive_cap(states[rw], N, CAPACITY, 50021 + round * 131 + rw * 977, DSLACK, CYCLES, cpu_work_moves[zones[rw]], cpu_wander_moves[zones[rw]]) ## i64
          active_near_seeds[rw] = nil
          active_seed_ranks[rw] = ffw_best_rank(states[rw])
          active_seed_start_moves[rw] = ffw_moves(states[rw])
          active_seed_finished[rw] = 0
          island_best_ranks[rw] = ffw_best_rank(states[rw])
          sources[rw] = ffp_door_name(doors[rw]) + "/manual-naive"
          last_seen_rank[rw] = ffw_best_rank(states[rw])
          last_seen_bits[rw] = ffw_best_bits(states[rw])
          last_moves[rw] = ffw_moves(states[rw])
          last_progress_ms[rw] = now_ms
          rw += 1

        # Space starts a fresh frontier, not merely fresh CPU working states.
        # Clone the exact naive seed so the leader never aliases a mutable
        # island, retire in-flight GPU results from the previous generation,
        # and rebuild every best-relative seed bank around the new baseline.
        naive_best = ffn_clone_exact(states[0], N, CAPACITY, STATE_SIZE, 50023 + round * 131, DSLACK, CYCLES, balanced_work, balanced_wander)
        if naive_best != nil
          best = naive_best
          recovered = 0
          fleet_generation += 1

          timeline_start_s = elapsed_s
          timeline_count = 1
          timeline_times[0] = 0
          timeline_ranks[0] = ffw_best_rank(best)
          rank_level_count = 1
          rank_levels[0] = ffw_best_rank(best)
          rank_ticks[0] = 1
          bits_level_count = 1
          bits_levels[0] = ffw_best_bits(best)
          bits_ticks[0] = 1
          new_bests = 0
          tie_bests = 0

          archive.clear
          archive_counters = i64[3]
          near_counters = i64[5]
          gpu_pareto_archive.clear
          gpu_pareto_ranks.clear
          gpu_pareto_bits.clear
          gpu_pareto_pairs.clear
          gpu_pareto_novelties.clear
          gpu_pareto_roles.clear
          gpu_pareto_uses.clear
          gpu_pareto_counters = i64[4]
          map_states.clear
          map_keys.clear
          map_uses.clear
          map_sources.clear
          cursor = i64[7]

          naive_archive = ffn_clone_trusted(best, STATE_SIZE, 50029 + round * 131)
          if naive_archive != nil
            archive.push(naive_archive)
          z = ffn_build_escape_banks(best, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, near1, near2, near1_signatures, near1_uses, near1_successes, near2_signatures, near2_uses, near2_successes, symmetry, mixed, orbit_bank, polar_bank, near1_capacity, near2_capacity, NEAR_SIGNATURE_QUOTA, SYMMETRY_CAP, near_counters)
          c3_base = nil
          if ffn_state_is_c3(best, N, CAPACITY) == 1
            c3_base = ffn_clone_trusted(best, STATE_SIZE, 50031 + round * 131)
          z = ffn_add_c3_family(c3_base, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, symmetry, orbit_bank, polar_bank, SYMMETRY_CAP)

          reset_map_pool = archive
          reset_map_source = 0 ## i64
          while reset_map_source < 5
            if reset_map_source == 1
              reset_map_pool = near1
            if reset_map_source == 2
              reset_map_pool = near2
            if reset_map_source == 3
              reset_map_pool = mixed
            if reset_map_source == 4
              reset_map_pool = symmetry
            reset_map_index = 0 ## i64
            while reset_map_index < reset_map_pool.size()
              z = ffme_add(map_states, map_keys, map_uses, map_sources, reset_map_pool[reset_map_index], ffw_best_rank(best), N, MAP_CAPACITY, reset_map_source)
              reset_map_index += 1
            reset_map_source += 1
          archive_min_cache = ffn_archive_min_distance(archive)
          symmetry_cpu_uses = 0

          if core_fringe_index >= 0
            reset_core_out = i64[1]
            reset_core = ffn_core_fringe_state(best, archive, near1, near2, mixed, N, CAPACITY, STATE_SIZE, 50037 + round * 131, DSLACK, CYCLES, cpu_work_moves[zones[core_fringe_index]], cpu_wander_moves[zones[core_fringe_index]], reset_core_out)
            if reset_core != nil
              states[core_fringe_index] = reset_core
              core_fringe_slots = reset_core_out[0]
              active_near_seeds[core_fringe_index] = nil
              active_seed_ranks[core_fringe_index] = ffw_best_rank(reset_core)
              active_seed_start_moves[core_fringe_index] = ffw_moves(reset_core)
              active_seed_finished[core_fringe_index] = 1
              island_best_ranks[core_fringe_index] = ffw_best_rank(reset_core)
              sources[core_fringe_index] = "core-fringe/manual-naive-" + core_fringe_slots.to_s()
              last_seen_rank[core_fringe_index] = ffw_best_rank(reset_core)
              last_seen_bits[core_fringe_index] = ffw_best_bits(reset_core)
              last_moves[core_fringe_index] = ffw_moves(reset_core)
              last_progress_ms[core_fringe_index] = now_ms

          reset_saved = ffn_dump_trusted(best, BEST_PATH, RUN_TAG) ## i64
          if reset_saved < 1
            gpu_degraded = 1
            flash_text = "fleet best reset to naive; checkpoint write failed"
          if reset_saved >= 1
            flash_text = "fleet best and rank timeline reset to naive (r" + ffw_best_rank(best).to_s + ")"
        if naive_best == nil
          flash_text = "naive reseed failed exact best clone; fleet best unchanged"
        flash_until_ms = now_ms + 4000
      if key == 119 || key == 87
        rw = 0 ## i64
        while rw < J
          z = ffw_reseed_from(states[rw], anchor, 52021 + round * 137 + rw * 991) ## i64
          active_near_seeds[rw] = nil
          active_seed_ranks[rw] = ffw_best_rank(states[rw])
          active_seed_start_moves[rw] = ffw_moves(states[rw])
          active_seed_finished[rw] = 1
          sources[rw] = ffp_door_name(doors[rw]) + "/manual-record"
          last_seen_rank[rw] = ffw_best_rank(states[rw])
          last_seen_bits[rw] = ffw_best_bits(states[rw])
          last_moves[rw] = ffw_moves(states[rw])
          last_progress_ms[rw] = now_ms
          rw += 1
        flash_text = "fleet reseeded on the record anchor (r" + ffw_best_rank(anchor).to_s + ")"
        flash_until_ms = now_ms + 4000
      if key == 3 || key == 113 || key == 81
        if stop_key == 1
          ccall("w_term_raw_disable")
          exit(130)
        stop_key = 1
        flash_text = "stopping — draining GPU epochs and saving state"
        flash_until_ms = now_ms + 10000
      keys_seen += 1
      key = ccall("w_input_poll", 0) ## i64

  i = 0
  while i < J
    state = states[i]
    rank = ffw_best_rank(state) ## i64
    bits = ffw_best_bits(state) ## i64
    moves_now = ffw_moves(state) ## i64
    delta_moves = moves_now - last_moves[i] ## i64
    if delta_moves < 0
      delta_moves = moves_now
    if delta_moves > 0
      last_progress_ms[i] = now_ms
    worker_ms = cpu_elapsed_ms[i] ## i64
    if worker_ms < 1
      worker_ms = 1
    last_rates[i] = delta_moves * 1000 / worker_ms
    total_moves += delta_moves
    cohort_index = ffp_seed_door(doors[i]) * 4 + zones[i] ## i64
    if cohort_index < 0
      cohort_index = 0
    if cohort_index > 27
      cohort_index = 27
    cohort_moves[cohort_index] = cohort_moves[cohort_index] + delta_moves
    if rank != last_seen_rank[i] || bits != last_seen_bits[i]
      exact = ffw_verify_best_exact(state, N) ## i64
      if exact == 1
        if rank > 0
          if island_best_ranks[i] <= 0 || rank < island_best_ranks[i]
            island_best_ranks[i] = rank
        if active_seed_finished[i] == 0
          seed_debt = active_seed_ranks[i] - ffw_best_rank(best) ## i64
          if seed_debt > 0 && rank <= ffw_best_rank(best)
            spent = moves_now - active_seed_start_moves[i] ## i64
            z = ffrd_finish(seed_debt, 1, spent, debt_returns, debt_failures, debt_exposure)
            active_seed_finished[i] = 1
        map_candidate = ffn_clone_trusted(state, STATE_SIZE, 7001 + round * 23 + i)
        if map_candidate != nil
          z = ffme_add(map_states, map_keys, map_uses, map_sources, map_candidate, ffw_best_rank(best), N, MAP_CAPACITY, doors[i])
          # Preserve structurally novel equal-frontier CPU returns even when
          # they do not beat the density leader. Previously only GPU returns
          # received this raw-distance archive admission.
          if rank == ffw_best_rank(best)
            z = ffn_archive_add(archive, map_candidate, ARCHIVE_CAP, 4, archive_counters)
            archive_min_cache = ffn_archive_min_distance(archive)
        if active_near_seeds[i] != nil
          if rank < ffw_best_rank(active_near_seeds[i])
            seed_door_s = ffp_seed_door(doors[i]) ## i64
            if seed_door_s == 2
              z = ffbp_mark_success(near1, near1_successes, active_near_seeds[i]) ## i64
            if seed_door_s == 3
              z = ffbp_mark_success(near2, near2_successes, active_near_seeds[i]) ## i64
            active_near_seeds[i] = nil
        if ffn_state_is_c3(state, N, CAPACITY) == 1
          c3_better = 0 ## i64
          if c3_base == nil
            c3_better = 1
          if c3_base != nil
            c3_better = ffn_better(rank, bits, ffw_best_rank(c3_base), ffw_best_bits(c3_base))
          if c3_better == 1
            c3_candidate = ffn_clone_trusted(state, STATE_SIZE, 8003 + round * 29 + i)
            if c3_candidate != nil
              c3_base = c3_candidate
              symmetry.clear
              orbit_bank.clear
              polar_bank.clear
              z = ffn_add_c3_family(c3_base, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, symmetry, orbit_bank, polar_bank, SYMMETRY_CAP) ## i64
        if ffn_better(rank, bits, ffw_best_rank(best), ffw_best_bits(best)) == 1
          old_rank = ffw_best_rank(best) ## i64
          replacement = ffn_clone_trusted(state, STATE_SIZE, 9001 + round * 31 + i)
          if replacement != nil
            if rank < old_rank
              if strict_drop == 0
                pi = 0 ## i64
                while pi < near1.size()
                  preserved_shoulders.push(near1[pi])
                  pi += 1
              demoted_frontiers.push(best)
            best = replacement
            if rank < old_rank
              new_bests += 1
              strict_drop = 1
              cohort_drops[cohort_index] = cohort_drops[cohort_index] + 1
            if rank == old_rank
              tie_bests += 1
              cohort_ties[cohort_index] = cohort_ties[cohort_index] + 1
            if timeline_count < 256
              timeline_times[timeline_count] = elapsed_s - timeline_start_s
              timeline_ranks[timeline_count] = rank
              timeline_count += 1
            else
              ti = 0 ## i64
              while ti < 255
                timeline_times[ti] = timeline_times[ti + 1]
                timeline_ranks[ti] = timeline_ranks[ti + 1]
                ti += 1
              timeline_times[255] = elapsed_s - timeline_start_s
              timeline_ranks[255] = rank
            snapshot = ffn_clone_trusted(best, STATE_SIZE, 12001 + round * 37 + i)
            if snapshot != nil
              z = ffn_archive_add(archive, snapshot, ARCHIVE_CAP, 4, archive_counters) ## i64
              archive_min_cache = ffn_archive_min_distance(archive)
            z = ffn_dump_trusted(best, BEST_PATH, RUN_TAG)
            if z < 1
              gpu_degraded = 1
        fleet_rank = ffw_best_rank(best) ## i64
        if rank == fleet_rank + 1
          shoulder = ffn_clone_trusted(state, STATE_SIZE, 15001 + round * 41 + i)
          if shoulder != nil
            if ffbp_near_add(near1, near1_signatures, near1_uses, near1_successes, shoulder, near1_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters) == 1
              cohort_near[cohort_index] = cohort_near[cohort_index] + 1
        if rank == fleet_rank + 2
          shoulder = ffn_clone_trusted(state, STATE_SIZE, 17001 + round * 43 + i)
          if shoulder != nil
            if ffbp_near_add(near2, near2_signatures, near2_uses, near2_successes, shoulder, near2_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters) == 1
              cohort_near[cohort_index] = cohort_near[cohort_index] + 1
      if exact == 0
        invalid_candidates += 1
        qz = ffw_reseed_from(state, anchor, 19001 + round * 59 + i) ## i64
        sources[i] = ffp_door_name(doors[i]) + "/quarantine-anchor"
        rank = ffw_best_rank(state)
        bits = ffw_best_bits(state)
      last_seen_rank[i] = rank
      last_seen_bits[i] = bits
    last_moves[i] = moves_now
    last_ages[i] = (now_ms - last_progress_ms[i]) / 1000
    i += 1

  # Harvest completed bounded generic-GPU epochs.  The generated Tungsten host
  # already performs an exhaustive gate; loading here repeats the independent
  # coordinator gate before any candidate can affect a bank or fleet best.
  if GPU == 1 && gpu_ready == 1
    gpu_slot = 0 ## i64
    while gpu_slot < 13
      gpu_role = gpu_slot ## i64
      pool_child_slot = 0 - 1 ## i64
      completed_pool_mode = 0 - 1 ## i64
      if gpu_slot >= 10
        gpu_role = 10
        pool_child_slot = gpu_slot - 10
        completed_pool_mode = pool_modes[pool_child_slot]
      gpu_thread = gpu_threads[gpu_slot]
      if gpu_thread != nil
        if gpu_thread.alive? == false
          gpu_thread_result = gpu_thread.join
          launched_lanes = gpu_launch_lanes[gpu_slot] ## i64
          lane_chunks = launched_lanes / 32 ## i64
          if lane_chunks < 1
            lane_chunks = 1
          elapsed_quanta = (gpu_elapsed_ms[gpu_slot] + 99) / 100 ## i64
          if elapsed_quanta < 1
            elapsed_quanta = 1
          lane_exposure = lane_chunks * elapsed_quanta ## i64
          transition_context = ffkp_context(N, gpu_launch_debt[gpu_slot]) ## i64
          transition_index = gpu_role * ffkp_context_count() + transition_context ## i64
          gpu_transition_exposure[transition_index] = gpu_transition_exposure[transition_index] + lane_exposure
          gpu_wall_ms[gpu_role] = gpu_wall_ms[gpu_role] + gpu_elapsed_ms[gpu_slot]
          if gpu_thread_result == false
            gpu_failures[gpu_role] = gpu_failures[gpu_role] + 1
            gpu_degraded = 1
            if gpu_role != 10
              gpu_eligible[gpu_role] = 0
              gpu_lanes[gpu_role] = 0
              gpu_disabled[gpu_role] = 1
              gpu_retry_round[gpu_role] = round + ffn_gpu_retry_delay(gpu_failures[gpu_role])
            if pool_child_slot >= 0
              pool_slot_retry_round[pool_child_slot] = round + ffn_gpu_retry_delay(gpu_failures[10])
          gpu_threads[gpu_slot] = nil
          gpu_epochs[gpu_role] = gpu_epochs[gpu_role] + 1
          gpu_lane_epochs[gpu_role] = gpu_lane_epochs[gpu_role] + lane_exposure
          gpu_output = ffn_gpu_output_path(RUN_TAG, N, gpu_slot)
          raw_gpu_output = read_file(gpu_output)
          gpu_candidate = i64[STATE_SIZE]
          gpu_launch_is_current = 0 ## i64
          if gpu_launch_generation[gpu_slot] == fleet_generation
            gpu_launch_is_current = 1
          gpu_rank = 0 - 1 ## i64
          if gpu_launch_is_current == 1
            gpu_rank = ffw_load_scheme_cap(gpu_candidate, gpu_output, N, CAPACITY, 41001 + round * 61 + gpu_slot, DSLACK, CYCLES, balanced_work, balanced_wander)
          if gpu_rank > 0 && gpu_role == 2
            if ffn_state_is_c3(gpu_candidate, N, CAPACITY) == 0
              gpu_rank = 0 - 1
          if gpu_rank > 0
            gpu_bits = ffw_best_bits(gpu_candidate) ## i64
            before_rank = ffw_best_rank(best) ## i64
            before_bits = ffw_best_bits(best) ## i64
            novelty = ffn_distance(gpu_candidate, best) ## i64
            pareto_admitted = 0 ## i64
            if gpu_rank == before_rank
              gpu_snapshot = ffn_clone_trusted(gpu_candidate, STATE_SIZE, 43001 + round * 67 + gpu_role)
              if gpu_snapshot != nil
                pareto_admitted = ffbp_pareto_add(gpu_pareto_archive, gpu_pareto_ranks, gpu_pareto_bits, gpu_pareto_pairs, gpu_pareto_novelties, gpu_pareto_roles, gpu_pareto_uses, gpu_snapshot, best, GPU_NOVELTY_CAP, gpu_role, gpu_pareto_counters)
                if pareto_admitted == 1
                  pareto_index = ffbp_find_state(gpu_pareto_archive, gpu_snapshot) ## i64
                  if pareto_index >= 0
                    novelty = gpu_pareto_novelties[pareto_index]
                z = ffn_archive_add(archive, gpu_snapshot, ARCHIVE_CAP, 4, archive_counters) ## i64
                archive_min_cache = ffn_archive_min_distance(archive)
            c3_branch_reward = 0 ## i64
            if ffn_state_is_c3(gpu_candidate, N, CAPACITY) == 1
              c3_better = 0 ## i64
              old_c3_rank = 0 ## i64
              old_c3_bits = 0 ## i64
              if c3_base == nil
                c3_better = 1
              if c3_base != nil
                old_c3_rank = ffw_best_rank(c3_base)
                old_c3_bits = ffw_best_bits(c3_base)
                c3_better = ffn_better(gpu_rank, gpu_bits, old_c3_rank, old_c3_bits)
              if c3_better == 1
                c3_candidate = ffn_clone_trusted(gpu_candidate, STATE_SIZE, 45001 + round * 69 + gpu_role)
                if c3_candidate != nil
                  c3_base = c3_candidate
                  symmetry.clear
                  orbit_bank.clear
                  polar_bank.clear
                  z = ffn_add_c3_family(c3_base, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, symmetry, orbit_bank, polar_bank, SYMMETRY_CAP) ## i64
                  c3_branch_reward = 1000
                  if old_c3_rank > 0 && gpu_rank < old_c3_rank
                    c3_branch_reward = (old_c3_rank - gpu_rank) * 5000
                  if old_c3_rank == gpu_rank && old_c3_bits > gpu_bits
                    c3_branch_reward = (old_c3_bits - gpu_bits) * 2000 / old_c3_bits
                    if c3_branch_reward < 100
                      c3_branch_reward = 100
            reward = ffg_record_candidate(gpu_role, before_rank, gpu_rank, before_bits, gpu_bits, pareto_admitted, novelty, gpu_rewards, gpu_epoch_rewards, gpu_candidates, gpu_pareto, gpu_rank_drops, gpu_density) ## i64
            if gpu_role == 10 && completed_pool_mode >= 0
              z = ffkp_record_reward(completed_pool_mode, N, gpu_launch_debt[gpu_slot], reward, pool_rewards)
            map_snapshot = ffn_clone_trusted(gpu_candidate, STATE_SIZE, 44001 + round * 68 + gpu_role)
            if map_snapshot != nil
              z = ffme_add(map_states, map_keys, map_uses, map_sources, map_snapshot, ffw_best_rank(best), N, MAP_CAPACITY, 10 + gpu_role)
            if c3_branch_reward > 0
              gpu_rewards[gpu_role] = gpu_rewards[gpu_role] + c3_branch_reward
              gpu_epoch_rewards[gpu_role] = gpu_epoch_rewards[gpu_role] + c3_branch_reward
            gpu_transition_rewards[transition_index] = gpu_transition_rewards[transition_index] + reward + c3_branch_reward
            if ffn_better(gpu_rank, gpu_bits, before_rank, before_bits) == 1
              if gpu_rank < before_rank
                if strict_drop == 0
                  pi = 0 ## i64
                  while pi < near1.size()
                    preserved_shoulders.push(near1[pi])
                    pi += 1
                demoted_frontiers.push(best)
                strict_drop = 1
                new_bests += 1
              if gpu_rank == before_rank
                tie_bests += 1
              best = gpu_candidate
              if timeline_count < 256
                timeline_times[timeline_count] = elapsed_s - timeline_start_s
                timeline_ranks[timeline_count] = gpu_rank
                timeline_count += 1
              else
                ti = 0 ## i64
                while ti < 255
                  timeline_times[ti] = timeline_times[ti + 1]
                  timeline_ranks[ti] = timeline_ranks[ti + 1]
                  ti += 1
                timeline_times[255] = elapsed_s - timeline_start_s
                timeline_ranks[255] = gpu_rank
              z = ffn_dump_trusted(best, BEST_PATH, RUN_TAG)
              if z < 1
                gpu_degraded = 1
            fleet_rank = ffw_best_rank(best) ## i64
            if gpu_rank == fleet_rank + 1
              z = ffbp_near_add(near1, near1_signatures, near1_uses, near1_successes, gpu_candidate, near1_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters)
            if gpu_rank == fleet_rank + 2
              z = ffbp_near_add(near2, near2_signatures, near2_uses, near2_successes, gpu_candidate, near2_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters)
          if gpu_rank <= 0 && gpu_launch_is_current == 1
            if raw_gpu_output != nil
              if raw_gpu_output.size() > 0
                # A worker may report a provisional algebraic improvement that
                # loses the independent n^6 gate.  That is a rejected search
                # candidate, not lost GPU coverage.  Process/launch/I/O errors
                # above remain infrastructure failures and still degrade.
                invalid_candidates += 1
          clear_ok = write_file(gpu_output, "")
          if clear_ok == false
            gpu_failures[gpu_role] = gpu_failures[gpu_role] + 1
            gpu_degraded = 1
            if gpu_role != 10
              gpu_eligible[gpu_role] = 0
              gpu_lanes[gpu_role] = 0
              gpu_disabled[gpu_role] = 1
              gpu_retry_round[gpu_role] = round + ffn_gpu_retry_delay(gpu_failures[gpu_role])
            if pool_child_slot >= 0
              pool_slot_retry_round[pool_child_slot] = round + ffn_gpu_retry_delay(gpu_failures[10])
          if pool_child_slot >= 0
            if completed_pool_mode >= 0
              pool_active_modes[completed_pool_mode] = 0
            pool_modes[pool_child_slot] = 0 - 1
            pool_drain_anchors[pool_child_slot] = 0
      gpu_slot += 1

    # Pool children are much less uniform than the dedicated Metal epochs:
    # a constraint walk may finish while a host-heavy join is still running.
    # Refill each empty family slot independently.  When the dedicated side
    # drains, mark the then-running pool children as barrier anchors and keep
    # the faster siblings busy until those anchors finish.  Refills then stop
    # and only the last short tail drains before the clean global rebalance.
    gpu_dedicated_live = 0 ## i64
    gpu_slot = 0
    while gpu_slot < 10
      if gpu_threads[gpu_slot] != nil
        gpu_dedicated_live = 1
      gpu_slot += 1
    if gpu_dedicated_live != 0
      pool_drain_active = 0
      pool_slot = 0
      while pool_slot < 3
        pool_drain_anchors[pool_slot] = 0
        pool_slot += 1
    if gpu_dedicated_live == 0 && pool_drain_active == 0
      pool_drain_active = 1
      pool_slot = 0
      while pool_slot < 3
        gpu_slot = 10 + pool_slot ## i64
        if gpu_threads[gpu_slot] != nil
          pool_drain_anchors[pool_slot] = 1
        pool_slot += 1
    pool_anchor_count = 0 ## i64
    pool_slot = 0
    while pool_slot < 3
      pool_anchor_count += pool_drain_anchors[pool_slot]
      pool_slot += 1
    pool_refill_allowed = gpu_dedicated_live ## i64
    if pool_anchor_count > 0
      pool_refill_allowed = 1
    if pool_refill_allowed != 0 && gpu_eligible[10] != 0 && gpu_disabled[10] == 0
      gpu_pool_ready = ffn_fill_pool_readiness(pool_mode_ready, gpu_generic_ready, gpu_mitm_ready, gpu_constraint_ready, gpu_kxor_ready, orbit_bank, polar_bank)
      pool_slot = 0
      while pool_slot < 3
        gpu_slot = 10 + pool_slot ## i64
        pool_group = pool_slot_groups[pool_slot] ## i64
        pool_lanes = pool_slot_lanes[pool_slot] ## i64
        if gpu_threads[gpu_slot] == nil && pool_group >= 0 && pool_lanes > 0 && round >= pool_slot_retry_round[pool_slot]
          pool_mode = ffkp_select_group_mode_ready(pool_group_epochs[pool_group], pool_group, N, ffw_best_rank(best), 0, pool_mode_ready, pool_last_modes, pool_pulls, pool_rewards) ## i64
          if pool_mode >= 0
            pool_cap = ffkp_mode_lane_budget(GPU_WALKERS, pool_mode) ## i64
            if pool_lanes > pool_cap
              pool_lanes = pool_cap
            pool_modes[pool_slot] = pool_mode
            pool_launch_number = gpu_launch_number[10] ## i64
            pool_slot_launch_numbers[pool_slot] = pool_launch_number
            gpu_seed = ffn_pool_seed(pool_mode, pool_launch_number, best, map_states, map_uses, c3_base, orbit_bank, polar_bank, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander)
            if gpu_seed != nil
              gpu_seed_rank = ffw_best_rank(gpu_seed) ## i64
              if gpu_seed_ranks[10] == 0 || gpu_seed_rank < gpu_seed_ranks[10]
                gpu_seed_ranks[10] = gpu_seed_rank
              gpu_launch_debt[gpu_slot] = gpu_seed_rank - ffw_best_rank(best)
              gpu_launch_lanes[gpu_slot] = pool_lanes
              gpu_elapsed_ms[gpu_slot] = 0
              gpu_launch_generation[gpu_slot] = fleet_generation
              gpu_threads[gpu_slot] = ffn_gpu_launch_pool(REPO_ROOT, GPU_BINARY, MITM_BINARY, CONSTRAINT_BINARY, KXOR_BINARY, RUN_TAG, N, gpu_slot, pool_mode, pool_lanes, GPU_STEPS, GPU_EPOCH_ROUNDS, pool_launch_number, gpu_seed, gpu_elapsed_ms)
            if gpu_seed == nil || gpu_threads[gpu_slot] == nil
              gpu_failures[10] = gpu_failures[10] + 1
              gpu_degraded = 1
              pool_modes[pool_slot] = 0 - 1
              pool_slot_retry_round[pool_slot] = round + ffn_gpu_retry_delay(gpu_failures[10])
            else
              pool_active_modes[pool_mode] = 1
              z = ffkp_record_launch(pool_mode, N, gpu_launch_debt[gpu_slot], pool_lanes / 32, pool_pulls, pool_exposure)
              pool_last_modes[pool_group] = pool_mode
              pool_group_epochs[pool_group] = pool_group_epochs[pool_group] + 1
              pool_slot_retry_round[pool_slot] = 0
              gpu_launch_number[10] = gpu_launch_number[10] + 1
        pool_slot += 1

  if strict_drop == 1
    # Rebase learned states around the final frontier reached this round.
    # The old frontier becomes a valuable R+1 shoulder after a one-rank drop;
    # prior R+1 shoulders can become R+2.  Obsolete archive ranks never remain
    # mislabeled as same-rank frontier diversity.
    old_archive = archive
    archive = []
    gpu_pareto_archive = []
    gpu_pareto_ranks = []
    gpu_pareto_bits = []
    gpu_pareto_pairs = []
    gpu_pareto_novelties = []
    gpu_pareto_roles = []
    gpu_pareto_uses = []
    gpu_pareto_counters = i64[4]
    frontier_snapshot = ffn_clone_trusted(best, STATE_SIZE, 20001 + round * 47)
    if frontier_snapshot != nil
      z = ffn_archive_add(archive, frontier_snapshot, ARCHIVE_CAP, 4, archive_counters) ## i64
    z = ffn_build_escape_banks(best, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, near1, near2, near1_signatures, near1_uses, near1_successes, near2_signatures, near2_uses, near2_successes, symmetry, mixed, orbit_bank, polar_bank, near1_capacity, near2_capacity, NEAR_SIGNATURE_QUOTA, SYMMETRY_CAP, near_counters) ## i64
    if ffn_state_is_c3(best, N, CAPACITY) == 1
      c3_base = ffn_clone_trusted(best, STATE_SIZE, 20003 + round * 47)
    z = ffn_add_c3_family(c3_base, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, symmetry, orbit_bank, polar_bank, SYMMETRY_CAP) ## i64
    if GPU == 1
      special_policy = 1 ## i64
      if GPU_POLICY == "single"
        special_policy = 0

      if c3_base != nil && ffp_gpu_weight(N, 2) > 0 && special_policy == 1 && gpu_disabled[2] == 0
        if gpu_c3_ready == 0
          gpu_c3_ready = ffc3_build(REPO_ROOT, N, C3_BINARY)
          if gpu_c3_ready == 0
            gpu_disabled[2] = 1
            gpu_degraded = 1
        if gpu_c3_ready == 1
          gpu_eligible[2] = 1
          gpu_weights[2] = ffp_gpu_weight(N, 2)
      else
        gpu_eligible[2] = 0

      if orbit_bank.size() > 0 && ffp_gpu_weight(N, 5) > 0 && special_policy == 1 && gpu_disabled[5] == 0 && gpu_generic_ready == 1
        gpu_eligible[5] = 1
        gpu_weights[5] = ffp_gpu_weight(N, 5)
      else
        gpu_eligible[5] = 0

      if polar_bank.size() > 0 && ffp_gpu_weight(N, 6) > 0 && special_policy == 1 && gpu_disabled[6] == 0 && gpu_generic_ready == 1
        gpu_eligible[6] = 1
        gpu_weights[6] = ffp_gpu_weight(N, 6)
      else
        gpu_eligible[6] = 0
    final_rank = ffw_best_rank(best) ## i64
    pi = 0
    while pi < demoted_frontiers.size()
      rr = ffw_best_rank(demoted_frontiers[pi]) ## i64
      if rr == final_rank + 1
        z = ffbp_near_add(near1, near1_signatures, near1_uses, near1_successes, demoted_frontiers[pi], near1_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters)
      if rr == final_rank + 2
        z = ffbp_near_add(near2, near2_signatures, near2_uses, near2_successes, demoted_frontiers[pi], near2_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters)
      pi += 1
    pi = 0
    while pi < preserved_shoulders.size()
      rr = ffw_best_rank(preserved_shoulders[pi]) ## i64
      if rr == final_rank + 1
        z = ffbp_near_add(near1, near1_signatures, near1_uses, near1_successes, preserved_shoulders[pi], near1_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters)
      if rr == final_rank + 2
        z = ffbp_near_add(near2, near2_signatures, near2_uses, near2_successes, preserved_shoulders[pi], near2_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters)
      pi += 1
    pi = 0
    while pi < old_archive.size()
      rr = ffw_best_rank(old_archive[pi]) ## i64
      if rr == final_rank
        z = ffn_archive_add(archive, old_archive[pi], ARCHIVE_CAP, 4, archive_counters)
      if rr == final_rank + 1
        z = ffbp_near_add(near1, near1_signatures, near1_uses, near1_successes, old_archive[pi], near1_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters)
      if rr == final_rank + 2
        z = ffbp_near_add(near2, near2_signatures, near2_uses, near2_successes, old_archive[pi], near2_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters)
      pi += 1
    archive_min_cache = ffn_archive_min_distance(archive)

    map_states = []
    map_keys = []
    map_uses = []
    map_sources = []
    map_pool = archive
    map_source = 0 ## i64
    while map_source < 5
      if map_source == 1
        map_pool = near1
      if map_source == 2
        map_pool = near2
      if map_source == 3
        map_pool = mixed
      if map_source == 4
        map_pool = symmetry
      mi = 0 ## i64
      while mi < map_pool.size()
        z = ffme_add(map_states, map_keys, map_uses, map_sources, map_pool[mi], final_rank, N, MAP_CAPACITY, map_source)
        mi += 1
      map_source += 1

    if core_fringe_index >= 0
      core_out = i64[1]
      refreshed_core = ffn_core_fringe_state(best, archive, near1, near2, mixed, N, CAPACITY, STATE_SIZE, 20501 + round * 47, DSLACK, CYCLES, cpu_work_moves[zones[core_fringe_index]], cpu_wander_moves[zones[core_fringe_index]], core_out)
      if refreshed_core != nil
        states[core_fringe_index] = refreshed_core
        core_fringe_slots = core_out[0]
        active_near_seeds[core_fringe_index] = nil
        active_seed_ranks[core_fringe_index] = final_rank
        active_seed_start_moves[core_fringe_index] = 0
        active_seed_finished[core_fringe_index] = 1
        sources[core_fringe_index] = "core-fringe/frozen-" + core_fringe_slots.to_s()
        last_seen_rank[core_fringe_index] = ffw_best_rank(refreshed_core)
        last_seen_bits[core_fringe_index] = ffw_best_bits(refreshed_core)
        last_moves[core_fringe_index] = 0

    # Only the leader island migrates now; every other sticky door keeps
    # knocking on its independent basin.
    migrated = 0 ## i64
    i = 0
    while i < J
      migrate_this = 0 ## i64
      if STRATEGY == "converge"
        migrate_this = 1
      if STRATEGY == "islands" && migrated < MIGRATE
        seed_door_m = ffp_seed_door(doors[i]) ## i64
        if seed_door_m == 0 || seed_door_m == 1
          if ffn_distance(states[i], best) > 0
            migrate_this = 1
      if migrate_this == 1
        z = ffw_reseed_from(states[i], best, 21001 + round * 47 + i)
        active_near_seeds[i] = nil
        active_seed_ranks[i] = ffw_best_rank(states[i])
        active_seed_start_moves[i] = ffw_moves(states[i])
        active_seed_finished[i] = 1
        sources[i] = "leader/new-best"
        last_seen_rank[i] = ffw_best_rank(states[i])
        last_seen_bits[i] = ffw_best_bits(states[i])
        last_moves[i] = ffw_moves(states[i])
        migrated = 1
      i += 1

  # Individual cycle-outs preserve door and zone; there is no fleet-wide wrap.
  # Short and balanced islands also have a finite basin lease independent of
  # the four-wrap sawtooth cycle. This rotates reversible shoulder escapes in
  # seconds/minutes rather than leaving them on one seed for hours; high-band
  # and marathon islands retain their deliberately deep leases.
  i = 0
  while i < J
    cycle_due = ffw_cycled(states[i]) ## i64
    lease_due = 0 ## i64
    seed_moves = ffw_moves(states[i]) - active_seed_start_moves[i] ## i64
    seed_door_l = ffp_seed_door(doors[i]) ## i64
    if zones[i] <= 1 && seed_door_l != 0 && seed_door_l != 6
      lease_moves = cpu_work_moves[zones[i]] + cpu_wander_moves[zones[i]] ## i64
      if seed_moves >= lease_moves
        lease_due = 1
    if cycle_due == 1 || lease_due == 1
      # Equal-density frontier states are algebraically exact but were not
      # personal bests, so sample the live state through a fresh exhaustive
      # gate before the lease is recycled.
      if ffw_current_rank(states[i]) == ffw_best_rank(best)
        current_distance = ffn_current_to_best_distance(states[i], best) ## i64
        if current_distance >= 4
          live_candidate = ffn_clone_current_exact(states[i], N, CAPACITY, STATE_SIZE, 23001 + round * 53 + i, DSLACK, CYCLES, balanced_work, balanced_wander)
          if live_candidate != nil
            z = ffn_archive_add(archive, live_candidate, ARCHIVE_CAP, 4, archive_counters)
            archive_min_cache = ffn_archive_min_distance(archive)
            z = ffme_add(map_states, map_keys, map_uses, map_sources, live_candidate, ffw_best_rank(best), N, MAP_CAPACITY, doors[i])
      old_debt = active_seed_ranks[i] - ffw_best_rank(best) ## i64
      if old_debt > 0 && active_seed_finished[i] == 0
        spent = ffw_moves(states[i]) - active_seed_start_moves[i] ## i64
        z = ffrd_finish(old_debt, 0, spent, debt_returns, debt_failures, debt_exposure)
      native_seed = ffn_door_has_native_seed(doors[i], archive, near1, near2, symmetry, mixed)
      selected = ffn_pick_seed(doors[i], best, anchor, archive, near1, near2, near1_uses, near2_uses, symmetry, mixed, states, cursor, round * J + i)
      next_core_slots = core_fringe_slots ## i64
      if i == core_fringe_index
        core_out = i64[1]
        refreshed_core = ffn_core_fringe_state(best, archive, near1, near2, mixed, N, CAPACITY, STATE_SIZE, 24001 + round * 53 + i, DSLACK, CYCLES, cpu_work_moves[zones[i]], cpu_wander_moves[zones[i]], core_out)
        if refreshed_core != nil
          selected = refreshed_core
          next_core_slots = core_out[0]
      active_near_seeds[i] = nil
      if seed_door_l == 2 && near1.size() > 0
        active_near_seeds[i] = selected
      if seed_door_l == 3 && near2.size() > 0
        active_near_seeds[i] = selected
      if seed_door_l == 4 && symmetry.size() > 0
        symmetry_cpu_uses += 1
      z = ffw_reseed_from(states[i], selected, 25001 + round * 53 + i)
      used_anchor_fallback = 0 ## i64
      if z < 1
        z = ffw_reseed_from(states[i], anchor, 27001 + round * 53 + i)
        active_near_seeds[i] = nil
        sources[i] = ffp_door_name(doors[i]) + "/anchor-fallback"
        used_anchor_fallback = 1
      if z >= 1 && native_seed != 0 && used_anchor_fallback == 0
        sources[i] = ffp_door_name(doors[i]) + "/seed" + (ffn_current_basin_id(selected) % 100000).to_s()
      if z >= 1 && native_seed == 0 && used_anchor_fallback == 0
        sources[i] = ffp_door_name(doors[i]) + "/leader-fallback"
      if z >= 1 && i == core_fringe_index
        core_fringe_slots = next_core_slots
        sources[i] = "core-fringe/frozen-" + core_fringe_slots.to_s()
      active_seed_ranks[i] = ffw_best_rank(states[i])
      active_seed_start_moves[i] = ffw_moves(states[i])
      active_seed_finished[i] = 0
      next_debt = active_seed_ranks[i] - ffw_best_rank(best) ## i64
      if next_debt > 0
        z = ffrd_launch(next_debt, debt_launches)
        adaptive_work = ffrd_budget(cpu_work_moves[zones[i]], next_debt, debt_returns, debt_failures) ## i64
        adaptive_wander = ffrd_budget(cpu_wander_moves[zones[i]], next_debt, debt_returns, debt_failures) ## i64
        z = ffw_set_zone_quotas(states[i], adaptive_work, adaptive_wander)
      if next_debt <= 0
        active_seed_finished[i] = 1
      last_seen_rank[i] = ffw_best_rank(states[i])
      last_seen_bits[i] = ffw_best_bits(states[i])
      last_moves[i] = ffw_moves(states[i])
      last_progress_ms[i] = now_ms
      if cycle_due == 1
        cycleouts += 1
      if cycle_due == 0 && lease_due == 1
        basin_rotations += 1
    i += 1

  # Rebalance only at a clean epoch boundary, then relaunch every active role
  # from its current role-specific exact bank.  This keeps lane accounting
  # honest: an allocation changes only after all old allocations completed.
  if GPU == 1
    gpu_all_done = 1 ## i64
    gpu_slot = 0 ## i64
    while gpu_slot < 13
      if gpu_threads[gpu_slot] != nil
        gpu_all_done = 0
      gpu_slot += 1
    if gpu_all_done == 1
      gpu_generic_retry_attempted = 0 ## i64
      gpu_c3_retry_attempted = 0 ## i64
      gpu_simd_retry_attempted = 0 ## i64
      gpu_mitm_retry_attempted = 0 ## i64
      gpu_role = 0
      while gpu_role < 11
        if gpu_disabled[gpu_role] != 0 && round >= gpu_retry_round[gpu_role]
          wanted = 0 ## i64
          if ffp_gpu_weight(N, gpu_role) > 0
            wanted = 1
          if GPU_POLICY == "single" && gpu_role != 0
            wanted = 0
          engine_kind = ffg_engine_kind(gpu_role) ## i64
          engine_ready = 0 ## i64
          if engine_kind == 0
            if gpu_generic_ready == 0 && wanted == 1 && gpu_generic_retry_attempted == 0
              gpu_generic_retry_attempted = 1
              gpu_generic_ready = ffb_build(REPO_ROOT, N, GPU_BINARY)
            engine_ready = gpu_generic_ready
          if engine_kind == 1
            if gpu_c3_ready == 0 && wanted == 1 && gpu_c3_retry_attempted == 0
              gpu_c3_retry_attempted = 1
              gpu_c3_ready = ffc3_build(REPO_ROOT, N, C3_BINARY)
            engine_ready = gpu_c3_ready
          if engine_kind == 2
            if gpu_simd_ready == 0 && wanted == 1 && gpu_simd_retry_attempted == 0
              gpu_simd_retry_attempted = 1
              gpu_simd_ready = ffsimd_build(REPO_ROOT, N, SIMD_BINARY)
            engine_ready = gpu_simd_ready
          if engine_kind == 3
            if wanted == 1 && gpu_mitm_retry_attempted == 0
              gpu_mitm_retry_attempted = 1
              if gpu_mitm_ready == 0
                gpu_mitm_ready = ffn_mitm_build(REPO_ROOT, MITM_BINARY)
              if gpu_constraint_ready == 0
                gpu_constraint_ready = ffn_pool_worker_build(REPO_ROOT, CONSTRAINT_BINARY, "benchmarks/matmul/metaflip/flipfleet_constraint_pool.w")
              if gpu_kxor_ready == 0
                gpu_kxor_ready = ffn_pool_worker_build(REPO_ROOT, KXOR_BINARY, "benchmarks/matmul/metaflip/flipfleet_kxor_pool.w")
              gpu_pool_ready = ffn_fill_pool_readiness(pool_mode_ready, gpu_generic_ready, gpu_mitm_ready, gpu_constraint_ready, gpu_kxor_ready, orbit_bank, polar_bank)
            engine_ready = 0
            if gpu_pool_ready > 0
              engine_ready = 1
          retry_seed = nil
          if wanted == 1 && engine_ready == 1
            retry_seed = ffn_gpu_role_seed(gpu_role, gpu_launch_number[gpu_role], best, archive, near1, near2, mixed, c3_base, orbit_bank, polar_bank, gpu_pareto_archive, gpu_pareto_bits, gpu_pareto_pairs, gpu_pareto_novelties, gpu_pareto_uses, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander)
          if retry_seed != nil
            gpu_disabled[gpu_role] = 0
            gpu_eligible[gpu_role] = 1
            gpu_weights[gpu_role] = ffp_gpu_weight(N, gpu_role)
          else
            gpu_retry_round[gpu_role] = round + ffn_gpu_retry_delay(gpu_failures[gpu_role])
        gpu_role += 1
      if gpu_generic_ready == 1 || gpu_c3_ready == 1 || gpu_simd_ready == 1 || gpu_pool_ready > 0
        gpu_ready = 1
      gpu_pool_ready = ffn_fill_pool_readiness(pool_mode_ready, gpu_generic_ready, gpu_mitm_ready, gpu_constraint_ready, gpu_kxor_ready, orbit_bank, polar_bank)
      pool_count = 0
      if gpu_eligible[10] != 0
        pool_count = ffkp_select_group_modes_ready(pool_selection_epoch, N, ffw_best_rank(best), 0, GPU_WALKERS, pool_mode_ready, pool_last_modes, pool_pulls, pool_rewards, pool_modes)
      pool_budget = ffkp_allocate_selected_lanes(GPU_WALKERS, pool_modes, pool_count, pool_slot_lanes) ## i64
      pool_selection_epoch += 1
      proposed_lanes = i64[11]
      contextual_exposure = i64[11]
      contextual_rewards = i64[11]
      context_role = 0 ## i64
      while context_role < 11
        context = ffkp_context(N, gpu_launch_debt[context_role]) ## i64
        transition_index = context_role * ffkp_context_count() + context ## i64
        contextual_exposure[context_role] = gpu_transition_exposure[transition_index]
        contextual_rewards[context_role] = gpu_transition_rewards[transition_index]
        context_role += 1
      covered = ffg_adaptive_allocate_pool(GPU_WALKERS, pool_budget, gpu_eligible, gpu_weights, contextual_exposure, contextual_rewards, proposed_lanes) ## i64
      # DEGRADED is current coverage health, not a lifetime latch.  A role that
      # successfully rebuilds/retries clears the banner while retaining its
      # cumulative failure counter for diagnosis.
      gpu_degraded = 0
      if gpu_ready == 0 || covered == 0
        gpu_degraded = 1
      health_role = 0 ## i64
      while health_role < 11
        if gpu_disabled[health_role] != 0
          gpu_degraded = 1
        health_role += 1
      gpu_role = 0
      while gpu_role < 10
        gpu_lanes[gpu_role] = proposed_lanes[gpu_role]
        if gpu_eligible[gpu_role] != 0 && gpu_lanes[gpu_role] > 0
          gpu_seed = ffn_gpu_role_seed(gpu_role, gpu_launch_number[gpu_role], best, archive, near1, near2, mixed, c3_base, orbit_bank, polar_bank, gpu_pareto_archive, gpu_pareto_bits, gpu_pareto_pairs, gpu_pareto_novelties, gpu_pareto_uses, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander)
          if gpu_seed == nil
            gpu_eligible[gpu_role] = 0
            gpu_lanes[gpu_role] = 0
            gpu_disabled[gpu_role] = 1
            gpu_failures[gpu_role] = gpu_failures[gpu_role] + 1
            gpu_retry_round[gpu_role] = round + ffn_gpu_retry_delay(gpu_failures[gpu_role])
            gpu_degraded = 1
          else
            gpu_seed_ranks[gpu_role] = ffw_best_rank(gpu_seed)
            gpu_launch_debt[gpu_role] = gpu_seed_ranks[gpu_role] - ffw_best_rank(best)
            gpu_launch_lanes[gpu_role] = gpu_lanes[gpu_role]
            gpu_elapsed_ms[gpu_role] = 0
            gpu_launch_generation[gpu_role] = fleet_generation
            engine_kind = ffg_engine_kind(gpu_role) ## i64
            if engine_kind == 0
              gpu_threads[gpu_role] = ffn_gpu_launch(REPO_ROOT, GPU_BINARY, RUN_TAG, N, gpu_role, gpu_lanes[gpu_role], GPU_STEPS, GPU_EPOCH_ROUNDS, gpu_seed, gpu_elapsed_ms)
            if engine_kind == 1
              gpu_threads[gpu_role] = ffn_gpu_launch_c3(REPO_ROOT, C3_BINARY, RUN_TAG, N, gpu_lanes[gpu_role], gpu_seed, gpu_elapsed_ms)
            if engine_kind == 2
              gpu_threads[gpu_role] = ffn_gpu_launch_simd(REPO_ROOT, SIMD_BINARY, RUN_TAG, N, gpu_lanes[gpu_role], gpu_seed, gpu_elapsed_ms)
            if gpu_threads[gpu_role] == nil
              gpu_eligible[gpu_role] = 0
              gpu_lanes[gpu_role] = 0
              gpu_disabled[gpu_role] = 1
              gpu_failures[gpu_role] = gpu_failures[gpu_role] + 1
              gpu_retry_round[gpu_role] = round + ffn_gpu_retry_delay(gpu_failures[gpu_role])
              gpu_degraded = 1
            else
              gpu_launch_number[gpu_role] = gpu_launch_number[gpu_role] + 1
        gpu_role += 1

      pool_drain_active = 0
      pool_slot = 0
      while pool_slot < 3
        pool_drain_anchors[pool_slot] = 0
        pool_slot += 1
      pool_launched_lanes = 0
      pool_launched_count = 0
      pool_slot = 0
      while pool_slot < pool_count
        pool_mode = pool_modes[pool_slot] ## i64
        pool_lanes = pool_slot_lanes[pool_slot] ## i64
        gpu_slot = 10 + pool_slot ## i64
        if pool_mode >= 0 && pool_lanes > 0 && gpu_eligible[10] != 0
          pool_group = ffkp_mode_group(pool_mode) ## i64
          pool_slot_groups[pool_slot] = pool_group
          pool_launch_number = gpu_launch_number[10] ## i64
          pool_slot_launch_numbers[pool_slot] = pool_launch_number
          gpu_seed = ffn_pool_seed(pool_mode, pool_launch_number, best, map_states, map_uses, c3_base, orbit_bank, polar_bank, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander)
          if gpu_seed != nil
            gpu_seed_rank = ffw_best_rank(gpu_seed) ## i64
            if pool_launched_count == 0 || gpu_seed_rank < gpu_seed_ranks[10]
              gpu_seed_ranks[10] = gpu_seed_rank
            gpu_launch_debt[gpu_slot] = gpu_seed_rank - ffw_best_rank(best)
            gpu_launch_lanes[gpu_slot] = pool_lanes
            gpu_elapsed_ms[gpu_slot] = 0
            gpu_launch_generation[gpu_slot] = fleet_generation
            gpu_threads[gpu_slot] = ffn_gpu_launch_pool(REPO_ROOT, GPU_BINARY, MITM_BINARY, CONSTRAINT_BINARY, KXOR_BINARY, RUN_TAG, N, gpu_slot, pool_mode, pool_lanes, GPU_STEPS, GPU_EPOCH_ROUNDS, pool_launch_number, gpu_seed, gpu_elapsed_ms)
          if gpu_seed == nil || gpu_threads[gpu_slot] == nil
            gpu_failures[10] = gpu_failures[10] + 1
            gpu_degraded = 1
            pool_modes[pool_slot] = 0 - 1
            pool_slot_retry_round[pool_slot] = round + ffn_gpu_retry_delay(gpu_failures[10])
          else
            pool_active_modes[pool_mode] = 1
            z = ffkp_record_launch(pool_mode, N, gpu_launch_debt[gpu_slot], pool_lanes / 32, pool_pulls, pool_exposure)
            pool_last_modes[pool_group] = pool_mode
            pool_group_epochs[pool_group] = pool_group_epochs[pool_group] + 1
            pool_slot_retry_round[pool_slot] = 0
            gpu_launch_number[10] = gpu_launch_number[10] + 1
            pool_launched_lanes += pool_lanes
            pool_launched_count += 1
        pool_slot += 1
      gpu_lanes[10] = pool_launched_lanes
      if gpu_eligible[10] != 0 && pool_budget > 0 && pool_launched_count == 0
        gpu_eligible[10] = 0
        gpu_disabled[10] = 1
        gpu_retry_round[10] = round + ffn_gpu_retry_delay(gpu_failures[10])

  if ff_tui_heartbeat_due(last_status_ms, now_ms, 500) == 1
    sequence += 1
    z = ffn_status(STATUS_PATH, RUN_TAG, "LIVE", now_ms, sequence, N, RECORD, RECORD_KNOWN, best, total_moves, elapsed_s, archive, near1, near2, symmetry, GPU, gpu_degraded)
    if z == 0
      gpu_degraded = 1
    if z == 1
      last_status_ms = now_ms
  if TUI == 1
    if ff_tui_heartbeat_due(last_render_ms, now_ms, 200) == 1
      last_render_ms = now_ms
      tick_rank = ffw_best_rank(best) ## i64
      if rank_level_count > 0 && rank_levels[rank_level_count - 1] == tick_rank
        rank_ticks[rank_level_count - 1] = rank_ticks[rank_level_count - 1] + 1
      else
        if rank_level_count == 256
          h = 1 ## i64
          while h < 256
            rank_levels[h - 1] = rank_levels[h]
            rank_ticks[h - 1] = rank_ticks[h]
            h += 1
          rank_level_count = 255
        rank_levels[rank_level_count] = tick_rank
        rank_ticks[rank_level_count] = 1
        rank_level_count += 1
      tick_bits = ffw_best_bits(best) ## i64
      if bits_level_count > 0 && bits_levels[bits_level_count - 1] == tick_bits
        bits_ticks[bits_level_count - 1] = bits_ticks[bits_level_count - 1] + 1
      else
        if bits_level_count == 256
          h = 1 ## i64
          while h < 256
            bits_levels[h - 1] = bits_levels[h]
            bits_ticks[h - 1] = bits_ticks[h]
            h += 1
          bits_level_count = 255
        bits_levels[bits_level_count] = tick_bits
        bits_ticks[bits_level_count] = 1
        bits_level_count += 1
      z = ffn_render(N, J, round, elapsed_s, total_moves, RECORD, RECORD_KNOWN, recovered, best, states, island_best_ranks, doors, zones, sources, last_rates, last_ages, cpu_work_moves, cpu_wander_moves, archive, ARCHIVE_CAP, near1, near1_capacity, near2, near2_capacity, symmetry, SYMMETRY_CAP, archive_counters, archive_min_cache, cohort_moves, cohort_drops, cohort_ties, cohort_near, timeline_times, timeline_ranks, timeline_count, elapsed_s - timeline_start_s, GPU, GPU_POLICY, gpu_degraded, gpu_lanes, gpu_candidates, gpu_rank_drops, gpu_density, gpu_rewards, gpu_lane_epochs, gpu_wall_ms, gpu_failures, gpu_disabled, gpu_retry_round, gpu_seed_ranks, gpu_pareto, gpu_pareto_archive, GPU_NOVELTY_CAP, gpu_pareto_counters, symmetry_cpu_uses, gpu_launch_number, pool_active_modes, pool_mode_ready, last_status_ms, sequence, now_ms, rank_levels, rank_ticks, rank_level_count, bits_levels, bits_ticks, bits_level_count, new_bests, tie_bests, cycleouts, invalid_candidates, DSLACK, flash_text, flash_until_ms)
  if QUIET == 0 && TUI == 0
    << "round=" + round.to_s() + " best=" + ffw_best_rank(best).to_s() + " bits=" + ffw_best_bits(best).to_s() + " moves=" + total_moves.to_s() + " exact_bad=" + invalid_candidates.to_s() + " archive=" + archive.size().to_s()
    flush()

  round += 1
  interrupted = ccall("__w_interrupted") ## i64
  if interrupted != 0 || stop_key != 0
    running = 0
  if round >= MAX_ROUNDS
    running = 0
  if MAX_SECS > 0
    if elapsed_s >= MAX_SECS
      running = 0
  if STOP_ON_RECORD == 1
    if ffw_best_rank(best) < RECORD
      running = 0

ccall("w_term_raw_disable")
if interrupted != 0 || stop_key != 0
  << "  " + ff_tui_paint("interrupt — draining GPU epochs and saving state (Ctrl-C again to force quit)", "1;33")
  flush()

# Bounded GPU commands are ordinary Tungsten-owned OS threads.  Reap the final
# epoch and exact-gate any late result so the process never leaves GPU work
# behind and a last-second record is not lost at shutdown.
if GPU == 1 && gpu_ready == 1
  gpu_slot = 0 ## i64
  while gpu_slot < 13
    gpu_role = gpu_slot ## i64
    if gpu_slot >= 10
      gpu_role = 10
    if gpu_threads[gpu_slot] != nil
      late_thread_result = gpu_threads[gpu_slot].join
      if late_thread_result == false
        gpu_failures[gpu_role] = gpu_failures[gpu_role] + 1
        gpu_degraded = 1
        if gpu_role != 10
          gpu_disabled[gpu_role] = 1
      gpu_threads[gpu_slot] = nil
      late_output_path = ffn_gpu_output_path(RUN_TAG, N, gpu_slot)
      late_raw = read_file(late_output_path)
      late = i64[STATE_SIZE]
      late_launch_is_current = 0 ## i64
      if gpu_launch_generation[gpu_slot] == fleet_generation
        late_launch_is_current = 1
      late_rank = 0 - 1 ## i64
      if late_launch_is_current == 1
        late_rank = ffw_load_scheme_cap(late, late_output_path, N, CAPACITY, 51001 + gpu_slot, DSLACK, CYCLES, balanced_work, balanced_wander)
      if late_rank > 0 && gpu_role == 2
        if ffn_state_is_c3(late, N, CAPACITY) == 0
          late_rank = 0 - 1
      if late_rank > 0
        late_bits = ffw_best_bits(late) ## i64
        if ffn_better(late_rank, late_bits, ffw_best_rank(best), ffw_best_bits(best)) == 1
          if late_rank < ffw_best_rank(best)
            new_bests += 1
          if late_rank == ffw_best_rank(best)
            tie_bests += 1
          best = late
      if late_rank <= 0 && late_launch_is_current == 1
        if late_raw != nil
          if late_raw.size() > 0
            invalid_candidates += 1
      if gpu_slot >= 10
        late_pool_slot = gpu_slot - 10 ## i64
        late_pool_mode = pool_modes[late_pool_slot] ## i64
        if late_pool_mode >= 0
          pool_active_modes[late_pool_mode] = 0
        pool_modes[late_pool_slot] = 0 - 1
    gpu_slot += 1

final_ms = ccall("__w_clock_ms") ## i64
final_s = (final_ms - start_ms) / 1000 ## i64
final_write_failed = 0 ## i64
z = ffn_dump_trusted(best, BEST_PATH, RUN_TAG)
if z < 1
  gpu_degraded = 1
  final_write_failed = 1
final_state = "DONE"
if final_write_failed != 0
  final_state = "FAILED"
z = ffn_status(STATUS_PATH, RUN_TAG, final_state, final_ms, sequence + 1, N, RECORD, RECORD_KNOWN, best, total_moves, final_s, archive, near1, near2, symmetry, GPU, gpu_degraded)
if z == 0
  final_write_failed = 1
if TUI == 1
  << ""
  if final_write_failed == 0
    << "DONE best rank " + ffw_best_rank(best).to_s() + " density " + ffw_best_bits(best).to_s() + " exact=1"
  if final_write_failed != 0
    << "FAILED to persist final exact certificate/status"
if TUI == 0
  if final_write_failed == 0
    << "flipfleet native done: tensor=" + N.to_s() + "x" + N.to_s() + " best=" + ffw_best_rank(best).to_s() + " bits=" + ffw_best_bits(best).to_s() + " moves=" + total_moves.to_s() + " rank-drops=" + new_bests.to_s() + " density-ties=" + tie_bests.to_s() + " exact-rejects=" + invalid_candidates.to_s()
  if final_write_failed != 0
    << "flipfleet native: FAILED to persist final exact certificate/status"
flush()
if final_write_failed != 0
  exit(1)

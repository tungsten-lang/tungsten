# Pure-Tungsten Metaflip coordinator.
#
# This is the authoritative in-process CPU coordinator.  It owns sticky
# islands, variable-rank exact escape banks, exact adoption, durable status,
# and the native TUI.  Dimension-specialized Metal engines attach through the
# native GPU policy module; there is no Python in the campaign runtime.

use core/system
use scheme
use strategies/escape
use fleet/banks
use seeds/catalog
use tui
use kernels/policy
use kernels/pool
use fleet/map_elites
use fleet/rank_debt
use kernels/bundles/generic
use kernels/bundles/c3
use kernels/bundles/simd
use rect
use kernels/bundles/rect
use rect/campaign
use rect/portfolio
use compose
use fleet/seven_by_seven
use fleet/basins
use fleet/lineage
use fleet/cpu_experiments
use fleet/cpu_pool
use kernels/metallib_cache
use kernels/bundles/workers
use kernels/reject
use kernels/rect_reject
use kernels/bundles/differential
use fleet/frontier
use kernels/bundles/frozen_fringe_sat
use kernels/bundles/global_kernel_shear
use strategies/syndrome_repair
use strategies/global_isotropy
use strategies/partial_automorphism_nullspace
use seeds/shoulders
use paths

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

# The 7x7 block construction gives each rectangular component three copies,
# so a one-rank component improvement is worth three ranks in the composed
# square scheme.  Keep this reward separate from square-candidate accounting;
# the coordinator adds it to role 10 only after the rectangular exact gate.
-> ffn_rect_reward(old_rank, old_bits, new_rank, new_bits) (i64 i64 i64 i64) i64
  reward = 0 ## i64
  gain = old_rank - new_rank ## i64
  if gain > 0
    reward = gain * 30000
  if gain == 0 && new_bits < old_bits && old_bits > 0
    density_reward = 2000 * (old_bits - new_bits) / old_bits ## i64
    if density_reward < 1
      density_reward = 1
    if density_reward > 2000
      density_reward = 2000
    reward += density_reward
  reward

# Normalize a package checkout, its `lib/` directory, or the namespaced source
# directory into the immutable runtime root. Compiler discovery is deliberately
# separate (see ffmc_tungsten): an installed bit and the Tungsten executable do
# not have to share a root.
-> ffn_normalize_runtime_root(root) (String)
  if root == ""
    return ""
  marker = read_file(root + "/fleet.w")
  if marker != nil
    return ffls_canonical_dir(root)
  marker = read_file(root + "/metaflip/fleet.w")
  if marker != nil
    return ffls_canonical_dir(root + "/metaflip")
  marker = read_file(root + "/lib/metaflip/fleet.w")
  if marker != nil
    return ffls_canonical_dir(root + "/lib/metaflip")
  ""

-> ffn_runtime_marker(root) (String) i64
  if ffn_normalize_runtime_root(root) != ""
    return 1
  0

-> ffn_discover_runtime_root(configured) (String)
  if configured != ""
    return ffn_normalize_runtime_root(configured)
  configured = env("METAFLIP_RUNTIME_ROOT")
  if configured == nil || configured == ""
    configured = env("METAFLIP_ROOT")
  if configured == nil || configured == ""
    configured = env("METAFLIP_ASSET_ROOT")
  if configured != nil && configured != ""
    return ffn_normalize_runtime_root(configured)
  executable_dir = System.executable_dir
  if executable_dir != nil && executable_dir != ""
    located = ffn_normalize_runtime_root(executable_dir)
    if located == ""
      located = ffn_normalize_runtime_root(executable_dir + "/..")
    if located == ""
      located = ffn_normalize_runtime_root(executable_dir + "/../..")
    if located != ""
      return located
  if __DIR__ != nil
    located = ffn_normalize_runtime_root(__DIR__)
    if located == ""
      located = ffn_normalize_runtime_root(__DIR__ + "/..")
    if located == ""
      located = ffn_normalize_runtime_root(__DIR__ + "/../..")
    if located != ""
      return located
  candidate = capture("pwd").strip()
  depth = 0 ## i64
  while depth < 12
    located = ffn_normalize_runtime_root(candidate)
    if located != ""
      return located
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

# Freeze one generation's exact archive sources for lazy shoulder expansion.
# Slots are allocated only until the configured archive high-water capacity;
# later rank generations reseed those slots in place, so a long campaign does
# not retain one full snapshot per generation under the lifetime allocator.
-> ffn_snapshot_archive_into(snapshots, archive, capacity, state_size, seed) i64
  limit = archive.size() ## i64
  if limit > capacity
    limit = capacity
  copied = 0 ## i64
  while copied < limit
    loaded = 0 ## i64
    if copied < snapshots.size()
      loaded = ffw_reseed_from(snapshots[copied], archive[copied], seed + copied * 17)
    else
      stable = i64[state_size]
      loaded = ffw_reseed_from(stable, archive[copied], seed + copied * 17)
      if loaded > 0
        snapshots.push(stable)
    if loaded < 1
      return copied
    copied += 1
  copied

# Probe shoulder-bank admission on the live exact state, then either append a
# fresh stable copy or reseed an existing bank slot in place.  Replacement must
# not allocate a second full state and overwrite the old slot by reference —
# under Tungsten's campaign-lifetime allocator that retained every displaced
# STATE_SIZE buffer until OOM (observed ~369 GiB on a 188-walker 4x4 run).
# Signature scratch is coordinator-owned and reused across every CPU/GPU candidate.
-> ffn_near_add_if_admitted(bank, signatures, uses, successes, candidate, capacity, signature_quota, min_distance, counters, signature_values, signature_counts, axis_signatures, state_size, seed) i64
  signature = ffbp_structural_signature_scratch(candidate, signature_values, signature_counts, axis_signatures) ## i64
  action = ffbp_near_admission_action(bank, signatures, candidate, capacity, signature_quota, min_distance, counters, signature) ## i64
  if action == 0
    return 0
  if action == 1
    stable = ffn_clone_trusted(candidate, state_size, seed)
    if stable == nil
      return 0
    return ffbp_near_commit(bank, signatures, uses, successes, stable, signature, action, counters)
  # Replacement: reseed the victim slot; do not orphan the previous state.
  slot = action - 2 ## i64
  if slot < 0 || slot >= bank.size()
    return 0
  loaded = ffw_reseed_from(bank[slot], candidate, seed) ## i64
  if loaded < 1
    return 0
  signatures[slot] = signature
  uses[slot] = 0
  successes[slot] = 0
  counters[0] = counters[0] + 1
  counters[1] = counters[1] + 1
  1

-> ffn_atomic_write(path, body, run_tag) (String String String) i64
  tmp = path + ".tmp." + run_tag
  wrote = write_file(tmp, body)
  result = 0 ## i64
  if wrote
    moved = ccall("__w_rename", tmp, path)
    if moved
      result = 1
  result

# GPU/rect worker threads return the boolean from system()/persistent dispatch
# (true on exit 0, false otherwise).  Never feed that WValue to integer paths
# (w_to_i64 treats the singleton true=0x2 as a type error).  Normalize once.
-> ffn_join_ok(thread_result) i64
  ok = 0 ## i64
  if thread_result == true
    ok = 1
  ok

-> ffn_thread_join_release(thread)
  ccall("w_thread_join_release", thread)

# Drain an ordinary GPU controller without allowing an experimental pool/SIMD
# kernel to strand final persistence. Thread.kill cancels system(), whose
# runtime cleanup terminates and waitpid-reaps the exact child process group.
#
# IMPORTANT: Thread.join(timeout) returns true/false (completed vs timed out),
# while join_release returns the worker's system() boolean.  Both are bool
# singletons — never return them raw into ## i64 slots.  This helper always
# returns a plain i64 0/1 for "joined within the deadline".
-> ffn_thread_join_bounded(thread, timeout_ms) i64
  joined = thread.join(timeout_ms)
  ok = 0 ## i64
  if joined == true
    ok = 1
  if joined == false
    z = thread.kill
  # Always reap/free the thread object; discard the worker return value.
  z = ffn_thread_join_release(thread)
  ok

# Non-empty scheme body is required before late-load on interrupt; a killed
# child often leaves "" or a partial file that is not worth parsing.
-> ffn_scheme_file_nonempty(raw) i64
  ok = 0 ## i64
  if raw != nil
    if raw.size() > 0
      ok = 1
  ok

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

# Zero-pad a small non-negative index for stable bank filenames (00..99).
-> ffn_index_token(i) (i64)
  if i < 0
    return "00"
  if i < 10
    return "0" + i.to_s()
  if i < 100
    return i.to_s()
  i.to_s()

-> ffn_ensure_dir(path) (String) i64
  if path == ""
    return 0
  ok = system("mkdir -p " + ffg_shell_quote(path))
  result = 0 ## i64
  if ok
    result = 1
  result

# Persist every admitted shoulder scheme under dir/prefix_NN.txt.  Overwrites
# the same stable slots each dump so rsync/pull always sees a complete bank.
# Returns the number of schemes successfully written.
-> ffn_dump_bank(bank, dir, prefix, run_tag) i64
  if dir == "" || prefix == ""
    return 0
  if ffn_ensure_dir(dir) == 0
    return 0
  written = 0 ## i64
  i = 0 ## i64
  while i < bank.size()
    if bank[i] != nil
      path = dir + "/" + prefix + "_" + ffn_index_token(i) + ".txt"
      rank = ffn_dump_trusted(bank[i], path, run_tag + "-" + prefix + i.to_s()) ## i64
      if rank > 0
        written += 1
    i += 1
  # Manifest for humans and for loaders that want a size check.
  manifest = "count=" + written.to_s() + " capacity_slots=" + bank.size().to_s() + "\n"
  z = ffn_atomic_write(dir + "/" + prefix + "_manifest.txt", manifest, run_tag + "-" + prefix + "-manifest") ## i64
  written

# Load every bare rank-header dump from dir matching prefix_NN.txt into the
# shoulder bank.  Does not clear existing entries — callers usually load after
# algebraic bank construction so file-backed discoveries merge with escapes.
# Returns the number of schemes admitted (push or replace).
-> ffn_load_near_bank(dir, prefix, max_slots, n, capacity, state_size, seed_base, dslack, cycles, workq, wanderq, bank, signatures, uses, successes, bank_capacity, signature_quota, min_distance, counters) i64
  if dir == "" || prefix == ""
    return 0
  admitted = 0 ## i64
  i = 0 ## i64
  limit = max_slots ## i64
  if limit < 1
    limit = bank_capacity
  if limit > 256
    limit = 256
  while i < limit
    path = dir + "/" + prefix + "_" + ffn_index_token(i) + ".txt"
    exists = system("test -f " + ffg_shell_quote(path))
    if exists
      candidate = i64[state_size]
      rank = ffw_load_scheme_cap(candidate, path, n, capacity, seed_base + i * 17, dslack, cycles, workq, wanderq) ## i64
      if rank > 0
        if ffw_verify_best_exact(candidate, n) == 1
          if ffbp_near_add(bank, signatures, uses, successes, candidate, bank_capacity, signature_quota, min_distance, counters) == 1
            admitted += 1
    i += 1
  admitted

-> ffn_dump_near_dirs(near1, near2, near_dir, run_tag) i64
  if near_dir == ""
    return 0
  n1 = ffn_dump_bank(near1, near_dir + "/near1", "near1", run_tag) ## i64
  n2 = ffn_dump_bank(near2, near_dir + "/near2", "near2", run_tag) ## i64
  n1 + n2

-> ffn_dump_rect_atomic(state, path, run_tag, component) (i64[] String String i64) i64
  tmp = path + ".tmp." + run_tag + "." + ffn_rect_tag(component)
  rank = ffr_dump_best(state, tmp) ## i64
  if rank > 0
    moved = ccall("__w_rename", tmp, path)
    if moved
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
  if ffbi_best_id(a) == ffbi_best_id(b)
    return 0
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
-> ffn_current_distance_raw(left, right) (i64[] i64[]) i64
  left_rank = ffw_current_rank(left) ## i64
  right_rank = ffw_current_rank(right) ## i64
  common = 0 ## i64
  i = 0 ## i64
  while i < left_rank
    common += ffn_current_term_in(right, ffw_read_current_u(left, i), ffw_read_current_v(left, i), ffw_read_current_w(left, i))
    i += 1
  left_rank + right_rank - common - common

-> ffn_current_distance(left, right) (i64[] i64[]) i64
  if ffbi_current_id(left) == ffbi_current_id(right)
    return 0
  ffn_current_distance_raw(left, right)

-> ffn_current_to_best_distance(state, best) (i64[] i64[]) i64
  if ffbi_current_id(state) == ffbi_best_id(best)
    return 0
  current_rank = ffw_current_rank(state) ## i64
  best_rank = ffw_best_rank(best) ## i64
  common = 0 ## i64
  i = 0 ## i64
  while i < current_rank
    common += ffn_term_in(best, ffw_read_current_u(state, i), ffw_read_current_v(state, i), ffw_read_current_w(state, i))
    i += 1
  current_rank + best_rank - common - common

-> ffn_best_to_current_distance(candidate, active) (i64[] i64[]) i64
  if ffbi_best_id(candidate) == ffbi_current_id(active)
    return 0
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
  ffbi_current_id(state)

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
  # No temporary identities[] — campaign-lifetime allocator retained one
  # J-word array every TUI frame under the previous version.
  i = 0 ## i64
  while i < count
    id_i = ffbi_current_id(states[i]) ## i64
    seen = 0 ## i64
    j = 0 ## i64
    while j < i
      id_j = ffbi_current_id(states[j]) ## i64
      pair_distance = 0 ## i64
      if id_i != id_j
        pair_distance = ffn_current_distance_raw(states[i], states[j])
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

-> ffn_clone_current_exact_into(src, candidate, us, vs, ws, n, capacity, seed, dslack, cycles, workq, wanderq) (i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64) i64
  rank = ffw_current_rank(src) ## i64
  if rank < 1
    return 0
  exported = ffw_export_current(src, us, vs, ws) ## i64
  if exported != rank
    return 0
  loaded = ffw_init_terms_cap(candidate, us, vs, ws, rank, n, capacity, seed, dslack, cycles, workq, wanderq) ## i64
  if loaded != rank || ffw_verify_best_exact(candidate, n) != 1
    return 0
  loaded

-> ffn_state_is_c3(state, n, capacity) (i64[] i64 i64) i64
  ffbi_state_is_c3(state, n, 0)

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

-> ffn_archive_admission_action(archive, candidate, capacity, min_distance) i64
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
        return 1
      if archive.size() >= capacity
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
          return replace + 2
  0

-> ffn_archive_add(archive, candidate, capacity, min_distance, counters)
  action = ffn_archive_admission_action(archive, candidate, capacity, min_distance) ## i64
  if action == 1
    archive.push(candidate)
  if action >= 2
    slot = action - 2 ## i64
    # Prefer reseed so a displaced archive state is not retained forever.
    loaded = ffw_reseed_from(archive[slot], candidate, 1) ## i64
    if loaded < 1
      archive[slot] = candidate
    counters[1] = counters[1] + 1
  if action > 0
    counters[0] = counters[0] + 1
    return 1
  if action == 0
    counters[2] = counters[2] + 1
  0

# Hot CPU candidates are copied into archive-owned storage only after the
# allocation-free admission plan succeeds. Appends allocate at most capacity
# slots; replacements reuse the selected slot in place.
-> ffn_archive_add_copy(archive, candidate, capacity, min_distance, counters, state_size, seed) i64
  action = ffn_archive_admission_action(archive, candidate, capacity, min_distance) ## i64
  if action == 0
    counters[2] = counters[2] + 1
    return 0
  if action == 1
    stored = i64[state_size]
    loaded = ffw_reseed_from(stored, candidate, seed) ## i64
    if loaded < 1
      counters[2] = counters[2] + 1
      return 0
    archive.push(stored)
  if action >= 2
    slot = action - 2 ## i64
    loaded = ffw_reseed_from(archive[slot], candidate, seed) ## i64
    if loaded < 1
      counters[2] = counters[2] + 1
      return 0
    counters[1] = counters[1] + 1
  counters[0] = counters[0] + 1
  1

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
        # Reseed in place; reference overwrite orphans full states permanently.
        loaded = ffw_reseed_from(bank[replace], candidate, 1) ## i64
        if loaded < 1
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
  # One scratch set for the whole rebuild — not per candidate.
  sig_values = i64[capacity]
  sig_counts = i64[capacity]
  sig_axes = i64[3]
  work_q = ffp_work_moves(n, 1) ## i64
  wander_q = ffp_wander_moves(n, 1) ## i64
  base_rank = ffw_best_rank(base) ## i64
  kind = 1 ## i64
  while kind <= 5
    nonce = 0 ## i64
    while nonce < 6
      c = ffn_escape_state(base, kind, nonce, n, capacity, state_size, 1009 + kind * 97 + nonce, dslack, cycles, work_q, wander_q, 0)
      if c != nil
        rank = ffw_best_rank(c) ## i64
        z = ffn_bank_add(mixed, c, 32, 2) ## i64
        if rank == base_rank + 1
          z = ffbp_near_add_scratch(near1, near1_signatures, near1_uses, near1_successes, c, near1_capacity, signature_quota, 2, near_counters, sig_values, sig_counts, sig_axes)
        if rank == base_rank + 2
          z = ffbp_near_add_scratch(near2, near2_signatures, near2_uses, near2_successes, c, near2_capacity, signature_quota, 2, near_counters, sig_values, sig_counts, sig_axes)
      if kind == 3 || kind == 4
        s = ffn_escape_state(base, kind, nonce, n, capacity, state_size, 4001 + kind * 97 + nonce, dslack, cycles, work_q, wander_q, 1)
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

# Add bounded, density-directed whole-scheme GL images to the generic restart
# pool.  These are exact reparametrizations, not independent algebraic-basin
# evidence; the cheap `gi` signature attached to CPU provenance below makes
# that distinction visible without attempting a full GL canonicalizer.
# counters: attempted seeds, improved images, admitted images, descent steps.
-> ffn_add_global_isotropy_images(sources, mixed, n, capacity, state_size, dslack, cycles, workq, wanderq, counters) i64
  source_count = sources.size() ## i64
  admitted = 0 ## i64
  i = 0 ## i64
  while i < source_count
    counters[0] = counters[0] + 1
    candidate = i64[state_size]
    stats = i64[4]
    improved = ffgir_density_descent_state_into(sources[i], candidate, n, capacity, 57001 + counters[0] * 17, dslack, cycles, workq, wanderq, 32, stats) ## i64
    if improved > 0
      counters[1] = counters[1] + 1
      counters[3] = counters[3] + stats[2]
      if ffn_bank_add(mixed, candidate, 32, 2) == 1
        counters[2] = counters[2] + 1
        admitted += 1
    i += 1
  admitted

-> ffn_global_isotropy_tag(state) (i64[])
  signature = ffgir_orbit_signature(state) ## i64
  if signature < 0
    signature = 0 - signature
  "gi" + (signature % 10000).to_s()

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
  # Generic split is the broadest direct GPU walk. Rotate it across exact
  # same-rank frontier components instead of always following the density
  # leader; on 4x4 this explicitly alternates the disjoint d450/d677 basins.
  if role == 3 && archive.size() > 0
    seed = archive[epoch % archive.size()]
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

# Write a frozen-core / fringe-mutable seed into an existing state buffer.
# Returns 1 on success.  Hot campaign paths must use this instead of allocating
# a second STATE_SIZE candidate and dropping the previous island buffer.
-> ffn_core_fringe_state_into(dst, best, archive, near1, near2, mixed, n, capacity, seed, dslack, cycles, workq, wanderq, core_out) i64
  if dst == nil || best == nil
    return 0
  rank = ffw_best_rank(best) ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  z = ffw_export_best(best, us, vs, ws) ## i64
  if z != rank
    return 0
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
  loaded = ffw_init_terms_cap(dst, us, vs, ws, rank, n, capacity, seed, dslack, cycles, workq, wanderq) ## i64
  if loaded != rank || ffw_verify_best_exact(dst, n) != 1
    return 0
  1

-> ffn_core_fringe_state(best, archive, near1, near2, mixed, n, capacity, state_size, seed, dslack, cycles, workq, wanderq, core_out)
  # Cold-path convenience: allocate once. Prefer ffn_core_fringe_state_into on
  # the live campaign so island slots are not discarded every cycle-out.
  candidate = i64[state_size]
  if ffn_core_fringe_state_into(candidate, best, archive, near1, near2, mixed, n, capacity, seed, dslack, cycles, workq, wanderq, core_out) == 1
    return candidate
  nil

-> ffn_pool_seed(mode, epoch, best, map_states, map_uses, c3_base, orbit_bank, polar_bank, n, capacity, state_size, dslack, cycles, workq, wanderq)
  seed = best
  if mode == 1 || mode == 2 || mode == 3 || mode == 4 || mode == 11 || mode == 12 || mode == 13 || mode == 14 || mode == 15 || mode == 16 || mode == 17
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
    escaped = ffkp_beam_recipe_state(best, n, capacity, state_size, epoch, dslack, cycles, workq, wanderq)
    if escaped != nil
      seed = escaped
  seed

-> ffn_parent_companion(primary, map_states, archive, min_distance)
  companion = nil
  farthest = min_distance - 1 ## i64
  pool_index = 0 ## i64
  while pool_index < 2
    pool = map_states
    if pool_index == 1
      pool = archive
    i = 0 ## i64
    while i < pool.size()
      distance = ffn_distance(primary, pool[i]) ## i64
      if distance > farthest
        farthest = distance
        companion = pool[i]
      i += 1
    pool_index += 1
  companion

-> ffn_parent_pair_primary(map_states, archive, min_distance)
  required = min_distance ## i64
  if required < 0
    required = 0
  left_pool_index = 0 ## i64
  while left_pool_index < 2
    left_pool = map_states
    if left_pool_index == 1
      left_pool = archive
    left_index = 0 ## i64
    while left_index < left_pool.size()
      left = left_pool[left_index]
      left_identity = ffbi_best_id(left) ## i64
      right_pool_index = left_pool_index ## i64
      while right_pool_index < 2
        right_pool = map_states
        if right_pool_index == 1
          right_pool = archive
        right_index = 0 ## i64
        if right_pool_index == left_pool_index
          right_index = left_index + 1
        while right_index < right_pool.size()
          right = right_pool[right_index]
          # Equal canonical identities include the same object and exact
          # duplicates; neither can supply differential surgery distance.
          if ffbi_best_id(right) != left_identity
            if ffn_distance(left, right) >= required
              return left
          right_index += 1
        right_pool_index += 1
      left_index += 1
    left_pool_index += 1
  nil

-> ffn_has_parent_pair(map_states, archive, min_distance) i64
  if ffn_parent_pair_primary(map_states, archive, min_distance) != nil
    return 1
  0

-> ffn_fill_pool_readiness(ready, generic_ready, mitm_ready, constraint_ready, kxor_ready, differential_ready, span_ready, shear_ready, frozen_sat_ready, global_shear_ready, parent_pair_ready, orbit_bank, polar_bank)
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
  ready[11] = kxor_ready
  if differential_ready != 0 && parent_pair_ready != 0
    ready[12] = 1
  ready[13] = kxor_ready
  ready[14] = kxor_ready
  ready[15] = span_ready
  ready[16] = span_ready
  ready[17] = shear_ready
  ready[18] = frozen_sat_ready
  ready[19] = global_shear_ready
  count = 0 ## i64
  mode = 0
  while mode < ffkp_mode_count()
    count += ready[mode]
    mode += 1
  count

-> ffn_gpu_seed_path(run_tag, n, role) (String i64 i64)
  "/tmp/metaflip_gpu_seed_" + run_tag + "_" + n.to_s() + "_" + role.to_s() + ".txt"

-> ffn_gpu_output_path(run_tag, n, role) (String i64 i64)
  "/tmp/metaflip_gpu_best_" + run_tag + "_" + n.to_s() + "_" + role.to_s() + ".txt"

-> ffn_gpu_log_path(run_tag, n, role) (String i64 i64)
  "/tmp/metaflip_gpu_log_" + run_tag + "_" + n.to_s() + "_" + role.to_s() + ".txt"

# Event-triggered salvage for a worker-preserved nominal record.  The GPU is
# best used to discover the near-record; reconstructing and solving the exact
# one-bit edit syndrome is faster on one CPU (1 ms at 4x4 through ~289 ms at
# 7x7 in the measured safe-axis lanes).  Modes 1--6 never edit two axes of one
# term.  The broader nonlinear mode 0 is tried only through 5x5 and still must
# pass the independent full n^6 gate below.
-> ffn_repair_gpu_internal_reject(run_tag, n, slot, nonce, target_rank, capacity, dslack, cycles, workq, wanderq, scratch) (String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  output_path = ffn_gpu_output_path(run_tag, n, slot)
  candidate_path = ffgr_worker_candidate_path(output_path)
  worker_meta = read_file(ffgr_worker_meta_path(output_path))
  candidate_raw = read_file(candidate_path)
  if ffn_scheme_file_nonempty(worker_meta) == 0 || ffn_scheme_file_nonempty(candidate_raw) == 0
    return 0
  nominal_rank = ffgr_meta_i64(worker_meta, "nominal_rank", ffgr_nominal_rank(candidate_raw)) ## i64
  if nominal_rank < 1 || nominal_rank > target_rank || nominal_rank > capacity
    return 0
  parsed = ffw_load_scheme_cap(scratch, candidate_path, n, capacity, 84001 + (nonce & 65535) + slot, dslack, cycles, workq, wanderq) ## i64
  if parsed > 0 || ffw_valid(scratch) == 0 || ffw_current_rank(scratch) != nominal_rank
    return 0
  if ffgr_candidate_exact_error(scratch, n, nominal_rank) <= 0
    return 0

  max_work_words = 4000000 ## i64
  if n == 6
    max_work_words = 6000000
  if n == 7
    max_work_words = 26000000
  modes = [1, 2, 3, 4, 5, 6]
  # A 7x7 safe-axis elimination peaks near 201 MB.  Cover every pure axis and
  # one rotating striped assignment without retaining six such allocations in
  # a single reject event.
  if n == 7
    modes = [1, 2, 3, 4 + (nonce % 3)]
  if n <= 5
    modes.push(0)
  mode_index = 0 ## i64
  while mode_index < modes.size()
    out_u = i64[capacity]
    out_v = i64[capacity]
    out_w = i64[capacity]
    repair_meta = i64[16]
    repaired = ffsr_try_repair_current(scratch, n, modes[mode_index], max_work_words, out_u, out_v, out_w, capacity, repair_meta) ## i64
    if repaired > 0 && repaired <= target_rank && repair_meta[8] == 1
      loaded = ffw_init_terms_cap(scratch, out_u, out_v, out_w, repaired, n, capacity, 85001 + (nonce & 65535) + mode_index, dslack, cycles, workq, wanderq) ## i64
      if loaded == repaired && ffw_verify_current_exact(scratch, n) == 1
        return repaired
    mode_index += 1
  0

# Freeze a worker-side nominal record only when it meets the campaign's strict
# improvement target.  The worker exact error and this independent parser/gate
# error are recorded separately, along with immutable seed/candidate bytes and
# the coordinator launch nonce.  The returned value is the monotonic counter.
-> ffn_harvest_gpu_internal_reject(run_tag, n, slot, role, pool_mode, nonce, target_rank, capacity, dslack, cycles, workq, wanderq, counter, scratch) (String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  output_path = ffn_gpu_output_path(run_tag, n, slot)
  candidate_path = ffgr_worker_candidate_path(output_path)
  seed_path = ffgr_worker_seed_path(output_path)
  meta_path = ffgr_worker_meta_path(output_path)
  worker_meta = read_file(meta_path)
  candidate_raw = read_file(candidate_path)
  seed_raw = read_file(seed_path)
  if ffn_scheme_file_nonempty(worker_meta) == 1 && ffn_scheme_file_nonempty(candidate_raw) == 1
    nominal_rank = ffgr_meta_i64(worker_meta, "nominal_rank", ffgr_nominal_rank(candidate_raw)) ## i64
    if nominal_rank > 0 && target_rank > 0 && nominal_rank <= target_rank
      parsed = ffw_load_scheme_cap(scratch, candidate_path, n, capacity, 81001 + counter * 17 + slot, dslack, cycles, workq, wanderq) ## i64
      coordinator_error = 0 ## i64
      if parsed <= 0
        coordinator_error = ffgr_candidate_exact_error(scratch, n, nominal_rank)
      worker = ffgr_meta_value(worker_meta, "worker")
      if worker == ""
        worker = "unknown"
      worker_nonce = ffgr_meta_i64(worker_meta, "worker_nonce", 0 - 1) ## i64
      worker_round = ffgr_meta_i64(worker_meta, "worker_round", 0 - 1) ## i64
      seed_rank = ffgr_meta_i64(worker_meta, "seed_rank", 0 - 1) ## i64
      worker_error = ffgr_meta_i64(worker_meta, "exact_error", 0 - 100) ## i64
      if seed_raw == nil
        seed_raw = read_file(ffn_gpu_seed_path(run_tag, n, slot))
      if seed_raw == nil
        seed_raw = ""
      counter += 1
      # Preserve seed/candidate/meta under /tmp for offline replay.  Do not
      # print to the campaign console: the one-line banner flashes too briefly
      # to read and reads as a hard error when it is only a discarded
      # inexact GPU proposal (counter still lands in the DONE summary).
      z = ffgr_preserve(run_tag, n, counter, slot, role, pool_mode, nonce, target_rank, worker, worker_nonce, worker_round, seed_rank, nominal_rank, worker_error, coordinator_error, seed_raw, candidate_raw) ## i64
  z = ffgr_clear_worker_sidecars(output_path) ## i64
  counter

-> ffn_rect_tag(component) (i64)
  if component == 0
    return "334"
  if component == 1
    return "344"
  "invalid"

-> ffn_rect_tensor(component) (i64)
  if component == 0
    return "3x3x4"
  if component == 1
    return "3x4x4"
  "invalid"

-> ffn_rect_n(component) (i64) i64
  3

-> ffn_rect_m(component) (i64) i64
  if component == 0
    return 3
  4

-> ffn_rect_p(component) (i64) i64
  4

-> ffn_rect_seed_path(run_tag, component) (String i64)
  "/tmp/metaflip_rect_seed_" + run_tag + "_" + ffn_rect_tag(component) + ".txt"

-> ffn_rect_output_path(run_tag, component) (String i64)
  "/tmp/metaflip_rect_best_" + run_tag + "_" + ffn_rect_tag(component) + ".txt"

-> ffn_rect_log_path(run_tag, component) (String i64)
  "/tmp/metaflip_rect_log_" + run_tag + "_" + ffn_rect_tag(component) + ".txt"

-> ffn_rect_composed_path(run_tag, component, launch_number) (String i64 i64)
  "/tmp/metaflip_composed_777_" + run_tag + "_" + ffn_rect_tag(component) + "_" + launch_number.to_s() + ".txt"

-> ffn_executable_exists(path) (String) i64
  checked = system("test -x " + ffg_shell_quote(path))
  exists = 0 ## i64
  if checked
    exists = 1
  exists

-> ffn_binary_fresh(binary, source) (String String) i64
  fresh = 0 ## i64
  if ffn_executable_exists(binary) == 1
    binary_mtime = file_mtime_ns(binary)
    source_mtime = file_mtime_ns(source)
    if binary_mtime != nil && source_mtime != nil
      if binary_mtime >= source_mtime
        fresh = 1
  fresh

-> ffn_binary_fresh2(binary, first, second) (String String String) i64
  fresh = ffn_binary_fresh(binary, first) ## i64
  if fresh == 1
    binary_mtime = file_mtime_ns(binary)
    second_mtime = file_mtime_ns(second)
    if binary_mtime == nil || second_mtime == nil || binary_mtime < second_mtime
      fresh = 0
  fresh

-> ffn_binary_fresh3(binary, first, second, third) (String String String String) i64
  fresh = ffn_binary_fresh2(binary, first, second) ## i64
  if fresh == 1
    binary_mtime = file_mtime_ns(binary)
    third_mtime = file_mtime_ns(third)
    if binary_mtime == nil || third_mtime == nil || binary_mtime < third_mtime
      fresh = 0
  fresh

-> ffn_binary_fresh4(binary, first, second, third, fourth) (String String String String String) i64
  if ffn_executable_exists(binary) == 0
    return 0
  binary_mtime = file_mtime_ns(binary)
  if binary_mtime == nil
    return 0
  paths = [first, second, third, fourth]
  i = 0 ## i64
  while i < paths.size()
    dependency_mtime = file_mtime_ns(paths[i])
    if dependency_mtime == nil || binary_mtime < dependency_mtime
      return 0
    i += 1
  1

-> ffn_binary_fresh5(binary, first, second, third, fourth, fifth) (String String String String String String) i64
  if ffn_binary_fresh4(binary, first, second, third, fourth) == 0
    return 0
  binary_mtime = file_mtime_ns(binary)
  fifth_mtime = file_mtime_ns(fifth)
  if binary_mtime == nil || fifth_mtime == nil || binary_mtime < fifth_mtime
    return 0
  1

-> ffn_binary_fresh6(binary, first, second, third, fourth, fifth, sixth) (String String String String String String String) i64
  if ffn_binary_fresh5(binary, first, second, third, fourth, fifth) == 0
    return 0
  binary_mtime = file_mtime_ns(binary)
  sixth_mtime = file_mtime_ns(sixth)
  if binary_mtime == nil || sixth_mtime == nil || binary_mtime < sixth_mtime
    return 0
  1

-> ffn_persistent_command_path(run_tag, slot) (String i64)
  "/tmp/metaflip_gpu_persist_cmd_" + run_tag + "_" + slot.to_s() + ".txt"

-> ffn_persistent_ack_path(run_tag, slot) (String i64)
  "/tmp/metaflip_gpu_persist_ack_" + run_tag + "_" + slot.to_s() + ".txt"

-> ffn_persistent_wait(ack_path, generation, state, timeout_ms, process) i64
  start = ccall("__w_clock_ms") ## i64
  while ccall("__w_clock_ms") - start < timeout_ms
    if ffpg_ack_matches(read_file(ack_path), generation, state) == 1
      return 1
    if process != nil && process.alive? == false
      return 0
    if ccall("__w_interrupted") != 0
      return 0
    z = ccall("__w_sleep_ms", 10)
  0

# A persistent Metal child that misses a bounded epoch/stop deadline cannot be
# allowed to strand coordinator shutdown or survive into the next campaign.
# Thread.kill cancels the controller's OS.system wait; the runtime cancellation
# cleanup owns that exact posix_spawn process group, sends TERM/KILL as needed,
# and waitpid-reaps it.  No process-name matching is involved.
-> ffn_persistent_force_stop_slot(run_tag, slot, processes, active, generations, lanes) i64
  process = processes[slot]
  if process == nil
    active[slot] = 0
    lanes[slot] = 0
    return 1
  if process.alive?
    z = process.kill
  result = ffn_thread_join_release(process)
  processes[slot] = nil
  active[slot] = 0
  lanes[slot] = 0
  1

-> ffn_persistent_stop_slot(run_tag, slot, processes, active, generations, lanes) i64
  if active[slot] == 0
    return 1
  process = processes[slot]
  generations[slot] = generations[slot] + 1
  generation = generations[slot] ## i64
  command_path = ffn_persistent_command_path(run_tag, slot)
  ack_path = ffn_persistent_ack_path(run_tag, slot)
  body = ffpg_command(generation, 0, 1, 1, 0, 1, 1, 1, 1)
  published = ffpg_publish(command_path, body, run_tag + "-stop-" + slot.to_s()) ## i64
  stopped = 0 ## i64
  if published == 1
    stopped = ffn_persistent_wait(ack_path, generation, "stopped", 30000, process)
  if stopped == 1 && process != nil
    result = ffn_thread_join_release(process)
    process = nil
  if process != nil && process.alive? == false
    result = ffn_thread_join_release(process)
    process = nil
    stopped = 1
  if stopped == 0
    stopped = ffn_persistent_force_stop_slot(run_tag, slot, processes, active, generations, lanes)
  if stopped != 0
    processes[slot] = nil
    active[slot] = 0
    lanes[slot] = 0
  stopped

-> ffn_persistent_dispatch(base_command, log_path, run_tag, slot, requested_lanes, steps, reseed, margin, workq, wanderq, wthr, escapes, processes, active, generations, lanes) i64
  process = processes[slot]
  if active[slot] != 0 && process != nil && process.alive? == false
    result = ffn_thread_join_release(process)
    processes[slot] = nil
    active[slot] = 0
    lanes[slot] = 0
  if active[slot] != 0 && lanes[slot] != requested_lanes
    z = ffn_persistent_stop_slot(run_tag, slot, processes, active, generations, lanes) ## i64
  # State 2 only exists while a freshly launched child is inside its bounded
  # ready handshake. A missed deadline is force-stopped below, so no stale
  # ownership can suppress this role forever or permit an orphan duplicate.
  if active[slot] == 2
    ack_path = ffn_persistent_ack_path(run_tag, slot)
    if ffpg_ack_matches(read_file(ack_path), 0, "ready") == 1
      active[slot] = 1
    if active[slot] == 2
      return 0
  command_path = ffn_persistent_command_path(run_tag, slot)
  ack_path = ffn_persistent_ack_path(run_tag, slot)
  if active[slot] == 0
    prepared = ffpg_prepare_mailboxes(command_path, ack_path, run_tag + "-start-" + slot.to_s()) ## i64
    if prepared == 0
      return 0
    worker_command = ffpg_launch_command(base_command, command_path, ack_path)
    # Redirection belongs after the two persistent argv fields. Putting it on
    # base_command makes command/ack paths shell redirection operands instead
    # of worker argv[18]/argv[19].
    worker_command = worker_command + " >> " + ffg_shell_quote(log_path) + " 2>&1"
    process = Thread.new ->
      system(worker_command)
    processes[slot] = process
    active[slot] = 2
    lanes[slot] = requested_lanes
    ready = ffn_persistent_wait(ack_path, 0, "ready", 30000, process) ## i64
    if ready == 0
      z = ffn_persistent_force_stop_slot(run_tag, slot, processes, active, generations, lanes)
      return 0
    active[slot] = 1
  generations[slot] = generations[slot] + 1
  generation = generations[slot] ## i64
  body = ffpg_command(generation, 1, steps, reseed, margin, workq, wanderq, wthr, escapes)
  published = ffpg_publish(command_path, body, run_tag + "-run-" + slot.to_s() + "-" + generation.to_s()) ## i64
  if published == 0
    return 0
  completed = ffn_persistent_wait(ack_path, generation, "done", 120000, processes[slot]) ## i64
  if completed == 0
    z = ffn_persistent_force_stop_slot(run_tag, slot, processes, active, generations, lanes)
  completed

-> ffn_gpu_launch(root, binary, run_tag, n, role, lanes, steps, rounds, seed_state, elapsed_ms, persistent_processes, persistent_active, persistent_generations, persistent_lanes)
  seed_path = ffn_gpu_seed_path(run_tag, n, role)
  output_path = ffn_gpu_output_path(run_tag, n, role)
  log_path = ffn_gpu_log_path(run_tag, n, role)
  z = ffn_dump_trusted(seed_state, seed_path, run_tag) ## i64
  if z < 1
    return nil
  write_ok = write_file(output_path, "")
  if write_ok == false
    return nil
  if ffgr_clear_worker_sidecars(output_path) == 0
    return nil
  escapes = 1 ## i64
  if role == 3
    escapes = lanes
  reseed = ffp_gpu_reseed(role) ## i64
  margin = ffp_gpu_margin(role) ## i64
  workq = ffg_cal2zone_workq(role) ## i64
  wanderq = ffg_cal2zone_wanderq(role) ## i64
  wthr = ffg_cal2zone_wthr(role) ## i64
  command = ffb_epoch_command(root, binary, n, seed_path, output_path, "", 0, steps, reseed, margin, workq, wanderq, wthr, lanes, "", escapes, rounds)
  if command == ""
    return nil
  Thread.new ->
    t0 = ccall("__w_clock_ms") ## i64
    ok = false
    if rounds == 1
      persistent_ok = ffn_persistent_dispatch(command, log_path, run_tag, role, lanes, steps, reseed, margin, workq, wanderq, wthr, escapes, persistent_processes, persistent_active, persistent_generations, persistent_lanes) ## i64
      if persistent_ok == 1
        ok = true
    if rounds != 1
      bounded_command = command + " > " + ffg_shell_quote(log_path) + " 2>&1"
      ok = system(bounded_command)
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

# Launch one bounded rectangular Metal epoch.  The generated cal2zone host ABI
# is dimension-generic; the checked-in 334/344 assets specialize mask width,
# capacity, WPG, and split sampling so every proposed factor remains in range.
-> ffn_gpu_launch_rect(root, binary, run_tag, component, lanes, steps, rounds, seed_state, elapsed_ms, persistent_processes, persistent_active, persistent_generations, persistent_lanes)
  seed_path = ffn_rect_seed_path(run_tag, component)
  output_path = ffn_rect_output_path(run_tag, component)
  log_path = ffn_rect_log_path(run_tag, component)
  dumped = ffr_dump_best(seed_state, seed_path) ## i64
  if dumped < 1
    return nil
  write_ok = write_file(output_path, "")
  if write_ok == false
    return nil
  if ffrgr_prepare_worker_sidecars(output_path) == 0
    return nil
  n = ffn_rect_n(component) ## i64
  m = ffn_rect_m(component) ## i64
  p = ffn_rect_p(component) ## i64
  reseed = ffp_gpu_reseed(0) ## i64
  margin = ffp_gpu_margin(0) ## i64
  workq = ffg_cal2zone_workq(0) ## i64
  wanderq = ffg_cal2zone_wanderq(0) ## i64
  wthr = ffg_cal2zone_wthr(0) ## i64
  command = ffrgb_epoch_command(root, binary, n, m, p, seed_path, output_path, "", 0, steps, reseed, margin, workq, wanderq, wthr, lanes, "", lanes, rounds)
  if command == ""
    return nil
  Thread.new ->
    t0 = ccall("__w_clock_ms") ## i64
    slot = 13 + component ## i64
    ok = false
    if rounds == 1
      persistent_ok = ffn_persistent_dispatch(command, log_path, run_tag, slot, lanes, steps, reseed, margin, workq, wanderq, wthr, lanes, persistent_processes, persistent_active, persistent_generations, persistent_lanes) ## i64
      if persistent_ok == 1
        ok = true
    if rounds != 1
      bounded_command = command + " > " + ffg_shell_quote(log_path) + " 2>&1"
      ok = system(bounded_command)
    elapsed_ms[component] = ccall("__w_clock_ms") - t0
    ok

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
  if ffgr_clear_worker_sidecars(output_path) == 0
    return nil
  plan = i64[4]
  work = ffg_mitm_plan(lanes, steps, 700, 16, plan) ## i64
  subsets = plan[1] ## i64
  if subsets > 16
    subsets = 16
  pool = plan[2] ## i64
  nearby = ffg_mitm_nearby(launch_number) ## i64
  offset = launch_number % 256 ## i64
  command = ffm_epoch_command(root, binary, seed_path, output_path, n, subsets, pool, nearby, offset)
  if command == ""
    return nil
  command = command + " >> " + ffg_shell_quote(log_path) + " 2>&1"
  Thread.new ->
    t0 = ccall("__w_clock_ms") ## i64
    ok = system(command)
    elapsed_ms[slot] = ccall("__w_clock_ms") - t0
    ok

-> ffn_gpu_launch_pool(root, generic_binary, mitm_binary, constraint_binary, kxor_binary, differential_binary, span_binary, shear_binary, frozen_sat_binary, global_shear_binary, run_tag, n, slot, mode, lanes, steps, rounds, launch_number, seed_state, companion_state, elapsed_ms)
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
  if ffgr_clear_worker_sidecars(output_path) == 0
    return nil
  command = ""
  if mode == 0 || mode == 5 || mode == 6
    constraint_mode = 0 ## i64
    if mode == 5
      constraint_mode = 1
    if mode == 6
      constraint_mode = 2
    command = ffpc_epoch_command(root, constraint_binary, seed_path, output_path, n, constraint_mode, lanes, steps, launch_number)
  if mode == 2 || mode == 3 || mode == 11 || mode == 13 || mode == 14
    k = 6 ## i64
    # Keep bounded joins inside the empirically safe shared-buffer envelope;
    # breadth comes from rotating subsets, not one oversized allocation.
    pool = 32 ## i64
    if mode == 3
      k = 7
      pool = 24
    if mode == 11
      k = 5
      pool = 32
    if mode == 13
      k = 8
      pool = 16
    if mode == 14
      k = 9
      pool = 16
    subsets = lanes / 64 ## i64
    if subsets < 1
      subsets = 1
    if subsets > 4
      subsets = 4
    command = ffx_epoch_command(root, kxor_binary, seed_path, output_path, n, k, subsets, pool, 2, launch_number % 256)
  if mode == 12
    if companion_state == nil
      return nil
    parent_path = seed_path + ".parent"
    parent_dumped = ffn_dump_trusted(companion_state, parent_path, run_tag) ## i64
    if parent_dumped < 1
      return nil
    command = ffdb_epoch_command(root, differential_binary, seed_path, parent_path, output_path, n, 96, launch_number % 256, 12)
  if mode == 15 || mode == 16
    k = 3 ## i64
    want = 2 ## i64
    subsets = lanes / 32 ## i64
    if subsets < 1
      subsets = 1
    if subsets > 8
      subsets = 8
    phase = launch_number % 4 ## i64
    if phase == 2
      want = 3
    if phase == 3
      want = 4
    if mode == 16
      k = 4
      want = 3
      if phase == 3
        want = 4
      # One complete four-span pair table can already contain 5.69M entries.
      # The logical 128-lane reserve accounts for its device pressure without
      # multiplying that peak memory inside one child.
      subsets = 1
    command = ffsrp_epoch_command(root, span_binary, seed_path, output_path, n, k, want, subsets, launch_number % 256)
  if mode == 17
    # The real 5x5 hit lies at pair 504.  A 512-pair epoch reaches it while
    # nonce rotation opens a different contiguous source-pair window on every
    # relaunch. Larger logical allocations buy breadth up to the 2048 guard.
    pair_limit = (lanes / 32) * 64 ## i64
    if pair_limit < 512
      pair_limit = 512
    if pair_limit > 2048
      pair_limit = 2048
    command = fflrsp_epoch_command(root, shear_binary, seed_path, output_path, n, pair_limit, launch_number)
  if mode == 18
    # This is a single bounded CPU child charged as one logical SIMDgroup so
    # it can rotate with the pool without stealing a hot walker core.  The
    # child itself enforces n=4 and the clustered 16->15 exact query.
    command = fffsb_epoch_command(root, frozen_sat_binary, seed_path, output_path, 2, launch_number)
  if mode == 19
    # A whole-frontier exact CPU elimination, charged as one logical quantum.
    # Production eligibility is 5x5-only, where 8/64 deterministic plans made
    # verified beyond-one-flip endpoints in under one second total.
    command = ffgksb_epoch_command(root, global_shear_binary, seed_path, output_path, launch_number)
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
  command = command + " >> " + ffg_shell_quote(log_path) + " 2>&1"
  Thread.new ->
    t0 = ccall("__w_clock_ms") ## i64
    ok = system(command)
    elapsed_ms[slot] = ccall("__w_clock_ms") - t0
    ok

# wr_status: unknown | above | ties | beats  (vs published/configured record)
-> ffn_wr_status(best_rank, record, record_known) (i64 i64 i64)
  if record <= 0 || best_rank <= 0
    return "unknown"
  if record_known == 0 && record <= 0
    return "unknown"
  gap = best_rank - record ## i64
  if gap > 0
    return "above"
  if gap == 0
    return "ties"
  "beats"

-> ffn_wr_gap(best_rank, record) (i64 i64) i64
  if record <= 0 || best_rank <= 0
    return 0
  best_rank - record

-> ffn_status(path, run_tag, producer_state, updated_ms, sequence, n, record, record_known, best, moves, elapsed_s, archive, near1, near2, symmetry, gpu_enabled, gpu_degraded) i64
  best_rank = ffw_best_rank(best) ## i64
  best_bits = ffw_best_bits(best) ## i64
  wr_gap = ffn_wr_gap(best_rank, record) ## i64
  wr_status = ffn_wr_status(best_rank, record, record_known)
  body = "schema=4 producer_state=" + producer_state + " updated_ms=" + updated_ms.to_s() + " sequence=" + sequence.to_s()
  body = body + " tensor=" + n.to_s() + "x" + n.to_s()
  body = body + " record=" + record.to_s() + " record_known=" + record_known.to_s()
  body = body + " best_rank=" + best_rank.to_s() + " best_bits=" + best_bits.to_s()
  body = body + " wr_gap=" + wr_gap.to_s() + " wr_status=" + wr_status
  body = body + " moves=" + moves.to_s() + " elapsed=" + elapsed_s.to_s()
  body = body + " archive=" + archive.size().to_s() + " near1=" + near1.size().to_s()
  body = body + " near2=" + near2.size().to_s() + " symmetry=" + symmetry.size().to_s()
  body = body + " gpu=" + gpu_enabled.to_s() + " gpu_degraded=" + gpu_degraded.to_s() + "\n"
  stored = ffn_atomic_write(path, body, run_tag) ## i64
  stored

-> ffn_render(n, threads_count, round, elapsed_s, total_moves, record, record_known, recovered, best, states, island_best_ranks, doors, zones, sources, last_rates, last_ages, cpu_work_moves, cpu_wander_moves, archive, archive_capacity, near1, near1_capacity, near2, near2_capacity, symmetry, symmetry_capacity, archive_counters, archive_min_distance, cohort_moves, cohort_drops, cohort_ties, cohort_near, timeline_times, timeline_ranks, timeline_count, timeline_elapsed_s, gpu_enabled, gpu_policy, gpu_degraded, gpu_lanes, gpu_candidates, gpu_rank_drops, gpu_density, gpu_rewards, gpu_epochs, gpu_wall_ms, gpu_failures, gpu_disabled, gpu_retry_round, gpu_seed_ranks, gpu_pareto, gpu_pareto_archive, gpu_pareto_capacity, gpu_pareto_counters, symmetry_cpu_uses, gpu_launch_number, pool_active_modes, pool_mode_ready, rect_enabled, rect_ready, rect_active, rect_lanes, rect_states, rect_archive_counts, rect_candidates, rect_rank_drops, rect_density, rect_rewards, rect_exposure, rect_failures, rect_retry_round, rect_composition_failures, last_status_ms, sequence, now_ms, rank_levels, rank_ticks, rank_level_count, bits_levels, bits_ticks, bits_level_count, new_bests_count, tie_bests_count, cycleouts_count, exact_rejects, dslack, flash_text, flash_until_ms)
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
  title_plain = "  metaflip  <" + dims + "> GF(2)" + record_plain + "   " + state + " age " + age_text + "   seq " + sequence.to_s()
  title_paint = "  " + ff_tui_paint("metaflip", "1;33") + "  ⟨" + dims + "⟩ GF(2)" + record_paint + "   " + ff_tui_paint(state, ff_tui_health_code(state)) + ff_tui_dim(" age " + age_text + "   seq " + sequence.to_s())
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
          if rect_enabled != 0 && n == 7
            rect_left_rank = 0 ## i64
            rect_right_rank = 0 ## i64
            if rect_states[0] != nil
              rect_left_rank = ffr_best_rank(rect_states[0])
            if rect_states[1] != nil
              rect_right_rank = ffr_best_rank(rect_states[1])
            rect_left = ff7_rect_pool_label("rect-3x3x4", rect_lanes[0], rect_left_rank, rect_archive_counts[0], rect_rank_drops[0], rect_rewards[0], rect_failures[0], rect_ready[0], rect_active[0], round, rect_retry_round[0], rect_composition_failures)
            rect_right = ff7_rect_pool_label("rect-3x4x4", rect_lanes[1], rect_right_rank, rect_archive_counts[1], rect_rank_drops[1], rect_rewards[1], rect_failures[1], rect_ready[1], rect_active[1], round, rect_retry_round[1], rect_composition_failures)
            rows.push("  " + ff_tui_gpu_pool_pair(rect_left, rect_active[0], rect_ready[0], rect_right, rect_active[1], rect_ready[1], inner))
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
  rows.push("  " + ff_tui_dim("rank → asymptotic exponent (want ↓) · density → base-case ops (want ↓) · space=reset naive · w=reseed anchor · q/Ctrl-C stops"))

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
TENSOR_LABEL = "5x5"
RECT_MODE = 0 ## i64
RECT_PORTFOLIO = 0 ## i64
RECT_SHAPES = ""
# Base rectangular rounds per portfolio epoch before reallocation. Fast shapes
# may run additional fill rounds until the slowest shape finishes this quota.
# Clamp remains 1..64 via CLI validation below.
RECT_EPOCH_ROUNDS = 16 ## i64
TENSOR_EXPLICIT = 0 ## i64
J = 0 ## i64
J_EXPLICIT = 0 ## i64
STEPS = 500000 ## i64
MAX_ROUNDS = 2000000000 ## i64
MAX_SECS = 0 ## i64
DSLACK = 4 ## i64
CYCLES = 4 ## i64
GPU = 1 ## i64
GPU_POLICY = "adaptive"
# The generic and rectangular cal2zone engines reach their measured occupancy
# knee at 8,192 walkers on the reference M5 Max.  Forty-thousand-step epochs
# amortize command/relay overhead without making the exact scheduler boundary
# unresponsive.  Both remain explicit CLI knobs for smaller/larger devices.
GPU_WALKERS = 8192 ## i64
GPU_STEPS = 40000 ## i64
GPU_EPOCH_ROUNDS = 1 ## i64
GPU_BINARY = ""
GPU_REBUILD = 0 ## i64
RUNTIME_ROOT = ""
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
SEED_NAIVE = 0 ## i64
SELF_TEST = 0 ## i64
RECORD_OVERRIDE = 0 ## i64
STATUS_PATH = "metaflip_status.txt"
BEST_PATH = "metaflip_best.txt"
STATUS_EXPLICIT = 0 ## i64
BEST_EXPLICIT = 0 ## i64
RUN_TAG = ""
STATE_DIR = ""
STATE_DIR_EXPLICIT = 0 ## i64
# When set, dump near1/near2 schemes under NEAR_DIR/{near1,near2}/ periodically
# and on exit, and load any existing dumps there into the shoulder banks at
# startup (after algebraic escape construction).
NEAR_DIR = ""
NEAR_EXPLICIT = 0 ## i64

av = argv()
value_options = ["--tensor", "--rect-shapes", "--rect-epoch-rounds", "-J", "--walkers", "--steps", "--rounds", "--secs", "-d", "--density", "--cycles", "--seed", "--record", "--gpu-walkers", "--gpu-policy", "--gpu-steps", "--gpu-epoch-rounds", "--gpu-binary", "--gpu-novelty-size", "--runtime-root", "--asset-root", "--repo-root", "--state-dir", "--strategy", "--migrate", "--archive-size", "--cpu-near-size", "--cpu-near-signature-quota", "--cpu-symmetry-seeds", "--cpu-work-moves", "--cpu-wander-moves", "--status", "--best", "--run-tag", "--near-dir"]
switch_options = ["--rect", "--rebuild-gpu", "--no-gpu", "--gpu", "--no-tui", "--tui", "--quiet", "--stop-on-record", "--self-test", "--naive"]
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
    << "metaflip: unknown option " + arg
    exit(2)
  if needs_value == 1 && ai + 1 >= av.size()
    << "metaflip: missing value for " + arg
    exit(2)
  if arg == "--tensor" && ai + 1 < av.size()
    TENSOR_EXPLICIT = 1
    TENSOR_LABEL = av[ai + 1].downcase
    N = ffn_parse_tensor(TENSOR_LABEL)
    RECT_MODE = 0
    if N == 0 && ffrp_supported_label(TENSOR_LABEL) == 1
      RECT_MODE = 1
    ai += 1
  if arg == "--rect"
    RECT_PORTFOLIO = 1
  if arg == "--rect-shapes" && ai + 1 < av.size()
    RECT_SHAPES = av[ai + 1].downcase
    RECT_PORTFOLIO = 1
    ai += 1
  if arg == "--rect-epoch-rounds" && ai + 1 < av.size()
    RECT_EPOCH_ROUNDS = av[ai + 1].to_i()
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
  if arg == "--naive"
    SEED_NAIVE = 1
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
  if (arg == "--runtime-root" || arg == "--asset-root" || arg == "--repo-root") && ai + 1 < av.size()
    RUNTIME_ROOT = av[ai + 1]
    ai += 1
  if arg == "--state-dir" && ai + 1 < av.size()
    STATE_DIR = av[ai + 1]
    STATE_DIR_EXPLICIT = 1
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
  if arg == "--near-dir" && ai + 1 < av.size()
    NEAR_DIR = av[ai + 1]
    NEAR_EXPLICIT = 1
    ai += 1
  if arg == "--self-test"
    SELF_TEST = 1
    GPU = 0
    TUI = 0
    QUIET = 0
    STEPS = 200
    MAX_ROUNDS = 2
    J = 2
    J_EXPLICIT = 1
  ai += 1

if RECT_PORTFOLIO != 0 && TENSOR_EXPLICIT != 0
  << "metaflip: --rect conflicts with --tensor; use --rect-shapes to select the portfolio"
  exit(2)
if RECT_PORTFOLIO != 0 && SEED_PATH != ""
  << "metaflip: --seed is shape-specific and cannot be used with --rect"
  exit(2)
if RECT_PORTFOLIO != 0 && RECORD_OVERRIDE > 0
  << "metaflip: --record is shape-specific and cannot be used with --rect"
  exit(2)
if RECT_PORTFOLIO == 0 && RECT_MODE == 0 && (N < 2 || N > 7)
  << "metaflip: --tensor must be square 2x2 through 7x7 or a supported rectangular profile (2x2x5, 2x2x6, 2x3x4, 2x3x5, 2x4x5, 2x5x6, 3x3x4, 3x3x5, 3x4x4, 3x4x5, 3x4x6, 3x4x7, 3x5x5, 3x5x6, 3x5x7, 4x4x5, 4x4x6, 4x5x5, 4x5x6, 4x5x7, 4x5x8, 4x6x6, 4x6x7, 4x6x8, 5x6x7)"
  exit(2)
if RECT_PORTFOLIO != 0
  TENSOR_LABEL = "rect"
  if RECT_SHAPES == ""
    RECT_SHAPES = ffrpo_default_shape_spec()
if RECT_PORTFOLIO == 0 && RECT_MODE == 0
  TENSOR_LABEL = N.to_s() + "x" + N.to_s()
HOST_THREADS = System.cpu_count ## i64
if J_EXPLICIT == 0
  # Default: host cores minus six. With no GPU the reserve (plus strategy
  # slots inside J) hosts the continuous-role / pool CPU strategy layout.
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
if RECT_EPOCH_ROUNDS < 1 || RECT_EPOCH_ROUNDS > 64
  << "metaflip: --rect-epoch-rounds must be 1 through 64"
  exit(2)
if GPU_WALKERS < 32
  GPU_WALKERS = 32
if GPU_WALKERS > 65536
  GPU_WALKERS = 65536
if MIGRATE < 0
  MIGRATE = 0
if MIGRATE > J
  MIGRATE = J
if ARCHIVE_CAP < 2 || ARCHIVE_CAP > 64
  << "metaflip: --archive-size must be 2 through 64"
  exit(2)
if NEAR_CAP < 2 || NEAR_CAP > 256
  << "metaflip: --cpu-near-size must be 2 through 256"
  exit(2)
if NEAR_SIGNATURE_QUOTA < 1 || NEAR_SIGNATURE_QUOTA > NEAR_CAP
  << "metaflip: --cpu-near-signature-quota must be positive and no larger than the near bank"
  exit(2)
if SYMMETRY_CAP < 1 || SYMMETRY_CAP > 64
  << "metaflip: --cpu-symmetry-seeds must be 1 through 64"
  exit(2)
if GPU_NOVELTY_CAP < 2 || GPU_NOVELTY_CAP > 128
  << "metaflip: --gpu-novelty-size must be 2 through 128"
  exit(2)
if GPU_POLICY != "adaptive" && GPU_POLICY != "single"
  << "metaflip: --gpu-policy must be adaptive or single"
  exit(2)
if STRATEGY != "islands" && STRATEGY != "independent" && STRATEGY != "converge"
  << "metaflip: --strategy must be islands, independent, or converge"
  exit(2)
if SEED_NAIVE == 1 && SEED_PATH != ""
  << "metaflip: --naive conflicts with --seed (pick one starting scheme)"
  exit(2)

RUNTIME_ROOT = ffn_discover_runtime_root(RUNTIME_ROOT)
if RUNTIME_ROOT == ""
  << "metaflip: cannot locate packaged runtime sources; pass --runtime-root PATH or set METAFLIP_RUNTIME_ROOT"
  exit(2)

if RUN_TAG == ""
  RUN_TAG = capture("printf '%s' $$").strip() + "_" + ccall("__w_clock_ms").to_s()
if RUN_TAG.include?("/") || RUN_TAG.include?("..")
  << "metaflip: --run-tag may not contain '/' or '..'"
  exit(2)
if STATE_DIR_EXPLICIT != 0 && STATE_DIR == ""
  << "metaflip: --state-dir may not be empty"
  exit(2)
if SELF_TEST != 0 && STATE_DIR_EXPLICIT == 0
  STATE_DIR = "/tmp/metaflip_self_test_" + RUN_TAG
STATE_DIR = ffls_root(STATE_DIR)
if STATE_DIR == "" || STATE_DIR.include?("\n")
  << "metaflip: cannot resolve live state directory; set HOME, METAFLIP_HOME, or --state-dir PATH"
  exit(2)
if NEAR_DIR != ""
  if NEAR_DIR.include?("\n")
    << "metaflip: --near-dir may not contain a newline"
    exit(2)
STATE_SHAPE = ffls_shape_label(TENSOR_LABEL, 0)
if RECT_PORTFOLIO == 0 && RECT_MODE == 0
  STATE_SHAPE = ffls_shape_label(TENSOR_LABEL, N)
if STATUS_EXPLICIT == 0
  STATUS_PATH = ffls_status_path(STATE_DIR, "gf2", STATE_SHAPE, RUN_TAG)
if BEST_EXPLICIT == 0
  BEST_PATH = ffls_best_path(STATE_DIR, "gf2", STATE_SHAPE)
if NEAR_EXPLICIT == 0
  NEAR_DIR = ffls_bank_dir(STATE_DIR, "gf2", STATE_SHAPE)

state_dirs_ok = 1 ## i64
if STATUS_EXPLICIT == 0
  state_dirs_ok *= ffls_ensure_dir(ffls_run_dir(STATE_DIR, "gf2", STATE_SHAPE, RUN_TAG))
if BEST_EXPLICIT == 0 && RECT_PORTFOLIO == 0
  state_dirs_ok *= ffls_ensure_dir(ffls_checkpoint_dir(STATE_DIR, "gf2", STATE_SHAPE))
if NEAR_EXPLICIT == 0 && RECT_PORTFOLIO == 0 && RECT_MODE == 0
  state_dirs_ok *= ffls_ensure_dir(NEAR_DIR)
if state_dirs_ok == 0
  << "metaflip: could not create default live-state directories under " + STATE_DIR
  exit(2)

# Rectangular profiles share this entry point, CLI, and styled dashboard but
# not the square state layout.  Dispatch before allocating any square worker
# structures, keeping ordinary 2x2..7x7 runs on their existing runtime hot
# path; the rectangular coordinator renders the same TUI from its own loop.
if RECT_PORTFOLIO == 1
  result = ffrpo_run(RECT_SHAPES, RUNTIME_ROOT, STATE_DIR.to_s(), BEST_PATH, BEST_EXPLICIT, STATUS_PATH, STATUS_EXPLICIT, RUN_TAG, J, STEPS, MAX_ROUNDS, MAX_SECS, RECT_EPOCH_ROUNDS, DSLACK, CYCLES, GPU, GPU_WALKERS, GPU_POLICY, GPU_STEPS, GPU_EPOCH_ROUNDS, GPU_BINARY, GPU_REBUILD, QUIET, TUI, STOP_ON_RECORD, SEED_NAIVE) ## i64
  exit(result)

if RECT_MODE == 1
  result = ffrc_run(TENSOR_LABEL, RUNTIME_ROOT, SEED_PATH, BEST_PATH, STATUS_PATH, RUN_TAG, J, STEPS, MAX_ROUNDS, MAX_SECS, DSLACK, CYCLES, RECORD_OVERRIDE, GPU, GPU_WALKERS, GPU_STEPS, GPU_EPOCH_ROUNDS, GPU_BINARY, GPU_REBUILD, QUIET, TUI, STOP_ON_RECORD, SEED_NAIVE, 0) ## i64
  exit(result)

RECORD = ffp_record(N) ## i64
RECORD_KNOWN = ffp_record_known(N) ## i64
if RECORD_OVERRIDE > 0
  RECORD = RECORD_OVERRIDE
  RECORD_KNOWN = 0
# --naive still knows the published WR rank for tie/beat reporting; it only
# refuses to *load* WR schemes into banks (zero scheme inventory at start).

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
    << "metaflip: --cpu-work-moves requires four positive comma-separated budgets"
    exit(2)
if CPU_WANDER_SPEC != ""
  if ffn_parse_move_portfolio(CPU_WANDER_SPEC, cpu_wander_moves) == 0
    << "metaflip: --cpu-wander-moves requires four positive comma-separated budgets"
    exit(2)
balanced_work = cpu_work_moves[1] ## i64
balanced_wander = cpu_wander_moves[1] ## i64
near1_capacity = (NEAR_CAP + 1) / 2 ## i64
near2_capacity = NEAR_CAP / 2 ## i64

# Exact anchor and monotonic fleet best.
# --naive: schoolbook scheme inventory only. No checked-in WR *schemes*, no
# prior --best recovery, no frontier/shoulder files from the repo. The published
# WR *rank* is still known for wr_status reporting. Fleet best (this run) drives
# escape banks and near+1/near+2 admission — never a static published scheme.
anchor = i64[STATE_SIZE]
loaded = 0 - 1 ## i64
if SEED_NAIVE == 1
  loaded = ffw_init_naive_cap(anchor, N, CAPACITY, 17, DSLACK, CYCLES, balanced_work, balanced_wander)
if SEED_NAIVE == 0
  path = SEED_PATH
  if path == ""
    profile_path = ffp_seed_path(N)
    if profile_path != ""
      path = RUNTIME_ROOT + "/" + profile_path
  if path != ""
    loaded = ffw_load_scheme_cap(anchor, path, N, CAPACITY, 17, DSLACK, CYCLES, balanced_work, balanced_wander)
  if SEED_PATH != "" && loaded < 1
    << "metaflip: explicit --seed is missing, malformed, inexact, or for a different tensor"
    exit(2)
  if SEED_PATH == "" && loaded < 1
    loaded = ffw_init_naive_cap(anchor, N, CAPACITY, 17, DSLACK, CYCLES, balanced_work, balanced_wander)
if loaded < 1 || ffw_verify_best_exact(anchor, N) != 1
  << "metaflip: exact anchor initialization failed"
  exit(2)

best = ffn_clone_exact(anchor, N, CAPACITY, STATE_SIZE, 23, DSLACK, CYCLES, balanced_work, balanced_wander)
if best == nil
  << "metaflip: exact best clone failed"
  exit(2)
recovered = 0 ## i64
# Never recover a prior campaign under --naive (even default best-path files
# would re-inject published or earlier-run knowledge).
if SEED_NAIVE == 0
  durable = i64[STATE_SIZE]
  durable_text = read_file(BEST_PATH)
  durable_rank = ffw_load_scheme_cap(durable, BEST_PATH, N, CAPACITY, 31, DSLACK, CYCLES, balanced_work, balanced_wander) ## i64
  if durable_text != nil && durable_rank < 1
    << "metaflip: refusing to overwrite malformed, inexact, or wrong-tensor --best checkpoint"
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
lineage_registry_ids = []
lineage_registry_sources = []
LINEAGE_REGISTRY_CAPACITY = 256 ## i64
first_archive = ffn_clone_trusted(best, STATE_SIZE, 29)
if first_archive != nil
  archive.push(first_archive)

# External same-rank schemes from the repo (and their escape families).  Skipped
# entirely under --naive so the fleet only learns from its own constructions.
frontier_paths = []
if SEED_NAIVE == 0
  frontier_paths = ffp_frontier_seed_paths(N)
frontier_escape_admissions = []
frontier_escape_counters = i64[6]
frontier_index = 0 ## i64
while frontier_index < frontier_paths.size()
  frontier_candidate = i64[STATE_SIZE]
  frontier_path = RUNTIME_ROOT + "/" + frontier_paths[frontier_index]
  frontier_rank = ffw_load_scheme_cap(frontier_candidate, frontier_path, N, CAPACITY, 3001 + frontier_index * 17, DSLACK, CYCLES, balanced_work, balanced_wander) ## i64
  if frontier_rank == ffw_best_rank(best)
    if ffw_verify_best_exact(frontier_candidate, N) == 1
      z = ffn_archive_add(archive, frontier_candidate, ARCHIVE_CAP, 4, archive_counters)
  frontier_index += 1
archive_min_cache = ffn_archive_min_distance(archive) ## i64
# Algebraic escapes of the live best, then any file-backed shoulder inventory
# under --near-dir (near1/near2 subdirs written by prior dumps).
bank_count = ffn_build_escape_banks(best, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, near1, near2, near1_signatures, near1_uses, near1_successes, near2_signatures, near2_uses, near2_successes, symmetry, mixed, orbit_bank, polar_bank, near1_capacity, near2_capacity, NEAR_SIGNATURE_QUOTA, SYMMETRY_CAP, near_counters) ## i64
global_isotropy_counters = i64[4]
bank_count += ffn_add_global_isotropy_images(archive, mixed, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, global_isotropy_counters)
if SEED_NAIVE == 0
  # The archive already owns independently full-gated frontier states.  Their
  # 300 derived escapes are expanded in rotating minute-scale batches below;
  # doing all of them here cost roughly 89 seconds on 7x7 before round zero.
  z = ff7_add_known_7x7_shoulder(RUNTIME_ROOT, best, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, near2, near2_signatures, near2_uses, near2_successes, near2_capacity, NEAR_SIGNATURE_QUOTA, near_counters) ## i64
  z = ff7_add_known_7x7_rank247_shoulders(RUNTIME_ROOT, best, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, near1, near1_signatures, near1_uses, near1_successes, near1_capacity, NEAR_SIGNATURE_QUOTA, near_counters) ## i64
  bank_count += ffps_add_profile_near_seeds(RUNTIME_ROOT, best, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, near1, near1_signatures, near1_uses, near1_successes, near1_capacity, near2, near2_signatures, near2_uses, near2_successes, near2_capacity, NEAR_SIGNATURE_QUOTA, near_counters) ## i64
near_loaded = 0 ## i64
if NEAR_DIR != ""
  near_loaded += ffn_load_near_bank(NEAR_DIR + "/near1", "near1", near1_capacity, N, CAPACITY, STATE_SIZE, 81001, DSLACK, CYCLES, balanced_work, balanced_wander, near1, near1_signatures, near1_uses, near1_successes, near1_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters)
  near_loaded += ffn_load_near_bank(NEAR_DIR + "/near2", "near2", near2_capacity, N, CAPACITY, STATE_SIZE, 82001, DSLACK, CYCLES, balanced_work, balanced_wander, near2, near2_signatures, near2_uses, near2_successes, near2_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters)
  bank_count += near_loaded
  # Snapshot whatever the bank holds at startup (algebraic + loaded) so the
  # near-dir is never empty while the campaign is still filling.
  z = ffn_dump_near_dirs(near1, near2, NEAR_DIR, RUN_TAG) ## i64
mi = 0 ## i64
while mi < archive.size()
  z = ffme_add_copy(map_states, map_keys, map_uses, map_sources, archive[mi], ffw_best_rank(best), N, MAP_CAPACITY, 0, STATE_SIZE, 6001 + mi)
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
    z = ffme_add_copy(map_states, map_keys, map_uses, map_sources, map_pool[mi], ffw_best_rank(best), N, MAP_CAPACITY, map_source, STATE_SIZE, 6201 + map_source * 101 + mi)
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
# Provenance survives copies through exact banks via canonical basin lookup.
lineage_roles = i64[J]
lineage_modes = i64[J]
lineage_origin_ids = i64[J]
lineage_start_ranks = i64[J]
lineage_start_bits = i64[J]
lineage_debts = i64[J]
lineage_paid = i64[J]
lineage_rewards = i64[11]
lineage_returns = 0 ## i64
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
  origin_source = ffl_registry_find(selected, lineage_registry_ids, lineage_registry_sources) ## i64
  if origin_source < 0
    origin_source = ffl_find_source(selected, map_states, map_sources)
  lineage_roles[i] = ffl_source_role(origin_source)
  lineage_modes[i] = ffl_source_pool_mode(origin_source)
  lineage_origin_ids[i] = ffbi_best_id(selected)
  lineage_start_ranks[i] = ffw_best_rank(selected)
  lineage_start_bits[i] = ffw_best_bits(selected)
  lineage_debts[i] = lineage_start_ranks[i] - ffw_best_rank(best)
  lineage_paid[i] = 0
  seed_debt = active_seed_ranks[i] - ffw_best_rank(best) ## i64
  if seed_debt > 0
    z = ffrd_launch(seed_debt, debt_launches)
  source_name = ffp_door_name(doors[i])
  source_name = source_name + "/seed" + (ffn_current_basin_id(selected) % 100000).to_s() + "/" + ffn_global_isotropy_tag(selected)
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
# Campaign-owned one-word core-size out-param; never reallocate in the loop.
core_fringe_out_scratch = i64[1]
if STRATEGY == "islands" && J > 1
  core_fringe_index = J - 1
  # The 12-slot profile reserves slot 11 as its anchor/marathon control.
  # Hardware-derived J may add workers beyond that pattern; keep the control
  # on slot 11 so extra breadth does not accidentally turn it into a short
  # frontier lane.
  if J >= 12
    core_fringe_index = 11
  if ffn_core_fringe_state_into(states[core_fringe_index], best, archive, near1, near2, mixed, N, CAPACITY, 41003, DSLACK, CYCLES, cpu_work_moves[zones[core_fringe_index]], cpu_wander_moves[zones[core_fringe_index]], core_fringe_out_scratch) == 1
    core_fringe_slots = core_fringe_out_scratch[0]
    active_near_seeds[core_fringe_index] = nil
    active_seed_ranks[core_fringe_index] = ffw_best_rank(states[core_fringe_index])
    active_seed_start_moves[core_fringe_index] = 0
    active_seed_finished[core_fringe_index] = 1
    sources[core_fringe_index] = "core-fringe/frozen-" + core_fringe_slots.to_s()
    lineage_roles[core_fringe_index] = 0 - 1
    lineage_modes[core_fringe_index] = 0 - 1
    lineage_origin_ids[core_fringe_index] = ffbi_best_id(states[core_fringe_index])
    lineage_start_ranks[core_fringe_index] = ffw_best_rank(states[core_fringe_index])
    lineage_start_bits[core_fringe_index] = ffw_best_bits(states[core_fringe_index])
    lineage_paid[core_fringe_index] = 0

# The constrained core/fringe move is substantially more expensive than an
# ordinary flip.  Give the control lane an initially time-balanced quota, then
# adapt it from measured per-thread wall time so it never becomes a barrier for
# the productive islands.
core_round_steps = STEPS ## i64
if core_fringe_index >= 0
  core_round_steps = STEPS / 5
  if core_round_steps < 1
    core_round_steps = 1

# Keep experiments bounded: one island races CPU controls and a different one
# measures accepted-state recurrence.  The leader and core/fringe control are
# never displaced, and small/self-test fleets keep the ordinary worker path.
racer_index = 0 - 1 ## i64
cycle_watch_index = 0 - 1 ## i64
if STRATEGY == "islands" && J >= 4
  candidate_index = J - 1 ## i64
  if candidate_index == core_fringe_index
    candidate_index -= 1
  racer_index = candidate_index
  candidate_index -= 1
  while candidate_index >= 0 && candidate_index == core_fringe_index
    candidate_index -= 1
  if candidate_index > 0
    cycle_watch_index = candidate_index

racer_controls = i64[7]
racer_pulls = i64[9]
racer_exposure = i64[9]
racer_novel = i64[9]
racer_returns = i64[9]
racer_drops = i64[9]
racer_density = i64[9]
racer_seen_ids = i64[64]
racer_seen_count = 0 ## i64
racer_epoch = 0 ## i64
racer_arm = 0 ## i64
racer_lease_start_moves = 0 ## i64
racer_lease_start_rank = 0 ## i64
racer_lease_start_bits = 0 ## i64
racer_lease_origin_id = 0 ## i64
racer_lease_novel = 0 ## i64
if racer_index >= 0
  racer_arm = ffcr_select_arm(racer_epoch, racer_pulls, racer_exposure, racer_novel, racer_returns, racer_drops, racer_density)
  z = ffcr_apply_arm(states[racer_index], racer_arm, cpu_work_moves[zones[racer_index]], cpu_wander_moves[zones[racer_index]], racer_controls) ## i64
  racer_lease_start_moves = ffw_moves(states[racer_index])
  racer_lease_start_rank = ffw_best_rank(states[racer_index])
  racer_lease_start_bits = ffw_best_bits(states[racer_index])
  racer_lease_origin_id = ffbi_current_id(states[racer_index])
  racer_seen_ids[0] = racer_lease_origin_id
  racer_seen_count = 1
  sources[racer_index] = sources[racer_index] + "/race-a" + racer_arm.to_s()

cycle_recent_capacity = 512 ## i64
cycle_recent = i64[cycle_recent_capacity]
cycle_stats = i64[9]
if cycle_watch_index >= 0
  sources[cycle_watch_index] = sources[cycle_watch_index] + "/cycle-watch"

# Cohort exposure counters, indexed door*4+zone.
cohort_moves = i64[28]
cohort_drops = i64[28]
cohort_ties = i64[28]
cohort_near = i64[28]

# Two exact rectangular component subfleets are part of the default 7x7 mixed
# campaign.  They own independent frontier states, archives, checkpoints,
# rewards, failures, and retry clocks.  Their Metal allocations are carved out
# of role 10 below; they never add lanes on top of GPU_WALKERS.
rect_enabled = 0 ## i64
# Rectangular 7x7 children load published 334/344/444 leaves and recompose
# through them — all external knowledge.  --naive keeps a pure square fleet.
if N == 7 && GPU == 1 && GPU_POLICY == "adaptive" && SEED_NAIVE == 0
  rect_enabled = 1
rect_states = []
rect_states.push(nil)
rect_states.push(nil)
rect_capacities = i64[2]
rect_ready = i64[2]
rect_sched_ready = i64[2]
rect_active = i64[2]
rect_lanes = i64[2]
rect_candidates = i64[2]
rect_rank_drops = i64[2]
rect_density = i64[2]
rect_rewards = i64[2]
rect_epochs = i64[2]
rect_exposure = i64[2]
rect_wall_ms = i64[2]
rect_elapsed_ms = i64[2]
rect_failures = i64[2]
rect_retry_round = i64[2]
rect_launch_number = i64[2]
rect_archive_counts = i64[2]
rect_composition_dirty = 0 ## i64
rect_composition_retry_round = 0 ## i64
rect_composition_failures = 0 ## i64
rect_composition_attempts = 0 ## i64
rect_last_improved = 0 - 1 ## i64
rect_archive_334 = []
rect_archive_344 = []
rect_binaries = ["/tmp/metaflip_rect_gpu_334", "/tmp/metaflip_rect_gpu_344"]
rect_seed_paths = [RUNTIME_ROOT + "/seeds/gf2/matmul_3x3x4_rank29_gf2.txt", RUNTIME_ROOT + "/seeds/gf2/matmul_3x4x4_rank38_gf2.txt"]
rect_checkpoint_paths = [ffls_best_path(STATE_DIR, "gf2", "3x3x4"), ffls_best_path(STATE_DIR, "gf2", "3x4x4")]
rect_candidate_states = []
rect_reject_scratch = []
if rect_enabled != 0
  rect_dirs_ok = ffls_ensure_dir(ffls_checkpoint_dir(STATE_DIR, "gf2", "3x3x4")) ## i64
  rect_dirs_ok *= ffls_ensure_dir(ffls_checkpoint_dir(STATE_DIR, "gf2", "3x4x4"))
  if rect_dirs_ok == 0
    << "metaflip: could not create 7x7 component checkpoint directories under " + STATE_DIR
    exit(2)
rect_component = 0 ## i64
while rect_component < 2
  rn = ffn_rect_n(rect_component) ## i64
  rm = ffn_rect_m(rect_component) ## i64
  rp = ffn_rect_p(rect_component) ## i64
  rcap = ffr_default_capacity(rn, rm, rp) ## i64
  rect_capacities[rect_component] = rcap
  rect_candidate_states.push(i64[ffr_state_size(rcap)])
  rect_reject_scratch.push(i64[ffr_state_size(rcap)])
  if rect_enabled != 0
    # rect_enabled is already gated off under --naive; this path only loads
    # published rectangular leaves and prior campaign checkpoints.
    seed_state = i64[ffr_state_size(rcap)]
    seed_rank = ffr_load_scheme_cap(seed_state, rect_seed_paths[rect_component], rn, rm, rp, rcap, 61001 + rect_component * 101, DSLACK, CYCLES, balanced_work, balanced_wander) ## i64
    selected_rect = nil
    if seed_rank > 0
      selected_rect = seed_state
    durable_rect = i64[ffr_state_size(rcap)]
    durable_rect_text = read_file(rect_checkpoint_paths[rect_component])
    durable_rank = ffr_load_scheme_cap(durable_rect, rect_checkpoint_paths[rect_component], rn, rm, rp, rcap, 62003 + rect_component * 103, DSLACK, CYCLES, balanced_work, balanced_wander) ## i64
    rect_checkpoint_writable = 1 ## i64
    if durable_rect_text != nil && durable_rank < 1
      rect_failures[rect_component] = rect_failures[rect_component] + 1
      # Atomically quarantine the malformed bytes, then keep using the stable
      # canonical checkpoint name. The exact bundled seed is written back below, so
      # improvements made by this and later runs remain restart-durable.
      corrupt_preserved = ff7_quarantine_corrupt_checkpoint(rect_checkpoint_paths[rect_component], RUN_TAG) ## i64
      if corrupt_preserved == 0
        # Never overwrite bytes we failed to preserve.  This optional child is
        # disabled; its sibling and ordinary role-10 pool remain available.
        rect_checkpoint_writable = 0
    if durable_rank > 0
      if selected_rect == nil
        selected_rect = durable_rect
      if selected_rect != nil
        if ffn_better(durable_rank, ffr_best_bits(durable_rect), ffr_best_rank(selected_rect), ffr_best_bits(selected_rect)) == 1
          selected_rect = durable_rect
    if selected_rect != nil && rect_checkpoint_writable != 0
      rect_states[rect_component] = selected_rect
      rect_archive_counts[rect_component] = 1
      if rect_component == 0
        rect_archive_334.push(selected_rect)
      if rect_component == 1
        rect_archive_344.push(selected_rect)
      seeded_checkpoint = ffn_dump_rect_atomic(selected_rect, rect_checkpoint_paths[rect_component], RUN_TAG, rect_component) ## i64
      if seeded_checkpoint < 1
        rect_states[rect_component] = nil
        rect_archive_counts[rect_component] = 0
        rect_failures[rect_component] = rect_failures[rect_component] + 1
        if rect_component == 0 && rect_archive_334.size() > 0
          discarded_rect = rect_archive_334.pop
        if rect_component == 1 && rect_archive_344.size() > 0
          discarded_rect = rect_archive_344.pop
  rect_component += 1
if rect_states[0] != nil && rect_states[1] != nil
  # Compose once during the first coordinator round even if no child improves;
  # this recovers a stronger durable component checkpoint after restart.
  rect_composition_dirty = 1
rect_composed_candidate = i64[STATE_SIZE]

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
# Physical execution slots 10..12 are the rotating children of logical role
# 10; slots 13..14 are the 334/344 component Metal subfleets.  Keeping every
# launch-local cell physical prevents concurrent children from sharing paths,
# elapsed time, seed debt, or reward attribution.
gpu_launch_lanes = i64[15]
gpu_launch_debt = i64[15]
gpu_elapsed_ms = i64[15]
gpu_launch_generation = i64[15]
# Physical square slots keep the launch ordinal that produced their current
# output.  Pool slots rotate logical modes, so role counters alone are not a
# replay nonce after an asynchronous refill.
gpu_launch_nonces = i64[13]
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
gpu_candidate_states = []
gpu_persistent_processes = []
gpu_persistent_active = i64[15]
gpu_persistent_generations = i64[15]
gpu_persistent_lanes = i64[15]
gpu_role = 0 ## i64
while gpu_role < 15
  gpu_threads.push(nil)
  gpu_persistent_processes.push(nil)
  if gpu_role < 13
    gpu_candidate_states.push(i64[STATE_SIZE])
    gpu_launch_nonces[gpu_role] = 0 - 1
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
  gpu_differential_ready = 0 ## i64
  gpu_span_ready = 0 ## i64
  gpu_shear_ready = 0 ## i64
  gpu_frozen_sat_ready = 0 ## i64
  gpu_global_shear_ready = 0 ## i64
  gpu_pool_ready = 0 ## i64
  gpu_degraded = 0

  if GPU_BINARY == ""
    GPU_BINARY = "/tmp/metaflip_gpu_cal2zone_" + N.to_s()
  needs_build = GPU_REBUILD ## i64
  if needs_build == 0 && (ffn_binary_fresh(GPU_BINARY, ffb_source_path(RUNTIME_ROOT, N)) == 0 || ffb_gpu_artifact_ready(RUNTIME_ROOT, N, GPU_BINARY) == 0)
    needs_build = 1
  if needs_build == 1
    if QUIET == 0
      << "metaflip: compiling Tungsten GPU worker for " + N.to_s() + "x" + N.to_s()
      flush()
    gpu_generic_ready = ffb_build(RUNTIME_ROOT, N, GPU_BINARY)
  if needs_build == 0
    gpu_generic_ready = 1

  C3_BINARY = "/tmp/metaflip_gpu_c3_" + N.to_s()
  if gpu_eligible[2] != 0
    c3_needs_build = GPU_REBUILD ## i64
    if c3_needs_build == 0 && (ffn_binary_fresh(C3_BINARY, ffc3_source_path(RUNTIME_ROOT, N)) == 0 || ffc3_gpu_artifact_ready(RUNTIME_ROOT, N, C3_BINARY) == 0)
      c3_needs_build = 1
    if c3_needs_build == 1
      gpu_c3_ready = ffc3_build(RUNTIME_ROOT, N, C3_BINARY)
    if c3_needs_build == 0
      gpu_c3_ready = 1
    if gpu_c3_ready == 0
      gpu_eligible[2] = 0
      gpu_disabled[2] = 1
      gpu_failures[2] = gpu_failures[2] + 1
      gpu_retry_round[2] = 1
      gpu_degraded = 1

  SIMD_BINARY = "/tmp/metaflip_gpu_simd_" + N.to_s()
  if gpu_eligible[9] != 0
    simd_needs_build = GPU_REBUILD ## i64
    if simd_needs_build == 0 && (ffn_binary_fresh(SIMD_BINARY, ffsimd_source_path(RUNTIME_ROOT, N)) == 0 || ffsimd_gpu_artifact_ready(RUNTIME_ROOT, N, SIMD_BINARY) == 0)
      simd_needs_build = 1
    if simd_needs_build == 1
      gpu_simd_ready = ffsimd_build(RUNTIME_ROOT, N, SIMD_BINARY)
    if simd_needs_build == 0
      gpu_simd_ready = 1
    if gpu_simd_ready == 0
      gpu_eligible[9] = 0
      gpu_disabled[9] = 1
      gpu_failures[9] = gpu_failures[9] + 1
      gpu_retry_round[9] = 1
      gpu_degraded = 1

  MITM_BINARY = "/tmp/metaflip_gpu_mitm"
  if gpu_eligible[10] != 0
    mitm_needs_build = GPU_REBUILD ## i64
    mitm_worker = RUNTIME_ROOT + "/kernels/workers/mitm.w"
    mitm_library = RUNTIME_ROOT + "/kernels/mitm.w"
    worker_bundle = RUNTIME_ROOT + "/kernels/bundles/workers.w"
    if mitm_needs_build == 0 && (ffn_binary_fresh3(MITM_BINARY, mitm_worker, mitm_library, worker_bundle) == 0 || ffm_gpu_artifact_ready(RUNTIME_ROOT, MITM_BINARY) == 0)
      mitm_needs_build = 1
    if mitm_needs_build == 1
      gpu_mitm_ready = ffm_build(RUNTIME_ROOT, MITM_BINARY)
    if mitm_needs_build == 0
      gpu_mitm_ready = 1

    CONSTRAINT_BINARY = "/tmp/metaflip_gpu_constraint_pool"
    constraint_worker = RUNTIME_ROOT + "/kernels/workers/constraint.w"
    constraint_library = RUNTIME_ROOT + "/kernels/constraint.w"
    constraint_needs_build = GPU_REBUILD ## i64
    if constraint_needs_build == 0 && (ffn_binary_fresh3(CONSTRAINT_BINARY, constraint_worker, constraint_library, worker_bundle) == 0 || ffpc_gpu_artifact_ready(RUNTIME_ROOT, CONSTRAINT_BINARY) == 0)
      constraint_needs_build = 1
    if constraint_needs_build == 1
      gpu_constraint_ready = ffpc_build(RUNTIME_ROOT, CONSTRAINT_BINARY)
    if constraint_needs_build == 0
      gpu_constraint_ready = 1

    KXOR_BINARY = "/tmp/metaflip_gpu_kxor_pool"
    kxor_worker = RUNTIME_ROOT + "/kernels/workers/kxor.w"
    kxor_library = RUNTIME_ROOT + "/kernels/kxor.w"
    kxor_needs_build = GPU_REBUILD ## i64
    if kxor_needs_build == 0 && (ffn_binary_fresh4(KXOR_BINARY, kxor_worker, kxor_library, mitm_library, worker_bundle) == 0 || ffx_gpu_artifact_ready(RUNTIME_ROOT, KXOR_BINARY) == 0)
      kxor_needs_build = 1
    if kxor_needs_build == 1
      gpu_kxor_ready = ffx_build(RUNTIME_ROOT, KXOR_BINARY)
    if kxor_needs_build == 0
      gpu_kxor_ready = 1

    SPAN_BINARY = "/tmp/metaflip_gpu_span_refactor"
    span_worker = RUNTIME_ROOT + "/kernels/workers/span_refactor.w"
    span_library = RUNTIME_ROOT + "/kernels/span_refactor.w"
    span_core = RUNTIME_ROOT + "/strategies/span_refactor.w"
    span_needs_build = GPU_REBUILD ## i64
    if span_needs_build == 0 && (ffn_binary_fresh4(SPAN_BINARY, span_worker, span_library, span_core, worker_bundle) == 0 || ffsrp_gpu_artifact_ready(RUNTIME_ROOT, SPAN_BINARY) == 0)
      span_needs_build = 1
    if span_needs_build == 1
      gpu_span_ready = ffsrp_build(RUNTIME_ROOT, SPAN_BINARY)
    if span_needs_build == 0
      gpu_span_ready = 1

    SHEAR_BINARY = "/tmp/metaflip_gpu_low_rank_shear"
    shear_worker = RUNTIME_ROOT + "/kernels/workers/low_rank_shear.w"
    shear_library = RUNTIME_ROOT + "/kernels/low_rank_shear.w"
    shear_search = RUNTIME_ROOT + "/strategies/low_rank_shear.w"
    shear_core = RUNTIME_ROOT + "/strategies/shear.w"
    if N >= 5
      shear_needs_build = GPU_REBUILD ## i64
      if shear_needs_build == 0 && (ffn_binary_fresh5(SHEAR_BINARY, shear_worker, shear_library, shear_search, shear_core, worker_bundle) == 0 || fflrsp_gpu_artifact_ready(RUNTIME_ROOT, SHEAR_BINARY) == 0)
        shear_needs_build = 1
      if shear_needs_build == 1
        gpu_shear_ready = fflrsp_build(RUNTIME_ROOT, SHEAR_BINARY)
      if shear_needs_build == 0
        gpu_shear_ready = 1

    DIFFERENTIAL_BINARY = "/tmp/metaflip_cpu_parent_diff"
    differential_worker = RUNTIME_ROOT + "/kernels/workers/differential.w"
    differential_lib = RUNTIME_ROOT + "/kernels/differential.w"
    differential_kxor = RUNTIME_ROOT + "/kernels/kxor.w"
    differential_mitm = RUNTIME_ROOT + "/kernels/mitm.w"
    differential_nullspace = RUNTIME_ROOT + "/strategies/archive_nullspace.w"
    differential_needs_build = GPU_REBUILD ## i64
    if differential_needs_build == 0 && ffn_binary_fresh5(DIFFERENTIAL_BINARY, differential_worker, differential_lib, differential_kxor, differential_mitm, differential_nullspace) == 0
      differential_needs_build = 1
    if differential_needs_build == 1
      gpu_differential_ready = ffdb_build(RUNTIME_ROOT, DIFFERENTIAL_BINARY)
    if differential_needs_build == 0
      gpu_differential_ready = 1

    FROZEN_SAT_BINARY = "/tmp/metaflip_cpu_frozen_fringe_sat"
    frozen_sat_worker = RUNTIME_ROOT + "/kernels/workers/frozen_fringe_sat.w"
    frozen_sat_library = RUNTIME_ROOT + "/kernels/frozen_fringe_sat.w"
    frozen_sat_core = RUNTIME_ROOT + "/strategies/frozen_fringe_sat.w"
    frozen_sat_encoder = RUNTIME_ROOT + "/strategies/sat_repair.w"
    frozen_sat_span = RUNTIME_ROOT + "/strategies/span_refactor.w"
    frozen_sat_worker_core = RUNTIME_ROOT + "/scheme.w"
    if N == 4 && system("command -v cryptominisat5 >/dev/null 2>&1")
      frozen_sat_needs_build = GPU_REBUILD ## i64
      if frozen_sat_needs_build == 0 && ffn_binary_fresh6(FROZEN_SAT_BINARY, frozen_sat_worker, frozen_sat_library, frozen_sat_core, frozen_sat_encoder, frozen_sat_span, frozen_sat_worker_core) == 0
        frozen_sat_needs_build = 1
      if frozen_sat_needs_build == 1
        gpu_frozen_sat_ready = fffsb_build(RUNTIME_ROOT, FROZEN_SAT_BINARY)
      if frozen_sat_needs_build == 0
        gpu_frozen_sat_ready = 1

    GLOBAL_SHEAR_BINARY = "/tmp/metaflip_cpu_global_kernel_shear"
    global_shear_worker = RUNTIME_ROOT + "/kernels/workers/global_kernel_shear.w"
    global_shear_library = RUNTIME_ROOT + "/kernels/global_kernel_shear.w"
    global_shear_core = RUNTIME_ROOT + "/strategies/kernel_shear.w"
    global_shear_tunnel = RUNTIME_ROOT + "/strategies/tunnel.w"
    global_shear_span = RUNTIME_ROOT + "/strategies/span_refactor.w"
    global_shear_worker_core = RUNTIME_ROOT + "/scheme.w"
    if N == 5
      global_shear_needs_build = GPU_REBUILD ## i64
      if global_shear_needs_build == 0 && ffn_binary_fresh6(GLOBAL_SHEAR_BINARY, global_shear_worker, global_shear_library, global_shear_core, global_shear_tunnel, global_shear_span, global_shear_worker_core) == 0
        global_shear_needs_build = 1
      if global_shear_needs_build == 1
        gpu_global_shear_ready = ffgksb_build(RUNTIME_ROOT, GLOBAL_SHEAR_BINARY)
      if global_shear_needs_build == 0
        gpu_global_shear_ready = 1

    if rect_enabled != 0
      rect_component = 0
      while rect_component < 2
        if rect_states[rect_component] != nil
          rect_n = ffn_rect_n(rect_component) ## i64
          rect_m = ffn_rect_m(rect_component) ## i64
          rect_p = ffn_rect_p(rect_component) ## i64
          rect_source = ffrgb_source_path(RUNTIME_ROOT, rect_n, rect_m, rect_p)
          rect_glue = RUNTIME_ROOT + "/kernels/bundles/rect.w"
          rect_needs_build = GPU_REBUILD ## i64
          if rect_needs_build == 0 && (ffn_binary_fresh2(rect_binaries[rect_component], rect_source, rect_glue) == 0 || ffrgb_gpu_artifact_ready(RUNTIME_ROOT, rect_n, rect_m, rect_p, rect_binaries[rect_component]) == 0)
            rect_needs_build = 1
          if rect_needs_build == 1
            rect_ready[rect_component] = ffrgb_build(RUNTIME_ROOT, rect_n, rect_m, rect_p, rect_binaries[rect_component])
          if rect_needs_build == 0
            rect_ready[rect_component] = 1
          if rect_ready[rect_component] == 0
            rect_failures[rect_component] = rect_failures[rect_component] + 1
            rect_retry_round[rect_component] = 1
        rect_component += 1

    parent_pair_ready = ffn_has_parent_pair(map_states, archive, 12) ## i64
    gpu_pool_ready = ffn_fill_pool_readiness(pool_mode_ready, gpu_generic_ready, gpu_mitm_ready, gpu_constraint_ready, gpu_kxor_ready, gpu_differential_ready, gpu_span_ready, gpu_shear_ready, gpu_frozen_sat_ready, gpu_global_shear_ready, parent_pair_ready, orbit_bank, polar_bank)
    rect_ready_count = rect_ready[0] + rect_ready[1] ## i64
    if gpu_pool_ready == 0 && rect_ready_count == 0
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
  if gpu_generic_ready == 1 || gpu_c3_ready == 1 || gpu_simd_ready == 1 || gpu_pool_ready > 0 || rect_ready[0] != 0 || rect_ready[1] != 0
    gpu_ready = 1

  pool_count = 0 ## i64
  rect_ready_count = ff7_fill_rect_sched_ready(0, rect_ready, rect_retry_round, rect_sched_ready) ## i64
  if gpu_eligible[10] != 0
    pool_count = ffkp_select_group_modes_ready(pool_selection_epoch, N, ffw_best_rank(best), 0, GPU_WALKERS, pool_mode_ready, pool_last_modes, pool_pulls, pool_rewards, pool_modes)
  pool_full_budget = ffkp_lane_budget(GPU_WALKERS) ## i64
  rect_reserved = ff7_rect_pool_allocation(pool_full_budget, pool_selection_epoch, rect_sched_ready, rect_exposure, rect_rewards, rect_lanes) ## i64
  pool_remainder = pool_full_budget - rect_reserved ## i64
  pool_generic_budget = ff7_allocate_pool_remainder_for_tensor(N, GPU_WALKERS, pool_remainder, pool_modes, pool_count, pool_slot_lanes) ## i64
  pool_budget = pool_generic_budget + rect_reserved ## i64
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
          gpu_launch_nonces[gpu_role] = gpu_launch_number[gpu_role]
          engine_kind = ffg_engine_kind(gpu_role) ## i64
          if engine_kind == 0
            gpu_threads[gpu_role] = ffn_gpu_launch(RUNTIME_ROOT, GPU_BINARY, RUN_TAG, N, gpu_role, gpu_lanes[gpu_role], GPU_STEPS, GPU_EPOCH_ROUNDS, gpu_seed, gpu_elapsed_ms, gpu_persistent_processes, gpu_persistent_active, gpu_persistent_generations, gpu_persistent_lanes)
          if engine_kind == 1
            gpu_threads[gpu_role] = ffn_gpu_launch_c3(RUNTIME_ROOT, C3_BINARY, RUN_TAG, N, gpu_lanes[gpu_role], gpu_seed, gpu_elapsed_ms)
          if engine_kind == 2
            gpu_threads[gpu_role] = ffn_gpu_launch_simd(RUNTIME_ROOT, SIMD_BINARY, RUN_TAG, N, gpu_lanes[gpu_role], gpu_seed, gpu_elapsed_ms)
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

    # The aggregate pool role owns three rotating square workers plus the two
    # fixed-leverage rectangular component workers.  Every child has a
    # distinct seed/output/log namespace and launch-local accounting.
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
        gpu_launch_nonces[gpu_slot] = pool_launch_number
        gpu_seed = ffn_pool_seed(pool_mode, pool_launch_number, best, map_states, map_uses, c3_base, orbit_bank, polar_bank, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander)
        gpu_companion = nil
        if pool_mode == 12 && gpu_seed != nil
          gpu_companion = ffn_parent_companion(gpu_seed, map_states, archive, 12)
          if gpu_companion == nil
            gpu_seed = ffn_parent_pair_primary(map_states, archive, 12)
            if gpu_seed != nil
              gpu_companion = ffn_parent_companion(gpu_seed, map_states, archive, 12)
        if gpu_seed != nil
          gpu_seed_rank = ffw_best_rank(gpu_seed) ## i64
          if pool_launched_count == 0 || gpu_seed_rank < gpu_seed_ranks[10]
            gpu_seed_ranks[10] = gpu_seed_rank
          gpu_launch_debt[gpu_slot] = gpu_seed_rank - ffw_best_rank(best)
          gpu_launch_lanes[gpu_slot] = pool_lanes
          gpu_elapsed_ms[gpu_slot] = 0
          gpu_launch_generation[gpu_slot] = fleet_generation
          gpu_threads[gpu_slot] = ffn_gpu_launch_pool(RUNTIME_ROOT, GPU_BINARY, MITM_BINARY, CONSTRAINT_BINARY, KXOR_BINARY, DIFFERENTIAL_BINARY, SPAN_BINARY, SHEAR_BINARY, FROZEN_SAT_BINARY, GLOBAL_SHEAR_BINARY, RUN_TAG, N, gpu_slot, pool_mode, pool_lanes, GPU_STEPS, GPU_EPOCH_ROUNDS, pool_launch_number, gpu_seed, gpu_companion, gpu_elapsed_ms)
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
    rect_launched_lanes = 0 ## i64
    rect_launched_count = 0 ## i64
    rect_component = 0
    while rect_component < 2
      gpu_slot = 13 + rect_component ## i64
      component_lanes = rect_lanes[rect_component] ## i64
      if component_lanes > 0 && rect_sched_ready[rect_component] != 0 && rect_states[rect_component] != nil
        gpu_launch_lanes[gpu_slot] = component_lanes
        gpu_launch_debt[gpu_slot] = 0
        rect_elapsed_ms[rect_component] = 0
        gpu_threads[gpu_slot] = ffn_gpu_launch_rect(RUNTIME_ROOT, rect_binaries[rect_component], RUN_TAG, rect_component, component_lanes, GPU_STEPS, GPU_EPOCH_ROUNDS, rect_states[rect_component], rect_elapsed_ms, gpu_persistent_processes, gpu_persistent_active, gpu_persistent_generations, gpu_persistent_lanes)
        if gpu_threads[gpu_slot] == nil
          rect_failures[rect_component] = rect_failures[rect_component] + 1
          rect_retry_round[rect_component] = 1
          rect_active[rect_component] = 0
        else
          rect_active[rect_component] = 1
          rect_launch_number[rect_component] = rect_launch_number[rect_component] + 1
          rect_launched_lanes += component_lanes
          rect_launched_count += 1
      rect_component += 1
    gpu_lanes[10] = pool_launched_lanes + rect_launched_lanes
    if gpu_eligible[10] != 0 && pool_budget > 0 && pool_launched_count + rect_launched_count == 0
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
last_near_dump_ms = 0 - 1 ## i64
frontier_escape_last_ms = start_ms ## i64
frontier_escape_sources = []
frontier_escape_source_count = ffn_snapshot_archive_into(frontier_escape_sources, archive, ARCHIVE_CAP, STATE_SIZE, 28801) ## i64
frontier_escape_completed_batches = 0 ## i64
frontier_escape_lazy_admissions = 0 ## i64
frontier_escape_schedule = i64[3]
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
gpu_internal_rejects = 0 ## i64
rect_internal_rejects = 0 ## i64
rect_reject_status = i64[8]
cycleouts = 0 ## i64
basin_rotations = 0 ## i64
running = 1 ## i64

# CPU islands are persistent.  The old coordinator created and joined J OS
# threads every round; Tungsten's campaign-lifetime allocator consequently
# retained each thread closure/capture snapshot and every transient thread
# list.  Private start channels plus one bounded completion channel keep both
# the OS-thread count and coordinator allocation footprint constant.
cpu_round_steps = i64[J]
cpu_core_slots = i64[1]
cpu_start_channels = []
cpu_threads = []
cpu_done_channel = Channel.new(J)
i = 0
while i < J
  cpu_mode = 0 ## i64
  if i == core_fringe_index
    cpu_mode = 1
  if i == racer_index
    cpu_mode = 2
  if i == cycle_watch_index
    cpu_mode = 3
  cpu_round_steps[i] = STEPS
  start_channel = Channel.new(1)
  cpu_start_channels.push(start_channel)
  cpu_threads.push(ffcp_spawn(states, i, cpu_mode, cpu_round_steps, cpu_core_slots, racer_controls, cycle_recent, cycle_recent_capacity, cycle_stats, cpu_elapsed_ms, start_channel, cpu_done_channel))
  i += 1

# The strict-drop helper arrays are also campaign-owned.  Most rounds leave
# them empty, so allocating fresh arrays in the loop was pure retained churn.
demoted_frontiers = []
preserved_shoulders = []
live_candidate_scratch = i64[STATE_SIZE]
global_isotropy_scratch = i64[STATE_SIZE]
global_isotropy_stats = i64[4]
live_us_scratch = i64[CAPACITY]
live_vs_scratch = i64[CAPACITY]
live_ws_scratch = i64[CAPACITY]
near_signature_values = i64[CAPACITY]
near_signature_counts = i64[CAPACITY]
near_axis_signatures = i64[3]

# Whole-frontier partial-automorphism tunnels are unusually cheap at 7x7
# (roughly 39ms mean with this retained workspace) and can replace all 247
# terms at once.  Keep them out of the hot worker/GPU loops: the coordinator
# rotates one elementary generator start per minute, independently n^6-gates
# the endpoint inside the finder, then offers only a genuine quotient-novel
# state to the ordinary archive/MAP admission policies.
partial_auto_workspace_rank = 0 ## i64
partial_auto_workspace = nil
if N == 7
  partial_auto_workspace_rank = ffw_best_rank(best)
  partial_auto_workspace = FFPANWorkspace.new(partial_auto_workspace_rank, N, CAPACITY)
partial_auto_us = i64[CAPACITY]
partial_auto_vs = i64[CAPACITY]
partial_auto_ws = i64[CAPACITY]
partial_auto_out_u = i64[CAPACITY]
partial_auto_out_v = i64[CAPACITY]
partial_auto_out_w = i64[CAPACITY]
partial_auto_state = i64[STATE_SIZE]
partial_auto_meta = i64[18]
partial_auto_last_ms = 0 - 1 ## i64
partial_auto_nonce = 0 ## i64
partial_auto_attempts = 0 ## i64
partial_auto_hits = 0 ## i64
partial_auto_admissions = 0 ## i64

if QUIET == 0 && TUI == 0
  seed_note = "seed=record"
  if SEED_NAIVE == 1
    seed_note = "seed=naive"
  if SEED_PATH != ""
    seed_note = "seed=file"
  wr_note = ffn_wr_status(ffw_best_rank(best), RECORD, RECORD_KNOWN)
  near_note = ""
  if NEAR_DIR != ""
    near_note = " near_dir=" + NEAR_DIR + " near_loaded=" + near_loaded.to_s() + " near1=" + near1.size().to_s() + " near2=" + near2.size().to_s()
  << "metaflip native: tensor=" + N.to_s() + "x" + N.to_s() + " walkers=" + J.to_s() + " strategy=" + STRATEGY + " gpu=" + GPU.to_s() + " policy=" + GPU_POLICY + " banks=" + mixed.size().to_s() + " " + seed_note + " best_rank=" + ffw_best_rank(best).to_s() + " WR=" + RECORD.to_s() + " wr_status=" + wr_note + near_note
  flush()

while running == 1
  i = 0
  while i < J
    cpu_elapsed_ms[i] = 0
    cpu_round_steps[i] = STEPS
    if i == core_fringe_index
      cpu_round_steps[i] = core_round_steps
    cpu_core_slots[0] = core_fringe_slots
    cpu_start_channels[i].send(1)
    i += 1
  i = 0
  while i < J
    completed_slot = cpu_done_channel.recv() ## i64
    if completed_slot < 0
      completed_slot = 0
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
  demoted_frontiers.clear
  preserved_shoulders.clear

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
          lineage_roles[rw] = 0 - 1
          lineage_modes[rw] = 0 - 1
          lineage_origin_ids[rw] = ffbi_best_id(states[rw])
          lineage_start_ranks[rw] = ffw_best_rank(states[rw])
          lineage_start_bits[rw] = ffw_best_bits(states[rw])
          lineage_debts[rw] = 0
          lineage_paid[rw] = 0
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
          lineage_registry_ids.clear
          lineage_registry_sources.clear
          cursor = i64[7]

          naive_archive = ffn_clone_trusted(best, STATE_SIZE, 50029 + round * 131)
          if naive_archive != nil
            archive.push(naive_archive)
          z = ffn_build_escape_banks(best, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, near1, near2, near1_signatures, near1_uses, near1_successes, near2_signatures, near2_uses, near2_successes, symmetry, mixed, orbit_bank, polar_bank, near1_capacity, near2_capacity, NEAR_SIGNATURE_QUOTA, SYMMETRY_CAP, near_counters)
          frontier_escape_admissions.clear
          frontier_escape_last_ms = now_ms
          frontier_escape_source_count = ffn_snapshot_archive_into(frontier_escape_sources, archive, ARCHIVE_CAP, STATE_SIZE, 51801 + round * 131)
          frontier_escape_completed_batches = 0
          if SEED_NAIVE == 0
            z = ff7_add_known_7x7_shoulder(RUNTIME_ROOT, best, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, near2, near2_signatures, near2_uses, near2_successes, near2_capacity, NEAR_SIGNATURE_QUOTA, near_counters)
            z = ff7_add_known_7x7_rank247_shoulders(RUNTIME_ROOT, best, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, near1, near1_signatures, near1_uses, near1_successes, near1_capacity, NEAR_SIGNATURE_QUOTA, near_counters)
            z = ffps_add_profile_near_seeds(RUNTIME_ROOT, best, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, near1, near1_signatures, near1_uses, near1_successes, near1_capacity, near2, near2_signatures, near2_uses, near2_successes, near2_capacity, NEAR_SIGNATURE_QUOTA, near_counters)
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
              z = ffme_add_copy(map_states, map_keys, map_uses, map_sources, reset_map_pool[reset_map_index], ffw_best_rank(best), N, MAP_CAPACITY, reset_map_source, STATE_SIZE, 52051 + reset_map_source * 101 + reset_map_index)
              reset_map_index += 1
            reset_map_source += 1
          archive_min_cache = ffn_archive_min_distance(archive)
          symmetry_cpu_uses = 0

          if core_fringe_index >= 0
            if ffn_core_fringe_state_into(states[core_fringe_index], best, archive, near1, near2, mixed, N, CAPACITY, 50037 + round * 131, DSLACK, CYCLES, cpu_work_moves[zones[core_fringe_index]], cpu_wander_moves[zones[core_fringe_index]], core_fringe_out_scratch) == 1
              core_fringe_slots = core_fringe_out_scratch[0]
              active_near_seeds[core_fringe_index] = nil
              active_seed_ranks[core_fringe_index] = ffw_best_rank(states[core_fringe_index])
              active_seed_start_moves[core_fringe_index] = ffw_moves(states[core_fringe_index])
              active_seed_finished[core_fringe_index] = 1
              island_best_ranks[core_fringe_index] = ffw_best_rank(states[core_fringe_index])
              sources[core_fringe_index] = "core-fringe/manual-naive-" + core_fringe_slots.to_s()
              lineage_roles[core_fringe_index] = 0 - 1
              lineage_modes[core_fringe_index] = 0 - 1
              lineage_origin_ids[core_fringe_index] = ffbi_best_id(states[core_fringe_index])
              last_seen_rank[core_fringe_index] = ffw_best_rank(states[core_fringe_index])
              last_seen_bits[core_fringe_index] = ffw_best_bits(states[core_fringe_index])
              last_moves[core_fringe_index] = ffw_moves(states[core_fringe_index])
              last_progress_ms[core_fringe_index] = now_ms

          if racer_index >= 0
            racer_pulls = i64[9]
            racer_exposure = i64[9]
            racer_novel = i64[9]
            racer_returns = i64[9]
            racer_drops = i64[9]
            racer_density = i64[9]
            racer_seen_ids = i64[64]
            racer_seen_count = 1
            racer_epoch = 0
            racer_arm = ffcr_select_arm(0, racer_pulls, racer_exposure, racer_novel, racer_returns, racer_drops, racer_density)
            z = ffcr_apply_arm(states[racer_index], racer_arm, cpu_work_moves[zones[racer_index]], cpu_wander_moves[zones[racer_index]], racer_controls)
            racer_lease_start_moves = ffw_moves(states[racer_index])
            racer_lease_start_rank = ffw_best_rank(states[racer_index])
            racer_lease_start_bits = ffw_best_bits(states[racer_index])
            racer_lease_origin_id = ffbi_current_id(states[racer_index])
            racer_seen_ids[0] = racer_lease_origin_id
            racer_lease_novel = 0
            sources[racer_index] = sources[racer_index] + "/race-a" + racer_arm.to_s()
          if cycle_watch_index >= 0
            cycle_stats = i64[9]
            sources[cycle_watch_index] = sources[cycle_watch_index] + "/cycle-watch"

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
          lineage_roles[rw] = 0 - 1
          lineage_modes[rw] = 0 - 1
          lineage_origin_ids[rw] = ffbi_best_id(anchor)
          lineage_start_ranks[rw] = ffw_best_rank(anchor)
          lineage_start_bits[rw] = ffw_best_bits(anchor)
          lineage_debts[rw] = 0
          lineage_paid[rw] = 0
          if SEED_NAIVE == 1
            sources[rw] = ffp_door_name(doors[rw]) + "/manual-naive-anchor"
          if SEED_NAIVE == 0
            sources[rw] = ffp_door_name(doors[rw]) + "/manual-record"
          last_seen_rank[rw] = ffw_best_rank(states[rw])
          last_seen_bits[rw] = ffw_best_bits(states[rw])
          last_moves[rw] = ffw_moves(states[rw])
          last_progress_ms[rw] = now_ms
          rw += 1
        if racer_index >= 0
          z = ffcr_apply_arm(states[racer_index], racer_arm, cpu_work_moves[zones[racer_index]], cpu_wander_moves[zones[racer_index]], racer_controls)
          racer_lease_start_moves = ffw_moves(states[racer_index])
          racer_lease_start_rank = ffw_best_rank(states[racer_index])
          racer_lease_start_bits = ffw_best_bits(states[racer_index])
          racer_lease_origin_id = ffbi_current_id(states[racer_index])
          racer_lease_novel = 0
          sources[racer_index] = sources[racer_index] + "/race-a" + racer_arm.to_s()
        if cycle_watch_index >= 0
          cycle_stats[8] = 0
          sources[cycle_watch_index] = sources[cycle_watch_index] + "/cycle-watch"
        if SEED_NAIVE == 1
          flash_text = "fleet reseeded on the naive anchor (r" + ffw_best_rank(anchor).to_s + ")"
        if SEED_NAIVE == 0
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
    if i == racer_index
      live_identity = ffbi_current_id(state) ## i64
      seen_identity = 0 ## i64
      race_seen = 0 ## i64
      while race_seen < racer_seen_count
        if racer_seen_ids[race_seen] == live_identity
          seen_identity = 1
          race_seen = racer_seen_count
        else
          race_seen += 1
      if seen_identity == 0
        racer_lease_novel = 1
        if racer_seen_count < 64
          racer_seen_ids[racer_seen_count] = live_identity
          racer_seen_count += 1
    if i == cycle_watch_index
      sources[i] = "cycle-watch u" + cycle_stats[2].to_s() + " h" + cycle_stats[3].to_s() + " i" + cycle_stats[4].to_s()
    cohort_index = ffp_seed_door(doors[i]) * 4 + zones[i] ## i64
    if cohort_index < 0
      cohort_index = 0
    if cohort_index > 27
      cohort_index = 27
    cohort_moves[cohort_index] = cohort_moves[cohort_index] + delta_moves
    if rank != last_seen_rank[i] || bits != last_seen_bits[i]
      exact = ffw_verify_best_exact(state, N) ## i64
      if exact == 1
        descendant_identity = ffbi_best_id(state) ## i64
        if lineage_roles[i] >= 0 && lineage_paid[i] == 0
          lineage_novel = 0 ## i64
          if descendant_identity != lineage_origin_ids[i]
            lineage_novel = 1
          delayed_reward = ffl_delayed_reward(lineage_start_ranks[i], lineage_start_bits[i], rank, bits, lineage_novel) ## i64
          if delayed_reward > 0
            lineage_role = lineage_roles[i] ## i64
            gpu_rewards[lineage_role] = gpu_rewards[lineage_role] + delayed_reward
            gpu_epoch_rewards[lineage_role] = gpu_epoch_rewards[lineage_role] + delayed_reward
            lineage_rewards[lineage_role] = lineage_rewards[lineage_role] + delayed_reward
            lineage_context = ffkp_context(N, lineage_debts[i]) ## i64
            lineage_transition = lineage_role * ffkp_context_count() + lineage_context ## i64
            gpu_transition_rewards[lineage_transition] = gpu_transition_rewards[lineage_transition] + delayed_reward
            if lineage_modes[i] >= 0
              z = ffkp_record_reward(lineage_modes[i], N, lineage_debts[i], delayed_reward, pool_rewards)
            lineage_paid[i] = 1
        if rank > 0
          if island_best_ranks[i] <= 0 || rank < island_best_ranks[i]
            island_best_ranks[i] = rank
        if active_seed_finished[i] == 0
          seed_debt = active_seed_ranks[i] - ffw_best_rank(best) ## i64
          if seed_debt > 0 && rank <= ffw_best_rank(best)
            spent = moves_now - active_seed_start_moves[i] ## i64
            z = ffrd_finish(seed_debt, 1, spent, debt_returns, debt_failures, debt_exposure)
            active_seed_finished[i] = 1
        map_candidate_source = doors[i] ## i64
        if lineage_roles[i] >= 0
          map_candidate_source = ffl_gpu_source(lineage_roles[i], lineage_modes[i])
        z = ffme_add_copy(map_states, map_keys, map_uses, map_sources, state, ffw_best_rank(best), N, MAP_CAPACITY, map_candidate_source, STATE_SIZE, 7001 + round * 23 + i)
        z = ffl_registry_add(lineage_registry_ids, lineage_registry_sources, state, map_candidate_source, LINEAGE_REGISTRY_CAPACITY)
        # Preserve structurally novel equal-frontier CPU returns in separate,
        # fixed archive storage; neither archive nor MAP retains the mutable
        # island state itself.
        if rank == ffw_best_rank(best)
          z = ffn_archive_add_copy(archive, state, ARCHIVE_CAP, 4, archive_counters, STATE_SIZE, 7101 + round * 23 + i)
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
            c3_ok = 0 ## i64
            if c3_base == nil
              c3_candidate = ffn_clone_trusted(state, STATE_SIZE, 8003 + round * 29 + i)
              if c3_candidate != nil
                c3_base = c3_candidate
                c3_ok = 1
            if c3_base != nil && c3_ok == 0
              loaded_c3 = ffw_reseed_from(c3_base, state, 8005 + round * 29 + i) ## i64
              if loaded_c3 > 0
                c3_ok = 1
              if loaded_c3 < 1
                c3_candidate = ffn_clone_trusted(state, STATE_SIZE, 8007 + round * 29 + i)
                if c3_candidate != nil
                  c3_base = c3_candidate
                  c3_ok = 1
            if c3_ok == 1
              symmetry.clear
              orbit_bank.clear
              polar_bank.clear
              z = ffn_add_c3_family(c3_base, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, symmetry, orbit_bank, polar_bank, SYMMETRY_CAP) ## i64
        # Normalize a would-be fleet improvement within its exact global GL
        # orbit before adoption.  This is a bounded coordinator task, never a
        # random restart and never part of the hot worker loop.
        if ffn_better(rank, bits, ffw_best_rank(best), ffw_best_bits(best)) == 1
          normalized = ffgir_density_descent_state_into(state, global_isotropy_scratch, N, CAPACITY, 88001 + round * 31 + i, DSLACK, CYCLES, balanced_work, balanced_wander, 32, global_isotropy_stats) ## i64
          if normalized == rank && ffw_best_bits(global_isotropy_scratch) < bits
            old_signature = ffgir_orbit_signature(state) ## i64
            if ffw_reseed_from(state, global_isotropy_scratch, 88101 + round * 31 + i) == rank
              rank = ffw_best_rank(state)
              bits = ffw_best_bits(state)
              global_isotropy_counters[0] = global_isotropy_counters[0] + 1
              global_isotropy_counters[1] = global_isotropy_counters[1] + 1
              global_isotropy_counters[3] = global_isotropy_counters[3] + global_isotropy_stats[2]
              # The invariant signature must survive every directed rewrite;
              # a mismatch is telemetry only, but prevents a false provenance
              # claim if this code is ever generalized incorrectly.
              if old_signature == ffgir_orbit_signature(state)
                sources[i] = sources[i] + "/" + ffn_global_isotropy_tag(state)
        if ffn_better(rank, bits, ffw_best_rank(best), ffw_best_bits(best)) == 1
          old_rank = ffw_best_rank(best) ## i64
          # On a rank drop, snapshot the previous leader before reseeding best
          # in place (demoted_frontiers must not alias the live best buffer).
          # Density-only ties reseed best without a demoted snapshot.
          adopted = 0 ## i64
          if rank < old_rank
            if strict_drop == 0
              pi = 0 ## i64
              while pi < near1.size()
                preserved_shoulders.push(near1[pi])
                pi += 1
            demoted_snapshot = ffn_clone_trusted(best, STATE_SIZE, 9001 + round * 31 + i)
            if demoted_snapshot != nil
              demoted_frontiers.push(demoted_snapshot)
            loaded_best = ffw_reseed_from(best, state, 9003 + round * 31 + i) ## i64
            if loaded_best > 0
              adopted = 1
            if loaded_best < 1
              replacement = ffn_clone_trusted(state, STATE_SIZE, 9005 + round * 31 + i)
              if replacement != nil
                best = replacement
                adopted = 1
          if rank == old_rank
            loaded_best = ffw_reseed_from(best, state, 9007 + round * 31 + i) ## i64
            if loaded_best > 0
              adopted = 1
            if loaded_best < 1
              replacement = ffn_clone_trusted(state, STATE_SIZE, 9009 + round * 31 + i)
              if replacement != nil
                best = replacement
                adopted = 1
          if adopted == 1
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
            # Archive owns its own copy; reseed-in-place when replacing a slot.
            z = ffn_archive_add_copy(archive, best, ARCHIVE_CAP, 4, archive_counters, STATE_SIZE, 12001 + round * 37 + i) ## i64
            archive_min_cache = ffn_archive_min_distance(archive)
            z = ffn_dump_trusted(best, BEST_PATH, RUN_TAG)
            if z < 1
              gpu_degraded = 1
        fleet_rank = ffw_best_rank(best) ## i64
        if rank == fleet_rank + 1
          if ffn_near_add_if_admitted(near1, near1_signatures, near1_uses, near1_successes, state, near1_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters, near_signature_values, near_signature_counts, near_axis_signatures, STATE_SIZE, 15001 + round * 41 + i) == 1
            cohort_near[cohort_index] = cohort_near[cohort_index] + 1
        if rank == fleet_rank + 2
          if ffn_near_add_if_admitted(near2, near2_signatures, near2_uses, near2_successes, state, near2_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters, near_signature_values, near_signature_counts, near_axis_signatures, STATE_SIZE, 17001 + round * 43 + i) == 1
            cohort_near[cohort_index] = cohort_near[cohort_index] + 1
      if exact == 0
        invalid_candidates += 1
        qz = ffw_reseed_from(state, anchor, 19001 + round * 59 + i) ## i64
        sources[i] = ffp_door_name(doors[i]) + "/quarantine-anchor"
        lineage_roles[i] = 0 - 1
        lineage_modes[i] = 0 - 1
        lineage_origin_ids[i] = ffbi_best_id(anchor)
        lineage_start_ranks[i] = ffw_best_rank(anchor)
        lineage_start_bits[i] = ffw_best_bits(anchor)
        lineage_paid[i] = 0
        if i == cycle_watch_index
          cycle_stats[8] = 0
        rank = ffw_best_rank(state)
        bits = ffw_best_bits(state)
      last_seen_rank[i] = rank
      last_seen_bits[i] = bits
    last_moves[i] = moves_now
    last_ages[i] = (now_ms - last_progress_ms[i]) / 1000
    i += 1

  if cycle_watch_index >= 0
    baseline_rate_sum = 0 ## i64
    baseline_rate_count = 0 ## i64
    ci = 0 ## i64
    while ci < J
      if ci != core_fringe_index && ci != racer_index && ci != cycle_watch_index && last_rates[ci] > 0
        baseline_rate_sum += last_rates[ci]
        baseline_rate_count += 1
      ci += 1
    cycle_overhead = 0 ## i64
    if baseline_rate_count > 0
      baseline_rate = baseline_rate_sum / baseline_rate_count ## i64
      if baseline_rate > last_rates[cycle_watch_index] && baseline_rate > 0
        cycle_overhead = (baseline_rate - last_rates[cycle_watch_index]) * 100 / baseline_rate
    sources[cycle_watch_index] = "cycle-watch u" + cycle_stats[2].to_s() + " h" + cycle_stats[3].to_s() + " i" + cycle_stats[4].to_s() + " o" + cycle_overhead.to_s() + "%"

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
          gpu_join_ok = ffn_join_ok(ffn_thread_join_release(gpu_thread)) ## i64
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
          if gpu_join_ok == 0
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
          gpu_candidate = gpu_candidate_states[gpu_slot]
          gpu_launch_is_current = 0 ## i64
          if gpu_launch_generation[gpu_slot] == fleet_generation
            gpu_launch_is_current = 1
          gpu_rank = 0 - 1 ## i64
          if gpu_join_ok == 1 && gpu_launch_is_current == 1 && ffn_scheme_file_nonempty(raw_gpu_output) == 1
            gpu_rank = ffw_load_scheme_cap(gpu_candidate, gpu_output, N, CAPACITY, 41001 + round * 61 + gpu_slot, DSLACK, CYCLES, balanced_work, balanced_wander)
          internal_target = ffw_best_rank(best) - 1 ## i64
          if gpu_rank <= 0 && gpu_join_ok == 1 && gpu_launch_is_current == 1
            repaired_rank = ffn_repair_gpu_internal_reject(RUN_TAG, N, gpu_slot, gpu_launch_nonces[gpu_slot], internal_target, CAPACITY, DSLACK, CYCLES, balanced_work, balanced_wander, gpu_candidate) ## i64
            if repaired_rank > 0
              gpu_rank = repaired_rank
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
              # Archive/MAP-style: copy only on admit, reseed on replace.
              z = ffn_archive_add_copy(archive, gpu_candidate, ARCHIVE_CAP, 4, archive_counters, STATE_SIZE, 43001 + round * 67 + gpu_role) ## i64
              archive_min_cache = ffn_archive_min_distance(archive)
              # Pareto bank still takes a stable owned snapshot only when admitted
              # by its own policy (reference form); reseed is handled inside
              # ffbp_pareto_add if present — clone only when needed.
              gpu_snapshot = ffn_clone_trusted(gpu_candidate, STATE_SIZE, 43003 + round * 67 + gpu_role)
              if gpu_snapshot != nil
                pareto_admitted = ffbp_pareto_add(gpu_pareto_archive, gpu_pareto_ranks, gpu_pareto_bits, gpu_pareto_pairs, gpu_pareto_novelties, gpu_pareto_roles, gpu_pareto_uses, gpu_snapshot, best, GPU_NOVELTY_CAP, gpu_role, gpu_pareto_counters)
                if pareto_admitted == 1
                  pareto_index = ffbp_find_state(gpu_pareto_archive, gpu_snapshot) ## i64
                  if pareto_index >= 0
                    novelty = gpu_pareto_novelties[pareto_index]
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
                c3_ok = 0 ## i64
                if c3_base == nil
                  c3_candidate = ffn_clone_trusted(gpu_candidate, STATE_SIZE, 45001 + round * 69 + gpu_role)
                  if c3_candidate != nil
                    c3_base = c3_candidate
                    c3_ok = 1
                if c3_base != nil && c3_ok == 0
                  loaded_c3 = ffw_reseed_from(c3_base, gpu_candidate, 45003 + round * 69 + gpu_role) ## i64
                  if loaded_c3 > 0
                    c3_ok = 1
                  if loaded_c3 < 1
                    c3_candidate = ffn_clone_trusted(gpu_candidate, STATE_SIZE, 45005 + round * 69 + gpu_role)
                    if c3_candidate != nil
                      c3_base = c3_candidate
                      c3_ok = 1
                if c3_ok == 1
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
            map_gpu_source = ffl_gpu_source(gpu_role, completed_pool_mode) ## i64
            z = ffme_add_copy(map_states, map_keys, map_uses, map_sources, gpu_candidate, ffw_best_rank(best), N, MAP_CAPACITY, map_gpu_source, STATE_SIZE, 44001 + round * 68 + gpu_role)
            z = ffl_registry_add(lineage_registry_ids, lineage_registry_sources, gpu_candidate, map_gpu_source, LINEAGE_REGISTRY_CAPACITY)
            if c3_branch_reward > 0
              gpu_rewards[gpu_role] = gpu_rewards[gpu_role] + c3_branch_reward
              gpu_epoch_rewards[gpu_role] = gpu_epoch_rewards[gpu_role] + c3_branch_reward
            gpu_transition_rewards[transition_index] = gpu_transition_rewards[transition_index] + reward + c3_branch_reward
            if ffn_better(gpu_rank, gpu_bits, before_rank, before_bits) == 1
              gpu_adopted = 0 ## i64
              if gpu_rank < before_rank
                if strict_drop == 0
                  pi = 0 ## i64
                  while pi < near1.size()
                    preserved_shoulders.push(near1[pi])
                    pi += 1
                demoted_snapshot = ffn_clone_trusted(best, STATE_SIZE, 46001 + round * 71 + gpu_role)
                if demoted_snapshot != nil
                  demoted_frontiers.push(demoted_snapshot)
                strict_drop = 1
                new_bests += 1
              if gpu_rank == before_rank
                tie_bests += 1
              loaded_best = ffw_reseed_from(best, gpu_candidate, 46003 + round * 71 + gpu_role) ## i64
              if loaded_best > 0
                gpu_adopted = 1
              if loaded_best < 1
                gpu_replacement = ffn_clone_trusted(gpu_candidate, STATE_SIZE, 46005 + round * 71 + gpu_role)
                if gpu_replacement != nil
                  best = gpu_replacement
                  gpu_adopted = 1
              if gpu_adopted == 1
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
              z = ffn_near_add_if_admitted(near1, near1_signatures, near1_uses, near1_successes, gpu_candidate, near1_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters, near_signature_values, near_signature_counts, near_axis_signatures, STATE_SIZE, 47001 + round * 73 + gpu_role)
            if gpu_rank == fleet_rank + 2
              z = ffn_near_add_if_admitted(near2, near2_signatures, near2_uses, near2_successes, gpu_candidate, near2_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters, near_signature_values, near_signature_counts, near_axis_signatures, STATE_SIZE, 48001 + round * 73 + gpu_role)
          if gpu_rank <= 0 && gpu_join_ok == 1 && gpu_launch_is_current == 1
            if ffn_scheme_file_nonempty(raw_gpu_output) == 1
              # A worker may report a provisional algebraic improvement that
              # loses the independent n^6 gate.  That is a rejected search
              # candidate, not lost GPU coverage.  Process/launch/I/O errors
              # above remain infrastructure failures and still degrade.
              invalid_candidates += 1
          gpu_internal_rejects = ffn_harvest_gpu_internal_reject(RUN_TAG, N, gpu_slot, gpu_role, completed_pool_mode, gpu_launch_nonces[gpu_slot], internal_target, CAPACITY, DSLACK, CYCLES, balanced_work, balanced_wander, gpu_internal_rejects, gpu_candidate)
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

    # Harvest the two rectangular Metal children through an independent
    # exhaustive host gate.  A component improvement is durable on its own,
    # earns its three-copy propagated reward, and is then recomposed into a
    # fully verified 7x7 candidate before it can touch the square frontier.
    rect_component = 0
    while rect_component < 2
      rect_slot = 13 + rect_component ## i64
      rect_thread = gpu_threads[rect_slot]
      if rect_thread != nil
        if rect_thread.alive? == false
          rect_join_ok = ffn_join_ok(ffn_thread_join_release(rect_thread)) ## i64
          gpu_threads[rect_slot] = nil
          rect_active[rect_component] = 0
          rect_epochs[rect_component] = rect_epochs[rect_component] + 1
          rect_wall_ms[rect_component] = rect_wall_ms[rect_component] + rect_elapsed_ms[rect_component]
          gpu_wall_ms[10] = gpu_wall_ms[10] + rect_elapsed_ms[rect_component]
          rect_chunks = gpu_launch_lanes[rect_slot] / 32 ## i64
          if rect_chunks < 1
            rect_chunks = 1
          rect_quanta = (rect_elapsed_ms[rect_component] + 99) / 100 ## i64
          if rect_quanta < 1
            rect_quanta = 1
          rect_lane_exposure = rect_chunks * rect_quanta ## i64
          rect_exposure[rect_component] = rect_exposure[rect_component] + rect_lane_exposure
          gpu_epochs[10] = gpu_epochs[10] + 1
          gpu_lane_epochs[10] = gpu_lane_epochs[10] + rect_lane_exposure
          rect_transition = 10 * ffkp_context_count() + ffkp_context(7, 0) ## i64
          gpu_transition_exposure[rect_transition] = gpu_transition_exposure[rect_transition] + rect_lane_exposure
          if rect_join_ok == 0
            rect_failures[rect_component] = rect_failures[rect_component] + 1
            rect_retry_round[rect_component] = round + ffn_gpu_retry_delay(rect_failures[rect_component])

          rect_output = ffn_rect_output_path(RUN_TAG, rect_component)
          raw_rect_output = read_file(rect_output)
          rect_n = ffn_rect_n(rect_component) ## i64
          rect_m = ffn_rect_m(rect_component) ## i64
          rect_p = ffn_rect_p(rect_component) ## i64
          rect_candidate = rect_candidate_states[rect_component]
          rect_rank = 0 - 1 ## i64
          if rect_join_ok == 1 && ffn_scheme_file_nonempty(raw_rect_output) == 1
            rect_rank = ffr_load_scheme_cap(rect_candidate, rect_output, rect_n, rect_m, rect_p, rect_capacities[rect_component], 63001 + round * 71 + rect_component, DSLACK, CYCLES, balanced_work, balanced_wander)
          if rect_rank > 0 && rect_states[rect_component] != nil
            rect_candidates[rect_component] = rect_candidates[rect_component] + 1
            old_rect_rank = ffr_best_rank(rect_states[rect_component]) ## i64
            old_rect_bits = ffr_best_bits(rect_states[rect_component]) ## i64
            rect_bits = ffr_best_bits(rect_candidate) ## i64
            if ffn_better(rect_rank, rect_bits, old_rect_rank, old_rect_bits) == 1
              component_reward = ffn_rect_reward(old_rect_rank, old_rect_bits, rect_rank, rect_bits) ## i64
              checkpoint_rank = ffn_dump_rect_atomic(rect_candidate, rect_checkpoint_paths[rect_component], RUN_TAG, rect_component) ## i64
              if checkpoint_rank > 0
                rect_state_size = ffr_state_size(rect_capacities[rect_component]) ## i64
                rect_stable = i64[rect_state_size]
                rect_copy_index = 0 ## i64
                while rect_copy_index < rect_state_size
                  rect_stable[rect_copy_index] = rect_candidate[rect_copy_index]
                  rect_copy_index += 1
                rect_states[rect_component] = rect_stable
                if rect_component == 0
                  if rect_archive_334.size() < 16
                    rect_archive_334.push(rect_stable)
                  rect_archive_counts[0] = rect_archive_334.size()
                if rect_component == 1
                  if rect_archive_344.size() < 16
                    rect_archive_344.push(rect_stable)
                  rect_archive_counts[1] = rect_archive_344.size()
                rect_rewards[rect_component] = rect_rewards[rect_component] + component_reward
                if rect_rank < old_rect_rank
                  rect_rank_drops[rect_component] = rect_rank_drops[rect_component] + 1
                if rect_rank == old_rect_rank && rect_bits < old_rect_bits
                  rect_density[rect_component] = rect_density[rect_component] + 1

                # Role 10 learns the component's propagated value, but keeps
                # per-component evidence above for the 334/344 lane split.
                gpu_rewards[10] = gpu_rewards[10] + component_reward
                gpu_epoch_rewards[10] = gpu_epoch_rewards[10] + component_reward
                gpu_transition_rewards[rect_transition] = gpu_transition_rewards[rect_transition] + component_reward
                rect_composition_dirty = 1
                rect_last_improved = rect_component
              if checkpoint_rank <= 0
                rect_failures[rect_component] = rect_failures[rect_component] + 1
                rect_retry_round[rect_component] = round + ffn_gpu_retry_delay(rect_failures[rect_component])
          if rect_rank <= 0 && rect_join_ok == 1
            if ffn_scheme_file_nonempty(raw_rect_output) == 1
              invalid_candidates += 1

          # Rectangular cal2zone publishes inexact nominal improvements only
          # through committed sidecars.  Harvest even when ordinary output is
          # empty, preserve a shape-aware replay bundle, and account the event
          # in both the exact-reject counter and GPU health telemetry.
          rect_target = 0 ## i64
          if rect_states[rect_component] != nil
            rect_target = ffr_best_rank(rect_states[rect_component]) - 1
          rect_nonce = rect_launch_number[rect_component] - 1 ## i64
          if rect_nonce < 0
            rect_nonce = 0
          rect_internal_rejects = ffrgr_harvest(rect_output, ffn_rect_seed_path(RUN_TAG, rect_component), RUN_TAG, rect_n, rect_m, rect_p, rect_slot, 10, 0 - 1, rect_nonce, rect_target, rect_capacities[rect_component], DSLACK, CYCLES, balanced_work, balanced_wander, rect_internal_rejects, rect_reject_scratch[rect_component], rect_reject_status)
          if rect_reject_status[0] != 0
            invalid_candidates += 1
            rect_failures[rect_component] = rect_failures[rect_component] + 1
            gpu_failures[10] = gpu_failures[10] + 1
            gpu_degraded = 1
            rect_retry_round[rect_component] = round + ffn_gpu_retry_delay(rect_failures[rect_component])
          rect_clear_ok = write_file(rect_output, "")
          if rect_clear_ok == false
            rect_failures[rect_component] = rect_failures[rect_component] + 1
            rect_retry_round[rect_component] = round + ffn_gpu_retry_delay(rect_failures[rect_component])
      rect_component += 1

    # Retry any exact component composition that has not yet produced an
    # independently verified square candidate.  This runs once at startup and
    # after every component improvement; transient composer/I/O failures retain
    # dirty state with bounded backoff instead of stranding a stronger leaf.
    if ff7_composition_due(rect_composition_dirty, round, rect_composition_retry_round) != 0 && rect_states[0] != nil && rect_states[1] != nil
      compose_source = rect_last_improved ## i64
      if compose_source < 0
        compose_source = 0
      rect_composition_attempts += 1
      composed_path = ffn_rect_composed_path(RUN_TAG, compose_source, rect_composition_attempts)
      component_444_path = RUNTIME_ROOT + "/seeds/gf2/matmul_4x4_rank47_d450_gf2.txt"
      composed_rank = ffsc_compose_files(component_444_path, rect_checkpoint_paths[0], rect_checkpoint_paths[1], composed_path, 0) ## i64
      composed_loaded = 0 - 1 ## i64
      composed_candidate = rect_composed_candidate
      if composed_rank > 0
        composed_loaded = ffw_load_scheme_cap(composed_candidate, composed_path, 7, CAPACITY, 64007 + round * 73 + compose_source, DSLACK, CYCLES, balanced_work, balanced_wander)
      if composed_loaded > 0
        rect_composition_dirty = 0
        rect_composition_retry_round = 0
        composed_bits = ffw_best_bits(composed_candidate) ## i64
        square_before_rank = ffw_best_rank(best) ## i64
        square_before_bits = ffw_best_bits(best) ## i64
        gpu_candidates[10] = gpu_candidates[10] + 1
        if composed_loaded < square_before_rank
          gpu_rank_drops[10] = gpu_rank_drops[10] + 1
        if composed_loaded == square_before_rank && composed_bits < square_before_bits
          gpu_density[10] = gpu_density[10] + 1
        z = ffme_add_copy(map_states, map_keys, map_uses, map_sources, composed_candidate, square_before_rank, N, MAP_CAPACITY, ffl_rect_source(compose_source), STATE_SIZE, 66003 + round * 83 + compose_source)
        z = ffl_registry_add(lineage_registry_ids, lineage_registry_sources, composed_candidate, ffl_rect_source(compose_source), LINEAGE_REGISTRY_CAPACITY)
        if ffn_better(composed_loaded, composed_bits, square_before_rank, square_before_bits) == 1
          composed_adopted = 0 ## i64
          if composed_loaded < square_before_rank
            if strict_drop == 0
              pi = 0 ## i64
              while pi < near1.size()
                preserved_shoulders.push(near1[pi])
                pi += 1
            demoted_snapshot = ffn_clone_trusted(best, STATE_SIZE, 67001 + round * 89 + compose_source)
            if demoted_snapshot != nil
              demoted_frontiers.push(demoted_snapshot)
            strict_drop = 1
            new_bests += 1
          if composed_loaded == square_before_rank
            tie_bests += 1
          loaded_best = ffw_reseed_from(best, composed_candidate, 67003 + round * 89 + compose_source) ## i64
          if loaded_best > 0
            composed_adopted = 1
          if loaded_best < 1
            composed_replacement = ffn_clone_trusted(composed_candidate, STATE_SIZE, 67005 + round * 89 + compose_source)
            if composed_replacement != nil
              best = composed_replacement
              composed_adopted = 1
          if composed_adopted == 1
            if timeline_count < 256
              timeline_times[timeline_count] = elapsed_s - timeline_start_s
              timeline_ranks[timeline_count] = composed_loaded
              timeline_count += 1
            else
              ti = 0 ## i64
              while ti < 255
                timeline_times[ti] = timeline_times[ti + 1]
                timeline_ranks[ti] = timeline_ranks[ti + 1]
                ti += 1
              timeline_times[255] = elapsed_s - timeline_start_s
              timeline_ranks[255] = composed_loaded
            z = ffn_dump_trusted(best, BEST_PATH, RUN_TAG)
            if z < 1
              gpu_degraded = 1
            flash_text = "rectangular checkpoints recomposed exactly: 7x7 r" + composed_loaded.to_s()
            flash_until_ms = now_ms + 6000
      if composed_loaded <= 0
        rect_composition_failures += 1
        invalid_candidates += 1
        rect_composition_retry_round = round + ffn_gpu_retry_delay(rect_composition_failures)

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
      parent_pair_ready = ffn_has_parent_pair(map_states, archive, 12) ## i64
      gpu_pool_ready = ffn_fill_pool_readiness(pool_mode_ready, gpu_generic_ready, gpu_mitm_ready, gpu_constraint_ready, gpu_kxor_ready, gpu_differential_ready, gpu_span_ready, gpu_shear_ready, gpu_frozen_sat_ready, gpu_global_shear_ready, parent_pair_ready, orbit_bank, polar_bank)
      pool_slot = 0
      while pool_slot < 3
        gpu_slot = 10 + pool_slot ## i64
        pool_group = pool_slot_groups[pool_slot] ## i64
        pool_lanes = pool_slot_lanes[pool_slot] ## i64
        if gpu_threads[gpu_slot] == nil && pool_group >= 0 && pool_lanes > 0 && round >= pool_slot_retry_round[pool_slot]
          pool_mode = ffkp_select_group_mode_ready(pool_group_epochs[pool_group], pool_group, N, ffw_best_rank(best), 0, pool_mode_ready, pool_last_modes, pool_pulls, pool_rewards) ## i64
          if pool_mode >= 0
            pool_cap = ffkp_mode_lane_budget_for_tensor(N, GPU_WALKERS, pool_mode) ## i64
            if pool_lanes > pool_cap
              pool_lanes = pool_cap
            pool_modes[pool_slot] = pool_mode
            pool_launch_number = gpu_launch_number[10] ## i64
            pool_slot_launch_numbers[pool_slot] = pool_launch_number
            gpu_launch_nonces[gpu_slot] = pool_launch_number
            gpu_seed = ffn_pool_seed(pool_mode, pool_launch_number, best, map_states, map_uses, c3_base, orbit_bank, polar_bank, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander)
            gpu_companion = nil
            if pool_mode == 12 && gpu_seed != nil
              gpu_companion = ffn_parent_companion(gpu_seed, map_states, archive, 12)
              if gpu_companion == nil
                gpu_seed = ffn_parent_pair_primary(map_states, archive, 12)
                if gpu_seed != nil
                  gpu_companion = ffn_parent_companion(gpu_seed, map_states, archive, 12)
            if gpu_seed != nil
              gpu_seed_rank = ffw_best_rank(gpu_seed) ## i64
              if gpu_seed_ranks[10] == 0 || gpu_seed_rank < gpu_seed_ranks[10]
                gpu_seed_ranks[10] = gpu_seed_rank
              gpu_launch_debt[gpu_slot] = gpu_seed_rank - ffw_best_rank(best)
              gpu_launch_lanes[gpu_slot] = pool_lanes
              gpu_elapsed_ms[gpu_slot] = 0
              gpu_launch_generation[gpu_slot] = fleet_generation
              gpu_threads[gpu_slot] = ffn_gpu_launch_pool(RUNTIME_ROOT, GPU_BINARY, MITM_BINARY, CONSTRAINT_BINARY, KXOR_BINARY, DIFFERENTIAL_BINARY, SPAN_BINARY, SHEAR_BINARY, FROZEN_SAT_BINARY, GLOBAL_SHEAR_BINARY, RUN_TAG, N, gpu_slot, pool_mode, pool_lanes, GPU_STEPS, GPU_EPOCH_ROUNDS, pool_launch_number, gpu_seed, gpu_companion, gpu_elapsed_ms)
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

      # Keep each rectangular component's assigned Metal slice busy while the
      # current adaptive epoch is live.  Independent backoff prevents one
      # broken child from suppressing the other component or the square pool.
      rect_component = 0
      while rect_component < 2
        rect_slot = 13 + rect_component ## i64
        if gpu_threads[rect_slot] == nil && rect_ready[rect_component] != 0 && rect_lanes[rect_component] > 0 && round >= rect_retry_round[rect_component]
          rect_elapsed_ms[rect_component] = 0
          gpu_launch_lanes[rect_slot] = rect_lanes[rect_component]
          gpu_launch_debt[rect_slot] = 0
          gpu_threads[rect_slot] = ffn_gpu_launch_rect(RUNTIME_ROOT, rect_binaries[rect_component], RUN_TAG, rect_component, rect_lanes[rect_component], GPU_STEPS, GPU_EPOCH_ROUNDS, rect_states[rect_component], rect_elapsed_ms, gpu_persistent_processes, gpu_persistent_active, gpu_persistent_generations, gpu_persistent_lanes)
          if gpu_threads[rect_slot] == nil
            rect_failures[rect_component] = rect_failures[rect_component] + 1
            rect_retry_round[rect_component] = round + ffn_gpu_retry_delay(rect_failures[rect_component])
            rect_active[rect_component] = 0
          else
            rect_active[rect_component] = 1
            rect_launch_number[rect_component] = rect_launch_number[rect_component] + 1
        rect_component += 1

  if strict_drop == 1
    # GPU-originated rank drops reach this point without traversing the CPU
    # candidate path above.  Normalize the final round leader once, before
    # rebuilding frontier-relative banks.
    normalized_best = ffgir_density_descent_state_into(best, global_isotropy_scratch, N, CAPACITY, 99001 + round * 47, DSLACK, CYCLES, balanced_work, balanced_wander, 32, global_isotropy_stats) ## i64
    if normalized_best == ffw_best_rank(best) && ffw_best_bits(global_isotropy_scratch) < ffw_best_bits(best)
      if ffw_reseed_from(best, global_isotropy_scratch, 99003 + round * 47) == normalized_best
        global_isotropy_counters[0] = global_isotropy_counters[0] + 1
        global_isotropy_counters[1] = global_isotropy_counters[1] + 1
        global_isotropy_counters[3] = global_isotropy_counters[3] + global_isotropy_stats[2]
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
    z = ffn_add_global_isotropy_images(archive, mixed, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, global_isotropy_counters) ## i64
    frontier_escape_admissions.clear
    frontier_escape_last_ms = now_ms
    if SEED_NAIVE == 0
      z = ff7_add_known_7x7_shoulder(RUNTIME_ROOT, best, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, near2, near2_signatures, near2_uses, near2_successes, near2_capacity, NEAR_SIGNATURE_QUOTA, near_counters) ## i64
      z = ff7_add_known_7x7_rank247_shoulders(RUNTIME_ROOT, best, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, near1, near1_signatures, near1_uses, near1_successes, near1_capacity, NEAR_SIGNATURE_QUOTA, near_counters) ## i64
      z = ffps_add_profile_near_seeds(RUNTIME_ROOT, best, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, near1, near1_signatures, near1_uses, near1_successes, near1_capacity, near2, near2_signatures, near2_uses, near2_successes, near2_capacity, NEAR_SIGNATURE_QUOTA, near_counters) ## i64
    if ffn_state_is_c3(best, N, CAPACITY) == 1
      c3_base = ffn_clone_trusted(best, STATE_SIZE, 20003 + round * 47)
    z = ffn_add_c3_family(c3_base, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, symmetry, orbit_bank, polar_bank, SYMMETRY_CAP) ## i64
    if GPU == 1
      special_policy = 1 ## i64
      if GPU_POLICY == "single"
        special_policy = 0

      if c3_base != nil && ffp_gpu_weight(N, 2) > 0 && special_policy == 1 && gpu_disabled[2] == 0
        if gpu_c3_ready == 0
          gpu_c3_ready = ffc3_build(RUNTIME_ROOT, N, C3_BINARY)
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
        z = ffbp_near_add_scratch(near1, near1_signatures, near1_uses, near1_successes, demoted_frontiers[pi], near1_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters, near_signature_values, near_signature_counts, near_axis_signatures)
      if rr == final_rank + 2
        z = ffbp_near_add_scratch(near2, near2_signatures, near2_uses, near2_successes, demoted_frontiers[pi], near2_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters, near_signature_values, near_signature_counts, near_axis_signatures)
      pi += 1
    pi = 0
    while pi < preserved_shoulders.size()
      rr = ffw_best_rank(preserved_shoulders[pi]) ## i64
      if rr == final_rank + 1
        z = ffbp_near_add_scratch(near1, near1_signatures, near1_uses, near1_successes, preserved_shoulders[pi], near1_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters, near_signature_values, near_signature_counts, near_axis_signatures)
      if rr == final_rank + 2
        z = ffbp_near_add_scratch(near2, near2_signatures, near2_uses, near2_successes, preserved_shoulders[pi], near2_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters, near_signature_values, near_signature_counts, near_axis_signatures)
      pi += 1
    pi = 0
    while pi < old_archive.size()
      rr = ffw_best_rank(old_archive[pi]) ## i64
      if rr == final_rank
        z = ffn_archive_add(archive, old_archive[pi], ARCHIVE_CAP, 4, archive_counters)
      if rr == final_rank + 1
        z = ffbp_near_add_scratch(near1, near1_signatures, near1_uses, near1_successes, old_archive[pi], near1_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters, near_signature_values, near_signature_counts, near_axis_signatures)
      if rr == final_rank + 2
        z = ffbp_near_add_scratch(near2, near2_signatures, near2_uses, near2_successes, old_archive[pi], near2_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters, near_signature_values, near_signature_counts, near_axis_signatures)
      pi += 1
    archive_min_cache = ffn_archive_min_distance(archive)

    # Rebuild MAP into existing slots via reseed; drop old list only after
    # reseeding so we do not orphan every elite buffer on each rank drop.
    map_states.clear
    map_keys.clear
    map_uses.clear
    map_sources.clear
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
        z = ffme_add_copy(map_states, map_keys, map_uses, map_sources, map_pool[mi], final_rank, N, MAP_CAPACITY, map_source, STATE_SIZE, 20701 + map_source * 101 + mi)
        mi += 1
      map_source += 1

    if core_fringe_index >= 0
      # Reuse the island buffer; do not allocate a second STATE_SIZE and discard it.
      if ffn_core_fringe_state_into(states[core_fringe_index], best, archive, near1, near2, mixed, N, CAPACITY, 20501 + round * 47, DSLACK, CYCLES, cpu_work_moves[zones[core_fringe_index]], cpu_wander_moves[zones[core_fringe_index]], core_fringe_out_scratch) == 1
        core_fringe_slots = core_fringe_out_scratch[0]
        refreshed_core = states[core_fringe_index]
        active_near_seeds[core_fringe_index] = nil
        active_seed_ranks[core_fringe_index] = final_rank
        active_seed_start_moves[core_fringe_index] = 0
        active_seed_finished[core_fringe_index] = 1
        sources[core_fringe_index] = "core-fringe/frozen-" + core_fringe_slots.to_s()
        lineage_roles[core_fringe_index] = 0 - 1
        lineage_modes[core_fringe_index] = 0 - 1
        lineage_origin_ids[core_fringe_index] = ffbi_best_id(refreshed_core)
        lineage_start_ranks[core_fringe_index] = ffw_best_rank(refreshed_core)
        lineage_start_bits[core_fringe_index] = ffw_best_bits(refreshed_core)
        lineage_paid[core_fringe_index] = 0
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
        migrated_source = ffl_registry_find(best, lineage_registry_ids, lineage_registry_sources) ## i64
        if migrated_source < 0
          migrated_source = ffl_find_source(best, map_states, map_sources)
        lineage_roles[i] = ffl_source_role(migrated_source)
        lineage_modes[i] = ffl_source_pool_mode(migrated_source)
        lineage_origin_ids[i] = ffbi_best_id(best)
        lineage_start_ranks[i] = ffw_best_rank(best)
        lineage_start_bits[i] = ffw_best_bits(best)
        lineage_debts[i] = 0
        lineage_paid[i] = 0
        if i == cycle_watch_index
          cycle_stats[8] = 0
        last_seen_rank[i] = ffw_best_rank(states[i])
        last_seen_bits[i] = ffw_best_bits(states[i])
        last_moves[i] = ffw_moves(states[i])
        migrated = 1
      i += 1

    # Freeze the completed rank generation only after old same-rank archive
    # members have been re-admitted.  Dynamic plateau admissions cannot extend
    # this finite source_count*6*5 schedule; the next rank generation refreshes
    # the same high-water storage in place.
    frontier_escape_source_count = ffn_snapshot_archive_into(frontier_escape_sources, archive, ARCHIVE_CAP, STATE_SIZE, 21801 + round * 47)
    frontier_escape_completed_batches = 0

  # Expand one exact kind from one frozen frontier source per minute.  Source
  # rotates fastest, then kind, then nonce.  This bounds a 10-seed 7x7
  # generation to 300 independently gated calls and keeps the coordinator/TUI
  # stall near one candidate rather than the measured ~1.5s five-kind batch.
  frontier_escape_target_batches = fffeb_schedule_target(frontier_escape_source_count) ## i64
  if frontier_escape_source_count > 0 && frontier_escape_completed_batches < frontier_escape_target_batches && now_ms - frontier_escape_last_ms >= 60000
    z = fffeb_schedule_decode(frontier_escape_completed_batches, frontier_escape_source_count, frontier_escape_schedule) ## i64
    lazy_source_index = frontier_escape_schedule[0] ## i64
    lazy_kind = frontier_escape_schedule[1] ## i64
    lazy_nonce = frontier_escape_schedule[2] ## i64
    lazy_source = frontier_escape_sources[lazy_source_index]
    lazy_admitted = fffeb_append_source_kind_nonce(lazy_source, ffw_best_rank(best), lazy_source_index, lazy_kind, lazy_nonce, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander, near1, near1_signatures, near1_uses, near1_successes, near1_capacity, near2, near2_signatures, near2_uses, near2_successes, near2_capacity, NEAR_SIGNATURE_QUOTA, 2, near_counters, frontier_escape_counters) ## i64
    frontier_escape_completed_batches += 1
    frontier_escape_lazy_admissions += lazy_admitted
    if lazy_admitted > 0
      lazy_index = 0 ## i64
      while lazy_index < near1.size()
        z = ffme_add_copy(map_states, map_keys, map_uses, map_sources, near1[lazy_index], ffw_best_rank(best), N, MAP_CAPACITY, 1, STATE_SIZE, 29301 + round * 67 + lazy_index)
        lazy_index += 1
      lazy_index = 0
      while lazy_index < near2.size()
        z = ffme_add_copy(map_states, map_keys, map_uses, map_sources, near2[lazy_index], ffw_best_rank(best), N, MAP_CAPACITY, 2, STATE_SIZE, 29401 + round * 67 + lazy_index)
        lazy_index += 1
    frontier_escape_last_ms = now_ms

  # Low-cadence exact tunneling for the only square frontier on which the
  # complete elementary audit found genuine proper relations.  Recreate the
  # workspace only if a naive reset exceeds its high-water rank.  Ordinary rank
  # drops reuse the larger buffers under Tungsten's campaign-lifetime allocator.
  if ffpan_tunnel_due(N, now_ms, partial_auto_last_ms, 60000) == 1
    tunnel_rank = ffw_best_rank(best) ## i64
    if partial_auto_workspace_rank != tunnel_rank
      configured_rank = 0 ## i64
      if partial_auto_workspace != nil
        configured_rank = partial_auto_workspace.configure_rank(tunnel_rank)
      if configured_rank != tunnel_rank
        partial_auto_workspace = FFPANWorkspace.new(tunnel_rank, N, CAPACITY)
      partial_auto_workspace_rank = tunnel_rank
    partial_auto_last_ms = now_ms
    partial_auto_attempts += 1
    exported = ffw_export_best(best, partial_auto_us, partial_auto_vs, partial_auto_ws) ## i64
    if exported == tunnel_rank
      tunnel_found = ffpan_find_elementary_escape(partial_auto_us, partial_auto_vs, partial_auto_ws, tunnel_rank, N, CAPACITY, partial_auto_nonce, 5, partial_auto_workspace, partial_auto_out_u, partial_auto_out_v, partial_auto_out_w, partial_auto_meta) ## i64
      partial_auto_nonce = ffpan_next_nonce(N, partial_auto_nonce, 37)
      if tunnel_found == tunnel_rank && partial_auto_meta[6] == 1 && partial_auto_meta[15] == 0
        tunnel_loaded = ffw_init_terms_cap(partial_auto_state, partial_auto_out_u, partial_auto_out_v, partial_auto_out_w, tunnel_found, N, CAPACITY, 29001 + round * 61 + partial_auto_nonce, DSLACK, CYCLES, balanced_work, balanced_wander) ## i64
        if tunnel_loaded == tunnel_found && ffw_verify_best_exact(partial_auto_state, N) == 1
          partial_auto_hits += 1
          tunnel_admitted = ffn_archive_add_copy(archive, partial_auto_state, ARCHIVE_CAP, 4, archive_counters, STATE_SIZE, 29101 + round * 61 + partial_auto_nonce) ## i64
          if tunnel_admitted == 1
            partial_auto_admissions += 1
            archive_min_cache = ffn_archive_min_distance(archive)
            z = ffme_add_copy(map_states, map_keys, map_uses, map_sources, partial_auto_state, ffw_best_rank(best), N, MAP_CAPACITY, 0, STATE_SIZE, 29201 + round * 61 + partial_auto_nonce)

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
      if lineage_roles[i] >= 0
        if ffl_returned_to_origin(states[i], lineage_origin_ids[i]) == 1
          lineage_returns += 1
      if i == racer_index
        racer_spent = ffw_moves(states[i]) - racer_lease_start_moves ## i64
        racer_returned = 0 ## i64
        if ffbi_current_id(states[i]) == racer_lease_origin_id
          racer_returned = 1
        racer_drop = racer_lease_start_rank - ffw_best_rank(states[i]) ## i64
        if racer_drop < 0
          racer_drop = 0
        racer_density_gain = 0 ## i64
        if ffw_best_rank(states[i]) == racer_lease_start_rank && ffw_best_bits(states[i]) < racer_lease_start_bits
          racer_density_gain = racer_lease_start_bits - ffw_best_bits(states[i])
        z = ffcr_record_lease(racer_arm, racer_spent, racer_lease_novel, racer_returned, racer_drop, racer_density_gain, racer_pulls, racer_exposure, racer_novel, racer_returns, racer_drops, racer_density) ## i64
        racer_epoch += 1
        racer_arm = ffcr_select_arm(racer_epoch, racer_pulls, racer_exposure, racer_novel, racer_returns, racer_drops, racer_density)
      # Equal-density frontier states are algebraically exact but were not
      # personal bests, so sample the live state through a fresh exhaustive
      # gate before the lease is recycled.
      if ffw_current_rank(states[i]) == ffw_best_rank(best)
        current_distance = ffn_current_to_best_distance(states[i], best) ## i64
        if current_distance >= 4
          live_loaded = ffn_clone_current_exact_into(states[i], live_candidate_scratch, live_us_scratch, live_vs_scratch, live_ws_scratch, N, CAPACITY, 23001 + round * 53 + i, DSLACK, CYCLES, balanced_work, balanced_wander) ## i64
          if live_loaded > 0
            z = ffn_archive_add_copy(archive, live_candidate_scratch, ARCHIVE_CAP, 4, archive_counters, STATE_SIZE, 23051 + round * 53 + i)
            archive_min_cache = ffn_archive_min_distance(archive)
            live_source = doors[i] ## i64
            if lineage_roles[i] >= 0
              live_source = ffl_gpu_source(lineage_roles[i], lineage_modes[i])
            z = ffme_add_copy(map_states, map_keys, map_uses, map_sources, live_candidate_scratch, ffw_best_rank(best), N, MAP_CAPACITY, live_source, STATE_SIZE, 23101 + round * 53 + i)
            z = ffl_registry_add(lineage_registry_ids, lineage_registry_sources, live_candidate_scratch, live_source, LINEAGE_REGISTRY_CAPACITY)
      old_debt = active_seed_ranks[i] - ffw_best_rank(best) ## i64
      if old_debt > 0 && active_seed_finished[i] == 0
        spent = ffw_moves(states[i]) - active_seed_start_moves[i] ## i64
        z = ffrd_finish(old_debt, 0, spent, debt_returns, debt_failures, debt_exposure)
      native_seed = ffn_door_has_native_seed(doors[i], archive, near1, near2, symmetry, mixed)
      selected = ffn_pick_seed(doors[i], best, anchor, archive, near1, near2, near1_uses, near2_uses, symmetry, mixed, states, cursor, round * J + i)
      next_core_slots = core_fringe_slots ## i64
      core_rebuilt_in_place = 0 ## i64
      if i == core_fringe_index
        # Build into scratch then reseed the island slot — no orphaned STATE_SIZE.
        if ffn_core_fringe_state_into(live_candidate_scratch, best, archive, near1, near2, mixed, N, CAPACITY, 24001 + round * 53 + i, DSLACK, CYCLES, cpu_work_moves[zones[i]], cpu_wander_moves[zones[i]], core_fringe_out_scratch) == 1
          selected = live_candidate_scratch
          next_core_slots = core_fringe_out_scratch[0]
          core_rebuilt_in_place = 1
      active_near_seeds[i] = nil
      if seed_door_l == 2 && near1.size() > 0
        active_near_seeds[i] = selected
      if seed_door_l == 3 && near2.size() > 0
        active_near_seeds[i] = selected
      if seed_door_l == 4 && symmetry.size() > 0
        symmetry_cpu_uses += 1
      z = ffw_reseed_from(states[i], selected, 25001 + round * 53 + i)
      if core_rebuilt_in_place == 1 && z >= 1
        # selected was scratch; island now owns the rebuilt seed.
        selected = states[i]
      used_anchor_fallback = 0 ## i64
      if z < 1
        z = ffw_reseed_from(states[i], anchor, 27001 + round * 53 + i)
        active_near_seeds[i] = nil
        selected = anchor
        sources[i] = ffp_door_name(doors[i]) + "/anchor-fallback"
        used_anchor_fallback = 1
      if z >= 1 && native_seed != 0 && used_anchor_fallback == 0
        sources[i] = ffp_door_name(doors[i]) + "/seed" + (ffn_current_basin_id(selected) % 100000).to_s() + "/" + ffn_global_isotropy_tag(selected)
      if z >= 1 && native_seed == 0 && used_anchor_fallback == 0
        sources[i] = ffp_door_name(doors[i]) + "/leader-fallback"
      if z >= 1 && i == core_fringe_index
        core_fringe_slots = next_core_slots
        sources[i] = "core-fringe/frozen-" + core_fringe_slots.to_s()
      origin_source = ffl_registry_find(selected, lineage_registry_ids, lineage_registry_sources) ## i64
      if origin_source < 0
        origin_source = ffl_find_source(selected, map_states, map_sources)
      lineage_roles[i] = ffl_source_role(origin_source)
      lineage_modes[i] = ffl_source_pool_mode(origin_source)
      lineage_origin_ids[i] = ffbi_best_id(selected)
      lineage_start_ranks[i] = ffw_best_rank(selected)
      lineage_start_bits[i] = ffw_best_bits(selected)
      lineage_debts[i] = lineage_start_ranks[i] - ffw_best_rank(best)
      lineage_paid[i] = 0
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
      if i == racer_index
        z = ffcr_apply_arm(states[i], racer_arm, cpu_work_moves[zones[i]], cpu_wander_moves[zones[i]], racer_controls)
        racer_lease_start_moves = ffw_moves(states[i])
        racer_lease_start_rank = ffw_best_rank(states[i])
        racer_lease_start_bits = ffw_best_bits(states[i])
        racer_lease_origin_id = ffbi_current_id(states[i])
        racer_lease_novel = 0
        sources[i] = sources[i] + "/race-a" + racer_arm.to_s()
      if i == cycle_watch_index
        cycle_stats[8] = 0
        sources[i] = sources[i] + "/cycle-watch"
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
    while gpu_slot < 15
      if gpu_threads[gpu_slot] != nil
        gpu_all_done = 0
      gpu_slot += 1
    if gpu_all_done == 1
      gpu_generic_retry_attempted = 0 ## i64
      gpu_c3_retry_attempted = 0 ## i64
      gpu_simd_retry_attempted = 0 ## i64
      gpu_mitm_retry_attempted = 0 ## i64
      rect_component = 0 ## i64
      while rect_component < 2
        if rect_enabled != 0 && rect_states[rect_component] != nil && rect_ready[rect_component] == 0 && round >= rect_retry_round[rect_component]
          rect_n = ffn_rect_n(rect_component) ## i64
          rect_m = ffn_rect_m(rect_component) ## i64
          rect_p = ffn_rect_p(rect_component) ## i64
          rect_ready[rect_component] = ffrgb_build(RUNTIME_ROOT, rect_n, rect_m, rect_p, rect_binaries[rect_component])
          if rect_ready[rect_component] == 0
            rect_failures[rect_component] = rect_failures[rect_component] + 1
            rect_retry_round[rect_component] = round + ffn_gpu_retry_delay(rect_failures[rect_component])
        rect_component += 1
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
              gpu_generic_ready = ffb_build(RUNTIME_ROOT, N, GPU_BINARY)
            engine_ready = gpu_generic_ready
          if engine_kind == 1
            if gpu_c3_ready == 0 && wanted == 1 && gpu_c3_retry_attempted == 0
              gpu_c3_retry_attempted = 1
              gpu_c3_ready = ffc3_build(RUNTIME_ROOT, N, C3_BINARY)
            engine_ready = gpu_c3_ready
          if engine_kind == 2
            if gpu_simd_ready == 0 && wanted == 1 && gpu_simd_retry_attempted == 0
              gpu_simd_retry_attempted = 1
              gpu_simd_ready = ffsimd_build(RUNTIME_ROOT, N, SIMD_BINARY)
            engine_ready = gpu_simd_ready
          if engine_kind == 3
            if wanted == 1 && gpu_mitm_retry_attempted == 0
              gpu_mitm_retry_attempted = 1
              if gpu_mitm_ready == 0
                gpu_mitm_ready = ffm_build(RUNTIME_ROOT, MITM_BINARY)
              if gpu_constraint_ready == 0
                gpu_constraint_ready = ffpc_build(RUNTIME_ROOT, CONSTRAINT_BINARY)
              if gpu_kxor_ready == 0
                gpu_kxor_ready = ffx_build(RUNTIME_ROOT, KXOR_BINARY)
              if gpu_differential_ready == 0
                gpu_differential_ready = ffdb_build(RUNTIME_ROOT, DIFFERENTIAL_BINARY)
              if gpu_span_ready == 0
                gpu_span_ready = ffsrp_build(RUNTIME_ROOT, SPAN_BINARY)
              if N >= 5 && gpu_shear_ready == 0
                gpu_shear_ready = fflrsp_build(RUNTIME_ROOT, SHEAR_BINARY)
              if N == 4 && gpu_frozen_sat_ready == 0 && system("command -v cryptominisat5 >/dev/null 2>&1")
                gpu_frozen_sat_ready = fffsb_build(RUNTIME_ROOT, FROZEN_SAT_BINARY)
              if N == 5 && gpu_global_shear_ready == 0
                gpu_global_shear_ready = ffgksb_build(RUNTIME_ROOT, GLOBAL_SHEAR_BINARY)
              parent_pair_ready = ffn_has_parent_pair(map_states, archive, 12) ## i64
              gpu_pool_ready = ffn_fill_pool_readiness(pool_mode_ready, gpu_generic_ready, gpu_mitm_ready, gpu_constraint_ready, gpu_kxor_ready, gpu_differential_ready, gpu_span_ready, gpu_shear_ready, gpu_frozen_sat_ready, gpu_global_shear_ready, parent_pair_ready, orbit_bank, polar_bank)
            engine_ready = 0
            if gpu_pool_ready > 0 || rect_ready[0] != 0 || rect_ready[1] != 0
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
      if gpu_generic_ready == 1 || gpu_c3_ready == 1 || gpu_simd_ready == 1 || gpu_pool_ready > 0 || rect_ready[0] != 0 || rect_ready[1] != 0
        gpu_ready = 1
      parent_pair_ready = ffn_has_parent_pair(map_states, archive, 12) ## i64
      gpu_pool_ready = ffn_fill_pool_readiness(pool_mode_ready, gpu_generic_ready, gpu_mitm_ready, gpu_constraint_ready, gpu_kxor_ready, gpu_differential_ready, gpu_span_ready, gpu_shear_ready, gpu_frozen_sat_ready, gpu_global_shear_ready, parent_pair_ready, orbit_bank, polar_bank)
      pool_count = 0
      rect_ready_count = ff7_fill_rect_sched_ready(round, rect_ready, rect_retry_round, rect_sched_ready) ## i64
      if gpu_eligible[10] != 0
        pool_count = ffkp_select_group_modes_ready(pool_selection_epoch, N, ffw_best_rank(best), 0, GPU_WALKERS, pool_mode_ready, pool_last_modes, pool_pulls, pool_rewards, pool_modes)
      pool_full_budget = ffkp_lane_budget(GPU_WALKERS) ## i64
      rect_reserved = ff7_rect_pool_allocation(pool_full_budget, pool_selection_epoch, rect_sched_ready, rect_exposure, rect_rewards, rect_lanes) ## i64
      pool_remainder = pool_full_budget - rect_reserved ## i64
      pool_generic_budget = ff7_allocate_pool_remainder_for_tensor(N, GPU_WALKERS, pool_remainder, pool_modes, pool_count, pool_slot_lanes) ## i64
      pool_budget = pool_generic_budget + rect_reserved ## i64
      pool_selection_epoch += 1
      proposed_lanes = i64[11]
      contextual_exposure = i64[11]
      contextual_rewards = i64[11]
      z = ff7_fill_contextual_evidence(N, gpu_launch_debt, gpu_transition_exposure, gpu_transition_rewards, contextual_exposure, contextual_rewards) ## i64
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
      health_rect = 0 ## i64
      while health_rect < 2
        if rect_ready[health_rect] != 0 && rect_states[health_rect] != nil && round < rect_retry_round[health_rect]
          gpu_degraded = 1
        health_rect += 1
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
            gpu_launch_nonces[gpu_role] = gpu_launch_number[gpu_role]
            engine_kind = ffg_engine_kind(gpu_role) ## i64
            if engine_kind == 0
              gpu_threads[gpu_role] = ffn_gpu_launch(RUNTIME_ROOT, GPU_BINARY, RUN_TAG, N, gpu_role, gpu_lanes[gpu_role], GPU_STEPS, GPU_EPOCH_ROUNDS, gpu_seed, gpu_elapsed_ms, gpu_persistent_processes, gpu_persistent_active, gpu_persistent_generations, gpu_persistent_lanes)
            if engine_kind == 1
              gpu_threads[gpu_role] = ffn_gpu_launch_c3(RUNTIME_ROOT, C3_BINARY, RUN_TAG, N, gpu_lanes[gpu_role], gpu_seed, gpu_elapsed_ms)
            if engine_kind == 2
              gpu_threads[gpu_role] = ffn_gpu_launch_simd(RUNTIME_ROOT, SIMD_BINARY, RUN_TAG, N, gpu_lanes[gpu_role], gpu_seed, gpu_elapsed_ms)
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
          gpu_launch_nonces[gpu_slot] = pool_launch_number
          gpu_seed = ffn_pool_seed(pool_mode, pool_launch_number, best, map_states, map_uses, c3_base, orbit_bank, polar_bank, N, CAPACITY, STATE_SIZE, DSLACK, CYCLES, balanced_work, balanced_wander)
          gpu_companion = nil
          if pool_mode == 12 && gpu_seed != nil
            gpu_companion = ffn_parent_companion(gpu_seed, map_states, archive, 12)
            if gpu_companion == nil
              gpu_seed = ffn_parent_pair_primary(map_states, archive, 12)
              if gpu_seed != nil
                gpu_companion = ffn_parent_companion(gpu_seed, map_states, archive, 12)
          if gpu_seed != nil
            gpu_seed_rank = ffw_best_rank(gpu_seed) ## i64
            if pool_launched_count == 0 || gpu_seed_rank < gpu_seed_ranks[10]
              gpu_seed_ranks[10] = gpu_seed_rank
            gpu_launch_debt[gpu_slot] = gpu_seed_rank - ffw_best_rank(best)
            gpu_launch_lanes[gpu_slot] = pool_lanes
            gpu_elapsed_ms[gpu_slot] = 0
            gpu_launch_generation[gpu_slot] = fleet_generation
            gpu_threads[gpu_slot] = ffn_gpu_launch_pool(RUNTIME_ROOT, GPU_BINARY, MITM_BINARY, CONSTRAINT_BINARY, KXOR_BINARY, DIFFERENTIAL_BINARY, SPAN_BINARY, SHEAR_BINARY, FROZEN_SAT_BINARY, GLOBAL_SHEAR_BINARY, RUN_TAG, N, gpu_slot, pool_mode, pool_lanes, GPU_STEPS, GPU_EPOCH_ROUNDS, pool_launch_number, gpu_seed, gpu_companion, gpu_elapsed_ms)
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

      rect_launched_lanes = 0
      rect_launched_count = 0
      rect_component = 0
      while rect_component < 2
        rect_slot = 13 + rect_component ## i64
        component_lanes = rect_lanes[rect_component] ## i64
        rect_active[rect_component] = 0
        if component_lanes > 0 && rect_ready[rect_component] != 0 && rect_states[rect_component] != nil && round >= rect_retry_round[rect_component]
          gpu_launch_lanes[rect_slot] = component_lanes
          gpu_launch_debt[rect_slot] = 0
          rect_elapsed_ms[rect_component] = 0
          gpu_threads[rect_slot] = ffn_gpu_launch_rect(RUNTIME_ROOT, rect_binaries[rect_component], RUN_TAG, rect_component, component_lanes, GPU_STEPS, GPU_EPOCH_ROUNDS, rect_states[rect_component], rect_elapsed_ms, gpu_persistent_processes, gpu_persistent_active, gpu_persistent_generations, gpu_persistent_lanes)
          if gpu_threads[rect_slot] == nil
            rect_failures[rect_component] = rect_failures[rect_component] + 1
            rect_retry_round[rect_component] = round + ffn_gpu_retry_delay(rect_failures[rect_component])
          else
            rect_active[rect_component] = 1
            rect_launch_number[rect_component] = rect_launch_number[rect_component] + 1
            rect_launched_lanes += component_lanes
            rect_launched_count += 1
        rect_component += 1
      gpu_lanes[10] = pool_launched_lanes + rect_launched_lanes
      if gpu_eligible[10] != 0 && pool_budget > 0 && pool_launched_count + rect_launched_count == 0
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
    # Shoulder banks are in-RAM only without this path.  Dump every ~60s so a
    # kill -9 / spot reclaim still leaves the latest near1/near2 on disk.
    if NEAR_DIR != ""
      if last_near_dump_ms < 0 || now_ms - last_near_dump_ms >= 60000
        dumped = ffn_dump_near_dirs(near1, near2, NEAR_DIR, RUN_TAG) ## i64
        if dumped >= 0
          last_near_dump_ms = now_ms
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
      z = ffn_render(N, J, round, elapsed_s, total_moves, RECORD, RECORD_KNOWN, recovered, best, states, island_best_ranks, doors, zones, sources, last_rates, last_ages, cpu_work_moves, cpu_wander_moves, archive, ARCHIVE_CAP, near1, near1_capacity, near2, near2_capacity, symmetry, SYMMETRY_CAP, archive_counters, archive_min_cache, cohort_moves, cohort_drops, cohort_ties, cohort_near, timeline_times, timeline_ranks, timeline_count, elapsed_s - timeline_start_s, GPU, GPU_POLICY, gpu_degraded, gpu_lanes, gpu_candidates, gpu_rank_drops, gpu_density, gpu_rewards, gpu_lane_epochs, gpu_wall_ms, gpu_failures, gpu_disabled, gpu_retry_round, gpu_seed_ranks, gpu_pareto, gpu_pareto_archive, GPU_NOVELTY_CAP, gpu_pareto_counters, symmetry_cpu_uses, gpu_launch_number, pool_active_modes, pool_mode_ready, rect_enabled, rect_ready, rect_active, rect_lanes, rect_states, rect_archive_counts, rect_candidates, rect_rank_drops, rect_density, rect_rewards, rect_exposure, rect_failures, rect_retry_round, rect_composition_failures, last_status_ms, sequence, now_ms, rank_levels, rank_ticks, rank_level_count, bits_levels, bits_ticks, bits_level_count, new_bests, tie_bests, cycleouts, invalid_candidates, DSLACK, flash_text, flash_until_ms)
  if QUIET == 0 && TUI == 0
    round_wr = ffn_wr_status(ffw_best_rank(best), RECORD, RECORD_KNOWN)
    << "round=" + round.to_s() + " best=" + ffw_best_rank(best).to_s() + " bits=" + ffw_best_bits(best).to_s() + " WR=" + RECORD.to_s() + " wr=" + round_wr + " moves=" + total_moves.to_s() + " exact_bad=" + invalid_candidates.to_s() + " archive=" + archive.size().to_s() + " near1=" + near1.size().to_s() + " near2=" + near2.size().to_s()
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

# Stop workers only at a clean epoch boundary.  Every state is quiescent here,
# before GPU late-result adoption and final certificate persistence.
i = 0
while i < J
  cpu_start_channels[i].send(0)
  i += 1
i = 0
while i < J
  # CPU walkers return i64 move counts; discard without integer coercion of bools.
  z = ffn_thread_join_release(cpu_threads[i])
  i += 1

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
      late_pool_mode = 0 - 1 ## i64
      if gpu_slot >= 10
        late_pool_mode = pool_modes[gpu_slot - 10]
      # Bounded join returns plain i64 0/1 (never system() true).
      late_join_ok = ffn_thread_join_bounded(gpu_threads[gpu_slot], 5000) ## i64
      if late_join_ok == 0
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
      # Only parse a complete successful epoch.  A SIGINT mid-child often
      # leaves "" / partial output; loading that used to feed a boolean
      # success token into integer rank compares (expected int, got true).
      if late_join_ok == 1 && late_launch_is_current == 1 && ffn_scheme_file_nonempty(late_raw) == 1
        late_rank = ffw_load_scheme_cap(late, late_output_path, N, CAPACITY, 51001 + gpu_slot, DSLACK, CYCLES, balanced_work, balanced_wander) ## i64
      late_internal_target = ffw_best_rank(best) - 1 ## i64
      if late_rank <= 0 && late_join_ok == 1 && late_launch_is_current == 1
        repaired_rank = ffn_repair_gpu_internal_reject(RUN_TAG, N, gpu_slot, gpu_launch_nonces[gpu_slot], late_internal_target, CAPACITY, DSLACK, CYCLES, balanced_work, balanced_wander, late) ## i64
        if repaired_rank > 0
          late_rank = repaired_rank
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
      if late_rank <= 0 && late_join_ok == 1 && late_launch_is_current == 1
        if ffn_scheme_file_nonempty(late_raw) == 1
          invalid_candidates += 1
      gpu_internal_rejects = ffn_harvest_gpu_internal_reject(RUN_TAG, N, gpu_slot, gpu_role, late_pool_mode, gpu_launch_nonces[gpu_slot], late_internal_target, CAPACITY, DSLACK, CYCLES, balanced_work, balanced_wander, gpu_internal_rejects, late) ## i64
      if gpu_slot >= 10
        late_pool_slot = gpu_slot - 10 ## i64
        late_pool_mode = pool_modes[late_pool_slot] ## i64
        if late_pool_mode >= 0
          pool_active_modes[late_pool_mode] = 0
        pool_modes[late_pool_slot] = 0 - 1
    gpu_slot += 1

  # Rectangular children use different state dimensions and therefore cannot
  # pass through the square late-result loader above.  Drain both explicitly,
  # preserve any exact component improvement, and recompose/exact-gate 7x7 so
  # a last-epoch world-record candidate is never lost at shutdown.
  rect_component = 0
  while rect_component < 2
    rect_slot = 13 + rect_component ## i64
    if gpu_threads[rect_slot] != nil
      late_rect_join_ok = ffn_thread_join_bounded(gpu_threads[rect_slot], 5000) ## i64
      gpu_threads[rect_slot] = nil
      rect_active[rect_component] = 0
      if late_rect_join_ok == 0
        rect_failures[rect_component] = rect_failures[rect_component] + 1
      late_rect_path = ffn_rect_output_path(RUN_TAG, rect_component)
      late_rect_raw = read_file(late_rect_path)
      late_rect = i64[ffr_state_size(rect_capacities[rect_component])]
      late_rect_rank = 0 - 1 ## i64
      if late_rect_join_ok == 1 && ffn_scheme_file_nonempty(late_rect_raw) == 1
        late_rect_rank = ffr_load_scheme_cap(late_rect, late_rect_path, ffn_rect_n(rect_component), ffn_rect_m(rect_component), ffn_rect_p(rect_component), rect_capacities[rect_component], 71003 + rect_component, DSLACK, CYCLES, balanced_work, balanced_wander) ## i64
      if late_rect_rank > 0 && rect_states[rect_component] != nil
        late_rect_bits = ffr_best_bits(late_rect) ## i64
        old_rect_rank = ffr_best_rank(rect_states[rect_component]) ## i64
        old_rect_bits = ffr_best_bits(rect_states[rect_component]) ## i64
        if ffn_better(late_rect_rank, late_rect_bits, old_rect_rank, old_rect_bits) == 1
          checkpoint_rank = ffn_dump_rect_atomic(late_rect, rect_checkpoint_paths[rect_component], RUN_TAG, rect_component) ## i64
          if checkpoint_rank > 0
            rect_states[rect_component] = late_rect
            if rect_component == 0 && rect_archive_334.size() < 16
              rect_archive_334.push(late_rect)
              rect_archive_counts[0] = rect_archive_334.size()
            if rect_component == 1 && rect_archive_344.size() < 16
              rect_archive_344.push(late_rect)
              rect_archive_counts[1] = rect_archive_344.size()
            rect_composition_dirty = 1
            rect_last_improved = rect_component
          if checkpoint_rank <= 0
            rect_failures[rect_component] = rect_failures[rect_component] + 1
      if late_rect_rank <= 0 && late_rect_join_ok == 1
        if ffn_scheme_file_nonempty(late_rect_raw) == 1
          invalid_candidates += 1
      late_rect_n = ffn_rect_n(rect_component) ## i64
      late_rect_m = ffn_rect_m(rect_component) ## i64
      late_rect_p = ffn_rect_p(rect_component) ## i64
      late_rect_target = 0 ## i64
      if rect_states[rect_component] != nil
        late_rect_target = ffr_best_rank(rect_states[rect_component]) - 1
      late_rect_nonce = rect_launch_number[rect_component] - 1 ## i64
      if late_rect_nonce < 0
        late_rect_nonce = 0
      rect_internal_rejects = ffrgr_harvest(late_rect_path, ffn_rect_seed_path(RUN_TAG, rect_component), RUN_TAG, late_rect_n, late_rect_m, late_rect_p, rect_slot, 10, 0 - 1, late_rect_nonce, late_rect_target, rect_capacities[rect_component], DSLACK, CYCLES, balanced_work, balanced_wander, rect_internal_rejects, rect_reject_scratch[rect_component], rect_reject_status)
      if rect_reject_status[0] != 0
        invalid_candidates += 1
        rect_failures[rect_component] = rect_failures[rect_component] + 1
        gpu_failures[10] = gpu_failures[10] + 1
        gpu_degraded = 1
      cleared = write_file(late_rect_path, "")
      if cleared == false
        rect_failures[rect_component] = rect_failures[rect_component] + 1
    rect_component += 1

  # Generic and rectangular cal2zone controllers return after each mailbox
  # acknowledgement; their Metal-owning child processes deliberately remain
  # alive between epochs. Stop and reap them only after every final result has
  # passed the ordinary late exact gate above.
  persistent_slot = 0 ## i64
  while persistent_slot < 15
    if gpu_persistent_active[persistent_slot] != 0
      stopped = ffn_persistent_stop_slot(RUN_TAG, persistent_slot, gpu_persistent_processes, gpu_persistent_active, gpu_persistent_generations, gpu_persistent_lanes) ## i64
      if stopped == 0
        gpu_degraded = 1
    persistent_slot += 1

  if rect_composition_dirty != 0 && rect_states[0] != nil && rect_states[1] != nil
    compose_source = rect_last_improved ## i64
    if compose_source < 0
      compose_source = 0
    rect_composition_attempts += 1
    late_composed_path = ffn_rect_composed_path(RUN_TAG, compose_source, rect_composition_attempts)
    component_444_path = RUNTIME_ROOT + "/seeds/gf2/matmul_4x4_rank47_d450_gf2.txt"
    late_composed_rank = ffsc_compose_files(component_444_path, rect_checkpoint_paths[0], rect_checkpoint_paths[1], late_composed_path, 0) ## i64
    late_composed_loaded = 0 - 1 ## i64
    late_composed = i64[STATE_SIZE]
    if late_composed_rank > 0
      late_composed_loaded = ffw_load_scheme_cap(late_composed, late_composed_path, 7, CAPACITY, 72007 + compose_source, DSLACK, CYCLES, balanced_work, balanced_wander) ## i64
    if late_composed_loaded > 0
      rect_composition_dirty = 0
      if ffn_better(late_composed_loaded, ffw_best_bits(late_composed), ffw_best_rank(best), ffw_best_bits(best)) == 1
        if late_composed_loaded < ffw_best_rank(best)
          new_bests += 1
        if late_composed_loaded == ffw_best_rank(best)
          tie_bests += 1
        best = late_composed
    if late_composed_loaded <= 0
      rect_composition_failures += 1
      invalid_candidates += 1

final_ms = ccall("__w_clock_ms") ## i64
final_s = (final_ms - start_ms) / 1000 ## i64
final_write_failed = 0 ## i64
# Every adoption path is already exact-gated, but make the durable handoff a
# proof boundary of its own. A would-be record is never written or reported as
# exact merely because an earlier in-memory invariant was expected to hold.
final_exact = ffw_verify_best_exact(best, N) ## i64
if final_exact != 1
  gpu_degraded = 1
  final_write_failed = 1
  invalid_candidates += 1
if final_exact == 1
  dumped = ffn_dump_trusted(best, BEST_PATH, RUN_TAG) ## i64
  if dumped < 1
    gpu_degraded = 1
    final_write_failed = 1
if NEAR_DIR != ""
  final_near = ffn_dump_near_dirs(near1, near2, NEAR_DIR, RUN_TAG) ## i64
  if final_near < 0
    gpu_degraded = 1
    final_write_failed = 1
  if QUIET == 0
    << "metaflip near dump: dir=" + NEAR_DIR + " near1=" + near1.size().to_s() + " near2=" + near2.size().to_s() + " written=" + final_near.to_s()
    flush()
final_state = "DONE"
if final_write_failed != 0
  final_state = "FAILED"
status_ok = ffn_status(STATUS_PATH, RUN_TAG, final_state, final_ms, sequence + 1, N, RECORD, RECORD_KNOWN, best, total_moves, final_s, archive, near1, near2, symmetry, GPU, gpu_degraded) ## i64
if status_ok == 0
  final_write_failed = 1
final_wr = ffn_wr_status(ffw_best_rank(best), RECORD, RECORD_KNOWN)
if TUI == 1
  << ""
  if final_write_failed == 0
    << "DONE best rank " + ffw_best_rank(best).to_s() + " density " + ffw_best_bits(best).to_s() + " exact=1 WR=" + RECORD.to_s() + " " + final_wr
  if final_write_failed != 0
    << "FAILED to persist final exact certificate/status"
if TUI == 0
  if final_write_failed == 0
    << "metaflip native done: tensor=" + N.to_s() + "x" + N.to_s() + " best=" + ffw_best_rank(best).to_s() + " bits=" + ffw_best_bits(best).to_s() + " WR=" + RECORD.to_s() + " wr=" + final_wr + " moves=" + total_moves.to_s() + " rank-drops=" + new_bests.to_s() + " density-ties=" + tie_bests.to_s() + " exact-rejects=" + invalid_candidates.to_s() + " internal-rejects=" + (gpu_internal_rejects + rect_internal_rejects).to_s() + " rect-internal-rejects=" + rect_internal_rejects.to_s() + " gliso=" + global_isotropy_counters[1].to_s() + "/" + global_isotropy_counters[2].to_s() + ":" + global_isotropy_counters[3].to_s()
  if final_write_failed != 0
    << "metaflip native: FAILED to persist final exact certificate/status"
flush()
if final_write_failed != 0
  exit(1)

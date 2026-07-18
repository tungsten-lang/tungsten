# Exact-gated decision audit for live 7x7 partial-automorphism scheduling.
#
# The production tunnel visits a frozen frontier source on every call.  This
# benchmark compares that policy with two cheap stateful alternatives:
#
#   chain: feed every exact endpoint into the next call;
#   map-walk: retain one exact state per canonical structural bucket and
#             expand the least-used bucket next. Modes 2 and 4 compare a
#             wider 61-way structural quotient with production's 23-way key.
#
# A fourth arm runs short A/B/A/B generator words.  The elementary finder is
# state-resolved, so these are not algebraically trivial XORs of two fixed
# zero relations: the subset relation is recomputed after each prefix.  Every
# endpoint still receives the ordinary full 7^6 reconstruction gate.
#
# This is a report, not a pass/fail policy test.  It deliberately lives outside
# the coordinator until continuation or objective evidence justifies a live
# CPU-side sequence lane.

use ../lib/metaflip/fleet/seven_by_seven
use ../lib/metaflip/strategies/partial_automorphism_nullspace

-> ffpasa_unique(values, value)
  i = 0 ## i64
  while i < values.size()
    if values[i] == value
      return 0
    i += 1
  values.push(value)
  1

-> ffpasa_key_unique(values, value)
  ffpasa_unique(values, value)

-> ffpasa_structural_key(state, frontier_rank, n, modulus) (i64[] i64 i64 i64) i64
  rank = ffw_best_rank(state) ## i64
  debt = rank - frontier_rank ## i64
  if debt < 0
    debt = 0
  if debt > 3
    debt = 3
  bits_per_term = 0 ## i64
  if rank > 0
    bits_per_term = ffw_best_bits(state) / rank
  density_bin = bits_per_term / 3 ## i64
  if density_bin > 31
    density_bin = 31
  pairs = ffbp_flip_pairs(state) ## i64
  connectivity_bin = 0 ## i64
  if rank > 0
    connectivity_bin = pairs / rank
  if connectivity_bin > 31
    connectivity_bin = 31
  symmetry = ffbi_state_is_c3(state, n, 0) ## i64
  structure = ffbi_best_id(state) % modulus ## i64
  if structure < 0
    structure += modulus
  debt * 1000000 + symmetry * 500000 + density_bin * 10000 + connectivity_bin * 100 + structure

-> ffpasa_find_key(keys, key) (i64[] i64) i64
  i = 0 ## i64
  while i < keys.size()
    if keys[i] == key
      return i
    i += 1
  0 - 1

# MAP-shaped storage with a wider structural quotient.  Existing-key
# replacement follows production MAP-Elites exactly; capacity is intentionally
# bounded at 64 so this changes diversity, not memory policy.
-> ffpasa_map_add(states, keys, uses, candidate, frontier_rank, n, modulus, capacity, state_size, seed)
  key = ffpasa_structural_key(candidate, frontier_rank, n, modulus) ## i64
  existing = ffpasa_find_key(keys, key) ## i64
  if existing >= 0
    better = 0 ## i64
    if ffw_best_rank(candidate) < ffw_best_rank(states[existing])
      better = 1
    if ffw_best_rank(candidate) == ffw_best_rank(states[existing])
      if ffw_best_bits(candidate) < ffw_best_bits(states[existing])
        better = 1
      if ffw_best_bits(candidate) == ffw_best_bits(states[existing])
        if ffbp_flip_pairs(candidate) > ffbp_flip_pairs(states[existing])
          better = 1
    if better == 0
      return 0
    loaded = ffw_reseed_from(states[existing], candidate, seed) ## i64
    if loaded < 1
      return 0
    uses[existing] = 0
    return 2
  if states.size() >= capacity
    return 0
  stored = i64[state_size]
  loaded = ffw_reseed_from(stored, candidate, seed) ## i64
  if loaded < 1
    return 0
  states.push(stored)
  keys.push(key)
  uses.push(0)
  1

-> ffpasa_select(states, uses, epoch)
  if states.size() < 1
    return 0 - 1
  start = epoch % states.size() ## i64
  best = start ## i64
  offset = 1 ## i64
  while offset < states.size()
    index = (start + offset) % states.size() ## i64
    if uses[index] < uses[best]
      best = index
    offset += 1
  uses[best] += 1
  best

-> ffpasa_generator_match(requested, meta, n, decoded) (i64 i64[] i64 i64[]) i64
  if ffpan_elementary_decode(n, requested, decoded) != 1
    return 0
  if decoded[0] == meta[8] && decoded[1] == meta[9] && decoded[2] == meta[10] && decoded[3] == meta[11]
    return 1
  0

-> ffpasa_ring_distance(states)
  if states.size() < 2
    return 0 - 1
  minimum = 1 << 30 ## i64
  i = 0 ## i64
  while i < states.size()
    j = (i + 1) % states.size() ## i64
    distance = ffn_distance(states[i], states[j]) ## i64
    if distance < minimum
      minimum = distance
    i += 1
  minimum

# mode: 0 frozen source, 1 rolling chain, 2 61-bucket MAP walk,
#       3 short state-resolved A/B/A/B words, 4 production MAP walk.
-> ffpasa_run(label, root, mode, attempts, capacity, state_size) (String i64[] i64 i64 i64 i64) i64
  rank = ffw_best_rank(root) ## i64
  n = 7 ## i64
  total = ffpan_elementary_count(n) ## i64
  root_density = ffw_best_bits(root) ## i64
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  meta = i64[18]
  decoded = i64[4]
  endpoint = i64[state_size]
  workspace = FFPANWorkspace.new(rank, n, capacity)

  current = i64[state_size]
  z = ffw_reseed_from(current, root, 88001 + mode * 1009) ## i64
  map_states = []
  map_keys = []
  map_uses = []
  if mode == 2
    z = ffpasa_map_add(map_states, map_keys, map_uses, root, rank, n, 61, 64, state_size, 88101 + mode * 1009)
  production_map_states = []
  production_map_keys = []
  production_map_uses = []
  production_map_sources = []
  if mode == 4
    z = ffme_add_copy(production_map_states, production_map_keys, production_map_uses, production_map_sources, root, rank, n, 64, 0, state_size, 88151 + mode * 1009)

  ids = []
  keys23 = []
  keys61 = []
  hits = 0 ## i64
  exact = 0 ## i64
  rank_drops = 0 ## i64
  density_wins = 0 ## i64
  best_rank = rank ## i64
  best_density = root_density ## i64
  max_root_distance = 0 ## i64
  requested_generator_hits = 0 ## i64
  map_admits = 0 ## i64
  map_replaces = 0 ## i64
  failures = 0 ## i64
  sequence_finals = 0 ## i64
  sequence_final_unique = []
  started = ccall_nobox("__w_clock_ns_raw") ## i64
  attempt = 0 ## i64
  while attempt < attempts
    source = root
    if mode == 1 || mode == 3
      source = current
    if mode == 2
      selected = ffpasa_select(map_states, map_uses, attempt) ## i64
      if selected >= 0
        source = map_states[selected]
    if mode == 4
      selected = ffme_select(production_map_states, production_map_uses, attempt) ## i64
      if selected >= 0
        source = production_map_states[selected]
    if mode == 3 && attempt % 4 == 0
      z = ffw_reseed_from(current, root, 88201 + attempt)
      source = current

    exported = ffw_export_best(source, source_u, source_v, source_w) ## i64
    requested = (attempt * 37) % total ## i64
    if mode == 3
      block = attempt / 4 ## i64
      a = (block * 37) % total ## i64
      b = (a + 61 + (block % 7)) % total ## i64
      requested = a
      if attempt % 4 == 1 || attempt % 4 == 3
        requested = b
    found = 0 ## i64
    if exported == rank
      found = ffpan_find_elementary_escape(source_u, source_v, source_w, rank, n, capacity, requested, 5, workspace, out_u, out_v, out_w, meta)
    if found > 0 && found <= capacity && meta[6] == 1 && meta[15] == 0
      loaded = ffw_init_terms_cap(endpoint, out_u, out_v, out_w, found, n, capacity, 88301 + mode * 100000 + attempt, 0, 1, 1, 1) ## i64
      if loaded == found && ffw_verify_best_exact(endpoint, n) == 1
        hits += 1
        exact += 1
        requested_generator_hits += ffpasa_generator_match(requested, meta, n, decoded)
        identity = ffbi_best_id(endpoint) ## i64
        z = ffpasa_unique(ids, identity)
        z = ffpasa_key_unique(keys23, ffme_descriptor(endpoint, rank, n))
        z = ffpasa_key_unique(keys61, ffpasa_structural_key(endpoint, rank, n, 61))
        endpoint_rank = ffw_best_rank(endpoint) ## i64
        endpoint_density = ffw_best_bits(endpoint) ## i64
        if endpoint_rank < rank
          rank_drops += 1
        if endpoint_rank < best_rank || (endpoint_rank == best_rank && endpoint_density < best_density)
          best_rank = endpoint_rank
          best_density = endpoint_density
        if endpoint_rank == rank && endpoint_density < root_density
          density_wins += 1
        if endpoint_rank == rank
          distance = ffn_distance(root, endpoint) ## i64
          if distance > max_root_distance
            max_root_distance = distance
          if mode == 2
            action = ffpasa_map_add(map_states, map_keys, map_uses, endpoint, rank, n, 61, 64, state_size, 88401 + mode * 100000 + attempt) ## i64
            if action == 1
              map_admits += 1
            if action == 2
              map_replaces += 1
          if mode == 4
            z = ffme_add_copy(production_map_states, production_map_keys, production_map_uses, production_map_sources, endpoint, rank, n, 64, 0, state_size, 88451 + mode * 100000 + attempt)
        if mode == 1 || mode == 3
          z = ffw_reseed_from(current, endpoint, 88501 + mode * 100000 + attempt)
        if mode == 3 && attempt % 4 == 3
          sequence_finals += 1
          z = ffpasa_unique(sequence_final_unique, identity)
      else
        failures += 1
    else
      failures += 1
    attempt += 1
  elapsed_ns = ccall_nobox("__w_clock_ns_raw") - started ## i64
  ring_min = 0 - 1 ## i64
  if mode == 2
    ring_min = ffpasa_ring_distance(map_states)
  if mode == 4
    ring_min = ffpasa_ring_distance(production_map_states)
  << "PARTIAL_SEQUENCE label=" + label + " mode=" + mode.to_s() + " attempts=" + attempts.to_s() + " hits=" + hits.to_s() + " exact=" + exact.to_s() + " unique=" + ids.size().to_s() + " key23=" + keys23.size().to_s() + " key61=" + keys61.size().to_s() + " map23=" + production_map_states.size().to_s() + " map61=" + map_states.size().to_s() + " admits61=" + map_admits.to_s() + " replaces61=" + map_replaces.to_s() + " generator_match=" + requested_generator_hits.to_s() + " drops=" + rank_drops.to_s() + " density_wins=" + density_wins.to_s() + " best=" + best_rank.to_s() + "/" + best_density.to_s() + " max_root_distance=" + max_root_distance.to_s() + " ring_min61=" + ring_min.to_s() + " finals=" + sequence_finals.to_s() + " final_unique=" + sequence_final_unique.size().to_s() + " failures=" + failures.to_s() + " elapsed_ns=" + elapsed_ns.to_s()
  rank_drops

# Pick the lowest-density, then farthest, exact endpoint from one scheduling
# arm. Mode 0 is frozen, 1 is a rolling chain, and 2 is production-MAP-fed.
# stats: hits, exact, chosen density, chosen root distance, failures.
-> ffpasa_pick_door(root, mode, attempts, capacity, state_size, output, stats) (i64[] i64 i64 i64 i64 i64[] i64[]) i64
  rank = ffw_best_rank(root) ## i64
  n = 7 ## i64
  total = ffpan_elementary_count(n) ## i64
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  meta = i64[18]
  endpoint = i64[state_size]
  current = i64[state_size]
  z = ffw_reseed_from(current, root, 90001 + mode * 1009) ## i64
  map_states = []
  map_keys = []
  map_uses = []
  map_sources = []
  if mode == 2
    z = ffme_add_copy(map_states, map_keys, map_uses, map_sources, root, rank, n, 64, 0, state_size, 90101 + mode * 1009)
  workspace = FFPANWorkspace.new(rank, n, capacity)
  i = 0 ## i64
  while i < stats.size()
    stats[i] = 0
    i += 1
  stats[2] = 1 << 30
  stats[3] = 0 - 1
  attempt = 0 ## i64
  while attempt < attempts
    source = root
    if mode == 1
      source = current
    if mode == 2
      selected = ffme_select(map_states, map_uses, attempt) ## i64
      if selected >= 0
        source = map_states[selected]
    exported = ffw_export_best(source, source_u, source_v, source_w) ## i64
    found = 0 ## i64
    if exported == rank
      found = ffpan_find_elementary_escape(source_u, source_v, source_w, rank, n, capacity, (attempt * 37) % total, 5, workspace, out_u, out_v, out_w, meta)
    if found == rank && meta[6] == 1 && meta[15] == 0
      loaded = ffw_init_terms_cap(endpoint, out_u, out_v, out_w, found, n, capacity, 90201 + mode * 100000 + attempt, 0, 1, 1, 1) ## i64
      if loaded == rank && ffw_verify_best_exact(endpoint, n) == 1
        stats[0] += 1
        stats[1] += 1
        density = ffw_best_bits(endpoint) ## i64
        distance = ffn_distance(root, endpoint) ## i64
        if density < stats[2] || (density == stats[2] && distance > stats[3])
          stats[2] = density
          stats[3] = distance
          z = ffw_reseed_from(output, endpoint, 90301 + mode * 100000 + attempt)
        if mode == 2
          z = ffme_add_copy(map_states, map_keys, map_uses, map_sources, endpoint, rank, n, 64, 0, state_size, 90401 + mode * 100000 + attempt)
        if mode == 1
          z = ffw_reseed_from(current, endpoint, 90501 + mode * 100000 + attempt)
      else
        stats[4] += 1
    else
      stats[4] += 1
    attempt += 1
  if stats[1] < 1 || ffw_best_rank(output) != rank || ffw_verify_best_exact(output, n) != 1
    return 0
  rank

-> ffpasa_better(rank_a, bits_a, rank_b, bits_b) (i64 i64 i64 i64) i64
  if rank_a < rank_b
    return 1
  if rank_a == rank_b && bits_a < bits_b
    return 1
  0

# Matched ordinary-walker continuation from the root, a one-step frozen door,
# a rolling-chain door, and a production-MAP-fed door. All four arms receive
# identical RNG seeds and stay in the work zone for the bounded tranche.
-> ffpasa_continue(label, roots, moves, trials, capacity, state_size)
  arm_count = roots.size() ## i64
  names = ["root", "frozen", "chain", "map23"]
  best_ranks = i64[arm_count]
  best_bits = i64[arm_count]
  density_sum = i64[arm_count]
  accepted_sum = i64[arm_count]
  drops = i64[arm_count]
  wins = i64[arm_count]
  exact = i64[arm_count]
  states = []
  trial_ranks = i64[arm_count]
  trial_bits = i64[arm_count]
  arm = 0 ## i64
  while arm < arm_count
    best_ranks[arm] = 1 << 30
    best_bits[arm] = 1 << 30
    states.push(i64[state_size])
    arm += 1
  started = ccall_nobox("__w_clock_ns_raw") ## i64
  trial = 0 ## i64
  while trial < trials
    arm = 0
    while arm < arm_count
      state = states[arm]
      loaded = ffw_reseed_from(state, roots[arm], 91001 + trial * 1009) ## i64
      if loaded != 247
        << "PARTIAL_CONTINUE_FAIL clone label=" + label + " arm=" + arm.to_s()
        exit(1)
      z = ffw_set_zone_quotas(state, 1000000000, 200000000) ## i64
      walked = ffw_walk(state, moves) ## i64
      if walked < 1 || ffw_verify_current_exact(state, 7) != 1
        << "PARTIAL_CONTINUE_FAIL exact label=" + label + " arm=" + arm.to_s()
        exit(1)
      exact[arm] += 1
      trial_ranks[arm] = ffw_best_rank(state)
      trial_bits[arm] = ffw_best_bits(state)
      density_sum[arm] += trial_bits[arm]
      accepted_sum[arm] += ffw_accepted(state)
      if trial_ranks[arm] < 247
        drops[arm] += 1
      if trial_ranks[arm] < best_ranks[arm] || (trial_ranks[arm] == best_ranks[arm] && trial_bits[arm] < best_bits[arm])
        best_ranks[arm] = trial_ranks[arm]
        best_bits[arm] = trial_bits[arm]
      arm += 1
    arm = 0
    while arm < arm_count
      winner = 1 ## i64
      other = 0 ## i64
      while other < arm_count
        if other != arm
          if ffpasa_better(trial_ranks[arm], trial_bits[arm], trial_ranks[other], trial_bits[other]) == 0
            winner = 0
        other += 1
      if winner == 1
        wins[arm] += 1
      arm += 1
    trial += 1
  elapsed_ns = ccall_nobox("__w_clock_ns_raw") - started ## i64
  arm = 0
  while arm < arm_count
    << "PARTIAL_CONTINUE label=" + label + " arm=" + names[arm] + " trials=" + trials.to_s() + " moves=" + moves.to_s() + " exact=" + exact[arm].to_s() + " drops=" + drops[arm].to_s() + " wins=" + wins[arm].to_s() + " best=" + best_ranks[arm].to_s() + "/" + best_bits[arm].to_s() + " mean_density=" + (density_sum[arm] / trials).to_s() + " accepted=" + accepted_sum[arm].to_s() + " elapsed_all_ns=" + elapsed_ns.to_s()
    arm += 1
  1

root_dir = __DIR__ + "/../lib/metaflip/seeds/gf2/"
paths = ["matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt",
         "matmul_7x7_rank247_d3098_global_isotropy_gf2.txt"]
labels = ["d3096", "d3098"]
capacity = 320 ## i64
state_size = ffw_state_size(capacity) ## i64
attempts = 189 ## i64
# Continuation is opt-in: four simultaneous 7x7 walker states retain roughly
# one gigabyte on the reference host. Exact tunnel generation itself is cheap.
continuation_moves = 0 ## i64
continuation_trials = 4 ## i64
av = argv()
if av.size() > 0
  attempts = av[0].to_i()
if av.size() > 1
  continuation_moves = av[1].to_i()
if av.size() > 2
  continuation_trials = av[2].to_i()
if attempts < 4
  attempts = 4
if continuation_moves < 0
  continuation_moves = 0
if continuation_trials < 1
  continuation_trials = 1

total_drops = 0 ## i64
i = 0 ## i64
while i < paths.size()
  root = i64[state_size]
  loaded = ffw_load_scheme_cap(root, root_dir + paths[i], 7, capacity, 89001 + i, 0, 1, 1, 1) ## i64
  if loaded != 247 || ffw_verify_best_exact(root, 7) != 1
    << "PARTIAL_SEQUENCE_FAIL load=" + paths[i]
    exit(1)
  mode = 0 ## i64
  while mode < 5
    total_drops += ffpasa_run(labels[i], root, mode, attempts, capacity, state_size)
    mode += 1
  if continuation_moves > 0
    continuation_roots = []
    continuation_roots.push(root)
    pick_mode = 0 ## i64
    while pick_mode < 3
      door = i64[state_size]
      pick_stats = i64[5]
      picked = ffpasa_pick_door(root, pick_mode, attempts, capacity, state_size, door, pick_stats) ## i64
      if picked != 247
        << "PARTIAL_SEQUENCE_FAIL door mode=" + pick_mode.to_s()
        exit(1)
      << "PARTIAL_DOOR label=" + labels[i] + " mode=" + pick_mode.to_s() + " density=" + pick_stats[2].to_s() + " distance=" + pick_stats[3].to_s() + " exact=" + pick_stats[1].to_s() + " failures=" + pick_stats[4].to_s()
      continuation_roots.push(door)
      pick_mode += 1
    z = ffpasa_continue(labels[i], continuation_roots, continuation_moves, continuation_trials, capacity, state_size)
  i += 1

<< "PASS partial-automorphism sequence audit rank_drops=" + total_drops.to_s()

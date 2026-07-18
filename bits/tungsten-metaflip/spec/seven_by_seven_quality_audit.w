use ../lib/metaflip/fleet/archive
use ../lib/metaflip/fleet/map_elites
use ../lib/metaflip/fleet/frontier
use ../lib/metaflip/fleet/seven_by_seven
use ../lib/metaflip/seeds/catalog
use ../lib/metaflip/strategies/partial_automorphism_nullspace

# Diagnostic audit for the curated 7x7 frontier. This is intentionally a
# report rather than a pass/fail regression: it makes archive/MAP collisions
# and partial-automorphism endpoint coverage measurable while campaign policy
# is being tuned.

root = __DIR__ + "/../lib/metaflip/"
paths = ffp_frontier_seed_paths(7)
capacity = 320 ## i64
state_size = ffw_state_size(capacity) ## i64
states = []
names = []

i = 0 ## i64
while i < paths.size()
  state = i64[state_size]
  loaded = ffw_load_scheme_cap(state, root + paths[i], 7, capacity, 71001 + i, 0, 1, 1, 1) ## i64
  if loaded != 247 || ffw_verify_best_exact(state, 7) != 1
    << "FAIL 7x7 quality audit load " + paths[i]
    exit(1)
  states.push(state)
  names.push(paths[i])
  i += 1

# Reproduce coordinator archive construction, including the initial clone of
# the explicit anchor followed by every catalog frontier in catalog order.
archive = []
archive_names = []
archive_counters = i64[3]
anchor = i64[state_size]
z = ffw_reseed_from(anchor, states[0], 17) ## i64
archive.push(anchor)
archive_names.push("anchor")
i = 0
while i < states.size()
  action = ffn_archive_admission_action(archive, states[i], 16, 4) ## i64
  changed = ffn_archive_add(archive, states[i], 16, 4, archive_counters) ## i64
  if changed == 1
    if action == 1
      archive_names.push(names[i])
    if action >= 2
      archive_names[action - 2] = names[i]
  i += 1

# Count raw descriptor collisions before the bounded MAP archive can hide
# them. The descriptor's structure bucket deliberately has only 23 values.
map_keys = []
map_unique = 0 ## i64
map_collisions = 0 ## i64
i = 0
while i < states.size()
  key = ffme_descriptor(states[i], 247, 7) ## i64
  seen = 0 ## i64
  j = 0 ## i64
  while j < map_keys.size()
    if map_keys[j] == key
      seen = 1
    j += 1
  if seen == 0
    map_keys.push(key)
    map_unique += 1
  if seen != 0
    map_collisions += 1
  << "FRONTIER slot=" + i.to_s() + " bits=" + ffw_best_bits(states[i]).to_s() + " id=" + ffbi_best_id(states[i]).to_s() + " map=" + key.to_s() + " name=" + names[i]
  i += 1

pair_min = ffn_archive_min_distance(states) ## i64
leader_min = 999999999 ## i64
leader_max = 0 ## i64
i = 1
while i < states.size()
  distance = ffn_distance(states[0], states[i]) ## i64
  if distance < leader_min
    leader_min = distance
  if distance > leader_max
    leader_max = distance
  i += 1

<< "ARCHIVE raw=" + states.size().to_s() + " retained=" + archive.size().to_s() + " min=" + ffn_archive_min_distance(archive).to_s() + " admissions=" + archive_counters[0].to_s() + " evictions=" + archive_counters[1].to_s() + " rejects=" + archive_counters[2].to_s()
<< "MAP raw=" + states.size().to_s() + " unique=" + map_unique.to_s() + " collisions=" + map_collisions.to_s()
<< "DISTANCE pair_min=" + pair_min.to_s() + " leader_min=" + leader_min.to_s() + " leader_max=" + leader_max.to_s()

# Reproduce the rank-247 leader's ordinary near-bank construction before the
# four curated rank-248 shoulders are layered in. This catches ordering and
# structural-quota interactions that the empty-bank shoulder unit test cannot.
near1 = []
near1_signatures = []
near1_uses = []
near1_successes = []
near2 = []
near2_signatures = []
near2_uses = []
near2_successes = []
near_counters = i64[5]
raw_near1 = 0 ## i64
raw_near2 = 0 ## i64
kind = 1 ## i64
while kind <= 5
  nonce = 0 ## i64
  while nonce < 6
    candidate = fffeb_escape_state(states[0], kind, nonce, 7, capacity, state_size, 72001 + kind * 97 + nonce, 0, 1, 1, 1)
    if candidate != nil
      candidate_rank = ffw_best_rank(candidate) ## i64
      if candidate_rank == 248
        raw_near1 += 1
        z = ffbp_near_add(near1, near1_signatures, near1_uses, near1_successes, candidate, 32, 8, 2, near_counters) ## i64
      if candidate_rank == 249
        raw_near2 += 1
        z = ffbp_near_add(near2, near2_signatures, near2_uses, near2_successes, candidate, 32, 8, 2, near_counters) ## i64
    nonce += 1
  kind += 1
base_near1 = near1.size() ## i64
base_near2 = near2.size() ## i64
shoulders_admitted = ff7_add_known_7x7_rank247_shoulders(root, states[0], 7, capacity, state_size, 0, 1, 1, 1, near1, near1_signatures, near1_uses, near1_successes, 32, 8, near_counters) ## i64
<< "NEAR base_raw1=" + raw_near1.to_s() + " base_kept1=" + base_near1.to_s() + " base_raw2=" + raw_near2.to_s() + " base_kept2=" + base_near2.to_s() + " shoulders_admitted=" + shoulders_admitted.to_s() + " final1=" + near1.size().to_s() + " min1=" + ffbp_min_distance(near1).to_s() + " final2=" + near2.size().to_s() + " min2=" + ffbp_min_distance(near2).to_s()

# Sample the production nonce progression on each of the three supervisor
# anchors. Report endpoint identities and duplicates; each finder invocation
# still audits all elementary generators, merely rotating its starting point.
anchor_slots = i64[3]
anchor_slots[0] = 0
anchor_slots[1] = 14
anchor_slots[2] = 1
sample_count = 120 ## i64
slot = 0 ## i64
while slot < anchor_slots.size()
  source = states[anchor_slots[slot]]
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  meta = i64[18]
  endpoint = i64[state_size]
  ids = []
  workspace = FFPANWorkspace.new(247, 7, capacity)
  exported = ffw_export_best(source, us, vs, ws) ## i64
  nonce = 0 ## i64
  hits = 0 ## i64
  attempts = 0 ## i64
  started = ccall_nobox("__w_clock_ns_raw") ## i64
  while attempts < sample_count
    found = ffpan_find_elementary_escape(us, vs, ws, exported, 7, capacity, nonce, 5, workspace, out_u, out_v, out_w, meta) ## i64
    if found == 247 && meta[6] == 1 && meta[15] == 0
      loaded = ffw_init_terms_cap(endpoint, out_u, out_v, out_w, found, 7, capacity, 73001 + slot * 1000 + attempts, 0, 1, 1, 1) ## i64
      if loaded == 247 && ffw_verify_best_exact(endpoint, 7) == 1
        identity = ffbi_best_id(endpoint) ## i64
        unique = 1 ## i64
        j = 0
        while j < ids.size()
          if ids[j] == identity
            unique = 0
          j += 1
        if unique == 1
          ids.push(identity)
        hits += 1
    nonce = ffpan_next_nonce(7, nonce, 37)
    attempts += 1
  elapsed_ns = ccall_nobox("__w_clock_ns_raw") - started ## i64
  << "PARTIAL anchor=" + anchor_slots[slot].to_s() + " attempts=" + attempts.to_s() + " hits=" + hits.to_s() + " unique=" + ids.size().to_s() + " elapsed_ns=" + elapsed_ns.to_s()
  slot += 1

# Compare the current best-only two-hour cadence with a source-balanced scan
# over the same number of calls. Also measure the policy coupling where a
# max-min archive rejection prevents an otherwise eligible MAP admission.
audit_archive = []
audit_archive_counters = i64[3]
map_nested_states = []
map_nested_keys = []
map_nested_uses = []
map_nested_sources = []
map_independent_states = []
map_independent_keys = []
map_independent_uses = []
map_independent_sources = []
i = 0
while i < states.size()
  stored = i64[state_size]
  loaded = ffw_reseed_from(stored, states[i], 75001 + i) ## i64
  if loaded != 247
    << "FAIL 7x7 quality audit archive clone"
    exit(1)
  audit_archive.push(stored)
  z = ffme_add_copy(map_nested_states, map_nested_keys, map_nested_uses, map_nested_sources, states[i], 247, 7, 64, 0, state_size, 76001 + i) ## i64
  z = ffme_add_copy(map_independent_states, map_independent_keys, map_independent_uses, map_independent_sources, states[i], 247, 7, 64, 0, state_size, 77001 + i) ## i64
  i += 1

portfolio_ids = []
portfolio_hits = 0 ## i64
portfolio_archive_admits = 0 ## i64
portfolio_map_nested = 0 ## i64
portfolio_map_independent = 0 ## i64
source_attempts = i64[states.size()]
portfolio_attempt = 0 ## i64
portfolio_us = i64[capacity]
portfolio_vs = i64[capacity]
portfolio_ws = i64[capacity]
portfolio_out_u = i64[capacity]
portfolio_out_v = i64[capacity]
portfolio_out_w = i64[capacity]
portfolio_meta = i64[18]
portfolio_endpoint = i64[state_size]
portfolio_workspace = FFPANWorkspace.new(247, 7, capacity)
portfolio_started = ccall_nobox("__w_clock_ns_raw") ## i64
while portfolio_attempt < sample_count
  source_index = portfolio_attempt % states.size() ## i64
  source = states[source_index]
  exported = ffw_export_best(source, portfolio_us, portfolio_vs, portfolio_ws) ## i64
  source_nonce = (source_attempts[source_index] * 37) % ffpan_elementary_count(7) ## i64
  source_attempts[source_index] = source_attempts[source_index] + 1
  found = ffpan_find_elementary_escape(portfolio_us, portfolio_vs, portfolio_ws, exported, 7, capacity, source_nonce, 5, portfolio_workspace, portfolio_out_u, portfolio_out_v, portfolio_out_w, portfolio_meta) ## i64
  if found == 247 && portfolio_meta[6] == 1 && portfolio_meta[15] == 0
    loaded = ffw_init_terms_cap(portfolio_endpoint, portfolio_out_u, portfolio_out_v, portfolio_out_w, found, 7, capacity, 78001 + portfolio_attempt, 0, 1, 1, 1) ## i64
    if loaded == 247 && ffw_verify_best_exact(portfolio_endpoint, 7) == 1
      portfolio_hits += 1
      identity = ffbi_best_id(portfolio_endpoint) ## i64
      unique = 1 ## i64
      j = 0
      while j < portfolio_ids.size()
        if portfolio_ids[j] == identity
          unique = 0
        j += 1
      if unique == 1
        portfolio_ids.push(identity)
      archive_changed = ffn_archive_add_copy(audit_archive, portfolio_endpoint, 16, 4, audit_archive_counters, state_size, 79001 + portfolio_attempt) ## i64
      if archive_changed == 1
        portfolio_archive_admits += 1
        nested_changed = ffme_add_copy(map_nested_states, map_nested_keys, map_nested_uses, map_nested_sources, portfolio_endpoint, 247, 7, 64, 0, state_size, 80001 + portfolio_attempt) ## i64
        if nested_changed > 0
          portfolio_map_nested += 1
      independent_changed = ffme_add_copy(map_independent_states, map_independent_keys, map_independent_uses, map_independent_sources, portfolio_endpoint, 247, 7, 64, 0, state_size, 81001 + portfolio_attempt) ## i64
      if independent_changed > 0
        portfolio_map_independent += 1
  portfolio_attempt += 1
portfolio_elapsed_ns = ccall_nobox("__w_clock_ns_raw") - portfolio_started ## i64
<< "PARTIAL_PORTFOLIO attempts=" + sample_count.to_s() + " hits=" + portfolio_hits.to_s() + " unique=" + portfolio_ids.size().to_s() + " archive_admits=" + portfolio_archive_admits.to_s() + " map_nested=" + portfolio_map_nested.to_s() + " map_independent=" + portfolio_map_independent.to_s() + " elapsed_ns=" + portfolio_elapsed_ns.to_s()

<< "PASS 7x7 quality audit"

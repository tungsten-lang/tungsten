use ../lib/metaflip/fleet/seven_by_seven
use ../lib/metaflip/strategies/partial_automorphism_nullspace
use ../lib/metaflip/seeds/catalog

failures = 0 ## i64

-> ffpait_expect(label, condition) (String bool) i64
  if condition == 0
    << "FAIL partial-automorphism intake: " + label
    return 1
  0

root = __DIR__ + "/../lib/metaflip/"
paths = ffp_frontier_seed_paths(7)
capacity = 320 ## i64
state_size = ffw_state_size(capacity) ## i64
frontier = []
archive = []
archive_counters = i64[3]
map_states = []
map_keys = []
map_uses = []
map_sources = []

i = 0 ## i64
while i < paths.size()
  state = i64[state_size]
  loaded = ffw_load_scheme_cap(state, root + paths[i], 7, capacity, 93001 + i, 0, 1, 1, 1) ## i64
  failures += ffpait_expect("load exact frontier " + paths[i], loaded == 247 && ffw_verify_best_exact(state, 7) == 1)
  frontier.push(state)
  stored = i64[state_size]
  copied = ffw_reseed_from(stored, state, 94001 + i) ## i64
  failures += ffpait_expect("clone exact frontier", copied == 247)
  archive.push(stored)
  z = ffme_add_copy(map_states, map_keys, map_uses, map_sources, state, 247, 7, 64, 0, state_size, 95001 + i) ## i64
  i += 1

failures += ffpait_expect("curated archive fills cap", archive.size() == 16)
failures += ffpait_expect("curated MAP descriptors distinct", map_states.size() == 16)

us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
out_u = i64[capacity]
out_v = i64[capacity]
out_w = i64[capacity]
meta = i64[18]
schedule = i64[3]
intake = i64[2]
candidate = i64[state_size]
workspace = FFPANWorkspace.new(247, 7, capacity)
map_only_found = 0 ## i64
exact_candidates = 0 ## i64
attempt = 0 ## i64
while attempt < 40 && map_only_found == 0
  decoded = ffpan_portfolio_decode(7, frontier.size(), attempt, 1, schedule) ## i64
  source = frontier[schedule[0]]
  exported = ffw_export_best(source, us, vs, ws) ## i64
  found = ffpan_find_elementary_escape(us, vs, ws, exported, 7, capacity, schedule[1], 5, workspace, out_u, out_v, out_w, meta) ## i64
  if decoded == 1 && found == 247 && meta[6] == 1 && meta[15] == 0
    loaded = ffw_init_terms_cap(candidate, out_u, out_v, out_w, found, 7, capacity, 96001 + attempt, 0, 1, 1, 1) ## i64
    if loaded == 247 && ffw_verify_best_exact(candidate, 7) == 1
      exact_candidates += 1
      old_archive_size = archive.size() ## i64
      old_map_size = map_states.size() ## i64
      mask = ff7_partial_auto_admit(archive, 16, 4, archive_counters, map_states, map_keys, map_uses, map_sources, 64, candidate, 247, 7, state_size, 0, 97001 + attempt * 17, intake) ## i64
      if intake[0] == 0 && intake[1] > 0
        map_only_found = 1
        failures += ffpait_expect("independent mask marks MAP only", mask == 2)
        failures += ffpait_expect("archive rejection leaves size stable", archive.size() == old_archive_size)
        failures += ffpait_expect("MAP-only change is committed", map_states.size() > old_map_size || intake[1] == 2)
  attempt += 1

failures += ffpait_expect("real exact endpoint demonstrates MAP-only admission", map_only_found == 1)
failures += ffpait_expect("intake exercised exact candidates", exact_candidates > 1)

if failures > 0
  exit(1)
<< "PASS partial-automorphism independent intake attempts=" + attempt.to_s() + " exact=" + exact_candidates.to_s() + " archive=" + archive.size().to_s() + " map=" + map_states.size().to_s()

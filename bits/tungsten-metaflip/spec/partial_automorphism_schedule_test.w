use ../lib/metaflip/fleet/seven_by_seven
use ../lib/metaflip/strategies/partial_automorphism_nullspace
use ../lib/metaflip/seeds/catalog

failures = 0 ## i64

-> ffpasst_expect(label, condition) (String bool) i64
  if condition == 0
    << "FAIL partial-automorphism schedule: " + label
    return 1
  0

failures += ffpasst_expect("7x7 measured cooldown", ffpan_tunnel_cooldown_ms(7) == 15000)
failures += ffpasst_expect("other tensors retain cold fallback", ffpan_tunnel_cooldown_ms(6) == 60000)
failures += ffpasst_expect("first call due", ffpan_tunnel_due(7, 100, 0 - 1, ffpan_tunnel_cooldown_ms(7)) == 1)
failures += ffpasst_expect("cooldown blocks early call", ffpan_tunnel_due(7, 15099, 100, ffpan_tunnel_cooldown_ms(7)) == 0)
failures += ffpasst_expect("cooldown opens boundary", ffpan_tunnel_due(7, 15100, 100, ffpan_tunnel_cooldown_ms(7)) == 1)

source_count = ffp_frontier_seed_paths(7).size() ## i64
failures += ffpasst_expect("schedule covers full active frontier", source_count == 16)
generator_count = ffpan_elementary_count(7) ## i64
schedule = i64[3]
seen = i64[source_count * generator_count]
source_visits = i64[source_count]
completed = 0 ## i64
while completed < source_count * generator_count
  decoded = ffpan_portfolio_decode(7, source_count, completed, 0, schedule) ## i64
  failures += ffpasst_expect("full-cycle decode " + completed.to_s(), decoded == 1)
  if decoded == 1
    source_index = schedule[0] ## i64
    nonce = schedule[1] ## i64
    index = source_index * generator_count + nonce ## i64
    failures += ffpasst_expect("source in range", source_index >= 0 && source_index < source_count)
    failures += ffpasst_expect("generator in range", nonce >= 0 && nonce < generator_count)
    failures += ffpasst_expect("source-generator pair visited once", seen[index] == 0)
    seen[index] = 1
    source_visits[source_index] = source_visits[source_index] + 1
  completed += 1

source_index = 0
while source_index < source_count
  failures += ffpasst_expect("every source gets complete generator cycle " + source_index.to_s(), source_visits[source_index] == generator_count)
  source_index += 1

# Three supervisor nonces receive disjoint generator starts for the first 32
# visits to each source (just over two hours at the 15-second cadence for the
# current 16-state frontier). Source phases may reorder calls but not coverage.
cross_seen = i64[source_count * generator_count]
cross_duplicates = 0 ## i64
campaign_nonce = 1 ## i64
while campaign_nonce <= 3
  completed = 0
  while completed < source_count * 32
    decoded = ffpan_portfolio_decode(7, source_count, completed, campaign_nonce, schedule) ## i64
    if decoded == 1
      index = schedule[0] * generator_count + schedule[1] ## i64
      if cross_seen[index] != 0
        cross_duplicates += 1
      cross_seen[index] = campaign_nonce
    completed += 1
  campaign_nonce += 1
failures += ffpasst_expect("three-shard first-two-hour starts are disjoint", cross_duplicates == 0)

small = i64[2]
failures += ffpasst_expect("zero-source schedule rejected", ffpan_portfolio_decode(7, 0, 0, 0, schedule) == 0)
failures += ffpasst_expect("short output rejected", ffpan_portfolio_decode(7, 1, 0, 0, small) == 0)
failures += ffpasst_expect("non-7x7 schedule rejected", ffpan_portfolio_decode(6, 1, 0, 0, schedule) == 0)

# Exact regression over the three supervisor anchors. This exercises source
# rotation and phased nonces through the real arbitrary-cardinality finder.
root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
paths = ["matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt",
         "matmul_7x7_rank247_d3096_affine_code_cuda_epoch3306_gf2.txt",
         "matmul_7x7_rank247_d3098_global_isotropy_gf2.txt"]
capacity = 320 ## i64
state_size = ffw_state_size(capacity) ## i64
states = []
i = 0 ## i64
while i < paths.size()
  state = i64[state_size]
  loaded = ffw_load_scheme_cap(state, root + paths[i], 7, capacity, 91001 + i, 0, 1, 1, 1) ## i64
  failures += ffpasst_expect("exact anchor " + paths[i], loaded == 247 && ffw_verify_best_exact(state, 7) == 1)
  states.push(state)
  i += 1

us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
out_u = i64[capacity]
out_v = i64[capacity]
out_w = i64[capacity]
meta = i64[18]
endpoint = i64[state_size]
workspace = FFPANWorkspace.new(247, 7, capacity)
endpoint_ids = []
exact_hits = 0 ## i64
completed = 0
while completed < 18
  decoded = ffpan_portfolio_decode(7, states.size(), completed, 1, schedule) ## i64
  source_state = states[schedule[0]]
  exported = ffw_export_best(source_state, us, vs, ws) ## i64
  found = ffpan_find_elementary_escape(us, vs, ws, exported, 7, capacity, schedule[1], 5, workspace, out_u, out_v, out_w, meta) ## i64
  if decoded == 1 && found == 247 && meta[6] == 1 && meta[15] == 0
    loaded = ffw_init_terms_cap(endpoint, out_u, out_v, out_w, found, 7, capacity, 92001 + completed, 0, 1, 1, 1) ## i64
    if loaded == 247 && ffw_verify_best_exact(endpoint, 7) == 1
      exact_hits += 1
      identity = ffbi_best_id(endpoint) ## i64
      present = 0 ## i64
      j = 0 ## i64
      while j < endpoint_ids.size()
        if endpoint_ids[j] == identity
          present = 1
        j += 1
      if present == 0
        endpoint_ids.push(identity)
  completed += 1

failures += ffpasst_expect("all scheduled real endpoints exact", exact_hits == 18)
failures += ffpasst_expect("scheduled real endpoints are diverse", endpoint_ids.size() >= 12)

if failures > 0
  exit(1)
<< "PASS partial-automorphism schedule pairs=" + (source_count * generator_count).to_s() + " cross_duplicates=" + cross_duplicates.to_s() + " exact=" + exact_hits.to_s() + " unique=" + endpoint_ids.size().to_s()

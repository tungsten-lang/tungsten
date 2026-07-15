use flipfleet_profiles
use flipfleet_frontier_escape_banks
use flipfleet_global_isotropy

-> ffspb_now() i64
  ccall("__w_clock_ms")

n = 7 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
paths = ffp_frontier_seed_paths(n)
sources = []

started = ffspb_now() ## i64
index = 0 ## i64
while index < paths.size()
  state = i64[state_size]
  rank = ffw_load_scheme_cap(state, paths[index], n, capacity, 93001 + index, 4, 4, 1, 1) ## i64
  if rank != 247 || ffw_verify_best_exact(state, n) != 1
    << "FLIPFLEET_STARTUP_PHASE_FAIL load=" + paths[index]
    exit(1)
  sources.push(state)
  index += 1
load_ms = ffspb_now() - started ## i64

started = ffspb_now()
isotropy_improved = 0 ## i64
index = 0
while index < sources.size()
  destination = i64[state_size]
  stats = i64[4]
  if ffgir_density_descent_state_into(sources[index], destination, n, capacity, 93101 + index, 4, 4, 1, 1, 32, stats) == 247
    isotropy_improved += 1
  index += 1
isotropy_ms = ffspb_now() - started ## i64

-> ffspb_append_loaded(sources, count, n, capacity, state_size) i64
  near1 = []
  near2 = []
  near1_signatures = []
  near1_uses = []
  near1_successes = []
  near2_signatures = []
  near2_uses = []
  near2_successes = []
  near_counters = i64[5]
  counters = i64[6]
  admitted = 0 ## i64
  index = 0 ## i64
  while index < count
    admitted += fffeb_append_source(sources[index], 247, index, n, capacity, state_size, 4, 4, 1, 1, 6, near1, near1_signatures, near1_uses, near1_successes, 32, near2, near2_signatures, near2_uses, near2_successes, 32, 8, 2, near_counters, counters)
    index += 1
  admitted

started = ffspb_now()
leader_admitted = ffspb_append_loaded(sources, 1, n, capacity, state_size) ## i64
leader_escape_ms = ffspb_now() - started ## i64

started = ffspb_now()
frontier_admitted = ffspb_append_loaded(sources, sources.size(), n, capacity, state_size) ## i64
frontier_escape_ms = ffspb_now() - started ## i64

<< "flipfleet_startup_phase_bench: paths=" + paths.size().to_s() + " load_full_gate_ms=" + load_ms.to_s() + " isotropy_ms=" + isotropy_ms.to_s() + " isotropy_improved=" + isotropy_improved.to_s() + " leader_escape_ms=" + leader_escape_ms.to_s() + " leader_admitted=" + leader_admitted.to_s() + " all_frontier_escape_ms=" + frontier_escape_ms.to_s() + " frontier_admitted=" + frontier_admitted.to_s()

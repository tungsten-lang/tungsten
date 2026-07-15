use flipfleet_profiles
use flipfleet_frontier_escape_banks

-> fflfel_now() i64
  ccall("__w_clock_ms")

n = 7 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
paths = ffp_frontier_seed_paths(n)
sources = []
index = 0 ## i64
while index < paths.size()
  state = i64[state_size]
  rank = ffw_load_scheme_cap(state, paths[index], n, capacity, 94001 + index, 4, 4, 1, 1) ## i64
  if rank != 247 || ffw_verify_best_exact(state, n) != 1
    << "FLIPFLEET_LAZY_ESCAPE_LATENCY_FAIL load=" + paths[index]
    exit(1)
  sources.push(state)
  index += 1

near1 = []
near1_signatures = []
near1_uses = []
near1_successes = []
near2 = []
near2_signatures = []
near2_uses = []
near2_successes = []
near_counters = i64[5]
counters = i64[6]

# Match the production bank's immediate leader family before timing lazy calls.
z = fffeb_append_source(sources[0], 247, 0, n, capacity, state_size, 4, 4, 1, 1, 6, near1, near1_signatures, near1_uses, near1_successes, 32, near2, near2_signatures, near2_uses, near2_successes, 32, 8, 2, near_counters, counters) ## i64

call_count = sources.size() * 5 ## i64
latencies = i64[call_count]
sum_ms = 0 ## i64
max_ms = 0 ## i64
slow_500 = 0 ## i64
call = 0 ## i64
kind = 1 ## i64
while kind <= 5
  source_index = 0 ## i64
  while source_index < sources.size()
    started = fflfel_now() ## i64
    z = fffeb_append_source_kind_nonce(sources[source_index], 247, source_index, kind, 0, n, capacity, state_size, 4, 4, 1, 1, near1, near1_signatures, near1_uses, near1_successes, 32, near2, near2_signatures, near2_uses, near2_successes, 32, 8, 2, near_counters, counters)
    elapsed = fflfel_now() - started ## i64
    latencies[call] = elapsed
    sum_ms += elapsed
    if elapsed > max_ms
      max_ms = elapsed
    if elapsed >= 500
      slow_500 += 1
    call += 1
    source_index += 1
  kind += 1

# Tiny insertion sort for percentile telemetry.
i = 1 ## i64
while i < call_count
  value = latencies[i] ## i64
  j = i ## i64
  while j > 0 && latencies[j - 1] > value
    latencies[j] = latencies[j - 1]
    j -= 1
  latencies[j] = value
  i += 1

<< "flipfleet_lazy_frontier_escape_latency_bench: calls=" + call_count.to_s() + " mean_ms=" + (sum_ms / call_count).to_s() + " p50_ms=" + latencies[call_count / 2].to_s() + " p90_ms=" + latencies[call_count * 9 / 10].to_s() + " max_ms=" + max_ms.to_s() + " ge500ms=" + slow_500.to_s() + " near=" + near1.size().to_s() + "/" + near2.size().to_s()

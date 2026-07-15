# Coordinator-cost benchmark for the production whole-frontier elementary
# automorphism finder.  One workspace is retained across calls, matching the
# intended fleet integration.  Every reported hit has already crossed the
# finder's independent n^6 gate and source/global-image quotient.
#
# Usage: flipfleet_partial_automorphism_nullspace_latency_bench [samples=189]

use flipfleet_partial_automorphism_nullspace

-> ffpanlb_sort(values, count) (i64[] i64) i64
  i = 1 ## i64
  while i < count
    value = values[i] ## i64
    j = i ## i64
    while j > 0 && values[j - 1] > value
      values[j] = values[j - 1]
      j -= 1
    values[j] = value
    i += 1
  count

args = argv()
n = 7 ## i64
total = ffpan_elementary_count(n) ## i64
samples = total ## i64
if args.size() > 0
  samples = args[0].to_i()
if samples < 1 || samples > total
  << "samples must be in 1.." + total.to_s()
  exit(2)

capacity = ffw_default_capacity(n) ## i64
state = i64[ffw_state_size(capacity)]
rank = ffw_load_scheme_cap(state, "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt", n, capacity, 973001, 0, 1, 1, 1) ## i64
if rank != 247 || ffw_verify_best_exact(state, n) != 1
  << "source load failed"
  exit(1)
us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
if ffw_export_best(state, us, vs, ws) != rank
  << "source export failed"
  exit(1)
workspace = FFPANWorkspace.new(rank, n, capacity)
out_u = i64[capacity]
out_v = i64[capacity]
out_w = i64[capacity]
latencies = i64[samples]
operation_counts = i64[samples]
hits = 0 ## i64
failures = 0 ## i64
total_ms = 0 ## i64
total_operations = 0 ## i64
step = 0 ## i64
while step < samples
  nonce = step * total / samples ## i64
  meta = i64[18]
  started = ccall("__w_clock_ms") ## i64
  found = ffpan_find_elementary_escape(us, vs, ws, rank, n, capacity, nonce, 5, workspace, out_u, out_v, out_w, meta) ## i64
  elapsed = ccall("__w_clock_ms") - started ## i64
  latencies[step] = elapsed
  operation_counts[step] = meta[0]
  total_ms += elapsed
  total_operations += meta[0]
  if found == rank && meta[6] == 1
    hits += 1
  if found < 0 || meta[15] != 0
    failures += 1
  step += 1

z = ffpanlb_sort(latencies, samples) ## i64
z = ffpanlb_sort(operation_counts, samples)
p50_index = (samples - 1) / 2 ## i64
p95_index = (samples * 95 + 99) / 100 - 1 ## i64
if p95_index >= samples
  p95_index = samples - 1
<< "PARTIAL_AUTO_LATENCY samples=" + samples.to_s() + " generators=" + total.to_s() + " hits=" + hits.to_s() + " failures=" + failures.to_s() + " total_ms=" + total_ms.to_s() + " mean_ms=" + (total_ms / samples).to_s() + " p50_ms=" + latencies[p50_index].to_s() + " p95_ms=" + latencies[p95_index].to_s() + " max_ms=" + latencies[samples - 1].to_s() + " total_operations=" + total_operations.to_s() + " mean_operations=" + (total_operations / samples).to_s() + " p50_operations=" + operation_counts[p50_index].to_s() + " p95_operations=" + operation_counts[p95_index].to_s() + " max_operations=" + operation_counts[samples - 1].to_s()

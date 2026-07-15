# Single-process real-frontier benchmark for one bounded five-circuit trial.
# Keeping one trial per process prevents retained scratch from distorting a
# multi-policy campaign's memory profile.
#
# Usage:
#   flipfleet_matroid_circuit5_bench seed n policy nonce pool triple_cap [output]

use flipfleet_matroid_circuit5

args = argv()
if args.size() < 6
  << "usage: flipfleet_matroid_circuit5_bench seed n policy nonce pool triple_cap [output]"
  exit(2)
path = args[0]
n = args[1].to_i() ## i64
policy = args[2].to_i() ## i64
nonce = args[3].to_i() ## i64
pool = args[4].to_i() ## i64
triple_cap = args[5].to_i() ## i64
if n < 2 || n > 7 || policy < 0 || policy > 4 || nonce < 0 || pool < 5 || pool > 2048 || triple_cap < 0
  << "invalid benchmark bounds"
  exit(2)

capacity = ffw_default_capacity(n) ## i64
size = ffw_state_size(capacity) ## i64
source = i64[size]
rank = ffw_load_scheme_cap(source, path, n, capacity, 97001 + nonce, 0, 1, 1, 1) ## i64
if rank < 5 || ffw_verify_current_exact(source, n) == 0
  << "MATROID_CIRCUIT5 error=load path=" + path
  exit(2)
us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
if ffw_export_current(source, us, vs, ws) != rank
  exit(2)
source_density = fftc_density(us, vs, ws, rank) ## i64
out_u = i64[capacity]
out_v = i64[capacity]
out_w = i64[capacity]
meta = i64[18]
started = ccall("__w_clock_ms") ## i64
found = ffmc5_search_bounded(us, vs, ws, rank, n * n, pool, policy, nonce, triple_cap, out_u, out_v, out_w, meta) ## i64
elapsed = ccall("__w_clock_ms") - started ## i64
full_exact = 0 ## i64
endpoint_density = 0 - 1 ## i64
written = 0 ## i64
if found > 0
  endpoint = i64[size]
  loaded = ffw_init_terms_cap(endpoint, out_u, out_v, out_w, found, n, capacity, 98001 + nonce, 0, 1, 1, 1) ## i64
  if loaded == found && ffw_verify_current_exact(endpoint, n) == 1
    full_exact = 1
    endpoint_density = ffw_current_bits(endpoint)
    if args.size() > 6
      dumped = ffw_dump_current(endpoint, args[6]) ## i64
      if dumped == found
        reparsed = i64[size]
        checked = ffw_load_scheme_cap(reparsed, args[6], n, capacity, 99001 + nonce, 0, 1, 1, 1) ## i64
        if checked == found && ffw_verify_current_exact(reparsed, n) == 1
          written = checked
<< "MATROID_CIRCUIT5 n=" + n.to_s() + " rank=" + rank.to_s() + " density=" + source_density.to_s() + " policy=" + policy.to_s() + " nonce=" + nonce.to_s() + " generated=" + meta[0].to_s() + " selected=" + meta[1].to_s() + " negative=" + meta[14].to_s() + " nonnegative=" + meta[15].to_s() + " pairs=" + meta[2].to_s() + " triples=" + meta[3].to_s() + " sketch=" + meta[4].to_s() + " exact=" + meta[5].to_s() + " minimal=" + meta[6].to_s() + " valid=" + meta[7].to_s() + " one_flip=" + meta[8].to_s() + " span5=" + meta[9].to_s() + " distance5=" + meta[10].to_s() + " rank_drops=" + meta[11].to_s() + " best_delta=" + meta[12].to_s() + " endpoint_rank=" + found.to_s() + " endpoint_density=" + endpoint_density.to_s() + " full_exact=" + full_exact.to_s() + " written=" + written.to_s() + " table=" + meta[17].to_s() + " ms=" + elapsed.to_s()

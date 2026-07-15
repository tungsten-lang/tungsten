# Bounded CPU-only archive benchmark for three-anchor primitive-circuit images.
#
# Usage:
#   flipfleet_circuit_image_search3_bench seed n fit_cap nonce gauge_only [output]
#
# fit_cap=0 exhausts all independent live triples and all 32 template anchor
# triples (six live assignments each).  A retained circuit and its complete
# matrix-multiplication endpoint are both exact-gated.

use flipfleet_circuit_image_search3

-> ffcis3b_added_axis_values(circuit_u, circuit_v, circuit_w, count, source_u, source_v, source_w, rank, axis) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64) i64
  distinct = 0 ## i64
  term = 0 ## i64
  while term < count
    live = 0 ## i64
    source = 0 ## i64
    while source < rank
      if ffc_same_term(circuit_u[term], circuit_v[term], circuit_w[term], source_u[source], source_v[source], source_w[source]) == 1
        live = 1
      source += 1
    if live == 0
      value = circuit_u[term] ## i64
      if axis == 1
        value = circuit_v[term]
      if axis == 2
        value = circuit_w[term]
      earlier = 0 ## i64
      previous = 0 ## i64
      while previous < term
        previous_live = 0 ## i64
        source = 0
        while source < rank
          if ffc_same_term(circuit_u[previous], circuit_v[previous], circuit_w[previous], source_u[source], source_v[source], source_w[source]) == 1
            previous_live = 1
          source += 1
        previous_value = circuit_u[previous] ## i64
        if axis == 1
          previous_value = circuit_v[previous]
        if axis == 2
          previous_value = circuit_w[previous]
        if previous_live == 0 && previous_value == value
          earlier = 1
        previous += 1
      if earlier == 0
        distinct += 1
    term += 1
  distinct

args = argv()
if args.size() < 5
  << "usage: flipfleet_circuit_image_search3_bench seed n fit_cap nonce gauge_only [output]"
  exit(2)
path = args[0]
n = args[1].to_i() ## i64
fit_cap = args[2].to_i() ## i64
nonce = args[3].to_i() ## i64
gauge_only = args[4].to_i() ## i64
if n < 2 || n > 7 || fit_cap < 0 || nonce < 0 || gauge_only < 0 || gauge_only > 1
  << "CIRCUIT_IMAGE_SEARCH3 error=arguments"
  exit(2)

capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
source = i64[state_size]
rank = ffw_load_scheme_cap(source, path, n, capacity, 89101 + nonce, 0, 1, 1, 1) ## i64
if rank < 3 || ffw_verify_current_exact(source, n) == 0
  << "CIRCUIT_IMAGE_SEARCH3 error=load path=" + path
  exit(2)
us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
if ffw_export_current(source, us, vs, ws) != rank
  << "CIRCUIT_IMAGE_SEARCH3 error=export"
  exit(2)

circuit_u = i64[12]
circuit_v = i64[12]
circuit_w = i64[12]
meta = i64[21]
started = ccall("__w_clock_ms") ## i64
circuit_count = ffcis3_search_triples(us, vs, ws, rank, fit_cap, nonce, gauge_only, circuit_u, circuit_v, circuit_w, meta) ## i64
search_ms = ccall("__w_clock_ms") - started ## i64
if circuit_count < 10 || circuit_count > 12 || ffc_is_primitive_circuit(circuit_u, circuit_v, circuit_w, circuit_count) == 0
  << "CIRCUIT_IMAGE_SEARCH3 error=search path=" + path + " count=" + circuit_count.to_s()
  exit(2)

out_u = i64[capacity]
out_v = i64[capacity]
out_w = i64[capacity]
out_rank = ffcis3_apply_circuit(us, vs, ws, rank, circuit_u, circuit_v, circuit_w, circuit_count, out_u, out_v, out_w) ## i64
if out_rank != rank + meta[9]
  << "CIRCUIT_IMAGE_SEARCH3 error=rank-accounting"
  exit(2)
endpoint = i64[state_size]
loaded = ffw_init_terms_cap(endpoint, out_u, out_v, out_w, out_rank, n, capacity, 89201 + nonce, 0, 1, 1, 1) ## i64
full_exact = 0 ## i64
if loaded == out_rank && ffw_verify_current_exact(endpoint, n) == 1
  full_exact = 1
if full_exact == 0
  << "CIRCUIT_IMAGE_SEARCH3 error=full-gate"
  exit(2)

written = 0 ## i64
if args.size() > 5
  written = ffw_dump_current(endpoint, args[5]) ## i64
  if written != out_rank
    << "CIRCUIT_IMAGE_SEARCH3 error=write"
    exit(2)
  reparsed = i64[state_size]
  checked = ffw_load_scheme_cap(reparsed, args[5], n, capacity, 89301 + nonce, 0, 1, 1, 1) ## i64
  if checked != out_rank || ffw_verify_current_exact(reparsed, n) == 0
    << "CIRCUIT_IMAGE_SEARCH3 error=reparse"
    exit(2)

source_density = ffw_current_bits(source) ## i64
endpoint_density = ffw_current_bits(endpoint) ## i64
added_u = ffcis3b_added_axis_values(circuit_u, circuit_v, circuit_w, circuit_count, us, vs, ws, rank, 0) ## i64
added_v = ffcis3b_added_axis_values(circuit_u, circuit_v, circuit_w, circuit_count, us, vs, ws, rank, 1) ## i64
added_w = ffcis3b_added_axis_values(circuit_u, circuit_v, circuit_w, circuit_count, us, vs, ws, rank, 2) ## i64
<< "CIRCUIT_IMAGE_SEARCH3 n=" + n.to_s() + " rank=" + rank.to_s() + " density=" + source_density.to_s() + " gauge_only=" + gauge_only.to_s() + " anchors=" + meta[0].to_s() + " live_triples=" + meta[1].to_s() + " visited=" + meta[16].to_s() + " fits=" + meta[2].to_s() + " injective=" + meta[3].to_s() + " scored=" + meta[4].to_s() + " exact_circuit_gates=" + meta[5].to_s() + " drops=" + meta[6].to_s() + " neutral=" + meta[7].to_s() + " debt_le2=" + meta[8].to_s() + " gauge-resistant=" + meta[18].to_s() + " max-min-added=" + meta[19].to_s() + " best_delta=" + meta[9].to_s() + " circuit=" + circuit_count.to_s() + " overlap=" + meta[12].to_s() + " max_overlap=" + meta[13].to_s() + " added-axis-values=" + added_u.to_s() + "/" + added_v.to_s() + "/" + added_w.to_s() + " endpoint_rank=" + out_rank.to_s() + " endpoint_density=" + endpoint_density.to_s() + " full_exact=" + full_exact.to_s() + " cap=" + fit_cap.to_s() + " capped=" + meta[14].to_s() + " written=" + written.to_s() + " ms=" + search_ms.to_s()

use flipfleet_global_isotropy

arguments = argv()
path = "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt"
n = 5 ## i64
restarts = 64 ## i64
max_descent = 256 ## i64
output = "/tmp/matmul_global_isotropy_best_gf2.txt"
if arguments.size() > 0
  path = arguments[0]
if arguments.size() > 1
  n = arguments[1].to_i()
if arguments.size() > 2
  restarts = arguments[2].to_i()
if arguments.size() > 3
  output = arguments[3]
if restarts < 0
  restarts = 0
if restarts > 4096
  restarts = 4096

capacity = ffw_default_capacity(n) ## i64
size = ffw_state_size(capacity) ## i64
source = i64[size]
rank = ffw_load_scheme_cap(source, path, n, capacity, 81731, 6, 4, 100000, 25000) ## i64
if rank < 1 || ffw_verify_best_exact(source, n) != 1
  << "GLOBAL_ISOTROPY_DESCENT_LOAD_FAIL"
  exit(1)

source_u = i64[capacity]
source_v = i64[capacity]
source_w = i64[capacity]
z = ffw_export_best(source, source_u, source_v, source_w) ## i64
best_u = i64[capacity]
best_v = i64[capacity]
best_w = i64[capacity]
z = ffgir_copy_terms(source_u, source_v, source_w, best_u, best_v, best_w, rank) ## i64
stats = i64[4]
best_density = ffgir_density_descent(best_u, best_v, best_w, rank, n, max_descent, stats) ## i64
<< "GLOBAL_ISOTROPY_DESCENT restart=base start=" + stats[0].to_s() + " final=" + stats[1].to_s() + " steps=" + stats[2].to_s() + " evals=" + stats[3].to_s()

restart = 0 ## i64
while restart < restarts
  candidate_u = i64[capacity]
  candidate_v = i64[capacity]
  candidate_w = i64[capacity]
  z = ffgir_copy_terms(source_u, source_v, source_w, candidate_u, candidate_v, candidate_w, rank)
  length = 1 + (restart % 24) ## i64
  operations = i64[24]
  domains = i64[24]
  sources = i64[24]
  targets = i64[24]
  made = ffgir_make_word(n, 104729 * (restart + 1) + rank * 65537, length, operations, domains, sources, targets) ## i64
  z = ffgir_apply_word(candidate_u, candidate_v, candidate_w, rank, n, operations, domains, sources, targets, made, 0)
  candidate_stats = i64[4]
  candidate_density = ffgir_density_descent(candidate_u, candidate_v, candidate_w, rank, n, max_descent, candidate_stats) ## i64
  if candidate_density < best_density
    best_density = candidate_density
    z = ffgir_copy_terms(candidate_u, candidate_v, candidate_w, best_u, best_v, best_w, rank)
    << "GLOBAL_ISOTROPY_DESCENT restart=" + restart.to_s() + " word=" + length.to_s() + " start=" + candidate_stats[0].to_s() + " final=" + candidate_stats[1].to_s() + " steps=" + candidate_stats[2].to_s() + " best=1"
  restart += 1

# Materialize through the worker, full-gate, serialize, reparse, and full-gate
# again.  The output is never trusted solely because a GL word should be exact.
candidate = i64[size]
loaded = ffw_init_terms_cap(candidate, best_u, best_v, best_w, rank, n, capacity, 99173, 6, 4, 100000, 25000) ## i64
if loaded != rank || ffw_verify_best_exact(candidate, n) != 1 || ffw_best_bits(candidate) != best_density
  << "GLOBAL_ISOTROPY_DESCENT_GATE_FAIL"
  exit(1)
dumped = ffw_dump_best(candidate, output) ## i64
reparsed = i64[size]
reloaded = ffw_load_scheme_cap(reparsed, output, n, capacity, 99233, 6, 4, 100000, 25000) ## i64
if dumped != rank || reloaded != rank || ffw_verify_best_exact(reparsed, n) != 1 || ffw_best_bits(reparsed) != best_density
  << "GLOBAL_ISOTROPY_DESCENT_REPARSE_FAIL"
  exit(1)

distance = ffgir_term_set_distance(source_u, source_v, source_w, rank, best_u, best_v, best_w, rank) ## i64
<< "GLOBAL_ISOTROPY_DESCENT_SUMMARY rank=" + rank.to_s() + " source-density=" + ffgir_density(source_u, source_v, source_w, rank).to_s() + " best-density=" + best_density.to_s() + " distance=" + distance.to_s() + " union=" + ffgir_union_support(best_u, best_v, best_w, rank).to_s() + " factors=" + ffgir_distinct_factor_support(best_u, best_v, best_w, rank).to_s() + " exact=1 reparsed=1 output=" + output

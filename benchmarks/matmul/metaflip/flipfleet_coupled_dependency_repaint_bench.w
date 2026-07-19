# Usage: flipfleet_coupled_dependency_repaint_bench seed n [include_reverse] [fit_cap] [nonce]

use flipfleet_coupled_dependency_repaint

args = argv()
if args.size() < 2
  << "usage: flipfleet_coupled_dependency_repaint_bench seed n [include_reverse] [fit_cap] [nonce]"
  exit(1)

path = args[0]
n = args[1].to_i()
include_reverse = 1 ## i64
if args.size() > 2
  include_reverse = args[2].to_i()
fit_cap = 200000 ## i64
if args.size() > 3
  fit_cap = args[3].to_i()
nonce = 0 ## i64
if args.size() > 4
  nonce = args[4].to_i()
capacity = ffw_default_capacity(n) ## i64
state = i64[ffw_state_size(capacity)]
rank = ffw_load_scheme_cap(state,path,n,capacity,970031,0,1,1,1) ## i64
if rank < 1 || ffw_verify_current_exact(state,n) != 1
  << "COUPLED_DEPENDENCY_REPAINT_BENCH load_or_verify_failed path=" + path
  exit(2)
us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
if ffw_export_current(state,us,vs,ws) != rank
  << "COUPLED_DEPENDENCY_REPAINT_BENCH export_failed path=" + path
  exit(3)

best_u = i64[9]
best_v = i64[9]
best_w = i64[9]
stats = i64[9]
found = ffcdr_scan(us,vs,ws,rank,include_reverse,best_u,best_v,best_w,stats) ## i64
fit_best_u = i64[9]
fit_best_v = i64[9]
fit_best_w = i64[9]
fit_meta = i64[14]
fit_found = ffcdr_fit_search(us,vs,ws,rank,fit_cap,nonce,fit_best_u,fit_best_v,fit_best_w,fit_meta) ## i64
if fit_found == 9
  if found != 9 || fit_meta[9] < stats[4] || (fit_meta[9] == stats[4] && fit_meta[10] < stats[5])
    i = 0 ## i64
    while i < 9
      best_u[i] = fit_best_u[i]
      best_v[i] = fit_best_v[i]
      best_w[i] = fit_best_w[i]
      i += 1
    found = 9
    stats[3] = fit_meta[8]
    stats[4] = fit_meta[9]
    stats[5] = fit_meta[10]
    stats[6] = fit_meta[11]
    stats[7] = 2
    stats[8] = fit_meta[13]
endpoint_rank = rank ## i64
endpoint_exact = 0 ## i64
if found == 9
  out_u = i64[capacity + 9]
  out_v = i64[capacity + 9]
  out_w = i64[capacity + 9]
  endpoint_rank = ffcis3_apply_circuit(us,vs,ws,rank,best_u,best_v,best_w,9,out_u,out_v,out_w) ## i64
  if endpoint_rank > 0 && endpoint_rank <= capacity
    endpoint = i64[ffw_state_size(capacity)]
    loaded = ffw_init_terms_cap(endpoint,out_u,out_v,out_w,endpoint_rank,n,capacity,970033,0,1,1,1) ## i64
    if loaded == endpoint_rank && ffw_verify_current_exact(endpoint,n) == 1
      endpoint_exact = 1

<< "COUPLED_DEPENDENCY_REPAINT_BENCH path=" + path + " rank=" + rank.to_s() + " direct_candidates=" + stats[0].to_s() + " forward=" + stats[1].to_s() + " reverse=" + stats[2].to_s() + " fit_cap=" + fit_cap.to_s() + " fit_attempts=" + fit_meta[2].to_s() + " fit_consistent=" + fit_meta[3].to_s() + " overlap3=" + fit_meta[5].to_s() + " overlap4=" + fit_meta[6].to_s() + " overlap5plus=" + fit_meta[7].to_s() + " found=" + found.to_s() + " best_delta=" + stats[4].to_s() + " density_delta=" + stats[5].to_s() + " overlap=" + stats[3].to_s() + " permutation=" + stats[6].to_s() + " direction=" + stats[7].to_s() + " primitive=" + stats[8].to_s() + " endpoint_rank=" + endpoint_rank.to_s() + " endpoint_exact=" + endpoint_exact.to_s()

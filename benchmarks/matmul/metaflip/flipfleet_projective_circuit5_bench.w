# Usage: flipfleet_projective_circuit5_bench seed n circuit_cap nonce [output]

use flipfleet_projective_circuit5

args = argv()
if args.size() < 4
  << "usage: flipfleet_projective_circuit5_bench seed n circuit_cap nonce [output]"
  exit(2)
path = args[0]
n = args[1].to_i() ## i64
circuit_cap = args[2].to_i() ## i64
nonce = args[3].to_i() ## i64
if n < 2 || n > 7 || circuit_cap < 0 || nonce < 0
  << "PROJECTIVE_CIRCUIT5 error=arguments"
  exit(2)
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
source = i64[state_size]
rank = ffw_load_scheme_cap(source,path,n,capacity,95901 + nonce,0,1,1,1) ## i64
if rank < 5 || ffw_verify_current_exact(source,n) == 0
  << "PROJECTIVE_CIRCUIT5 error=load"
  exit(2)
us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
if ffw_export_current(source,us,vs,ws) != rank
  << "PROJECTIVE_CIRCUIT5 error=export"
  exit(2)
out_u = i64[capacity]
out_v = i64[capacity]
out_w = i64[capacity]
meta = i64[14]
started = ccall("__w_clock_ms") ## i64
out_rank = ffpc5_search(us,vs,ws,rank,circuit_cap,nonce,out_u,out_v,out_w,meta) ## i64
search_ms = ccall("__w_clock_ms") - started ## i64
if out_rank == 0
  << "PROJECTIVE_CIRCUIT5 n=" + n.to_s() + " rank=" + rank.to_s() + " candidate=none quads=" + meta[0].to_s() + " circuits=" + meta[1].to_s() + " d=" + meta[2].to_s() + " local_le2=" + meta[3].to_s() + " capped=" + meta[11].to_s() + " ms=" + search_ms.to_s()
  exit(0)
endpoint = i64[state_size]
loaded = ffw_init_terms_cap(endpoint,out_u,out_v,out_w,out_rank,n,capacity,96001 + nonce,0,1,1,1) ## i64
if loaded != out_rank || ffw_verify_current_exact(endpoint,n) == 0
  << "PROJECTIVE_CIRCUIT5 error=full-gate"
  exit(2)
written = 0 ## i64
if args.size() > 4
  written = ffw_dump_current(endpoint,args[4])
  if written != out_rank
    << "PROJECTIVE_CIRCUIT5 error=write"
    exit(2)
  reparsed = i64[state_size]
  checked = ffw_load_scheme_cap(reparsed,args[4],n,capacity,96101 + nonce,0,1,1,1) ## i64
  if checked != out_rank || ffw_verify_current_exact(reparsed,n) == 0
    << "PROJECTIVE_CIRCUIT5 error=reparse"
    exit(2)
<< "PROJECTIVE_CIRCUIT5 n=" + n.to_s() + " rank=" + rank.to_s() + " density=" + meta[10].to_s() + " quads=" + meta[0].to_s() + " circuits=" + meta[1].to_s() + " d=" + meta[2].to_s() + " local_le2=" + meta[3].to_s() + " changed=" + meta[4].to_s() + " drops=" + meta[5].to_s() + " neutral=" + meta[6].to_s() + " best_rank=" + meta[7].to_s() + " best_density=" + meta[8].to_s() + " best_local_delta=" + meta[9].to_s() + " axis=" + meta[13].to_s() + " exact=1 capped=" + meta[11].to_s() + " written=" + written.to_s() + " ms=" + search_ms.to_s()

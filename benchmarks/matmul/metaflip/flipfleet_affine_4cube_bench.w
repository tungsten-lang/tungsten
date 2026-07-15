# Usage: flipfleet_affine_4cube_bench seed n basis_cap nonce [output]

use flipfleet_affine_4cube

args = argv()
if args.size() < 4
  << "usage: flipfleet_affine_4cube_bench seed n basis_cap nonce [output]"
  exit(2)
path = args[0]
n = args[1].to_i() ## i64
basis_cap = args[2].to_i() ## i64
nonce = args[3].to_i() ## i64
if n < 2 || n > 7 || basis_cap < 0 || nonce < 0
  << "AFFINE_4CUBE error=arguments"
  exit(2)
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
source = i64[state_size]
rank = ffw_load_scheme_cap(source,path,n,capacity,95501 + nonce,0,1,1,1) ## i64
if rank < 5 || ffw_verify_current_exact(source,n) == 0
  << "AFFINE_4CUBE error=load path=" + path
  exit(2)
us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
if ffw_export_current(source,us,vs,ws) != rank
  << "AFFINE_4CUBE error=export"
  exit(2)

circuit_u = i64[16]
circuit_v = i64[16]
circuit_w = i64[16]
meta = i64[12]
started = ccall("__w_clock_ms") ## i64
count = ffa4_search(us,vs,ws,rank,basis_cap,nonce,circuit_u,circuit_v,circuit_w,meta) ## i64
search_ms = ccall("__w_clock_ms") - started ## i64
if count == 0
  << "AFFINE_4CUBE n=" + n.to_s() + " rank=" + rank.to_s() + " candidate=none bases=" + meta[0].to_s() + " independent=" + meta[1].to_s() + " valid=" + meta[2].to_s() + " capped=" + meta[9].to_s() + " ms=" + search_ms.to_s()
  exit(0)
if count != 16 || ffa4_zero_relation(circuit_u,circuit_v,circuit_w,count) == 0
  << "AFFINE_4CUBE error=circuit-gate"
  exit(2)
out_u = i64[capacity]
out_v = i64[capacity]
out_w = i64[capacity]
out_rank = ffcis3_apply_circuit(us,vs,ws,rank,circuit_u,circuit_v,circuit_w,count,out_u,out_v,out_w) ## i64
if out_rank != rank + meta[4]
  << "AFFINE_4CUBE error=rank-accounting"
  exit(2)
endpoint = i64[state_size]
loaded = ffw_init_terms_cap(endpoint,out_u,out_v,out_w,out_rank,n,capacity,95601 + nonce,0,1,1,1) ## i64
if loaded != out_rank || ffw_verify_current_exact(endpoint,n) == 0
  << "AFFINE_4CUBE error=full-gate"
  exit(2)
written = 0 ## i64
if args.size() > 4
  written = ffw_dump_current(endpoint,args[4])
  if written != out_rank
    << "AFFINE_4CUBE error=write"
    exit(2)
  reparsed = i64[state_size]
  checked = ffw_load_scheme_cap(reparsed,args[4],n,capacity,95701 + nonce,0,1,1,1) ## i64
  if checked != out_rank || ffw_verify_current_exact(reparsed,n) == 0
    << "AFFINE_4CUBE error=reparse"
    exit(2)

<< "AFFINE_4CUBE n=" + n.to_s() + " rank=" + rank.to_s() + " density=" + meta[10].to_s() + " bases=" + meta[0].to_s() + " independent=" + meta[1].to_s() + " valid=" + meta[2].to_s() + " drops=" + meta[6].to_s() + " neutral=" + meta[7].to_s() + " debt_le2=" + meta[8].to_s() + " max_overlap=" + meta[3].to_s() + " best_delta=" + meta[4].to_s() + " endpoint_rank=" + out_rank.to_s() + " endpoint_density=" + meta[5].to_s() + " exact=1 capped=" + meta[9].to_s() + " written=" + written.to_s() + " ms=" + search_ms.to_s()

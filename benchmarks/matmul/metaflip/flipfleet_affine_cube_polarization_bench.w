# Bounded CPU-only benchmark for affine-cube polarization circuits.
#
# Usage:
#   flipfleet_affine_cube_polarization_bench seed n frame_cap origin_samples cube_cap nonce [output]

use flipfleet_affine_cube_polarization

args = argv()
if args.size() < 6
  << "usage: flipfleet_affine_cube_polarization_bench seed n frame_cap origin_samples cube_cap nonce [output]"
  exit(2)
path = args[0]
n = args[1].to_i() ## i64
frame_cap = args[2].to_i() ## i64
origin_samples = args[3].to_i() ## i64
cube_cap = args[4].to_i() ## i64
nonce = args[5].to_i() ## i64
if n < 2 || n > 7 || frame_cap < 0 || origin_samples < 1 || cube_cap < 0 || nonce < 0
  << "AFFINE_CUBE_POLARIZATION error=arguments"
  exit(2)

capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
source = i64[state_size]
rank = ffw_load_scheme_cap(source,path,n,capacity,94601 + nonce,0,1,1,1) ## i64
if rank < 4 || ffw_verify_current_exact(source,n) == 0
  << "AFFINE_CUBE_POLARIZATION error=load path=" + path
  exit(2)
us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
if ffw_export_current(source,us,vs,ws) != rank
  << "AFFINE_CUBE_POLARIZATION error=export"
  exit(2)

circuit_u = i64[14]
circuit_v = i64[14]
circuit_w = i64[14]
meta = i64[24]
started = ccall("__w_clock_ms") ## i64
circuit_count = ffacp_search(us,vs,ws,rank,frame_cap,origin_samples,cube_cap,nonce,circuit_u,circuit_v,circuit_w,meta) ## i64
search_ms = ccall("__w_clock_ms") - started ## i64
if circuit_count == 0
  << "AFFINE_CUBE_POLARIZATION n=" + n.to_s() + " rank=" + rank.to_s() + " density=" + ffw_current_bits(source).to_s() + " candidate=none frames=" + meta[0].to_s() + " independent=" + meta[1].to_s() + " structural=" + meta[2].to_s() + " origins=" + meta[3].to_s() + " pair_edges=" + meta[13].to_s() + " parallel_pairs=" + meta[14].to_s() + " cube_trials=" + meta[15].to_s() + " live_cubes=" + meta[16].to_s() + " cap=" + meta[18].to_s() + " ms=" + search_ms.to_s()
  exit(0)
if circuit_count != 14 || meta[17] != 1 || ffacp_is_primitive(circuit_u,circuit_v,circuit_w,14) == 0
  << "AFFINE_CUBE_POLARIZATION error=circuit-gate"
  exit(2)

out_u = i64[capacity]
out_v = i64[capacity]
out_w = i64[capacity]
out_rank = ffcis3_apply_circuit(us,vs,ws,rank,circuit_u,circuit_v,circuit_w,14,out_u,out_v,out_w) ## i64
if out_rank != rank + meta[9]
  << "AFFINE_CUBE_POLARIZATION error=rank-accounting"
  exit(2)
endpoint = i64[state_size]
loaded = ffw_init_terms_cap(endpoint,out_u,out_v,out_w,out_rank,n,capacity,94701 + nonce,0,1,1,1) ## i64
full_exact = 0 ## i64
if loaded == out_rank && ffw_verify_current_exact(endpoint,n) == 1
  full_exact = 1
if full_exact == 0
  << "AFFINE_CUBE_POLARIZATION error=full-gate"
  exit(2)

written = 0 ## i64
if args.size() > 6
  written = ffw_dump_current(endpoint,args[6])
  if written != out_rank
    << "AFFINE_CUBE_POLARIZATION error=write"
    exit(2)
  reparsed = i64[state_size]
  checked = ffw_load_scheme_cap(reparsed,args[6],n,capacity,94801 + nonce,0,1,1,1) ## i64
  if checked != out_rank || ffw_verify_current_exact(reparsed,n) == 0
    << "AFFINE_CUBE_POLARIZATION error=reparse"
    exit(2)

<< "AFFINE_CUBE_POLARIZATION n=" + n.to_s() + " rank=" + rank.to_s() + " density=" + meta[23].to_s() + " frames=" + meta[0].to_s() + " independent=" + meta[1].to_s() + " structural=" + meta[2].to_s() + " max_correction_overlap=" + meta[22].to_s() + " origins=" + meta[3].to_s() + " pair_edges=" + meta[13].to_s() + " parallel_pairs=" + meta[14].to_s() + " cube_trials=" + meta[15].to_s() + " live_cubes=" + meta[16].to_s() + " scored=" + meta[5].to_s() + " drops=" + meta[6].to_s() + " neutral=" + meta[7].to_s() + " debt_le2=" + meta[8].to_s() + " best_delta=" + meta[9].to_s() + " overlap=" + meta[11].to_s() + " source_kind=" + meta[20].to_s() + " endpoint_rank=" + out_rank.to_s() + " endpoint_density=" + meta[10].to_s() + " primitive=" + meta[17].to_s() + " full_exact=" + full_exact.to_s() + " capped=" + meta[18].to_s() + " written=" + written.to_s() + " ms=" + search_ms.to_s()

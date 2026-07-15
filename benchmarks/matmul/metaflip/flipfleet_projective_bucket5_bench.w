# Usage: flipfleet_projective_bucket5_bench seed n circuit_cap debt_cap nonce [output]

use flipfleet_projective_bucket5

args = argv()
if args.size() < 5
  << "usage: flipfleet_projective_bucket5_bench seed n circuit_cap debt_cap nonce [output]"
  exit(2)
path = args[0]
n = args[1].to_i() ## i64
circuit_cap = args[2].to_i() ## i64
debt_cap = args[3].to_i() ## i64
nonce = args[4].to_i() ## i64
if n < 2 || n > 7 || circuit_cap < 0 || debt_cap < 0 || nonce < 0
  << "PROJECTIVE_BUCKET5 error=arguments"
  exit(2)
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
source = i64[state_size]
rank = ffw_load_scheme_cap(source,path,n,capacity,983001 + nonce,0,1,1,1) ## i64
if rank < 5 || ffw_verify_current_exact(source,n) == 0
  << "PROJECTIVE_BUCKET5 error=load"
  exit(2)
candidate = i64[state_size]
meta = i64[30]
started = ccall("__w_clock_ms") ## i64
out_rank = ffpb5_search_state(source,circuit_cap,debt_cap,nonce,candidate,meta) ## i64
search_ms = ccall("__w_clock_ms") - started ## i64
written = 0 ## i64
if out_rank > 0 && args.size() > 5
  written = ffw_dump_current(candidate,args[5])
  if written != out_rank
    << "PROJECTIVE_BUCKET5 error=write"
    exit(2)
  reparsed = i64[state_size]
  checked = ffw_load_scheme_cap(reparsed,args[5],n,capacity,984001 + nonce,0,1,1,1) ## i64
  if checked != out_rank || ffw_verify_current_exact(reparsed,n) == 0
    << "PROJECTIVE_BUCKET5 error=reparse"
    exit(2)
if out_rank == 0
  << "PROJECTIVE_BUCKET5 n=" + n.to_s() + " rank=" + rank.to_s() + " density=" + meta[15].to_s() + " candidate=none quads=" + meta[0].to_s() + " circuits=" + meta[1].to_s() + " captured=" + meta[2].to_s() + " masks=" + meta[3].to_s() + " nonzero_d=" + meta[4].to_s() + " local_exact=" + meta[5].to_s() + " min_debt=" + meta[24].to_s() + " debt_hist=" + meta[25].to_s() + "/" + meta[26].to_s() + "/" + meta[27].to_s() + "/" + meta[28].to_s() + "/" + meta[29].to_s() + " admitted=" + meta[6].to_s() + " full=" + meta[7].to_s() + " failures=" + meta[8].to_s() + " unique=" + meta[23].to_s() + " max_bucket=" + meta[22].to_s() + " capped=" + meta[16].to_s() + " ms=" + search_ms.to_s()
  exit(0)
<< "PROJECTIVE_BUCKET5 n=" + n.to_s() + " rank=" + rank.to_s() + " density=" + meta[15].to_s() + " quads=" + meta[0].to_s() + " circuits=" + meta[1].to_s() + " captured=" + meta[2].to_s() + " masks=" + meta[3].to_s() + " nonzero_d=" + meta[4].to_s() + " local_exact=" + meta[5].to_s() + " min_debt=" + meta[24].to_s() + " debt_hist=" + meta[25].to_s() + "/" + meta[26].to_s() + "/" + meta[27].to_s() + "/" + meta[28].to_s() + "/" + meta[29].to_s() + " admitted=" + meta[6].to_s() + " full=" + meta[7].to_s() + " failures=" + meta[8].to_s() + " drops=" + meta[9].to_s() + " neutral=" + meta[10].to_s() + " shoulders=" + meta[11].to_s() + " best_rank=" + meta[12].to_s() + " best_density=" + meta[13].to_s() + " axis=" + meta[18].to_s() + " local=" + meta[19].to_s() + "to" + meta[20].to_s() + " subset=" + meta[21].to_s() + " unique=" + meta[23].to_s() + " max_bucket=" + meta[22].to_s() + " exact=1 capped=" + meta[16].to_s() + " written=" + written.to_s() + " ms=" + search_ms.to_s()

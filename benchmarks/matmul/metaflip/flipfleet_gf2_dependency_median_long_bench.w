# Usage: flipfleet_gf2_dependency_median_long_bench seed n d_cap debt_cap nonce minimum_buckets [output]

use flipfleet_gf2_dependency_median

args = argv()
if args.size() < 6
  << "usage: flipfleet_gf2_dependency_median_long_bench seed n d_cap debt_cap nonce minimum_buckets [output]"
  exit(2)
path = args[0]
n = args[1].to_i() ## i64
d_cap = args[2].to_i() ## i64
debt_cap = args[3].to_i() ## i64
nonce = args[4].to_i() ## i64
minimum_buckets = args[5].to_i() ## i64
if n < 2 || n > 7 || d_cap < 0 || debt_cap < 0 || nonce < 0 || minimum_buckets < 2
  << "GF2_DEPENDENCY_LONG error=arguments"
  exit(2)
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
source = i64[state_size]
rank = ffw_load_scheme_cap(source,path,n,capacity,998001 + nonce,0,1,1,1) ## i64
if rank < 2 || ffw_verify_current_exact(source,n) == 0
  << "GF2_DEPENDENCY_LONG error=load"
  exit(2)
candidate = i64[state_size]
meta = i64[32]
started = ccall("__w_clock_ms") ## i64
out_rank = ffgdm_search_state_min(source,d_cap,debt_cap,nonce,minimum_buckets,candidate,meta) ## i64
search_ms = ccall("__w_clock_ms") - started ## i64
written = 0 ## i64
if out_rank > 0 && args.size() > 6
  written = ffw_dump_current(candidate,args[6])
  if written != out_rank
    << "GF2_DEPENDENCY_LONG error=write"
    exit(2)
prefix = "GF2_DEPENDENCY_LONG n=" + n.to_s() + " rank=" + rank.to_s() + " minimum=" + minimum_buckets.to_s() + " d_unique=" + meta[1].to_s() + " deltas=" + meta[3].to_s() + "/" + meta[4].to_s() + "/" + meta[5].to_s() + " dependencies=" + meta[7].to_s() + " families=" + meta[8].to_s() + "/" + meta[9].to_s() + "/" + meta[10].to_s() + " full=" + meta[13].to_s() + " failures=" + meta[14].to_s() + " max_dependency=" + meta[31].to_s()
if out_rank == 0
  << prefix + " candidate=none ms=" + search_ms.to_s()
  exit(0)
<< prefix + " best_rank=" + meta[18].to_s() + " best_density=" + meta[19].to_s() + " dependency=" + meta[25].to_s() + " local=" + meta[26].to_s() + "to" + meta[27].to_s() + " predicted=" + meta[28].to_s() + " exact=1 written=" + written.to_s() + " ms=" + search_ms.to_s()

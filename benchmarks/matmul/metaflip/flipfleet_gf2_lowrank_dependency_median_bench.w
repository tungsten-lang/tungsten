# Usage: flipfleet_gf2_lowrank_dependency_median_bench seed n d_cap debt_cap nonce minimum_buckets minimum_d_rank [output]

use flipfleet_gf2_lowrank_dependency_median

args = argv()
if args.size() < 7
  << "usage: flipfleet_gf2_lowrank_dependency_median_bench seed n d_cap debt_cap nonce minimum_buckets minimum_d_rank [output]"
  exit(2)
path = args[0]
n = args[1].to_i() ## i64
d_cap = args[2].to_i() ## i64
debt_cap = args[3].to_i() ## i64
nonce = args[4].to_i() ## i64
minimum_buckets = args[5].to_i() ## i64
minimum_d_rank = args[6].to_i() ## i64
if n < 2 || n > 7 || d_cap < 0 || debt_cap < 0 || debt_cap > 1 || nonce < 0 || minimum_buckets < 2 || minimum_d_rank < 1 || minimum_d_rank > 2
  << "GF2_LOWRANK_DEPENDENCY error=arguments"
  exit(2)
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
source = i64[state_size]
rank = ffw_load_scheme_cap(source,path,n,capacity,1002001 + nonce,0,1,1,1) ## i64
if rank < 2 || ffw_verify_current_exact(source,n) == 0
  << "GF2_LOWRANK_DEPENDENCY error=load"
  exit(2)
candidate = i64[state_size]
meta = i64[41]
started = ccall("__w_clock_ms") ## i64
out_rank = fflrd_search_state_filtered(source,d_cap,debt_cap,nonce,minimum_buckets,minimum_d_rank,candidate,meta) ## i64
search_ms = ccall("__w_clock_ms") - started ## i64
written = 0 ## i64
if out_rank > 0 && args.size() > 7
  written = ffw_dump_current(candidate,args[7])
  if written != out_rank
    << "GF2_LOWRANK_DEPENDENCY error=write"
    exit(2)
  reparsed = i64[state_size]
  checked = ffw_load_scheme_cap(reparsed,args[7],n,capacity,1003001 + nonce,0,1,1,1) ## i64
  if checked != out_rank || ffw_verify_current_exact(reparsed,n) == 0
    << "GF2_LOWRANK_DEPENDENCY error=reparse"
    exit(2)
prefix = "GF2_LOWRANK_DEPENDENCY n=" + n.to_s() + " rank=" + rank.to_s() + " density=" + meta[26].to_s() + " minimum=" + minimum_buckets.to_s() + " minimum_d_rank=" + minimum_d_rank.to_s() + " atoms=" + meta[0].to_s() + " d_unique=" + meta[1].to_s() + " singleton=" + meta[2].to_s() + " pairs=" + meta[3].to_s() + " duplicates=" + meta[4].to_s() + " d_ranks=" + meta[5].to_s() + "/" + meta[6].to_s() + " buckets=" + meta[7].to_s() + " deltas=" + meta[8].to_s() + "/" + meta[9].to_s() + "/" + meta[10].to_s() + "/" + meta[11].to_s() + " dependencies=" + meta[12].to_s() + " families=" + meta[13].to_s() + "/" + meta[14].to_s() + "/" + meta[15].to_s() + " local_exact=" + meta[16].to_s() + " full=" + meta[18].to_s() + " failures=" + meta[19].to_s() + " endpoint=" + meta[20].to_s() + "/" + meta[21].to_s() + "/" + meta[22].to_s() + " max_dependency=" + meta[39].to_s() + " axes=" + meta[40].to_s() + " capped=" + meta[37].to_s()
if out_rank == 0
  << prefix + " candidate=none ms=" + search_ms.to_s()
  exit(0)
<< prefix + " best_rank=" + meta[23].to_s() + " best_density=" + meta[24].to_s() + " axis=" + meta[27].to_s() + " d_rank=" + meta[28].to_s() + " d=" + meta[29].to_s() + "x" + meta[30].to_s() + "+" + meta[31].to_s() + "x" + meta[32].to_s() + " dependency=" + meta[33].to_s() + " local=" + meta[34].to_s() + "to" + meta[35].to_s() + " predicted=" + meta[36].to_s() + " exact=1 written=" + written.to_s() + " ms=" + search_ms.to_s()

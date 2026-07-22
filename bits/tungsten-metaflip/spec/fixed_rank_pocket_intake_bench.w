use ../lib/metaflip/strategies/fixed_rank_pocket

# Cold intake probe for an arbitrary exact 7x7 archive artifact.  This keeps
# campaign harvesting separate from the production racer while answering the
# useful question immediately: does the newly discovered basin contain a
# deterministic strict-density fixed-rank pocket closure?
if ARGV.size() < 1
  << "usage: fixed_rank_pocket_intake_bench SCHEME [ENDPOINT]"
  exit(2)

source_path = ARGV[0]
endpoint_path = ""
if ARGV.size() > 1
  endpoint_path = ARGV[1]

capacity = 320 ## i64
state = i64[ffw_state_size(capacity)]
rank = ffw_load_scheme_cap(state, source_path, 7, capacity, 270001, 4, 1, 25000000, 6250000) ## i64
if rank != 247 || ffw_verify_best_exact(state, 7) != 1
  << "FIXED_RANK_POCKET_INTAKE_FAIL load-or-exact source=" + source_path
  exit(1)

source_density = ffw_best_bits(state) ## i64
meta = i64[19]
started = ccall("__w_clock_ms") ## i64
applied = ffpa_apply_greedy_closure(state, 8, 4, 5, 64, 5, 5, 512, 12, meta) ## i64
elapsed = ccall("__w_clock_ms") - started ## i64
endpoint_density = ffw_best_bits(state) ## i64
if ffw_best_rank(state) != 247 || ffw_verify_best_exact(state, 7) != 1
  << "FIXED_RANK_POCKET_INTAKE_FAIL endpoint-exact source=" + source_path
  exit(1)
if endpoint_density > source_density
  << "FIXED_RANK_POCKET_INTAKE_FAIL density-regressed source=" + source_path
  exit(1)

saved = 0 ## i64
if applied == 1 && endpoint_path.size() > 0
  dumped = ffw_dump_best(state, endpoint_path) ## i64
  if dumped != 247
    << "FIXED_RANK_POCKET_INTAKE_FAIL dump source=" + source_path
    exit(1)
  saved = 1

<< "FIXED_RANK_POCKET_INTAKE source=" + source_path + " rank=247 density=" + source_density.to_s() + "->" + endpoint_density.to_s() + " gain=" + meta[5].to_s() + " applied=" + meta[6].to_s() + " prefix=" + meta[7].to_s() + " rounds=" + meta[15].to_s() + " tickets=" + meta[13].to_s() + " proposals=" + meta[1].to_s() + " barrier=" + meta[8].to_s() + " exact-rejects=" + meta[16].to_s() + " elapsed-ms=" + elapsed.to_s() + " saved=" + saved.to_s()

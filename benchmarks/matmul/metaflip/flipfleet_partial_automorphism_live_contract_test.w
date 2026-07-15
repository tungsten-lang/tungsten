use flipfleet_partial_automorphism_nullspace
use flipfleet_profiles
use flipfleet_basin_identity

-> ffpanc_expect(label, condition) (String bool) i64
  if !condition
    << "PARTIAL_AUTOMORPHISM_LIVE_CONTRACT_FAIL " + label
    exit(1)
  1

-> ffpanc_term_in(state, u, v, w) (i64[] i64 i64 i64) i64
  rank = ffw_best_rank(state) ## i64
  i = 0 ## i64
  while i < rank
    if ffw_read_best_u(state, i) == u && ffw_read_best_v(state, i) == v && ffw_read_best_w(state, i) == w
      return 1
    i += 1
  0

# Match the production archive's distance rule, including its inexpensive
# D3/reversal canonical-identity duplicate gate.
-> ffpanc_archive_distance(left, right) (i64[] i64[]) i64
  if ffbi_best_id(left) == ffbi_best_id(right)
    return 0
  left_rank = ffw_best_rank(left) ## i64
  right_rank = ffw_best_rank(right) ## i64
  common = 0 ## i64
  i = 0 ## i64
  while i < left_rank
    common += ffpanc_term_in(right, ffw_read_best_u(left, i), ffw_read_best_v(left, i), ffw_read_best_w(left, i))
    i += 1
  left_rank + right_rank - common - common

# The live policy is deliberately 7x7-only, including the first-call path.
n = 2 ## i64
while n <= 8
  if n != 7
    ffpanc_expect("non-7 first call suppressed", ffpan_tunnel_due(n, 0, 0 - 1, 60000) == 0)
    ffpanc_expect("non-7 cooldown call suppressed", ffpan_tunnel_due(n, 120000, 0, 60000) == 0)
  n += 1
ffpanc_expect("7x7 first call due", ffpan_tunnel_due(7, 0, 0 - 1, 60000) == 1)
ffpanc_expect("7x7 cooldown held", ffpan_tunnel_due(7, 59999, 0, 60000) == 0)
ffpanc_expect("7x7 cooldown released", ffpan_tunnel_due(7, 60000, 0, 60000) == 1)
ffpanc_expect("clock reversal held", ffpan_tunnel_due(7, 99, 100, 1) == 0)

# Stride 37 is coprime to the 189 elementary 7x7 generators, so the minute
# cadence visits every possible start exactly once before repeating.
generator_count = ffpan_elementary_count(7) ## i64
seen = i64[generator_count]
nonce = 0 ## i64
i = 0 ## i64
while i < generator_count
  ffpanc_expect("nonce in range", nonce >= 0 && nonce < generator_count)
  ffpanc_expect("nonce rotation unique", seen[nonce] == 0)
  seen[nonce] = 1
  nonce = ffpan_next_nonce(7, nonce, 37)
  i += 1
ffpanc_expect("nonce full cycle", nonce == 0)

n7 = 7 ## i64
capacity = ffw_default_capacity(n7) ## i64
state_size = ffw_state_size(capacity) ## i64
source = i64[state_size]
source_path = "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt"
rank = ffw_load_scheme_cap(source, source_path, n7, capacity, 91001, 0, 1, 1, 1) ## i64
ffpanc_expect("source exact", rank == 247 && ffw_verify_best_exact(source, n7) == 1)

us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
ffpanc_expect("source export", ffw_export_best(source, us, vs, ws) == rank)
out_u = i64[capacity]
out_v = i64[capacity]
out_w = i64[capacity]
meta = i64[18]
workspace = FFPANWorkspace.new(rank, n7, capacity)
ffpanc_expect("fresh workspace", workspace.scan_count() == 0 && workspace.max_rank() == rank)

started_ms = ccall("__w_clock_ms") ## i64
found = ffpan_find_elementary_escape(us, vs, ws, rank, n7, capacity, 0, 5, workspace, out_u, out_v, out_w, meta) ## i64
first_ms = ccall("__w_clock_ms") - started_ms ## i64
ffpanc_expect("genuine finder endpoint", found == rank && meta[6] == 1 && meta[15] == 0)
ffpanc_expect("finder exhaustive gate", meta[14] == 1 && meta[12] >= 4 && meta[13] > 0)
ffpanc_expect("first scan retained", workspace.scan_count() == 1)

endpoint = i64[state_size]
loaded = ffw_init_terms_cap(endpoint, out_u, out_v, out_w, found, n7, capacity, 91003, 0, 1, 1, 1) ## i64
ffpanc_expect("endpoint full exact", loaded == found && ffw_verify_best_exact(endpoint, n7) == 1)

# At startup the archive has fewer than 16 checked-in frontier schemes.  The
# new endpoint must clear the exact production distance/identity threshold
# against every one of them, making action=append (1) in ffn_archive_add_copy.
paths = ffp_frontier_seed_paths(n7)
ffpanc_expect("archive has append capacity", paths.size() < 16)
minimum_distance = 999999999 ## i64
path_index = 0 ## i64
while path_index < paths.size()
  archived = i64[state_size]
  archived_rank = ffw_load_scheme_cap(archived, paths[path_index], n7, capacity, 91101 + path_index, 0, 1, 1, 1) ## i64
  ffpanc_expect("frontier archive exact", archived_rank == rank && ffw_verify_best_exact(archived, n7) == 1)
  distance = ffpanc_archive_distance(archived, endpoint) ## i64
  if distance < minimum_distance
    minimum_distance = distance
  path_index += 1
ffpanc_expect("endpoint archive-admissible", minimum_distance >= 4)

# A rank drop changes only the active prefix; the high-water buffers and scan
# counter survive.  Restoring the frontier rank and scanning from the next
# nonce therefore exercises the same workspace rather than allocating again.
ffpanc_expect("workspace lower-rank reuse", workspace.configure_rank(rank - 1) == rank - 1 && workspace.max_rank() == rank && workspace.scan_count() == 1)
ffpanc_expect("workspace rank restore", workspace.configure_rank(rank) == rank)
next_nonce = ffpan_next_nonce(n7, 0, 37) ## i64
started_ms = ccall("__w_clock_ms")
second = ffpan_find_elementary_escape(us, vs, ws, rank, n7, capacity, next_nonce, 5, workspace, out_u, out_v, out_w, meta) ## i64
second_ms = ccall("__w_clock_ms") - started_ms ## i64
ffpanc_expect("rotated finder remains sound", second == rank && meta[6] == 1 && meta[15] == 0)
ffpanc_expect("workspace reused across calls", workspace.scan_count() == 2 && workspace.max_rank() == rank)

<< "flipfleet_partial_automorphism_live_contract_test: pass generators=" + generator_count.to_s() + " archive_min=" + minimum_distance.to_s() + " scans=" + workspace.scan_count().to_s() + " first_ms=" + first_ms.to_s() + " second_ms=" + second_ms.to_s()

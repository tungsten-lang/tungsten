# One-shot host engine for the bounded exact-move pool.
#
# Kinds retain the research move numbers so logs and saved telemetry remain
# comparable: 1 mode-locked solve, 5 two-level debt MITM, and 10 dynamic
# syzygy mining.  Every strategy exact-gates its own candidates; this wrapper
# independently rebuilds, serializes, reloads, and verifies the winner before
# publication.

use ../scheme
use ../strategies/pooled_exact
use ../strategies/mode_locked
use ../strategies/debt_mitm
use ../strategies/dynamic_syzygy

-> ffpem_kind_supported(kind) (i64) i64
  if kind == 1 || kind == 5 || kind == 10
    return 1
  0

-> ffpem_kind_name(kind) (i64)
  if kind == 1
    return "mode-locked"
  if kind == 5
    return "debt-mitm"
  if kind == 10
    return "dynamic-syzygy"
  "invalid"

-> ffpem_clear(values) (i64[]) i64
  i = 0 ## i64
  while i < values.size()
    values[i] = 0
    i += 1
  1

# Metadata (capacity >= 20): kind, budget, nonce, source rank/density,
# attempts, exact, rank hits, density hits, neutral, rejects, candidates,
# output rank/density, elapsed ms, final exact gate, reserved...
-> ffpem_run(seed_path, output_path, n, kind, budget, nonce, meta) (String String i64 i64 i64 i64 i64[]) i64
  if meta.size() < 20
    return 0 - 1
  z = ffpem_clear(meta) ## i64
  meta[0] = kind
  meta[1] = budget
  meta[2] = nonce
  if seed_path.size() < 1 || output_path.size() < 1 || seed_path == output_path
    return 0 - 1
  if n < 2 || n > 7 || ffpem_kind_supported(kind) == 0
    return 0 - 1
  if budget < 1 || budget > 4096 || nonce < 0
    return 0 - 1
  if write_file(output_path, "") == false
    return 0 - 3

  capacity = ffw_default_capacity(n) ## i64
  source = i64[ffw_state_size(capacity)]
  source_rank = ffw_load_scheme_cap(source, seed_path, n, capacity, 85001 + (nonce % 1000000) * 17, 0, 1, 1, 1) ## i64
  if source_rank < 1 || ffw_verify_best_exact(source, n) == 0
    return 0 - 2
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  if ffw_export_best(source, source_u, source_v, source_w) != source_rank
    return 0 - 2
  source_density = ffpe_density(source_u, source_v, source_w, source_rank) ## i64
  meta[3] = source_rank
  meta[4] = source_density

  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  stats = i64[8]
  started = ccall("__w_clock_ms") ## i64
  result = 0 ## i64
  if kind == 1
    result = ffml_search(source_u, source_v, source_w, source_rank, n, n, n, budget, nonce, out_u, out_v, out_w, stats)
  if kind == 5
    result = ffdm_search(source_u, source_v, source_w, source_rank, n, n, n, budget, nonce, out_u, out_v, out_w, stats)
  if kind == 10
    result = ffds_search(source_u, source_v, source_w, source_rank, n, n, n, budget, nonce, out_u, out_v, out_w, stats)
  elapsed = ccall("__w_clock_ms") - started ## i64
  meta[5] = stats[0]
  meta[6] = stats[1]
  meta[7] = stats[2]
  meta[8] = stats[3]
  meta[9] = stats[4]
  meta[10] = stats[5]
  meta[11] = stats[6]
  meta[14] = elapsed
  if result < 1
    << "CPU_POOL_EXACT_MOVE kind=" + ffpem_kind_name(kind) + " n=" + n.to_s() + " rank=" + source_rank.to_s() + " budget=" + budget.to_s() + " nonce=" + nonce.to_s() + " attempts=" + stats[0].to_s() + " hit=0 elapsed_ms=" + elapsed.to_s()
    return 0

  result_density = ffpe_density(out_u, out_v, out_w, result) ## i64
  meta[12] = result
  meta[13] = result_density
  # Rank-neutral endpoints are useful for diversity only when they do not
  # surrender the source's density objective.  Rank debt belongs to the
  # opener pool, not to these closing moves.
  if result > source_rank || (result == source_rank && result_density > source_density)
    return 0
  if ffpe_verify(out_u, out_v, out_w, result, n, n, n) == 0
    return 0 - 4

  endpoint = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(endpoint, out_u, out_v, out_w, result, n, capacity, 86001 + (nonce % 1000000) * 19, 0, 1, 1, 1) ## i64
  if loaded != result || ffw_verify_current_exact(endpoint, n) == 0
    return 0 - 4
  if ffw_dump_current(endpoint, output_path) != result
    z = write_file(output_path, "") ## Bool
    return 0 - 3

  check = i64[ffw_state_size(capacity)]
  checked = ffw_load_scheme_cap(check, output_path, n, capacity, 87001 + (nonce % 1000000) * 23, 0, 1, 1, 1) ## i64
  if checked != result || ffw_verify_best_exact(check, n) == 0
    z = write_file(output_path, "")
    return 0 - 4
  check_u = i64[capacity]
  check_v = i64[capacity]
  check_w = i64[capacity]
  if ffw_export_best(check, check_u, check_v, check_w) != result
    z = write_file(output_path, "")
    return 0 - 4
  if ffpe_density(check_u, check_v, check_w, result) != result_density
    z = write_file(output_path, "")
    return 0 - 4
  meta[15] = 1
  << "CPU_POOL_EXACT_MOVE kind=" + ffpem_kind_name(kind) + " n=" + n.to_s() + " rank=" + source_rank.to_s() + "->" + result.to_s() + " density=" + source_density.to_s() + "->" + result_density.to_s() + " budget=" + budget.to_s() + " nonce=" + nonce.to_s() + " attempts=" + stats[0].to_s() + " hit=1 elapsed_ms=" + elapsed.to_s()
  result

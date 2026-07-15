# One-shot 5x5 whole-frontier kernel-shear child.
#
# The child changes at most one factor axis per live term, so every kernel
# dependency is a finite exact involution.  It publishes only beyond-one-flip
# endpoints that pass a fresh full-tensor rebuild and serialized reparse.

use metaflip_worker
use flipfleet_kernel_shear

-> ffgks_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> ffgks_remove(path) (String) i64
  if system("/bin/rm -f " + ffgks_shell_quote(path))
    return 1
  0

# Return a verified endpoint rank, zero for an ordinary miss, and a negative
# value only for malformed input or publication failure. Metadata:
# mode, plan, columns, basis, dependencies, changed, work words, solve status,
# input rank, output rank, exact gate, elapsed ms, reserved...
-> ffgks_run_engine(seed_path, output_path, nonce, meta) (String String i64 i64[]) i64
  if seed_path.size() < 1 || output_path.size() < 1 || seed_path == output_path || nonce < 0 || meta.size() < 16
    return 0 - 1
  if ffgks_remove(output_path) == 0
    return 0 - 4
  i = 0 ## i64
  while i < 16
    meta[i] = 0
    i += 1

  n = 5 ## i64
  capacity = ffw_default_capacity(n) ## i64
  state_size = ffw_state_size(capacity) ## i64
  source = i64[state_size]
  rank = ffw_load_scheme_cap(source, seed_path, n, capacity, 91009 + (nonce % 1000000) * 17, 0, 1, 1, 1) ## i64
  if rank < 3 || ffw_verify_current_exact(source, n) == 0
    return 0 - 2
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  if ffw_export_current(source, source_u, source_v, source_w) != rank
    return 0 - 2

  plan = nonce % 64 ## i64
  mode = plan ## i64
  if mode > 7
    mode = 7
  axis_nonce = 104729 + plan * 130363 ## i64
  axes = i64[capacity]
  if ffks_fill_axis_plan(source_u, source_v, source_w, rank, mode, axis_nonce, axes) != rank
    return 0 - 2
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  solve_meta = i64[8]
  started = ccall("__w_clock_ms") ## i64
  found = ffks_find_novel_bounded(source_u, source_v, source_w, rank, axes, n * n, 1000000, out_u, out_v, out_w, solve_meta) ## i64
  elapsed = ccall("__w_clock_ms") - started ## i64
  meta[0] = mode
  meta[1] = plan
  meta[2] = solve_meta[0]
  meta[3] = solve_meta[1]
  meta[4] = solve_meta[2]
  meta[5] = solve_meta[3]
  meta[6] = solve_meta[6]
  meta[7] = solve_meta[7]
  meta[8] = rank
  meta[11] = elapsed
  if found != rank
    << "CPU_POOL_GLOBAL_SHEAR_RESULT n=5 rank=" + rank.to_s() + " plan=" + plan.to_s() + " mode=" + mode.to_s() + " dependencies=" + solve_meta[2].to_s() + " hit=0 elapsed_ms=" + elapsed.to_s()
    return 0

  endpoint = i64[state_size]
  endpoint_rank = ffw_init_terms_cap(endpoint, out_u, out_v, out_w, rank, n, capacity, 92009 + (nonce % 1000000) * 19, 0, 1, 1, 1) ## i64
  meta[9] = endpoint_rank
  if endpoint_rank < 1 || endpoint_rank > rank || solve_meta[3] < 3 || ffw_verify_current_exact(endpoint, n) == 0
    return 0
  meta[10] = 1
  written = ffw_dump_current(endpoint, output_path) ## i64
  if written != endpoint_rank
    z = ffgks_remove(output_path) ## i64
    return 0 - 4
  check = i64[state_size]
  checked = ffw_load_scheme_cap(check, output_path, n, capacity, 93009 + (nonce % 1000000) * 23, 0, 1, 1, 1) ## i64
  if checked != endpoint_rank || ffw_verify_current_exact(check, n) == 0
    z = ffgks_remove(output_path)
    return 0 - 4
  << "CPU_POOL_GLOBAL_SHEAR_RESULT n=5 rank=" + rank.to_s() + " plan=" + plan.to_s() + " mode=" + mode.to_s() + " dependencies=" + solve_meta[2].to_s() + " changed=" + solve_meta[3].to_s() + " hit=1 output_rank=" + endpoint_rank.to_s() + " elapsed_ms=" + elapsed.to_s()
  endpoint_rank

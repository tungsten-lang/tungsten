# One-shot production wrapper for the 4x4 frozen-fringe SAT strategy.
#
# This child deliberately owns no hot walker.  It loads one exact frontier,
# chooses one support-clustered fringe of sixteen live terms, asks an external
# solver for an exact replacement of rank at most fifteen, and publishes a
# file only after the existing local and full-tensor gates both pass.

use metaflip_worker
use flipfleet_frozen_fringe_sat

-> fffsp_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> fffsp_solver_command()
  "cryptominisat5 --verb 0"

-> fffsp_timed_solver_command(timeout_s) (i64)
  fffsp_solver_command() + " --maxtime " + timeout_s.to_s()

-> fffsp_solver_available() i64
  if system("command -v cryptominisat5 >/dev/null 2>&1")
    return 1
  0

-> fffsp_status_label(status) (i64)
  if status == 1
    return "sat"
  if status == 0 - 1
    return "unsat"
  if status == 0 - 2
    return "timeout-or-process"
  if status == 0 - 3
    return "unknown"
  "not-run"

-> fffsp_remove(path) (String) i64
  if system("/bin/rm -f " + fffsp_shell_quote(path))
    return 1
  0

-> fffsp_cleanup(stem) (String) i64
  a = fffsp_remove(stem + ".cnf") ## i64
  b = fffsp_remove(stem + ".model") ## i64
  if a == 1 && b == 1
    return 1
  0

# Return the verified output rank on a hit, zero for an ordinary miss/timeout,
# and a negative value only for a malformed plan, seed, or publication error.
# `solver_command` is injectable solely so the wrapper can be tested without
# making CryptoMiniSat part of every unit-test environment.  Production gives
# CryptoMiniSat its own time limit and keeps a two-second process guard around
# it; that avoids the shell's noisy SIGALRM diagnostic on normal timeouts.
-> fffsp_run_engine(seed_path, output_path, solver_limit_s, process_timeout_s, nonce, solver_command, meta) (String String i64 i64 i64 String i64[]) i64
  if seed_path.size() < 1 || output_path.size() < 1 || seed_path == output_path
    return 0 - 1
  if solver_limit_s < 1 || solver_limit_s > 86400 || process_timeout_s < solver_limit_s || process_timeout_s > 86402 || nonce < 0 || solver_command.size() < 1 || meta.size() < 16
    return 0 - 1

  # A unique epoch output must never inherit a hit from an earlier child.
  if fffsp_remove(output_path) == 0
    return 0 - 4
  stem = output_path + ".ffsat-" + nonce.to_s() ## String
  z = fffsp_cleanup(stem) ## i64

  n = 4 ## i64
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(state, seed_path, n, capacity, 97001 + (nonce % 1000000) * 17, 0, 1, 1, 1) ## i64
  if rank < 16 || ffw_verify_current_exact(state, n) == 0
    z = fffsp_cleanup(stem)
    return 0 - 2

  started = ccall("__w_clock_ms") ## i64
  attempt_meta = i64[13]
  << "CPU_POOL_FROZEN_SAT_START n=4 rank=" + rank.to_s() + " k=16 want=15 mode=clustered solver_limit_s=" + solver_limit_s.to_s() + " process_guard_s=" + process_timeout_s.to_s() + " nonce=" + nonce.to_s()
  hit = fffsat_attempt(state, 16, 104729 + (nonce % 100000000) * 131, 1, solver_command, process_timeout_s, stem, attempt_meta) ## i64
  elapsed = ccall("__w_clock_ms") - started ## i64
  z = fffsp_cleanup(stem)

  i = 0 ## i64
  while i < 13
    meta[i] = attempt_meta[i]
    i += 1
  meta[13] = rank
  meta[14] = hit
  meta[15] = elapsed

  status = fffsp_status_label(attempt_meta[9]) ## String
  if hit > 0
    if hit >= rank || ffw_verify_current_exact(state, n) == 0
      << "CPU_POOL_FROZEN_SAT_RESULT n=4 rank=" + rank.to_s() + " status=sat-rejected hit=0 elapsed_ms=" + elapsed.to_s()
      return 0
    written = ffw_dump_current(state, output_path) ## i64
    if written != hit
      z = fffsp_remove(output_path)
      return 0 - 4
    # The serialized candidate gets a second independent parse/exactness gate.
    check = i64[ffw_state_size(capacity)]
    checked = ffw_load_scheme_cap(check, output_path, n, capacity, 99001 + (nonce % 1000000) * 19, 0, 1, 1, 1) ## i64
    if checked != hit || ffw_verify_current_exact(check, n) == 0
      z = fffsp_remove(output_path)
      return 0 - 4
    << "CPU_POOL_FROZEN_SAT_RESULT n=4 rank=" + rank.to_s() + " k=16 want=15 support=" + attempt_meta[3].to_s() + "/" + attempt_meta[4].to_s() + "/" + attempt_meta[5].to_s() + " cells=" + attempt_meta[6].to_s() + " vars=" + attempt_meta[7].to_s() + " clauses=" + attempt_meta[8].to_s() + " solver=" + status + " hit=1 output_rank=" + hit.to_s() + " elapsed_ms=" + elapsed.to_s()
    return hit

  << "CPU_POOL_FROZEN_SAT_RESULT n=4 rank=" + rank.to_s() + " k=16 want=15 support=" + attempt_meta[3].to_s() + "/" + attempt_meta[4].to_s() + "/" + attempt_meta[5].to_s() + " cells=" + attempt_meta[6].to_s() + " vars=" + attempt_meta[7].to_s() + " clauses=" + attempt_meta[8].to_s() + " solver=" + status + " hit=0 output_rank=0 elapsed_ms=" + elapsed.to_s()
  0

-> fffsp_run_with_solver(seed_path, output_path, timeout_s, nonce, solver_command, meta) (String String i64 i64 String i64[]) i64
  fffsp_run_engine(seed_path, output_path, timeout_s, timeout_s, nonce, solver_command, meta)

-> fffsp_run(seed_path, output_path, timeout_s, nonce, meta) (String String i64 i64 i64[]) i64
  fffsp_run_engine(seed_path, output_path, timeout_s, timeout_s + 2, nonce, fffsp_timed_solver_command(timeout_s), meta)

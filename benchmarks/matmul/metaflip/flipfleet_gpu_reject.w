# Replay bundles for nominal GPU records that fail the exhaustive GF(2) gate.
#
# Generic workers publish three stable sidecars beside their ordinary output:
# candidate, seed, and metadata (metadata last).  The coordinator freezes an
# interesting `rank <= target` sidecar under a monotonic launch nonce before
# the physical slot can be reused.  These helpers contain no TUI policy.

use metaflip_worker

-> ffgr_worker_candidate_path(output_path) (String)
  output_path + ".internal_reject.candidate"

-> ffgr_worker_seed_path(output_path) (String)
  output_path + ".internal_reject.seed"

-> ffgr_worker_meta_path(output_path) (String)
  output_path + ".internal_reject.meta"

-> ffgr_clear_worker_sidecars(output_path) (String) i64
  candidate_ok = write_file(ffgr_worker_candidate_path(output_path), "")
  seed_ok = write_file(ffgr_worker_seed_path(output_path), "")
  meta_ok = write_file(ffgr_worker_meta_path(output_path), "")
  if candidate_ok && seed_ok && meta_ok
    return 1
  0

-> ffgr_meta_value(meta, key) (String String)
  prefix = key + "="
  lines = meta.split("\n")
  i = 0 ## i64
  while i < lines.size()
    line = lines[i]
    if line.starts_with?(prefix)
      return line.slice(prefix.size(), line.size() - prefix.size())
    i += 1
  ""

-> ffgr_meta_i64(meta, key, fallback) (String String i64) i64
  value = ffgr_meta_value(meta, key)
  if value == ""
    return fallback
  parsed = value.to_i() ## i64
  parsed

-> ffgr_nominal_rank(raw) (String) i64
  lines = raw.split("\n")
  if lines.size() < 1
    return 0 - 1
  parts = lines[0].split(" ")
  if parts.size() >= 4 && parts[0] == "R"
    rank = lines.size() ## i64
    if rank > 0 && lines[rank - 1] == ""
      rank -= 1
    return rank
  parsed = parts[0].to_i() ## i64
  parsed

# `ffw_load_scheme_cap` deliberately leaves a syntactically valid rejected
# candidate in the current view.  Re-run its deterministic gate and retain the
# first mismatching tensor coordinate.  Negative values describe malformed or
# incomplete parser state; the raw candidate remains sufficient for replay.
-> ffgr_candidate_exact_error(candidate, n, nominal_rank) (i64[] i64 i64) i64
  if candidate == nil
    return 0 - 101
  if ffw_valid(candidate) != 1
    return 0 - 102
  if ffw_current_rank(candidate) != nominal_rank
    return 0 - 103
  ffw_current_exact_error(candidate, n)

-> ffgr_error_ai(error, n) (i64 i64) i64
  if error <= 0
    return 0 - 1
  dim = n * n ## i64
  (error - 1) / (dim * dim)

-> ffgr_error_bi(error, n) (i64 i64) i64
  if error <= 0
    return 0 - 1
  dim = n * n ## i64
  ((error - 1) / dim) % dim

-> ffgr_error_ci(error, n) (i64 i64) i64
  if error <= 0
    return 0 - 1
  dim = n * n ## i64
  (error - 1) % dim

-> ffgr_error_want(error, n) (i64 i64) i64
  ai = ffgr_error_ai(error, n) ## i64
  bi = ffgr_error_bi(error, n) ## i64
  ci = ffgr_error_ci(error, n) ## i64
  if ai < 0 || bi < 0 || ci < 0
    return 0 - 1
  want = 0 ## i64
  if (ai % n) == (bi / n)
    if (ai / n) == (ci / n)
      if (bi % n) == (ci % n)
        want = 1
  want

-> ffgr_bundle_prefix(run_tag, n, counter, slot, nonce) (String i64 i64 i64 i64)
  "/tmp/flipfleet_gpu_reject_" + run_tag + "_" + n.to_s() + "_" + counter.to_s() + "_slot" + slot.to_s() + "_nonce" + nonce.to_s()

-> ffgr_bundle_meta_path(run_tag, n, counter, slot, nonce) (String i64 i64 i64 i64)
  ffgr_bundle_prefix(run_tag, n, counter, slot, nonce) + ".meta"

-> ffgr_atomic_write(path, body, tag) (String String String) i64
  tmp = path + ".tmp." + tag
  wrote = write_file(tmp, body)
  if wrote
    moved = ccall("__w_rename", tmp, path)
    if moved
      return 1
  0

-> ffgr_summary_path(run_tag, n) (String i64)
  "/tmp/flipfleet_gpu_reject_" + run_tag + "_" + n.to_s() + "_summary.txt"

# Metadata is the bundle commit marker and is published after both raw replay
# files.  The worker and coordinator errors are kept separately so a host-side
# parser/gate disagreement is visible rather than silently normalized.
-> ffgr_preserve(run_tag, n, counter, slot, role, pool_mode, nonce, target_rank, worker, worker_nonce, worker_round, seed_rank, nominal_rank, worker_error, coordinator_error, seed_raw, candidate_raw) (String i64 i64 i64 i64 i64 i64 i64 String i64 i64 i64 i64 i64 i64 String String) i64
  prefix = ffgr_bundle_prefix(run_tag, n, counter, slot, nonce)
  seed_path = prefix + ".seed"
  candidate_path = prefix + ".candidate"
  meta_path = prefix + ".meta"
  tag = counter.to_s() + "-" + slot.to_s() + "-" + nonce.to_s()
  if ffgr_atomic_write(seed_path, seed_raw, tag + "-seed") == 0
    return 0
  if ffgr_atomic_write(candidate_path, candidate_raw, tag + "-candidate") == 0
    return 0

  replay_error = coordinator_error ## i64
  if replay_error <= 0 && worker_error > 0
    replay_error = worker_error
  ai = ffgr_error_ai(replay_error, n) ## i64
  bi = ffgr_error_bi(replay_error, n) ## i64
  ci = ffgr_error_ci(replay_error, n) ## i64
  want = ffgr_error_want(replay_error, n) ## i64
  got = 0 - 1 ## i64
  if want >= 0
    got = want ^ 1
  body = "schema=1\nkind=gpu_internal_reject\ninternal_rejects=" + counter.to_s() + "\nrun_tag=" + run_tag + "\ntensor=" + n.to_s() + "x" + n.to_s() + "\nslot=" + slot.to_s() + "\nrole=" + role.to_s() + "\npool_mode=" + pool_mode.to_s() + "\nlaunch_nonce=" + nonce.to_s() + "\ntarget_rank=" + target_rank.to_s() + "\nworker=" + worker + "\nworker_nonce=" + worker_nonce.to_s() + "\nworker_round=" + worker_round.to_s() + "\nseed_rank=" + seed_rank.to_s() + "\nnominal_rank=" + nominal_rank.to_s() + "\nworker_exact_error=" + worker_error.to_s() + "\ncoordinator_exact_error=" + coordinator_error.to_s() + "\nreplay_error=" + replay_error.to_s() + "\nmismatch_ai=" + ai.to_s() + "\nmismatch_bi=" + bi.to_s() + "\nmismatch_ci=" + ci.to_s() + "\nmismatch_want=" + want.to_s() + "\nmismatch_got=" + got.to_s() + "\nseed_path=" + seed_path + "\ncandidate_path=" + candidate_path + "\n"
  if ffgr_atomic_write(meta_path, body, tag + "-meta") == 0
    return 0
  summary = "schema=1\ninternal_rejects=" + counter.to_s() + "\nlatest_metadata=" + meta_path + "\n"
  z = ffgr_atomic_write(ffgr_summary_path(run_tag, n), summary, tag + "-summary") ## i64
  1

-> ffgr_log_line(counter, slot, role, pool_mode, nonce, target_rank, nominal_rank, worker_error, coordinator_error, preserved, metadata_path) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 String)
  "GPU_INTERNAL_REJECT internal_rejects=" + counter.to_s() + " slot=" + slot.to_s() + " role=" + role.to_s() + " pool_mode=" + pool_mode.to_s() + " nonce=" + nonce.to_s() + " target_rank=" + target_rank.to_s() + " nominal_rank=" + nominal_rank.to_s() + " worker_exact_error=" + worker_error.to_s() + " coordinator_exact_error=" + coordinator_error.to_s() + " preserved=" + preserved.to_s() + " metadata=" + metadata_path

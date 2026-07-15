# Shape-aware replay bundles for rectangular cal2zone candidates that fail
# the exhaustive GF(2) gate.
#
# The worker publishes candidate and seed bytes first, then `.meta` as the
# commit marker.  A coordinator must preserve that committed triple before it
# reuses the output path.  Cleanup removes the commit marker first, so a
# partial cleanup can leave harmless payload orphans but can never replay the
# same reject as a newly committed event.

use metaflip_rect_worker
use flipfleet_gpu_reject

-> ffrgr_worker_sidecars_committed(output_path) (String) i64
  meta = read_file(ffgr_worker_meta_path(output_path))
  if meta != nil && meta.size() > 0
    return 1
  0

# Refuse to erase an unharvested committed reject.  This is used immediately
# before every rectangular epoch; preservation/I/O failures therefore retain
# their only replay evidence instead of being overwritten by the next worker.
-> ffrgr_prepare_worker_sidecars(output_path) (String) i64
  if ffrgr_worker_sidecars_committed(output_path) != 0
    return 0
  ffrgr_clear_worker_sidecars(output_path)

# Metadata is the worker's commit marker, so clear it before either payload.
-> ffrgr_clear_worker_sidecars(output_path) (String) i64
  meta_ok = write_file(ffgr_worker_meta_path(output_path), "")
  if meta_ok == false
    return 0
  candidate_ok = write_file(ffgr_worker_candidate_path(output_path), "")
  seed_ok = write_file(ffgr_worker_seed_path(output_path), "")
  if candidate_ok && seed_ok
    return 1
  0

-> ffrgr_candidate_exact_error(candidate, n, m, p, nominal_rank) (i64[] i64 i64 i64 i64) i64
  if candidate == nil
    return 0 - 101
  if ffr_valid(candidate) != 1
    return 0 - 102
  if ffr_shape_n(candidate) != n || ffr_shape_m(candidate) != m || ffr_shape_p(candidate) != p
    return 0 - 103
  if ffw_current_rank(candidate) != nominal_rank
    return 0 - 104
  ffr_view_error(candidate, candidate[44], candidate[45], candidate[46], candidate[50], nominal_rank, n, m, p)

-> ffrgr_error_ai(error, n, m, p) (i64 i64 i64 i64) i64
  if error <= 0
    return 0 - 1
  vw = m * p ## i64
  ww = n * p ## i64
  (error - 1) / (vw * ww)

-> ffrgr_error_bi(error, n, m, p) (i64 i64 i64 i64) i64
  if error <= 0
    return 0 - 1
  vw = m * p ## i64
  ww = n * p ## i64
  ((error - 1) / ww) % vw

-> ffrgr_error_ci(error, n, m, p) (i64 i64 i64 i64) i64
  if error <= 0
    return 0 - 1
  ww = n * p ## i64
  (error - 1) % ww

-> ffrgr_error_want(error, n, m, p) (i64 i64 i64 i64) i64
  ai = ffrgr_error_ai(error, n, m, p) ## i64
  bi = ffrgr_error_bi(error, n, m, p) ## i64
  ci = ffrgr_error_ci(error, n, m, p) ## i64
  if ai < 0 || bi < 0 || ci < 0
    return 0 - 1
  want = 0 ## i64
  if (ai % m) == (bi / p)
    if (ai / m) == (ci / p)
      if (bi % p) == (ci % p)
        want = 1
  want

-> ffrgr_tensor_tag(n, m, p) (i64 i64 i64)
  n.to_s() + "x" + m.to_s() + "x" + p.to_s()

-> ffrgr_bundle_prefix(run_tag, n, m, p, counter, slot, nonce)
  "/tmp/flipfleet_rect_gpu_reject_" + run_tag + "_" + ffrgr_tensor_tag(n, m, p) + "_" + counter.to_s() + "_slot" + slot.to_s() + "_nonce" + nonce.to_s()

-> ffrgr_bundle_meta_path(run_tag, n, m, p, counter, slot, nonce)
  ffrgr_bundle_prefix(run_tag, n, m, p, counter, slot, nonce) + ".meta"

-> ffrgr_summary_path(run_tag, n, m, p)
  "/tmp/flipfleet_rect_gpu_reject_" + run_tag + "_" + ffrgr_tensor_tag(n, m, p) + "_summary.txt"

# The synthesized metadata is itself a commit marker and is written after the
# immutable seed, candidate, and raw worker metadata.  Keeping the raw worker
# record makes parser/gate disagreements replayable without trusting this
# coordinator's interpretation.
-> ffrgr_preserve(run_tag, n, m, p, counter, slot, role, pool_mode, nonce, target_rank, worker, worker_nonce, worker_round, seed_rank, nominal_rank, worker_error, coordinator_error, worker_meta_raw, seed_raw, candidate_raw)
  prefix = ffrgr_bundle_prefix(run_tag, n, m, p, counter, slot, nonce)
  seed_path = prefix + ".seed"
  candidate_path = prefix + ".candidate"
  worker_meta_path = prefix + ".worker.meta"
  meta_path = prefix + ".meta"
  tag = counter.to_s() + "-" + slot.to_s() + "-" + nonce.to_s()
  if ffgr_atomic_write(seed_path, seed_raw, tag + "-seed") == 0
    return 0
  if ffgr_atomic_write(candidate_path, candidate_raw, tag + "-candidate") == 0
    return 0
  if ffgr_atomic_write(worker_meta_path, worker_meta_raw, tag + "-worker-meta") == 0
    return 0

  replay_error = coordinator_error ## i64
  if replay_error <= 0 && worker_error > 0
    replay_error = worker_error
  ai = ffrgr_error_ai(replay_error, n, m, p) ## i64
  bi = ffrgr_error_bi(replay_error, n, m, p) ## i64
  ci = ffrgr_error_ci(replay_error, n, m, p) ## i64
  want = ffrgr_error_want(replay_error, n, m, p) ## i64
  got = 0 - 1 ## i64
  if want >= 0
    got = want ^ 1
  arow = 0 - 1 ## i64
  acol = 0 - 1 ## i64
  brow = 0 - 1 ## i64
  bcol = 0 - 1 ## i64
  crow = 0 - 1 ## i64
  ccol = 0 - 1 ## i64
  if ai >= 0
    arow = ai / m
    acol = ai % m
  if bi >= 0
    brow = bi / p
    bcol = bi % p
  if ci >= 0
    crow = ci / p
    ccol = ci % p

  body = "schema=1\nkind=rect_gpu_internal_reject\ninternal_rejects=" + counter.to_s() + "\nrun_tag=" + run_tag + "\ntensor=" + ffrgr_tensor_tag(n, m, p) + "\nslot=" + slot.to_s() + "\nrole=" + role.to_s() + "\npool_mode=" + pool_mode.to_s() + "\nlaunch_nonce=" + nonce.to_s() + "\ntarget_rank=" + target_rank.to_s() + "\nworker=" + worker + "\nworker_nonce=" + worker_nonce.to_s() + "\nworker_round=" + worker_round.to_s() + "\nseed_rank=" + seed_rank.to_s() + "\nnominal_rank=" + nominal_rank.to_s() + "\nworker_exact_error=" + worker_error.to_s() + "\ncoordinator_exact_error=" + coordinator_error.to_s() + "\nreplay_error=" + replay_error.to_s() + "\nmismatch_ai=" + ai.to_s() + "\nmismatch_bi=" + bi.to_s() + "\nmismatch_ci=" + ci.to_s() + "\nmismatch_a_row=" + arow.to_s() + "\nmismatch_a_col=" + acol.to_s() + "\nmismatch_b_row=" + brow.to_s() + "\nmismatch_b_col=" + bcol.to_s() + "\nmismatch_c_row=" + crow.to_s() + "\nmismatch_c_col=" + ccol.to_s() + "\nmismatch_want=" + want.to_s() + "\nmismatch_got=" + got.to_s() + "\nseed_path=" + seed_path + "\ncandidate_path=" + candidate_path + "\nworker_metadata_path=" + worker_meta_path + "\n"
  if ffgr_atomic_write(meta_path, body, tag + "-meta") == 0
    return 0
  summary = "schema=1\ninternal_rejects=" + counter.to_s() + "\nlatest_metadata=" + meta_path + "\n"
  z = ffgr_atomic_write(ffrgr_summary_path(run_tag, n, m, p), summary, tag + "-summary") ## i64
  1

# status words:
#   0 committed event detected, 1 replay bundle preserved, 2 live sidecars
#   cleared, 3 worker error, 4 coordinator error, 5 nominal rank,
#   6 candidate byte count, 7 seed byte count.
# The monotonic bundle counter advances only after preservation succeeds.
-> ffrgr_harvest(output_path, fallback_seed_path, run_tag, n, m, p, slot, role, pool_mode, nonce, target_rank, capacity, dslack, cycles, workq, wanderq, counter, scratch, status)
  i = 0 ## i64
  while i < 8
    status[i] = 0
    i += 1
  worker_meta = read_file(ffgr_worker_meta_path(output_path))
  if worker_meta == nil || worker_meta.size() == 0
    return counter
  status[0] = 1

  candidate_path = ffgr_worker_candidate_path(output_path)
  candidate_raw = read_file(candidate_path)
  if candidate_raw == nil
    candidate_raw = ""
  seed_raw = read_file(ffgr_worker_seed_path(output_path))
  if seed_raw == nil || seed_raw.size() == 0
    seed_raw = read_file(fallback_seed_path)
  if seed_raw == nil
    seed_raw = ""
  status[6] = candidate_raw.size()
  status[7] = seed_raw.size()

  nominal_rank = ffgr_meta_i64(worker_meta, "nominal_rank", ffgr_nominal_rank(candidate_raw)) ## i64
  worker_error = ffgr_meta_i64(worker_meta, "exact_error", 0 - 100) ## i64
  coordinator_error = 0 - 105 ## i64
  if candidate_raw.size() > 0 && nominal_rank > 0 && nominal_rank <= capacity
    parsed = ffr_load_scheme_cap(scratch, candidate_path, n, m, p, capacity, 91001 + counter * 17 + slot, dslack, cycles, workq, wanderq) ## i64
    if parsed > 0
      coordinator_error = 0
    if parsed <= 0
      coordinator_error = ffrgr_candidate_exact_error(scratch, n, m, p, nominal_rank)
  status[3] = worker_error
  status[4] = coordinator_error
  status[5] = nominal_rank

  worker = ffgr_meta_value(worker_meta, "worker")
  if worker == ""
    worker = "unknown"
  worker_nonce = ffgr_meta_i64(worker_meta, "worker_nonce", 0 - 1) ## i64
  worker_round = ffgr_meta_i64(worker_meta, "worker_round", 0 - 1) ## i64
  seed_rank = ffgr_meta_i64(worker_meta, "seed_rank", 0 - 1) ## i64
  next_counter = counter + 1 ## i64
  preserved = ffrgr_preserve(run_tag, n, m, p, next_counter, slot, role, pool_mode, nonce, target_rank, worker, worker_nonce, worker_round, seed_rank, nominal_rank, worker_error, coordinator_error, worker_meta, seed_raw, candidate_raw) ## i64
  if preserved == 0
    return counter
  status[1] = 1
  counter = next_counter
  if ffrgr_clear_worker_sidecars(output_path) == 1
    status[2] = 1
  counter

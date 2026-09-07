# Local, single-threaded training evidence. No GPU, no fleet, no record writes.
# Each row labels a real exact-verified escaped state with a fixed-step CPU
# continuation. Separate origin and canonical basin IDs support group holdout.
use ../lib/metaflip/fleet/coreml_features

-> ffcm_arg(args, name, fallback)
  i = 0
  while i + 1 < args.size()
    if args[i] == name
      return args[i + 1]
    i += 1
  fallback

-> ffcm_die(message)
  ccall("w_eputs", message)
  exit(1)

args = argv()
if args.include?("--help")
  << "coreml_ranker_dataset --out FILE --bank-dir DIR --origins 12 --candidates 24 --steps 4096 --max-ms 30000"
  exit(0)
output_path = ffcm_arg(args, "--out", "")
bank_dir = ffcm_arg(args, "--bank-dir", "")
origin_limit = ffcm_arg(args, "--origins", "12").to_i
candidate_limit = ffcm_arg(args, "--candidates", "24").to_i
steps = ffcm_arg(args, "--steps", "4096").to_i
max_ms = ffcm_arg(args, "--max-ms", "30000").to_i
if output_path == "" || bank_dir == "" || origin_limit < 1 || origin_limit > 12 || candidate_limit < 1 || candidate_limit > 256 || steps < 1 || steps > 1000000 || max_ms < 1 || max_ms > 300000
  ffcm_die("Invalid or missing bounded dataset arguments; use --help")
if !file_directory?(bank_dir)
  ffcm_die("Create --bank-dir before generation")

paths = ["matmul_5x5_rank93_gf2.txt", "matmul_5x5_rank93_sparse_gf2.txt", "matmul_5x5_rank93_d1191_gf2.txt", "matmul_5x5_rank93_d1168_gf2.txt", "matmul_5x5_rank93_d1155_gf2.txt", "matmul_5x5_rank93_d1661_gf2.txt", "matmul_5x5_rank93_d967_four_split_control_gf2.txt", "matmul_5x5_rank93_d983_global_isotropy_gf2.txt", "matmul_5x5_rank93_d1291_d3_partial_nullspace_s8_gf2.txt", "matmul_5x5_rank93_catalog_perminov_c843_gf2.txt", "matmul_5x5_rank93_catalog_kauers_a_gf2.txt", "matmul_5x5_rank93_catalog_kauers_b_gf2.txt"]
root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
cap = 160 ## i64
origin = i64[ffw_state_size(cap)]
candidate = i64[ffw_state_size(cap)]
rollout = i64[ffw_state_size(cap)]
us = i64[cap]
vs = i64[cap]
ws = i64[cap]
meta = i64[8]
features = f64[16]
scratch_words = ffw_verify_scratch_words(5, 5, 5) ## i64
scratch = i64[scratch_words]
rows = []
metadata = {type: "metadata", schema: "metaflip-ranker-v1", feature_names: ffcm_feature_names(), tensor: "5x5", frontier_rank: 93, rollout_steps: steps, cpu_threads: 1, gpu: false, requested_origins: origin_limit, requested_candidates_per_origin: candidate_limit, source_commit: capture("git rev-parse HEAD").strip, dataset_source_sha256: Digest.sha256(read_file(__DIR__ + "/coreml_ranker_dataset.w")), features_source_sha256: Digest.sha256(read_file(__DIR__ + "/../lib/metaflip/fleet/coreml_features.w")), walk_source_sha256: Digest.sha256(read_file(__DIR__ + "/../lib/metaflip/scheme.w")), escape_source_sha256: Digest.sha256(read_file(__DIR__ + "/../lib/metaflip/strategies/escape.w"))}
rows.push(JSON.encode(metadata))
started = clock_ms()
completed = 0
rejected = 0
origin_index = 0
while origin_index < origin_limit && clock_ms() - started < max_ms
  path = root + paths[origin_index]
  origin_sha = Digest.sha256(read_file(path))
  loaded = ffw_load_scheme_cap(origin, path, 5, cap, 7001 + origin_index, 0, 1000000, 1000, 1000) ## i64
  if loaded != 93 || ffw_verify_best_exact_scratch(origin, 5, scratch, scratch_words) != 1
    ffcm_die("Origin exact verification failed: " + path)
  origin_basin = ffbi_best_id(origin) ## i64
  ci = 0
  while ci < candidate_limit && clock_ms() - started < max_ms
    nonce = 104729 * (origin_index + 1) + 7919 * (ci + 1) ## i64
    kind = ci % 6 ## i64
    rank = ffw_export_best(origin, us, vs, ws) ## i64
    if kind != 0
      rank = ffe_apply(us, vs, ws, rank, cap, 5, kind, nonce, meta)
    if rank > 0 && rank <= cap
      loaded = ffw_init_terms_cap(candidate, us, vs, ws, rank, 5, cap, nonce, 0, 1000000, 1000, 1000)
      if loaded > 0 && ffw_verify_best_exact_scratch(candidate, 5, scratch, scratch_words) == 1
        candidate_id = origin_index.to_s() + "-" + ci.to_s()
        candidate_path = bank_dir + "/candidate-" + candidate_id + ".txt"
        z = ffw_dump_best(candidate, candidate_path) ## i64
        if !file_exists?(candidate_path)
          ffcm_die("Candidate serialization failed: " + candidate_path)
        # Check the persisted bank artifact too, not just its in-memory parent.
        stored = ffw_load_scheme_cap(rollout, candidate_path, 5, cap, nonce, 0, 1000000, 1000, 1000) ## i64
        if stored != loaded || ffw_verify_best_exact_scratch(rollout, 5, scratch, scratch_words) != 1 || ffbi_best_id(rollout) != ffbi_best_id(candidate)
          ffcm_die("Persisted candidate verification failed: " + candidate_path)
        z = ffcm_features(candidate, 93, features)
        feature_values = []
        fi = 0
        while fi < 16
          feature_values.push(features[fi])
          fi += 1
        start_rank = ffw_best_rank(candidate) ## i64
        start_bits = ffw_best_bits(candidate) ## i64
        start_basin = ffbi_best_id(candidate) ## i64
        start_descriptor = ffme_descriptor(candidate, 93, 5) ## i64
        z = ffw_reseed_from(rollout, candidate, nonce + 15485863)
        trial_started = clock_ms()
        z = ffw_walk(rollout, steps)
        elapsed_ms = clock_ms() - trial_started
        if ffw_verify_best_exact_scratch(rollout, 5, scratch, scratch_words) != 1 || ffw_verify_current_exact_scratch(rollout, 5, scratch, scratch_words) != 1
          ffcm_die("Rollout exact verification failed: " + candidate_id)
        best_rank = ffw_best_rank(rollout) ## i64
        result_basin = ffbi_best_id(rollout) ## i64
        result_descriptor = ffme_descriptor(rollout, 93, 5) ## i64
        distance = ffbp_distance(candidate, rollout) ## i64
        novelty = distance * 1.0 / (start_rank + best_rank) ## f64
        row = {type: "rollout", schema: "metaflip-ranker-v1", origin_seed: paths[origin_index], origin_sha256: origin_sha, origin_basin: origin_basin.to_s(), basin_id: start_basin.to_s(), result_basin: result_basin.to_s(), candidate_id: candidate_id, candidate_path: candidate_path, candidate_sha256: Digest.sha256(read_file(candidate_path)), escape_kind: kind, nonce: nonce, rollout_seed: nonce + 15485863, features: feature_values, start_rank: start_rank, start_bits: start_bits, best_rank: best_rank, best_bits: ffw_best_bits(rollout), final_rank: ffw_current_rank(rollout), rank_improvement: start_rank - best_rank, novelty: novelty, start_descriptor: start_descriptor, result_descriptor: result_descriptor, novel_basin: result_basin != start_basin, new_descriptor: result_descriptor != start_descriptor, requested_steps: steps, moves: ffw_moves(rollout), accepted: ffw_accepted(rollout), elapsed_ms: elapsed_ms, verified: true}
        rows.push(JSON.encode(row))
        completed += 1
      else
        rejected += 1
    else
      rejected += 1
    ci += 1
  origin_index += 1
summary = {type: "summary", completed: completed, rejected_escapes: rejected, elapsed_ms: clock_ms() - started, time_cap_ms: max_ms, completed_origins: origin_index}
rows.push(JSON.encode(summary))
if !write_file(output_path, rows.join("\n") + "\n")
  ffcm_die("Could not write dataset")
<< JSON.encode(summary)

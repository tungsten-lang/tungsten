# Separate pure-Tungsten CPU/GPU fleet for exact {-1,0,1} decompositions.
#
# This executable intentionally shares no coordinator or TUI state with the
# GF(2) FlipFleet.  Each CPU island owns a private exact state; the bounded
# Metal scout rotates independent exact seeds concurrently.  Only a short
# channel-protected publication section is shared, so `--best` is always a
# fully integer-gated result.

use core/system
use flipfleet_ternary_gl3_tunnel
use flipfleet_ternary_seed_variants
use flipfleet_ternary_index_word2

-> fftc_parse_tensor(text) (String) i64
  normalized = text.downcase
  parts = normalized.split("x")
  if parts.size() != 2
    return 0
  n = parts[0].to_i() ## i64
  if n != parts[1].to_i()
    return 0
  if n < 4 || n > 7
    return 0
  n

-> fftc_parse_moves(text) (String) i64
  normalized = text.strip().downcase
  factor = 1 ## i64
  number = normalized
  if normalized.ends_with?("k")
    factor = 1000
    number = normalized.slice(0, normalized.size() - 1)
  if normalized.ends_with?("m")
    factor = 1000000
    number = normalized.slice(0, normalized.size() - 1)
  if normalized.ends_with?("b")
    factor = 1000000000
    number = normalized.slice(0, normalized.size() - 1)
  value = number.to_i() * factor ## i64
  if value < 1
    return 0 - 1
  value

-> fftc_repo_marker(root) (String) i64
  if read_file(root + "/benchmarks/matmul/metaflip/flipfleet_ternary_worker.w") != nil
    return 1
  0

-> fftc_repo_root
  root = capture("pwd").strip()
  depth = 0 ## i64
  while depth < 12
    if fftc_repo_marker(root) == 1
      return root
    root = root + "/.."
    depth += 1
  ""

-> fftc_better(rank, density, old_rank, old_density) (i64 i64 i64 i64) i64
  if old_rank < 1 || rank < old_rank
    return 1
  if rank == old_rank && density < old_density
    return 1
  0

-> fftc_atomic_dump_best(state, path, tag) (i64[] String String) i64
  temporary = path + ".tmp." + tag
  rank = fft_dump_best(state, temporary) ## i64
  if rank < 1
    return 0
  moved = ccall("__w_rename", temporary, path)
  if moved
    return 1
  0

-> fftc_atomic_dump_current(state, path, tag) (i64[] String String) i64
  temporary = path + ".tmp." + tag
  rank = fft_dump_current(state, temporary) ## i64
  if rank < 1
    return 0
  moved = ccall("__w_rename", temporary, path)
  if moved
    return 1
  0

-> fftc_atomic_write(path, body, tag) (String String String) i64
  temporary = path + ".tmp." + tag
  wrote = write_file(temporary, body)
  if !wrote
    return 0
  moved = ccall("__w_rename", temporary, path)
  if moved
    return 1
  0

-> fftc_try_publish(state, path, slot, publication, lock)
  if fftc_better(state[6],state[21],publication[0],publication[1]) == 0
    return 0
  token = lock.recv() ## i64
  published = 0 ## i64
  if fftc_better(state[6],state[21],publication[0],publication[1]) == 1
    tag = slot.to_s() + "." + state[9].to_s()
    if fftc_atomic_dump_best(state, path,tag) == 1
      publication[0] = state[6]
      publication[1] = state[21]
      publication[2] = slot
      publication[3] = publication[3] + 1
      published = 1
  lock.send(token)
  published

# Preserve a bounded global set of exact equal-rank tunnel endpoints.  These
# are deliberately separate from the objective best: a denser presentation
# can still be a valuable restart door.  Fingerprints only deduplicate the
# archive; every emitted file receives the full integer gate.
-> fftc_try_archive(state, prefix, slot, fingerprint, archive_control, archive_fingerprints, lock)
  if archive_control[0] >= archive_control[1]
    return 0
  token = lock.recv() ## i64
  duplicate = 0 ## i64
  i = 0 ## i64
  while i < archive_control[0]
    if archive_fingerprints[i] == fingerprint
      duplicate = 1
    i += 1
  archived = 0 ## i64
  if duplicate == 0 && archive_control[0] < archive_control[1]
    index = archive_control[0] ## i64
    path = prefix + "." + index.to_s() + ".island" + slot.to_s() + ".txt"
    tag = slot.to_s() + "." + state[9].to_s()
    if fftc_atomic_dump_current(state,path,tag) == 1
      archive_fingerprints[index] = fingerprint
      archive_control[0] = index + 1
      archived = 1
  lock.send(token)
  archived

-> fftc_update_metrics(state, metrics, base, moves, drops, basin_returns, archives, elapsed) (i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  metrics[base + 1] = moves
  metrics[base + 2] = state[5]
  metrics[base + 3] = state[6]
  metrics[base + 4] = state[20]
  metrics[base + 5] = state[21]
  metrics[base + 6] = state[10]
  metrics[base + 7] = drops
  metrics[base + 8] = basin_returns
  metrics[base + 9] = state[19]
  metrics[base + 10] = state[13]
  metrics[base + 11] = state[15]
  metrics[base + 12] = state[17]
  metrics[base + 13] = elapsed
  metrics[base + 14] = archives
  1

-> fftc_spawn(state, slot, source_slot, start_ms, deadline_ms, move_limit, chunk, best_path, archive_prefix, publication, archive_control, archive_fingerprints, publish_lock, metrics)
  Thread.new ->
    base = slot * 15 ## i64
    moved = 0 ## i64
    drops = 0 ## i64
    basin_returns = 0 ## i64
    archives = 0 ## i64
    baseline_rank = state[6] ## i64
    baseline_fingerprint = fft_current_fingerprint(state) ## i64
    last_fingerprint = baseline_fingerprint ## i64
    next_gl3 = 65536 ## i64
    gl3_round = 0 ## i64
    next_index_shear = 8388608 ## i64
    failed = 0 ## i64
    running = 1 ## i64
    while running == 1
      now = ccall("__w_clock_ms") ## i64
      if deadline_ms > 0 && now >= deadline_ms
        running = 0
      if move_limit >= 0 && moved >= move_limit
        running = 0
      if running == 1
        take = chunk ## i64
        if move_limit >= 0 && moved + take > move_limit
          take = move_limit - moved
        if take < 1
          running = 0
        if take > 0
          result = fft_walk(state, take) ## i64
          if result < 0
            failed = 1
            running = 0
          if result >= 0
            moved += take
            drops += result
            if moved >= next_gl3
              gl3_wander = 0 ## i64
              if (gl3_round % 4) == 3
                gl3_wander = 1
              gl3_result = fft_gl3_try(state,gl3_wander) ## i64
              if gl3_result < 0
                failed = 1
                running = 0
              gl3_round += 1
              while next_gl3 <= moved
                next_gl3 += 65536
            if moved >= next_index_shear
              index_shear_result = fft_index_shear_directed_descent(state) ## i64
              if index_shear_result < 0
                failed = 1
                running = 0
              while next_index_shear <= moved
                next_index_shear += 8388608
            if state[6] < baseline_rank
              baseline_rank = state[6]
              baseline_fingerprint = fft_current_fingerprint(state)
              last_fingerprint = baseline_fingerprint
            if state[5] == baseline_rank
              fingerprint = fft_current_fingerprint(state) ## i64
              if fingerprint != baseline_fingerprint && fingerprint != last_fingerprint
                basin_returns += 1
                archives += fftc_try_archive(state,archive_prefix,slot,fingerprint,archive_control,archive_fingerprints,publish_lock)
              last_fingerprint = fingerprint
            z = fftc_try_publish(state,best_path,slot,publication,publish_lock) ## i64
            z = fftc_update_metrics(state,metrics,base,moved,drops,basin_returns,archives,ccall("__w_clock_ms") - start_ms)
    z = fftc_update_metrics(state,metrics,base,moved,drops,basin_returns,archives,ccall("__w_clock_ms") - start_ms) ## i64
    metrics[base + 0] = 1
    if failed == 1
      metrics[base + 0] = 0 - 1
    failed

-> fftc_spawn_gpu(prototypes, root, lanes, steps, rounds, slot, best_path, archive_prefix, publication, archive_control, archive_fingerprints, publish_lock, gpu_metrics)
  Thread.new ->
    outputs = []
    result = fftgs_scout_portfolio(prototypes,outputs,root,lanes,steps,rounds,gpu_metrics) ## i64
    if result >= 0
      i = 0 ## i64
      while i < outputs.size() && result >= 0
        candidate = outputs[i]
        closed = fft_index_shear_directed_descent(candidate) ## i64
        if closed < 0
          result = 0 - 1
          gpu_metrics[0] = 0 - 1
        if closed >= 0
          fingerprint = fft_current_fingerprint(candidate) ## i64
          gpu_metrics[12] += fftc_try_archive(candidate,archive_prefix,slot,fingerprint,archive_control,archive_fingerprints,publish_lock)
          gpu_metrics[13] += fftc_try_publish(candidate,best_path,slot,publication,publish_lock)
        i += 1
    result

-> fftc_status_body(n, seed_paths, metrics, islands, publication, archive_control, start_ms, done, gpu_enabled, gpu_metrics)
  now = ccall("__w_clock_ms") ## i64
  elapsed = now - start_ms ## i64
  if elapsed < 1
    elapsed = 1
  total_moves = 0 ## i64
  accepted = 0 ## i64
  drops = 0 ## i64
  basin_returns = 0 ## i64
  rejects = 0 ## i64
  active = 0 ## i64
  failed = 0 ## i64
  slot = 0 ## i64
  while slot < islands
    base = slot * 15 ## i64
    total_moves += metrics[base + 1]
    accepted += metrics[base + 6]
    drops += metrics[base + 7]
    basin_returns += metrics[base + 8]
    rejects += metrics[base + 9]
    if metrics[base] == 0
      active += 1
    if metrics[base] < 0
      failed += 1
    slot += 1
  state = "RUNNING"
  if done != 0
    state = "DONE"
  if failed > 0
    state = "FAILED"
  body = "TERNARY_FLIPFLEET 1\n"
  body += "state=" + state + "\n"
  body += "tensor=" + n.to_s() + "x" + n.to_s() + "\n"
  body += "islands=" + islands.to_s() + "\n"
  body += "active=" + active.to_s() + "\n"
  body += "elapsed_ms=" + elapsed.to_s() + "\n"
  body += "moves=" + total_moves.to_s() + "\n"
  body += "moves_per_sec=" + (total_moves * 1000 / elapsed).to_s() + "\n"
  body += "best_rank=" + publication[0].to_s() + "\n"
  body += "best_density=" + publication[1].to_s() + "\n"
  body += "publications=" + publication[3].to_s() + "\n"
  body += "rank_drops=" + drops.to_s() + "\n"
  body += "equal_rank_basin_returns=" + basin_returns.to_s() + "\n"
  body += "basin_archives=" + archive_control[0].to_s() + "\n"
  body += "accepted_moves=" + accepted.to_s() + "\n"
  body += "exact_rejects=" + rejects.to_s() + "\n"
  gpu_state = "off"
  if gpu_enabled == 1
    gpu_state = "running"
    if gpu_metrics[0] > 0
      gpu_state = "done"
    if gpu_metrics[0] < 0
      gpu_state = "degraded"
  body += "gpu=" + gpu_state + " lanes=" + gpu_metrics[14].to_s() + " seeds=" + gpu_metrics[7].to_s() + " rank=" + gpu_metrics[8].to_s() + " rounds=" + gpu_metrics[11].to_s() + " attempts=" + gpu_metrics[1].to_s() + " accepted=" + gpu_metrics[2].to_s() + " gated=" + gpu_metrics[3].to_s() + " rejects=" + gpu_metrics[4].to_s() + " archives=" + gpu_metrics[12].to_s() + " publications=" + gpu_metrics[13].to_s() + " kernel_ms=" + gpu_metrics[10].to_s() + "\n"
  slot = 0
  while slot < islands
    base = slot * 15
    source_slot = slot % seed_paths.size() ## i64
    body += "island=" + slot.to_s() + " state=" + metrics[base].to_s() + " current=" + metrics[base+2].to_s() + " best=" + metrics[base+3].to_s() + " density=" + metrics[base+5].to_s() + " moves=" + metrics[base+1].to_s() + " basins=" + metrics[base+8].to_s() + " archives=" + metrics[base+14].to_s() + " seed=" + seed_paths[source_slot] + "\n"
    slot += 1
  body

-> fftc_usage
  << "usage: flipfleet-ternary --tensor 4x4|5x5|6x6|7x7 --seed FILE --secs N --moves N(k|m|b) -J N --best FILE --status FILE --archive-prefix FILE --no-gpu --gpu-lanes N --gpu-steps N --gpu-rounds N"
  << "       --seed may be repeated; defaults are the checked-in exact ternary catalogue records"
  1


arguments = argv()
n = 5 ## i64
islands = System.cpu_count - 2 ## i64
if islands < 1
  islands = 1
seconds = 0 ## i64
move_budget = 0 ## i64
max_debt = 3 ## i64
chunk = 8192 ## i64
best_path = ""
status_path = ""
archive_prefix = ""
seed_paths = []
gpu_enabled = 1 ## i64
gpu_lanes = 1024 ## i64
gpu_steps = 4096 ## i64
gpu_rounds = 4 ## i64
help = 0 ## i64
bad = 0 ## i64

i = 0 ## i64
while i < arguments.size()
  argument = arguments[i]
  if argument == "--help" || argument == "-h"
    help = 1
  if argument == "--tensor"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      n = fftc_parse_tensor(arguments[i])
      if n == 0
        bad = 1
  if argument == "--seed"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      seed_paths.push(arguments[i])
  if argument == "--secs"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      seconds = arguments[i].to_i()
      if seconds < 1
        bad = 1
  if argument == "--moves"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      move_budget = fftc_parse_moves(arguments[i])
      if move_budget < 1
        bad = 1
  if argument == "-J"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      islands = arguments[i].to_i()
      if islands < 1
        bad = 1
  if argument.starts_with?("-J") && argument.size() > 2
    islands = argument.slice(2, argument.size() - 2).to_i()
    if islands < 1
      bad = 1
  if argument == "--best"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      best_path = arguments[i]
  if argument == "--status"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      status_path = arguments[i]
  if argument == "--archive-prefix"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      archive_prefix = arguments[i]
  if argument == "--max-debt"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      max_debt = arguments[i].to_i()
      if max_debt < 1 || max_debt > 8
        bad = 1
  if argument == "--chunk"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      chunk = fftc_parse_moves(arguments[i])
      if chunk < 1
        bad = 1
  if argument == "--no-gpu"
    gpu_enabled = 0
  if argument == "--gpu-lanes"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      gpu_lanes = arguments[i].to_i()
      if gpu_lanes < 2
        bad = 1
  if argument == "--gpu-steps"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      gpu_steps = fftc_parse_moves(arguments[i])
      if gpu_steps < 1
        bad = 1
  if argument == "--gpu-rounds"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      gpu_rounds = arguments[i].to_i()
      if gpu_rounds < 1
        bad = 1
  known = argument == "--help" || argument == "-h" || argument == "--tensor" || argument == "--seed" || argument == "--secs" || argument == "--moves" || argument == "-J" || argument.starts_with?("-J") || argument == "--best" || argument == "--status" || argument == "--archive-prefix" || argument == "--max-debt" || argument == "--chunk" || argument == "--no-gpu" || argument == "--gpu-lanes" || argument == "--gpu-steps" || argument == "--gpu-rounds"
  if !known
    bad = 1
  i += 1

if help == 1
  z = fftc_usage() ## i64
  exit(0)
if bad == 1
  z = fftc_usage()
  exit(2)
if seconds == 0 && move_budget == 0
  seconds = 3600
if move_budget > 0 && islands > move_budget
  islands = move_budget

root = fftc_repo_root()
if root == ""
  << "error: cannot locate the Tungsten repository"
  exit(2)
assets = root + "/benchmarks/matmul/metaflip/"
if seed_paths.size() == 0
  if n == 4
    seed_paths.push(assets + "matmul_4x4_rank49_dronperminov_ternary.txt")
  if n == 5
    seed_paths.push(assets + "matmul_5x5_rank93_d967_index_shear_gpu_ternary.txt")
    seed_paths.push(assets + "matmul_5x5_rank93_d997_index_shear_ternary.txt")
    seed_paths.push(assets + "matmul_5x5_rank93_d1245_ternary_gpu.txt")
    seed_paths.push(assets + "matmul_5x5_rank93_d1248_gl3_ternary.txt")
    seed_paths.push(assets + "matmul_5x5_rank93_d1249_ternary_walk.txt")
    seed_paths.push(assets + "matmul_5x5_rank93_kauers_ternary.txt")
  if n == 6
    seed_paths.push(assets + "matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt")
    seed_paths.push(assets + "matmul_6x6_rank153_d1931_symmetry_escape_ternary.txt")
    seed_paths.push(assets + "matmul_6x6_rank153_d1935_uphill_gpu_ternary.txt")
    seed_paths.push(assets + "matmul_6x6_rank153_d1938_index_shear_ternary.txt")
    seed_paths.push(assets + "matmul_6x6_rank153_d2148_kauers_index_shear_gpu_ternary.txt")
    seed_paths.push(assets + "matmul_6x6_rank153_d2148_kauers_r153_index_shear_gpu_ternary.txt")
    seed_paths.push(assets + "matmul_6x6_rank153_d2502_ternary_walk.txt")
    seed_paths.push(assets + "matmul_6x6_rank153_kauers_ternary.txt")
    seed_paths.push(assets + "matmul_6x6_rank153_kauers_r153_ternary.txt")
  if n == 7
    seed_paths.push(assets + "matmul_7x7_rank250_dronperminov_ternary.txt")
    seed_paths.push(assets + "matmul_7x7_rank250_d3069_ternary_door.txt")
if best_path == ""
  best_path = "flipfleet_ternary_" + n.to_s() + "x" + n.to_s() + "_best.txt"
if status_path == ""
  status_path = "flipfleet_ternary_" + n.to_s() + "x" + n.to_s() + "_status.txt"
if archive_prefix == ""
  archive_prefix = best_path + ".basin"

capacity = fft_default_capacity(n) ## i64
state_words = fft_state_size(capacity) ## i64
cpu_prototypes = []
gpu_prototypes = []
source_slot = 0 ## i64
while source_slot < seed_paths.size()
  prototype = i64[state_words]
  loaded = fft_load_seed(prototype,seed_paths[source_slot],n,capacity,2026071400 + source_slot,max_debt) ## i64
  if loaded < 1
    << "error: seed failed parser or exhaustive integer gate: " + seed_paths[source_slot]
    exit(3)
  variants = fftsv_add_variants(cpu_prototypes,gpu_prototypes,prototype,2026071500 + source_slot,max_debt) ## i64
  if variants < 0
    << "error: seed failed deterministic strict-ternary variant construction: " + seed_paths[source_slot]
    exit(3)
  source_slot += 1

initial_slot = 0 ## i64
source_slot = 1
while source_slot < cpu_prototypes.size()
  candidate_prototype = cpu_prototypes[source_slot]
  initial_prototype = cpu_prototypes[initial_slot]
  if fftc_better(candidate_prototype[6],candidate_prototype[21],initial_prototype[6],initial_prototype[21]) == 1
    initial_slot = source_slot
  source_slot += 1
initial_prototype = cpu_prototypes[initial_slot]
publication = i64[4]
publication[0] = initial_prototype[6]
publication[1] = initial_prototype[21]
publication[2] = 0 - 1
publication[3] = 0
if fftc_atomic_dump_best(initial_prototype,best_path,"initial") == 0
  << "error: could not write initial exact best: " + best_path
  exit(3)

publish_lock = Channel.new(1)
publish_lock.send(1)
archive_control = i64[2]
archive_control[0] = 0
archive_control[1] = 16
archive_fingerprints = i64[16]
metrics = i64[islands * 15]
states = []
threads = []
start_ms = ccall("__w_clock_ms") ## i64
deadline_ms = 0 ## i64
if seconds > 0
  deadline_ms = start_ms + seconds * 1000

slot = 0 ## i64
while slot < islands
  source_slot = slot % cpu_prototypes.size()
  state = i64[state_words]
  loaded = fft_clone_gated_seed(state,cpu_prototypes[source_slot],202607140000 + slot * 104729,max_debt) ## i64
  if loaded < 1
    << "error: failed to clone gated seed for island " + slot.to_s()
    exit(3)
  # One CPU island starts behind a genuine strict-alphabet barrier.  The
  # exhaustive length-two scan is admission-only; all other CPU islands and
  # every GPU seed retain their existing independent presentations.
  if slot == 0 && n <= 6
    word2_meta = i64[4]
    word2_door = fftiw2_shallow_atomic_door(state,96,word2_meta) ## i64
    if word2_door < 0 || (word2_door > 0 && fft_current_exact_error(state) != 0)
      << "error: failed exact atomic index-word admission"
      exit(3)
  states.push(state)
  base = slot * 15
  metrics[base + 0] = 0
  metrics[base + 2] = state[5]
  metrics[base + 3] = state[6]
  metrics[base + 4] = state[20]
  metrics[base + 5] = state[21]
  quota = 0 - 1 ## i64
  if move_budget > 0
    quota = move_budget / islands
    if slot < (move_budget % islands)
      quota += 1
  threads.push(fftc_spawn(state,slot,source_slot,start_ms,deadline_ms,quota,chunk,best_path,archive_prefix,publication,archive_control,archive_fingerprints,publish_lock,metrics))
  slot += 1

gpu_metrics = i64[15]
gpu_metrics[14] = gpu_lanes
gpu_thread = nil
if gpu_enabled == 1
  gpu_thread = fftc_spawn_gpu(gpu_prototypes,root,gpu_lanes,gpu_steps,gpu_rounds,islands,best_path,archive_prefix,publication,archive_control,archive_fingerprints,publish_lock,gpu_metrics)

gpu_label = "on"
if gpu_enabled == 0
  gpu_label = "off"
<< "TERNARY_FLIPFLEET tensor=" + n.to_s() + "x" + n.to_s() + " islands=" + islands.to_s() + " gpu=" + gpu_label + " seed_rank=" + publication[0].to_s() + " best=" + best_path + " status=" + status_path

done = 0 ## i64
last_status = 0 - 1000 ## i64
while done == 0
  alive = 0 ## i64
  slot = 0
  while slot < threads.size()
    if threads[slot].alive?
      alive += 1
    slot += 1
  if gpu_enabled == 1
    if gpu_thread.alive?
      alive += 1
  now = ccall("__w_clock_ms") ## i64
  if now - last_status >= 1000 || alive == 0
    body = fftc_status_body(n,seed_paths,metrics,islands,publication,archive_control,start_ms,0,gpu_enabled,gpu_metrics) ## String
    status_written = fftc_atomic_write(status_path,body,"status") ## i64
    if status_written == 0
      << "warning: could not write status: " + status_path
    last_status = now
  if alive == 0
    done = 1
  if done == 0
    ccall("__w_sleep_ms", 25)

failures = 0 ## i64
slot = 0
while slot < threads.size()
  result = threads[slot].join
  if result != 0
    failures += 1
  slot += 1
gpu_result = 0 ## i64
if gpu_enabled == 1
  gpu_result = gpu_thread.join
body = fftc_status_body(n,seed_paths,metrics,islands,publication,archive_control,start_ms,1,gpu_enabled,gpu_metrics) ## String
status_written = fftc_atomic_write(status_path,body,"final") ## i64
if status_written == 0
  << "warning: could not write final status: " + status_path

# Reparse and exhaustively gate the durable winner once more after all writers
# have joined.  This makes successful exit a certificate-level contract.
final_state = i64[state_words]
final_rank = fft_load_seed(final_state,best_path,n,capacity,2026071499,max_debt) ## i64
if final_rank < 1
  << "error: final best failed exhaustive integer verification"
  exit(4)

elapsed = ccall("__w_clock_ms") - start_ms ## i64
total_moves = 0 ## i64
basin_returns = 0 ## i64
slot = 0
while slot < islands
  base = slot * 15
  total_moves += metrics[base + 1]
  basin_returns += metrics[base + 8]
  slot += 1
if elapsed < 1
  elapsed = 1
gpu_state = "off"
if gpu_enabled == 1
  gpu_state = "done"
  if gpu_result < 0
    gpu_state = "degraded"
<< "TERNARY_DONE tensor=" + n.to_s() + "x" + n.to_s() + " best=" + final_rank.to_s() + " density=" + final_state[21].to_s() + " moves=" + total_moves.to_s() + " rate=" + (total_moves * 1000 / elapsed).to_s() + "/s equal_rank_basins=" + basin_returns.to_s() + " gpu=" + gpu_state + " gpu_attempts=" + gpu_metrics[1].to_s() + " gpu_accepted=" + gpu_metrics[2].to_s() + " gpu_gated=" + gpu_metrics[3].to_s() + " failures=" + failures.to_s()
if failures > 0
  exit(4)

# Host-side production wrapper for the isolated signed Metal basis walker.
#
# The kernel itself remains authored in pure Tungsten in
# flipfleet_ternary_gpu_bench.w; this wrapper loads its checked-in generated
# Metal sidecar.  CPU islands and the GPU scout run concurrently.  Every
# endpoint returned through `outputs` has already passed fft_init_terms' full
# integer n^6 reconstruction gate.

use core/metal
use flipfleet_ternary_worker

-> fftgs_promote_current(dest, source, seed) (i64[] i64[] i64) i64
  rank = source[5] ## i64
  up = i64[rank]
  un = i64[rank]
  vp = i64[rank]
  vn = i64[rank]
  wp = i64[rank]
  wn = i64[rank]
  i = 0 ## i64
  while i < rank
    up[i] = source[source[32] + i]
    un[i] = source[source[33] + i]
    vp[i] = source[source[34] + i]
    vn[i] = source[source[35] + i]
    wp[i] = source[source[36] + i]
    wn[i] = source[source[37] + i]
    i += 1
  fft_init_terms(dest,up,un,vp,vn,wp,wn,rank,source[2],source[4],seed,3)

-> fftgs_has_shared_pair(state) (i64[]) i64
  axis = 0 ## i64
  while axis < 3
    left = 0 ## i64
    while left < state[5]
      right = left + 1 ## i64
      while right < state[5]
        relation = fft_pair_relation(state,axis,left,right) ## i64
        if relation != 0
          if axis == 2 || relation > 0
            return 1
        right += 1
      left += 1
    axis += 1
  0

-> fftgs_has_legal_basis_flip(state, seed) (i64[] i64) i64
  probe = i64[fft_state_size(state[4])]
  if fft_clone_gated_seed(probe,state,seed,3) < 1
    return 0
  axis = 0 ## i64
  while axis < 3
    left = 0 ## i64
    while left < probe[5]
      right = 0 ## i64
      while right < probe[5]
        if right != left
          sign = 0 - 1 ## i64
          while sign <= 1
            if sign != 0
              result = fft_basis_flip_pair(probe,left,right,axis,sign,1) ## i64
              if result > 0
                return 1
              if result < 0
                return 0
            sign += 1
        right += 1
      left += 1
    axis += 1
  0

# Open the default 4x4 rank-49 support's missing shared-factor door.  For
# custom doorless seeds, search deterministic donor splits before declining
# the GPU lane; no approximate or ungated seed is admitted.
-> fftgs_open_donor_door(source, destination, seed) (i64[] i64[] i64) i64
  state_words = fft_state_size(source[4]) ## i64
  target = 0 ## i64
  while target < source[6]
    donor = 0 ## i64
    while donor < source[6]
      if donor != target
        axis = 0 ## i64
        while axis < 3
          door = i64[state_words]
          z = fft_clone_gated_seed(door,source,seed + target * 1009 + donor * 17 + axis,3) ## i64
          if fft_split_with_donor(door,target,donor,axis) == 1
            if fft_verify_current_exact(door) == 1
              promoted = i64[state_words]
              if fftgs_promote_current(promoted,door,seed + 700000) == door[5]
                if fftgs_has_legal_basis_flip(promoted,seed + 800000) == 1
                  # Copy through the same exhaustive initializer so the caller
                  # owns a state with its original capacity/layout.
                  return fftgs_promote_current(destination,promoted,seed + 900000)
          axis += 1
      donor += 1
    target += 1
  0 - 1

-> fftgs_import_view(state,up,un,vp,vn,wp,wn,base,rank,n,capacity,seed) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  cup = i64[rank]
  cun = i64[rank]
  cvp = i64[rank]
  cvn = i64[rank]
  cwp = i64[rank]
  cwn = i64[rank]
  i = 0 ## i64
  while i < rank
    cup[i] = up[base + i]
    cun[i] = un[base + i]
    cvp[i] = vp[base + i]
    cvn[i] = vn[base + i]
    cwp[i] = wp[base + i]
    cwn[i] = wn[base + i]
    i += 1
  fft_init_terms(state,cup,cun,cvp,cvn,cwp,cwn,rank,n,capacity,seed,3)

# Keep the source parameter statically typed while crossing from the generic
# portfolio container into raw Metal i64 views. This preserves a zero-boxing
# upload path even for 49-bit 7x7 masks. The compiler's generic-to-typed store
# boundary also converts boxed BigInts correctly; this helper avoids paying
# that dynamic conversion after `source = portfolio[i]` erases the nested type.
-> fftgs_upload_seed(source,up,un,vp,vn,wp,wn,base,rank) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < rank
    destination = base + i ## i64
    up[destination] = source[source[38] + i]
    un[destination] = source[source[39] + i]
    vp[destination] = source[source[40] + i]
    vn[destination] = source[source[41] + i]
    wp[destination] = source[source[42] + i]
    wn[destination] = source[source[43] + i]
    i += 1
  1

# metrics layout:
#   0 state: 0 running, 1 done, -1 degraded
#   1 attempts, 2 accepted, 3 gated outputs, 4 exact rejects
#   5 best density, 6 elapsed ms, 7 portfolio seeds, 8 walk rank
#   9 +1 donor doors, 10 kernel ms, 11 rounds completed
-> fftgs_scout_portfolio(input_seeds, outputs, root, requested_lanes, steps, rounds, metrics)
  metrics[0] = 0
  started = ccall("__w_clock_ms") ## i64
  result = 0 ## i64
  begin
    lanes = requested_lanes ## i64
    if lanes < 2
      lanes = 2
    lanes = (lanes / 2) * 2
    if lanes > 8192
      lanes = 8192
    epoch_steps = steps ## i64
    if epoch_steps < 1
      epoch_steps = 1
    epoch_rounds = rounds ## i64
    if epoch_rounds < 1
      epoch_rounds = 1
    if input_seeds.size() < 1
      raise "ternary GPU: empty seed portfolio"

    capacity = input_seeds[0][4] ## i64
    n = input_seeds[0][2] ## i64
    state_words = fft_state_size(capacity) ## i64
    portfolio = []
    donor_doors = 0 ## i64
    source_index = 0 ## i64
    walk_rank = 0 ## i64
    while source_index < input_seeds.size()
      source = input_seeds[source_index]
      gated = i64[state_words]
      loaded = fft_clone_gated_seed(gated,source,2026073000 + source_index * 104729,3) ## i64
      if loaded > 0 && fftgs_has_legal_basis_flip(gated,2026073500 + source_index * 104729) == 0
        opened = i64[state_words]
        loaded = fftgs_open_donor_door(gated,opened,2026074000 + source_index * 104729)
        if loaded > 0
          gated = opened
          donor_doors += 1
      if loaded > 0 && fftgs_has_legal_basis_flip(gated,2026074500 + source_index * 104729) == 1
        if walk_rank == 0
          walk_rank = gated[6]
        if gated[6] == walk_rank && gated[6] <= 256
          portfolio.push(gated)
      source_index += 1
    if portfolio.size() < 1
      raise "ternary GPU: no exact same-rank seed has a basis-flip door"

    seed_count = portfolio.size() ## i64
    cap = 256 ## i64
    device = metal_device()
    metal_path = root + "/benchmarks/matmul/metaflip/flipfleet_ternary_gpu_bench.msl"
    msl = read_file(metal_path)
    if msl == nil
      raise "ternary GPU: missing Metal sidecar"
    library = metal_compile_source(device,msl)
    pipeline = metal_pipeline(library,"fftg_basis_walk")

    bytes = lanes * cap * 8 ## i64
    work_up_buffer = metal_buffer(device,bytes)
    work_un_buffer = metal_buffer(device,bytes)
    work_vp_buffer = metal_buffer(device,bytes)
    work_vn_buffer = metal_buffer(device,bytes)
    work_wp_buffer = metal_buffer(device,bytes)
    work_wn_buffer = metal_buffer(device,bytes)
    best_up_buffer = metal_buffer(device,bytes)
    best_un_buffer = metal_buffer(device,bytes)
    best_vp_buffer = metal_buffer(device,bytes)
    best_vn_buffer = metal_buffer(device,bytes)
    best_wp_buffer = metal_buffer(device,bytes)
    best_wn_buffer = metal_buffer(device,bytes)
    seed_bytes = seed_count * cap * 8 ## i64
    seed_up_buffer = metal_buffer(device,seed_bytes)
    seed_un_buffer = metal_buffer(device,seed_bytes)
    seed_vp_buffer = metal_buffer(device,seed_bytes)
    seed_vn_buffer = metal_buffer(device,seed_bytes)
    seed_wp_buffer = metal_buffer(device,seed_bytes)
    seed_wn_buffer = metal_buffer(device,seed_bytes)
    telemetry_buffer = metal_buffer(device,lanes * 10 * 8)
    params_buffer = metal_buffer(device,13 * 4)

    work_up = metal_buffer_view(work_up_buffer,66,lanes * cap) ## i64[]
    work_un = metal_buffer_view(work_un_buffer,66,lanes * cap) ## i64[]
    work_vp = metal_buffer_view(work_vp_buffer,66,lanes * cap) ## i64[]
    work_vn = metal_buffer_view(work_vn_buffer,66,lanes * cap) ## i64[]
    work_wp = metal_buffer_view(work_wp_buffer,66,lanes * cap) ## i64[]
    work_wn = metal_buffer_view(work_wn_buffer,66,lanes * cap) ## i64[]
    best_up = metal_buffer_view(best_up_buffer,66,lanes * cap) ## i64[]
    best_un = metal_buffer_view(best_un_buffer,66,lanes * cap) ## i64[]
    best_vp = metal_buffer_view(best_vp_buffer,66,lanes * cap) ## i64[]
    best_vn = metal_buffer_view(best_vn_buffer,66,lanes * cap) ## i64[]
    best_wp = metal_buffer_view(best_wp_buffer,66,lanes * cap) ## i64[]
    best_wn = metal_buffer_view(best_wn_buffer,66,lanes * cap) ## i64[]
    seed_up = metal_buffer_view(seed_up_buffer,66,seed_count * cap) ## i64[]
    seed_un = metal_buffer_view(seed_un_buffer,66,seed_count * cap) ## i64[]
    seed_vp = metal_buffer_view(seed_vp_buffer,66,seed_count * cap) ## i64[]
    seed_vn = metal_buffer_view(seed_vn_buffer,66,seed_count * cap) ## i64[]
    seed_wp = metal_buffer_view(seed_wp_buffer,66,seed_count * cap) ## i64[]
    seed_wn = metal_buffer_view(seed_wn_buffer,66,seed_count * cap) ## i64[]
    telemetry = metal_buffer_view(telemetry_buffer,66,lanes * 10) ## i64[]

    source_index = 0
    while source_index < seed_count
      source = portfolio[source_index]
      uploaded = fftgs_upload_seed(source,seed_up,seed_un,seed_vp,seed_vn,seed_wp,seed_wn,source_index * cap,walk_rank) ## i64
      if uploaded != 1
        raise "ternary GPU: seed upload failed"
      source_index += 1

    queue = metal_queue(device)
    buffers = [work_up_buffer,work_un_buffer,work_vp_buffer,work_vn_buffer,work_wp_buffer,work_wn_buffer,best_up_buffer,best_un_buffer,best_vp_buffer,best_vn_buffer,best_wp_buffer,best_wn_buffer,seed_up_buffer,seed_un_buffer,seed_vp_buffer,seed_vn_buffer,seed_wp_buffer,seed_wn_buffer,telemetry_buffer,params_buffer]
    total_attempts = 0 ## i64
    total_accepted = 0 ## i64
    exact_rejects = 0 ## i64
    best_density_seen = portfolio[0][21] ## i64
    source_index = 1
    while source_index < seed_count
      if portfolio[source_index][21] < best_density_seen
        best_density_seen = portfolio[source_index][21]
      source_index += 1
    kernel_ms = 0 ## i64
    completed = 0 ## i64
    round = 0 ## i64
    while round < epoch_rounds
      metal_buffer_write_i32(params_buffer,0,walk_rank)
      metal_buffer_write_i32(params_buffer,1,cap)
      metal_buffer_write_i32(params_buffer,2,epoch_steps)
      metal_buffer_write_i32(params_buffer,3,1)
      metal_buffer_write_i32(params_buffer,4,0)
      metal_buffer_write_i32(params_buffer,5,0)
      metal_buffer_write_i32(params_buffer,6,0)
      metal_buffer_write_i32(params_buffer,7,0)
      metal_buffer_write_i32(params_buffer,8,0)
      metal_buffer_write_i32(params_buffer,9,0)
      metal_buffer_write_i32(params_buffer,10,1)
      metal_buffer_write_i32(params_buffer,11,seed_count)
      metal_buffer_write_i32(params_buffer,12,round)
      dispatch_started = ccall("__w_clock_ms") ## i64
      metal_dispatch_groups(queue,pipeline,buffers,lanes / 2,2)
      dispatch_ms = ccall("__w_clock_ms") - dispatch_started ## i64
      if dispatch_ms < 1
        dispatch_ms = 1
      kernel_ms += dispatch_ms

      minimum_density = 9223372036854775807 ## i64
      minimum_lane = 0 ## i64
      novelty_lane = 0 ## i64
      novelty_accepted = 0 - 1 ## i64
      target_seed = round % seed_count ## i64
      lane = 0 ## i64
      while lane < lanes
        lane_base = lane * 10 ## i64
        total_attempts += telemetry[lane_base + 1]
        total_accepted += telemetry[lane_base + 4]
        density = telemetry[lane_base + 6] ## i64
        if density < minimum_density
          minimum_density = density
          minimum_lane = lane
        lane_seed = (lane + round) % seed_count ## i64
        if (lane % 3) == 0 && lane_seed == target_seed
          if telemetry[lane_base + 4] > novelty_accepted
            novelty_accepted = telemetry[lane_base + 4]
            novelty_lane = lane
        lane += 1

      chosen_lane = novelty_lane ## i64
      use_best = 0 ## i64
      if minimum_density < best_density_seen
        chosen_lane = minimum_lane
        use_best = 1
      candidate = i64[state_words]
      loaded = 0 - 1 ## i64
      if use_best == 1
        loaded = fftgs_import_view(candidate,best_up,best_un,best_vp,best_vn,best_wp,best_wn,chosen_lane * cap,walk_rank,n,capacity,2026075000 + round)
      if use_best == 0
        loaded = fftgs_import_view(candidate,work_up,work_un,work_vp,work_vn,work_wp,work_wn,chosen_lane * cap,walk_rank,n,capacity,2026075000 + round)
      expected_density = telemetry[chosen_lane * 10 + 5] ## i64
      if use_best == 1
        expected_density = telemetry[chosen_lane * 10 + 6]
      if loaded == walk_rank && candidate[21] != expected_density
        loaded = 0 - 1
      if loaded == walk_rank
        duplicate = 0 ## i64
        fingerprint = fft_current_fingerprint(candidate) ## i64
        source_index = 0
        while source_index < portfolio.size()
          if fft_current_fingerprint(portfolio[source_index]) == fingerprint
            duplicate = 1
          source_index += 1
        if duplicate == 0 || candidate[21] < best_density_seen
          outputs.push(candidate)
          if candidate[21] < best_density_seen
            best_density_seen = candidate[21]
      if loaded != walk_rank
        exact_rejects += 1
      completed += 1
      metrics[1] = total_attempts
      metrics[2] = total_accepted
      metrics[3] = outputs.size()
      metrics[4] = exact_rejects
      metrics[5] = best_density_seen
      metrics[6] = ccall("__w_clock_ms") - started
      metrics[7] = seed_count
      metrics[8] = walk_rank
      metrics[9] = donor_doors
      metrics[10] = kernel_ms
      metrics[11] = completed
      round += 1
    metrics[0] = 1
    result = outputs.size()
  rescue error
    metrics[0] = 0 - 1
    metrics[6] = ccall("__w_clock_ms") - started
    result = 0 - 1
  result

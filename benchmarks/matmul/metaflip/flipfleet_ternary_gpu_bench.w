# Isolated Metal breadth engine for exact {-1,0,1} FlipFleet schemes.
#
# Every GPU lane performs signed rank-preserving 2x2 basis flips at fixed
# rank.  The six-mask representation is identical to
# flipfleet_ternary_worker.w.  GPU moves are exact algebraic identities, but
# no GPU endpoint is trusted: candidates cross the exhaustive integer n^6
# host gate before they are counted as a basin or written to disk.
#
# This executable intentionally has no dependency on the GF(2) coordinator or
# TUI.  It is a benchmark/scout until its useful yield justifies integration
# into flipfleet_ternary.w.


# Six signed factor arrays for the current lane, six for its best-density
# endpoint, one exact seed, per-lane telemetry, and scalar parameters.
## i64[]: work_up
## i64[]: work_un
## i64[]: work_vp
## i64[]: work_vn
## i64[]: work_wp
## i64[]: work_wn
## i64[]: best_up
## i64[]: best_un
## i64[]: best_vp
## i64[]: best_vn
## i64[]: best_wp
## i64[]: best_wn
## i64[]: seed_up
## i64[]: seed_un
## i64[]: seed_vp
## i64[]: seed_vn
## i64[]: seed_wp
## i64[]: seed_wn
## i64[]: telemetry
## i32[]: params
@gpu fn fftg_basis_walk(work_up,work_un,work_vp,work_vn,work_wp,work_wn,best_up,best_un,best_vp,best_vn,best_wp,best_wn,seed_up,seed_un,seed_vp,seed_vn,seed_wp,seed_wn,telemetry,params)
  tid = gpu.thread_position_in_grid.x ## i32
  ltid = gpu.thread_position_in_threadgroup.x ## i32
  rank = params[0] ## i32
  cap = params[1] ## i32
  steps = params[2] ## i32
  initialize = params[3] ## i32
  seed_density = params[4] ## i32
  policy = params[5] ## i32
  planted = params[6] ## i32
  planted_left = params[7] ## i32
  planted_right = params[8] ## i32
  planted_axis = params[9] ## i32
  planted_sign = params[10] ## i32
  seed_count = params[11] ## i32
  rotation = params[12] ## i32
  base = tid * cap ## i32
  sb = tid * 10 ## i32
  if seed_count < 1
    seed_count = 1
  seed_id = (tid + rotation) % seed_count ## i32
  seed_base = seed_id * cap ## i32

  # CAP=256 and WPG=2: 6 * 512 * 8 = 24 KiB, below Metal's 32 KiB
  # threadgroup-memory ceiling even for the rank-250 7x7 seed.
  sup = gpu.shared_i64(512)
  sun = gpu.shared_i64(512)
  svp = gpu.shared_i64(512)
  svn = gpu.shared_i64(512)
  swp = gpu.shared_i64(512)
  swn = gpu.shared_i64(512)

  i = 0 ## i32
  at = 0 ## i32
  lane_seed_density = 0 ## i64
  if initialize == 1
    while i < rank
      at = i * 2 + ltid
      sup[at] = seed_up[seed_base + i]
      sun[at] = seed_un[seed_base + i]
      svp[at] = seed_vp[seed_base + i]
      svn[at] = seed_vn[seed_base + i]
      swp[at] = seed_wp[seed_base + i]
      swn[at] = seed_wn[seed_base + i]
      best_up[base + i] = sup[at]
      best_un[base + i] = sun[at]
      best_vp[base + i] = svp[at]
      best_vn[base + i] = svn[at]
      best_wp[base + i] = swp[at]
      best_wn[base + i] = swn[at]
      seed_pc = sup[at] | sun[at] ## i64
      while seed_pc != 0
        seed_pc = seed_pc & (seed_pc - 1)
        lane_seed_density = lane_seed_density + 1
      seed_pc = svp[at] | svn[at]
      while seed_pc != 0
        seed_pc = seed_pc & (seed_pc - 1)
        lane_seed_density = lane_seed_density + 1
      seed_pc = swp[at] | swn[at]
      while seed_pc != 0
        seed_pc = seed_pc & (seed_pc - 1)
        lane_seed_density = lane_seed_density + 1
      i = i + 1
    telemetry[sb] = ((tid + 1 + rotation * 104729) * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
    telemetry[sb + 1] = 0
    telemetry[sb + 2] = 0
    telemetry[sb + 3] = 0
    telemetry[sb + 4] = 0
    telemetry[sb + 5] = lane_seed_density
    telemetry[sb + 6] = lane_seed_density
    telemetry[sb + 7] = 0
    telemetry[sb + 8] = 0
    telemetry[sb + 9] = 0
  if initialize == 0
    while i < rank
      at = i * 2 + ltid
      sup[at] = work_up[base + i]
      sun[at] = work_un[base + i]
      svp[at] = work_vp[base + i]
      svn[at] = work_vn[base + i]
      swp[at] = work_wp[base + i]
      swn[at] = work_wn[base + i]
      i = i + 1

  rng = telemetry[sb] ## i64
  attempts = telemetry[sb + 1] ## i64
  partners = telemetry[sb + 2] ## i64
  ternary_valid = telemetry[sb + 3] ## i64
  accepted = telemetry[sb + 4] ## i64
  current_density = telemetry[sb + 5] ## i64
  best_density = telemetry[sb + 6] ## i64
  best_move = telemetry[sb + 7] ## i64
  hotter_rejects = telemetry[sb + 8] ## i64
  no_partner = telemetry[sb + 9] ## i64

  mode = 0 ## i32
  if policy == 0
    mode = tid % 3
  if policy == 1
    mode = 0
  if policy == 2
    mode = 1
  if policy == 3
    mode = 2

  # Declare cross-branch temporaries outside the move loop.  The Metal emitter
  # follows lexical declaration scope, while Tungsten assignments themselves
  # are function-scoped.
  li = 0 ## i32
  ri = 0 ## i32
  swap64 = 0 ## i64
  pu = 0 ## i64
  nu = 0 ## i64
  step = 0 ## i32
  while step < steps
    attempts = attempts + 1
    left = 0 ## i32
    right = -1 ## i32
    axis = 0 ## i32
    sign = 1 ## i32
    if planted == 1
      left = planted_left
      right = planted_right
      axis = planted_axis
      sign = planted_sign
    if planted == 0
      rng = (rng * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
      left = (rng >> 32) % rank
      rng = (rng * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
      axis = (rng >> 32) % 3
      rng = (rng * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
      start = (rng >> 32) % rank ## i32
      scan = 0 ## i32
      while scan < rank
        candidate = (start + scan) % rank ## i32
        relation_probe = 0 ## i32
        li = left * 2 + ltid ## i32
        ri = candidate * 2 + ltid ## i32
        if candidate != left
          if axis == 0
            if sup[li] == sup[ri]
              if sun[li] == sun[ri]
                relation_probe = 1
          if axis == 1
            if svp[li] == svp[ri]
              if svn[li] == svn[ri]
                relation_probe = 1
          if axis == 2
            if swp[li] == swp[ri]
              if swn[li] == swn[ri]
                relation_probe = 1
            if swp[li] == swn[ri]
              if swn[li] == swp[ri]
                relation_probe = -1
        if right < 0
          if relation_probe != 0
            right = candidate
        scan = scan + 1
      rng = (rng * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
      if ((rng >> 32) & 1) != 0
        sign = -1

    relation = 0 ## i32
    indices_ok = 0 ## i32
    if right >= 0
      if left >= 0
        if left < rank
          if right < rank
            if right != left
              indices_ok = 1
    if indices_ok == 1
      li = left * 2 + ltid
      ri = right * 2 + ltid
      if axis == 0
        if sup[li] == sup[ri]
          if sun[li] == sun[ri]
            relation = 1
      if axis == 1
        if svp[li] == svp[ri]
          if svn[li] == svn[ri]
            relation = 1
      if axis == 2
        if swp[li] == swp[ri]
          if swn[li] == swn[ri]
            relation = 1
        if swp[li] == swn[ri]
          if swn[li] == swp[ri]
            relation = -1
    if relation == 0
      no_partner = no_partner + 1
    if relation != 0
      partners = partners + 1
      li = left * 2 + ltid
      ri = right * 2 + ltid

      aup = sup[li] ## i64
      aun = sun[li] ## i64
      avp = svp[li] ## i64
      avn = svn[li] ## i64
      awp = swp[li] ## i64
      awn = swn[li] ## i64
      bup = sup[ri] ## i64
      bun = sun[ri] ## i64
      bvp = svp[ri] ## i64
      bvn = svn[ri] ## i64
      bwp = swp[ri] ## i64
      bwn = swn[ri] ## i64

      # A projectively opposite shared W is absorbed by negating B's U and W
      # factors together; the rank-one term itself is unchanged.
      if axis == 2
        if relation < 0
          swap64 = bup
          bup = bun
          bun = swap64
          swap64 = bwp
          bwp = bwn
          bwn = swap64

      x0p = 0 ## i64
      x0n = 0 ## i64
      x1p = 0 ## i64
      x1n = 0 ## i64
      ap0 = 0 ## i64
      an0 = 0 ## i64
      bp0 = 0 ## i64
      bn0 = 0 ## i64
      ap1 = 0 ## i64
      an1 = 0 ## i64
      bp1 = 0 ## i64
      bn1 = 0 ## i64
      if axis == 0
        ap0 = avp
        an0 = avn
        bp0 = bvp
        bn0 = bvn
        ap1 = bwp
        an1 = bwn
        bp1 = awp
        bn1 = awn
      if axis == 1
        ap0 = aup
        an0 = aun
        bp0 = bup
        bn0 = bun
        ap1 = bwp
        an1 = bwn
        bp1 = awp
        bn1 = awn
      if axis == 2
        ap0 = aup
        an0 = aun
        bp0 = bup
        bn0 = bun
        ap1 = bvp
        an1 = bvn
        bp1 = avp
        bn1 = avn

      xp = bp0 ## i64
      xn = bn0 ## i64
      if sign < 0
        xp = bn0
        xn = bp0
      valid = 1 ## i32
      if (ap0 & xp) != 0
        valid = 0
      if (an0 & xn) != 0
        valid = 0
      if valid == 1
        pu = ap0 | xp
        nu = an0 | xn
        x0p = pu ^ (pu & nu)
        x0n = nu ^ (pu & nu)

      xp = bp1
      xn = bn1
      if sign > 0
        # The second update uses -sign.
        xp = bn1
        xn = bp1
      if sign < 0
        xp = bp1
        xn = bn1
      if valid == 1
        if (ap1 & xp) != 0
          valid = 0
        if (an1 & xn) != 0
          valid = 0
      if valid == 1
        pu = ap1 | xp
        nu = an1 | xn
        x1p = pu ^ (pu & nu)
        x1n = nu ^ (pu & nu)
      if (x0p | x0n) == 0
        valid = 0
      if (x1p | x1n) == 0
        valid = 0

      if valid == 1
        ternary_valid = ternary_valid + 1
        old_density = 0 ## i64
        new_density = 0 ## i64
        pc = aup | aun ## i64
        while pc != 0
          pc = pc & (pc - 1)
          old_density = old_density + 1
        pc = avp | avn
        while pc != 0
          pc = pc & (pc - 1)
          old_density = old_density + 1
        pc = awp | awn
        while pc != 0
          pc = pc & (pc - 1)
          old_density = old_density + 1
        pc = sup[ri] | sun[ri]
        while pc != 0
          pc = pc & (pc - 1)
          old_density = old_density + 1
        pc = svp[ri] | svn[ri]
        while pc != 0
          pc = pc & (pc - 1)
          old_density = old_density + 1
        pc = swp[ri] | swn[ri]
        while pc != 0
          pc = pc & (pc - 1)
          old_density = old_density + 1

        nlu_p = aup ## i64
        nlu_n = aun ## i64
        nlv_p = avp ## i64
        nlv_n = avn ## i64
        nlw_p = awp ## i64
        nlw_n = awn ## i64
        nru_p = bup ## i64
        nru_n = bun ## i64
        nrv_p = bvp ## i64
        nrv_n = bvn ## i64
        nrw_p = bwp ## i64
        nrw_n = bwn ## i64
        if axis == 0
          nlv_p = x0p
          nlv_n = x0n
          nrw_p = x1p
          nrw_n = x1n
        if axis == 1
          nlu_p = x0p
          nlu_n = x0n
          nrw_p = x1p
          nrw_n = x1n
        if axis == 2
          nlu_p = x0p
          nlu_n = x0n
          nrv_p = x1p
          nrv_n = x1n

        pc = nlu_p | nlu_n
        while pc != 0
          pc = pc & (pc - 1)
          new_density = new_density + 1
        pc = nlv_p | nlv_n
        while pc != 0
          pc = pc & (pc - 1)
          new_density = new_density + 1
        pc = nlw_p | nlw_n
        while pc != 0
          pc = pc & (pc - 1)
          new_density = new_density + 1
        pc = nru_p | nru_n
        while pc != 0
          pc = pc & (pc - 1)
          new_density = new_density + 1
        pc = nrv_p | nrv_n
        while pc != 0
          pc = pc & (pc - 1)
          new_density = new_density + 1
        pc = nrw_p | nrw_n
        while pc != 0
          pc = pc & (pc - 1)
          new_density = new_density + 1

        take = 0 ## i32
        if mode == 0
          take = 1
        if mode == 1
          if new_density <= old_density + 2
            take = 1
        if mode == 2
          if new_density <= old_density
            take = 1
        if take == 0
          hotter_rejects = hotter_rejects + 1
        if take == 1
          sup[li] = nlu_p
          sun[li] = nlu_n
          svp[li] = nlv_p
          svn[li] = nlv_n
          swp[li] = nlw_p
          swn[li] = nlw_n
          sup[ri] = nru_p
          sun[ri] = nru_n
          svp[ri] = nrv_p
          svn[ri] = nrv_n
          swp[ri] = nrw_p
          swn[ri] = nrw_n

          # Gauge-canonicalize each touched term: leading U and V signs are
          # positive, with compensating sign changes absorbed into W.
          canon = 0 ## i32
          while canon < 2
            ci = li ## i32
            if canon == 1
              ci = ri
            allbits = sup[ci] | sun[ci] ## i64
            lowbit = allbits & (0 - allbits) ## i64
            if (sup[ci] & lowbit) == 0
              swap64 = sup[ci]
              sup[ci] = sun[ci]
              sun[ci] = swap64
              swap64 = swp[ci]
              swp[ci] = swn[ci]
              swn[ci] = swap64
            allbits = svp[ci] | svn[ci]
            lowbit = allbits & (0 - allbits)
            if (svp[ci] & lowbit) == 0
              swap64 = svp[ci]
              svp[ci] = svn[ci]
              svn[ci] = swap64
              swap64 = swp[ci]
              swp[ci] = swn[ci]
              swn[ci] = swap64
            canon = canon + 1

          accepted = accepted + 1
          current_density = current_density + new_density - old_density
          if current_density < best_density
            best_density = current_density
            best_move = attempts
            i = 0
            while i < rank
              at = i * 2 + ltid
              best_up[base + i] = sup[at]
              best_un[base + i] = sun[at]
              best_vp[base + i] = svp[at]
              best_vn[base + i] = svn[at]
              best_wp[base + i] = swp[at]
              best_wn[base + i] = swn[at]
              i = i + 1
    step = step + 1

  i = 0
  while i < rank
    at = i * 2 + ltid
    work_up[base + i] = sup[at]
    work_un[base + i] = sun[at]
    work_vp[base + i] = svp[at]
    work_vn[base + i] = svn[at]
    work_wp[base + i] = swp[at]
    work_wn[base + i] = swn[at]
    i = i + 1
  telemetry[sb] = rng
  telemetry[sb + 1] = attempts
  telemetry[sb + 2] = partners
  telemetry[sb + 3] = ternary_valid
  telemetry[sb + 4] = accepted
  telemetry[sb + 5] = current_density
  telemetry[sb + 6] = best_density
  telemetry[sb + 7] = best_move
  telemetry[sb + 8] = hotter_rejects
  telemetry[sb + 9] = no_partner


# ---------------- host benchmark / exhaustive adoption gate ---------------

use core/system
use core/metal
use flipfleet_ternary_worker

-> fftg_repo_marker(root) (String) i64
  if read_file(root + "/benchmarks/matmul/metaflip/flipfleet_ternary_worker.w") != nil
    return 1
  0

-> fftg_repo_root
  root = capture("pwd").strip()
  depth = 0 ## i64
  while depth < 12
    if fftg_repo_marker(root) == 1
      return root
    root = root + "/.."
    depth += 1
  ""

-> fftg_default_seed(root, n) (String i64)
  base = root + "/benchmarks/matmul/metaflip/"
  if n == 4
    return base + "matmul_4x4_rank49_dronperminov_ternary.txt"
  if n == 5
    return base + "matmul_5x5_rank93_d967_index_shear_gpu_ternary.txt"
  if n == 6
    return base + "matmul_6x6_rank153_d1931_index_shear_gpu_ternary.txt"
  if n == 7
    return base + "matmul_7x7_rank250_dronperminov_ternary.txt"
  ""

-> fftg_policy_code(name) (String) i64
  value = name.strip().downcase
  if value == "mixed"
    return 0
  if value == "wander"
    return 1
  if value == "slack"
    return 2
  if value == "downhill"
    return 3
  0 - 1

-> fftg_load_view(st,up,un,vp,vn,wp,wn,base,rank,n,capacity,seed) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
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
  fft_init_terms(st,cup,cun,cvp,cvn,cwp,cwn,rank,n,capacity,seed,3)

-> fftg_promote_current(dest, source, seed) (i64[] i64[] i64) i64
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

-> fftg_same_current(left, right) (i64[] i64[]) i64
  if left[5] != right[5]
    return 0
  i = 0 ## i64
  while i < left[5]
    axis = 0 ## i64
    while axis < 6
      if left[left[32 + axis] + i] != right[right[32 + axis] + i]
        return 0
      axis += 1
    i += 1
  1

-> fftg_usage
  << "usage: flipfleet-ternary-gpu-bench --tensor 4x4|5x5|6x6|7x7; optional: --seed FILE --lanes N --steps N --rounds N --policy mixed|wander|slack|downhill --gate-every N --cpu-steps N --output FILE --archive-prefix FILE --metallib FILE --selftest-only"
  1

arguments = argv()
n = 4 ## i64
seed_path = ""
lanes = 4096 ## i64
steps = 8192 ## i64
rounds = 8 ## i64
gate_every = 4 ## i64
cpu_steps = 0 ## i64
policy_name = "mixed"
output_path = ""
archive_prefix = ""
metallib_path = ""
selftest_only = 0 ## i64
bad = 0 ## i64
i = 0 ## i64
while i < arguments.size()
  argument = arguments[i]
  if argument == "--help" || argument == "-h"
    z = fftg_usage() ## i64
    exit(0)
  if argument == "--tensor"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      parts = arguments[i].downcase.split("x")
      if parts.size() != 2 || parts[0].to_i() != parts[1].to_i()
        bad = 1
      if parts.size() == 2
        n = parts[0].to_i()
        if n < 4 || n > 7
          bad = 1
  if argument == "--seed"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      seed_path = arguments[i]
  if argument == "--lanes"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      lanes = arguments[i].to_i()
  if argument == "--steps"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      steps = arguments[i].to_i()
  if argument == "--rounds"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      rounds = arguments[i].to_i()
  if argument == "--gate-every"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      gate_every = arguments[i].to_i()
  if argument == "--cpu-steps"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      cpu_steps = arguments[i].to_i()
  if argument == "--policy"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      policy_name = arguments[i]
      if fftg_policy_code(policy_name) < 0
        bad = 1
  if argument == "--output"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      output_path = arguments[i]
  if argument == "--archive-prefix"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      archive_prefix = arguments[i]
  if argument == "--metallib"
    i += 1
    if i >= arguments.size()
      bad = 1
    if i < arguments.size()
      metallib_path = arguments[i]
  if argument == "--selftest-only"
    selftest_only = 1
  known = argument == "--tensor" || argument == "--seed" || argument == "--lanes" || argument == "--steps" || argument == "--rounds" || argument == "--gate-every" || argument == "--cpu-steps" || argument == "--policy" || argument == "--output" || argument == "--archive-prefix" || argument == "--metallib" || argument == "--selftest-only"
  if !known
    bad = 1
  i += 1

if lanes < 2 || steps < 1 || rounds < 1 || gate_every < 1 || cpu_steps < 0
  bad = 1
lanes = (lanes / 2) * 2
if bad == 1
  z = fftg_usage()
  exit(2)

root = fftg_repo_root()
if root == ""
  << "error: cannot locate the Tungsten repository"
  exit(2)
if seed_path == ""
  seed_path = fftg_default_seed(root,n)

capacity = 256 ## i64
state_words = fft_state_size(capacity) ## i64
prototype = i64[state_words]
rank = fft_load_seed(prototype,seed_path,n,capacity,2026071401,3) ## i64
if rank < 1 || rank > capacity
  << "error: seed failed parser or exhaustive integer gate: " + seed_path
  exit(3)
record_rank = rank ## i64
door_delta = 0 ## i64

# The public rank-49 4x4 support has no shared factor at all, so a pure
# fixed-rank flip lane would be inert.  Open one deterministic exact donor
# door first (term 0, donor 2, U axis), then keep the GPU walk fixed at rank
# 50.  The endpoint is a restart door, never a replacement for the rank-49
# record.  Other checked-in square seeds already contain direct flip pairs.
has_shared = 0 ## i64
axis = 0 ## i64
while axis < 3
  left = 0 ## i64
  while left < rank
    right = left + 1 ## i64
    while right < rank
      relation = fft_pair_relation(prototype,axis,left,right) ## i64
      if relation != 0
        if axis == 2 || relation > 0
          has_shared = 1
      right += 1
    left += 1
  axis += 1
if has_shared == 0
  door = i64[state_words]
  z = fft_clone_gated_seed(door,prototype,2026071404,3) ## i64
  opened = 0 ## i64
  if rank > 2
    opened = fft_split_with_donor(door,0,2,0)
  if opened != 1 || fft_verify_current_exact(door) != 1
    << "error: seed has no direct flip pair and deterministic donor door failed"
    exit(4)
  promoted = i64[state_words]
  if fftg_promote_current(promoted,door,2026071405) != rank + 1
    << "error: donor door failed exhaustive integer promotion gate"
    exit(4)
  prototype = promoted
  rank = prototype[6]
  door_delta = rank - record_rank
seed_density = prototype[21] ## i64
seed_fingerprint = fft_current_fingerprint(prototype) ## i64

device = metal_device()
library = nil
if metallib_path != ""
  library = metal_load_library(device,metallib_path)
if library == nil
  metal_path = root + "/benchmarks/matmul/metaflip/flipfleet_ternary_gpu_bench.msl"
  msl = read_file(metal_path)
  if msl == nil
    << "error: missing generated Metal sidecar: " + metal_path
    << "compile with TUNGSTEN_METAL_PATH=" + metal_path
    exit(3)
  library = metal_compile_source(device,msl)
if library == nil
  << "error: could not compile/load ternary Metal kernel"
  exit(3)
pipeline = metal_pipeline(library,"fftg_basis_walk")

bytes = lanes * capacity * 8 ## i64
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
seed_up_buffer = metal_buffer(device,capacity * 8)
seed_un_buffer = metal_buffer(device,capacity * 8)
seed_vp_buffer = metal_buffer(device,capacity * 8)
seed_vn_buffer = metal_buffer(device,capacity * 8)
seed_wp_buffer = metal_buffer(device,capacity * 8)
seed_wn_buffer = metal_buffer(device,capacity * 8)
telemetry_buffer = metal_buffer(device,lanes * 10 * 8)
params_buffer = metal_buffer(device,13 * 4)

work_up_view = metal_buffer_view(work_up_buffer,66,lanes * capacity) ## i64[]
work_un_view = metal_buffer_view(work_un_buffer,66,lanes * capacity) ## i64[]
work_vp_view = metal_buffer_view(work_vp_buffer,66,lanes * capacity) ## i64[]
work_vn_view = metal_buffer_view(work_vn_buffer,66,lanes * capacity) ## i64[]
work_wp_view = metal_buffer_view(work_wp_buffer,66,lanes * capacity) ## i64[]
work_wn_view = metal_buffer_view(work_wn_buffer,66,lanes * capacity) ## i64[]
best_up_view = metal_buffer_view(best_up_buffer,66,lanes * capacity) ## i64[]
best_un_view = metal_buffer_view(best_un_buffer,66,lanes * capacity) ## i64[]
best_vp_view = metal_buffer_view(best_vp_buffer,66,lanes * capacity) ## i64[]
best_vn_view = metal_buffer_view(best_vn_buffer,66,lanes * capacity) ## i64[]
best_wp_view = metal_buffer_view(best_wp_buffer,66,lanes * capacity) ## i64[]
best_wn_view = metal_buffer_view(best_wn_buffer,66,lanes * capacity) ## i64[]
seed_up_view = metal_buffer_view(seed_up_buffer,66,capacity) ## i64[]
seed_un_view = metal_buffer_view(seed_un_buffer,66,capacity) ## i64[]
seed_vp_view = metal_buffer_view(seed_vp_buffer,66,capacity) ## i64[]
seed_vn_view = metal_buffer_view(seed_vn_buffer,66,capacity) ## i64[]
seed_wp_view = metal_buffer_view(seed_wp_buffer,66,capacity) ## i64[]
seed_wn_view = metal_buffer_view(seed_wn_buffer,66,capacity) ## i64[]
telemetry_view = metal_buffer_view(telemetry_buffer,66,lanes * 10) ## i64[]

i = 0
while i < rank
  seed_up_view[i] = prototype[prototype[38] + i]
  seed_un_view[i] = prototype[prototype[39] + i]
  seed_vp_view[i] = prototype[prototype[40] + i]
  seed_vn_view[i] = prototype[prototype[41] + i]
  seed_wp_view[i] = prototype[prototype[42] + i]
  seed_wn_view[i] = prototype[prototype[43] + i]
  i += 1

queue = metal_queue(device)
buffers = [work_up_buffer,work_un_buffer,work_vp_buffer,work_vn_buffer,work_wp_buffer,work_wn_buffer,best_up_buffer,best_un_buffer,best_vp_buffer,best_vn_buffer,best_wp_buffer,best_wn_buffer,seed_up_buffer,seed_un_buffer,seed_vp_buffer,seed_vn_buffer,seed_wp_buffer,seed_wn_buffer,telemetry_buffer,params_buffer]

# Deterministic planted regression: choose the first legal CPU flip, execute
# exactly that endpoint on one GPU lane, compare every mask, then independently
# reconstruct all n^6 integer coefficients from the GPU output.
expected = i64[state_words]
z = fft_clone_gated_seed(expected,prototype,2026071402,3) ## i64
planted_left = -1 ## i64
planted_right = -1 ## i64
planted_axis = -1 ## i64
planted_sign = 0 ## i64
axis = 0 ## i64
while axis < 3 && planted_left < 0
  left = 0 ## i64
  while left < rank && planted_left < 0
    right = 0 ## i64
    while right < rank && planted_left < 0
      if left != right
        sign = -1 ## i64
        while sign <= 1 && planted_left < 0
          if sign != 0
            result = fft_basis_flip_pair(expected,left,right,axis,sign,1) ## i64
            if result > 0
              planted_left = left
              planted_right = right
              planted_axis = axis
              planted_sign = sign
          sign += 1
      right += 1
    left += 1
  axis += 1
if planted_left < 0
  << "error: no deterministic planted basis flip exists in seed"
  exit(4)

metal_buffer_write_i32(params_buffer,0,rank)
metal_buffer_write_i32(params_buffer,1,capacity)
metal_buffer_write_i32(params_buffer,2,1)
metal_buffer_write_i32(params_buffer,3,1)
metal_buffer_write_i32(params_buffer,4,seed_density)
metal_buffer_write_i32(params_buffer,5,1)
metal_buffer_write_i32(params_buffer,6,1)
metal_buffer_write_i32(params_buffer,7,planted_left)
metal_buffer_write_i32(params_buffer,8,planted_right)
metal_buffer_write_i32(params_buffer,9,planted_axis)
metal_buffer_write_i32(params_buffer,10,planted_sign)
metal_buffer_write_i32(params_buffer,11,1)
metal_buffer_write_i32(params_buffer,12,0)
metal_dispatch_groups(queue,pipeline,buffers,1,2)
planted_gpu = i64[state_words]
loaded = fftg_load_view(planted_gpu,work_up_view,work_un_view,work_vp_view,work_vn_view,work_wp_view,work_wn_view,0,rank,n,capacity,2026071403) ## i64
if loaded != rank || fftg_same_current(expected,planted_gpu) == 0
  << "error: planted GPU endpoint disagrees with CPU or failed exhaustive integer gate"
  exit(4)
<< "TERNARY_GPU_PLANTED PASS tensor=" + n.to_s() + "x" + n.to_s() + " record_rank=" + record_rank.to_s() + " walk_rank=" + rank.to_s() + " door_delta=" + door_delta.to_s() + " pair=" + planted_left.to_s() + "," + planted_right.to_s() + " axis=" + planted_axis.to_s() + " sign=" + planted_sign.to_s()
if selftest_only == 1
  exit(0)

policy = fftg_policy_code(policy_name) ## i64
published_density = seed_density ## i64
published_fingerprint = seed_fingerprint ## i64
fingerprints = []
fingerprints.push(seed_fingerprint)
exact_rejects = 0 ## i64
gated_basins = 0 ## i64
kernel_ms = 0 ## i64
round = 0 ## i64
while round < rounds
  metal_buffer_write_i32(params_buffer,0,rank)
  metal_buffer_write_i32(params_buffer,1,capacity)
  metal_buffer_write_i32(params_buffer,2,steps)
  initialize = 0 ## i64
  if round == 0
    initialize = 1
  metal_buffer_write_i32(params_buffer,3,initialize)
  metal_buffer_write_i32(params_buffer,4,seed_density)
  metal_buffer_write_i32(params_buffer,5,policy)
  metal_buffer_write_i32(params_buffer,6,0)
  metal_buffer_write_i32(params_buffer,7,0)
  metal_buffer_write_i32(params_buffer,8,0)
  metal_buffer_write_i32(params_buffer,9,0)
  metal_buffer_write_i32(params_buffer,10,1)
  metal_buffer_write_i32(params_buffer,11,1)
  metal_buffer_write_i32(params_buffer,12,round)
  dispatch_start = ccall("__w_clock_ms") ## i64
  metal_dispatch_groups(queue,pipeline,buffers,lanes / 2,2)
  dispatch_ms = ccall("__w_clock_ms") - dispatch_start ## i64
  if dispatch_ms < 1
    dispatch_ms = 1
  kernel_ms += dispatch_ms

  minimum_density = 9223372036854775807 ## i64
  minimum_lane = 0 ## i64
  lane = 0 ## i64
  while lane < lanes
    density = telemetry_view[lane * 10 + 6] ## i64
    if density < minimum_density
      minimum_density = density
      minimum_lane = lane
    lane += 1
  if minimum_density < published_density
    candidate = i64[state_words]
    loaded = fftg_load_view(candidate,best_up_view,best_un_view,best_vp_view,best_vn_view,best_wp_view,best_wn_view,minimum_lane * capacity,rank,n,capacity,2026071500 + round) ## i64
    if loaded == rank && candidate[21] == minimum_density
      published_density = minimum_density
      published_fingerprint = fft_current_fingerprint(candidate)
      if output_path != ""
        dumped = fft_dump_best(candidate,output_path) ## i64
        if dumped != rank
          << "error: gated candidate could not be published"
          exit(4)
    if loaded != rank || candidate[21] != minimum_density
      exact_rejects += 1

  if ((round + 1) % gate_every) == 0
    gate_lane = ((round + 1) * 104729) % lanes ## i64
    if policy == 0 || policy == 1
      while (gate_lane % 3) != 0
        gate_lane = (gate_lane + 1) % lanes
    endpoint = i64[state_words]
    loaded = fftg_load_view(endpoint,work_up_view,work_un_view,work_vp_view,work_vn_view,work_wp_view,work_wn_view,gate_lane * capacity,rank,n,capacity,2026072500 + round) ## i64
    if loaded == rank
      fingerprint = fft_current_fingerprint(endpoint) ## i64
      duplicate = 0 ## i64
      fi = 0 ## i64
      while fi < fingerprints.size()
        if fingerprints[fi] == fingerprint
          duplicate = 1
        fi += 1
      if duplicate == 0
        fingerprints.push(fingerprint)
        gated_basins += 1
        if archive_prefix != ""
          archive_path = archive_prefix + "." + gated_basins.to_s() + ".txt"
          dumped = fft_dump_current(endpoint,archive_path) ## i64
          if dumped != rank
            << "error: gated basin could not be archived"
            exit(4)
    if loaded != rank
      exact_rejects += 1
  << "round=" + (round + 1).to_s() + " kernel_ms=" + dispatch_ms.to_s() + " min_density=" + minimum_density.to_s() + " gated_best=" + published_density.to_s() + " gated_basins=" + gated_basins.to_s() + " rejects=" + exact_rejects.to_s()
  round += 1

total_attempts = 0 ## i64
total_partners = 0 ## i64
total_valid = 0 ## i64
total_accepted = 0 ## i64
total_hot_rejects = 0 ## i64
lane = 0
while lane < lanes
  total_attempts += telemetry_view[lane * 10 + 1]
  total_partners += telemetry_view[lane * 10 + 2]
  total_valid += telemetry_view[lane * 10 + 3]
  total_accepted += telemetry_view[lane * 10 + 4]
  total_hot_rejects += telemetry_view[lane * 10 + 8]
  lane += 1
if kernel_ms < 1
  kernel_ms = 1

if cpu_steps == 0
  cpu_steps = steps * rounds
cpu_state = i64[state_words]
z = fft_clone_gated_seed(cpu_state,prototype,2026071491,3) ## i64
cpu_accepted = 0 ## i64
cpu_start = ccall("__w_clock_ms") ## i64
i = 0
while i < cpu_steps
  result = fft_try_flip(cpu_state,1) ## i64
  if result < 0
    << "error: CPU reference walker failed its exact gate"
    exit(4)
  if result > 0
    cpu_accepted += 1
  i += 1
cpu_ms = ccall("__w_clock_ms") - cpu_start ## i64
if cpu_ms < 1
  cpu_ms = 1
cpu_exact = fft_verify_current_exact(cpu_state) ## i64
if cpu_exact != 1
  << "error: CPU comparison endpoint failed exhaustive integer gate"
  exit(4)

<< "TERNARY_GPU_DONE tensor=" + n.to_s() + "x" + n.to_s() + " record_rank=" + record_rank.to_s() + " walk_rank=" + rank.to_s() + " door_delta=" + door_delta.to_s() + " policy=" + policy_name + " lanes=" + lanes.to_s() + " depth=" + (steps * rounds).to_s()
<< "gpu attempts=" + total_attempts.to_s() + " attempts_per_sec=" + (total_attempts * 1000 / kernel_ms).to_s() + " partners=" + total_partners.to_s() + " valid=" + total_valid.to_s() + " accepted=" + total_accepted.to_s() + " accepted_per_sec=" + (total_accepted * 1000 / kernel_ms).to_s() + " kernel_ms=" + kernel_ms.to_s()
<< "gpu seed_density=" + seed_density.to_s() + " best_density=" + published_density.to_s() + " gated_basins=" + gated_basins.to_s() + " exact_rejects=" + exact_rejects.to_s() + " density_fingerprint=" + published_fingerprint.to_s()
<< "cpu attempts=" + cpu_steps.to_s() + " attempts_per_sec=" + (cpu_steps * 1000 / cpu_ms).to_s() + " accepted=" + cpu_accepted.to_s() + " accepted_per_sec=" + (cpu_accepted * 1000 / cpu_ms).to_s() + " best_density=" + cpu_state[21].to_s() + " endpoint_density=" + cpu_state[20].to_s() + " exact=" + cpu_exact.to_s()

# Evidence-guided native FlipFleet defaults for square tensors 3x3 through 7x7.

# Default walker count is host cores minus four, whether or not a GPU is
# present.  The reserved cores cover coordinator work and, with no GPU, the
# dedicated CPU strategy lanes/pool described below.
-> ffp_default_cpu_walkers(host_threads, gpu_enabled) (i64 i64) i64
  host = host_threads ## i64
  if host < 1
    host = 1
  reserve = 4 ## i64
  if host <= reserve
    reserve = host / 2
  walkers = host - reserve ## i64
  if walkers < 1
    walkers = 1
  walkers

# When Metal/CUDA is unavailable, continuous GPU roles become sticky CPU
# strategy lanes. Count roles 0-9 with positive weight and clamp to 4..10.
-> ffp_cpu_strategy_lane_count(n) (i64) i64
  count = 0 ## i64
  role = 0 ## i64
  while role < 10
    if ffp_gpu_weight(n, role) > 0
      count += 1
    role += 1
  if count < 4
    count = 4
  if count > 10
    count = 10
  count

-> ffp_cpu_strategy_pool_count() i64
  4

# The k-th continuous strategy role with positive weight (0-based among
# weighted roles).  Falls back to rank/density/split/novelty cycling when the
# tensor has fewer than four weighted roles so the lane floor stays full.
-> ffp_cpu_strategy_role_at(n, lane) (i64 i64) i64
  seen = 0 ## i64
  role = 0 ## i64
  while role < 10
    if ffp_gpu_weight(n, role) > 0
      if seen == lane
        return role
      seen += 1
    role += 1
  fallback = i64[4]
  fallback[0] = 0
  fallback[1] = 1
  fallback[2] = 3
  fallback[3] = 8
  fallback[lane % 4]

# Strategy doors are encoded as 100 + gpu-role-id so ordinary sticky doors
# (0-6) keep their existing semantics.  Pool walkers use role 10.
-> ffp_cpu_strategy_door(role) (i64) i64
  100 + role

-> ffp_record(n) (i64) i64
  if n == 3
    return 23
  if n == 4
    return 47
  if n == 5
    return 93
  if n == 6
    return 153
  n * n * n

-> ffp_record_known(n) (i64) i64
  if n >= 3 && n <= 6
    return 1
  0

-> ffp_seed_path(n) (i64)
  base = "benchmarks/matmul/metaflip/"
  if n == 3
    return base + "matmul_3x3_rank23_d139_gf2.txt"
  if n == 4
    return base + "matmul_4x4_rank47_d450_gf2.txt"
  if n == 5
    return base + "matmul_5x5_rank93_d1155_gf2.txt"
  if n == 6
    return base + "matmul_6x6_rank153_d2502_gf2.txt"
  ""

# Every checked-in exact scheme at the tracked frontier. The coordinator
# independently reloads and verifies these files, admits only states at its
# current best rank, and max-min selects among them for active CPU islands.
-> ffp_frontier_seed_paths(n) (i64)
  base = "benchmarks/matmul/metaflip/"
  paths = []
  if n == 3
    paths.push(base + "matmul_3x3_rank23_d139_gf2.txt")
    paths.push(base + "matmul_3x3_rank23_d159_gf2.txt")
  if n == 4
    paths.push(base + "matmul_4x4_rank47_d450_gf2.txt")
  if n == 5
    paths.push(base + "matmul_5x5_rank93_d1155_gf2.txt")
    paths.push(base + "matmul_5x5_rank93_d1168_gf2.txt")
    paths.push(base + "matmul_5x5_rank93_d1191_gf2.txt")
    paths.push(base + "matmul_5x5_rank93_d1661_gf2.txt")
    paths.push(base + "matmul_5x5_rank93_gf2.txt")
    paths.push(base + "matmul_5x5_rank93_sparse_gf2.txt")
  if n == 6
    paths.push(base + "matmul_6x6_rank153_d2502_gf2.txt")
    paths.push(base + "matmul_6x6_rank153_d2508_gf2.txt")
    paths.push(base + "matmul_6x6_rank153_d2512_gf2.txt")
    paths.push(base + "matmul_6x6_rank153_d2574_c3_gf2.txt")
  paths

-> ffp_c3_seed_path(n) (i64)
  base = "benchmarks/matmul/metaflip/"
  if n == 5
    return base + "matmul_5x5_rank93_d1155_gf2.txt"
  if n == 6
    return base + "matmul_6x6_rank153_d2502_gf2.txt"
  ""

# CPU door codes: leader, frontier, near1, near2, symmetry, mixed, anchor.
# Codes >= 100 are no-GPU strategy lanes (100 + gpu role id).
-> ffp_door_name(code) (i64)
  if code >= 100
    return "cpu-" + ffp_gpu_role_name(code - 100)
  if code == 0
    return "leader"
  if code == 1
    return "frontier"
  if code == 2
    return "near1"
  if code == 3
    return "near2"
  if code == 4
    return "symmetry"
  if code == 5
    return "mixed"
  "anchor"

# Map a strategy role onto the ordinary sticky seed bank it should draw from.
-> ffp_strategy_seed_door(role) (i64) i64
  # rank / density hunt from shoulders and the leader
  if role == 0
    return 3
  if role == 1
    return 0
  if role == 2 || role == 4 || role == 5 || role == 6
    return 4
  if role == 3 || role == 7 || role == 10
    return 5
  if role == 8 || role == 9
    return 1
  0

# Collapse strategy doors (>=100) onto 0-6 for seed banks and cohort indexes.
-> ffp_seed_door(code) (i64) i64
  if code >= 100
    return ffp_strategy_seed_door(code - 100)
  code

-> ffp_door(n, slot) (i64 i64) i64
  ffp_door_gpu(n, slot, 1)

# When gpu_enabled == 0, pin the first strategy-lane + pool slots onto CPU
# strategy doors, then fall through to the ordinary sticky pattern.
-> ffp_door_gpu(n, slot, gpu_enabled) (i64 i64 i64) i64
  if gpu_enabled == 0
    lanes = ffp_cpu_strategy_lane_count(n) ## i64
    pool = ffp_cpu_strategy_pool_count() ## i64
    if slot < lanes
      return ffp_cpu_strategy_door(ffp_cpu_strategy_role_at(n, slot))
    if slot < lanes + pool
      return ffp_cpu_strategy_door(10)
    return ffp_door_pattern(n, slot - lanes - pool)
  ffp_door_pattern(n, slot)

-> ffp_door_pattern(n, slot) (i64 i64) i64
  if slot >= 12
    # Extra hardware-derived workers add breadth instead of repeating the
    # leader/anchor controls from the canonical 12-slot profile.
    extension = i64[4]
    extension[0] = 1
    extension[1] = 5
    extension[2] = 2
    extension[3] = 3
    return extension[(slot - 12) % 4]
  s = slot % 12 ## i64
  if n == 3
    pattern = i64[12]
    pattern[0] = 0
    pattern[1] = 1
    pattern[2] = 2
    pattern[3] = 2
    pattern[4] = 2
    pattern[5] = 2
    pattern[6] = 3
    pattern[7] = 3
    pattern[8] = 3
    pattern[9] = 5
    pattern[10] = 5
    pattern[11] = 6
    return pattern[s]
  if n == 4
    pattern = i64[12]
    pattern[0] = 0
    pattern[1] = 2
    pattern[2] = 2
    pattern[3] = 2
    pattern[4] = 2
    pattern[5] = 2
    pattern[6] = 3
    pattern[7] = 3
    pattern[8] = 3
    pattern[9] = 3
    pattern[10] = 5
    pattern[11] = 6
    return pattern[s]
  if n == 5
    pattern = i64[12]
    pattern[0] = 0
    pattern[1] = 1
    pattern[2] = 2
    pattern[3] = 2
    pattern[4] = 3
    pattern[5] = 3
    pattern[6] = 4
    pattern[7] = 4
    pattern[8] = 4
    pattern[9] = 5
    pattern[10] = 5
    pattern[11] = 6
    return pattern[s]
  if n == 6
    pattern = i64[12]
    pattern[0] = 0
    pattern[1] = 1
    pattern[2] = 1
    pattern[3] = 2
    pattern[4] = 2
    pattern[5] = 3
    pattern[6] = 3
    pattern[7] = 3
    pattern[8] = 4
    pattern[9] = 5
    pattern[10] = 5
    pattern[11] = 6
    return pattern[s]
  pattern = i64[12]
  pattern[0] = 0
  pattern[1] = 1
  pattern[2] = 1
  pattern[3] = 1
  pattern[4] = 1
  pattern[5] = 2
  pattern[6] = 2
  pattern[7] = 3
  pattern[8] = 3
  pattern[9] = 4
  pattern[10] = 5
  pattern[11] = 6
  pattern[s]

-> ffp_zone_name(code) (i64)
  if code == 0
    return "short"
  if code == 1
    return "balanced"
  if code == 2
    return "high-band"
  "marathon"

-> ffp_zone(slot) (i64) i64
  if slot >= 12
    extension = i64[4]
    extension[0] = 0
    extension[1] = 1
    extension[2] = 2
    extension[3] = 1
    return extension[(slot - 12) % 4]
  pattern = i64[12]
  pattern[0] = 1
  pattern[1] = 0
  pattern[2] = 1
  pattern[3] = 2
  pattern[4] = 0
  pattern[5] = 1
  pattern[6] = 2
  pattern[7] = 3
  pattern[8] = 0
  pattern[9] = 1
  pattern[10] = 2
  pattern[11] = 3
  pattern[slot % 12]

-> ffp_work_moves(n, zone) (i64 i64) i64
  if n == 3
    vals = i64[4]
    vals[0] = 25000000
    vals[1] = 125000000
    vals[2] = 625000000
    vals[3] = 2500000000
    return vals[zone]
  if n == 4
    vals = i64[4]
    vals[0] = 50000000
    vals[1] = 250000000
    vals[2] = 1250000000
    vals[3] = 5000000000
    return vals[zone]
  if n == 7
    vals = i64[4]
    vals[0] = 200000000
    vals[1] = 1000000000
    vals[2] = 5000000000
    vals[3] = 20000000000
    return vals[zone]
  vals = i64[4]
  vals[0] = 100000000
  vals[1] = 500000000
  vals[2] = 2500000000
  vals[3] = 10000000000
  vals[zone]

-> ffp_wander_moves(n, zone) (i64 i64) i64
  if n == 3
    vals = i64[4]
    vals[0] = 6250000
    vals[1] = 25000000
    vals[2] = 125000000
    vals[3] = 250000000
    return vals[zone]
  if n == 4
    vals = i64[4]
    vals[0] = 12500000
    vals[1] = 50000000
    vals[2] = 250000000
    vals[3] = 500000000
    return vals[zone]
  if n == 7
    vals = i64[4]
    vals[0] = 50000000
    vals[1] = 200000000
    vals[2] = 1000000000
    vals[3] = 2000000000
    return vals[zone]
  vals = i64[4]
  vals[0] = 25000000
  vals[1] = 100000000
  vals[2] = 500000000
  vals[3] = 1000000000
  vals[zone]

# GPU role codes: rank, density, symmetry, split, break, orbit, polarize,
# compose, novelty, cooperative SIMD, and the rotating kernel pool.
-> ffp_gpu_role_name(role) (i64)
  if role == 0
    return "rank"
  if role == 1
    return "density"
  if role == 2
    return "symmetry"
  if role == 3
    return "split"
  if role == 4
    return "break"
  if role == 5
    return "orbit"
  if role == 6
    return "polarize"
  if role == 7
    return "compose"
  if role == 8
    return "novelty"
  if role == 9
    return "simd"
  "pool"

-> ffp_gpu_weight(n, role) (i64 i64) i64
  # Relative weights for the six continuously active roles.  Break, orbit,
  # polarization, and composition rotate through role 10 instead of consuming
  # permanent floors; role 10's physical budget is reserved separately.
  vals = i64[11]
  if n == 3
    vals[0] = 18
    vals[1] = 15
    vals[2] = 0
    vals[3] = 12
    vals[4] = 0
    vals[5] = 0
    vals[6] = 0
    vals[7] = 0
    vals[8] = 10
    vals[9] = 25
    vals[10] = 5
    return vals[role]
  if n == 4
    vals[0] = 20
    vals[1] = 5
    vals[2] = 0
    vals[3] = 15
    vals[4] = 0
    vals[5] = 0
    vals[6] = 0
    vals[7] = 0
    vals[8] = 15
    vals[9] = 10
    vals[10] = 15
    return vals[role]
  if n == 5
    vals[0] = 15
    vals[1] = 15
    vals[2] = 12
    vals[3] = 6
    vals[4] = 0
    vals[5] = 0
    vals[6] = 0
    vals[7] = 0
    vals[8] = 7
    vals[9] = 15
    vals[10] = 4
    return vals[role]
  if n == 6
    vals[0] = 16
    vals[1] = 16
    vals[2] = 6
    vals[3] = 7
    vals[4] = 0
    vals[5] = 0
    vals[6] = 0
    vals[7] = 0
    vals[8] = 8
    vals[9] = 16
    vals[10] = 4
    return vals[role]
  vals[0] = 18
  vals[1] = 10
  vals[2] = 10
  vals[3] = 8
  vals[4] = 0
  vals[5] = 0
  vals[6] = 0
  vals[7] = 0
  vals[8] = 8
  vals[9] = 12
  vals[10] = 4
  vals[role]

-> ffp_gpu_reseed(role) (i64) i64
  vals = i64[11]
  vals[0] = 300
  vals[1] = 800
  vals[2] = 60
  vals[3] = 20
  vals[4] = 40
  vals[5] = 60
  vals[6] = 60
  vals[7] = 30
  vals[8] = 100
  vals[9] = 100
  vals[10] = 1
  vals[role]

-> ffp_gpu_margin(role) (i64) i64
  vals = i64[11]
  vals[0] = 8
  vals[1] = 1
  vals[2] = 10
  vals[3] = 8
  vals[4] = 8
  vals[5] = 10
  vals[6] = 12
  vals[7] = 14
  vals[8] = 3
  vals[9] = 16
  vals[10] = 0
  vals[role]

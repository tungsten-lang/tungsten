# Evidence-guided native FlipFleet defaults for square tensors 2x2 through 7x7.

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
  if n == 2
    # Strassen's algorithm: 7 multiplies (optimal over GF(2) as well).
    return 7
  if n == 3
    return 23
  if n == 4
    return 47
  if n == 5
    return 93
  if n == 6
    return 153
  if n == 7
    # Exact outer-Strassen isotropy/placement composition, independently
    # exhaustive-gated.  Fleet target is now rank 246.
    return 247
  n * n * n

-> ffp_record_known(n) (i64) i64
  if n >= 2 && n <= 7
    return 1
  0

-> ffp_seed_path(n) (i64)
  base = "benchmarks/matmul/metaflip/"
  if n == 2
    return base + "matmul_2x2_rank7_strassen_gf2.txt"
  if n == 3
    return base + "matmul_3x3_rank23_d139_gf2.txt"
  if n == 4
    return base + "matmul_4x4_rank47_d450_gf2.txt"
  if n == 5
    # Four-split continuation from the GL-normalized AlphaEvolve frontier.
    return base + "matmul_5x5_rank93_d967_four_split_control_gf2.txt"
  if n == 6
    # Exact whole-scheme GL normalization followed by productive short walks.
    return base + "matmul_6x6_rank153_d1860_global_isotropy_gf2.txt"
  if n == 7
    return base + "matmul_7x7_rank247_d3098_global_isotropy_gf2.txt"
  ""

# Every checked-in exact scheme at the tracked frontier. The coordinator
# independently reloads and verifies these files, admits only states at its
# current best rank, and max-min selects among them for active CPU islands.
-> ffp_frontier_seed_paths(n) (i64)
  base = "benchmarks/matmul/metaflip/"
  paths = []
  if n == 2
    # Strassen seed first, then curated leaf-local GL(2,2) orbit doors.  All
    # are exact rank 7; densities 36/40/42 change support for composition and
    # give FlipFleet distinct term-set presentations at the optimal rank.
    paths.push(base + "matmul_2x2_rank7_strassen_gf2.txt")
    paths.push(base + "matmul_2x2_rank7_d36_gl120_gf2.txt")
    paths.push(base + "matmul_2x2_rank7_d36_gl190_gf2.txt")
    paths.push(base + "matmul_2x2_rank7_d40_gl01_gf2.txt")
    paths.push(base + "matmul_2x2_rank7_d40_gl108_gf2.txt")
    paths.push(base + "matmul_2x2_rank7_d40_gl214_gf2.txt")
    paths.push(base + "matmul_2x2_rank7_d42_gl08_gf2.txt")
    paths.push(base + "matmul_2x2_rank7_d42_gl110_gf2.txt")
    paths.push(base + "matmul_2x2_rank7_d42_gl207_gf2.txt")
  if n == 3
    paths.push(base + "matmul_3x3_rank23_d139_gf2.txt")
    paths.push(base + "matmul_3x3_rank23_d159_gf2.txt")
  if n == 4
    paths.push(base + "matmul_4x4_rank47_d450_gf2.txt")
    paths.push(base + "matmul_4x4_rank47_d677_flips_gf2.txt")
  if n == 5
    paths.push(base + "matmul_5x5_rank93_d967_four_split_control_gf2.txt")
    paths.push(base + "matmul_5x5_rank93_d983_global_isotropy_gf2.txt")
    paths.push(base + "matmul_5x5_rank93_d1155_gf2.txt")
    paths.push(base + "matmul_5x5_rank93_d1168_gf2.txt")
    paths.push(base + "matmul_5x5_rank93_d1191_gf2.txt")
    paths.push(base + "matmul_5x5_rank93_d1661_gf2.txt")
    paths.push(base + "matmul_5x5_rank93_gf2.txt")
    paths.push(base + "matmul_5x5_rank93_sparse_gf2.txt")
    # Independent catalog presentations become usable by the square worker's
    # mixed `rank` + `R u v w` loader.  AlphaEvolve is omitted because d967 is
    # descended from its directed global-isotropy frontier; these three add distinct raw
    # and D3/reversal-canonical doors instead of another known GL image.
    paths.push(base + "matmul_5x5_rank93_catalog_kauers_a_gf2.txt")
    paths.push(base + "matmul_5x5_rank93_catalog_kauers_b_gf2.txt")
    paths.push(base + "matmul_5x5_rank93_catalog_perminov_c843_gf2.txt")
    # Exact genuine-D3 partial nullspace endpoint from Kauers A.  It is 32
    # terms away from its source and outside every other frontier seed's
    # D3/reversal-canonical class; the full n^6 gate is regression-tested.
    paths.push(base + "matmul_5x5_rank93_d1291_d3_partial_nullspace_s8_gf2.txt")
  if n == 6
    paths.push(base + "matmul_6x6_rank153_d1860_global_isotropy_gf2.txt")
    paths.push(base + "matmul_6x6_rank153_d1878_global_isotropy_gf2.txt")
    paths.push(base + "matmul_6x6_rank153_d2502_gf2.txt")
    paths.push(base + "matmul_6x6_rank153_d2508_gf2.txt")
    paths.push(base + "matmul_6x6_rank153_d2512_gf2.txt")
    paths.push(base + "matmul_6x6_rank153_d2574_c3_gf2.txt")
    # Two independently gated genuine-D3 partial nullspace endpoints.  They
    # add distinct D3/reversal classes at source distances 8 and 16.
    paths.push(base + "matmul_6x6_rank153_d2508_d3_partial_nullspace_s3_gf2.txt")
    paths.push(base + "matmul_6x6_rank153_d2512_d3_partial_nullspace_s4_gf2.txt")
    # Exact odd-parent affine closures.  These remain file-backed low-cadence
    # archive/restart doors: the density leader stays first and no hot worker
    # move enumerates parent combinations.  Triple/five density and canonical
    # novelty representatives are independently full-gated.
    paths.push(base + "matmul_6x6_rank153_d2506_odd_parent3_gf2.txt")
    paths.push(base + "matmul_6x6_rank153_d2527_odd_parent3_novel_gf2.txt")
    paths.push(base + "matmul_6x6_rank153_d2522_odd_parent5_gf2.txt")
    paths.push(base + "matmul_6x6_rank153_d2533_odd_parent5_novel_gf2.txt")
  if n == 7
    paths.push(base + "matmul_7x7_rank247_d3098_global_isotropy_gf2.txt")
    # Exact partial-automorphism nullspace tunnels from the density leader.
    # Each is independently n^6-gated and differs from both the source and
    # the corresponding whole-scheme automorphism image.
    paths.push(base + "matmul_7x7_rank247_d3098_partial_auto_max_distance_gf2.txt")
    paths.push(base + "matmul_7x7_rank247_d3098_partial_auto_min_density_gf2.txt")
    paths.push(base + "matmul_7x7_rank247_d3142_partial_auto_min_weight_gf2.txt")
    # Depth-four compositions of genuine partial nullspace edges.  Both keep
    # the d3098 density leader's rank/density while reaching the maximum
    # possible set distance 2*247: their term supports are disjoint from it.
    paths.push(base + "matmul_7x7_rank247_d3098_partial_auto_beam_dense_gf2.txt")
    paths.push(base + "matmul_7x7_rank247_d3098_partial_auto_beam_far_gf2.txt")
    # Three max-distance representatives from the eight unique weighted-outer
    # term sets.  They are archive/frontier restart seeds only; the compact
    # d3098 scheme above remains the default and therefore gets the hot path.
    paths.push(base + "matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt")
    paths.push(base + "matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt")
    paths.push(base + "matmul_7x7_rank247_d3554_outer_isotropy_c021_m4_gf2.txt")
    paths.push(base + "matmul_7x7_rank247_d3554_outer_isotropy_c024_m0_gf2.txt")
    # Reflection-factor partial nullspace tunnels from the c013/c024 outer
    # seeds.  Both exact endpoints are 216 terms from their source and are
    # distinct from each other and the complete checked-in frontier archive.
    paths.push(base + "matmul_7x7_rank247_d3554_d3_partial_nullspace_s7_gf2.txt")
    paths.push(base + "matmul_7x7_rank247_d3554_d3_partial_nullspace_s9_gf2.txt")
    # A record-rank/density affine triple at canonical distance 40 from the
    # existing bank.  It is an archive/restart source only; the minute-scale
    # frontier-source scheduler supplies its derived work lazily.
    paths.push(base + "matmul_7x7_rank247_d3098_odd_parent3_gf2.txt")
    # Large-bank affine-code descent over 164 exact-zero generators.  This
    # independently gated record-rank/density endpoint is 398 terms from the
    # density source, at least 56 terms from every generating-bank member, and
    # outside all of their D3/reversal-canonical identities.  Keep it as a
    # file-backed low-cadence restart door; no hot walker enumerates the code.
    paths.push(base + "matmul_7x7_rank247_d3098_affine_code_gf2.txt")
  paths

# Independently exact, structurally distant cross-field shoulders.  These are
# file-backed restart inventory only: they are loaded into the best+1/+2 banks
# at coordinator boundaries and never participate in a hot move loop.  Keeping
# the delta explicit prevents an old shoulder from being mislabeled after a
# frontier rank drop.
-> ffp_near_seed_paths(n, delta) (i64 i64)
  base = "benchmarks/matmul/metaflip/"
  paths = []
  if n == 4 && delta == 2
    # Public {-1,0,1} rank-49 scheme, independently integer-gated and reduced
    # mod 2 with the trace-dual W factor transposed.  Its exact r49/d432
    # projection is orbit-distance 96 from the r47 density leader.
    paths.push(base + "matmul_4x4_rank49_d432_signed_4x4x4_m49_zt_gf2.txt")
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

# Door/zone/move tables are pure scalar lookups — never allocate a temporary
# i64[] and return one element.  Under the campaign-lifetime allocator that
# pattern retained every table forever (same class of leak as near-bank
# overwrite OOM).

-> ffp_door_pattern(n, slot) (i64 i64) i64
  if slot >= 12
    # Extra hardware-derived workers add breadth instead of repeating the
    # leader/anchor controls from the canonical 12-slot profile.
    e = (slot - 12) % 4 ## i64
    if e == 0
      return 1
    if e == 1
      return 5
    if e == 2
      return 2
    return 3
  s = slot % 12 ## i64
  if n == 2
    # Tiny tensor: keep most islands on leader/frontier; shoulders are thin.
    if s == 0
      return 0
    if s >= 1 && s <= 4
      return 1
    if s == 5 || s == 6
      return 2
    if s == 7 || s == 8
      return 3
    if s == 9 || s == 10
      return 5
    return 6
  if n == 3
    if s == 0
      return 0
    if s == 1
      return 1
    if s >= 2 && s <= 5
      return 2
    if s >= 6 && s <= 8
      return 3
    if s == 9 || s == 10
      return 5
    return 6
  if n == 4
    # Keep one direct CPU island (slot 5) in the independent
    # Kauers--Moosbauer/Flips rank-47 orbit instead of making every
    # record-rank island descend from the AlphaTensor representative.
    if s == 0
      return 0
    if s >= 1 && s <= 4
      return 2
    if s == 5
      return 1
    if s >= 6 && s <= 9
      return 3
    if s == 10
      return 5
    return 6
  if n == 5
    if s == 0
      return 0
    if s == 1
      return 1
    if s == 2 || s == 3
      return 2
    if s == 4 || s == 5
      return 3
    if s >= 6 && s <= 8
      return 4
    if s == 9 || s == 10
      return 5
    return 6
  if n == 6
    if s == 0
      return 0
    if s == 1 || s == 2
      return 1
    if s == 3 || s == 4
      return 2
    if s >= 5 && s <= 7
      return 3
    if s == 8
      return 4
    if s == 9 || s == 10
      return 5
    return 6
  # default / 7x7
  if s == 0
    return 0
  if s >= 1 && s <= 4
    return 1
  if s == 5 || s == 6
    return 2
  if s == 7 || s == 8
    return 3
  if s == 9
    return 4
  if s == 10
    return 5
  6

# When gpu_enabled == 0, pin the first strategy-lane + pool slots onto CPU
# strategy doors, then fall through to the ordinary sticky pattern. Define
# dependencies before their wrappers so typed lowering sees raw-i64 signatures
# at every call site rather than emitting boxed forward calls.
-> ffp_door_gpu(n, slot, gpu_enabled) (i64 i64 i64) i64
  if gpu_enabled != 0
    return ffp_door_pattern(n, slot)
  lanes = ffp_cpu_strategy_lane_count(n) ## i64
  pool = ffp_cpu_strategy_pool_count() ## i64
  if slot < lanes
    return ffp_cpu_strategy_door(ffp_cpu_strategy_role_at(n, slot))
  if slot < lanes + pool
    return ffp_cpu_strategy_door(10)
  return ffp_door_pattern(n, slot - lanes - pool)

-> ffp_door(n, slot) (i64 i64) i64
  return ffp_door_gpu(n, slot, 1)

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
    e = (slot - 12) % 4 ## i64
    if e == 0
      return 0
    if e == 1
      return 1
    if e == 2
      return 2
    return 1
  s = slot % 12 ## i64
  if s == 0
    return 1
  if s == 1
    return 0
  if s == 2
    return 1
  if s == 3
    return 2
  if s == 4
    return 0
  if s == 5
    return 1
  if s == 6
    return 2
  if s == 7
    return 3
  if s == 8
    return 0
  if s == 9
    return 1
  if s == 10
    return 2
  3

-> ffp_work_moves(n, zone) (i64 i64) i64
  if zone < 0
    zone = 0
  if zone > 3
    zone = 3
  if n == 2
    # Short budgets: 2x2 saturates the rank-7 Strassen component quickly.
    if zone == 0
      return 5000000
    if zone == 1
      return 25000000
    if zone == 2
      return 125000000
    return 500000000
  if n == 3
    if zone == 0
      return 25000000
    if zone == 1
      return 125000000
    if zone == 2
      return 625000000
    return 2500000000
  if n == 4
    if zone == 0
      return 50000000
    if zone == 1
      return 250000000
    if zone == 2
      return 1250000000
    return 5000000000
  if n == 7
    if zone == 0
      return 200000000
    if zone == 1
      return 1000000000
    if zone == 2
      return 5000000000
    return 20000000000
  if zone == 0
    return 100000000
  if zone == 1
    return 500000000
  if zone == 2
    return 2500000000
  10000000000

-> ffp_wander_moves(n, zone) (i64 i64) i64
  if zone < 0
    zone = 0
  if zone > 3
    zone = 3
  if n == 2
    if zone == 0
      return 1250000
    if zone == 1
      return 5000000
    if zone == 2
      return 25000000
    return 50000000
  if n == 3
    if zone == 0
      return 6250000
    if zone == 1
      return 25000000
    if zone == 2
      return 125000000
    return 250000000
  if n == 4
    if zone == 0
      return 12500000
    if zone == 1
      return 50000000
    if zone == 2
      return 250000000
    return 500000000
  if n == 7
    if zone == 0
      return 50000000
    if zone == 1
      return 200000000
    if zone == 2
      return 1000000000
    return 2000000000
  if zone == 0
    return 25000000
  if zone == 1
    return 100000000
  if zone == 2
    return 500000000
  1000000000

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
  if n == 2
    # No checked-in Metal cal2zone for 2x2; weights only matter if a host is added.
    vals[0] = 20
    vals[1] = 15
    vals[2] = 0
    vals[3] = 15
    vals[4] = 0
    vals[5] = 0
    vals[6] = 0
    vals[7] = 0
    vals[8] = 15
    vals[9] = 0
    vals[10] = 10
    return vals[role]
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

# Canonical rectangular GF(2) campaign profiles.
#
# Keep this module free of worker/GPU dependencies: both the generic CPU lane
# and dimension-specialized Tungsten GPU worker consume it. Shapes are deliberately
# allowlisted.  Although the rectangular worker is runtime-generic, admitting
# a shape here means that Metaflip has an exact checked-in frontier seed and a
# documented rank target or proved-optimal parent role for it.
use bounds

-> ffrp_supported(n, m, p) (i64 i64 i64) i64
  ok = 0 ## i64
  if n == 2 && m == 2 && (p == 5 || p == 6 || p == 7 || p == 8 || p == 9)
    ok = 1
  if n == 2 && m == 3 && (p == 4 || p == 5)
    ok = 1
  if n == 2 && m == 4 && p == 5
    ok = 1
  if n == 2 && m == 5 && p == 6
    ok = 1
  if n == 3 && m == 3 && p == 4
    ok = 1
  if n == 3 && m == 3 && p == 5
    ok = 1
  if n == 3 && m == 4 && p == 4
    ok = 1
  if n == 3 && m == 4 && p == 5
    ok = 1
  if n == 3 && m == 4 && p == 6
    ok = 1
  if n == 3 && m == 4 && p == 7
    ok = 1
  if n == 3 && m == 5 && p == 5
    ok = 1
  if n == 3 && m == 5 && p == 6
    ok = 1
  if n == 3 && m == 5 && p == 7
    ok = 1
  if n == 4 && m == 4 && p == 5
    ok = 1
  if n == 4 && m == 5 && p == 5
    ok = 1
  if n == 4 && m == 4 && p == 6
    ok = 1
  if n == 4 && m == 5 && p == 6
    ok = 1
  if n == 4 && m == 5 && p == 7
    ok = 1
  if n == 4 && m == 5 && p == 8
    ok = 1
  if n == 4 && m == 6 && p == 6
    ok = 1
  if n == 4 && m == 6 && p == 7
    ok = 1
  if n == 4 && m == 6 && p == 8
    ok = 1
  if n == 5 && m == 6 && p == 7
    ok = 1
  ok

-> ffrp_supported_label(label) (String) i64
  ok = 0 ## i64
  if label == "2x2x5" || label == "2x2x6" || label == "2x2x7" || label == "2x2x8" || label == "2x2x9" || label == "2x3x4" || label == "2x3x5" || label == "2x4x5" || label == "2x5x6" || label == "3x3x4" || label == "3x3x5" || label == "3x4x4" || label == "3x4x5" || label == "3x4x6" || label == "3x4x7" || label == "3x5x5" || label == "3x5x6" || label == "3x5x7" || label == "4x4x5" || label == "4x5x5" || label == "4x4x6" || label == "4x5x6" || label == "4x5x7" || label == "4x5x8" || label == "4x6x6" || label == "4x6x7" || label == "4x6x8" || label == "5x6x7"
    ok = 1
  ok

-> ffrp_label_axis(label, axis) (String i64) i64
  if label == nil || axis < 0 || axis > 2
    return 0
  length = ccall_nobox("w_string_byte_length", label) ## i64
  ptr = ccall_nobox("w_string_byte_ptr", label) ## i64
  current_axis = 0 ## i64
  value = 0 ## i64
  digits = 0 ## i64
  cursor = 0 ## i64
  while cursor < length
    byte = raw_load_u8(ptr, cursor) ## i64
    if byte == 120
      if digits < 1
        return 0
      if current_axis == axis
        return value
      current_axis += 1
      value = 0
      digits = 0
    elsif byte >= 48 && byte <= 57
      value = value * 10 + byte - 48
      digits += 1
    else
      return 0
    cursor += 1
  if current_axis == axis && digits > 0
    return value
  0

-> ffrp_n(label) (String) i64
  if ffrp_supported_label(label) == 1
    return ffrp_label_axis(label, 0)
  0

-> ffrp_m(label) (String) i64
  if ffrp_supported_label(label) == 1
    return ffrp_label_axis(label, 1)
  0

-> ffrp_p(label) (String) i64
  if ffrp_supported_label(label) == 1
    return ffrp_label_axis(label, 2)
  0

-> ffrp_label(n, m, p) (i64 i64 i64)
  if ffrp_supported(n, m, p) == 1
    return n.to_s() + "x" + m.to_s() + "x" + p.to_s()
  "invalid"

-> ffrp_record_rank(n, m, p) (i64 i64 i64) i64
  if n == 2 && m == 2 && p == 5
    return 18
  if n == 2 && m == 2 && p == 6
    return 21
  if n == 2 && m == 2 && p == 7
    return 25
  if n == 2 && m == 2 && p == 8
    return 28
  if n == 2 && m == 2 && p == 9
    return 32
  if n == 2 && m == 3 && p == 4
    return 20
  if n == 2 && m == 3 && p == 5
    return 25
  if n == 2 && m == 4 && p == 5
    return 33
  if n == 2 && m == 5 && p == 6
    return 47
  if n == 3 && m == 3 && p == 4
    return 29
  if n == 3 && m == 3 && p == 5
    return 36
  if n == 3 && m == 4 && p == 4
    return 38
  if n == 3 && m == 4 && p == 5
    return 47
  if n == 3 && m == 4 && p == 6
    return 54
  if n == 3 && m == 4 && p == 7
    return 64
  if n == 3 && m == 5 && p == 5
    return 58
  if n == 3 && m == 5 && p == 6
    return 68
  if n == 3 && m == 5 && p == 7
    return 79
  if n == 4 && m == 4 && p == 5
    return 60
  if n == 4 && m == 5 && p == 5
    return 76
  if n == 4 && m == 4 && p == 6
    return 73
  if n == 4 && m == 5 && p == 6
    return 90
  if n == 4 && m == 5 && p == 7
    return 104
  if n == 4 && m == 5 && p == 8
    return 118
  if n == 4 && m == 6 && p == 6
    return 105
  if n == 4 && m == 6 && p == 7
    return 123
  if n == 4 && m == 6 && p == 8
    return 140
  if n == 5 && m == 6 && p == 7
    return 150
  0

-> ffrp_target_rank(n, m, p) (i64 i64 i64) i64
  record = ffrp_record_rank(n, m, p) ## i64
  # Proved-optimal profiles remain available for diversity/composition work,
  # but never advertise a rank target below their proved bound.
  if ffpr_exact_rank(n,m,p) == record && record > 0
    return record
  if record > 0
    return record - 1
  0

-> ffrp_proven_optimal(n, m, p) (i64 i64 i64) i64
  if ffpr_exact_rank(n,m,p) > 0 && ffpr_exact_rank(n,m,p) == ffrp_record_rank(n,m,p)
    return 1
  0

-> ffrp_seed_rel(n, m, p) (i64 i64 i64)
  base = "seeds/gf2/"
  if n == 2 && m == 2 && p == 5
    return base + "matmul_2x2x5_rank18_d84_gf2.txt"
  if n == 2 && m == 2 && p == 6
    return base + "matmul_2x2x6_rank21_strassen_blocks_gf2.txt"
  if n == 2 && m == 2 && p == 7
    return base + "matmul_2x2x7_rank25_d128_rect_portfolio_gf2.txt"
  if n == 2 && m == 2 && p == 8
    return base + "matmul_2x2x8_rank28_catalog_gf2.txt"
  if n == 2 && m == 2 && p == 9
    return base + "matmul_2x2x9_rank32_d156_perminov_2025_gf2.txt"
  if n == 2 && m == 3 && p == 4
    return base + "matmul_2x3x4_rank20_d130_global_isotropy_gf2.txt"
  if n == 2 && m == 3 && p == 5
    return base + "matmul_2x3x5_rank25_d160_fleet_gf2.txt"
  if n == 2 && m == 4 && p == 5
    return base + "matmul_2x4x5_rank33_d222_fleet_gf2.txt"
  if n == 2 && m == 5 && p == 6
    return base + "matmul_2x5x6_rank47_catalog_gf2.txt"
  if n == 3 && m == 3 && p == 4
    return base + "matmul_3x3x4_rank29_gf2.txt"
  if n == 3 && m == 3 && p == 5
    return base + "matmul_3x3x5_rank36_d287_gf2.txt"
  if n == 3 && m == 4 && p == 4
    return base + "matmul_3x4x4_rank38_d280_live_density_leader_gf2.txt"
  if n == 3 && m == 4 && p == 5
    return base + "matmul_3x4x5_rank47_d386_gf2.txt"
  if n == 3 && m == 4 && p == 6
    return base + "matmul_3x4x6_rank54_d488_gl_frontier_gf2.txt"
  if n == 3 && m == 4 && p == 7
    return base + "matmul_3x4x7_rank64_d519_gl_frontier_gf2.txt"
  if n == 3 && m == 5 && p == 5
    return base + "matmul_3x5x5_rank58_d518_gf2.txt"
  if n == 3 && m == 5 && p == 6
    return base + "matmul_3x5x6_rank68_catalog_gf2.txt"
  if n == 3 && m == 5 && p == 7
    return base + "matmul_3x5x7_rank79_d699_gf2.txt"
  if n == 4 && m == 4 && p == 5
    return base + "matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt"
  if n == 4 && m == 5 && p == 5
    return base + "matmul_4x5x5_rank76_gf2.txt"
  if n == 4 && m == 4 && p == 6
    return base + "matmul_4x4x6_rank73_d690_gl_frontier_gf2.txt"
  if n == 4 && m == 5 && p == 6
    return base + "matmul_4x5x6_rank90_d906_rect_portfolio_gf2.txt"
  if n == 4 && m == 5 && p == 7
    return base + "matmul_4x5x7_rank104_d1089_gl_frontier_gf2.txt"
  if n == 4 && m == 5 && p == 8
    return base + "matmul_4x5x8_rank118_d1283_gl_frontier_gf2.txt"
  if n == 4 && m == 6 && p == 6
    return base + "matmul_4x6x6_rank105_d1197_gf2.txt"
  if n == 4 && m == 6 && p == 7
    return base + "matmul_4x6x7_rank123_d1406_gl_frontier_gf2.txt"
  if n == 4 && m == 6 && p == 8
    return base + "matmul_4x6x8_rank140_d1560_global_isotropy_gf2.txt"
  if n == 5 && m == 6 && p == 7
    return base + "matmul_5x6x7_rank150_d1875_gl_frontier_gf2.txt"
  ""

# A profile may expose more than one exact frontier door.  Slot zero is the
# monotonic density leader returned by `ffrp_seed_rel`; later slots are kept
# only when they add a materially different verified term set.  The legacy
# 4x4x5 door has zero terms in common with its GL-derived density leader, and
# its third short-orbit splice is independently distant from both. The 2x2x5
# profile also keeps a GPU-discovered block tunnel which returned from the d92
# component to a fifth exact d84 presentation. The 2x2x6 block-local door
# likewise shares no terms with its
# three-Strassen baseline while preserving the same rank and density.
# The 2x2x7 profile keeps its former rank-25/density-132 catalog seed beside
# the rank-25/density-128 portfolio leader; their support distance is 42. The
# 2x2x7, 2x2x8, and 2x2x9 profiles additionally retain certified +1/+2 split
# shoulders from the public corpus. They implement the fleet policy of keeping
# controlled rank debt near a frontier instead of making every CPU island
# knock on the same rank-R door. Other retained rectangular pairs are at
# distance 56--300, so rotating these doors prevents a fresh multiwalker
# campaign from cloning one presentation across every CPU island.
#
# The curated public corpus also retains verified R+1/R+2 shoulders for the
# six larger leaf campaigns below.  Their parents are coordinate-isotropy
# images, so in the runtime coordinates they are far from the density leader
# rather than merely exposing its one-step split inverse.  Keep the discoverer,
# year, construction, and parent digest in each filename; the public metadata
# remains the authoritative full provenance record.
-> ffrp_frontier_seed_count(n, m, p) (i64 i64 i64) i64
  if ffrp_supported(n, m, p) == 0
    return 0
  if n == 2 && m == 2 && p == 5
    return 6
  if n == 2 && m == 2 && p == 6
    return 2
  if n == 2 && m == 2 && p == 7
    return 4
  if n == 2 && m == 2 && p == 8
    return 3
  if n == 2 && m == 2 && p == 9
    return 5
  if n == 2 && m == 3 && p == 5
    return 6
  if n == 2 && m == 4 && p == 5
    return 3
  if n == 2 && m == 5 && p == 6
    return 4
  if n == 3 && m == 3 && p == 5
    return 5
  if n == 3 && m == 4 && p == 6
    return 3
  if n == 3 && m == 4 && p == 7
    return 3
  if n == 3 && m == 5 && p == 5
    return 7
  if n == 3 && m == 5 && p == 6
    return 3
  if n == 3 && m == 5 && p == 7
    return 8
  if n == 3 && m == 3 && p == 4
    return 4
  if n == 3 && m == 4 && p == 4
    return 5
  if n == 3 && m == 4 && p == 5
    return 4
  if n == 4 && m == 4 && p == 5
    return 3
  if n == 4 && m == 4 && p == 6
    return 4
  if n == 4 && m == 5 && p == 6
    return 3
  if n == 4 && m == 5 && p == 7
    return 8
  if n == 4 && m == 5 && p == 8
    return 4
  if n == 4 && m == 6 && p == 6
    return 2
  if n == 4 && m == 6 && p == 7
    return 3
  if n == 4 && m == 6 && p == 8
    return 2
  if n == 4 && m == 5 && p == 5
    return 4
  if n == 5 && m == 6 && p == 7
    return 4
  1

-> ffrp_frontier_seed_rel(n, m, p, slot) (i64 i64 i64 i64)
  if slot < 0 || slot >= ffrp_frontier_seed_count(n, m, p)
    return ""
  if n == 2 && m == 2 && p == 5 && slot == 1
    return "seeds/gf2/matmul_2x2x5_rank18_d88_gf2.txt"
  if n == 2 && m == 2 && p == 5 && slot == 2
    return "seeds/gf2/matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt"
  if n == 2 && m == 2 && p == 5 && slot == 3
    return "seeds/gf2/matmul_2x2x5_rank18_d84_block_splice_gf2.txt"
  if n == 2 && m == 2 && p == 5 && slot == 4
    return "seeds/gf2/matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt"
  # AWS high-leverage campaign archive doors.  Each has zero term overlap
  # with its campaign leader, so these occupy cold rotation slots rather than
  # replacing the monotonic density leaders returned by `ffrp_seed_rel`.
  if n == 2 && m == 2 && p == 5 && slot == 5
    return "seeds/gf2/matmul_2x2x5_rank18_d141_peterson_2026_aws_disjoint_gf2.txt"
  if n == 2 && m == 2 && p == 6 && slot == 1
    return "seeds/gf2/matmul_2x2x6_rank21_d108_block_local_gl_gf2.txt"
  if n == 2 && m == 2 && p == 7 && slot == 1
    return "seeds/gf2/matmul_2x2x7_rank25_catalog_gf2.txt"
  if n == 2 && m == 2 && p == 7 && slot == 2
    return "seeds/gf2/matmul_2x2x7_rank26_isotropy_split_plus1_gf2.txt"
  if n == 2 && m == 2 && p == 7 && slot == 3
    return "seeds/gf2/matmul_2x2x7_rank27_isotropy_split_plus2_gf2.txt"
  if n == 2 && m == 2 && p == 8 && slot == 1
    return "seeds/gf2/matmul_2x2x8_rank29_isotropy_split_plus1_gf2.txt"
  if n == 2 && m == 2 && p == 8 && slot == 2
    return "seeds/gf2/matmul_2x2x8_rank30_isotropy_split_plus2_gf2.txt"
  if n == 2 && m == 2 && p == 9 && slot == 1
    return "seeds/gf2/matmul_2x2x9_rank32_d156_perminov_2025_pperm_cycle_gf2.txt"
  if n == 2 && m == 2 && p == 9 && slot == 2
    return "seeds/gf2/matmul_2x2x9_rank32_d156_perminov_2025_pperm_reverse_gf2.txt"
  if n == 2 && m == 2 && p == 9 && slot == 3
    return "seeds/gf2/matmul_2x2x9_rank33_d159_isotropy_split_plus1_gf2.txt"
  if n == 2 && m == 2 && p == 9 && slot == 4
    return "seeds/gf2/matmul_2x2x9_rank34_d165_isotropy_split_plus2_gf2.txt"
  if n == 2 && m == 3 && p == 5 && slot == 1
    return "seeds/gf2/matmul_2x3x5_rank25_d170_fleet_gf2.txt"
  if n == 2 && m == 3 && p == 5 && slot == 2
    return "seeds/gf2/matmul_2x3x5_rank25_d210_fleet_gf2.txt"
  if n == 2 && m == 3 && p == 5 && slot == 3
    return "seeds/gf2/matmul_2x3x5_rank25_d278_fleet_gf2.txt"
  if n == 2 && m == 3 && p == 5 && slot == 4
    return "seeds/gf2/matmul_2x3x5_rank26_peterson_2026_block15_11_gf2.txt"
  if n == 2 && m == 3 && p == 5 && slot == 5
    return "seeds/gf2/matmul_2x3x5_rank27_peterson_2026_isotropy_split_plus2_parent_06df603ec6_gf2.txt"
  if n == 2 && m == 5 && p == 6 && slot == 1
    return "seeds/gf2/matmul_2x5x6_rank47_d438_orbit_door_gf2.txt"
  if n == 4 && m == 4 && p == 5 && slot == 1
    return "seeds/gf2/matmul_4x4x5_rank60_d919_gf2.txt"
  if n == 4 && m == 4 && p == 5 && slot == 2
    return "seeds/gf2/matmul_4x4x5_rank60_d662_short_orbit_splice_gf2.txt"
  if n == 2 && m == 4 && p == 5 && slot == 1
    return "seeds/gf2/matmul_2x4x5_rank33_d241_gl_frontier_gf2.txt"
  if n == 2 && m == 4 && p == 5 && slot == 2
    return "seeds/gf2/matmul_2x4x5_rank33_catalog_gf2.txt"
  if n == 3 && m == 4 && p == 6 && slot == 1
    return "seeds/gf2/matmul_3x4x6_rank54_catalog_gf2.txt"
  if n == 3 && m == 4 && p == 7 && slot == 1
    return "seeds/gf2/matmul_3x4x7_rank64_d576_gf2.txt"
  if n == 3 && m == 4 && p == 4 && slot == 1
    return "seeds/gf2/matmul_3x4x4_rank38_gf2.txt"
  if n == 3 && m == 3 && p == 4 && slot == 1
    return "seeds/gf2/matmul_3x3x4_rank29_d249_peterson_2026_aws_disjoint_gf2.txt"
  if n == 3 && m == 3 && p == 4 && slot == 2
    return "seeds/gf2/matmul_3x3x4_rank30_peterson_2026_isotropy_split_plus1_parent_5314db3816_gf2.txt"
  if n == 3 && m == 3 && p == 4 && slot == 3
    return "seeds/gf2/matmul_3x3x4_rank31_peterson_2026_isotropy_split_plus2_parent_5314db3816_gf2.txt"
  if n == 3 && m == 4 && p == 4 && slot == 2
    return "seeds/gf2/matmul_3x4x4_rank38_d310_peterson_2026_aws_disjoint_gf2.txt"
  if n == 3 && m == 4 && p == 4 && slot == 3
    return "seeds/gf2/matmul_3x4x4_rank39_peterson_2026_isotropy_split_plus1_parent_91bff8b09f_gf2.txt"
  if n == 3 && m == 4 && p == 4 && slot == 4
    return "seeds/gf2/matmul_3x4x4_rank40_peterson_2026_isotropy_split_plus2_parent_8aa9879491_gf2.txt"
  if n == 3 && m == 4 && p == 5 && slot == 1
    return "seeds/gf2/matmul_3x4x5_rank47_d396_peterson_2026_gf2.txt"
  if n == 3 && m == 4 && p == 5 && slot == 2
    return "seeds/gf2/matmul_3x4x5_rank48_peterson_2026_isotropy_split_plus1_parent_7cd768a07f_gf2.txt"
  if n == 3 && m == 4 && p == 5 && slot == 3
    return "seeds/gf2/matmul_3x4x5_rank49_peterson_2026_isotropy_split_plus2_parent_50f10726e4_gf2.txt"
  if n == 4 && m == 5 && p == 5 && slot == 1
    return "seeds/gf2/matmul_4x5x5_rank76_d721_matmulcatalog_2026_gf2.txt"
  if n == 4 && m == 5 && p == 5 && slot == 2
    return "seeds/gf2/matmul_4x5x5_rank77_peterson_2026_isotropy_split_plus1_parent_2a74e4371e_gf2.txt"
  if n == 4 && m == 5 && p == 5 && slot == 3
    return "seeds/gf2/matmul_4x5x5_rank78_peterson_2026_isotropy_split_plus2_parent_f95eb7bc99_gf2.txt"
  if n == 4 && m == 4 && p == 6 && slot == 1
    return "seeds/gf2/matmul_4x4x6_rank73_gf2.txt"
  if n == 4 && m == 5 && p == 6 && slot == 1
    return "seeds/gf2/matmul_4x5x6_rank90_d907_gl_frontier_gf2.txt"
  if n == 4 && m == 5 && p == 6 && slot == 2
    return "seeds/gf2/matmul_4x5x6_rank90_catalog_gf2.txt"
  if n == 4 && m == 5 && p == 7 && slot == 1
    return "seeds/gf2/matmul_4x5x7_rank104_d1160_gf2.txt"
  if n == 4 && m == 5 && p == 8 && slot == 1
    return "seeds/gf2/matmul_4x5x8_rank118_d1729_gf2.txt"
  if n == 4 && m == 6 && p == 7 && slot == 1
    return "seeds/gf2/matmul_4x6x7_rank123_catalog_gf2.txt"
  if n == 4 && m == 6 && p == 8 && slot == 1
    return "seeds/gf2/matmul_4x6x8_rank140_d1748_gf2.txt"
  if n == 5 && m == 6 && p == 7 && slot == 1
    return "seeds/gf2/matmul_5x6x7_rank150_catalog_gf2.txt"
  if n == 5 && m == 6 && p == 7 && slot == 2
    return "seeds/gf2/matmul_5x6x7_rank151_peterson_2026_isotropy_split_plus1_parent_58d60803a6_gf2.txt"
  if n == 5 && m == 6 && p == 7 && slot == 3
    return "seeds/gf2/matmul_5x6x7_rank152_peterson_2026_isotropy_split_plus2_parent_806ac40bca_gf2.txt"
  # Public-corpus doors (2026-09 import; per-file provenance in THIRD_PARTY.md):
  # normalized GF(2) reductions of MIT-licensed FastMatrixMultiplication
  # schemes (Perminov results, plus its AlphaTensor/AlphaEvolve conversions)
  # and of AlphaTensor's Apache-2.0 F2 factorizations.  Every door differs
  # from every earlier door of its profile in exact term set and in
  # `ffrda_structural_signature`, and same-rank doors are at least ceil(R/4)
  # terms of symmetric difference from every earlier door, so no import is
  # a coordinate relabeling or a few-flip neighbour of a packaged seed.
  # Slots list same-rank doors by ascending density, then at most one R+1
  # and one R+2 shoulder.  Slot zero (`ffrp_seed_rel`) is unchanged.
  if n == 2 && m == 5 && p == 6 && slot == 2
    return "seeds/gf2/matmul_2x5x6_rank47_d763_perminov_2026_serendipitous_5ec0a82ac7_gf2.txt"
  if n == 2 && m == 5 && p == 6 && slot == 3
    return "seeds/gf2/matmul_2x5x6_rank47_d892_perminov_2026_serendipitous_66ab3aeb9f_gf2.txt"
  if n == 3 && m == 3 && p == 5 && slot == 1
    return "seeds/gf2/matmul_3x3x5_rank36_d265_alphatensor_2022_z_gf2.txt"
  if n == 3 && m == 3 && p == 5 && slot == 2
    return "seeds/gf2/matmul_3x3x5_rank36_d317_alphatensor_2022_f2_gf2.txt"
  if n == 3 && m == 3 && p == 5 && slot == 3
    return "seeds/gf2/matmul_3x3x5_rank36_d392_perminov_2026_serendipitous_dcc0b5ad07_gf2.txt"
  if n == 3 && m == 3 && p == 5 && slot == 4
    return "seeds/gf2/matmul_3x3x5_rank38_d328_perminov_2026_serendipitous_8438674c82_gf2.txt"
  if n == 3 && m == 4 && p == 6 && slot == 2
    return "seeds/gf2/matmul_3x4x6_rank56_d489_perminov_2025_zt_gf2.txt"
  if n == 3 && m == 4 && p == 7 && slot == 2
    return "seeds/gf2/matmul_3x4x7_rank64_d603_perminov_2025_zt_gf2.txt"
  if n == 3 && m == 5 && p == 5 && slot == 1
    return "seeds/gf2/matmul_3x5x5_rank58_d482_perminov_2025_naive_c351_gf2.txt"
  if n == 3 && m == 5 && p == 5 && slot == 2
    return "seeds/gf2/matmul_3x5x5_rank58_d500_alphatensor_2022_z_gf2.txt"
  if n == 3 && m == 5 && p == 5 && slot == 3
    return "seeds/gf2/matmul_3x5x5_rank58_d544_alphatensor_2022_f2_gf2.txt"
  if n == 3 && m == 5 && p == 5 && slot == 4
    return "seeds/gf2/matmul_3x5x5_rank58_d613_perminov_2026_serendipitous_506f8f6eb3_gf2.txt"
  if n == 3 && m == 5 && p == 5 && slot == 5
    return "seeds/gf2/matmul_3x5x5_rank58_d634_perminov_2026_serendipitous_e3fdc8efb8_gf2.txt"
  if n == 3 && m == 5 && p == 5 && slot == 6
    return "seeds/gf2/matmul_3x5x5_rank60_d1011_perminov_2026_serendipitous_73950dde67_gf2.txt"
  if n == 3 && m == 5 && p == 6 && slot == 1
    return "seeds/gf2/matmul_3x5x6_rank68_d677_perminov_2026_serendipitous_e2edca7153_gf2.txt"
  if n == 3 && m == 5 && p == 6 && slot == 2
    return "seeds/gf2/matmul_3x5x6_rank70_d719_perminov_2025_addred_cr265_gf2.txt"
  if n == 3 && m == 5 && p == 7 && slot == 1
    return "seeds/gf2/matmul_3x5x7_rank79_d796_perminov_2026_serendipitous_6fdc4c9f06_gf2.txt"
  if n == 3 && m == 5 && p == 7 && slot == 2
    return "seeds/gf2/matmul_3x5x7_rank79_d797_perminov_2026_serendipitous_cdc7d44ac6_gf2.txt"
  if n == 3 && m == 5 && p == 7 && slot == 3
    return "seeds/gf2/matmul_3x5x7_rank79_d924_perminov_2026_serendipitous_943c9b5305_gf2.txt"
  if n == 3 && m == 5 && p == 7 && slot == 4
    return "seeds/gf2/matmul_3x5x7_rank79_d1630_perminov_2026_serendipitous_92252b0e1a_gf2.txt"
  if n == 3 && m == 5 && p == 7 && slot == 5
    return "seeds/gf2/matmul_3x5x7_rank79_d1690_perminov_2026_z_gf2.txt"
  if n == 3 && m == 5 && p == 7 && slot == 6
    return "seeds/gf2/matmul_3x5x7_rank80_d831_alphaevolve_2025_gf2.txt"
  if n == 3 && m == 5 && p == 7 && slot == 7
    return "seeds/gf2/matmul_3x5x7_rank81_d895_perminov_2026_zt_gf2.txt"
  if n == 4 && m == 4 && p == 6 && slot == 2
    return "seeds/gf2/matmul_4x4x6_rank73_d735_perminov_2025_zt_gf2.txt"
  if n == 4 && m == 4 && p == 6 && slot == 3
    return "seeds/gf2/matmul_4x4x6_rank73_d1406_perminov_2026_serendipitous_fb4e63f7bf_gf2.txt"
  if n == 4 && m == 5 && p == 7 && slot == 2
    return "seeds/gf2/matmul_4x5x7_rank104_d1222_perminov_2025_serendipitous_c41080c5e5_gf2.txt"
  if n == 4 && m == 5 && p == 7 && slot == 3
    return "seeds/gf2/matmul_4x5x7_rank104_d1247_perminov_2025_serendipitous_63dd14617f_gf2.txt"
  if n == 4 && m == 5 && p == 7 && slot == 4
    return "seeds/gf2/matmul_4x5x7_rank104_d1252_perminov_2025_serendipitous_43d850ea60_gf2.txt"
  if n == 4 && m == 5 && p == 7 && slot == 5
    return "seeds/gf2/matmul_4x5x7_rank104_d1377_perminov_2026_serendipitous_444e8a9ac8_gf2.txt"
  if n == 4 && m == 5 && p == 7 && slot == 6
    return "seeds/gf2/matmul_4x5x7_rank104_d1391_perminov_2026_serendipitous_0b3b2fc9c4_gf2.txt"
  if n == 4 && m == 5 && p == 7 && slot == 7
    return "seeds/gf2/matmul_4x5x7_rank104_d1394_perminov_2026_serendipitous_a71031bd4e_gf2.txt"
  if n == 4 && m == 5 && p == 8 && slot == 2
    return "seeds/gf2/matmul_4x5x8_rank118_d1789_perminov_2025_zt_gf2.txt"
  if n == 4 && m == 5 && p == 8 && slot == 3
    return "seeds/gf2/matmul_4x5x8_rank118_d1810_perminov_2026_serendipitous_b428f55b8f_gf2.txt"
  if n == 4 && m == 6 && p == 6 && slot == 1
    return "seeds/gf2/matmul_4x6x6_rank105_d1198_perminov_2026_serendipitous_6c1e220825_gf2.txt"
  if n == 4 && m == 6 && p == 7 && slot == 2
    return "seeds/gf2/matmul_4x6x7_rank123_d1930_perminov_2025_serendipitous_1c38c2b939_gf2.txt"
  ffrp_seed_rel(n, m, p)

# GPU geometry is intentionally present only for profiles with a specialized
# Tungsten worker. The remaining CPU-only profiles remain valid
# CPU campaigns without pretending that a generic square kernel is safe.
-> ffrp_gpu_cap(n, m, p) (i64 i64 i64) i64
  if n == 2 && m == 2 && p == 5
    return 64
  if n == 2 && m == 2 && p == 6
    return 64
  if n == 2 && m == 2 && p == 7
    return 64
  if n == 2 && m == 2 && p == 8
    return 64
  if n == 2 && m == 2 && p == 9
    return 64
  if n == 2 && m == 3 && p == 4
    return 64
  if n == 2 && m == 3 && p == 5
    return 68
  if n == 2 && m == 4 && p == 5
    return 80
  if n == 2 && m == 5 && p == 6
    return 92
  if n == 3 && m == 3 && p == 4
    return 68
  if n == 3 && m == 3 && p == 5
    return 77
  if n == 3 && m == 4 && p == 4
    return 80
  if n == 3 && m == 4 && p == 5
    return 92
  if n == 3 && m == 4 && p == 6
    return 104
  if n == 3 && m == 4 && p == 7
    return 116
  if n == 3 && m == 5 && p == 5
    return 107
  if n == 3 && m == 5 && p == 6
    return 122
  # 3x5x7 has 15/35/21-bit factors, so it takes the i64 worker.  CAP=128
  # keeps 49 slots above the rank-79 reference at 128*8*8*3 = 24,576 bytes.
  if n == 3 && m == 5 && p == 7
    return 128
  if n == 4 && m == 4 && p == 5
    return 112
  if n == 4 && m == 4 && p == 6
    return 128
  # 4x5x5 (20/25/20-bit factors) fits the i32 worker.  CAP=128 keeps 52
  # slots above the rank-76 reference at 128*16*4*3 = 24,576 bytes.
  if n == 4 && m == 5 && p == 5
    return 128
  if n == 4 && m == 5 && p == 6
    return 152
  # The 35-bit V factor requires the i64 worker.  CAP=168 retains 64 slots
  # above the r104 frontier while allowing eight walkers to fit in one
  # 32,768-byte Metal threadgroup allocation.
  if n == 4 && m == 5 && p == 7
    return 168
  # 4x5x8 (20/40/32-bit factors) reuses the 168-slot eight-walker i64
  # geometry: 50 slots above its rank-118 reference in 32,256 bytes.
  if n == 4 && m == 5 && p == 8
    return 168
  # 4x6x6 (24/36/24-bit factors): CAP=160 keeps 55 slots above the rank-105
  # reference at 160*8*8*3 = 30,720 bytes.
  if n == 4 && m == 6 && p == 6
    return 160
  # The high-leverage 4x6x7 frontier has 24/42/28-bit factors.  Its rank-123
  # and rank-168 naive seeds both fit the same 168-slot, eight-walker i64
  # geometry as 4x5x7 (32,256 bytes of threadgroup memory).
  if n == 4 && m == 6 && p == 7
    return 168
  # 4x6x8 (24/48/32-bit factors) is the widest bundled rectangle.  CAP=170 is
  # the largest eight-walker i64 capacity under the ceiling (170*8*8*3 =
  # 32,640 bytes) and keeps 30 slots above the rank-140 reference.
  if n == 4 && m == 6 && p == 8
    return 170
  # 5x6x7 (30/42/35-bit factors) needs 50 slots above its rank-150 reference;
  # eight walkers would cap out at 170, so it runs four walkers per group:
  # 200*4*8*3 = 19,200 bytes.
  if n == 5 && m == 6 && p == 7
    return 200
  0

# Factor masks wider than 30 bits need the i64 worker variant; the host relay
# and the generated kernel size their buffers from this same rule.
-> ffrp_gpu_mask_bytes(n, m, p) (i64 i64 i64) i64
  if n * m > 30 || m * p > 30 || n * p > 30
    return 8
  4

-> ffrp_gpu_wpg(n, m, p) (i64 i64 i64) i64
  if ffrp_gpu_cap(n, m, p) < 1
    return 0
  # Eight-byte masks halve the walkers that fit one 32,768-byte threadgroup;
  # 5x6x7 halves again so its rank-150 frontier keeps 50 slots of room.
  if n == 5 && m == 6 && p == 7
    return 4
  if ffrp_gpu_mask_bytes(n, m, p) == 8
    return 8
  16

# A finite standalone campaign must not depend on the RNG-selected starting
# band to see both sides of the search.  Reserve deterministic bookends for
# focused work and algebraic wandering, and leave most moves to the adaptive
# sawtooth zone engine.  At the documented 100M-move scale this is
# 10M work + 70M adaptive + 20M wander; a 10k smoke is already long enough
# for the guaranteed wander slice to hit the worker's 2k split cadence.
-> ffrp_campaign_budgets(steps, budgets) (i64 i64[]) i64
  total = steps ## i64
  if total < 0
    total = 0
  focused_work = total / 10 ## i64
  guaranteed_wander = total / 5 ## i64
  if total >= 2 && focused_work < 1
    focused_work = 1
  if total >= 2 && guaranteed_wander < 1
    guaranteed_wander = 1
  if focused_work + guaranteed_wander > total
    guaranteed_wander = total - focused_work
  adaptive = total - focused_work - guaranteed_wander ## i64
  budgets[0] = focused_work
  budgets[1] = adaptive
  budgets[2] = guaranteed_wander
  total

-> ffrp_work_quota(steps) (i64) i64
  quota = steps / 10 ## i64
  if quota < 1000
    quota = 1000
  quota

-> ffrp_wander_quota(steps) (i64) i64
  quota = steps / 25 ## i64
  if quota < 250
    quota = 250
  quota

# Bounded real-frontier audit of exact selected-subset replacements under
# simultaneous raw maps on all three factor spaces.
#
# All 4^3 operation-family triples and support-guided high/low coordinate
# variants exercise swaps, shears, deletes, and folds on every factor.
# Complete n^6-bit rows are eliminated; every changed basis endpoint is
# parity-compacted and rebuilt behind the independent full tensor gate.
#
# Usage:
#   flipfleet_three_factor_map_nullspace_bench \
#       [only_n=0] [variants=8] [output_prefix] [custom_scheme]

use flipfleet_three_factor_map_nullspace

+ FF3MBenchScratch
  -> new(rank, n, capacity)
    @kernel = FFPANWorkspace.new(rank, n, capacity)
    @out_u = i64[capacity]
    @out_v = i64[capacity]
    @out_w = i64[capacity]
    @best_u = i64[capacity]
    @best_v = i64[capacity]
    @best_w = i64[capacity]

  -> kernel()
    @kernel
  -> out_u()
    @out_u
  -> out_v()
    @out_v
  -> out_w()
    @out_w
  -> best_u()
    @best_u
  -> best_v()
    @best_v
  -> best_w()
    @best_w

-> ff3mb_density(us, vs, ws, rank) (i64[] i64[] i64[] i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < rank
    density += ffw_popcount(us[i]) + ffw_popcount(vs[i]) + ffw_popcount(ws[i])
    i += 1
  density

-> ff3mb_copy(source_u, source_v, source_w, target_u, target_v, target_w, count) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    target_u[i] = source_u[i]
    target_v[i] = source_v[i]
    target_w[i] = source_w[i]
    i += 1
  count

-> ff3mb_axis_value(us, vs, ws, position, axis) (i64[] i64[] i64[] i64 i64) i64
  if axis == 0
    return us[position]
  if axis == 1
    return vs[position]
  ws[position]

-> ff3mb_source_score(us, vs, ws, rank, axis, operation, coordinate) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  frequency = 0 ## i64
  singleton = 0 ## i64
  doubleton = 0 ## i64
  bit = 1 << coordinate ## i64
  i = 0 ## i64
  while i < rank
    value = ff3mb_axis_value(us, vs, ws, i, axis) ## i64
    if (value & bit) != 0
      frequency += 1
      if value == bit
        singleton += 1
      if ffw_popcount(value) == 2
        doubleton += 1
    i += 1
  if operation == 2
    return singleton * 1000000 + frequency
  if operation == 3
    return doubleton * 1000000 + frequency
  frequency

-> ff3mb_target_score(us, vs, ws, rank, axis, operation, source, target) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  source_bit = 1 << source ## i64
  target_bit = 1 << target ## i64
  source_only = 0 ## i64
  both = 0 ## i64
  different = 0 ## i64
  exact_pair = 0 ## i64
  target_frequency = 0 ## i64
  i = 0 ## i64
  while i < rank
    value = ff3mb_axis_value(us, vs, ws, i, axis) ## i64
    has_source = (value & source_bit) != 0 ## bool
    has_target = (value & target_bit) != 0 ## bool
    if has_target
      target_frequency += 1
    if has_source && has_target
      both += 1
    if has_source && !has_target
      source_only += 1
    if has_source != has_target
      different += 1
    if value == (source_bit | target_bit)
      exact_pair += 1
    i += 1
  if operation == 0
    return different * 10000 + both
  if operation == 1
    balanced = source_only ## i64
    if both < balanced
      balanced = both
    return balanced * 10000 + both + target_frequency
  if operation == 3
    return exact_pair * 1000000 + both * 1000 + target_frequency
  0

# Select an order statistic from the high- or low-support end.  Eight variants
# cover the first four of each, rather than repeatedly choosing the densest
# raw coordinate.
-> ff3mb_pick_source(us, vs, ws, rank, width, axis, operation, variant) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  low = variant % 2 ## i64
  ordinal = (variant / 2) % 4 ## i64
  used = i64[width]
  chosen = 0 - 1 ## i64
  pass = 0 ## i64
  while pass <= ordinal
    chosen = 0 - 1
    chosen_score = 0 ## i64
    coordinate = 0 ## i64
    while coordinate < width
      if used[coordinate] == 0
        score = ff3mb_source_score(us, vs, ws, rank, axis, operation, coordinate) ## i64
        better = chosen < 0 ## bool
        if chosen >= 0 && low == 0 && score > chosen_score
          better = true
        if chosen >= 0 && low != 0 && score < chosen_score
          better = true
        if better
          chosen = coordinate
          chosen_score = score
      coordinate += 1
    if chosen >= 0
      used[chosen] = 1
    pass += 1
  chosen

-> ff3mb_pick_target(us, vs, ws, rank, width, axis, operation, source, variant) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  if operation == 2
    return 0
  low = variant % 2 ## i64
  ordinal = (variant / 2) % 4 ## i64
  used = i64[width]
  used[source] = 1
  chosen = 0 - 1 ## i64
  pass = 0 ## i64
  while pass <= ordinal
    chosen = 0 - 1
    chosen_score = 0 ## i64
    coordinate = 0 ## i64
    while coordinate < width
      if used[coordinate] == 0
        score = ff3mb_target_score(us, vs, ws, rank, axis, operation, source, coordinate) ## i64
        better = chosen < 0 ## bool
        if chosen >= 0 && low == 0 && score > chosen_score
          better = true
        if chosen >= 0 && low != 0 && score < chosen_score
          better = true
        if better
          chosen = coordinate
          chosen_score = score
      coordinate += 1
    if chosen >= 0
      used[chosen] = 1
    pass += 1
  chosen

-> ff3mb_operation_triple(index, operations) (i64 i64[]) i64
  if index < 0 || index >= 64 || operations.size() < 3
    return 0
  operations[0] = index / 16
  operations[1] = (index / 4) % 4
  operations[2] = index % 4
  1

# stats: kernels, nullity sum, bases, set noops, nontrivial bases, full gates,
# exact changed, failures, rank drops, density wins, rank neutral, max distance,
# min weight, rows, zeros, duplicate pairs, best rank, best density,
# best distance, min nullity, max nullity, relation failures,
# nontrivial kernels.
-> ff3mb_reset(stats, rank, density) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < stats.size()
    stats[i] = 0
    i += 1
  stats[12] = rank + 1
  stats[16] = rank
  stats[17] = density
  stats[19] = rank + 1
  1

-> ff3mb_audit_plan(label, us, vs, ws, rank, n, plan, scratch, stats, source_density) (String i64[] i64[] i64[] i64 i64 i64[] FF3MBenchScratch i64[] i64) i64
  kernel = scratch.kernel()
  words = ffpa_tensor_words(n) ## i64
  built = ff3m_build_deltas(us, vs, ws, rank, n, plan, kernel.transformed_u(), kernel.transformed_v(), kernel.transformed_w(), kernel.deltas()) ## i64
  stats[0] = stats[0] + 1
  stats[13] = stats[13] + rank
  if built != words
    stats[7] = stats[7] + 1
    return 0 - 1
  nullity = ffpan_nullspace_into(kernel.deltas(), rank, words, kernel.dependencies(), kernel.basis_rows(), kernel.basis_coefficients(), kernel.pivot_owners(), kernel.work(), kernel.work_coefficients(), kernel.nullspace_meta()) ## i64
  if nullity < 0
    stats[7] = stats[7] + 1
    return 0 - 1
  stats[1] = stats[1] + nullity
  if nullity < stats[19]
    stats[19] = nullity
  if nullity > stats[20]
    stats[20] = nullity
  changed_in_kernel = 0 ## i64
  dependency = 0 ## i64
  while dependency < nullity
    stats[2] = stats[2] + 1
    weight = ffpan_dependency_weight(kernel.dependencies(), dependency, rank) ## i64
    made = ffpan_dependency_ids(kernel.dependencies(), dependency, rank, kernel.ids()) ## i64
    if made != weight || ffpa_relation_exact(kernel.deltas(), kernel.ids(), made, words) != 1
      stats[21] = stats[21] + 1
      stats[7] = stats[7] + 1
    else
      if ff3m_selected_image_same_parity(us, vs, ws, kernel.transformed_u(), kernel.transformed_v(), kernel.transformed_w(), kernel.ids(), made) == 1
        stats[3] = stats[3] + 1
      else
        changed_in_kernel = 1
        stats[4] = stats[4] + 1
        if weight < stats[12]
          stats[12] = weight
        materialize_meta = i64[3]
        endpoint_rank = ff3m_materialize(us, vs, ws, rank, kernel.transformed_u(), kernel.transformed_v(), kernel.transformed_w(), kernel.ids(), made, kernel.raw_u(), kernel.raw_v(), kernel.raw_w(), scratch.out_u(), scratch.out_v(), scratch.out_w(), materialize_meta) ## i64
        stats[14] = stats[14] + materialize_meta[0]
        stats[15] = stats[15] + materialize_meta[1]
        exact = 0 ## i64
        if endpoint_rank > 0
          loaded = ffw_init_terms_cap(kernel.endpoint(), scratch.out_u(), scratch.out_v(), scratch.out_w(), endpoint_rank, n, kernel.capacity(), 813001 + stats[4] * 17 + n * 1009, 0, 1, 1, 1) ## i64
          stats[5] = stats[5] + 1
          if loaded == endpoint_rank && ffw_verify_current_exact(kernel.endpoint(), n) == 1
            exact = 1
        if exact == 0
          stats[7] = stats[7] + 1
          << "THREE_FACTOR_GATE_FAIL tensor=" + label + " weight=" + weight.to_s() + " endpoint_rank=" + endpoint_rank.to_s()
        if exact == 1
          distance = ffpan_term_set_distance_unique(us, vs, ws, rank, scratch.out_u(), scratch.out_v(), scratch.out_w(), endpoint_rank) ## i64
          if distance == 0
            stats[3] = stats[3] + 1
          if distance > 0
            stats[6] = stats[6] + 1
            density = ff3mb_density(scratch.out_u(), scratch.out_v(), scratch.out_w(), endpoint_rank) ## i64
            if endpoint_rank < rank
              stats[8] = stats[8] + 1
            if endpoint_rank == rank
              stats[10] = stats[10] + 1
              if density < source_density
                stats[9] = stats[9] + 1
            if distance > stats[11]
              stats[11] = distance
            better = endpoint_rank < stats[16] ## bool
            if endpoint_rank == stats[16] && density < stats[17]
              better = true
            if endpoint_rank == stats[16] && density == stats[17] && distance > stats[18]
              better = true
            if better
              stats[16] = endpoint_rank
              stats[17] = density
              stats[18] = distance
              z = ff3mb_copy(scratch.out_u(), scratch.out_v(), scratch.out_w(), scratch.best_u(), scratch.best_v(), scratch.best_w(), endpoint_rank) ## i64
            if endpoint_rank < rank || (endpoint_rank == rank && density < source_density)
              << "THREE_FACTOR_IMPROVEMENT tensor=" + label + " rank=" + endpoint_rank.to_s() + " density=" + density.to_s() + " distance=" + distance.to_s() + " weight=" + weight.to_s()
    dependency += 1
  if changed_in_kernel == 1
    stats[22] = stats[22] + 1
  1

-> ff3mb_summary(label, rank, density, variants, stats, elapsed_ms) (String i64 i64 i64 i64[] i64) i64
  min_weight = stats[12] ## i64
  if min_weight > rank
    min_weight = 0 - 1
  min_nullity = stats[19] ## i64
  if min_nullity > rank
    min_nullity = 0 - 1
  kernels_per_s = 0 ## i64
  rows_per_s = 0 ## i64
  if elapsed_ms > 0
    kernels_per_s = stats[0] * 1000 / elapsed_ms
    rows_per_s = stats[13] * 1000 / elapsed_ms
  << "THREE_FACTOR_SUMMARY tensor=" + label + " rank=" + rank.to_s() + " density=" + density.to_s() + " variants=" + variants.to_s() + " kernels=" + stats[0].to_s() + " rows=" + stats[13].to_s() + " nullity_min=" + min_nullity.to_s() + " nullity_max=" + stats[20].to_s() + " bases=" + stats[2].to_s() + " set_noops=" + stats[3].to_s() + " nontrivial_bases=" + stats[4].to_s() + " nontrivial_kernels=" + stats[22].to_s() + " full_gates=" + stats[5].to_s() + " exact_changed=" + stats[6].to_s() + " failures=" + stats[7].to_s() + " relation_failures=" + stats[21].to_s() + " rank_drops=" + stats[8].to_s() + " density_wins=" + stats[9].to_s() + " rank_neutral=" + stats[10].to_s() + " best_rank=" + stats[16].to_s() + " best_density=" + stats[17].to_s() + " best_distance=" + stats[18].to_s() + " max_distance=" + stats[11].to_s() + " min_weight=" + min_weight.to_s() + " zeros=" + stats[14].to_s() + " duplicates=" + stats[15].to_s() + " elapsed_ms=" + elapsed_ms.to_s() + " kernels_s=" + kernels_per_s.to_s() + " rows_s=" + rows_per_s.to_s()
  1

-> ff3mb_dump_best(prefix, label, rank, n, capacity, scratch, stats) (String String i64 i64 i64 FF3MBenchScratch i64[]) i64
  if prefix == "" || stats[6] < 1
    return 0
  best_rank = stats[16] ## i64
  state = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(state, scratch.best_u(), scratch.best_v(), scratch.best_w(), best_rank, n, capacity, 823001 + n, 0, 1, 1, 1) ## i64
  if loaded != best_rank || ffw_verify_best_exact(state, n) != 1
    return 0 - 1
  path = prefix + "_" + label + "_r" + best_rank.to_s() + "_d" + stats[17].to_s() + ".txt" ## String
  dumped = ffw_dump_best(state, path) ## i64
  << "THREE_FACTOR_BEST path=" + path + " rank=" + best_rank.to_s() + " density=" + stats[17].to_s() + " distance=" + stats[18].to_s() + " exact=" + (dumped == best_rank).to_s()
  dumped

-> ff3mb_run(label, path, n, variants, output_prefix) (String String i64 i64 String) i64
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(state, path, n, capacity, 803001 + n, 0, 1, 1, 1) ## i64
  if rank < 2 || ffw_verify_best_exact(state, n) != 1
    << "THREE_FACTOR_ERROR tensor=" + label + " error=load"
    return 0 - 1
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if ffw_export_best(state, us, vs, ws) != rank
    return 0 - 1
  density = ff3mb_density(us, vs, ws, rank) ## i64
  scratch = FF3MBenchScratch.new(rank, n, capacity)
  stats = i64[23]
  z = ff3mb_reset(stats, rank, density) ## i64
  plan = i64[12]
  started = ccall("__w_clock_ms") ## i64
  operation_index = 0 ## i64
  while operation_index < 64
    variant = 0 ## i64
    while variant < variants
      operations = i64[3]
      plan_ok = ff3mb_operation_triple(operation_index, operations) ## i64
      axis = 0 ## i64
      while axis < 3 && plan_ok == 1
        operation = operations[axis] ## i64
        local_variant = variant + axis * 3 + operation_index ## i64
        source = ff3mb_pick_source(us, vs, ws, rank, n * n, axis, operation, local_variant) ## i64
        target = ff3mb_pick_target(us, vs, ws, rank, n * n, axis, operation, source, local_variant + axis + 2) ## i64
        offset = axis * 4 ## i64
        plan[offset] = axis
        plan[offset + 1] = operation
        plan[offset + 2] = source
        plan[offset + 3] = target
        axis += 1
      if plan_ok != 1 || ff3m_valid_plan(n * n, plan) != 1
        stats[7] = stats[7] + 1
      else
        z = ff3mb_audit_plan(label, us, vs, ws, rank, n, plan, scratch, stats, density)
      variant += 1
    operation_index += 1
  elapsed_ms = ccall("__w_clock_ms") - started ## i64
  z = ff3mb_summary(label, rank, density, variants, stats, elapsed_ms)
  ff3mb_dump_best(output_prefix, label, rank, n, capacity, scratch, stats)

args = argv()
only_n = 0 ## i64
variants = 8 ## i64
output_prefix = "" ## String
custom_scheme = "" ## String
if args.size() > 0
  only_n = args[0].to_i()
if args.size() > 1
  variants = args[1].to_i()
if args.size() > 2
  output_prefix = args[2]
if args.size() > 3
  custom_scheme = args[3]
if only_n != 0 && (only_n < 3 || only_n > 7)
  << "invalid only_n"
  exit(2)
if variants < 1 || variants > 32
  << "invalid variants"
  exit(2)
if custom_scheme != ""
  if only_n < 3 || only_n > 7
    << "custom_scheme requires only_n=3..7"
    exit(2)
  z = ff3mb_run("custom-" + only_n.to_s() + "x" + only_n.to_s(), custom_scheme, only_n, variants, output_prefix) ## i64
  exit(0)

if only_n == 0 || only_n == 3
  z = ff3mb_run("3x3-d139", "benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt", 3, variants, output_prefix) ## i64
  z = ff3mb_run("3x3-d159", "benchmarks/matmul/metaflip/matmul_3x3_rank23_d159_gf2.txt", 3, variants, output_prefix)
if only_n == 0 || only_n == 4
  z = ff3mb_run("4x4-d450", "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt", 4, variants, output_prefix)
  z = ff3mb_run("4x4-d677", "benchmarks/matmul/metaflip/matmul_4x4_rank47_d677_flips_gf2.txt", 4, variants, output_prefix)
if only_n == 0 || only_n == 5
  z = ff3mb_run("5x5-d968", "benchmarks/matmul/metaflip/matmul_5x5_rank93_d968_global_isotropy_gf2.txt", 5, variants, output_prefix)
  z = ff3mb_run("5x5-d1155", "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", 5, variants, output_prefix)
if only_n == 0 || only_n == 6
  z = ff3mb_run("6x6-d1860", "benchmarks/matmul/metaflip/matmul_6x6_rank153_d1860_global_isotropy_gf2.txt", 6, variants, output_prefix)
  z = ff3mb_run("6x6-d2502", "benchmarks/matmul/metaflip/matmul_6x6_rank153_d2502_gf2.txt", 6, variants, output_prefix)
if only_n == 7
  z = ff3mb_run("7x7-d3098", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt", 7, variants, output_prefix)
  z = ff3mb_run("7x7-d3554", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt", 7, variants, output_prefix)

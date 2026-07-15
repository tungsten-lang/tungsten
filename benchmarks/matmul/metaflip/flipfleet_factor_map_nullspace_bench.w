# Bounded real-frontier audit for exact selected-subset replacements under raw
# one-factor linear maps.  This deliberately does not assume a tensor
# automorphism and therefore has no inevitable whole-scheme dependency.
#
# The source-coordinate kernels are shared:
#   shear(source,target), delete(source), and fold(source,target)
# all have the same coefficient kernel for fixed factor/source, differing only
# in the fixed output direction.  We eliminate just 3*n^2 complete n^6 delta
# systems, then materialize every target/map from each dependency.  Raw swaps
# require one kernel per factor/coordinate pair.  Every non-noop materialized
# endpoint is zero-omitted, parity-compacted, and exhaustively n^6-gated.
#
# Usage:
#   flipfleet_factor_map_nullspace_bench \
#       [only_n=0] [family=-1] [kernel_cap=0] [candidate_cap=2000] [output_prefix]
# family: -1 both, 0 shared-source maps, 1 raw coordinate swaps.

use flipfleet_factor_map_nullspace

+ FFMFNBenchScratch
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

-> ffmfnb_density(us, vs, ws, rank) (i64[] i64[] i64[] i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < rank
    density += ffw_popcount(us[i]) + ffw_popcount(vs[i]) + ffw_popcount(ws[i])
    i += 1
  density

-> ffmfnb_copy(source_u, source_v, source_w, target_u, target_v, target_w, count) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    target_u[i] = source_u[i]
    target_v[i] = source_v[i]
    target_w[i] = source_w[i]
    i += 1
  count

# stats: kernels, nullity sum, fixed bases, nontrivial bases, maps transformed,
# set-noops, candidates gated, exact changed endpoints, failures, rank drops,
# density wins, best rank, best density, max distance, min weight, zero terms,
# duplicate cancellations, elimination ms, admission ms, skipped by cap,
# source noops, best weight, best distance, best factor/op/source/target,
# max nullity, min nullity, relation failures, candidate exact gates,
# rank-neutral changed endpoints, total basis weight.
-> ffmfnb_reset(stats, histogram, rank, source_density) (i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < stats.size()
    stats[i] = 0
    i += 1
  i = 0
  while i < histogram.size()
    histogram[i] = 0
    i += 1
  stats[11] = rank
  stats[12] = source_density
  stats[14] = rank + 1
  stats[21] = rank + 1
  stats[28] = rank + 1
  1

-> ffmfnb_admit(label, us, vs, ws, rank, n, factor, operation, source, target, ids, made, weight, scratch, stats, source_density, candidate_cap) (String i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64 i64 FFMFNBenchScratch i64[] i64 i64) i64
  kernel = scratch.kernel()
  transformed_u = kernel.transformed_u()
  transformed_v = kernel.transformed_v()
  transformed_w = kernel.transformed_w()
  stats[4] = stats[4] + 1
  if ffmfn_transform_terms(us, vs, ws, rank, n, factor, operation, source, target, transformed_u, transformed_v, transformed_w) != rank
    stats[8] = stats[8] + 1
    return 0 - 1
  if ffpa_selected_image_same_set(us, vs, ws, transformed_u, transformed_v, transformed_w, ids, made) == 1
    stats[5] = stats[5] + 1
    return 0
  if candidate_cap > 0 && stats[6] >= candidate_cap
    stats[19] = stats[19] + 1
    return 0
  stats[6] = stats[6] + 1
  started = ccall("__w_clock_ms") ## i64
  raw_u = kernel.raw_u()
  raw_v = kernel.raw_v()
  raw_w = kernel.raw_w()
  z = ffmfnb_copy(us, vs, ws, raw_u, raw_v, raw_w, rank) ## i64
  i = 0 ## i64
  while i < made
    position = ids[i] ## i64
    raw_u[position] = transformed_u[position]
    raw_v[position] = transformed_v[position]
    raw_w[position] = transformed_w[position]
    i += 1
  compact_meta = i64[2]
  endpoint_rank = ffmfn_compact_allow_zero(raw_u, raw_v, raw_w, rank, scratch.out_u(), scratch.out_v(), scratch.out_w(), compact_meta) ## i64
  stats[15] = stats[15] + compact_meta[0]
  stats[16] = stats[16] + compact_meta[1]
  full_exact = 0 ## i64
  if endpoint_rank > 0
    loaded = ffw_init_terms_cap(kernel.endpoint(), scratch.out_u(), scratch.out_v(), scratch.out_w(), endpoint_rank, n, kernel.capacity(), 930001 + stats[6] * 17 + operation * 101 + factor * 1009, 0, 1, 1, 1) ## i64
    stats[30] = stats[30] + 1
    if loaded == endpoint_rank && ffw_verify_current_exact(kernel.endpoint(), n) == 1
      full_exact = 1
  if full_exact == 0
    stats[8] = stats[8] + 1
    << "FACTOR_MAP_GATE_FAIL tensor=" + label + " factor=" + factor.to_s() + " operation=" + operation.to_s() + " source=" + source.to_s() + " target=" + target.to_s() + " weight=" + weight.to_s() + " endpoint_rank=" + endpoint_rank.to_s()
  result = 0 ## i64
  if full_exact == 1
    distance = ffpan_term_set_distance_unique(us, vs, ws, rank, scratch.out_u(), scratch.out_v(), scratch.out_w(), endpoint_rank) ## i64
    if distance == 0
      stats[20] = stats[20] + 1
    if distance > 0
      stats[7] = stats[7] + 1
      density = ffmfnb_density(scratch.out_u(), scratch.out_v(), scratch.out_w(), endpoint_rank) ## i64
      if endpoint_rank < rank
        stats[9] = stats[9] + 1
        result = 2
      if endpoint_rank == rank
        stats[31] = stats[31] + 1
        if density < source_density
          stats[10] = stats[10] + 1
      if distance > stats[13]
        stats[13] = distance
      better = 0 ## i64
      if endpoint_rank < stats[11]
        better = 1
      if endpoint_rank == stats[11] && density < stats[12]
        better = 1
      if endpoint_rank == stats[11] && density == stats[12] && distance > stats[22]
        better = 1
      if better == 1
        stats[11] = endpoint_rank
        stats[12] = density
        stats[21] = weight
        stats[22] = distance
        stats[23] = factor
        stats[24] = operation
        stats[25] = source
        stats[26] = target
        z = ffmfnb_copy(scratch.out_u(), scratch.out_v(), scratch.out_w(), scratch.best_u(), scratch.best_v(), scratch.best_w(), endpoint_rank)
      if endpoint_rank < rank || (endpoint_rank == rank && density < source_density)
        << "FACTOR_MAP_IMPROVEMENT tensor=" + label + " factor=" + factor.to_s() + " operation=" + operation.to_s() + " source=" + source.to_s() + " target=" + target.to_s() + " weight=" + weight.to_s() + " endpoint_rank=" + endpoint_rank.to_s() + " density=" + density.to_s() + " source_distance=" + distance.to_s() + " zeros=" + compact_meta[0].to_s() + " duplicates=" + compact_meta[1].to_s()
      if result == 0
        result = 1
  stats[18] = stats[18] + ccall("__w_clock_ms") - started
  result

# Audit one complete kernel.  For `expand_source=1`, the representative delete
# kernel is reused for delete plus every shear/fold target.
-> ffmfnb_audit_kernel(label, us, vs, ws, rank, n, factor, representative_operation, source, representative_target, expand_source, scratch, stats, histogram, source_density, candidate_cap) (String i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 FFMFNBenchScratch i64[] i64[] i64 i64) i64
  kernel = scratch.kernel()
  words = ffpa_tensor_words(n) ## i64
  built = ffmfn_build_deltas(us, vs, ws, rank, n, factor, representative_operation, source, representative_target, kernel.transformed_u(), kernel.transformed_v(), kernel.transformed_w(), kernel.deltas()) ## i64
  stats[0] = stats[0] + 1
  if built != words
    stats[8] = stats[8] + 1
    return 0 - 1
  nullspace_meta = i64[4]
  started = ccall("__w_clock_ms") ## i64
  nullity = ffpan_nullspace_into(kernel.deltas(), rank, words, kernel.dependencies(), kernel.basis_rows(), kernel.basis_coefficients(), kernel.pivot_owners(), kernel.work(), kernel.work_coefficients(), nullspace_meta) ## i64
  stats[17] = stats[17] + ccall("__w_clock_ms") - started
  if nullity < 0
    stats[8] = stats[8] + 1
    return 0 - 1
  stats[1] = stats[1] + nullity
  if nullity > stats[27]
    stats[27] = nullity
  if nullity < stats[28]
    stats[28] = nullity
  histogram[nullity] = histogram[nullity] + 1
  ids = kernel.ids()
  dependency = 0 ## i64
  while dependency < nullity
    weight = ffpan_dependency_weight(kernel.dependencies(), dependency, rank) ## i64
    stats[32] = stats[32] + weight
    made = ffpan_dependency_ids(kernel.dependencies(), dependency, rank, ids) ## i64
    selected_nonstable = 0 ## i64
    i = 0 ## i64
    while i < made
      if ffpan_row_zero(kernel.deltas(), ids[i] * words, words) == 0
        selected_nonstable += 1
      i += 1
    if selected_nonstable == 0
      stats[2] = stats[2] + 1
    if selected_nonstable > 0
      if ffpa_relation_exact(kernel.deltas(), ids, made, words) != 1
        stats[29] = stats[29] + 1
        stats[8] = stats[8] + 1
      else
        stats[3] = stats[3] + 1
        if weight < stats[14]
          stats[14] = weight
        if expand_source == 0
          z = ffmfnb_admit(label, us, vs, ws, rank, n, factor, representative_operation, source, representative_target, ids, made, weight, scratch, stats, source_density, candidate_cap) ## i64
        if expand_source != 0
          z = ffmfnb_admit(label, us, vs, ws, rank, n, factor, 2, source, 0, ids, made, weight, scratch, stats, source_density, candidate_cap)
          dimension = n * n ## i64
          target = 0 ## i64
          while target < dimension
            if target != source
              z = ffmfnb_admit(label, us, vs, ws, rank, n, factor, 1, source, target, ids, made, weight, scratch, stats, source_density, candidate_cap)
              z = ffmfnb_admit(label, us, vs, ws, rank, n, factor, 3, source, target, ids, made, weight, scratch, stats, source_density, candidate_cap)
            target += 1
    dependency += 1
  nullity

-> ffmfnb_histogram(histogram) (i64[])
  text = "" ## String
  i = 0 ## i64
  while i < histogram.size()
    if histogram[i] > 0
      if text.size() > 0
        text = text + ","
      text = text + i.to_s() + ":" + histogram[i].to_s()
    i += 1
  text

-> ffmfnb_summary(label, family, rank, source_density, stats, histogram) (String String i64 i64 i64[] i64[]) i64
  min_weight = stats[14] ## i64
  if min_weight > rank
    min_weight = 0 - 1
  min_nullity = stats[28] ## i64
  if min_nullity > rank
    min_nullity = 0 - 1
  << "FACTOR_MAP_SUMMARY tensor=" + label + " family=" + family + " rank=" + rank.to_s() + " density=" + source_density.to_s() + " kernels=" + stats[0].to_s() + " nullity_min=" + min_nullity.to_s() + " nullity_max=" + stats[27].to_s() + " nullity_hist=" + ffmfnb_histogram(histogram) + " fixed_bases=" + stats[2].to_s() + " nontrivial_bases=" + stats[3].to_s() + " maps=" + stats[4].to_s() + " set_noops=" + stats[5].to_s() + " candidates=" + stats[6].to_s() + " skipped=" + stats[19].to_s() + " full_exact_changed=" + stats[7].to_s() + " source_noops=" + stats[20].to_s() + " failures=" + stats[8].to_s() + " rank_drops=" + stats[9].to_s() + " density_wins=" + stats[10].to_s() + " rank_neutral=" + stats[31].to_s() + " best_rank=" + stats[11].to_s() + " best_density=" + stats[12].to_s() + " best_distance=" + stats[22].to_s() + " best_weight=" + stats[21].to_s() + " best_map=" + stats[23].to_s() + ":" + stats[24].to_s() + ":" + stats[25].to_s() + ">" + stats[26].to_s() + " max_distance=" + stats[13].to_s() + " min_weight=" + min_weight.to_s() + " zeros=" + stats[15].to_s() + " duplicates=" + stats[16].to_s() + " elimination_ms=" + stats[17].to_s() + " admission_ms=" + stats[18].to_s()
  1

-> ffmfnb_dump_best(prefix, label, family, rank, n, capacity, scratch, stats) (String String String i64 i64 i64 FFMFNBenchScratch i64[]) i64
  if prefix == "" || stats[7] < 1
    return 0
  best_rank = stats[11] ## i64
  state = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(state, scratch.best_u(), scratch.best_v(), scratch.best_w(), best_rank, n, capacity, 950001 + n, 0, 1, 1, 1) ## i64
  if loaded != best_rank || ffw_verify_best_exact(state, n) != 1
    return 0 - 1
  path = prefix + "_" + label + "_" + family + "_r" + best_rank.to_s() + "_d" + stats[12].to_s() + ".txt"
  dumped = ffw_dump_best(state, path) ## i64
  << "FACTOR_MAP_BEST path=" + path + " rank=" + best_rank.to_s() + " density=" + stats[12].to_s() + " distance=" + stats[22].to_s() + " weight=" + stats[21].to_s() + " map=" + stats[23].to_s() + ":" + stats[24].to_s() + ":" + stats[25].to_s() + ">" + stats[26].to_s() + " exact=" + (dumped == best_rank).to_s()
  dumped

-> ffmfnb_run(label, path, n, family, kernel_cap, candidate_cap, output_prefix) (String String i64 i64 i64 i64 String) i64
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(state, path, n, capacity, 920001 + n, 0, 1, 1, 1) ## i64
  if rank < 2 || ffw_verify_best_exact(state, n) != 1
    << "FACTOR_MAP_ERROR tensor=" + label + " error=load"
    return 0 - 1
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if ffw_export_best(state, us, vs, ws) != rank
    return 0 - 1
  source_density = ffmfnb_density(us, vs, ws, rank) ## i64
  scratch = FFMFNBenchScratch.new(rank, n, capacity)
  stats = i64[33]
  histogram = i64[rank + 1]
  dimension = n * n ## i64
  decoded = i64[3]

  if family < 0 || family == 0
    z = ffmfnb_reset(stats, histogram, rank, source_density) ## i64
    total = 3 * dimension ## i64
    attempts = total ## i64
    if kernel_cap > 0 && kernel_cap < attempts
      attempts = kernel_cap
    step = 0 ## i64
    while step < attempts
      flat = step * total / attempts ## i64
      if ffmfn_decode(dimension, 2, flat, decoded) != 1
        return 0 - 1
      z = ffmfnb_audit_kernel(label, us, vs, ws, rank, n, decoded[0], 2, decoded[1], 0, 1, scratch, stats, histogram, source_density, candidate_cap)
      step += 1
    z = ffmfnb_summary(label, "source", rank, source_density, stats, histogram)
    z = ffmfnb_dump_best(output_prefix, label, "source", rank, n, capacity, scratch, stats)

  if family < 0 || family == 1
    z = ffmfnb_reset(stats, histogram, rank, source_density)
    total = ffmfn_family_operations(dimension, 0)
    attempts = total
    if kernel_cap > 0 && kernel_cap < attempts
      attempts = kernel_cap
    step = 0
    while step < attempts
      flat = step * total / attempts
      if ffmfn_decode(dimension, 0, flat, decoded) != 1
        return 0 - 1
      z = ffmfnb_audit_kernel(label, us, vs, ws, rank, n, decoded[0], 0, decoded[1], decoded[2], 0, scratch, stats, histogram, source_density, candidate_cap)
      step += 1
    z = ffmfnb_summary(label, "swap", rank, source_density, stats, histogram)
    z = ffmfnb_dump_best(output_prefix, label, "swap", rank, n, capacity, scratch, stats)
  1

args = argv()
only_n = 0 ## i64
family = 0 - 1 ## i64
kernel_cap = 0 ## i64
candidate_cap = 2000 ## i64
output_prefix = "" ## String
if args.size() > 0
  only_n = args[0].to_i()
if args.size() > 1
  family = args[1].to_i()
if args.size() > 2
  kernel_cap = args[2].to_i()
if args.size() > 3
  candidate_cap = args[3].to_i()
if args.size() > 4
  output_prefix = args[4]
if only_n != 0 && (only_n < 4 || only_n > 7)
  << "invalid only_n"
  exit(2)
if family < 0 - 1 || family > 1 || kernel_cap < 0 || candidate_cap < 0
  << "invalid bounds"
  exit(2)

if only_n == 0 || only_n == 4
  z = ffmfnb_run("4x4-d450", "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt", 4, family, kernel_cap, candidate_cap, output_prefix) ## i64
if only_n == 0 || only_n == 5
  z = ffmfnb_run("5x5-d968", "benchmarks/matmul/metaflip/matmul_5x5_rank93_d968_global_isotropy_gf2.txt", 5, family, kernel_cap, candidate_cap, output_prefix)
if only_n == 0 || only_n == 6
  z = ffmfnb_run("6x6-d1860", "benchmarks/matmul/metaflip/matmul_6x6_rank153_d1860_global_isotropy_gf2.txt", 6, family, kernel_cap, candidate_cap, output_prefix)
if only_n == 0 || only_n == 7
  z = ffmfnb_run("7x7-d3098", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt", 7, family, kernel_cap, candidate_cap, output_prefix)

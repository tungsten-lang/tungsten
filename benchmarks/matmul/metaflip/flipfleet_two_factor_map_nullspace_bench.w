# Bounded real-frontier audit of exact selected-subset replacements under two
# simultaneous raw factor maps.  Every kernel row is the complete n^6-bit
# old-XOR-new tensor, including the cross term from changing both factors.
#
# Coordinate plans are support-guided.  For each factor pair and map-family
# pair we sample both high- and low-support source/target coordinates.  Delete
# maps prefer singleton support, folds prefer exact two-bit support, and
# swap/shear targets prefer coordinates with strong toggling interaction.
# Every nontrivial basis endpoint (plus all basis combinations when the
# nontrivial nullity is small) is zero-omitted, parity-compacted, and rebuilt
# behind a complete n^6 exactness gate.
#
# Usage:
#   flipfleet_two_factor_map_nullspace_bench \
#       [only_n=0] [variants=8] [combo_limit=10] \
#       [candidate_cap=20000] [output_prefix] [custom_scheme]

use flipfleet_two_factor_map_nullspace

+ FFTFNBenchScratch
  -> new(rank, n, capacity)
    @kernel = FFPANWorkspace.new(rank, n, capacity)
    @out_u = i64[capacity]
    @out_v = i64[capacity]
    @out_w = i64[capacity]
    @best_u = i64[capacity]
    @best_v = i64[capacity]
    @best_w = i64[capacity]
    @nontrivial = i64[rank]
    @aggregate = i64[ffpan_coeff_words(rank)]

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
  -> nontrivial()
    @nontrivial
  -> aggregate()
    @aggregate

-> fftfnb_density(us, vs, ws, rank) (i64[] i64[] i64[] i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < rank
    density += ffw_popcount(us[i]) + ffw_popcount(vs[i]) + ffw_popcount(ws[i])
    i += 1
  density

-> fftfnb_copy(source_u, source_v, source_w, target_u, target_v, target_w, count) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    target_u[i] = source_u[i]
    target_v[i] = source_v[i]
    target_w[i] = source_w[i]
    i += 1
  count

-> fftfnb_axis_value(us, vs, ws, position, axis) (i64[] i64[] i64[] i64 i64) i64
  if axis == 0
    return us[position]
  if axis == 1
    return vs[position]
  ws[position]

# Score a source coordinate.  Singular maps receive a strong preference for
# coordinates which can actually erase a factor: singleton masks for delete,
# and membership in exact two-bit masks for fold.
-> fftfnb_source_score(us, vs, ws, rank, axis, operation, coordinate) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  frequency = 0 ## i64
  singleton = 0 ## i64
  doubleton = 0 ## i64
  bit = 1 << coordinate ## i64
  i = 0 ## i64
  while i < rank
    value = fftfnb_axis_value(us, vs, ws, i, axis) ## i64
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

# Score a target conditioned on its source.  A fold prioritizes exact
# source+target masks because those map to zero.  Swaps prioritize masks whose
# two bits differ; shears prioritize a balanced mixture of source-only and
# source+target occurrences, which exercises both sides of the cross term.
-> fftfnb_target_score(us, vs, ws, rank, axis, operation, source, target) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  source_bit = 1 << source ## i64
  target_bit = 1 << target ## i64
  source_only = 0 ## i64
  both = 0 ## i64
  different = 0 ## i64
  exact_pair = 0 ## i64
  target_frequency = 0 ## i64
  i = 0 ## i64
  while i < rank
    value = fftfnb_axis_value(us, vs, ws, i, axis) ## i64
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

# `variant` alternates high/low score and walks the first four order
# statistics, so a campaign includes dense and rare support rather than only
# repeating the most frequent coordinate.
-> fftfnb_pick_source(us, vs, ws, rank, width, axis, operation, variant) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
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
        score = fftfnb_source_score(us, vs, ws, rank, axis, operation, coordinate) ## i64
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

-> fftfnb_pick_target(us, vs, ws, rank, width, axis, operation, source, variant) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) i64
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
        score = fftfnb_target_score(us, vs, ws, rank, axis, operation, source, coordinate) ## i64
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

-> fftfnb_axis_pair(index, out) (i64 i64[]) i64
  if out.size() < 2 || index < 0 || index > 2
    return 0
  if index == 0
    out[0] = 0
    out[1] = 1
  if index == 1
    out[0] = 0
    out[1] = 2
  if index == 2
    out[0] = 1
    out[1] = 2
  1

# shear/delete/fold combinations are the primary projection audit.  Raw swap
# combinations remain in the bounded mix because their paired cross term was
# not present in the exhaustive one-factor swap certificate.
-> fftfnb_operation_pair(index, out) (i64 i64[]) i64
  if out.size() < 2 || index < 0 || index >= 16
    return 0
  if index == 0
    out[0] = 1
    out[1] = 1
  if index == 1
    out[0] = 2
    out[1] = 2
  if index == 2
    out[0] = 2
    out[1] = 1
  if index == 3
    out[0] = 1
    out[1] = 2
  if index == 4
    out[0] = 3
    out[1] = 3
  if index == 5
    out[0] = 3
    out[1] = 1
  if index == 6
    out[0] = 1
    out[1] = 3
  if index == 7
    out[0] = 2
    out[1] = 3
  if index == 8
    out[0] = 3
    out[1] = 2
  if index == 9
    out[0] = 0
    out[1] = 0
  if index == 10
    out[0] = 0
    out[1] = 1
  if index == 11
    out[0] = 1
    out[1] = 0
  if index == 12
    out[0] = 0
    out[1] = 2
  if index == 13
    out[0] = 2
    out[1] = 0
  if index == 14
    out[0] = 0
    out[1] = 3
  if index == 15
    out[0] = 3
    out[1] = 0
  1

-> fftfnb_build_plan(us, vs, ws, rank, width, pair_index, operation_index, variant, plan) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[]) i64
  axes = i64[2]
  operations = i64[2]
  if plan.size() < 8 || fftfnb_axis_pair(pair_index, axes) != 1 || fftfnb_operation_pair(operation_index, operations) != 1
    return 0
  variant_a = variant + operation_index ## i64
  variant_b = variant + pair_index + operation_index + 1 ## i64
  source_a = fftfnb_pick_source(us, vs, ws, rank, width, axes[0], operations[0], variant_a) ## i64
  source_b = fftfnb_pick_source(us, vs, ws, rank, width, axes[1], operations[1], variant_b) ## i64
  target_a = fftfnb_pick_target(us, vs, ws, rank, width, axes[0], operations[0], source_a, variant_a + 2) ## i64
  target_b = fftfnb_pick_target(us, vs, ws, rank, width, axes[1], operations[1], source_b, variant_b + 2) ## i64
  plan[0] = axes[0]
  plan[1] = operations[0]
  plan[2] = source_a
  plan[3] = target_a
  plan[4] = axes[1]
  plan[5] = operations[1]
  plan[6] = source_b
  plan[7] = target_b
  fftfn_valid_map(width, plan[1], plan[2], plan[3]) * fftfn_valid_map(width, plan[5], plan[6], plan[7])

# stats: kernels, nullity sum, stable bases, nontrivial bases, candidate
# relations, set-noops, full gates, exact changed, failures, rank drops,
# density wins, best rank, best density, max distance, min weight, zeros,
# duplicate pairs, elimination ms, admission ms, skipped by cap, rank-neutral,
# max nullity, min nullity, combination vectors, best distance, best weight,
# best plan[8], relation failures, nontrivial kernels, combination kernels.
-> fftfnb_reset(stats, histogram, rank, density) (i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < stats.size()
    stats[i] = 0
    i += 1
  i = 0
  while i < histogram.size()
    histogram[i] = 0
    i += 1
  stats[11] = rank
  stats[12] = density
  stats[14] = rank + 1
  stats[22] = rank + 1
  stats[25] = rank + 1
  1

-> fftfnb_admit(label, us, vs, ws, rank, n, plan, ids, made, weight, scratch, stats, source_density, candidate_cap) (String i64[] i64[] i64[] i64 i64 i64[] i64[] i64 i64 FFTFNBenchScratch i64[] i64 i64) i64
  if candidate_cap > 0 && stats[4] >= candidate_cap
    stats[19] = stats[19] + 1
    return 0
  stats[4] = stats[4] + 1
  kernel = scratch.kernel()
  if ffpa_selected_image_same_set(us, vs, ws, kernel.transformed_u(), kernel.transformed_v(), kernel.transformed_w(), ids, made) == 1
    stats[5] = stats[5] + 1
    return 0
  started = ccall("__w_clock_ms") ## i64
  materialize_meta = i64[3]
  endpoint_rank = fftfn_materialize(us, vs, ws, rank, kernel.transformed_u(), kernel.transformed_v(), kernel.transformed_w(), ids, made, kernel.raw_u(), kernel.raw_v(), kernel.raw_w(), scratch.out_u(), scratch.out_v(), scratch.out_w(), materialize_meta) ## i64
  stats[15] = stats[15] + materialize_meta[0]
  stats[16] = stats[16] + materialize_meta[1]
  exact = 0 ## i64
  if endpoint_rank > 0
    loaded = ffw_init_terms_cap(kernel.endpoint(), scratch.out_u(), scratch.out_v(), scratch.out_w(), endpoint_rank, n, kernel.capacity(), 940001 + stats[4] * 17 + plan[0] * 101 + plan[4] * 1009, 0, 1, 1, 1) ## i64
    stats[6] = stats[6] + 1
    if loaded == endpoint_rank && ffw_verify_current_exact(kernel.endpoint(), n) == 1
      exact = 1
  if exact == 0
    stats[8] = stats[8] + 1
    << "TWO_FACTOR_GATE_FAIL tensor=" + label + " rank=" + endpoint_rank.to_s() + " weight=" + weight.to_s()
    stats[18] = stats[18] + ccall("__w_clock_ms") - started
    return 0 - 1
  distance = ffpan_term_set_distance_unique(us, vs, ws, rank, scratch.out_u(), scratch.out_v(), scratch.out_w(), endpoint_rank) ## i64
  if distance == 0
    stats[5] = stats[5] + 1
    stats[18] = stats[18] + ccall("__w_clock_ms") - started
    return 0
  stats[7] = stats[7] + 1
  density = fftfnb_density(scratch.out_u(), scratch.out_v(), scratch.out_w(), endpoint_rank) ## i64
  if endpoint_rank < rank
    stats[9] = stats[9] + 1
  if endpoint_rank == rank
    stats[20] = stats[20] + 1
    if density < source_density
      stats[10] = stats[10] + 1
  if distance > stats[13]
    stats[13] = distance
  better = endpoint_rank < stats[11] ## bool
  if endpoint_rank == stats[11] && density < stats[12]
    better = true
  if endpoint_rank == stats[11] && density == stats[12] && distance > stats[24]
    better = true
  if better
    stats[11] = endpoint_rank
    stats[12] = density
    stats[24] = distance
    stats[25] = weight
    i = 0 ## i64
    while i < 8
      stats[26 + i] = plan[i]
      i += 1
    z = fftfnb_copy(scratch.out_u(), scratch.out_v(), scratch.out_w(), scratch.best_u(), scratch.best_v(), scratch.best_w(), endpoint_rank) ## i64
  if endpoint_rank < rank || (endpoint_rank == rank && density < source_density)
    << "TWO_FACTOR_IMPROVEMENT tensor=" + label + " endpoint_rank=" + endpoint_rank.to_s() + " density=" + density.to_s() + " distance=" + distance.to_s() + " weight=" + weight.to_s() + " zeros=" + materialize_meta[0].to_s() + " duplicates=" + materialize_meta[1].to_s()
  stats[18] = stats[18] + ccall("__w_clock_ms") - started
  1

-> fftfnb_audit_plan(label, us, vs, ws, rank, n, plan, scratch, stats, histogram, source_density, combo_limit, candidate_cap) (String i64[] i64[] i64[] i64 i64 i64[] FFTFNBenchScratch i64[] i64[] i64 i64 i64) i64
  kernel = scratch.kernel()
  words = ffpa_tensor_words(n) ## i64
  built = fftfn_build_deltas(us, vs, ws, rank, n, plan, kernel.transformed_u(), kernel.transformed_v(), kernel.transformed_w(), kernel.deltas()) ## i64
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
  if nullity > stats[21]
    stats[21] = nullity
  if nullity < stats[22]
    stats[22] = nullity
  histogram[nullity] = histogram[nullity] + 1
  nontrivial_count = 0 ## i64
  dependency = 0 ## i64
  ids = kernel.ids()
  while dependency < nullity
    weight = ffpan_dependency_weight(kernel.dependencies(), dependency, rank) ## i64
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
      stats[3] = stats[3] + 1
      scratch.nontrivial()[nontrivial_count] = dependency
      nontrivial_count += 1
      if weight < stats[14]
        stats[14] = weight
      if ffpa_relation_exact(kernel.deltas(), ids, made, words) != 1
        stats[34] = stats[34] + 1
        stats[8] = stats[8] + 1
      else
        z = fftfnb_admit(label, us, vs, ws, rank, n, plan, ids, made, weight, scratch, stats, source_density, candidate_cap) ## i64
    dependency += 1
  if nontrivial_count > 0
    stats[35] = stats[35] + 1

  # The nullspace rows are a basis.  Exhaust their XOR closure only when its
  # dimension is explicitly bounded; otherwise the individual basis vectors
  # still provide a deterministic sampled certificate.
  if nontrivial_count > 1 && nontrivial_count <= combo_limit && nontrivial_count < 63
    stats[36] = stats[36] + 1
    coefficient_words = ffpan_coeff_words(rank) ## i64
    aggregate = scratch.aggregate()
    z = ffpan_clear(aggregate, coefficient_words) ## i64
    previous_gray = 0 ## i64
    mask = 1 ## i64
    limit = 1 << nontrivial_count ## i64
    while mask < limit
      gray = mask ^ (mask >> 1) ## i64
      changed = gray ^ previous_gray ## i64
      changed_index = 0 ## i64
      while ((changed >> changed_index) & 1) == 0
        changed_index += 1
      dependency_index = scratch.nontrivial()[changed_index] ## i64
      z = ffpan_xor_into(aggregate, 0, kernel.dependencies(), dependency_index * coefficient_words, coefficient_words)
      previous_gray = gray
      if ffw_popcount(gray) > 1
        stats[23] = stats[23] + 1
        made = ffpan_dependency_ids(aggregate, 0, rank, ids)
        weight = made
        if ffpa_relation_exact(kernel.deltas(), ids, made, words) != 1
          stats[34] = stats[34] + 1
          stats[8] = stats[8] + 1
        else
          z = fftfnb_admit(label, us, vs, ws, rank, n, plan, ids, made, weight, scratch, stats, source_density, candidate_cap)
      mask += 1
  nullity

-> fftfnb_histogram(histogram) (i64[])
  text = "" ## String
  i = 0 ## i64
  while i < histogram.size()
    if histogram[i] > 0
      if text.size() > 0
        text = text + ","
      text = text + i.to_s() + ":" + histogram[i].to_s()
    i += 1
  text

-> fftfnb_summary(label, rank, source_density, stats, histogram) (String i64 i64 i64[] i64[]) i64
  min_weight = stats[14] ## i64
  if min_weight > rank
    min_weight = 0 - 1
  min_nullity = stats[22] ## i64
  if min_nullity > rank
    min_nullity = 0 - 1
  << "TWO_FACTOR_SUMMARY tensor=" + label + " rank=" + rank.to_s() + " density=" + source_density.to_s() + " kernels=" + stats[0].to_s() + " nullity_min=" + min_nullity.to_s() + " nullity_max=" + stats[21].to_s() + " nullity_hist=" + fftfnb_histogram(histogram) + " stable_bases=" + stats[2].to_s() + " nontrivial_bases=" + stats[3].to_s() + " nontrivial_kernels=" + stats[35].to_s() + " combo_kernels=" + stats[36].to_s() + " combo_vectors=" + stats[23].to_s() + " candidates=" + stats[4].to_s() + " skipped=" + stats[19].to_s() + " set_noops=" + stats[5].to_s() + " full_exact_changed=" + stats[7].to_s() + " failures=" + stats[8].to_s() + " relation_failures=" + stats[34].to_s() + " rank_drops=" + stats[9].to_s() + " density_wins=" + stats[10].to_s() + " rank_neutral=" + stats[20].to_s() + " best_rank=" + stats[11].to_s() + " best_density=" + stats[12].to_s() + " best_distance=" + stats[24].to_s() + " best_weight=" + stats[25].to_s() + " max_distance=" + stats[13].to_s() + " min_weight=" + min_weight.to_s() + " zeros=" + stats[15].to_s() + " duplicates=" + stats[16].to_s() + " elimination_ms=" + stats[17].to_s() + " admission_ms=" + stats[18].to_s()
  1

-> fftfnb_dump_best(prefix, label, rank, n, capacity, scratch, stats) (String String i64 i64 i64 FFTFNBenchScratch i64[]) i64
  if prefix == "" || stats[7] < 1
    return 0
  best_rank = stats[11] ## i64
  state = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(state, scratch.best_u(), scratch.best_v(), scratch.best_w(), best_rank, n, capacity, 960001 + n, 0, 1, 1, 1) ## i64
  if loaded != best_rank || ffw_verify_best_exact(state, n) != 1
    return 0 - 1
  path = prefix + "_" + label + "_r" + best_rank.to_s() + "_d" + stats[12].to_s() + ".txt" ## String
  dumped = ffw_dump_best(state, path) ## i64
  << "TWO_FACTOR_BEST path=" + path + " rank=" + best_rank.to_s() + " density=" + stats[12].to_s() + " distance=" + stats[24].to_s() + " exact=" + (dumped == best_rank).to_s()
  dumped

-> fftfnb_run(label, path, n, variants, combo_limit, candidate_cap, output_prefix) (String String i64 i64 i64 i64 String) i64
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(state, path, n, capacity, 930001 + n, 0, 1, 1, 1) ## i64
  if rank < 2 || ffw_verify_best_exact(state, n) != 1
    << "TWO_FACTOR_ERROR tensor=" + label + " error=load"
    return 0 - 1
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if ffw_export_best(state, us, vs, ws) != rank
    return 0 - 1
  source_density = fftfnb_density(us, vs, ws, rank) ## i64
  scratch = FFTFNBenchScratch.new(rank, n, capacity)
  stats = i64[37]
  histogram = i64[rank + 1]
  z = fftfnb_reset(stats, histogram, rank, source_density) ## i64
  plan = i64[8]
  pair_index = 0 ## i64
  while pair_index < 3
    operation_index = 0 ## i64
    while operation_index < 16
      variant = 0 ## i64
      while variant < variants
        if fftfnb_build_plan(us, vs, ws, rank, n * n, pair_index, operation_index, variant, plan) != 1
          stats[8] = stats[8] + 1
        else
          z = fftfnb_audit_plan(label, us, vs, ws, rank, n, plan, scratch, stats, histogram, source_density, combo_limit, candidate_cap)
        variant += 1
      operation_index += 1
    pair_index += 1
  z = fftfnb_summary(label, rank, source_density, stats, histogram)
  fftfnb_dump_best(output_prefix, label, rank, n, capacity, scratch, stats)

args = argv()
only_n = 0 ## i64
variants = 8 ## i64
combo_limit = 10 ## i64
candidate_cap = 20000 ## i64
output_prefix = "" ## String
custom_scheme = "" ## String
if args.size() > 0
  only_n = args[0].to_i()
if args.size() > 1
  variants = args[1].to_i()
if args.size() > 2
  combo_limit = args[2].to_i()
if args.size() > 3
  candidate_cap = args[3].to_i()
if args.size() > 4
  output_prefix = args[4]
if args.size() > 5
  custom_scheme = args[5]
if only_n != 0 && (only_n < 4 || only_n > 7)
  << "invalid only_n"
  exit(2)
if variants < 1 || variants > 32 || combo_limit < 0 || combo_limit > 20 || candidate_cap < 0
  << "invalid bounds"
  exit(2)
if custom_scheme != ""
  if only_n < 4 || only_n > 7
    << "custom_scheme requires only_n=4..7"
    exit(2)
  z = fftfnb_run("custom-" + only_n.to_s() + "x" + only_n.to_s(), custom_scheme, only_n, variants, combo_limit, candidate_cap, output_prefix) ## i64
  exit(0)

if only_n == 0 || only_n == 4
  z = fftfnb_run("4x4-d450", "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt", 4, variants, combo_limit, candidate_cap, output_prefix) ## i64
if only_n == 0 || only_n == 5
  z = fftfnb_run("5x5-d968", "benchmarks/matmul/metaflip/matmul_5x5_rank93_d968_global_isotropy_gf2.txt", 5, variants, combo_limit, candidate_cap, output_prefix)
if only_n == 0 || only_n == 6
  z = fftfnb_run("6x6-d1860", "benchmarks/matmul/metaflip/matmul_6x6_rank153_d1860_global_isotropy_gf2.txt", 6, variants, combo_limit, candidate_cap, output_prefix)
if only_n == 0 || only_n == 7
  z = fftfnb_run("7x7-d3098", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt", 7, variants, combo_limit, candidate_cap, output_prefix)

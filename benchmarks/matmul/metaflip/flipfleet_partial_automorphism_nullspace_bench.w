# Complete real-frontier audit for arbitrary-cardinality partial tensor
# automorphisms.  Unlike the bounded 2/3/4-term enumerator, this benchmark
# builds every per-term n^6 delta and solves the entire binary kernel.  Kernel
# basis vectors are classified before admission:
#
#   fixed       only individually fixed terms were selected;
#   set-noop    nonfixed terms were selected, but their image is the same set;
#   global      every nonfixed term was selected (the whole isotropy image);
#   proper      a genuinely partial, non-set-stable exact relation.
#
# Every proper basis vector is materialized, parity compacted, rebuilt in a
# fresh worker, and passed through the exhaustive n^6 coefficient gate.  This
# program never mutates or publishes a frontier.
#
# Usage:
#   flipfleet_partial_automorphism_nullspace_bench [only_n=0] [word_samples=4]

use flipfleet_partial_automorphism_nullspace
use flipfleet_global_isotropy

+ FFPANBenchScratch
  -> new(capacity, rank, n)
    words = ffpa_tensor_words(n) ## i64
    coefficient_words = ffpan_coeff_words(rank) ## i64
    @transformed_u = i64[capacity]
    @transformed_v = i64[capacity]
    @transformed_w = i64[capacity]
    @deltas = i64[rank * words]
    @dependencies = i64[rank * coefficient_words]
    @basis_rows = i64[rank * words]
    @basis_coefficients = i64[rank * coefficient_words]
    @pivot_owners = i32[words * 64]
    @work = i64[words]
    @work_coefficients = i64[coefficient_words]
    @ids = i64[rank]
    @raw_u = i64[capacity]
    @raw_v = i64[capacity]
    @raw_w = i64[capacity]
    @out_u = i64[capacity]
    @out_v = i64[capacity]
    @out_w = i64[capacity]
    @endpoint = i64[ffw_state_size(capacity)]

  -> transformed_u()
    @transformed_u
  -> transformed_v()
    @transformed_v
  -> transformed_w()
    @transformed_w
  -> deltas()
    @deltas
  -> dependencies()
    @dependencies
  -> basis_rows()
    @basis_rows
  -> basis_coefficients()
    @basis_coefficients
  -> pivot_owners()
    @pivot_owners
  -> work()
    @work
  -> work_coefficients()
    @work_coefficients
  -> ids()
    @ids
  -> raw_u()
    @raw_u
  -> raw_v()
    @raw_v
  -> raw_w()
    @raw_w
  -> out_u()
    @out_u
  -> out_v()
    @out_v
  -> out_w()
    @out_w
  -> endpoint()
    @endpoint

-> ffpanb_row_zero(rows, offset, words) (i64[] i64 i64) i64
  zero = 1 ## i64
  word = 0 ## i64
  while word < words && zero == 1
    if rows[offset + word] != 0
      zero = 0
    word += 1
  zero

-> ffpanb_copy_terms(source_u, source_v, source_w, target_u, target_v, target_w, count) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    target_u[i] = source_u[i]
    target_v[i] = source_v[i]
    target_w[i] = source_w[i]
    i += 1
  count

# Toggle a multiset into a compact XOR set.  A transformed selected term is
# allowed to collide with an untouched term: that cancellation is exactly the
# rank-changing consequence this audit is looking for.
-> ffpanb_parity_compact(raw_u, raw_v, raw_w, raw_count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  count = 0 ## i64
  i = 0 ## i64
  while i < raw_count
    if raw_u[i] == 0 || raw_v[i] == 0 || raw_w[i] == 0
      return 0 - 1
    found = 0 - 1 ## i64
    j = 0 ## i64
    while j < count && found < 0
      if raw_u[i] == out_u[j] && raw_v[i] == out_v[j] && raw_w[i] == out_w[j]
        found = j
      j += 1
    if found >= 0
      count -= 1
      if found < count
        out_u[found] = out_u[count]
        out_v[found] = out_v[count]
        out_w[found] = out_w[count]
    if found < 0
      out_u[count] = raw_u[i]
      out_v[count] = raw_v[i]
      out_w[count] = raw_w[i]
      count += 1
    i += 1
  count

-> ffpanb_build_word_deltas(us, vs, ws, rank, n, operations, domains, sources, targets, length, transformed_u, transformed_v, transformed_w, deltas) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  words = ffpa_tensor_words(n) ## i64
  if ffpanb_copy_terms(us, vs, ws, transformed_u, transformed_v, transformed_w, rank) != rank
    return 0
  if ffgir_apply_word(transformed_u, transformed_v, transformed_w, rank, n, operations, domains, sources, targets, length, 0) != rank
    return 0
  i = 0 ## i64
  while i < rank
    z = ffpa_clear_row(deltas, i * words, words) ## i64
    z = ffpa_xor_outer(deltas, i * words, us[i], vs[i], ws[i], n)
    z = ffpa_xor_outer(deltas, i * words, transformed_u[i], transformed_v[i], transformed_w[i], n)
    i += 1
  words

# stats layout:
#  0 operations, 1 nullity sum, 2 min nullity, 3 max nullity,
#  4 stable-term sum, 5 max stable terms,
#  6 fixed bases, 7 set-noop bases, 8 global bases, 9 proper bases,
# 10 exact endpoints, 11 failures, 12 rank drops, 13 density improvements,
# 14 max distance, 15 min basis weight, 16 min proper weight,
# 17 best rank, 18 best density, 19 basis-weight sum, 20 proper-weight sum,
# 21 relation failures, 22 proper weight<=4, 23 proper weight>4,
# 24 elimination ms, 25 admission ms,
# 26 source-equivalent endpoints, 27 global-image-equivalent endpoints,
# 28 genuinely partial endpoints, 29 genuine weight<=4, 30 genuine weight>4,
# 31 minimum genuine weight, 32 explicit exact global vectors,
# 33 globally set-stable automorphisms.
-> ffpanb_stats_init(stats, rank, density) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < stats.size()
    stats[i] = 0
    i += 1
  stats[2] = rank + 1
  stats[15] = rank + 1
  stats[16] = rank + 1
  stats[31] = rank + 1
  stats[17] = rank
  stats[18] = density
  1

-> ffpanb_audit_kernel(label, family, operation_label, us, vs, ws, rank, n, scratch, capacity, source_density, stats, histogram) (String String String i64[] i64[] i64[] i64 i64 FFPANBenchScratch i64 i64 i64[] i64[]) i64
  transformed_u = scratch.transformed_u()
  transformed_v = scratch.transformed_v()
  transformed_w = scratch.transformed_w()
  deltas = scratch.deltas()
  dependencies = scratch.dependencies()
  basis_rows = scratch.basis_rows()
  basis_coefficients = scratch.basis_coefficients()
  pivot_owners = scratch.pivot_owners()
  work = scratch.work()
  work_coefficients = scratch.work_coefficients()
  ids = scratch.ids()
  raw_u = scratch.raw_u()
  raw_v = scratch.raw_v()
  raw_w = scratch.raw_w()
  out_u = scratch.out_u()
  out_v = scratch.out_v()
  out_w = scratch.out_w()
  endpoint = scratch.endpoint()
  words = ffpa_tensor_words(n) ## i64
  coefficient_words = ffpan_coeff_words(rank) ## i64
  meta = i64[4]
  started = ccall("__w_clock_ms") ## i64
  nullity = ffpan_nullspace_into(deltas, rank, words, dependencies, basis_rows, basis_coefficients, pivot_owners, work, work_coefficients, meta) ## i64
  stats[24] = stats[24] + ccall("__w_clock_ms") - started
  if nullity < 0 || meta[0] + nullity != rank
    << "PARTIAL_AUTOMORPHISM_KERNEL_ERROR tensor=" + label + " family=" + family + " op=" + operation_label + " error=nullspace"
    stats[11] = stats[11] + 1
    return 0 - 1

  stable_terms = 0 ## i64
  i = 0 ## i64
  while i < rank
    stable_terms += ffpanb_row_zero(deltas, i * words, words)
    i += 1
  nonstable_terms = rank - stable_terms ## i64

  stats[0] = stats[0] + 1
  stats[1] = stats[1] + nullity
  if nullity < stats[2]
    stats[2] = nullity
  if nullity > stats[3]
    stats[3] = nullity
  stats[4] = stats[4] + stable_terms
  if stable_terms > stats[5]
    stats[5] = stable_terms
  histogram[nullity] = histogram[nullity] + 1

  # Audit the inevitable all-term dependency explicitly rather than relying
  # on it to appear as one particular elimination basis vector.  When the
  # quotient kernel has dimension >1 it is commonly the XOR of two proper
  # basis vectors and therefore is absent from `basis_global` below.
  i = 0
  while i < rank
    ids[i] = i
    i += 1
  global_exact = ffpa_relation_exact(deltas, ids, rank, words) ## i64
  if global_exact == 1
    stats[32] = stats[32] + 1
    if ffpa_selected_image_same_set(us, vs, ws, transformed_u, transformed_v, transformed_w, ids, rank) == 1
      stats[33] = stats[33] + 1
  if global_exact != 1
    stats[11] = stats[11] + 1
    stats[21] = stats[21] + 1
    << "PARTIAL_AUTOMORPHISM_KERNEL_ERROR tensor=" + label + " family=" + family + " op=" + operation_label + " error=global-vector"

  dependency = 0 ## i64
  while dependency < nullity
    weight = ffpan_dependency_weight(dependencies, dependency, rank) ## i64
    made = ffpan_dependency_ids(dependencies, dependency, rank, ids) ## i64
    stats[19] = stats[19] + weight
    if weight < stats[15]
      stats[15] = weight
    exact_relation = ffpa_relation_exact(deltas, ids, made, words) ## i64
    if exact_relation != 1
      stats[11] = stats[11] + 1
      stats[21] = stats[21] + 1
      << "PARTIAL_AUTOMORPHISM_KERNEL_ERROR tensor=" + label + " family=" + family + " op=" + operation_label + " dependency=" + dependency.to_s() + " error=relation"
    if exact_relation == 1
      selected_nonstable = 0 ## i64
      selected = 0 ## i64
      while selected < made
        source = ids[selected] ## i64
        if ffpanb_row_zero(deltas, source * words, words) == 0
          selected_nonstable += 1
        selected += 1
      if selected_nonstable == 0
        stats[6] = stats[6] + 1
      if selected_nonstable > 0
        set_noop = ffpa_selected_image_same_set(us, vs, ws, transformed_u, transformed_v, transformed_w, ids, made) ## i64
        if set_noop == 1
          stats[7] = stats[7] + 1
        if set_noop == 0 && selected_nonstable == nonstable_terms
          stats[8] = stats[8] + 1
        if set_noop == 0 && selected_nonstable < nonstable_terms
          stats[9] = stats[9] + 1
          stats[20] = stats[20] + weight
          if weight < stats[16]
            stats[16] = weight
          if weight <= 4
            stats[22] = stats[22] + 1
          if weight > 4
            stats[23] = stats[23] + 1

          admission_started = ccall("__w_clock_ms") ## i64
          z = ffpanb_copy_terms(us, vs, ws, raw_u, raw_v, raw_w, rank) ## i64
          selected = 0
          while selected < made
            source = ids[selected]
            raw_u[source] = transformed_u[source]
            raw_v[source] = transformed_v[source]
            raw_w[source] = transformed_w[source]
            selected += 1
          endpoint_rank = ffpanb_parity_compact(raw_u, raw_v, raw_w, rank, out_u, out_v, out_w) ## i64
          full_exact = 0 ## i64
          endpoint_density = 0 - 1 ## i64
          distance = 0 - 1 ## i64
          global_distance = 0 - 1 ## i64
          quotient_class = "invalid" ## String
          if endpoint_rank > 0 && endpoint_rank <= capacity
            loaded = ffw_init_terms_cap(endpoint, out_u, out_v, out_w, endpoint_rank, n, capacity, 890071 + n * 1009 + stats[10] * 17 + stats[11], 0, 1, 1, 1) ## i64
            if loaded == endpoint_rank && ffw_verify_current_exact(endpoint, n) == 1
              full_exact = 1
              stats[10] = stats[10] + 1
              endpoint_density = ffgir_density(out_u, out_v, out_w, endpoint_rank)
              distance = ffgir_term_set_distance(us, vs, ws, rank, out_u, out_v, out_w, endpoint_rank)
              global_distance = ffgir_term_set_distance(transformed_u, transformed_v, transformed_w, rank, out_u, out_v, out_w, endpoint_rank)
              if distance == 0
                quotient_class = "source"
                stats[26] = stats[26] + 1
              if distance != 0 && global_distance == 0
                quotient_class = "global"
                stats[27] = stats[27] + 1
              if distance != 0 && global_distance != 0
                quotient_class = "partial"
                stats[28] = stats[28] + 1
                if weight <= 4
                  stats[29] = stats[29] + 1
                if weight > 4
                  stats[30] = stats[30] + 1
                if weight < stats[31]
                  stats[31] = weight
                if endpoint_rank < rank
                  stats[12] = stats[12] + 1
                if endpoint_rank == rank && endpoint_density < source_density
                  stats[13] = stats[13] + 1
                if distance > stats[14]
                  stats[14] = distance
                if endpoint_rank < stats[17]
                  stats[17] = endpoint_rank
                  stats[18] = endpoint_density
                if endpoint_rank == stats[17] && endpoint_density < stats[18]
                  stats[18] = endpoint_density
          if full_exact == 0
            stats[11] = stats[11] + 1
          stats[25] = stats[25] + ccall("__w_clock_ms") - admission_started
          << "PARTIAL_AUTOMORPHISM_PROPER tensor=" + label + " family=" + family + " op=" + operation_label + " nullity=" + nullity.to_s() + " stable=" + stable_terms.to_s() + " weight=" + weight.to_s() + " nonstable=" + selected_nonstable.to_s() + "/" + nonstable_terms.to_s() + " endpoint_rank=" + endpoint_rank.to_s() + " density_delta=" + (endpoint_density - source_density).to_s() + " source_distance=" + distance.to_s() + " global_distance=" + global_distance.to_s() + " quotient=" + quotient_class + " full_exact=" + full_exact.to_s()
    dependency += 1
  nullity

-> ffpanb_histogram(histogram) (i64[])
  text = "" ## String
  i = 0 ## i64
  while i < histogram.size()
    if histogram[i] > 0
      if text.size() > 0
        text = text + ","
      text = text + i.to_s() + ":" + histogram[i].to_s()
    i += 1
  text

-> ffpanb_summary(label, family, rank, density, stats, histogram) (String String i64 i64 i64[] i64[]) i64
  average_milli = 0 ## i64
  stable_milli = 0 ## i64
  if stats[0] > 0
    average_milli = stats[1] * 1000 / stats[0]
    stable_milli = stats[4] * 1000 / stats[0]
  min_basis = stats[15] ## i64
  min_proper = stats[16] ## i64
  min_genuine = stats[31] ## i64
  if min_basis > rank
    min_basis = 0 - 1
  if min_proper > rank
    min_proper = 0 - 1
  if min_genuine > rank
    min_genuine = 0 - 1
  << "PARTIAL_AUTOMORPHISM_SUMMARY tensor=" + label + " family=" + family + " rank=" + rank.to_s() + " density=" + density.to_s() + " operations=" + stats[0].to_s() + " nullity_min=" + stats[2].to_s() + " nullity_max=" + stats[3].to_s() + " nullity_avg_milli=" + average_milli.to_s() + " nullity_hist=" + ffpanb_histogram(histogram) + " stable_avg_milli=" + stable_milli.to_s() + " stable_max=" + stats[5].to_s() + " global_vectors=" + stats[32].to_s() + " global_set_stable=" + stats[33].to_s() + " basis_fixed=" + stats[6].to_s() + " basis_set_noop=" + stats[7].to_s() + " basis_global=" + stats[8].to_s() + " basis_proper=" + stats[9].to_s() + " min_basis_weight=" + min_basis.to_s() + " min_proper_weight=" + min_proper.to_s() + " apparent_le4=" + stats[22].to_s() + " apparent_gt4=" + stats[23].to_s() + " source_quotient=" + stats[26].to_s() + " global_quotient=" + stats[27].to_s() + " genuine_partial=" + stats[28].to_s() + " genuine_le4=" + stats[29].to_s() + " genuine_gt4=" + stats[30].to_s() + " min_genuine_weight=" + min_genuine.to_s() + " full_exact=" + stats[10].to_s() + " failures=" + stats[11].to_s() + " rank_drops=" + stats[12].to_s() + " density_better=" + stats[13].to_s() + " best_rank=" + stats[17].to_s() + " best_density=" + stats[18].to_s() + " max_distance=" + stats[14].to_s() + " elimination_ms=" + stats[24].to_s() + " admission_ms=" + stats[25].to_s()
  1

-> ffpanb_run(label, path, n, word_samples) (String String i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  state_size = ffw_state_size(capacity) ## i64
  source_state = i64[state_size]
  rank = ffw_load_scheme_cap(source_state, path, n, capacity, 880003 + n, 0, 1, 1, 1) ## i64
  if rank < 2 || ffw_verify_current_exact(source_state, n) != 1
    << "PARTIAL_AUTOMORPHISM_BENCH_ERROR tensor=" + label + " error=load"
    return 0 - 1
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if ffw_export_current(source_state, us, vs, ws) != rank
    return 0 - 1
  source_density = ffgir_density(us, vs, ws, rank) ## i64
  words = ffpa_tensor_words(n) ## i64
  coefficient_words = ffpan_coeff_words(rank) ## i64

  # All large scratch is allocated once per frontier and reused across every
  # elementary generator, direct 3-cycle, and composite word.
  scratch = FFPANBenchScratch.new(capacity, rank, n)

  elementary_stats = i64[34]
  elementary_histogram = i64[rank + 1]
  z = ffpanb_stats_init(elementary_stats, rank, source_density) ## i64
  operation = 0 ## i64
  while operation < 2
    domain = 0 ## i64
    while domain < 3
      source = 0 ## i64
      while source < n
        target = 0 ## i64
        while target < n
          admissible = 0 ## i64
          if operation == 0 && source < target
            admissible = 1
          if operation == 1 && source != target
            admissible = 1
          if admissible == 1
            built = ffpa_build_deltas_kind(us, vs, ws, rank, n, operation, domain, source, target, scratch.transformed_u(), scratch.transformed_v(), scratch.transformed_w(), scratch.deltas()) ## i64
            if built != words
              return 0 - 1
            family = "swap" ## String
            if operation == 1
              family = "shear"
            op_label = domain.to_s() + ":" + source.to_s() + ">" + target.to_s() ## String
            got = ffpanb_audit_kernel(label, family, op_label, us, vs, ws, rank, n, scratch, capacity, source_density, elementary_stats, elementary_histogram) ## i64
          target += 1
        source += 1
      domain += 1
    operation += 1
  z = ffpanb_summary(label, "elementary", rank, source_density, elementary_stats, elementary_histogram)

  # If the generators expose only fixed/set-stable/global dependencies, audit
  # automorphisms that cannot be represented by a single elementary move.
  if elementary_stats[28] == 0
    cycle_stats = i64[34]
    cycle_histogram = i64[rank + 1]
    z = ffpanb_stats_init(cycle_stats, rank, source_density)
    domain = 0
    while domain < 3
      first = 0 ## i64
      while first < n - 2
        second = first + 1 ## i64
        while second < n - 1
          third = second + 1 ## i64
          while third < n
            orientation = 0 ## i64
            while orientation < 2
              code = ffpa_cycle_code(n, first, second, third) ## i64
              built = ffpa_build_deltas_kind(us, vs, ws, rank, n, 2, domain, code, orientation, scratch.transformed_u(), scratch.transformed_v(), scratch.transformed_w(), scratch.deltas()) ## i64
              if built != words
                return 0 - 1
              op_label = domain.to_s() + ":" + first.to_s() + ">" + second.to_s() + ">" + third.to_s() + ":" + orientation.to_s()
              got = ffpanb_audit_kernel(label, "cycle3", op_label, us, vs, ws, rank, n, scratch, capacity, source_density, cycle_stats, cycle_histogram)
              orientation += 1
            third += 1
          second += 1
        first += 1
      domain += 1
    z = ffpanb_summary(label, "cycle3", rank, source_density, cycle_stats, cycle_histogram)

    composite_stats = i64[34]
    composite_histogram = i64[rank + 1]
    z = ffpanb_stats_init(composite_stats, rank, source_density)
    operations = i64[4]
    domains = i64[4]
    sources = i64[4]
    targets = i64[4]
    length = 2 ## i64
    while length <= 4
      sample = 0 ## i64
      while sample < word_samples
        seed = 104729 * n + 130363 * length + 32452843 * sample ## i64
        made = ffgir_make_word(n, seed, length, operations, domains, sources, targets) ## i64
        if made != length
          return 0 - 1
        built = ffpanb_build_word_deltas(us, vs, ws, rank, n, operations, domains, sources, targets, length, scratch.transformed_u(), scratch.transformed_v(), scratch.transformed_w(), scratch.deltas()) ## i64
        if built != words
          return 0 - 1
        op_label = "L" + length.to_s() + ":S" + sample.to_s() + ":" + seed.to_s()
        got = ffpanb_audit_kernel(label, "word", op_label, us, vs, ws, rank, n, scratch, capacity, source_density, composite_stats, composite_histogram)
        sample += 1
      length += 1
    z = ffpanb_summary(label, "word", rank, source_density, composite_stats, composite_histogram)
  1

args = argv()
only_n = 0 ## i64
word_samples = 4 ## i64
if args.size() > 0
  only_n = args[0].to_i()
if args.size() > 1
  word_samples = args[1].to_i()
if only_n != 0 && (only_n < 4 || only_n > 7)
  << "invalid only_n"
  exit(2)
if word_samples < 1 || word_samples > 64
  << "invalid word_samples"
  exit(2)

if only_n == 0 || only_n == 4
  z = ffpanb_run("4x4-d450", "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt", 4, word_samples) ## i64
if only_n == 0 || only_n == 5
  z = ffpanb_run("5x5-d968", "benchmarks/matmul/metaflip/matmul_5x5_rank93_d968_global_isotropy_gf2.txt", 5, word_samples)
if only_n == 0 || only_n == 6
  z = ffpanb_run("6x6-r153-d1860", "benchmarks/matmul/metaflip/matmul_6x6_rank153_d1860_global_isotropy_gf2.txt", 6, word_samples)
if only_n == 0 || only_n == 7
  z = ffpanb_run("7x7-r247-d3098", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt", 7, word_samples)

# Exhaustive odd-parent affine XOR closure of the checked-in frontier banks.
#
# Usage:
#   flipfleet_odd_parent_affine_splice_bench [N] [FIVE] [PUBLISH] [HULL] [ISOTROPY]
#
# N=0 audits 4x4..7x7. FIVE=1 also exhausts every distinct five-parent
# combination. HULL=1 Gray-enumerates the complete odd affine hull. PUBLISH=1
# writes canonical seeds only when a novel endpoint is within two terms of the
# tracked record. ISOTROPY=1 substitutes the bounded cancellation-oriented
# global-isotropy image bank (supported for 4x4, 6x6, and 7x7).

use flipfleet_odd_parent_affine_splice
use flipfleet_global_isotropy
use flipfleet_profiles

-> ffoasb_expect(label, condition) (String bool) i64
  if !condition
    << "ODD_PARENT_AFFINE_BENCH_FAIL " + label
    exit(1)
  1

+ FFOASBankAudit
  -> new(n, paths)
    record = ffp_record(n) ## i64
    # Every checked-in parent is at most record+1 terms after parsing.  The
    # complete odd hull can contain the disjoint union of the whole bank, so
    # size endpoint slots for that bound rather than the old five-parent cap.
    stride = paths.size() * (record + 2) ## i64
    @config = i64[6]
    @config[0] = n
    @config[1] = record
    @config[2] = stride
    @config[3] = 0
    @config[4] = paths.size()
    @config[5] = 0
    @bank_u = i64[paths.size() * stride]
    @bank_v = i64[paths.size() * stride]
    @bank_w = i64[paths.size() * stride]
    @ranks = i64[paths.size()]
    @densities = i64[paths.size()]
    @source_ids = i64[paths.size()]
    load_state = i64[ffw_state_size(stride)]
    canonical_state = i64[ffw_state_size(stride)]
    raw_u = i64[stride]
    raw_v = i64[stride]
    raw_w = i64[stride]
    canonical_u = i64[stride]
    canonical_v = i64[stride]
    canonical_w = i64[stride]
    source = 0 ## i64
    count = 0 ## i64
    while source < paths.size()
      loaded = ffw_load_scheme_cap(load_state, paths[source], n, stride, 940003 + n * 1009 + source * 17, 0, 1, 1, 1) ## i64
      if loaded < 1 || ffw_verify_current_exact(load_state, n) != 1
        << "ODD_PARENT_AFFINE_LOAD_FAIL path=" + paths[source]
        exit(1)
      exported = ffw_export_current(load_state, raw_u, raw_v, raw_w) ## i64
      canonical_rank = ffoas_canonicalize(raw_u, raw_v, raw_w, exported, canonical_u, canonical_v, canonical_w) ## i64
      canonical_loaded = ffw_init_terms_cap(canonical_state, canonical_u, canonical_v, canonical_w, canonical_rank, n, stride, 940101 + source, 0, 1, 1, 1) ## i64
      if canonical_loaded != canonical_rank || ffw_verify_current_exact(canonical_state, n) != 1
        << "ODD_PARENT_AFFINE_CANONICAL_FAIL path=" + paths[source]
        exit(1)
      duplicate = 0 ## i64
      prior = 0 ## i64
      while prior < count && duplicate == 0
        if ffoas_equal_slot(@bank_u, @bank_v, @bank_w, prior * stride, @ranks[prior], canonical_u, canonical_v, canonical_w, canonical_rank) == 1
          duplicate = 1
        prior += 1
      if duplicate == 0
        ffoas_copy_slot(canonical_u, canonical_v, canonical_w, 0, @bank_u, @bank_v, @bank_w, count * stride, canonical_rank)
        @ranks[count] = canonical_rank
        @densities[count] = ffgir_density(canonical_u, canonical_v, canonical_w, canonical_rank)
        @source_ids[count] = source
        count += 1
      else
        @config[5] = @config[5] + 1
      source += 1
    @config[3] = count
    triple_count = ffoas_choose(count, 3) ## i64
    five_count = ffoas_choose(count, 5) ## i64
    hull_count = 1 << (count - 1) ## i64
    archive_capacity = triple_count ## i64
    if five_count > archive_capacity
      archive_capacity = five_count
    if hull_count > archive_capacity
      archive_capacity = hull_count
    if archive_capacity < 1
      archive_capacity = 1
    @archive_u = i64[archive_capacity * stride]
    @archive_v = i64[archive_capacity * stride]
    @archive_w = i64[archive_capacity * stride]
    @archive_rank = i64[archive_capacity]
    @archive_fp_a = i64[archive_capacity]
    @archive_fp_b = i64[archive_capacity]
    @raw_u = i64[stride]
    @raw_v = i64[stride]
    @raw_w = i64[stride]
    @candidate_u = i64[stride]
    @candidate_v = i64[stride]
    @candidate_w = i64[stride]
    @gate = i64[ffw_state_size(stride)]
    @selection = i64[paths.size()]
    @best_u = i64[stride]
    @best_v = i64[stride]
    @best_w = i64[stride]
    @best_ids = i64[paths.size()]
    @best_config = i64[3]
    @novel_u = i64[stride]
    @novel_v = i64[stride]
    @novel_w = i64[stride]
    @novel_ids = i64[paths.size()]
    @novel_config = i64[4]

  -> bank_count()
    @config[3]
  -> input_count()
    @config[4]
  -> duplicate_parents()
    @config[5]
  -> source_id(slot)
    @source_ids[slot]
  -> best_parent(index)
    @best_ids[index]
  -> novel_parent(index)
    @novel_ids[index]
  -> best_parent_count()
    @best_config[2]
  -> novel_parent_count()
    @novel_config[3]

  # stats: combinations, full gates, failures, canonical unique/duplicate,
  # best rank/density/novelty, max novelty, max min/max-parent distance,
  # debt <=0/1/2/5, rank sum, materialize ms, gate+score ms,
  # best min/max-parent distance, best multiplicity, elapsed ms,
  # maximum-novelty record-or-better endpoint novelty/density/rank and its
  # min/max-parent distance.
  -> score_candidate(rank, parent_count, stats)
    stats[0] = stats[0] + 1
    if stats.size() > 30
      if parent_count == 1
        stats[26] = stats[26] + 1
      if parent_count == 3
        stats[27] = stats[27] + 1
      if parent_count == 5
        stats[28] = stats[28] + 1
      if parent_count >= 7
        stats[29] = stats[29] + 1
      if parent_count > stats[30]
        stats[30] = parent_count
    if rank < 1 || rank > @config[2]
      stats[2] = stats[2] + 1
      return 0
    gate_started = ccall("__w_clock_ms") ## i64
    loaded = ffw_init_terms_cap(@gate, @candidate_u, @candidate_v, @candidate_w, rank, @config[0], @config[2], 940201 + stats[0] * 17 + parent_count * 1009, 0, 1, 1, 1) ## i64
    if loaded != rank || ffw_verify_current_exact(@gate, @config[0]) != 1
      stats[2] = stats[2] + 1
      return 0
    stats[1] = stats[1] + 1
    density = ffgir_density(@candidate_u, @candidate_v, @candidate_w, rank) ## i64
    min_parent = 9223372036854775807 ## i64
    max_parent = 0 ## i64
    p = 0 ## i64
    while p < parent_count
      id = @selection[p] ## i64
      distance = ffoas_distance_slot(@bank_u, @bank_v, @bank_w, id * @config[2], @ranks[id], @candidate_u, @candidate_v, @candidate_w, rank) ## i64
      if distance < min_parent
        min_parent = distance
      if distance > max_parent
        max_parent = distance
      p += 1
    novelty = 9223372036854775807 ## i64
    bank = 0 ## i64
    while bank < @config[3]
      distance = ffoas_distance_slot(@bank_u, @bank_v, @bank_w, bank * @config[2], @ranks[bank], @candidate_u, @candidate_v, @candidate_w, rank)
      if distance < novelty
        novelty = distance
      bank += 1
    fingerprint = i64[2]
    ffoas_fingerprint(@candidate_u, @candidate_v, @candidate_w, rank, fingerprint)
    archive_count = stats[3] ## i64
    duplicate = 0 ## i64
    archive = 0 ## i64
    while archive < archive_count && duplicate == 0
      if @archive_rank[archive] == rank && @archive_fp_a[archive] == fingerprint[0] && @archive_fp_b[archive] == fingerprint[1]
        if ffoas_equal_slot(@archive_u, @archive_v, @archive_w, archive * @config[2], rank, @candidate_u, @candidate_v, @candidate_w, rank) == 1
          duplicate = 1
      archive += 1
    if duplicate == 1
      stats[4] = stats[4] + 1
    if duplicate == 0
      ffoas_copy_slot(@candidate_u, @candidate_v, @candidate_w, 0, @archive_u, @archive_v, @archive_w, archive_count * @config[2], rank)
      @archive_rank[archive_count] = rank
      @archive_fp_a[archive_count] = fingerprint[0]
      @archive_fp_b[archive_count] = fingerprint[1]
      stats[3] = stats[3] + 1
    if novelty > stats[8]
      stats[8] = novelty
    if min_parent > stats[9]
      stats[9] = min_parent
    if max_parent > stats[10]
      stats[10] = max_parent
    debt = rank - @config[1] ## i64
    if debt <= 0
      stats[11] = stats[11] + 1
    if debt <= 1
      stats[12] = stats[12] + 1
    if debt <= 2
      stats[13] = stats[13] + 1
    if debt <= 5
      stats[14] = stats[14] + 1
    stats[15] = stats[15] + rank
    if debt <= 0 && novelty > 0
      novel_better = 0 ## i64
      if rank < stats[23]
        novel_better = 1
      if rank == stats[23] && novelty > stats[21]
        novel_better = 1
      if rank == stats[23] && novelty == stats[21] && density < stats[22]
        novel_better = 1
      if novel_better == 1
        stats[21] = novelty
        stats[22] = density
        stats[23] = rank
        stats[24] = min_parent
        stats[25] = max_parent
        q = 0 ## i64
        while q < parent_count
          @novel_ids[q] = @selection[q]
          q += 1
        ffoas_copy_slot(@candidate_u, @candidate_v, @candidate_w, 0, @novel_u, @novel_v, @novel_w, 0, rank)
        @novel_config[0] = rank
        @novel_config[1] = density
        @novel_config[2] = novelty
        @novel_config[3] = parent_count
    better = 0 ## i64
    if novelty > 0
      if rank < stats[5]
        better = 1
      if rank == stats[5] && density < stats[6]
        better = 1
      if rank == stats[5] && density == stats[6] && novelty > stats[7]
        better = 1
    if better == 1
      stats[5] = rank
      stats[6] = density
      stats[7] = novelty
      stats[17] = min_parent
      stats[18] = max_parent
      q = 0 ## i64
      while q < parent_count
        @best_ids[q] = @selection[q]
        q += 1
      ffoas_copy_slot(@candidate_u, @candidate_v, @candidate_w, 0, @best_u, @best_v, @best_w, 0, rank)
      @best_config[0] = rank
      @best_config[1] = density
      @best_config[2] = parent_count
      stats[19] = 1
    else
      if rank == stats[5]
        stats[19] = stats[19] + 1
    stats[16] = stats[16] + ccall("__w_clock_ms") - gate_started
    1

  -> consider(parent_count, stats)
    rank = ffoas_materialize(@bank_u, @bank_v, @bank_w, @config[2], @ranks, @selection, parent_count, @raw_u, @raw_v, @raw_w, @candidate_u, @candidate_v, @candidate_w) ## i64
    score_candidate(rank, parent_count, stats)

  -> reset_stats(stats)
    i = 0 ## i64
    while i < stats.size()
      stats[i] = 0
      i += 1
    stats[5] = 9223372036854775807
    stats[6] = 9223372036854775807
    stats[22] = 9223372036854775807
    stats[23] = 9223372036854775807
    @best_config[0] = 0
    @best_config[1] = 0
    @best_config[2] = 0
    @novel_config[0] = 0
    @novel_config[1] = 0
    @novel_config[2] = 0
    @novel_config[3] = 0
    1

  -> finish_stats(stats, started)
    stats[20] = ccall("__w_clock_ms") - started
    if stats[0] == 0 || stats[5] == 9223372036854775807
      stats[5] = 0 - 1
      stats[6] = 0 - 1
    if stats[0] == 0 || stats[23] == 9223372036854775807
      stats[21] = 0
      stats[22] = 0 - 1
      stats[23] = 0 - 1
    if stats[0] > 0 && stats[11] == 0
      stats[21] = 0
      stats[22] = 0 - 1
      stats[23] = 0 - 1
    1

  -> run(parent_count, stats)
    reset_stats(stats)
    started = ccall("__w_clock_ms") ## i64
    count = @config[3] ## i64
    if parent_count == 3
      a = 0 ## i64
      while a < count - 2
        b = a + 1 ## i64
        while b < count - 1
          c = b + 1 ## i64
          while c < count
            @selection[0] = a
            @selection[1] = b
            @selection[2] = c
            consider(3, stats)
            c += 1
          b += 1
        a += 1
    if parent_count == 5
      a = 0
      while a < count - 4
        b = a + 1
        while b < count - 3
          c = b + 1
          while c < count - 2
            d = c + 1 ## i64
            while d < count - 1
              e = d + 1 ## i64
              while e < count
                @selection[0] = a
                @selection[1] = b
                @selection[2] = c
                @selection[3] = d
                @selection[4] = e
                consider(5, stats)
                e += 1
              d += 1
            c += 1
          b += 1
        a += 1
    finish_stats(stats, started)
    stats[0]

  # Enumerate the complete odd affine hull in Gray order.  Parent 0 is the
  # affine origin.  Flipping Gray bit i applies the exact-zero difference
  # parent_0 XOR parent_(i+1), so each endpoint update is two sorted symmetric
  # differences and consecutive iterations differ in one affine coordinate.
  -> run_hull(stats)
    reset_stats(stats)
    started = ccall("__w_clock_ms") ## i64
    count = @config[3] ## i64
    if count < 1 || count > 20
      finish_stats(stats, started)
      return 0
    current_rank = @ranks[0] ## i64
    ffoas_copy_slot(@bank_u, @bank_v, @bank_w, 0, @candidate_u, @candidate_v, @candidate_w, 0, current_rank)
    limit = 1 << (count - 1) ## i64
    previous_gray = 0 ## i64
    index = 0 ## i64
    while index < limit
      gray = index ^ (index >> 1) ## i64
      if index > 0
        changed = gray ^ previous_gray ## i64
        bit = 0 ## i64
        while ((changed >> bit) & 1) == 0
          bit += 1
        scratch_rank = ffoas_xor_sorted_slot(@candidate_u, @candidate_v, @candidate_w, current_rank, @bank_u, @bank_v, @bank_w, 0, @ranks[0], @raw_u, @raw_v, @raw_w) ## i64
        current_rank = ffoas_xor_sorted_slot(@raw_u, @raw_v, @raw_w, scratch_rank, @bank_u, @bank_v, @bank_w, (bit + 1) * @config[2], @ranks[bit + 1], @candidate_u, @candidate_v, @candidate_w) ## i64
      selected = 0 ## i64
      selected_other = 0 ## i64
      bit = 0
      while bit < count - 1
        if ((gray >> bit) & 1) == 1
          @selection[selected] = bit + 1
          selected += 1
          selected_other += 1
        bit += 1
      if (selected_other & 1) == 0
        # Keep parent ids sorted for stable provenance strings.
        move = selected ## i64
        while move > 0
          @selection[move] = @selection[move - 1]
          move -= 1
        @selection[0] = 0
        selected += 1
      score_candidate(current_rank, selected, stats)
      previous_gray = gray
      index += 1
    finish_stats(stats, started)
    stats[0]

  -> publish(path)
    if @best_config[0] < 1
      return 0
    loaded = ffw_init_terms_cap(@gate, @best_u, @best_v, @best_w, @best_config[0], @config[0], @config[2], 940901, 0, 1, 1, 1) ## i64
    if loaded != @best_config[0] || ffw_verify_current_exact(@gate, @config[0]) != 1
      return 0
    ffw_dump_current(@gate, path)

  -> novel_distinct()
    if @novel_config[0] < 1 || @best_config[0] < 1
      return 0
    if @novel_config[0] != @best_config[0]
      return 1
    if ffoas_equal_slot(@best_u, @best_v, @best_w, 0, @best_config[0], @novel_u, @novel_v, @novel_w, @novel_config[0]) == 1
      return 0
    1

  -> publish_novel(path)
    if @novel_config[0] < 1
      return 0
    loaded = ffw_init_terms_cap(@gate, @novel_u, @novel_v, @novel_w, @novel_config[0], @config[0], @config[2], 940907, 0, 1, 1, 1) ## i64
    if loaded != @novel_config[0] || ffw_verify_current_exact(@gate, @config[0]) != 1
      return 0
    ffw_dump_current(@gate, path)

-> ffoasb_paths(n) (i64)
  # Audit the independent generating bank, not outputs of a prior affine
  # audit; otherwise rerunning the benchmark silently changes the experiment
  # into another affine-hull generation.
  frontier = ffp_frontier_seed_paths(n)
  paths = []
  i = 0 ## i64
  while i < frontier.size()
    if !frontier[i].include?("odd_parent")
      paths.push(frontier[i])
    i += 1
  base = "benchmarks/matmul/metaflip/" ## String
  if n == 5
    paths.push(base + "matmul_5x5_rank93_catalog_alphaevolve_gf2.txt")
  if n == 6
    paths.push(base + "matmul_6x6_rank153_catalog_gf2.txt")
  paths

# A deliberately small global-isotropy image bank.  For 4x4 we retain the
# closest elementary image on each transvection axis plus the closest swap for
# both frontier orbits (10 parents, 512 odd endpoints).  For 6x6/7x7 we use
# three sources and retain only the closest transvection and swap from each
# (9 parents, 256 endpoints).  Images live in /tmp because they are audit
# inputs, not authoritative frontier artifacts.
-> ffoasb_isotropy_sources(n) (i64)
  base = "benchmarks/matmul/metaflip/" ## String
  paths = []
  if n == 4
    paths.push(base + "matmul_4x4_rank47_d450_gf2.txt")
    paths.push(base + "matmul_4x4_rank47_d677_flips_gf2.txt")
  if n == 6
    paths.push(base + "matmul_6x6_rank153_d1860_global_isotropy_gf2.txt")
    paths.push(base + "matmul_6x6_rank153_d2502_gf2.txt")
    paths.push(base + "matmul_6x6_rank153_catalog_gf2.txt")
  if n == 7
    paths.push(base + "matmul_7x7_rank247_d3098_global_isotropy_gf2.txt")
    paths.push(base + "matmul_7x7_rank247_d3098_partial_auto_max_distance_gf2.txt")
    paths.push(base + "matmul_7x7_rank247_d3098_partial_auto_beam_far_gf2.txt")
  paths

# category 0..2: transvection on that domain; 3: any coordinate swap;
# 4: any transvection.  The closest nonidentity image maximizes immediate
# support cancellation with its source under symmetric difference.
-> ffoasb_make_isotropy_image(path, n, source_id, category) (String i64 i64 i64)
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(state, path, n, capacity, 951001 + n * 101 + source_id * 17 + category, 0, 1, 1, 1) ## i64
  if rank < 1 || ffw_verify_current_exact(state, n) != 1
    return ""
  raw_u = i64[capacity]
  raw_v = i64[capacity]
  raw_w = i64[capacity]
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  exported = ffw_export_current(state, raw_u, raw_v, raw_w) ## i64
  source_rank = ffoas_canonicalize(raw_u, raw_v, raw_w, exported, source_u, source_v, source_w) ## i64
  best_distance = 9223372036854775807 ## i64
  best_density = 9223372036854775807 ## i64
  best_operation = 0 - 1 ## i64
  best_domain = 0 ## i64
  best_source = 0 ## i64
  best_target = 0 ## i64
  operation = 0 ## i64
  while operation < 2
    domain = 0 ## i64
    while domain < 3
      source = 0 ## i64
      while source < n
        target = 0 ## i64
        while target < n
          admissible = 0 ## i64
          if operation == 0 && source < target && category == 3
            admissible = 1
          if operation == 1 && source != target && (category == 4 || category == domain)
            admissible = 1
          if admissible == 1
            image_u = i64[capacity]
            image_v = i64[capacity]
            image_w = i64[capacity]
            ffgir_copy_terms(source_u, source_v, source_w, image_u, image_v, image_w, source_rank)
            transformed = ffgir_apply_generator(image_u, image_v, image_w, source_rank, n, operation, domain, source, target) ## i64
            ffoas_sort_terms(image_u, image_v, image_w, transformed)
            distance = ffoas_distance_slot(source_u, source_v, source_w, 0, source_rank, image_u, image_v, image_w, transformed) ## i64
            density = ffgir_density(image_u, image_v, image_w, transformed) ## i64
            if distance > 0 && (distance < best_distance || (distance == best_distance && density < best_density))
              best_distance = distance
              best_density = density
              best_operation = operation
              best_domain = domain
              best_source = source
              best_target = target
          target += 1
        source += 1
      domain += 1
    operation += 1
  if best_operation < 0
    return ""
  image_u = i64[capacity]
  image_v = i64[capacity]
  image_w = i64[capacity]
  ffgir_copy_terms(source_u, source_v, source_w, image_u, image_v, image_w, source_rank)
  transformed = ffgir_apply_generator(image_u, image_v, image_w, source_rank, n, best_operation, best_domain, best_source, best_target) ## i64
  ffoas_sort_terms(image_u, image_v, image_w, transformed)
  gate = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(gate, image_u, image_v, image_w, transformed, n, capacity, 951701 + source_id * 31 + category, 0, 1, 1, 1) ## i64
  if loaded != transformed || ffw_verify_current_exact(gate, n) != 1
    return ""
  image_path = "/tmp/flipfleet_odd_isotropy_n" + n.to_s() + "_s" + source_id.to_s() + "_c" + category.to_s() + ".txt" ## String
  written = ffw_dump_current(gate, image_path) ## i64
  if written != transformed
    return ""
  << "ODD_PARENT_ISOTROPY_IMAGE tensor=" + n.to_s() + "x" + n.to_s() + " source=" + source_id.to_s() + " category=" + category.to_s() + " generator=" + best_operation.to_s() + "/" + best_domain.to_s() + "/" + best_source.to_s() + "/" + best_target.to_s() + " rank=" + transformed.to_s() + " density=" + best_density.to_s() + " source_distance=" + best_distance.to_s() + " path=" + image_path
  image_path

-> ffoasb_isotropy_paths(n) (i64)
  sources = ffoasb_isotropy_sources(n)
  paths = []
  source = 0 ## i64
  while source < sources.size()
    paths.push(sources[source])
    if n == 4
      category = 0 ## i64
      while category <= 3
        image_path = ffoasb_make_isotropy_image(sources[source], n, source, category) ## String
        if image_path.size() > 0
          paths.push(image_path)
        category += 1
    else
      image_path = ffoasb_make_isotropy_image(sources[source], n, source, 4) ## String
      if image_path.size() > 0
        paths.push(image_path)
      image_path = ffoasb_make_isotropy_image(sources[source], n, source, 3)
      if image_path.size() > 0
        paths.push(image_path)
    source += 1
  paths

-> ffoasb_parent_labels(audit, paths, count) (FFOASBankAudit Array i64)
  text = "" ## String
  i = 0 ## i64
  while i < count
    if i > 0
      text += ","
    slot = audit.best_parent(i) ## i64
    source = audit.source_id(slot) ## i64
    text += source.to_s()
    i += 1
  text

-> ffoasb_novel_parent_labels(audit, paths, count) (FFOASBankAudit Array i64)
  text = "" ## String
  i = 0 ## i64
  while i < count
    if i > 0
      text += ","
    slot = audit.novel_parent(i) ## i64
    source = audit.source_id(slot) ## i64
    text += source.to_s()
    i += 1
  text

-> ffoasb_run(n, include_five, publish, include_hull, isotropy) (i64 i64 i64 i64 i64) i64
  paths = ffoasb_paths(n)
  if isotropy == 1
    paths = ffoasb_isotropy_paths(n)
  ffoasb_expect("nonempty bank", paths.size() > 0)
  audit = FFOASBankAudit.new(n, paths)
  triple = i64[26]
  triple_count = audit.run(3, triple) ## i64
  expected_triples = ffoas_choose(audit.bank_count(), 3) ## i64
  ffoasb_expect("triple coverage", triple_count == expected_triples && triple[1] == triple_count && triple[2] == 0 && triple[3] + triple[4] == triple_count)
  average_rank = 0 ## i64
  if triple_count > 0
    average_rank = triple[15] / triple_count
  debt = 0 - 1 ## i64
  if triple[5] >= 0
    debt = triple[5] - ffp_record(n)
  labels = "none" ## String
  if triple_count > 0
    labels = ffoasb_parent_labels(audit, paths, 3)
  novel_labels = "none" ## String
  if triple[23] >= 0
    novel_labels = ffoasb_novel_parent_labels(audit, paths, 3)
  << "ODD_PARENT_AFFINE_SUMMARY tensor=" + n.to_s() + "x" + n.to_s() + " parents_input=" + audit.input_count().to_s() + " parents_canonical=" + audit.bank_count().to_s() + " duplicate_parents=" + audit.duplicate_parents().to_s() + " arity=3 combinations=" + triple[0].to_s() + "/" + expected_triples.to_s() + " full_n6_gates=" + triple[1].to_s() + " failures=" + triple[2].to_s() + " canonical_unique=" + triple[3].to_s() + " duplicate_endpoints=" + triple[4].to_s() + " best_rank=" + triple[5].to_s() + " debt=" + debt.to_s() + " best_density=" + triple[6].to_s() + " best_novelty=" + triple[7].to_s() + " best_parent_distance=" + triple[17].to_s() + "/" + triple[18].to_s() + " max_novelty=" + triple[8].to_s() + " max_min_parent_distance=" + triple[9].to_s() + " max_parent_distance=" + triple[10].to_s() + " debt_le0=" + triple[11].to_s() + " debt_le1=" + triple[12].to_s() + " debt_le2=" + triple[13].to_s() + " debt_le5=" + triple[14].to_s() + " average_rank=" + average_rank.to_s() + " best_rank_multiplicity=" + triple[19].to_s() + " record_novel_rank=" + triple[23].to_s() + " record_novel_density=" + triple[22].to_s() + " record_max_novelty=" + triple[21].to_s() + " record_novel_parent_distance=" + triple[24].to_s() + "/" + triple[25].to_s() + " elapsed_ms=" + triple[20].to_s() + " score_ms=" + triple[16].to_s() + " best_parents=" + labels + " record_novel_parents=" + novel_labels
  if publish == 1 && triple_count > 0 && debt <= 2 && triple[7] > 0
    path = "benchmarks/matmul/metaflip/matmul_" + n.to_s() + "x" + n.to_s() + "_rank" + triple[5].to_s() + "_d" + triple[6].to_s() + "_odd_parent3_gf2.txt" ## String
    written = audit.publish(path) ## i64
    ffoasb_expect("publish", written == triple[5])
    << "ODD_PARENT_AFFINE_PUBLISHED path=" + path + " rank=" + triple[5].to_s() + " density=" + triple[6].to_s() + " novelty=" + triple[7].to_s()
    if audit.novel_distinct() == 1 && triple[23] <= ffp_record(n)
      novel_path = "benchmarks/matmul/metaflip/matmul_" + n.to_s() + "x" + n.to_s() + "_rank" + triple[23].to_s() + "_d" + triple[22].to_s() + "_odd_parent3_novel_gf2.txt" ## String
      novel_written = audit.publish_novel(novel_path) ## i64
      ffoasb_expect("publish novel", novel_written == triple[23])
      << "ODD_PARENT_AFFINE_PUBLISHED path=" + novel_path + " rank=" + triple[23].to_s() + " density=" + triple[22].to_s() + " novelty=" + triple[21].to_s()

  if include_five == 1
    five = i64[26]
    five_count = audit.run(5, five) ## i64
    expected_five = ffoas_choose(audit.bank_count(), 5) ## i64
    ffoasb_expect("five coverage", five_count == expected_five && five[1] == five_count && five[2] == 0 && five[3] + five[4] == five_count)
    five_average = 0 ## i64
    if five_count > 0
      five_average = five[15] / five_count
    five_debt = 0 - 1 ## i64
    five_labels = "none" ## String
    if five_count > 0
      five_debt = five[5] - ffp_record(n)
      five_labels = ffoasb_parent_labels(audit, paths, 5)
    five_novel_labels = "none" ## String
    if five[23] >= 0
      five_novel_labels = ffoasb_novel_parent_labels(audit, paths, 5)
    << "ODD_PARENT_AFFINE_SUMMARY tensor=" + n.to_s() + "x" + n.to_s() + " parents_input=" + audit.input_count().to_s() + " parents_canonical=" + audit.bank_count().to_s() + " duplicate_parents=" + audit.duplicate_parents().to_s() + " arity=5 combinations=" + five[0].to_s() + "/" + expected_five.to_s() + " full_n6_gates=" + five[1].to_s() + " failures=" + five[2].to_s() + " canonical_unique=" + five[3].to_s() + " duplicate_endpoints=" + five[4].to_s() + " best_rank=" + five[5].to_s() + " debt=" + five_debt.to_s() + " best_density=" + five[6].to_s() + " best_novelty=" + five[7].to_s() + " best_parent_distance=" + five[17].to_s() + "/" + five[18].to_s() + " max_novelty=" + five[8].to_s() + " max_min_parent_distance=" + five[9].to_s() + " max_parent_distance=" + five[10].to_s() + " debt_le0=" + five[11].to_s() + " debt_le1=" + five[12].to_s() + " debt_le2=" + five[13].to_s() + " debt_le5=" + five[14].to_s() + " average_rank=" + five_average.to_s() + " best_rank_multiplicity=" + five[19].to_s() + " record_novel_rank=" + five[23].to_s() + " record_novel_density=" + five[22].to_s() + " record_max_novelty=" + five[21].to_s() + " record_novel_parent_distance=" + five[24].to_s() + "/" + five[25].to_s() + " elapsed_ms=" + five[20].to_s() + " score_ms=" + five[16].to_s() + " best_parents=" + five_labels + " record_novel_parents=" + five_novel_labels
    if publish == 1 && five_count > 0 && five_debt <= 2 && five[7] > 0
      five_path = "benchmarks/matmul/metaflip/matmul_" + n.to_s() + "x" + n.to_s() + "_rank" + five[5].to_s() + "_d" + five[6].to_s() + "_odd_parent5_gf2.txt" ## String
      five_written = audit.publish(five_path) ## i64
      ffoasb_expect("publish five", five_written == five[5])
      << "ODD_PARENT_AFFINE_PUBLISHED path=" + five_path + " rank=" + five[5].to_s() + " density=" + five[6].to_s() + " novelty=" + five[7].to_s()
      if audit.novel_distinct() == 1 && five[23] <= ffp_record(n)
        five_novel_path = "benchmarks/matmul/metaflip/matmul_" + n.to_s() + "x" + n.to_s() + "_rank" + five[23].to_s() + "_d" + five[22].to_s() + "_odd_parent5_novel_gf2.txt" ## String
        five_novel_written = audit.publish_novel(five_novel_path) ## i64
        ffoasb_expect("publish five novel", five_novel_written == five[23])
        << "ODD_PARENT_AFFINE_PUBLISHED path=" + five_novel_path + " rank=" + five[23].to_s() + " density=" + five[22].to_s() + " novelty=" + five[21].to_s()

  if include_hull == 1
    hull = i64[31]
    hull_count = audit.run_hull(hull) ## i64
    expected_hull = 1 << (audit.bank_count() - 1) ## i64
    ffoasb_expect("hull coverage", hull_count == expected_hull && hull[1] == hull_count && hull[2] == 0 && hull[3] + hull[4] == hull_count)
    hull_average = 0 ## i64
    if hull_count > 0
      hull_average = hull[15] / hull_count
    hull_debt = 0 - 1 ## i64
    hull_labels = "none" ## String
    if hull[5] >= 0
      hull_debt = hull[5] - ffp_record(n)
      hull_labels = ffoasb_parent_labels(audit, paths, audit.best_parent_count())
    hull_novel_labels = "none" ## String
    if hull[23] >= 0
      hull_novel_labels = ffoasb_novel_parent_labels(audit, paths, audit.novel_parent_count())
    << "ODD_PARENT_AFFINE_HULL tensor=" + n.to_s() + "x" + n.to_s() + " parents_input=" + audit.input_count().to_s() + " parents_canonical=" + audit.bank_count().to_s() + " endpoints=" + hull[0].to_s() + "/" + expected_hull.to_s() + " gray_transitions=" + (hull[0] - 1).to_s() + " full_n6_gates=" + hull[1].to_s() + " failures=" + hull[2].to_s() + " canonical_unique=" + hull[3].to_s() + " duplicate_endpoints=" + hull[4].to_s() + " arity1=" + hull[26].to_s() + " arity3=" + hull[27].to_s() + " arity5=" + hull[28].to_s() + " arity7plus=" + hull[29].to_s() + " max_arity=" + hull[30].to_s() + " best_novel_rank=" + hull[5].to_s() + " debt=" + hull_debt.to_s() + " best_novel_density=" + hull[6].to_s() + " best_novelty=" + hull[7].to_s() + " best_arity=" + audit.best_parent_count().to_s() + " best_parent_distance=" + hull[17].to_s() + "/" + hull[18].to_s() + " max_novelty=" + hull[8].to_s() + " debt_le0_including_parents=" + hull[11].to_s() + " debt_le2_including_parents=" + hull[13].to_s() + " average_rank=" + hull_average.to_s() + " record_novel_rank=" + hull[23].to_s() + " record_novel_density=" + hull[22].to_s() + " record_max_novelty=" + hull[21].to_s() + " record_novel_arity=" + audit.novel_parent_count().to_s() + " elapsed_ms=" + hull[20].to_s() + " score_ms=" + hull[16].to_s() + " best_parents=" + hull_labels + " record_novel_parents=" + hull_novel_labels
    if publish == 1 && hull[5] > 0 && hull_debt <= 2 && hull[7] > 0
      hull_kind = "odd_hull" ## String
      if isotropy == 1
        hull_kind = "isotropy_odd_hull"
      hull_path = "benchmarks/matmul/metaflip/matmul_" + n.to_s() + "x" + n.to_s() + "_rank" + hull[5].to_s() + "_d" + hull[6].to_s() + "_" + hull_kind + "_a" + audit.best_parent_count().to_s() + "_gf2.txt" ## String
      hull_written = audit.publish(hull_path) ## i64
      ffoasb_expect("publish hull", hull_written == hull[5])
      << "ODD_PARENT_AFFINE_PUBLISHED path=" + hull_path + " rank=" + hull[5].to_s() + " density=" + hull[6].to_s() + " novelty=" + hull[7].to_s()
      if audit.novel_distinct() == 1 && hull[23] <= ffp_record(n)
        hull_novel_path = "benchmarks/matmul/metaflip/matmul_" + n.to_s() + "x" + n.to_s() + "_rank" + hull[23].to_s() + "_d" + hull[22].to_s() + "_" + hull_kind + "_a" + audit.novel_parent_count().to_s() + "_novel_gf2.txt" ## String
        hull_novel_written = audit.publish_novel(hull_novel_path) ## i64
        ffoasb_expect("publish hull novel", hull_novel_written == hull[23])
        << "ODD_PARENT_AFFINE_PUBLISHED path=" + hull_novel_path + " rank=" + hull[23].to_s() + " density=" + hull[22].to_s() + " novelty=" + hull[21].to_s()
  1

args = argv()
only_n = 0 ## i64
include_five = 1 ## i64
publish = 0 ## i64
include_hull = 0 ## i64
isotropy = 0 ## i64
if args.size() > 0
  only_n = args[0].to_i()
if args.size() > 1
  include_five = args[1].to_i()
if args.size() > 2
  publish = args[2].to_i()
if args.size() > 3
  include_hull = args[3].to_i()
if args.size() > 4
  isotropy = args[4].to_i()
ffoasb_expect("arguments", (only_n == 0 || (only_n >= 4 && only_n <= 7)) && (include_five == 0 || include_five == 1) && (publish == 0 || publish == 1) && (include_hull == 0 || include_hull == 1) && (isotropy == 0 || isotropy == 1) && (isotropy == 0 || only_n == 4 || only_n == 6 || only_n == 7))

n = 4 ## i64
while n <= 7
  if only_n == 0 || only_n == n
    z = ffoasb_run(n, include_five, publish, include_hull, isotropy) ## i64
  n += 1

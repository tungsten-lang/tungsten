use flipfleet_global_isotropy

-> ffgirb_unique(values, count) (i64[] i64) i64
  unique = 0 ## i64
  i = 0 ## i64
  while i < count
    seen = 0 ## i64
    j = 0 ## i64
    while j < i && seen == 0
      if values[j] == values[i]
        seen = 1
      j += 1
    if seen == 0
      unique += 1
    i += 1
  unique

# Exhaust every elementary generator and report density-locality around the
# seed: out = attempts, lower, equal, higher, minimum, maximum.
-> ffgirb_scan_generators(us, vs, ws, rank, n, capacity, out) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  source_density = ffgir_density(us, vs, ws, rank) ## i64
  out[0] = 0
  out[1] = 0
  out[2] = 0
  out[3] = 0
  out[4] = source_density
  out[5] = source_density
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
            tu = i64[capacity]
            tv = i64[capacity]
            tw = i64[capacity]
            z = ffgir_copy_terms(us, vs, ws, tu, tv, tw, rank) ## i64
            if ffgir_apply_generator(tu, tv, tw, rank, n, operation, domain, source, target) == rank
              density = ffgir_density(tu, tv, tw, rank) ## i64
              out[0] = out[0] + 1
              if density < source_density
                out[1] = out[1] + 1
              if density == source_density
                out[2] = out[2] + 1
              if density > source_density
                out[3] = out[3] + 1
              if density < out[4]
                out[4] = density
              if density > out[5]
                out[5] = density
          target += 1
        source += 1
      domain += 1
    operation += 1
  out[0]

-> ffgirb_run(label, path, n, trials, steps, word_length) (String String i64 i64 i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  size = ffw_state_size(capacity) ## i64
  # A short but complete work/wander sawtooth.  A work-only micro-run leaves
  # the 4x4 rank-47 frontiers completely stationary because they have no
  # immediately accepted equal-factor flip; shoulder splits are essential to
  # testing whether a restart changes their descendants.
  workq = steps / 16 ## i64
  wanderq = steps / 32 ## i64
  if workq < 1
    workq = 1
  if wanderq < 1
    wanderq = 1
  reference = i64[size]
  rank = ffw_load_scheme_cap(reference, path, n, capacity, 73001 + n, 6, 4, workq, wanderq) ## i64
  if rank < 1 || ffw_verify_best_exact(reference, n) != 1
    << "GLOBAL_ISOTROPY_LOAD_FAIL tensor=" + label
    return 0 - 1

  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  exported = ffw_export_best(reference, source_u, source_v, source_w) ## i64
  source_density = ffgir_density(source_u, source_v, source_w, rank) ## i64
  source_union = ffgir_union_support(source_u, source_v, source_w, rank) ## i64
  source_factors = ffgir_distinct_factor_support(source_u, source_v, source_w, rank) ## i64
  generator_scan = i64[6]
  z = ffgirb_scan_generators(source_u, source_v, source_w, rank, n, capacity, generator_scan) ## i64

  control_ids = i64[trials]
  image_ids = i64[trials]
  control_gls = i64[trials]
  image_gls = i64[trials]
  exact_images = 0 ## i64
  inverse_ok = 0 ## i64
  initial_id_changes = 0 ## i64
  initial_gl_matches = 0 ## i64
  initial_distance_sum = 0 ## i64
  initial_density_sum = 0 ## i64
  min_initial_density = 9223372036854775807 ## i64
  max_initial_density = 0 ## i64
  union_matches = 0 ## i64
  factor_matches = 0 ## i64
  conjugate_after = 0 ## i64
  conjugate_distance_sum = 0 ## i64
  control_rank_wins = 0 ## i64
  image_rank_wins = 0 ## i64
  control_density_wins = 0 ## i64
  image_density_wins = 0 ## i64
  control_desc_distance_sum = 0 ## i64
  image_desc_distance_sum = 0 ## i64
  control_accept_sum = 0 ## i64
  image_accept_sum = 0 ## i64
  control_best_density_sum = 0 ## i64
  image_best_density_sum = 0 ## i64
  control_best_density_min = 9223372036854775807 ## i64
  image_best_density_min = 9223372036854775807 ## i64
  image_beats_control = 0 ## i64
  image_beats_source = 0 ## i64

  trial = 0 ## i64
  while trial < trials
    operations = i64[word_length]
    domains = i64[word_length]
    sources = i64[word_length]
    targets = i64[word_length]
    program_seed = 104729 * (trial + 1) + n * 1009 + rank * 17 ## i64
    made = ffgir_make_word(n, program_seed, word_length, operations, domains, sources, targets) ## i64

    image_u = i64[capacity]
    image_v = i64[capacity]
    image_w = i64[capacity]
    z = ffgir_copy_terms(source_u, source_v, source_w, image_u, image_v, image_w, rank) ## i64
    transformed = ffgir_apply_word(image_u, image_v, image_w, rank, n, operations, domains, sources, targets, made, 0) ## i64
    initial_distance = ffgir_term_set_distance(source_u, source_v, source_w, rank, image_u, image_v, image_w, rank) ## i64
    initial_density = ffgir_density(image_u, image_v, image_w, rank) ## i64
    initial_union = ffgir_union_support(image_u, image_v, image_w, rank) ## i64
    initial_factors = ffgir_distinct_factor_support(image_u, image_v, image_w, rank) ## i64
    initial_distance_sum += initial_distance
    initial_density_sum += initial_density
    if initial_density < min_initial_density
      min_initial_density = initial_density
    if initial_density > max_initial_density
      max_initial_density = initial_density
    if initial_union == source_union
      union_matches += 1
    if initial_factors == source_factors
      factor_matches += 1

    search_seed = 13007 * (trial + 1) + n * 65537 ## i64
    control = i64[size]
    image = i64[size]
    control_loaded = ffw_init_terms_cap(control, source_u, source_v, source_w, rank, n, capacity, search_seed, 6, 4, workq, wanderq) ## i64
    image_loaded = ffw_init_terms_cap(image, image_u, image_v, image_w, rank, n, capacity, search_seed, 6, 4, workq, wanderq) ## i64
    if transformed == rank && made == word_length && control_loaded == rank && image_loaded == rank && ffw_verify_best_exact(image, n) == 1
      exact_images += 1
    if ffbi_best_id(reference) != ffbi_best_id(image)
      initial_id_changes += 1
    if ffbi_gl_invariant_view(reference, 0) == ffbi_gl_invariant_view(image, 0)
      initial_gl_matches += 1

    inverse_u = i64[capacity]
    inverse_v = i64[capacity]
    inverse_w = i64[capacity]
    z = ffgir_copy_terms(image_u, image_v, image_w, inverse_u, inverse_v, inverse_w, rank)
    undone = ffgir_apply_word(inverse_u, inverse_v, inverse_w, rank, n, operations, domains, sources, targets, made, 1) ## i64
    if undone == rank && ffgir_terms_equal(source_u, source_v, source_w, rank, inverse_u, inverse_v, inverse_w, rank) == 1
      inverse_ok += 1

    z = ffw_walk(control, steps)
    z = ffw_walk(image, steps)
    if ffw_verify_current_exact(control, n) != 1 || ffw_verify_current_exact(image, n) != 1
      << "GLOBAL_ISOTROPY_WALK_GATE_FAIL tensor=" + label + " trial=" + trial.to_s()
      return 0 - 1

    conjugate_distance = ffgir_conjugate_current_distance(control, image, n, capacity, operations, domains, sources, targets, made) ## i64
    conjugate_distance_sum += conjugate_distance
    if conjugate_distance == 0
      conjugate_after += 1

    control_u = i64[capacity]
    control_v = i64[capacity]
    control_w = i64[capacity]
    descendant_u = i64[capacity]
    descendant_v = i64[capacity]
    descendant_w = i64[capacity]
    control_current_rank = ffw_export_current(control, control_u, control_v, control_w) ## i64
    image_current_rank = ffw_export_current(image, descendant_u, descendant_v, descendant_w) ## i64
    control_desc_distance = ffgir_term_set_distance(source_u, source_v, source_w, rank, control_u, control_v, control_w, control_current_rank) ## i64
    image_desc_distance = ffgir_term_set_distance(image_u, image_v, image_w, rank, descendant_u, descendant_v, descendant_w, image_current_rank) ## i64
    control_desc_distance_sum += control_desc_distance
    image_desc_distance_sum += image_desc_distance
    control_accept_sum += ffw_accepted(control)
    image_accept_sum += ffw_accepted(image)
    control_best_density_sum += ffw_best_bits(control)
    image_best_density_sum += ffw_best_bits(image)
    if ffw_best_bits(control) < control_best_density_min
      control_best_density_min = ffw_best_bits(control)
    if ffw_best_bits(image) < image_best_density_min
      image_best_density_min = ffw_best_bits(image)
    if ffw_best_rank(image) < ffw_best_rank(control)
      image_beats_control += 1
    else
      if ffw_best_rank(image) == ffw_best_rank(control) && ffw_best_bits(image) < ffw_best_bits(control)
        image_beats_control += 1
    if ffw_best_rank(image) < rank
      image_beats_source += 1
    else
      if ffw_best_rank(image) == rank && ffw_best_bits(image) < source_density
        image_beats_source += 1

    if ffw_best_rank(control) < rank
      control_rank_wins += 1
    else
      if ffw_best_rank(control) == rank && ffw_best_bits(control) < source_density
        control_density_wins += 1
    if ffw_best_rank(image) < rank
      image_rank_wins += 1
    else
      if ffw_best_rank(image) == rank && ffw_best_bits(image) < initial_density
        image_density_wins += 1

    control_ids[trial] = ffbi_current_id(control)
    image_ids[trial] = ffbi_current_id(image)
    control_gls[trial] = ffbi_gl_invariant_view(control, 1)
    image_gls[trial] = ffbi_gl_invariant_view(image, 1)
    << "GLOBAL_ISOTROPY_TRIAL tensor=" + label + " trial=" + trial.to_s() + " init-d=" + initial_distance.to_s() + " init-density=" + initial_density.to_s() + " control=" + ffw_current_rank(control).to_s() + "/" + ffw_best_rank(control).to_s() + ":" + ffw_best_bits(control).to_s() + " image=" + ffw_current_rank(image).to_s() + "/" + ffw_best_rank(image).to_s() + ":" + ffw_best_bits(image).to_s() + " conjugate-d=" + conjugate_distance.to_s() + " desc-d=" + control_desc_distance.to_s() + "/" + image_desc_distance.to_s() + " accepted=" + ffw_accepted(control).to_s() + "/" + ffw_accepted(image).to_s()
    trial += 1

  << "GLOBAL_ISOTROPY_SUMMARY tensor=" + label + " rank=" + rank.to_s() + " trials=" + trials.to_s() + " steps=" + steps.to_s() + " word=" + word_length.to_s() + " exact=" + exact_images.to_s() + " inverse=" + inverse_ok.to_s() + " ids-changed=" + initial_id_changes.to_s() + " gl-matched=" + initial_gl_matches.to_s() + " source-density=" + source_density.to_s() + " generator-density=" + generator_scan[4].to_s() + ".." + generator_scan[5].to_s() + ":" + generator_scan[1].to_s() + "/" + generator_scan[2].to_s() + "/" + generator_scan[3].to_s() + " image-density=" + min_initial_density.to_s() + ".." + max_initial_density.to_s() + ":avg" + (initial_density_sum / trials).to_s() + " init-d-avg=" + (initial_distance_sum / trials).to_s() + " union=" + union_matches.to_s() + " factors=" + factor_matches.to_s() + " conjugate-after=" + conjugate_after.to_s() + " conjugate-d-avg=" + (conjugate_distance_sum / trials).to_s() + " unique-id=" + ffgirb_unique(control_ids, trials).to_s() + "/" + ffgirb_unique(image_ids, trials).to_s() + " unique-gl=" + ffgirb_unique(control_gls, trials).to_s() + "/" + ffgirb_unique(image_gls, trials).to_s() + " rank-win=" + control_rank_wins.to_s() + "/" + image_rank_wins.to_s() + " density-win=" + control_density_wins.to_s() + "/" + image_density_wins.to_s() + " final-density-min=" + control_best_density_min.to_s() + "/" + image_best_density_min.to_s() + " final-density-avg=" + (control_best_density_sum / trials).to_s() + "/" + (image_best_density_sum / trials).to_s() + " image-beats=" + image_beats_control.to_s() + "/" + image_beats_source.to_s() + " desc-d-avg=" + (control_desc_distance_sum / trials).to_s() + "/" + (image_desc_distance_sum / trials).to_s() + " accepted-avg=" + (control_accept_sum / trials).to_s() + "/" + (image_accept_sum / trials).to_s()
  exact_images

arguments = argv()
trials = 8 ## i64
steps = 250000 ## i64
word_length = 9 ## i64
if arguments.size() > 0
  trials = arguments[0].to_i()
if arguments.size() > 1
  steps = arguments[1].to_i()
if arguments.size() > 2
  word_length = arguments[2].to_i()
if trials < 1
  trials = 1
if trials > 64
  trials = 64
if steps < 1
  steps = 1
if steps > 10000000
  steps = 10000000
if word_length < 1
  word_length = 1
if word_length > 32
  word_length = 32

root = "benchmarks/matmul/metaflip/"
ok = 0 ## i64
ok += ffgirb_run("4x4-d450", root + "matmul_4x4_rank47_d450_gf2.txt", 4, trials, steps, word_length)
ok += ffgirb_run("4x4-d677", root + "matmul_4x4_rank47_d677_flips_gf2.txt", 4, trials, steps, word_length)
ok += ffgirb_run("5x5-d1155", root + "matmul_5x5_rank93_d1155_gf2.txt", 5, trials, steps, word_length)
ok += ffgirb_run("5x5-d1168", root + "matmul_5x5_rank93_d1168_gf2.txt", 5, trials, steps, word_length)
if ok != trials * 4
  exit(1)

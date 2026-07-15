# Conjugated projection/replacement audit.
#
# The coordinate-core audit only tests coordinate 2-planes.  Conjugating the
# whole scheme by a matrix-multiplication isotropy before projecting, and then
# undoing that isotropy, tests many non-coordinate 2-planes and retractions
# without adding a second implementation of the dual maps.  Every accepted
# endpoint is independently exact-gated after the inverse conjugation.

use flipfleet_projection_replacement
use flipfleet_global_isotropy
use metaflip_worker

-> ffprc_expect(label, condition) (String bool) i64
  if !condition
    << "PROJECTION_CONJUGATE_FAIL " + label
    exit(1)
  1

-> ffprc_pair(rng, n, pair) (i64[] i64 i64[]) i64
  first = ffgir_next(rng) % n ## i64
  second = ffgir_next(rng) % (n - 1) ## i64
  if second >= first
    second += 1
  if first > second
    swap = first ## i64
    first = second
    second = swap
  pair[0] = first
  pair[1] = second
  1

-> ffprc_scan(root, source_path, n, seed, word_count, samples_per_word, word_length) (String String i64 i64 i64 i64 i64) i64
  capacity = 1024 ## i64
  state = i64[ffw_state_size(capacity)]
  source_rank = ffw_load_scheme_cap(state, root + source_path, n, capacity, seed, 6, 4, 100000, 25000) ## i64
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  exported = ffw_export_best(state, source_u, source_v, source_w) ## i64
  ffprc_expect("source", source_rank > 0 && exported == source_rank && ffw_verify_best_exact(state, n) == 1)

  lower_state = i64[ffw_state_size(32)]
  lower_rank = ffw_load_scheme_cap(lower_state, root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 32, seed + 1, 6, 4, 1000, 250) ## i64
  lower_u = i64[32]
  lower_v = i64[32]
  lower_w = i64[32]
  lower_exported = ffw_export_best(lower_state, lower_u, lower_v, lower_w) ## i64
  ffprc_expect("lower", lower_rank == 7 && lower_exported == 7 && ffw_verify_best_exact(lower_state, 2) == 1)

  image_u = i64[capacity]
  image_v = i64[capacity]
  image_w = i64[capacity]
  projected_u = i64[capacity]
  projected_v = i64[capacity]
  projected_w = i64[capacity]
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  operations = i64[word_length]
  domains = i64[word_length]
  sources = i64[word_length]
  targets = i64[word_length]
  pair_i = i64[2]
  pair_j = i64[2]
  pair_k = i64[2]
  meta = i64[8]

  placements = 0 ## i64
  trivial = 0 ## i64
  novel = 0 ## i64
  novel_neutral = 0 ## i64
  novel_debt_le2 = 0 ## i64
  novel_debt_le4 = 0 ## i64
  max_distance_le2 = 0 ## i64
  max_distance_le4 = 0 ## i64
  max_distance_le8 = 0 ## i64
  max_distance_le12 = 0 ## i64
  min_debt_distance8 = 1 << 30 ## i64
  best_rank = 1 << 30 ## i64
  best_distance = 0 - 1 ## i64
  best_density = 1 << 30 ## i64
  best_trial = 0 ## i64
  best_i0 = 0 ## i64
  best_i1 = 1 ## i64
  best_j0 = 0 ## i64
  best_j1 = 1 ## i64
  best_k0 = 0 ## i64
  best_k1 = 1 ## i64

  trial = 0 ## i64
  while trial < word_count
    word_seed = seed + 104729 * (trial + 1) ## i64
    ffprc_expect("word", ffgir_make_word(n, word_seed, word_length, operations, domains, sources, targets) == word_length)
    z = ffgir_copy_terms(source_u, source_v, source_w, image_u, image_v, image_w, source_rank) ## i64
    ffprc_expect("apply", ffgir_apply_word(image_u, image_v, image_w, source_rank, n, operations, domains, sources, targets, word_length, 0) == source_rank)
    rng = i64[1]
    rng[0] = (word_seed ^ 7640891576956012809) & 9223372036854775807
    sample = 0 ## i64
    while sample < samples_per_word
      z = ffprc_pair(rng, n, pair_i)
      z = ffprc_pair(rng, n, pair_j)
      z = ffprc_pair(rng, n, pair_k)
      rank = ffpr_splice2_indexed(image_u, image_v, image_w, source_rank, lower_u, lower_v, lower_w, lower_rank, n, pair_i[0], pair_i[1], pair_j[0], pair_j[1], pair_k[0], pair_k[1], projected_u, projected_v, projected_w, out_u, out_v, out_w, capacity, 0, meta) ## i64
      ffprc_expect("placement", rank > 0)
      placements += 1
      distance = ffgir_term_set_distance(image_u, image_v, image_w, source_rank, out_u, out_v, out_w, rank) ## i64
      if distance == 0
        trivial += 1
      else
        novel += 1
        debt = rank - source_rank ## i64
        if debt == 0
          novel_neutral += 1
        if debt <= 2
          novel_debt_le2 += 1
          if distance > max_distance_le2
            max_distance_le2 = distance
        if debt <= 4
          novel_debt_le4 += 1
          if distance > max_distance_le4
            max_distance_le4 = distance
        if debt <= 8 && distance > max_distance_le8
          max_distance_le8 = distance
        if debt <= 12 && distance > max_distance_le12
          max_distance_le12 = distance
        if distance >= 8 && debt < min_debt_distance8
          min_debt_distance8 = debt
        density = ffgir_density(out_u, out_v, out_w, rank) ## i64
        if rank < best_rank || (rank == best_rank && distance > best_distance) || (rank == best_rank && distance == best_distance && density < best_density)
          best_rank = rank
          best_distance = distance
          best_density = density
          best_trial = trial
          best_i0 = pair_i[0]
          best_i1 = pair_i[1]
          best_j0 = pair_j[0]
          best_j1 = pair_j[1]
          best_k0 = pair_k[0]
          best_k1 = pair_k[1]
      sample += 1
    trial += 1

  if novel == 0
    << "PROJECTION_CONJUGATE tensor=" + n.to_s() + " source=" + source_rank.to_s() + " words=" + word_count.to_s() + " samples=" + placements.to_s() + " novel=0 trivial=" + trivial.to_s() + " source-file=" + source_path
    return 999

  # Recreate the selected endpoint, gate it in the conjugated coordinates,
  # undo the word, and gate it again in the source coordinates.
  best_word_seed = seed + 104729 * (best_trial + 1) ## i64
  ffprc_expect("best word", ffgir_make_word(n, best_word_seed, word_length, operations, domains, sources, targets) == word_length)
  z = ffgir_copy_terms(source_u, source_v, source_w, image_u, image_v, image_w, source_rank)
  ffprc_expect("best apply", ffgir_apply_word(image_u, image_v, image_w, source_rank, n, operations, domains, sources, targets, word_length, 0) == source_rank)
  gated = ffpr_splice2_indexed(image_u, image_v, image_w, source_rank, lower_u, lower_v, lower_w, lower_rank, n, best_i0, best_i1, best_j0, best_j1, best_k0, best_k1, projected_u, projected_v, projected_w, out_u, out_v, out_w, capacity, 1, meta) ## i64
  ffprc_expect("best conjugated exact", gated == best_rank && meta[7] == 1)
  ffprc_expect("inverse", ffgir_apply_word(out_u, out_v, out_w, gated, n, operations, domains, sources, targets, word_length, 1) == gated)
  ffprc_expect("best source exact", ffpbr_verify_exact(out_u, out_v, out_w, gated, n, n, n) == 1)
  source_distance = ffgir_term_set_distance(source_u, source_v, source_w, source_rank, out_u, out_v, out_w, gated) ## i64
  ffprc_expect("distance invariant", source_distance == best_distance)

  << "PROJECTION_CONJUGATE tensor=" + n.to_s() + " source=" + source_rank.to_s() + " words=" + word_count.to_s() + " samples=" + placements.to_s() + " best=" + best_rank.to_s() + " debt=" + (best_rank - source_rank).to_s() + " distance=" + best_distance.to_s() + " density=" + best_density.to_s() + " novel=" + novel.to_s() + " neutral=" + novel_neutral.to_s() + " debt<=2=" + novel_debt_le2.to_s() + ":d" + max_distance_le2.to_s() + " debt<=4=" + novel_debt_le4.to_s() + ":d" + max_distance_le4.to_s() + " d<=8:" + max_distance_le8.to_s() + " d<=12:" + max_distance_le12.to_s() + " min-debt@distance8=" + min_debt_distance8.to_s() + " trivial=" + trivial.to_s() + " trial=" + best_trial.to_s() + " I=" + best_i0.to_s() + "," + best_i1.to_s() + " J=" + best_j0.to_s() + "," + best_j1.to_s() + " K=" + best_k0.to_s() + "," + best_k1.to_s() + " source-file=" + source_path
  best_rank - source_rank

root = "benchmarks/matmul/metaflip/"
best_debt = ffprc_scan(root, "matmul_4x4_rank47_d450_gf2.txt", 4, 93101, 48, 216, 12) ## i64
debt = ffprc_scan(root, "matmul_5x5_rank93_d968_global_isotropy_gf2.txt", 5, 93201, 32, 512, 15) ## i64
if debt < best_debt
  best_debt = debt
debt = ffprc_scan(root, "matmul_6x6_rank153_d1860_global_isotropy_gf2.txt", 6, 93301, 24, 768, 18)
if debt < best_debt
  best_debt = debt
debt = ffprc_scan(root, "matmul_7x7_rank247_d3098_global_isotropy_gf2.txt", 7, 93401, 24, 1024, 21)
if debt < best_debt
  best_debt = debt
<< "PROJECTION_CONJUGATE_SUMMARY cases=4 best-debt=" + best_debt.to_s()

# Large-bank exact affine-code benchmark.
#
# The 7x7 run generates every genuine basis endpoint exposed by all 189
# elementary partial-automorphism kernels (155 on the current d3098 source),
# then adds the checked-in D3/isotropy/beam/odd-parent frontier.  The 5x5 and
# 6x6 runs perform the same generator audit and add their complete live
# frontier banks.  Descent therefore operates on a substantially larger zero-
# tensor code than the small odd-parent closure benchmark.
#
# Usage:
#   flipfleet_affine_code_descent_bench [only_n=0] [restarts=24]
#                                      [pair_restarts=6] [pair_rounds=2]
#                                      [publish=0] [temper_epochs=0]
#                                      [temper_steps=128] [k=12]

use flipfleet_affine_code_descent
use flipfleet_partial_automorphism_nullspace
use flipfleet_profiles
use flipfleet_global_isotropy
use flipfleet_basin_identity

-> ffacdb_expect(label, condition) (String bool) i64
  if !condition
    << "AFFINE_CODE_BENCH_FAIL " + label
    exit(1)
  1

-> ffacdb_copy(source_u, source_v, source_w, target_u, target_v, target_w, target_offset, rank) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < rank
    target_u[target_offset + i] = source_u[i]
    target_v[target_offset + i] = source_v[i]
    target_w[target_offset + i] = source_w[i]
    i += 1
  rank

-> ffacdb_fingerprint(us, vs, ws, rank, out) (i64[] i64[] i64[] i64 i64[]) i64
  p1 = 2147483647 ## i64
  p2 = 2147483629 ## i64
  sum1 = 0 ## i64
  square1 = 0 ## i64
  sum2 = 0 ## i64
  square2 = 0 ## i64
  i = 0 ## i64
  while i < rank
    h1 = (ffacd_hash(us[i], vs[i], ws[i]) & 2147483647) % p1 ## i64
    h2 = (ffacd_hash(ws[i], us[i], vs[i]) & 2147483647) % p2 ## i64
    sum1 = (sum1 + h1) % p1
    square1 = (square1 + (h1 * h1) % p1) % p1
    sum2 = (sum2 + h2) % p2
    square2 = (square2 + (h2 * h2) % p2) % p2
    i += 1
  out[0] = (sum1 * 65537 + square1 + rank * 8191) % p1
  out[1] = (sum2 * 1009 + square2 + rank * 131071) % p2
  1

# Append a term-set-unique exact scheme. meta[0]=admitted, [1]=duplicates,
# [2]=capacity rejects. Exactness is deliberately established by the caller.
-> ffacdb_append(bank_u, bank_v, bank_w, bank_rank, bank_fp1, bank_fp2, count, bank_capacity, stride, us, vs, ws, rank, meta) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64 i64[]) i64
  fingerprint = i64[2]
  ffacdb_fingerprint(us, vs, ws, rank, fingerprint)
  duplicate = 0 ## i64
  prior = 0 ## i64
  while prior < count && duplicate == 0
    if bank_rank[prior] == rank && bank_fp1[prior] == fingerprint[0] && bank_fp2[prior] == fingerprint[1]
      prior_u = i64[stride]
      prior_v = i64[stride]
      prior_w = i64[stride]
      i = 0 ## i64
      while i < bank_rank[prior]
        prior_u[i] = bank_u[prior * stride + i]
        prior_v[i] = bank_v[prior * stride + i]
        prior_w[i] = bank_w[prior * stride + i]
        i += 1
      distance = ffpan_term_set_distance_unique(prior_u, prior_v, prior_w, bank_rank[prior], us, vs, ws, rank) ## i64
      if distance == 0
        duplicate = 1
    prior += 1
  if duplicate == 1
    meta[1] = meta[1] + 1
    return count
  if count >= bank_capacity || rank > stride
    meta[2] = meta[2] + 1
    return count
  ffacdb_copy(us, vs, ws, bank_u, bank_v, bank_w, count * stride, rank)
  bank_rank[count] = rank
  bank_fp1[count] = fingerprint[0]
  bank_fp2[count] = fingerprint[1]
  meta[0] = meta[0] + 1
  count + 1

# Generate genuine proper partial-automorphism basis endpoints.  stats:
# generators, raw dependencies, proper relations, full gates, failures,
# source/global quotients, genuine, unique admissions, rank drops,
# density wins, max source distance, elapsed ms.
-> ffacdb_generate_partial(us, vs, ws, rank, n, capacity, bank_u, bank_v, bank_w, bank_rank, bank_fp1, bank_fp2, bank_count, bank_capacity, stride, append_meta, stats) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64[] i64[]) i64
  i = 0 ## i64
  while i < stats.size()
    stats[i] = 0
    i += 1
  workspace = FFPANWorkspace.new(rank, n, capacity)
  transformed_u = workspace.transformed_u()
  transformed_v = workspace.transformed_v()
  transformed_w = workspace.transformed_w()
  deltas = workspace.deltas()
  dependencies = workspace.dependencies()
  basis_rows = workspace.basis_rows()
  basis_coefficients = workspace.basis_coefficients()
  pivot_owners = workspace.pivot_owners()
  work = workspace.work()
  work_coefficients = workspace.work_coefficients()
  ids = workspace.ids()
  raw_u = workspace.raw_u()
  raw_v = workspace.raw_v()
  raw_w = workspace.raw_w()
  endpoint = workspace.endpoint()
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  words = ffpa_tensor_words(n) ## i64
  nullspace_meta = i64[4]
  decoded = i64[4]
  source_density = ffgir_density(us, vs, ws, rank) ## i64
  started = ccall("__w_clock_ms") ## i64
  flat = 0 ## i64
  while flat < ffpan_elementary_count(n)
    ffacdb_expect("elementary decode", ffpan_elementary_decode(n, flat, decoded) == 1)
    built = ffpa_build_deltas_kind(us, vs, ws, rank, n, decoded[0], decoded[1], decoded[2], decoded[3], transformed_u, transformed_v, transformed_w, deltas) ## i64
    ffacdb_expect("delta build", built == words)
    nullity = ffpan_nullspace_into(deltas, rank, words, dependencies, basis_rows, basis_coefficients, pivot_owners, work, work_coefficients, nullspace_meta) ## i64
    ffacdb_expect("nullspace", nullity >= 0 && nullspace_meta[0] + nullity == rank)
    stats[0] = stats[0] + 1
    stable_terms = 0 ## i64
    term = 0 ## i64
    while term < rank
      stable_terms += ffpan_row_zero(deltas, term * words, words)
      term += 1
    nonstable_terms = rank - stable_terms ## i64
    dependency = 0 ## i64
    while dependency < nullity
      stats[1] = stats[1] + 1
      made = ffpan_dependency_ids(dependencies, dependency, rank, ids) ## i64
      if ffpa_relation_exact(deltas, ids, made, words) != 1
        stats[4] = stats[4] + 1
      if ffpa_relation_exact(deltas, ids, made, words) == 1
        selected_nonstable = 0 ## i64
        selected = 0 ## i64
        while selected < made
          if ffpan_row_zero(deltas, ids[selected] * words, words) == 0
            selected_nonstable += 1
          selected += 1
        if selected_nonstable > 0 && selected_nonstable < nonstable_terms
          set_stable = ffpa_selected_image_same_set(us, vs, ws, transformed_u, transformed_v, transformed_w, ids, made) ## i64
          if set_stable == 0
            stats[2] = stats[2] + 1
            ffpan_copy_terms(us, vs, ws, raw_u, raw_v, raw_w, rank)
            selected = 0
            while selected < made
              position = ids[selected] ## i64
              raw_u[position] = transformed_u[position]
              raw_v[position] = transformed_v[position]
              raw_w[position] = transformed_w[position]
              selected += 1
            endpoint_rank = ffpan_parity_compact(raw_u, raw_v, raw_w, rank, out_u, out_v, out_w) ## i64
            full_exact = 0 ## i64
            if endpoint_rank > 0 && endpoint_rank <= capacity
              loaded = ffw_init_terms_cap(endpoint, out_u, out_v, out_w, endpoint_rank, n, capacity, 920001 + n * 10007 + flat * 257 + dependency, 0, 1, 1, 1) ## i64
              if loaded == endpoint_rank && ffw_verify_current_exact(endpoint, n) == 1
                full_exact = 1
                stats[3] = stats[3] + 1
            if full_exact == 0
              stats[4] = stats[4] + 1
            if full_exact == 1
              source_distance = ffpan_term_set_distance_unique(us, vs, ws, rank, out_u, out_v, out_w, endpoint_rank) ## i64
              global_distance = ffpan_term_set_distance_unique(transformed_u, transformed_v, transformed_w, rank, out_u, out_v, out_w, endpoint_rank) ## i64
              if source_distance == 0
                stats[5] = stats[5] + 1
              if source_distance != 0 && global_distance == 0
                stats[6] = stats[6] + 1
              if source_distance != 0 && global_distance != 0
                stats[7] = stats[7] + 1
                before = bank_count ## i64
                bank_count = ffacdb_append(bank_u, bank_v, bank_w, bank_rank, bank_fp1, bank_fp2, bank_count, bank_capacity, stride, out_u, out_v, out_w, endpoint_rank, append_meta)
                if bank_count > before
                  stats[8] = stats[8] + 1
                if endpoint_rank < rank
                  stats[9] = stats[9] + 1
                density = ffgir_density(out_u, out_v, out_w, endpoint_rank) ## i64
                if endpoint_rank == rank && density < source_density
                  stats[10] = stats[10] + 1
                if source_distance > stats[11]
                  stats[11] = source_distance
      dependency += 1
    flat += 1
  stats[12] = ccall("__w_clock_ms") - started
  bank_count

-> ffacdb_append_frontiers(n, rank, capacity, bank_u, bank_v, bank_w, bank_rank, bank_fp1, bank_fp2, bank_count, bank_capacity, stride, append_meta, stats) (i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64[] i64[]) i64
  paths = ffp_frontier_seed_paths(n)
  i = 0 ## i64
  while i < paths.size()
    state = i64[ffw_state_size(capacity)]
    loaded = ffw_load_scheme_cap(state, paths[i], n, capacity, 930001 + n * 1009 + i * 17, 0, 1, 1, 1) ## i64
    stats[0] = stats[0] + 1
    if loaded == rank && ffw_verify_current_exact(state, n) == 1
      stats[1] = stats[1] + 1
      us = i64[capacity]
      vs = i64[capacity]
      ws = i64[capacity]
      exported = ffw_export_current(state, us, vs, ws) ## i64
      ffacdb_expect("frontier export", exported == rank)
      bank_count = ffacdb_append(bank_u, bank_v, bank_w, bank_rank, bank_fp1, bank_fp2, bank_count, bank_capacity, stride, us, vs, ws, rank, append_meta)
    if loaded != rank || ffw_verify_current_exact(state, n) != 1
      stats[2] = stats[2] + 1
    i += 1
  bank_count

-> ffacdb_min_bank_distance(bank_u, bank_v, bank_w, bank_rank, bank_count, stride, us, vs, ws, rank) (i64[] i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64) i64
  best = rank + stride ## i64
  prior_u = i64[stride]
  prior_v = i64[stride]
  prior_w = i64[stride]
  scheme = 0 ## i64
  while scheme < bank_count
    i = 0 ## i64
    while i < bank_rank[scheme]
      prior_u[i] = bank_u[scheme * stride + i]
      prior_v[i] = bank_v[scheme * stride + i]
      prior_w[i] = bank_w[scheme * stride + i]
      i += 1
    distance = ffpan_term_set_distance_unique(prior_u, prior_v, prior_w, bank_rank[scheme], us, vs, ws, rank) ## i64
    if distance < best
      best = distance
    scheme += 1
  best

# Count D3/reversal-canonical collisions with the generating bank.  The basin
# identity is telemetry, not the exactness proof, but it prevents a raw-distant
# symmetry image from being misreported as a new restart door.
-> ffacdb_canonical_matches(bank_u, bank_v, bank_w, bank_rank, bank_count, stride, n, capacity, candidate) (i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  candidate_id = ffbi_best_id(candidate) ## i64
  matches = 0 ## i64
  state = i64[ffw_state_size(capacity)]
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  scheme = 0 ## i64
  while scheme < bank_count
    i = 0 ## i64
    while i < bank_rank[scheme]
      us[i] = bank_u[scheme * stride + i]
      vs[i] = bank_v[scheme * stride + i]
      ws[i] = bank_w[scheme * stride + i]
      i += 1
    loaded = ffw_init_terms_cap(state, us, vs, ws, bank_rank[scheme], n, capacity, 935001 + n * 1009 + scheme, 0, 1, 1, 1) ## i64
    ffacdb_expect("canonical bank gate", loaded == bank_rank[scheme] && ffw_verify_current_exact(state, n) == 1)
    if ffbi_best_id(state) == candidate_id
      matches += 1
    scheme += 1
  matches

-> ffacdb_run(n, restarts, pair_restarts, pair_rounds, publish_enabled, temper_epochs, temper_steps, neighborhood_size) (i64 i64 i64 i64 i64 i64 i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  stride = capacity ## i64
  source_state = i64[ffw_state_size(capacity)]
  source_path = ffp_seed_path(n)
  rank = ffw_load_scheme_cap(source_state, source_path, n, capacity, 940001 + n, 0, 1, 1, 1) ## i64
  ffacdb_expect("source exact", rank == ffp_record(n) && ffw_verify_current_exact(source_state, n) == 1)
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  ffacdb_expect("source export", ffw_export_current(source_state, source_u, source_v, source_w) == rank)
  source_density = ffgir_density(source_u, source_v, source_w, rank) ## i64

  bank_capacity = 512 ## i64
  bank_u = i64[bank_capacity * stride]
  bank_v = i64[bank_capacity * stride]
  bank_w = i64[bank_capacity * stride]
  bank_rank = i64[bank_capacity]
  bank_fp1 = i64[bank_capacity]
  bank_fp2 = i64[bank_capacity]
  append_meta = i64[3]
  bank_count = ffacdb_append(bank_u, bank_v, bank_w, bank_rank, bank_fp1, bank_fp2, 0, bank_capacity, stride, source_u, source_v, source_w, rank, append_meta) ## i64
  partial_stats = i64[13]
  bank_count = ffacdb_generate_partial(source_u, source_v, source_w, rank, n, capacity, bank_u, bank_v, bank_w, bank_rank, bank_fp1, bank_fp2, bank_count, bank_capacity, stride, append_meta, partial_stats)
  frontier_stats = i64[3]
  bank_count = ffacdb_append_frontiers(n, rank, capacity, bank_u, bank_v, bank_w, bank_rank, bank_fp1, bank_fp2, bank_count, bank_capacity, stride, append_meta, frontier_stats)

  code = FFAffineCode.new(bank_u, bank_v, bank_w, bank_rank, bank_count, stride)
  ffacdb_expect("code construction", code.valid() == 1 && code.generator_count() > 0)
  search_meta = i64[13]
  best_rank = code.search(restarts, 12, pair_restarts, pair_rounds, 950001 + n * 1009, search_meta) ## i64
  best_u = i64[capacity]
  best_v = i64[capacity]
  best_w = i64[capacity]
  materialized = code.materialize_best(best_u, best_v, best_w) ## i64
  ffacdb_expect("materialized objective", materialized == best_rank)
  gate = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(gate, best_u, best_v, best_w, best_rank, n, capacity, 960001 + n, 0, 1, 1, 1) ## i64
  full_exact = 0 ## i64
  if loaded == best_rank && ffw_verify_current_exact(gate, n) == 1
    full_exact = 1
  ffacdb_expect("final full n^6 gate", full_exact == 1)
  best_density = ffgir_density(best_u, best_v, best_w, best_rank) ## i64
  source_distance = ffpan_term_set_distance_unique(source_u, source_v, source_w, rank, best_u, best_v, best_w, best_rank) ## i64
  min_bank_distance = ffacdb_min_bank_distance(bank_u, bank_v, bank_w, bank_rank, bank_count, stride, best_u, best_v, best_w, best_rank) ## i64
  canonical_matches = ffacdb_canonical_matches(bank_u, bank_v, bank_w, bank_rank, bank_count, stride, n, capacity, gate) ## i64

  rank_win = 0 ## i64
  density_win = 0 ## i64
  novel_win = 0 ## i64
  if best_rank < rank
    rank_win = 1
  if best_rank == rank && best_density < source_density
    density_win = 1
  if best_rank == rank && best_density == source_density && min_bank_distance >= 16 && canonical_matches == 0
    novel_win = 1
  published = 0 ## i64
  if publish_enabled == 1 && (rank_win == 1 || density_win == 1 || novel_win == 1)
    path = "benchmarks/matmul/metaflip/matmul_" + n.to_s() + "x" + n.to_s() + "_rank" + best_rank.to_s() + "_d" + best_density.to_s() + "_affine_code_gf2.txt" ## String
    dumped = ffw_dump_best(gate, path) ## i64
    ffacdb_expect("publish", dumped == best_rank)
    published = 1
    << "AFFINE_CODE_PUBLISHED path=" + path

  << "AFFINE_CODE_BANK tensor=" + n.to_s() + "x" + n.to_s() + " source=r" + rank.to_s() + "/d" + source_density.to_s() + " generators_scanned=" + partial_stats[0].to_s() + " raw_dependencies=" + partial_stats[1].to_s() + " proper=" + partial_stats[2].to_s() + " full_gates=" + partial_stats[3].to_s() + " failures=" + partial_stats[4].to_s() + " source_quotient=" + partial_stats[5].to_s() + " global_quotient=" + partial_stats[6].to_s() + " genuine=" + partial_stats[7].to_s() + " generated_unique=" + partial_stats[8].to_s() + " generated_rank_drops=" + partial_stats[9].to_s() + " generated_density_wins=" + partial_stats[10].to_s() + " generated_max_distance=" + partial_stats[11].to_s() + " generation_ms=" + partial_stats[12].to_s() + " frontier_paths=" + frontier_stats[0].to_s() + " frontier_exact=" + frontier_stats[1].to_s() + " bank=" + bank_count.to_s() + " duplicates=" + append_meta[1].to_s()
  << "AFFINE_CODE_SEARCH tensor=" + n.to_s() + "x" + n.to_s() + " coordinates=" + code.coordinate_count().to_s() + " zero_generators=" + code.generator_count().to_s() + " code_dimension=" + code.dimension().to_s() + " zero_rows=" + code.zero_rows().to_s() + " duplicate_rows=" + code.duplicate_rows().to_s() + " restarts=" + search_meta[0].to_s() + " perturb_toggles=" + search_meta[1].to_s() + " single_probes=" + search_meta[2].to_s() + " single_accepts=" + search_meta[3].to_s() + " pair_probes=" + search_meta[4].to_s() + " pair_accepts=" + search_meta[5].to_s() + " local_minima=" + search_meta[6].to_s() + " max_local_rank=" + search_meta[7].to_s() + " best=r" + best_rank.to_s() + "/d" + best_density.to_s() + " source_distance=" + source_distance.to_s() + " min_bank_distance=" + min_bank_distance.to_s() + " canonical_matches=" + canonical_matches.to_s() + " best_updates=" + search_meta[11].to_s() + " full_exact=" + full_exact.to_s() + " rank_win=" + rank_win.to_s() + " density_win=" + density_win.to_s() + " novel_win=" + novel_win.to_s() + " published=" + published.to_s() + " search_ms=" + search_meta[12].to_s()
  temper_win = 0 ## i64
  if temper_epochs > 0
    temper_meta = i64[20]
    tempered_rank = code.search_tempered(temper_epochs, temper_steps, 32768, 64, neighborhood_size, 970001 + n * 101, temper_meta) ## i64
    tempered_u = i64[capacity]
    tempered_v = i64[capacity]
    tempered_w = i64[capacity]
    tempered_materialized = code.materialize_best(tempered_u, tempered_v, tempered_w) ## i64
    ffacdb_expect("tempered materialize", tempered_materialized == tempered_rank)
    tempered_gate = i64[ffw_state_size(capacity)]
    tempered_loaded = ffw_init_terms_cap(tempered_gate, tempered_u, tempered_v, tempered_w, tempered_rank, n, capacity, 975001 + n, 0, 1, 1, 1) ## i64
    tempered_exact = 0 ## i64
    if tempered_loaded == tempered_rank && ffw_verify_current_exact(tempered_gate, n) == 1
      tempered_exact = 1
    ffacdb_expect("tempered final n^6 gate", tempered_exact == 1)
    tempered_density = ffgir_density(tempered_u, tempered_v, tempered_w, tempered_rank) ## i64
    tempered_source_distance = ffpan_term_set_distance_unique(source_u, source_v, source_w, rank, tempered_u, tempered_v, tempered_w, tempered_rank) ## i64
    tempered_min_bank = ffacdb_min_bank_distance(bank_u, bank_v, bank_w, bank_rank, bank_count, stride, tempered_u, tempered_v, tempered_w, tempered_rank) ## i64
    escaped_strict = 0 ## i64
    if tempered_rank < best_rank || (tempered_rank == best_rank && tempered_density < best_density)
      escaped_strict = 1
    if tempered_rank < rank || (tempered_rank == rank && tempered_density < source_density)
      temper_win = 1
    << "AFFINE_CODE_TEMPER tensor=" + n.to_s() + "x" + n.to_s() + " epochs=" + temper_meta[0].to_s() + " steps/epoch=" + temper_steps.to_s() + " k=" + neighborhood_size.to_s() + " proposals=" + temper_meta[1].to_s() + " improving_accepts=" + temper_meta[2].to_s() + " uphill_accepts=" + temper_meta[3].to_s() + " rejects=" + temper_meta[4].to_s() + " max_rank=" + temper_meta[5].to_s() + " single_probes=" + temper_meta[6].to_s() + " single_accepts=" + temper_meta[7].to_s() + " neighborhoods=" + temper_meta[8].to_s() + " combinations=" + temper_meta[9].to_s() + " k_accepts=" + temper_meta[10].to_s() + " best=r" + tempered_rank.to_s() + "/d" + tempered_density.to_s() + " source_distance=" + tempered_source_distance.to_s() + " min_bank_distance=" + tempered_min_bank.to_s() + " best_updates=" + temper_meta[14].to_s() + " final=r" + temper_meta[16].to_s() + "/d" + temper_meta[17].to_s() + " escaped_strict=" + escaped_strict.to_s() + " objective_win=" + temper_win.to_s() + " full_exact=" + tempered_exact.to_s() + " evaluations/s=" + temper_meta[19].to_s() + " elapsed_ms=" + temper_meta[15].to_s()
  rank_win + density_win + novel_win + temper_win

args = argv()
only_n = 0 ## i64
restarts = 24 ## i64
pair_restarts = 6 ## i64
pair_rounds = 2 ## i64
publish_enabled = 0 ## i64
temper_epochs = 0 ## i64
temper_steps = 128 ## i64
neighborhood_size = 12 ## i64
if args.size() > 0
  only_n = args[0].to_i()
if args.size() > 1
  restarts = args[1].to_i()
if args.size() > 2
  pair_restarts = args[2].to_i()
if args.size() > 3
  pair_rounds = args[3].to_i()
if args.size() > 4
  publish_enabled = args[4].to_i()
if args.size() > 5
  temper_epochs = args[5].to_i()
if args.size() > 6
  temper_steps = args[6].to_i()
if args.size() > 7
  neighborhood_size = args[7].to_i()
ffacdb_expect("arguments", (only_n == 0 || (only_n >= 5 && only_n <= 7)) && restarts >= 1 && restarts <= 10000 && pair_restarts >= 0 && pair_restarts <= restarts && pair_rounds >= 0 && pair_rounds <= 16 && (publish_enabled == 0 || publish_enabled == 1) && temper_epochs >= 0 && temper_epochs <= 10000 && temper_steps >= 1 && temper_steps <= 1000000 && neighborhood_size >= 1 && neighborhood_size <= 16)

wins = 0 ## i64
n = 5 ## i64
while n <= 7
  if only_n == 0 || only_n == n
    wins += ffacdb_run(n, restarts, pair_restarts, pair_rounds, publish_enabled, temper_epochs, temper_steps, neighborhood_size)
  n += 1
<< "flipfleet_affine_code_descent_bench: done wins=" + wins.to_s()

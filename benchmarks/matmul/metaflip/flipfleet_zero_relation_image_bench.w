# Bounded support-guided audit of linear archive-zero images.
#
# For each nonleader live frontier B, form Z=leader XOR B.  On each of the
# three rank-one factor spaces, choose the six raw coordinates occurring most
# often in Z and test delete(source), fold(source->target), and elementary
# shear(source->target).  Every candidate is exact algebraically; only the
# lexicographic winner is reconstructed and n^6-gated.
#
# Usage: flipfleet_zero_relation_image_bench [only_n=0] [top=6] [publish=0]

use flipfleet_zero_relation_image
use flipfleet_profiles
use flipfleet_global_isotropy

-> ffzrib_expect(label, condition) (String bool) i64
  if !condition
    << "ZERO_RELATION_IMAGE_BENCH_FAIL " + label
    exit(1)
  1

-> ffzrib_copy(source_u, source_v, source_w, target_u, target_v, target_w, count) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    target_u[i] = source_u[i]
    target_v[i] = source_v[i]
    target_w[i] = source_w[i]
    i += 1
  count

# stats: relations, relation terms, relation failures, maps, zero images,
# duplicate cancellations, rank wins, density wins, rank-neutral changed,
# best rank/density/distance, best relation/factor/op/source/target/image rank,
# final gate, final zero-image proof, elapsed ms.
-> ffzrib_run(n, top_count, publish_enabled) (i64 i64 i64) i64
  paths = ffp_frontier_seed_paths(n)
  capacity = ffw_default_capacity(n) ## i64
  leader_state = i64[ffw_state_size(capacity)]
  leader_rank = ffw_load_scheme_cap(leader_state, paths[0], n, capacity, 991001 + n, 0, 1, 1, 1) ## i64
  ffzrib_expect("leader exact", leader_rank == ffp_record(n) && ffw_verify_current_exact(leader_state, n) == 1)
  leader_u = i64[capacity]
  leader_v = i64[capacity]
  leader_w = i64[capacity]
  ffzrib_expect("leader export", ffw_export_current(leader_state, leader_u, leader_v, leader_w) == leader_rank)
  leader_density = ffgir_density(leader_u, leader_v, leader_w, leader_rank) ## i64

  raw_u = i64[capacity * 3]
  raw_v = i64[capacity * 3]
  raw_w = i64[capacity * 3]
  relation_u = i64[capacity * 2]
  relation_v = i64[capacity * 2]
  relation_w = i64[capacity * 2]
  image_u = i64[capacity * 2]
  image_v = i64[capacity * 2]
  image_w = i64[capacity * 2]
  best_image_u = i64[capacity * 2]
  best_image_v = i64[capacity * 2]
  best_image_w = i64[capacity * 2]
  candidate_u = i64[capacity * 3]
  candidate_v = i64[capacity * 3]
  candidate_w = i64[capacity * 3]
  other_u = i64[capacity]
  other_v = i64[capacity]
  other_w = i64[capacity]
  compact_meta = i64[2]
  score = i64[4]
  stats = i64[20]
  stats[9] = leader_rank
  stats[10] = leader_density
  stats[12] = 0 - 1
  stats[13] = 0 - 1
  stats[14] = 0 - 1
  stats[15] = 0 - 1
  stats[16] = 0 - 1
  stats[17] = 0
  started = ccall("__w_clock_ms") ## i64
  relation_id = 1 ## i64
  while relation_id < paths.size()
    other_state = i64[ffw_state_size(capacity)]
    other_rank = ffw_load_scheme_cap(other_state, paths[relation_id], n, capacity, 991101 + n * 1009 + relation_id, 0, 1, 1, 1) ## i64
    ffzrib_expect("archive endpoint exact", other_rank == leader_rank && ffw_verify_current_exact(other_state, n) == 1)
    ffzrib_expect("archive endpoint export", ffw_export_current(other_state, other_u, other_v, other_w) == other_rank)
    relation_rank = ffzri_relation(leader_u, leader_v, leader_w, leader_rank, other_u, other_v, other_w, other_rank, raw_u, raw_v, raw_w, relation_u, relation_v, relation_w, compact_meta) ## i64
    stats[0] = stats[0] + 1
    stats[1] = stats[1] + relation_rank
    if relation_rank < 1 || ffzri_zero_tensor(relation_u, relation_v, relation_w, relation_rank, n) != 1
      stats[2] = stats[2] + 1
    ffzrib_expect("archive difference zero", relation_rank > 0 && stats[2] == 0)
    factor = 0 ## i64
    while factor < 3
      selected = i64[top_count]
      selected_count = ffzri_top_coordinates(relation_u, relation_v, relation_w, relation_rank, factor, n * n, top_count, selected) ## i64
      s = 0 ## i64
      while s < selected_count
        source = selected[s] ## i64
        operation = 2 ## i64
        image_rank = ffzri_map_relation(relation_u, relation_v, relation_w, relation_rank, factor, operation, source, 0, raw_u, raw_v, raw_w, image_u, image_v, image_w, compact_meta) ## i64
        stats[3] = stats[3] + 1
        stats[4] = stats[4] + compact_meta[0]
        stats[5] = stats[5] + compact_meta[1]
        if image_rank >= 0
          ffzri_score(leader_u, leader_v, leader_w, leader_rank, leader_density, image_u, image_v, image_w, image_rank, score)
          if score[0] < leader_rank
            stats[6] = stats[6] + 1
          if score[0] == leader_rank && score[1] < leader_density
            stats[7] = stats[7] + 1
          if score[0] == leader_rank && score[2] > 0
            stats[8] = stats[8] + 1
          better = 0 ## i64
          if score[0] < stats[9]
            better = 1
          if score[0] == stats[9] && score[1] < stats[10]
            better = 1
          if score[0] == stats[9] && score[1] == stats[10] && score[2] > stats[11]
            better = 1
          if better == 1
            stats[9] = score[0]
            stats[10] = score[1]
            stats[11] = score[2]
            stats[12] = relation_id
            stats[13] = factor
            stats[14] = operation
            stats[15] = source
            stats[16] = 0
            stats[17] = image_rank
            ffzrib_copy(image_u, image_v, image_w, best_image_u, best_image_v, best_image_w, image_rank)
        t = 0 ## i64
        while t < selected_count
          target = selected[t] ## i64
          if target != source
            operation = 1
            while operation <= 3
              if operation != 2
                image_rank = ffzri_map_relation(relation_u, relation_v, relation_w, relation_rank, factor, operation, source, target, raw_u, raw_v, raw_w, image_u, image_v, image_w, compact_meta)
                stats[3] = stats[3] + 1
                stats[4] = stats[4] + compact_meta[0]
                stats[5] = stats[5] + compact_meta[1]
                if image_rank >= 0
                  ffzri_score(leader_u, leader_v, leader_w, leader_rank, leader_density, image_u, image_v, image_w, image_rank, score)
                  if score[0] < leader_rank
                    stats[6] = stats[6] + 1
                  if score[0] == leader_rank && score[1] < leader_density
                    stats[7] = stats[7] + 1
                  if score[0] == leader_rank && score[2] > 0
                    stats[8] = stats[8] + 1
                  better = 0
                  if score[0] < stats[9]
                    better = 1
                  if score[0] == stats[9] && score[1] < stats[10]
                    better = 1
                  if score[0] == stats[9] && score[1] == stats[10] && score[2] > stats[11]
                    better = 1
                  if better == 1
                    stats[9] = score[0]
                    stats[10] = score[1]
                    stats[11] = score[2]
                    stats[12] = relation_id
                    stats[13] = factor
                    stats[14] = operation
                    stats[15] = source
                    stats[16] = target
                    stats[17] = image_rank
                    ffzrib_copy(image_u, image_v, image_w, best_image_u, best_image_v, best_image_w, image_rank)
              operation += 1
          t += 1
        s += 1
      factor += 1
    relation_id += 1

  candidate_rank = leader_rank ## i64
  if stats[12] >= 0
    candidate_rank = ffzri_toggle_image(leader_u, leader_v, leader_w, leader_rank, best_image_u, best_image_v, best_image_w, stats[17], raw_u, raw_v, raw_w, candidate_u, candidate_v, candidate_w, compact_meta)
  if stats[12] < 0
    ffzrib_copy(leader_u, leader_v, leader_w, candidate_u, candidate_v, candidate_w, leader_rank)
  ffzrib_expect("score/materialize rank", candidate_rank == stats[9])
  gate_capacity = capacity ## i64
  if candidate_rank > gate_capacity
    gate_capacity = candidate_rank + 8
  gate = i64[ffw_state_size(gate_capacity)]
  loaded = ffw_init_terms_cap(gate, candidate_u, candidate_v, candidate_w, candidate_rank, n, gate_capacity, 992001 + n, 0, 1, 1, 1) ## i64
  if loaded == candidate_rank && ffw_verify_current_exact(gate, n) == 1
    stats[18] = 1
  if stats[12] >= 0 && ffzri_zero_tensor(best_image_u, best_image_v, best_image_w, stats[17], n) == 1
    stats[19] = 1
  ffzrib_expect("best mapped relation zero", stats[12] < 0 || stats[19] == 1)
  ffzrib_expect("winner full gate", stats[18] == 1)
  stats_elapsed = ccall("__w_clock_ms") - started ## i64
  published = 0 ## i64
  objective_win = 0 ## i64
  if stats[9] < leader_rank || (stats[9] == leader_rank && stats[10] < leader_density)
    objective_win = 1
  if publish_enabled == 1 && objective_win == 1
    path = "benchmarks/matmul/metaflip/matmul_" + n.to_s() + "x" + n.to_s() + "_rank" + stats[9].to_s() + "_d" + stats[10].to_s() + "_zero_relation_image_gf2.txt" ## String
    dumped = ffw_dump_best(gate, path) ## i64
    ffzrib_expect("publish", dumped == stats[9])
    published = 1
    << "ZERO_RELATION_IMAGE_PUBLISHED path=" + path
  << "ZERO_RELATION_IMAGE_SUMMARY tensor=" + n.to_s() + "x" + n.to_s() + " source=r" + leader_rank.to_s() + "/d" + leader_density.to_s() + " archive=" + paths.size().to_s() + " relations=" + stats[0].to_s() + " relation_terms=" + stats[1].to_s() + " relation_failures=" + stats[2].to_s() + " maps=" + stats[3].to_s() + " zero_terms=" + stats[4].to_s() + " duplicate_cancellations=" + stats[5].to_s() + " rank_wins=" + stats[6].to_s() + " density_wins=" + stats[7].to_s() + " rank_neutral_changed=" + stats[8].to_s() + " best=r" + stats[9].to_s() + "/d" + stats[10].to_s() + " distance=" + stats[11].to_s() + " image_rank=" + stats[17].to_s() + " map=parent" + stats[12].to_s() + ":factor" + stats[13].to_s() + ":op" + stats[14].to_s() + ":" + stats[15].to_s() + ">" + stats[16].to_s() + " image_zero=" + stats[19].to_s() + " full_exact=" + stats[18].to_s() + " objective_win=" + objective_win.to_s() + " published=" + published.to_s() + " elapsed_ms=" + stats_elapsed.to_s()
  objective_win

args = argv()
only_n = 0 ## i64
top_count = 6 ## i64
publish_enabled = 0 ## i64
if args.size() > 0
  only_n = args[0].to_i()
if args.size() > 1
  top_count = args[1].to_i()
if args.size() > 2
  publish_enabled = args[2].to_i()
ffzrib_expect("arguments", (only_n == 0 || only_n == 6 || only_n == 7) && top_count >= 2 && top_count <= 12 && (publish_enabled == 0 || publish_enabled == 1))
wins = 0 ## i64
n = 6 ## i64
while n <= 7
  if only_n == 0 || only_n == n
    wins += ffzrib_run(n, top_count, publish_enabled)
  n += 1
<< "flipfleet_zero_relation_image_bench: done wins=" + wins.to_s()

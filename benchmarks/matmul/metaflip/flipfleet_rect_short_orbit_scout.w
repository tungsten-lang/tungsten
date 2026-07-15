# Bounded short-word GL scout for a third exact 4x4x5 frontier.
#
# For every deterministic two- and three-generator image of SOURCE, audit the
# complete archive-difference nullspace against both checked-in 4x4x5 doors.
# Proper relations are materialized and fully reconstructed.  Only the best
# rank/density/novelty child and its generating image are written.
#
# Usage:
#   flipfleet_rect_short_orbit_scout SOURCE COUNT OUTPUT_PREFIX

use flipfleet_rect_archive_nullspace

arguments = argv()
if arguments.size() != 3
  << "usage: flipfleet_rect_short_orbit_scout SOURCE COUNT OUTPUT_PREFIX"
  exit(2)

source_path = arguments[0]
count = arguments[1].to_i() ## i64
prefix = arguments[2]
if count < 1 || count > 4096
  << "RECT_SHORT_ORBIT_ERROR code=count"
  exit(2)

root = "benchmarks/matmul/metaflip/"
source = ffbc_load_exact(source_path, 4, 4, 5, 128)
d628 = ffbc_load_exact(root + "matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt", 4, 4, 5, 128)
d919 = ffbc_load_exact(root + "matmul_4x4x5_rank60_d919_gf2.txt", 4, 4, 5, 128)
if source == nil || d628 == nil || d919 == nil || ffbc_verify_exact(source) != 1 || ffbc_verify_exact(d628) != 1 || ffbc_verify_exact(d919) != 1
  << "RECT_SHORT_ORBIT_ERROR code=seed"
  exit(1)

audited = 0 ## i64
proper_pairs = 0 ## i64
children = 0 ## i64
rank_drops = 0 ## i64
max_nullity = 0 ## i64
best = nil
best_image = nil
best_rank = 1000000 ## i64
best_density = 1000000 ## i64
best_novelty = 0 - 1 ## i64
best_seed = 0 ## i64
best_moves = 0 ## i64
best_anchor = 0 ## i64
best_difference = 0 ## i64
best_nullity = 0 ## i64
best_selected = 0 ## i64
best_mix_a = 0 ## i64
best_mix_b = 0 ## i64

seed = 1 ## i64
while seed <= count
  moves = 2 ## i64
  while moves <= 3
    image = fflc_sparse_leaf_image(source, seed * 104729 + moves * 65537, moves)
    if image != nil && ffbc_verify_exact(image) == 1 && fflc_term_set_distance(source, image) > 0
      anchor_index = 0 ## i64
      while anchor_index < 2
        anchor = d628
        if anchor_index == 1
          anchor = d919
        meta = i64[9]
        child = ffran_crossover(anchor, image, 4096, meta)
        audited += 1
        if meta[1] > max_nullity
          max_nullity = meta[1]
        if meta[1] > 1
          proper_pairs += 1
        if child != nil && meta[8] == 1
          children += 1
          child_rank = child.rank() ## i64
          child_density = fflc_density(child) ## i64
          distance_628 = fflc_term_set_distance(child, d628) ## i64
          distance_919 = fflc_term_set_distance(child, d919) ## i64
          novelty = distance_628 ## i64
          if distance_919 < novelty
            novelty = distance_919
          if child_rank < 60
            rank_drops += 1
          improved = 0 ## i64
          if child_rank < best_rank
            improved = 1
          if child_rank == best_rank && child_density < best_density
            improved = 1
          if child_rank == best_rank && child_density == best_density && novelty > best_novelty
            improved = 1
          if improved == 1
            best = fflc_clone(child)
            best_image = fflc_clone(image)
            best_rank = child_rank
            best_density = child_density
            best_novelty = novelty
            best_seed = seed
            best_moves = moves
            best_anchor = anchor_index
            best_difference = meta[0]
            best_nullity = meta[1]
            best_selected = meta[5]
            best_mix_a = meta[6]
            best_mix_b = meta[7]
        anchor_index += 1
    moves += 1
  seed += 1

if best == nil || best_image == nil
  << "RECT_SHORT_ORBIT_RESULT source=" + source_path + " words=" + count.to_s() + " audited=" + audited.to_s() + " proper_pairs=" + proper_pairs.to_s() + " children=0 rank_drops=0 max_nullity=" + max_nullity.to_s()
  exit(0)

image_path = prefix + "_image.txt"
child_path = prefix + "_child.txt"
if ffbc_write(image_path, best_image) != best_image.rank() || ffbc_write(child_path, best) != best.rank()
  << "RECT_SHORT_ORBIT_ERROR code=write"
  exit(1)
reparsed = ffbc_load_exact(child_path, 4, 4, 5, 128)
if reparsed == nil || reparsed.rank() != best.rank() || ffbc_verify_exact(reparsed) != 1 || fflc_term_set_distance(reparsed, best) != 0
  << "RECT_SHORT_ORBIT_ERROR code=reparse"
  exit(1)

audit_628 = i64[9]
audit_919 = i64[9]
unused_628 = ffran_crossover(best, d628, 4096, audit_628)
unused_919 = ffran_crossover(best, d919, 4096, audit_919)
anchor_name = "d628"
if best_anchor == 1
  anchor_name = "d919"
<< "RECT_SHORT_ORBIT_RESULT source=" + source_path + " words=" + count.to_s() + " audited=" + audited.to_s() + " proper_pairs=" + proper_pairs.to_s() + " children=" + children.to_s() + " rank_drops=" + rank_drops.to_s() + " max_nullity=" + max_nullity.to_s() + " best_rank=" + best.rank().to_s() + " best_density=" + fflc_density(best).to_s() + " distance_source=" + fflc_term_set_distance(best, source).to_s() + " distance_d628=" + fflc_term_set_distance(best, d628).to_s() + " distance_d919=" + fflc_term_set_distance(best, d919).to_s() + " seed=" + best_seed.to_s() + " generators=" + best_moves.to_s() + " splice_anchor=" + anchor_name + " parent_difference=" + best_difference.to_s() + " parent_nullity=" + best_nullity.to_s() + " selected=" + best_selected.to_s() + " mix=" + best_mix_a.to_s() + "/" + best_mix_b.to_s() + " child_vs_d628_nullity=" + audit_628[1].to_s() + " child_vs_d919_nullity=" + audit_919[1].to_s() + " exact=1 reparsed=1 image=" + image_path + " child=" + child_path

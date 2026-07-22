# Pareto audit for the complete weighted Strassen GL(2,2)^3 orbit.
#
# The exhaustive rank-247 discovery benchmark chooses one density-first
# winner.  This companion retains all exact rank-247 recipes and compares
# density (lower), equal-factor pairs (higher), and symmetric term-set distance
# from the checked-in density leader (higher).  It writes three independently
# reloaded candidates under /tmp: the density, connectivity, and distance
# extrema, suppressing duplicate choices.

use flipfleet_outer_isotropy

-> ffoip_expect(label, condition) (String bool) i64
  if condition
    return 1
  << "OUTER_ISOTROPY_PARETO_FAIL " + label
  exit(1)
  0

-> ffoip_choose(current, candidate, densities, pairs, distances, role) (i64 i64 i64[] i64[] i64[] i64) i64
  if current < 0
    return candidate
  better = 0 ## i64
  if role == 0
    if densities[candidate] < densities[current]
      better = 1
    elsif densities[candidate] == densities[current] && pairs[candidate] > pairs[current]
      better = 1
    elsif densities[candidate] == densities[current] && pairs[candidate] == pairs[current] && distances[candidate] > distances[current]
      better = 1
  elsif role == 1
    if pairs[candidate] > pairs[current]
      better = 1
    elsif pairs[candidate] == pairs[current] && densities[candidate] < densities[current]
      better = 1
    elsif pairs[candidate] == pairs[current] && densities[candidate] == densities[current] && distances[candidate] > distances[current]
      better = 1
  else
    if distances[candidate] > distances[current]
      better = 1
    elsif distances[candidate] == distances[current] && densities[candidate] < densities[current]
      better = 1
    elsif distances[candidate] == distances[current] && densities[candidate] == densities[current] && pairs[candidate] > pairs[current]
      better = 1
  if better == 1
    return candidate
  current

-> ffoip_write_reload(candidate, code_i, code_j, code_k, mask, density, pairs, distance, slot, output_root) (FFBCScheme i64 i64 i64 i64 i64 i64 i64 i64 String) i64
  path = output_root + "matmul_7x7_rank247_d" + density.to_s() + "_outer_isotropy_c" + code_i.to_s() + code_j.to_s() + code_k.to_s() + "_m" + mask.to_s() + "_gf2.txt"
  ffoip_expect("write selection " + slot.to_s(), ffbc_write(path, candidate) == 247)
  reloaded = ffbc_load_exact(path, 7, 7, 7, 320)
  ffoip_expect("reparse selection " + slot.to_s(), reloaded != nil && reloaded.rank() == 247 && ffbc_verify_exact(reloaded) == 1 && fflc_equal(reloaded, candidate) == 1)
  << "OUTER_ISOTROPY_PARETO_SELECT slot=" + slot.to_s() + " density=" + density.to_s() + " pairs=" + pairs.to_s() + " distance=" + distance.to_s() + " code=" + code_i.to_s() + "," + code_j.to_s() + "," + code_k.to_s() + " mask=" + mask.to_s() + " zero=" + candidate.compose_zero_terms().to_s() + " parity=" + candidate.compose_parity_reduction().to_s() + " output=" + path
  1

av = argv()
if av.size() > 1 || (av.size() == 1 && av[0] != "publish")
  << "usage: outer-isotropy-pareto [publish]"
  exit(1)
root = "benchmarks/matmul/metaflip/"
output_root = "/tmp/"
if av.size() == 1
  output_root = root
leaf_paths = ["matmul_3x3_rank23_d139_gf2.txt",
              "matmul_3x3x4_rank29_gf2.txt",
              "matmul_3x4x4_rank38_gf2.txt",
              "matmul_4x4_rank47_d450_gf2.txt"]
leaf_ns = i64[4]
leaf_ms = i64[4]
leaf_ps = i64[4]
leaf_ns[0] = 3
leaf_ms[0] = 3
leaf_ps[0] = 3
leaf_ns[1] = 3
leaf_ms[1] = 3
leaf_ps[1] = 4
leaf_ns[2] = 3
leaf_ms[2] = 4
leaf_ps[2] = 4
leaf_ns[3] = 4
leaf_ms[3] = 4
leaf_ps[3] = 4
leaves = []
i = 0 ## i64
while i < 4
  leaf = ffbc_load_exact(root + leaf_paths[i], leaf_ns[i], leaf_ms[i], leaf_ps[i], 128)
  ffoip_expect("load leaf " + i.to_s(), leaf != nil)
  leaves.push(leaf)
  i += 1

outer = ffbc_load_exact(root + "matmul_2x2_rank7_strassen_gf2.txt", 2, 2, 2, 16)
leader = ffbc_load_exact(root + "matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt", 7, 7, 7, 320)
ffoip_expect("load outer/leader", outer != nil && leader != nil && leader.rank() == 247)

# First recover all 480 formula-minimizing recipes.
tie_ci = i64[1728]
tie_cj = i64[1728]
tie_ck = i64[1728]
tie_mask = i64[1728]
tie_count = 0 ## i64
best_formula = 1 << 30 ## i64
ci = 0 ## i64
while ci < 6
  cj = 0 ## i64
  while cj < 6
    ck = 0 ## i64
    while ck < 6
      image = ffois_image(outer, ci, cj, ck)
      ffoip_expect("exact image", image != nil && ffbc_verify_exact(image) == 1)
      mask = 0 ## i64
      while mask < 8
        score = ffbc_score_allocation(image, ffois_alloc(mask, 0), ffois_alloc(mask, 1), ffois_alloc(mask, 2), leaves) ## i64
        if score > 0 && score < best_formula
          best_formula = score
          tie_count = 0
        if score == best_formula
          tie_ci[tie_count] = ci
          tie_cj[tie_count] = cj
          tie_ck[tie_count] = ck
          tie_mask[tie_count] = mask
          tie_count += 1
        mask += 1
      ck += 1
    cj += 1
  ci += 1

ffoip_expect("known nominal frontier", best_formula == 248 && tie_count == 480)

schemes = []
densities = i64[tie_count]
pairs = i64[tie_count]
distances = i64[tie_count]
codes_i = i64[tie_count]
codes_j = i64[tie_count]
codes_k = i64[tie_count]
masks = i64[tie_count]
rank247 = 0 ## i64
mapped_zero = 0 ## i64
parity_cancel = 0 ## i64
t = 0 ## i64
while t < tie_count
  image = ffois_image(outer, tie_ci[t], tie_cj[t], tie_ck[t])
  candidate = ffbc_compose(image, ffois_alloc(tie_mask[t], 0), ffois_alloc(tie_mask[t], 1), ffois_alloc(tie_mask[t], 2), leaves)
  ffoip_expect("exact tie", candidate != nil && ffbc_verify_exact(candidate) == 1)
  if candidate.rank() == 247
    schemes.push(candidate)
    densities[rank247] = fflc_density(candidate)
    pairs[rank247] = fflc_equal_factor_pairs(candidate)
    distances[rank247] = fflc_term_set_distance(leader, candidate)
    codes_i[rank247] = tie_ci[t]
    codes_j[rank247] = tie_cj[t]
    codes_k[rank247] = tie_ck[t]
    masks[rank247] = tie_mask[t]
    if candidate.compose_zero_terms() > 0
      mapped_zero += 1
    if candidate.compose_parity_reduction() > 0
      parity_cancel += 1
    rank247 += 1
  t += 1

ffoip_expect("rank247 exists", rank247 > 0 && schemes.size() == rank247)

# Count exact term-set representatives separately from recipes.  Forty-eight
# endpoints are small enough that the authoritative symmetric-distance check
# is preferable to a probabilistic hash.
unique = i64[rank247]
unique_count = 0 ## i64
i = 0
while i < rank247
  duplicate = 0 ## i64
  j = 0 ## i64
  while j < i && duplicate == 0
    if unique[j] == 1 && fflc_term_set_distance(schemes[j], schemes[i]) == 0
      duplicate = 1
    j += 1
  if duplicate == 0
    unique[i] = 1
    unique_count += 1
  i += 1

# Pareto flags over recipe endpoints.  Duplicated recipes are retained in the
# raw frontier count; the greedy saved bank below is de-duplicated exactly.
pareto = i64[rank247]
pareto_count = 0 ## i64
i = 0
while i < rank247
  dominated = 0 ## i64
  j = 0 ## i64
  while j < rank247 && dominated == 0
    if j != i && densities[j] <= densities[i] && pairs[j] >= pairs[i] && distances[j] >= distances[i]
      if densities[j] < densities[i] || pairs[j] > pairs[i] || distances[j] > distances[i]
        dominated = 1
    j += 1
  if dominated == 0
    pareto[i] = 1
    pareto_count += 1
    << "OUTER_ISOTROPY_PARETO_ROW index=" + i.to_s() + " density=" + densities[i].to_s() + " pairs=" + pairs[i].to_s() + " distance=" + distances[i].to_s() + " code=" + codes_i[i].to_s() + "," + codes_j[i].to_s() + "," + codes_k[i].to_s() + " mask=" + masks[i].to_s()
  i += 1

density_pick = 0 - 1 ## i64
pair_pick = 0 - 1 ## i64
distance_pick = 0 - 1 ## i64
i = 0
while i < rank247
  if pareto[i] == 1
    density_pick = ffoip_choose(density_pick, i, densities, pairs, distances, 0)
    pair_pick = ffoip_choose(pair_pick, i, densities, pairs, distances, 1)
    distance_pick = ffoip_choose(distance_pick, i, densities, pairs, distances, 2)
  i += 1

selected = i64[3]
s = 0 ## i64
while s < 3
  selected[s] = 0 - 1
  s += 1
selected[0] = density_pick

# Farthest-point sampling inside the Pareto set.  This deliberately optimizes
# actual term-set separation after choosing the density/connectivity/distance
# extreme, so equal metric triples still provide distinct restart doors.
s = 1
while s < 3
  pick = 0 - 1 ## i64
  pick_separation = 0 - 1 ## i64
  i = 0
  while i < rank247
    if pareto[i] == 1
      separation = 1 << 30 ## i64
      prior = 0 ## i64
      duplicate = 0 ## i64
      while prior < s
        d = fflc_term_set_distance(schemes[selected[prior]], schemes[i]) ## i64
        if d == 0
          duplicate = 1
        if d < separation
          separation = d
        prior += 1
      if duplicate == 0
        if separation > pick_separation
          pick = i
          pick_separation = separation
        elsif separation == pick_separation && pick >= 0
          pick = ffoip_choose(pick, i, densities, pairs, distances, 0)
    i += 1
  if pick < 0
    s = 3
  else
    selected[s] = pick
    s += 1

selected_count = 0 ## i64
s = 0
while s < 3
  index = selected[s] ## i64
  if index >= 0
    selected_count += ffoip_write_reload(schemes[index], codes_i[index], codes_j[index], codes_k[index], masks[index], densities[index], pairs[index], distances[index], s, output_root)
  s += 1

bank_min_distance = 1 << 30 ## i64
i = 0
while i < selected_count
  j = i + 1
  while j < selected_count
    distance = fflc_term_set_distance(schemes[selected[i]], schemes[selected[j]]) ## i64
    if distance < bank_min_distance
      bank_min_distance = distance
    j += 1
  i += 1
if selected_count < 2
  bank_min_distance = 0
<< "OUTER_ISOTROPY_PARETO_SUMMARY formula_ties=" + tie_count.to_s() + " rank247_recipes=" + rank247.to_s() + " rank247_unique=" + unique_count.to_s() + " pareto_recipes=" + pareto_count.to_s() + " mapped_zero=" + mapped_zero.to_s() + " parity_cancel=" + parity_cancel.to_s() + " selected=" + selected_count.to_s() + " bank_min_distance=" + bank_min_distance.to_s() + " publish=" + (av.size() == 1).to_s()

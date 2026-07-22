use flipfleet_rect_global_isotropy
use flipfleet_rect_profiles

-> ffrfgpt_expect(label, condition) i64
  if condition == false || condition == 0
    << "FAIL " + label
    exit(1)
  1

labels = ["2x4x5", "3x4x6", "3x4x7", "4x4x5", "4x4x6", "4x5x6", "4x5x7", "4x5x8", "4x6x7", "4x6x8", "5x6x7"]
densities = i64[11]
distances = i64[11]
densities[0] = 222
densities[1] = 488
densities[2] = 519
densities[3] = 628
densities[4] = 690
densities[5] = 907
densities[6] = 1089
densities[7] = 1283
densities[8] = 1406
densities[9] = 1560
densities[10] = 1875
distances[0] = 52
distances[1] = 108
distances[2] = 124
distances[3] = 120
distances[4] = 144
distances[5] = 180
distances[6] = 208
distances[7] = 236
distances[8] = 246
distances[9] = 280
distances[10] = 300

i = 0 ## i64
while i < labels.size()
  label = labels[i]
  n = ffrp_n(label) ## i64
  m = ffrp_m(label) ## i64
  p = ffrp_p(label) ## i64
  primary = ffbc_load_exact(ffrp_seed_rel(n,m,p), n, m, p, 512)
  legacy = ffbc_load_exact(ffrp_frontier_seed_rel(n,m,p,1), n, m, p, 512)
  z = ffrfgpt_expect(label + " primary loads", primary != nil)
  z = ffrfgpt_expect(label + " legacy loads", legacy != nil)
  if primary != nil && legacy != nil
    z = ffrfgpt_expect(label + " primary exact", primary.rank() == ffrp_record_rank(n,m,p) && ffbc_verify_exact(primary) == 1)
    z = ffrfgpt_expect(label + " legacy exact", legacy.rank() == ffrp_record_rank(n,m,p) && ffbc_verify_exact(legacy) == 1)
    z = ffrfgpt_expect(label + " density", fflc_density(primary) == densities[i])
    z = ffrfgpt_expect(label + " frontier distance", fflc_term_set_distance(primary, legacy) == distances[i])
  i += 1

<< "PASS flipfleet rectangular far-GL profiles"

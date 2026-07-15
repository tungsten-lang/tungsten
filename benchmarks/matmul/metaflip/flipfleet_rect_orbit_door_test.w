use flipfleet_rect_global_isotropy
use flipfleet_rect_profiles

root = "benchmarks/matmul/metaflip/"
source = ffbc_load_exact(root + "matmul_2x5x6_rank47_catalog_gf2.txt", 2, 5, 6, 64)
expected = ffbc_load_exact(root + "matmul_2x5x6_rank47_d438_orbit_door_gf2.txt", 2, 5, 6, 64)
if source == nil || expected == nil || source.rank() != 47 || expected.rank() != 47
  << "FAIL 2x5x6 orbit-door assets"
  exit(1)

# Replay sample three from flipfleet_rect_orbit_door_cli: a four-generator
# sparse GL word followed by complete-gated directed descent.
sample = 3 ## i64
seed = 32452843 * (sample + 1) + source.rank() * 49999 ## i64
image = fflc_sparse_leaf_image(source, seed, 4)
stats = i64[4]
candidate = ffrgir_descent(image, 64, stats)
if candidate == nil || ffbc_verify_exact(candidate) != 1
  << "FAIL 2x5x6 orbit-door replay gate"
  exit(1)
if fflc_density(source) != 438 || fflc_density(candidate) != 438
  << "FAIL 2x5x6 orbit-door density"
  exit(1)
if fflc_term_set_distance(source, candidate) != 94 || fflc_term_set_distance(source, expected) != 94
  << "FAIL 2x5x6 orbit-door distance"
  exit(1)
if fflc_equal(candidate, expected) != 1
  << "FAIL 2x5x6 orbit-door byte-order replay"
  exit(1)
if ffrp_frontier_seed_count(2,5,6) != 2 || ffrp_frontier_seed_rel(2,5,6,1) != root + "matmul_2x5x6_rank47_d438_orbit_door_gf2.txt"
  << "FAIL 2x5x6 orbit-door profile admission"
  exit(1)

<< "PASS 2x5x6 orbit door rank=47 density=438 distance=94 steps=" + stats[2].to_s()

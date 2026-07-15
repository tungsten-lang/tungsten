use flipfleet_leaf_conjugation
use flipfleet_rect_profiles

# Independent pure-Tungsten admission gate for the exact upper endpoint of
# the high-leverage <2,5,6> campaign. `ffbc_load_exact` reconstructs all 3,600
# tensor coefficients before returning the catalog import.

-> ff256_popcount(value) (i64) i64
  x = value ## i64
  count = 0 ## i64
  while x != 0
    count += x & 1
    x = x >> 1
  count

path = "benchmarks/matmul/metaflip/matmul_2x5x6_rank47_catalog_gf2.txt"
scheme = ffbc_load_exact(path, 2, 5, 6, 64)
if scheme == nil || scheme.rank() != 47
  << "FAIL 2x5x6 exact rank-47 certificate"
  exit(1)

density = 0 ## i64
i = 0 ## i64
while i < scheme.rank()
  u = scheme.us()[i] ## i64
  v = scheme.vs()[i] ## i64
  w = scheme.ws()[i] ## i64
  if u < 1 || u >= (1 << 10) || v < 1 || v >= (1 << 30) || w < 1 || w >= (1 << 12)
    << "FAIL 2x5x6 factor width term=" + i.to_s()
    exit(1)
  density += ff256_popcount(u) + ff256_popcount(v) + ff256_popcount(w)
  i += 1

if density != 438 || ffrp_record_rank(2, 5, 6) != 47 || ffrp_target_rank(2, 5, 6) != 46 || ffrp_seed_rel(2, 5, 6) != path
  << "FAIL 2x5x6 profile contract density=" + density.to_s()
  exit(1)

door_path = "benchmarks/matmul/metaflip/matmul_2x5x6_rank47_d438_orbit_door_gf2.txt"
door = ffbc_load_exact(door_path, 2, 5, 6, 64)
if door == nil || door.rank() != 47 || fflc_density(door) != 438
  << "FAIL 2x5x6 exact orbit door"
  exit(1)
if fflc_term_set_distance(scheme, door) != 94
  << "FAIL 2x5x6 orbit door is not disjoint"
  exit(1)
if ffrp_frontier_seed_count(2,5,6) != 2 || ffrp_frontier_seed_rel(2,5,6,1) != door_path
  << "FAIL 2x5x6 orbit door profile contract"
  exit(1)

<< "PASS 2x5x6 exact upper rank=47 density=438 target=46 doors=2 distance=94"

use flipfleet_block_composer

# Pure-Tungsten exact gate for the upper endpoint paired with proof_n235/.
# The d160 fleet leader is a distant continuation of the public d173
# AlphaTensor basin. The two earlier fleet rediscoveries are disjoint from that
# basin and each other, so d160/d170/d210/d278 are the four active restart
# doors while d173 remains pinned provenance.

-> ff235_density(scheme) i64
  total = 0 ## i64
  term = 0 ## i64
  while term < scheme.rank()
    total += ffbc_popcount_small(scheme.us()[term])
    total += ffbc_popcount_small(scheme.vs()[term])
    total += ffbc_popcount_small(scheme.ws()[term])
    term += 1
  total

-> ff235_common_terms(left, right) i64
  common = 0 ## i64
  i = 0 ## i64
  while i < left.rank()
    j = 0 ## i64
    while j < right.rank()
      if left.us()[i] == right.us()[j] && left.vs()[i] == right.vs()[j] && left.ws()[i] == right.ws()[j]
        common += 1
      j += 1
    i += 1
  common

paths = ["benchmarks/matmul/metaflip/matmul_2x3x5_rank25_d160_fleet_gf2.txt", "benchmarks/matmul/metaflip/matmul_2x3x5_rank25_d170_fleet_gf2.txt", "benchmarks/matmul/metaflip/matmul_2x3x5_rank25_d173_alphatensor_zt_mod2_gf2.txt", "benchmarks/matmul/metaflip/matmul_2x3x5_rank25_d210_fleet_gf2.txt", "benchmarks/matmul/metaflip/matmul_2x3x5_rank25_d278_fleet_gf2.txt"]
expected_density = i64[5]
expected_density[0] = 160
expected_density[1] = 170
expected_density[2] = 173
expected_density[3] = 210
expected_density[4] = 278
schemes = []
i = 0 ## i64
while i < paths.size()
  scheme = ffbc_load_exact(paths[i], 2, 3, 5, 32)
  if scheme == nil || scheme.rank() != 25 || ff235_density(scheme) != expected_density[i]
    << "FAIL 2x3x5 rank-25 certificate slot=" + i.to_s()
    exit(1)
  schemes.push(scheme)
  i += 1

if ff235_common_terms(schemes[0], schemes[1]) != 3 || ff235_common_terms(schemes[0], schemes[2]) != 3 || ff235_common_terms(schemes[0], schemes[3]) != 0 || ff235_common_terms(schemes[0], schemes[4]) != 0 || ff235_common_terms(schemes[1], schemes[2]) != 23 || ff235_common_terms(schemes[1], schemes[3]) != 0 || ff235_common_terms(schemes[1], schemes[4]) != 0 || ff235_common_terms(schemes[2], schemes[3]) != 0 || ff235_common_terms(schemes[2], schemes[4]) != 0 || ff235_common_terms(schemes[3], schemes[4]) != 0
  << "FAIL 2x3x5 rank-25 term-distance audit"
  exit(1)

<< "PASS 2x3x5 exact upper rank=25 schemes=5 active-doors=4"

use flipfleet_fixed_rank_pocket

-> fffrpt_expect(label, condition) (String bool) i64
  if !condition
    << "FIXED_RANK_POCKET_FAIL " + label
    exit(1)
  1

-> fffrpt_scheme_density(scheme) (FFBCScheme) i64
  total = 0 ## i64
  i = 0 ## i64
  while i < scheme.rank() * scheme.uw()
    total += fffrp_popcount(scheme.us()[i])
    i += 1
  i = 0
  while i < scheme.rank() * scheme.vw()
    total += fffrp_popcount(scheme.vs()[i])
    i += 1
  i = 0
  while i < scheme.rank() * scheme.ww()
    total += fffrp_popcount(scheme.ws()[i])
    i += 1
  total

root = "bits/tungsten-metaflip/lib/metaflip/seeds/gf2/"
source_path = root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt"
target_path = root + "matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt"
source = ffbc_load_exact(source_path, 2, 2, 5, 24)
target = ffbc_load_exact(target_path, 2, 2, 5, 24)
fffrpt_expect("load exact endpoints", source != nil && target != nil && source.rank() == 18 && target.rank() == 18)
fffrpt_expect("d92 to d84 endpoints", fffrpt_scheme_density(source) == 92 && fffrpt_scheme_density(target) == 84)

source_u = i64[8]
source_v = i64[8]
source_w = i64[8]
target_u = i64[8]
target_v = i64[8]
target_w = i64[8]
pocket = fffrp_extract_pocket(source, target, source_u, source_v, source_w, target_u, target_v, target_w) ## i64
fffrpt_expect("five-term symmetric difference", pocket == 5)
fffrpt_expect("local endpoint densities", fffrp_density(source_u, source_v, source_w, 0, pocket) == 26 && fffrp_density(target_u, target_v, target_w, 0, pocket) == 18)

endpoint_u = i64[8]
endpoint_v = i64[8]
endpoint_w = i64[8]
path_density = i64[8]
path_axes = i64[8]
stats = i64[11]

# A four-edge closure budget cannot cross this pocket.
depth4 = fffrp_search(source_u, source_v, source_w, target_u, target_v, target_w, pocket, 4, 128, 1, endpoint_u, endpoint_v, endpoint_w, path_density, path_axes, stats) ## i64
fffrpt_expect("depth four misses", depth4 == 0 && stats[4] == -1 && stats[0] == 12)

# Pure density descent also misses: every depth-five closure has to repay one
# temporary bit of density after first descending from 26 to 23.
monotone = fffrp_search(source_u, source_v, source_w, target_u, target_v, target_w, pocket, 5, 128, 0, endpoint_u, endpoint_v, endpoint_w, path_density, path_axes, stats) ## i64
fffrpt_expect("monotone descent misses", monotone == 0 && stats[3] > 0)

# One bit of edge-local debt is sufficient. Deterministic BFS discovers the
# exact 26->23->24->22->20->18 closure in five ordinary flips.
depth5 = fffrp_search(source_u, source_v, source_w, target_u, target_v, target_w, pocket, 5, 128, 1, endpoint_u, endpoint_v, endpoint_w, path_density, path_axes, stats) ## i64
fffrpt_expect("depth five closes", depth5 == 5 && stats[4] == 5 && stats[0] == 14 && stats[8] == 1)
fffrpt_expect("density-debt trace", path_density[0] == 26 && path_density[1] == 23 && path_density[2] == 24 && path_density[3] == 22 && path_density[4] == 20 && path_density[5] == 18)
common_density = fffrpt_scheme_density(source) - path_density[0] ## i64
fffrpt_expect("whole-scheme density trace", common_density == 66 && path_density[0] + common_density == 92 && path_density[1] + common_density == 89 && path_density[2] + common_density == 90 && path_density[3] + common_density == 88 && path_density[4] + common_density == 86 && path_density[5] + common_density == 84)
fffrpt_expect("deterministic axis trace", path_axes[1] == 0 && path_axes[2] == 2 && path_axes[3] == 1 && path_axes[4] == 2 && path_axes[5] == 2)
fffrpt_expect("endpoint term set", fffrp_terms_equal(endpoint_u, endpoint_v, endpoint_w, 0, target_u, target_v, target_w, 0, pocket) == 1)

# Ordinary flips preserve the local tensor by construction, but the operator
# does not trust that fact at intake: rebuild the 13 frozen terms plus the
# discovered pocket and independently verify all 2x2x5 coefficients.
closed = fffrp_materialize_endpoint(source, source_u, source_v, source_w, endpoint_u, endpoint_v, endpoint_w, pocket)
fffrpt_expect("whole endpoint exact gate", closed != nil && closed.rank() == 18 && fffrpt_scheme_density(closed) == 84 && ffbc_verify_exact(closed) == 1)

<< "flipfleet_fixed_rank_pocket_test: pass d92->d84 pocket=5 depth4=miss depth5=" + depth5.to_s() + " states=" + stats[0].to_s() + " density=92,89,90,88,86,84 exact=1"

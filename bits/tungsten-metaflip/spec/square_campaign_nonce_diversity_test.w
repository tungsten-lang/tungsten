use ../lib/metaflip/fleet/archive
use ../lib/metaflip/fleet/cpu_pool
use ../lib/metaflip/strategies/escape
use ../lib/metaflip/strategies/global_isotropy

failures = 0 ## i64

-> nonce_diversity_expect(label, condition) (String bool) i64
  if condition == 0
    << "FAIL square campaign nonce diversity: " + label
    return 1
  0

-> nonce_diversity_escape(base, kind, local_nonce, campaign_nonce, n, capacity, state_size)
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_best(base, us, vs, ws) ## i64
  meta = i64[8]
  identity_nonce = ffcp_campaign_identity_nonce(local_nonce, campaign_nonce) ## i64
  escaped = ffe_apply(us, vs, ws, rank, capacity, n, kind, identity_nonce, meta) ## i64
  if escaped < 1 || meta[7] != 1
    return nil
  candidate = i64[state_size]
  loaded = ffw_init_terms_cap(candidate, us, vs, ws, escaped, n, capacity, ffcp_campaign_seed(91001 + kind * 97 + local_nonce, campaign_nonce), 0, 1, 1, 1) ## i64
  if loaded != escaped || ffw_verify_best_exact(candidate, n) != 1
    return nil
  candidate

n = 4 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base, root + "matmul_4x4_rank47_d677_flips_gf2.txt", n, capacity, 90001, 0, 1, 1, 1) ## i64
failures += nonce_diversity_expect("exact 4x4 source", base_rank == 47 && ffw_verify_best_exact(base, n) == 1)

# Nonce zero must enumerate exactly the historical identities. The two AWS
# campaign nonces must select different six-identity windows.
i = 0 ## i64
while i < 6
  failures += nonce_diversity_expect("zero identity nonce " + i.to_s(), ffcp_campaign_identity_nonce(i, 0) == i)
  i += 1
failures += nonce_diversity_expect("AWS offsets differ", ffcp_campaign_identity_nonce(0, 3019) != ffcp_campaign_identity_nonce(0, 4021))

splits_a = []
splits_b = []
composes_a = []
composes_b = []
i = 0
while i < 6
  split_a = nonce_diversity_escape(base, 1, i, 3019, n, capacity, state_size)
  split_b = nonce_diversity_escape(base, 1, i, 4021, n, capacity, state_size)
  compose_a = nonce_diversity_escape(base, 5, i, 3019, n, capacity, state_size)
  compose_b = nonce_diversity_escape(base, 5, i, 4021, n, capacity, state_size)
  failures += nonce_diversity_expect("split exact/rank profile A " + i.to_s(), split_a != nil && ffw_best_rank(split_a) == 48)
  failures += nonce_diversity_expect("split exact/rank profile B " + i.to_s(), split_b != nil && ffw_best_rank(split_b) == 48)
  failures += nonce_diversity_expect("compose exact/rank profile A " + i.to_s(), compose_a != nil && ffw_best_rank(compose_a) == 49)
  failures += nonce_diversity_expect("compose exact/rank profile B " + i.to_s(), compose_b != nil && ffw_best_rank(compose_b) == 49)
  if split_a != nil
    splits_a.push(split_a)
  if split_b != nil
    splits_b.push(split_b)
  if compose_a != nil
    composes_a.push(compose_a)
  if compose_b != nil
    composes_b.push(compose_b)
  i += 1

split_overlap = 0 ## i64
i = 0
while i < splits_a.size()
  j = 0 ## i64
  while j < splits_b.size()
    if ffn_distance(splits_a[i], splits_b[j]) == 0
      split_overlap += 1
    j += 1
  i += 1
failures += nonce_diversity_expect("different campaigns choose disjoint +1 identities", split_overlap == 0)

compose_overlap = 0 ## i64
i = 0
while i < composes_a.size()
  j = 0 ## i64
  while j < composes_b.size()
    if ffn_distance(composes_a[i], composes_b[j]) == 0
      compose_overlap += 1
    j += 1
  i += 1
failures += nonce_diversity_expect("different campaigns choose disjoint +2 identities", compose_overlap == 0)

# Density descent itself is deterministic. Campaign diversification therefore
# applies a coordinate-swap word afterward: exactness, rank, and density stay
# fixed while the local-flip embedding changes.
normalized = i64[state_size]
stats = i64[4]
normalized_rank = ffgir_density_descent_state_into(base, normalized, n, capacity, 92001, 0, 1, 1, 1, 32, stats) ## i64
failures += nonce_diversity_expect("isotropy descent improves exactly", normalized_rank == 47 && ffw_verify_best_exact(normalized, n) == 1 && ffw_best_bits(normalized) < ffw_best_bits(base))
normalized_density = ffw_best_bits(normalized) ## i64
image_a = i64[state_size]
image_b = i64[state_size]
z = ffw_reseed_from(image_a, normalized, 92003) ## i64
z = ffw_reseed_from(image_b, normalized, 92005)
seed_a = ffcp_campaign_seed(57018, 3019) ## i64
seed_b = ffcp_campaign_seed(57018, 4021) ## i64
image_a_rank = ffgir_coordinate_image_state_into(image_a, image_a, n, capacity, seed_a, 0, 1, 1, 1, 3) ## i64
image_b_rank = ffgir_coordinate_image_state_into(image_b, image_b, n, capacity, seed_b, 0, 1, 1, 1, 3) ## i64
failures += nonce_diversity_expect("isotropy image A preserves profile", image_a_rank == 47 && ffw_best_bits(image_a) == normalized_density && ffw_verify_best_exact(image_a, n) == 1)
failures += nonce_diversity_expect("isotropy image B preserves profile", image_b_rank == 47 && ffw_best_bits(image_b) == normalized_density && ffw_verify_best_exact(image_b, n) == 1)
failures += nonce_diversity_expect("isotropy images differ from source", ffn_distance(image_a, normalized) > 0 && ffn_distance(image_b, normalized) > 0)
failures += nonce_diversity_expect("isotropy images differ by campaign", ffn_distance(image_a, image_b) > 0)

if failures > 0
  exit(1)

<< "PASS square campaign nonce diversifies exact escape/isotropy banks split-overlap=" + split_overlap.to_s() + " compose-overlap=" + compose_overlap.to_s() + " density=" + normalized_density.to_s()

# Stable metaflip-ranker-v1 input contract. These are pre-rollout state
# measurements only: no identities, labels, future outcomes, or exactness
# shortcuts. Core ML receives Float32 values after JSON conversion; the model
# owns normalization fitted exclusively on its training origins.
use map_elites

-> ffcm_feature_names()
  ["rank", "rank_debt", "total_bits", "bits_per_term", "flip_pairs", "flip_pairs_per_term", "c3_symmetric", "unique_u", "unique_v", "unique_w", "singleton_u", "singleton_v", "singleton_w", "max_bucket_u", "max_bucket_v", "max_bucket_w"]

-> ffcm_features(state, frontier_rank, output) (i64[] i64 f64[]) i64
  rank = ffw_best_rank(state) ## i64
  if rank < 1
    return 0
  bits = ffw_best_bits(state) ## i64
  pairs = ffbp_flip_pairs(state) ## i64
  output[0] = rank * 1.0
  output[1] = (rank - frontier_rank) * 1.0
  output[2] = bits * 1.0
  output[3] = bits * 1.0 / rank
  output[4] = pairs * 1.0
  output[5] = pairs * 1.0 / rank
  output[6] = ffbi_state_is_c3(state, ffw_n(state), 0) * 1.0
  axis = 0 ## i64
  while axis < 3
    unique = 0 ## i64
    singletons = 0 ## i64
    largest = 0 ## i64
    i = 0 ## i64
    while i < rank
      value = ffbi_view_u(state, i, 0) ## i64
      if axis == 1
        value = ffbi_view_v(state, i, 0)
      if axis == 2
        value = ffbi_view_w(state, i, 0)
      count = 0 ## i64
      first = 1 ## i64
      j = 0 ## i64
      while j < rank
        other = ffbi_view_u(state, j, 0) ## i64
        if axis == 1
          other = ffbi_view_v(state, j, 0)
        if axis == 2
          other = ffbi_view_w(state, j, 0)
        if value == other
          count += 1
          if j < i
            first = 0
        j += 1
      if first == 1
        unique += 1
        if count == 1
          singletons += 1
        if count > largest
          largest = count
      i += 1
    output[7 + axis] = unique * 1.0
    output[10 + axis] = singletons * 1.0
    output[13 + axis] = largest * 1.0
    axis += 1
  16

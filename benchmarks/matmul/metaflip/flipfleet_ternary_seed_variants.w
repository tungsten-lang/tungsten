use flipfleet_ternary_index_shear
use flipfleet_ternary_gpu_lib

# Deterministic CPU/GPU seed expansion.  For each already-gated raw seed:
#
#   CPU: exactly one strict density-normalized clone;
#   GPU: the raw seed, the normalized clone if distinct, and at most one
#        fingerprint-distinct shallow positive isotropy door (density debt
#        capped at eight and exhaustively promoted through fft_init_terms).
#
# Doors are generated only from the normalized clone and are never expanded
# recursively.  The GPU coordinator closes every returned candidate through
# the same deterministic normalization before archive/publication.

-> fftsv_push_unique(states, candidate)
  fingerprint = fft_current_fingerprint(candidate) ## i64
  i = 0 ## i64
  while i < states.size()
    if fft_current_fingerprint(states[i]) == fingerprint
      return 0
    i += 1
  states.push(candidate)
  1

# Return the selected shallow-door debt (zero when no capped door exists), or
# -1 if cloning, normalization, or the exhaustive door promotion failed.
-> fftsv_add_variants(cpu_states, gpu_states, raw, seed, max_debt)
  z = fftsv_push_unique(gpu_states,raw) ## i64
  state_words = fft_state_size(raw[4]) ## i64
  normalized = i64[state_words]
  if fft_clone_gated_seed(normalized,raw,seed,max_debt) < 1
    return 0 - 1
  if fft_index_shear_directed_descent(normalized) < 0
    return 0 - 1
  cpu_states.push(normalized)
  z = fftsv_push_unique(gpu_states,normalized)

  door = i64[state_words]
  if fft_clone_gated_seed(door,normalized,seed + 100000,max_debt) < 1
    return 0 - 1
  debt = fft_index_shear_shallow_positive_door(door,8) ## i64
  if debt < 0
    return 0 - 1
  if debt > 0
    promoted = i64[state_words]
    if fftgs_promote_current(promoted,door,seed + 200000) < 1
      return 0 - 1
    z = fftsv_push_unique(gpu_states,promoted)
  debt

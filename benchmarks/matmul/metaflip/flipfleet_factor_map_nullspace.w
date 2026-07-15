# Exact selected-subset replacements under arbitrary elementary linear maps on
# one rank-one factor space.
#
# The map need not preserve the matrix-multiplication tensor.  For any linear
# phi and selected live terms S, a kernel relation
#
#   XOR(t in S) (t XOR phi(t)) = 0
#
# proves that replacing precisely S by phi(S) preserves the represented
# tensor.  This is the syndrome-gated form of pivot-and-absorb.  Operations:
#
#   0  swap two raw factor coordinates (invertible)
#   1  target ^= source              (invertible transvection)
#   2  delete source                 (rank-d-1 projection)
#   3  fold source into target, then delete source (rank-d-1 quotient)
#
# Operations 2/3 may map a rank-one term to zero.  Materialization must omit
# that zero contribution before parity compaction; it is a legitimate direct
# rank reduction, not an invalid term.

use flipfleet_partial_automorphism_nullspace

-> ffmfn_map_factor(value, operation, source, target) (i64 i64 i64 i64) i64
  if operation == 0
    source_bit = (value >> source) & 1 ## i64
    target_bit = (value >> target) & 1 ## i64
    if source_bit != target_bit
      return value ^ (1 << source) ^ (1 << target)
    return value
  if operation == 1
    if ((value >> source) & 1) != 0
      return value ^ (1 << target)
    return value
  if operation == 2
    return value & (0 - 1 - (1 << source))
  if operation == 3
    result = value ## i64
    if ((value >> source) & 1) != 0
      result = result ^ (1 << target)
    result = result & (0 - 1 - (1 << source))
    return result
  value

-> ffmfn_transform_term(u, v, w, factor, operation, source, target, out) (i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  if out.size() < 3 || factor < 0 || factor > 2 || operation < 0 || operation > 3 || source < 0 || source >= 63
    return 0
  if operation != 2
    if target < 0 || target >= 63 || target == source
      return 0
  out[0] = u
  out[1] = v
  out[2] = w
  if factor == 0
    out[0] = ffmfn_map_factor(u, operation, source, target)
  if factor == 1
    out[1] = ffmfn_map_factor(v, operation, source, target)
  if factor == 2
    out[2] = ffmfn_map_factor(w, operation, source, target)
  1

-> ffmfn_build_deltas(us, vs, ws, rank, n, factor, operation, source, target, transformed_u, transformed_v, transformed_w, deltas) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  words = ffpa_tensor_words(n) ## i64
  dimension = n * n ## i64
  if rank < 1 || factor < 0 || factor > 2 || operation < 0 || operation > 3 || source < 0 || source >= dimension
    return 0
  if operation != 2 && (target < 0 || target >= dimension || target == source)
    return 0
  if transformed_u.size() < rank || transformed_v.size() < rank || transformed_w.size() < rank || deltas.size() < rank * words
    return 0
  out = i64[3]
  i = 0 ## i64
  while i < rank
    if ffmfn_transform_term(us[i], vs[i], ws[i], factor, operation, source, target, out) != 1
      return 0
    transformed_u[i] = out[0]
    transformed_v[i] = out[1]
    transformed_w[i] = out[2]
    z = ffpa_clear_row(deltas, i * words, words) ## i64
    z = ffpa_xor_outer(deltas, i * words, us[i], vs[i], ws[i], n)
    # A zero factor is the zero tensor and intentionally contributes nothing.
    if out[0] != 0 && out[1] != 0 && out[2] != 0
      z = ffpa_xor_outer(deltas, i * words, out[0], out[1], out[2], n)
    i += 1
  words

-> ffmfn_transform_terms(us, vs, ws, rank, n, factor, operation, source, target, transformed_u, transformed_v, transformed_w) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[]) i64
  dimension = n * n ## i64
  if rank < 1 || factor < 0 || factor > 2 || operation < 0 || operation > 3 || source < 0 || source >= dimension
    return 0
  if operation != 2 && (target < 0 || target >= dimension || target == source)
    return 0
  out = i64[3]
  i = 0 ## i64
  while i < rank
    if ffmfn_transform_term(us[i], vs[i], ws[i], factor, operation, source, target, out) != 1
      return 0
    transformed_u[i] = out[0]
    transformed_v[i] = out[1]
    transformed_w[i] = out[2]
    i += 1
  rank

# Compact a raw endpoint while treating any zero-factor term as the additive
# zero. `meta[0]` counts omitted zeros and `meta[1]` duplicate-pair removals.
-> ffmfn_compact_allow_zero(raw_u, raw_v, raw_w, raw_count, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  if meta.size() < 2
    return 0 - 1
  meta[0] = 0
  meta[1] = 0
  count = 0 ## i64
  i = 0 ## i64
  while i < raw_count
    if raw_u[i] == 0 || raw_v[i] == 0 || raw_w[i] == 0
      meta[0] = meta[0] + 1
    else
      found = 0 - 1 ## i64
      j = 0 ## i64
      while j < count && found < 0
        if raw_u[i] == out_u[j] && raw_v[i] == out_v[j] && raw_w[i] == out_w[j]
          found = j
        j += 1
      if found >= 0
        count -= 1
        meta[1] = meta[1] + 1
        if found < count
          out_u[found] = out_u[count]
          out_v[found] = out_v[count]
          out_w[found] = out_w[count]
      if found < 0
        out_u[count] = raw_u[i]
        out_v[count] = raw_v[i]
        out_w[count] = raw_w[i]
        count += 1
    i += 1
  count

-> ffmfn_family_operations(dimension, operation) (i64 i64) i64
  if operation == 0
    return 3 * dimension * (dimension - 1) / 2
  if operation == 1 || operation == 3
    return 3 * dimension * (dimension - 1)
  if operation == 2
    return 3 * dimension
  0

# Decode a family-local flat index as factor, source, target.
-> ffmfn_decode(dimension, operation, index, out) (i64 i64 i64 i64[]) i64
  total = ffmfn_family_operations(dimension, operation) ## i64
  if dimension < 2 || operation < 0 || operation > 3 || index < 0 || index >= total || out.size() < 3
    return 0
  if operation == 2
    out[0] = index / dimension
    out[1] = index % dimension
    out[2] = 0
    return 1
  if operation == 0
    pairs = dimension * (dimension - 1) / 2 ## i64
    out[0] = index / pairs
    wanted = index % pairs ## i64
    pair = 0 ## i64
    source = 0 ## i64
    while source < dimension - 1
      target = source + 1 ## i64
      while target < dimension
        if pair == wanted
          out[1] = source
          out[2] = target
        pair += 1
        target += 1
      source += 1
    return 1
  ordered = dimension * (dimension - 1) ## i64
  out[0] = index / ordered
  pair = index % ordered
  source = pair / (dimension - 1) ## i64
  target = pair % (dimension - 1) ## i64
  if target >= source
    target += 1
  out[1] = source
  out[2] = target
  1

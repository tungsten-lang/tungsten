# Standalone move lab: paired nonzero-defect cancellation over GF(2).
#
# A local proposal need not preserve its source subtotal.  Write
#
#   defect(A -> A') = tensor(A) XOR tensor(A').
#
# Two proposals with the same *nonzero* defect cancel when applied together:
#
#   defect(A -> A') = defect(B -> B')
#       implies tensor(A + B) = tensor(A' + B').
#
# The prototype below exhausts 3-to-2 proposals from two bounded rank-one
# pools.  Two linear 63-bit hashes are only a join filter.  Every hash hit is
# compared as a complete packed tensor, and the returned 6-to-4 relation is
# independently reconstructed once more.  No Metaflip runtime module is used.

-> pdc_clear(values) (i64[]) i64
  i = 0 ## i64
  while i < values.size()
    values[i] = 0
    i += 1
  1

-> pdc_tensor_cells(ubits, vbits, wbits) (i64 i64 i64) i64
  ubits * vbits * wbits

-> pdc_tensor_words(ubits, vbits, wbits) (i64 i64 i64) i64
  (pdc_tensor_cells(ubits,vbits,wbits) + 63) / 64

-> pdc_factor_fits(value, width) (i64 i64) i64
  if value <= 0 || width < 1 || width > 62
    return 0
  if (value >> width) != 0
    return 0
  1

-> pdc_term_fits(u, v, w, ubits, vbits, wbits) (i64 i64 i64 i64 i64 i64) i64
  if pdc_factor_fits(u,ubits) == 0
    return 0
  if pdc_factor_fits(v,vbits) == 0
    return 0
  pdc_factor_fits(w,wbits)

-> pdc_xor_outer(words, u, v, w, ubits, vbits, wbits) (i64[] i64 i64 i64 i64 i64 i64) i64
  if pdc_term_fits(u,v,w,ubits,vbits,wbits) == 0
    return 0
  ui = 0 ## i64
  while ui < ubits
    if ((u >> ui) & 1) != 0
      vi = 0 ## i64
      while vi < vbits
        if ((v >> vi) & 1) != 0
          base = (ui * vbits + vi) * wbits ## i64
          wi = 0 ## i64
          while wi < wbits
            if ((w >> wi) & 1) != 0
              cell = base + wi ## i64
              words[cell / 64] = words[cell / 64] ^ (1 << (cell % 64))
            wi += 1
        vi += 1
    ui += 1
  1

-> pdc_xor_packed(words, packed, count, ubits, vbits, wbits) (i64[] i64[] i64 i64 i64 i64) i64
  if packed.size() < count * 3
    return 0
  i = 0 ## i64
  while i < count
    if pdc_xor_outer(words,packed[i*3],packed[i*3+1],packed[i*3+2],ubits,vbits,wbits) == 0
      return 0
    i += 1
  1

-> pdc_all_zero(words) (i64[]) i64
  i = 0 ## i64
  while i < words.size()
    if words[i] != 0
      return 0
    i += 1
  1

-> pdc_equal_words(left, right) (i64[] i64[]) i64
  if left.size() != right.size()
    return 0
  i = 0 ## i64
  while i < left.size()
    if left[i] != right[i]
      return 0
    i += 1
  1

-> pdc_relation_exact(source, source_count, target, target_count, shape) (i64[] i64 i64[] i64 i64[]) i64
  if shape.size() < 3
    return 0
  ubits = shape[0] ## i64
  vbits = shape[1] ## i64
  wbits = shape[2] ## i64
  relation = i64[pdc_tensor_words(ubits,vbits,wbits)]
  if pdc_xor_packed(relation,source,source_count,ubits,vbits,wbits) == 0
    return 0
  if pdc_xor_packed(relation,target,target_count,ubits,vbits,wbits) == 0
    return 0
  pdc_all_zero(relation)

# Positive, wrap-safe cell mixer.  Hashes remain linear because outer-product
# supports combine only through XOR of these fixed per-cell values.
-> pdc_cell_hash(cell, salt) (i64 i64) i64
  x = ((cell + 1) * 6364136223846793005 + (salt + 1) * 1442695040888963407) & 9223372036854775807 ## i64
  x = x ^ (x >> 23)
  x = (x * 3202034522624059733) & 9223372036854775807
  x ^ (x >> 29)

-> pdc_term_hash(u, v, w, ubits, vbits, wbits, salt) (i64 i64 i64 i64 i64 i64 i64) i64
  hash = 0 ## i64
  ui = 0 ## i64
  while ui < ubits
    if ((u >> ui) & 1) != 0
      vi = 0 ## i64
      while vi < vbits
        if ((v >> vi) & 1) != 0
          base = (ui * vbits + vi) * wbits ## i64
          wi = 0 ## i64
          while wi < wbits
            if ((w >> wi) & 1) != 0
              hash = hash ^ pdc_cell_hash(base + wi,salt)
            wi += 1
        vi += 1
    ui += 1
  hash

-> pdc_packed_hash(packed, count, shape, salt) (i64[] i64 i64[] i64) i64
  hash = 0 ## i64
  i = 0 ## i64
  while i < count
    hash = hash ^ pdc_term_hash(packed[i*3],packed[i*3+1],packed[i*3+2],shape[0],shape[1],shape[2],salt)
    i += 1
  hash

-> pdc_pair_hash(pool, first, second, shape, salt) (i64[] i64 i64 i64[] i64) i64
  pdc_term_hash(pool[first*3],pool[first*3+1],pool[first*3+2],shape[0],shape[1],shape[2],salt) ^ pdc_term_hash(pool[second*3],pool[second*3+1],pool[second*3+2],shape[0],shape[1],shape[2],salt)

-> pdc_hash_slot(key0, key1, mask) (i64 i64 i64) i64
  mixed = (key0 * 6364136223846793005 + key1 * 1442695040888963407) & 9223372036854775807 ## i64
  mixed = mixed ^ (mixed >> 27)
  mixed & mask

-> pdc_next_power_two(value) (i64) i64
  result = 1 ## i64
  while result < value
    result = result * 2
  result

-> pdc_same_term(packed, first, second) (i64[] i64 i64) i64
  if packed[first*3] == packed[second*3] && packed[first*3+1] == packed[second*3+1] && packed[first*3+2] == packed[second*3+2]
    return 1
  0

-> pdc_pair_valid(pool, count, first, second, shape) (i64[] i64 i64 i64 i64[]) i64
  if first < 0 || second <= first || second >= count
    return 0
  if pdc_same_term(pool,first,second) == 1
    return 0
  if pdc_term_fits(pool[first*3],pool[first*3+1],pool[first*3+2],shape[0],shape[1],shape[2]) == 0
    return 0
  pdc_term_fits(pool[second*3],pool[second*3+1],pool[second*3+2],shape[0],shape[1],shape[2])

-> pdc_fill_defect(defect, source, pool, first, second, shape) (i64[] i64[] i64[] i64 i64 i64[]) i64
  z = pdc_clear(defect) ## i64
  if pdc_xor_packed(defect,source,3,shape[0],shape[1],shape[2]) == 0
    return 0
  if pdc_xor_outer(defect,pool[first*3],pool[first*3+1],pool[first*3+2],shape[0],shape[1],shape[2]) == 0
    return 0
  pdc_xor_outer(defect,pool[second*3],pool[second*3+1],pool[second*3+2],shape[0],shape[1],shape[2])

-> pdc_copy_pair(pool, first, second, out, offset) (i64[] i64 i64 i64[] i64) i64
  axis = 0 ## i64
  while axis < 3
    out[offset*3+axis] = pool[first*3+axis]
    out[(offset+1)*3+axis] = pool[second*3+axis]
    axis += 1
  1

# Exhaust all two-term proposals for each three-term source.  `stats` layout:
# [0] A proposals, [1] B proposals, [2] dual-hash hits,
# [3] exact equal nonzero defects, [4] exact returned 6->4 relation,
# [5] nominal rank delta, [6..9] retained A0/A1/B0/B1 pool indices,
# [10] hash-table capacity, [11] probes.
-> pdc_join_3to2(source_a, source_b, pool_a, pool_a_count, pool_b, pool_b_count, shape, out, stats) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[]) i64
  if source_a.size() < 9 || source_b.size() < 9 || out.size() < 12 || stats.size() < 12
    return 0
  if pool_a.size() < pool_a_count*3 || pool_b.size() < pool_b_count*3
    return 0
  z = pdc_clear(stats) ## i64
  stats[5] = 0 - 2
  pair_count = (pool_a_count * (pool_a_count - 1)) / 2 ## i64
  capacity = pdc_next_power_two(pair_count * 2 + 1) ## i64
  if capacity < 16
    capacity = 16
  table_h0 = i64[capacity]
  table_h1 = i64[capacity]
  table_first = i64[capacity]
  table_second = i64[capacity]
  occupied = i64[capacity]
  mask = capacity - 1 ## i64
  stats[10] = capacity

  source_a_h0 = pdc_packed_hash(source_a,3,shape,17) ## i64
  source_a_h1 = pdc_packed_hash(source_a,3,shape,97) ## i64
  first = 0 ## i64
  while first < pool_a_count
    second = first + 1 ## i64
    while second < pool_a_count
      if pdc_pair_valid(pool_a,pool_a_count,first,second,shape) == 1
        key0 = source_a_h0 ^ pdc_pair_hash(pool_a,first,second,shape,17) ## i64
        key1 = source_a_h1 ^ pdc_pair_hash(pool_a,first,second,shape,97) ## i64
        slot = pdc_hash_slot(key0,key1,mask) ## i64
        searching = 1 ## i64
        while searching == 1
          stats[11] = stats[11] + 1
          if occupied[slot] == 0
            occupied[slot] = 1
            table_h0[slot] = key0
            table_h1[slot] = key1
            table_first[slot] = first
            table_second[slot] = second
            searching = 0
          else
            if table_h0[slot] == key0 && table_h1[slot] == key1
              searching = 0
            else
              slot = (slot + 1) & mask
        stats[0] = stats[0] + 1
      second += 1
    first += 1

  words = pdc_tensor_words(shape[0],shape[1],shape[2]) ## i64
  defect_a = i64[words]
  defect_b = i64[words]
  source_b_h0 = pdc_packed_hash(source_b,3,shape,17) ## i64
  source_b_h1 = pdc_packed_hash(source_b,3,shape,97) ## i64
  found = 0 ## i64
  first = 0
  while first < pool_b_count && found == 0
    second = first + 1
    while second < pool_b_count && found == 0
      if pdc_pair_valid(pool_b,pool_b_count,first,second,shape) == 1
        key0 = source_b_h0 ^ pdc_pair_hash(pool_b,first,second,shape,17) ## i64
        key1 = source_b_h1 ^ pdc_pair_hash(pool_b,first,second,shape,97) ## i64
        slot = pdc_hash_slot(key0,key1,mask) ## i64
        searching = 1 ## i64
        while searching == 1 && found == 0
          stats[11] = stats[11] + 1
          if occupied[slot] == 0
            searching = 0
          else
            if table_h0[slot] == key0 && table_h1[slot] == key1
              stats[2] = stats[2] + 1
              af = table_first[slot] ## i64
              ase = table_second[slot] ## i64
              ok_a = pdc_fill_defect(defect_a,source_a,pool_a,af,ase,shape) ## i64
              ok_b = pdc_fill_defect(defect_b,source_b,pool_b,first,second,shape) ## i64
              if ok_a == 1 && ok_b == 1 && pdc_all_zero(defect_a) == 0 && pdc_equal_words(defect_a,defect_b) == 1
                stats[3] = stats[3] + 1
                z = pdc_copy_pair(pool_a,af,ase,out,0)
                z = pdc_copy_pair(pool_b,first,second,out,2)
                combined_source = i64[18]
                i = 0 ## i64
                while i < 9
                  combined_source[i] = source_a[i]
                  combined_source[i+9] = source_b[i]
                  i += 1
                if pdc_relation_exact(combined_source,6,out,4,shape) == 1
                  stats[4] = 1
                  stats[6] = af
                  stats[7] = ase
                  stats[8] = first
                  stats[9] = second
                  found = 1
              searching = 0
            else
              slot = (slot + 1) & mask
        stats[1] = stats[1] + 1
      second += 1
    first += 1
  found

-> pdc_add_unique(values, count, value) (i64[] i64 i64) i64
  if value == 0
    return count
  i = 0 ## i64
  while i < count
    if values[i] == value
      return count
    i += 1
  if count < values.size()
    values[count] = value
    return count + 1
  count

-> pdc_axis_spans(source, axis, values) (i64[] i64 i64[]) i64
  count = 0 ## i64
  code = 1 ## i64
  while code < 8
    value = 0 ## i64
    i = 0 ## i64
    while i < 3
      if ((code >> i) & 1) != 0
        value = value ^ source[i*3+axis]
      i += 1
    count = pdc_add_unique(values,count,value)
    code += 1
  count

# Bounded complete-factor pool from the three source spans.  When the Cartesian
# product is larger than `cap`, a nonce-rotated contiguous slice is returned.
-> pdc_span_pool(source, cap, nonce, pool) (i64[] i64 i64 i64[]) i64
  if source.size() < 9 || cap < 1 || pool.size() < cap*3
    return 0
  us = i64[7]
  vs = i64[7]
  ws = i64[7]
  uc = pdc_axis_spans(source,0,us) ## i64
  vc = pdc_axis_spans(source,1,vs) ## i64
  wc = pdc_axis_spans(source,2,ws) ## i64
  total = uc * vc * wc ## i64
  count = total ## i64
  if count > cap
    count = cap
  start = 0 ## i64
  if total > 0
    start = nonce % total
    if start < 0
      start += total
  i = 0 ## i64
  while i < count
    code = (start + i) % total ## i64
    ui = code / (vc * wc) ## i64
    remainder = code - ui * vc * wc ## i64
    vi = remainder / wc ## i64
    wi = remainder - vi * wc ## i64
    pool[i*3] = us[ui]
    pool[i*3+1] = vs[vi]
    pool[i*3+2] = ws[wi]
    i += 1
  count

-> pdc_copy_term(source, source_index, target, target_index) (i64[] i64 i64[] i64) i64
  target[target_index*3] = source[source_index*3]
  target[target_index*3+1] = source[source_index*3+1]
  target[target_index*3+2] = source[source_index*3+2]
  1

-> pdc_windows_disjoint(indices) (i64[]) i64
  i = 0 ## i64
  while i < 6
    j = i + 1 ## i64
    while j < 6
      if indices[i] == indices[j]
        return 0
      j += 1
    i += 1
  1

# Deterministic six-index ticket used by the standalone real-seed bench.
-> pdc_window_ticket(rank, ticket, indices) (i64 i64 i64[]) i64
  if rank < 6 || indices.size() < 6
    return 0
  x = (ticket * 6364136223846793005 + 1442695040888963407) & 9223372036854775807 ## i64
  i = 0 ## i64
  while i < 6
    candidate = (x + i * i + i * 17) % rank ## i64
    unique = 0 ## i64
    while unique == 0
      unique = 1
      j = 0 ## i64
      while j < i
        if indices[j] == candidate
          candidate = (candidate + 1) % rank
          unique = 0
          j = i
        else
          j += 1
    indices[i] = candidate
    x = (x * 3202034522624059733 + 3935559000370003845) & 9223372036854775807
    i += 1
  pdc_windows_disjoint(indices)

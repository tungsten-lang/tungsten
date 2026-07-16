# Exact partial-automorphism splices for Metaflip.
#
# A simultaneous relabeling of the three matrix-multiplication index domains
# I,K,J is a tensor automorphism.  For a term t, let d(t)=t+phi(t).  A subset
# whose exact deltas XOR to zero can be transformed without changing the
# represented tensor, even when transforming the whole decomposition would
# merely produce a globally equivalent seed.
#
# The bounded enumerators below consider elementary coordinate transpositions,
# elementary GL(n,2) transvections, and direct coordinate 3-cycles in I/K/J,
# together with every 2-, 3-, or 4-term relation in a caller-supplied rotating
# window.  The paired occurrence of an index receives the inverse transpose.
# Deltas are complete n^6-bit tensors.  Hashes only
# select buckets; every hit is compared word-for-word before it is returned.
# `ffpa_apply_current` performs an independent full-tensor pre/post gate and
# restores the original worker state if any postcondition fails.

use ../scheme

-> ffpa_tensor_words(n) (i64) i64
  bits = n * n * n * n * n * n ## i64
  (bits + 63) / 64

-> ffpa_swap_coordinate(value, n, row_domain, col_domain, domain, left, right) (i64 i64 i64 i64 i64 i64 i64) i64
  result = 0 ## i64
  dim = n * n ## i64
  bit = 0 ## i64
  while bit < dim
    if ((value >> bit) & 1) != 0
      row = bit / n ## i64
      col = bit % n ## i64
      if row_domain == domain
        if row == left
          row = right
        else
          if row == right
            row = left
      if col_domain == domain
        if col == left
          col = right
        else
          if col == right
            col = left
      result = result | (1 << (row * n + col))
    bit += 1
  result

# domain: 0=I, 1=K, 2=J.  The factor coordinates are U=(I,K),
# V=(K,J), W=(I,J).
-> ffpa_transform_term(u, v, w, n, domain, left, right, out) (i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  ok = 0 ## i64
  if out.size() >= 3 && n >= 2 && n <= 7 && domain >= 0 && domain < 3
    if left >= 0 && left < right && right < n && u > 0 && v > 0 && w > 0
      out[0] = ffpa_swap_coordinate(u, n, 0, 1, domain, left, right)
      out[1] = ffpa_swap_coordinate(v, n, 1, 2, domain, left, right)
      out[2] = ffpa_swap_coordinate(w, n, 0, 2, domain, left, right)
      ok = 1
  ok

# Apply one of the two orientations of the coordinate cycle
# `(first second third)`.  Permutation matrices satisfy P^-T=P, so the same
# coordinate relabeling is correct on both paired occurrences of the chosen
# contracted index domain.
-> ffpa_cycle_coordinate(value, n, row_domain, col_domain, domain, first, second, third, orientation) (i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  result = 0 ## i64
  dim = n * n ## i64
  bit = 0 ## i64
  while bit < dim
    if ((value >> bit) & 1) != 0
      row = bit / n ## i64
      col = bit % n ## i64
      if row_domain == domain
        original = row ## i64
        if orientation == 0
          if original == first
            row = second
          if original == second
            row = third
          if original == third
            row = first
        else
          if original == first
            row = third
          if original == third
            row = second
          if original == second
            row = first
      if col_domain == domain
        original = col
        if orientation == 0
          if original == first
            col = second
          if original == second
            col = third
          if original == third
            col = first
        else
          if original == first
            col = third
          if original == third
            col = second
          if original == second
            col = first
      result = result | (1 << (row * n + col))
    bit += 1
  result

-> ffpa_cycle_code(n, first, second, third) (i64 i64 i64 i64) i64
  if n < 3 || n > 7 || first < 0 || second < 0 || third < 0 || first >= n || second >= n || third >= n
    return 0 - 1
  if first == second || first == third || second == third
    return 0 - 1
  (first * n + second) * n + third

-> ffpa_transform_term_cycle(u, v, w, n, domain, first, second, third, orientation, out) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  ok = 0 ## i64
  if out.size() >= 3 && domain >= 0 && domain < 3 && orientation >= 0 && orientation < 2 && u > 0 && v > 0 && w > 0
    if ffpa_cycle_code(n, first, second, third) >= 0
      out[0] = ffpa_cycle_coordinate(u, n, 0, 1, domain, first, second, third, orientation)
      out[1] = ffpa_cycle_coordinate(v, n, 1, 2, domain, first, second, third, orientation)
      out[2] = ffpa_cycle_coordinate(w, n, 0, 2, domain, first, second, third, orientation)
      ok = 1
  ok

# Apply an elementary transvection to one factor.  `dual=0` applies
# A=I+E(target,source), while `dual=1` applies A^-T=I+E(source,target).
-> ffpa_shear_factor(value, n, row_domain, row_dual, col_domain, col_dual, domain, source, target) (i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  result = value ## i64
  row = 0 ## i64
  while row < n
    col = 0 ## i64
    while col < n
      bit = row * n + col ## i64
      if ((value >> bit) & 1) != 0
        if row_domain == domain
          if row_dual == 0 && row == source
            result = result ^ (1 << (target * n + col))
          if row_dual != 0 && row == target
            result = result ^ (1 << (source * n + col))
        if col_domain == domain
          if col_dual == 0 && col == source
            result = result ^ (1 << (row * n + target))
          if col_dual != 0 && col == target
            result = result ^ (1 << (row * n + source))
      col += 1
    row += 1
  result

# operation 0 is a coordinate swap; operation 1 is an ordered elementary
# shear; operation 2 is a packed coordinate 3-cycle.  For operation 2,
# `source=(first*n+second)*n+third` and `target` is the orientation bit.  U is
# forward on I/K, V is dual on K and forward on J, and W is dual on I/J,
# exactly preserving the three contraction pairings.
-> ffpa_transform_term_kind(u, v, w, n, operation, domain, source, target, out) (i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  if operation == 0
    return ffpa_transform_term(u, v, w, n, domain, source, target, out)
  if operation == 2
    if n < 3 || n > 7 || source < 0
      return 0
    first = source / (n * n) ## i64
    remainder = source % (n * n) ## i64
    second = remainder / n ## i64
    third = remainder % n ## i64
    return ffpa_transform_term_cycle(u, v, w, n, domain, first, second, third, target, out)
  ok = 0 ## i64
  if operation == 1 && out.size() >= 3 && n >= 2 && n <= 7
    if domain >= 0 && domain < 3 && source >= 0 && source < n && target >= 0 && target < n && source != target
      if u > 0 && v > 0 && w > 0
        out[0] = ffpa_shear_factor(u, n, 0, 0, 1, 0, domain, source, target)
        out[1] = ffpa_shear_factor(v, n, 1, 1, 2, 0, domain, source, target)
        out[2] = ffpa_shear_factor(w, n, 0, 1, 2, 1, domain, source, target)
        ok = 1
  ok

-> ffpa_clear_row(rows, offset, words) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < words
    rows[offset + i] = 0
    i += 1
  words

-> ffpa_xor_outer(rows, offset, u, v, w, n) (i64[] i64 i64 i64 i64 i64) i64
  dim = n * n ## i64
  ai = 0 ## i64
  while ai < dim
    if ((u >> ai) & 1) != 0
      bi = 0 ## i64
      while bi < dim
        if ((v >> bi) & 1) != 0
          ci = 0 ## i64
          while ci < dim
            if ((w >> ci) & 1) != 0
              tensor_bit = (ai * dim + bi) * dim + ci ## i64
              word = tensor_bit / 64 ## i64
              shift = tensor_bit % 64 ## i64
              rows[offset + word] = rows[offset + word] ^ (1 << shift)
            ci += 1
        bi += 1
    ai += 1
  1

-> ffpa_build_deltas_kind(us, vs, ws, count, n, operation, domain, source, target, transformed_u, transformed_v, transformed_w, deltas) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  words = ffpa_tensor_words(n) ## i64
  ok = 1 ## i64
  if count < 1 || transformed_u.size() < count || transformed_v.size() < count || transformed_w.size() < count
    ok = 0
  if deltas.size() < count * words
    ok = 0
  i = 0 ## i64
  out = i64[3]
  while i < count && ok == 1
    if ffpa_transform_term_kind(us[i], vs[i], ws[i], n, operation, domain, source, target, out) != 1
      ok = 0
    if ok == 1
      transformed_u[i] = out[0]
      transformed_v[i] = out[1]
      transformed_w[i] = out[2]
      z = ffpa_clear_row(deltas, i * words, words) ## i64
      z = ffpa_xor_outer(deltas, i * words, us[i], vs[i], ws[i], n)
      z = ffpa_xor_outer(deltas, i * words, out[0], out[1], out[2], n)
    i += 1
  if ok == 0
    return 0
  words

-> ffpa_build_deltas(us, vs, ws, count, n, domain, left, right, transformed_u, transformed_v, transformed_w, deltas) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  ffpa_build_deltas_kind(us, vs, ws, count, n, 0, domain, left, right, transformed_u, transformed_v, transformed_w, deltas)

-> ffpa_row_equal(rows, left_offset, right_offset, words) (i64[] i64 i64 i64) i64
  same = 1 ## i64
  i = 0 ## i64
  while i < words && same == 1
    if rows[left_offset + i] != rows[right_offset + i]
      same = 0
    i += 1
  same

-> ffpa_pair_equal(rows, a, b, c, d, words) (i64[] i64 i64 i64 i64 i64) i64
  same = 1 ## i64
  i = 0 ## i64
  while i < words && same == 1
    left = rows[a * words + i] ^ rows[b * words + i] ## i64
    right = rows[c * words + i] ^ rows[d * words + i] ## i64
    if left != right
      same = 0
    i += 1
  same

-> ffpa_pair_equals_single(rows, a, b, c, words) (i64[] i64 i64 i64 i64) i64
  same = 1 ## i64
  i = 0 ## i64
  while i < words && same == 1
    if (rows[a * words + i] ^ rows[b * words + i]) != rows[c * words + i]
      same = 0
    i += 1
  same

-> ffpa_hash_word(hash, value) (i64 i64) i64
  mixed = value ^ (value >> 23) ^ (value << 17) ## i64
  (hash ^ mixed) * 6364136223846793005 + 1442695040888963407

-> ffpa_hash_row(rows, offset, words) (i64[] i64 i64) i64
  hash = 7046029254386353131 ## i64
  i = 0 ## i64
  while i < words
    hash = ffpa_hash_word(hash, rows[offset + i])
    i += 1
  hash

-> ffpa_hash_pair(rows, a, b, words) (i64[] i64 i64 i64) i64
  hash = 7046029254386353131 ## i64
  i = 0 ## i64
  while i < words
    hash = ffpa_hash_word(hash, rows[a * words + i] ^ rows[b * words + i])
    i += 1
  hash

-> ffpa_same_term(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  same = 0 ## i64
  if u0 == u1 && v0 == v1 && w0 == w1
    same = 1
  same

-> ffpa_selected_image_same_set(us, vs, ws, transformed_u, transformed_v, transformed_w, ids, count) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  same = 1 ## i64
  i = 0 ## i64
  while i < count && same == 1
    source = ids[i] ## i64
    found = 0 ## i64
    j = 0 ## i64
    while j < count
      target = ids[j] ## i64
      if ffpa_same_term(transformed_u[source], transformed_v[source], transformed_w[source], us[target], vs[target], ws[target]) == 1
        found = 1
      j += 1
    if found == 0
      same = 0
    i += 1
  same

-> ffpa_candidate_ok(us, vs, ws, transformed_u, transformed_v, transformed_w, ids, count) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  ok = 1 ## i64
  i = 0 ## i64
  while i < count
    j = i + 1 ## i64
    while j < count
      if ids[i] == ids[j]
        ok = 0
      j += 1
    i += 1
  if ok == 1
    if ffpa_selected_image_same_set(us, vs, ws, transformed_u, transformed_v, transformed_w, ids, count) == 1
      ok = 0
  ok

-> ffpa_table_capacity(entries) (i64) i64
  capacity = 16 ## i64
  while capacity < entries * 2
    capacity *= 2
  capacity

# Complete exact search for a nontrivial relation of cardinality 2, 3, or 4.
# meta[0]=word comparisons, meta[1]=hash buckets, meta[2]=relations rejected
# as global orbit/no-op sets, meta[3]=result size.
-> ffpa_find_subset(us, vs, ws, transformed_u, transformed_v, transformed_w, deltas, count, words, wanted, out_ids, meta) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64[] i64[]) i64
  found = 0 ## i64
  meta[0] = 0
  meta[1] = 0
  meta[2] = 0
  meta[3] = 0
  if wanted < 2 || wanted > 4 || count < wanted
    return 0

  if wanted == 2
    a = 0 ## i64
    while a < count && found == 0
      b = a + 1 ## i64
      while b < count && found == 0
        meta[0] = meta[0] + words
        if ffpa_row_equal(deltas, a * words, b * words, words) == 1
          ids = i64[4]
          ids[0] = a
          ids[1] = b
          if ffpa_candidate_ok(us, vs, ws, transformed_u, transformed_v, transformed_w, ids, 2) == 1
            out_ids[0] = a
            out_ids[1] = b
            found = 2
          else
            meta[2] = meta[2] + 1
        b += 1
      a += 1

  if wanted == 3
    capacity = ffpa_table_capacity(count) ## i64
    meta[1] = capacity
    heads = i32[capacity]
    nexts = i32[count]
    i = 0 ## i64
    while i < count
      slot = ffpa_hash_row(deltas, i * words, words) & (capacity - 1) ## i64
      nexts[i] = heads[slot]
      heads[slot] = i + 1
      i += 1
    a = 0
    while a < count && found == 0
      b = a + 1 ## i64
      while b < count && found == 0
        slot = ffpa_hash_pair(deltas, a, b, words) & (capacity - 1) ## i64
        chain = heads[slot] ## i64
        while chain != 0 && found == 0
          c = chain - 1 ## i64
          if c != a && c != b
            meta[0] = meta[0] + words
            if ffpa_pair_equals_single(deltas, a, b, c, words) == 1
              ids = i64[4]
              ids[0] = a
              ids[1] = b
              ids[2] = c
              if ffpa_candidate_ok(us, vs, ws, transformed_u, transformed_v, transformed_w, ids, 3) == 1
                out_ids[0] = a
                out_ids[1] = b
                out_ids[2] = c
                found = 3
              else
                meta[2] = meta[2] + 1
          chain = nexts[c]
        b += 1
      a += 1

  if wanted == 4
    pairs = count * (count - 1) / 2 ## i64
    capacity = ffpa_table_capacity(pairs) ## i64
    meta[1] = capacity
    heads = i32[capacity]
    nexts = i32[pairs]
    pair_a = i32[pairs]
    pair_b = i32[pairs]
    pair_id = 0 ## i64
    a = 0
    while a < count && found == 0
      b = a + 1 ## i64
      while b < count && found == 0
        hash = ffpa_hash_pair(deltas, a, b, words) ## i64
        slot = hash & (capacity - 1) ## i64
        chain = heads[slot] ## i64
        while chain != 0 && found == 0
          prior = chain - 1 ## i64
          c = pair_a[prior] ## i64
          d = pair_b[prior] ## i64
          if a != c && a != d && b != c && b != d
            meta[0] = meta[0] + words
            if ffpa_pair_equal(deltas, a, b, c, d, words) == 1
              ids = i64[4]
              ids[0] = a
              ids[1] = b
              ids[2] = c
              ids[3] = d
              if ffpa_candidate_ok(us, vs, ws, transformed_u, transformed_v, transformed_w, ids, 4) == 1
                i = 0
                while i < 4
                  out_ids[i] = ids[i]
                  i += 1
                found = 4
              else
                meta[2] = meta[2] + 1
          chain = nexts[prior]
        pair_a[pair_id] = a
        pair_b[pair_id] = b
        nexts[pair_id] = heads[slot]
        heads[slot] = pair_id + 1
        pair_id += 1
        b += 1
      a += 1
  meta[3] = found
  found

-> ffpa_relation_exact(deltas, ids, count, words) (i64[] i64[] i64 i64) i64
  exact = 1 ## i64
  word = 0 ## i64
  while word < words && exact == 1
    value = 0 ## i64
    i = 0 ## i64
    while i < count
      value = value ^ deltas[ids[i] * words + word]
      i += 1
    if value != 0
      exact = 0
    word += 1
  exact

# Enumerate every swap and elementary shear over a rotating term window.
# out_ids are positions in the original arrays.  meta layout:
# [0] operation; [1..3] domain,source,target; [4] window; [5] wanted;
# [6] tensor words; [7] automorphisms attempted; [8] exact candidates found.
-> ffpa_enumerate_terms(us, vs, ws, rank, n, window, offset, wanted, out_ids, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[]) i64
  found = 0 ## i64
  if rank < wanted || wanted < 2 || wanted > 4 || n < 2 || n > 7
    return 0
  count = window ## i64
  if count < wanted || count > rank
    count = rank
  pu = i64[count]
  pv = i64[count]
  pw = i64[count]
  positions = i64[count]
  i = 0 ## i64
  start = offset % rank ## i64
  while i < count
    source = (start + i) % rank ## i64
    positions[i] = source
    pu[i] = us[source]
    pv[i] = vs[source]
    pw[i] = ws[source]
    i += 1
  words = ffpa_tensor_words(n) ## i64
  transformed_u = i64[count]
  transformed_v = i64[count]
  transformed_w = i64[count]
  deltas = i64[count * words]
  local_ids = i64[4]
  search_meta = i64[4]
  attempts = 0 ## i64
  operation = 0 ## i64
  while operation < 2 && found == 0
    domain = 0 ## i64
    while domain < 3 && found == 0
      source = 0 ## i64
      while source < n && found == 0
        target = 0 ## i64
        while target < n && found == 0
          admissible = 0 ## i64
          if operation == 0 && source < target
            admissible = 1
          if operation == 1 && source != target
            admissible = 1
          if admissible == 1
            attempts += 1
            built = ffpa_build_deltas_kind(pu, pv, pw, count, n, operation, domain, source, target, transformed_u, transformed_v, transformed_w, deltas) ## i64
            if built == words
              got = ffpa_find_subset(pu, pv, pw, transformed_u, transformed_v, transformed_w, deltas, count, words, wanted, local_ids, search_meta) ## i64
              if got == wanted && ffpa_relation_exact(deltas, local_ids, wanted, words) == 1
                i = 0
                while i < wanted
                  out_ids[i] = positions[local_ids[i]]
                  i += 1
                meta[0] = operation
                meta[1] = domain
                meta[2] = source
                meta[3] = target
                found = wanted
          target += 1
        source += 1
      domain += 1
    operation += 1
  meta[4] = count
  meta[5] = wanted
  meta[6] = words
  meta[7] = attempts
  meta[8] = found
  found

# Direct coordinate 3-cycle scan.  A composite automorphism can have a valid
# partial relation even when neither elementary transposition has an exact
# intermediate subset, so this is intentionally not reduced to two calls of
# `ffpa_enumerate_terms`.  The same complete 2/3/4-subset delta solver is used.
# meta layout:
# [0] operation=2; [1..5] domain,first,second,third,orientation;
# [6] window; [7] wanted; [8] tensor words; [9] cycles attempted; [10] found.
-> ffpa_enumerate_cycle_terms(us, vs, ws, rank, n, window, offset, wanted, out_ids, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[]) i64
  if meta.size() < 11 || out_ids.size() < wanted
    return 0
  i = 0 ## i64
  while i < 11
    meta[i] = 0
    i += 1
  found = 0 ## i64
  if rank < wanted || wanted < 2 || wanted > 4 || n < 3 || n > 7
    return 0
  count = window ## i64
  if count < wanted || count > rank
    count = rank
  pu = i64[count]
  pv = i64[count]
  pw = i64[count]
  positions = i64[count]
  start = offset % rank ## i64
  i = 0
  while i < count
    source_position = (start + i) % rank ## i64
    positions[i] = source_position
    pu[i] = us[source_position]
    pv[i] = vs[source_position]
    pw[i] = ws[source_position]
    i += 1
  words = ffpa_tensor_words(n) ## i64
  transformed_u = i64[count]
  transformed_v = i64[count]
  transformed_w = i64[count]
  deltas = i64[count * words]
  local_ids = i64[4]
  search_meta = i64[4]
  attempts = 0 ## i64
  domain = 0 ## i64
  while domain < 3 && found == 0
    first = 0 ## i64
    while first < n - 2 && found == 0
      second = first + 1 ## i64
      while second < n - 1 && found == 0
        third = second + 1 ## i64
        while third < n && found == 0
          orientation = 0 ## i64
          while orientation < 2 && found == 0
            attempts += 1
            code = ffpa_cycle_code(n, first, second, third) ## i64
            built = ffpa_build_deltas_kind(pu, pv, pw, count, n, 2, domain, code, orientation, transformed_u, transformed_v, transformed_w, deltas) ## i64
            if built == words
              got = ffpa_find_subset(pu, pv, pw, transformed_u, transformed_v, transformed_w, deltas, count, words, wanted, local_ids, search_meta) ## i64
              if got == wanted && ffpa_relation_exact(deltas, local_ids, wanted, words) == 1
                i = 0
                while i < wanted
                  out_ids[i] = positions[local_ids[i]]
                  i += 1
                meta[0] = 2
                meta[1] = domain
                meta[2] = first
                meta[3] = second
                meta[4] = third
                meta[5] = orientation
                found = wanted
            orientation += 1
          third += 1
        second += 1
      first += 1
    domain += 1
  meta[6] = count
  meta[7] = wanted
  meta[8] = words
  meta[9] = attempts
  meta[10] = found
  found

# Bounded evidence collector for real frontiers.  Each direct 3-cycle is built
# once, then queried for all supported relation cardinalities.  A hit count is
# the number of automorphisms having at least one exact non-noop relation in
# the rotating window, not the (potentially much larger) number of subsets.
# stats: window,words,attempts,hits2,hits3,hits4,word-comparisons,no-op rejects.
-> ffpa_audit_cycle_terms(us, vs, ws, rank, n, window, offset, stats) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  if stats.size() < 8 || rank < 2 || n < 3 || n > 7
    return 0
  i = 0 ## i64
  while i < 8
    stats[i] = 0
    i += 1
  count = window ## i64
  if count < 2 || count > rank
    count = rank
  pu = i64[count]
  pv = i64[count]
  pw = i64[count]
  start = offset % rank ## i64
  i = 0
  while i < count
    source_position = (start + i) % rank ## i64
    pu[i] = us[source_position]
    pv[i] = vs[source_position]
    pw[i] = ws[source_position]
    i += 1
  words = ffpa_tensor_words(n) ## i64
  transformed_u = i64[count]
  transformed_v = i64[count]
  transformed_w = i64[count]
  deltas = i64[count * words]
  local_ids = i64[4]
  search_meta = i64[4]
  attempts = 0 ## i64
  comparisons = 0 ## i64
  rejects = 0 ## i64
  domain = 0 ## i64
  while domain < 3
    first = 0 ## i64
    while first < n - 2
      second = first + 1 ## i64
      while second < n - 1
        third = second + 1 ## i64
        while third < n
          orientation = 0 ## i64
          while orientation < 2
            attempts += 1
            code = ffpa_cycle_code(n, first, second, third) ## i64
            built = ffpa_build_deltas_kind(pu, pv, pw, count, n, 2, domain, code, orientation, transformed_u, transformed_v, transformed_w, deltas) ## i64
            if built == words
              wanted = 2 ## i64
              while wanted <= 4
                if wanted <= count
                  got = ffpa_find_subset(pu, pv, pw, transformed_u, transformed_v, transformed_w, deltas, count, words, wanted, local_ids, search_meta) ## i64
                  comparisons += search_meta[0]
                  rejects += search_meta[2]
                  if got == wanted && ffpa_relation_exact(deltas, local_ids, wanted, words) == 1
                    stats[1 + wanted] = stats[1 + wanted] + 1
                wanted += 1
            orientation += 1
          third += 1
        second += 1
      first += 1
    domain += 1
  stats[0] = count
  stats[1] = words
  stats[2] = attempts
  stats[6] = comparisons
  stats[7] = rejects
  attempts

-> ffpa_positions_valid(selected, count, rank) (i64[] i64 i64) i64
  ok = 1 ## i64
  i = 0 ## i64
  while i < count
    if selected[i] < 0 || selected[i] >= rank
      ok = 0
    j = i + 1 ## i64
    while j < count
      if selected[i] == selected[j]
        ok = 0
      j += 1
    i += 1
  ok

# Apply a proven relation to the current worker view.  Collisions with live
# unselected terms are intentionally legal: XOR-set cancellation is a genuine
# rank-changing consequence of the identity.
-> ffpa_apply_current_kind(st, selected, count, operation, domain, source, target) (i64[] i64[] i64 i64 i64 i64 i64) i64
  result = 0 - 1 ## i64
  if ffw_valid(st) != 1 || count < 2 || count > 4
    return result
  old_rank = st[6] ## i64
  if ffpa_positions_valid(selected, count, old_rank) != 1
    return result
  if ffw_verify_current_exact(st, st[2]) != 1
    return result
  su = i64[count]
  sv = i64[count]
  sw = i64[count]
  tu = i64[count]
  tv = i64[count]
  tw = i64[count]
  deltas = i64[count * ffpa_tensor_words(st[2])]
  i = 0 ## i64
  while i < count
    position = selected[i] ## i64
    slot = st[st[50] + position] ## i64
    su[i] = st[st[44] + slot]
    sv[i] = st[st[45] + slot]
    sw[i] = st[st[46] + slot]
    i += 1
  words = ffpa_build_deltas_kind(su, sv, sw, count, st[2], operation, domain, source, target, tu, tv, tw, deltas) ## i64
  local_ids = i64[4]
  i = 0
  while i < count
    local_ids[i] = i
    i += 1
  valid = 0 ## i64
  if words > 0
    valid = 1
  if valid == 1 && ffpa_relation_exact(deltas, local_ids, count, words) != 1
    valid = 0
  if valid == 1 && ffpa_selected_image_same_set(su, sv, sw, tu, tv, tw, local_ids, count) == 1
    valid = 0
  if valid != 1
    return result

  rank = old_rank ## i64
  i = 0
  while i < count
    rank = ffw_toggle(st, su[i], sv[i], sw[i], rank)
    i += 1
  i = 0
  while i < count
    rank = ffw_toggle(st, tu[i], tv[i], tw[i], rank)
    i += 1
  st[6] = rank
  if rank > 0 && rank <= st[4] && ffw_verify_current_exact(st, st[2]) == 1
    result = rank
  if result < 0
    i = 0
    while i < count
      rank = ffw_toggle(st, tu[i], tv[i], tw[i], rank)
      i += 1
    i = 0
    while i < count
      rank = ffw_toggle(st, su[i], sv[i], sw[i], rank)
      i += 1
    st[6] = rank
    z = ffw_verify_current_exact(st, st[2])
  result

-> ffpa_apply_current(st, selected, count, domain, left, right) (i64[] i64[] i64 i64 i64 i64) i64
  ffpa_apply_current_kind(st, selected, count, 0, domain, left, right)

-> ffpa_apply_current_cycle(st, selected, count, domain, first, second, third, orientation) (i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  code = ffpa_cycle_code(st[2], first, second, third) ## i64
  if code < 0
    return 0 - 1
  ffpa_apply_current_kind(st, selected, count, 2, domain, code, orientation)

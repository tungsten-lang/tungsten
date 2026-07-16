# Exact Sedoglavic/Strassen-pad composer for <7,7,7> over GF(2).
#
# Canonical inputs are exact schemes for <4,4,4>, <3,3,4>, and <3,4,4>.
# The seven-product identity gives
#
#   R(7,7,7) <= R(4,4,4) + 3 R(3,3,4) + 3 R(3,4,4).
#
# `ffsc_compose_files` parses ordinary Metaflip seed files, exhaustively
# verifies every input tensor, composes with GF(2) duplicate cancellation,
# exhaustively verifies the complete 7x7 tensor, and only then writes output.
# It has no Python/runtime-tool dependency and is safe to import from the
# native coordinator.
#
# Stable variants:
#   0  density-best coordinate placement (d2952 for checked-in components)
#   1  canonical sparse placement       (d2958 for checked-in components)
#   2  connectivity placement           (recipe documented with its seed)

-> ffsc_parse_i64(text) (String) i64
  cut = text.size() - 7 ## i64
  value = 0 ## i64
  if cut > 0
    high = text.slice(0, cut).to_i() ## i64
    low = text.slice(cut, 7).to_i() ## i64
    value = high * 10000000 + low
  if cut <= 0
    value = text.to_i()
  value

-> ffsc_load(path, us, vs, ws, cap) (String i64[] i64[] i64[] i64) i64
  content = read_file(path)
  if content == nil
    return 0 - 1
  lines = content.split("\n")
  if lines.size() < 1
    return 0 - 1
  first = lines[0].split(" ")
  line_base = 1 ## i64
  field_base = 0 ## i64
  rank = lines[0].to_i() ## i64
  if first.size() >= 4 && first[0] == "R"
    line_base = 0
    field_base = 1
    rank = lines.size()
    if rank > 0 && lines[rank - 1].size() == 0
      rank -= 1
  if rank < 1 || rank > cap || lines.size() < rank + line_base
    return 0 - 1
  i = 0 ## i64
  while i < rank
    fields = lines[i + line_base].split(" ")
    if fields.size() < field_base + 3
      return 0 - 1
    u = ffsc_parse_i64(fields[field_base]) ## i64
    v = ffsc_parse_i64(fields[field_base + 1]) ## i64
    w = ffsc_parse_i64(fields[field_base + 2]) ## i64
    if u <= 0 || v <= 0 || w <= 0
      return 0 - 1
    j = 0 ## i64
    while j < i
      if us[j] == u && vs[j] == v && ws[j] == w
        return 0 - 1
      j += 1
    us[i] = u
    vs[i] = v
    ws[i] = w
    i += 1
  rank

# Exhaustive coefficient check, including every off-support coefficient.
-> ffsc_verify_exact(us, vs, ws, rank, n, m, p) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  if rank < 1 || n < 1 || m < 1 || p < 1
    return 0
  ab = n * m ## i64
  bc = m * p ## i64
  ac = n * p ## i64
  umask = (1 << ab) - 1 ## i64
  vmask = (1 << bc) - 1 ## i64
  wmask = (1 << ac) - 1 ## i64
  t = 0 ## i64
  while t < rank
    if us[t] <= 0 || (us[t] & umask) != us[t]
      return 0
    if vs[t] <= 0 || (vs[t] & vmask) != vs[t]
      return 0
    if ws[t] <= 0 || (ws[t] & wmask) != ws[t]
      return 0
    t += 1
  ai = 0 ## i64
  while ai < ab
    bi = 0 ## i64
    while bi < bc
      ci = 0 ## i64
      while ci < ac
        ii = ai / m ## i64
        jj = ai % m ## i64
        jj2 = bi / p ## i64
        kk = bi % p ## i64
        ii2 = ci / p ## i64
        kk2 = ci % p ## i64
        parity = 0 ## i64
        if ii == ii2 && jj == jj2 && kk == kk2
          parity = 1
        t = 0
        while t < rank
          if ((us[t] >> ai) & 1) == 1 && ((vs[t] >> bi) & 1) == 1 && ((ws[t] >> ci) & 1) == 1
            parity = parity ^ 1
          t += 1
        if parity != 0
          return 0
        ci += 1
      bi += 1
    ai += 1
  1

-> ffsc_transpose(mask, rows, cols) (i64 i64 i64) i64
  result = 0 ## i64
  b = 0 ## i64
  while b < rows * cols
    if ((mask >> b) & 1) == 1
      i = b / cols ## i64
      j = b % cols ## i64
      result = result | (1 << (j * rows + i))
    b += 1
  result

# Small fixed permutations used by the reproducible recipes.
# 0 identity; 1 maps [0,1,2,3] -> [0,3,1,2]; 2 swaps 2 and 3.
-> ffsc_perm_index(code, x) (i64 i64) i64
  if code == 1
    if x == 1
      return 3
    if x == 2
      return 1
    if x == 3
      return 2
  if code == 2
    if x == 2
      return 3
    if x == 3
      return 2
  x

-> ffsc_permute(mask, rows, cols, row_code, col_code) (i64 i64 i64 i64 i64) i64
  result = 0 ## i64
  b = 0 ## i64
  while b < rows * cols
    if ((mask >> b) & 1) == 1
      i = b / cols ## i64
      j = b % cols ## i64
      ni = ffsc_perm_index(row_code, i) ## i64
      nj = ffsc_perm_index(col_code, j) ## i64
      result = result | (1 << (ni * cols + nj))
    b += 1
  result

-> ffsc_permute_packed(mask, rows, cols, row_map, col_map) (i64 i64 i64 i64 i64) i64
  result = 0 ## i64
  b = 0 ## i64
  while b < rows * cols
    if ((mask >> b) & 1) == 1
      i = b / cols ## i64
      j = b % cols ## i64
      ni = (row_map >> (2 * i)) & 3 ## i64
      nj = (col_map >> (2 * j)) & 3 ## i64
      result = result | (1 << (ni * cols + nj))
    b += 1
  result

# Variant-2 placement found by the checked-in coordinate recipe search. Each
# value packs a permutation with two bits per source coordinate.
-> ffsc_connectivity_map(group, axis) (i64 i64) i64
  if group == 0
    if axis == 0
      return 210
    if axis == 1
      return 30
    return 198
  if group == 1
    if axis == 0
      return 27
    if axis == 1
      return 114
    return 6
  if group == 2
    if axis == 0
      return 6
    if axis == 1
      return 54
    return 39
  if group == 3
    if axis == 0
      return 54
    if axis == 1
      return 6
    return 27
  if group == 4
    if axis == 0
      return 198
    return 6
  if group == 5
    if axis == 0
      return 9
    if axis == 1
      return 6
    return 27
  if axis == 0
    return 9
  if axis == 1
    return 27
  6

-> ffsc_group_n(group) (i64) i64
  if group == 0 || group == 1 || group == 3 || group == 4
    return 4
  3

-> ffsc_group_m(group) (i64) i64
  if group <= 2 || group == 6
    return 4
  3

-> ffsc_group_p(group) (i64) i64
  if group == 1 || group == 4 || group == 6
    return 3
  4

# Orient one canonical component term to the group tensor, then apply its
# fixed coordinate placement. Group order: M1, M3, M2, M7, M5, M4, M6 in
# the standard Strassen notation used by the block maps below.
-> ffsc_orient(group, u, v, w, variant, out) (i64 i64 i64 i64 i64 i64[]) i64
  ou = u ## i64
  ov = v ## i64
  ow = w ## i64
  # Groups 1..3 consume canonical <3,4,4>.
  if group == 1
    # swap: <3,4,4> -> <4,4,3>, (V^T,U^T,W^T)
    ou = ffsc_transpose(v, 4, 4)
    ov = ffsc_transpose(u, 3, 4)
    ow = ffsc_transpose(w, 3, 4)
  if group == 2
    ou = u
    ov = v
    ow = w
  if group == 3
    # swap then rotate: <3,4,4> -> <4,3,4>, (U^T,W,V)
    ou = ffsc_transpose(u, 3, 4)
    ov = w
    ow = v
  # Groups 4..6 consume canonical <3,3,4>.
  if group == 4
    # swap: <3,3,4> -> <4,3,3>, (V^T,U^T,W^T)
    ou = ffsc_transpose(v, 3, 4)
    ov = ffsc_transpose(u, 3, 3)
    ow = ffsc_transpose(w, 3, 4)
  if group == 5
    ou = u
    ov = v
    ow = w
  if group == 6
    # swap, rotate twice: <3,3,4> -> <3,4,3>, (W,V^T,U)
    ou = w
    ov = ffsc_transpose(v, 3, 4)
    ow = u

  n = ffsc_group_n(group) ## i64
  m = ffsc_group_m(group) ## i64
  p = ffsc_group_p(group) ## i64
  pi = 0 ## i64
  pj = 0 ## i64
  pk = 0 ## i64
  if group == 0 && variant == 0
    # The sole difference between d2958 and d2952: put the sparsest C
    # coordinate on the unreplicated fourth block coordinate.
    pk = 2
  if group == 1
    pi = 1
    pj = 1
  if group == 2
    pj = 1
    pk = 1
  if group == 3
    pi = 1
    pk = 1
  if variant == 2
    pimap = ffsc_connectivity_map(group, 0) ## i64
    pjmap = ffsc_connectivity_map(group, 1) ## i64
    pkmap = ffsc_connectivity_map(group, 2) ## i64
    out[0] = ffsc_permute_packed(ou, n, m, pimap, pjmap)
    out[1] = ffsc_permute_packed(ov, m, p, pjmap, pkmap)
    out[2] = ffsc_permute_packed(ow, n, p, pimap, pkmap)
    return 0
  out[0] = ffsc_permute(ou, n, m, pi, pj)
  out[1] = ffsc_permute(ov, m, p, pj, pk)
  out[2] = ffsc_permute(ow, n, p, pi, pk)
  0

# Map an oriented local factor through its Strassen input/output linear map.
-> ffsc_embed(group, axis, mask, rows, cols) (i64 i64 i64 i64 i64) i64
  result = 0 ## i64
  b = 0 ## i64
  while b < rows * cols
    if ((mask >> b) & 1) == 1
      i = b / cols ## i64
      j = b % cols ## i64
      r1 = i ## i64
      c1 = j ## i64
      r2 = 0 ## i64
      c2 = 0 ## i64
      second = 0 ## i64
      if group == 0
        r1 = i
        c1 = j
        if i < 3 && j < 3
          r2 = 4 + i
          c2 = 4 + j
          second = 1
      if group == 1
        if axis == 0
          r1 = i
          c1 = j
        if axis == 1
          r1 = i
          c1 = 4 + j
          if i < 3
            r2 = 4 + i
            c2 = 4 + j
            second = 1
        if axis == 2
          r1 = i
          c1 = 4 + j
          if i < 3
            r2 = 4 + i
            c2 = 4 + j
            second = 1
      if group == 2
        if axis == 0
          r1 = 4 + i
          c1 = j
          if j < 3
            r2 = 4 + i
            c2 = 4 + j
            second = 1
        if axis == 1
          r1 = i
          c1 = j
        if axis == 2
          r1 = 4 + i
          c1 = j
          if j < 3
            r2 = 4 + i
            c2 = 4 + j
            second = 1
      if group == 3
        if axis == 0
          r1 = i
          c1 = 4 + j
          if i < 3
            r2 = 4 + i
            c2 = 4 + j
            second = 1
        if axis == 1
          r1 = 4 + i
          c1 = j
          if j < 3
            r2 = 4 + i
            c2 = 4 + j
            second = 1
        if axis == 2
          r1 = i
          c1 = j
      if group == 4
        if axis == 0
          r1 = i
          c1 = j
          r2 = i
          c2 = 4 + j
          second = 1
        if axis == 1
          r1 = 4 + i
          c1 = 4 + j
        if axis == 2
          r1 = i
          c1 = j
          r2 = i
          c2 = 4 + j
          second = 1
      if group == 5
        if axis == 0
          r1 = 4 + i
          c1 = 4 + j
        if axis == 1
          r1 = 4 + i
          c1 = j
          r2 = i
          c2 = j
          second = 1
        if axis == 2
          r1 = i
          c1 = j
          r2 = 4 + i
          c2 = j
          second = 1
      if group == 6
        if axis == 0
          r1 = i
          c1 = j
          r2 = 4 + i
          c2 = j
          second = 1
        if axis == 1
          r1 = i
          c1 = j
          r2 = i
          c2 = 4 + j
          second = 1
        if axis == 2
          r1 = 4 + i
          c1 = 4 + j
      result = result ^ (1 << (r1 * 7 + c1))
      if second == 1
        result = result ^ (1 << (r2 * 7 + c2))
    b += 1
  result

-> ffsc_toggle(us, vs, ws, rank, cap, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  if u == 0 || v == 0 || w == 0
    return rank
  i = 0 ## i64
  while i < rank
    if us[i] == u && vs[i] == v && ws[i] == w
      last = rank - 1 ## i64
      us[i] = us[last]
      vs[i] = vs[last]
      ws[i] = ws[last]
      return last
    i += 1
  if rank >= cap
    return 0 - rank - 1
  us[rank] = u
  vs[rank] = v
  ws[rank] = w
  rank + 1

-> ffsc_add_group(cu, cv, cw, crank, group, variant, ou, ov, ow, rank, cap) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64 i64) i64
  n = ffsc_group_n(group) ## i64
  m = ffsc_group_m(group) ## i64
  p = ffsc_group_p(group) ## i64
  term = i64[3]
  i = 0 ## i64
  result = rank ## i64
  while i < crank && result >= 0
    z = ffsc_orient(group, cu[i], cv[i], cw[i], variant, term) ## i64
    u = ffsc_embed(group, 0, term[0], n, m) ## i64
    v = ffsc_embed(group, 1, term[1], m, p) ## i64
    w = ffsc_embed(group, 2, term[2], n, p) ## i64
    result = ffsc_toggle(ou, ov, ow, result, cap, u, v, w)
    i += 1
  result

-> ffsc_density(us, vs, ws, rank) (i64[] i64[] i64[] i64) i64
  total = 0 ## i64
  i = 0 ## i64
  while i < rank
    axis = 0 ## i64
    vals = i64[3]
    vals[0] = us[i]
    vals[1] = vs[i]
    vals[2] = ws[i]
    while axis < 3
      x = vals[axis] ## i64
      while x != 0
        total += x & 1
        x = x >> 1
      axis += 1
    i += 1
  total

-> ffsc_compose_terms(u444, v444, w444, r444, u334, v334, w334, r334, u344, v344, w344, r344, variant, ou, ov, ow, cap) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64) i64
  if variant < 0 || variant > 2
    return 0 - 1
  rank = 0 ## i64
  rank = ffsc_add_group(u444, v444, w444, r444, 0, variant, ou, ov, ow, rank, cap)
  group = 1 ## i64
  while group <= 3 && rank >= 0
    rank = ffsc_add_group(u344, v344, w344, r344, group, variant, ou, ov, ow, rank, cap)
    group += 1
  group = 4
  while group <= 6 && rank >= 0
    rank = ffsc_add_group(u334, v334, w334, r334, group, variant, ou, ov, ow, rank, cap)
    group += 1
  rank

-> ffsc_write(path, us, vs, ws, rank) (String i64[] i64[] i64[] i64) i64
  body = rank.to_s() + "\n"
  i = 0 ## i64
  while i < rank
    body = body + us[i].to_s() + " " + vs[i].to_s() + " " + ws[i].to_s() + "\n"
    i += 1
  if write_file(path, body) == nil
    return 0 - 1
  rank

-> ffsc_compose_files(path444, path334, path344, output_path, variant) (String String String String i64) i64
  cap = 384 ## i64
  u444 = i64[384]
  v444 = i64[384]
  w444 = i64[384]
  u334 = i64[384]
  v334 = i64[384]
  w334 = i64[384]
  u344 = i64[384]
  v344 = i64[384]
  w344 = i64[384]
  ou = i64[384]
  ov = i64[384]
  ow = i64[384]
  r444 = ffsc_load(path444, u444, v444, w444, cap) ## i64
  r334 = ffsc_load(path334, u334, v334, w334, cap) ## i64
  r344 = ffsc_load(path344, u344, v344, w344, cap) ## i64
  if r444 < 1 || r334 < 1 || r344 < 1
    return 0 - 1
  if ffsc_verify_exact(u444, v444, w444, r444, 4, 4, 4) != 1
    return 0 - 1
  if ffsc_verify_exact(u334, v334, w334, r334, 3, 3, 4) != 1
    return 0 - 1
  if ffsc_verify_exact(u344, v344, w344, r344, 3, 4, 4) != 1
    return 0 - 1
  rank = ffsc_compose_terms(u444, v444, w444, r444, u334, v334, w334, r334, u344, v344, w344, r344, variant, ou, ov, ow, cap) ## i64
  if rank < 1
    return 0 - 1
  if ffsc_verify_exact(ou, ov, ow, rank, 7, 7, 7) != 1
    return 0 - 1
  ffsc_write(output_path, ou, ov, ow, rank)

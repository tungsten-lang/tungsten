# Shared exact infrastructure for bounded pooled exact moves.
# Stats: attempts, exact admissions, rank hits, density hits, neutral hits,
# rejects, structural candidates, flags.

use ../scheme
use ../rect

-> ffpe_clear(stats) (i64[]) i64
  i = 0 ## i64
  while i < stats.size()
    stats[i] = 0
    i += 1
  1

-> ffpe_popcount(value) (i64) i64
  ffw_popcount(value)

-> ffpe_density(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  bits = 0 ## i64
  i = 0 ## i64
  while i < count
    bits += ffw_popcount(us[i]) + ffw_popcount(vs[i]) + ffw_popcount(ws[i])
    i += 1
  bits

-> ffpe_copy(su, sv, sw, count, du, dv, dw) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < count
    du[i] = su[i]
    dv[i] = sv[i]
    dw[i] = sw[i]
    i += 1
  count

-> ffpe_axis_get(us, vs, ws, position, axis) (i64[] i64[] i64[] i64 i64) i64
  case axis
    when 0
      us[position]
    when 1
      vs[position]
    when 2
      ws[position]
    else
      0

-> ffpe_axis_set(us, vs, ws, position, axis, value) (i64[] i64[] i64[] i64 i64 i64) i64
  case axis
    when 0
      us[position] = value
    when 1
      vs[position] = value
    when 2
      ws[position] = value
  value

-> ffpe_same_term(us, vs, ws, left, right) (i64[] i64[] i64[] i64 i64) i64
  if us[left] == us[right] && vs[left] == vs[right] && ws[left] == ws[right]
    return 1
  0
# GF(2) parity canonicalization. Zero-factor terms vanish; equal triples cancel.
-> ffpe_compact(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    if us[i] == 0 || vs[i] == 0 || ws[i] == 0
      count -= 1
      us[i] = us[count]
      vs[i] = vs[count]
      ws[i] = ws[count]
    else
      i += 1
  i = 0
  while i < count
    j = i + 1 ## i64
    cancelled = 0 ## i64
    while j < count && cancelled == 0
      if us[i] == us[j] && vs[i] == vs[j] && ws[i] == ws[j]
        count -= 1
        us[j] = us[count]
        vs[j] = vs[count]
        ws[j] = ws[count]
        count -= 1
        us[i] = us[count]
        vs[i] = vs[count]
        ws[i] = ws[count]
        cancelled = 1
      else
        j += 1
    if cancelled == 0
      i += 1
  count

# Exact equality of two arbitrary local tensors over the supplied factor widths.
-> ffpe_local_equal(au, av, aw, acount, bu, bv, bw, bcount, uw, vw, ww) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64) i64
  a = 0 ## i64
  while a < uw
    b = 0 ## i64
    while b < vw
      c = 0 ## i64
      while c < ww
        left = 0 ## i64
        i = 0 ## i64
        while i < acount
          if ((au[i] >> a) & 1) == 1 && ((av[i] >> b) & 1) == 1 && ((aw[i] >> c) & 1) == 1
            left = left ^ 1
          i += 1
        right = 0 ## i64
        i = 0
        while i < bcount
          if ((bu[i] >> a) & 1) == 1 && ((bv[i] >> b) & 1) == 1 && ((bw[i] >> c) & 1) == 1
            right = right ^ 1
          i += 1
        if left != right
          return 0
        c += 1
      b += 1
    a += 1
  1

-> ffpe_mix(value, seed) (i64 i64) i64
  x = value + seed * 1000003 + 97 ## i64
  x = (x ^ (x >> 17)) * 999983
  x = x ^ (x >> 23)
  x

# Linear fingerprints: XOR of the pseudorandom labels of supported cells.
-> ffpe_term_fingerprint(u, v, w, uw, vw, ww, seed) (i64 i64 i64 i64 i64 i64 i64) i64
  result = 0 ## i64
  a = 0 ## i64
  while a < uw
    if ((u >> a) & 1) == 1
      b = 0 ## i64
      while b < vw
        if ((v >> b) & 1) == 1
          c = 0 ## i64
          while c < ww
            if ((w >> c) & 1) == 1
              result = result ^ ffpe_mix((a * vw + b) * ww + c, seed)
            c += 1
        b += 1
    a += 1
  result

-> ffpe_verify_direct(us, vs, ws, rank, n, m, p) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  uw = n * m ## i64
  vw = m * p ## i64
  ww = n * p ## i64
  a = 0 ## i64
  while a < uw
    ai = a / m ## i64
    aj = a % m ## i64
    b = 0 ## i64
    while b < vw
      bj = b / p ## i64
      bk = b % p ## i64
      c = 0 ## i64
      while c < ww
        ci = c / p ## i64
        ck = c % p ## i64
        parity = 0 ## i64
        t = 0 ## i64
        while t < rank
          if ((us[t] >> a) & 1) == 1 && ((vs[t] >> b) & 1) == 1 && ((ws[t] >> c) & 1) == 1
            parity = parity ^ 1
          t += 1
        expected = 0 ## i64
        if ai == ci && aj == bj && bk == ck
          expected = 1
        if parity != expected
          return 0
        c += 1
      b += 1
    a += 1
  1

# Complete independent matrix-multiplication tensor gate, square or rectangular.
-> ffpe_verify(us, vs, ws, rank, n, m, p) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  if rank < 1
    return 0
  capacity = rank + 8 ## i64
  if n == m && m == p
    default_capacity = ffw_default_capacity(n) ## i64
    if capacity < default_capacity
      capacity = default_capacity
    st = i64[ffw_state_size(capacity)]
    got = ffw_init_terms_cap(st, us, vs, ws, rank, n, capacity, 9173, 4, 0, 1000, 1000) ## i64
    if got != rank
      return 0
    return ffw_verify_current_exact(st, n)
  if ffr_supported(n, m, p) == 0
    return ffpe_verify_direct(us, vs, ws, rank, n, m, p)
  default_capacity = ffr_default_capacity(n, m, p)
  if capacity < default_capacity
    capacity = default_capacity
  st = i64[ffr_state_size(capacity)]
  got = ffr_init_terms_cap(st, us, vs, ws, rank, n, m, p, capacity, 9173, 4, 0, 1000, 1000) ## i64
  if got != rank
    return 0
  ffr_verify_current_exact(st, n, m, p)

-> ffpe_load(path, n, m, p, us, vs, ws, cap) (String i64 i64 i64 i64[] i64[] i64[] i64) i64
  capacity = cap ## i64
  if n == m && m == p
    st = i64[ffw_state_size(capacity)]
    rank = ffw_load_scheme_cap(st, path, n, capacity, 19, 4, 0, 1000, 1000) ## i64
    if rank < 1 || ffw_verify_best_exact(st, n) == 0
      return 0 - 1
    z = ffw_export_best(st, us, vs, ws) ## i64
    return rank
  if ffr_supported(n, m, p) == 0
    return 0 - 2
  st = i64[ffr_state_size(capacity)]
  rank = ffr_load_scheme_cap(st, path, n, m, p, capacity, 19, 4, 0, 1000, 1000) ## i64
  if rank < 1 || ffr_verify_best_exact(st, n, m, p) == 0
    return 0 - 1
  z = ffw_export_best(st, us, vs, ws) ## i64
  rank

-> ffpe_selected(selected, count, position) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if selected[i] == position
      return 1
    i += 1
  0

-> ffpe_splice(us, vs, ws, rank, selected, selected_count, rep_u, rep_v, rep_w, replacement_count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  count = 0 ## i64
  i = 0 ## i64
  while i < rank
    is_selected = 0 ## i64
    j = 0 ## i64
    while j < selected_count
      if selected[j] == i
        is_selected = 1
      j += 1
    if is_selected == 0
      out_u[count] = us[i]
      out_v[count] = vs[i]
      out_w[count] = ws[i]
      count += 1
    i += 1
  i = 0
  while i < replacement_count
    out_u[count] = rep_u[i]
    out_v[count] = rep_v[i]
    out_w[count] = rep_w[i]
    count += 1
    i += 1
  ffpe_compact(out_u, out_v, out_w, count)

-> ffpe_note(old_u, old_v, old_w, old_rank, new_u, new_v, new_w, new_rank, n, m, p, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  stats[6] += 1
  if ffpe_verify(new_u, new_v, new_w, new_rank, n, m, p) == 0
    stats[5] += 1
    return 0
  stats[1] += 1
  if new_rank < old_rank
    stats[2] += 1
  if new_rank == old_rank
    old_density = ffpe_density(old_u, old_v, old_w, old_rank) ## i64
    new_density = ffpe_density(new_u, new_v, new_w, new_rank) ## i64
    if new_density < old_density
      stats[3] += 1
    if new_density == old_density
      stats[4] += 1
  1

# Deterministic +1 split plant. Returns rank+1 or zero.
-> ffpe_plant_split(us, vs, ws, rank, out_u, out_v, out_w, nonce) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  pass = 0 ## i64
  while pass < rank * 3
    position = (nonce + pass * 17) % rank ## i64
    axis = (nonce + pass) % 3 ## i64
    factor = ffpe_axis_get(us, vs, ws, position, axis) ## i64
    if ffw_popcount(factor) >= 2
      low = factor & (0 - factor) ## i64
      rest = factor ^ low ## i64
      if low != 0 && rest != 0
        count = 0 ## i64
        i = 0 ## i64
        while i < rank
          if i != position
            out_u[count] = us[i]
            out_v[count] = vs[i]
            out_w[count] = ws[i]
            count += 1
          i += 1
        out_u[count] = us[position]
        out_v[count] = vs[position]
        out_w[count] = ws[position]
        z = ffpe_axis_set(out_u, out_v, out_w, count, axis, low) ## i64
        count += 1
        out_u[count] = us[position]
        out_v[count] = vs[position]
        out_w[count] = ws[position]
        z = ffpe_axis_set(out_u, out_v, out_w, count, axis, rest)
        return count + 1
    pass += 1
  0

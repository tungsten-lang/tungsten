# Exact algebraic escape moves for the native FlipFleet coordinator.
#
# Schemes are three parallel i64 arrays.  Every helper below works by toggling
# terms over GF(2): an existing term is removed, a new term is appended, and a
# term with a zero factor vanishes.  Consequently the split, fixed-cube break,
# orbit-split, polarization, and two-identity composition moves preserve the
# represented tensor before the independent exact adoption gate sees them.

-> ffe_transpose(mask, n) (i64 i64) i64
  out = 0 ## i64
  bit = 0 ## i64
  one = 1 ## i64
  width = n * n ## i64
  while bit < width
    if ((mask >> bit) & one) == one
      row = bit / n ## i64
      col = bit % n ## i64
      out = out | (one << (col * n + row))
    bit += 1
  out

-> ffe_toggle(us, vs, ws, rank, cap, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  if u == 0 || v == 0 || w == 0
    return rank
  found = 0 - 1 ## i64
  i = 0 ## i64
  while i < rank
    if us[i] == u && vs[i] == v && ws[i] == w
      found = i
      i = rank
    else
      i += 1
  if found >= 0
    last = rank - 1 ## i64
    us[found] = us[last]
    vs[found] = vs[last]
    ws[found] = ws[last]
    return last
  if rank >= cap
    return 0 - rank - 1
  us[rank] = u
  vs[rank] = v
  ws[rank] = w
  rank + 1

-> ffe_toggle_orbit(us, vs, ws, rank, cap, u, v, w, n) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  r = ffe_toggle(us, vs, ws, rank, cap, u, v, w) ## i64
  if r < 0
    return r
  u1 = v ## i64
  v1 = ffe_transpose(w, n) ## i64
  w1 = ffe_transpose(u, n) ## i64
  r = ffe_toggle(us, vs, ws, r, cap, u1, v1, w1)
  if r < 0
    return r
  u2 = v1 ## i64
  v2 = ffe_transpose(w1, n) ## i64
  w2 = ffe_transpose(u1, n) ## i64
  ffe_toggle(us, vs, ws, r, cap, u2, v2, w2)

-> ffe_is_fixed(u, v, w, n) (i64 i64 i64 i64) i64
  ok = 0 ## i64
  if u == v
    if w == ffe_transpose(u, n)
      ok = 1
  ok

-> ffe_has_term(us, vs, ws, rank, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  yes = 0 ## i64
  i = 0 ## i64
  while i < rank
    if us[i] == u && vs[i] == v && ws[i] == w
      yes = 1
      i = rank
    else
      i += 1
  yes

-> ffe_is_c3(us, vs, ws, rank, n) (i64[] i64[] i64[] i64 i64) i64
  ok = 1 ## i64
  i = 0 ## i64
  while i < rank
    ru = vs[i] ## i64
    rv = ffe_transpose(ws[i], n) ## i64
    rotated_w = ffe_transpose(us[i], n) ## i64
    if ffe_has_term(us, vs, ws, rank, ru, rv, rotated_w) == 0
      ok = 0
      i = rank
    else
      i += 1
  ok

-> ffe_part_for_axis(us, vs, ws, rank, source, axis) (i64[] i64[] i64[] i64 i64 i64) i64
  old = us[source] ## i64
  if axis == 1
    old = vs[source]
  if axis == 2
    old = ws[source]
  part = 0 ## i64
  k = 1 ## i64
  while k <= rank
    i = (source + k) % rank ## i64
    candidate = us[i] ## i64
    if axis == 1
      candidate = vs[i]
    if axis == 2
      candidate = ws[i]
    if candidate != 0 && candidate != old
      part = candidate
      k = rank + 1
    else
      k += 1
  if part == 0
    part = old ^ 1
    if part == 0
      part = 2
  part

-> ffe_common_part(us, vs, ws, rank, source, x, n) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  part = 0 ## i64
  k = 1 ## i64
  while k <= rank
    i = (source + k) % rank ## i64
    candidate = us[i] ## i64
    if candidate == 0 || candidate == x
      candidate = vs[i]
    if candidate == 0 || candidate == x
      candidate = ffe_transpose(ws[i], n)
    if candidate != 0 && candidate != x
      part = candidate
      k = rank + 1
    else
      k += 1
  if part == 0
    part = x ^ 1
    if part == 0
      part = 2
  part

# Toggle one ordinary factor split.  Returns a negative capacity sentinel on
# failure; metadata is [kind, before, after, source, axis, part, c3, eligible].
-> ffe_split(us, vs, ws, rank, cap, source, axis, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  if rank < 1
    meta[7] = 0
    return rank
  source = source % rank
  axis = axis % 3
  u = us[source] ## i64
  v = vs[source] ## i64
  w = ws[source] ## i64
  old = u ## i64
  if axis == 1
    old = v
  if axis == 2
    old = w
  part = ffe_part_for_axis(us, vs, ws, rank, source, axis) ## i64
  leftu = u ## i64
  leftv = v ## i64
  leftw = w ## i64
  rightu = u ## i64
  rightv = v ## i64
  rightw = w ## i64
  if axis == 0
    leftu = part
    rightu = old ^ part
  if axis == 1
    leftv = part
    rightv = old ^ part
  if axis == 2
    leftw = part
    rightw = old ^ part
  before = rank ## i64
  r = ffe_toggle(us, vs, ws, rank, cap, u, v, w) ## i64
  if r >= 0
    r = ffe_toggle(us, vs, ws, r, cap, leftu, leftv, leftw)
  if r >= 0
    r = ffe_toggle(us, vs, ws, r, cap, rightu, rightv, rightw)
  meta[0] = 1
  meta[1] = before
  meta[2] = r
  meta[3] = source
  meta[4] = axis
  meta[5] = part
  meta[6] = 0
  meta[7] = 1
  r

# Explicit-part form used by lifted cross-tensor identities.  It is the same
# exact GF(2) identity as ffe_split; the caller chooses the embedded subspace.
-> ffe_split_with_part(us, vs, ws, rank, cap, source, axis, part, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[]) i64
  if rank < 1 || part == 0
    meta[7] = 0
    return rank
  source = source % rank
  axis = axis % 3
  u = us[source] ## i64
  v = vs[source] ## i64
  w = ws[source] ## i64
  old = u ## i64
  if axis == 1
    old = v
  if axis == 2
    old = w
  if part == old
    meta[7] = 0
    return rank
  leftu = u ## i64
  leftv = v ## i64
  leftw = w ## i64
  rightu = u ## i64
  rightv = v ## i64
  rightw = w ## i64
  if axis == 0
    leftu = part
    rightu = old ^ part
  if axis == 1
    leftv = part
    rightv = old ^ part
  if axis == 2
    leftw = part
    rightw = old ^ part
  before = rank ## i64
  r = ffe_toggle(us, vs, ws, rank, cap, u, v, w) ## i64
  if r >= 0
    r = ffe_toggle(us, vs, ws, r, cap, leftu, leftv, leftw)
  if r >= 0
    r = ffe_toggle(us, vs, ws, r, cap, rightu, rightv, rightw)
  meta[0] = 6
  meta[1] = before
  meta[2] = r
  meta[3] = source
  meta[4] = axis
  meta[5] = part
  meta[6] = 0
  meta[7] = 1
  r

-> ffe_fixed_source(us, vs, ws, rank, n, ordinal) (i64[] i64[] i64[] i64 i64 i64) i64
  count = 0 ## i64
  ci = 0 ## i64
  while ci < rank
    if ffe_is_fixed(us[ci], vs[ci], ws[ci], n) == 1
      count += 1
    ci += 1
  if count == 0
    return 0 - 1
  target = ordinal % count ## i64
  found = 0 - 1 ## i64
  seen = 0 ## i64
  i = 0 ## i64
  while i < rank
    if ffe_is_fixed(us[i], vs[i], ws[i], n) == 1
      if seen == target
        found = i
        i = rank
      else
        seen += 1
        i += 1
    else
      i += 1
  found

-> ffe_break(us, vs, ws, rank, cap, n, ordinal, axis, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[]) i64
  source = ffe_fixed_source(us, vs, ws, rank, n, ordinal) ## i64
  if source < 0
    meta[0] = 2
    meta[1] = rank
    meta[2] = rank
    meta[7] = 0
    return rank
  r = ffe_split(us, vs, ws, rank, cap, source, axis, meta) ## i64
  meta[0] = 2
  r

-> ffe_orbit_split(us, vs, ws, rank, cap, n, ordinal, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  before = rank ## i64
  source = ffe_fixed_source(us, vs, ws, rank, n, ordinal) ## i64
  if source < 0 || ffe_is_c3(us, vs, ws, rank, n) == 0
    meta[0] = 3
    meta[1] = before
    meta[2] = before
    meta[7] = 0
    return rank
  x = us[source] ## i64
  xt = ffe_transpose(x, n) ## i64
  part = ffe_common_part(us, vs, ws, rank, source, x, n) ## i64
  r = ffe_toggle(us, vs, ws, rank, cap, x, x, xt) ## i64
  if r >= 0
    r = ffe_toggle_orbit(us, vs, ws, r, cap, part, x, xt, n)
  if r >= 0
    r = ffe_toggle_orbit(us, vs, ws, r, cap, x ^ part, x, xt, n)
  meta[0] = 3
  meta[1] = before
  meta[2] = r
  meta[3] = source
  meta[4] = 0 - 1
  meta[5] = part
  meta[6] = 1
  meta[7] = 1
  r

-> ffe_polarize(us, vs, ws, rank, cap, n, ordinal, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  before = rank ## i64
  source = ffe_fixed_source(us, vs, ws, rank, n, ordinal) ## i64
  if source < 0 || ffe_is_c3(us, vs, ws, rank, n) == 0
    meta[0] = 4
    meta[1] = before
    meta[2] = before
    meta[7] = 0
    return rank
  x = us[source] ## i64
  y = ffe_common_part(us, vs, ws, rank, source, x, n) ## i64
  xt = ffe_transpose(x, n) ## i64
  yt = ffe_transpose(y, n) ## i64
  xyt = ffe_transpose(x ^ y, n) ## i64
  r = ffe_toggle(us, vs, ws, rank, cap, x, x, xt) ## i64
  if r >= 0
    r = ffe_toggle(us, vs, ws, r, cap, y, y, yt)
  if r >= 0
    r = ffe_toggle(us, vs, ws, r, cap, x ^ y, x ^ y, xyt)
  if r >= 0
    r = ffe_toggle_orbit(us, vs, ws, r, cap, x, x, yt, n)
  if r >= 0
    r = ffe_toggle_orbit(us, vs, ws, r, cap, x, y, yt, n)
  meta[0] = 4
  meta[1] = before
  meta[2] = r
  meta[3] = source
  meta[4] = 0 - 1
  meta[5] = y
  meta[6] = 1
  meta[7] = 1
  r

-> ffe_compose(us, vs, ws, rank, cap, nonce, meta) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  before = rank ## i64
  scratch = i64[8]
  r = ffe_split(us, vs, ws, rank, cap, nonce % rank, nonce % 3, scratch) ## i64
  if r >= 0
    r = ffe_split(us, vs, ws, r, cap, (nonce * 7 + 3) % r, (nonce + 1) % 3, scratch)
  meta[0] = 5
  meta[1] = before
  meta[2] = r
  meta[3] = nonce
  meta[4] = 0 - 1
  meta[5] = 0
  meta[6] = 0
  meta[7] = 1
  r

# Unified deterministic portfolio entry point.
# kind: 1 split, 2 fixed-cube break, 3 orbit-split, 4 polarization, 5 compose.
-> ffe_apply(us, vs, ws, rank, cap, n, kind, nonce, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[]) i64
  if kind == 1
    return ffe_split(us, vs, ws, rank, cap, nonce % rank, nonce % 3, meta)
  if kind == 2
    return ffe_break(us, vs, ws, rank, cap, n, nonce % 8, nonce % 3, meta)
  if kind == 3
    return ffe_orbit_split(us, vs, ws, rank, cap, n, nonce % 8, meta)
  if kind == 4
    return ffe_polarize(us, vs, ws, rank, cap, n, nonce % 8, meta)
  if kind == 5
    return ffe_compose(us, vs, ws, rank, cap, nonce, meta)
  meta[0] = kind
  meta[1] = rank
  meta[2] = rank
  meta[7] = 0
  rank

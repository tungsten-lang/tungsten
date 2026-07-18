# Order-independent block-seam window selection for exact local refactoring.
#
# Matrix-multiplication factors use the rectangular layouts U=n*m, V=m*p,
# and W=n*p.  Explicit cuts therefore describe a coherent three-axis block
# decomposition rather than assuming that every packed factor is square.
# This module only selects live terms; `span_refactor` remains the exact
# algebra and admission gate.

use ../scheme

-> ffbir_valid_cut(size, cut) (i64 i64) i64
  valid = 0 ## i64
  if size > 1 && cut > 0 && cut < size
    valid = 1
  valid

-> ffbir_default_cut(size) (i64) i64
  cut = 0 ## i64
  if size > 1
    cut = (size + 1) / 2
  cut

# Return a four-bit occupancy mask in row-major block order:
# top-left, top-right, bottom-left, bottom-right.  Invalid dimensions/cuts
# return zero, as does an empty factor mask.
-> ffbir_quadrants(mask, rows, columns, row_cut, column_cut) (i64 i64 i64 i64 i64) i64
  if rows < 1 || columns < 1
    return 0
  if rows * columns > 63
    return 0
  if ffbir_valid_cut(rows,row_cut) == 0 || ffbir_valid_cut(columns,column_cut) == 0
    return 0
  touched = 0 ## i64
  row = 0 ## i64
  while row < rows
    column = 0 ## i64
    while column < columns
      if ((mask >> (row * columns + column)) & 1) != 0
        quadrant = 0 ## i64
        if row >= row_cut
          quadrant += 2
        if column >= column_cut
          quadrant += 1
        touched = touched | (1 << quadrant)
      column += 1
    row += 1
  touched

-> ffbir_quadrant_count(mask, rows, columns, row_cut, column_cut) (i64 i64 i64 i64 i64) i64
  ffw_popcount(ffbir_quadrants(mask,rows,columns,row_cut,column_cut))

# Zero means that every factor stays inside one block quadrant.  Larger
# values identify terms crossing more of the proposed composition seam.
-> ffbir_term_seam_score(u, v, w, n, m, p, cut_n, cut_m, cut_p) (i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  score = 0 ## i64
  uq = ffbir_quadrant_count(u,n,m,cut_n,cut_m) ## i64
  vq = ffbir_quadrant_count(v,m,p,cut_m,cut_p) ## i64
  wq = ffbir_quadrant_count(w,n,p,cut_n,cut_p) ## i64
  if uq > 0
    score += uq - 1
  if vq > 0
    score += vq - 1
  if wq > 0
    score += wq - 1
  score

# Favor the equality and factor reuse on which small exact identities depend,
# then softly favor intersecting/nearby supports.  This score is symmetric in
# the two terms and independent of their live-array positions.
-> ffbir_overlap_score(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  score = 0 ## i64
  if u0 == u1
    score += 48
  if v0 == v1
    score += 48
  if w0 == w1
    score += 48
  if (u0 & u1) != 0
    score += 8
  if (v0 & v1) != 0
    score += 8
  if (w0 & w1) != 0
    score += 8
  score -= ffw_popcount(u0 ^ u1)
  score -= ffw_popcount(v0 ^ v1)
  score -= ffw_popcount(w0 ^ w1)
  score

# Stable content hash used only to rotate ties.  The final lexicographic
# comparison makes collisions deterministic.  Live schemes use nonnegative
# masks of at most 49 bits, so their ordinary integer order is canonical.
-> ffbir_term_hash(u, v, w, nonce) (i64 i64 i64 i64) i64
  value = (u * 6364136223846793005 + v * 1442695040888963407 + w * 3202034522624059733 + (nonce + 1) * 3935559000370003845) & 9223372036854775807 ## i64
  value = value ^ (value >> 29)
  value = (value * 2862933555777941757 + 3037000493) & 9223372036854775807
  value ^ (value >> 31)

-> ffbir_term_before(us, vs, ws, left, right, nonce) (i64[] i64[] i64[] i64 i64 i64) i64
  if right < 0
    return 1
  left_hash = ffbir_term_hash(us[left],vs[left],ws[left],nonce) ## i64
  right_hash = ffbir_term_hash(us[right],vs[right],ws[right],nonce) ## i64
  if left_hash < right_hash
    return 1
  if left_hash > right_hash
    return 0
  if us[left] < us[right]
    return 1
  if us[left] > us[right]
    return 0
  if vs[left] < vs[right]
    return 1
  if vs[left] > vs[right]
    return 0
  if ws[left] < ws[right]
    return 1
  0

-> ffbir_selected(selected, count, position) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if selected[i] == position
      return 1
    i += 1
  0

# Choose k seam-connected terms.  The anchor maximizes seam crossing; a
# nonce-salted content order rotates ties.  Remaining terms maximize the sum
# of seam and pair-overlap scores.  All tie breaks use term contents, so a
# permutation of the live-term array yields the same selected term set.
-> ffbir_choose_window(us, vs, ws, rank, n, m, p, cut_n, cut_m, cut_p, k, nonce, selected) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  if rank < k || k < 3 || k > 4
    return 0
  if n * m > 63 || m * p > 63 || n * p > 63
    return 0
  if ffbir_valid_cut(n,cut_n) == 0 || ffbir_valid_cut(m,cut_m) == 0 || ffbir_valid_cut(p,cut_p) == 0
    return 0

  anchor = 0 - 1 ## i64
  anchor_score = 0 - 1 ## i64
  candidate = 0 ## i64
  while candidate < rank
    seam = ffbir_term_seam_score(us[candidate],vs[candidate],ws[candidate],n,m,p,cut_n,cut_m,cut_p) ## i64
    if seam > anchor_score || (seam == anchor_score && ffbir_term_before(us,vs,ws,candidate,anchor,nonce) == 1)
      anchor = candidate
      anchor_score = seam
    candidate += 1
  if anchor < 0
    return 0

  selected[0] = anchor
  chosen = 1 ## i64
  while chosen < k
    best = 0 - 1 ## i64
    best_score = 0 - 1000000000 ## i64
    candidate = 0
    while candidate < rank
      if ffbir_selected(selected,chosen,candidate) == 0
        score = ffbir_term_seam_score(us[candidate],vs[candidate],ws[candidate],n,m,p,cut_n,cut_m,cut_p) * 64 ## i64
        i = 0 ## i64
        while i < chosen
          other = selected[i] ## i64
          score += ffbir_overlap_score(us[candidate],vs[candidate],ws[candidate],us[other],vs[other],ws[other])
          i += 1
        if score > best_score || (score == best_score && ffbir_term_before(us,vs,ws,candidate,best,nonce + chosen * 1009) == 1)
          best = candidate
          best_score = score
      candidate += 1
    if best < 0
      return 0
    selected[chosen] = best
    chosen += 1
  chosen

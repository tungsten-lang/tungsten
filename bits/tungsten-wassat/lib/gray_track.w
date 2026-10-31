# A clause-checked counting refutation for cyclic single-track Gray codes.
# If every bit column is a rotation of column zero, all columns have the same
# even cyclic flip count F. Exactly one flip on each of W edges gives W=B*F.
# Hence 2B must divide W. Recognition checks a sufficient ORIGINAL-clause
# subset; additional clauses cannot invalidate its contradiction. No answer
# table, filename, or precomputed instance verdict participates in admission.
# Fast mode only: this counting certificate is not a DRAT/WRAT derivation.
# meta: status, words, bits, clause visits, rotation relations, complete XOR
# gates, exact-one pairs, candidate layouts. Status zero means no refutation.

# Constant-cost CLI admission from the shape histogram already cached during
# parsing. Unrelated inputs allocate no recognition scratch or clause scan.
# Wider extra clauses may make this conservative gate miss; CDCL then handles
# the input normally. This gate is not itself evidence of a contradiction.
-> wassat_gray_track_bits(nv, w) (i64 i64) i64
  return 0 if nv < 1 || nv > 262144 || w < 3 || w > 256
  b = 2
  while b <= 32 && b <= w
    return b if nv == w * b * (w + b + 4) / 2 && w % (2 * b) != 0
    b += 1
  0

# Verify one bounded matrix layout. XOR auxiliaries are recovered from their
# complete four-clause truth tables, independently of their numbering/order.
-> wassat_gray_track_check(lits, offs, lens, nv, nc, w, b, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  wb = w * b
  nr = (b - 1) * w * w
  return 0 if 2 * nr + 4 * wb + w * (b * (b - 1) / 2 + 1) + b - 1 > nc
  rotations = i8[nr]
  shift_alo = i8[b]
  seen = i64[w]
  gate_edge = i32[nv + 1]
  gate_mask = i8[nv + 1]
  edge_alo = i8[w]
  edge_amo = i8[w * b * b]
  ci = 0
  while ci < nc
    n = lens[ci]
    off = offs[ci]
    # A positive selector clause must cover every shift exactly once.
    if n == w
      first = lits[off]
      if first > wb && first <= 2 * wb
        col = (first - wb - 1) / w
        ok = 1
        k = 0
        while k < n && ok == 1
          l = lits[off + k]
          shift = l - wb - col * w - 1
          if shift < 0 || shift >= w
            ok = 0
          elsif seen[shift] == ci + 1
            ok = 0
          else
            seen[shift] = ci + 1
          k += 1
        shift_alo[col] = 1 if ok == 1
    if n == 3
      sel = 0
      x = 0
      y = 0
      z = 0
      primary = 0
      selectors = 0
      aux = 0
      k = 0
      while k < 3
        l = lits[off + k]
        v = l
        v = 0 - l if l < 0
        if v >= 1 && v <= wb
          x = l if primary == 0
          y = l if primary == 1
          primary += 1
        elsif v > wb && v <= 2 * wb
          sel = l
          selectors += 1
        elsif v > 2 * wb && v <= nv
          z = l
          aux += 1
        k += 1
      if primary == 2
        ax = x
        ay = y
        ax = 0 - x if x < 0
        ay = 0 - y if y < 0
        cx = (ax - 1) % b
        cy = (ay - 1) % b
        tx = (ax - 1) / b
        ty = (ay - 1) / b
        if selectors == 1 && sel < 0
          if cy == 0 && cx > 0
            tmp = x
            x = y
            y = tmp
            tmp = tx
            tx = ty
            ty = tmp
            cy = cx
            cx = 0
          col = ((0 - sel) - wb - 1) / w
          shift = ((0 - sel) - wb - 1) % w
          if cx == 0 && cy == col && col > 0 && ty == (tx + shift) % w
            r = ((col - 1) * w + shift) * w + tx
            rotations[r] = rotations[r] | 1 if x > 0 && y < 0
            rotations[r] = rotations[r] | 2 if x < 0 && y > 0
        elsif aux == 1 && cx == cy
          edge = -1
          if ty == (tx + 1) % w
            edge = tx
          elsif tx == (ty + 1) % w
            edge = ty
            tmp = x
            x = y
            y = tmp
          if edge >= 0
            sx = 0
            sy = 0
            sz = 0
            sx = 1 if x < 0
            sy = 1 if y < 0
            sz = 1 if z < 0
            az = z
            az = 0 - z if z < 0
            # Each sign pattern forbids one assignment with z != x XOR y.
            if (sx ^ sy ^ sz) == 1
              key = edge * b + cx + 1
              if gate_edge[az] == 0
                gate_edge[az] = key
              elsif gate_edge[az] != key
                gate_edge[az] = -1
              if gate_edge[az] == key
                gate_mask[az] = gate_mask[az] | (1 << (sx * 2 + sy))
    ci += 1
  meta[3] += nc
  col = 1
  while col < b
    return 0 if shift_alo[col] == 0
    col += 1
  i = 0
  while i < nr
    return 0 if rotations[i] != 3
    i += 1
  meta[4] = nr
  gates = 0
  v = 2 * wb + 1
  while v <= nv
    gates += 1 if gate_mask[v] == 15 && gate_edge[v] > 0
    v += 1
  meta[5] = gates
  # Map clauses through complete XOR definitions. Different auxiliary copies
  # of the same XOR are interchangeable only after each has all four rows.
  ci = 0
  while ci < nc
    n = lens[ci]
    off = offs[ci]
    if n == b
      first = lits[off]
      if first > 2 * wb && first <= nv && gate_mask[first] == 15 && gate_edge[first] > 0
        edge = (gate_edge[first] - 1) / b
        ok = 1
        k = 0
        while k < n && ok == 1
          l = lits[off + k]
          if l <= 2 * wb || l > nv
            ok = 0
          elsif gate_mask[l] != 15 || gate_edge[l] <= 0
            ok = 0
          else
            key = gate_edge[l] - 1
            col = key % b
            if key / b != edge || seen[col] == nc + ci + 1
              ok = 0
            else
              seen[col] = nc + ci + 1
          k += 1
        edge_alo[edge] = 1 if ok == 1
    if n == 2
      a = 0 - lits[off]
      d = 0 - lits[off + 1]
      if a > 2 * wb && a <= nv && d > 2 * wb && d <= nv
        if gate_mask[a] == 15 && gate_mask[d] == 15 && gate_edge[a] > 0 && gate_edge[d] > 0
          ka = gate_edge[a] - 1
          kd = gate_edge[d] - 1
          ea = ka / b
          ed = kd / b
          ca = ka % b
          cd = kd % b
          if ea == ed && ca != cd
            if ca > cd
              tmp = ca
              ca = cd
              cd = tmp
            edge_amo[(ea * b + ca) * b + cd] = 1
    ci += 1
  meta[3] += nc
  edge = 0
  while edge < w
    return 0 if edge_alo[edge] == 0
    col = 0
    while col < b
      other = col + 1
      while other < b
        return 0 if edge_amo[(edge * b + col) * b + other] == 0
        other += 1
      col += 1
    edge += 1
  meta[6] = w * b * (b - 1) / 2
  1

-> wassat_gray_track_scan(lits, offs, lens, nv, nc, meta) (i64[] i64[] i64[] i64 i64 i64[]) i64
  return 0 if nv < 1 || nv > 262144 || nc < 1 || nc > 500000
  # The layout filter is only a cheap admission hint. Soundness comes from
  # checking every rotation/transition clause required by the counting proof.
  ci = 0
  while ci < nc
    w = lens[ci]
    if w >= 3 && w <= 256
      off = offs[ci]
      minimum = lits[off]
      k = 1
      while k < w && minimum > 0
        l = lits[off + k]
        minimum = l if l < minimum
        k += 1
      if minimum > 1 && (minimum - 1) % w == 0
        b = (minimum - 1) / w
        if b >= 2 && b <= 32 && b <= w && nv == w * b * (w + b + 4) / 2 && w % (2 * b) != 0
          # Bound admission work even when candidate selector rows repeat.
          if meta[7] >= 8
            meta[3] += ci + 1
            return 0
          meta[7] += 1
          meta[1] = w
          meta[2] = b
          if wassat_gray_track_check(lits, offs, lens, nv, nc, w, b, meta) == 1
            meta[0] = -1
            meta[3] += ci + 1
            return 1
    ci += 1
  meta[3] += nc
  0

-> wassat_gray_track_refute(formula)
  meta = i64[8]
  return meta if formula == nil || formula["flat_lits"] == nil
  z = wassat_gray_track_scan(formula["flat_lits"], formula["flat_offs"],
                              formula["flat_lens"], formula["nvars"],
                              formula["flat_ncl"], meta)
  meta

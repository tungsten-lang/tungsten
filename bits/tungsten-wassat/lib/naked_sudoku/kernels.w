# Typed native clause-checking kernels. The coordinator class owns these
# fixed buffers; the hot loops access typed arguments, not dynamic ivars.

-> wassat_naked_k_poll(ks, m, stop) (i64[] i64[] i64[]) bool
  m[1] += 1
  m[0] = 1 if wassat_stop_load(stop) != 0
  m[0] = 2 if m[0] == 0 && ks[1] > 0 && clock_ms() >= ks[1]
  m[0] != 0

-> wassat_naked_k_visit(ks, m, stop) (i64[] i64[] i64[]) bool
  ks[0] += 1
  m[0] = 3 if ks[0] > 1000000000
  (ks[0] & 1023) == 0 ? wassat_naked_k_poll(ks, m, stop) : m[0] != 0

# Signed machine arithmetic, including the wraparound multiplications.

-> wassat_naked_k_abs(v) (i64) i64
  v < 0 ? 0 - v : v

-> wassat_naked_k_li(v) (i64) i64
  v < 0 ? (0 - v) * 2 + 1 : v * 2

-> wassat_naked_k_mix(v) (i64) i64
  h = v ## i64
  h = (h ^ (h >> 30)) * -4658895280553007687
  h = (h ^ (h >> 27)) * -7723592293110705685
  # Method results cross a boxed boundary. Keep the return in the immediate
  # integer range: every bucket mask is below 2^22, so discarding these high
  # bits preserves bucket selection while avoiding one BigInt per literal.
  (h ^ (h >> 31)) & 2147483647

-> wassat_naked_k_has_clause(ks, m, stop, lits, offs, lens, heads, hnext, qmark, mseen, query, n) (i64[] i64[] i64[] i64[] i64[] i64[] i32[] i32[] i32[] i32[] i32[] i64) bool
  return false if n < 1 || n > 1024 || wassat_naked_k_visit(ks, m, stop)
  m[4] += 1; ks[7] += 1; j = 0
  h = 0 ## i64
  while j < n
    v = query[j]; return false if v == 0 || wassat_naked_k_abs((v ## i64)) > ks[6]
    k = wassat_naked_k_li((v ## i64)); return false if qmark[k] == ks[7]
    qmark[k] = ks[7]; h += wassat_naked_k_mix((v ## i64)); j += 1
  ci = heads[h & ks[4]] - 1
  while ci >= 0
    return false if wassat_naked_k_visit(ks, m, stop)
    m[5] += 1
    if lens[ci] == n
      ks[8] += 1; o = offs[ci]; j = 0; good = true
      while j < n && good
        k = wassat_naked_k_li((lits[o + j] ## i64)); m[6] += 1
        good = false if qmark[k] != ks[7] || mseen[k] == ks[8]
        mseen[k] = ks[8]; j += 1
      return true if good
    ci = hnext[ci] - 1
  false

-> wassat_naked_k_binary_implies(ks, m, stop, lits, offs, bfirst, bnext, oci, a, b) (i64[] i64[] i64[] i64[] i64[] i32[] i32[] i32[] i64 i64) bool
  p = bfirst[wassat_naked_k_li((0 - a ## i64))] - 1
  while p >= 0
    return false if wassat_naked_k_visit(ks, m, stop)
    m[7] += 1; ci = oci[p]; o = offs[ci]
    other = lits[p == o ? o + 1 : o]
    return true if other == b
    p = bnext[p] - 1
  false

-> wassat_naked_k_order_implies(ks, domain, a, b) (i64[] i32[] i64 i64) bool
  return true if a == b
  va = wassat_naked_k_abs((a ## i64)); vb = wassat_naked_k_abs((b ## i64))
  return false if va < 1 || va > ks[2] || vb < 1 || vb > ks[2] || (a < 0) != (b < 0)
  domain[va] == domain[vb] && a <= b

-> wassat_naked_k_implies(ks, m, stop, lits, offs, domain, bfirst, bnext, oci, a, b) (i64[] i64[] i64[] i64[] i64[] i32[] i32[] i32[] i32[] i64 i64) bool
  return true if wassat_naked_k_order_implies(ks, domain, (a ## i64), (b ## i64)) || wassat_naked_k_binary_implies(ks, m, stop, lits, offs, bfirst, bnext, oci, (a ## i64), (b ## i64))
  p = bfirst[wassat_naked_k_li((0 - a ## i64))] - 1
  while p >= 0
    return false if wassat_naked_k_visit(ks, m, stop)
    ci = oci[p]; o = offs[ci]; mid = lits[p == o ? o + 1 : o]
    return true if wassat_naked_k_abs((mid ## i64)) <= ks[2] && wassat_naked_k_order_implies(ks, domain, (mid ## i64), (b ## i64))
    if wassat_naked_k_abs((a ## i64)) > ks[3]
      return true if wassat_naked_k_binary_implies(ks, m, stop, lits, offs, bfirst, bnext, oci, (mid ## i64), (b ## i64))
      q = bfirst[wassat_naked_k_li((0 - mid ## i64))] - 1
      while q >= 0
        return false if wassat_naked_k_visit(ks, m, stop)
        cj = oci[q]; oo = offs[cj]; last = lits[q == oo ? oo + 1 : oo]
        return true if wassat_naked_k_abs((last ## i64)) <= ks[2] && wassat_naked_k_order_implies(ks, domain, (last ## i64), (b ## i64))
        q = bnext[q] - 1
    p = bnext[p] - 1
  false

-> wassat_naked_k_singleton(ks, ta, ts, v) (i64[] i32[] i8[] i64) bool
  i = 0
  while i < ks[10]
    return true if ts[i] == 1 && ta[i] == v
    i += 1
  false

# Every literal of an original covering clause must imply the requested
# disjunction. Short helper implications may themselves have a disjunction
# as consequent, e.g. B => not(x=d) for a two-threshold equality.

-> wassat_naked_k_covers(ks, m, stop, lits, offs, lens, domain, ofirst, onext, bfirst, bnext, oci, ta, tb, ts, v) (i64[] i64[] i64[] i64[] i64[] i64[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i8[] i64) bool
  i = 0
  while i < ks[10]
    if wassat_naked_k_implies(ks, m, stop, lits, offs, domain, bfirst, bnext, oci, (v ## i64), (ta[i] ## i64))
      return true if ts[i] == 1 || wassat_naked_k_implies(ks, m, stop, lits, offs, domain, bfirst, bnext, oci, (v ## i64), (tb[i] ## i64))
    i += 1
  if wassat_naked_k_abs((v ## i64)) > ks[3]
    p = ofirst[wassat_naked_k_li((0 - v ## i64))] - 1
    while p >= 0
      return false if wassat_naked_k_visit(ks, m, stop)
      ci = oci[p]; o = offs[ci]; len = lens[ci]; j = 0; good = true
      while j < len && good
        l = lits[o + j]
        good = false if l != 0 - v && !wassat_naked_k_singleton(ks, ta, ts, (l ## i64))
        j += 1
      return true if good
      p = onext[p] - 1
  false

-> wassat_naked_k_require_query(ks, m, stop, lits, offs, lens, domain, heads, hnext, ofirst, onext, bfirst, bnext, oci, ocount, cseen, qmark, mseen, query, ta, tb, ts, tried) (i64[] i64[] i64[] i64[] i64[] i64[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i8[] i8[]) bool
  return false if m[0] != 0 || wassat_naked_k_visit(ks, m, stop)
  m[8] += 1
  return true if (ks[11] != 0)
  all_single = true; n = 0; i = 0
  while i < ks[10]
    tried[i] = 0
    if ts[i] != 1
      all_single = false
    else
      v = ta[i]; return true if wassat_naked_k_singleton(ks, ta, ts, (0 - v ## i64))
      j = 0
      while j < n && query[j] != v
        j += 1
      if j == n
        query[n] = v; n += 1
    i += 1
  return true if all_single && wassat_naked_k_has_clause(ks, m, stop, lits, offs, lens, heads, hnext, qmark, mseen, query, (n ## i64))
  ks[9] += 1; attempts = 0
  while attempts < ks[10]
    best = -1; count = ks[12] + 1; i = 0
    while i < ks[10]
      if ts[i] == 1 && tried[i] == 0 && ocount[wassat_naked_k_li((ta[i] ## i64))] < count
        best = i; count = ocount[wassat_naked_k_li((ta[i] ## i64))]
      i += 1
    break if best < 0
    tried[best] = 1; attempts += 1; anchor = ta[best]
    p = ofirst[wassat_naked_k_li((anchor ## i64))] - 1
    while p >= 0
      return false if wassat_naked_k_visit(ks, m, stop)
      ci = oci[p]
      break if wassat_naked_k_abs((anchor ## i64)) <= ks[2] && ci >= ks[5]
      if cseen[ci] != ks[9]
        cseen[ci] = ks[9]; m[9] += 1
        j = 0; good = true; o = offs[ci]; len = lens[ci]
        while j < len && good
          good = wassat_naked_k_covers(ks, m, stop, lits, offs, lens, domain, ofirst, onext, bfirst, bnext, oci, ta, tb, ts, (lits[o + j] ## i64)); j += 1
        return true if good && m[0] == 0
      p = onext[p] - 1
  false

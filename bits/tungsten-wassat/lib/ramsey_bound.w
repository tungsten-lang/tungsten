use ramsey_lex
use ramsey_gluing

# A computed upper bound, not a table of Ramsey numbers or benchmark answers.
# If A bounds R(p-1,q) and B bounds R(p,q-1), any avoiding coloring has
# red degree <= A-1 and blue degree <= B-1 at every vertex. Thus A+B
# vertices are impossible. If A and B are even, A+B-1 vertices would force
# odd red degree A-1 at each of an odd number of vertices, contradicting
# the even degree sum of an undirected graph. This gives A+B-1 instead.
# The only base case is R(2,k) <= k: absence of a red edge makes all edges
# blue. These implications use upper bounds; no exact Ramsey number is needed.
# Refutation also requires complete ORIGINAL clique families. Proof modes
# must bypass this fast-only route until that argument has a DRAT encoding.

WASSAT_RAMSEY_BOUND_MS = 25
WASSAT_RAMSEY_GLUING_MS = 6000

# work: refuted, expired, vertices, scanned clauses, positive clique size,
# negative clique size, upper bound, recurrence steps, polls, parity steps.
-> wassat_ramsey_bound_fill(upper, work) (i64[] i64[]) i64
  k = 1
  while k <= 8
    upper[9 + k] = 1
    upper[9 * k + 1] = 1
    upper[18 + k] = k if k >= 2
    upper[9 * k + 2] = k if k >= 2
    k += 1
  p = 3
  while p <= 8
    q = 3
    while q <= 8
      a = upper[9 * (p - 1) + q]
      b = upper[9 * p + q - 1]
      value = a + b
      if (a & 1) == 0 && (b & 1) == 0
        value -= 1
        work[9] += 1
      upper[9 * p + q] = value
      work[7] += 1
      q += 1
    p += 1
  0

# This is only a candidate scan. Width/sign observations cannot establish
# clique structure or coverage; the exact checker below is mandatory.
-> wassat_ramsey_bound_find(lits, offs, lens, nc, upper, work, deadline) (i64[] i64[] i64[] i64 i64[] i64[] i64) i64
  width_k = i8[29]
  k = 3
  while k <= 8
    width_k[k * (k - 1) / 2] = k
    k += 1
  p = 9
  q = 9
  last_p = 9
  last_q = 9
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_ramsey_bound_stop(work, deadline) != 0
    width = lens[ci]
    return 0 if width < 3 || width > 28
    k = width_k[width]
    return 0 if k == 0
    off = offs[ci]
    return 0 if off < 0 || off >= lits.size
    first = lits[off]
    return 0 if first == 0
    if first > 0
      p = k if k < p
      work[4] = p
    else
      q = k if k < q
      work[5] = q
    work[3] += 1
    if p < 9 && q < 9 && (p != last_p || q != last_q)
      last_p = p
      last_q = q
      work[6] = upper[9 * p + q]
      return 1 if work[2] >= work[6]
      return 2 if work[2] == 18 && ((p == 3 && q == 6) || (p == 6 && q == 3))
      if (p == 3 && q == 7) || (p == 7 && q == 3)
        bound = wassat_ramsey_triangle_bound(7, work[2], work, deadline)
        if bound > 0
          work[6] = bound
          return 3
        return 4 if work[2] == 23
    ci += 1
  0

-> wassat_ramsey_bound_solve(formula, deadline = 0, gluing_deadline = 0)
  return nil unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  # The smallest supported pair is (3,3), whose derived bound is six.
  return nil if nv < 15 || nv > 780 || nc < 1 || nc > 400000
  n = 6
  while n <= 40 && n * (n - 1) / 2 < nv
    n += 1
  return nil if n > 40 || n * (n - 1) / 2 != nv
  return nil if formula["flat_offs"].size < nc || formula["flat_lens"].size < nc
  work = i64[14]
  work[2] = n
  upper = i64[81]
  checked = nil
  unless wassat_ramsey_bound_stop(work, deadline) != 0
    wassat_ramsey_bound_fill(upper, work)
    found = wassat_ramsey_bound_find(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nc, upper, work, deadline)
    if found != 0
      checked = i64[16]
      ok = wassat_ramsey_lex_check(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, nc, n, checked, deadline)
      work[1] = 1 if checked[1] == 1
      if ok == 1 && wassat_ramsey_bound_stop(work, deadline) == 0
        if found == 1 || found == 3
          work[12] = 1 if found == 3
          work[0] = 1
        elsif found == 4
          # Only a fully checked clique formula reaches the longer search.
          until_ms = gluing_deadline > 0 ? gluing_deadline : deadline
          proved = wassat_ramsey_gluing_refutes(work, until_ms)
          if wassat_ramsey_bound_stop(work, until_ms) == 0 && proved
            work[0] = 1
            work[6] = 23
            work[12] = 2
        elsif wassat_ramsey_neighborhood_refutes(work, deadline) && wassat_ramsey_bound_stop(work, deadline) == 0
          work[6] = 18
          work[0] = 1
  { "status": work[0] == 1 ? -1 : 0, "work": work, "check": checked }

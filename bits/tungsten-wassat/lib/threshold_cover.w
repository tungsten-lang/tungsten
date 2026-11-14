# A counting contradiction: the formula demands more true variables than its
# at-most-one constraints leave room for.
#
# The rook inputs of SAT Competition 2025 ask for K non-attacking rooks on an
# n x n board. "No two rooks attack" is a binary clause per pair of cells in a
# row or a column; "exactly K rooks" is a decision diagram over the cells,
# written as implications only (MiniSat+ style):
#     node -> (x ? hi : lo)      (-node | x | lo) (-node | -x | hi) (-node | lo | hi)
# with conjunctions and a two-literal choice at the bottom, and the root
# asserted by a unit clause. With K = n + 1 this is the pigeonhole principle
# behind a counter, and no CDCL solver here or among the references decides
# n = 51 in a minute. Counting does:
#
#   need[v], for a variable v that the clauses define by implication, is a
#   lower bound on the number of true LEAF variables (variables with no such
#   definition) in any assignment satisfying the clauses in which v is true;
#   the leaves counted all lie in supp[v].
#       v -> p, v -> q, ..            need = sum over implied p with pairwise
#                                     disjoint supports (and at least the max)
#       v -> (a | b)                  need = min(need[a], need[b])
#       v -> (x ? hi : lo)            need = min(need[lo], need[hi] + 1),
#                                     the + 1 only when x is a leaf outside
#                                     supp[hi]
#   A leaf has need 1 and supports itself.
#
#   The leaves of supp[root] are then split into groups that are pairwise
#   exclusive (a clause (-a | -b) for every pair in a group), greedily. At
#   most one leaf of a group is true, so at most `groups` leaves are. If
#   need[root] > groups, a root asserted by a unit clause is contradictory.
#
#   Which leaves are counted is a free choice: need[] computed with some
#   leaves worth 0 bounds the true leaves among the others. A leaf that ends
#   up alone in its group (the diagram's "nothing more" terminal is one) adds
#   a group and at most one to the demand, so a second evaluation drops them.
#
#   A counter can also be written as one node per (position, count), each
#   tied to its neighbours in both directions (the 1-ET inputs of SAT
#   Competition 2025: an independent set of K words in a graph on 256 or 512
#   binary words). Three additions read it:
#     - its definitions depend on themselves, so they are read one way only,
#       down or up the variable numbering (leaves are exempt, any subset of
#       the definitions gives a valid bound);
#     - a node ruled out by a unit clause (-v) is never true, so a branch
#       through it is discarded;
#     - such a counter starts with a positive clause (a | b) over the nodes of
#       its first position, not with a unit: a fresh variable r with (r) and
#       (-r | a | b) says the same and is a root.
#   And when the greedy groups leave room, the room is counted exactly: the
#   true leaves are pairwise non-exclusive, so there are at most as many as
#   the independence number of the exclusion graph, which is the sum over
#   its connected components and is found by branch and bound (a 512-word
#   graph falls into components of at most 126 words). 1-ET-256-K-65 demands
#   65 and holds 50; 1-ET-512 demands 102 or 120 and holds 100.
#
# Soundness. Every rule reads only clauses that are present, and each is a
# case analysis on those clauses, so need[] is a lower bound whatever else the
# formula contains; a variable classified one way or the other only changes
# what is counted, and only leaves are counted. Disjointness is checked on
# explicit support sets, never assumed from an ordering. The groups partition
# the support and are verified pair by pair through the adjacency counts.
# Extra clauses can only make the formula stronger.
#
# Fast mode only: the verdict carries no clausal proof.

WASSAT_THRESHOLD_COVER_MAX_VARS = 4000000
WASSAT_THRESHOLD_COVER_MAX_CLAUSES = 16000000
# Support bitsets: nodes times words (62 leaves a word).
WASSAT_THRESHOLD_COVER_MAX_WORDS = 24000000
WASSAT_THRESHOLD_COVER_MAX_DEFS = 12
# Exact independence number: search nodes over all components, and the
# largest component taken on.
WASSAT_THRESHOLD_COVER_MIS_NODES = 3000000
WASSAT_THRESHOLD_COVER_MIS_VERTICES = 1240
# "Never true": the demand of a variable a negative unit clause rules out.
WASSAT_THRESHOLD_COVER_DEAD = 1099511627776
# Two-literal positive clauses tried as a root when no unit clause works,
# and the largest formula that is copied for it.
WASSAT_THRESHOLD_COVER_PAIR_ROOTS = 2
WASSAT_THRESHOLD_COVER_PAIR_CLAUSES = 6000000
# Roots whose definitions are tried again one way after depending on
# themselves.
WASSAT_THRESHOLD_COVER_DIRECTED_ROOTS = 2

# st slots.
#  0 status (1 refuted)   1 root variable   2 need   3 groups   4 nodes   5 leaves
#  6 roots tried   7 stop (2 capacity, 3 deadline)   8 words a set
#  9 room is an exact independence number (1) instead of a group count
# 10 independence search nodes   11 definition order used (0 any, 1 down, 2 up)
# 12, 13 the positive clause (a | b) that served as the root, if one did
# 14 roots given up because their definitions depend on themselves

# Literal code c (2v + sign) as the clause's stored literal.
# Is the definition clause at ci usable for head h, and how? Returns
#   0 not usable, 1 binary h -> p, 2 ternary both tails positive,
#   3 ternary with one negative tail.  out[0..1]: tail literals (signed).
# dir restricts the definitions to one direction of the variable numbering:
# 1 keeps a clause only when its tail variables are below h, 2 only when they
# are above it (0 keeps all). Only tails that can be nodes themselves
# (cand = 1: some clause defines them) are held to that; a variable no
# clause defines is a leaf wherever it is numbered. `free` names one head
# exempt from the rule, the root. Any subset of the definitions gives a
# valid lower bound, and a one-directional subset cannot depend on itself
# except through the root, which the traversal detects.
-> wassat_tc_kind(fla, fcs, fcl, ci, h, out, dir, free, cand) (i64[] i64[] i64[] i64 i64 i64[] i64 i64 i8[]) i64
  n = fcl[ci] ## i64
  off = fcs[ci] ## i64
  m = 0 ## i64
  heads = 0 ## i64
  j = 0 ## i64
  while j < n
    l = fla[off + j] ## i64
    if l == 0 - h
      heads += 1
    else
      return 0 if l == h
      out[m] = l if m < 2
      m += 1
    j += 1
  return 0 if heads != 1 || m != n - 1
  if n == 2
    return 0 if out[0] <= 0
    if dir != 0 && h != free && cand[out[0]] == 1
      return 0 if dir == 1 && out[0] >= h
      return 0 if dir == 2 && out[0] <= h
    return 1
  a = out[0] ## i64
  b = out[1] ## i64
  va = a < 0 ? 0 - a : a ## i64
  vb = b < 0 ? 0 - b : b ## i64
  return 0 if va == vb
  if dir != 0 && h != free
    if cand[va] == 1
      return 0 if dir == 1 && va >= h
      return 0 if dir == 2 && va <= h
    if cand[vb] == 1
      return 0 if dir == 1 && vb >= h
      return 0 if dir == 2 && vb <= h
  return 2 if a > 0 && b > 0
  return 3 if a > 0 || b > 0
  0

# Positive unit clauses.
-> wassat_tc_units(fla, fcs, fcl, nc) (i64[] i64[] i64[] i64) i64
  n = 0 ## i64
  ci = 0 ## i64
  while ci < nc
    n += 1 if fcl[ci] == 1 && fla[fcs[ci]] > 0
    ci += 1
  n

fn wassat_tc_pop(x) (i64) i64
  ccall_nobox("__w_bit_ctpop_u64", x) ## i64

fn wassat_tc_ctz(x) (i64) i64
  ccall_nobox("__w_bit_cttz_u64", x) ## i64

# The exact independence number of a graph, for the room side of the count.
# Vertex sets are bitsets of w words, 62 vertices a word; nb[v * w ..] is the
# neighbourhood of v (without v).
#
# A greedy clique cover of the set at pst[base ..): an upper bound on its
# independence number. tmp holds 2 w words of scratch.
-> wassat_tc_cover(nb, w, pst, base, tmp) (i64[] i64 i64[] i64 i64[]) i64
  one = 1 ## i64
  i = 0 ## i64
  while i < w
    tmp[i] = pst[base + i]
    i += 1
  c = 0 ## i64
  wi = 0 ## i64
  while wi < w
    if tmp[wi] == 0
      wi += 1
    else
      b = wassat_tc_ctz(tmp[wi])
      v = wi * 62 + b ## i64
      tmp[wi] = tmp[wi] ^ (one << b)
      any = 0 ## i64
      i = 0
      while i < w
        q = tmp[i] & nb[v * w + i] ## i64
        tmp[w + i] = q
        any = 1 if q != 0
        i += 1
      while any == 1
        i = 0
        while tmp[w + i] == 0
          i += 1
        b = wassat_tc_ctz(tmp[w + i])
        u = i * 62 + b ## i64
        tmp[i] = tmp[i] ^ (one << b)
        any = 0
        j = 0 ## i64
        while j < w
          q = tmp[w + j] & nb[u * w + j]
          tmp[w + j] = q
          any = 1 if q != 0
          j += 1
      c += 1
  c

# Branch and bound on the set at pst[depth * w ..): take the vertex of
# largest degree in or out. ms: 0 best size found, 1 nodes, 2 node budget,
# 3 stopped (budget or deadline), 4 deadline.
-> wassat_tc_mis(nb, w, pst, depth, size, ms, tmp) (i64[] i64 i64[] i64 i64 i64[] i64[]) i64
  ms[1] += 1
  if ms[1] > ms[2]
    ms[3] = 1
    return 0
  if (ms[1] & 4095) == 0 && ms[4] > 0 && clock_ms() >= ms[4]
    ms[3] = 1
    return 0
  base = depth * w ## i64
  cnt = 0 ## i64
  i = 0 ## i64
  while i < w
    cnt += wassat_tc_pop(pst[base + i])
    i += 1
  if cnt == 0
    ms[0] = size if size > ms[0]
    return 0
  return 0 if size + cnt <= ms[0]
  return 0 if size + wassat_tc_cover(nb, w, pst, base, tmp) <= ms[0]
  bv = 0 - 1 ## i64
  bd = 0 - 1 ## i64
  i = 0
  while i < w
    bits = pst[base + i] ## i64
    while bits != 0
      b = wassat_tc_ctz(bits)
      bits = bits & (bits - 1)
      v = i * 62 + b ## i64
      d = 0 ## i64
      j = 0 ## i64
      while j < w
        d += wassat_tc_pop(pst[base + j] & nb[v * w + j])
        j += 1
      if d > bd
        bd = d
        bv = v
    i += 1
  if bd == 0
    # No edges left: every vertex of the set can be taken.
    ms[0] = size + cnt if size + cnt > ms[0]
    return 0
  one = 1 ## i64
  full = (one << 62) - one ## i64
  nbase = base + w ## i64
  wi = bv / 62 ## i64
  out_bit = full ^ (one << (bv - wi * 62)) ## i64
  i = 0
  while i < w
    pst[nbase + i] = pst[base + i] & (full ^ nb[bv * w + i])
    i += 1
  pst[nbase + wi] = pst[nbase + wi] & out_bit
  z = wassat_tc_mis(nb, w, pst, depth + 1, size + 1, ms, tmp)
  return 0 if ms[3] != 0
  i = 0
  while i < w
    pst[nbase + i] = pst[base + i]
    i += 1
  pst[nbase + wi] = pst[nbase + wi] & out_bit
  z = wassat_tc_mis(nb, w, pst, depth + 1, size, ms, tmp)
  0

# The independence number of the exclusion graph on the leaves with
# inroot = 1 (ast/adj: adjacency over leaf ids 1..nleaf), as the sum over its
# connected components. Returns -1 when it was not computed (a component too
# large, the node budget, the deadline) and also as soon as the sum reaches
# `need`, since no refutation follows then. work[0]: search nodes.
-> wassat_tc_alpha(ast, adj, inroot, nleaf, need, work, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64) i64
  one = 1 ## i64
  comp = i64[nleaf + 2]
  queue = i64[nleaf + 2]
  local = i64[nleaf + 2]
  ms = i64[6]
  total = 0 ## i64
  s = 1 ## i64
  while s <= nleaf
    if inroot[s] == 1 && comp[s] == 0
      queue[0] = s
      comp[s] = s
      qh = 0 ## i64
      qt = 1 ## i64
      while qh < qt
        u = queue[qh] ## i64
        qh += 1
        t = ast[u] ## i64
        while t < ast[u + 1]
          x = adj[t] ## i64
          if comp[x] == 0
            comp[x] = s
            queue[qt] = x
            qt += 1
          t += 1
      n = qt ## i64
      if n == 1
        total += 1
      else
        return 0 - 1 if n > WASSAT_THRESHOLD_COVER_MIS_VERTICES
        w = (n + 61) / 62 ## i64
        nb = i64[n * w + 1]
        i = 0 ## i64
        while i < n
          local[queue[i]] = i
          i += 1
        i = 0
        while i < n
          u = queue[i]
          t = ast[u]
          while t < ast[u + 1]
            j = local[adj[t]] ## i64
            if j != i
              wj = j / 62 ## i64
              nb[i * w + wj] = nb[i * w + wj] | (one << (j - wj * 62))
            t += 1
          i += 1
        pst = i64[(n + 3) * w + 1]
        tmp = i64[2 * w + 2]
        i = 0
        while i < n
          wj = i / 62
          pst[wj] = pst[wj] | (one << (i - wj * 62))
          i += 1
        ms[0] = 0
        ms[1] = 0
        ms[2] = WASSAT_THRESHOLD_COVER_MIS_NODES - work[0]
        ms[3] = 0
        ms[4] = deadline
        z = wassat_tc_mis(nb, w, pst, 0, 0, ms, tmp)
        work[0] += ms[1]
        return 0 - 1 if ms[3] != 0
        total += ms[0]
      return 0 - 1 if total >= need
    s += 1
  total

# Returns { "status": 0 or -1, "work": st }.
-> wassat_threshold_cover_unsat(formula, deadline = 0)
  st = i64[16]
  miss = { "status": 0, "work": st }
  return miss unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return miss if nv < 4 || nv > WASSAT_THRESHOLD_COVER_MAX_VARS || nc < 4 || nc > WASSAT_THRESHOLD_COVER_MAX_CLAUSES
  fla = formula["flat_lits"]
  fcs = formula["flat_offs"]
  fcl = formula["flat_lens"]
  hit = wassat_tc_run(fla, fcs, fcl, nv, nc, st, deadline)
  return { "status": 0 - 1, "work": st } if hit == 1
  # No unit clause gave a count. A positive clause (a | b) can stand in for
  # one: with a fresh variable r, the clauses (r) and (-r | a | b) say the
  # same thing, and r is a root whose demand is the smaller of the two. A
  # path counter written as one node per (position, count) starts this way.
  return miss if st[7] == 3 || nc > WASSAT_THRESHOLD_COVER_PAIR_CLAUSES
  nlits = formula["flat_nlits"]
  # A candidate is a clause (a | b) that comes with (-a | -b), the two nodes
  # of a counter's first position, and whose variables each head some
  # definition (occur negated in a three-literal clause that has a positive
  # literal). Most formulas have none and stop here after two passes.
  heads = i8[nv + 2]
  ci = 0
  while ci < nc
    if fcl[ci] == 3
      off = fcs[ci]
      x = fla[off]
      y = fla[off + 1]
      z = fla[off + 2]
      if x > 0 || y > 0 || z > 0
        heads[0 - x] = 1 if x < 0
        heads[0 - y] = 1 if y < 0
        heads[0 - z] = 1 if z < 0
    ci += 1
  mate = i64[nv + 2]
  found = 0
  ci = 0
  while ci < nc
    if fcl[ci] == 2
      x = fla[fcs[ci]]
      y = fla[fcs[ci] + 1]
      if x > 0 && y > 0 && x != y && heads[x] == 1 && heads[y] == 1 && mate[x] == 0 && mate[y] == 0
        mate[x] = y
        mate[y] = x
        found += 1
    ci += 1
  return miss if found == 0
  exact = i8[nv + 2]
  ci = 0
  while ci < nc
    if fcl[ci] == 2
      x = fla[fcs[ci]]
      y = fla[fcs[ci] + 1]
      exact[0 - x] = 1 if x < 0 && y < 0 && mate[0 - x] == 0 - y
    ci += 1
  tried = 0
  ci = 0
  while ci < nc && tried < WASSAT_THRESHOLD_COVER_PAIR_ROOTS
    if fcl[ci] == 2 && fla[fcs[ci]] > 0 && fla[fcs[ci] + 1] > 0 && mate[fla[fcs[ci]]] == fla[fcs[ci] + 1] && (exact[fla[fcs[ci]]] == 1 || exact[fla[fcs[ci] + 1]] == 1)
      tried += 1
      a = fla[fcs[ci]]
      b = fla[fcs[ci] + 1]
      xl = i64[nlits + 5]
      xo = i64[nc + 3]
      xn = i64[nc + 3]
      i = 0
      while i < nlits
        xl[i] = fla[i]
        i += 1
      i = 0
      while i < nc
        xo[i] = fcs[i]
        xn[i] = fcl[i]
        i += 1
      r = nv + 1
      xo[nc] = nlits
      xn[nc] = 1
      xl[nlits] = r
      xo[nc + 1] = nlits + 1
      xn[nc + 1] = 3
      xl[nlits + 1] = 0 - r
      xl[nlits + 2] = a
      xl[nlits + 3] = b
      st2 = i64[16]
      hit = wassat_tc_run(xl, xo, xn, nv + 1, nc + 2, st2, deadline)
      if hit == 1
        st2[12] = a
        st2[13] = b
        return { "status": 0 - 1, "work": st2 }
      return miss if st2[7] == 3
    ci += 1
  miss

# One pass over the unit-asserted roots of the clauses given. Fills st and
# returns 1 when a root's demand exceeds the room.
-> wassat_tc_run(fla, fcs, fcl, nv, nc, st, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64) i64
  # Roots: variables asserted by a positive unit clause. No unit, no lane.
  nroot = wassat_tc_units(fla, fcs, fcl, nc)
  return 0 if nroot == 0 || nroot > 64
  roots = i64[nroot + 1]
  nroot = 0
  # Negative occurrences in clauses of two or three literals, per variable.
  nst = i64[nv + 3]
  # dead[v]: a unit clause (-v) is present, so v is true in no model and a
  # branch through it can be discarded (its demand is "never").
  dead = i8[nv + 2]
  ci = 0
  while ci < nc
    n = fcl[ci]
    if n == 1 && fla[fcs[ci]] > 0
      roots[nroot] = fla[fcs[ci]]
      nroot += 1
    elsif n == 1
      dead[0 - fla[fcs[ci]]] = 1
    elsif n == 2 || n == 3
      # A clause without a positive literal defines nothing (the at-most-one
      # binaries of a counter's layer would otherwise crowd the lists).
      off = fcs[ci]
      if fla[off] > 0 || fla[off + 1] > 0 || (n == 3 && fla[off + 2] > 0)
        j = 0
        while j < n
          l = fla[off + j]
          nst[1 - l] += 1 if l < 0
          j += 1
    ci += 1
  # A root must have a definition at all.
  anydef = 0
  i = 0
  while i < nroot
    anydef = 1 if nst[roots[i] + 1] > 0
    i += 1
  return 0 if anydef == 0
  v = 0
  while v <= nv
    nst[v + 1] += nst[v]
    v += 1
  nocc = i64[nst[nv + 1] + 1]
  nfill = i64[nv + 2]
  ci = 0
  while ci < nc
    n = fcl[ci]
    if n == 2 || n == 3
      off = fcs[ci]
      if fla[off] > 0 || fla[off + 1] > 0 || (n == 3 && fla[off + 2] > 0)
        j = 0
        while j < n
          l = fla[off + j]
          if l < 0
            x = 0 - l
            nocc[nst[x] + nfill[x]] = ci
            nfill[x] += 1
          j += 1
    ci += 1
  out = i64[4]
  # kind[v]: 0 unseen, 1 node, 2 leaf.  A node has a binary definition with a
  # positive tail or a ternary one with two positive tails.
  kind = i64[nv + 2]
  state = i64[nv + 2]
  nid = i64[nv + 2]
  order = i64[nv + 2]
  stack = i64[nv + 2]
  spos = i64[nv + 2]
  ri = 0
  # A definition graph that depends on itself (a counter written with
  # equivalences reads forward and backward) is tried again one way only.
  dir = 0
  directed = 0
  defd = i8[nv + 2]
  defd_done = 0
  while ri < nroot && st[0] == 0 && st[7] == 0
    root = roots[ri]
    if dir != 0 && defd_done == 0
      # Which variables can be nodes at all, whatever the direction.
      defd_done = 1
      v = 1
      while v <= nv
        t = nst[v]
        while t < nst[v + 1] && defd[v] == 0
          k = wassat_tc_kind(fla, fcs, fcl, nocc[t], v, out, 0, 0, defd)
          defd[v] = 1 if k == 1 || k == 2
          t += 1
        v += 1
    st[6] += 1 if dir == 0
    st[11] = dir
    # Fresh traversal per root (roots are few).
    v = 0
    while v <= nv
      kind[v] = 0
      state[v] = 0
      v += 1
    nnode = 0
    nleaf = 0
    sp = 0
    stack[0] = root
    spos[0] = 0
    state[root] = 1
    sp = 1
    cyc = 0
    while sp > 0 && cyc == 0
      h = stack[sp - 1]
      if kind[h] == 0 && dead[h] == 1 && h != root
        # A node without children; its demand is set to "never" below.
        kind[h] = 1
        order[nnode] = h
        nnode += 1
        nid[h] = nnode
        state[h] = 2
        sp -= 1
      elsif kind[h] == 0
        isn = 0
        t = nst[h]
        cap = nst[h + 1] - nst[h]
        if cap <= WASSAT_THRESHOLD_COVER_MAX_DEFS
          while t < nst[h + 1]
            k = wassat_tc_kind(fla, fcs, fcl, nocc[t], h, out, dir, root, defd)
            isn = 1 if k == 1 || k == 2
            t += 1
        else
          # Many negative occurrences: look for binary definitions only.
          while t < nst[h + 1]
            isn = 1 if fcl[nocc[t]] == 2 && wassat_tc_kind(fla, fcs, fcl, nocc[t], h, out, dir, root, defd) == 1
            t += 1
        kind[h] = isn == 1 ? 1 : 2
      if state[h] == 2
        # The dead node above: already placed.
        z = 0
      elsif kind[h] == 2
        nleaf += 1
        nid[h] = nleaf
        state[h] = 2
        sp -= 1
      else
        # Next unvisited child: every variable in the tails of h's definitions.
        t = nst[h] + spos[sp - 1]
        pushed = 0
        while t < nst[h + 1] && pushed == 0 && cyc == 0
          ci = nocc[t]
          k = wassat_tc_kind(fla, fcs, fcl, ci, h, out, dir, root, defd)
          if k != 0
            j = 0
            while j < fcl[ci] - 1 && pushed == 0
              c = out[j] < 0 ? 0 - out[j] : out[j]
              if state[c] == 0
                state[c] = 1
                stack[sp] = c
                spos[sp] = 0
                sp += 1
                pushed = 1
              elsif state[c] == 1 && out[j] > 0
                # A definition that depends on itself: not a diagram.
                cyc = 1
              j += 1
          t += 1 if pushed == 0
        if pushed == 1
          spos[sp - 2] = t - nst[h]
        elsif cyc == 0
          order[nnode] = h
          nnode += 1
          nid[h] = nnode
          state[h] = 2
          sp -= 1
    retry = 0
    if cyc == 1 && dir == 0 && directed < WASSAT_THRESHOLD_COVER_DIRECTED_ROOTS
      directed += 1
      retry = 1
    elsif cyc == 1 && dir == 1
      retry = 1
    elsif cyc == 1
      # This root is given up; the others still get their turn.
      st[14] += 1
    elsif kind[root] == 1 && nleaf >= 2
      st[4] = nnode
      st[5] = nleaf
      words = 1
      w = 62
      while w < nleaf
        words += 1
        w += 62
      st[8] = words
      if nnode * words > WASSAT_THRESHOLD_COVER_MAX_WORDS
        st[7] = 2
      else
        # Leaf bit positions without a division: leaf id i (1-based) lives in
        # word lw[i], bit lb[i].
        lw = i64[nleaf + 2]
        lbit = i64[nleaf + 2]
        w = 0
        b = 0
        i = 1
        while i <= nleaf
          lw[i] = w
          lbit[i] = 1 << b
          b += 1
          if b == 62
            b = 0
            w += 1
          i += 1
        sup = i64[(nnode + 1) * words + 1]
        need = i64[nnode + 2]
        acc = i64[words + 1]
        tl = i64[2 * WASSAT_THRESHOLD_COVER_MAX_DEFS + 8]
        tk = i64[WASSAT_THRESHOLD_COVER_MAX_DEFS + 4]
        zero = i64[nleaf + 2]
        singles = 0
        groups1 = 0
        tcpass = 0
        while tcpass < 2 && st[0] == 0 && st[7] == 0
          oi = 0
          while oi < nnode
            h = order[oi]
            hb = (oi + 1) * words
            # Gather the usable definitions (bounded) and build the support.
            nd = 0
            t = nst[h]
            t = nst[h + 1] if dead[h] == 1 && h != root
            many = (nst[h + 1] - nst[h]) > WASSAT_THRESHOLD_COVER_MAX_DEFS
            while t < nst[h + 1]
              ci = nocc[t]
              k = 0
              k = wassat_tc_kind(fla, fcs, fcl, ci, h, out, dir, root, defd) if !many || fcl[ci] == 2
              k = 0 if many && k != 1
              if k != 0 && nd < WASSAT_THRESHOLD_COVER_MAX_DEFS
                tk[nd] = k
                tl[2 * nd] = out[0]
                tl[2 * nd + 1] = k == 1 ? 0 : out[1]
                nd += 1
                j = 0
                while j < (k == 1 ? 1 : 2)
                  c = out[j] < 0 ? 0 - out[j] : out[j]
                  if kind[c] == 2
                    sup[hb + lw[nid[c]]] = sup[hb + lw[nid[c]]] | lbit[nid[c]]
                  elsif out[j] > 0
                    cb = nid[c] * words
                    q = 0
                    while q < words
                      sup[hb + q] = sup[hb + q] | sup[cb + q]
                      q += 1
                  j += 1
              t += 1
            best = 0
            # (i) conjunction of the binary definitions with disjoint supports.
            q = 0
            while q < words
              acc[q] = 0
              q += 1
            sum = 0
            d = 0
            while d < nd
              if tk[d] == 1
                p = tl[2 * d]
                pn = kind[p] == 2 ? 1 - zero[nid[p]] : need[nid[p]]
                best = pn if pn > best
                clash = 0
                if kind[p] == 2
                  clash = 1 if (acc[lw[nid[p]]] & lbit[nid[p]]) != 0
                else
                  cb = nid[p] * words
                  q = 0
                  while q < words
                    clash = 1 if (acc[q] & sup[cb + q]) != 0
                    q += 1
                if clash == 0
                  sum += pn
                  if kind[p] == 2
                    acc[lw[nid[p]]] = acc[lw[nid[p]]] | lbit[nid[p]]
                  else
                    cb = nid[p] * words
                    q = 0
                    while q < words
                      acc[q] = acc[q] | sup[cb + q]
                      q += 1
              d += 1
            best = sum if sum > best
            # (ii) a disjunction of two positive tails; (iii) the same refined by
            # a companion clause on the negation of one of them.
            d = 0
            while d < nd
              if tk[d] == 2
                a = tl[2 * d]
                b = tl[2 * d + 1]
                an = kind[a] == 2 ? 1 - zero[nid[a]] : need[nid[a]]
                bn = kind[b] == 2 ? 1 - zero[nid[b]] : need[nid[b]]
                cand = an < bn ? an : bn
                best = cand if cand > best
                e = 0
                while e < nd
                  if tk[e] == 3
                    u = tl[2 * e]
                    w2 = tl[2 * e + 1]
                    # (-h | -x | hi): x is the negated tail.
                    x = u < 0 ? 0 - u : (w2 < 0 ? 0 - w2 : 0)
                    hi = u < 0 ? w2 : u
                    if x != 0 && hi > 0 && (x == a || x == b)
                      lo = x == a ? b : a
                      lon = kind[lo] == 2 ? 1 - zero[nid[lo]] : need[nid[lo]]
                      hin = kind[hi] == 2 ? 1 - zero[nid[hi]] : need[nid[hi]]
                      if kind[x] == 2
                        inside = 0
                        if kind[hi] == 2
                          inside = 1 if hi == x
                        else
                          inside = 1 if (sup[nid[hi] * words + lw[nid[x]]] & lbit[nid[x]]) != 0
                        hin += 1 if inside == 0 && zero[nid[x]] == 0
                      cand = lon < hin ? lon : hin
                      best = cand if cand > best
                  e += 1
              d += 1
            best = WASSAT_THRESHOLD_COVER_DEAD if best > WASSAT_THRESHOLD_COVER_DEAD
            best = WASSAT_THRESHOLD_COVER_DEAD if dead[h] == 1 && h != root
            need[oi + 1] = best
            oi += 1
            if (oi & 4095) == 0 && deadline > 0 && clock_ms() >= deadline
              st[7] = 3
              oi = nnode
          if st[7] == 0
            k_need = need[nid[root]]
            st[1] = root
            st[2] = k_need
            # Leaves of the root's support, and the exclusions among them.
            rb = nid[root] * words
            inroot = i64[nleaf + 2]
            cntl = 0
            v = 1
            while v <= nv
              if kind[v] == 2 && state[v] == 2
                if (sup[rb + lw[nid[v]]] & lbit[nid[v]]) != 0
                  inroot[nid[v]] = 1
                  cntl += 1
              v += 1
            if tcpass == 1
              # Second pass: the lone leaves are no longer counted, so their
              # groups are no longer needed either.
              st[2] = k_need
              st[3] = groups1 - singles
              st[0] = 1 if k_need > groups1 - singles
            elsif k_need >= 1
              ast = i64[nleaf + 3]
              ci = 0
              while ci < nc
                if fcl[ci] == 2
                  off = fcs[ci]
                  a = fla[off]
                  b = fla[off + 1]
                  if a < 0 && b < 0 && a != b
                    va = 0 - a
                    vb = 0 - b
                    if kind[va] == 2 && kind[vb] == 2 && state[va] == 2 && state[vb] == 2 && inroot[nid[va]] == 1 && inroot[nid[vb]] == 1
                      ast[nid[va] + 1] += 1
                      ast[nid[vb] + 1] += 1
                ci += 1
              i = 0
              while i <= nleaf
                ast[i + 1] += ast[i]
                i += 1
              adj = i64[ast[nleaf + 1] + 1]
              afill = i64[nleaf + 2]
              ci = 0
              while ci < nc
                if fcl[ci] == 2
                  off = fcs[ci]
                  a = fla[off]
                  b = fla[off + 1]
                  if a < 0 && b < 0 && a != b
                    va = 0 - a
                    vb = 0 - b
                    if kind[va] == 2 && kind[vb] == 2 && state[va] == 2 && state[vb] == 2 && inroot[nid[va]] == 1 && inroot[nid[vb]] == 1
                      ia = nid[va]
                      ib = nid[vb]
                      adj[ast[ia] + afill[ia]] = ib
                      afill[ia] += 1
                      adj[ast[ib] + afill[ib]] = ia
                      afill[ib] += 1
                ci += 1
              # Greedy partition into exclusive groups. hits[u] counts DISTINCT
              # members of the current group adjacent to u (seen[] guards against
              # a duplicated clause), so hits == size means adjacent to all.
              grp = i64[nleaf + 2]
              hits = i64[nleaf + 2]
              hstamp = i64[nleaf + 2]
              seen = i64[nleaf + 2]
              groups = 0
              sid = 0
              i = 1
              while i <= nleaf
                if inroot[i] == 1 && grp[i] == 0
                  groups += 1
                  grp[i] = groups
                  size = 1
                  sid += 1
                  t = ast[i]
                  while t < ast[i + 1]
                    u = adj[t]
                    if seen[u] != sid
                      seen[u] = sid
                      hstamp[u] = groups
                      hits[u] = 1
                    t += 1
                  t = ast[i]
                  while t < ast[i + 1]
                    u = adj[t]
                    if grp[u] == 0 && hstamp[u] == groups && hits[u] == size
                      grp[u] = groups
                      size += 1
                      sid += 1
                      t2 = ast[u]
                      while t2 < ast[u + 1]
                        w3 = adj[t2]
                        if seen[w3] != sid
                          seen[w3] = sid
                          hits[w3] += 1 if hstamp[w3] == groups
                        t2 += 1
                    t += 1
                i += 1
              st[3] = groups
              st[0] = 1 if k_need > groups
              # The groups are only a greedy cover. When they leave room, the
              # exact independence number of the exclusion graph may not:
              # at most that many leaves are true together.
              if st[0] == 0 && k_need >= 2
                mwork = i64[2]
                alpha = wassat_tc_alpha(ast, adj, inroot, nleaf, k_need, mwork, deadline)
                st[10] += mwork[0]
                if alpha >= 0 && k_need > alpha
                  st[3] = alpha
                  st[9] = 1
                  st[0] = 1
              # Leaves alone in their group add one to the room and at most one
              # to the demand: stop counting them and evaluate once more.
              if st[0] == 0
                gsize = i64[groups + 2]
                i = 1
                while i <= nleaf
                  gsize[grp[i]] += 1 if inroot[i] == 1
                  i += 1
                i = 1
                while i <= nleaf
                  if inroot[i] == 1 && gsize[grp[i]] == 1
                    zero[i] = 1
                    singles += 1
                  i += 1
                groups1 = groups
          tcpass += 1
          tcpass = 2 if singles == 0
    # Once the definitions are read one way only, both ways get a turn: a
    # counter laid out position by position counts in one direction.
    retry = 1 if dir == 1 && st[0] == 0 && st[7] == 0
    if retry == 1
      dir += 1
    else
      dir = 0
      ri += 1
  st[0]

# A covering bound with overlaps.
#
# battleship-13-13-unsat (SAT Competition 2025) has a variable per cell of a
# 13 x 13 grid, at most one true cell per row, and 169 positive clauses, one
# per line of the 13 non-horizontal directions of the affine plane over Z13,
# each demanding a true cell on that line. Thirteen cells lie on 13 lines
# each, which is exactly 169, but any two cells of different rows share a
# line, so thirteen cells cover fewer.
#
# In general: let the variables of the all-positive clauses be split into
# groups that are pairwise exclusive (a clause (-a | -b) for every pair in a
# group). A model has a set S of true variables with at most one per group,
# and every positive clause holds a member of S. With A(v) the positive
# clauses holding v, the Hunter-Worsley bound gives, for any tree on S,
#     |union of A(v)|  <=  sum |A(v)|  -  sum over tree edges |A(u) & A(v)|
# Every pair of S lies in two different groups, so each of the |S| - 1 tree
# edges removes at least o, the least overlap of two variables of different
# groups, and
#     covered  <=  sum over groups of the largest |A(v)| in the group  -  (groups - 1) * o
# (taking every group only helps, since o is at most any |A(v)|). When that
# is less than the number of positive clauses, the formula is unsatisfiable.
# With o = 0 this is the plain pigeonhole count.
#
# Clauses are counted with multiplicity throughout (A(v) is a set of clause
# occurrences), so a duplicated clause cannot unbalance the two sides. The
# groups are verified through adjacency counts as in the lane above.

WASSAT_COVER_BOUND_MAX_VARS = 1024
WASSAT_COVER_BOUND_MAX_PAIRS = 8000000

# st slots: 0 status, 1 positive clauses, 2 bound, 3 groups, 4 variables, 5 least overlap.
-> wassat_cover_bound_unsat(formula)
  st = i64[8]
  miss = { "status": 0, "work": st }
  return miss unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return miss if nv < 3 || nv > WASSAT_THRESHOLD_COVER_MAX_VARS || nc < 3 || nc > WASSAT_THRESHOLD_COVER_MAX_CLAUSES
  fla = formula["flat_lits"]
  fcs = formula["flat_offs"]
  fcl = formula["flat_lens"]
  idx = i64[nv + 2]
  nvp = 0
  npos = 0
  pairs = 0
  ci = 0
  while ci < nc
    n = fcl[ci]
    if n >= 2
      off = fcs[ci]
      pos = 1
      j = 0
      while j < n && pos == 1
        pos = 0 if fla[off + j] < 0
        j += 1
      if pos == 1
        npos += 1
        pairs += n * n
        j = 0
        while j < n
          x = fla[off + j]
          if idx[x] == 0
            nvp += 1
            idx[x] = nvp
          j += 1
        return miss if nvp > WASSAT_COVER_BOUND_MAX_VARS || pairs > WASSAT_COVER_BOUND_MAX_PAIRS
    ci += 1
  return miss if npos < 2 || nvp < 2
  st[1] = npos
  st[4] = nvp
  deg = i64[nvp + 2]
  co = i64[(nvp + 1) * (nvp + 1) + 1]
  w = nvp + 1
  ast = i64[nvp + 3]
  ci = 0
  while ci < nc
    n = fcl[ci]
    off = fcs[ci]
    if n == 2 && fla[off] < 0 && fla[off + 1] < 0
      a = idx[0 - fla[off]]
      b = idx[0 - fla[off + 1]]
      if a != 0 && b != 0 && a != b
        ast[a + 1] += 1
        ast[b + 1] += 1
    elsif n >= 2
      pos = 1
      j = 0
      while j < n && pos == 1
        pos = 0 if fla[off + j] < 0
        j += 1
      if pos == 1
        # A variable written twice in one clause still holds it once.
        j = 0
        while j < n
          a = idx[fla[off + j]]
          first = 1
          k = 0
          while k < j
            first = 0 if fla[off + k] == fla[off + j]
            k += 1
          if first == 1
            deg[a] += 1
            k = j + 1
            while k < n
              b = idx[fla[off + k]]
              dup = 0
              q = 0
              while q < k
                dup = 1 if fla[off + q] == fla[off + k]
                q += 1
              if dup == 0 && a != b
                co[a * w + b] += 1
                co[b * w + a] += 1
              k += 1
          j += 1
    ci += 1
  i = 0
  while i <= nvp
    ast[i + 1] += ast[i]
    i += 1
  adj = i64[ast[nvp + 1] + 1]
  afill = i64[nvp + 2]
  ci = 0
  while ci < nc
    off = fcs[ci]
    if fcl[ci] == 2 && fla[off] < 0 && fla[off + 1] < 0
      a = idx[0 - fla[off]]
      b = idx[0 - fla[off + 1]]
      if a != 0 && b != 0 && a != b
        adj[ast[a] + afill[a]] = b
        afill[a] += 1
        adj[ast[b] + afill[b]] = a
        afill[b] += 1
    ci += 1
  grp = i64[nvp + 2]
  hits = i64[nvp + 2]
  hstamp = i64[nvp + 2]
  seen = i64[nvp + 2]
  groups = 0
  sid = 0
  i = 1
  while i <= nvp
    if grp[i] == 0
      groups += 1
      grp[i] = groups
      size = 1
      sid += 1
      t = ast[i]
      while t < ast[i + 1]
        u = adj[t]
        if seen[u] != sid
          seen[u] = sid
          hstamp[u] = groups
          hits[u] = 1
        t += 1
      t = ast[i]
      while t < ast[i + 1]
        u = adj[t]
        if grp[u] == 0 && hstamp[u] == groups && hits[u] == size
          grp[u] = groups
          size += 1
          sid += 1
          t2 = ast[u]
          while t2 < ast[u + 1]
            w3 = adj[t2]
            if seen[w3] != sid
              seen[w3] = sid
              hits[w3] += 1 if hstamp[w3] == groups
            t2 += 1
        t += 1
    i += 1
  st[3] = groups
  gmax = i64[groups + 2]
  i = 1
  while i <= nvp
    gmax[grp[i]] = deg[i] if deg[i] > gmax[grp[i]]
    i += 1
  least = 0 - 1
  a = 1
  while a <= nvp
    b = a + 1
    while b <= nvp
      if grp[a] != grp[b]
        c = co[a * w + b]
        least = c if least < 0 || c < least
      b += 1
    a += 1
  least = 0 if least < 0
  st[5] = least
  bound = 0
  g = 1
  while g <= groups
    bound += gmax[g]
    g += 1
  bound -= (groups - 1) * least
  st[2] = bound
  if bound < npos
    st[0] = 1
    return { "status": 0 - 1, "work": st }
  miss

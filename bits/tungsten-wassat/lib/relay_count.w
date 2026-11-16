# A pigeonhole count through relays.
#
# The rphp5 inputs of SAT Competition 2025 are the relativized pigeonhole
# principle with the sign of every variable scrambled: 5 pigeons each choose
# one of 50 (or 85) resting places, a resting place is taken by at most one
# pigeon, a taken resting place chooses one of 4 holes, and two taken resting
# places may not choose the same hole:
#     (p[u,1] | .. | p[u,R])                      pigeon u rests somewhere
#     (-p[u,v] | -p[u',v])                        one pigeon per resting place
#     (-p[u,v] | r[v])                            a resting place in use is taken
#     (-r[v] | q[v,1] | .. | q[v,H])              a taken place has a hole
#     (-r[v] | -r[v'] | -q[v,w] | -q[v',w])       two taken places, two holes
# Five pigeons into four holes, but resolution has to consider which five
# resting places are taken, and neither this solver's search nor the reference
# solvers finish in a minute. Counting does not care about the resting places.
#
# Everything below is over LITERALS, so scrambled signs do not matter.
#
#   A relay is a literal r with a clause D = (-r | k1 | .. | km); the k are
#   its tokens, and (r, k) is a node.
#   A choice clause is a clause C in which every literal p has a binary
#   clause (-p | r) to some relay r.
#   Choice clauses are accepted one by one; C is accepted only if, for every
#   literal p of C and every literal p' of an earlier accepted clause with the
#   same relay, the binary clause (-p | -p') is present.
#   Two nodes (r, k), (r', k') of different relays are adjacent when the
#   clause (-r | -r' | -k | -k') is present. The nodes are split greedily into
#   classes of pairwise adjacent nodes of pairwise different relays.
#
# Soundness. Take a model. Every accepted choice clause has a true literal p;
# its relay r is true by (-p | r), so D has a true token k: the clause is sent
# to the node (r, k). Two accepted clauses are never sent to the same relay,
# since (-p | -p') would be false. So they are sent to nodes of different
# relays, and if those two nodes were in one class, (-r | -r' | -k | -k')
# would be false. The accepted clauses therefore go to different classes, and
# more accepted clauses than classes is a contradiction. Each step reads only
# clauses that are present; which literal is taken for a relay, which clause
# for D, and how the classes are grown only change how strong the count is.
#
# Fast mode only: the verdict carries no clausal proof.

WASSAT_RELAY_MAX_VARS = 8000000
WASSAT_RELAY_MAX_CLAUSES = 8000000
WASSAT_RELAY_MAX_TOKENS = 64
WASSAT_RELAY_MAX_NODES = 2500
WASSAT_RELAY_MAX_ENTRIES = 2000000
WASSAT_RELAY_BUDGET = 40000000

# Literal code: 2v for v, 2v + 1 for -v.
-> wassat_relay_code(x) (i64) i64
  return (0 - x) * 2 + 1 if x < 0
  x * 2

-> wassat_relay_neg(c) (i64) i64
  return c - 1 if c % 2 == 1
  c + 1

# Is the binary clause (a | b), as codes, present? bst/badj: binary
# occurrences per literal code. work[0] counts the entries read.
-> wassat_relay_binary(bst, badj, a, b, work) (i64[] i64[] i64 i64 i64[]) i64
  t = bst[a]
  e = bst[a + 1]
  work[0] += e - t
  while t < e
    return 1 if badj[t] == b
    t += 1
  0

# Node of (relay index ri, token code k), or -1. A token written twice in D
# is found at its first place only; the later node just stays isolated.
-> wassat_relay_node(fla, fcs, fcl, rd, rhead, nbase, ri, k) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  ci = rd[ri]
  off = fcs[ci]
  n = fcl[ci]
  head = rhead[ri]
  slot = 0
  j = 0
  while j < n
    c = wassat_relay_code(fla[off + j])
    if c != head
      return nbase[ri] + slot if c == k
      slot += 1
    j += 1
  0 - 1

# st slots: 0 status (1 refuted)   1 accepted choice clauses   2 classes
#           3 relays   4 nodes   5 candidate choice clauses
#           6 stop (1 budget, 2 capacity)
# Returns { "status": 0 or -1, "work": st }.
-> wassat_relay_count_unsat(formula)
  st = i64[8]
  miss = { "status": 0, "work": st }
  return miss unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return miss if nv < 4 || nv > WASSAT_RELAY_MAX_VARS || nc < 4 || nc > WASSAT_RELAY_MAX_CLAUSES
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  top = 2 * nv + 4
  # Literals of four-literal clauses, and binary occurrences per literal.
  cnt4 = i64[top]
  bst = i64[top + 2]
  n4 = 0
  ci = 0
  while ci < nc
    n = fcl[ci]
    off = fcs[ci]
    if n == 4
      n4 += 1
      j = 0
      while j < 4
        cnt4[wassat_relay_code(fla[off + j])] += 1
        j += 1
    elsif n == 2
      bst[wassat_relay_code(fla[off]) + 1] += 1
      bst[wassat_relay_code(fla[off + 1]) + 1] += 1
    ci += 1
  return miss if n4 == 0
  # dof[h]: 1 + the clause D whose head is the literal h (the negated relay).
  # D has exactly one literal whose negation is in no four-literal clause,
  # and that literal is itself in one: the head.
  dof = i64[top]
  nd = 0
  ci = 0
  while ci < nc
    n = fcl[ci]
    if n >= 3 && n <= WASSAT_RELAY_MAX_TOKENS + 1
      off = fcs[ci]
      bad = 0
      badc = 0
      j = 0
      while j < n && bad < 2
        c = wassat_relay_code(fla[off + j])
        if cnt4[wassat_relay_neg(c)] == 0
          bad += 1 if bad == 0 || c != badc
          badc = c
        j += 1
      if bad == 1 && cnt4[badc] > 0 && dof[badc] == 0
        dof[badc] = ci + 1
        nd += 1
    ci += 1
  return miss if nd < 2
  i = 0
  while i <= top
    bst[i + 1] += bst[i]
    i += 1
  badj = i64[bst[top] + 1]
  bfill = i64[top]
  # relay[p]: 1 + the relay code of literal p, from a binary clause (-p | r)
  # whose r has a clause D. With several, the r busiest in the conflicts.
  relay = i64[top]
  leads = 0
  ci = 0
  while ci < nc
    if fcl[ci] == 2
      off = fcs[ci]
      a = wassat_relay_code(fla[off])
      b = wassat_relay_code(fla[off + 1])
      badj[bst[a] + bfill[a]] = b
      bfill[a] += 1
      badj[bst[b] + bfill[b]] = a
      bfill[b] += 1
      na = wassat_relay_neg(a)
      nb = wassat_relay_neg(b)
      if dof[nb] != 0
        leads += 1 if relay[na] == 0
        relay[na] = b + 1 if relay[na] == 0 || cnt4[nb] > cnt4[wassat_relay_neg(relay[na] - 1)]
      if dof[na] != 0
        leads += 1 if relay[nb] == 0
        relay[nb] = a + 1 if relay[nb] == 0 || cnt4[na] > cnt4[wassat_relay_neg(relay[nb] - 1)]
    ci += 1
  # Two choice clauses of two literals each need four literals with a relay.
  return miss if leads < 4
  # Choice clauses, accepted greedily. Entries (literal code) hang off the
  # relay they lead to; ridx numbers the relays in use.
  ridx = i64[top]
  ehead = i64[top]
  ecap = 1024
  elit = i64[ecap]
  enext = i64[ecap]
  ne = 0
  nr = 0
  accepted = 0
  work = i64[2]
  ci = 0
  while ci < nc
    n = fcl[ci]
    if n >= 2
      off = fcs[ci]
      whole = 1
      j = 0
      while j < n && whole == 1
        whole = 0 if relay[wassat_relay_code(fla[off + j])] == 0
        j += 1
      if whole == 1
        st[5] += 1
        ok = 1
        j = 0
        while j < n && ok == 1
          p = wassat_relay_code(fla[off + j])
          r = relay[p] - 1
          np = wassat_relay_neg(p)
          e = ehead[r]
          while e != 0 && ok == 1
            ok = 0 if wassat_relay_binary(bst, badj, np, wassat_relay_neg(elit[e]), work) == 0
            e = enext[e]
          j += 1
        if work[0] > WASSAT_RELAY_BUDGET
          st[6] = 1
          return miss
        if ok == 1
          if ne + n + 2 > ecap
            ecap = (ne + n + 2) * 2
            if ecap > WASSAT_RELAY_MAX_ENTRIES
              st[6] = 2
              return miss
            elit2 = i64[ecap]
            enext2 = i64[ecap]
            q = 0
            while q <= ne
              elit2[q] = elit[q]
              enext2[q] = enext[q]
              q += 1
            elit = elit2
            enext = enext2
          j = 0
          while j < n
            p = wassat_relay_code(fla[off + j])
            r = relay[p] - 1
            if ridx[r] == 0
              nr += 1
              ridx[r] = nr
            ne += 1
            elit[ne] = p
            enext[ne] = ehead[r]
            ehead[r] = ne
            j += 1
          accepted += 1
    ci += 1
  st[1] = accepted
  st[3] = nr
  return miss if accepted < 2 || nr < 2
  # Nodes: the tokens of each relay in use.
  rd = i64[nr + 2]
  rhead = i64[nr + 2]
  nbase = i64[nr + 2]
  nn = 0
  c = 2
  while c < top
    if ridx[c] != 0
      ri = ridx[c]
      h = wassat_relay_neg(c)
      d = dof[h] - 1
      rd[ri] = d
      rhead[ri] = h
    c += 1
  ri = 1
  while ri <= nr
    nbase[ri] = nn
    d = rd[ri]
    off = fcs[d]
    n = fcl[d]
    j = 0
    while j < n
      nn += 1 if wassat_relay_code(fla[off + j]) != rhead[ri]
      j += 1
    ri += 1
  st[4] = nn
  if nn > WASSAT_RELAY_MAX_NODES
    st[6] = 2
    return miss
  nrel = i64[nn + 2]
  ri = 1
  while ri <= nr
    last = ri < nr ? nbase[ri + 1] : nn
    q = nbase[ri]
    while q < last
      nrel[q] = ri
      q += 1
    ri += 1
  adj = i8[nn * nn + 1]
  ci = 0
  while ci < nc
    if fcl[ci] == 4
      off = fcs[ci]
      i = 0
      while i < 4
        r1 = ridx[wassat_relay_neg(wassat_relay_code(fla[off + i]))]
        if r1 != 0
          j = i + 1
          while j < 4
            r2 = ridx[wassat_relay_neg(wassat_relay_code(fla[off + j]))]
            if r2 != 0 && r2 != r1
              # The two remaining places.
              o1 = 0 - 1
              o2 = 0 - 1
              q = 0
              while q < 4
                if q != i && q != j
                  if o1 < 0
                    o1 = q
                  else
                    o2 = q
                q += 1
              k1 = wassat_relay_neg(wassat_relay_code(fla[off + o1]))
              k2 = wassat_relay_neg(wassat_relay_code(fla[off + o2]))
              work[0] += 4 * WASSAT_RELAY_MAX_TOKENS
              x = wassat_relay_node(fla, fcs, fcl, rd, rhead, nbase, r1, k1)
              y = wassat_relay_node(fla, fcs, fcl, rd, rhead, nbase, r2, k2)
              if x >= 0 && y >= 0
                adj[x * nn + y] = 1
                adj[y * nn + x] = 1
              x = wassat_relay_node(fla, fcs, fcl, rd, rhead, nbase, r1, k2)
              y = wassat_relay_node(fla, fcs, fcl, rd, rhead, nbase, r2, k1)
              if x >= 0 && y >= 0
                adj[x * nn + y] = 1
                adj[y * nn + x] = 1
            j += 1
        i += 1
      if work[0] > WASSAT_RELAY_BUDGET
        st[6] = 1
        return miss
    ci += 1
  # Greedy classes: pairwise adjacent, pairwise different relays.
  grp = i64[nn + 2]
  cand = i64[nn + 2]
  rstamp = i64[nr + 2]
  classes = 0
  i = 0
  while i < nn && classes < accepted
    if grp[i] == 0
      classes += 1
      grp[i] = classes
      rstamp[nrel[i]] = classes
      ncand = 0
      j = i + 1
      while j < nn
        if grp[j] == 0 && adj[i * nn + j] == 1
          cand[ncand] = j
          ncand += 1
        j += 1
      t = 0
      while t < ncand
        u = cand[t]
        if u >= 0 && rstamp[nrel[u]] != classes
          grp[u] = classes
          rstamp[nrel[u]] = classes
          q = t + 1
          while q < ncand
            w = cand[q]
            cand[q] = 0 - 1 if w >= 0 && adj[u * nn + w] != 1
            q += 1
          work[0] += ncand - t
        t += 1
      if work[0] > WASSAT_RELAY_BUDGET
        st[6] = 1
        return miss
    i += 1
  # Nodes not reached before the loop stopped would only add classes.
  if i < nn
    st[2] = classes
    return miss
  st[2] = classes
  if accepted > classes
    st[0] = 1
    return { "status": 0 - 1, "work": st }
  miss

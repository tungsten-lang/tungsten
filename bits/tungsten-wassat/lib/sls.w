# Wassat SLS -- CCAnr-family stochastic local search.
#
# A WalkSAT-descendant tuned for STRUCTURED instances, after Cai & Su's
# CCAnr: configuration checking (a variable is only greedily flippable if a
# neighbour changed since its last flip -- this is what lifts the family
# beyond random 3-SAT) combined with clause weighting (the load-bearing half
# on structured instances: stuck states raise the weight of their unsatisfied
# clauses, reshaping the landscape instead of restarting).
#
# Returns a MODEL ONLY, never UNSAT: local search cannot refute. The
# portfolio treats it as a satisfiable-instance specialist beside CDCL.
#
# DATA LAYOUT
#
# Everything the flip loop touches is flat typed storage walked by one
# native function (`wassat_sls_run`), the solver core's proven pattern:
# clause literal arena + offsets, intrusive per-literal occurrence lists,
# per-clause true-literal counts with the classic critical-variable slot
# (O(1) break bookkeeping), per-variable weighted scores maintained
# incrementally, and an unsatisfied-clause list with positions. The plan
# asked for the assignment as bool[]; bool[] in native typed signatures
# currently trips the KIND_BOOL inline-encoding linker bug, so it is i64[]
# holding 0/1 until that is fixed.
#
#   score(v) = w(clauses made satisfied by flipping v)
#            - w(clauses broken by flipping v)
#   A clause contributes only when unsatisfied (every member could make it)
#   or critically satisfied (only its one true variable can break it).

WASSAT_SLS_WEIGHT_CAP_MULT = 16

+ WassatSls
  -> new(@nvars, @input_clauses)
    nv = @nvars
    @impossible = false
    # Local search owes no proof obligations, so clauses are normalised at
    # intake: duplicate literals collapse (they would double-count in the
    # true-occurrence bookkeeping and can corrupt the critical-variable
    # scan) and tautologies drop (always satisfied, pure noise here).
    @work = []
    @input_clauses.each -> (c)
      @impossible = true if c.size == 0
      uniq = []
      taut = false
      c.each -> (l)
        dup = false
        uniq.each -> (u)
          dup = true if u == l
          taut = true if u == 0 - l
        uniq.push(l) unless dup
      @work.push(uniq) unless taut
    total = 0
    @work.each -> (c)
      total += c.size

    @ncl = @work.size
    @fla = i64[total + 2]
    @fcs = i64[@ncl + 2]
    @fcl = i64[@ncl + 2]
    @och = i64[2 * nv + 4]
    i = 0
    while i < 2 * nv + 4
      @och[i] = -1
      i += 1
    @ocn = i64[total + 2]
    @ocv = i64[total + 2]

    pos = 0
    ci = 0
    @work.each -> (c)
      @fcs[ci] = pos
      @fcl[ci] = c.size
      c.each -> (l)
        @fla[pos] = l
        li = l > 0 ? 2 * l : 2 * (0 - l) + 1
        @ocn[pos] = @och[li]
        @ocv[pos] = ci
        @och[li] = pos
        pos += 1
      ci += 1

    @asg = i64[nv + 1]           # 0 false, 1 true (see bool[] note above)
    @satc = i64[@ncl + 2]
    @crit = i64[@ncl + 2]
    @wght = i64[@ncl + 2]
    @score = i64[nv + 1]
    @ccf = i64[nv + 1]
    @lastf = i64[nv + 1]
    @ulist = i64[@ncl + 2]
    @upos = i64[@ncl + 2]
    @gstk = i64[nv + 2]
    @gin = i64[nv + 1]
    @st = i64[12]

  # One full search from a fresh seeded assignment. Deterministic per seed.
  # Returns {"sat", "model", "flips", "restarts", "best_unsat", "seed"}.
  -> solve(max_flips, seed)
    if @impossible
      return { "sat": false, "model": [], "flips": 0, "restarts": 0,
               "best_unsat": 1, "seed": seed }

    # seeded initial assignment (xorshift64*)
    rng = seed
    rng = 88172645463325252 if rng == 0
    v = 1
    while v <= @nvars
      rng = rng ^ (rng << 13)
      rng = rng ^ (rng >> 7)
      rng = rng ^ (rng << 17)
      @asg[v] = rng & 1
      @ccf[v] = 1
      @gin[v] = 0
      @score[v] = 0
      @lastf[v] = 0
      v += 1

    # clause states, unsat list, weights
    ucount = 0
    ci = 0
    while ci < @ncl
      @wght[ci] = 1
      st = @fcs[ci]
      n = @fcl[ci]
      sc = 0
      cv = 0
      j = 0
      while j < n
        l = @fla[st + j]
        lv = l > 0 ? @asg[l] : 1 - @asg[0 - l]
        if lv == 1
          sc += 1
          cv = l.abs
        j += 1
      @satc[ci] = sc
      @crit[ci] = cv
      if sc == 0
        @ulist[ucount] = ci
        @upos[ci] = ucount
        ucount += 1
      else
        @upos[ci] = 0 - 1
      ci += 1

    # initial scores from the definition
    ci = 0
    while ci < @ncl
      if @satc[ci] == 0
        st = @fcs[ci]
        n = @fcl[ci]
        j = 0
        while j < n
          @score[@fla[st + j].abs] += 1
          j += 1
      elsif @satc[ci] == 1
        @score[@crit[ci]] -= 1
      ci += 1

    # seed the goodvar stack with positive-score variables
    gsize = 0
    v = 1
    while v <= @nvars
      if @score[v] > 0
        @gstk[gsize] = v
        gsize += 1
        @gin[v] = 1
      v += 1

    @st[0] = @nvars
    @st[1] = @ncl
    @st[2] = ucount
    @st[3] = gsize
    @st[4] = 0
    @st[5] = max_flips
    @st[6] = rng
    @st[7] = ucount
    @st[8] = @ncl               # total weight (all start at 1)
    @st[9] = 0
    wassat_sls_run(@fla, @fcs, @fcl, @och, @ocn, @ocv, @asg, @satc, @crit,
                   @wght, @score, @ccf, @lastf, @ulist, @upos, @gstk, @gin, @st)

    model = []
    if @st[9] == 1
      v = 1
      while v <= @nvars
        model.push(@asg[v] == 1 ? v : 0 - v)
        v += 1
    { "sat": @st[9] == 1, "model": model, "flips": @st[4], "restarts": 0,
      "best_unsat": @st[7], "seed": seed }

# One complete CCAnr-style search to a model or the flip budget.
#
#   st[0] nvars   st[1] ncl        st[2] unsat count   st[3] goodstack size
#   st[4] flips   st[5] max flips  st[6] rng state     st[7] best unsat
#   st[8] total weight             st[9] 1 = model found
-> wassat_sls_run(fla, fcs, fcl, och, ocn, ocv, asg, satc, crit, wght, score, ccf, lastf, ulist, upos, gstk, gin, st) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[])
  nv = st[0]
  ncl = st[1]
  ucount = st[2]
  gsize = st[3]
  step = st[4]
  maxflips = st[5]
  rng = st[6]
  best = st[7]
  wtotal = st[8]
  found = 0
  wcap = ncl * WASSAT_SLS_WEIGHT_CAP_MULT

  while ucount > 0 && step < maxflips
    # ---- pick: best configuration-changed positive-score variable ---------
    flip = 0
    bestscore = 0
    k = 0
    keep = 0
    while k < gsize
      u = gstk[k]
      if score[u] > 0 && ccf[u] == 1
        gstk[keep] = u
        keep += 1
        better = 0
        if score[u] > bestscore
          better = 1
        else
          if score[u] == bestscore && flip != 0 && lastf[u] < lastf[flip]
            better = 1
        if better == 1
          bestscore = score[u]
          flip = u
      else
        gin[u] = 0
      k += 1
    gsize = keep

    if flip == 0
      # ---- stuck: reweight unsatisfied clauses, then diversify ------------
      k = 0
      while k < ucount
        ci = ulist[k]
        wght[ci] = wght[ci] + 1
        wtotal += 1
        stx = fcs[ci]
        n = fcl[ci]
        j = 0
        while j < n
          uvar = fla[stx + j]
          if uvar < 0
            uvar = 0 - uvar
          score[uvar] = score[uvar] + 1
          if score[uvar] > 0 && ccf[uvar] == 1 && gin[uvar] == 0
            gstk[gsize] = uvar
            gsize += 1
            gin[uvar] = 1
          j += 1
        k += 1
      if wtotal > wcap
        # smooth: halve every weight and rebuild scores from the definition
        i = 0
        wtotal = 0
        while i < ncl
          wght[i] = (wght[i] + 1) / 2
          wtotal += wght[i]
          i += 1
        v2 = 1
        while v2 <= nv
          score[v2] = 0
          v2 += 1
        i = 0
        while i < ncl
          if satc[i] == 0
            stx = fcs[i]
            n = fcl[i]
            j = 0
            while j < n
              uvar = fla[stx + j]
              if uvar < 0
                uvar = 0 - uvar
              score[uvar] = score[uvar] + wght[i]
              j += 1
          else
            if satc[i] == 1
              score[crit[i]] = score[crit[i]] - wght[i]
          i += 1
        gsize = 0
        v2 = 1
        while v2 <= nv
          gin[v2] = 0
          if score[v2] > 0 && ccf[v2] == 1
            gstk[gsize] = v2
            gsize += 1
            gin[v2] = 1
          v2 += 1

      # random unsatisfied clause, best-score member, oldest on ties
      rng = rng ^ (rng << 13)
      rng = rng ^ (rng >> 7)
      rng = rng ^ (rng << 17)
      r = rng
      if r < 0
        r = 0 - r
      ci = ulist[r % ucount]
      stx = fcs[ci]
      n = fcl[ci]
      flip = 0
      bestscore = 0
      j = 0
      while j < n
        uvar = fla[stx + j]
        if uvar < 0
          uvar = 0 - uvar
        better = 0
        if flip == 0
          better = 1
        else
          if score[uvar] > bestscore
            better = 1
          else
            if score[uvar] == bestscore && lastf[uvar] < lastf[flip]
              better = 1
        if better == 1
          bestscore = score[uvar]
          flip = uvar
        j += 1

    # ---- flip -------------------------------------------------------------
    v = flip
    nowtrue = 0
    if asg[v] == 0
      asg[v] = 1
      nowtrue = 1
    else
      asg[v] = 0
    step += 1
    lastf[v] = step
    ccf[v] = 0

    # clauses gaining a true literal: occurrences of v's now-true literal
    li = 0
    if nowtrue == 1
      li = v << 1
    else
      li = (v << 1) + 1
    w = och[li]
    while w >= 0
      ci = ocv[w]
      old = satc[ci]
      satc[ci] = old + 1
      if old == 0
        # leaves the unsat list; every member loses its make bonus, the
        # flipped variable additionally becomes the breaker
        p = upos[ci]
        last = ulist[ucount - 1]
        ulist[p] = last
        upos[last] = p
        ucount -= 1
        upos[ci] = 0 - 1
        crit[ci] = v
        stx = fcs[ci]
        n = fcl[ci]
        j = 0
        while j < n
          uvar = fla[stx + j]
          if uvar < 0
            uvar = 0 - uvar
          score[uvar] = score[uvar] - wght[ci]
          if uvar != v
            ccf[uvar] = 1
            if score[uvar] > 0 && gin[uvar] == 0
              gstk[gsize] = uvar
              gsize += 1
              gin[uvar] = 1
          j += 1
        score[v] = score[v] - wght[ci]
      else
        if old == 1
          x = crit[ci]
          score[x] = score[x] + wght[ci]
          if score[x] > 0 && ccf[x] == 1 && gin[x] == 0
            gstk[gsize] = x
            gsize += 1
            gin[x] = 1
      w = ocn[w]

    # clauses losing a true literal: occurrences of v's now-false literal
    if nowtrue == 1
      li = (v << 1) + 1
    else
      li = v << 1
    w = och[li]
    while w >= 0
      ci = ocv[w]
      old = satc[ci]
      satc[ci] = old - 1
      if old == 1
        # newly unsatisfied: every member gains a make bonus, the flipped
        # variable additionally stops being the breaker
        ulist[ucount] = ci
        upos[ci] = ucount
        ucount += 1
        stx = fcs[ci]
        n = fcl[ci]
        j = 0
        while j < n
          uvar = fla[stx + j]
          if uvar < 0
            uvar = 0 - uvar
          score[uvar] = score[uvar] + wght[ci]
          if uvar != v
            ccf[uvar] = 1
          if score[uvar] > 0 && ccf[uvar] == 1 && gin[uvar] == 0
            gstk[gsize] = uvar
            gsize += 1
            gin[uvar] = 1
          j += 1
        score[v] = score[v] + wght[ci]
      else
        if old == 2
          # find the surviving true literal; it becomes the breaker
          stx = fcs[ci]
          n = fcl[ci]
          x = 0
          j = 0
          while j < n
            l2 = fla[stx + j]
            uvar = l2
            if l2 < 0
              uvar = 0 - l2
            if uvar != v
              lv = 0
              if l2 > 0
                lv = asg[uvar]
              else
                lv = 1 - asg[uvar]
              if lv == 1
                x = uvar
                j = n
              else
                j += 1
            else
              j += 1
          crit[ci] = x
          score[x] = score[x] - wght[ci]
      w = ocn[w]

    if ucount < best
      best = ucount
  if ucount == 0
    found = 1
  st[2] = ucount
  st[3] = gsize
  st[4] = step
  st[6] = rng
  st[7] = best
  st[8] = wtotal
  st[9] = found
  0

# Library entry: parse-level formula in, model or nothing out. Never UNSAT.
-> wassat_sls_solve(formula, max_flips, seed)
  s = WassatSls.new(formula["nvars"], formula["clauses"])
  s.solve(max_flips, seed)

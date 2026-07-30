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

use atomic_stop

WASSAT_SLS_WEIGHT_CAP_MULT = 16

+ WassatSls
  # `stop` is the race's interrupt cell, honoured DURING CONSTRUCTION. The
  # normalisation walk is O(total literals) of boxed work -- on a 10M-clause
  # formula it runs for seconds, and a race arm that constructs its solver
  # inside its thread would otherwise hold the join hostage long after some
  # other arm has answered (measured: lucky wins Large-result_b23 in ~0.4s and
  # the join then waited 5.3s on this constructor). An aborted intake marks
  # the walker unusable (@aborted); solve returns "no model" immediately.
  # `flat` is either the parser's formula Hash
  # (flat_lits/flat_offs/flat_lens/flat_ncl), the already-built raw artifact
  # (fla/fcs/fcl/fncl), or nil. When present the boxed clause list is never
  # touched: normalisation reads the i64[] mirrors and writes this walker's own
  # flat arrays directly, which is both faster and thread-safe (a worker must
  # never subscript a boxed Array -- see the SIGBUS note on the stop cell
  # below). The portfolio passes the raw artifact so the SLS arm cannot
  # accidentally rebuild a second view from the shared parser Hash.
  -> new(@nvars, @input_clauses, stop, flat_in)
    # Same guard as WassatPreprocess: an input without either trusted mirror
    # layout is boxed.
    flat = flat_in
    if flat != nil
      parsed = flat.has_key?("flat_ncl")
      artifact = flat.has_key?("fncl") && flat.has_key?("raw") && flat["raw"] == true
      flat = nil unless parsed || artifact
    nv = @nvars
    @impossible = false
    @aborted = false
    # Local search owes no proof obligations, so clauses are normalised at
    # intake: duplicate literals collapse (they would double-count in the
    # true-occurrence bookkeeping and can corrupt the critical-variable
    # scan) and tautologies drop (always satisfied, pure noise here).
    # .each rather than subscripting, deliberately: worker threads may only
    # iterate a boxed array through the .each IC -- indexing it concurrently
    # from a thread SIGBUSes (the subscript inline cache is not tear-safe the
    # way the iteration path is; measured on ntil-90d-33, instant crash). On
    # abort the walk still touches the remaining clauses, but with an empty
    # body -- the poll costs one flag check per clause.
    @work = []
    flat_ok = false
    total = 0
    if flat != nil
      # Two native passes over the flat mirrors: size, then fill. `pm` carries
      # the counts back; a stamp array does dedupe and tautology detection in
      # O(1) per literal with no allocation at all.
      parsed = flat.has_key?("flat_ncl")
      sfla = parsed ? flat["flat_lits"] : flat["fla"]
      sfcs = parsed ? flat["flat_offs"] : flat["fcs"]
      sfcl = parsed ? flat["flat_lens"] : flat["fcl"]
      sncl = parsed ? flat["flat_ncl"] : flat["fncl"]
      stamp = i64[2 * nv + 4]
      scell = stop == nil ? i64[4] : stop
      pm = i64[6]
      pm[0] = sncl
      pm[1] = nv
      wassat_sls_flat_size(sfla, sfcs, sfcl, stamp, pm, scell)
      @aborted = true if pm[5] == 1
      @impossible = true if pm[4] == 1
      @ncl = pm[2]
      total = pm[3]
      @fla = i64[total + 2]
      @fcs = i64[@ncl + 2]
      @fcl = i64[@ncl + 2]
      k = 0
      while k < 2 * nv + 4
        stamp[k] = 0
        k += 1
      pm[0] = sncl
      pm[1] = nv
      pm[5] = 0
      wassat_sls_flat_fill(sfla, sfcs, sfcl, stamp, @fla, @fcs, @fcl, pm, scell) unless @aborted
      @aborted = true if pm[5] == 1
      @ncl = 0 if @aborted
      flat_ok = true
    unless flat_ok
      cnt = 0
      @input_clauses.each -> (c)
        cnt += 1
        unless @aborted
          if (cnt & 4095) == 0 && stop != nil
            @aborted = true if wassat_stop_requested?(stop)
          unless @aborted
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
      @work = [] if @aborted
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

    # The boxed path still has to flatten @work; the flat path already wrote
    # @fla/@fcs/@fcl in its fill pass. Occurrence lists are then built from the
    # flat arrays in BOTH cases, so there is exactly one occurrence builder.
    unless flat_ok
      pos = 0
      ci = 0
      @work.each -> (c)
        @fcs[ci] = pos
        @fcl[ci] = c.size
        c.each -> (l)
          @fla[pos] = l
          pos += 1
        ci += 1
    ci = 0
    while ci < @ncl
      o = @fcs[ci]
      n = @fcl[ci]
      j = 0
      while j < n
        l = @fla[o + j]
        li = l > 0 ? 2 * l : 2 * (0 - l) + 1
        @ocn[o + j] = @och[li]
        @ocv[o + j] = ci
        @och[li] = o + j
        j += 1
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
    # Best assignment seen, and the trail of variables flipped since it was
    # taken (see wassat_sls_run): the flip loop is not monotone, so the
    # assignment it ends on is routinely worse than the best one it passed
    # through, and the best one is what a phase seed wants.
    @bag = i64[nv + 1]
    @wtr = i64[nv + 4]
    # st[12] is the resume bit.  The portfolio may pause one eligible walk
    # at a fixed prefix to try an exact frozen-fringe repair, then resume the
    # SAME weighted trajectory if the repair misses.  Keeping this bit in the
    # native state block lets wassat_sls_run preserve both @bag and the
    # flip-since-best trail across that cold detour.
    @st = i64[13]
    @started = false
    # Interrupt cell, polled by the flip loop. Private by default so a
    # standalone walk behaves exactly as before; a race arm swaps in the
    # shared cell so a win by any other arm stops this one immediately
    # rather than at the end of its flip budget (see wassat_sls_arm_body).
    @stop = i64[4]
    # [0] improvement window in flips  [1] windows without progress before
    # retiring  [2] set by the kernel when it retired on a plateau
    @plateau = i64[4]

  # Share an interrupt cell with a race. Cell 0 nonzero means "somebody else
  # answered, stop now"; the walker never writes it.
  # Retire the walk after `windows` consecutive `win`-flip windows with no
  # improvement in best-unsat. 0 disables.
  -> set_plateau(win, windows)
    @plateau[0] = win
    @plateau[1] = windows
    0

  -> set_stop_cell(cell)
    @stop = cell
    0

  # One full search from a fresh seeded assignment. Deterministic per seed.
  # Returns {"sat", "model", "flips", "restarts", "best_unsat", "seed"}.
  -> solve(max_flips, seed)
    if @impossible || @aborted
      return { "sat": false, "model": [], "flips": 0, "restarts": 0,
               "best_unsat": 1, "seed": seed, "assign": [],
               "best_assign": [], "best_bits": i64[1],
               "retired": true }

    # seeded initial assignment (xorshift64*); ## i64 prevents BigInt
    # promotion (untyped shifts never wrap)
    rng = seed ## i64
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
    self.run_from_assignment(max_flips, rng)
    @started = true
    self.result(seed)

  # Resume a prefix-bounded walk without resetting its assignment, weights,
  # configuration-change state, RNG, best snapshot, or flip-since-best trail.
  # `max_flips` is the new TOTAL ceiling, not an additional allowance.
  -> continue_solve(max_flips, seed)
    return self.result(seed) unless @started
    return self.result(seed) if max_flips <= @st[4] || @st[9] == 1
    @st[5] = max_flips
    @st[12] = 1
    wassat_sls_run(@fla, @fcs, @fcl, @och, @ocn, @ocv, @asg, @satc, @crit,
                   @wght, @score, @ccf, @lastf, @ulist, @upos, @gstk, @gin,
                   @bag, @wtr, @st, @stop, @plateau)
    self.result(seed)

  # Detached result construction.  `best_bits` is the allocation-stable
  # native snapshot consumed by frozen-fringe repair; `best_assign` is its
  # literal-form public twin.  Before this split the miss payload labelled as
  # a near-solution was built from @asg, the arbitrary FINAL assignment, even
  # though @bag already retained the strictly better point.
  -> result(seed)
    model = []
    if @st[9] == 1
      v = 1
      while v <= @nvars
        model.push(@asg[v] == 1 ? v : 0 - v)
        v += 1
    # A miss returns the BEST assignment, not the arbitrary endpoint: a
    # near-solution is exactly the polarity/frozen-core seed CDCL wants
    # (cms5's CCAnr/'polar stb' trick).
    assign = []
    best_bits = i64[@nvars + 1]
    v = 1
    while v <= @nvars
      bit = @bag[v]
      best_bits[v] = bit
      assign.push(bit == 1 ? v : 0 - v)
      v += 1
    { "sat": @st[9] == 1, "model": model, "assign": assign, "flips": @st[4],
      "best_assign": assign.dup, "best_bits": best_bits,
      "restarts": 0, "best_unsat": @st[7], "seed": seed,
      "retired": @plateau[2] == 1 }

  # Everything downstream of the initial assignment: clause states, weights,
  # scores, the good-variable stack, then the flip loop. @asg must already
  # hold the assignment to start from -- `solve` seeds it randomly,
  # `walk_from_phase` seeds it from CDCL's saved phases.
  -> run_from_assignment(max_flips, rng)
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
    @st[10] = 0
    @st[11] = 0
    @st[12] = 0
    wassat_sls_run(@fla, @fcs, @fcl, @och, @ocn, @ocv, @asg, @satc, @crit,
                   @wght, @score, @ccf, @lastf, @ulist, @upos, @gstk, @gin,
                   @bag, @wtr, @st, @stop, @plateau)
    0

  # Build the flat structures directly from a CDCL solver's clause arena:
  # the IRREDUNDANT clauses (learned ones are implied, and carrying them
  # would only distort the weights), root-satisfied clauses dropped and
  # root-falsified literals removed. No array-of-arrays intermediate -- a
  # walk that runs at every other rephase on a 200k-clause kernel cannot
  # afford the boxed round trip the parse-level constructor makes.
  #
  # ALLOCATION half, and the only half that allocates: sized once, from the
  # solver's initial irredundant clause set, because a walk that runs inside
  # a portfolio worker thread must not allocate (see Wassat#enable_fixed_caps
  # — every buffer a thread touches is built on the main thread before the
  # spawn). Headroom absorbs the irredundant clauses inprocessing adds
  # afterwards; past that the refill simply stops early, which costs the
  # walk resolution and nothing else.
  -> alloc_arena(cmeta, alive, clbd, ncl_in)
    nv = @nvars
    @apm = i64[8]
    @apm[0] = ncl_in
    @apm[1] = nv
    wassat_sls_arena_size(cmeta, alive, clbd, @apm)
    cap = @apm[4] + @apm[4] / 4 + 4096
    tot = @apm[5] + @apm[5] / 4 + 16384
    @wcap_cl = cap
    @wcap_lit = tot
    @fla = i64[tot + 2]
    @fcs = i64[cap + 2]
    @fcl = i64[cap + 2]
    @och = i64[2 * nv + 4]
    @ocn = i64[tot + 2]
    @ocv = i64[tot + 2]
    @stamp = i64[2 * nv + 4]
    @satc = i64[cap + 2]
    @crit = i64[cap + 2]
    @wght = i64[cap + 2]
    @ulist = i64[cap + 2]
    @upos = i64[cap + 2]
    @impossible = false
    cap

  # FILL half: allocation-free, and therefore legal inside a worker thread.
  # Re-read every walk rather than cached, exactly as kissat rebuilds its
  # walker per walk: the root trail grows and clauses die between walks, and
  # a stale view would walk clauses that no longer constrain anything.
  -> refill_arena(ar, cmeta, alive, clbd, ncl_in, asg)
    @apm[0] = ncl_in
    @apm[1] = @nvars
    @apm[6] = @wcap_cl
    @apm[7] = @wcap_lit
    wassat_sls_from_arena(ar, cmeta, alive, clbd, asg, @fla, @fcs, @fcl,
                          @och, @ocn, @ocv, @stamp, @apm)
    @ncl = @apm[2]
    @ncl

  # THE phase-feedback entry point: a bounded walk seeded FROM the solver's
  # saved phases whose best assignment is written straight BACK into them.
  #
  # Unconditional on purpose. Every leading solver does this and none of
  # them gate it on finding a model: kissat's `rephase_walking` hands the
  # saved phases to walk.c and copies the walker's minimum back out,
  # CryptoMiniSat's ccnr_cms.cpp writes `stable_polarity` from the CCAnr
  # assignment whether or not it was a model. The payload is the
  # near-solution, not the solution -- a run that ends 12 clauses short has
  # still told CDCL where to descend.
  #
  # Returns the number of clauses left unsatisfied at the best point.
  -> walk_from_phase(phase, max_flips, seed)
    return 0 - 1 if @ncl == 0 || @nvars == 0
    rng = seed ## i64
    rng = 88172645463325252 if rng == 0
    v = 1
    while v <= @nvars
      @asg[v] = phase[v] > 0 ? 1 : 0
      @ccf[v] = 1
      @gin[v] = 0
      @score[v] = 0
      @lastf[v] = 0
      v += 1
    self.run_from_assignment(max_flips, rng)
    v = 1
    while v <= @nvars
      phase[v] = @bag[v] == 1 ? 1 : -1
      v += 1
    @st[7]

# One complete CCAnr-style search to a model or the flip budget.
#
#   st[0] nvars   st[1] ncl        st[2] unsat count   st[3] goodstack size
#   st[4] flips   st[5] max flips  st[6] rng state     st[7] best unsat
#   st[8] total weight             st[9] 1 = model found
#   st[10] flip-trail size         st[11] flip trail overflowed
#   st[12] resume existing native state (preserve best snapshot/trail)
# Pass 1: count surviving clauses and literals. A clause is dropped when it is
# a tautology; duplicate literals collapse. `stamp` holds a per-literal
# generation so both tests are O(1) with no allocation -- the same trick the
# preprocessor's subsumption uses.
#   pm in : [0] ncl  [1] nvars
#   pm out: [2] clauses kept  [3] literals kept  [4] saw-empty-clause
-> wassat_sls_flat_size(fla, fcs, fcl, stamp, pm, stp) (i64[] i64[] i64[] i64[] i64[] i64[])
  ncl = pm[0]
  nv = pm[1]
  keep = 0
  lits = 0
  empty = 0
  gen = 0
  ci = 0
  while ci < ncl
    if (ci & 8191) == 0
      if wassat_stop_load(stp) != 0
        pm[5] = 1
        # Do not use `ci = ncl` as a loop-break sentinel here: the clause
        # body follows this poll in the same iteration, so that form reads
        # fcs[ncl]/fcl[ncl]. Parser mirrors are exactly ncl entries long.
        return 0
    o = fcs[ci]
    n = fcl[ci]
    empty = 1 if n == 0
    gen += 1
    taut = 0
    uniq = 0
    j = 0
    while j < n
      l = fla[o + j]
      li = 0
      if l > 0
        li = 2 * l
      else
        li = 2 * (0 - l) + 1
      if li >= 0 && li < 2 * nv + 4
        taut = 1 if stamp[li ^ 1] == gen
        if stamp[li] != gen
          stamp[li] = gen
          uniq += 1
      j += 1
    if taut == 0
      keep += 1
      lits += uniq
    ci += 1
  pm[2] = keep
  pm[3] = lits
  pm[4] = empty
  0

# Pass 2: write the deduplicated, tautology-free clauses into the walker's own
# flat arrays. Identical traversal to pass 1, so the counts cannot disagree.
-> wassat_sls_flat_fill(fla, fcs, fcl, stamp, ofla, ofcs, ofcl, pm, stp) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[])
  ncl = pm[0]
  nv = pm[1]
  gen = 0
  out = 0
  pos = 0
  ci = 0
  while ci < ncl
    if (ci & 8191) == 0
      if wassat_stop_load(stp) != 0
        pm[5] = 1
        # See the sizing pass above. A pre-raised stop must return before
        # touching the first clause, not redirect the current read one past
        # the end of an exact-sized mirror.
        return 0
    o = fcs[ci]
    n = fcl[ci]
    gen += 1
    taut = 0
    j = 0
    while j < n
      l = fla[o + j]
      li = 0
      if l > 0
        li = 2 * l
      else
        li = 2 * (0 - l) + 1
      if li >= 0 && li < 2 * nv + 4
        taut = 1 if stamp[li ^ 1] == gen
        stamp[li] = gen
      j += 1
    if taut == 0
      gen += 1
      start = pos
      j = 0
      while j < n
        l = fla[o + j]
        li = 0
        if l > 0
          li = 2 * l
        else
          li = 2 * (0 - l) + 1
        if li >= 0 && li < 2 * nv + 4
          if stamp[li] != gen
            stamp[li] = gen
            ofla[pos] = l
            pos += 1
        j += 1
      ofcs[out] = start
      ofcl[out] = pos - start
      out += 1
    ci += 1
  pm[2] = out
  pm[3] = pos
  0

-> wassat_sls_run(fla, fcs, fcl, och, ocn, ocv, asg, satc, crit, wght, score, ccf, lastf, ulist, upos, gstk, gin, bag, wtr, st, stp, pm2) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[])
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
  # Best-assignment snapshot, kissat walk.c's `update_best`. The search is
  # not monotone -- clause weighting deliberately climbs out of minima --
  # so the assignment the budget happens to end on is routinely worse than
  # the best one passed through. Copying all of `asg` at every improvement
  # is O(nv) per improvement; instead flipped variables are trailed and the
  # snapshot is patched with just that delta (kissat's trick), with a full
  # copy as the overflow fallback once the trail passes nv/4.
  resume = st[12]
  wtn = resume == 1 ? st[10] : 0
  wovf = resume == 1 ? st[11] : 0
  wtcap = nv / 4 + 1
  if resume == 0
    vb = 1
    while vb <= nv
      bag[vb] = asg[vb]
      vb += 1

  # Plateau retirement. A walker that has stopped improving its best-unsat
  # count will not answer, and on an UNSAT instance it never can -- it just
  # holds a core a CDCL arm would use. Measured: removing the arm outright is
  # worth 24% on shuffling-1 and 10% on smulo016 but COSTS 15-21% on
  # qg3-09/qg5-13, so the static choice is wrong in both directions and the
  # arm has to decide for itself. pm2[0] is the improvement window in flips,
  # pm2[1] the number of consecutive windows without progress that retires it,
  # and the kernel sets pm2[2] when it did. 0 disables.
  plat_win = pm2[0]
  plat_max = pm2[1]
  plat_ref = best
  plat_run = 0
  plat_next = plat_win
  plat_stop = 0
  while ucount > 0 && step < maxflips && wassat_stop_load(stp) == 0 && plat_stop == 0
    if plat_win > 0 && step >= plat_next
      plat_next = step + plat_win
      if best < plat_ref
        plat_ref = best
        plat_run = 0
      else
        plat_run += 1
        if plat_run >= plat_max
          plat_stop = 1
          pm2[2] = 1
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
    if wovf == 0
      if wtn < wtcap
        wtr[wtn] = v
        wtn += 1
      else
        wovf = 1

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
      if wovf == 1
        vb = 1
        while vb <= nv
          bag[vb] = asg[vb]
          vb += 1
        wovf = 0
      else
        kb = 0
        while kb < wtn
          xb = wtr[kb]
          bag[xb] = asg[xb]
          kb += 1
      wtn = 0
  if ucount == 0
    found = 1
  st[2] = ucount
  st[3] = gsize
  st[4] = step
  st[6] = rng
  st[7] = best
  st[8] = wtotal
  st[9] = found
  st[10] = wtn
  st[11] = wovf
  st[12] = 1
  0

# Mark the smallest exact SAT-repair fringe around a best SLS snapshot:
# every variable in every currently unsatisfied clause is mutable; all other
# variables may be frozen to their snapshot values.  The caller can then grow
# this set from failed-assumption cores without ever guessing which frozen
# coordinate blocked the extension.
#
# meta[0] = unsatisfied clauses, meta[1] = distinct mutable variables.
-> wassat_sls_mark_fringe(fla, fcs, fcl, ncl, bits, mutable, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  meta[0] = 0
  meta[1] = 0
  ci = 0
  while ci < ncl
    o = fcs[ci]
    n = fcl[ci]
    satisfied = 0
    j = 0
    while j < n
      l = fla[o + j]
      v = l
      v = 0 - l if l < 0
      bit = bits[v]
      if (l > 0 && bit == 1) || (l < 0 && bit == 0)
        satisfied = 1
        j = n
      else
        j += 1
    if satisfied == 0
      meta[0] += 1
      j = 0
      while j < n
        v = fla[o + j]
        v = 0 - v if v < 0
        if mutable[v] == 0
          mutable[v] = 1
          meta[1] += 1
        j += 1
    ci += 1
  meta[0]

# Worst-case sizing for a walk over a solver's arena: how many irredundant
# clauses are alive and how many literals they hold. Learned clauses carry a
# non-zero LBD, originals do not -- the same test `reduce_db` uses.
-> wassat_sls_arena_size(cmeta, alive, clbd, pm) (i64[] i64[] i64[] i64[])
  ncl_in = pm[0]
  tot = 0
  cnt = 0
  ci = 0
  while ci < ncl_in
    if alive[ci] == 1 && clbd[ci] == 0
      tot += cmeta[2 * ci + 1]
      cnt += 1
    ci += 1
  pm[4] = cnt
  pm[5] = tot
  0

# Fill the walk's flat structures from the arena in one pass. Clauses
# already satisfied by the ROOT trail are dropped and root-falsified
# literals removed, so the walk works on exactly the residual problem --
# kissat's walker does the same before connecting its counters. Duplicate
# literals collapse and tautologies drop (both corrupt the critical-variable
# bookkeeping), using a per-clause stamp rather than the parse-level
# constructor's quadratic scan.
#
#   pm[0] clauses in   pm[1] nvars   pm[2] clauses out   pm[3] literals out
#   pm[6] clause capacity            pm[7] literal capacity
-> wassat_sls_from_arena(ar, cmeta, alive, clbd, asg, fla, fcs, fcl, och, ocn, ocv, stamp, pm) (i64[] i64[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[])
  ncl_in = pm[0]
  nv = pm[1]
  capcl = pm[6]
  caplit = pm[7]
  i = 0
  while i < 2 * nv + 4
    och[i] = -1
    stamp[i] = 0
    i += 1
  out = 0
  pos = 0
  mark = 0
  stop = 0
  ci = 0
  while ci < ncl_in && stop == 0
    if alive[ci] == 1 && clbd[ci] == 0
      stx = cmeta[2 * ci]
      n = cmeta[2 * ci + 1]
      if out >= capcl || pos + n > caplit
        stop = 1
        n = 0
      mark += 1
      keep = 1
      start = pos
      cnt = 0
      j = 0
      while j < n
        l = ar[stx + j]
        v = l
        v = 0 - l if l < 0
        a = asg[v]
        tv = a
        tv = 0 - a if l < 0
        if tv > 0
          keep = 0
          j = n
        else
          if tv == 0
            li = 2 * v
            li = 2 * v + 1 if l < 0
            if stamp[li ^ 1] == mark
              keep = 0
              j = n
            else
              if stamp[li] != mark
                stamp[li] = mark
                fla[pos] = l
                pos += 1
                cnt += 1
              j += 1
          else
            j += 1
      keep = 0 if cnt == 0 || stop == 1
      if keep == 1
        fcs[out] = start
        fcl[out] = cnt
        k = 0
        while k < cnt
          l = fla[start + k]
          li = 2 * l
          li = 2 * (0 - l) + 1 if l < 0
          ocn[start + k] = och[li]
          ocv[start + k] = out
          och[li] = start + k
          k += 1
        out += 1
      else
        pos = start
    ci += 1
  pm[2] = out
  pm[3] = pos
  0

# Library entry: parse-level formula in, model or nothing out. Never UNSAT.
-> wassat_sls_solve(formula, max_flips, seed)
  # Formulas from the BOXED parser carry no flat mirrors, so only hand the
  # walker the flat path when they are actually present.
  flat = formula.has_key?("flat_ncl") ? formula : nil
  boxed = flat == nil ? formula["clauses"] : []
  s = WassatSls.new(formula["nvars"], boxed, nil, flat)
  s.solve(max_flips, seed)

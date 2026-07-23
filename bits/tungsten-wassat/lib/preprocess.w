# Wassat preprocessing -- DETOUR dominance rules for CNF.
#
# Runs once, above solver construction, on the parsed formula. Consumes
# {"nvars", "clauses"} and produces an immutable artifact: the reduced clause
# list with its global proof ids, the elimination stack needed to reconstruct
# a model of the ORIGINAL formula from a model of the reduced one, and the
# proof prefix justifying every transformation. No arm ever re-preprocesses;
# every arm consumes this artifact.
#
# Four techniques, in this order, each independently budgeted and testable:
#
#   1. Failed-literal probing   assume v, propagate; conflict => unit -v
#   2. Equivalent-literal substitution   SCCs of the binary implication graph
#   3. Subsumption + self-subsuming strengthening
#   4. Bounded variable elimination (BVE), atomic per variable
#
# PROOF OBLIGATIONS
#
# Every derived clause is RUP and is logged like a learned clause: additions
# carry hint chains (the parent ids that make the checker's replay
# deterministic), deletions carry none because deleting only weakens the
# formula. The obligation that actually bites is on SAT answers: an
# eliminated variable is absent from the reduced formula, so its value must
# be reconstructed by walking the elimination stack backwards. The stack is
# built in the same pass as the deletions it undoes.
#
# Hints are emitted directly from the antecedents at derivation time --
# probing records reasons on its trail, resolution knows its two parents --
# never reconstructed afterwards by database scan.
#
# DATA LAYOUT
#
# The proof-side truth is boxed (@lits: one literal Array per clause, feeding
# proof lines, resolution, and the elimination stack). Everything the hot
# loops touch is mirrored flat, exactly like the solver core: a typed literal
# arena with per-clause offsets, typed alive/tautology/signature/proof-id
# columns, intrusive occurrence lists threaded through typed arrays, and a
# typed trail. Root propagation and subsumption candidate scanning run as
# native top-level functions over those arrays; a profile of the boxed
# version spent ~90% of its time re-boxing literal reads.

WASSAT_PRE_PROBE_CAP = 2000
WASSAT_PRE_OCC_PRODUCT_CAP = 4096
WASSAT_PRE_MAX_PASSES = 10
WASSAT_PRE_PROBE_TICKS = 2000000
WASSAT_PRE_BUCKET_CAP = 1024

+ WassatPreprocess
  -> new(@nvars, @input_clauses, @proof_mode)
    nv = @nvars
    @passign = i64[nv + 1]       # root assignment: 0 / 1 / -1
    @preason = i64[nv + 1]       # root reason clause index, -1 = none
    @tpos = i64[nv + 1]          # trail position, for hint ordering
    @seen = i64[nv + 1]          # scratch marks for cone closure
    @gone = i64[nv + 1]          # 0 live, 1 = BVE-eliminated, 2 = substituted
    @frozen = i64[nv + 1]
    @replit = i64[nv + 1]        # substitution: var -> representative literal
    v = 0
    while v <= nv
      @preason[v] = -1
      @replit[v] = 0
      v += 1

    # typed trail (root prefix + probe segment, contiguous)
    @ftrail = i64[nv + 2]
    @ftsize = 0
    @fqhead = 0

    # clause storage: boxed literal arrays as the proof-side truth, flat
    # typed mirrors for the scan loops
    @lits = []                   # ci -> Array of literals
    total = 0
    @input_clauses.each -> (c)
      total += c.size
    @fccap = 2 * @input_clauses.size + 4 * nv + 1024
    @facap = 2 * total + 8 * nv + 4096
    @fcs = i64[@fccap]           # ci -> arena offset
    @fcl = i64[@fccap]           # ci -> length
    @falive = i64[@fccap]        # ci -> 1 live, 0 deleted (logical/proof life)
    @ftaut = i64[@fccap]         # ci -> 1 when the clause is a tautology
    @fsig = i64[@fccap]          # ci -> 64-bit literal signature
    @fpgid = i64[@fccap]         # ci -> global proof id
    @fla = i64[@facap]           # literal arena
    @fasize = 0
    @next_gid = 1
    @ncl = 0

    # intrusive occurrence lists: one node per stored literal occurrence
    @ocap = @facap
    @oh = i64[2 * nv + 2]        # lit_index -> first node, -1 = empty
    @on = i64[@ocap]             # node -> next node
    @ov = i64[@ocap]             # node -> clause index
    @ocount = i64[2 * nv + 2]    # lit_index -> stored occurrences (not decayed)
    @osize = 0
    i = 0
    while i < 2 * nv + 2
      @oh[i] = -1
      i += 1

    # proof prefix streams (in-memory; the coordinator owns writing them out)
    @emit_wrat = @proof_mode == WASSAT_PROOF_WRAT
    @emit_drat = @proof_mode == WASSAT_PROOF_DRAT
    @wrat_lines = []
    @drat_lines = []

    # elimination stack: tagged entries, walked backwards at reconstruction
    @stack = []

    @status = 0                  # 0 unknown, -1 refuted during preprocessing
    @ticks = 0
    @tick_budget = 0             # 0 = derived from formula size in `run`
    @probe_cap = WASSAT_PRE_PROBE_CAP
    # BVE growth margin, raised per pass (CaDiCaL-style elimination
    # rounds): Sinz-counter registers — the whole encoding layer of
    # cardinality instances — cost ONE extra literal to eliminate and a
    # zero-growth bound rejects every one of them. Measured on the k=5
    # Lonely Runner class: margin 0 eliminated 44 variables, the pass-2
    # margin unlocked 573 of 976 (CaDiCaL's inprocessing gets 596).
    @bve_margin = 0

    # stats
    @probes_run = 0
    @probes_failed = 0
    @vars_substituted = 0
    @clauses_subsumed = 0
    @clauses_strengthened = 0
    @vars_eliminated = 0

    # native-call scratch
    @pst = i64[4]                # qhead / tsize / conflict / ticks
    @subscan_pm = i64[10]
    @subscan_out = i64[16384]    # survivor triples: 3 slots each + header
    @bve_pm = i64[12]
    @bve_out = i64[131072]       # packed resolvents: [len, aci, bci, lits...]*
    @bve_hash = i64[8192]        # per-candidate resolvent dedup hashes

    # reusable BFS scratch for implication paths (allocated on first use);
    # a fresh boxed array per path was the substitution phase's entire cost
    @bfs_from = i64[1]
    @bfs_ci = i64[1]
    @bfs_mark = i64[1]
    @bfs_gen = 0
    @bfs_ready = 0

    # literal stamps for subsumption: mark the subsumer's literals once,
    # count marks per candidate. The exact subset check runs only on
    # candidates that pass the count filter.
    @lstamp = i64[2 * nv + 2]
    @lgen = 0

    # Certificate-lifetime state. A proof citation is valid only if it
    # precedes any deletion of the cited clause in the stream, so: helper
    # equivalence binaries are excluded from rewriting and deleted only
    # after the whole class is rewritten (@helper_mark), and root literals
    # propagated from multi-literal clauses get their unit derived
    # immediately (never at sweep time, when the reason may be gone).
    # @probing suppresses unit derivation for temporary probe assignments.
    @helper_mark = {}
    @probing = false
    @lazy_lits = false
    @raw_kernel = false

  # From-flat intake for the trusted path: the native parser's flat arrays
  # fill the mirrors (arena, occurrence lists, signatures, tautology marks,
  # sequential proof ids) in one native pass; the boxed @lits truth — still
  # needed by rewriting, resolution commits, the elimination stack, and the
  # artifact — is built by a single cheap walk. Replaces the boxed
  # per-literal store() intake. Call INSTEAD of intake() via run_light_flat.
  -> intake_flat(parse)
    @fqhead = 0
    ncl = parse["flat_ncl"]
    lits = parse["flat_lits"]
    offs = parse["flat_offs"]
    lens = parse["flat_lens"]
    pm = i64[8]
    pm[0] = ncl
    wassat_pre_intake(lits, offs, lens, @fla, @fcs, @fcl, @falive, @ftaut,
                      @fsig, @fpgid, @oh, @on, @ov, @ocount, pm)
    @ncl = ncl
    @fasize = pm[1]
    @osize = pm[2]
    @next_gid = ncl + 1
    # boxed truth stays LAZY: nil slots, materialized per clause on touch
    @lazy_lits = true
    k = 0
    while k < ncl
      @lits.push(nil)
      k += 1
    # fire input units / empty clauses exactly like intake()
    ci = 0
    while ci < @ncl && @status == 0
      n = @fcl[ci]
      if n == 0
        self.plog_add(@next_gid, [], [@fpgid[ci]])
        @next_gid += 1
        @status = -1
      elsif n == 1 && @ftaut[ci] == 0
        l = @fla[@fcs[ci]]
        lv = self.value(l)
        if lv < 0
          self.refute(ci)
        elsif lv == 0
          self.assign(l, ci)
      ci += 1
    if @status == 0
      confl = self.propagate_root
      self.refute(confl) if confl >= 0
    0

  -> run_light_flat(parse)
    self.init_budget
    tp = wassat_prof_clock
    self.intake_flat(parse)
    tp = wassat_prof("pre.intake_flat", tp)
    # Raw-kernel policy, measured on the bmc family: on big structured
    # instances substitution made search HARDER (ibm-12: 12.2k conflicts on
    # the substituted kernel, 6.5k after heavy repair, 4.9k raw) and every
    # pipeline phase was pure overhead on top. Modern-solver shape: large
    # inputs go straight to CDCL; preprocessing effort belongs to small
    # kernels where it is cheap and provably shrinks search (php, dubois,
    # lr5's Sinz chains). WASSAT_RAW=1/0 forces either policy.
    raw = @ncl > 50000
    raw = env("WASSAT_RAW") == "1" if env("WASSAT_RAW") != nil
    @raw_kernel = raw
    self.run_probing if @status == 0 && !raw
    tp = wassat_prof("pre.probing", tp)
    self.run_substitution if @status == 0 && !raw
    tp = wassat_prof("pre.substitution", tp)
    self.sweep_satisfied if @status == 0
    tp = wassat_prof("pre.sweep", tp)
    art = self.artifact
    tp = wassat_prof("pre.artifact", tp)
    art

  # Lazy boxed truth: intake_flat leaves @lits as nil slots and clauses
  # materialize from the flat mirrors only when a technique actually touches
  # them (proof lines, subset re-verification, the elimination stack, the
  # artifact). The certificate path's intake() stays fully materialized.
  -> lits_of(ci)
    c = @lits[ci]
    return c unless c == nil
    st = @fcs[ci]
    n = @fcl[ci]
    c = []
    j = 0
    while j < n
      c.push(@fla[st + j])
      j += 1
    @lits[ci] = c
    c

  # Both proof dialects at once (CLI requested --proof and --drat together).
  -> enable_dual_emission
    @emit_wrat = true
    @emit_drat = true
    0

  -> set_budget(ticks)
    @tick_budget = ticks
    0

  -> freeze(v)
    @frozen[v] = 1
    0

  # ---- literal helpers ------------------------------------------------------

  -> lit_index(l)
    l > 0 ? 2 * l : 2 * (0 - l) + 1

  -> value(l)
    a = @passign[l.abs]
    l > 0 ? a : 0 - a

  -> signature_of(arr)
    s = 0
    i = 0
    while i < arr.size
      s = s | (1 << (arr[i].abs & 63))
      i += 1
    s

  # ---- proof emission -------------------------------------------------------

  -> plog_add(gid, lits_arr, hints)
    if @emit_wrat
      body = lits_arr.empty? ? "" : lits_arr.join(" ") + " "
      @wrat_lines.push("[gid] " + body + "0 " + hints.join(" ") + " 0")
    if @emit_drat
      @drat_lines.push(lits_arr.empty? ? "0" : lits_arr.join(" ") + " 0")
    0

  -> plog_delete(ids, lits_list)
    if @emit_wrat && !ids.empty?
      last = @next_gid - 1
      @wrat_lines.push("[last] d " + ids.join(" ") + " 0")
    if @emit_drat
      lits_list.each -> (arr)
        @drat_lines.push(arr.empty? ? "d 0" : "d " + arr.join(" ") + " 0")
    0

  # ---- clause database ------------------------------------------------------

  -> grow_meta
    if @ncl + 1 >= @fccap
      ncap = @fccap * 2
      cs = i64[ncap]
      cl = i64[ncap]
      al = i64[ncap]
      tt = i64[ncap]
      sg = i64[ncap]
      gd = i64[ncap]
      i = 0
      while i < @ncl
        cs[i] = @fcs[i]
        cl[i] = @fcl[i]
        al[i] = @falive[i]
        tt[i] = @ftaut[i]
        sg[i] = @fsig[i]
        gd[i] = @fpgid[i]
        i += 1
      @fcs = cs
      @fcl = cl
      @falive = al
      @ftaut = tt
      @fsig = sg
      @fpgid = gd
      @fccap = ncap
    0

  -> grow_arena(need)
    if @fasize + need > @facap
      ncap = @facap * 2
      ncap = @fasize + need + 4096 if ncap < @fasize + need
      bigger = i64[ncap]
      i = 0
      while i < @fasize
        bigger[i] = @fla[i]
        i += 1
      @fla = bigger
      @facap = ncap
    0

  -> grow_occ(need)
    if @osize + need > @ocap
      ncap = @ocap * 2
      ncap = @osize + need + 4096 if ncap < @osize + need
      nn = i64[ncap]
      nv2 = i64[ncap]
      i = 0
      while i < @osize
        nn[i] = @on[i]
        nv2[i] = @ov[i]
        i += 1
      @on = nn
      @ov = nv2
      @ocap = ncap
    0

  # Store a clause; assigns the next global proof id. Detects tautologies and
  # registers occurrences. Does not emit proof lines -- input clauses are the
  # checker's axioms and additions log themselves at the derivation site.
  -> store(arr)
    self.grow_meta
    self.grow_arena(arr.size)
    self.grow_occ(arr.size)
    ci = @ncl
    @ncl += 1
    @lits.push(arr)
    @fcs[ci] = @fasize
    @fcl[ci] = arr.size
    @falive[ci] = 1
    @fpgid[ci] = @next_gid
    @next_gid += 1
    @fsig[ci] = self.signature_of(arr)
    t = 0
    i = 0
    while i < arr.size
      j = 0
      while j < arr.size
        t = 1 if arr[i] == 0 - arr[j]
        j += 1
      i += 1
    @ftaut[ci] = t
    i = 0
    while i < arr.size
      l = arr[i]
      @fla[@fasize] = l
      @fasize += 1
      li = self.lit_index(l)
      slot = @osize
      @osize += 1
      @on[slot] = @oh[li]
      @ov[slot] = ci
      @oh[li] = slot
      @ocount[li] = @ocount[li] + 1
      i += 1
    ci

  # Delete one clause from the logical database, with its proof line.
  -> delete_clause(ci)
    if @falive[ci] == 1
      @falive[ci] = 0
      self.plog_delete([@fpgid[ci]], [self.lits_of(ci)])
    0

  # Delete a batch with one WRAT line (and per-clause DRAT lines).
  -> delete_batch(cis)
    ids = []
    lls = []
    cis.each -> (ci)
      if @falive[ci] == 1
        @falive[ci] = 0
        ids.push(@fpgid[ci])
        lls.push(self.lits_of(ci))
    self.plog_delete(ids, lls) unless ids.empty?
    0

  # ---- root propagation with reasons ---------------------------------------

  -> assign(l, from)
    v = l.abs
    @passign[v] = l > 0 ? 1 : -1
    @preason[v] = from
    @tpos[v] = @ftsize
    @ftrail[@ftsize] = l
    @ftsize += 1
    0

  # Propagate the unconsumed tail of the trail to fixpoint. Returns the
  # conflicting clause index or -1. Delegates to the native occurrence-scan
  # loop; every implication records its reason and trail position so hint
  # chains can be emitted directly.
  -> propagate_root
    pre_ts = @ftsize
    @pst[0] = @fqhead
    @pst[1] = @ftsize
    @pst[2] = -1
    @pst[3] = 0
    wassat_pre_prop(@fla, @fcs, @fcl, @falive, @ftaut, @oh, @on, @ov,
                    @passign, @preason, @tpos, @ftrail, @pst)
    @fqhead = @pst[0]
    @ftsize = @pst[1]
    @ticks += @pst[3]
    confl = @pst[2]
    # Committed root implications derive their units NOW, while every
    # antecedent is still alive; a conflict path instead emits the empty
    # clause immediately (also while everything it cites is alive).
    self.derive_root_units(pre_ts) unless @probing || confl >= 0
    confl

  # Root literals propagated from multi-literal clauses get an explicit RUP
  # unit at once: later techniques may delete the reason clause, and a
  # citation emitted after that deletion is invalid. @preason is re-pointed
  # at the unit so every later cone cites the unit instead.
  -> derive_root_units(from_ts)
    ti = from_ts
    while ti < @ftsize
      l = @ftrail[ti]
      rci = @preason[l.abs]
      if rci >= 0 && @fcl[rci] > 1
        chain = self.conflict_chain(rci, l.abs)
        gid = @next_gid
        self.plog_add(gid, [l], chain)
        nci = self.store([l])
        @preason[l.abs] = nci
      ti += 1
    0

  # ---- hint chains ----------------------------------------------------------

  # Cone closure: the ordered antecedent chain justifying a conflict under
  # the current (root + probe) assignment, excluding `skip_var` (the probe
  # assumption, which the checker asserts itself by negating the derived
  # clause). Returns proof ids, dependency-first, conflict clause last.
  -> conflict_chain(confl_ci, skip_var)
    stamp_list = []
    work = [confl_ci]
    wi = 0
    while wi < work.size
      arr = self.lits_of(work[wi])
      i = 0
      while i < arr.size
        v = arr[i].abs
        if v != skip_var && @seen[v] == 0 && @preason[v] >= 0
          @seen[v] = 1
          stamp_list.push(v)
          work.push(@preason[v])
        i += 1
      wi += 1
    # Order the cone reasons by the trail position of the variable each one
    # propagated (dependency order for the checker's replay). Insertion sort
    # on the variables directly: cones are small, and a packed sort key of
    # trail-position times clause-count can overflow the 48-bit boxed range.
    ord_v = []
    stamp_list.each -> (v)
      j = ord_v.size
      ord_v.push(v)
      while j > 0 && @tpos[ord_v[j - 1]] > @tpos[v]
        ord_v[j] = ord_v[j - 1]
        j -= 1
      ord_v[j] = v
    chain = []
    i = 0
    while i < ord_v.size
      chain.push(@fpgid[@preason[ord_v[i]]])
      i += 1
    chain.push(@fpgid[confl_ci])
    # clear marks
    stamp_list.each -> (v)
      @seen[v] = 0
    chain

  # The formula is refuted at the root: log the empty clause and stop.
  -> refute(confl_ci)
    self.plog_add(@next_gid, [], self.conflict_chain(confl_ci, 0))
    @next_gid += 1
    @status = -1
    0

  # ---- intake ---------------------------------------------------------------

  # Store every input clause, then fire the input units. Empty input clause
  # refutes immediately, citing itself.
  -> intake
    @fqhead = 0
    @input_clauses.each -> (c)
      z = self.store(c.dup)
    ci = 0
    while ci < @ncl && @status == 0
      arr = self.lits_of(ci)
      if arr.size == 0
        self.plog_add(@next_gid, [], [@fpgid[ci]])
        @next_gid += 1
        @status = -1
      elsif arr.size == 1 && @ftaut[ci] == 0
        lv = self.value(arr[0])
        if lv < 0
          confl = ci
          self.refute(confl)
        elsif lv == 0
          self.assign(arr[0], ci)
      ci += 1
    if @status == 0
      confl = self.propagate_root
      self.refute(confl) if confl >= 0
    0

  # ---- technique 1: failed-literal probing ----------------------------------

  # Probe candidate order: unassigned variables by descending occurrence
  # count (probing never removes a variable, so freezing is irrelevant).
  # Packed sort keys must stay under 2^46: the boxed integer fast path is
  # 48-bit signed, and a wrapped key decodes to a wild variable index.
  -> probe_candidates
    scored = []
    v = 1
    while v <= @nvars
      if @passign[v] == 0
        c = @ocount[2 * v] + @ocount[2 * v + 1]
        c = 4194302 if c > 4194302
        scored.push((4194303 - c) * 16777216 + v)
      v += 1
    scored = scored.sort
    out = []
    i = 0
    while i < scored.size && i < @probe_cap
      out.push(scored[i] % 16777216)
      i += 1
    out

  # Assume `lit`, propagate, undo. If a conflict arises, the negation is
  # implied unconditionally: log it, assert it at the root, and propagate.
  # Runs on the same trail past the root prefix -- probing never touches
  # saved solver state because there is no solver yet.
  -> probe(lit)
    mark = @ftsize
    qsave = @fqhead
    @probing = true
    self.assign(lit, 0 - 1)
    confl = self.propagate_root
    if confl >= 0
      chain = self.conflict_chain(confl, lit.abs)
      # undo the probe segment before touching root state
      self.undo_to(mark, qsave)
      @probing = false
      unit = [0 - lit]
      gid = @next_gid
      self.plog_add(gid, unit, chain)
      nci = self.store(unit)
      @probes_failed += 1
      rc = -1
      if self.value(unit[0]) < 0
        rc = nci                 # -lit already false at root: refuted
      else
        if self.value(unit[0]) == 0
          self.assign(unit[0], nci)
        rc = self.propagate_root
      self.refute(rc) if rc >= 0
      true
    else
      self.undo_to(mark, qsave)
      @probing = false
      false

  -> undo_to(mark, qsave)
    while @ftsize > mark
      @ftsize -= 1
      l = @ftrail[@ftsize]
      @passign[l.abs] = 0
      @preason[l.abs] = -1
    @fqhead = qsave
    0

  -> run_probing
    cands = self.probe_candidates
    start = @ticks
    i = 0
    while i < cands.size && @status == 0 && self.within_budget && @ticks - start < WASSAT_PRE_PROBE_TICKS
      v = cands[i]
      if @passign[v] == 0
        @probes_run += 1
        hit = self.probe(v)
        hit = self.probe(0 - v) if !hit && @status == 0 && @passign[v] == 0
      i += 1
    0

  -> within_budget
    @tick_budget == 0 || @ticks < @tick_budget

  # ---- technique 2: equivalent-literal substitution -------------------------

  # Binary implication graph over unassigned literals; edges carry the clause
  # index that justifies them. adj[lit_index] -> Array of [to_lit, ci].
  -> build_binary_graph
    adj = []
    i = 0
    while i < 2 * @nvars + 2
      adj.push([])
      i += 1
    ci = 0
    while ci < @ncl
      if @falive[ci] == 1 && @ftaut[ci] == 0 && @fcl[ci] == 2
        a = @fla[@fcs[ci]]
        b = @fla[@fcs[ci] + 1]
        # `a == b` is a duplicated-literal pseudo-binary; its hint replay
        # would classify as two unassigned occurrences, never a unit.
        if a != b && self.value(a) == 0 && self.value(b) == 0
          adj[self.lit_index(0 - a)].push([b, ci])
          adj[self.lit_index(0 - b)].push([a, ci])
      ci += 1
    adj

  # Iterative Tarjan over literal nodes. Returns comp[lit_index] labels.
  -> tarjan(adj)
    n = 2 * @nvars + 2
    index = i64[n]
    low = i64[n]
    oncur = i64[n]
    comp = i64[n]
    i = 0
    while i < n
      index[i] = -1
      comp[i] = -1
      i += 1
    counter = i64[2]             # [0] next index, [1] next component
    cur = []                     # Tarjan stack of lit nodes
    node = 2
    while node < 2 * @nvars + 2
      if index[node] < 0 && @passign[node / 2] == 0
        # explicit DFS: frames of [lit_node, child_cursor]
        frames = [[node, 0]]
        while !frames.empty?
          fr = frames[frames.size - 1]
          u = fr[0]
          if fr[1] == 0
            index[u] = counter[0]
            low[u] = counter[0]
            counter[0] = counter[0] + 1
            cur.push(u)
            oncur[u] = 1
          edges = adj[u]
          advanced = false
          k = fr[1]
          while k < edges.size && !advanced
            w = self.lit_index(edges[k][0])
            @ticks += 1
            if index[w] < 0
              fr[1] = k + 1
              frames.push([w, 0])
              advanced = true
            else
              low[u] = low[w] if oncur[w] == 1 && low[w] < low[u]
              k += 1
          unless advanced
            fr[1] = edges.size
            frames.pop
            unless frames.empty?
              parent = frames[frames.size - 1][0]
              low[parent] = low[u] if low[u] < low[parent]
            if low[u] == index[u]
              done = false
              while !done
                w = cur.pop
                oncur[w] = 0
                comp[w] = counter[1]
                done = true if w == u
              counter[1] = counter[1] + 1
      node += 1
    comp

  # BFS a path of implication edges from literal `a` to literal `b`,
  # restricted to nodes of one component. Returns the clause-index list of
  # the edges, or [] when a == b.
  -> implication_path(adj, comp, a, b)
    ai = self.lit_index(a)
    bi = self.lit_index(b)
    return [] if ai == bi
    n = 2 * @nvars + 2
    if @bfs_ready == 0
      @bfs_from = i64[n]
      @bfs_ci = i64[n]
      @bfs_mark = i64[n]
      @bfs_ready = 1
    @bfs_gen += 1
    gen = @bfs_gen
    queue = [ai]
    qi = 0
    found = false
    while qi < queue.size && !found
      u = queue[qi]
      qi += 1
      edges = adj[u]
      k = 0
      while k < edges.size
        w = self.lit_index(edges[k][0])
        @ticks += 1
        if comp[w] == comp[ai] && @bfs_mark[w] != gen && w != ai
          @bfs_mark[w] = gen
          @bfs_from[w] = u
          @bfs_ci[w] = edges[k][1]
          queue.push(w)
          found = true if w == bi
        k += 1
    path = []
    if found
      at = bi
      while at != ai
        path.push(@bfs_ci[at])
        at = @bfs_from[at]
      rev = []
      k = path.size - 1
      while k >= 0
        rev.push(path[k])
        k -= 1
      path = rev
    path

  -> run_substitution
    return 0 unless @status == 0 && self.within_budget
    adj = self.build_binary_graph
    comp = self.tarjan(adj)

    # group literals by component
    groups = {}
    node = 2
    while node < 2 * @nvars + 2
      if comp[node] >= 0
        key = comp[node]
        groups[key] = [] unless groups.has_key?(key)
        groups[key].push(node)
      node += 1

    groups.each -> (key, members)
      if @status == 0 && members.size > 1 && self.within_budget
        self.substitute_class(adj, comp, members)
    0

  # Substitute one nontrivial SCC. members are lit_indexes.
  -> substitute_class(adj, comp, members)
    # detect x and -x in one class: the formula is unsatisfiable
    stampv = {}
    contradiction_var = 0
    lits_of = []
    members.each -> (m)
      v = m / 2
      l = m % 2 == 0 ? v : 0 - v
      lits_of.push(l)
      if stampv.has_key?(v)
        contradiction_var = v
      else
        stampv[v] = true
    if contradiction_var > 0
      x = contradiction_var
      # derive [-x] via the path x => -x, then [x] via -x => x, then empty
      p1 = self.implication_path(adj, comp, x, 0 - x)
      g1 = @next_gid
      self.plog_add(g1, [0 - x], self.path_gids(p1))
      c1 = self.store([0 - x])
      p2 = self.implication_path(adj, comp, 0 - x, x)
      g2 = @next_gid
      self.plog_add(g2, [x], self.path_gids(p2))
      c2 = self.store([x])
      self.plog_add(@next_gid, [], [@fpgid[c1], @fpgid[c2]])
      @next_gid += 1
      @status = -1
      return 0

    # choose the representative: a frozen member if any, else smallest var,
    # and skip the class if its variables were already mapped through the
    # mirror class (each SCC pairs with the SCC of its negations).
    rep = 0
    lits_of.each -> (l)
      rep = l if rep == 0 && @frozen[l.abs] == 1
    if rep == 0
      best = 0
      lits_of.each -> (l)
        best = l if best == 0 || l.abs < best.abs
      rep = best
    already = false
    lits_of.each -> (l)
      already = true if @replit[l.abs] != 0
    return 0 if already

    # Derive both equivalence binaries per non-representative member. The
    # helpers are marked so occurrence rewriting skips them: rewriting a
    # helper maps it to a tautology and deletes it while later rewritten
    # clauses still cite its id — the certificate then fails both checkers.
    # They are deleted only after the whole class is rewritten.
    binid_fwd = {}               # var -> pgid of (-y | r')  [y => r']
    binid_back = {}              # var -> pgid of (y | -r')
    helpers = []
    lits_of.each -> (y)
      if y != rep && @status == 0
        yv = y.abs
        if @frozen[yv] == 1
          # frozen members keep their occurrences; note the equivalence only
          0
        else
          r_for_y = yv == y ? rep : 0 - rep    # rep literal seen from +yv
          # (-yv | r_for_y): path from +yv to r_for_y
          pf = self.implication_path(adj, comp, yv, r_for_y)
          gf = @next_gid
          self.plog_add(gf, [0 - yv, r_for_y], self.path_gids(pf))
          cf = self.store([0 - yv, r_for_y])
          binid_fwd[yv] = @fpgid[cf]
          # (yv | -r_for_y): path from -yv to -r_for_y, which holds because
          # r_for_y => yv around the cycle.
          pb = self.implication_path(adj, comp, 0 - yv, 0 - r_for_y)
          gb = @next_gid
          self.plog_add(gb, [yv, 0 - r_for_y], self.path_gids(pb))
          cb = self.store([yv, 0 - r_for_y])
          binid_back[yv] = @fpgid[cb]
          @helper_mark[cf] = true
          @helper_mark[cb] = true
          helpers.push(cf)
          helpers.push(cb)
          @replit[yv] = r_for_y
          @gone[yv] = 2
          @stack.push({ "kind": "subst", "var": yv, "rep": r_for_y })
          @vars_substituted += 1

    # rewrite every live clause containing a substituted variable of this class
    lits_of.each -> (y)
      yv = y.abs
      if @replit[yv] != 0 && @status == 0
        self.rewrite_occurrences(yv, binid_fwd[yv], binid_back[yv])

    # Every citation of the helpers has been emitted; retiring them now is a
    # pure deletion. Eager unit derivation has already re-pointed @preason
    # away from any helper that propagated during the rewrite cascades.
    self.delete_batch(helpers)
    @helper_mark = {}
    0

  -> path_gids(path)
    out = []
    path.each -> (ci)
      out.push(@fpgid[ci])
    out

  # Rewrite all live clauses mentioning yv through @replit[yv]. Hints per
  # rewritten clause: the equivalence binary used for each mapped literal,
  # then the original clause id. Helper binaries are skipped (their ids are
  # cited by these very steps), and so are clauses satisfied at the root —
  # they may be the recorded reason of a root literal, they are swept later
  # anyway, and replacing one would orphan its citation.
  -> rewrite_occurrences(yv, gid_fwd, gid_back)
    r = @replit[yv]
    two = [2 * yv, 2 * yv + 1]
    two.each -> (li)
      w = @oh[li]
      while w >= 0
        ci = @ov[w]
        eligible = @falive[ci] == 1 && !@helper_mark.has_key?(ci)
        if eligible
          sat_root = false
          si = 0
          while si < @fcl[ci]
            sat_root = true if self.value(@fla[@fcs[ci] + si]) > 0
            si += 1
          eligible = !sat_root
        if eligible
          arr = self.lits_of(ci)
          @ticks += arr.size
          mapped = []
          hints = []
          used_fwd = false
          used_back = false
          i = 0
          while i < arr.size
            l = arr[i]
            if l == yv
              mapped.push(r)
              # cite each equivalence binary once: a duplicated literal would
              # replay an already-satisfied hint and break the chain
              hints.push(gid_fwd) unless used_fwd
              used_fwd = true
            elsif l == 0 - yv
              mapped.push(0 - r)
              hints.push(gid_back) unless used_back
              used_back = true
            else
              mapped.push(l)
            i += 1
          # dedupe and tautology-check the mapped clause
          uniq = []
          t = false
          i = 0
          while i < mapped.size
            l = mapped[i]
            dup = false
            j = 0
            while j < uniq.size
              dup = true if uniq[j] == l
              t = true if uniq[j] == 0 - l
              j += 1
            uniq.push(l) unless dup
            i += 1
          if t
            self.delete_clause(ci)
          else
            hints.push(@fpgid[ci])
            gid = @next_gid
            self.plog_add(gid, uniq, hints)
            nci = self.store(uniq)
            self.delete_clause(ci)
            if uniq.size == 1 && @status == 0
              lv = self.value(uniq[0])
              if lv < 0
                self.refute(nci)
              elsif lv == 0
                self.assign(uniq[0], nci)
                confl = self.propagate_root
                self.refute(confl) if confl >= 0
        w = @on[w]
    0

  # ---- technique 3: subsumption + self-subsuming strengthening --------------

  # Forward pass over live clauses: C subsumes D (delete D) when C's literals
  # are a subset of D's; C strengthens D when the subset holds after flipping
  # exactly one literal (add D minus that literal, delete D). The native pass
  # walks whole chunks of the clause range -- stamping each subsumer, then
  # scanning its rarest bucket for subsumption and each literal's negation
  # bucket for strengthening -- and reports rare survivor triples
  # (subsumer, candidate, flip literal). The boxed side re-verifies each
  # survivor exactly and owns all proof emission. One pass per call; the
  # driver iterates while passes keep earning their keep.
  -> run_subsumption
    progress = false
    next_ci = 0
    while next_ci < @ncl && self.within_budget && @status == 0
      base = @lgen + 1
      snapshot = @ncl
      @subscan_pm[0] = base
      @subscan_pm[1] = next_ci
      @subscan_pm[2] = snapshot
      @subscan_pm[3] = WASSAT_PRE_BUCKET_CAP
      @subscan_pm[4] = 4000
      @subscan_pm[5] = 0
      @subscan_pm[6] = 0
      wassat_pre_subpass(@fla, @fcs, @fcl, @falive, @ftaut, @fsig, @oh, @on,
                         @ov, @ocount, @lstamp, @subscan_out, @subscan_pm)
      @ticks += @subscan_pm[5]
      @lgen = base + snapshot + 1
      hits = @subscan_out[0]
      k = 0
      while k < hits && @status == 0
        progress = true if self.commit_survivor(@subscan_out[3 * k + 1], @subscan_out[3 * k + 2], @subscan_out[3 * k + 3])
        k += 1
      next_ci = @subscan_pm[6]
    progress

  # Re-verify one native-scan survivor exactly and commit it: flip == 0 is a
  # subsumption (pure deletion), otherwise strengthen the candidate by
  # dropping the negated flip literal (add-then-delete, never in place).
  -> commit_survivor(sci, di, fl)
    return false unless @falive[sci] == 1 && @falive[di] == 1
    arr = self.lits_of(sci)
    if fl == 0
      if self.subset_of(arr, self.lits_of(di))
        self.delete_clause(di)
        @clauses_subsumed += 1
        true
      else
        false
    else
      # Strengthen to fixpoint against this subsumer: dropping one negated
      # literal often exposes the next (the within-subsumer cascade the
      # immediate-commit flow used to find via its later flip scans).
      any = false
      target = di
      more = true
      first_flip = fl
      while more && @status == 0
        flipped = 0
        if first_flip != 0 && self.subset_one_flip(arr, first_flip, self.lits_of(target))
          flipped = first_flip
        else
          fi = 0
          while fi < arr.size && flipped == 0
            cand = arr[fi]
            flipped = cand if self.subset_one_flip(arr, cand, self.lits_of(target))
            fi += 1
        first_flip = 0
        if flipped == 0
          more = false
        else
          l = flipped
          strengthened = []
          self.lits_of(target).each -> (dl)
            strengthened.push(dl) unless dl == 0 - l
          gid = @next_gid
          self.plog_add(gid, strengthened, [@fpgid[sci], @fpgid[target]])
          nci = self.store(strengthened)
          self.delete_clause(target)
          @clauses_strengthened += 1
          any = true
          if strengthened.size == 1 && @status == 0
            lv = self.value(strengthened[0])
            if lv < 0
              self.refute(nci)
            elsif lv == 0
              self.assign(strengthened[0], nci)
              confl = self.propagate_root
              self.refute(confl) if confl >= 0
          target = nci
          more = strengthened.size >= arr.size   # a further flip needs >= |C|
      any

  -> subset_of(small, big)
    ok = true
    i = 0
    while i < small.size && ok
      l = small[i]
      found = false
      j = 0
      while j < big.size && !found
        found = true if big[j] == l
        j += 1
      ok = found
      i += 1
    ok

  # small minus {flip} must be inside big, and -flip must be in big.
  -> subset_one_flip(small, flip, big)
    ok = true
    i = 0
    while i < small.size && ok
      l = small[i]
      want = l == flip ? 0 - l : l
      found = false
      j = 0
      while j < big.size && !found
        found = true if big[j] == want
        j += 1
      ok = found
      i += 1
    ok

  # ---- technique 4: bounded variable elimination ----------------------------

  # Eliminate v when the set of non-tautological resolvents is no larger
  # than the clauses it replaces, with bounds on literal volume and pairing
  # work. Atomic: either every resolvent is added and every original
  # deleted, or nothing happens.
  -> try_eliminate(v)
    return false if @frozen[v] == 1 || @passign[v] != 0 || @gone[v] != 0
    @bve_pm[0] = v
    @bve_pm[1] = @bve_margin
    @bve_pm[2] = WASSAT_PRE_OCC_PRODUCT_CAP
    @bve_pm[3] = 131072
    @bve_pm[4] = 0
    @bve_pm[5] = 0
    @bve_pm[6] = 0
    @bve_pm[7] = 0
    wassat_pre_bve_scan(@fla, @fcs, @fcl, @falive, @ftaut, @oh, @on, @ov,
                        @lstamp, @bve_hash, @bve_out, @bve_pm, @lgen)
    @lgen = @bve_pm[8]
    @ticks += @bve_pm[7]
    return false if @bve_pm[4] == 0

    # commit from the packed buffer: all resolvents added, all originals
    # deleted, or nothing — the atomicity contract is unchanged
    count = @bve_pm[5]
    pos = self.live_occ(2 * v)
    neg = self.live_occ(2 * v + 1)
    off = 0
    i = 0
    while i < count
      n = @bve_out[off]
      aci = @bve_out[off + 1]
      bci = @bve_out[off + 2]
      res = []
      j = 0
      while j < n
        res.push(@bve_out[off + 3 + j])
        j += 1
      gid = @next_gid
      self.plog_add(gid, res, [@fpgid[aci], @fpgid[bci]])
      nci = self.store(res)
      if res.size == 1 && @status == 0
        lv = self.value(res[0])
        if lv < 0
          self.refute(nci)
        elsif lv == 0
          self.assign(res[0], nci)
          confl = self.propagate_root
          self.refute(confl) if confl >= 0
      off += 3 + n
      i += 1
    @stack.push({ "kind": "bve_var", "pivot": v })
    pos.each -> (ci)
      @stack.push({ "kind": "bve", "pivot": v, "lits": self.lits_of(ci).dup })
    parents = []
    pos.each -> (ci)
      parents.push(ci)
    neg.each -> (ci)
      parents.push(ci)
    self.delete_batch(parents)
    @gone[v] = 1
    @vars_eliminated += 1
    true

  -> live_occ(li)
    out = []
    w = @oh[li]
    while w >= 0
      ci = @ov[w]
      out.push(ci) if @falive[ci] == 1 && @ftaut[ci] == 0
      w = @on[w]
    out

  # Resolvent of a (containing v) and b (containing -v); nil for tautologies.
  # Every occurrence of the pivot is removed from both sides; duplicates
  # collapse.
  -> resolve(a, b, v)
    out = []
    t = false
    i = 0
    while i < a.size
      l = a[i]
      unless l == v || l == 0 - v
        dup = false
        j = 0
        while j < out.size
          dup = true if out[j] == l
          t = true if out[j] == 0 - l
          j += 1
        out.push(l) unless dup
      i += 1
    i = 0
    while i < b.size
      l = b[i]
      unless l == v || l == 0 - v
        dup = false
        j = 0
        while j < out.size
          dup = true if out[j] == l
          t = true if out[j] == 0 - l
          j += 1
        out.push(l) unless dup
      i += 1
    t ? nil : out

  -> run_bve
    # cheapest first: ascending occurrence sum (packed key, see
    # probe_candidates on the 2^46 bound)
    scored = []
    v = 1
    while v <= @nvars
      if @passign[v] == 0 && @gone[v] == 0 && @frozen[v] == 0
        c = @ocount[2 * v] + @ocount[2 * v + 1]
        c = 4194302 if c > 4194302
        scored.push(c * 16777216 + v)
      v += 1
    scored = scored.sort
    progress = false
    i = 0
    while i < scored.size && @status == 0 && self.within_budget
      progress = true if self.try_eliminate(scored[i] % 16777216)
      i += 1
    progress

  # ---- driver ---------------------------------------------------------------

  # Two-stage entry for the trusted (--fast) path: run_light does the cheap
  # phases (intake, probing, substitution — ~150ms even on 100k-clause
  # inputs) and snapshots an artifact; if the caller's SLS burst misses,
  # run_heavy continues with the subsumption/BVE rounds on the same state.
  # The certificate path keeps using run() unchanged.
  -> run_light
    self.init_budget
    self.intake
    self.run_probing if @status == 0
    self.run_substitution if @status == 0
    self.sweep_satisfied if @status == 0
    self.artifact

  -> run_heavy
    tp = wassat_prof_clock
    self.heavy_rounds
    tp = wassat_prof("pre.heavy_rounds", tp)
    self.sweep_satisfied if @status == 0
    tp = wassat_prof("pre.heavy_sweep", tp)
    art = self.artifact
    tp = wassat_prof("pre.heavy_artifact", tp)
    art

  -> init_budget
    # Probing gets a fixed slice; encoding-scale instances get a deeper
    # budget for the margin rounds (see run).
    if @tick_budget == 0
      if @input_clauses.size <= 20000
        @tick_budget = 400 * self.total_literals + 40000000
      else
        @tick_budget = 200 * self.total_literals + 10000000
    0

  -> heavy_rounds
    passes = 0
    progress = true
    while progress && @status == 0 && self.within_budget && passes < WASSAT_PRE_MAX_PASSES
      before = @clauses_subsumed + @clauses_strengthened + @vars_eliminated
      tp = wassat_prof_clock
      z = self.run_subsumption
      tp = wassat_prof("pre.subsume.p[passes]", tp)
      z = self.run_bve if @status == 0 && self.within_budget
      tp = wassat_prof("pre.bve.p[passes]", tp)
      gained = @clauses_subsumed + @clauses_strengthened + @vars_eliminated - before
      threshold = 1 + @ncl / 512
      progress = gained >= threshold
      @bve_margin = @bve_margin + 4 if @bve_margin < 16 && @ncl <= 20000
      # The first margin steps must run even when the zero-margin pass
      # found little — that is exactly the case they exist for. Forced
      # only on encoding-scale instances; big inputs also cap at two
      # rounds (the pass-2 rescan cost ~270ms on bmc to find crumbs).
      progress = true if passes < 4 && @ncl <= 20000
      progress = false if passes >= 1 && @input_clauses.size > 20000
      passes += 1
    0

  -> run
    self.init_budget
    self.intake
    self.run_probing if @status == 0
    self.run_substitution if @status == 0
    self.heavy_rounds
    self.sweep_satisfied if @status == 0
    self.artifact

  -> total_literals
    n = 0
    @input_clauses.each -> (c)
      n += c.size
    n

  # Delete clauses satisfied at the root, keeping (or deriving) one unit
  # clause per root-assigned variable so the reduced formula still asserts
  # it. Tautologies go too. All pure deletions plus at most one RUP unit per
  # variable.
  -> sweep_satisfied
    keep_unit = i64[@ncl + @ftsize + 2]
    ti = 0
    while ti < @ftsize
      l = @ftrail[ti]
      rci = @preason[l.abs]
      # Eager derivation guarantees every root literal is backed by a live
      # unit clause by now (input unit, probe unit, or derived unit); a
      # violation means some technique deleted a cited clause and the
      # certificate is already unsound — stop loudly, never paper over it.
      unless rci >= 0 && @falive[rci] == 1 && @fcl[rci] == 1
        raise "internal error: root literal [l] lost its unit clause"
      keep_unit[rci] = 1
      ti += 1
    doomed = []
    ci = 0
    while ci < @ncl
      if @falive[ci] == 1 && keep_unit[ci] == 0
        if @ftaut[ci] == 1
          doomed.push(ci)
        else
          arr = self.lits_of(ci)
          sat = false
          i = 0
          while i < arr.size
            sat = true if self.value(arr[i]) > 0
            i += 1
          doomed.push(ci) if sat
      ci += 1
    self.delete_batch(doomed)
    0

  # ---- artifact -------------------------------------------------------------

  -> artifact
    # A substituted variable that ended up root-assigned during the rewrite
    # cascades is pinned by a live unit clause, so it is not "gone" in the
    # assumption/consistency sense (reconstruction still overwrites it with
    # the representative's value, which the equivalence makes identical).
    v = 1
    while v <= @nvars
      @gone[v] = 0 if @gone[v] == 2 && @passign[v] != 0
      v += 1
    # Boxed clauses are consumed only by the small-kernel SLS burst and
    # the portfolio artifact writer; on big trusted-path formulas every
    # downstream consumer reads the flat mirrors, and materializing 300k
    # lazy clauses here would undo the lazy-truth win — twice per run.
    want_boxed = !@lazy_lits || @ncl <= 50000
    clauses = []
    gids = []
    ci = 0
    while ci < @ncl
      if @falive[ci] == 1
        clauses.push(self.lits_of(ci)) if want_boxed
        gids.push(@fpgid[ci])
      ci += 1
    { "nvars": @nvars, "clauses": clauses, "gids": gids,
      "raw": @raw_kernel,
      "next_gid": @next_gid, "status": @status,
      "stack": @stack, "gone": @gone,
      "fla": @fla, "fcs": @fcs, "fcl": @fcl, "falive": @falive,
      "ftaut": @ftaut, "fpgid": @fpgid, "fncl": @ncl,
      "wrat": @wrat_lines, "drat": @drat_lines,
      "stats": { "probes": @probes_run, "probes_failed": @probes_failed,
                 "vars_substituted": @vars_substituted,
                 "clauses_subsumed": @clauses_subsumed,
                 "clauses_strengthened": @clauses_strengthened,
                 "vars_eliminated": @vars_eliminated,
                 "ticks": @ticks } }

# Native root-level unit propagation over the flat clause arena and the
# intrusive occurrence lists. Same reasoning as the solver's native helpers:
# typed array parameters keep literal reads raw machine integers.
#
#   st[0] = qhead   st[1] = trail size   st[2] = conflict ci or -1
#   st[3] = accumulated ticks
-> wassat_pre_prop(fla, fcs, fcl, falive, ftaut, och, ocn, ocv, asg, rsn, tps, tr, st) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[])
  qhead = st[0]
  tsize = st[1]
  conflict = -1
  ticks = 0
  while qhead < tsize && conflict < 0
    p = tr[qhead]
    qhead += 1
    neg = 0 - p
    li = 0
    if neg > 0
      li = neg << 1
    else
      li = ((0 - neg) << 1) + 1
    w = och[li]
    while w >= 0 && conflict < 0
      ci = ocv[w]
      if falive[ci] == 1 && ftaut[ci] == 0
        stx = fcs[ci]
        n = fcl[ci]
        ticks = ticks + n
        sat = 0
        unassigned = 0
        unit = 0
        j = 0
        while j < n
          l = fla[stx + j]
          vv = 0
          if l > 0
            vv = asg[l]
          else
            vv = 0 - asg[0 - l]
          if vv > 0
            sat = 1
            j = n
          else
            if vv == 0
              unassigned = unassigned + 1
              unit = l
            j = j + 1
        if sat == 0
          if unassigned == 0
            conflict = ci
          else
            if unassigned == 1
              uv = unit
              pol = 1
              if uv < 0
                uv = 0 - uv
                pol = -1
              asg[uv] = pol
              rsn[uv] = ci
              tps[uv] = tsize
              tr[tsize] = unit
              tsize = tsize + 1
      w = ocn[w]
  st[0] = qhead
  st[1] = tsize
  st[2] = conflict
  st[3] = st[3] + ticks
  0

# Native subsumption pass over a chunk of the clause range. For each live
# non-tautological subsumer clause: stamp its literals with a per-clause
# generation, scan the rarest literal's occurrence bucket for subsumption
# candidates (signature-filtered) and each literal's negation bucket for
# one-flip strengthening candidates, and record survivor triples
# (subsumer, candidate, flip literal or 0) in `out`. Stops when the range or
# the output budget is exhausted; pm[6] reports where to resume. Dropped
# survivors only forgo a reduction, never soundness.
#
#   pm[0] generation base  pm[1] start ci  pm[2] end ci (exclusive)
#   pm[3] bucket scan cap  pm[4] out triple budget  pm[5] ticks out
#   pm[6] next ci out
-> wassat_pre_subpass(fla, fcs, fcl, falive, ftaut, fsig, och, ocn, ocv, ocount, lstamp, out, pm) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[])
  base = pm[0]
  sci = pm[1]
  endci = pm[2]
  cap = pm[3]
  budget = pm[4]
  ticks = 0
  count = 0
  while sci < endci && count < budget
    keep = 1
    if falive[sci] != 1
      keep = 0
    if keep == 1 && ftaut[sci] == 1
      keep = 0
    slen = 0
    if keep == 1
      slen = fcl[sci]
      if slen < 1
        keep = 0
    if keep == 1
      gen = base + sci
      stx = fcs[sci]
      csig = fsig[sci]
      # duplicated-literal subsumers cannot anchor strengthening chains
      has_dup = 0
      a = 0
      while a < slen
        b = a + 1
        while b < slen
          if fla[stx + a] == fla[stx + b]
            has_dup = 1
          b += 1
        a += 1
      # stamp literals, find rarest bucket
      best_li = -1
      best_cnt = 0
      j = 0
      while j < slen
        l = fla[stx + j]
        li = 0
        if l > 0
          li = l << 1
        else
          li = ((0 - l) << 1) + 1
        lstamp[li] = gen
        c = ocount[li]
        if best_li < 0 || c < best_cnt
          best_li = li
          best_cnt = c
        j += 1
      pass_i = 0
      while pass_i <= slen
        mode = 0
        li = best_li
        flip = 0
        run = 1
        if pass_i > 0
          if has_dup == 1
            run = 0
          else
            mode = 1
            l = fla[stx + (pass_i - 1)]
            flip = 0 - l
            if flip > 0
              li = flip << 1
            else
              li = ((0 - flip) << 1) + 1
        if run == 1
          scanned = 0
          w = och[li]
          while w >= 0 && scanned < cap
            ci = ocv[w]
            scanned = scanned + 1
            ok = 1
            if ci == sci
              ok = 0
            if ok == 1 && falive[ci] != 1
              ok = 0
            if ok == 1 && mode == 1 && ftaut[ci] == 1
              ok = 0
            n = 0
            if ok == 1
              n = fcl[ci]
              if n < slen
                ok = 0
              # never delete or strengthen a unit clause: root literals'
              # units are load-bearing citations for the whole certificate
              if n < 2
                ok = 0
            if ok == 1 && mode == 0
              if (csig & fsig[ci]) != csig
                ok = 0
            if ok == 1
              dstx = fcs[ci]
              ticks = ticks + n
              matched = 0
              flip_seen = 0
              j = 0
              while j < n
                l2 = fla[dstx + j]
                lidx = 0
                if l2 > 0
                  lidx = l2 << 1
                else
                  lidx = ((0 - l2) << 1) + 1
                if lstamp[lidx] == gen
                  matched = matched + 1
                if mode == 1 && l2 == flip
                  flip_seen = 1
                j = j + 1
              hit = 0
              if mode == 0
                if matched >= slen
                  hit = 1
              else
                if flip_seen == 1 && matched >= slen - 1
                  hit = 1
              if hit == 1 && count < 5400
                out[3 * count + 1] = sci
                out[3 * count + 2] = ci
                if mode == 0
                  out[3 * count + 3] = 0
                else
                  out[3 * count + 3] = 0 - flip
                count = count + 1
            w = ocn[w]
        pass_i += 1
    sci += 1
  out[0] = count
  pm[5] = pm[5] + ticks
  pm[6] = sci
  0

# Native BVE feasibility scan for one pivot: walks both occurrence lists,
# forms every resolvent over the flat literal arena (tautologies skipped via
# generation stamps, duplicates collapsed by an order-independent 64-bit
# hash — a collision only under-counts growth, which is a size POLICY, never
# soundness), applies the growth bounds, and on success leaves the packed
# resolvents [len, aci, bci, lits...]* in `out` for the boxed commit. The
# boxed path used to build every rejected candidate's resolvents as Arrays
# with sort.join dedup keys — the dominant cost of the heavy round.
#
#   pm[0] pivot  pm[1] margin  pm[2] occ-product cap  pm[3] out capacity
#   pm[4] feasible(out)  pm[5] resolvent count(out)  pm[6] unused
#   pm[7] ticks(out)  pm[8] next lgen(out)
-> wassat_pre_bve_scan(fla, fcs, fcl, falive, ftaut, och, ocn, ocv, lstamp, hbuf, out, pm, lgen0) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64)
  v = pm[0]
  margin = pm[1]
  prodcap = pm[2]
  outcap = pm[3]
  gen = lgen0
  ticks = 0
  pm[4] = 0
  pm[5] = 0

  # count live occurrences, old totals, and reject duplicated pivots
  npos = 0
  nneg = 0
  old_lits = 0
  dup = 0
  side = 0
  while side < 2
    w = och[2 * v + side]
    while w >= 0
      ci = ocv[w]
      if falive[ci] == 1 && ftaut[ci] == 0
        if side == 0
          npos = npos + 1
        else
          nneg = nneg + 1
        stx = fcs[ci]
        n = fcl[ci]
        old_lits = old_lits + n
        pc = 0
        j = 0
        while j < n
          l = fla[stx + j]
          av = l
          if l < 0
            av = 0 - l
          if av == v
            pc = pc + 1
          j = j + 1
        if pc > 1
          dup = 1
      w = ocn[w]
    side = side + 1
  if dup == 1
    pm[8] = gen
    pm[7] = ticks
    0
  else
    if npos + nneg == 0 || npos * nneg > prodcap
      pm[8] = gen
      pm[7] = ticks
      0
    else
      old_count = npos + nneg
      count = 0
      new_lits = 0
      off = 0
      feasible = 1
      wa = och[2 * v]
      while wa >= 0 && feasible == 1
        aci = ocv[wa]
        if falive[aci] == 1 && ftaut[aci] == 0
          astx = fcs[aci]
          an = fcl[aci]
          wb = och[2 * v + 1]
          while wb >= 0 && feasible == 1
            bci = ocv[wb]
            if falive[bci] == 1 && ftaut[bci] == 0
              bstx = fcs[bci]
              bn = fcl[bci]
              ticks = ticks + an + bn
              # stamp a-side literals (minus pivot), then merge b-side
              gen = gen + 1
              taut = 0
              rl = 0
              hdr = off
              base = off + 3
              j = 0
              while j < an
                l = fla[astx + j]
                av = l
                if l < 0
                  av = 0 - l
                if av != v
                  li = av + av
                  if l < 0
                    li = li + 1
                  if lstamp[li] != gen
                    lstamp[li] = gen
                    if base + rl < outcap
                      out[base + rl] = l
                    rl = rl + 1
                j = j + 1
              j = 0
              while j < bn && taut == 0
                l = fla[bstx + j]
                av = l
                if l < 0
                  av = 0 - l
                if av != v
                  li = av + av
                  oi = li + 1
                  if l < 0
                    li = li + 1
                    oi = li - 1
                  if lstamp[oi] == gen
                    taut = 1
                  else
                    if lstamp[li] != gen
                      lstamp[li] = gen
                      if base + rl < outcap
                        out[base + rl] = l
                      rl = rl + 1
                j = j + 1
              if taut == 0
                if base + rl >= outcap
                  feasible = 0
                else
                  # order-independent hash for cross-pair dedup
                  h = 0
                  j = 0
                  while j < rl
                    x = out[base + j] * 2654435761
                    x = x ^ (x >> 13)
                    h = h ^ (x * 40503)
                    j = j + 1
                  h = h ^ rl
                  isdup = 0
                  j = 0
                  while j < count
                    if hbuf[j] == h
                      isdup = 1
                      j = count
                    j = j + 1
                  if isdup == 0
                    hbuf[count] = h
                    out[hdr] = rl
                    out[hdr + 1] = aci
                    out[hdr + 2] = bci
                    count = count + 1
                    new_lits = new_lits + rl
                    off = base + rl
                    if count > old_count + margin
                      feasible = 0
                    if new_lits > old_lits + 16 * margin
                      feasible = 0
            wb = ocn[wb]
        wa = ocn[wa]
      pm[4] = feasible
      pm[5] = count
      pm[7] = ticks
      pm[8] = gen
      0

# Native mirror intake from the parser's flat arrays: copy the literal
# arena, compute per-clause tautology marks and 64-bit signatures, build
# the intrusive occurrence lists, and assign sequential proof ids —
# everything store() did per boxed literal, in one pass.
#   pm[0] in: clause count   pm[1] out: arena size   pm[2] out: occ nodes
-> wassat_pre_intake(slits, soffs, slens, fla, fcs, fcl, falive, ftaut, fsig, fpgid, och, ocn, ocv, ocount, pm) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[])
  ncl = pm[0]
  asize = 0
  osize = 0
  k = 0
  while k < ncl
    o = soffs[k]
    n = slens[k]
    fcs[k] = asize
    fcl[k] = n
    falive[k] = 1
    fpgid[k] = k + 1
    sig = 0
    t = 0
    j = 0
    while j < n
      l = slits[o + j]
      fla[asize + j] = l
      av = l
      if l < 0
        av = 0 - l
      sig = sig | (1 << (av & 63))
      m = 0
      while m < j
        if fla[asize + m] == 0 - l
          t = 1
        m = m + 1
      li = av + av
      if l < 0
        li = li + 1
      ocn[osize] = och[li]
      ocv[osize] = k
      och[li] = osize
      ocount[li] = ocount[li] + 1
      osize = osize + 1
      j = j + 1
    ftaut[k] = t
    fsig[k] = sig
    asize = asize + n
    k = k + 1
  pm[1] = asize
  pm[2] = osize
  0

# Array concatenation helper: `+` on arrays is not defined in Tungsten.
-> wassat_concat_arrays(a, b)
  out = []
  a.each -> (x)
    out.push(x)
  b.each -> (x)
    out.push(x)
  out

# The preprocessing half of the stats contract line.
-> wassat_pre_stats_text(stats, pre_ms)
  "probes=[stats["probes"]] probes_failed=[stats["probes_failed"]] vars_substituted=[stats["vars_substituted"]] clauses_subsumed=[stats["clauses_subsumed"]] clauses_strengthened=[stats["clauses_strengthened"]] vars_eliminated=[stats["vars_eliminated"]] preprocess_ms=[pre_ms]"

# Preprocess CNF text and return the artifact.
-> wassat_preprocess(cnf_text, proof_mode)
  f = wassat_parse_cnf(cnf_text)
  pre = WassatPreprocess.new(f["nvars"], f["clauses"], proof_mode)
  pre.run

# End-to-end library entry: preprocess, solve the reduced formula, and
# return a result whose model is reconstructed for the ORIGINAL formula and
# whose proof arrays carry prefix + search certificate. The artifact rides
# along under "pre".
-> wassat_solve_preprocessed(cnf_text, proof_mode, lookahead, max_conflicts)
  f = wassat_parse_cnf(cnf_text)
  pre = WassatPreprocess.new(f["nvars"], f["clauses"], proof_mode)
  art = pre.run
  if art["status"] == -1
    { "sat": false, "unsat": true, "complete": true, "status": -1,
      "model": [], "proof": art["wrat"].dup, "drat": art["drat"].dup,
      "proof_mode": proof_mode, "conflicts": 0, "decisions": 0,
      "restarts": 0, "reduces": 0, "pre": art }
  else
    s = Wassat.new(f["nvars"], art["clauses"], proof_mode, lookahead)
    s.seed_proof_ids(art["gids"], art["next_gid"])
    r = s.solve_budget(max_conflicts)
    if r["status"] == 1
      r["model"] = wassat_reconstruct_model(art["stack"], r["model"], f["nvars"])
      # The library path carries the same output-integrity guard as the CLI:
      # a reconstructed model that fails the ORIGINAL formula is a hard
      # error, never a returned result.
      unless wassat_model_satisfies?(f, r["model"])
        raise "internal error: reconstructed model does not satisfy the original formula"
    if r["status"] == -1
      r["proof"] = wassat_concat_arrays(art["wrat"], r["proof"])
      r["drat"] = wassat_concat_arrays(art["drat"], r["drat"])
    r["pre"] = art
    r

# E4 contract: assumptions may only name variables that survived
# preprocessing. Anything eliminated or substituted must have been declared
# with freeze(var) BEFORE preprocessing ran; discovering it here is a hard
# error, never a silent wrong answer.
-> wassat_check_assumptions(art, assumptions)
  gone = art["gone"]
  assumptions.each -> (a)
    v = a.abs
    unless gone[v] == 0
      kind = gone[v] == 1 ? "eliminated" : "substituted"
      raise "assumption names [kind] variable [v]; freeze it before preprocessing"
  0

# Reconstruct a model of the ORIGINAL formula from a model of the reduced
# one. `model` is the solver's canonical array (index v-1 holds +-v); the
# stack is walked backwards, with every BVE pivot first defaulted to false
# so the flip rule starts from the pushed side's negation.
-> wassat_reconstruct_model(stack, model, nvars)
  sign = i64[nvars + 1]
  i = 0
  while i < model.size
    l = model[i]
    sign[l.abs] = l > 0 ? 1 : -1
    i += 1
  # default every eliminated pivot against its pushed polarity
  si = 0
  while si < stack.size
    e = stack[si]
    if e["kind"] == "bve_var"
      p = e["pivot"]
      sign[p.abs] = p > 0 ? -1 : 1
    si += 1
  # reverse walk: later transformations undone first
  si = stack.size - 1
  while si >= 0
    e = stack[si]
    if e["kind"] == "bve"
      arr = e["lits"]
      sat = false
      i = 0
      while i < arr.size
        l = arr[i]
        sat = true if (l > 0 ? sign[l.abs] : 0 - sign[l.abs]) > 0
        i += 1
      unless sat
        p = e["pivot"]
        sign[p.abs] = p > 0 ? 1 : -1
    elsif e["kind"] == "subst"
      r = e["rep"]
      rv = r > 0 ? sign[r.abs] : 0 - sign[r.abs]
      sign[e["var"]] = rv
    si -= 1
  out = []
  v = 1
  while v <= nvars
    out.push(sign[v] >= 0 ? v : 0 - v)
    v += 1
  out

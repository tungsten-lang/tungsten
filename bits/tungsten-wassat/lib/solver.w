# Wassat -- a CDCL SAT solver that can show its work.
#
# The search is conflict-driven clause learning: two-watched-literal
# propagation, first-UIP conflict analysis, non-chronological backjumping,
# activity-based branching with phase saving, and scheduled restarts.
#
# DATA LAYOUT
#
# Everything hot lives in flat `i64[]` arrays rather than boxed collections.
# Clauses are stored consecutively in one arena with per-clause offsets, so
# propagation walks machine integers and allocates nothing.  Literals are
# indexed by `lit_index`: variable v maps to 2v (positive) and 2v+1
# (negative), which makes the watch lists plain integer-keyed tables.
#
# Watch lists are per-literal contiguous blocks in one packed i64 pool
# (entry = clause index << 32 | blocker literal): appends relocate a full
# block to the pool top with doubling, and pool exhaustion triggers a
# counting repack from the clause DB — never an allocation, so worker
# threads stay allocation-free.
#
# PROOFS
#
# Proof logging is opt-in. Raw DRAT records each learned RUP clause directly.
# Hinted WRAT/LRAT derives each learned clause's antecedent chain DIRECTLY
# from the conflict's resolution cone while the trail is intact (reasons in
# trail order, conflict clause last) — replay-free, so hinted emission costs
# the resolution footprint instead of a whole-database propagation per
# clause. Occurrence-driven replay survives only for the rare steps with no
# analysis behind them (the terminal empty clause, assumption blocking
# clauses).

UNASSIGNED = 0

# Minimum conflicts between restarts. See the restart block in `solve_loop`.
WASSAT_MIN_RESTART_INTERVAL = 16384
WASSAT_PROOF_NONE = 0
WASSAT_PROOF_WRAT = 1
WASSAT_PROOF_DRAT = 2

+ Wassat
  -> new(@nvars, @input_clauses, @proof_mode, @lookahead)
    nv = @nvars
    @assign = i8[nv + 1]         # 0 unassigned, 1 true, -1 false — one BYTE
                                 # per var: the propagation loop's random
                                 # reads then live in L1 (i64 was 8x bigger)
    # VMTF decision queue (focused mode): doubly-linked list over vars,
    # analyzed vars move to the front, decisions walk from the cached
    # search position toward the tail. Stable mode keeps the EVSIDS heap —
    # the kissat split: VMTF chases the conflict frontier, the heap
    # remembers long-run importance.
    @vq_next = i64[nv + 2]
    @vq_prev = i64[nv + 2]
    @vq_stamp = i64[nv + 2]
    @vq_state = i64[4]           # head / tail / stamp counter / search pos
    # VMTF measured: bmc-scale raw kernels 4.6x fewer conflicts (ibm-10
    # 5.9k -> 1.3k); random 3-SAT regresses ~25% — so the queue drives
    # focused mode only on raw kernels, EVSIDS everywhere else.
    @use_vmtf = false
    v = 1
    while v <= nv
      @vq_prev[v] = v - 1
      @vq_next[v] = v + 1
      @vq_stamp[v] = nv - v + 1
      v += 1
    if nv >= 1
      @vq_next[nv] = 0
      @vq_state[0] = 1
      @vq_state[1] = nv
      @vq_state[2] = nv + 1
      @vq_state[3] = 1
    @level = i64[nv + 1]
    @reason = i64[nv + 1]        # clause index, or -1 for a decision
    @seen = i64[nv + 1]
    @phase = i64[nv + 1]         # saved polarity: 1 or -1
    @activity = i64[nv + 1]      # scaled integer VSIDS score
    @heap = i64[nv + 1]          # max-heap of branching variables
    @heappos = i64[nv + 1]       # variable -> heap slot, -1 when absent
    @hstate = i64[2]              # heap size / EVSIDS increment
    @rassign = i64[nv + 1]       # isolated scratch assignment for proof replay
    @pstate = i64[8]             # qhead / tsize / conflict / bail / props
    @astate = i64[6]             # scalars across the native analyze call
    @lbuf = i64[nv + 3]          # learned clause, reused every conflict
    @obuf = i64[nv + 3]          # watch-ordered copy of the learned clause
    @mbuf = i64[nv + 3]          # minimisation scratch
    @mstk = i64[nv + 3]          # recursive-minimisation DFS stack
    @mclr = i64[nv + 3]          # marks to clear after minimisation
    @lbd_seen = i64[nv + 2]      # scratch for literal-block-distance
    @lbd_stamp = 0
    @trail = i64[nv + 2]
    @trail_lim = i64[nv + 2]
    v = 0
    while v <= nv
      @assign[v] = 0
      @level[v] = 0
      @reason[v] = -1
      @seen[v] = 0
      @phase[v] = -1
      @activity[v] = 0
      @heappos[v] = -1
      v += 1

    # The heap starts with every declared variable, matching the historical
    # one-shot solver's treatment of the DIMACS variable count. Variables
    # disappear lazily when selected or encountered assigned at the root,
    # then backjumping restores any variable that was popped.
    @hstate[0] = nv
    @hstate[1] = 32
    v = 1
    while v <= nv
      @heap[v - 1] = v
      @heappos[v] = v - 1
      v += 1

    @tsize = 0
    @qhead = 0
    @dlevel = 0
    @conflicts = 0
    @decisions_made = 0
    @proof = []
    @drat = []
    @refuted = false
    @ok = true
    @terminal_status = 0

    # Incremental queries: assumptions are DECISIONS, not clauses — every
    # learned clause therefore remains implied by the formula alone, and the
    # proof stream never contains an assumption-dependent step. On failure
    # the negated core is logged as an ordinary RUP addition (the blocking
    # clause); deriving the empty clause under assumption units would NOT
    # refute the original CNF. @formula_unsat marks the one verdict no later
    # query can undo.
    @assump = []
    @nassump = 0
    @failed_core = []
    @formula_unsat = false

    # Global proof-id counter. Without preprocessing every stored clause gets
    # id `ci + 1` exactly as before; once a preprocessed artifact supplies
    # non-contiguous ids, hints must translate through @gid rather than assume
    # a constant offset from the clause index.
    @next_gid = 1

    # Streaming proof sinks. nil means the in-memory arrays (library mode);
    # a path streams proof lines to disk in bounded chunks so certificate
    # memory stays flat no matter how long the refutation runs.
    @wrat_sink = nil
    @drat_sink = nil
    @dual_drat = false           # WRAT mode also emits plain DRAT lines
    @wrat_pend = []
    @drat_pend = []
    @pend_bytes = 0
    @wrat_header_done = false

    # Search-schedule state belongs to the solver, not to one budget slice.
    # Keeping it here makes `solve_budget` continuation observationally the
    # same search as one uninterrupted solve (apart from where control returns
    # to the caller).
    @restart_count = 0
    @since_restart = 0
    # Glucose-style exponential moving averages (fixed-point << 16). The
    # fast/slow LBD ratio decides WHETHER learning has stalled; the trail
    # EMA blocks restarts while the search is unusually deep (plausibly
    # closing on a model). This replaces the old 64/512-entry windows AND
    # the 16,384-conflict floor: frequent restarts only pay off alongside
    # phase saving + rephasing, which now exist — measured on the k=5
    # Lonely Runner class, the rare-restart policy was >40x behind CaDiCaL
    # while raw propagation speed was fine.
    @ema_fast = 0                # LBD, alpha = 1/32
    @ema_slow = 0                # LBD, alpha = 1/16384
    @ema_trail = 0               # trail depth, alpha = 1/4096
    @lbd_gcount = 0              # restart warmup gate + stats
    @reductions = 0

    # Stable/focused alternation (CaDiCaL): FOCUSED mode restarts eagerly
    # (floor 64) and drives refutations; STABLE mode restarts rarely
    # (floor 16384) under best phases and protects satisfiable instances
    # from restart churn — the EMA policy alone re-created the old 4x
    # regression on satisfiable BMC. Intervals grow geometrically; stable
    # gets 3x the focused budget.
    # focused-first measured better on BOTH uuf250 (95k vs 160k conflicts
    # stable-first) and ibm-12 (14.8k vs 18.9k)
    @mode_stable = false
    @mode_len = 3000
    @mode_at = 3000

    # Rephasing (CaDiCaL-style): remember the deepest assignment seen in
    # this epoch, and periodically cycle the saved phases through
    # best / inverted / best / original / best / random. Restarting into a
    # remembered good basin is what makes frequent restarts cheap.
    @bphase = i64[nv + 1]        # phases at the deepest trail so far
    v = 0
    while v <= nv
      @bphase[v] = -1
      v += 1
    @best_tsize = 0
    @rephase_at = 4000
    @rephase_idx = 0
    @rephases = 0
    @rephase_rng = 88172645463325252

    # Clause-DB reduction is driven by the LIVE learned-clause count, not
    # by accepted restarts — coupling it to restarts left multi-minute
    # searches dragging an ever-larger database.
    @nlearned = 0
    @vivified = 0
    @last_reduce_at = 0
    # Random-3-SAT-scale formulas want a TIGHT reduction cadence (small DB
    # = fast propagation; uuf250: 95k conflicts tight vs 128k relaxed);
    # structured instances want it RELAXED (retained clauses collapse the
    # search; ibm-12: 5.1k conflicts relaxed vs 14.8k tight, and each
    # avoided reduce also skips a 200k-clause watch rebuild).
    if @input_clauses.size < 20000
      @reduce_limit = 2000
      @reduce_step = 300
    else
      @reduce_limit = 4000
      @reduce_step = 1000

    # Threaded-portfolio state (--fast). @stop_cell is a shared i64[] the
    # winner raises; the solve loop polls it at conflict boundaries —
    # cooperative cancellation, because Thread.kill is deferred
    # pthread_cancel and cannot stop an allocation-free loop. @ring is the
    # clause-sharing seqlock ring. @fixed_caps freezes the arena and clause
    # tables (worker threads must not allocate); on exhaustion the arm
    # compacts via reduce_db, then retires loudly.
    @stop_cell = nil
    @ring = nil
    @ring_cap = 0
    @ring_maxlen = 0
    @ring_stride = 0
    @arm_id = 0
    @read_ticket = 0
    @fixed_caps = false
    @retired = false
    @import_pending = 0
    @share_exports = 0
    @share_imports = 0
    @share_dropped = 0
    @rhist = i64[64]             # reduce_db scratch (worker threads: no alloc)

    # Replay occurrence lists (hinted mode only): intrusive per-literal
    # lists over the LOGICAL clause database, so hint replay propagates
    # queue-driven over the clauses that can actually fire instead of
    # re-scanning the whole database to a fixpoint per learned clause.
    # @rtrail tracks touched replay variables for touched-only resets.
    rtotal = 0
    @input_clauses.each -> (c)
      rtotal += c.size
    if @proof_mode == WASSAT_PROOF_WRAT
      @rocc_head = i64[2 * nv + 4]
      i = 0
      while i < 2 * nv + 4
        @rocc_head[i] = -1
        i += 1
      @rocc_cap = 2 * rtotal + 4096
      @rocc_next = i64[@rocc_cap]
      @rocc_ci = i64[@rocc_cap]
    else
      @rocc_head = i64[1]
      @rocc_cap = 1
      @rocc_next = i64[1]
      @rocc_ci = i64[1]
    @rocc_size = 0
    @rtrail = i64[nv + 2]
    @rst = i64[4]
    @rout = i64[nv + 8]
    @runits = []                 # indices of stored unit clauses (hinted mode)
    @rempties = []               # indices of stored empty clauses (hinted mode)

    # clause arena
    total = 0
    @input_clauses.each -> (c)
      total += c.size
    cap = total * 8 + 4096
    @arena = i64[cap]
    @acap = cap
    @asize = 0
    maxcl = @input_clauses.size * 8 + 1024
    @cstart = i64[maxcl]
    @clen = i64[maxcl]
    @alive = i64[maxcl]
    @clbd = i64[maxcl]           # 0 = original clause (never deleted)
    @cused = i64[maxcl]          # conflict count when last resolved in analysis
    @gid = i64[maxcl]            # clause index -> global proof id
    @ccap = maxcl
    @ncl = 0

    # Binary-clause implication lists: propagating -l walks blist[l] and
    # assigns/conflicts DIRECTLY — no clause-arena read, no watch movement
    # (a binary's watches never move). Binaries live here instead of the
    # two-watched lists; the clause body stays in the arena for analysis
    # and proofs. Payload is inline per node: other literal + reason ci.
    @bl_head = i64[2 * nv + 4]
    i = 0
    while i < 2 * nv + 4
      @bl_head[i] = -1
      i += 1
    @bl_cap = total + 4096
    @bl_next = i64[@bl_cap]
    @bl_other = i64[@bl_cap]
    @bl_ci = i64[@bl_cap]
    @bl_size = 0

    # Contiguous watch stacks: per-literal blocks inside one packed pool.
    # Entry = (clause_index << 32) | (blocker & 0xFFFFFFFF). The previous
    # intrusive linked lists paid a cache miss per node hop; blocks scan
    # linearly (propagation was 56% of the ibm-12 solve profile). Packing
    # and unpacking live ONLY in native typed code: a boxed `ci << 32`
    # promotes past the small-int range.
    nlits = 2 * nv + 4
    @ws_start = i64[nlits]
    @ws_size = i64[nlits]
    @ws_cap = i64[nlits]
    @wp_cap = 4 * maxcl + 2 * nlits + 64
    @wpool = i64[@wp_cap]
    @wp_state = i64[4]           # pool top / pool cap / overflow flag
    @wp_state[1] = @wp_cap

    @input_clauses.each -> (c)
      self.add_input_clause(c)

  # ---- literal encoding ---------------------------------------------------

  -> lit_index(l)
    l > 0 ? 2 * l : 2 * (0 - l) + 1

  -> value(l)
    a = @assign[l.abs]
    l > 0 ? a : 0 - a

  # ---- arena --------------------------------------------------------------

  -> grow_arena(need)
    if @asize + need > @acap
      ncap = @acap * 2
      ncap = @asize + need + 1024 if ncap < @asize + need
      # The arena is append-only (reduce_db only detaches); a search that
      # cannot finish grows it without bound until the runtime's typed-array
      # limit fires as a cryptic crash hours in. Fail precisely instead.
      if ncap > 1073741824
        raise "learned-clause arena exceeded 8 GiB; instance too hard for the current search — bound it with --conflicts or use the portfolio"
      bigger = i64[ncap]
      i = 0
      while i < @asize
        bigger[i] = @arena[i]
        i += 1
      @arena = bigger
      @acap = ncap
    0

  -> grow_clause_tables
    if @ncl + 1 >= @ccap
      ncap = @ccap * 2
      cs = i64[ncap]
      cl = i64[ncap]
      al = i64[ncap]
      lb = i64[ncap]
      cu = i64[ncap]
      gd = i64[ncap]
      i = 0
      while i < @ncl
        cs[i] = @cstart[i]
        cl[i] = @clen[i]
        al[i] = @alive[i]
        lb[i] = @clbd[i]
        cu[i] = @cused[i]
        gd[i] = @gid[i]
        i += 1
      @cstart = cs
      @clen = cl
      @alive = al
      @clbd = lb
      @cused = cu
      @gid = gd
      @ccap = ncap
      # the watch pool is sized by clause capacity: regrow it and repack
      # every live clause from the clause DB (watches are reconstructible)
      @wp_cap = 4 * ncap + 4 * @nvars + 72
      @wpool = i64[@wp_cap]
      @wp_state[0] = 0
      @wp_state[1] = @wp_cap
      self.rebuild_watches
    0

  # Register binary clause (a | b): falsifying a implies b and vice versa.
  -> bl_add(a, b, ci)
    if @bl_size + 2 > @bl_cap
      if @fixed_caps
        @retired = true
        return 0
      ncap = @bl_cap * 2
      nn = i64[ncap]
      no = i64[ncap]
      nc = i64[ncap]
      i = 0
      while i < @bl_size
        nn[i] = @bl_next[i]
        no[i] = @bl_other[i]
        nc[i] = @bl_ci[i]
        i += 1
      @bl_next = nn
      @bl_other = no
      @bl_ci = nc
      @bl_cap = ncap
    la = self.lit_index(a)
    lb = self.lit_index(b)
    n1 = @bl_size
    @bl_size += 1
    @bl_next[n1] = @bl_head[la]
    @bl_other[n1] = b
    @bl_ci[n1] = ci
    @bl_head[la] = n1
    n2 = @bl_size
    @bl_size += 1
    @bl_next[n2] = @bl_head[lb]
    @bl_other[n2] = a
    @bl_ci[n2] = ci
    @bl_head[lb] = n2
    0

  # Attach watcher slot `slot` of clause `ci` to the list of literal `l`,
  # caching `blocker` -- any other literal of the clause. If the blocker is
  # already true the clause is satisfied and propagation can skip it without
  # reading the clause body at all.
  -> watch(ci, slot, l, blocker)
    li = self.lit_index(l)
    wassat_ws_add(@ws_start, @ws_size, @ws_cap, @wpool, @wp_state, li, ci, blocker)
    0

  # Watches are a pure acceleration structure: repack every live clause's
  # two entries tight (+1 slack per literal) straight from the clause DB.
  # Runs on pool exhaustion and after table growth; allocation-free, so
  # worker threads may trigger it safely mid-search. The rebuilt layout
  # always fits: 2*live + nlits < 4*ccap + 2*nlits.
  -> rebuild_watches
    wassat_ws_rebuild(@cstart, @clen, @alive, @arena, @ws_start, @ws_size,
                      @ws_cap, @wpool, @wp_state, @ncl, 2 * @nvars + 4)
    @wp_state[2] = 0
    0

  # Store a clause and return its index; watches the first two literals.
  -> store_clause(lits_arr, n)
    self.grow_clause_tables
    self.grow_arena(n)
    ci = @ncl
    @ncl += 1
    @cstart[ci] = @asize
    @clen[ci] = n
    @alive[ci] = 1
    @clbd[ci] = 0
    @gid[ci] = @next_gid
    @next_gid += 1
    i = 0
    while i < n
      @arena[@asize] = lits_arr[i]
      @asize += 1
      i += 1
    if n == 2
      self.bl_add(@arena[@cstart[ci]], @arena[@cstart[ci] + 1], ci)
    elsif n >= 3
      self.watch(ci, 0, @arena[@cstart[ci]], @arena[@cstart[ci] + 1])
      self.watch(ci, 1, @arena[@cstart[ci] + 1], @arena[@cstart[ci]])
      # an overflowed append dropped its entry; the repack re-creates both
      self.rebuild_watches if @wp_state[2] == 1
    if @proof_mode == WASSAT_PROOF_WRAT
      self.grow_replay_occ(n)
      @runits.push(ci) if n == 1
      @rempties.push(ci) if n == 0
      i = 0
      st = @cstart[ci]
      while i < n
        li = self.lit_index(@arena[st + i])
        slot = @rocc_size
        @rocc_size += 1
        @rocc_next[slot] = @rocc_head[li]
        @rocc_ci[slot] = ci
        @rocc_head[li] = slot
        i += 1
    ci

  -> grow_replay_occ(need)
    if @rocc_size + need > @rocc_cap
      ncap = @rocc_cap * 2
      ncap = @rocc_size + need + 4096 if ncap < @rocc_size + need
      nn = i64[ncap]
      nc = i64[ncap]
      i = 0
      while i < @rocc_size
        nn[i] = @rocc_next[i]
        nc[i] = @rocc_ci[i]
        i += 1
      @rocc_next = nn
      @rocc_ci = nc
      @rocc_cap = ncap
    0

  -> add_input_clause(c)
    n = c.size
    if n == 0
      # Keep an explicit input empty clause in the database. Besides making
      # the arena faithfully represent the DIMACS input, this gives hinted
      # proof replay a real clause id with which to justify the derived empty
      # clause that terminates the certificate.
      self.store_clause(c, 0)
      @ok = false
    elsif n == 1
      ci = self.store_clause(c, 1)
      # the unit clause itself is the reason: direct hint chains cite it
      self.enqueue(c[0], ci) if self.value(c[0]) == 0
      @ok = false if self.value(c[0]) < 0
    else
      self.store_clause(c, n)
    0

  # ---- trail --------------------------------------------------------------

  -> enqueue(l, from)
    v = l.abs
    @assign[v] = l > 0 ? 1 : -1
    @level[v] = @dlevel
    @reason[v] = from
    @phase[v] = l > 0 ? 1 : -1
    @trail[@tsize] = l
    @tsize += 1
    0

  -> backjump(target)
    while @dlevel > target
      limit = @trail_lim[@dlevel - 1]
      while @tsize > limit
        @tsize -= 1
        l = @trail[@tsize]
        v = l.abs
        @assign[v] = 0
        @reason[v] = -1
        wassat_heap_insert(@heap, @heappos, @activity, @hstate, v)
        @vq_state[3] = v if @vq_stamp[v] > @vq_stamp[@vq_state[3]]
      @dlevel -= 1
    @qhead = @tsize
    0

  # ---- propagation --------------------------------------------------------

  # Two-watched-literal propagation. Delegates to the native top-level
  # `wassat_propagate` below; see the note there on why it takes every array
  # as a typed parameter. Scalars cross the boundary through @pstate.
  -> propagate
    @pstate[0] = @qhead
    @pstate[1] = @tsize
    @pstate[2] = -1
    @pstate[3] = 0
    wassat_propagate(@arena, @assign, @level, @reason, @phase, @ws_start,
                     @ws_size, @ws_cap, @wpool, @wp_state, @cstart, @clen,
                     @trail, @pstate, @dlevel,
                     @bl_head, @bl_next, @bl_other, @bl_ci)
    # Pool exhausted mid-scan: the native side rewound qhead past the
    # current literal, so a repack plus a re-run from the same queue
    # position re-derives everything soundly (assignments already made
    # stay on the trail; re-scans see them assigned).
    while @pstate[3] == 1
      self.rebuild_watches
      @pstate[2] = -1
      @pstate[3] = 0
      wassat_propagate(@arena, @assign, @level, @reason, @phase, @ws_start,
                       @ws_size, @ws_cap, @wpool, @wp_state, @cstart, @clen,
                       @trail, @pstate, @dlevel,
                       @bl_head, @bl_next, @bl_other, @bl_ci)
    @qhead = @pstate[0]
    @tsize = @pstate[1]
    @pstate[2]

  # ---- conflict analysis --------------------------------------------------

  # First-UIP analysis. Delegates to the native `wassat_analyze` below and
  # leaves the learned clause in @lbuf; @astate carries the scalars.
  -> analyze(confl)
    @astate[0] = confl
    @astate[1] = @tsize
    @astate[2] = @dlevel
    @astate[5] = @conflicts
    wassat_analyze(@arena, @assign, @level, @reason, @seen, @cstart, @clen,
                   @trail, @lbuf, @mbuf, @mstk, @mclr, @activity, @heap,
                   @heappos, @hstate, @astate, @nvars, @cused,
                   @vq_next, @vq_prev, @vq_stamp, @vq_state)
    @lsize = @astate[3]
    @astate[4]

  # The failed-assumption core: the assumption `a` is falsified under the
  # current trail; walk the reasons of everything that contributed back to
  # the assumption decisions. Returns [a, b1, ..., bm] — assumptions whose
  # conjunction the formula refutes. MiniSat's analyzeFinal.
  -> analyze_final(a)
    core = [a]
    av = a.abs
    @seen[av] = 1
    marked = [av]
    i = @tsize - 1
    floor = 0
    floor = @trail_lim[0] if @dlevel > 0
    while i >= floor
      l = @trail[i]
      v = l.abs
      if @seen[v] == 1
        if @reason[v] < 0 && @level[v] > 0
          # an assumption decision (level 0 reason-less literals are input
          # units, formula-implied, never part of a core); when it is the
          # same VARIABLE it is the opposing assumption literal itself
          # (assume x and -x together)
          core.push(l) unless l == a
        elsif @reason[v] >= 0
          ci = @reason[v]
          st = @cstart[ci]
          n = @clen[ci]
          j = 0
          while j < n
            q = @arena[st + j].abs
            if @seen[q] == 0 && @level[q] > 0
              @seen[q] = 1
              marked.push(q)
            j += 1
      i -= 1
    marked.each -> (v)
      @seen[v] = 0
    core

  # ---- branching ----------------------------------------------------------

  # One-step rollout branching, in the DETOUR sense: for each candidate action
  # (branch variable), run the cheap deterministic base policy (unit
  # propagation) to see where it lands, score the result, and take the best
  # action. Unit propagation stands in for "finish the tour" -- a full
  # completion would mean solving the formula, so the base policy is
  # truncated. Scoring is the classic product rule: a variable that propagates
  # a lot on BOTH polarities splits the search most evenly.
  #
  # A trial that propagates to a conflict is a failed literal: the opposite
  # polarity is implied, which is strictly better than branching at all.
  -> pick_branch_rollout
    best = 0
    bestscore = -1
    tried = 0
    v = 1
    while v <= @nvars
      if @assign[v] == 0 && tried < @lookahead
        tried += 1
        pos = self.trial(v)
        neg = self.trial(0 - v)
        # A polarity that propagates to a conflict makes this variable a very
        # attractive branch, but it is NOT acted on here: asserting the
        # opposite literal mid-search would put an assignment at a decision
        # level with no trail_lim entry, and backjumping would then mistake it
        # for a decision. Failed-literal probing belongs at level zero.
        score = 0
        if pos < 0 || neg < 0
          score = 1000000
        else
          score = pos * neg * 2 + pos + neg
        if score > bestscore
          bestscore = score
          best = v
      v += 1
    best == 0 ? self.pick_branch_activity : best

  # Trial-assign one literal, propagate, and report how many literals that
  # implied. Returns -1 if the trial hit a conflict. Restores the trail.
  -> trial(lit)
    mark = @tsize
    @trail_lim[@dlevel] = @tsize
    @dlevel += 1
    self.enqueue(lit, -1)
    confl = self.propagate
    gain = @tsize - mark
    self.backjump(@dlevel - 1)
    confl >= 0 ? -1 : gain

  # Pop assigned entries lazily until the highest-activity unassigned
  # variable is found; 0 means the assignment is total.
  # Arm diversity switch for the raw-kernel race: EVSIDS arms call this
  # after from_flat (which turns VMTF on for raw kernels).
  -> disable_vmtf
    @use_vmtf = false
    0

  -> pick_branch
    if @mode_stable || !@use_vmtf
      wassat_heap_pick(@assign, @heap, @heappos, @activity, @hstate)
    else
      wassat_vmtf_pick(@assign, @vq_next, @vq_stamp, @vq_state)

  -> pick_branch_activity
    self.pick_branch

  # ---- proof logging ------------------------------------------------------

  # Simple whole-database propagation used only to build hint chains.
  #
  # This runs on its OWN assignment array and never touches the search's
  # trail, levels, reasons or saved phases.  An earlier version reused
  # `enqueue`, which silently overwrote @level for every variable it
  # touched and corrupted the conflict analysis that follows.
  -> replay_value(l)
    a = @rassign[l.abs]
    l > 0 ? a : 0 - a

  -> replay_hints(lits)
    out = self.replay_hints_pass(lits, false)
    # The lazy pass only examines clauses touched by falsification, which
    # yields short chains but never proactively fires stored unit clauses;
    # retry with units seeded first (the checker's own order) before
    # declaring failure.
    out = self.replay_hints_pass(lits, true) if out.empty?
    out

  -> replay_hints_pass(lits, seed_units)
    # a stored empty clause conflicts under any assignment: it lives in no
    # occurrence bucket, so cite it directly
    unless @rempties.empty?
      return [@gid[@rempties[0]]]
    record = []
    conflict = false
    rt = 0
    i = 0
    while i < lits.size
      l = lits[i]
      if self.replay_value(l) > 0
        conflict = true
      elsif self.replay_value(l) == 0
        @rassign[l.abs] = l > 0 ? -1 : 1      # assert the negation
        @rtrail[rt] = l > 0 ? 0 - l : l.abs   # the literal made TRUE
        rt += 1
      i += 1

    if seed_units && !conflict
      ui = 0
      while ui < @runits.size && !conflict
        ci = @runits[ui]
        ul = @arena[@cstart[ci]]
        uv = self.replay_value(ul)
        if uv < 0
          record.push(@gid[ci])
          conflict = true
        elsif uv == 0
          @rassign[ul.abs] = ul > 0 ? 1 : -1
          @rtrail[rt] = ul
          rt += 1
          record.push(@gid[ci])
        ui += 1

    unless conflict
      @rst[0] = 0
      @rst[1] = rt
      @rst[2] = -1
      @rst[3] = 0
      wassat_replay_prop(@arena, @cstart, @clen, @rocc_head, @rocc_next,
                         @rocc_ci, @rassign, @rtrail, @rout, @rst)
      rt = @rst[1]
      k = 0
      while k < @rst[3]
        record.push(@gid[@rout[k]])
        k += 1
      if @rst[2] >= 0
        record.push(@gid[@rst[2]])
        conflict = true

    # touched-only reset: clearing all of @rassign per learned clause was
    # itself a per-conflict full-array scan
    i = 0
    while i < rt
      @rassign[@rtrail[i].abs] = 0
      i += 1

    # A chain that never reached a conflict does not justify the clause;
    # returning it would emit a proof step no checker can accept.
    conflict ? record : []

  -> log_clause(lits)
    if @proof_mode == WASSAT_PROOF_WRAT
      # A tautology (possible for the blocking clause of directly
      # contradictory assumptions) is RUP with no hints at all: negating it
      # is immediately contradictory, which the checker accepts before
      # reading a single hint. Replay would misreport it as a failure.
      taut = false
      ti = 0
      while ti < lits.size
        tj = ti + 1
        while tj < lits.size
          taut = true if lits[ti] == 0 - lits[tj]
          tj += 1
        ti += 1
      hints = []
      hints = self.replay_hints(lits) unless taut
      # Silently omitting a failed replay is unsound: the learned clause is
      # still inserted into the search database, so later hint ids could name
      # a clause the checker never received. Every first-UIP clause is RUP;
      # failure to reconstruct its chain therefore indicates a solver/proof
      # bug and must stop certificate production loudly.
      raise "internal proof replay failed for learned clause: [lits.join(" ")]" if hints.empty? && !taut
      cid = @next_gid                # the id the upcoming store will assign
      line = "[cid] " + lits.join(" ")
      line = "[cid]" if lits.empty?
      self.log_wrat_line(line + " 0 " + hints.join(" ") + " 0")
      self.log_drat_line(lits.empty? ? "0" : lits.join(" ") + " 0") if @dual_drat
      @refuted = true if lits.empty?
    elsif @proof_mode == WASSAT_PROOF_DRAT
      # First-UIP clauses are RUP, hence also valid DRAT additions. Recording
      # their literals directly avoids the whole-database propagation replay
      # required to construct WRAT hints.
      self.log_drat_line(lits.empty? ? "0" : lits.join(" ") + " 0")
      @refuted = true if lits.empty?
    0

  # ---- threaded-portfolio configuration (main thread, pre-spawn) ----------

  -> set_stop_cell(cell)
    @stop_cell = cell
    0

  # Freeze capacities: grow-in-thread is forbidden, exhaustion retires the
  # arm. Call on the main thread after construction.
  -> enable_fixed_caps
    @fixed_caps = true
    0

  # Join the sharing ring: ring[0] is the atomic ticket; slot t%cap starts
  # at 8 + slot*stride with [seq, src_arm, len, lits...].
  -> enable_sharing(ring, cap, maxlen, arm_id)
    @ring = ring
    @ring_cap = cap
    @ring_maxlen = maxlen
    @ring_stride = 3 + maxlen
    @arm_id = arm_id
    @read_ticket = 0
    0

  # Garden-arm diversity: randomize the initial saved phases from a seed
  # (xorshift). Call before solving; sound because phases only steer
  # branching polarity. Seed 0 keeps the all-negative default.
  -> reseed_phases(seed)
    return 0 if seed == 0
    # machine-int typing is load-bearing: untyped xorshift has no 64-bit
    # wrap, promotes to BigInt, and turns this loop quadratic
    rng = seed ## i64
    v = 1
    while v <= @nvars
      rng = rng ^ (rng << 13)
      rng = rng ^ (rng >> 7)
      rng = rng ^ (rng << 17)
      @phase[v] = (rng & 1) == 1 ? 1 : -1
      v += 1
    0

  # Adopt a preprocessed artifact's proof identity: clause k of the reduced
  # formula carries ids[k] in the certificate (surviving originals keep their
  # input ids, preprocessing additions sit between them), and fresh
  # derivations continue from next_gid.
  -> seed_proof_ids(ids, next_gid)
    i = 0
    while i < ids.size
      @gid[i] = ids[i]
      i += 1
    @next_gid = next_gid
    0

  # The coordinator already wrote the wrat header (with the preprocessing
  # prefix); the sink must not emit a second one.
  -> wrat_header_written
    @wrat_header_done = true
    0

  # ---- proof sinks ---------------------------------------------------------

  # Opt a proof stream into disk streaming. Lines then leave memory in
  # bounded chunks instead of accumulating for the whole run; the destination
  # must already be truncated (the CLI does this before solving). nil keeps a
  # stream in its in-memory array.
  -> stream_proofs(wrat_path, drat_path)
    @wrat_sink = wrat_path
    @drat_sink = drat_path
    0

  # In WRAT mode, additionally emit each step in plain DRAT. Emitting both
  # natively at log time is what keeps the two dialects in lockstep once
  # deletions appear: WRAT deletes by clause id, DRAT by literal content, and
  # only the emitter has both on hand.
  -> enable_dual_drat
    @dual_drat = true
    0

  -> log_wrat_line(line)
    if @wrat_sink == nil
      @proof.push(line)
    else
      unless @wrat_header_done
        @wrat_pend.push("wrat 1\n")
        @pend_bytes += 7
        @wrat_header_done = true
      @wrat_pend.push(line + "\n")
      @pend_bytes += line.size + 1
      self.flush_proof_sinks if @pend_bytes > 262144
    0

  -> log_drat_line(line)
    if @drat_sink == nil
      @drat.push(line)
    else
      @drat_pend.push(line + "\n")
      @pend_bytes += line.size + 1
      self.flush_proof_sinks if @pend_bytes > 262144
    0

  # Write pending chunks through the checked append primitive. A failed or
  # short write surfaces here, at fault time, not as a checker rejection two
  # commands later.
  -> flush_proof_sinks
    unless @wrat_pend.empty?
      text = @wrat_pend.join("")
      raise "proof write failed at '[@wrat_sink]'" unless wassat_append_text(@wrat_sink, text)
      @wrat_pend = []
    unless @drat_pend.empty?
      dtext = @drat_pend.join("")
      raise "proof write failed at '[@drat_sink]'" unless wassat_append_text(@drat_sink, dtext)
      @drat_pend = []
    @pend_bytes = 0
    0

  # Truncate sink destinations. A SAT or UNKNOWN outcome must not leave a
  # partial refutation on disk masquerading as evidence for this formula.
  -> abort_proof_sinks
    @wrat_pend = []
    @drat_pend = []
    @pend_bytes = 0
    z = write_file(@wrat_sink, "") unless @wrat_sink == nil
    z = write_file(@drat_sink, "") unless @drat_sink == nil
    0

  # Log the learned clause only when a proof was requested. Materialising the
  # Array unconditionally allocated once per conflict and showed up in the
  # profile as malloc traffic on the no-proof path.
  -> log_learned(n)
    self.log_clause(self.buf_to_array(n)) unless @proof_mode == WASSAT_PROOF_NONE
    0

  # Direct hint chain for the learned clause in @lbuf[0..n), derived from
  # the conflict's resolution cone while the trail is still intact: every
  # antecedent actually resolved by first-UIP analysis or consulted by
  # minimisation, ordered by trail position (dependency order), conflict
  # clause last. Replay-free: reconstructing chains by propagation replay
  # cost minutes per certificate at 50k-conflict scale, because late cones
  # approach the whole implication structure.
  #
  # Correctness: with the learned clause negated, each cited reason clause
  # becomes unit in trail order (its other literals are falsified by the
  # negated clause or by earlier-cited reasons), and the conflict clause is
  # then fully falsified. Minimisation-removed literals' reasons are in the
  # cone by closure, so their falsifications derive too.
  -> log_learned_direct(n, confl)
    return 0 if @proof_mode == WASSAT_PROOF_NONE
    lits = self.buf_to_array(n)
    if @proof_mode == WASSAT_PROOF_DRAT
      self.log_drat_line(lits.empty? ? "0" : lits.join(" ") + " 0")
      return 0
    # mark learned-clause variables: value 1 (never expanded)
    i = 0
    while i < n
      @seen[@lbuf[i].abs] = 1
      i += 1
    # cone closure from the conflict clause: value 2 (reason cited)
    work = [confl]
    wi = 0
    while wi < work.size
      wci = work[wi]
      st = @cstart[wci]
      m = @clen[wci]
      j = 0
      while j < m
        v = @arena[st + j].abs
        if @seen[v] == 0
          @seen[v] = 2
          rci = @reason[v]
          raise "internal error: cone literal [v] has no reason clause" if rci < 0
          work.push(rci)
        j += 1
      wi += 1
    # cite cone reasons in trail order, conflict last
    hints = []
    ti = 0
    while ti < @tsize
      v = @trail[ti].abs
      hints.push(@gid[@reason[v]]) if @seen[v] == 2
      ti += 1
    hints.push(@gid[confl])
    # clear both marker kinds
    i = 0
    while i < n
      @seen[@lbuf[i].abs] = 0
      i += 1
    work.each -> (wci2)
      st = @cstart[wci2]
      m = @clen[wci2]
      j = 0
      while j < m
        @seen[@arena[st + j].abs] = 0
        j += 1
    cid = @next_gid
    line = "[cid] " + lits.join(" ")
    line = "[cid]" if lits.empty?
    self.log_wrat_line(line + " 0 " + hints.join(" ") + " 0")
    self.log_drat_line(lits.empty? ? "0" : lits.join(" ") + " 0") if @dual_drat
    @refuted = true if lits.empty?
    0

  # Copy the learned clause out of the buffer; only needed for proof output.
  -> buf_to_array(n)
    out = []
    i = 0
    while i < n
      out.push(@lbuf[i])
      i += 1
    out

  # Literal block distance: how many distinct decision levels a clause spans.
  # Low-LBD clauses are the ones worth keeping (Audemard & Simon).
  -> compute_lbd_buf(n)
    @lbd_stamp += 1
    stamp = @lbd_stamp
    count = 0
    i = 0
    while i < n
      lv = @level[@lbuf[i].abs]
      if @lbd_seen[lv] != stamp
        @lbd_seen[lv] = stamp
        count += 1
      i += 1
    count

  # One bounded vivification pass over kept learned clauses (3 <= LBD <= 6,
  # length >= 3): for each, assert negations literal by literal at fresh
  # decision levels; unit propagation conflicting after i literals proves
  # l1..li is implied — store it, retire the original (its watchers stay
  # until the next rebuild; the dead clause is still implied, so stray
  # propagation from it remains sound). Runs at decision level zero.
  -> vivify_round
    budget = 300
    ci = 0
    while ci < @ncl && budget > 0
      if @alive[ci] == 1 && @clbd[ci] >= 3 && @clbd[ci] <= 6 && @clen[ci] >= 3
        budget -= 1
        st = @cstart[ci]
        n = @clen[ci]
        # copy out: propagation may reorder arena slots mid-walk
        i = 0
        while i < n
          @obuf[i] = @arena[st + i]
          i += 1
        sat_or_skip = false
        i = 0
        while i < n && !sat_or_skip
          sat_or_skip = true if self.value(@obuf[i]) != 0
          i += 1
        unless sat_or_skip
          shorten = 0
          i = 0
          while i < n && shorten == 0
            @trail_lim[@dlevel] = @tsize
            @dlevel += 1
            self.enqueue(0 - @obuf[i], -1)
            confl = self.propagate
            if confl >= 0
              shorten = i + 1
            else
              i += 1
          self.backjump(0)
          # a root-falsified derived unit is a whole-formula refutation the
          # loop machinery would not surface from here — leave that clause
          # to ordinary search (rare, and merely a missed shortening)
          if shorten == 1 && self.value(@obuf[0]) < 0
            shorten = 0
          if shorten > 0 && shorten < n
            nci = self.store_clause(@obuf, shorten)
            lbdv = @clbd[ci]
            lbdv = shorten - 1 if shorten - 1 < lbdv
            lbdv = 1 if lbdv < 1
            @clbd[nci] = lbdv
            @nlearned += 1 if shorten > 1
            if shorten == 1
              # a derived unit: assert it at the root; a conflict from the
              # propagation will resurface at the loop's next iteration
              l0 = @obuf[0]
              if self.value(l0) == 0
                self.enqueue(l0, nci)
                confl2 = self.propagate
            @alive[ci] = 0
            @vivified += 1
      ci += 1
    0

  # Cycle the saved phases: best-phase epochs interleaved with inverted,
  # original, and random assignments — diversification with a persistent
  # pull back toward the deepest basin seen. Runs at level zero.
  -> rephase
    idx = @rephase_idx % 6
    # typed local: untyped xorshift never wraps and promotes to BigInt;
    # masked to 47 bits on store-back so the ivar stays a fast small int
    rng = @rephase_rng ## i64
    v = 1
    while v <= @nvars
      if idx == 1
        @phase[v] = 1
      elsif idx == 3
        @phase[v] = -1
      elsif idx == 5
        rng = rng ^ (rng << 13)
        rng = rng ^ (rng >> 7)
        rng = rng ^ (rng << 17)
        @phase[v] = (rng & 1) == 1 ? 1 : -1
      else
        @phase[v] = @bphase[v]
      v += 1
    @rephase_rng = rng & 140737488355327
    @rephase_idx += 1
    @rephases += 1
    @rephase_at = @conflicts + 4000 + 1000 * @rephases
    @best_tsize = 0
    0

  # Drop the least useful half of the learned clauses and rebuild the watch
  # lists over the survivors. Only ever called at decision level zero, where
  # no clause is anybody's reason, so nothing in the trail can dangle.
  -> reduce_db
    # histogram LBD values to find a cut that removes about half
    total = 0
    hist = @rhist
    i = 0
    while i < 64
      hist[i] = 0
      i += 1
    ci = 0
    while ci < @ncl
      if @alive[ci] == 1 && @clbd[ci] > 0
        b = @clbd[ci]
        b = 63 if b > 63
        hist[b] += 1
        total += 1
      ci += 1
    cut = 63
    if total > 0
      half = total / 2
      acc = 0
      b = 63
      while b >= 2 && acc < half
        acc += hist[b]
        cut = b
        b -= 1

    # Keep binaries and anything below the cut; drop the rest — EXCEPT
    # tier-2 clauses (LBD <= 6) resolved in analysis since the previous
    # reduction: recency of use predicts future use better than glue alone
    # (glucose-style tiering; the counting chains of cardinality instances
    # live or die by this).
    ci = 0
    while ci < @ncl
      if @alive[ci] == 1 && @clbd[ci] >= cut && @clen[ci] > 2 && @clbd[ci] > 2
        keep2 = @clbd[ci] <= 6 && @cused[ci] >= @last_reduce_at
        @alive[ci] = 0 unless keep2
      ci += 1
    @last_reduce_at = @conflicts

    # Fixed-capacity mode reclaims the arena in place: live clauses slide
    # down over dead space (dest <= src, in index order), clause INDICES
    # stay stable (reasons, watch slots), dead clauses zero their length.
    # Only sound without proof logging — proof replay would still need the
    # dead literals; --fast is PROOF_NONE by contract.
    if @fixed_caps && @proof_mode == WASSAT_PROOF_NONE
      wp = 0
      ci = 0
      while ci < @ncl
        if @alive[ci] == 1
          st = @cstart[ci]
          n = @clen[ci]
          if st != wp
            k = 0
            while k < n
              @arena[wp + k] = @arena[st + k]
              k += 1
            @cstart[ci] = wp
          wp += n
        else
          @clen[ci] = 0
        ci += 1
      @asize = wp

    # rebuild watches from scratch over the survivors (tight repack)
    self.rebuild_watches
    # recount the live learned population for the reduction schedule
    @nlearned = 0
    ci = 0
    while ci < @ncl
      @nlearned += 1 if @alive[ci] == 1 && @clbd[ci] > 0
      ci += 1
    0

  # ---- clause sharing (seqlock ring) ---------------------------------------

  # Export the learned clause in @lbuf[0..n): reserve a ticket, mark the
  # slot (even seq), write payload plain, commit (odd seq, RELEASE). A
  # consumer that acquires the odd seq observes the payload.
  -> share_export(n)
    t = ccall("__w_arr_fetch_add", @ring, 0, 1)
    base = 8 + (t % @ring_cap) * @ring_stride
    z = ccall("__w_arr_store_rel", @ring, base, 2 * t)
    @ring[base + 1] = @arm_id
    @ring[base + 2] = n
    i = 0
    while i < n
      @ring[base + 3 + i] = @lbuf[i]
      i += 1
    z = ccall("__w_arr_store_rel", @ring, base, 2 * t + 1)
    @share_exports += 1
    0

  # Import committed clauses at a level-zero safe point. Returns -1 when an
  # import refutes the formula (all-false or unit-conflict at root), else 0.
  # Lapped slots are skipped (losing shared clauses is harmless); a torn
  # read is impossible by the seqlock protocol, and every accepted clause
  # is still sanity-scanned before it touches the database.
  -> share_import
    wt = ccall("__w_arr_load_acq", @ring, 0)
    status = 0
    while @read_ticket < wt && status == 0
      t = @read_ticket
      base = 8 + (t % @ring_cap) * @ring_stride
      s1 = ccall("__w_arr_load_acq", @ring, base)
      if s1 < 2 * t + 1
        # not committed yet; retry at the next safe point
        wt = @read_ticket
      else
        accept = false
        n = 0
        if s1 == 2 * t + 1
          src = @ring[base + 1]
          n = @ring[base + 2]
          if src != @arm_id && n >= 1 && n <= @ring_maxlen
            i = 0
            while i < n
              @mbuf[i] = @ring[base + 3 + i]
              i += 1
            s2 = ccall("__w_arr_load_acq", @ring, base)
            accept = s2 == 2 * t + 1
        if accept
          # sanity: literals in range (belt and braces under the seqlock)
          ok = true
          i = 0
          while i < n
            v = @mbuf[i].abs
            ok = false if v < 1 || v > @nvars
            i += 1
          if ok
            status = self.import_clause(n)
            @share_imports += 1 if status >= 0
          else
            @share_dropped += 1
        else
          @share_dropped += 1 if s1 > 2 * t + 1
        @read_ticket = t + 1
    status

  # Assignment-aware install of the clause in @mbuf[0..n) at level zero:
  # satisfied -> skip; all-false -> the formula is refuted (shared clauses
  # are formula-implied); unit -> store, enqueue, propagate; otherwise store
  # watching two non-false literals. Capacity exhaustion drops the import
  # (sharing is an optimization, never worth corruption).
  -> import_clause(n)
    sat = false
    unassigned = 0
    i = 0
    while i < n
      lv = self.value(@mbuf[i])
      sat = true if lv > 0
      unassigned += 1 if lv == 0
      i += 1
    return 0 if sat
    return -1 if unassigned == 0
    if @fixed_caps && (@asize + n + 4 > @acap || @ncl + 2 >= @ccap)
      @share_dropped += 1
      return 0
    # move non-false literals to the front so store_clause watches them
    front = 0
    i = 0
    while i < n
      if self.value(@mbuf[i]) == 0
        tmp = @mbuf[front]
        @mbuf[front] = @mbuf[i]
        @mbuf[i] = tmp
        front += 1
      i += 1
    ci = self.store_clause(@mbuf, n)
    @clbd[ci] = 2
    if unassigned == 1
      self.enqueue(@mbuf[0], ci)
      confl = self.propagate
      return -1 if confl >= 0
    0

  # ---- search -------------------------------------------------------------

  -> solve_loop(stop_conflicts)
    result = 0                       # 0 unknown, 1 sat, -1 unsat
    limited = false

    while result == 0 && !limited
      # Cooperative cancellation: another arm answered. Checked at the top
      # of every iteration — the only place a worker can be stopped.
      confl = -1
      if @stop_cell != nil && @stop_cell[0] != 0
        limited = true
      else
        confl = self.propagate
      if limited
        0
      elsif confl >= 0
        @conflicts += 1
        @since_restart += 1
        if @dlevel == 0
          self.log_clause([])
          @formula_unsat = true
          result = -1
        else
          # Fixed capacities: exhaustion first forces a reduce+compact, and
          # if the arena still cannot take this clause the arm retires
          # loudly — never a realloc in a worker thread.
          if @fixed_caps && (@asize + @nvars + 4 > @acap || @ncl + 2 >= @ccap)
            self.backjump(0)
            self.reduce_db
            if @asize + @nvars + 4 > @acap || @ncl + 2 >= @ccap
              @retired = true
              limited = true
          if limited
            0
          else
            target = self.analyze(confl)
            n = @lsize
            lbd = self.compute_lbd_buf(n)
            self.log_learned_direct(n, confl)
            # low-LBD learned clauses are the sharing currency
            self.share_export(n) if @ring != nil && lbd <= 2 && n <= @ring_maxlen
            self.backjump(target)
            asserting = @lbuf[0]
            if n == 1
              # Unit clauses are stored too, not just asserted: a logged clause
              # consumes an id in the checker's database, so skipping the store
              # here would desynchronise every later hint reference.
              ci = self.store_clause(@lbuf, 1)
              self.enqueue(asserting, ci)
            else
              # store learned clause, watching the asserting literal and a
              # literal from the backjump level
              best = 1
              bl = -1
              i = 1
              while i < n
                lv = @level[@lbuf[i].abs]
                if lv > bl
                  bl = lv
                  best = i
                i += 1
              @obuf[0] = asserting
              @obuf[1] = @lbuf[best]
              j = 2
              i = 1
              while i < n
                unless i == best
                  @obuf[j] = @lbuf[i]
                  j += 1
                i += 1
              ci = self.store_clause(@obuf, n)
              @clbd[ci] = lbd
              self.enqueue(asserting, ci)
            # Exponential moving averages (fixed-point << 16): the fast/slow
            # LBD ratio is the restart trigger, the trail EMA its blocker.
            @nlearned += 1 if n > 1
            lv = lbd << 16
            @ema_fast += (lv - @ema_fast) >> 5
            @ema_slow += (lv - @ema_slow) >> 14
            @ema_trail += ((@tsize << 16) - @ema_trail) >> 12
            @lbd_gcount += 1
            # Deepest assignment this epoch: remember its phases. Restarts
            # and rephases steer back into this basin instead of discarding
            # the progress (the reason rare restarts used to be right).
            if @tsize > @best_tsize
              @best_tsize = @tsize
              wassat_best_phase_save(@trail, @assign, @bphase, @tsize)
            wassat_evsids_advance(@hstate)
            # Import safe point: every 2048 conflicts, drain the ring at
            # level zero with assignment-aware installs.
            if @ring != nil
              @import_pending += 1
              if @import_pending >= 2048
                @import_pending = 0
                self.backjump(0)
                rc = self.share_import
                if rc < 0
                  self.log_clause([])
                  @formula_unsat = true
                  result = -1
            if stop_conflicts > 0 && @conflicts >= stop_conflicts
              limited = true
      else
        # Clause-DB reduction first, on its own schedule: when the live
        # learned count passes the limit, drop the high-LBD half. Decoupled
        # from restarts — coupling it to accepted restarts left long
        # searches dragging an ever-larger database (measured on both the
        # psi tensor cells and the k=5 Lonely Runner class).
        if @nlearned > @reduce_limit
          self.backjump(0)
          self.reduce_db
          @reductions += 1
          @reduce_limit += @reduce_step
          # Vivification (DETOUR dominance on learned clauses) — MEASURED
          # NET-NEGATIVE in v1 form and gated off: prefix-conflict
          # shortening replaced clauses but perturbed trajectories
          # (ibm-12 conflicts 5,074 -> 18,292; uuf250 +0.3s; lr5 frontier
          # unmoved). Opt-in for future experiments with the stronger
          # forms (false-literal removal, implication-aware shortening).
          self.vivify_round if @proof_mode == WASSAT_PROOF_NONE && env("WASSAT_VIVIFY") == "1"

        # Glucose restart: the recent learning quality (fast EMA) is
        # markedly worse than the long-run average (slow EMA) — the search
        # has stopped making progress where it is. Blocked while the trail
        # is much deeper than usual (plausibly closing on a model), which is
        # what protects satisfiable BMC-style instances from restart churn.
        # The old 16,384-conflict floor predates rephasing; with best-phase
        # rephasing a restart resumes near the remembered basin, so the
        # floor drops to 64.
        # mode switch at the boundary
        if @conflicts >= @mode_at
          @mode_stable = !@mode_stable
          if @mode_stable
            @mode_len = @mode_len * 2
            @mode_at = @conflicts + 3 * @mode_len
            # enter stable under the best phases seen so far
            v2 = 1
            while v2 <= @nvars
              @phase[v2] = @bphase[v2]
              v2 += 1
          else
            @mode_at = @conflicts + @mode_len
        floor = @mode_stable ? 16384 : 64
        want_restart = false
        if @since_restart >= floor && @lbd_gcount >= 128
          if @ema_fast * 4 > @ema_slow * 5
            want_restart = true
        if want_restart && (@tsize << 16) * 5 > @ema_trail * 7
          want_restart = false          # blocked: unusually deep trail
        if want_restart
          @since_restart = 0
          @restart_count += 1
          self.backjump(0)
          # Rephase on schedule, at a restart boundary: cycle the saved
          # phases through best / inverted / best / original / best /
          # random, then start a fresh best-phase epoch.
          if @conflicts >= @rephase_at
            self.rephase
        else
          # Assumptions occupy the first decision levels; a restart pops
          # them and this branch re-asserts them on the way back down.
          handled = false
          if @dlevel < @nassump
            a = @assump[@dlevel]
            av = self.value(a)
            if av > 0
              # already satisfied: hold an empty decision level so later
              # assumptions still map to their own levels
              @trail_lim[@dlevel] = @tsize
              @dlevel += 1
            elsif av < 0
              # falsified: the query is UNSAT under these assumptions
              @failed_core = self.analyze_final(a)
              blocking = []
              @failed_core.each -> (l)
                blocking.push(0 - l)
              self.log_clause(blocking) unless @proof_mode == WASSAT_PROOF_NONE
              bi = self.store_clause(blocking, blocking.size)
              result = -2
            else
              @decisions_made += 1
              @trail_lim[@dlevel] = @tsize
              @dlevel += 1
              self.enqueue(a, -1)
            handled = true
          unless handled
            v = 0
            if @lookahead > 0
              v = self.pick_branch_rollout
            else
              v = self.pick_branch
            if v == 0
              result = 1
            elsif v > 0
              @decisions_made += 1
              @trail_lim[@dlevel] = @tsize
              @dlevel += 1
              self.enqueue(@phase[v] > 0 ? v : 0 - v, -1)
            # v < 0 means rollout applied a forced literal; just loop again
    limited ? 0 : result

  # Flat-load construction for the trusted path: build the solver shell
  # with NO input clauses, then ingest the preprocessor's flat mirrors
  # natively (arena copy + watches + binary lists + proof ids in one pass).
  -> .from_flat(nvars, art, lookahead)
    s = Wassat.new(nvars, [], WASSAT_PROOF_NONE, lookahead)
    s.load_flat(art)
    s

  -> load_flat(art)
    sncl = art["fncl"]
    # size the arena and tables for the live clauses plus learning headroom
    total = 0
    sfcl = art["fcl"]
    salive = art["falive"]
    i = 0
    while i < sncl
      total += sfcl[i] if salive[i] == 1
      i += 1
    # Right-sized, not worst-cased: zero-filling 8x tables cost ~200ms of
    # pure page touching on bmc-scale kernels (the tables dwarfed the
    # solve). Learned clauses grow the tables on demand through
    # grow_clause_tables, which doubles and repacks — a few cheap
    # reallocations on long runs instead of a huge cold allocation on
    # every run.
    cap = total * 2 + 65536
    @arena = i64[cap]
    @acap = cap
    maxcl = sncl + sncl / 2 + 65536
    @cstart = i64[maxcl]
    @clen = i64[maxcl]
    @alive = i64[maxcl]
    @clbd = i64[maxcl]
    @cused = i64[maxcl]
    @gid = i64[maxcl]
    @ccap = maxcl
    @wp_cap = 2 * maxcl + 4 * @nvars + 72
    @wpool = i64[@wp_cap]
    @wp_state[0] = 0
    @wp_state[1] = @wp_cap
    @bl_cap = 2 * total + 4096
    @bl_next = i64[@bl_cap]
    @bl_other = i64[@bl_cap]
    @bl_ci = i64[@bl_cap]
    units = i64[@nvars + 4]
    pm = i64[10]
    pm[0] = sncl
    pm[1] = cap
    pm[2] = maxcl
    pm[8] = @bl_cap
    wassat_load_flat(art["fla"], art["fcs"], sfcl, salive, art["ftaut"],
                     art["fpgid"], @arena, @cstart, @clen, @alive, @clbd,
                     @gid, @bl_head, @bl_next,
                     @bl_other, @bl_ci, units, pm)
    @ncl = pm[3]
    @asize = pm[4]
    @use_vmtf = true if art["raw"] == true
    self.rebuild_watches
    @bl_size = pm[7]
    @next_gid = art["next_gid"]
    @ok = false if pm[6] == 1
    u = 0
    while u < pm[5]
      ci = units[u]
      l = @arena[@cstart[ci]]
      if self.value(l) == 0
        self.enqueue(l, ci)
      elsif self.value(l) < 0
        @ok = false
      u += 1
    0

  -> solve
    self.solve_budget(0)

  # Allocation-free worker entry for the threaded portfolio: run to a
  # decision (or stop/retire) and write the verdict and assignment into the
  # shared result slab — no boxed result objects in a worker thread.
  #   res[base]   = 1 SAT / -1 UNSAT / 0 stopped-unknown / 2 retired
  #   res[base+1..base+nvars] = assignment (SAT only)
  #   res[base+nvars+1..+3]  = exports / imports / dropped
  -> solve_shared(res, base)
    res[base + @nvars + 6] = ccall("__w_clock_ms")
    status = 0
    if @ok
      status = self.solve_loop(0)
    else
      @formula_unsat = true
      status = 0 - 1
    res[base] = status
    res[base] = 2 if status == 0 && @retired
    if status == 1
      v = 1
      while v <= @nvars
        res[base + v] = @assign[v] >= 0 ? 1 : 0
        v += 1
    res[base + @nvars + 1] = @share_exports
    res[base + @nvars + 2] = @share_imports
    res[base + @nvars + 3] = @share_dropped
    res[base + @nvars + 4] = @conflicts
    res[base + @nvars + 5] = ccall("__w_clock_ms")
    # first decisive answer raises the stop flag for every other arm
    if (status == 1 || status == 0 - 1) && @stop_cell != nil
      @stop_cell[1] = status
      @stop_cell[0] = 1
    0

  # Full MiniSat-style incremental query: SAT / UNSAT / UNKNOWN under the
  # given assumption literals, plus the failed-assumption core on UNSAT.
  # Each call is a FRESH query: per-query state (trail, cached non-formula
  # verdict, previous core) resets, while the learned-clause database,
  # branching activities, restart cadence, and hidden proof prefix persist.
  -> solve_assuming(assumptions)
    self.solve_assuming_budget(assumptions, 0)

  -> solve_assuming_budget(assumptions, max_conflicts)
    self.reset_query
    @assump = assumptions
    @nassump = assumptions.size
    r = self.solve_query(max_conflicts)
    @assump = []
    @nassump = 0
    r

  # Clear per-query state between incremental calls. A formula-level UNSAT
  # is the one verdict no later query can undo; everything else is scoped to
  # the query that produced it.
  -> reset_query
    self.backjump(0)
    @failed_core = []
    @terminal_status = 0 unless @formula_unsat
    0

  # Build a detached result. Arrays returned by an earlier call must not gain
  # proof steps, lose a model, or otherwise change when the same solver resumes.
  # Status -2 is UNSAT-under-assumptions: reported with status -1 plus a
  # non-empty "core" (formula-level UNSAT always carries an empty core).
  -> result_for(status)
    sat = status == 1
    unsat = status == -1 || status == -2
    model = []
    if sat
      v = 1
      while v <= @nvars
        model.push(@assign[v] >= 0 ? v : 0 - v)
        v += 1

    core = []
    core = @failed_core.dup if status == -2
    proof = []
    drat = []
    proof = @proof.dup if unsat && @proof_mode == WASSAT_PROOF_WRAT
    drat = @drat.dup if unsat && (@proof_mode == WASSAT_PROOF_DRAT || @dual_drat)
    { "sat": sat, "unsat": unsat, "complete": status != 0,
      "status": status == -2 ? -1 : status, "model": model,
      "core": core, "proof": proof, "drat": drat,
      "proof_mode": @proof_mode,
      "conflicts": @conflicts, "decisions": @decisions_made,
      "props": @pstate[4],
      "restarts": @restart_count, "reduces": @reductions }

  # A positive conflict budget is additional work for this call. Returning
  # UNKNOWN preserves the trail, learned database, restart cadence, and hidden
  # proof prefix so a later call can continue safely. Zero is unlimited.
  -> solve_budget(max_conflicts)
    @assump = []
    @nassump = 0
    self.solve_query(max_conflicts)

  -> solve_query(max_conflicts)
    raise "conflict budget must be non-negative, got [max_conflicts]" if max_conflicts < 0
    return self.result_for(@terminal_status) unless @terminal_status == 0

    status = -1
    if @ok
      stop_conflicts = 0
      stop_conflicts = @conflicts + max_conflicts if max_conflicts > 0
      status = self.solve_loop(stop_conflicts)
    else
      @formula_unsat = true
      self.log_clause([]) unless @refuted

    # UNSAT-under-assumptions is a per-query verdict, never terminal.
    @terminal_status = status unless status == 0 || status == -2
    self.result_for(status)

# Native two-watched-literal propagation.
#
# WHY THIS IS A TOP-LEVEL FUNCTION WITH TYPED ARRAY PARAMETERS
#
# Reading an element out of a typed array held in a local or an instance
# field loses the element type, so the scalar comes back NaN-boxed and every
# later operation on it dispatches through the boxed runtime helpers
# (`w_add`, `w_sub`, `w_array_get`). A profile of the method version showed
# ~39% of time in array-access primitives and ~34% in method dispatch. A
# function *parameter* declared `i64[]` keeps its element type, so reads stay
# raw machine integers and the arithmetic compiles to native instructions.
# Scalars are exchanged through `st` because scalar returns box too.
#
#   st[0] = qhead   st[1] = trail size   st[2] = conflicting clause, or -1
#
# Two standard tricks carry the algorithmic weight. Each watcher caches a
# BLOCKING LITERAL: if it is already true the clause is satisfied and we skip
# it without reading the clause body. And the watch list is traversed IN
# PLACE with a trailing pointer, so a watcher is spliced only when it really
# moves to another literal.
# Best-phase snapshot: copy the current assignment's polarity for every
# trail variable. Runs on every deepening conflict, so it must be a raw
# typed loop — the boxed version was 58% of the ibm-12 solve profile.
-> wassat_best_phase_save(tr, asg, bph, tsize) (i64[] i8[] i64[] i64)
  ti = 0
  while ti < tsize
    l = tr[ti]
    v = l
    v = 0 - l if l < 0
    bph[v] = asg[v]
    ti += 1
  0

-> wassat_propagate(ar, asg, lvl, rsn, phs, wss, wsn, wsc, wp, wst, cs, cln, tr, st, dl, blh, bln, blo, blc) (i64[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[])
  qhead = st[0]
  tsize = st[1]
  conflict = -1
  bail = 0
  visits = 0
  while qhead < tsize && conflict < 0 && bail == 0
    p = tr[qhead]
    qhead += 1
    visits += 1
    neg = 0 - p
    # literal index, written without a ternary: conditional expressions box
    li = 0
    if neg > 0
      li = neg << 1
    else
      li = ((0 - neg) << 1) + 1
    # binary implications first: direct assign/conflict, no arena access
    b = blh[li]
    while b >= 0 && conflict < 0
      other = blo[b]
      ov = 0
      if other > 0
        ov = asg[other]
      else
        ov = 0 - asg[0 - other]
      if ov < 0
        conflict = blc[b]
      else
        if ov == 0
          v = other
          pol = 1
          if other < 0
            v = 0 - other
            pol = -1
          asg[v] = pol
          lvl[v] = dl
          rsn[v] = blc[b]
          phs[v] = pol
          tr[tsize] = other
          tsize += 1
      b = bln[b]
    # Contiguous watch block, scanned BACKWARD: appends land at the end,
    # so the newest watch is visited first — the same order as the linked
    # lists this replaced (prepend). wss[li] cannot move during the scan
    # (appends go to OTHER literals); removal swaps the front entry in and
    # shrinks the block from the front, which keeps every unvisited entry
    # below j and leaks one pool slot until the next repack.
    j = wss[li] + wsn[li] - 1
    while j >= wss[li] && conflict < 0 && bail == 0
      e = wp[j]
      blk = e & 4294967295
      blk = blk - 4294967296 if blk > 2147483647
      bv = 0
      if blk > 0
        bv = asg[blk]
      else
        bv = 0 - asg[0 - blk]
      if bv > 0
        j -= 1
      else
        ci = e >> 32
        stx = cs[ci]
        n = cln[ci]
        if ar[stx] == neg
          ar[stx] = ar[stx + 1]
          ar[stx + 1] = neg
        other = ar[stx]
        ov = 0
        if other > 0
          ov = asg[other]
        else
          ov = 0 - asg[0 - other]
        if ov > 0
          wp[j] = (ci << 32) | (other & 4294967295)
          j -= 1
        else
          k = 2
          found = -1
          while k < n && found < 0
            lk = ar[stx + k]
            vk = 0
            if lk > 0
              vk = asg[lk]
            else
              vk = 0 - asg[0 - lk]
            if vk >= 0
              found = k
            k += 1
          if found >= 0
            repl = ar[stx + found]
            ar[stx + found] = neg
            ar[stx + 1] = repl
            # remove this entry: pull the (unvisited) front entry into j
            # and shrink the block from the front, then append (ci, other)
            # to repl's block — relocating it to the pool top on overflow
            wp[j] = wp[wss[li]]
            wss[li] = wss[li] + 1
            wsn[li] = wsn[li] - 1
            wsc[li] = wsc[li] - 1
            ri = 0
            if repl > 0
              ri = repl << 1
            else
              ri = ((0 - repl) << 1) + 1
            rn = wsn[ri]
            if rn >= wsc[ri]
              need = 4
              need = rn * 2 if rn * 2 > 4
              top = wst[0]
              if top + need > wst[1]
                bail = 1
              else
                src = wss[ri]
                q = 0
                while q < rn
                  wp[top + q] = wp[src + q]
                  q += 1
                wss[ri] = top
                wsc[ri] = need
                wst[0] = top + need
            if bail == 0
              wp[wss[ri] + rn] = (ci << 32) | (other & 4294967295)
              wsn[ri] = rn + 1
          else
            wp[j] = (ci << 32) | (other & 4294967295)
            if ov == 0
              v = other
              pol = 1
              if other < 0
                v = 0 - other
                pol = -1
              asg[v] = pol
              lvl[v] = dl
              rsn[v] = ci
              phs[v] = pol
              tr[tsize] = other
              tsize += 1
              j -= 1
            else
              conflict = ci
  # Pool exhausted: the current literal must be rescanned after the caller
  # repacks the pool (its entry was already swap-removed). Rewind qhead so
  # the retry re-derives everything from this point; work already enqueued
  # stays valid.
  if bail == 1
    qhead -= 1
    wst[2] = 1
  st[0] = qhead
  st[1] = tsize
  st[2] = conflict
  st[3] = bail
  st[4] = st[4] + visits
  0

# Append one watch entry to a literal's block, relocating the block to the
# pool top (capacity doubling) when full. Sets wst[2] and returns -1 when
# the pool itself is exhausted — the caller repacks via rebuild_watches.
-> wassat_ws_add(wss, wsn, wsc, wp, wst, li, ci, blk) (i64[] i64[] i64[] i64[] i64[] i64 i64 i64)
  n = wsn[li]
  if n >= wsc[li]
    need = 4
    need = n * 2 if n * 2 > 4
    top = wst[0]
    if top + need > wst[1]
      wst[2] = 1
      return 0 - 1
    src = wss[li]
    q = 0
    while q < n
      wp[top + q] = wp[src + q]
      q += 1
    wss[li] = top
    wsc[li] = need
    wst[0] = top + need
  wp[wss[li] + n] = (ci << 32) | (blk & 4294967295)
  wsn[li] = n + 1
  0

# Counting repack of the whole watch pool from the clause DB: two passes
# (count, fill) with +1 slack per literal so the first later append per
# literal does not immediately relocate. Always fits: 2*live + nlits is
# far below the pool's 4*ccap sizing. Never allocates.
-> wassat_ws_rebuild(cs, cln, alive, ar, wss, wsn, wsc, wp, wst, ncl, nlits) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64)
  li = 0
  while li < nlits
    wsn[li] = 0
    li += 1
  ci = 0
  while ci < ncl
    if alive[ci] == 1 && cln[ci] >= 3
      stx = cs[ci]
      a = ar[stx]
      bq = ar[stx + 1]
      la = 0
      if a > 0
        la = a << 1
      else
        la = ((0 - a) << 1) + 1
      lb = 0
      if bq > 0
        lb = bq << 1
      else
        lb = ((0 - bq) << 1) + 1
      wsn[la] = wsn[la] + 1
      wsn[lb] = wsn[lb] + 1
    ci += 1
  top = 0
  li = 0
  while li < nlits
    wss[li] = top
    wsc[li] = wsn[li] + 1
    top = top + wsn[li] + 1
    wsn[li] = 0
    li += 1
  wst[0] = top
  # Ascending fill + the backward block scan in propagate = exactly the
  # replaced linked lists' order (prepend, newest scanned first).
  ci = 0
  while ci < ncl
    if alive[ci] == 1 && cln[ci] >= 3
      stx = cs[ci]
      a = ar[stx]
      bq = ar[stx + 1]
      la = 0
      if a > 0
        la = a << 1
      else
        la = ((0 - a) << 1) + 1
      lb = 0
      if bq > 0
        lb = bq << 1
      else
        lb = ((0 - bq) << 1) + 1
      wp[wss[la] + wsn[la]] = (ci << 32) | (bq & 4294967295)
      wsn[la] = wsn[la] + 1
      wp[wss[lb] + wsn[lb]] = (ci << 32) | (a & 4294967295)
      wsn[lb] = wsn[lb] + 1
    ci += 1
  0

# Native first-UIP conflict analysis with self-subsuming minimisation.
#
# Same reasoning as `wassat_propagate`: arrays arrive as typed parameters so
# element reads stay raw machine integers, and scalars cross through `st`.
# The learned clause is written into `out`, which the caller reuses across
# conflicts -- the previous version allocated three Arrays per conflict and
# showed up as both boxed arithmetic and malloc traffic in the profile.
#
#   st[0] = conflicting clause   st[1] = trail size   st[2] = decision level
#   st[3] = learned clause size  st[4] = backjump level
-> wassat_analyze(ar, asg, lvl, rsn, sn, cs, cln, tr, out, tmp, stk, tclr, act, heap, hpos, hst, st, nv, cused, vqn, vqp, vqs, vst) (i64[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[])
  confl = st[0]
  tsize = st[1]
  dl = st[2]
  counter = 0
  p = 0
  index = tsize - 1
  cl = confl
  size = 1
  keep_going = true

  while keep_going
    cused[cl] = st[5]
    stx = cs[cl]
    n = cln[cl]
    # Skip the literal being RESOLVED by variable, not by slot: watch-based
    # propagation swaps the propagated literal to slot 0, but binary-list
    # propagation never touches the arena, so the slot invariant is gone.
    pv = 0
    if p != 0
      pv = p
      if pv < 0
        pv = 0 - pv
    j = 0
    while j < n
      q = ar[stx + j]
      vq = q
      if q < 0
        vq = 0 - q
      if vq != pv && sn[vq] == 0 && lvl[vq] > 0
        sn[vq] = 1
        # MiniSat-style EVSIDS bumps the whole conflict graph as it is first
        # discovered, not merely the literals surviving minimisation. The
        # latter throws away precisely the variables whose reasons explain a
        # conflict and produced noticeably poorer branching on structured
        # quotient formulas.
        z = wassat_evsids_bump(act, heap, hpos, hst, vq, nv)
        z = wassat_vmtf_front(vqn, vqp, vqs, vst, vq)
        if lvl[vq] >= dl
          counter += 1
        else
          out[size] = q
          size += 1
      j += 1
    tv = tr[index]
    av = tv
    if tv < 0
      av = 0 - tv
    while sn[av] == 0
      index -= 1
      tv = tr[index]
      av = tv
      if tv < 0
        av = 0 - tv
    p = tv
    index -= 1
    sn[av] = 0
    counter -= 1
    if counter > 0
      cl = rsn[av]
    else
      keep_going = false

  out[0] = 0 - p

  # Recursive (MiniSat-style) minimisation: a literal is redundant when
  # every path through its reason DAG bottoms out in clause literals or
  # root assignments. Marks double as a cache — a variable proven covered
  # stays marked so later candidates reuse the work; a failed probe unwinds
  # only its own marks. On Sinz-counter cardinality instances (the k=5
  # Lonely Runner class) the old one-level pass left learned clauses long,
  # and long clauses propagate weakly — this is the classic fix.
  # Results go to `tmp` rather than compacting `out` in place — compaction
  # would overwrite entries still needed to clear the marks.
  nclr = 0
  keep = 1
  i = 1
  while i < size
    q = out[i]
    vq = q
    if q < 0
      vq = 0 - q
    redundant = 0
    if rsn[vq] >= 0
      # iterative litRedundant over the reason DAG
      redundant = 1
      sp = 0
      stk[sp] = vq
      sp += 1
      top = nclr
      while sp > 0 && redundant == 1
        sp -= 1
        cv = stk[sp]
        r = rsn[cv]
        stx = cs[r]
        n = cln[r]
        k = 0
        while k < n && redundant == 1
          lk = ar[stx + k]
          vk = lk
          if lk < 0
            vk = 0 - lk
          if vk != cv && sn[vk] == 0 && lvl[vk] > 0
            if rsn[vk] >= 0
              sn[vk] = 1
              stk[sp] = vk
              sp += 1
              tclr[nclr] = vk
              nclr += 1
            else
              # a decision: this path cannot be covered — fail and unwind
              # the marks THIS probe added (earlier candidates' cache stays)
              redundant = 0
              j = top
              while j < nclr
                sn[tclr[j]] = 0
                j += 1
              nclr = top
          k += 1
    if redundant == 0
      tmp[keep] = q
      keep += 1
    i += 1

  # clear every mark: the clause's own literals, then the probe cache
  i = 1
  while i < size
    q = out[i]
    vq = q
    if q < 0
      vq = 0 - q
    sn[vq] = 0
    i += 1
  i = 0
  while i < nclr
    sn[tclr[i]] = 0
    i += 1

  i = 1
  while i < keep
    out[i] = tmp[i]
    i += 1

  target = 0
  i = 1
  while i < keep
    q = out[i]
    vq = q
    if q < 0
      vq = 0 - q
    lv = lvl[vq]
    if lv > target
      target = lv
    i += 1

  st[3] = keep
  st[4] = target
  0

# Native flat-formula loader: ingest a preprocessor's flat clause mirrors
# directly — live clauses copy arena-to-arena, watches and binary-implication
# lists are built in the same pass, proof ids carry over. Replaces a boxed
# artifact rebuild plus a boxed per-literal intake (~250ms on 100k-clause
# instances). Unit clause indices land in `units` for the boxed enqueue.
#
#   pm[0] src clause count      pm[1] dst arena cap   pm[2] dst clause cap
#   pm[3] out: clauses stored   pm[4] out: arena used pm[5] out: unit count
#   pm[6] out: 1 = saw empty clause  pm[7] out: bl nodes used  pm[8] bl cap
-> wassat_load_flat(sfla, sfcs, sfcl, salive, staut, spgid, dar, dcs, dcl, dal, dlbd, dgid, blh, bln, blo, blc, units, pm) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[])
  sncl = pm[0]
  acap = pm[1]
  ccap = pm[2]
  blcap = pm[8]
  ncl = 0
  asize = 0
  nunits = 0
  saw_empty = 0
  blsize = 0
  si = 0
  while si < sncl
    if salive[si] == 1
      n = sfcl[si]
      if ncl + 1 < ccap && asize + n < acap
        st = sfcs[si]
        dcs[ncl] = asize
        dcl[ncl] = n
        dal[ncl] = 1
        dlbd[ncl] = 0
        dgid[ncl] = spgid[si]
        j = 0
        while j < n
          dar[asize + j] = sfla[st + j]
          j = j + 1
        if n == 0
          saw_empty = 1
        else
          if n == 1
            units[nunits] = ncl
            nunits = nunits + 1
          else
            # long-clause watches are built afterwards by the caller's
            # counting repack (rebuild_watches); only binaries index here
            a = dar[asize]
            bq = dar[asize + 1]
            if n == 2
              if blsize + 2 <= blcap
                la = 0
                if a > 0
                  la = a << 1
                else
                  la = ((0 - a) << 1) + 1
                lb = 0
                if bq > 0
                  lb = bq << 1
                else
                  lb = ((0 - bq) << 1) + 1
                bln[blsize] = blh[la]
                blo[blsize] = bq
                blc[blsize] = ncl
                blh[la] = blsize
                blsize = blsize + 1
                bln[blsize] = blh[lb]
                blo[blsize] = a
                blc[blsize] = ncl
                blh[lb] = blsize
                blsize = blsize + 1
        asize = asize + n
        ncl = ncl + 1
    si = si + 1
  pm[3] = ncl
  pm[4] = asize
  pm[5] = nunits
  pm[6] = saw_empty
  pm[7] = blsize
  0

# Native replay propagation for hint construction: queue-driven unit
# propagation over the LOGICAL clause database via the replay occurrence
# lists. Records, in propagation order, the index of every clause that fired
# as a unit (out[0..st[3]-1]); st[2] reports the conflicting clause or -1.
# The recorded order IS the hint chain: each clause was unit at the moment it
# was recorded, which is exactly what the checker re-verifies. Replaces a
# whole-database fixpoint scan per learned clause that made hinted-proof
# generation quadratic.
#
#   st[0] = qhead   st[1] = trail size   st[2] = conflict ci or -1
#   st[3] = recorded unit count
-> wassat_replay_prop(ar, cs, cln, och, ocn, ocv, rasg, rtr, out, st) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[])
  qhead = st[0]
  tsize = st[1]
  conflict = -1
  count = 0
  while qhead < tsize && conflict < 0
    p = rtr[qhead]
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
      stx = cs[ci]
      n = cln[ci]
      sat = 0
      unassigned = 0
      unit = 0
      j = 0
      while j < n
        l = ar[stx + j]
        vv = 0
        if l > 0
          vv = rasg[l]
        else
          vv = 0 - rasg[0 - l]
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
            rasg[uv] = pol
            rtr[tsize] = unit
            tsize = tsize + 1
            out[count] = ci
            count = count + 1
      w = ocn[w]
  st[0] = qhead
  st[1] = tsize
  st[2] = conflict
  st[3] = count
  0

# Native variable-order heap. Keeping the arrays in typed top-level helpers
# matters: a linear scan over boxed instance fields accounted for roughly a
# quarter of the structured-quotient profile even after activity branching
# itself was repaired.
#
# `hst[0]` is the live heap size and `hst[1]` is the EVSIDS increment.

-> wassat_heap_swap(heap, hpos, a, b) (i64[] i64[] i64 i64) i64
  va = heap[a]
  vb = heap[b]
  heap[a] = vb
  heap[b] = va
  hpos[va] = b
  hpos[vb] = a
  1

-> wassat_heap_up(heap, hpos, act, index) (i64[] i64[] i64[] i64) i64
  i = index
  while i > 0
    parent = (i - 1) / 2
    if act[heap[i]] <= act[heap[parent]]
      return i
    z = wassat_heap_swap(heap, hpos, i, parent)
    i = parent
  i

-> wassat_heap_down(heap, hpos, act, hst, index) (i64[] i64[] i64[] i64[] i64) i64
  i = index
  while 0 < 1
    left = 2 * i + 1
    if left >= hst[0]
      return i
    best = left
    right = left + 1
    if right < hst[0] && act[heap[right]] > act[heap[left]]
      best = right
    if act[heap[best]] <= act[heap[i]]
      return i
    z = wassat_heap_swap(heap, hpos, i, best)
    i = best

-> wassat_heap_insert(heap, hpos, act, hst, v) (i64[] i64[] i64[] i64[] i64) i64
  if hpos[v] >= 0
    return 0
  index = hst[0]
  heap[index] = v
  hpos[v] = index
  hst[0] = index + 1
  z = wassat_heap_up(heap, hpos, act, index)
  1

-> wassat_heap_pop(heap, hpos, act, hst) (i64[] i64[] i64[] i64[]) i64
  size = hst[0]
  if size < 1
    return 0
  top = heap[0]
  last = heap[size - 1]
  hst[0] = size - 1
  hpos[top] = -1
  if size > 1
    heap[0] = last
    hpos[last] = 0
    z = wassat_heap_down(heap, hpos, act, hst, 0)
  top

# Assigned variables can remain in the heap after propagation. Discard them
# only when they reach the top; backjump reinserts a variable iff it had
# already been discarded. This avoids arbitrary heap removals on every unit.
-> wassat_heap_pick(asg, heap, hpos, act, hst) (i8[] i64[] i64[] i64[] i64[]) i64
  v = 0
  while v == 0 && hst[0] > 0
    cand = wassat_heap_pop(heap, hpos, act, hst)
    if cand > 0 && asg[cand] == 0
      v = cand
  v

# Debug/spec helper: validates the heap order and inverse-position map without
# adding checks to the search hot path.
-> wassat_heap_valid(heap, hpos, act, hst, nv) (i64[] i64[] i64[] i64[] i64) i64
  size = hst[0]
  if size < 0 || size > nv
    return 0
  i = 0
  while i < size
    v = heap[i]
    if v < 1 || v > nv || hpos[v] != i
      return 0
    if i > 0
      parent = (i - 1) / 2
      if act[heap[parent]] < act[v]
        return 0
    i += 1
  1

# Integer EVSIDS uses an increasing bump rather than repeatedly walking and
# decaying the whole activity array. Right shifts are rare and preserve heap
# order; 2^52 leaves ample exact headroom in both native i64 and boxed-number
# crossings elsewhere in the runtime.
-> wassat_evsids_rescale(act, hst, nv) (i64[] i64[] i64) i64
  v = 1
  while v <= nv
    act[v] = act[v] >> 32
    v += 1
  hst[1] = hst[1] >> 32
  if hst[1] < 32
    hst[1] = 32
  1

# VMTF move-to-front: unlink v and relink it at the queue head with a fresh
# stamp. The stamp orders "recently in a conflict"; backjump repositions the
# search cursor to the highest-stamp unassigned variable.
-> wassat_vmtf_front(vqn, vqp, vqs, vst, v) (i64[] i64[] i64[] i64[] i64) i64
  return 0 if vst[0] == v
  pn = vqn[v]
  pp = vqp[v]
  if pp > 0
    vqn[pp] = pn
  if pn > 0
    vqp[pn] = pp
  if vst[1] == v
    vst[1] = pp
  h = vst[0]
  vqp[h] = v
  vqn[v] = h
  vqp[v] = 0
  vst[0] = v
  vst[2] = vst[2] + 1
  vqs[v] = vst[2]
  0

# VMTF decision: walk from the search cursor toward the tail, skipping
# assigned variables. Returns 0 when everything is assigned (a model).
-> wassat_vmtf_pick(asg, vqn, vqs, vst) (i8[] i64[] i64[] i64[]) i64
  v = vst[3]
  while v > 0 && asg[v] != 0
    v = vqn[v]
  vst[3] = v
  v

-> wassat_evsids_bump(act, heap, hpos, hst, v, nv) (i64[] i64[] i64[] i64[] i64 i64) i64
  act[v] = act[v] + hst[1]
  if act[v] > 4503599627370496
    z = wassat_evsids_rescale(act, hst, nv)
  if hpos[v] >= 0
    z = wassat_heap_up(heap, hpos, act, hpos[v])
  1

-> wassat_evsids_advance(hst) (i64[]) i64
  hst[1] = hst[1] + hst[1] / 16
  1

# Solve DIMACS text, with proof logging. Returns the result record.
-> wassat_solve(cnf_text)
  wassat_solve_opts(cnf_text, true)

# Solve with proof logging enabled or disabled. Logging off is the fast path.
-> wassat_solve_opts(cnf_text, want_proof)
  wassat_solve_full(cnf_text, want_proof, 0)

# `lookahead` is the number of candidate variables scored by one-step rollout
# before each decision; 0 selects plain activity branching.
-> wassat_solve_full(cnf_text, want_proof, lookahead)
  wassat_solve_limited(cnf_text, want_proof, lookahead, 0)

# Bounded one-shot solve. Status is 1 SAT, -1 UNSAT, or 0 UNKNOWN when the
# positive conflict limit is reached. Proof text is conclusive only at -1.
-> wassat_solve_limited(cnf_text, want_proof, lookahead, max_conflicts)
  mode = want_proof ? WASSAT_PROOF_WRAT : WASSAT_PROOF_NONE
  wassat_solve_mode_limited(cnf_text, mode, lookahead, max_conflicts)

# Explicit proof-mode API. Raw DRAT logs each RUP learned clause directly;
# hinted WRAT additionally replays propagation to construct a checkable hint
# chain. Existing boolean APIs above retain their historical meaning.
-> wassat_solve_mode_limited(cnf_text, proof_mode, lookahead, max_conflicts)
  f = wassat_parse_cnf(cnf_text)
  unless proof_mode == WASSAT_PROOF_NONE || proof_mode == WASSAT_PROOF_WRAT || proof_mode == WASSAT_PROOF_DRAT
    raise "unknown Wassat proof mode: [proof_mode]"
  s = Wassat.new(f["nvars"], f["clauses"], proof_mode, lookahead)
  s.solve_budget(max_conflicts)

# Append text to a file through the runtime primitive, which reports short
# writes and close failures. Compiled path only: the embedded interpreter does
# not whitelist this ccall, and library/spec callers use the in-memory arrays.
-> wassat_append_text(path, text)
  ccall("__w_append_file", path, text)

# Render a proof as .wrat text (hinted, with header). Joined in one pass:
# line-at-a-time concatenation re-copied the accumulated prefix per line and
# went quadratic on long refutations.
-> wassat_proof_text(result)
  out = ""
  if result["status"] == -1 && result["complete"] == true && result["proof_mode"] == WASSAT_PROOF_WRAT && !result["proof"].empty?
    out = "wrat 1\n" + result["proof"].join("\n") + "\n"
  out

# Render the same proof as plain .drat: drop the clause id and the hint
# chain, keeping the clauses in order. Any DRAT checker accepts this, at
# the cost of making it search for the propagations the hints named.
-> wassat_drat_text(result)
  out = ""
  valid_mode = result["proof_mode"] == WASSAT_PROOF_DRAT || result["proof_mode"] == WASSAT_PROOF_WRAT
  if result["status"] == -1 && result["complete"] == true && valid_mode
    raw = result["drat"]
    unless raw == nil || raw.empty?
      out = raw.join("\n") + "\n"
    else
      # A hinted solve can still be rendered for DRAT interoperability by
      # dropping its ids and hints. Addition steps only: a WRAT deletion
      # names clause ids, whose literal content is not recoverable from the
      # proof text alone, which is why deletion-bearing runs emit both
      # dialects natively at log time instead of converting after the fact.
      lines = []
      result["proof"].each -> (line)
        toks = wassat_tokenize(line)
        raise "cannot render WRAT deletion step as DRAT after the fact: [line]" if toks.size > 1 && toks[1] == "d"
        lits = []
        i = 1
        while i < toks.size
          break if toks[i] == "0"
          lits.push(toks[i])
          i += 1
        lines.push(lits.empty? ? "0" : lits.join(" ") + " 0")
      out = lines.join("\n") + "\n" unless lines.empty?
  out

# Render a solver result in DIMACS competition output format.
-> wassat_result_text(result)
  if result["status"] == 1
    "s SATISFIABLE\nv " + result["model"].join(" ") + " 0\n"
  elsif result["status"] == 0
    "s UNKNOWN\n"
  else
    "s UNSATISFIABLE\n"

# Native model scan over the parser's flat arrays: every clause must have
# a literal agreeing with the sign array. Returns via pm[0].
-> wassat_verify_flat(slits, soffs, slens, sign, pm) (i64[] i64[] i64[] i64[] i64[])
  ncl = pm[1]
  ok = 1
  k = 0
  while k < ncl && ok == 1
    o = soffs[k]
    n = slens[k]
    hit = 0
    j = 0
    while j < n
      l = slits[o + j]
      av = l
      want = 1
      if l < 0
        av = 0 - l
        want = -1
      if sign[av] == want
        hit = 1
        j = n
      else
        j = j + 1
    if hit == 0
      ok = 0
    k = k + 1
  pm[0] = ok
  0

# Output-integrity guard: does the model satisfy every clause of the formula?
# Every SAT answer must pass this scan against the ORIGINAL formula before it
# is reported, whichever engine produced it. UNSAT has independent checkers;
# this is the SAT side of that symmetry.
-> wassat_model_satisfies?(formula, model)
  # formulas from the native parser carry flat arrays — scan those natively
  if formula.has_key?("flat_ncl")
    nv2 = formula["nvars"]
    sign = i64[nv2 + 1]
    model.each -> (l)
      v = l.abs
      sign[v] = l > 0 ? 1 : -1 if v >= 1 && v <= nv2
    pm = i64[2]
    pm[1] = formula["flat_ncl"]
    wassat_verify_flat(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], sign, pm)
    return pm[0] == 1
  nv = formula["nvars"]
  sign = i64[nv + 1]
  model.each -> (l)
    v = l.abs
    sign[v] = l > 0 ? 1 : -1 if v >= 1 && v <= nv
  ok = true
  formula["clauses"].each -> (c)
    hit = false
    c.each -> (l)
      want = l > 0 ? 1 : -1
      hit = true if sign[l.abs] == want
    ok = false unless hit
  ok

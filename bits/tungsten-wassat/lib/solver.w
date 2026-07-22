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
# Watch lists are intrusive singly-linked lists threaded through `@wnext`:
# each clause owns two watcher slots (`2*ci` and `2*ci+1`), so adding or
# moving a watch is a pointer write with no allocation.
#
# PROOFS
#
# Proof logging is opt-in. Raw DRAT records each learned RUP clause directly.
# Hinted WRAT additionally REPLAYS the propagation a checker will perform for
# every learned clause. That is slower than reconstructing hints from solver
# state but correct by construction: the emitted chain is literally the
# sequence the checker is about to follow.

UNASSIGNED = 0

# Minimum conflicts between restarts. See the restart block in `solve_loop`.
WASSAT_MIN_RESTART_INTERVAL = 16384
WASSAT_PROOF_NONE = 0
WASSAT_PROOF_WRAT = 1
WASSAT_PROOF_DRAT = 2

+ Wassat
  -> new(@nvars, @input_clauses, @proof_mode, @lookahead)
    nv = @nvars
    @assign = i64[nv + 1]        # 0 unassigned, 1 true, -1 false
    @level = i64[nv + 1]
    @reason = i64[nv + 1]        # clause index, or -1 for a decision
    @seen = i64[nv + 1]
    @phase = i64[nv + 1]         # saved polarity: 1 or -1
    @activity = i64[nv + 1]      # scaled integer VSIDS score
    @heap = i64[nv + 1]          # max-heap of branching variables
    @heappos = i64[nv + 1]       # variable -> heap slot, -1 when absent
    @hstate = i64[2]              # heap size / EVSIDS increment
    @rassign = i64[nv + 1]       # isolated scratch assignment for proof replay
    @pstate = i64[4]             # qhead / tsize / conflict across the native call
    @astate = i64[6]             # scalars across the native analyze call
    @lbuf = i64[nv + 3]          # learned clause, reused every conflict
    @obuf = i64[nv + 3]          # watch-ordered copy of the learned clause
    @mbuf = i64[nv + 3]          # minimisation scratch
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
    @restart_budget = 100
    @since_restart = 0
    # Glucose-style adaptive restart state. A fixed schedule is a guess about
    # how fast the search is learning; these two moving averages measure it.
    @lbd_win = i64[64]           # recent LBDs, circular
    @lbd_wi = 0
    @lbd_wsum = 0
    @lbd_wcount = 0
    @lbd_gsum = 0
    @lbd_gcount = 0
    @trail_win = i64[512]        # recent trail sizes, circular
    @trail_wi = 0
    @trail_wsum = 0
    @trail_wcount = 0
    @reductions = 0
    @next_reduce = 1500

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
    @gid = i64[maxcl]            # clause index -> global proof id
    @ccap = maxcl
    @ncl = 0

    # watch lists: 2*(nv+1) literal slots
    @wfirst = i64[2 * nv + 4]
    i = 0
    while i < 2 * nv + 4
      @wfirst[i] = -1
      i += 1
    @wnext = i64[2 * maxcl]
    @wblock = i64[2 * maxcl]     # cached literal per watcher (see propagate)
    i = 0
    while i < 2 * maxcl
      @wnext[i] = -1
      @wblock[i] = 0
      i += 1

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
      gd = i64[ncap]
      wn = i64[2 * ncap]
      wb = i64[2 * ncap]
      i = 0
      while i < @ncl
        cs[i] = @cstart[i]
        cl[i] = @clen[i]
        al[i] = @alive[i]
        lb[i] = @clbd[i]
        gd[i] = @gid[i]
        i += 1
      i = 0
      while i < 2 * @ncl
        wn[i] = @wnext[i]
        wb[i] = @wblock[i]
        i += 1
      i = 2 * @ncl
      while i < 2 * ncap
        wn[i] = -1
        wb[i] = 0
        i += 1
      @cstart = cs
      @clen = cl
      @alive = al
      @clbd = lb
      @gid = gd
      @wnext = wn
      @wblock = wb
      @ccap = ncap
    0

  # Attach watcher slot `slot` of clause `ci` to the list of literal `l`,
  # caching `blocker` -- any other literal of the clause. If the blocker is
  # already true the clause is satisfied and propagation can skip it without
  # reading the clause body at all.
  -> watch(ci, slot, l, blocker)
    w = 2 * ci + slot
    li = self.lit_index(l)
    @wnext[w] = @wfirst[li]
    @wblock[w] = blocker
    @wfirst[li] = w
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
    if n >= 2
      self.watch(ci, 0, @arena[@cstart[ci]], @arena[@cstart[ci] + 1])
      self.watch(ci, 1, @arena[@cstart[ci] + 1], @arena[@cstart[ci]])
    ci

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
      self.enqueue(c[0], -1) if self.value(c[0]) == 0
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
    wassat_propagate(@arena, @assign, @level, @reason, @phase, @wfirst,
                     @wnext, @wblock, @cstart, @clen, @trail, @pstate, @dlevel)
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
    wassat_analyze(@arena, @assign, @level, @reason, @seen, @cstart, @clen,
                   @trail, @lbuf, @mbuf, @activity, @heap, @heappos,
                   @hstate, @astate, @nvars)
    @lsize = @astate[3]
    @astate[4]

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
  -> pick_branch
    wassat_heap_pick(@assign, @heap, @heappos, @activity, @hstate)

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
    v = 0
    while v <= @nvars
      @rassign[v] = 0
      v += 1

    record = []
    conflict = false
    i = 0
    while i < lits.size
      l = lits[i]
      if self.replay_value(l) > 0
        conflict = true
      else
        @rassign[l.abs] = l > 0 ? -1 : 1      # assert the negation
      i += 1

    unless conflict
      changed = true
      while changed && !conflict
        changed = false
        ci = 0
        while ci < @ncl && !conflict
          # Proof replay uses the logical proof database, not the reduced
          # search database. reduce_db only detaches clauses from propagation;
          # it emits no deletion steps, so the independent checker still has
          # every input and learned clause at its original `ci + 1` id.
          st = @cstart[ci]
          n = @clen[ci]
          sat = false
          unassigned = 0
          unit = 0
          j = 0
          while j < n
            l = @arena[st + j]
            val = self.replay_value(l)
            if val > 0
              sat = true
              j = n
            else
              if val == 0
                unassigned += 1
                unit = l
              j += 1
          unless sat
            if unassigned == 0
              conflict = true
              record.push(@gid[ci])
            elsif unassigned == 1
              @rassign[unit.abs] = unit > 0 ? 1 : -1
              record.push(@gid[ci])
              changed = true
          ci += 1

    # A chain that never reached a conflict does not justify the clause;
    # returning it would emit a proof step no checker can accept.
    conflict ? record : []

  -> log_clause(lits)
    if @proof_mode == WASSAT_PROOF_WRAT
      hints = self.replay_hints(lits)
      # Silently omitting a failed replay is unsound: the learned clause is
      # still inserted into the search database, so later hint ids could name
      # a clause the checker never received. Every first-UIP clause is RUP;
      # failure to reconstruct its chain therefore indicates a solver/proof
      # bug and must stop certificate production loudly.
      raise "internal proof replay failed for learned clause: [lits.join(" ")]" if hints.empty?
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

  # Drop the least useful half of the learned clauses and rebuild the watch
  # lists over the survivors. Only ever called at decision level zero, where
  # no clause is anybody's reason, so nothing in the trail can dangle.
  -> reduce_db
    # histogram LBD values to find a cut that removes about half
    total = 0
    hist = i64[64]
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

    # keep binaries and anything below the cut; drop the rest
    ci = 0
    while ci < @ncl
      if @alive[ci] == 1 && @clbd[ci] >= cut && @clen[ci] > 2 && @clbd[ci] > 2
        @alive[ci] = 0
      ci += 1

    # rebuild watches from scratch over the survivors
    i = 0
    while i < 2 * @nvars + 4
      @wfirst[i] = -1
      i += 1
    ci = 0
    while ci < @ncl
      if @alive[ci] == 1 && @clen[ci] >= 2
        st = @cstart[ci]
        self.watch(ci, 0, @arena[st], @arena[st + 1])
        self.watch(ci, 1, @arena[st + 1], @arena[st])
      ci += 1
    0

  # ---- search -------------------------------------------------------------

  -> solve_loop(stop_conflicts)
    result = 0                       # 0 unknown, 1 sat, -1 unsat
    limited = false

    while result == 0 && !limited
      confl = self.propagate
      if confl >= 0
        @conflicts += 1
        @since_restart += 1
        if @dlevel == 0
          self.log_clause([])
          result = -1
        else
          target = self.analyze(confl)
          n = @lsize
          lbd = self.compute_lbd_buf(n)
          self.log_learned(n)
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
          # Feed both moving averages: the recent window drives restarts, the
          # global mean is the yardstick it is compared against.
          @lbd_gsum += lbd
          @lbd_gcount += 1
          if @lbd_wcount >= 64
            @lbd_wsum -= @lbd_win[@lbd_wi]
          else
            @lbd_wcount += 1
          @lbd_win[@lbd_wi] = lbd
          @lbd_wsum += lbd
          @lbd_wi = (@lbd_wi + 1) % 64
          if @trail_wcount >= 512
            @trail_wsum -= @trail_win[@trail_wi]
          else
            @trail_wcount += 1
          @trail_win[@trail_wi] = @tsize
          @trail_wsum += @tsize
          @trail_wi = (@trail_wi + 1) % 512
          wassat_evsids_advance(@hstate)
          if stop_conflicts > 0 && @conflicts >= stop_conflicts
            limited = true
      else
        # Restart when the recent window of learned-clause LBDs is markedly
        # worse than the running average -- the search has stopped learning
        # usefully. Blocked by a trail that is much deeper than usual, which
        # means we are plausibly closing in on a model and a restart would
        # throw that progress away. A fixed schedule got this badly wrong:
        # restarting every few hundred conflicts cost 8x the conflicts on
        # satisfiable BMC instances and 4x on hard random UNSAT.
        # Two gates. The LBD comparison decides *whether* learning has stalled;
        # the interval floor decides how often we are willing to act on it.
        #
        # The floor is large, and that is a measured choice rather than a
        # default. Restarting every few hundred conflicts (the previous
        # schedule) cost 8x the conflicts on satisfiable BMC instances and 4x
        # on hard random UNSAT; a pure LBD trigger and a 3000-conflict floor
        # were both still far too eager. Frequent restarts pay off in modern
        # solvers because they are paired with target phases and rephasing, so
        # a restart resumes near where it left off. With only basic phase
        # saving a restart genuinely discards progress, so this solver should
        # restart rarely until that machinery exists.
        want_restart = false
        if @since_restart >= WASSAT_MIN_RESTART_INTERVAL
          if @lbd_wcount >= 64 && @lbd_gcount > 0
            if @lbd_wsum * 8 * @lbd_gcount > @lbd_gsum * 64 * 10
              want_restart = true
        # Blocking compares against a RECENT trail average, not a global one:
        # a lifetime mean drifts stale and stops recognising that the search is
        # currently running deep, which is exactly when a restart is most
        # destructive on satisfiable instances.
        if want_restart && @trail_wcount >= 512
          if @tsize * 10 * @trail_wcount > @trail_wsum * 14
            want_restart = false          # blocked: unusually deep trail
        if want_restart
          @since_restart = 0
          @restart_count += 1
          @lbd_wsum = 0
          @lbd_wcount = 0
          @lbd_wi = 0
          self.backjump(0)
          # Learned clauses are only useful while they are cheap to walk;
          # periodically drop the high-LBD half so propagation stays fast.
          if @conflicts > @next_reduce
            @next_reduce = @conflicts + 1500 + 250 * @reductions
            @reductions += 1
            self.reduce_db
        else
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

  -> solve
    self.solve_budget(0)

  # Build a detached result. Arrays returned by an earlier call must not gain
  # proof steps, lose a model, or otherwise change when the same solver resumes.
  -> result_for(status)
    sat = status == 1
    unsat = status == -1
    model = []
    if sat
      v = 1
      while v <= @nvars
        model.push(@assign[v] >= 0 ? v : 0 - v)
        v += 1

    proof = []
    drat = []
    proof = @proof.dup if unsat && @proof_mode == WASSAT_PROOF_WRAT
    drat = @drat.dup if unsat && (@proof_mode == WASSAT_PROOF_DRAT || @dual_drat)
    { "sat": sat, "unsat": unsat, "complete": status != 0,
      "status": status, "model": model, "proof": proof, "drat": drat,
      "proof_mode": @proof_mode,
      "conflicts": @conflicts, "decisions": @decisions_made,
      "restarts": @restart_count, "reduces": @reductions }

  # A positive conflict budget is additional work for this call. Returning
  # UNKNOWN preserves the trail, learned database, restart cadence, and hidden
  # proof prefix so a later call can continue safely. Zero is unlimited.
  -> solve_budget(max_conflicts)
    raise "conflict budget must be non-negative, got [max_conflicts]" if max_conflicts < 0
    return self.result_for(@terminal_status) unless @terminal_status == 0

    status = -1
    if @ok
      stop_conflicts = 0
      stop_conflicts = @conflicts + max_conflicts if max_conflicts > 0
      status = self.solve_loop(stop_conflicts)
    else
      self.log_clause([]) unless @refuted

    @terminal_status = status unless status == 0
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
-> wassat_propagate(ar, asg, lvl, rsn, phs, wf, wn, wb, cs, cln, tr, st, dl) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64)
  qhead = st[0]
  tsize = st[1]
  conflict = -1
  while qhead < tsize && conflict < 0
    p = tr[qhead]
    qhead += 1
    neg = 0 - p
    # literal index, written without a ternary: conditional expressions box
    li = 0
    if neg > 0
      li = neg << 1
    else
      li = ((0 - neg) << 1) + 1
    prev = -1
    w = wf[li]
    while w >= 0 && conflict < 0
      nxt = wn[w]
      blk = wb[w]
      bv = 0
      if blk > 0
        bv = asg[blk]
      else
        bv = 0 - asg[0 - blk]
      if bv > 0
        prev = w
        w = nxt
      else
        ci = w >> 1
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
          wb[w] = other
          prev = w
          w = nxt
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
            if prev < 0
              wf[li] = nxt
            else
              wn[prev] = nxt
            ri = 0
            if repl > 0
              ri = repl << 1
            else
              ri = ((0 - repl) << 1) + 1
            wn[w] = wf[ri]
            wb[w] = other
            wf[ri] = w
            w = nxt
          else
            wb[w] = other
            prev = w
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
            else
              conflict = ci
            w = nxt
  st[0] = qhead
  st[1] = tsize
  st[2] = conflict
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
-> wassat_analyze(ar, asg, lvl, rsn, sn, cs, cln, tr, out, tmp, act, heap, hpos, hst, st, nv) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64)
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
    stx = cs[cl]
    n = cln[cl]
    j = 1
    if p == 0
      j = 0
    while j < n
      q = ar[stx + j]
      vq = q
      if q < 0
        vq = 0 - q
      if sn[vq] == 0 && lvl[vq] > 0
        sn[vq] = 1
        # MiniSat-style EVSIDS bumps the whole conflict graph as it is first
        # discovered, not merely the literals surviving minimisation. The
        # latter throws away precisely the variables whose reasons explain a
        # conflict and produced noticeably poorer branching on structured
        # quotient formulas.
        z = wassat_evsids_bump(act, heap, hpos, hst, vq, nv)
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

  # Self-subsuming minimisation: drop literals whose reason clause is already
  # covered by the clause. Results go to `tmp` rather than compacting `out`
  # in place -- compaction would overwrite entries still needed to clear the
  # marks of the literals it removed, silently corrupting later analyses.
  keep = 1
  i = 1
  while i < size
    q = out[i]
    vq = q
    if q < 0
      vq = 0 - q
    r = rsn[vq]
    redundant = 0
    if r >= 0
      redundant = 1
      stx = cs[r]
      n = cln[r]
      k = 1
      while k < n
        lk = ar[stx + k]
        vk = lk
        if lk < 0
          vk = 0 - lk
        if sn[vk] == 0 && lvl[vk] > 0
          redundant = 0
        k += 1
    if redundant == 0
      tmp[keep] = q
      keep += 1
    i += 1

  # clear every mark we set, using the untouched original literals
  i = 1
  while i < size
    q = out[i]
    vq = q
    if q < 0
      vq = 0 - q
    sn[vq] = 0
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
-> wassat_heap_pick(asg, heap, hpos, act, hst) (i64[] i64[] i64[] i64[] i64[]) i64
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

# Output-integrity guard: does the model satisfy every clause of the formula?
# Every SAT answer must pass this scan against the ORIGINAL formula before it
# is reported, whichever engine produced it. UNSAT has independent checkers;
# this is the SAT side of that symmetry.
-> wassat_model_satisfies?(formula, model)
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

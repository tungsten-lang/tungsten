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

use cnf
use policy
use atomic_stop

WASSAT_PRE_PROBE_CAP = 2000
WASSAT_PRE_OCC_PRODUCT_CAP = 4096
WASSAT_PRE_MAX_PASSES = 10
WASSAT_PRE_PROBE_TICKS = 2000000
WASSAT_PRE_BUCKET_CAP = 1024

# Physical capacities of the reusable BVE scratch.  These are memory-layout
# facts, not experiment knobs: native scans must never be told that either
# typed array is larger than the allocation below.  Resolvent volume and
# resolvent count are independent bounds because one is packed into
# @bve_out, while every distinct resolvent consumes one slot in BOTH
# @bve_hash and @bve_hpos.
WASSAT_PRE_BVE_OUT_CAPACITY = 131072
WASSAT_PRE_BVE_HASH_CAPACITY = 8192

# Ticks one native subsumption chunk may retire before it returns to the
# driver, so that the tick budget and the wall deadline get a say. Without
# it a chunk ends only when the clause range or the 4000-survivor output
# budget does, and on a formula with few subsumption hits that is the WHOLE
# range in one uninterruptible call: 4pipe spends 1.9s and blocks-4-ipc5-h21
# 95 seconds and 139 billion ticks inside a single one, where no budget,
# deadline or signal can reach it.
#
# Native subsumption retires roughly 1.5 billion ticks a second, so 2M is
# about 1.5ms of work per chunk — fine enough that the 1500ms stage deadline
# binds to within a thousandth of itself, coarse enough that the per-chunk
# driver overhead (one clock read and a re-entry) stays in the noise. The
# chunk boundary is free: pm[6] already reports where to resume, because the
# output budget always could stop a chunk early.
WASSAT_PRE_SUB_CHUNK_TICKS = 2000000

# Clauses the substitution rewrite may walk between budget checks. It used
# to check once per SCC class, and a class can own most of the formula:
# on blocks-4-ipc5-h21 (906k clauses) that overshot the 1500ms stage
# deadline to 2307ms, and with the deadline lifted the rewrite ran for 407
# SECONDS without ever consulting a budget. Checking every 256 clauses
# brings it to 1412ms against the same 1500ms deadline, and amortises the
# clock read to nothing.
#
# Worth recording, because it is why the DEADLINE and not the tick budget is
# what bounds this pass: `@ticks += arr.size` under-charges the rewrite by
# about three orders of magnitude. The 407s run retired only a few million
# ticks against a 16M allowance — the boxed cost per clause (materialise the
# literal array, O(n^2) dedup, store, delete, emit hints) is nowhere near
# proportional to the clause's length. Re-calibrating the tick currency would
# invalidate every tick figure quoted in policy.w, so the deadline stays the
# mechanism, exactly as wassat_pre_stage_ms says it is.
WASSAT_PRE_SUBST_CHECK_EVERY = 256

# Exact binary-AND definition elimination.  The recognizer is intentionally
# bounded: a missed gate only forgoes a reduction, while an accepted gate is
# eliminated with the complete definition-aware resolvent basis described in
# `try_eliminate_and2`.  The candidate cap bounds scratch memory at about
# 3.2MB (four i64 words per candidate).
WASSAT_PRE_AND2_CANDIDATE_CAP = 100000
WASSAT_PRE_AND2_BASE_SCAN_CAP = 256
WASSAT_PRE_AND2_SIDE_SCAN_CAP = 4096
WASSAT_PRE_AND2_PAIR_CAP = 4096
WASSAT_PRE_AND2_OCC_SCAN_CAP = 262144
WASSAT_PRE_AND2_FIND_TICK_CAP = 64000000
WASSAT_PRE_AND2_MAX_NVARS = 2000000
WASSAT_PRE_AND2_MAX_CLAUSES = 2000000

+ WassatPreprocess
  # `flat` is the parser formula Hash or nil. With it, the constructor takes
  # its counts from the flat mirrors and never touches the boxed clause list --
  # only `intake` (the certificate path) genuinely needs boxed clauses, and it
  # materializes them on demand.
  -> new(@nvars, @input_clauses, @proof_mode, flat_in)
    # Only a formula that actually carries the parser's flat mirrors counts as
    # a flat source; the boxed parser produces neither. Checking here rather
    # than trusting call sites -- passing a boxed formula as `flat` crashed the
    # proof portfolio with "expected int, got nil" until this guard existed.
    flat = flat_in
    flat = nil if flat != nil && !flat.has_key?("flat_ncl")
    @flat = flat
    nv = @nvars
    @config = flat == nil ? WassatConfig.new(@nvars, @input_clauses) : WassatConfig.from_lens(@nvars, flat["flat_lens"], flat["flat_ncl"])
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
    if flat == nil
      @input_clauses.each -> (c)
        total += c.size
      @ncl_in = @input_clauses.size
    else
      total = flat["flat_nlits"]
      @ncl_in = flat["flat_ncl"]
    @fccap = 2 * @ncl_in + 4 * nv + 1024
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
    @deadline_ms = 0             # 0 = no wall-clock stop (see set_deadline_ms)
    @stop_cell = nil             # shared portfolio cancellation flag
    @probe_cap = WASSAT_PRE_PROBE_CAP
    # Clauses the substitution rewrite has walked, across every variable and
    # every class of the whole pass. It has to span calls: a class is a list
    # of variables and most of them own only a handful of occurrences, so a
    # counter reset per variable would leave the budget unchecked exactly on
    # the formulas made of many small classes — which is the shape that runs
    # for minutes.
    @rewrite_seen = 0
    # BVE growth margin, raised per pass (CaDiCaL-style elimination
    # rounds): Sinz-counter registers — the whole encoding layer of
    # cardinality instances — cost ONE extra literal to eliminate and a
    # zero-growth bound rejects every one of them. Measured on the k=5
    # Lonely Runner class: margin 0 eliminated 44 variables, the pass-2
    # margin unlocked 573 of 976 (CaDiCaL's inprocessing gets 596).
    @bve_margin = 0
    # Experiment overrides are process environment, so read and validate
    # them once per preprocessor rather than once per pivot in run_bve's hot
    # loop.  -1 means the automatic per-pass margin remains in force.
    @bve_margin_override = wassat_bve_margin_override(-1)
    @bve_occ_cap = wassat_bve_occ_cap_override(WASSAT_PRE_OCC_PRODUCT_CAP)
    @bve_out_cap = wassat_bve_outcap_override(WASSAT_PRE_BVE_OUT_CAPACITY)

    # stats
    @probes_run = 0
    @probes_failed = 0
    @hbr_added = 0
    @vars_substituted = 0
    @clauses_subsumed = 0
    @clauses_strengthened = 0
    @vars_eliminated = 0
    @and2_candidates = 0
    @and2_eliminated = 0
    @and2_done = false

    # native-call scratch
    @pst = i64[4]                # qhead / tsize / conflict / ticks
    @subscan_pm = i64[10]
    @subscan_out = i64[16384]    # survivor triples: 3 slots each + header
    @bve_pm = i64[13]
    @bve_out = i64[WASSAT_PRE_BVE_OUT_CAPACITY]
                                 # packed: [len, aci, bci, lits...]*
    @bve_hash = i64[WASSAT_PRE_BVE_HASH_CAPACITY]
                                 # per-candidate dedup hashes (bucket)
    @bve_hpos = i64[WASSAT_PRE_BVE_HASH_CAPACITY]
                                 # header offsets; hash hits confirm exact sets

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
    @force_full = false
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
    lits = parse["flat_lits"] ## i64[]
    offs = parse["flat_offs"] ## i64[]
    lens = parse["flat_lens"] ## i64[]
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
    return nil if self.cancelled
    # Raw-kernel policy, measured on the bmc family: on big structured
    # instances substitution made search HARDER (ibm-12: 12.2k conflicts on
    # the substituted kernel, 6.5k after heavy repair, 4.9k raw) and every
    # pipeline phase was pure overhead on top. Modern-solver shape: large
    # inputs go straight to CDCL; preprocessing effort belongs to small
    # kernels where it is cheap and provably shrinks search (php, dubois,
    # and compact Sinz chains). The choice is deterministic from task shape.
    # The budgeted trial (see lib/wassat.w) needs the FULL pipeline —
    # probing and substitution are exactly what pays on the crypto and
    # bitvector families — so it forces this off. Without it the trial
    # runs a no-op and always falls back.
    raw = @config.raw_kernel? && !@force_full
    @raw_kernel = raw
    self.run_probing if @status == 0 && !raw
    tp = wassat_prof("pre.probing", tp)
    return nil if self.cancelled
    self.run_substitution if @status == 0 && !raw
    tp = wassat_prof("pre.substitution", tp)
    return nil if self.cancelled
    self.sweep_satisfied if @status == 0
    tp = wassat_prof("pre.sweep", tp)
    return nil if self.cancelled
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

  -> force_full_pipeline
    @force_full = true
    0

  -> set_budget(ticks)
    @tick_budget = ticks
    0

  # Stop this run `ms` milliseconds from now, whatever the tick budget says.
  #
  # A backstop for one specific failure: a tick is not proportional to time.
  # Substitution charges one tick per rewritten literal but pays, per clause,
  # for boxed materialization, an O(n^2) duplicate check, a store, a delete,
  # occurrence-list surgery and proof bookkeeping. On most formulas that
  # constant is stable and the tick budget bounds the pass; on the planning
  # kernel blocks-4-ipc5-h21 it collapses to ~270k ticks a second against a
  # healthy ~20M, so a 16M-tick allowance buys 59 SECONDS. No tick cap
  # separates the two — 16M is under what bmc-ibm-2004-03-k70 legitimately
  # spends — so time is bounded directly.
  #
  # Only the racing renderings set this. The certificate path (`run`) leaves
  # it at 0 and stays deterministic; here the deadline can only cost the
  # race an arm's head start, never a verdict.
  -> set_deadline_ms(ms)
    @deadline_ms = ms <= 0 ? 0 : ccall("__w_clock_ms") + ms
    0

  # A portfolio answer makes a losing rendering disposable.  The same shared
  # cell already stops every search arm; preprocessing checks it at its
  # bounded technique/chunk boundaries so the coordinator's join is not held
  # behind work whose artifact can no longer win.  Five-run interleaved
  # medians on raw-winning rows: bmc-ibm-12 0.785s -> 0.465s and ibm-k70
  # 0.843s -> 0.580s; the MD5 preprocessed winner stayed neutral at 0.373s.
  -> set_stop_cell(cell)
    @stop_cell = cell
    0

  -> cancelled
    wassat_stop_requested?(@stop_cell)

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
    self.boxed_input.each -> (c)
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
      # HYPER-BINARY RESOLUTION. A probe that does not fail still proved
      # something: every literal `m` on the probe segment satisfies
      # F & lit |= m, so (-lit | m) is implied by F and is RUP-checkable.
      # Today all of that is thrown away and only failed probes teach.
      #
      # Not every such pair is worth adding -- most are already reachable
      # along binary edges, and adding them would flood the formula. The ones
      # that are NOT redundant are exactly the literals whose reason is a
      # clause of length > 2: a literal derived through a binary clause
      # already has that edge in the implication graph, while one derived
      # through a long clause is a genuinely new edge. That is the strictness
      # filter, computed for free from the reason we already recorded.
      #
      # Why it matters: `substitute_equivalences` finds equivalences as SCCs
      # of the binary implication graph, and on the quasigroup rows it finds
      # ZERO while CaDiCaL substitutes 8-14% of variables. A graph that never
      # gains a derived edge cannot grow an SCC.
      added = 0
      cap = wassat_pre_hbr_cap
      if cap > 0 && @status == 0
        i = mark
        while i < @ftsize && added < cap
          m = @ftrail[i]
          rci = @preason[m.abs]
          if rci >= 0 && @falive[rci] == 1 && @fcl[rci] > 2
            bin = [0 - lit, m]
            gid = @next_gid
            self.plog_add(gid, bin, [])
            z = self.store(bin)
            @hbr_added += 1
            added += 1
          i += 1
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
    return false if self.cancelled
    return false if @deadline_ms > 0 && ccall("__w_clock_ms") >= @deadline_ms
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
    tsub = wassat_prof_clock
    adj = self.build_binary_graph
    tsub = wassat_prof("pre.subst.graph", tsub)
    comp = self.tarjan(adj)
    tsub = wassat_prof("pre.subst.tarjan", tsub)

    # group literals by component
    groups = {}
    node = 2
    while node < 2 * @nvars + 2
      if comp[node] >= 0
        key = comp[node]
        groups[key] = [] unless groups.has_key?(key)
        groups[key].push(node)
      node += 1
    tsub = wassat_prof("pre.subst.group", tsub)

    groups.each -> (key, members)
      if @status == 0 && members.size > 1 && self.within_budget
        self.substitute_class(adj, comp, members)
    tsub = wassat_prof("pre.subst.rewrite", tsub)
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
    finished = true
    lits_of.each -> (y)
      yv = y.abs
      if @replit[yv] != 0 && @status == 0 && finished
        finished = self.rewrite_occurrences(yv, binid_fwd[yv], binid_back[yv])

    # Every citation of the helpers has been emitted; retiring them now is a
    # pure deletion. Eager unit derivation has already re-pointed @preason
    # away from any helper that propagated during the rewrite cascades.
    #
    # NOT when the rewrite was interrupted. An unfinished class leaves its
    # members in live clauses, and then the helper binaries are the only
    # remaining statement that y == rep — delete them and the reconstruction
    # stack's `subst` replay would overwrite a variable the search had
    # decided independently, which is a wrong model, not a slower one.
    # Keeping them costs two binaries per member and is exactly sound:
    # @gone == 2 only withdraws a variable from BVE candidacy (see
    # bve_candidate), it never asserts the variable occurs nowhere. The
    # marks stay set with them so no later class can rewrite one away.
    if finished
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
  #
  # Returns false when the tick budget or the wall deadline stopped it part
  # way, which the caller must not treat as a completed class — see
  # substitute_class. The check is per clause (amortised over
  # WASSAT_PRE_SUBST_CHECK_EVERY of them, since it reads the clock) rather
  # than per class, because a class can own most of the formula and the
  # per-class check then arrives minutes late.
  -> rewrite_occurrences(yv, gid_fwd, gid_back)
    r = @replit[yv]
    two = [2 * yv, 2 * yv + 1]
    done = true
    two.each -> (li)
      w = @oh[li]
      while w >= 0 && done
        ci = @ov[w]
        @rewrite_seen += 1
        if @rewrite_seen % WASSAT_PRE_SUBST_CHECK_EVERY == 0
          done = false unless self.within_budget
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
    done

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
      @subscan_pm[7] = WASSAT_PRE_SUB_CHUNK_TICKS
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

  # Recognize exact binary AND definitions and eliminate their output before
  # general subsumption consumes the heavy-pass budget.
  #
  # For an output literal `o` and inputs `a,b`, the definition is:
  #
  #   (o | -a | -b)  (-o | a)  (-o | b)
  #
  # Other clauses may mention either polarity of `o`.  Full BVE would cross
  # every positive occurrence with every negative occurrence.  The definition
  # makes the non-gate/non-gate cross-products redundant: it is sufficient to
  # resolve every non-gate `(o | P)` with both binary sides, and the base with
  # every non-gate `(-o | N)`.  If P is false, the first pair forces a and b;
  # the base/N resolvent then forces N.  This is the complete Davis-Putnam
  # projection, factored through the gate rather than materialized
  # quadratically.
  #
  # Each emitted clause is still a direct two-parent RUP resolvent.  Additions
  # precede deletions, and the ordinary BVE reconstruction stack records every
  # positive-variable parent, so proof and SAT-model obligations stay exactly
  # the same as `try_eliminate`.
  -> run_and2_bve
    return false if @and2_done
    @and2_done = true
    # An interrupted substitution class deliberately keeps its helper
    # binaries live.  They are reconstruction obligations, not ordinary
    # formula structure, and must not be mistaken for gate sides.
    return false unless @helper_mark.empty?
    return false if @nvars > WASSAT_PRE_AND2_MAX_NVARS
    return false if @ncl > WASSAT_PRE_AND2_MAX_CLAUSES

    cap = @nvars
    cap = WASSAT_PRE_AND2_CANDIDATE_CAP if cap > WASSAT_PRE_AND2_CANDIDATE_CAP
    return false if cap <= 0
    cands = i64[4 * cap + 1]
    pm = i64[8]
    pm[0] = @nvars
    pm[1] = cap
    pm[2] = WASSAT_PRE_AND2_BASE_SCAN_CAP
    pm[3] = WASSAT_PRE_AND2_SIDE_SCAN_CAP
    pm[6] = WASSAT_PRE_AND2_FIND_TICK_CAP
    wassat_pre_find_and2(@fla, @fcs, @fcl, @falive, @ftaut, @oh, @on, @ov,
                         @passign, @gone, @frozen, cands, pm)
    @and2_candidates = pm[4]
    @ticks += pm[5]

    progress = false
    i = 0
    while i < @and2_candidates && @status == 0 && self.within_budget
      base = 4 * i
      if self.try_eliminate_and2(cands[base], cands[base + 1],
                                 cands[base + 2], cands[base + 3])
        progress = true
      i += 1
    wassat_prof_note("pre.and2 candidates=[@and2_candidates] eliminated=[@and2_eliminated] find_ticks=[pm[5]]")
    progress

  -> try_eliminate_and2(out_lit, base_ci, side1_ci, side2_ci)
    v = out_lit.abs
    return false if @frozen[v] == 1 || @passign[v] != 0 || @gone[v] != 0

    @bve_pm[0] = out_lit
    @bve_pm[1] = base_ci
    @bve_pm[2] = side1_ci
    @bve_pm[3] = side2_ci
    @bve_pm[4] = WASSAT_PRE_AND2_PAIR_CAP
    @bve_pm[5] = WASSAT_PRE_BVE_OUT_CAPACITY
    @bve_pm[6] = 0
    @bve_pm[7] = 0
    @bve_pm[8] = 0
    @bve_pm[9] = @lgen
    @bve_pm[10] = WASSAT_PRE_AND2_OCC_SCAN_CAP
    @bve_pm[11] = 0
    @bve_pm[12] = WASSAT_PRE_BVE_HASH_CAPACITY
    wassat_pre_and2_bve_scan(@fla, @fcs, @fcl, @falive, @ftaut, @oh, @on,
                             @ov, @lstamp, @bve_hash, @bve_hpos, @bve_out,
                             @bve_pm)
    @ticks += @bve_pm[8]
    @lgen = @bve_pm[9]
    return false if @bve_pm[6] == 0

    # Snapshot the original pivot clauses before storing any resolvent.
    # Resolvents never contain the pivot, but this also makes the proof and
    # reconstruction ordering explicit.
    pos = self.live_occ(2 * v)
    neg = self.live_occ(2 * v + 1)

    count = @bve_pm[7]
    units = []
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
      if res.size == 1
        units.push(nci)
      off += 3 + n
      i += 1

    @stack.push({ "kind": "bve_var", "pivot": v })
    pos.each -> (ci)
      @stack.push({ "kind": "bve", "pivot": v,
                    "lits": self.lits_of(ci).dup })
    parents = []
    pos.each -> (ci)
      parents.push(ci)
    neg.each -> (ci)
      parents.push(ci)
    self.delete_batch(parents)
    @gone[v] = 1
    @vars_eliminated += 1
    @and2_eliminated += 1
    # Propagate only after every pivot parent is gone.  Otherwise a new unit
    # can make a still-live parent imply the pivot, and derive a replacement
    # unit containing a variable that the artifact already marks eliminated.
    units.each -> (nci)
      if @status == 0
        l = @fla[@fcs[nci]]
        lv = self.value(l)
        if lv < 0
          self.refute(nci)
        elsif lv == 0
          self.assign(l, nci)
          confl = self.propagate_root
          self.refute(confl) if confl >= 0
    true

  # Eliminate v when the set of non-tautological resolvents is no larger
  # than the clauses it replaces, with bounds on literal volume and pairing
  # work. Atomic: either every resolvent is added and every original
  # deleted, or nothing happens.
  -> try_eliminate(v)
    return false if @frozen[v] == 1 || @passign[v] != 0 || @gone[v] != 0
    @bve_pm[0] = v
    @bve_pm[1] = @bve_margin_override < 0 ? @bve_margin : @bve_margin_override
    @bve_pm[2] = @bve_occ_cap
    @bve_pm[3] = @bve_out_cap
    @bve_pm[4] = 0
    @bve_pm[5] = 0
    @bve_pm[6] = WASSAT_PRE_BVE_HASH_CAPACITY
    @bve_pm[7] = 0
    wassat_pre_bve_scan(@fla, @fcs, @fcl, @falive, @ftaut, @oh, @on, @ov,
                        @lstamp, @bve_hash, @bve_hpos, @bve_out, @bve_pm, @lgen)
    @lgen = @bve_pm[8]
    @ticks += @bve_pm[7]
    return false if @bve_pm[4] == 0

    # commit from the packed buffer: all resolvents added, all originals
    # deleted, or nothing — the atomicity contract is unchanged
    count = @bve_pm[5]
    units = []
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
      if res.size == 1
        units.push(nci)
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
    units.each -> (nci)
      if @status == 0
        l = @fla[@fcs[nci]]
        lv = self.value(l)
        if lv < 0
          self.refute(nci)
        elsif lv == 0
          self.assign(l, nci)
          confl = self.propagate_root
          self.refute(confl) if confl >= 0
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
    return nil if self.cancelled
    self.sweep_satisfied if @status == 0
    tp = wassat_prof("pre.heavy_sweep", tp)
    return nil if self.cancelled
    art = self.artifact
    tp = wassat_prof("pre.heavy_artifact", tp)
    art

  -> init_budget
    # Probing gets a fixed slice; encoding-scale instances get a deeper
    # budget for the margin rounds (see run).
    if @tick_budget == 0
      if @ncl_in <= 20000
        @tick_budget = 400 * self.total_literals + 40000000
      else
        @tick_budget = 200 * self.total_literals + 10000000
    0

  -> heavy_rounds
    # Gate definitions are cheap, exact structure.  Run them before the
    # quadratic candidate scans: on spg_200_301 the old ordering spent the
    # bounded heavy allowance in subsumption before ordinary BVE reached
    # roughly sixty thousand removable definitions.  The bounded pass removes
    # 59,502 variables there in a 321ms heavy round; three interleaved solves
    # moved the median from 117.32s to 83.62s (all new runs 82.14--84.07s).
    self.run_and2_bve if @status == 0 && self.within_budget
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
      progress = false if passes >= 1 && @ncl_in > 20000
      passes += 1
    0

  -> run
    self.init_budget
    # The CLI parser already owns a complete flat rendering.  Reuse it in
    # certificate mode too: intake_flat assigns the same sequential axiom
    # ids, records the same root reasons, and materializes boxed clauses
    # lazily through lits_of when proof construction actually needs them.
    #
    # Besides avoiding one Array allocation per input clause, this is required
    # by the native CLI: eagerly materializing the parser's lazy clauses and
    # feeding them through the intake block SIGBUSed inside store() in compiled
    # proof runs. The typed flat mirrors are pinned for the preprocessor's
    # lifetime and avoid that unsafe boxed hand-off.
    if @flat == nil
      self.intake
    else
      self.intake_flat(@flat)
    self.run_probing if @status == 0
    self.run_substitution if @status == 0
    self.heavy_rounds
    self.sweep_satisfied if @status == 0
    self.artifact

  # Boxed input clauses, materialized only if something actually needs them.
  -> boxed_input
    return @input_clauses if @flat == nil
    wassat_formula_clauses(@flat)

  -> total_literals
    return @flat["flat_nlits"] if @flat != nil
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
      "next_gid": @next_gid, "status": @status, "config": @config,
      "stack": @stack, "gone": @gone,
      "fla": @fla, "fcs": @fcs, "fcl": @fcl, "falive": @falive,
      "ftaut": @ftaut, "fpgid": @fpgid, "fncl": @ncl,
      "wrat": @wrat_lines, "drat": @drat_lines,
      "stats": { "probes": @probes_run, "probes_failed": @probes_failed,
                 "vars_substituted": @vars_substituted,
                 "clauses_subsumed": @clauses_subsumed,
                 "clauses_strengthened": @clauses_strengthened,
                 "vars_eliminated": @vars_eliminated,
                 "and2_candidates": @and2_candidates,
                 "and2_eliminated": @and2_eliminated,
                 "ticks": @ticks } }

# Native root-level unit propagation over the flat clause arena and the
# intrusive occurrence lists. Same reasoning as the solver's native helpers:
# typed array parameters keep literal reads raw machine integers.
#
#   st[0] = qhead   st[1] = trail size   st[2] = conflict ci or -1
#   st[3] = accumulated ticks
# Measurement hooks for the two elimination bounds. The margin is resolvent
# growth allowed per pivot (0 = zero-growth); the cap rejects pivots whose
# pos*neg occurrence product exceeds it. qg-family rows eliminate ZERO
# variables under the shipped bounds while CaDiCaL clears ~30% there; these
# pins are how that gets measured without a rebuild per configuration.
-> wassat_bve_margin_override(v)
  return wassat_decimal_in_range("WASSAT_BVE_MARGIN", env("WASSAT_BVE_MARGIN"), 0, 1000000) if env("WASSAT_BVE_MARGIN") != nil
  v

-> wassat_bve_occ_cap_override(v)
  return wassat_decimal_in_range("WASSAT_BVE_OCC_CAP", env("WASSAT_BVE_OCC_CAP"), 1, 2000000000) if env("WASSAT_BVE_OCC_CAP") != nil
  v

# The packed resolvent buffer. NOT a policy knob in disguise: a pivot whose
# resolvents overflow it is rejected atomically (`base + rl >= outcap ->
# feasible = 0`).  The allocation is fixed at
# WASSAT_PRE_BVE_OUT_CAPACITY; an environment experiment may LOWER the
# logical cap but may not pretend the physical buffer grew.  Oversized values
# are rejected loudly instead of turning a margin experiment into unchecked
# native writes.  Raising the physical limit requires changing the allocation
# and both independently bounded hash-position arrays together.
-> wassat_bve_outcap_override(v)
  if env("WASSAT_BVE_OUTCAP") != nil
    return wassat_decimal_in_range(
      "WASSAT_BVE_OUTCAP", env("WASSAT_BVE_OUTCAP"),
      1024, WASSAT_PRE_BVE_OUT_CAPACITY
    )
  v

# Cap on hyper-binary clauses derived per non-failing probe. 0 disables.
-> wassat_pre_hbr_cap
  return wassat_decimal_in_range("WASSAT_HBR", env("WASSAT_HBR"), 0, 1000000) if env("WASSAT_HBR") != nil
  0

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
#   pm[6] next ci out     pm[7] tick cap in (0 = uncapped)
#
# The tick cap is what makes the pass interruptible at all: it is tested
# between subsumers, so a chunk always finishes the one it is on (bounded by
# that clause's length times the bucket cap) and always advances, and the
# driver gets the budget and the deadline back every ~1.5ms instead of once
# per formula.
-> wassat_pre_subpass(fla, fcs, fcl, falive, ftaut, fsig, och, ocn, ocv, ocount, lstamp, out, pm) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[])
  base = pm[0]
  sci = pm[1]
  endci = pm[2]
  cap = pm[3]
  budget = pm[4]
  tcap = pm[7]
  tcap = 9223372036854775807 if tcap <= 0
  ticks = 0
  # `ticks` is the CALIBRATED currency the budgets in policy.w are quoted
  # in, and it is charged only for a candidate that survives to the literal
  # match. That makes it the wrong thing to cut a chunk on: a bucket walk
  # that rejects every candidate retires no ticks at all and would run the
  # whole formula uninterrupted. `work` charges the walk too, so the chunk
  # boundary tracks real time, and it is deliberately kept out of pm[5] so
  # the reported tick counts stay comparable with every number on record.
  work = 0
  count = 0
  while sci < endci && count < budget && work < tcap
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
            work = work + 1
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
              work = work + n
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

# Find exact two-input AND definitions in ascending variable order.
#
# A candidate record is four words:
#
#   [output literal, ternary base clause, binary side 1, binary side 2]
#
# The output literal may be negative.  Candidates are only suggestions: the
# commit scan below revalidates every literal and every clause after earlier
# eliminations.  Scan caps are completeness bounds only; reaching one skips a
# possible gate and can never change the formula.
#
#   pm[0] nvars             pm[1] candidate capacity
#   pm[2] base bucket cap   pm[3] side bucket cap
#   pm[4] count(out)        pm[5] work ticks(out)
#   pm[6] work cap (0 = uncapped)
-> wassat_pre_find_and2(fla, fcs, fcl, falive, ftaut, och, ocn, ocv, asg, gone, frozen, out, pm) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[])
  nv = pm[0]
  cap = pm[1]
  bcap = pm[2]
  scap = pm[3]
  tickcap = pm[6]
  count = 0
  ticks = 0
  v = 1
  while v <= nv && count < cap && (tickcap == 0 || ticks < tickcap)
    if asg[v] == 0 && gone[v] == 0 && frozen[v] == 0
      polarity = 0
      found_gate = 0
      while polarity < 2 && found_gate == 0 && (tickcap == 0 || ticks < tickcap)
        o = v
        if polarity == 1
          o = 0 - v
        oli = v + v
        if o < 0
          oli = oli + 1
        nli = v + v
        if o > 0
          nli = nli + 1
        scanned = 0
        w = och[oli]
        while w >= 0 && scanned < bcap && found_gate == 0 && (tickcap == 0 || ticks < tickcap)
          ci = ocv[w]
          scanned = scanned + 1
          ticks = ticks + 1
          if falive[ci] == 1 && ftaut[ci] == 0 && fcl[ci] == 3
            stx = fcs[ci]
            oc = 0
            qn = 0
            q1 = 0
            q2 = 0
            j = 0
            while j < 3
              l = fla[stx + j]
              if l == o
                oc = oc + 1
              else
                if qn == 0
                  q1 = l
                else
                  q2 = l
                qn = qn + 1
              j = j + 1
            valid = 1
            if oc != 1 || qn != 2
              valid = 0
            if valid == 1
              a1 = q1
              a2 = q2
              if a1 < 0
                a1 = 0 - a1
              if a2 < 0
                a2 = 0 - a2
              if a1 == v || a2 == v || q1 == q2 || q1 == 0 - q2
                valid = 0
            if valid == 1
              s1 = -1
              s2 = -1
              sw = och[nli]
              sscan = 0
              while sw >= 0 && sscan < scap && (s1 < 0 || s2 < 0) && (tickcap == 0 || ticks < tickcap)
                sci = ocv[sw]
                sscan = sscan + 1
                ticks = ticks + 1
                if falive[sci] == 1 && ftaut[sci] == 0 && fcl[sci] == 2
                  sst = fcs[sci]
                  nc = 0
                  other = 0
                  k = 0
                  while k < 2
                    sl = fla[sst + k]
                    if sl == 0 - o
                      nc = nc + 1
                    else
                      other = sl
                    k = k + 1
                  if nc == 1
                    if other == 0 - q1 && s1 < 0
                      s1 = sci
                    elsif other == 0 - q2 && s2 < 0
                      s2 = sci
                sw = ocn[sw]
              if s1 >= 0 && s2 >= 0 && s1 != s2
                base = 4 * count
                out[base] = o
                out[base + 1] = ci
                out[base + 2] = s1
                out[base + 3] = s2
                count = count + 1
                found_gate = 1
          w = ocn[w]
        polarity = polarity + 1
    v = v + 1
  pm[4] = count
  pm[5] = ticks
  0

# Feasibility scan for one exact two-input AND definition.
#
# Instead of the quadratic full cross-product, emit the factored projection:
#
#   each non-base clause containing o   x each binary gate side
#   ternary gate base                  x each non-side clause containing -o
#
# Gate/gate pairs are tautologies.  Non-gate/non-gate pairs follow by
# resolving the clauses above through the two gate inputs, so materializing
# them is redundant.  The boxed driver commits the packed direct resolvents
# add-first/delete-second and uses the ordinary BVE reconstruction records.
#
# Rejected unless the factored basis has no clause growth, at most one extra
# literal (arity - 1), no more than the pair cap, and fits the output buffer.
#
#   pm[0] output literal   pm[1] base ci     pm[2..3] side cis
#   pm[4] pair cap         pm[5] output capacity
#   pm[6] feasible(out)    pm[7] resolvent count(out)
#   pm[8] ticks(out)       pm[9] next generation(in/out)
#   pm[10] occurrence-node cap (0 = uncapped)
#   pm[11] occurrence nodes visited(out)
#   pm[12] hash/header capacity
-> wassat_pre_and2_bve_scan(fla, fcs, fcl, falive, ftaut, och, ocn, ocv, lstamp, hbuf, hpos, out, pm) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[])
  o = pm[0]
  baseci = pm[1]
  side1 = pm[2]
  side2 = pm[3]
  paircap = pm[4]
  outcap = pm[5]
  gen = pm[9]
  occcap = pm[10]
  hashcap = pm[12]
  # The caller passes logical bounds for experiments, but these native loops
  # also defend the actual reusable allocations.  Packed output and
  # hash/header slots are separate resources and are clamped independently.
  outcap = WASSAT_PRE_BVE_OUT_CAPACITY if outcap > WASSAT_PRE_BVE_OUT_CAPACITY
  hashcap = WASSAT_PRE_BVE_HASH_CAPACITY if hashcap > WASSAT_PRE_BVE_HASH_CAPACITY
  pm[6] = 0
  pm[7] = 0
  ticks = 0
  occvisits = 0

  v = o
  if v < 0
    v = 0 - v
  valid = 1
  if baseci == side1 || baseci == side2 || side1 == side2
    valid = 0
  if valid == 1
    if falive[baseci] != 1 || ftaut[baseci] != 0 || fcl[baseci] != 3
      valid = 0
    if falive[side1] != 1 || ftaut[side1] != 0 || fcl[side1] != 2
      valid = 0
    if falive[side2] != 1 || ftaut[side2] != 0 || fcl[side2] != 2
      valid = 0

  # Revalidate the exact definition after earlier candidates may have
  # deleted clauses that shared a gate input/output.
  q1 = 0
  q2 = 0
  if valid == 1
    stx = fcs[baseci]
    oc = 0
    qn = 0
    j = 0
    while j < 3
      l = fla[stx + j]
      if l == o
        oc = oc + 1
      else
        if qn == 0
          q1 = l
        else
          q2 = l
        qn = qn + 1
      j = j + 1
    if oc != 1 || qn != 2
      valid = 0
    if valid == 1
      a1 = q1
      a2 = q2
      if a1 < 0
        a1 = 0 - a1
      if a2 < 0
        a2 = 0 - a2
      if a1 == v || a2 == v || q1 == q2 || q1 == 0 - q2
        valid = 0

  r1 = 0
  r2 = 0
  if valid == 1
    si = 0
    while si < 2 && valid == 1
      sci = side1
      if si == 1
        sci = side2
      sst = fcs[sci]
      nc = 0
      other = 0
      j = 0
      while j < 2
        l = fla[sst + j]
        if l == 0 - o
          nc = nc + 1
        else
          other = l
        j = j + 1
      if nc != 1
        valid = 0
      else
        if si == 0
          r1 = other
        else
          r2 = other
      si = si + 1
    unless (r1 == 0 - q1 && r2 == 0 - q2) || (r1 == 0 - q2 && r2 == 0 - q1)
      valid = 0

  oli = v + v
  if o < 0
    oli = oli + 1
  nli = v + v
  if o > 0
    nli = nli + 1

  # Count the exact old volume and reject duplicated pivots.  A duplicated
  # occurrence would make the intrusive list visit a clause more than once
  # and is outside the reconstruction invariant used by ordinary BVE.
  old_count = 0
  old_lits = 0
  if valid == 1
    side = 0
    while side < 2 && valid == 1
      li = oli
      if side == 1
        li = nli
      w = och[li]
      while w >= 0 && valid == 1
        occvisits = occvisits + 1
        ticks = ticks + 1
        if occcap > 0 && occvisits > occcap
          valid = 0
        ci = ocv[w]
        if valid == 1 && falive[ci] == 1 && ftaut[ci] == 0
          n = fcl[ci]
          pc = 0
          j = 0
          while j < n
            l = fla[fcs[ci] + j]
            av = l
            if av < 0
              av = 0 - av
            if av == v
              pc = pc + 1
            j = j + 1
          if pc != 1
            valid = 0
          old_count = old_count + 1
          old_lits = old_lits + n
        w = ocn[w]
      side = side + 1

  count = 0
  pairs = 0
  new_lits = 0
  off = 0
  phase = 0
  while phase < 3 && valid == 1
    li = oli
    fixed = side1
    if phase == 1
      fixed = side2
    elsif phase == 2
      li = nli
      fixed = baseci
    w = och[li]
    while w >= 0 && valid == 1
      occvisits = occvisits + 1
      ticks = ticks + 1
      if occcap > 0 && occvisits > occcap
        valid = 0
      ci = ocv[w]
      eligible = valid == 1 && falive[ci] == 1 && ftaut[ci] == 0
      if phase < 2
        eligible = false if ci == baseci
      else
        eligible = false if ci == side1 || ci == side2
      if eligible
        pairs = pairs + 1
        if pairs > paircap
          valid = 0
        else
          aci = ci
          bci = fixed
          if phase == 2
            aci = fixed
            bci = ci
          astx = fcs[aci]
          an = fcl[aci]
          bstx = fcs[bci]
          bn = fcl[bci]
          ticks = ticks + an + bn
          gen = gen + 1
          taut = 0
          rl = 0
          hdr = off
          dst = off + 3
          j = 0
          while j < an
            l = fla[astx + j]
            av = l
            if av < 0
              av = 0 - av
            if av != v
              lidx = av + av
              if l < 0
                lidx = lidx + 1
              if lstamp[lidx] != gen
                lstamp[lidx] = gen
                if dst + rl < outcap
                  out[dst + rl] = l
                rl = rl + 1
            j = j + 1
          j = 0
          while j < bn && taut == 0
            l = fla[bstx + j]
            av = l
            if av < 0
              av = 0 - av
            if av != v
              lidx = av + av
              opposite = lidx + 1
              if l < 0
                lidx = lidx + 1
                opposite = lidx - 1
              if lstamp[opposite] == gen
                taut = 1
              else
                if lstamp[lidx] != gen
                  lstamp[lidx] = gen
                  if dst + rl < outcap
                    out[dst + rl] = l
                  rl = rl + 1
            j = j + 1
          if taut == 0
            if dst + rl >= outcap
              valid = 0
            else
              h = 0
              j = 0
              while j < rl
                x = out[dst + j] * 2654435761
                x = x ^ (x >> 13)
                h = h ^ (x * 40503)
                j = j + 1
              h = h ^ rl
              isdup = 0
              j = 0
              while j < count && isdup == 0
                if hbuf[j] == h && out[hpos[j]] == rl
                  prev = hpos[j]
                  same = 1
                  p = 0
                  while p < rl && same == 1
                    hit = 0
                    q = 0
                    while q < rl && hit == 0
                      if out[prev + 3 + q] == out[dst + p]
                        hit = 1
                      q = q + 1
                    if hit == 0
                      same = 0
                    p = p + 1
                  if same == 1
                    isdup = 1
                j = j + 1
              if isdup == 0
                if count >= hashcap
                  valid = 0
                else
                  hbuf[count] = h
                  hpos[count] = hdr
                  out[hdr] = rl
                  out[hdr + 1] = aci
                  out[hdr + 2] = bci
                  count = count + 1
                  new_lits = new_lits + rl
                  off = dst + rl
                  if count > old_count || new_lits > old_lits + 1
                    valid = 0
      w = ocn[w]
    phase = phase + 1

  pm[6] = valid
  pm[7] = count
  pm[8] = ticks
  pm[9] = gen
  pm[11] = occvisits
  0

# Native BVE feasibility scan for one pivot: walks both occurrence lists,
# forms every resolvent over the flat literal arena (tautologies skipped via
# generation stamps, duplicates bucketed by an order-independent 64-bit hash
# and then compared exactly), applies the growth bounds, and on success leaves
# the packed resolvents [len, aci, bci, lits...]* in `out` for the boxed commit.
# The
# boxed path used to build every rejected candidate's resolvents as Arrays
# with sort.join dedup keys — the dominant cost of the heavy round.
#
#   pm[0] pivot  pm[1] margin  pm[2] occ-product cap  pm[3] out capacity
#   pm[4] feasible(out)  pm[5] resolvent count(out)  pm[6] hash/header cap
#   pm[7] ticks(out)  pm[8] next lgen(out)
-> wassat_pre_bve_scan(fla, fcs, fcl, falive, ftaut, och, ocn, ocv, lstamp, hbuf, hpos, out, pm, lgen0) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64)
  v = pm[0]
  margin = pm[1]
  prodcap = pm[2]
  outcap = pm[3]
  hashcap = pm[6]
  outcap = WASSAT_PRE_BVE_OUT_CAPACITY if outcap > WASSAT_PRE_BVE_OUT_CAPACITY
  hashcap = WASSAT_PRE_BVE_HASH_CAPACITY if hashcap > WASSAT_PRE_BVE_HASH_CAPACITY
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
                  # Order-independent 64-bit hash only SELECTS a candidate
                  # bucket; a hash hit then triggers an EXACT set comparison.
                  # Two DISTINCT resolvents can collide on this hash, and
                  # dropping a real resolvent as a false duplicate makes the
                  # reduced formula non-equisatisfiable (a reconstructed model
                  # then fails the original-formula guard).
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
                  while j < count && isdup == 0
                    if hbuf[j] == h && out[hpos[j]] == rl
                      # same hash and same length: confirm identical literal
                      # sets (unique lits per resolvent, so subset ⟹ equal)
                      sp = hpos[j]
                      same = 1
                      p = 0
                      while p < rl && same == 1
                        found = 0
                        q = 0
                        while q < rl && found == 0
                          if out[sp + 3 + q] == out[base + p]
                            found = 1
                          q = q + 1
                        if found == 0
                          same = 0
                        p = p + 1
                      if same == 1
                        isdup = 1
                    j = j + 1
                  if isdup == 0
                    if count >= hashcap
                      feasible = 0
                    else
                      hbuf[count] = h
                      hpos[count] = hdr
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
# Raw-kernel artifact: skip the preprocessor entirely.
#
# Above the size threshold every technique is disabled by policy, yet
# intake still built occurrence lists and signatures for the subsumption
# and BVE passes that never run, and sweep_satisfied re-derived root units
# the solver's own load already collects — 51ms of the 120ms on
# bmc-ibm-6. The parser's flat arrays are already exactly the arena the
# solver ingests, so hand them over directly with the three trivial
# side-tables the loader expects. Tautologies stay in: they are satisfied
# under every assignment, so they never propagate or conflict, and the
# watch scheme carries them at no cost.
-> wassat_raw_artifact(parse, nvars)
  ncl = parse["flat_ncl"]
  # No side tables at all: every clause is alive and proof ids are
  # sequential, so the loader synthesizes both from the index ("fsynth").
  # Materializing them cost three ncl-sized allocations plus their fills —
  # 7.8MB and ~5ms on bmc-ibm-10 — for data that is either constant or,
  # in the case of proof ids, never read on this path.
  empty = i64[1]
  { "nvars": nvars, "clauses": [], "gids": [], "raw": true,
    "config": WassatConfig.from_lens(nvars, parse["flat_lens"], ncl),
    "next_gid": ncl + 1, "status": 0,
    "stack": [], "gone": i64[nvars + 2],
    "fla": parse["flat_lits"], "fcs": parse["flat_offs"],
    "fcl": parse["flat_lens"], "falive": empty,
    "ftaut": empty, "fpgid": empty, "fncl": ncl, "fsynth": true,
    "wrat": [], "drat": [],
    "stats": { "probes": 0, "probes_failed": 0,
               "vars_substituted": 0,
               "clauses_subsumed": 0,
               "clauses_strengthened": 0,
               "vars_eliminated": 0,
               "and2_candidates": 0,
               "and2_eliminated": 0,
               "ticks": 0 } }

-> wassat_pre_stats_text(stats, pre_ms)
  "probes=[stats["probes"]] probes_failed=[stats["probes_failed"]] vars_substituted=[stats["vars_substituted"]] clauses_subsumed=[stats["clauses_subsumed"]] clauses_strengthened=[stats["clauses_strengthened"]] vars_eliminated=[stats["vars_eliminated"]] and2_candidates=[stats["and2_candidates"]] and2_eliminated=[stats["and2_eliminated"]] preprocess_ms=[pre_ms]"

# Preprocess CNF text and return the artifact.
-> wassat_preprocess(cnf_text, proof_mode)
  f = wassat_parse_cnf(cnf_text)
  pre = WassatPreprocess.new(f["nvars"], f["clauses"], proof_mode, nil)
  pre.run

# End-to-end library entry: preprocess, solve the reduced formula, and
# return a result whose model is reconstructed for the ORIGINAL formula and
# whose proof arrays carry prefix + search certificate. The artifact rides
# along under "pre".
-> wassat_solve_preprocessed(cnf_text, proof_mode, lookahead, max_conflicts)
  f = wassat_parse_cnf(cnf_text)
  pre = WassatPreprocess.new(f["nvars"], f["clauses"], proof_mode, nil)
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
  gone = art["gone"] ## i64[]
  assumptions.each -> (a)
    raise "assumption literal must not be zero" if a == 0
    v = a.abs
    raise "assumption literal [a] exceeds preprocessed variable count [gone.size - 1]" if v >= gone.size
    unless gone[v] == 0
      kind = gone[v] == 2 ? "substituted" : "eliminated"
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

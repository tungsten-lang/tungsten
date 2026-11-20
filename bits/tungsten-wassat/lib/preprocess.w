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
use counter_rewrite

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
WASSAT_PRE_BVE_OUT_CAPACITY = 131072  # 2^17: packed BVE header-offset width
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
WASSAT_PRE_AND2_CANDIDATE_CAP = 250000
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
  # The flat formula this preprocessor's buffers were sized for (or nil).
  ro :flat

  -> new(@nvars, @input_clauses, @proof_mode, flat_in)
    # Only a formula that actually carries the parser's flat mirrors counts as
    # a flat source; the boxed parser produces neither. Checking here rather
    # than trusting call sites -- passing a boxed formula as `flat` crashed the
    # proof portfolio with "expected int, got nil" until this guard existed.
    flat = flat_in
    flat = nil if flat != nil && !flat.has_key?("flat_ncl")
    @flat = flat
    nv = @nvars
    raise "variable count exceeds signed 32-bit preprocessor representation" if nv < 0 || nv > 1073741800
    if flat == nil
      @config = WassatConfig.new(@nvars, @input_clauses)
    elsif flat["config"] != nil && flat["config"].nvars == @nvars && flat["config"].nclauses == flat["flat_ncl"]
      @config = flat["config"]
    else
      @config = WassatConfig.from_lens(@nvars, flat["flat_lens"], flat["flat_ncl"])
    @passign = i8[nv + 1]        # root assignment: 0 / 1 / -1
    @preason = i32[nv + 1]       # root reason clause index, -1 = none
    @tpos = i32[nv + 1]          # trail position, for hint ordering
    @seen = i8[nv + 1]           # scratch marks for cone closure
    @gone = i8[nv + 1]           # 0 live, 1 = BVE-eliminated, 2 = substituted
    @frozen = i8[nv + 1]
    @has_frozen = false
    @counter_base = 0
    @replit = i32[nv + 1]        # substitution: var -> representative literal
    v = 0
    while v <= nv
      @preason[v] = -1
      @replit[v] = 0
      v += 1

    # typed trail (root prefix + probe segment, contiguous)
    @ftrail = i32[nv + 2]
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
    raise "clause count exceeds signed 32-bit preprocessor representation" if @ncl_in < 0 || @ncl_in + 4 > 2147483600
    raise "literal count exceeds signed 32-bit preprocessor representation" if total < 0 || total + 16 > 2147483600
    @fccap = 2 * @ncl_in + 4 * nv + 1024
    @fccap = 2147483600 if @fccap > 2147483600
    @facap = 2 * total + 8 * nv + 4096
    @facap = 2147483600 if @facap > 2147483600
    @fcs = i32[@fccap]           # ci -> arena offset
    @fcl = i32[@fccap]           # ci -> length
    @falive = i8[@fccap]         # ci -> 1 live, 0 deleted (logical/proof life)
    @ftaut = i8[@fccap]          # ci -> 1 when the clause is a tautology
    @fsig = i64[@fccap]          # ci -> 64-bit literal signature
    @fpgid = (@proof_mode == WASSAT_PROOF_WRAT || flat == nil) ? i64[@fccap] : i64[0]
    @sub_dirty = i8[@fccap]      # ci -> 1 needs subsumer/candidate scan, 0 clean
    @fla = i32[@facap]           # literal arena
    @fasize = 0
    @next_gid = 1
    @ncl = 0

    # intrusive occurrence lists: one node per stored literal occurrence
    @ocap = @facap
    @oh = i32[2 * nv + 2]        # lit_index -> first node, -1 = empty
    @on = i32[@ocap]             # node -> next node
    @ov = i32[@ocap]             # node -> clause index
    @ocount = i32[2 * nv + 2]    # lit_index -> live occurrences
    @bve_dirty = i8[nv + 2]      # v -> 1 eligible for next BVE scan, 0 clean
    @last_bve_margin = -1
    @osize = 0
    i = 0
    while i < 2 * nv + 2
      @oh[i] = -1
      i += 1
    wassat_pre_fill_i8(@bve_dirty, nv + 1, 1)

    # proof prefix streams (in-memory; the coordinator owns writing them out)
    @emit_wrat = @proof_mode == WASSAT_PROOF_WRAT
    @emit_drat = @proof_mode == WASSAT_PROOF_DRAT
    @wrat_lines = []
    @drat_lines = []
    @dbytes = nil
    @dbpos = 0
    @flat_drat = false
    @arenas_released = false

    # elimination stack: tagged entries, walked backwards at reconstruction.
    # Substitutions and BVE steps buffer into flat typed arrays (@rstack_hdr /
    # @rstack_lits) and flush as immutable "flat_batch" chunks onto @stack.
    @stack = []
    @rstack_hdr = nil
    @rstack_lits = nil
    @rstack_hcap = 0
    @rstack_lcap = 0
    @rstack_hend = 0
    @rstack_lsize = 0
    @rstack_flushed = 0

    @status = 0                  # 0 unknown, -1 refuted during preprocessing
    @ticks = 0
    @tick_budget = 0             # 0 = derived from formula size in `run`
    @deadline_ms = 0             # 0 = no wall-clock stop (see set_deadline_ms)
    @heavy_ticks = 0
    @heavy_stage_ms = 0
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
    @scc_runs = 0
    @scc_nodes = 0
    @scc_components = 0
    @scc_singletons = 0
    @scc_peak_frames = 0
    @scc_edges = 0
    @scc_graph_bytes = 0
    @scc_graph_offsets = nil
    @scc_graph_cursor = nil
    @scc_graph_targets = nil
    @scc_graph_clauses = nil
    @scc_index = nil
    @scc_low = nil
    @scc_oncur = nil
    @scc_cur = nil
    @scc_frame_node = nil
    @scc_frame_child = nil
    @scc_st = i64[4]
    @scc_last_ncomp = 0
    @sort_cnt = nil
    @sort_vars = nil
    @str_buf = i32[64]
    @str_cap = 64
    @clauses_subsumed = 0
    @clauses_strengthened = 0
    @vars_eliminated = 0
    @compact_after_eliminated = 0
    @compact_retry_fasize = 0
    @storage_compaction_ms = 0
    @storage_scanned_clauses = 0
    @storage_compactions = 0
    @storage_compacted_literals = 0
    @storage_reclaimed_literals = 0
    @storage_reclaimed_occurrences = 0
    @compact_pm = i64[2]
    @bve_hash_probes = 0
    @bve_hash_hits = 0
    @bve_compared_literals = 0
    @and2_candidates = 0
    @and2_eliminated = 0
    @and2_done = false

    # native-call scratch
    @pst = i64[7]                # qhead / tsize / conflict / ticks / scanned / visits / two-open
    @subscan_pm = i64[10]
    @subscan_out = i64[16384]    # survivor triples: 3 slots each + header
    @bve_pm = i64[13]
    @bve_out = i64[WASSAT_PRE_BVE_OUT_CAPACITY]
                                 # packed: [len, aci, bci, lits...]*
    @bve_hash = i64[WASSAT_PRE_BVE_HASH_CAPACITY]
                                 # per-candidate dedup hashes (bucket)
    @bve_hpos = i64[WASSAT_PRE_BVE_HASH_CAPACITY]
                                 # AND header offsets / epoch-tagged BVE headers; exact set checks

    # reusable BFS scratch for implication paths (allocated on first use);
    # a fresh boxed array per path was the substitution phase's entire cost
    @bfs_from = i32[1]
    @bfs_ci = i32[1]
    @bfs_mark = i32[1]
    @bfs_gen = 0
    @bfs_ready = 0

    # literal stamps for subsumption: mark the subsumer's literals once,
    # count marks per candidate. The exact subset check runs only on
    # candidates that pass the count filter.
    @lstamp = i32[2 * nv + 2]
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
    @flat_consumer = false
    @flat_proof_output = false
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
    wassat_pre_fill_i8(@sub_dirty, ncl, 1)
    @ncl = ncl
    @fasize = pm[1]
    @osize = pm[2]
    @next_gid = ncl + 1
    # boxed truth stays LAZY: nil slots only when WRAT needs per-clause caching
    @lazy_lits = true
    if @proof_mode == WASSAT_PROOF_WRAT
      k = 0
      while k < ncl
        @lits.push(nil)
        k += 1
    # fire input units / empty clauses exactly like intake()
    ci = 0
    while ci < @ncl && @status == 0
      n = @fcl[ci]
      if n == 0
        if @flat_drat
          self.drat_add_empty
        else
          self.plog_add(@next_gid, [], @emit_wrat ? [@fpgid[ci]] : [])
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

  -> run_light_flat(parse, rewrite_counter = false)
    @flat_consumer = true
    tp = wassat_prof_clock
    # Reuse this arm's original capacity, but shrink its logical variable
    # range: branching on discarded auxiliary coordinates changes the search.
    # The entry is pushed first so its model lift runs after all later passes.
    if rewrite_counter && @proof_mode == WASSAT_PROOF_NONE && @ncl == 0 && !@has_frozen
      counter = wassat_counter_rewrite(parse, @stop_cell, @deadline_ms)
      if counter != nil
        parse = counter["formula"]
        @flat = parse
        @nvars = parse["nvars"]
        @ncl_in = parse["flat_ncl"]
        @counter_base = counter["meta"][1]
        @config = WassatConfig.from_lens(@nvars, parse["flat_lens"], @ncl_in)
        self.flush_rstack
        @stack.push({ "kind": "counter_rewrite", "gates": counter["gates"], "meta": counter["meta"] })
        wassat_counter_profile(counter["meta"])
    return nil if self.cancelled
    self.init_budget
    self.intake_flat(parse)
    tp = wassat_prof("pre.intake_flat", tp)
    wassat_prof_note("pre.root_work clauses=[@pst[5]] scanned_literals=[@pst[4]] two_open_stops=[@pst[6]]") if tp != 0
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
    if ci < @lits.size
      c = @lits[ci]
      return c unless c == nil
    st = @fcs[ci]
    n = @fcl[ci]
    c = []
    j = 0
    while j < n
      c.push(@fla[st + j])
      j += 1
    @lits[ci] = c if ci < @lits.size
    c

  -> copy_clause_lits(ci)
    st = @fcs[ci]
    n = @fcl[ci]
    c = []
    j = 0
    while j < n
      c.push(@fla[st + j])
      j += 1
    c

  # Both proof dialects at once (CLI requested --proof and --drat together).
  -> enable_dual_emission
    @emit_wrat = true
    @emit_drat = true
    @flat_drat = false
    if @fpgid.size < @fccap
      @fpgid = i64[@fccap]
    0

  # Downstream DRAT solver ingests flat mirrors directly without boxed clauses.
  -> enable_flat_proof_output
    @flat_proof_output = true
    if @emit_drat && !@emit_wrat
      @flat_drat = true
      @dbytes = u8[262144] if @dbytes == nil
      @dbpos = 0
    0

  -> ensure_rstack(need_entries, need_lits)
    if @rstack_lsize + need_lits > 1073741824
      self.flush_rstack
      @rstack_hdr = nil
      @rstack_lits = nil
      @rstack_hcap = 0
      @rstack_lcap = 0
      @rstack_hend = 0
      @rstack_lsize = 0
      @rstack_flushed = 0
    need_hwords = 4 * (@rstack_hend + need_entries)
    if @rstack_hdr == nil || need_hwords > @rstack_hcap
      ncap = @rstack_hcap == 0 ? 1024 : @rstack_hcap * 2
      ncap = need_hwords + 1024 if ncap < need_hwords
      nh = i32[ncap]
      if @rstack_hdr != nil
        old_h = @rstack_hdr ## i32[]
        wassat_pre_copy_i32(old_h, nh, 4 * @rstack_hend)
        z = ccall("w_value_free_w", old_h) if @rstack_flushed == 0
      @rstack_hdr = nh
      @rstack_hcap = ncap
    need_lwords = @rstack_lsize + need_lits
    if @rstack_lits == nil || need_lwords > @rstack_lcap
      lcap = @rstack_lcap == 0 ? 2048 : @rstack_lcap * 2
      lcap = need_lwords + 2048 if lcap < need_lwords
      nl = i32[lcap]
      if @rstack_lits != nil
        old_l = @rstack_lits ## i32[]
        wassat_pre_copy_i32(old_l, nl, @rstack_lsize)
        z = ccall("w_value_free_w", old_l) if @rstack_flushed == 0
      @rstack_lits = nl
      @rstack_lcap = lcap
    0

  -> push_rstack_subst(yv, r_for_y)
    self.ensure_rstack(1, 0)
    hdr = @rstack_hdr ## i32[]
    base = 4 * @rstack_hend
    hdr[base] = 3
    hdr[base + 1] = yv
    hdr[base + 2] = r_for_y
    hdr[base + 3] = 0
    @rstack_hend += 1
    0

  -> flush_rstack
    if @rstack_hend > @rstack_flushed
      @stack.push({ "kind": "flat_batch", "hdr": @rstack_hdr, "lits": @rstack_lits,
                    "hstart": @rstack_flushed, "hend": @rstack_hend })
      @rstack_flushed = @rstack_hend
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

  -> set_heavy_budget(heavy_ticks, stage_ms)
    @heavy_ticks = heavy_ticks
    @heavy_stage_ms = stage_ms
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
    @has_frozen = true
    @frozen[v] = 1
    0

  # ---- literal helpers ------------------------------------------------------

  -> lit_index(l)
    l > 0 ? 2 * l : 2 * (0 - l) + 1

  -> value(l)
    a = @passign[l >= 0 ? l : 0 - l]
    l > 0 ? a : 0 - a

  -> signature_of(arr)
    s = 0
    i = 0
    while i < arr.size
      l = arr[i]
      av = l >= 0 ? l : 0 - l
      s = s | ((1 ## i64) << (av & 63))
      i += 1
    s

  # ---- proof emission -------------------------------------------------------

  -> ensure_dbytes(n)
    need = @dbpos + 16 * n + 32
    if @dbytes == nil
      cap = 262144
      cap = need + 4096 if cap < need
      @dbytes = u8[cap]
    elsif need > @dbytes.size
      ncap = @dbytes.size * 2
      ncap = need + 4096 if ncap < need
      bigger = u8[ncap]
      old = @dbytes ## u8[]
      wassat_pre_copy_u8(old, bigger, @dbpos)
      z = ccall("w_value_free_w", old)
      @dbytes = bigger
    0

  -> drat_add_slice(arr, off, n)
    self.ensure_dbytes(n)
    @dbpos = wassat_pre_drat_put_i32(@dbytes, @dbpos, arr, off, n, 0)
    0

  -> drat_del_slice(arr, off, n)
    self.ensure_dbytes(n)
    @dbpos = wassat_pre_drat_put_i32(@dbytes, @dbpos, arr, off, n, 1)
    0

  -> drat_add_unit(lit)
    @str_buf[0] = lit
    self.drat_add_slice(@str_buf, 0, 1)

  -> drat_add_pair(l1, l2)
    @str_buf[0] = l1
    @str_buf[1] = l2
    self.drat_add_slice(@str_buf, 0, 2)

  -> drat_add_empty
    self.drat_add_slice(@str_buf, 0, 0)

  -> plog_add(gid, lits_arr, hints)
    if @emit_wrat
      body = lits_arr.empty? ? "" : lits_arr.join(" ") + " "
      @wrat_lines.push("[gid] " + body + "0 " + hints.join(" ") + " 0")
    if @emit_drat
      if @flat_drat
        n = lits_arr.size
        self.ensure_str_buf(n)
        i = 0
        while i < n
          @str_buf[i] = lits_arr[i]
          i += 1
        self.drat_add_slice(@str_buf, 0, n)
      else
        @drat_lines.push(lits_arr.empty? ? "0" : lits_arr.join(" ") + " 0")
    0

  -> plog_delete(ids, lits_list)
    if @emit_wrat && !ids.empty?
      last = @next_gid - 1
      @wrat_lines.push("[last] d " + ids.join(" ") + " 0")
    if @emit_drat
      if @flat_drat
        lits_list.each -> (arr)
          n = arr.size
          self.ensure_str_buf(n)
          i = 0
          while i < n
            @str_buf[i] = arr[i]
            i += 1
          self.drat_del_slice(@str_buf, 0, n)
      else
        lits_list.each -> (arr)
          @drat_lines.push(arr.empty? ? "d 0" : "d " + arr.join(" ") + " 0")
    0

  # ---- clause database ------------------------------------------------------

  # Explicitly release all large preprocessor-owned arenas once the downstream
  # solver has ingested the flat rendering (or when an arm aborts/refutes).
  # Keeps @gone, @rstack_hdr/@rstack_lits (@stack), and @dbytes alive for model
  # reconstruction, assumption checks, and DRAT prefix output. Idempotent.
  -> release_arenas
    return 0 if @arenas_released
    @arenas_released = true
    if @fla.size > 1
      z = ccall("w_value_free_w", @fla)
      @fla = i32[1]
    if @fcs.size > 1
      z = ccall("w_value_free_w", @fcs)
      @fcs = i32[1]
    if @fcl.size > 1
      z = ccall("w_value_free_w", @fcl)
      @fcl = i32[1]
    if @falive.size > 1
      z = ccall("w_value_free_w", @falive)
      @falive = i8[1]
    if @ftaut.size > 1
      z = ccall("w_value_free_w", @ftaut)
      @ftaut = i8[1]
    if @fsig.size > 1
      z = ccall("w_value_free_w", @fsig)
      @fsig = i64[1]
    if @fpgid.size > 1
      z = ccall("w_value_free_w", @fpgid)
      @fpgid = i64[0]
    if @sub_dirty.size > 1
      z = ccall("w_value_free_w", @sub_dirty)
      @sub_dirty = i8[1]
    if @oh.size > 1
      z = ccall("w_value_free_w", @oh)
      @oh = i32[1]
    if @on.size > 1
      z = ccall("w_value_free_w", @on)
      @on = i32[1]
    if @ov.size > 1
      z = ccall("w_value_free_w", @ov)
      @ov = i32[1]
    if @ocount.size > 1
      z = ccall("w_value_free_w", @ocount)
      @ocount = i32[1]
    if @lstamp.size > 1
      z = ccall("w_value_free_w", @lstamp)
      @lstamp = i32[1]
    if @passign.size > 1
      z = ccall("w_value_free_w", @passign)
      @passign = i8[1]
    if @preason.size > 1
      z = ccall("w_value_free_w", @preason)
      @preason = i32[1]
    if @tpos.size > 1
      z = ccall("w_value_free_w", @tpos)
      @tpos = i32[1]
    if @seen.size > 1
      z = ccall("w_value_free_w", @seen)
      @seen = i8[1]
    if @frozen.size > 1
      z = ccall("w_value_free_w", @frozen)
      @frozen = i8[1]
    if @replit.size > 1
      z = ccall("w_value_free_w", @replit)
      @replit = i32[1]
    if @ftrail.size > 1
      z = ccall("w_value_free_w", @ftrail)
      @ftrail = i32[1]
    if @bve_dirty.size > 1
      z = ccall("w_value_free_w", @bve_dirty)
      @bve_dirty = i8[1]
    if @str_buf.size > 1
      z = ccall("w_value_free_w", @str_buf)
      @str_buf = i32[1]
      @str_cap = 1
    if @subscan_out.size > 1
      z = ccall("w_value_free_w", @subscan_out)
      @subscan_out = i64[1]
    if @bve_out.size > 1
      z = ccall("w_value_free_w", @bve_out)
      @bve_out = i64[1]
    if @bve_hash.size > 1
      z = ccall("w_value_free_w", @bve_hash)
      @bve_hash = i64[1]
    if @bve_hpos.size > 1
      z = ccall("w_value_free_w", @bve_hpos)
      @bve_hpos = i64[1]
    if @bfs_from.size > 1
      z = ccall("w_value_free_w", @bfs_from)
      @bfs_from = i32[1]
    if @bfs_ci.size > 1
      z = ccall("w_value_free_w", @bfs_ci)
      @bfs_ci = i32[1]
    if @bfs_mark.size > 1
      z = ccall("w_value_free_w", @bfs_mark)
      @bfs_mark = i32[1]
    @bfs_ready = 0
    if @sort_cnt != nil
      z = ccall("w_value_free_w", @sort_cnt)
      @sort_cnt = nil
    if @sort_vars != nil
      z = ccall("w_value_free_w", @sort_vars)
      @sort_vars = nil
    if @scc_graph_offsets != nil
      z = ccall("w_value_free_w", @scc_graph_offsets)
      @scc_graph_offsets = nil
    if @scc_graph_cursor != nil
      z = ccall("w_value_free_w", @scc_graph_cursor)
      @scc_graph_cursor = nil
    if @scc_graph_targets != nil
      z = ccall("w_value_free_w", @scc_graph_targets)
      @scc_graph_targets = nil
    if @scc_graph_clauses != nil
      z = ccall("w_value_free_w", @scc_graph_clauses)
      @scc_graph_clauses = nil
    if @scc_index != nil
      z = ccall("w_value_free_w", @scc_index)
      @scc_index = nil
    if @scc_low != nil
      z = ccall("w_value_free_w", @scc_low)
      @scc_low = nil
    if @scc_oncur != nil
      z = ccall("w_value_free_w", @scc_oncur)
      @scc_oncur = nil
    if @scc_cur != nil
      z = ccall("w_value_free_w", @scc_cur)
      @scc_cur = nil
    if @scc_frame_node != nil
      z = ccall("w_value_free_w", @scc_frame_node)
      @scc_frame_node = nil
    if @scc_frame_child != nil
      z = ccall("w_value_free_w", @scc_frame_child)
      @scc_frame_child = nil
    @lits = []
    @fccap = 1
    @facap = 1
    @ocap = 1
    @fasize = 0
    @osize = 0
    0

  -> grow_meta
    if @ncl + 1 >= @fccap
      raise "preprocessor clause capacity exceeded 32-bit limit" if @ncl + 1 >= 2147483600
      ncap = @fccap * 2
      ncap = 2147483600 if ncap > 2147483600
      cs = i32[ncap]
      cl = i32[ncap]
      al = i8[ncap]
      tt = i8[ncap]
      sg = i64[ncap]
      sd = i8[ncap]
      wassat_pre_copy_i32(@fcs, cs, @ncl)
      wassat_pre_copy_i32(@fcl, cl, @ncl)
      wassat_pre_copy_i8(@falive, al, @ncl)
      wassat_pre_copy_i8(@ftaut, tt, @ncl)
      wassat_pre_copy_i64(@fsig, sg, @ncl)
      wassat_pre_copy_i8(@sub_dirty, sd, @ncl)
      z = ccall("w_value_free_w", @fcs)
      z = ccall("w_value_free_w", @fcl)
      z = ccall("w_value_free_w", @falive)
      z = ccall("w_value_free_w", @ftaut)
      z = ccall("w_value_free_w", @fsig)
      z = ccall("w_value_free_w", @sub_dirty)
      @fcs = cs
      @fcl = cl
      @falive = al
      @ftaut = tt
      @fsig = sg
      @sub_dirty = sd
      if @fpgid.size > 0
        gd = i64[ncap]
        wassat_pre_copy_i64(@fpgid, gd, @ncl)
        z = ccall("w_value_free_w", @fpgid)
        @fpgid = gd
      @fccap = ncap
    0

  -> compact_live_storage
    started = wassat_prof_clock
    before_literals = @fasize
    before_occurrences = @osize
    wassat_pre_compact_live(@fla, @fcs, @fcl, @falive, @ftaut,
                            @oh, @on, @ov, @ncl, @nvars, @compact_pm)
    wassat_pre_recompute_ocount(@fla, @fcs, @fcl, @falive, @ocount, @ncl, @nvars)
    @fasize = @compact_pm[0]
    @osize = @compact_pm[1]
    @compact_after_eliminated = @vars_eliminated
    # Repeated tiny deletions must not cause a whole-database scan on every
    # growth. Require new appended storage proportional to the scan's size
    # before trying again; ordinary geometric growth remains the fallback.
    @compact_retry_fasize = @fasize + (@facap + @ncl + 2 * @nvars + 2) / 4
    @storage_compaction_ms += wassat_prof_clock - started if started != 0
    @storage_scanned_clauses += @ncl
    @storage_compactions += 1
    @storage_compacted_literals += @fasize
    @storage_reclaimed_literals += before_literals - @fasize
    @storage_reclaimed_occurrences += before_occurrences - @osize
    wassat_prof_note("pre.storage compactions=[@storage_compactions] ms=[@storage_compaction_ms] scanned_clauses=[@storage_scanned_clauses] copied_literals=[@storage_compacted_literals] reclaimed_literals=[@storage_reclaimed_literals] reclaimed_occurrences=[@storage_reclaimed_occurrences]") if env("WASSAT_PROFILE") == "1"
    0

  -> grow_arena(need)
    if @fasize + need > @facap
      raise "preprocessor literal arena exceeded 32-bit limit" if @fasize + need > 2147483600
      ncap = @facap * 2
      ncap = @fasize + need + 4096 if ncap < @fasize + need
      ncap = 2147483600 if ncap > 2147483600
      bigger = i32[ncap]
      wassat_pre_copy_i32(@fla, bigger, @fasize)
      z = ccall("w_value_free_w", @fla)
      @fla = bigger
      @facap = ncap
    0

  -> grow_occ(need)
    if @osize + need > @ocap
      raise "preprocessor occurrence arena exceeded 32-bit limit" if @osize + need > 2147483600
      ncap = @ocap * 2
      ncap = @osize + need + 4096 if ncap < @osize + need
      ncap = 2147483600 if ncap > 2147483600
      nn = i32[ncap]
      nv2 = i32[ncap]
      wassat_pre_copy_i32(@on, nn, @osize)
      wassat_pre_copy_i32(@ov, nv2, @osize)
      z = ccall("w_value_free_w", @on)
      z = ccall("w_value_free_w", @ov)
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
    @lits.push(arr) unless @lazy_lits && @proof_mode != WASSAT_PROOF_WRAT
    @fcs[ci] = @fasize
    @fcl[ci] = arr.size
    @falive[ci] = 1
    @sub_dirty[ci] = 1
    @fpgid[ci] = @next_gid if @fpgid.size > ci
    @next_gid += 1
    @fsig[ci] = self.signature_of(arr)
    t = 0
    n = arr.size
    i = 0
    while i < n
      nl = 0 - arr[i]
      j = i + 1
      while j < n
        t = 1 if arr[j] == nl
        j += 1
      i += 1
    @ftaut[ci] = t
    i = 0
    while i < n
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

  # Store a tautology-free, deduplicated resolvent slice directly from a typed
  # buffer when @lazy_lits is active and no WRAT boxed truth is needed.
  -> store_from_buf(buf, start, n)
    self.grow_meta
    self.grow_arena(n)
    self.grow_occ(n)
    ci = @ncl
    @ncl += 1
    @lits.push(nil) unless @lazy_lits && @proof_mode != WASSAT_PROOF_WRAT
    @fcs[ci] = @fasize
    @fcl[ci] = n
    @falive[ci] = 1
    @sub_dirty[ci] = 1
    @fpgid[ci] = @next_gid if @fpgid.size > ci
    @next_gid += 1
    @ftaut[ci] = 0
    sig = 0 ## i64
    i = 0
    while i < n
      l = buf[start + i]
      @fla[@fasize] = l
      @fasize += 1
      av = l >= 0 ? l : 0 - l
      sig = sig | ((1 ## i64) << (av & 63))
      li = (av << 1) + (l < 0 ? 1 : 0)
      slot = @osize
      @osize += 1
      @on[slot] = @oh[li]
      @ov[slot] = ci
      @oh[li] = slot
      @ocount[li] = @ocount[li] + 1
      i += 1
    @fsig[ci] = sig
    ci

  # Delete one clause from the logical database, with its proof line.
  -> delete_clause(ci)
    if @falive[ci] == 1
      @falive[ci] = 0
      wassat_pre_retire_clause(@fla, @fcs[ci], @fcl[ci], @ocount, @bve_dirty)
      if @flat_drat
        self.drat_del_slice(@fla, @fcs[ci], @fcl[ci])
      elsif @emit_wrat || @emit_drat
        ids = @emit_wrat ? [@fpgid[ci]] : []
        lls = @emit_drat ? [self.lits_of(ci)] : []
        self.plog_delete(ids, lls)
    0

  # Delete a batch with one WRAT line (and per-clause DRAT lines).
  -> delete_batch(cis)
    if @flat_drat
      cis.each -> (ci)
        if @falive[ci] == 1
          @falive[ci] = 0
          wassat_pre_retire_clause(@fla, @fcs[ci], @fcl[ci], @ocount, @bve_dirty)
          self.drat_del_slice(@fla, @fcs[ci], @fcl[ci])
    elsif @emit_wrat || @emit_drat
      ids = []
      lls = []
      any_del = false
      cis.each -> (ci)
        if @falive[ci] == 1
          @falive[ci] = 0
          wassat_pre_retire_clause(@fla, @fcs[ci], @fcl[ci], @ocount, @bve_dirty)
          ids.push(@fpgid[ci]) if @emit_wrat
          lls.push(self.lits_of(ci)) if @emit_drat
          any_del = true
      self.plog_delete(ids, lls) if any_del
    else
      cis.each -> (ci)
        if @falive[ci] == 1
          @falive[ci] = 0
          wassat_pre_retire_clause(@fla, @fcs[ci], @fcl[ci], @ocount, @bve_dirty)
    0

  -> delete_batch_buf(buf, n)
    if @flat_drat
      i = 0
      while i < n
        ci = buf[i]
        if @falive[ci] == 1
          @falive[ci] = 0
          wassat_pre_retire_clause(@fla, @fcs[ci], @fcl[ci], @ocount, @bve_dirty)
          self.drat_del_slice(@fla, @fcs[ci], @fcl[ci])
        i += 1
    elsif @emit_wrat || @emit_drat
      ids = []
      lls = []
      any_del = false
      i = 0
      while i < n
        ci = buf[i]
        if @falive[ci] == 1
          @falive[ci] = 0
          wassat_pre_retire_clause(@fla, @fcs[ci], @fcl[ci], @ocount, @bve_dirty)
          ids.push(@fpgid[ci]) if @emit_wrat
          lls.push(self.lits_of(ci)) if @emit_drat
          any_del = true
        i += 1
      self.plog_delete(ids, lls) if any_del
    else
      wassat_pre_delete_list(@fla, @fcs, @fcl, @falive, @ocount, @bve_dirty, buf, n)
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
      av = l >= 0 ? l : 0 - l
      rci = @preason[av]
      if rci >= 0 && @fcl[rci] > 1
        if !@emit_wrat && (!@emit_drat || @flat_drat) && @lazy_lits
          self.drat_add_unit(l) if @flat_drat
          @str_buf[0] = l
          nci = self.store_from_buf(@str_buf, 0, 1)
          @preason[av] = nci
        else
          chain = @emit_wrat ? self.conflict_chain(rci, av) : []
          gid = @next_gid
          self.plog_add(gid, [l], chain)
          nci = self.store([l])
          @preason[av] = nci
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
      wci = work[wi]
      st = @fcs[wci]
      len = @fcl[wci]
      i = 0
      while i < len
        l = @fla[st + i]
        v = l >= 0 ? l : 0 - l
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
    if @flat_drat
      self.drat_add_empty
    else
      self.plog_add(@next_gid, [], @emit_wrat ? self.conflict_chain(confl_ci, 0) : [])
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
        if @flat_drat
          self.drat_add_empty
        else
          self.plog_add(@next_gid, [], @emit_wrat ? [@fpgid[ci]] : [])
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

  -> ensure_sort_scratch
    if @sort_cnt == nil
      @sort_cnt = i64[16385]
    if @sort_vars == nil || @sort_vars.size < @nvars + 2
      @sort_vars = i32[@nvars + 2]
    0

  # Probe candidate order: unassigned variables by descending occurrence
  # count (probing never removes a variable, so freezing is irrelevant).
  # Uses a 16384-bucket typed counting sort so @nvars >= 16777216 never
  # overflows a packed key and no full-formula boxed sort runs.
  -> probe_candidates
    self.ensure_sort_scratch
    cnt = @sort_cnt ## i64[]
    vars = @sort_vars ## i32[]
    total = wassat_pre_sort_probe_vars(@passign, @ocount, cnt, vars, @nvars)
    limit = total < @probe_cap ? total : @probe_cap
    out = []
    i = 0
    while i < limit
      out.push(vars[i])
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
      chain = @emit_wrat ? self.conflict_chain(confl, lit.abs) : []
      # undo the probe segment before touching root state
      self.undo_to(mark, qsave)
      @probing = false
      ul = 0 - lit
      nci = -1
      if !@emit_wrat && (!@emit_drat || @flat_drat) && @lazy_lits
        self.drat_add_unit(ul) if @flat_drat
        @str_buf[0] = ul
        nci = self.store_from_buf(@str_buf, 0, 1)
      else
        unit = [ul]
        gid = @next_gid
        self.plog_add(gid, unit, chain)
        nci = self.store(unit)
      @probes_failed += 1
      rc = -1
      if self.value(ul) < 0
        rc = nci                 # -lit already false at root: refuted
      else
        if self.value(ul) == 0
          self.assign(ul, nci)
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
            if !@emit_wrat && (!@emit_drat || @flat_drat) && @lazy_lits
              self.drat_add_pair(0 - lit, m) if @flat_drat
              @str_buf[0] = 0 - lit
              @str_buf[1] = m
              z = self.store_from_buf(@str_buf, 0, 2)
            else
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

  # Borrowed CSR graph scratch: offsets, destination literal indices, and
  # justifying clause indices. Entries retain ascending clause order, as the
  # former adjacency lists did. A graph is valid until the next rebuild.
  -> build_binary_graph
    n = 2 * @nvars + 2
    if @scc_graph_offsets == nil || @scc_graph_offsets.size < n + 1
      z = ccall("w_value_free_w", @scc_graph_offsets) if @scc_graph_offsets != nil
      z = ccall("w_value_free_w", @scc_graph_cursor) if @scc_graph_cursor != nil
      @scc_graph_offsets = i32[n + 1]
      @scc_graph_cursor = i32[n]
    ne = wassat_pre_graph_count(@fla, @fcs, @fcl, @falive, @ftaut,
                                @passign, @scc_graph_offsets, @ncl, n)
    if @scc_graph_targets == nil || @scc_graph_targets.size < ne
      cap = ne
      if @scc_graph_targets != nil
        cap = 2 * @scc_graph_targets.size
        cap = ne if cap < ne
        z = ccall("w_value_free_w", @scc_graph_targets)
        z = ccall("w_value_free_w", @scc_graph_clauses)
      @scc_graph_targets = i32[cap]
      @scc_graph_clauses = i32[cap]
    wassat_pre_graph_fill(@fla, @fcs, @fcl, @falive, @ftaut, @passign,
                          @scc_graph_offsets, @scc_graph_cursor,
                          @scc_graph_targets, @scc_graph_clauses, @ncl, n)
    @scc_edges += ne
    @scc_graph_bytes = 4 * (@scc_graph_offsets.size + @scc_graph_cursor.size +
                           @scc_graph_targets.size + @scc_graph_clauses.size)
    [@scc_graph_offsets, @scc_graph_targets, @scc_graph_clauses]

  # Iterative Tarjan over literal nodes. Returns comp[lit_index] labels.
  -> tarjan(adj)
    offsets = adj[0] ## i32[]
    targets = adj[1] ## i32[]
    n = 2 * @nvars + 2
    if @scc_index == nil || @scc_index.size < n
      if @scc_index != nil
        z = ccall("w_value_free_w", @scc_index)
        z = ccall("w_value_free_w", @scc_low)
        z = ccall("w_value_free_w", @scc_oncur)
        z = ccall("w_value_free_w", @scc_cur)
        z = ccall("w_value_free_w", @scc_frame_node)
        z = ccall("w_value_free_w", @scc_frame_child)
      @scc_index = i32[n]
      @scc_low = i32[n]
      @scc_oncur = i8[n]
      @scc_cur = i32[n]
      @scc_frame_node = i32[n]
      @scc_frame_child = i32[n]
    idx_arr = @scc_index ## i32[]
    low_arr = @scc_low ## i32[]
    oncur_arr = @scc_oncur ## i8[]
    cur_arr = @scc_cur ## i32[]
    fnode_arr = @scc_frame_node ## i32[]
    fchild_arr = @scc_frame_child ## i32[]
    comp = i32[n]
    wassat_pre_tarjan(offsets, targets, @passign, idx_arr, low_arr, oncur_arr,
                      comp, cur_arr, fnode_arr, fchild_arr, @scc_st, n)
    @ticks += @scc_st[3]
    @scc_runs += 1
    @scc_nodes += @scc_st[0]
    @scc_components += @scc_st[1]
    @scc_last_ncomp = @scc_st[1]
    @scc_peak_frames = @scc_st[2] if @scc_st[2] > @scc_peak_frames
    comp

  # BFS a path of implication edges from literal `a` to literal `b`,
  # restricted to nodes of one component. Returns the clause-index list of
  # the edges, or [] when a == b.
  -> implication_path(adj, comp, a, b)
    offsets = adj[0] ## i32[]
    targets = adj[1] ## i32[]
    clauses = adj[2] ## i32[]
    ai = self.lit_index(a)
    bi = self.lit_index(b)
    return [] if ai == bi
    n = 2 * @nvars + 2
    if @bfs_ready == 0 || @bfs_from.size < n
      z = ccall("w_value_free_w", @bfs_from) if @bfs_from.size > 1
      z = ccall("w_value_free_w", @bfs_ci) if @bfs_ci.size > 1
      z = ccall("w_value_free_w", @bfs_mark) if @bfs_mark.size > 1
      @bfs_from = i32[n]
      @bfs_ci = i32[n]
      @bfs_mark = i32[n]
      @bfs_ready = 1
    if @bfs_gen >= 2147483000
      wassat_pre_zero_i32(@bfs_mark, @bfs_mark.size)
      @bfs_gen = 0
    @bfs_gen += 1
    gen = @bfs_gen
    queue = [ai]
    qi = 0
    found = false
    while qi < queue.size && !found
      u = queue[qi]
      qi += 1
      k = offsets[u]
      end = offsets[u + 1]
      while k < end
        w = targets[k]
        @ticks += 1
        if comp[w] == comp[ai] && @bfs_mark[w] != gen && w != ai
          @bfs_mark[w] = gen
          @bfs_from[w] = u
          @bfs_ci[w] = clauses[k]
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

    # Singleton components cannot substitute anything. Count first, then
    # build a flat CSR of nontrivial components in first-member order.
    n = 2 * @nvars + 2
    sizes = i32[n]
    gpm = i64[3]
    wassat_pre_count_scc(comp, sizes, n, gpm)
    @scc_singletons += gpm[0]
    nontrivial_nodes = gpm[1]
    if nontrivial_nodes == 0
      z = ccall("w_value_free_w", comp)
      z = ccall("w_value_free_w", sizes)
      tsub = wassat_prof("pre.subst.group", tsub)
      wassat_prof_note("pre.subst.work runs=[@scc_runs] nodes=[@scc_nodes] components=[@scc_components] singletons=[@scc_singletons] peak_frames=[@scc_peak_frames] edges=[@scc_edges] graph_bytes=[@scc_graph_bytes]") if tsub != 0
      tsub = wassat_prof("pre.subst.rewrite", tsub)
      return 0

    grp_id = i32[n]
    grp_offs = i32[n + 1]
    grp_cursor = i32[n]
    grp_members = i32[nontrivial_nodes]
    ngrp = wassat_pre_build_scc_csr(comp, sizes, grp_id, grp_offs, grp_cursor, grp_members, n)
    z = ccall("w_value_free_w", sizes)
    z = ccall("w_value_free_w", grp_id)
    z = ccall("w_value_free_w", grp_cursor)
    tsub = wassat_prof("pre.subst.group", tsub)

    before = @vars_substituted
    if @proof_mode == WASSAT_PROOF_NONE && @lazy_lits
      self.ensure_rstack(nontrivial_nodes, 0)
      hdr = @rstack_hdr ## i32[]
      spm = i64[3]
      gi = 0
      while gi < ngrp && @status == 0 && self.within_budget
        chunk_end = gi + 256
        chunk_end = ngrp if chunk_end > ngrp
        spm[0] = @status
        spm[1] = @vars_substituted
        spm[2] = @rstack_hend
        wassat_pre_collect_subst_csr(grp_offs, grp_members, @seen, @frozen,
                                     @replit, @gone, hdr, gi, chunk_end, spm)
        @status = spm[0]
        @vars_substituted = spm[1]
        @rstack_hend = spm[2]
        gi = chunk_end
    elsif @flat_drat && @lazy_lits
      gi = 0
      while gi < ngrp && @status == 0 && self.within_budget
        mstart = grp_offs[gi]
        mend = grp_offs[gi + 1]
        if mend - mstart > 1
          self.substitute_class_flat_drat(grp_members, mstart, mend)
        gi += 1
    else
      gi = 0
      while gi < ngrp && @status == 0 && self.within_budget
        mstart = grp_offs[gi]
        mend = grp_offs[gi + 1]
        if mend - mstart > 1
          members = []
          mk = mstart
          while mk < mend
            members.push(grp_members[mk])
            mk += 1
          self.substitute_class(adj, comp, members)
        gi += 1
    z = ccall("w_value_free_w", comp)
    z = ccall("w_value_free_w", grp_offs)
    z = ccall("w_value_free_w", grp_members)
    if @proof_mode == WASSAT_PROOF_NONE && @lazy_lits && @status == 0 && @vars_substituted > before
      self.rewrite_all_subst_flat
    wassat_prof_note("pre.subst.work runs=[@scc_runs] nodes=[@scc_nodes] components=[@scc_components] singletons=[@scc_singletons] peak_frames=[@scc_peak_frames] edges=[@scc_edges] graph_bytes=[@scc_graph_bytes]") if tsub != 0
    tsub = wassat_prof("pre.subst.rewrite", tsub)
    0

  -> rewrite_all_subst_flat
    ci = 0
    limit_lits = @lits.size
    while ci < limit_lits
      @lits[ci] = nil
      ci += 1
    units = i32[@ncl + 2]
    pm = i64[8]
    pm[0] = @ncl
    pm[1] = @nvars
    wassat_pre_subst_rewrite_flat_dirty(@fla, @fcs, @fcl, @falive, @ftaut, @fsig,
                                        @oh, @on, @ov, @ocount, @passign, @replit,
                                        units, pm, @sub_dirty, @bve_dirty)
    @osize = pm[2]
    @ticks += pm[3]
    nunits = pm[4]
    u = 0
    while u < nunits && @status == 0
      nci = units[u]
      if @falive[nci] == 1 && @fcl[nci] == 1
        l = @fla[@fcs[nci]]
        lv = self.value(l)
        if lv < 0
          self.refute(nci)
        elsif lv == 0
          self.assign(l, nci)
          confl = self.propagate_root
          self.refute(confl) if confl >= 0
      u += 1
    z = ccall("w_value_free_w", units)
    0

  # Allocation-free DRAT substitution of one nontrivial SCC slice directly into
  # @dbytes and @fla, preserving exact helper-binary RUP ordering.
  -> substitute_class_flat_drat(grp_members, mstart, mend)
    contradiction_var = 0
    mk = mstart
    while mk < mend
      v = grp_members[mk] >> 1
      if @seen[v] == 1
        contradiction_var = v
      else
        @seen[v] = 1
      mk += 1
    mk = mstart
    while mk < mend
      @seen[grp_members[mk] >> 1] = 0
      mk += 1
    if contradiction_var > 0
      x = contradiction_var
      self.drat_add_unit(0 - x)
      @str_buf[0] = 0 - x
      z = self.store_from_buf(@str_buf, 0, 1)
      self.drat_add_unit(x)
      @str_buf[0] = x
      z = self.store_from_buf(@str_buf, 0, 1)
      self.drat_add_empty
      @next_gid += 1
      @status = -1
      return 0

    rep = 0
    best = 0
    already = false
    mk = mstart
    while mk < mend
      m = grp_members[mk]
      v = m >> 1
      l = (m & 1) == 0 ? v : 0 - v
      rep = l if rep == 0 && @frozen[v] == 1
      bav = best >= 0 ? best : 0 - best
      best = l if best == 0 || v < bav
      already = true if @replit[v] != 0
      mk += 1
    rep = best if rep == 0
    return 0 if already

    helpers = i32[2 * (mend - mstart) + 1]
    nhelp = 0
    mk = mstart
    while mk < mend && @status == 0
      m = grp_members[mk]
      yv = m >> 1
      y = (m & 1) == 0 ? yv : 0 - yv
      if y != rep && @frozen[yv] == 0
        r_for_y = yv == y ? rep : 0 - rep
        self.drat_add_pair(0 - yv, r_for_y)
        @str_buf[0] = 0 - yv
        @str_buf[1] = r_for_y
        cf = self.store_from_buf(@str_buf, 0, 2)
        self.drat_add_pair(yv, 0 - r_for_y)
        @str_buf[0] = yv
        @str_buf[1] = 0 - r_for_y
        cb = self.store_from_buf(@str_buf, 0, 2)
        @helper_mark[cf] = true
        @helper_mark[cb] = true
        helpers[nhelp] = cf
        helpers[nhelp + 1] = cb
        nhelp += 2
        @replit[yv] = r_for_y
        @gone[yv] = 2
        self.push_rstack_subst(yv, r_for_y)
        @vars_substituted += 1
      mk += 1

    finished = true
    mk = mstart
    while mk < mend && @status == 0 && finished
      yv = grp_members[mk] >> 1
      if @replit[yv] != 0
        finished = self.rewrite_occurrences(yv, 0, 0)
      mk += 1

    if finished
      self.delete_batch_buf(helpers, nhelp) if nhelp > 0
      @helper_mark = {}
    z = ccall("w_value_free_w", helpers)
    0

  # Substitute one nontrivial SCC. members are lit_indexes.
  -> substitute_class(adj, comp, members)
    # detect x and -x in one class: the formula is unsatisfiable
    contradiction_var = 0
    lits_of = []
    members.each -> (m)
      v = m / 2
      l = m % 2 == 0 ? v : 0 - v
      lits_of.push(l)
      if @seen[v] == 1
        contradiction_var = v
      else
        @seen[v] = 1
    members.each -> (m)
      @seen[m / 2] = 0
    if contradiction_var > 0
      x = contradiction_var
      # derive [-x] via the path x => -x, then [x] via -x => x, then empty
      p1 = @emit_wrat ? self.implication_path(adj, comp, x, 0 - x) : []
      g1 = @next_gid
      self.plog_add(g1, [0 - x], @emit_wrat ? self.path_gids(p1) : [])
      c1 = self.store([0 - x])
      p2 = @emit_wrat ? self.implication_path(adj, comp, 0 - x, x) : []
      g2 = @next_gid
      self.plog_add(g2, [x], @emit_wrat ? self.path_gids(p2) : [])
      c2 = self.store([x])
      self.plog_add(@next_gid, [], @emit_wrat ? [@fpgid[c1], @fpgid[c2]] : [])
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
          pf = @emit_wrat ? self.implication_path(adj, comp, yv, r_for_y) : []
          gf = @next_gid
          self.plog_add(gf, [0 - yv, r_for_y], @emit_wrat ? self.path_gids(pf) : [])
          cf = self.store([0 - yv, r_for_y])
          binid_fwd[yv] = @emit_wrat ? @fpgid[cf] : 0
          # (yv | -r_for_y): path from -yv to -r_for_y, which holds because
          # r_for_y => yv around the cycle.
          pb = @emit_wrat ? self.implication_path(adj, comp, 0 - yv, 0 - r_for_y) : []
          gb = @next_gid
          self.plog_add(gb, [yv, 0 - r_for_y], @emit_wrat ? self.path_gids(pb) : [])
          cb = self.store([yv, 0 - r_for_y])
          binid_back[yv] = @emit_wrat ? @fpgid[cb] : 0
          @helper_mark[cf] = true
          @helper_mark[cb] = true
          helpers.push(cf)
          helpers.push(cb)
          @replit[yv] = r_for_y
          @gone[yv] = 2
          self.push_rstack_subst(yv, r_for_y)
          @vars_substituted += 1

    # rewrite every live clause containing a substituted variable of this class
    finished = true
    lits_of.each -> (y)
      yv = y.abs
      if @replit[yv] != 0 && @status == 0 && finished
        finished = self.rewrite_occurrences(yv, binid_fwd[yv], binid_back[yv])

    if finished
      self.delete_batch(helpers)
      @helper_mark = {}
    0

  -> path_gids(path)
    out = []
    path.each -> (ci)
      out.push(@fpgid[ci])
    out

  -> rewrite_occurrences(yv, gid_fwd, gid_back)
    r = @replit[yv]
    done = true
    side = 0
    while side < 2 && done
      li = 2 * yv + side
      w = @oh[li]
      while w >= 0 && done
        ci = @ov[w]
        @rewrite_seen += 1
        if @rewrite_seen % WASSAT_PRE_SUBST_CHECK_EVERY == 0
          done = false unless self.within_budget
        eligible = @falive[ci] == 1 && !@helper_mark.has_key?(ci)
        if eligible
          sat_root = false
          st = @fcs[ci]
          len = @fcl[ci]
          si = 0
          while si < len
            sat_root = true if self.value(@fla[st + si]) > 0
            si += 1
          eligible = !sat_root
        if eligible
          st = @fcs[ci]
          len = @fcl[ci]
          @ticks += len
          if !@emit_wrat && (!@emit_drat || @flat_drat) && @lazy_lits
            self.ensure_str_buf(len)
            un = wassat_pre_subst_clause_buf(@fla, st, len, yv, r, @str_buf)
            if un < 0
              self.delete_clause(ci)
            else
              unit_lit = un == 1 ? @str_buf[0] : 0
              self.drat_add_slice(@str_buf, 0, un) if @flat_drat
              nci = self.store_from_buf(@str_buf, 0, un)
              self.delete_clause(ci)
              if un == 1 && @status == 0
                lv = self.value(unit_lit)
                if lv < 0
                  self.refute(nci)
                elsif lv == 0
                  self.assign(unit_lit, nci)
                  confl = self.propagate_root
                  self.refute(confl) if confl >= 0
          else
            uniq = []
            hints = []
            used_fwd = false
            used_back = false
            t = false
            i = 0
            while i < len
              l = @fla[st + i]
              if l == yv
                l = r
                if @emit_wrat && !used_fwd
                  hints.push(gid_fwd)
                  used_fwd = true
              elsif l == 0 - yv
                l = 0 - r
                if @emit_wrat && !used_back
                  hints.push(gid_back)
                  used_back = true
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
              hints.push(@fpgid[ci]) if @emit_wrat
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
      side += 1
    done

  # ---- technique 3: subsumption + self-subsuming strengthening --------------

  -> bump_lgen(delta)
    if @lgen + 2 * @ncl + delta + 16 >= 2147483000
      wassat_pre_zero_i32(@lstamp, @lstamp.size)
      @lgen = 1
    @lgen += delta
    @lgen

  -> within_subsumption_budget(tick_cap, deadline_cap)
    return false unless self.within_budget
    return false if deadline_cap > 0 && ccall("__w_clock_ms") >= deadline_cap
    tick_cap == 0 || @ticks < tick_cap

  -> run_subsumption
    return false unless wassat_pre_any_dirty(@sub_dirty, @falive, @ftaut, @ncl) == 1
    tick_cap = 0
    work_cap = 0
    if @tick_budget > 0
      rem = @tick_budget - @ticks
      rem = 0 if rem < 0
      if @ncl_in > 20000
        tick_cap = @ticks + rem / 2
        work_cap = rem / 2
      else
        work_cap = rem
      work_cap = 1 if work_cap <= 0
    deadline_cap = 0
    if @deadline_ms > 0 && @ncl_in > 20000
      now = ccall("__w_clock_ms")
      rem_ms = @deadline_ms - now
      rem_ms = 0 if rem_ms < 0
      deadline_cap = now + rem_ms / 2
    progress = false
    sub_work = 0
    next_ci = 0
    while next_ci < @ncl && (work_cap == 0 || sub_work < work_cap) && self.within_subsumption_budget(tick_cap, deadline_cap) && @status == 0
      if @lgen + 2 * @ncl + 16 >= 2147483000
        wassat_pre_zero_i32(@lstamp, @lstamp.size)
        @lgen = 1
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
      @subscan_pm[8] = 0
      wassat_pre_subpass_dirty(@fla, @fcs, @fcl, @falive, @ftaut, @fsig, @oh, @on,
                               @ov, @ocount, @lstamp, @subscan_out, @subscan_pm,
                               @sub_dirty, 1)
      @ticks += @subscan_pm[5]
      sub_work += @subscan_pm[8]
      @lgen = @subscan_pm[0] + 2 * snapshot + 2
      hits = @subscan_out[0]
      k = 0
      while k < hits && @status == 0
        progress = true if self.commit_survivor(@subscan_out[3 * k + 1], @subscan_out[3 * k + 2], @subscan_out[3 * k + 3])
        k += 1
      next_ci = @subscan_pm[6]
    progress

  -> ensure_str_buf(need)
    if need > @str_cap
      ncap = @str_cap * 2
      ncap = need + 16 if ncap < need
      z = ccall("w_value_free_w", @str_buf) if @str_buf.size > 1
      @str_buf = i32[ncap]
      @str_cap = ncap
    0

  # Re-verify one native-scan survivor exactly over @fla and commit it:
  # flip == 0 is a subsumption (pure deletion), otherwise strengthen the
  # candidate by dropping the negated flip literal (add-then-delete).
  -> commit_survivor(sci, di, fl)
    return false unless @falive[sci] == 1 && @falive[di] == 1
    sst = @fcs[sci]
    slen = @fcl[sci]
    if fl == 0
      if wassat_pre_subset_flat(@fla, sst, slen, @fcs[di], @fcl[di]) == 1
        self.delete_clause(di)
        @clauses_subsumed += 1
        true
      else
        false
    else
      return false if @ftaut[di] == 1
      # Strengthen to fixpoint against this subsumer: dropping one negated
      # literal often exposes the next (the within-subsumer cascade the
      # immediate-commit flow used to find via its later flip scans).
      any = false
      target = di
      more = true
      first_flip = fl
      while more && @status == 0 && @falive[sci] == 1 && @falive[target] == 1
        tst = @fcs[target]
        tlen = @fcl[target]
        flipped = 0
        if first_flip != 0 && wassat_pre_subset_one_flip_flat(@fla, sst, slen, first_flip, tst, tlen) == 1
          flipped = first_flip
        else
          fi = 0
          while fi < slen && flipped == 0
            cand = @fla[sst + fi]
            flipped = cand if wassat_pre_subset_one_flip_flat(@fla, sst, slen, cand, tst, tlen) == 1
            fi += 1
        first_flip = 0
        if flipped == 0
          more = false
        else
          l = flipped
          nci = -1
          sn = 0
          unit_lit = 0
          if !@emit_wrat && (!@emit_drat || @flat_drat) && @lazy_lits
            self.ensure_str_buf(tlen)
            sn = wassat_pre_copy_without_lit(@fla, tst, tlen, 0 - l, @str_buf)
            unit_lit = @str_buf[0] if sn == 1
            self.drat_add_slice(@str_buf, 0, sn) if @flat_drat
            nci = self.store_from_buf(@str_buf, 0, sn)
          else
            strengthened = []
            ti = 0
            while ti < tlen
              dl = @fla[tst + ti]
              strengthened.push(dl) unless dl == 0 - l
              ti += 1
            sn = strengthened.size
            unit_lit = strengthened[0] if sn == 1
            gid = @next_gid
            self.plog_add(gid, strengthened, @emit_wrat ? [@fpgid[sci], @fpgid[target]] : [])
            nci = @lazy_lits ? self.store_from_buf_arr(strengthened) : self.store(strengthened)
          self.delete_clause(target)
          @clauses_strengthened += 1
          any = true
          if sn == 1 && @status == 0
            lv = self.value(unit_lit)
            if lv < 0
              self.refute(nci)
            elsif lv == 0
              self.assign(unit_lit, nci)
              confl = self.propagate_root
              self.refute(confl) if confl >= 0
          target = nci
          more = sn >= slen   # a further flip needs >= |C|
      any

  -> store_from_buf_arr(arr)
    n = arr.size
    self.ensure_str_buf(n)
    i = 0
    while i < n
      @str_buf[i] = arr[i]
      i += 1
    self.store_from_buf(@str_buf, 0, n)

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
    cands = i32[4 * cap + 1]
    pm = i64[8]
    pm[0] = @nvars
    pm[1] = cap
    pm[2] = WASSAT_PRE_AND2_BASE_SCAN_CAP
    pm[3] = WASSAT_PRE_AND2_SIDE_SCAN_CAP
    find_cap = WASSAT_PRE_AND2_FIND_TICK_CAP
    if @tick_budget > 0
      rem = @tick_budget - @ticks
      rem = 0 if rem < 0
      half = rem / 2
      find_cap = half if half > 0 && half < find_cap
    pm[6] = find_cap
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
    z = ccall("w_value_free_w", cands)
    wassat_prof_note("pre.and2 candidates=[@and2_candidates] eliminated=[@and2_eliminated] find_ticks=[pm[5]]")
    progress

  -> commit_bve_parents(v)
    wassat_pre_bve_parent_stats(@fla, @fcs, @fcl, @falive, @ftaut,
                                @oh, @on, @ov, v, @bve_pm)
    npos = @bve_pm[0]
    pos_nonpiv = @bve_pm[1]
    nneg = @bve_pm[2]
    neg_nonpiv = @bve_pm[3]
    push_pos = pos_nonpiv <= neg_nonpiv
    signed_piv = push_pos ? v : 0 - v
    push_li = push_pos ? 2 * v : 2 * v + 1
    need_entries = 1 + (push_pos ? npos : nneg)
    need_lits = push_pos ? pos_nonpiv : neg_nonpiv
    self.ensure_rstack(need_entries, need_lits)
    hdr = @rstack_hdr ## i32[]
    rlits = @rstack_lits ## i32[]
    @bve_pm[0] = @rstack_hend
    @bve_pm[1] = @rstack_lsize
    wassat_pre_push_bve_rstack(@fla, @fcs, @fcl, @falive, @ftaut,
                               @oh, @on, @ov, push_li, v, signed_piv,
                               hdr, rlits, @bve_pm)
    @rstack_hend = @bve_pm[0]
    @rstack_lsize = @bve_pm[1]
    if @flat_drat
      side = 0
      while side < 2
        w = @oh[2 * v + side]
        while w >= 0
          ci = @ov[w]
          if @falive[ci] == 1 && @ftaut[ci] == 0
            @falive[ci] = 0
            wassat_pre_retire_clause(@fla, @fcs[ci], @fcl[ci], @ocount, @bve_dirty)
            self.drat_del_slice(@fla, @fcs[ci], @fcl[ci])
          w = @on[w]
        side += 1
    elsif @emit_wrat || @emit_drat
      parents = self.live_occ(2 * v)
      w = @oh[2 * v + 1]
      while w >= 0
        ci = @ov[w]
        parents.push(ci) if @falive[ci] == 1 && @ftaut[ci] == 0
        w = @on[w]
      self.delete_batch(parents)
    else
      wassat_pre_retire_pivot_occ(@fla, @fcs, @fcl, @falive, @ftaut,
                                  @oh, @on, @ov, @ocount, @bve_dirty, v)
    0

  -> propagate_bve_units(units)
    return 0 if units == nil
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
    0

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

    count = @bve_pm[7]
    units = nil
    off = 0
    i = 0
    if !@emit_wrat && (!@emit_drat || @flat_drat) && @lazy_lits
      while i < count
        n = @bve_out[off]
        nci = self.store_from_buf(@bve_out, off + 3, n)
        self.drat_add_slice(@fla, @fcs[nci], n) if @flat_drat
        if n == 1
          units = [] if units == nil
          units.push(nci)
        off += 3 + n
        i += 1
    else
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
        self.plog_add(gid, res, @emit_wrat ? [@fpgid[aci], @fpgid[bci]] : [])
        nci = @lazy_lits ? self.store_from_buf(@bve_out, off + 3, n) : self.store(res)
        if n == 1
          units = [] if units == nil
          units.push(nci)
        off += 3 + n
        i += 1

    self.commit_bve_parents(v)
    @gone[v] = 1
    @bve_dirty[v] = 0
    @vars_eliminated += 1
    @and2_eliminated += 1
    # Propagate only after every pivot parent is gone.  Otherwise a new unit
    # can make a still-live parent imply the pivot, and derive a replacement
    # unit containing a variable that the artifact already marks eliminated.
    self.propagate_bve_units(units)
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
    wassat_pre_bve_scan_32(@fla, @fcs, @fcl, @falive, @ftaut, @oh, @on, @ov,
                           @lstamp, @bve_hash, @bve_hpos, @bve_out, @bve_pm, @lgen)
    @lgen = @bve_pm[8]
    @bve_hash_probes += @bve_pm[11]
    @bve_hash_hits += @bve_pm[9]
    @bve_compared_literals += @bve_pm[10]
    @ticks += @bve_pm[7]
    if @bve_pm[4] == 0
      @bve_dirty[v] = 0
      return false

    # The proposal contains copied literals and stable parent clause ids.
    # Reclaim before collecting occurrence lists or starting the atomic commit,
    # and only when this proposal would otherwise grow the backing buffers.
    needed = @bve_pm[12]
    if @vars_eliminated > @compact_after_eliminated && @fasize >= @compact_retry_fasize && (@fasize + needed > @facap || @osize + needed > @ocap)
      return false if self.cancelled
      self.compact_live_storage
      return false unless self.within_budget

    # commit from the packed buffer: all resolvents added, all originals
    # deleted, or nothing — the atomicity contract is unchanged
    count = @bve_pm[5]
    units = nil
    off = 0
    i = 0
    if !@emit_wrat && (!@emit_drat || @flat_drat) && @lazy_lits
      while i < count
        n = @bve_out[off]
        nci = self.store_from_buf(@bve_out, off + 3, n)
        self.drat_add_slice(@fla, @fcs[nci], n) if @flat_drat
        if n == 1
          units = [] if units == nil
          units.push(nci)
        off += 3 + n
        i += 1
    else
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
        self.plog_add(gid, res, @emit_wrat ? [@fpgid[aci], @fpgid[bci]] : [])
        nci = @lazy_lits ? self.store_from_buf(@bve_out, off + 3, n) : self.store(res)
        if n == 1
          units = [] if units == nil
          units.push(nci)
        off += 3 + n
        i += 1
    self.commit_bve_parents(v)
    @gone[v] = 1
    @bve_dirty[v] = 0
    @vars_eliminated += 1
    self.propagate_bve_units(units)
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
    eff_margin = @bve_margin_override < 0 ? @bve_margin : @bve_margin_override
    if eff_margin > @last_bve_margin
      wassat_pre_fill_i8(@bve_dirty, @nvars + 1, 1)
    @last_bve_margin = eff_margin
    self.ensure_sort_scratch
    cnt = @sort_cnt ## i64[]
    vars = @sort_vars ## i32[]
    total = wassat_pre_sort_bve_vars(@passign, @gone, @frozen, @bve_dirty,
                                     @ocount, cnt, vars, @nvars)
    progress = false
    i = 0
    while i < total && @status == 0 && self.within_budget
      progress = true if self.try_eliminate(vars[i])
      i += 1
    wassat_prof_note("pre.bve_hash probes=[@bve_hash_probes] hits=[@bve_hash_hits] compared_literals=[@bve_compared_literals]") if env("WASSAT_PROFILE") == "1"
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
    @tick_budget = @ticks + @heavy_ticks if @heavy_ticks > 0
    self.set_deadline_ms(@heavy_stage_ms) if @heavy_stage_ms > 0
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
    # Inputs above 20,000 clauses get two passes, and used to get both at
    # zero growth. With eight clauses of growth per pivot the heavy arm's
    # search propagates half as much on b21, takes 23M ticks instead of 99M
    # on Wallace_Bits_Fast_8, and reaches SC21_Timetable_C_527 inside 600M
    # ticks; over 56 inputs at that budget it solved 16 at zero growth, 20
    # at eight and 19 at sixteen. The certificate path keeps zero growth:
    # not measured there.
    if @ncl_in > 20000 && @proof_mode == WASSAT_PROOF_NONE && @bve_margin < wassat_pre_big_margin
      @bve_margin = wassat_pre_big_margin
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
    keep_unit = i8[@ncl + @ftsize + 2]
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
    doomed_buf = i32[@ncl + 1]
    ndoomed = wassat_pre_find_satisfied(@fla, @fcs, @fcl, @falive, @ftaut,
                                        @passign, keep_unit, doomed_buf, @ncl)
    self.delete_batch_buf(doomed_buf, ndoomed) if ndoomed > 0
    z = ccall("w_value_free_w", keep_unit)
    z = ccall("w_value_free_w", doomed_buf)
    0

  # ---- artifact -------------------------------------------------------------

  -> artifact
    self.flush_rstack
    # A substituted variable that ended up root-assigned during the rewrite
    # cascades is pinned by a live unit clause, so it is not "gone" in the
    # assumption/consistency sense (reconstruction still overwrites it with
    # the representative's value, which the equivalence makes identical).
    v = 1
    while v <= @nvars
      @gone[v] = 0 if @gone[v] == 2 && @passign[v] != 0
      v += 1
    # Boxed clauses are consumed only by the small-kernel SLS burst and
    # the portfolio artifact writer; on trusted-path flat formulas every
    # downstream consumer reads the flat mirrors, and materializing lazy
    # clauses here would undo the lazy-truth win — twice per run.
    # Proof callers construct the logical clause database from this mirror
    # unless flat DRAT output was requested; otherwise entries stay aligned
    # with gids even above the lazy threshold.
    skip_boxed = ((@stop_cell != nil || @flat_consumer) && @proof_mode == WASSAT_PROOF_NONE && @lazy_lits) || (@flat_proof_output && @proof_mode == WASSAT_PROOF_DRAT)
    want_boxed = !skip_boxed && (@proof_mode != WASSAT_PROOF_NONE || !@lazy_lits || @ncl <= 50000)
    clauses = []
    gids = []
    unless skip_boxed
      ci = 0
      while ci < @ncl
        if @falive[ci] == 1
          clauses.push(self.lits_of(ci)) if want_boxed
          gids.push(@fpgid.size > ci ? @fpgid[ci] : ci + 1)
        ci += 1
    out_fpgid = @proof_mode == WASSAT_PROOF_WRAT ? @fpgid : i64[0]
    art = { "nvars": @nvars, "clauses": clauses, "gids": gids,
            "counter_base": @counter_base, "raw": @raw_kernel,
            "next_gid": @next_gid, "status": @status, "config": @config,
            "stack": @stack.dup, "gone": @gone, "gone_bits": 8,
            "fla": @fla, "fla_bits": 32,
            "fcs": @fcs, "fcl": @fcl, "falive": @falive,
            "ftaut": @ftaut, "fpgid": out_fpgid, "fncl": @ncl,
            "wrat": @wrat_lines, "drat": @drat_lines,
            "stats": { "probes": @probes_run, "probes_failed": @probes_failed,
                       "vars_substituted": @vars_substituted,
                       "scc_runs": @scc_runs, "scc_nodes": @scc_nodes,
                       "scc_components": @scc_components, "scc_singletons": @scc_singletons,
                       "scc_peak_frames": @scc_peak_frames,
                       "scc_edges": @scc_edges, "scc_graph_bytes": @scc_graph_bytes,
                       "clauses_subsumed": @clauses_subsumed,
                       "clauses_strengthened": @clauses_strengthened,
                       "vars_eliminated": @vars_eliminated,
                       "storage_compactions": @storage_compactions,
                       "storage_compaction_ms": @storage_compaction_ms,
                       "storage_scanned_clauses": @storage_scanned_clauses,
                       "storage_compacted_literals": @storage_compacted_literals,
                       "storage_reclaimed_literals": @storage_reclaimed_literals,
                       "storage_reclaimed_occurrences": @storage_reclaimed_occurrences,
                       "bve_hash_probes": @bve_hash_probes,
                       "bve_hash_hits": @bve_hash_hits,
                       "bve_compared_literals": @bve_compared_literals,
                       "and2_candidates": @and2_candidates,
                       "and2_eliminated": @and2_eliminated,
                       "root_prop_scanned": @pst[4], "root_prop_visits": @pst[5],
                       "root_prop_two_open": @pst[6],
                       "ticks": @ticks } }
    if @flat_proof_output
      @dbytes = u8[1] if @dbytes == nil
      art["drat_bytes"] = @dbytes
      art["drat_bpos"] = @dbpos
    art

# Count and fill use the same admission rule: live, non-tautological binary
# clauses with distinct, unassigned literals. Both directions retain input
# clause order, including parallel edges and their proof references.
# A repeated literal is not an implication edge: proof replay sees two
# unassigned occurrences, so it cannot justify a unit through that clause.
-> wassat_pre_graph_count(ar, cs, cl, alive, taut, asg, offsets, ncl, n) (i32[] i32[] i32[] i8[] i8[] i8[] i32[] i64 i64) i64
  i = 0
  while i <= n
    offsets[i] = 0
    i += 1
  ci = 0
  while ci < ncl
    if alive[ci] == 1 && taut[ci] == 0 && cl[ci] == 2
      a = ar[cs[ci]] ## i64
      b = ar[cs[ci] + 1] ## i64
      sa = a >> 63
      sb = b >> 63
      av = (a ^ sa) - sa
      bv = (b ^ sb) - sb
      if a != b && asg[av] == 0 && asg[bv] == 0
        ai = ((av << 1) + (sa & 1)) ^ 1
        bi = ((bv << 1) + (sb & 1)) ^ 1
        offsets[ai + 1] += 1
        offsets[bi + 1] += 1
    ci += 1
  i = 0
  while i < n
    offsets[i + 1] += offsets[i]
    i += 1
  offsets[n]

-> wassat_pre_graph_fill(ar, cs, cl, alive, taut, asg, offsets, cursor, targets, clauses, ncl, n) (i32[] i32[] i32[] i8[] i8[] i8[] i32[] i32[] i32[] i32[] i64 i64)
  i = 0
  while i < n
    cursor[i] = offsets[i]
    i += 1
  ci = 0
  while ci < ncl
    if alive[ci] == 1 && taut[ci] == 0 && cl[ci] == 2
      a = ar[cs[ci]] ## i64
      b = ar[cs[ci] + 1] ## i64
      sa = a >> 63
      sb = b >> 63
      av = (a ^ sa) - sa
      bv = (b ^ sb) - sb
      if a != b && asg[av] == 0 && asg[bv] == 0
        ai = (av << 1) + (sa & 1)
        bi = (bv << 1) + (sb & 1)
        at = cursor[ai ^ 1]
        targets[at] = bi
        clauses[at] = ci
        cursor[ai ^ 1] = at + 1
        at = cursor[bi ^ 1]
        targets[at] = ai
        clauses[at] = ci
        cursor[bi ^ 1] = at + 1
    ci += 1
  0

# Native root-level unit propagation over the flat clause arena and the
# intrusive occurrence lists. Same reasoning as the solver's native helpers:
# typed array parameters keep literal reads raw machine integers.
#
#   st[0] = qhead   st[1] = trail size   st[2] = conflict ci or -1
#   st[3] = accumulated budget ticks (full clause lengths)
#   st[4..6] = cumulative scanned literals / live clause visits / two-open stops
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

-> wassat_pre_prop(fla, fcs, fcl, falive, ftaut, och, ocn, ocv, asg, rsn, tps, tr, st) (i32[] i32[] i32[] i8[] i8[] i32[] i32[] i32[] i8[] i32[] i32[] i32[] i64[])
  qhead = st[0]
  tsize = st[1]
  conflict = -1
  ticks = 0
  scanned = 0
  visits = 0
  two_open = 0
  while qhead < tsize && conflict < 0
    p = tr[qhead]
    qhead += 1
    neg = 0 - p
    li = 0 ## i64
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
        visits += 1
        ticks = ticks + n
        sat = 0
        unassigned = 0
        unit = 0
        j = 0
        while j < n
          l = fla[stx + j]
          j += 1
          vv = 0
          if l > 0
            vv = asg[l]
          else
            vv = 0 - asg[0 - l]
          if vv > 0
            sat = 1
            break
          else
            if vv == 0
              unassigned = unassigned + 1
              unit = l
              # Two open literals rule out both a unit and a conflict.
              # Keep charging the original clause length to the budget.
              if unassigned == 2
                two_open += 1
                break
        scanned += j
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
  st[4] += scanned
  st[5] += visits
  st[6] += two_open
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
-> wassat_pre_subpass(fla, fcs, fcl, falive, ftaut, fsig, och, ocn, ocv, ocount, lstamp, out, pm) (i32[] i32[] i32[] i8[] i8[] i64[] i32[] i32[] i32[] i32[] i32[] i64[] i64[])
  dummy = i8[1]
  wassat_pre_subpass_dirty(fla, fcs, fcl, falive, ftaut, fsig, och, ocn, ocv,
                           ocount, lstamp, out, pm, dummy, 0)
  z = ccall("w_value_free_w", dummy)
  0

-> wassat_pre_subpass_dirty(fla, fcs, fcl, falive, ftaut, fsig, och, ocn, ocv, ocount, lstamp, out, pm, sub_dirty, use_dirty) (i32[] i32[] i32[] i8[] i8[] i64[] i32[] i32[] i32[] i32[] i32[] i64[] i64[] i8[] i64)
  base = pm[0]
  sci = pm[1]
  endci = pm[2]
  if base + 2 * endci + 16 >= 2147483000
    wassat_pre_zero_i32(lstamp, lstamp.size)
    base = 2
    pm[0] = base
  cap = pm[3]
  budget = pm[4]
  tcap = pm[7]
  tcap = 9223372036854775807 if tcap <= 0
  visit_cap = 4 * cap
  ticks = 0
  # `ticks` is the CALIBRATED currency the budgets in policy.w are quoted
  # in, and it is charged only for a candidate that survives to the literal
  # match. `work` charges the walk too, so chunk boundaries and run_subsumption
  # work caps track real time even when signature filtering rejects everything.
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
    if keep == 0
      sub_dirty[sci] = 0 if use_dirty == 1
    else
      sci_dirty = 1
      sci_dirty = sub_dirty[sci] if use_dirty == 1
      gen_pos = base + 2 * sci
      gen_neg = gen_pos + 1
      stx = fcs[sci]
      csig = fsig[sci]
      # Stamp both polarities and find the two rarest positive buckets.
      has_dup = 0
      best_li1 = -1 ## i64
      best_cnt1 = 0
      best_li2 = -1 ## i64
      best_cnt2 = 0
      l_best1 = 0
      j = 0
      while j < slen
        l = fla[stx + j]
        li = 0 ## i64
        if l > 0
          li = l << 1
        else
          li = ((0 - l) << 1) + 1
        if lstamp[li] == gen_pos
          has_dup = 1
        else
          lstamp[li] = gen_pos
          lstamp[li ^ 1] = gen_neg
          c = ocount[li]
          if best_li1 < 0 || c < best_cnt1
            best_li2 = best_li1
            best_cnt2 = best_cnt1
            best_li1 = li
            best_cnt1 = c
            l_best1 = l
          elsif best_li2 < 0 || c < best_cnt2
            best_li2 = li
            best_cnt2 = c
        j += 1

      # Walk 1 (och[best_li1]): covers all subsumptions (mode 0) plus any
      # 1-flip strengthening (mode 1) where the flipped literal is NOT l_best1.
      scanned = 0
      visits = 0
      prev_ci = -1
      w = och[best_li1]
      while w >= 0 && scanned < cap && visits < visit_cap
        ci = ocv[w]
        visits = visits + 1
        work = work + 1
        ok = 1
        if ci == sci || ci == prev_ci
          ok = 0
        prev_ci = ci
        if ok == 1 && use_dirty == 1 && sci_dirty == 0 && sub_dirty[ci] == 0
          ok = 0
        if ok == 1 && falive[ci] != 1
          ok = 0
        n = 0
        if ok == 1
          scanned = scanned + 1
          n = fcl[ci]
          if n < slen || n < 2
            ok = 0
        if ok == 1
          if (csig & fsig[ci]) != csig
            ok = 0
        if ok == 1
          dstx = fcs[ci]
          ticks = ticks + n
          work = work + n
          pos_matched = 0
          neg_l2 = 0
          neg_conflict = 0
          j = 0
          while j < n
            l2 = fla[dstx + j]
            lidx = 0 ## i64
            if l2 > 0
              lidx = l2 << 1
            else
              lidx = ((0 - l2) << 1) + 1
            sv = lstamp[lidx]
            if sv == gen_pos
              pos_matched = pos_matched + 1
            elsif sv == gen_neg
              if neg_l2 == 0
                neg_l2 = l2
              elsif neg_l2 != l2
                neg_conflict = 1
            j = j + 1
          if pos_matched >= slen && count < 5400
            out[3 * count + 1] = sci
            out[3 * count + 2] = ci
            out[3 * count + 3] = 0
            count = count + 1
          if has_dup == 0 && ftaut[ci] == 0 && neg_l2 != 0 && neg_conflict == 0 && pos_matched >= slen - 1 && count < 5400
            out[3 * count + 1] = sci
            out[3 * count + 2] = ci
            out[3 * count + 3] = 0 - neg_l2
            count = count + 1
        w = ocn[w]

      # Walk 2: only needed when has_dup == 0, solely to find mode 1 hits where
      # l_best1 itself was flipped (so ci contains -l_best1 and, if slen >= 2,
      # every remaining literal of sci including best_li2). Pick whichever of
      # och[best_li1 ^ 1] and och[best_li2] has fewer live occurrences.
      if has_dup == 0
        flip1 = 0 - l_best1
        flip1_li = best_li1 ^ 1
        walk2_li = flip1_li
        if best_li2 >= 0 && ocount[best_li2] < ocount[flip1_li]
          walk2_li = best_li2
        scanned = 0
        visits = 0
        prev_ci = -1
        w = och[walk2_li]
        while w >= 0 && scanned < cap && visits < visit_cap
          ci = ocv[w]
          visits = visits + 1
          work = work + 1
          ok = 1
          if ci == sci || ci == prev_ci
            ok = 0
          prev_ci = ci
          if ok == 1 && use_dirty == 1 && sci_dirty == 0 && sub_dirty[ci] == 0
            ok = 0
          if ok == 1 && (falive[ci] != 1 || ftaut[ci] == 1)
            ok = 0
          n = 0
          if ok == 1
            scanned = scanned + 1
            n = fcl[ci]
            if n < slen || n < 2
              ok = 0
          if ok == 1
            if (csig & fsig[ci]) != csig
              ok = 0
          if ok == 1
            dstx = fcs[ci]
            ticks = ticks + n
            work = work + n
            pos_matched = 0
            flip1_seen = 0
            j = 0
            while j < n
              l2 = fla[dstx + j]
              if l2 == flip1
                flip1_seen = 1
              else
                lidx = 0 ## i64
                if l2 > 0
                  lidx = l2 << 1
                else
                  lidx = ((0 - l2) << 1) + 1
                if lstamp[lidx] == gen_pos
                  pos_matched = pos_matched + 1
              j = j + 1
            if flip1_seen == 1 && pos_matched >= slen - 1 && count < 5400
              out[3 * count + 1] = sci
              out[3 * count + 2] = ci
              out[3 * count + 3] = l_best1
              count = count + 1
          w = ocn[w]
      if use_dirty == 1 && count < 5400
        sub_dirty[sci] = 0
    sci += 1
  out[0] = count
  pm[5] = pm[5] + ticks
  pm[6] = sci
  pm[8] = work
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
-> wassat_pre_find_and2(fla, fcs, fcl, falive, ftaut, och, ocn, ocv, asg, gone, frozen, out, pm) (i32[] i32[] i32[] i8[] i8[] i32[] i32[] i32[] i8[] i8[] i8[] i32[] i64[])
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
-> wassat_pre_and2_bve_scan(fla, fcs, fcl, falive, ftaut, och, ocn, ocv, lstamp, hbuf, hpos, out, pm) (i32[] i32[] i32[] i8[] i8[] i32[] i32[] i32[] i32[] i64[] i64[] i64[] i64[])
  o = pm[0]
  baseci = pm[1]
  side1 = pm[2]
  side2 = pm[3]
  paircap = pm[4]
  outcap = pm[5] ## i64
  gen = pm[9]
  occcap = pm[10]
  hashcap = pm[12] ## i64
  # The caller passes logical bounds for experiments, but these native loops
  # also defend the actual reusable allocations.  Packed output and
  # hash/header slots are separate resources and are clamped independently.
  max_outcap = WASSAT_PRE_BVE_OUT_CAPACITY ## i64
  max_hashcap = WASSAT_PRE_BVE_HASH_CAPACITY ## i64
  outcap = max_outcap if outcap > max_outcap
  hashcap = max_hashcap if hashcap > max_hashcap
  hash_epoch = gen + 1
  if gen + paircap + 16 >= 2147483000
    wassat_pre_zero_i32(lstamp, lstamp.size)
    gen = 1
    hash_epoch = 1
    hi = 0
    while hi < hashcap
      hpos[hi] = -1
      hi += 1
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
              vacant = -1
              probes = 0
              slot = 0
              if hashcap > 0
                folded = (h ^ (h >> 32)) & 2147483647
                if (hashcap & (hashcap - 1)) == 0
                  slot = folded & (hashcap - 1)
                else
                  slot = folded % hashcap
              while probes < hashcap && isdup == 0 && vacant < 0
                encoded = hpos[slot]
                probes = probes + 1
                if (encoded >> 17) != hash_epoch
                  vacant = slot
                elsif hbuf[slot] == h && out[encoded & 131071] == rl
                  sp = encoded & 131071
                  same = 1
                  q = 0
                  while q < rl && same == 1
                    lq = out[sp + 3 + q]
                    avq = lq
                    if lq < 0
                      avq = 0 - lq
                    liq = avq + avq
                    if lq < 0
                      liq = liq + 1
                    if lstamp[liq] != gen
                      same = 0
                    q = q + 1
                  if same == 1
                    isdup = 1
                slot = slot + 1
                slot = 0 if slot == hashcap
              if isdup == 0
                if count >= hashcap || vacant < 0
                  valid = 0
                else
                  hbuf[vacant] = h
                  hpos[vacant] = (hash_epoch << 17) | hdr
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
#   pm[9..11] hash work(out)  pm[12] proposed literal count(out)
# Compatibility wrapper for unit specs passing either i64[] or i32[]/i8[]
# fixtures directly to wassat_pre_bve_scan. Hot production BVE calls
# wassat_pre_bve_scan_32 directly.
-> wassat_pre_bve_scan(fla, fcs, fcl, falive, ftaut, och, ocn, ocv, lstamp, hbuf, hpos, out, pm, lgen0)
  tfla = i32[fla.size]
  tfcs = i32[fcs.size]
  tfcl = i32[fcl.size]
  tal = i8[falive.size]
  ttt = i8[ftaut.size]
  toh = i32[och.size]
  ton = i32[ocn.size]
  tov = i32[ocv.size]
  tls = i32[lstamp.size]
  i = 0
  while i < fla.size
    tfla[i] = fla[i]
    i += 1
  i = 0
  while i < fcs.size
    tfcs[i] = fcs[i]
    i += 1
  i = 0
  while i < fcl.size
    tfcl[i] = fcl[i]
    i += 1
  i = 0
  while i < falive.size
    tal[i] = falive[i]
    i += 1
  i = 0
  while i < ftaut.size
    ttt[i] = ftaut[i]
    i += 1
  i = 0
  while i < och.size
    toh[i] = och[i]
    i += 1
  i = 0
  while i < ocn.size
    ton[i] = ocn[i]
    i += 1
  i = 0
  while i < ocv.size
    tov[i] = ocv[i]
    i += 1
  if lgen0 + pm[2] + 16 < 2147483000
    i = 0
    while i < lstamp.size
      tls[i] = lstamp[i]
      i += 1
  wassat_pre_bve_scan_32(tfla, tfcs, tfcl, tal, ttt, toh, ton, tov, tls, hbuf, hpos, out, pm, lgen0)
  i = 0
  while i < lstamp.size
    lstamp[i] = tls[i]
    i += 1
  z = ccall("w_value_free_w", tfla)
  z = ccall("w_value_free_w", tfcs)
  z = ccall("w_value_free_w", tfcl)
  z = ccall("w_value_free_w", tal)
  z = ccall("w_value_free_w", ttt)
  z = ccall("w_value_free_w", toh)
  z = ccall("w_value_free_w", ton)
  z = ccall("w_value_free_w", tov)
  z = ccall("w_value_free_w", tls)
  0

-> wassat_pre_bve_scan_32(fla, fcs, fcl, falive, ftaut, och, ocn, ocv, lstamp, hbuf, hpos, out, pm, lgen0) (i32[] i32[] i32[] i8[] i8[] i32[] i32[] i32[] i32[] i64[] i64[] i64[] i64[] i64)
  v = pm[0]
  margin = pm[1]
  prodcap = pm[2]
  outcap = pm[3] ## i64
  hashcap = pm[6] ## i64
  max_outcap = WASSAT_PRE_BVE_OUT_CAPACITY ## i64
  max_hashcap = WASSAT_PRE_BVE_HASH_CAPACITY ## i64
  outcap = max_outcap if outcap > max_outcap
  hashcap = max_hashcap if hashcap > max_hashcap
  # A header offset occupies 17 bits. Tag the existing header table with
  # this pivot's first literal-stamp generation, avoiding a full clear for
  # every pivot. Wrap cleanly before overflowing signed 32-bit lstamp.
  gen = lgen0
  hash_epoch = lgen0 + 1
  if lgen0 + prodcap + 16 >= 2147483000
    wassat_pre_zero_i32(lstamp, lstamp.size)
    gen = 1
    hash_epoch = 1
    hi = 0
    while hi < hashcap
      hpos[hi] = -1
      hi += 1
  ticks = 0
  hash_probes = 0
  hash_hits = 0
  compared_literals = 0
  pm[11] = 0
  pm[9] = 0
  pm[10] = 0
  pm[12] = 0
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
                  vacant = -1
                  probes = 0
                  slot = 0
                  if hashcap > 0
                    folded = (h ^ (h >> 32)) & 2147483647
                    if (hashcap & (hashcap - 1)) == 0
                      slot = folded & (hashcap - 1)
                    else
                      slot = folded % hashcap
                  while probes < hashcap && isdup == 0 && vacant < 0
                    encoded = hpos[slot]
                    probes += 1
                    if (encoded >> 17) != hash_epoch
                      vacant = slot
                    elsif hbuf[slot] == h && out[encoded & 131071] == rl
                      hash_hits += 1
                      sp = encoded & 131071
                      same = 1
                      q = 0
                      while q < rl && same == 1
                        lq = out[sp + 3 + q]
                        avq = lq
                        if lq < 0
                          avq = 0 - lq
                        liq = avq + avq
                        if lq < 0
                          liq = liq + 1
                        q += 1
                        if lstamp[liq] != gen
                          same = 0
                      compared_literals += q
                      if same == 1
                        isdup = 1
                    slot += 1
                    slot = 0 if slot == hashcap
                  hash_probes += probes
                  if isdup == 0
                    if count >= hashcap || vacant < 0
                      feasible = 0
                    else
                      hbuf[vacant] = h
                      hpos[vacant] = (hash_epoch << 17) | hdr
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
      pm[11] = hash_probes
      pm[9] = hash_hits
      pm[10] = compared_literals
      pm[12] = new_lits
      pm[4] = feasible
      pm[5] = count
      pm[7] = ticks
      pm[8] = gen
      0

-> wassat_pre_subst_rewrite_flat(fla, fcs, fcl, falive, ftaut, fsig, och, ocn, ocv, ocount, passign, replit, units, pm) (i32[] i32[] i32[] i8[] i8[] i64[] i32[] i32[] i32[] i32[] i8[] i32[] i32[] i64[]) i64
  dummy_sub = i8[pm[0] + 1]
  dummy_bve = i8[pm[1] + 2]
  r = wassat_pre_subst_rewrite_flat_dirty(fla, fcs, fcl, falive, ftaut, fsig,
                                          och, ocn, ocv, ocount, passign, replit,
                                          units, pm, dummy_sub, dummy_bve)
  z = ccall("w_value_free_w", dummy_sub)
  z = ccall("w_value_free_w", dummy_bve)
  r

-> wassat_pre_subst_rewrite_flat_dirty(fla, fcs, fcl, falive, ftaut, fsig, och, ocn, ocv, ocount, passign, replit, units, pm, sub_dirty, bve_dirty) (i32[] i32[] i32[] i8[] i8[] i64[] i32[] i32[] i32[] i32[] i8[] i32[] i32[] i64[] i8[] i8[]) i64
  ncl = pm[0]
  nv = pm[1]
  ticks = 0
  nunits = 0
  ci = 0
  while ci < ncl
    if falive[ci] == 1 && ftaut[ci] == 0
      st = fcs[ci]
      len = fcl[ci]
      sat_root = 0
      has_subst = 0
      i = 0
      while i < len
        l = fla[st + i]
        av = l < 0 ? 0 - l : l
        pa = passign[av]
        if (l > 0 && pa > 0) || (l < 0 && pa < 0)
          sat_root = 1
        if replit[av] != 0
          has_subst = 1
        i += 1
      if sat_root == 0 && has_subst == 1
        ticks += len
        w = 0
        taut = 0
        sig = 0 ## i64
        i = 0
        while i < len
          l = fla[st + i]
          av = l < 0 ? 0 - l : l
          bve_dirty[av] = 1
          rl = replit[av]
          if rl != 0
            l = l > 0 ? rl : 0 - rl
          dup = 0
          j = 0
          while j < w
            prev = fla[st + j]
            if prev == l
              dup = 1
            elsif prev == 0 - l
              taut = 1
            j += 1
          if dup == 0
            fla[st + w] = l
            wav = l < 0 ? 0 - l : l
            bve_dirty[wav] = 1
            sig = sig | ((1 ## i64) << (wav & 63))
            w += 1
          i += 1
        if taut == 1
          falive[ci] = 0
          ftaut[ci] = 1
          sub_dirty[ci] = 0
        else
          fcl[ci] = w
          fsig[ci] = sig
          sub_dirty[ci] = 1
          if w == 1
            units[nunits] = ci
            nunits += 1
    ci += 1
  li = 0
  limit = 2 * nv + 2
  while li < limit
    och[li] = 0 - 1
    ocount[li] = 0
    li += 1
  osize = 0
  ci = 0
  while ci < ncl
    if falive[ci] == 1
      st = fcs[ci]
      len = fcl[ci]
      is_taut = ftaut[ci]
      j = 0
      while j < len
        l = fla[st + j]
        av = l < 0 ? 0 - l : l
        lidx = av << 1
        lidx = lidx + 1 if l < 0
        ocount[lidx] = ocount[lidx] + 1
        if is_taut == 0
          ocn[osize] = och[lidx]
          ocv[osize] = ci
          och[lidx] = osize
          osize += 1
        j += 1
    ci += 1
  pm[2] = osize
  pm[3] = ticks
  pm[4] = nunits
  0

# Native mirror intake from the parser's flat arrays: copy the literal
# arena, compute per-clause tautology marks and 64-bit signatures, build
# the intrusive occurrence lists, and assign sequential proof ids —
# everything store() did per boxed literal, in one pass.
#   pm[0] in: clause count   pm[1] out: arena size   pm[2] out: occ nodes
-> wassat_pre_intake(slits, soffs, slens, fla, fcs, fcl, falive, ftaut, fsig, fpgid, och, ocn, ocv, ocount, pm) (i64[] i64[] i64[] i32[] i32[] i32[] i8[] i8[] i64[] i64[] i32[] i32[] i32[] i32[] i64[])
  ncl = pm[0]
  has_pgid = fpgid.size > 0
  asize = 0
  osize = 0
  k = 0
  while k < ncl
    o = soffs[k]
    n = slens[k]
    fcs[k] = asize
    fcl[k] = n
    falive[k] = 1
    fpgid[k] = k + 1 if has_pgid
    sig = 0 ## i64
    t = 0
    j = 0
    while j < n
      l = slits[o + j]
      fla[asize + j] = l
      av = l
      if l < 0
        av = 0 - l
      sig = sig | ((1 ## i64) << (av & 63))
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
-> wassat_raw_artifact(parse, nvars, cfg = nil)
  ncl = parse["flat_ncl"]
  c = cfg == nil ? parse["config"] : cfg
  c = WassatConfig.from_lens(nvars, parse["flat_lens"], ncl) if c == nil || c.nvars != nvars || c.nclauses != ncl
  # No side tables at all: every clause is alive and proof ids are
  # sequential, so the loader synthesizes both from the index ("fsynth").
  # Materializing them cost three ncl-sized allocations plus their fills —
  # 7.8MB and ~5ms on bmc-ibm-10 — for data that is either constant or,
  # in the case of proof ids, never read on this path.
  empty = i64[0]
  { "nvars": nvars, "clauses": [], "gids": [], "raw": true,
    "config": c,
    "next_gid": ncl + 1, "status": 0,
    "stack": [], "gone": nvars >= 50000000 ? i8[1] : i8[nvars + 2],
    "gone_bits": 8,
    "fla": parse["flat_lits"], "fcs": parse["flat_offs"],
    "fcl": parse["flat_lens"], "falive": empty,
    "ftaut": empty, "fpgid": empty, "fncl": ncl, "fsynth": true,
    "formula_ref": parse,
    "wrat": [], "drat": [],
    "stats": { "probes": 0, "probes_failed": 0,
               "vars_substituted": 0,
               "scc_runs": 0, "scc_nodes": 0, "scc_components": 0,
               "scc_singletons": 0, "scc_peak_frames": 0,
               "scc_edges": 0, "scc_graph_bytes": 0,
               "clauses_subsumed": 0,
               "clauses_strengthened": 0,
               "vars_eliminated": 0,
               "bve_hash_probes": 0,
               "bve_hash_hits": 0,
               "bve_compared_literals": 0,
               "and2_candidates": 0,
               "and2_eliminated": 0,
               "root_prop_scanned": 0, "root_prop_visits": 0,
               "root_prop_two_open": 0,
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
  gone = art["gone"]
  assumptions.each -> (a)
    raise "assumption literal must not be zero" if a == 0
    v = a.abs
    if art.has_key?("counter_base") && art["counter_base"] > 0 && v >= art["counter_base"]
      raise "assumption names rewritten counter variable [v]; freeze it before preprocessing"
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
  return model if stack.empty? && model.size == nvars && nvars >= 100000
  sign = i8[nvars + 1]
  i = 0
  while i < model.size
    l = model[i]
    sign[l.abs] = l > 0 ? 1 : -1
    i += 1
  # default every eliminated pivot against its pushed polarity
  si = 0
  while si < stack.size
    e = stack[si]
    kind = e["kind"]
    if kind == "flat_batch"
      hdr = e["hdr"] ## i32[]
      hs = e["hstart"] ## i64
      he = e["hend"] ## i64
      wassat_reconstruct_batch_defaults(hdr, sign, hs, he)
    elsif kind == "bve_var"
      p = e["pivot"]
      sign[p.abs] = p > 0 ? -1 : 1
    si += 1
  # reverse walk: later transformations undone first
  si = stack.size - 1
  while si >= 0
    e = stack[si]
    kind = e["kind"]
    if kind == "flat_batch"
      hdr = e["hdr"] ## i32[]
      lits = e["lits"] ## i32[]
      hs = e["hstart"] ## i64
      he = e["hend"] ## i64
      wassat_reconstruct_batch_reverse(hdr, lits, sign, hs, he)
    elsif kind == "bve"
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
    elsif kind == "counter_rewrite"
      z = wassat_pre_counter_lift_sign_i8(sign, e["gates"], e["meta"])
    elsif kind == "subst"
      r = e["rep"]
      rv = r > 0 ? sign[r.abs] : 0 - sign[r.abs]
      sign[e["var"]] = rv
    si -= 1
  out = []
  v = 1
  while v <= nvars
    out.push(sign[v] >= 0 ? v : 0 - v)
    v += 1
  z = ccall("w_value_free_w", sign)
  out

-> wassat_pre_counter_lift_sign_i8(sign, gates, m) (i8[] i64[] i64[]) i64
  g = 0 ## i64
  while g < m[3]
    p = g * 5 ## i64
    a = sign[gates[p + 2]] > 0 ## bool
    b = sign[gates[p + 3]] > 0 ## bool
    op = gates[p] ## i64
    value = op == 1 ? a || b : a && b ## bool
    value = a || (b && sign[gates[p + 4]] > 0) if op == 3
    sign[gates[p + 1]] = value ? 1 : -1
    g += 1
  1

-> wassat_reconstruct_batch_defaults(hdr, sign, hstart, hend) (i32[] i8[] i64 i64) i64
  k = hstart
  while k < hend
    base = 4 * k
    if hdr[base] == 1
      p = hdr[base + 1]
      pv = p >= 0 ? p : 0 - p
      sign[pv] = p > 0 ? -1 : 1
    k += 1
  0

-> wassat_reconstruct_batch_reverse(hdr, lits, sign, hstart, hend) (i32[] i32[] i8[] i64 i64) i64
  k = hend - 1
  while k >= hstart
    base = 4 * k
    tag = hdr[base]
    if tag == 2
      p = hdr[base + 1]
      pv = p >= 0 ? p : 0 - p
      pval = p > 0 ? sign[pv] : 0 - sign[pv]
      if pval <= 0
        off = hdr[base + 2]
        len = hdr[base + 3]
        sat = 0
        j = 0
        while j < len && sat == 0
          l = lits[off + j]
          lv = l >= 0 ? l : 0 - l
          if (l > 0 ? sign[lv] : 0 - sign[lv]) > 0
            sat = 1
          j += 1
        if sat == 0
          sign[pv] = p > 0 ? 1 : -1
    elsif tag == 3
      yv = hdr[base + 1]
      r = hdr[base + 2]
      rv = r >= 0 ? r : 0 - r
      sign[yv] = r > 0 ? sign[rv] : 0 - sign[rv]
    k -= 1
  0

# Clause ids and proof ids remain stable. Store order makes source offsets
# monotone, so live literals can be packed down in place. Rebuild occurrence
# links in the original clause/literal order, leaving heuristic counts intact.
-> wassat_pre_compact_live(fla, fcs, fcl, alive, taut, oh, ocn, ocv, ncl, nv, pm) (i32[] i32[] i32[] i8[] i8[] i32[] i32[] i32[] i64 i64 i64[])
  li = 0
  while li < 2 * nv + 2
    oh[li] = -1
    li += 1
  asize = 0
  osize = 0
  ci = 0
  while ci < ncl
    if alive[ci] == 1
      old = fcs[ci]
      n = fcl[ci]
      fcs[ci] = asize
      j = 0
      while j < n
        l = fla[old + j]
        fla[asize] = l
        asize += 1
        if taut[ci] == 0
          av = l >= 0 ? l : 0 - l
          li = (av << 1) + (l < 0 ? 1 : 0)
          ocn[osize] = oh[li]
          ocv[osize] = ci
          oh[li] = osize
          osize += 1
        j += 1
    ci += 1
  pm[0] = asize
  pm[1] = osize
  0

-> wassat_pre_recompute_ocount(fla, fcs, fcl, alive, ocount, ncl, nv) (i32[] i32[] i32[] i8[] i32[] i64 i64) i64
  li = 0
  limit = 2 * nv + 2
  while li < limit
    ocount[li] = 0
    li += 1
  ci = 0
  while ci < ncl
    if alive[ci] == 1
      st = fcs[ci]
      n = fcl[ci]
      j = 0
      while j < n
        l = fla[st + j]
        av = l >= 0 ? l : 0 - l
        lidx = (av << 1) + (l < 0 ? 1 : 0)
        ocount[lidx] = ocount[lidx] + 1
        j += 1
    ci += 1
  0

-> wassat_pre_fill_i8(arr, n, val) (i8[] i64 i64) i64
  i = 0
  while i < n
    arr[i] = val
    i += 1
  0

-> wassat_pre_copy_i8(src, dst, n) (i8[] i8[] i64) i64
  i = 0
  while i < n
    dst[i] = src[i]
    i += 1
  0

-> wassat_pre_copy_u8(src, dst, n) (u8[] u8[] i64) i64
  i = 0
  while i < n
    dst[i] = src[i]
    i += 1
  0

-> wassat_pre_copy_i32(src, dst, n) (i32[] i32[] i64) i64
  i = 0
  while i < n
    dst[i] = src[i]
    i += 1
  0

-> wassat_pre_copy_i64(src, dst, n) (i64[] i64[] i64) i64
  i = 0
  while i < n
    dst[i] = src[i]
    i += 1
  0

-> wassat_pre_zero_i32(arr, n) (i32[] i64) i64
  i = 0
  while i < n
    arr[i] = 0
    i += 1
  0

# Format a DRAT addition (`is_del == 0`) or deletion (`is_del == 1`) line of
# `n` literals from `arr[off ... off + n]` directly into `buf[pos...]` with
# zero heap allocations. Caller guarantees `pos + 16 * n + 32 <= buf.size`.
-> wassat_pre_drat_put_i32(buf, pos, arr, off, n, is_del) (u8[] i64 i32[] i64 i64 i64) i64
  p = pos
  if is_del != 0
    buf[p] = 100
    buf[p + 1] = 32
    p += 2
  i = 0
  while i < n
    l = arr[off + i] ## i64
    v = l ## i64
    if l < 0
      buf[p] = 45
      p += 1
      v = 0 - l
    if v == 0
      buf[p] = 48
      p += 1
    else
      dstart = p
      while v > 0
        q = v / 10 ## i64
        buf[p] = 48 + (v - q * 10)
        p += 1
        v = q
      lo = dstart
      hi = p - 1
      while lo < hi
        tmp = buf[lo]
        buf[lo] = buf[hi]
        buf[hi] = tmp
        lo += 1
        hi -= 1
    buf[p] = 32
    p += 1
    i += 1
  buf[p] = 48
  buf[p + 1] = 10
  p + 2

# Substitute `yv -> r` across `fla[st ... st + len]` into `dst`, deduplicating
# in place. Returns -1 when the rewritten clause is a tautology, else its width.
-> wassat_pre_subst_clause_buf(fla, st, len, yv, r, dst) (i32[] i64 i64 i64 i64 i32[]) i64
  un = 0
  taut = 0
  i = 0
  while i < len
    l = fla[st + i] ## i64
    if l == yv
      l = r
    elsif l == 0 - yv
      l = 0 - r
    dup = 0
    j = 0
    while j < un
      prev = dst[j] ## i64
      if prev == l
        dup = 1
      elsif prev == 0 - l
        taut = 1
      j += 1
    if dup == 0
      dst[un] = l
      un += 1
    i += 1
  return -1 if taut == 1
  un

-> wassat_pre_retire_clause(fla, st, len, ocount, bve_dirty) (i32[] i64 i64 i32[] i8[]) i64
  j = 0
  while j < len
    l = fla[st + j]
    av = l >= 0 ? l : 0 - l
    li = (av << 1) + (l < 0 ? 1 : 0)
    ocount[li] = ocount[li] - 1 if ocount[li] > 0
    bve_dirty[av] = 1
    j += 1
  0

-> wassat_pre_delete_list(fla, fcs, fcl, falive, ocount, bve_dirty, list, n) (i32[] i32[] i32[] i8[] i32[] i8[] i32[] i64) i64
  i = 0
  while i < n
    ci = list[i]
    if falive[ci] == 1
      falive[ci] = 0
      st = fcs[ci]
      len = fcl[ci]
      j = 0
      while j < len
        l = fla[st + j]
        av = l >= 0 ? l : 0 - l
        li = (av << 1) + (l < 0 ? 1 : 0)
        ocount[li] = ocount[li] - 1 if ocount[li] > 0
        bve_dirty[av] = 1
        j += 1
    i += 1
  0

-> wassat_pre_find_satisfied(fla, fcs, fcl, falive, ftaut, passign, keep_unit, doomed_out, ncl) (i32[] i32[] i32[] i8[] i8[] i8[] i8[] i32[] i64) i64
  ndoomed = 0
  ci = 0
  while ci < ncl
    if falive[ci] == 1 && keep_unit[ci] == 0
      if ftaut[ci] == 1
        doomed_out[ndoomed] = ci
        ndoomed += 1
      else
        st = fcs[ci]
        len = fcl[ci]
        sat = 0
        j = 0
        while j < len && sat == 0
          l = fla[st + j]
          av = l >= 0 ? l : 0 - l
          pa = passign[av]
          if (l > 0 && pa > 0) || (l < 0 && pa < 0)
            sat = 1
          j += 1
        if sat == 1
          doomed_out[ndoomed] = ci
          ndoomed += 1
    ci += 1
  ndoomed

-> wassat_pre_any_dirty(sub_dirty, falive, ftaut, ncl) (i8[] i8[] i8[] i64) i64
  ci = 0
  while ci < ncl
    if sub_dirty[ci] == 1 && falive[ci] == 1 && ftaut[ci] == 0
      return 1
    ci += 1
  0

-> wassat_pre_subset_flat(fla, sst, slen, bst, blen) (i32[] i64 i64 i64 i64) i64
  i = 0
  while i < slen
    l = fla[sst + i]
    found = 0
    j = 0
    while j < blen && found == 0
      found = 1 if fla[bst + j] == l
      j += 1
    return 0 if found == 0
    i += 1
  1

-> wassat_pre_subset_one_flip_flat(fla, sst, slen, flip, bst, blen) (i32[] i64 i64 i64 i64 i64) i64
  i = 0
  while i < slen
    l = fla[sst + i]
    want = l == flip ? 0 - l : l
    found = 0
    j = 0
    while j < blen && found == 0
      found = 1 if fla[bst + j] == want
      j += 1
    return 0 if found == 0
    i += 1
  1

-> wassat_pre_copy_without_lit(fla, st, len, drop_lit, dst) (i32[] i64 i64 i64 i32[]) i64
  w = 0
  i = 0
  while i < len
    l = fla[st + i]
    if l != drop_lit
      dst[w] = l
      w += 1
    i += 1
  w

-> wassat_pre_bve_parent_stats(fla, fcs, fcl, falive, ftaut, och, ocn, ocv, v, out_pm) (i32[] i32[] i32[] i8[] i8[] i32[] i32[] i32[] i64 i64[]) i64
  npos = 0
  pos_nonpiv = 0
  w = och[2 * v]
  while w >= 0
    ci = ocv[w]
    if falive[ci] == 1 && ftaut[ci] == 0
      npos += 1
      n = fcl[ci]
      pos_nonpiv += n - 1 if n > 1
    w = ocn[w]
  nneg = 0
  neg_nonpiv = 0
  w = och[2 * v + 1]
  while w >= 0
    ci = ocv[w]
    if falive[ci] == 1 && ftaut[ci] == 0
      nneg += 1
      n = fcl[ci]
      neg_nonpiv += n - 1 if n > 1
    w = ocn[w]
  out_pm[0] = npos
  out_pm[1] = pos_nonpiv
  out_pm[2] = nneg
  out_pm[3] = neg_nonpiv
  0

-> wassat_pre_push_bve_rstack(fla, fcs, fcl, falive, ftaut, och, ocn, ocv, push_li, v, signed_piv, hdr, rlits, pm) (i32[] i32[] i32[] i8[] i8[] i32[] i32[] i32[] i64 i64 i64 i32[] i32[] i64[]) i64
  hend = pm[0]
  lsize = pm[1]
  hbase = 4 * hend
  hdr[hbase] = 1
  hdr[hbase + 1] = signed_piv
  hdr[hbase + 2] = 0
  hdr[hbase + 3] = 0
  hend += 1
  w = och[push_li]
  while w >= 0
    ci = ocv[w]
    if falive[ci] == 1 && ftaut[ci] == 0
      st = fcs[ci]
      n = fcl[ci]
      loff = lsize
      j = 0
      while j < n
        l = fla[st + j]
        av = l >= 0 ? l : 0 - l
        if av != v
          rlits[lsize] = l
          lsize += 1
        j += 1
      hbase = 4 * hend
      hdr[hbase] = 2
      hdr[hbase + 1] = signed_piv
      hdr[hbase + 2] = loff
      hdr[hbase + 3] = lsize - loff
      hend += 1
    w = ocn[w]
  pm[0] = hend
  pm[1] = lsize
  0

-> wassat_pre_retire_pivot_occ(fla, fcs, fcl, falive, ftaut, och, ocn, ocv, ocount, bve_dirty, v) (i32[] i32[] i32[] i8[] i8[] i32[] i32[] i32[] i32[] i8[] i64) i64
  side = 0
  while side < 2
    w = och[2 * v + side]
    while w >= 0
      ci = ocv[w]
      if falive[ci] == 1 && ftaut[ci] == 0
        falive[ci] = 0
        st = fcs[ci]
        len = fcl[ci]
        j = 0
        while j < len
          l = fla[st + j]
          av = l >= 0 ? l : 0 - l
          li = (av << 1) + (l < 0 ? 1 : 0)
          ocount[li] = ocount[li] - 1 if ocount[li] > 0
          bve_dirty[av] = 1
          j += 1
      w = ocn[w]
    side += 1
  0

-> wassat_pre_sort_probe_vars(passign, ocount, cnt, out, nv) (i8[] i32[] i64[] i32[] i64) i64
  k = 0
  while k <= 16384
    cnt[k] = 0
    k += 1
  v = 1
  while v <= nv
    if passign[v] == 0
      c = ocount[2 * v] + ocount[2 * v + 1]
      b = 16383 - (c < 16383 ? c : 16383)
      cnt[b + 1] = cnt[b + 1] + 1
    v += 1
  k = 0
  while k < 16384
    cnt[k + 1] = cnt[k + 1] + cnt[k]
    k += 1
  total = cnt[16384]
  v = 1
  while v <= nv
    if passign[v] == 0
      c = ocount[2 * v] + ocount[2 * v + 1]
      b = 16383 - (c < 16383 ? c : 16383)
      pos = cnt[b]
      out[pos] = v
      cnt[b] = pos + 1
    v += 1
  total

-> wassat_pre_sort_bve_vars(passign, gone, frozen, bve_dirty, ocount, cnt, out, nv) (i8[] i8[] i8[] i8[] i32[] i64[] i32[] i64) i64
  k = 0
  while k <= 16384
    cnt[k] = 0
    k += 1
  v = 1
  while v <= nv
    if passign[v] == 0 && gone[v] == 0 && frozen[v] == 0 && bve_dirty[v] == 1
      c = ocount[2 * v] + ocount[2 * v + 1]
      b = c < 16383 ? c : 16383
      cnt[b + 1] = cnt[b + 1] + 1
    v += 1
  k = 0
  while k < 16384
    cnt[k + 1] = cnt[k + 1] + cnt[k]
    k += 1
  total = cnt[16384]
  v = 1
  while v <= nv
    if passign[v] == 0 && gone[v] == 0 && frozen[v] == 0 && bve_dirty[v] == 1
      c = ocount[2 * v] + ocount[2 * v + 1]
      b = c < 16383 ? c : 16383
      pos = cnt[b]
      out[pos] = v
      cnt[b] = pos + 1
    v += 1
  total

-> wassat_pre_tarjan(offsets, targets, passign, index, low, oncur, comp, cur, frame_node, frame_child, st, n) (i32[] i32[] i8[] i32[] i32[] i8[] i32[] i32[] i32[] i32[] i64[] i64) i64
  i = 0
  while i < n
    index[i] = -1
    comp[i] = -1
    oncur[i] = 0
    i += 1
  next_idx = 0
  next_comp = 0
  cur_size = 0
  peak = 0
  ticks = 0
  node = 2
  while node < n
    if index[node] < 0 && passign[node >> 1] == 0
      depth = 1
      peak = 1 if peak < 1
      frame_node[0] = node
      frame_child[0] = 0
      while depth > 0
        u = frame_node[depth - 1]
        if frame_child[depth - 1] == 0
          index[u] = next_idx
          low[u] = next_idx
          next_idx += 1
          cur[cur_size] = u
          cur_size += 1
          oncur[u] = 1
        start = offsets[u]
        count = offsets[u + 1] - start
        advanced = 0
        k = frame_child[depth - 1]
        while k < count && advanced == 0
          w = targets[start + k]
          ticks += 1
          if index[w] < 0
            frame_child[depth - 1] = k + 1
            frame_node[depth] = w
            frame_child[depth] = 0
            depth += 1
            peak = depth if depth > peak
            advanced = 1
          else
            low[u] = low[w] if oncur[w] == 1 && low[w] < low[u]
            k += 1
        if advanced == 0
          depth -= 1
          if depth > 0
            parent = frame_node[depth - 1]
            low[parent] = low[u] if low[u] < low[parent]
          if low[u] == index[u]
            done = 0
            while done == 0
              cur_size -= 1
              w = cur[cur_size]
              oncur[w] = 0
              comp[w] = next_comp
              done = 1 if w == u
            next_comp += 1
    node += 1
  st[0] = next_idx
  st[1] = next_comp
  st[2] = peak
  st[3] = ticks
  0

-> wassat_pre_count_scc(comp, sizes, n, gpm) (i32[] i32[] i64 i64[]) i64
  node = 2
  while node < n
    key = comp[node]
    sizes[key] = sizes[key] + 1 if key >= 0
    node += 1
  singletons = 0
  nontrivial_nodes = 0
  node = 2
  while node < n
    key = comp[node]
    if key >= 0
      if sizes[key] > 1
        nontrivial_nodes += 1
      else
        singletons += 1
    node += 1
  gpm[0] = singletons
  gpm[1] = nontrivial_nodes
  0

-> wassat_pre_build_scc_csr(comp, sizes, grp_id, grp_offs, grp_cursor, grp_members, n) (i32[] i32[] i32[] i32[] i32[] i32[] i64) i64
  i = 0
  while i < n
    grp_id[i] = -1
    i += 1
  ngrp = 0
  total = 0
  node = 2
  while node < n
    key = comp[node]
    if key >= 0 && sizes[key] > 1
      gid = grp_id[key]
      if gid < 0
        gid = ngrp
        ngrp += 1
        grp_id[key] = gid
        grp_offs[gid] = total
        grp_cursor[gid] = total
        total += sizes[key]
      pos = grp_cursor[gid]
      grp_members[pos] = node
      grp_cursor[gid] = pos + 1
    node += 1
  grp_offs[ngrp] = total
  ngrp

-> wassat_pre_collect_subst_csr(grp_offs, grp_members, seen, frozen, replit, gone, hdr, gstart, gend, spm) (i32[] i32[] i8[] i8[] i32[] i8[] i32[] i64 i64 i64[]) i64
  status = spm[0]
  vars_subst = spm[1]
  hend = spm[2]
  gi = gstart
  while gi < gend && status == 0
    mstart = grp_offs[gi]
    mend = grp_offs[gi + 1]
    contradiction_var = 0
    mk = mstart
    while mk < mend
      v = grp_members[mk] >> 1
      if seen[v] == 1
        contradiction_var = v
      else
        seen[v] = 1
      mk += 1
    mk = mstart
    while mk < mend
      seen[grp_members[mk] >> 1] = 0
      mk += 1
    if contradiction_var > 0
      status = -1
    else
      rep = 0
      best = 0
      already = 0
      mk = mstart
      while mk < mend
        m = grp_members[mk]
        v = m >> 1
        l = (m & 1) == 0 ? v : 0 - v
        rep = l if rep == 0 && frozen[v] == 1
        bav = best >= 0 ? best : 0 - best
        best = l if best == 0 || v < bav
        already = 1 if replit[v] != 0
        mk += 1
      rep = best if rep == 0
      if already == 0
        mk = mstart
        while mk < mend && status == 0
          m = grp_members[mk]
          yv = m >> 1
          y = (m & 1) == 0 ? yv : 0 - yv
          if y != rep && frozen[yv] == 0
            r_for_y = yv == y ? rep : 0 - rep
            replit[yv] = r_for_y
            gone[yv] = 2
            hbase = 4 * hend
            hdr[hbase] = 3
            hdr[hbase + 1] = yv
            hdr[hbase + 2] = r_for_y
            hdr[hbase + 3] = 0
            hend += 1
            vars_subst += 1
          mk += 1
    gi += 1
  spm[0] = status
  spm[1] = vars_subst
  spm[2] = hend
  0

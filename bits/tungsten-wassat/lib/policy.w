# Automatic formula inspection and search policy.
#
# Wassat deliberately has one supported solver mode per certificate contract,
# not a collection of undocumented experiment switches. The policy below is
# deterministic from the parsed task shape, so benchmark results are
# reproducible and library callers get the same decisions as the CLI.

# Clause-shape histogram over the parser's flat lengths:
#   [0] total literals  [1] longest clause  [2] units  [3] binary  [4] ternary
-> wassat_shape_counts(lens, ncl, out) (i64[] i64 i64[])
  i = 0
  while i < ncl
    n = lens[i]
    out[0] = out[0] + n
    out[1] = n if n > out[1]
    out[2] = out[2] + 1 if n == 1
    out[3] = out[3] + 1 if n == 2
    out[4] = out[4] + 1 if n == 3
    i += 1
  0

-> wassat_decimal_in_range(flag, token, minimum, maximum)
  raise "[flag] requires a non-negative decimal integer, got '[token]'" unless wassat_unsigned_decimal?(token)
  value = 0
  i = 0
  while i < token.size
    digit = "0123456789".index(token.slice(i, 1))
    if value > (maximum - digit) / 10
      raise "[flag] needs [minimum]..[maximum], got '[token]'"
    value = value * 10 + digit
    i += 1
  unless value >= minimum && value <= maximum
    raise "[flag] needs [minimum]..[maximum], got [value]"
  value

# Whether a solver that has been ASKED to simplify (Wassat#simplify_raw)
# runs each of the two techniques. Which solvers are asked is a separate
# decision and belongs to the coordinator — see wassat_raw_race.
WASSAT_SUBST_DEFAULT = true
WASSAT_CONGRUENCE_DEFAULT = true

# ---- adaptive race allocation (DORMANT: measured null) ------------------------
#
# The raw-kernel race allocates its arms from a hard-coded diversity matrix
# (see wassat_race_build). These numbers turn that one-shot allocation into a
# ROUND-BASED one: arms run a slice, stop at a barrier, get scored on progress
# telemetry they produced WITHOUT finishing, and the worst is respawned on a
# different configuration chosen by an integer UCB over the diversity axes.
#
# It is off by default because it was measured to be worth nothing — the
# evidence is under wassat_race_round1_conflicts, and the short version is that
# the raw arms are statistically exchangeable, so uniform allocation over them
# is already optimal. What survives is the instrumentation: the barrier is the
# only place a coordinator can look at an arm that has not finished, and every
# future question about this race ("should preprocessing get a third core?",
# "is this arm duplicating that one?") is asked there.

# Conflicts each arm gets in round 1. 0 turns the mechanism off entirely and
# restores the single unbounded round the race has always run.
#
# DORMANT (2026-07-26), and the measurement is the reason. Rounds exist ONLY to
# make reallocation possible, and reallocation over these axes was measured to
# be worth nothing.
#
# 1. No progress signal predicts the winner. Over 37 finished races the raw
#    arms were ranked at the first barrier by each candidate metric and the
#    position of the arm that went on to WIN was recorded; 0.5 is chance at 8
#    arms, and the interval is 95%:
#
#      conflicts/sec 0.459+-0.119   fast LBD EMA  0.479+-0.101
#      slow LBD EMA  0.456+-0.096   trail depth   0.425+-0.090
#      props/conflict 0.483+-0.119  cps over LBD  0.417+-0.100
#
#    Every interval contains chance. Only the live learned-clause count
#    (0.320+-0.097) clears it, and that is one hit out of ten metrics tried on
#    one sample — the multiple-comparison result you would expect from noise,
#    not a finding. An earlier n=17 pass ranked propagations-per-conflict the
#    OPPOSITE way round with the same confidence, which is what settled it.
#
# 2. Acting on any of them changes nothing. Forced to replace the worst arm
#    every 4th round (WASSAT_REALLOC=2) against no reallocation at all, 8 raw
#    arms, 3000-conflict rounds, medians of 5 interleaved:
#
#                  no-realloc  cps/LBD  fast-LBD  share-credit  learnt
#      minand064      5.704s    5.722    5.751      5.675       5.698
#      g125.18        2.029     1.998    1.971      1.991       2.012
#      g250.15        1.615     1.623    1.629      1.599       1.607
#      bmc-ibm-12     1.062     1.196    1.154      1.093       1.073
#      3bitadd_31     0.784     0.639    0.871      1.036       0.993
#
#    Four different reward signals, none separated from doing nothing by more
#    than the noise floor, on the one instance (bmc-ibm-12) where they separate
#    at all it is the wrong way.
#
# The explanation is not that the allocator is bad. It is that the arms are
# EXCHANGEABLE: at any barrier the raw arms sit within ~1.3x on conflicts and
# ~1.5x on LBD, and which one reaches the answer is decided by which basin
# happens to contain it. Uniform allocation over exchangeable arms is optimal
# by definition, so no bandit can beat the fixed matrix here — the fixed matrix
# is already the right answer.
#
# Retained, not deleted, because the telemetry underneath it (export_telemetry,
# the per-author sharing credit) is what made that measurable, and because the
# axis where the arms are NOT exchangeable — raw arms against preprocessed
# renderings — is a live question this machinery is the way to answer. Set
# WASSAT_ROUND1 to re-arm it.
-> wassat_race_round1_conflicts
  return wassat_decimal_in_range("WASSAT_ROUND1", env("WASSAT_ROUND1"), 0, 2000000000) if env("WASSAT_ROUND1") != nil
  0

# Wall-clock target for rounds 2..n, in milliseconds. Rounds after the first
# are sized PER ARM from the arm's own measured conflict rate, not by a shared
# conflict count: arms in a diversified race differ by up to 3x in conflicts
# per second, and a shared conflict slice would make the barrier wait on the
# slowest arm every round. Same reason metaflip's pool sizes its next round
# from measured elapsed time (ffcp_adapt_round_steps) rather than from a fixed
# step count.
-> wassat_race_round_ms
  return wassat_decimal_in_range("WASSAT_ROUND_MS", env("WASSAT_ROUND_MS"), 10, 3600000) if env("WASSAT_ROUND_MS") != nil
  400

# Whether a scored arm may be killed and respawned on a different
# configuration. Only consulted when WASSAT_ROUND1 has re-armed the rounds. 0
# keeps the rounds and their telemetry but leaves every arm on the
# configuration the diversity matrix gave it — the ablation that separates the
# cost of the barrier from the value of reallocating, and the one that showed
# the barrier costs 4-6% on a single-arm race and nothing on a multi-arm one.
-> wassat_race_reallocate
  return wassat_decimal_in_range("WASSAT_REALLOC", env("WASSAT_REALLOC"), 0, 2) if env("WASSAT_REALLOC") != nil
  1

# How eagerly a losing arm is replaced.
#   1  RATIO. Only an arm scoring below half the median of the live raw arms
#      is replaced. On a race whose arms are all within 25% of each other —
#      which is what every measured instance looks like — this never fires and
#      the allocator degenerates to the fixed matrix.
#   2  RANK. The worst live arm is replaced every wassat_race_realloc_every
#      rounds whatever the spread. The aggressive bracket: it exists to put an
#      upper bound on what reallocation can be worth, because a mechanism that
#      does not help when it fires constantly cannot help when it fires rarely.
-> wassat_race_realloc_every
  return wassat_decimal_in_range("WASSAT_REALLOC_EVERY", env("WASSAT_REALLOC_EVERY"), 1, 1000000) if env("WASSAT_REALLOC_EVERY") != nil
  4

# Which progress signal scores an arm. All five were measured over 37 finished
# races by ranking each raw arm at the first barrier and recording where the
# EVENTUAL WINNER sat in that ranking; all five came back at chance. The table
# is under wassat_race_round1_conflicts and the per-metric reasoning is at
# wassat_race_arm_score. The default is arbitrary among equals.
#   0  tight-rate: conflicts per second divided by the fast LBD EMA
#   1  learning quality alone: the fast LBD EMA, lower is better
#   2  propagations per conflict, higher is better
#   3  sharing credit: clauses this arm authored that OTHER arms installed
#   4  live learned-clause count
-> wassat_race_reward_metric
  return wassat_decimal_in_range("WASSAT_REWARD", env("WASSAT_REWARD"), 0, 4) if env("WASSAT_REWARD") != nil
  1

# Per-round arm telemetry to stderr, for the reward-signal study.
-> wassat_race_trace?
  env("WASSAT_RACE_TRACE") == "1"

# How many PREPROCESSED renderings of the formula join the raw-kernel race,
# in pipeline order: 1 adds the light one (probing plus equivalent-literal
# substitution), 2 adds the heavy one (subsumption plus bounded variable
# elimination) beside it. They are ADDITIONAL arms, so the raw side keeps
# every basin it sampled before and the preprocessing decision costs a thread
# instead of a gamble. 0 is the ablation switch: no preprocessing pass at
# all, and a raw kernel goes to CDCL exactly as it did before.
#
# Both renderings are worth their arm, and the reason they are separate arms
# rather than one pipeline is that they are separately best: the md5
# cryptography kernel is solved by the light rendering in 5k conflicts and
# the heavy one needs 255k, while the bitvector kernel smulo016 is untouched
# by the light rendering (33.8s) and solved by the heavy one in 4.9s.
# Flip budget for the raw race's SLS arm; 0 removes the arm entirely.
#
# Unbounded in effect rather than tuned: the arm polls the shared stop cell
# inside its flip loop, so a budget it never reaches costs nothing — whichever
# arm answers first stops it within a flip. The number is therefore a ceiling
# against a pathological walk, not a schedule. Measured flips-to-model on the
# rows this arm exists for: DivS_568_11 288, DivS_862_11 413, n320p5q2_n 6,610,
# n384p5q2_vh 105,627, ntil-90d-33 1,216,191 — the old serial burst's 60,000
# would have caught three of those five.
-> wassat_sls_arm_flips
  return wassat_decimal_in_range("WASSAT_SLS_FLIPS", env("WASSAT_SLS_FLIPS"), 0, 2000000000) if env("WASSAT_SLS_FLIPS") != nil
  200000000

-> wassat_pre_arm_count
  return wassat_decimal_in_range("WASSAT_PRE_ARMS", env("WASSAT_PRE_ARMS"), 0, 2) if env("WASSAT_PRE_ARMS") != nil
  2


# Effort allowance for the LIGHT rendering (probing and equivalent-literal
# substitution), in preprocessor ticks.
#
# ABSOLUTE, not size-derived. The rendering runs in its own thread, so its
# cost is not on anyone's critical path — but the coordinator still has to
# JOIN it, so a rendering that runs for minutes holds the whole answer even
# after another arm has won. What the budget bounds is that hostage window,
# and the window is the same length whatever the formula's size, so scaling
# the budget by size only makes it longest exactly where it is worst.
#
# The preprocessor's own size-derived budget (init_budget) is what this
# replaces, and it is worth being concrete about why: on the planning kernel
# blocks-4-ipc5-h21 (906k clauses, 2.4M literals) it works out to 499M ticks,
# and substitution's boxed implication walk retires roughly 20M ticks a
# second, so the "budget" authorised four minutes of preprocessing on an
# instance the race answers in 22 seconds.
#
# 16M is 5.8x the largest healthy consumption measured (medians, ticks):
#
#   smulo016 286k · crypto 566k · mrpp6x6 586k · agile1614 1.79M
#   minand064 2.06M · g125.18 2.14M · hwbmc 2.15M · 4pipe 2.26M
#   g250.15 2.47M · bmc-ibm-12 2.74M · ibm-2004-03-k70 2.76M
#
# Every one of those completes the pass well inside the cap; the instances
# the cap stops are the ones whose implication graph makes the pass
# superlinear, and stopping them early costs only the substitutions it had
# not found yet.
-> wassat_pre_light_ticks
  return wassat_decimal_in_range("WASSAT_PRE_TICKS", env("WASSAT_PRE_TICKS"), 1, 2000000000) if env("WASSAT_PRE_TICKS") != nil
  16000000

# Further allowance for the HEAVY rendering (subsumption and bounded variable
# elimination) on top of whatever the light one spent. A separate number
# because these rounds are native and retire ticks two orders of magnitude
# faster, so they can afford far more of them.
#
# 64M is 2.6x the largest USEFUL consumption measured — minand064 24.4M,
# crypto 21.5M, 3bitadd_31 14.9M, agile1614 13.2M, g250.15 11.9M, hwbmc
# 7.6M, smulo016 6.6M, g125.18 5.4M, mrpp6x6 4.4M. The one instance that
# wanted more is 4pipe at 567M ticks and 812ms, and it eliminated zero
# variables for them, which is the case a cap exists for.
#
# This used to bound ROUNDS and not the work inside one: a subsumption chunk
# ended only when the clause range or the survivor-output budget did, so
# 4pipe retired 567M ticks against a 66M allowance in a single pass and
# blocks-4-ipc5-h21 ran 95 seconds inside one call. The scan now takes a tick
# cap (WASSAT_PRE_SUB_CHUNK_TICKS) and resumes through the pm[6] token it
# already reported, so the allowance binds to within one chunk: 4pipe's pass
# went 1947ms -> 147ms and now stops at the budget instead of overrunning it
# 8x. This number is therefore a real allowance again, not an aspiration.
-> wassat_pre_heavy_ticks
  return wassat_decimal_in_range("WASSAT_PRE_HEAVY_TICKS", env("WASSAT_PRE_HEAVY_TICKS"), 1, 2000000000) if env("WASSAT_PRE_HEAVY_TICKS") != nil
  64000000

# Wall-clock stop for each rendering, in milliseconds. A backstop for the
# tick budgets above, not a replacement: ticks are the reproducible currency
# and bound the pass on every formula whose cost per tick is normal, but they
# do not bound TIME, and one measured formula makes that gap enormous — see
# WassatPreprocess#set_deadline_ms.
#
# 1500ms is ~11x the slowest healthy light pass (bmc-ibm-2004-03-k70, 137ms)
# and ~1.8x the slowest healthy heavy pass (4pipe, 812ms), so it never fires
# on an instance the tick budget already handles. It fires only where the
# alternative is minutes. Deliberately in the same range as the whole race it
# is a prefix to: a preprocessing pass that costs more than the search it is
# meant to accelerate has already lost, whatever it would have found.
-> wassat_pre_stage_ms
  return wassat_decimal_in_range("WASSAT_PRE_STAGE_MS", env("WASSAT_PRE_STAGE_MS"), 0, 3600000) if env("WASSAT_PRE_STAGE_MS") != nil
  1500

# Clauses above which no preprocessed rendering is built at all.
#
# A RESOURCE gate, not a yield prediction — the distinction the rest of this
# file insists on, and the one CryptoMiniSat draws in OccSimplifier::setup(),
# where >40M clauses or >100M literals skips occurrence-based simplification
# outright because the structure cannot be afforded. kissat by contrast has
# no size gate on preprocessing at all, and CaDiCaL's one clause-count term
# only postpones. So this is the minority position and it is held for a
# specific, documented reason rather than a general belief about big
# formulas.
#
# It used to be 400,000, and it was that low because two passes had stopping
# points too coarse to bound: forward subsumption spent up to 95 SECONDS and
# 139 billion ticks inside ONE native chunk where no budget, deadline or
# signal could reach it, and the substitution rewrite only checked its budget
# between SCC classes, so one big class ran for minutes. Both are now
# interruptible — the native scan takes a tick cap and resumes through pm[6]
# (WASSAT_PRE_SUB_CHUNK_TICKS), and the rewrite tests the deadline every
# WASSAT_PRE_SUBST_CHECK_EVERY clauses instead of once per class — so the
# reason for holding the gate down is gone. Measured, medians, interleaved,
# with the gate as the only variable:
#
#   4pipe            subsumption pass 1947ms -> 147ms  (one chunk -> chunked)
#   blocks-4-ipc5    22.42s gated off vs 22.55s gated on, medians of 3 — the
#   (906k clauses)   cliff is gone. Before the fix the same comparison was
#                    19.3s -> 32.4s, a 68% penalty for offering the arm.
#   spg_200_301      116.5s gated off vs 97.6s gated on, medians of 4 — about
#   (1.55M clauses)  1.2x, so preprocessing now earns its arm here where the
#                    old gate refused it outright.
#
# Both instances are UNSAT and both were run on a contended machine; spg
# spans 93-188s run to run, so treat 1.2x as "no longer harmful and probably
# positive", not as a measured speedup. The claim this change rests on is the
# blocks-4-ipc5 pair — the cliff the gate existed to avoid is gone — not on
# spg being faster.
#
# So the gate is raised 5x rather than removed. Removed is still wrong: this
# is a RESOURCE gate — the distinction the rest of this file insists on, and
# the one CryptoMiniSat draws in OccSimplifier::setup(), where >40M clauses
# or >100M literals skips occurrence-based simplification outright because
# the structure cannot be afforded. The occurrence lists and boxed clause
# objects the preprocessor builds are proportional to LITERALS, and the
# competition set contains formulas (Large-result_b24, 25M clauses) an order
# of magnitude past anything measured here. 2,000,000 is 1.3x the largest
# instance shown to preprocess profitably and keeps those outliers out.
#
# kissat by contrast has no size gate on preprocessing at all, and CaDiCaL's
# one clause-count term only postpones, so even at 2M this remains the
# minority position — held now for a memory bound, not a scaling defect.
-> wassat_pre_max_clauses
  return wassat_decimal_in_range("WASSAT_PRE_MAX_CLAUSES", env("WASSAT_PRE_MAX_CLAUSES"), 0, 2000000000) if env("WASSAT_PRE_MAX_CLAUSES") != nil
  2000000

+ WassatConfig
  -> new(@nvars, clauses)
    @nclauses = clauses.size
    @nliterals = 0
    @binary = 0
    @ternary = 0
    @units = 0
    @max_clause = 0
    clauses.each -> (clause)
      n = clause.size
      @nliterals += n
      @max_clause = n if n > @max_clause
      @units += 1 if n == 1
      @binary += 1 if n == 2
      @ternary += 1 if n == 3

  # Shape counters straight from the parser's flat length array, for the
  # raw path that never materializes boxed clauses (see
  # wassat_raw_artifact). Same numbers the boxed constructor computes.
  -> .from_lens(nvars, lens, ncl)
    c = WassatConfig.new(nvars, [])
    counts = i64[8]
    wassat_shape_counts(lens, ncl, counts)
    c.adopt_counts(ncl, counts)
    c

  -> adopt_counts(ncl, counts)
    @nclauses = ncl
    @nliterals = counts[0]
    @max_clause = counts[1]
    @units = counts[2]
    @binary = counts[3]
    @ternary = counts[4]
    0

  -> raw_heuristics?
    # This is the historical raw-kernel classifier used by preprocessing
    # technique gates. Trusted routing is deliberately a separate question
    # (race_route?): a raw race still gets its established VMTF/target search
    # matrix, regardless of whether this classifier would have selected a
    # serial raw kernel.
    #
    # Swept 2026-07-26, medians of 3, ratio against the value below. Every
    # column from 0 to 100,000 is identical on every instance; the ratios
    # appear only where an instance CROSSES the threshold onto the serial
    # preprocessed route, and every crossing is a loss:
    #
    #                   clauses   raced   serial-preprocessed
    #   3bitadd_31       31,310   0.93s   2.59s  (2.8x worse)
    #   g125.18          70,163   1.26s   3.45s  (2.8x worse)
    #   bmc-ibm-12      194,778   0.70s   1.17s  (1.7x worse)
    #   bmc-ibm-6       368,352   0.076s  0.272s (3.6x worse)
    #   ak128 miter     968,713   0.18s   0.57s  (3.1x worse)
    #
    # The one instance that prefers the serial route is the md5 kernel
    # (131,279 clauses, 0.53s raced against 0.20s serial) and it is not a
    # preprocessing gap — the race finds the same reduced formula, it just
    # pays a slice of racing and two thread-spawn rounds to get there.
    #
    return true if @nclauses > 50000
    # Once routing is separated, small random-3-SAT no longer inherits the
    # serial-preprocessed EVSIDS bundle by accident. In the raw race the
    # focused VMTF/target scout is the SAT specialist (uf250-0100: 0.020s
    # versus 0.268s), while diversified EVSIDS and preprocessed arms still
    # cover the UNSAT side.
    return true if @nclauses >= 80 && @ternary * 4 >= @nclauses * 3
    # Size alone is the wrong rule for the middle band. Measured, verdicts
    # identical: bmc-ibm-2 (11,683 clauses, structured) runs 17.5ms through
    # the pipeline against 6.3ms raw, while uuf250-01 (1,065 clauses,
    # random 3-SAT) runs 1.60s through the pipeline against 2.89s raw —
    # dense ternary formulas genuinely want probing and elimination, and
    # structured ones do not. The ternary-dominance test that separates
    # them for lookahead and shrinking separates them here too.
    @nclauses > 5000 && !(@ternary * 4 >= @nclauses * 3)

  # Proof/preprocessor compatibility name: preprocessing technique gates keep
  # the historical classifier. The trusted CLI uses race_route? instead.
  -> raw_kernel?
    self.raw_heuristics?

  -> race_route?
    # Raw and preprocessed renderings now race, so trusted routing no longer
    # has to predict which representation will win. This is especially
    # important for small SAT random-3-SAT: uf250-0100 is 0.268s through the
    # serial preprocessing route and 0.020s through the raw race, while the
    # preprocessed arms remain present to catch UNSAT cases that prefer
    # elimination. The only formula that cannot benefit is the empty one.
    #
    # Measurement hook retained for controlled route A/Bs. Unlike the old
    # switch, it changes ROUTING ONLY; a raw race retains its established
    # VMTF/target matrix.
    return @nclauses > env("WASSAT_RAW_AT").to_i if env("WASSAT_RAW_AT") != nil
    # Compact pigeonhole rows finish inside the prepared scout with the exact
    # same 416-conflict trajectory, while raw intake adds ~15ms. Larger rows
    # (hole9 and up) cross into the race and benefit from scout continuation.
    return false if @nvars <= 64 && @nclauses >= 100 && @binary * 2 >= @nclauses && @max_clause >= 4
    @nclauses > 0

  -> stage_pre_after_scout?
    # A staged exception for the dense random-3-SAT band: take the focused
    # raw SAT shot first, then—only after that shot misses—avoid paying for
    # six concurrent long searches on the upper end of the family. This is a
    # work observation, not a guessed verdict: uf250-0100 answers inside the
    # 2k-conflict scout, while uuf250 reaches the miss and is faster through
    # the serial prepared kernel. Smaller uuf200 still benefits from the wide
    # race, so both variable and clause floors are intentional.
    @nvars >= 225 && @nclauses >= 1000 && @nclauses <= 5000 && @ternary * 4 >= @nclauses * 3

  -> use_vmtf(raw)
    raw

  -> use_target_phases(raw)
    # ON everywhere since 2026-07-28. The light path used to run without
    # target phases at all -- the assignment sat under `if art["raw"]` in
    # load_flat, so every preprocessed serial solve decided on churn-prone
    # saved phases only. That was the whole f1000-class failure: our conflict
    # rate on it BEATS CaDiCaL's (58.6k/s vs 43.3k/s) and the row still
    # timed out at 40x CaDiCaL's conflict count. With target phases the same
    # serial solver matches CaDiCaL (5.5s vs 5.18s), uf250-0100 drops 0.23s
    # -> 0.02s and f600 1.0s -> 0.35s. The cost is a ~1.3x slowdown on
    # uuf-class refutations (uuf250-01 1.42s -> 1.89s serial), which the
    # parity gate absorbs: we stay 1.4x ahead of CaDiCaL there.
    return env("WASSAT_TARGET") == "1" if env("WASSAT_TARGET") != nil
    true

  -> use_substitution(raw)
    # Equivalent-literal substitution: Tarjan SCCs of the binary implication
    # graph, collapsing each component to one representative literal. On the
    # preprocessed path this is WassatPreprocess#run_substitution; on the raw
    # path it runs against the solver's own arena
    # (Wassat#substitute_equivalences).
    #
    # An explicit switch, not a shape guess, because the technique's value
    # splits by instance family rather than by any counter this class holds:
    # WASSAT_SUBST=1 forces it on, WASSAT_SUBST=0 off, on both paths.
    return env("WASSAT_SUBST") == "1" if env("WASSAT_SUBST") != nil
    WASSAT_SUBST_DEFAULT

  -> use_lucky
    # kissat's lucky phases (lucky.c): four decision-free greedy dives run
    # once, before the first branching decision. Not shape-gated, because the
    # cost is bounded by a propagation sweep on any shape and the payoff is
    # the whole instance: the SC2026 miter ak128modbtbg2msisc is answered by
    # the forward-true dive with zero conflicts, where an 8-arm CDCL race
    # needs 14.4s to rediscover the same assignment. WASSAT_LUCKY=0 turns it
    # off for ablation.
    env("WASSAT_LUCKY") != "0"

  # Ternary count, for sizing the congruence pass's scratch tables.
  -> ternary_count
    @ternary

  -> use_congruence(raw)
    # Congruence closure: ternary strengthening (extract_binaries) plus AND
    # and XOR gate extraction, merging gates that share a right-hand side.
    # It never rewrites the CNF itself — every merge is emitted as the two
    # equivalence binaries and consumed by use_substitution's SCC pass,
    # which is why the two switches are only worth anything together.
    # WASSAT_CONGRUENCE=1 forces it on, =0 off.
    return env("WASSAT_CONGRUENCE") == "1" if env("WASSAT_CONGRUENCE") != nil
    WASSAT_CONGRUENCE_DEFAULT

  # Rounds of (extract gates -> substitute equivalences) before the closure
  # gives up. See Wassat#congruence_rounds for why re-extraction is the
  # rehash that walks an equivalence up a circuit layer, and why 1 is
  # bit-identical to the single pass this replaced.
  #
  # DEFAULT 1 — the fixpoint is implemented, correct and measurably deeper,
  # and it is still off, because nothing measured got FASTER for it.
  #
  # Where it merges at all it compounds exactly as the theory says, and the
  # later rounds are the productive ones (agile-sat bench_1614 XOR merges by
  # round: 165, 336, 314, 288, 261 — the second round beats the first):
  #
  #   instance                  substituted vars, round 1 -> 8 rounds
  #   agile-sat bench_1614      988 -> 2818   (2.9x)
  #   agile-sat bench_2778      935 -> 3455   (3.7x)
  #   agile-sat bench_1794      919 -> 2782   (3.0x)
  #   cryptography md5 r24      695 ->  701   (1.01x, fixpoint at round 3)
  #
  # Note the agile rows are still CLIMBING at the round cap, so 8 is not the
  # fixpoint there — it is the budget. Only md5 actually converges.
  #
  # But that is a count of equivalences, not of solved instances. On the md5
  # kernel — the only one of these whose wall time is stable enough to read
  # under load — the extra rounds cost a consistent 8% (0.40s -> 0.43s,
  # medians of 5, interleaved) and win nothing, because the arm that
  # actually answers it is the PREPROCESSED one, not a raw arm carrying
  # congruence. The agile instances swing 5.6s-137s run to run on a
  # contended machine, which is far too wide to resolve the difference.
  #
  # So: measured, deeper, not yet shown to pay, and therefore not on. Raise
  # it to re-open the question on a quiet machine; the numbers above are the
  # baseline to beat. Congruence merges anything at all on only 7 of the 115
  # instances in the competition set, so the whole question is narrow.
  -> congruence_max_rounds
    return wassat_decimal_in_range("WASSAT_CONGRUENCE_ROUNDS", env("WASSAT_CONGRUENCE_ROUNDS"), 1, 64) if env("WASSAT_CONGRUENCE_ROUNDS") != nil
    1

  # Ceiling on the gate arena, in gates. The arena starts at min(clauses,
  # 131072) and doubles whenever extraction reports it filled one (see
  # Wassat#extract_and_gates), so this is a memory bound, not a work bound:
  # a gate costs 2+arity words of arena, 8 words of hash table and 2 words
  # of merge output, so a 1M-gate ceiling is ~150MB transient, freed the
  # moment the pass returns. Formulas that want more are exactly the ones
  # whose arena already dwarfs it.
  -> congruence_gate_ceiling
    return wassat_decimal_in_range("WASSAT_CONGRUENCE_GATES", env("WASSAT_CONGRUENCE_GATES"), 1024, 2000000000) if env("WASSAT_CONGRUENCE_GATES") != nil
    1048576

  -> force_simplify?
    # Measurement hook. The race turns the simplification axis on for four
    # of its arms and the serial probe never uses it, so an end-to-end
    # ablation of the technique needs a way to say "every raw solver".
    env("WASSAT_SIMPLIFY") == "1"

  -> use_chronological_backtracking(raw)
    # v2 (analysis AT the conflict level, one combined jump) wins on long
    # raw searches (ibm-12: 12.2k -> 8.3k conflicts) and loses on the
    # fast target-phase dives that decide inside the probe (ibm-6:
    # 272 -> 2k). The coordinator therefore enables it per-solver on the
    # post-probe-miss main solve only (enable_chrono); solvers default
    # plain.
    false

  -> escalate_conflicts
    # Conflicts of fruitless search before the solver reconfigures itself
    # to the aggressive frontier stack (see solve_loop). Set above every
    # gate instance's conflict need — uuf250-01 decides in ~135k — so the
    # escalation only ever fires on searches that are genuinely stuck; the
    # Lonely Runner class needs ~1.2M and escalates at 4% of that cost.
    250000

  -> use_shrinking
    # All-UIP learned-clause shrinking (Feng & Bacchus; CaDiCaL's shrink)
    # pays where learned clauses carry multi-literal decision-level blocks
    # — counting/cardinality encodings and structured kernels. On
    # random-3-SAT-like formulas the blocks are near-singletons: measured
    # on uuf250-01 the pass removed ~1% of learned literals while costing
    # ~5% conflict throughput and perturbing the trajectory (+4.6%
    # conflicts) — a strict loss, so the ternary-dominated shape keeps it
    # off, the same measured-policy treatment as lookahead and VMTF.
    #
    # DORMANT (2026-07-24): shape-gating is not enough — interleaved A/B on
    # the whole gate found php87 0.03s -> 0.11s (3.7x: heavy shrinking,
    # 29% of literals removed, on a row already decided in 416 conflicts by
    # lookahead) and bmc-ibm-12 0.88 -> 0.94s, against ibm-10 0.18 -> 0.16s
    # and uuf250 unchanged. Net negative, so the pass stays off everywhere.
    # It is retained (certified: 38+12 specs, php87 WRAT verified WITH the
    # pass active, 200-case differential) because the technique is
    # trajectory-dependent: wassat's lr5 clauses carry only ~20% of their
    # literals in multi-literal level blocks (1% removed, ~15% ceiling)
    # versus CaDiCaL's 37%, and the restart/branching cadence work that
    # reshapes that trajectory is the phase that could make this pay.
    return env("WASSAT_SHRINK") == "1" if env("WASSAT_SHRINK") != nil
    return false if true
    !(@ternary * 4 >= @nclauses * 3)

  -> use_vivification
    # The current prefix-conflict pass is a measured net loss: on uuf250 it
    # perturbs a roughly 95k-conflict trajectory into a multi-million-conflict
    # search, and prior BMC measurements also regressed. Keep the technique
    # out of the automatic policy until a stronger form wins the reference
    # gate.
    #
    # Measurement hook (2026-07-28): that verdict rests on uuf250 and BMC --
    # rows wassat already WINS. The same "disabled on evidence from rows we
    # win" pattern hid the SLS burst (97ed3d1) and target phases (7f24dd2),
    # both of which turned out to be large wins once measured on the rows we
    # LOSE. CaDiCaL vivifies on every one of those rows (0.02-0.81% of
    # clauses). This pins the axis so that can be tested without a rebuild.
    return env("WASSAT_VIVIFY") == "1" if env("WASSAT_VIVIFY") != nil
    false

  -> raw_race_arms
    # Re-enabled 2026-07-25 after the fault was isolated and fixed: the
    # SIGBUS was an inline-cache publication tear (key stored before
    # fn_ptr/arity with no ordering, so a second arm could dispatch
    # through a stale pointer or a zero arity). runtime.h now invalidates,
    # fills, then release-publishes, and readers re-check the key.
    #
    # Diversity is the point, not raw parallelism: this session measured
    # the same instances swinging 2-15x on trajectory alone (lr5 solved in
    # 4s once the configuration changed; bmc-ibm-10 moved 20% on watch
    # order; bmc-ibm-12 spans 4.9k-17k conflicts across configurations).
    # Racing configurations takes the min instead of gambling on one.
    # Measurement hook: racing diversified arms makes a raw-kernel run
    # non-deterministic by construction, so any A/B on a technique that
    # changes the trajectory has to be able to pin the arm count — and to pin
    # it at ONE to get a deterministic reading at all. Same spirit as
    # WASSAT_RAW_AT.
    #
    # NO STATIC PREDICTOR EXISTS FOR THIS, so the rule stopped trying to be one.
    # It used to be a clause-count ladder (1 below 50k, 4 below 150k, 8 above)
    # and that ladder was wrong in BOTH directions inside a single size band:
    # 3bitadd_31 at 31k wanted more arms and paid 3-8x for getting one, while
    # smulo016 at 8.7k and minand064 at 43k gain nothing from a second arm.
    # Clause count carries no signal about how much trajectory diversity an
    # instance needs — the same shape as the preprocessing-yield question the
    # race already answered by racing instead of predicting.
    #
    # FOUR, measured 2026-07-26 against reference.py's own parity and survey
    # rows (29 rows scored, 11 excluded for exceeding the 25s budget on every
    # column rather than being counted as ties), three reps, min-of-3, one
    # binary driven by WASSAT_ARMS so the columns cannot differ by anything but
    # width, every `s` line checked against the published answer and across
    # columns. Geomean of per-row (width / ladder):
    #
    #   width 2   1.006      width 4   0.983      width 6   0.967
    #
    # 4 and 6 are the same number here: 6 moved 0.948 -> 0.967 between two and
    # three reps while 4 held 0.981 -> 0.983, and the gap between them is
    # smaller than that movement. 4 is the one that ships because four raw arms
    # plus the two preprocessing arms is six threads, which is exactly this
    # machine's performance-core count; six raw arms is eight threads and
    # oversubscribes them. That reasoning is about core supply, not about this
    # corpus, so it is the safer constant on the smaller machines this
    # self-hosts on too.
    #
    # What the change actually buys is the removal of a catastrophic row, not a
    # big average: the ladder is 3.1x slower than width 4 on 3bitadd_31, and
    # width 4's own worst row against the ladder is 1.85x (mrpp_6x6#14_10).
    # Total wall across the scored rows is a wash (30.5s -> 31.9s); the geomean
    # is the honest breadth statistic and the one the scoreboard already uses.
    #
    # TWO BANKED NEGATIVES from the same campaign, so neither gets re-derived:
    #
    # 1. Width 2 looked like the answer on a 9-instance sweep (geomean 1.05
    #    against a per-row oracle, where the ladder scored 1.38) and was then
    #    falsified by the breadth set above, where it is a wash. Nine rows
    #    chosen because they were interesting is a tuning set, not evidence.
    #
    # 2. Making arm 0 the serial post-probe configuration at every width —
    #    on the theory that a race should contain the configuration you would
    #    have run if you were not racing — is a 3.3% NET LOSS (geomean 1.033,
    #    isolated at fixed width 4). It does exactly what it was meant to on
    #    mrpp_6x6#14_10 (1.85x -> 0.54x) and loses more than that back on
    #    ContextModel 1.98x, bench_1614 1.97x and ibm-2004-03-k70 1.72x. The
    #    reseed on arm 0 is load-bearing: its diversity is worth more than
    #    retaining the serial trajectory, exactly as the matrix comment in
    #    portfolio.w already claimed.
    #
    # STILL OPEN. The measurement ran with ~2.3 foreign cores busy; contention
    # can only understate a wide race, never overstate it, so the width-6 row
    # is a lower bound on what a quiet machine would show. Two instances show
    # contention-immune trajectory wins that only appear above width 4 —
    # smulo016 234,312 -> 122,873 conflicts and minand064 94,504 -> 40,420 at
    # width 16 — so the ceiling is a function of free performance cores, and
    # the principled rule is total race width (raw + preprocessing arms)
    # against that number.
    return env("WASSAT_ARMS").to_i if env("WASSAT_ARMS") != nil
    # Fill no more than the cores left after the two representation arms,
    # capped at the breadth-set winner (four). This preserves four raw + two
    # preprocessed arms on the development host, but does not oversubscribe a
    # 2- or 4-core machine.
    cores = System.cpu_count ## i64
    arms = cores - 2
    arms = 1 if arms < 1
    arms = 4 if arms > 4

    # A clause-count ladder could not predict useful diversity, but formula
    # size DOES predict resident memory. Estimate the fixed flat solver
    # structures conservatively and keep all raw arms below one third of
    # physical RAM, leaving room for the parsed formula and preprocessing
    # renderings. Unknown memory (zero) leaves the CPU-only decision intact.
    memory = System.physical_memory_bytes ## i64
    if memory > 0
      per_arm = 25165824 + 24 * @nliterals + 96 * @nclauses
      budget = memory / 3
      while arms > 1 && per_arm * arms > budget
        arms -= 1
    arms

  -> lookahead_candidates
    # Trial propagation is a strong win for compact random 3-SAT and
    # pigeonhole-like "one long choice plus many binary exclusions" tasks,
    # but it multiplies decision work and destroys the tuned CDCL trajectory
    # on uuf100/uuf250-scale random kernels. Keep rollout to the small random
    # class where it wins; select it from shape rather than exposing a knob.
    random3 = @nvars >= 20 && @nvars <= 64 && @nclauses >= 80 && @ternary * 4 >= @nclauses * 3
    choice_binary = @nvars >= 20 && @nvars <= 512 && @nclauses >= 100 && @binary * 2 >= @nclauses && @max_clause >= 4
    return 16 if random3 || choice_binary
    0

  -> continue_scout?
    # Continuation earns an extra runnable arm only on the compact random-3
    # and choice/binary families where the bounded scout is itself a useful
    # specialist. On general structured SAT it merely contends with the four
    # established matrix arms (mrpp6 median regressed 31%).
    self.lookahead_candidates > 0

  -> probe_ms(raw)
    raw ? 150 : 120

  -> probe_conflicts(raw)
    raw ? 2000 : 4000

  -> reduce_limit
    @nclauses < 20000 ? 2000 : 4000

  -> reduce_step
    @nclauses < 20000 ? 300 : 1000

  -> summary(raw)
    avg100 = @nclauses == 0 ? 0 : 100 * @nliterals / @nclauses
    "raw=[raw] vars=[@nvars] clauses=[@nclauses] literals=[@nliterals] avg_clause_x100=[avg100] binary=[@binary] ternary=[@ternary] lookahead=[self.lookahead_candidates]"

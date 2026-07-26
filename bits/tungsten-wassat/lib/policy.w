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
# Honest limitation: this bounds ROUNDS, not the work inside one. The native
# subsumption and elimination scans check the budget between chunks, and a
# chunk can overshoot enormously — 4pipe reaches 567M ticks against a 66M
# allowance in a single pass. The wall-clock deadline below is the backstop
# that actually binds, and the clause gate is what covers the case where even
# that cannot (a chunk that runs 95s without returning).
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
# The reason: two passes here have stopping points too coarse to bound. On
# the planning kernel blocks-4-ipc5-h21 (906k clauses) substitution rewrites
# for 59s before its per-class budget check comes round — the wall-clock
# deadline now cuts that to ~2.2s — and forward subsumption spends 95
# SECONDS and 139 BILLION ticks inside ONE native chunk, where no budget,
# deadline or signal can reach it. That is a scaling defect in
# WassatPreprocess, not a property of large formulas, and the fix is to make
# those passes interruptible (chunk the subsumption scan, charge and check
# the rewrite per clause). Until then the renderings are not offered inputs
# they cannot survive, because the alternative is a 22s answer becoming a
# 125s one.
#
# 400,000 is 1.4x the largest formula measured to preprocess healthily
# (ibm-2004-03-k70, 286k clauses, 137ms) and 2.3x below the one that does
# not. Raise it once the passes are interruptible; the race handles the
# question of whether preprocessing was WORTH it on its own.
-> wassat_pre_max_clauses
  return wassat_decimal_in_range("WASSAT_PRE_MAX_CLAUSES", env("WASSAT_PRE_MAX_CLAUSES"), 0, 2000000000) if env("WASSAT_PRE_MAX_CLAUSES") != nil
  400000

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

  -> raw_kernel?
    # This no longer decides whether preprocessing HAPPENS — the raw path
    # races preprocessed renderings of the formula (wassat_race_stage_pre), so
    # a "raw" kernel gets probing, substitution, subsumption and elimination
    # anyway, as racers rather than as a commitment. What is left is a choice
    # between two ROUTES: race the renderings, or solve one serially.
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
    # So the threshold is no longer load-bearing and any value in [0, 100000]
    # is equivalent. It is kept, at the value it has always had, because
    # moving it UP is a measured regression and moving it DOWN also flips
    # VMTF, target phases, chronological backtracking and the probe budget
    # (see the confound note below) — a change that deserves its own campaign,
    # not a side effect of this one. Measured at 0 it is neutral-to-better on
    # 14 instances, random-3-SAT SAT most of all (uf250-0100 0.245s -> 0.017s),
    # which is where that campaign should start.
    #
    # Validation hook: no correctness-suite instance is anywhere near this
    # size, so lowering the threshold is the only way to exercise the raw
    # path across the differential.
    return @nclauses > env("WASSAT_RAW_AT").to_i if env("WASSAT_RAW_AT") != nil
    return true if @nclauses > 50000
    # Size alone is the wrong rule for the middle band. Measured, verdicts
    # identical: bmc-ibm-2 (11,683 clauses, structured) runs 17.5ms through
    # the pipeline against 6.3ms raw, while uuf250-01 (1,065 clauses,
    # random 3-SAT) runs 1.60s through the pipeline against 2.89s raw —
    # dense ternary formulas genuinely want probing and elimination, and
    # structured ones do not. The ternary-dominance test that separates
    # them for lookahead and shrinking separates them here too.
    #
    # Confounded, deliberately: this predicate also selects VMTF, target
    # phases and chronological backtracking, so the numbers above are the
    # combined effect of the bypass and the heuristics, not the bypass
    # alone. Splitting the two is worth doing before this threshold moves
    # again.
    @nclauses > 5000 && !(@ternary * 4 >= @nclauses * 3)

  -> use_vmtf(raw)
    raw

  -> use_target_phases(raw)
    raw

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
    return false if true
    !(@ternary * 4 >= @nclauses * 3)

  -> use_vivification
    # The current prefix-conflict pass is a measured net loss: on uuf250 it
    # perturbs a roughly 95k-conflict trajectory into a multi-million-conflict
    # search, and prior BMC measurements also regressed. Keep the technique
    # out of the automatic policy until a stronger form wins the reference
    # gate; there is deliberately no user-facing opt-in tuning switch.
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
    # Measurement hook: racing 8 diversified arms makes a raw-kernel run
    # non-deterministic by construction, so any A/B on a technique that
    # changes the trajectory has to be able to pin the arm count. Same
    # spirit as WASSAT_RAW_AT.
    return env("WASSAT_ARMS").to_i if env("WASSAT_ARMS") != nil
    return 8 if @nclauses >= 150000
    return 4 if @nclauses >= 50000
    1

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

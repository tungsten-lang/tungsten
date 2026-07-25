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
    # Large kernels currently lose more to full preprocessing intake and
    # rewrite passes than they regain in search. Small encoding kernels still
    # benefit substantially from probing, substitution, subsumption, and BVE.
    #
    # Validation hook: no correctness-suite instance is anywhere near this
    # size, so lowering the threshold is the only way to exercise the raw
    # path (preprocessor bypass included) across the differential.
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

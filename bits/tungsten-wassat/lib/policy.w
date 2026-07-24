# Automatic formula inspection and search policy.
#
# Wassat deliberately has one supported solver mode per certificate contract,
# not a collection of undocumented experiment switches. The policy below is
# deterministic from the parsed task shape, so benchmark results are
# reproducible and library callers get the same decisions as the CLI.

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

  -> raw_kernel?
    # Large kernels currently lose more to full preprocessing intake and
    # rewrite passes than they regain in search. Small encoding kernels still
    # benefit substantially from probing, substitution, subsumption, and BVE.
    @nclauses > 50000

  -> use_vmtf(raw)
    raw

  -> use_target_phases(raw)
    raw

  -> use_chronological_backtracking(raw)
    # v2 (analysis AT the conflict level, one combined jump) wins on long
    # raw searches (ibm-12: 12.2k -> 8.3k conflicts) and loses on the
    # fast target-phase dives that decide inside the probe (ibm-6:
    # 272 -> 2k). The coordinator therefore enables it per-solver on the
    # post-probe-miss main solve only (enable_chrono); solvers default
    # plain.
    false

  -> use_vivification
    # The current prefix-conflict pass is a measured net loss: on uuf250 it
    # perturbs a roughly 95k-conflict trajectory into a multi-million-conflict
    # search, and prior BMC measurements also regressed. Keep the technique
    # out of the automatic policy until a stronger form wins the reference
    # gate; there is deliberately no user-facing opt-in tuning switch.
    false

  -> raw_race_arms
    # DISABLED (2026-07-24): the implicit multi-arm race intermittently
    # SIGBUSed inside worker-thread conflict analysis on small raw
    # kernels (13 crash reports against wassat-reaudit-e06). The inline
    # cache publication tear it exposed is fixed in the runtime
    # (w_ic_publish, runtime.h), but the crash never reproduced locally
    # under 100+ attempts, so the implicit race stays serial until the
    # original reproducer validates the fix. The explicit `portfolio`
    # subcommand and wassat_raw_race remain available for that
    # validation.
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

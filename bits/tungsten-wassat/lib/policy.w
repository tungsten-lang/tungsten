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
    # The existing kept-block implementation is sound but slower than ordinary
    # backjumping on every gate family. It is not exposed as an opt-in. This
    # policy method is the sole future activation point once true trail reuse
    # wins the automatic gate.
    false

  -> use_vivification
    # Vivification pays only after a meaningful learned database exists and is
    # currently proof-free. Avoid tiny formulas and huge watch rebuilds.
    @nclauses >= 1000 && @nclauses <= 50000 && @nliterals <= 1000000

  -> raw_race_arms
    return 8 if @nclauses >= 150000
    return 4 if @nclauses >= 50000
    1

  -> lookahead_candidates
    # Trial propagation is a strong win for compact random 3-SAT and
    # pigeonhole-like "one long choice plus many binary exclusions" tasks,
    # but a loss on the large structured kernels. Select it from shape rather
    # than exposing a tuning switch.
    random3 = @nvars >= 20 && @nvars <= 2000 && @nclauses >= 80 && @ternary * 4 >= @nclauses * 3
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

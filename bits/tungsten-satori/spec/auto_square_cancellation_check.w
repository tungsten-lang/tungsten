use ../lib/satori
use proof_source

-> check_auto_square_cancellation(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("prelude")
  good = ["shared", "weighted", "two_bounds", "cycle", "reordered", "function", "strict", "quartic"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_square_cancellation.sat", good))
  if session.failures != 0
    raise "square cancellation failed: " + suffix
  good.each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != ["oracle:arith"]
      raise "square cancellation missing, open or has unexpected trust: " + name
  ["factor", "strict_without_margin", "missing_guard", "reversed_guard", "missing_cycle_bound", "wrong_function", "negative_scale"].each -> (part)
    name = suffix + "_" + part
    before = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_square_cancellation_failure.sat", [name]))
    if session.failures != before + 1 || session.theorems[name] != nil
      raise "square cancellation accepted a false inequality: " + name
  if suffix == "rat"
    k = session.k
    theorem = session.theorems["rat_reordered"]
    fixes = []
    ["orchid", "maple", "weight"].each -> (name)
      v = mk_var(name, ty_rat)
      fixes.push([name, v])
      theorem = k.spec(v, theorem)
    goal = Goal.new(fixes, [], theorem.concl)
    ref = GoalRef.new(goal, nil, 0)
    prover = Prover.new(session)
    prover.goals = [ref]
    proof = prover.auto_square_arithmetic(goal, [2])
    if proof == nil || prover.fit(ref, proof).tags != ["oracle:arith"]
      raise "detached square proof failed"
    budget = [0]
    if prover.auto_square_arithmetic(goal, budget) != nil || budget != [0]
      raise "square cancellation ignored exhausted fuel"
    power = k.mk_const("^", ty_funs([ty_rat, ty_nat], ty_rat))
    large = mk_apps(power, [fixes[0][1], mk_nat(32)])
    if prover.auto_square_arithmetic(goal.with_concl(k.eq_tm(large, large)), [2]) != nil
      raise "square cancellation ignored expansion limits"
    session.run_source("axiom sq_nonneg.rat (a : ℚ) : 0 ≤ a^2\n")
    if prover.auto_square_arithmetic(goal, [2]) != nil
      raise "square cancellation silently selected a named square axiom"
    if prover.goals.size != 1 || prover.goals[0] != ref || ref.thm != nil
      raise "detached square attempts changed the caller's goal"
  << "Square cancellation passed: " + suffix

use ../lib/satori
use proof_source

-> check_auto_arithmetic_cases(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("prelude")
  good = ["order", "strict_order", "zero_product", "union", "product_sign", "strict_square", "swapped", "fresh_name", "two_nonzero", "duplicate"].map -> (name) suffix + "_" + name
  nonzero = [suffix + "_cancel", suffix + "_symmetric"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_arithmetic_cases.sat", good))
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_nonzero_arithmetic.sat", nonzero))
  if session.failures != 0
    raise "arithmetic cases failed: " + suffix
  (good + nonzero).each -> (name)
    tags = ["oracle:arith"]
    if suffix == "nat" && !name.ends_with?("_order")
      tags.push("oracle:ring")
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != tags
      raise "arithmetic case missing, open or has unexpected trust: " + name
  ["wrong_order", "nonzero_product", "missing_upper", "wrong_sign", "gap", "branch_leak", "missing_second"].each -> (part)
    name = suffix + "_" + part
    before = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_arithmetic_cases_failure.sat", [name]))
    if session.failures != before + 1 || session.theorems[name] != nil
      raise "arithmetic cases accepted a false disjunction or leaked branch: " + name
  ["missing", "wrong_value", "wrong_factor"].each -> (part)
    name = suffix + "_" + part
    before = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_nonzero_arithmetic_failure.sat", [name]))
    if session.failures != before + 1 || session.theorems[name] != nil
      raise "nonzero arithmetic accepted a false cancellation: " + name
  if suffix == "nat"
    x = mk_var("x", ty_nat)
    lt = session.k.mk_const("<", ty_funs([ty_nat, ty_nat], ty_bool))
    zero = mk_nat(0)
    claim = session.k.bin("∨", mk_apps(lt, [x, zero]), mk_apps(lt, [zero, x]))
    ref = GoalRef.new(Goal.new([["x", x]], [], claim), nil, 0)
    prover = Prover.new(session)
    prover.goals = [ref]
    result = prover.auto_arithmetic_disjunction(ref.goal, 4, [], [24, 4], [])
    if result != nil || prover.goals.size != 1 || prover.goals[0] != ref || ref.thm != nil
      raise "failed arithmetic cases changed the caller's goal"
    budget = [0, 4]
    if prover.auto_arithmetic_disjunction(ref.goal, 4, [], budget, []) != nil || budget != [0, 4]
      raise "arithmetic cases ignored exhausted fuel"
  << "Arithmetic cases passed: " + suffix

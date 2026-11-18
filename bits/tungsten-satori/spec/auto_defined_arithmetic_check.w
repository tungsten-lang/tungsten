use ../lib/satori
use proof_source

-> check_auto_defined_arithmetic(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("prelude")
  defs = ["shift", "total", "ordered", "positive", "pairwise", "allowance", "record"].map -> (name) name + "." + suffix
  good = ["shift_bound", "ordered", "positive", "equal_totals", "record", "guarded", "hint", "local_hint"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_defined_arithmetic.sat", defs + good))
  if session.failures != 0
    raise "defined arithmetic failed: " + suffix
  good.each -> (name)
    tags = name.ends_with?("_equal_totals") ? [] : ["oracle:arith"]
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != tags
      raise "defined arithmetic missing, open or unexpectedly trusted: " + name
  ["wrong_shift", "missing_order", "strict_equal", "wrong_record", "missing_guard", "wrong_guard"].each -> (part)
    name = suffix + "_" + part
    before = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_defined_arithmetic_failure.sat", [name]))
    if session.failures != before+1 || session.theorems[name] != nil
      raise "defined arithmetic accepted a false bound or missing guard: " + name
  if suffix == "nat"
    pair_ty = ty_con("prod", [ty_nat, ty_nat])
    v = mk_var("v", pair_ty)
    shifted = mk_app(session.k.mk_const("shift.nat", ty_fun(pair_ty, pair_ty)), v)
    total = mk_app(session.k.mk_const("total.nat", ty_fun(pair_ty, ty_nat)), shifted)
    claim = mk_apps(session.k.mk_const("≤", ty_funs([ty_nat, ty_nat], ty_bool)), [mk_nat(4), total])
    ref = GoalRef.new(Goal.new([["v", v]], [], claim), nil, 0)
    prover = Prover.new(session)
    prover.goals = [ref]
    result = prover.auto_defined_arithmetic(ref.goal, [], [24, 4])
    if result != nil || prover.goals.size != 1 || prover.goals[0] != ref || ref.thm != nil
      raise "failed definition normalization changed the caller's goal"
  << "Defined arithmetic passed: " + suffix

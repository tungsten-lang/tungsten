use ../lib/satori
use proof_source

-> check_auto_finite_cases(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("prelude")
  defs = ["mode"]
  good = []
  bad = []
  if suffix == "generic"
    defs = defs + ["quarter", "cycle", "choose", "code", "blend", "mark", "ghost"]
    good = ["cycle_three", "cycle_distinct", "choose_first", "choose_second", "choose_equal", "choose_guard", "excluded_case", "impossible_mark", "blend_commutes", "blend_bound", "blend_formula", "phantom_cases"]
    bad = ["cycle_fixed", "cycle_twice", "choose_unrestricted", "choose_wrong_projection", "choose_missing_guard", "forgotten_case", "possible_mark", "blend_too_small", "blend_wrong_formula", "blend_point"]
  else
    defs = defs + (["weight", "scale"].map -> (name) name + "." + suffix)
    good = ["formula", "add", "nonnegative", "positive", "monotone", "paired"].map -> (name) suffix + "_" + name
    bad = ["wrong_formula", "wrong_add", "too_large", "wrong_monotone", "wrong_pair"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_finite_cases.sat", defs + good))
  if session.failures != 0
    raise "automatic finite cases failed: " + suffix
  good.each -> (name)
    tags = []
    if suffix != "generic"
      tags = ["oracle:arith"]
      if [suffix + "_formula", suffix + "_add", suffix + "_paired"].include?(name)
        tags = ["oracle:ring"]
      if name == "nat_nonnegative"
        tags = []
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != tags
      raise "finite case theorem missing, open or unexpectedly trusted: " + name
  bad.each -> (name)
    before = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_finite_cases_failure.sat", [name]))
    if session.failures != before+1 || session.theorems[name] != nil
      raise "finite cases accepted an invalid or omitted constructor case: " + name
  if suffix == "generic"
    body = session.d.spec_all(session.theorems["blend_formula"]).concl
    fixes = tm_frees(body).map -> (v) [v.name, v]
    prover = Prover.new(session)
    result = prover.auto_finite_cases(Goal.new(fixes, [], body), [], [24, 4])
    if result == nil || !tm_eq(result.concl, body) || result.hyps.size != 0 || result.tags != []
      raise "the complete sixteen-case table was not checked"
    ty = ty_con("quarter", [])
    a = mk_var("a", ty)
    b = mk_var("b", ty)
    value = mk_apps(session.k.mk_const("blend", ty_funs([ty, ty], ty_nat)), [a, b])
    claim = mk_apps(session.k.mk_const("≤", ty_funs([ty_nat, ty_nat], ty_bool)), [value, mk_nat(5)])
    ref = GoalRef.new(Goal.new([["a", a], ["b", b]], [], claim), nil, 0)
    prover.goals = [ref]
    budget = [24, 4]
    result = prover.auto_finite_cases(ref.goal, [], budget)
    if result != nil || prover.goals.size != 1 || prover.goals[0] != ref || ref.thm != nil || budget[0] <= 0
      raise "failed finite cases changed the caller or exhausted fallback search"
    before = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_finite_cases_failure.sat", ["packet", "payload_is_not_empty"]))
    if session.failures != before+1 || session.theorems["payload_is_not_empty"] != nil || session.k.inductives["packet"] == nil
      raise "finite cases ignored a constructor payload"
    session.run_source("inductive large_enum\n  | large_a\n  | large_b\n  | large_c\n  | large_d\n  | large_e\n")
    if session.failures != before+1 || session.k.inductives["large_enum"] == nil
      raise "finite case limit fixture did not load"
    [ty_con("packet", []), ty_con("large_enum", []), ty_nat].each -> (kind)
      v = mk_var("value", kind)
      probe = Goal.new([["value", v]], [], session.k.eq_tm(v, v))
      if prover.auto_finite_cases(probe, [], [24, 4]) != nil
        raise "finite case recognition exceeded its constructor bounds"
  << "Automatic finite cases passed: " + suffix

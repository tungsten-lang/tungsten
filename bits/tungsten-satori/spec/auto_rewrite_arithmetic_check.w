use ../lib/satori
use proof_source

-> check_auto_rewrite_arithmetic(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("prelude")
  stem = "measure_" + suffix
  definitions = [stem, "allowed_" + suffix, stem + "_formula", stem + "_guarded"]
  names = ["zero", "upper", "local", "guarded", "applied", "assumed", "unused"].map -> (part) suffix + "_" + part
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_rewrite_arithmetic.sat", definitions + names))
  if session.failures != 0
    raise "supplied arithmetic rewrite failed: " + suffix
  names.each -> (name)
    tags = ["oracle:arith"]
    if suffix == "nat"
      tags.push("oracle:ring")
    if !name.ends_with?("_assumed")
      axiom = name.ends_with?("_guarded") || name.ends_with?("_applied") ? "_guarded" : "_formula"
      tags = ["axiom:" + stem + axiom] + tags
    proof = session.theorems[name]
    if proof == nil || proof.hyps.size != 0 || tm_frees(proof.concl).size != 0 || proof.tags != tags
      raise "supplied rewrite proof missing, open or has wrong dependencies: " + name
  ["unsupplied", "missing_guard", "wrong_guard", "wrong_component", "nonzero_total", "strict"].each -> (part)
    name = suffix + "_" + part
    before = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_rewrite_arithmetic_failure.sat", [name]))
    if session.failures != before + 1 || session.theorems[name] != nil
      raise "supplied rewrite accepted a false goal or missing guard: " + name
  if suffix == "nat"
    x = mk_var("x", ty_nat)
    claim = session.k.eq_tm(x, mk_nat(0))
    ref = GoalRef.new(Goal.new([["x", x]], [], claim), nil, 0)
    prover = Prover.new(session)
    prover.goals = [ref]
    hints = [session.theorems[stem + "_formula"]]
    result = prover.auto_defined_arithmetic(ref.goal, hints, [24, 4], true)
    if result != nil || prover.goals.size != 1 || prover.goals[0] != ref || ref.thm != nil
      raise "failed arithmetic rewrite changed the caller's goal"
  << "Supplied arithmetic rewrites passed: " + suffix

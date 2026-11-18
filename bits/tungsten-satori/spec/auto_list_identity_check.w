use ../lib/satori
use proof_source

-> check_auto_list_identity(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["list.recursive_identity"]))
  rule = session.theorems["list.recursive_identity"]
  if rule == nil || rule.hyps.size != 0 || rule.tags != []
    raise "list induction is not kernel-only"
  defs = ["items", "twice", "weighted", "units", "twounits", "rows"].map -> (name) name + "." + suffix
  good = ["defined", "reverse", "scaled", "generic", "same_step", "offset", "sum", "parameter", "hinted", "local_hint"].map -> (name) suffix + "_" + name
  if suffix == "rat"
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/logic.sat", ["prod", "fst", "snd"]))
    defs = defs + ["data_mass", "data_moment", "data_energy", "pair_energy", "tensor_energy"]
    good = good + ["rat_pair_energy", "rat_tensor_energy"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_list_identity.sat", defs + good))
  if session.failures != 0
    raise "automatic list identity failed: " + suffix
  good.each -> (name)
    expected = ["oracle:ring"]
    if name.ends_with?("_reverse")
      expected = ["oracle:arith"]
    if name.ends_with?("_same_step") || name.ends_with?("_parameter")
      expected = []
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "list identity missing, open or has unexpected trust: " + name
  bad = ["missing_base", "missing_left_step", "missing_right_step", "wrong_base", "wrong_step", "point_head", "point_tail", "singleton_step", "wrong_list", "guarded_step"].map -> (name) suffix + "_" + name
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_list_identity_failure.sat", [name]))
    if session.failures != previous+1 || session.theorems[name] != nil
      raise "list induction accepted missing or invalid premises: " + name
  if suffix == "rat"
    session.run_source("opaque marked_list : list ℚ → ℚ\naxiom list_base : marked_list \[] = 0\naxiom list_step : ∀ x xs, marked_list (x :: xs) = x+marked_list xs\n")
    previous = session.failures
    session.run_source("+ unsupplied (xs : list ℚ) : marked_list xs = items.rat xs := by auto\n")
    if session.failures != previous+1 || session.theorems["unsupplied"] != nil
      raise "list induction used an unsupplied axiom"
    session.run_source("+ marked (xs : list ℚ) : marked_list xs = items.rat xs := by auto \[list_base, list_step]\n+ local_marked (xs : list ℚ) : marked_list xs = items.rat xs\n  have base := list_base\n  have step := list_step\n  auto\n")
    ["marked", "local_marked"].each -> (name)
      th = session.theorems[name]
      if th == nil || th.hyps.size != 0 || th.tags != ["axiom:list_base", "axiom:list_step"]
        raise "list induction lost supplied assumption tags"
  << "Automatic list identities passed: " + suffix

use ../lib/satori
use proof_source

-> check_auto_recurrence_family(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/recurrence.sat", ["recurrence.identity", "recurrence.family"]))
  family = session.theorems["recurrence.family"]
  if family == nil || family.hyps.size != 0 || family.tags != []
    raise "family induction is not kernel-only"
  defs = ["count", "walk", "scaled", "forced", "first"].map -> (name) name + "." + suffix
  good = ["walk", "reverse", "scaled", "forced", "first", "supplied", "same_call", "product"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_recurrence_family.sat", defs + good))
  if session.failures != 0
    raise "automatic recurrence family failed: " + suffix
  good.each -> (name)
    expected = ["oracle:ring"]
    if name.ends_with?("_same_call") || name.ends_with?("_product")
      expected = []
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "recurrence family missing, open or has unexpected trust: " + name
  bad = ["point_base", "point_step", "missing_base", "missing_step", "wrong_base", "wrong_shift", "late_step", "guarded_step", "next_index", "wrong_parameter"].map -> (name) suffix + "_" + name
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_recurrence_family_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "recurrence family generalized a point assumption: " + name
  if suffix == "rat"
    session.run_source("opaque marked_family : ℕ → ℚ → ℚ\naxiom family_base : ∀ a, marked_family 0 a = a\naxiom family_step : ∀ i a, marked_family (i+1) a = marked_family i (a+1)\n")
    previous = session.failures
    session.run_source("+ unsupplied (n : ℕ) (a : ℚ) : marked_family n a = a+count.rat n := by auto\n")
    if session.failures != previous + 1 || session.theorems["unsupplied"] != nil
      raise "family induction used an unsupplied axiom"
    session.run_source("+ marked (n : ℕ) (a : ℚ) : marked_family n a = a+count.rat n := by auto \[family_base, family_step]\n+ local_marked (n : ℕ) (a : ℚ) : marked_family n a = a+count.rat n\n  have base := family_base\n  have step := family_step\n  auto\n")
    ["marked", "local_marked"].each -> (name)
      th = session.theorems[name]
      if th == nil || th.hyps.size != 0 || th.tags != ["axiom:family_base", "axiom:family_step", "oracle:ring"]
        raise "family induction lost supplied assumption tags"
  << "Automatic recurrence families passed: " + suffix

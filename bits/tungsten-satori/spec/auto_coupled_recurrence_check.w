use ../lib/satori
use proof_source

-> check_auto_coupled_recurrence(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/recurrence.sat", ["recurrence.identity"]))
  good = ["defined", "defined_reverse", "product", "sum", "same_step", "offset", "four", "family"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_coupled_recurrence.sat", ["tick." + suffix, "squares." + suffix] + good))
  if session.failures != 0
    raise "automatic coupled recurrence failed: " + suffix
  good.each -> (name)
    expected = ["oracle:ring"]
    if name.ends_with?("_defined_reverse")
      expected = ["oracle:arith"]
    if name.ends_with?("_same_step") || name.ends_with?("_family")
      expected = []
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "coupled recurrence missing, open or has unexpected trust: " + name
  bad = ["missing_base", "missing_left_step", "missing_right_step", "wrong_base", "wrong_step", "point_step", "late_step", "wrong_index", "wrong_parameter", "conditional_step"].map -> (name) suffix + "_" + name
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_coupled_recurrence_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "coupled recurrence accepted missing or incorrect premises: " + name
  if suffix == "rat"
    session.run_source("opaque left_sequence : ℕ → ℚ\nopaque right_sequence : ℕ → ℚ\naxiom sequence_base : left_sequence 0 = right_sequence 0\naxiom left_step : ∀ i, left_sequence (i+1) = left_sequence i+1\naxiom right_step : ∀ i, right_sequence (i+1) = right_sequence i+1\n")
    previous = session.failures
    session.run_source("+ unsupplied (n : ℕ) : left_sequence n = right_sequence n := by auto\n")
    if session.failures != previous + 1 || session.theorems["unsupplied"] != nil
      raise "coupled recurrence used an unsupplied axiom"
    session.run_source("+ marked (n : ℕ) : left_sequence n = right_sequence n := by auto \[sequence_base, left_step, right_step]\n+ local_marked (n : ℕ) : left_sequence n = right_sequence n\n  have base := sequence_base\n  have left := left_step\n  have right := right_step\n  auto\n")
    ["marked", "local_marked"].each -> (name)
      th = session.theorems[name]
      if th == nil || th.hyps.size != 0 || th.tags != ["axiom:left_step", "axiom:right_step", "axiom:sequence_base"]
        raise "coupled recurrence lost a supplied assumption"
  << "Automatic coupled recurrences passed: " + suffix

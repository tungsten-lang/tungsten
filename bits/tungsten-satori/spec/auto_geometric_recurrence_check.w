use ../lib/satori
use proof_source

-> check_auto_geometric_recurrence(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["mul_le_mul_of_nonneg_left." + suffix]))
  rules = ["recurrence.geometric_forcing." + suffix, "recurrence.geometric_sum." + suffix]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/recurrence.sat", rules))
  good = ["sum", "sum_reverse", "defined_sum", "forcing", "quantified_forcing"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_geometric_recurrence.sat", ["partial_" + suffix] + good))
  if session.failures != 0
    raise "automatic geometric recurrence failed: " + suffix
  (rules + good).each -> (name)
    expected = ["oracle:ring"]
    if name.include?("forcing")
      expected = ["oracle:arith"]
    if name.ends_with?("_sum_reverse")
      expected = ["oracle:arith", "oracle:ring"]
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "geometric recurrence missing, open or has unexpected trust: " + name
  bad = ["sum_missing_base", "sum_missing_step", "sum_wrong_index", "forcing_missing_rate", "forcing_missing_gap", "forcing_missing_base"].map -> (name) suffix + "_" + name
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_geometric_recurrence_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "geometric recurrence accepted missing premises or wrong indices: " + name
  if suffix == "rat"
    session.run_source("opaque marked_total : ℕ → ℚ\naxiom marked_base : marked_total 0 = 0\naxiom marked_step : ∀ i, marked_total (i+1) = marked_total i+2^i\n")
    previous = session.failures
    session.run_source("+ unsupplied_sum (n : ℕ) : (1-2)*marked_total n = 1-2^n := by auto\n")
    if session.failures != previous + 1 || session.theorems["unsupplied_sum"] != nil
      raise "geometric sum used an unsupplied axiom"
    session.run_source("+ marked_sum (n : ℕ) : (1-2)*marked_total n = 1-2^n := by auto \[marked_base, marked_step]\n+ local_marked_sum (n : ℕ) : (1-2)*marked_total n = 1-2^n\n  have base := marked_base\n  have step := marked_step\n  auto \[base, step]\n")
    ["marked_sum", "local_marked_sum"].each -> (name)
      th = session.theorems[name]
      if th == nil || th.hyps.size != 0 || th.tags != ["axiom:marked_base", "axiom:marked_step", "oracle:ring"]
        raise "geometric sum lost explicit assumption tags: " + name
  if suffix == "real"
    session.run_source("opaque forced_total : ℕ → ℝ\naxiom forced_base : forced_total 0 ≤ 0\naxiom forced_step : ∀ i, forced_total (i+1) ≤ 2*forced_total i+(-3)*3^i\n")
    previous = session.failures
    session.run_source("+ unsupplied_forcing (n : ℕ) : (3-2)*forced_total n ≤ (-3)*(3^n-2^n) := by auto\n")
    if session.failures != previous + 1 || session.theorems["unsupplied_forcing"] != nil
      raise "forced recurrence used an unsupplied axiom"
    session.run_source("+ marked_forcing (n : ℕ) : (3-2)*forced_total n ≤ (-3)*(3^n-2^n) := by auto \[forced_base, forced_step]\n")
    th = session.theorems["marked_forcing"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:forced_base", "axiom:forced_step", "oracle:arith"]
      raise "forced recurrence lost explicit assumption tags"
  << "Automatic geometric recurrence passed: " + suffix

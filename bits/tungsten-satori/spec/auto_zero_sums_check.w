use ../lib/satori
use proof_source

-> check_auto_zero_sums(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  basics = ["sum_below_zero", "sum_below_succ", "sum_below.congr", "sum_below.zero." + suffix, "sum_below.eq_zero." + suffix]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", basics))
  good = ["constant", "pointwise", "smaller", "all", "cancel", "alias", "guarded", "empty"]
  names = good.map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_zero_sums.sat", [suffix + "_zero_weight"] + names))
  if session.failures != 0
    raise "automatic zero sums failed: " + suffix
  good.each -> (name)
    th = session.theorems[suffix + "_" + name]
    expected = ["oracle:arith"]
    if name == "constant" || name == "empty"
      expected = []
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "automatic zero sum missing, open or has unexpected trust: " + suffix + "_" + name
  ["missing", "outside", "wrong_function", "wrong_total", "weak", "cycle"].each -> (name)
    full = suffix + "_" + name
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_zero_sums_failure.sat", [full]))
    if session.failures != previous + 1 || session.theorems[full] != nil
      raise "automatic zero sum accepted an invalid premise or total: " + full
  if suffix == "real"
    previous = session.failures
    session.run_source("opaque hidden : ℕ → ℝ\naxiom hidden_zero : ∀ i, hidden i = 0\n+ marked (n : ℕ) : (∑ i < n, hidden i) = 0 := by auto \[hidden_zero]\n")
    th = session.theorems["marked"]
    if session.failures != previous || th == nil || th.hyps.size != 0 || th.tags != ["axiom:hidden_zero"]
      raise "automatic zero sum lost the supplied zero assumption tag"
  << "Automatic zero sums passed: " + suffix

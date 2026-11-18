use ../lib/satori
use proof_source

-> check_auto_single_sum(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  rules = ["single_out", "single", "single_eq"].map -> (name) "sum_below." + name + "." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below_zero", "sum_below_succ"] + rules))
  names = ["inside", "outside", "boundary", "last", "larger", "alias", "product", "nested", "known_value", "calculated_value", "value_from_arithmetic"]
  good = names.map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_single_sum.sat", [suffix + "_pick"] + good))
  if session.failures != 0
    raise "automatic single-index sums failed: " + suffix
  (good + rules).each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
      raise "single-index sum missing, open or has unexpected trust: " + name
  bad = ["missing_inside", "missing_outside", "closed_inside", "wrong_index", "wrong_value", "nonzero_else", "wrong_predicate", "wrong_value_index", "unproved_value", "missing_inner"].map -> (name) suffix + "_" + name
  if suffix == "nat"
    bad.push("generic")
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_single_sum_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "automatic single-index sum accepted invalid values or ranges: " + name
  if suffix == "real"
    previous = session.failures
    session.run_source("opaque hidden_f : ℕ → ℝ\nopaque hidden_j : ℕ\naxiom hidden_value : hidden_f hidden_j = 4\n+ marked_single (n : ℕ) (h : hidden_j < n) : (∑ i < n, hidden_f i*(if i=hidden_j then 1 else 0)) = 4 := by auto \[hidden_value]\n")
    th = session.theorems["marked_single"]
    if session.failures != previous || th == nil || th.hyps.size != 0 || th.tags != ["axiom:hidden_value", "oracle:arith"]
      raise "single-index sum lost its selected-value assumption tag"
  << "Automatic single-index sums passed: " + suffix

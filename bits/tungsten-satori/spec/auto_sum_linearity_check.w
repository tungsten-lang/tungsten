use ../lib/satori
use proof_source

-> check_auto_sum_linearity(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  basics = ["sum_below_zero", "sum_below_succ", "sum_below.congr", "sum_add." + suffix, "sum_const_mul." + suffix, "sum_below.scale." + suffix, "sum_below.add." + suffix]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", basics))
  good = ["scale", "scale_larger", "scale_algebra", "scale_reverse", "add", "add_larger", "add_algebra", "alias"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_linearity.sat", [suffix + "_combine"] + good))
  if session.failures != 0
    raise "automatic termwise linearity failed: " + suffix
  (good + ["sum_below.scale." + suffix, "sum_below.add." + suffix]).each -> (name)
    th = session.theorems[name]
    polynomial = name == suffix + "_add_algebra" || name == suffix + "_alias"
    expected = polynomial ? ["oracle:ring"] : ["oracle:arith", "oracle:ring"]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "automatic termwise linearity missing, open or has unexpected trust: " + name
  bad = ["scale_missing", "scale_outside", "wrong_scalar", "scale_cycle", "add_missing", "add_outside", "wrong_summand"].map -> (name) suffix + "_" + name
  if suffix == "nat"
    bad = bad + ["generic_scale", "generic_add"]
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_linearity_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "automatic linearity accepted invalid coefficients, ranges or premises: " + name
  if suffix == "real"
    previous = session.failures
    session.run_source("opaque hidden_f : ℕ → ℝ\nopaque hidden_g : ℕ → ℝ\nopaque hidden_k : ℕ → ℝ\naxiom hidden_scale : ∀ i, hidden_f i = 3 * hidden_g i\naxiom hidden_add : ∀ i, hidden_f i = hidden_g i + hidden_k i\n+ marked_scale (n : ℕ) : (∑ i < n, hidden_f i) = 3 * (∑ i < n, hidden_g i) := by auto \[hidden_scale]\n+ marked_add (n : ℕ) : (∑ i < n, hidden_f i) = (∑ i < n, hidden_g i) + (∑ i < n, hidden_k i) := by auto \[hidden_add]\n")
    ["scale", "add"].each -> (name)
      th = session.theorems["marked_" + name]
      if session.failures != previous || th == nil || th.hyps.size != 0 || th.tags != ["axiom:hidden_" + name, "oracle:ring"]
        raise "automatic linearity lost or mixed pointwise assumption tags"
  << "Automatic termwise linearity passed: " + suffix

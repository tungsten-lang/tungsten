use ../lib/satori
use proof_source

-> check_auto_sum_distribution(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  rules = ["sum_add", "sum_const_mul", "sum_mul_const", "sum_below.zero", "sum_below.single_out", "sum_below.single"].map -> (name) name + "." + suffix
  if suffix != "nat"
    rules = rules + ["sum_sub." + suffix, "mul_sub." + suffix]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below_zero", "sum_below_succ"] + rules))
  names = ["pair", "offset", "repeated", "outside", "mixed", "boundary"]
  if suffix != "nat"
    names = names + ["difference", "triangle"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_distribution.sat", names.map(-> (name) suffix + "_" + name)))
  if session.failures != 0
    raise "automatic sum distribution failed: " + suffix
  names.each -> (name)
    th = session.theorems[suffix + "_" + name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
      raise "automatic distribution missing, open or has unexpected trust: " + name
  bad = ["missing_range", "closed_range", "wrong_weight", "wrong_sign", "wrong_bound", "branch_leak", "conditional_guard"].map -> (name) suffix + "_" + name
  if suffix == "nat"
    bad = bad + ["natural_difference", "generic_pair"]
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_distribution_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "automatic distribution accepted invalid signs or ranges: " + name
  if suffix == "real"
    previous = session.failures
    session.run_source("opaque hidden_f : ℕ → ℝ\nopaque hidden_a : ℕ\nopaque hidden_b : ℕ\nopaque hidden_n : ℕ\naxiom hidden_ranges : hidden_a < hidden_n ∧ hidden_b < hidden_n\n+ marked_distribution : (∑ i < hidden_n, hidden_f i*((if i=hidden_a then 1 else 0)+(if i=hidden_b then 1 else 0))) = hidden_f hidden_a+hidden_f hidden_b := by auto \[hidden_ranges]\n")
    th = session.theorems["marked_distribution"]
    if session.failures != previous || th == nil || th.hyps.size != 0 || th.tags != ["axiom:hidden_ranges", "oracle:arith", "oracle:ring"]
      raise "automatic distribution lost its range assumption tag"
  << "Automatic sum distribution passed: " + suffix

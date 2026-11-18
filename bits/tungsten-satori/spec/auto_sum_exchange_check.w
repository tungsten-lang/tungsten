use ../lib/satori
use proof_source

-> check_auto_sum_exchange(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  basics = ["sum_below_zero", "sum_below_succ", "sum_below.congr", "sum_add." + suffix, "sum_const_mul." + suffix, "sum_below.zero." + suffix, "sum_below.swap." + suffix, "sum_below.exchange." + suffix]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", basics))
  good = ["bilinear", "left_weights", "guarded", "reverse", "larger", "alias"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_exchange.sat", [suffix + "_row", suffix + "_col"] + good))
  if session.failures != 0
    raise "automatic weighted exchange failed: " + suffix
  (good + ["sum_below.exchange." + suffix]).each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
      raise "automatic weighted exchange missing, open or has unexpected trust: " + name
  bad = ["missing", "outside_i", "outside_j", "wrong_weight", "wrong_entry", "weak", "cycle"].map -> (name) suffix + "_" + name
  if suffix == "nat"
    bad.push("generic")
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_exchange_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "automatic exchange accepted invalid weights, ranges or premises: " + name
  if suffix == "real"
    previous = session.failures
    session.run_source("opaque hidden_f : ℕ → ℕ → ℝ\nopaque hidden_g : ℕ → ℕ → ℝ\naxiom hidden_relation : ∀ i j, 2 * hidden_f i j = 3 * hidden_g j i\n+ marked (n m : ℕ) : (∑ i < n, 2 * (∑ j < m, hidden_f i j)) = (∑ j < m, 3 * (∑ i < n, hidden_g j i)) := by auto \[hidden_relation]\n")
    th = session.theorems["marked"]
    if session.failures != previous || th == nil || th.hyps.size != 0 || th.tags != ["axiom:hidden_relation", "oracle:arith", "oracle:ring"]
      raise "automatic weighted exchange lost its pointwise assumption tag"
  << "Automatic weighted exchange passed: " + suffix

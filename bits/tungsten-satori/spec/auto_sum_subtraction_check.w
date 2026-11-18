use ../lib/satori
use proof_source

-> check_auto_sum_subtraction(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below_zero", "sum_below_succ", "sum_below.congr", "sum_sub." + suffix, "sum_below.sub." + suffix]))
  names = ["direct", "termwise", "larger", "algebra", "alias", "reverse", "weighted", "nested"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_subtraction.sat", [suffix + "_difference"] + names.map(-> (name) suffix + "_" + name)))
  if session.failures != 0
    raise "automatic sum subtraction failed: " + suffix
  names.each -> (name)
    th = session.theorems[suffix + "_" + name]
    tags = ["oracle:arith", "oracle:ring"]
    if ["direct", "alias"].include?(name)
      tags = ["oracle:ring"]
    if th == nil || th.hyps.size != 0 || th.tags != tags
      raise "automatic sum subtraction missing, open or has unexpected trust: " + name
  th = session.theorems["sum_below.sub." + suffix]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
    raise "termwise subtraction lemma missing, open or has unexpected trust"
  bad = ["missing", "outside", "wrong_sign", "wrong_order", "wrong_range", "circular"].map -> (name) suffix + "_" + name
  if suffix == "int"
    bad = bad + ["natural", "generic"]
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_subtraction_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "automatic subtraction accepted invalid ranges, signs or premises: " + name
  if suffix == "real"
    previous = session.failures
    session.run_source("opaque hidden_f : ℕ → ℝ\nopaque hidden_g : ℕ → ℝ\nopaque hidden_k : ℕ → ℝ\naxiom hidden_sub : ∀ i, hidden_f i = hidden_g i - hidden_k i\n+ marked_sub (n : ℕ) : (∑ i < n, hidden_f i) = (∑ i < n, hidden_g i) - (∑ i < n, hidden_k i) := by auto \[hidden_sub]\n")
    th = session.theorems["marked_sub"]
    if session.failures != previous || th == nil || th.hyps.size != 0 || th.tags != ["axiom:hidden_sub", "oracle:arith", "oracle:ring"]
      raise "automatic subtraction lost its pointwise assumption tag"
  << "Automatic sum subtraction passed: " + suffix

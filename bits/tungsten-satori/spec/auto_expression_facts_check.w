use ../lib/satori
use proof_source

-> check_auto_expression_facts(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  rules = ["sum_add", "sum_const_mul", "sum_below.split", "sum_below.zero", "sum_below.swap", "sum_below.single_out", "sum_below.single"].map -> (name) name + "." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below_zero", "sum_below_succ"] + rules))
  names = ["offset", "bound", "strict", "outside", "add", "scale", "split", "swap"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_expression_facts.sat", names.map(-> (name) suffix + "_" + name)))
  if session.failures != 0
    raise "arithmetic expression facts failed: " + suffix
  names.each -> (name)
    th = session.theorems[suffix + "_" + name]
    tags = ["oracle:arith"]
    if ["add", "scale", "split", "swap"].include?(name)
      tags = ["oracle:arith", "oracle:ring"]
    if th == nil || th.hyps.size != 0 || th.tags != tags
      raise "arithmetic expression fact missing, open or has unexpected trust: " + name
  bad = ["missing_guard", "closed_guard", "wrong_index", "wrong_scale", "wrong_sum", "weak_strict", "reversed_outside", "conditional_leak", "branch_leak"]
  bad.each -> (name)
    previous = session.failures
    full_name = suffix + "_" + name
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_expression_facts_failure.sat", [full_name]))
    if session.failures != previous + 1 || session.theorems[full_name] != nil
      raise "expression facts accepted invalid guards or identities: " + full_name
  if suffix == "real"
    previous = session.failures
    session.run_source("opaque hidden_f : ℕ → ℝ\nopaque hidden_j : ℕ\nopaque hidden_n : ℕ\naxiom hidden_range : hidden_j < hidden_n\n+ marked_expression (v : ℝ) (h : hidden_f hidden_j+3 = v+2) : (∑ i < hidden_n, hidden_f i*(if i=hidden_j then 1 else 0))+1 = v := by auto \[hidden_range]\n")
    th = session.theorems["marked_expression"]
    if session.failures != previous || th == nil || th.hyps.size != 0 || th.tags != ["axiom:hidden_range", "oracle:arith"]
      raise "arithmetic expression fact lost its guard assumption tag"
    session.run_source("+ unmarked_expression (v : ℝ) (h : hidden_f hidden_j+3 = v+2) : (∑ i < hidden_n, hidden_f i*(if i=hidden_j then 1 else 0))+1 = v := by auto\n")
    if session.failures != previous + 1 || session.theorems["unmarked_expression"] != nil
      raise "arithmetic expression fact used an unsupplied guard axiom"
  << "Arithmetic expression facts passed: " + suffix

use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/nat.sat", ["min", "max"]))
session.run_import("order")
lemmas = ["min_cases.real", "max_cases.real", "min_le_left.real", "min_le_right.real", "le_min.real", "lt_min.real", "le_min_iff.real", "min_eq_left.real", "min_eq_right.real", "min_comm.real", "min_self.real", "le_max_left.real", "le_max_right.real", "max_le.real", "max_lt.real", "max_le_iff.real", "max_eq_left.real", "max_eq_right.real", "max_comm.real", "max_self.real", "min_le_max.real", "min_add_max.real", "max_le_max.real", "min_le_min.real", "max_le_mul_max.real", "mul_min_le_min.real"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/auto_minmax_real.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "automatic min/max bounds failed"
examples = ["lower", "upper", "strict_lower", "strict_upper", "min_endpoint", "max_endpoint", "chosen_min", "chosen_max", "min_commute", "max_commute", "sum", "min_monotone", "max_monotone", "clamp", "upper_endpoints", "lower_endpoints", "sum_bound", "scaled_max", "scaled_min", "pointwise", "branch", "alias", "explicit_bound"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith"]
  if name == "explicit_bound"
    expected = ["axiom:supplied_max", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "min/max proof missing, open or has unexpected trust: " + name
bad = ["missing_upper", "missing_lower", "weak_strict_upper", "weak_strict_lower", "wrong_min", "wrong_max", "wrong_endpoint", "missing_clamp_order", "branch_leak", "missing_scale_sign", "no_global_bound"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_minmax_real_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid min/max bound: " + name
# Both backward rules and automatically generated endpoints must reject
# replacement named axioms, even when they have familiar theorem names.
session.run_source("axiom max_le.real (a b c : ℝ) (h : a ≤ c) : max a b ≤ c\n")
previous = session.failures
session.run_source("+ poisoned_rule (a b c : ℝ) (h : a ≤ c) : max a b ≤ c := by auto\n")
if session.failures != previous + 1 || session.theorems["poisoned_rule"] != nil
  raise "auto silently selected a named maximum axiom"
session.run_source("+ explicit_poison (a b c : ℝ) (h : a ≤ c) : max a b ≤ c := by auto \[max_le.real]\n")
th = session.theorems["explicit_poison"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:max_le.real"]
  raise "explicit maximum axiom lost its dependency"
session.run_source("axiom le_max_left.real (a b : ℝ) : a ≤ b\n")
previous = session.failures
session.run_source("+ poisoned_endpoint (a b c : ℝ) (h : max a b ≤ c) : a ≤ b := by auto\n")
if session.failures != previous + 1 || session.theorems["poisoned_endpoint"] != nil
  raise "auto silently generated an endpoint from a named axiom"
isolated = Session.new(".")
isolated.quiet = true
isolated.no_cache = true
isolated.run_import("core")
isolated.run_source(proof_declarations("bits/tungsten-satori/prelude/nat.sat", ["min", "max"]))
isolated.run_source("+ no_hidden_minmax (a b c : ℝ) (h : max a b ≤ c) : a ≤ c := by auto\n")
if isolated.failures != 1 || isolated.theorems["le_max_left.real"] != nil || isolated.theorems["no_hidden_minmax"] != nil
  raise "auto imported min/max rules behind the caller's back"
<< "automatic real min/max bounds passed"

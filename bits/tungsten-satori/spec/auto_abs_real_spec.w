use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
lemmas = ["abs_cases.real", "abs_of_nonpos.real", "le_abs_self.real", "neg_le_abs.real", "neg_abs_le.real", "abs_le.real", "abs_lt.real", "abs_le_of.real", "abs_lt_of.real", "abs_neg.real", "abs_sub_comm.real", "abs_mul.real", "abs_add.real", "abs_sub.real", "abs_sub_le.real", "abs_sub_abs_le_abs_sub.real", "abs_abs_sub_abs_le.real", "abs_abs.real", "abs_pos.real", "abs_sq.real", "sq_abs.real", "sq_le_sq.real", "sq_lt_sq.real", "abs_le_of_sq_le_sq.real"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/auto_abs_real.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "absolute-value defaults failed"
examples = ["nonnegative", "positive", "nonnegative_value", "nonpositive_value", "interval", "strict_interval", "endpoints", "strict_endpoints", "weakened_endpoint", "triangle", "difference", "metric_triangle", "reverse_triangle", "product", "nested", "squared_bound", "strict_squared_order", "zero_bound", "pointwise", "explicit_bound"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith", "oracle:ring"]
  if name == "nonnegative" || name == "nonnegative_value" || name == "nested"
    expected = []
  if name == "explicit_bound"
    expected = ["axiom:known_abs", "oracle:arith", "oracle:ring"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "absolute-value proof missing, open or has unexpected trust: " + name
bad = ["missing_lower", "missing_upper", "weak_strict", "strict_endpoint", "wrong_endpoint", "negative_squared_bound", "wrong_value", "false_monotonicity", "branch_leak", "no_global_bound"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_abs_real_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid absolute-value bound: " + name
# Newly named assumptions must not become implicit rules or fact extractors.
session.run_source("axiom abs_le_of.real (x c : ℝ) : |x| < 0\n")
previous = session.failures
session.run_source("+ poisoned_default (x : ℝ) : |x| < 0 := by auto\n")
if session.failures != previous + 1 || session.theorems["poisoned_default"] != nil
  raise "auto silently selected a named absolute-value axiom"
session.run_source("axiom abs_lt.real (x c : ℝ) : |x| < c ↔ False\n")
previous = session.failures
session.run_source("+ poisoned_extraction (x c : ℝ) (h : |x| < c) : False := by auto\n")
if session.failures != previous + 1 || session.theorems["poisoned_extraction"] != nil
  raise "auto silently extracted a named absolute-value axiom"
session.run_source("+ explicit_extraction (x c : ℝ) (h : |x| < c) : False := by exact (abs_lt.real x c).mp h\n")
th = session.theorems["explicit_extraction"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:abs_lt.real"]
  raise "explicit absolute-value axiom lost its dependency"
isolated = Session.new(".")
isolated.quiet = true
isolated.no_cache = true
isolated.run_import("core")
isolated.run_source("+ no_hidden_abs (x c : ℝ) (h : |x| < c) : x < c := by auto\n")
if isolated.failures != 1 || isolated.theorems["abs_lt.real"] != nil || isolated.theorems["no_hidden_abs"] != nil
  raise "auto imported absolute-value lemmas behind the caller's back"
<< "absolute-value real defaults passed"

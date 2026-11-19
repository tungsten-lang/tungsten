use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
lemmas = ["mul_le_mul_of_nonneg_left.real", "mul_le_mul_of_nonneg_right.real", "mul_lt_mul_of_pos_left.real", "mul_lt_mul_of_pos_right.real", "one_div_pos.real", "one_div_nonneg.real", "one_div_neg.real", "eq_one_div_of_mul_eq_one.real", "one_div_one_div.real", "one_div_mul_one_div.real", "div_self.real", "mul_div_cancel.real", "mul_div_cancel_right.real", "mul_div_cancel_left.real", "div_pos.real", "div_nonneg.real", "div_le_div_of_nonneg_right.real", "div_lt_div_of_pos_right.real", "div_le_iff.real", "le_div_iff.real", "div_lt_iff.real", "lt_div_iff.real", "div_le_one.real", "eq_div_iff.real", "div_eq_iff.real", "mul_div_assoc.real", "add_div.real", "sub_div.real", "div_div.real", "div_mul_div.real", "div_add_div.real", "one_div_le_one_div_of_le.real", "one_div_lt_one_div_of_lt.real", "inv_le_inv.real", "inv_lt_inv.real", "div_le_div_of_nonneg_left.real", "div_le_div_iff.real", "div_lt_div_iff.real"]
lemmas = lemmas + ["div_eq_zero_of_den_eq_zero.real", "zero_div.real", "div_le_of_nonneg_den.real", "le_div_of_nonneg_den.real", "div_lt_of_nonneg_den.real", "lt_div_of_nonneg_den.real"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/auto_division_real.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "automatic division failed"
examples = ["square_over_bound", "lower_at_zero", "strict_at_zero", "strict_lower_at_zero", "zero_denominator", "zero_numerator", "discount_loss", "conditional_scale", "scaled_bound", "nested_slope", "positive", "nonnegative", "reciprocal_positive", "reciprocal_negative", "upper", "lower", "strict_upper", "strict_lower", "cross", "cross_strict", "numerator_order", "numerator_strict", "denominator_order", "reciprocal_order", "reciprocal_strict", "unit_bound", "self", "cancel", "cancel_right", "cancel_left", "equality", "equality_right", "guard_arithmetic", "nested", "double_inverse", "alias", "cleared_hint", "explicit_bound"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith", "oracle:ring"]
  if ["zero_denominator", "positive", "nonnegative", "reciprocal_positive", "reciprocal_negative", "numerator_order", "numerator_strict", "guard_arithmetic", "nested", "alias"].include?(name)
    expected = ["oracle:arith"]
  if ["zero_numerator", "cancel", "cancel_left", "cancel_right", "equality", "equality_right"].include?(name)
    expected = ["oracle:ring"]
  if name == "self"
    expected = []
  if name == "conditional_scale"
    expected = ["axiom:supplied_positive", "oracle:arith", "oracle:ring"]
  if name == "explicit_bound"
    expected = ["axiom:supplied_cross", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "division proof missing, open or has unexpected trust: " + name
bad = ["missing_zero_case", "weak_zero_case", "missing_positive_case", "missing_scale_guard", "wrong_scale_direction", "zero_scale_equality", "missing_slope_bound", "missing_positive", "zero_strict", "missing_denominator", "negative_denominator", "weak_denominator", "missing_second_denominator", "weak_strict", "wrong_numerator", "wrong_reciprocal", "missing_numerator_sign", "zero_cancel", "unguarded_self", "unguarded_equality", "branch_leak", "no_global_bound", "integer_quotient", "natural_quotient"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_division_real_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid quotient: " + name
# Cross multiplication is selected only for quotient goals. An ordinary
# product comparison must not invent an arbitrary denominator.
session.run_source("+ unwrapped (x y : ℝ) (h : x ≤ y) : x ≤ y := by auto\n")
prover = Prover.new(session)
goal = Goal.new([], [], session.theorems["unwrapped"].concl)
if prover.auto_default_hints(goal).size != 0
  raise "division defaults selected for an unwrapped comparison"
# New named axioms never become implicit rules.
session.run_source("axiom div_self.real (x : ℝ) (hx : x ≠ 0) : x/x = 2\n")
previous = session.failures
session.run_source("+ poisoned_rule (x : ℝ) (hx : x ≠ 0) : x/x = 2 := by auto\n")
if session.failures != previous + 1 || session.theorems["poisoned_rule"] != nil
  raise "auto silently selected a named division axiom"
session.run_source("+ explicit_poison (x : ℝ) (hx : x ≠ 0) : x/x = 2 := by auto \[div_self.real]\n")
th = session.theorems["explicit_poison"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:div_self.real"]
  raise "explicit division axiom lost its dependency"
isolated = Session.new(".")
isolated.quiet = true
isolated.no_cache = true
isolated.run_import("core")
isolated.run_source("+ no_hidden_division (x : ℝ) (hx : 0 < x) : 0 < 1/x := by auto\n")
if isolated.failures != 1 || isolated.theorems["one_div_pos.real"] != nil || isolated.theorems["no_hidden_division"] != nil
  raise "auto imported division rules behind the caller's back"
<< "automatic real division passed"

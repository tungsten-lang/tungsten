use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
lemmas = ["mul_le_mul_of_nonneg_left.rat", "mul_le_mul_of_nonneg_right.rat", "mul_lt_mul_of_pos_left.rat", "mul_lt_mul_of_pos_right.rat", "one_div_pos.rat", "one_div_nonneg.rat", "one_div_neg.rat", "eq_one_div_of_mul_eq_one.rat", "one_div_one_div.rat", "one_div_mul_one_div.rat", "div_self.rat", "mul_div_cancel.rat", "mul_div_cancel_right.rat", "mul_div_cancel_left.rat", "div_pos.rat", "div_nonneg.rat", "div_le_div_of_nonneg_right.rat", "div_lt_div_of_pos_right.rat", "div_le_iff.rat", "le_div_iff.rat", "div_lt_iff.rat", "lt_div_iff.rat", "div_le_one.rat", "eq_div_iff.rat", "div_eq_iff.rat", "mul_div_assoc.rat", "add_div.rat", "sub_div.rat", "div_div.rat", "div_mul_div.rat", "div_add_div.rat", "one_div_le_one_div_of_le.rat", "one_div_lt_one_div_of_lt.rat", "inv_le_inv.rat", "inv_lt_inv.rat", "div_le_div_of_nonneg_left.rat", "div_le_div_iff.rat", "div_lt_div_iff.rat"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/auto_division_rat.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "automatic division failed"
examples = ["positive", "nonnegative", "reciprocal_positive", "reciprocal_negative", "upper", "lower", "strict_upper", "strict_lower", "cross", "cross_strict", "numerator_order", "numerator_strict", "denominator_order", "reciprocal_order", "reciprocal_strict", "unit_bound", "self", "cancel", "cancel_right", "cancel_left", "equality", "equality_right", "guard_arithmetic", "nested", "double_inverse", "alias", "cleared_hint", "explicit_bound"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith", "oracle:ring"]
  if ["positive", "nonnegative", "reciprocal_positive", "reciprocal_negative", "numerator_order", "numerator_strict", "guard_arithmetic", "nested", "alias"].include?(name)
    expected = ["oracle:arith"]
  if ["cancel", "cancel_left", "cancel_right", "equality", "equality_right"].include?(name)
    expected = ["oracle:ring"]
  if name == "self"
    expected = []
  if name == "explicit_bound"
    expected = ["axiom:supplied_cross", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "division proof missing, open or has unexpected trust: " + name
bad = ["missing_positive", "zero_strict", "missing_denominator", "negative_denominator", "weak_denominator", "missing_second_denominator", "weak_strict", "wrong_numerator", "wrong_reciprocal", "missing_numerator_sign", "zero_cancel", "unguarded_self", "unguarded_equality", "branch_leak", "no_global_bound"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_division_rat_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid quotient: " + name
<< "automatic rat division passed"

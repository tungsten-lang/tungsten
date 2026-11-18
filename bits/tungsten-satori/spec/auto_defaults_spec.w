use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
session.run_import("real")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["abs_cases.real", "abs_of_nonpos.real", "sq_abs.real", "abs_cases.rat", "abs_of_nonpos.rat", "one_div_pos.real", "eq_one_div_of_mul_eq_one.real", "sum_below_zero", "sum_below_succ", "cast_add.int", "int_cast_add.real", "cast_add.real", "cast_zero.real", "cast_one.real", "cast_succ.real", "sum_const.real", "sum_mul_const.real", "sum_add.real", "sum_le.real"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/realx.sat", ["exp_neg_mul", "exp_neg", "exp_sub", "one_lt_exp", "exp_lt_exp_of_lt", "exp_le_exp", "log_one", "log_mul", "log_div", "log_le_log"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/exp_convex.sat", ["exp_tangent_le", "exp_weighted_jensen", "exp_midpoint_le", "one_add_lt_exp", "exp_tangent_lt", "exp_weighted_jensen_lt", "exp_midpoint_lt"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/log_convex.sat", ["log_tangent_le", "log_tangent_lt"]))
lemmas = ["mul_log_tangent_le", "mul_log_tangent_lt", "sub_one_le_mul_log", "neg_mul_log_le_scale", "neg_mul_log_le_of_le", "sum_below.entropy_le_log.real"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/entropy.sat", lemmas))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/order.sat", ["sq_nonneg.real"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/square_gap.sat", ["square_gap.le_abs.real", "square_gap.le_abs.rat"]))
fractions = ["mul_le_mul_of_nonneg_right", "mul_lt_mul_of_pos_right", "one_div_nonneg", "mul_div_cancel", "mul_div_cancel_right", "div_le_div_of_nonneg_right", "div_lt_div_of_pos_right", "div_le_iff", "le_div_iff", "div_lt_iff", "lt_div_iff", "div_le_div_iff", "div_lt_div_iff"].map -> (name) name + ".real"
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", fractions))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/realx.sat", ["sqrt_pos", "sqrt_le_iff", "le_sqrt_iff", "one_div_sqrt_le_div_iff", "one_div_sqrt_lt_div_iff", "div_le_one_div_sqrt_iff", "div_lt_one_div_sqrt_iff"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/sqrt_distance.sat", ["sqrt_sub_sq_le_abs", "sqrt_sub_abs_le"]))
examples = ["exponential_gap", "strict_midpoint", "root_distance", "scalar_entropy", "finite_entropy", "reciprocal_root", "nonnegative_square", "square_gap", "root_certificate", "zero_entropy", "equal_midpoint", "combined"]
session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_defaults.sat", examples))
if session.failures != 0
  raise "plain auto defaults failed"
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith", "oracle:ring"]
  if name == "nonnegative_square"
    expected = ["oracle:arith"]
  if name == "zero_entropy"
    expected = []
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "auto default theorem missing, open or has unexpected trust: " + name
# A finite entropy goal has one indexed candidate, not the whole default set.
prover = Prover.new(session)
goal = Goal.new([], [], session.theorems["finite_entropy"].concl)
if prover.auto_default_hints(goal).size != 1
  raise "auto default index selected unrelated shapes"
# Matching shapes from a different numeric family must not consume the budget.
goal = Goal.new([], [], session.theorems["square_gap"].concl)
candidates = prover.auto_default_hints(goal)
if candidates.size == 0
  raise "auto default index missed the square-gap bound"
candidates.each -> (candidate)
  if prover.auto_rule_shape(candidate.concl)[3] != prover.auto_rule_shape(goal.concl)[3]
    raise "auto default index selected a different numeric family"
bad = ["missing_exp_difference", "strict_equal", "missing_root_sign", "missing_entropy_sign", "missing_total", "root_wrong_sign", "strict_root_equality", "missing_square_sign"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_defaults_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "plain auto accepted an invalid bound: " + name
# Redefining a familiar name with a named axiom must not make it a default.
session.run_source("axiom one_add_lt_exp (x : ℝ) : exp x < 0\n")
previous = session.failures
session.run_source("+ poisoned_default (x : ℝ) : exp x < 0 := by auto\n")
if session.failures != previous + 1 || session.theorems["poisoned_default"] != nil
  raise "auto silently used a named axiom as a default"
session.run_source("+ explicit_assumption (x : ℝ) : exp x < 0 := by auto \[one_add_lt_exp]\n")
th = session.theorems["explicit_assumption"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:one_add_lt_exp"]
  raise "explicit hint did not preserve its named assumption"
# Defaults do not import additional libraries behind the caller's back.
isolated = Session.new(".")
isolated.quiet = true
isolated.no_cache = true
isolated.run_import("core")
isolated.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
isolated.run_import("real")
isolated.run_source("+ no_hidden_import (x y : ℝ) (hx : 0 ≤ x) (hy : 0 ≤ y) : |sqrt x-sqrt y| ≤ sqrt (|x-y|) := by auto\n")
if isolated.failures != 1 || isolated.theorems["sqrt_sub_abs_le"] != nil || isolated.theorems["no_hidden_import"] != nil
  raise "auto unexpectedly imported an optional library"
<< "plain auto defaults passed"

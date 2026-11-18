use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("order")
lemmas = ["mul_le_mul_left.nat", "mul_le_mul_right.nat", "mul_le_mul.nat", "pow_nonneg.nat", "pow_pos.nat", "one_le_pow.nat", "pow_le_one.nat", "pow_le_pow_left.nat", "pow_le_pow_right.nat", "pow_lt_pow_left.nat", "pow_lt_pow_right.nat"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/power.sat", ["pow_add.nat"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/auto_powers_nat.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "automatic powers failed"
examples = ["nonnegative", "positive", "unit_lower", "unit_upper", "base_order", "base_strict", "exponent_order", "exponent_strict", "derived_sign", "nested", "pointwise", "large_exponent", "explicit_bound", "subtract", "truncate", "recover"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith"]
  if ["nonnegative", "positive", "large_exponent"].include?(name)
    expected = []
  if ["exponent_order", "exponent_strict", "decay"].include?(name)
    expected = ["oracle:arith", "oracle:ring"]
  if name == "explicit_bound"
    expected = ["axiom:supplied_positive"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "power proof missing, open or has unexpected trust: " + name
bad = ["missing_positive", "zero_base", "weak_strict", "zero_exponent", "missing_exponent", "unit_strict", "wrong_direction", "weak_unit_upper", "branch_leak", "no_global_bound", "weak_subtract", "wrong_cancel", "subtract_branch"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_powers_nat_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid power bound: " + name
# An implicit subtraction split must use trusted core rules as well.
session.run_source("axiom sub_eq_zero.nat (a b : ℕ) : a ≤ b → a-b = 1\n")
previous = session.failures
session.run_source("+ poisoned_subtraction (a b : ℕ) (h : a < b) : a-b = 1 := by auto\n")
if session.failures != previous + 1 || session.theorems["poisoned_subtraction"] != nil
  raise "auto silently selected a named subtraction axiom"
session.run_source("+ explicit_subtraction (a b : ℕ) (h : a < b) : a-b = 1 := by auto \[sub_eq_zero.nat]\n")
th = session.theorems["explicit_subtraction"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:sub_eq_zero.nat", "oracle:arith"]
  raise "explicit subtraction axiom lost its dependency"
<< "automatic nat powers passed"

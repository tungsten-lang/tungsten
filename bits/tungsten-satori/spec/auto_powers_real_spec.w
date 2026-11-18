use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("order")
lemmas = ["pow_nonneg.real", "pow_pos.real", "one_le_pow.real", "pow_le_one.real", "pow_le_pow_left.real", "pow_le_pow_right.real", "pow_le_pow_of_le_one.real", "pow_lt_pow_left.real", "pow_lt_pow_right.real"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/power.sat", ["pow_add.real"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/auto_powers_real.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "automatic powers failed"
examples = ["nonnegative", "positive", "unit_lower", "unit_upper", "base_order", "base_strict", "exponent_order", "exponent_strict", "derived_sign", "nested", "pointwise", "large_exponent", "decay", "explicit_bound"]
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
bad = ["missing_positive", "zero_base", "weak_strict", "zero_exponent", "missing_exponent", "unit_strict", "wrong_direction", "weak_unit_upper", "branch_leak", "negative_base", "no_global_bound"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_powers_real_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid power bound: " + name
session.run_source("axiom pow_pos.real (a : ℝ) (n : ℕ) (h : 0 < a) : a^n < 0\n")
previous = session.failures
session.run_source("+ poisoned_power (a : ℝ) (n : ℕ) (h : 0 < a) : a^n < 0 := by auto\n")
if session.failures != previous + 1 || session.theorems["poisoned_power"] != nil
  raise "auto silently selected a named power axiom"
session.run_source("+ explicit_poison (a : ℝ) (n : ℕ) (h : 0 < a) : a^n < 0 := by auto \[pow_pos.real]\n")
th = session.theorems["explicit_poison"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:pow_pos.real"]
  raise "explicit power axiom lost its dependency"
isolated = Session.new(".")
isolated.quiet = true
isolated.no_cache = true
isolated.run_import("core")
isolated.run_source("+ no_hidden_power (a : ℝ) (n : ℕ) (h : 0 < a) : 0 < a^n := by auto\n")
if isolated.failures != 1 || isolated.theorems["pow_pos.real"] != nil || isolated.theorems["no_hidden_power"] != nil
  raise "auto imported power rules behind the caller's back"
<< "automatic real powers passed"

use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("order")
lemmas = ["pow_nonneg.int", "pow_pos.int", "one_le_pow.int", "pow_le_one.int", "pow_le_pow_left.int", "pow_le_pow_right.int", "pow_le_pow_of_le_one.int", "pow_lt_pow_left.int", "pow_lt_pow_right.int"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/power.sat", ["pow_add.int"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/auto_powers_int.sat").replace("import arith\n", ""))
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
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_powers_int_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid power bound: " + name
<< "automatic int powers passed"

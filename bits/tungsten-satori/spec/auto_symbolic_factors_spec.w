use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("order")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/nat.sat", ["min", "max"]))
lemmas = ["max_cases.rat", "le_max_left.rat", "le_max_right.rat", "max_le.rat", "mul_le_mul_left.nat", "mul_le_mul_right.nat", "mul_le_mul.nat", "pow_nonneg.real", "pow_le_pow_left.real", "pow_nonneg.rat", "pow_pos.rat", "one_le_pow.rat", "pow_le_pow_left.rat", "pow_le_pow_right.rat", "pow_lt_pow_left.rat", "pow_nonneg.int", "pow_le_pow_left.int", "pow_nonneg.nat", "pow_le_pow_left.nat"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/power.sat", ["pow_add.rat"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/auto_symbolic_factors.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "automatic symbolic factors failed"
examples = ["direct", "direct_strict", "lower", "upper", "strict_outer", "strict_inner", "right_factor", "negative_factor", "balanced_shift", "conjunction", "generic", "integer", "real_value", "natural", "natural_direct", "product_bound", "product_margin", "square_margin", "explicit_bound"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith"]
  if name == "natural" || name == "natural_direct" || name == "square_margin"
    expected = ["oracle:arith", "oracle:ring"]
  if name == "explicit_bound"
    expected = ["axiom:supplied_bound", "axiom:supplied_sign", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "symbolic factor missing, open or has unexpected trust: " + name
bad = ["zero_factor", "weak_factor", "unknown_factor", "negative_direction", "nonzero_factor", "weak_strict", "zero_exponent", "missing_base", "branch_leak", "wrong_function", "natural_zero", "wrong_product", "no_global_bound", "no_global_sign"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_symbolic_factors_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid symbolic factor: " + name
<< "automatic symbolic factors passed"

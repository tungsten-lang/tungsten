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
session.run_source(File.read("bits/tungsten-satori/spec/auto_normalized_chains.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "automatic normalized chains failed"
examples = ["balanced_shift", "variable_shift", "positive_scale", "negative_scale", "fraction_scale", "strict_bound", "strict_monotone", "upper", "strict_upper", "margin", "conjunction", "equality", "generic", "maximum", "natural", "integer", "real_value", "explicit_bound"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith"]
  if name == "explicit_bound"
    expected = ["axiom:supplied_bound", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "normalized chain missing, open or has unexpected trust: " + name
bad = ["weak_strict", "negative_direction", "zero_scale", "wrong_offset", "missing_guard", "zero_exponent", "wrong_upper", "unknown_scale", "branch_leak", "wrong_function", "natural_truncation", "cycle", "no_global_bound"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_normalized_chains_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid normalized chain: " + name
<< "automatic normalized chains passed"

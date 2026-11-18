use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/nat.sat", ["min", "max"]))
session.run_import("order")
lemmas = ["min_cases.int", "max_cases.int", "min_le_left.int", "min_le_right.int", "le_min.int", "lt_min.int", "le_min_iff.int", "min_eq_left.int", "min_eq_right.int", "min_comm.int", "min_self.int", "le_max_left.int", "le_max_right.int", "max_le.int", "max_lt.int", "max_le_iff.int", "max_eq_left.int", "max_eq_right.int", "max_comm.int", "max_self.int", "min_le_max.int", "min_add_max.int", "max_le_max.int", "min_le_min.int", "max_le_mul_max.int", "mul_min_le_min.int"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/auto_minmax_int.sat").replace("import arith\n", ""))
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
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_minmax_int_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid min/max bound: " + name
<< "automatic int min/max bounds passed"

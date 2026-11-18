use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/nat.sat", ["min", "max"]))
session.run_import("order")
lemmas = ["min_cases.rat", "max_cases.rat", "min_le_left.rat", "min_le_right.rat", "le_min.rat", "lt_min.rat", "le_min_iff.rat", "min_eq_left.rat", "min_eq_right.rat", "min_comm.rat", "min_self.rat", "le_max_left.rat", "le_max_right.rat", "max_le.rat", "max_lt.rat", "max_le_iff.rat", "max_eq_left.rat", "max_eq_right.rat", "max_comm.rat", "max_self.rat", "min_le_max.rat", "min_add_max.rat", "max_le_mul_max.rat", "mul_min_le_min.rat"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/auto_minmax_rat.sat").replace("import arith\n", ""))
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
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_minmax_rat_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid min/max bound: " + name
<< "automatic rat min/max bounds passed"

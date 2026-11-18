use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/nat.sat", ["min", "max"]))
session.run_import("order")
lemmas = ["min_cases.nat", "max_cases.nat", "min_le_left.nat", "min_le_right.nat", "le_min.nat", "lt_min.nat", "le_min_iff.nat", "min_eq_left.nat", "min_eq_right.nat", "min_comm.nat", "min_self.nat", "le_max_left.nat", "le_max_right.nat", "max_le.nat", "max_lt.nat", "max_le_iff.nat", "max_eq_left.nat", "max_eq_right.nat", "max_comm.nat", "max_self.nat", "min_le_max.nat", "min_add_max.nat", "max_le_max.nat", "min_le_min.nat", "max_le_mul_max.nat", "mul_min_le_min.nat"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/auto_minmax_nat.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "automatic min/max bounds failed"
examples = ["lower", "upper", "strict_lower", "strict_upper", "min_endpoint", "max_endpoint", "chosen_min", "chosen_max", "min_commute", "max_commute", "sum", "min_monotone", "max_monotone", "clamp", "upper_endpoints", "lower_endpoints", "sum_bound", "scaled_max", "scaled_min", "pointwise", "branch", "alias", "explicit_bound"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith"]
  if ["scaled_max", "scaled_min"].include?(name)
    expected = ["oracle:arith", "oracle:ring"]
  if name == "explicit_bound"
    expected = ["axiom:supplied_max", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "min/max proof missing, open or has unexpected trust: " + name
bad = ["missing_upper", "missing_lower", "weak_strict_upper", "weak_strict_lower", "wrong_min", "wrong_max", "wrong_endpoint", "missing_clamp_order", "branch_leak", "no_global_bound"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_minmax_nat_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid min/max bound: " + name
<< "automatic nat min/max bounds passed"

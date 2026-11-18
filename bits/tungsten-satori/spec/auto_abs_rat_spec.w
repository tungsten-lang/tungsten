use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
lemmas = ["abs_cases.rat", "abs_of_nonpos.rat", "le_abs_self.rat", "neg_le_abs.rat", "neg_abs_le.rat", "abs_le.rat", "abs_lt.rat", "abs_le_of.rat", "abs_lt_of.rat", "abs_neg.rat", "abs_sub_comm.rat", "abs_mul.rat", "abs_add.rat", "abs_sub.rat", "abs_sub_le.rat", "abs_sub_abs_le_abs_sub.rat", "abs_abs_sub_abs_le.rat", "abs_abs.rat", "abs_pos.rat", "abs_sq.rat", "sq_abs.rat", "sq_le_sq.rat", "sq_lt_sq.rat", "abs_le_of_sq_le_sq.rat"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/auto_abs_rat.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "absolute-value defaults failed"
examples = ["nonnegative", "positive", "nonnegative_value", "nonpositive_value", "interval", "strict_interval", "endpoints", "strict_endpoints", "weakened_endpoint", "triangle", "difference", "metric_triangle", "reverse_triangle", "product", "nested", "squared_bound", "strict_squared_order", "zero_bound", "pointwise", "explicit_bound"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith", "oracle:ring"]
  if name == "nonnegative" || name == "nonnegative_value" || name == "nested"
    expected = []
  if name == "explicit_bound"
    expected = ["axiom:known_abs", "oracle:arith", "oracle:ring"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "absolute-value proof missing, open or has unexpected trust: " + name
bad = ["missing_lower", "missing_upper", "weak_strict", "strict_endpoint", "wrong_endpoint", "negative_squared_bound", "wrong_value", "false_monotonicity", "branch_leak", "no_global_bound"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_abs_rat_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid absolute-value bound: " + name
<< "absolute-value rat defaults passed"

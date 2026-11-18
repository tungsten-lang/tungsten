use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
session.run_import("real")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["pow_two.real", "abs_cases.real", "abs_sq.real"]))
lemmas = ["sq_sqrt", "sqrt_eq_of_mul_self", "sqrt_sq", "sqrt_sq_eq_abs", "sqrt_pos", "sqrt_le_sqrt", "sqrt_lt_sqrt", "sqrt_mul", "sqrt_le_iff", "le_sqrt_iff", "sqrt_lt_iff", "lt_sqrt_iff"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/realx.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/auto_roots.sat").replace("import realx\n", ""))
if session.failures != 0
  raise "automatic root proofs failed"
examples = ["nonnegative", "positive", "order", "strict_order", "quadratic_order", "strict_upper", "strict_lower", "strict_upper_zero", "strict_lower_zero", "square_root", "root_square", "root_abs", "product", "root_value", "rate_square", "rate_bound", "nested_positive", "nested_order", "explicit_bound", "upper_squared", "lower_squared"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith"]
  if name == "nonnegative"
    expected = []
  if name == "square_root"
    expected = ["oracle:ring"]
  if ["root_square", "root_abs", "product", "rate_square"].include?(name)
    expected = ["oracle:arith", "oracle:ring"]
  if name == "explicit_bound"
    expected = ["axiom:supplied_bound", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "root proof missing, open or has unexpected trust: " + name
["sqrt_lt_iff", "lt_sqrt_iff"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "strict root equivalence has unexpected trust: " + name
bad = ["missing_domain", "weak_positive", "weak_strict_order", "missing_order", "missing_square_domain", "negative_root_square", "wrong_root_value", "missing_product_domain", "weak_upper", "negative_upper", "weak_lower", "reversed_lower", "no_global_bound", "strict_missing_domain"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_roots_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto escaped a root sign, domain or bound: " + name
# A familiar name must not grant a named axiom implicit use.
session.run_source("axiom sqrt_le_sqrt (x y : ℝ) (h : x ≤ y) : sqrt x ≤ sqrt y\n")
previous = session.failures
session.run_source("+ poisoned_root (x y : ℝ) (h : x ≤ y) : sqrt x ≤ sqrt y := by auto\n")
if session.failures != previous + 1 || session.theorems["poisoned_root"] != nil
  raise "auto silently selected a named root axiom"
session.run_source("+ explicit_poison (x y : ℝ) (h : x ≤ y) : sqrt x ≤ sqrt y := by auto \[sqrt_le_sqrt]\n")
th = session.theorems["explicit_poison"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:sqrt_le_sqrt"]
  raise "explicit root axiom lost its trust tag"
isolated = Session.new(".")
isolated.quiet = true
isolated.no_cache = true
isolated.run_import("core")
isolated.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
isolated.run_import("real")
isolated.run_source("+ no_hidden_order (x y : ℝ) (hx : 0 ≤ x) (h : x ≤ y) : sqrt x ≤ sqrt y := by auto\n")
if isolated.failures != 1 || isolated.theorems["sqrt_le_sqrt"] != nil || isolated.theorems["no_hidden_order"] != nil
  raise "auto imported root lemmas behind the caller's back"
<< "automatic root proofs passed"

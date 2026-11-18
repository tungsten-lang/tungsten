use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
session.run_import("real")
lemmas = ["exp_nonneg", "one_lt_exp", "exp_lt_exp_of_lt", "exp_lt_exp", "exp_le_exp", "log_one", "log_lt_log", "log_le_log", "log_le_sub_one", "log_nonneg", "log_pos", "log_neg", "exp_le_one_iff", "exp_lt_one", "one_le_exp_iff"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/realx.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/auto_log_exp.sat").replace("import realx\n", ""))
if session.failures != 0
  raise "automatic logarithmic/exponential order failed"
examples = ["logarithm", "logarithm_strict", "logarithm_affine", "logarithm_quadratic", "logarithm_nonnegative", "logarithm_positive", "logarithm_negative", "logarithm_tangent", "exponential", "exponential_strict", "exponential_positive", "exponential_nonnegative", "exponential_upper", "exponential_upper_strict", "exponential_lower", "exponential_lower_strict", "exponential_tangent", "decay_order", "nested_order", "nested_strict", "explicit_order"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith", "oracle:ring"]
  if ["logarithm_tangent", "exponential_nonnegative", "exponential_lower_strict"].include?(name)
    expected = ["oracle:arith"]
  if ["exponential_positive", "exponential_tangent"].include?(name)
    expected = []
  if name == "explicit_order"
    expected = ["axiom:supplied_order", "oracle:arith", "oracle:ring"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "order proof missing, open or has unexpected trust: " + name
bad = ["missing_log_domain", "zero_log_domain", "missing_log_order", "reversed_log_order", "weak_strict_log", "missing_log_sign", "missing_exp_order", "weak_strict_exp", "wrong_decay_sign", "weak_unit_exp", "weak_log_negative", "wrong_exp_lower"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_log_exp_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid analysis bound: " + name
# Default order rules must remove the named function, not introduce it into
# arbitrary arithmetic. Explicit hints still expose both iff directions.
session.run_source("+ unwrapped (x y : ℝ) (h : x ≤ y) : x ≤ y := by auto\n")
prover = Prover.new(session)
goal = Goal.new([], [], session.theorems["unwrapped"].concl)
if prover.auto_default_hints(goal).size != 0
  raise "analytic defaults selected for an unwrapped arithmetic goal"
session.run_source("+ inverse_order (x y : ℝ) (h : exp x ≤ exp y) : x ≤ y := by auto \[exp_le_exp]\n")
if session.theorems["inverse_order"] == nil
  raise "explicit inverse-order hint no longer works"
# A familiar theorem name does not authorize a new named axiom.
session.run_source("axiom log_le_log (x y : ℝ) (h : x ≤ y) : log x ≤ log y\n")
previous = session.failures
session.run_source("+ poisoned_order (x y : ℝ) (h : x ≤ y) : log x ≤ log y := by auto\n")
if session.failures != previous + 1 || session.theorems["poisoned_order"] != nil
  raise "auto silently selected a named order axiom"
session.run_source("+ explicit_poison (x y : ℝ) (h : x ≤ y) : log x ≤ log y := by auto \[log_le_log]\n")
th = session.theorems["explicit_poison"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:log_le_log"]
  raise "explicit order axiom lost its trust tag"
isolated = Session.new(".")
isolated.quiet = true
isolated.no_cache = true
isolated.run_import("core")
isolated.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
isolated.run_import("real")
isolated.run_source("+ no_hidden_order (x y : ℝ) (hx : 0 < x) (h : x ≤ y) : log x ≤ log y := by auto\n")
if isolated.failures != 1 || isolated.theorems["log_le_log"] != nil || isolated.theorems["no_hidden_order"] != nil
  raise "auto imported realx behind the caller's back"
<< "automatic logarithmic/exponential order passed"

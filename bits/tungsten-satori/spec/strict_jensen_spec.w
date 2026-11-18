use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
session.run_import("real")
exp_rules = ["exp_tangent_le", "exp_weighted_jensen", "exp_midpoint_le", "one_add_lt_exp", "exp_tangent_lt", "exp_weighted_jensen_lt", "exp_midpoint_lt"]
log_rules = ["log_tangent_le", "log_tangent_lt", "log_weighted_jensen", "log_weighted_jensen_lt", "log_midpoint_le", "log_midpoint_lt"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/exp_convex.sat", exp_rules))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/log_convex.sat", log_rules))
examples = ["exp_lower", "exp_negative", "exp_support", "exp_weighted", "exp_middle", "exp_zero_weights", "log_support", "log_support_strict", "log_weighted", "log_weighted_strict", "log_middle", "log_middle_strict", "log_equal", "log_zero_weights", "log_one_zero_weight", "log_scaled"]
session.run_source(proof_declarations("bits/tungsten-satori/spec/strict_jensen.sat", examples))
if session.failures != 0
  raise "Strict exponential/logarithmic Jensen proofs failed"
(exp_rules + log_rules + examples).each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
    raise "Jensen theorem missing, open or has unexpected trust: " + name
bad = ["exp_at_zero", "exp_equal", "exp_zero_weight", "exp_equal_middle", "exp_missing_mean", "exp_reverse", "log_missing_left", "log_missing_right", "log_zero_center", "log_zero_left_weight", "log_zero_right_weight", "log_equal_middle", "log_missing_mean", "log_weak_to_strict", "log_equal_support", "log_reverse"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/strict_jensen_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "Strict Jensen accepted an invalid sign, mean, equality or direction: " + name
session.run_source("axiom false_log_mean (x y z a b : ℝ) : (a+b)*z = a*x+b*y\n+ marked_log_mean (x y z a b : ℝ) (hx : 0 < x) (hy : 0 < y) (ha : 0 < a) (hb : 0 < b) (hne : x ≠ y) : a*log x+b*log y < (a+b)*log z := log_weighted_jensen_lt x y z a b hx hy ha hb hne (false_log_mean x y z a b)\n")
th = session.theorems["marked_log_mean"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_log_mean", "oracle:arith", "oracle:ring"]
  raise "Logarithmic Jensen lost its mean assumption tag"
<< "Strict exponential/logarithmic Jensen passed"

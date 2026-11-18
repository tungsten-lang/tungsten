use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
session.run_import("real")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below_zero", "sum_below_succ", "cast_add.int", "int_cast_add.real", "cast_add.real", "cast_zero.real", "cast_one.real", "cast_succ.real", "sum_const.real", "sum_const_mul.real", "sum_add.real", "sum_sub.real", "sum_le.real"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/convex.sat", ["convex_interval.real"]))
lemmas = ["exp_tangent_le", "exp_weighted_jensen", "exp_midpoint_le"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/exp_convex.sat", lemmas))
other = ["convex_interval.exp.real", "sum_below.exp_jensen.real"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/convex_real.sat", other))
examples = ["tangent", "weighted_exp", "midpoint", "finite_exp", "exp_interval", "zero_weights", "zero_count", "single_exp"]
session.run_source(proof_declarations("bits/tungsten-satori/spec/convex_instances.sat", examples))
if session.failures != 0
  raise "exponential convexity proofs failed"
(lemmas + other + examples).each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
    raise "exponential convexity theorem missing, open or has unexpected trust: " + name
["tangent_upper", "strict_midpoint", "missing_exp_sign", "missing_exp_mean", "wrong_finite_mean", "strict_zero_count"].each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/convex_instances_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "exponential convexity accepted an invalid mean, sign or strict bound: " + name
session.run_source("axiom false_exp_mean (n : ℕ) (p : ℕ → ℝ) (m : ℝ) : (n : ℝ)*m = ∑ i < n, p i\n+ marked_exp_mean (n : ℕ) (p : ℕ → ℝ) (m : ℝ) : (n : ℝ)*exp m ≤ ∑ i < n, exp (p i) := sum_below.exp_jensen.real n p m (false_exp_mean n p m)\n")
th = session.theorems["marked_exp_mean"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_exp_mean", "oracle:arith", "oracle:ring"]
  raise "exponential convexity lost its mean assumption tag"
<< "Exponential convexity passed"

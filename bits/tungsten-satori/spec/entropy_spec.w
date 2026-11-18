use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
session.run_import("real")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["one_div_pos.real", "eq_one_div_of_mul_eq_one.real", "sum_below_zero", "sum_below_succ", "cast_add.int", "int_cast_add.real", "cast_add.real", "cast_zero.real", "cast_one.real", "cast_succ.real", "sum_const.real", "sum_mul_const.real", "sum_add.real", "sum_le.real"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/realx.sat", ["exp_neg_mul", "exp_neg", "exp_sub", "one_lt_exp", "exp_lt_exp_of_lt", "exp_le_exp", "log_one", "log_mul", "log_div", "log_le_log"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/exp_convex.sat", ["exp_tangent_le", "one_add_lt_exp", "exp_tangent_lt"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/log_convex.sat", ["log_tangent_le", "log_tangent_lt"]))
lemmas = ["mul_log_tangent_le", "mul_log_tangent_lt", "sub_one_le_mul_log", "neg_mul_log_le_scale", "neg_mul_log_le_of_le", "sum_below.entropy_le_log.real"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/entropy.sat", lemmas))
examples = ["tangent", "strict_tangent", "zero_tangent", "equal_tangent", "gibbs", "zero_gibbs", "scaled", "zero_scaled", "heavy", "equal_heavy", "finite_entropy", "uniform_binary", "point_mass"]
session.run_source(proof_declarations("bits/tungsten-satori/spec/entropy.sat", examples))
if session.failures != 0
  raise "Entropy proofs failed"
(lemmas + examples).each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
    raise "Entropy theorem missing, open or has unexpected trust: " + name
bad = ["missing_center", "missing_mass_sign", "equal_strict", "weak_to_strict", "negative_gibbs", "zero_scale", "negative_scale", "wrong_heavy_order", "zero_threshold", "missing_total", "missing_atom_signs", "strict_finite"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/entropy_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "Entropy accepted an invalid sign, normalization or strictness: " + name
session.run_source("axiom false_entropy_mass (n : ℕ) (p : ℕ → ℝ) : sum_below n p = 1\n+ marked_entropy (n : ℕ) (p : ℕ → ℝ) (hn : 0 < (n : ℝ)) (hp : ∀ i < n, 0 ≤ p i) : sum_below n (fun i => 0-p i*log (p i)) ≤ log (n : ℝ) := sum_below.entropy_le_log.real n p hn hp (false_entropy_mass n p)\n")
th = session.theorems["marked_entropy"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_entropy_mass", "oracle:arith", "oracle:ring"]
  raise "Entropy lost its total-mass assumption tag"
<< "Entropy bounds passed"

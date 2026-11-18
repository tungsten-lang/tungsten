use ../lib/satori
use proof_source

-> check_euclidean(mode)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_list", "sum_below", "mem_nil", "mem_cons"]))
  session.run_import("real")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below_zero", "sum_below_succ", "sum_nonneg.real", "pow_two.real", "abs_cases.real", "abs_sq.real", "le_abs_self.real"]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list_sum.sat", ["list_sum.nil", "list_sum.cons", "list_sum.closed", "sum_list_nonneg.real"]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/realx.sat", ["sq_sqrt", "sqrt_eq_of_mul_self", "sqrt_sq_eq_abs", "sqrt_le_sqrt", "sqrt_mul", "sqrt_le_iff", "abs_le_sqrt_mul"]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/quadratic.sat", ["quadratic_form.bound.real"]))
  prefix = mode == "list" ? "list_sum" : "sum_below"
  prerequisites = ["weighted_square_expand", "weighted_cauchy", "cauchy"].map -> (name) prefix + "." + name + ".real"
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/cauchy.sat", prerequisites))
  lemmas = ["weighted_cauchy_sqrt", "cauchy_sqrt", "weighted_add_square_expand", "weighted_minkowski", "minkowski"].map -> (name) prefix + "." + name + ".real"
  examples = ["cauchy", "triangle", "unweighted", "unweighted_cauchy", "zero_weights"].map -> (name) mode + "_" + name
  bad = ["missing_cauchy_sign", "missing_triangle_sign", "strict_triangle", "strict_cauchy", "wrong_vector"].map -> (name) mode + "_" + name
  if mode == "list"
    lemmas = lemmas + ["norm2.add_le", "norm2.sub_le"]
    examples = examples + ["planar_triangle", "planar_reverse", "empty_triangle", "repeated_triangle", "scalar_bound"]
    bad = bad + ["scalar_missing_signs", "planar_wrong_direction"]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/euclidean.sat", lemmas))
  session.run_source(proof_declarations("bits/tungsten-satori/spec/euclidean.sat", examples))
  if session.failures != 0
    raise "Euclidean proofs failed: " + mode
  (lemmas + examples + ["abs_le_sqrt_mul"]).each -> (name)
    th = session.theorems[name]
    expected = name == prefix + ".weighted_add_square_expand.real" ? ["oracle:ring"] : ["oracle:arith", "oracle:ring"]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "Euclidean theorem missing, open or has unexpected trust: " + name
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/euclidean_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "Euclidean accepted an invalid sign, vector or strict bound: " + name
  if mode == "range"
    session.run_source("axiom false_norm_weight (n : ℕ) (w : ℕ → ℝ) : ∀ i < n, 0 ≤ w i\n+ marked_norm (n : ℕ) (w f g : ℕ → ℝ) : sqrt (sum_below n (fun i => w i*((f i+g i)*(f i+g i)))) ≤ sqrt (sum_below n (fun i => w i*(f i*f i))) + sqrt (sum_below n (fun i => w i*(g i*g i))) := sum_below.weighted_minkowski.real n w f g (false_norm_weight n w)\n")
    th = session.theorems["marked_norm"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_norm_weight", "oracle:arith", "oracle:ring"]
      raise "Euclidean lost its weight assumption tag"
  << "Euclidean passed: " + mode

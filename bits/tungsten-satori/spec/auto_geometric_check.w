use ../lib/satori
use proof_source

-> check_auto_geometric(mode)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_list", "sum_below", "mem_nil", "mem_cons"]))
  session.run_import("real")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below_zero", "sum_below_succ", "sum_nonneg.real", "pow_two.real", "abs_cases.real", "abs_sq.real", "le_abs_self.real"]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list_sum.sat", ["list_sum.nil", "list_sum.cons", "list_sum.congr", "list_sum.closed", "sum_list_nonneg.real"]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/realx.sat", ["sq_sqrt", "sqrt_eq_of_mul_self", "sqrt_sq_eq_abs", "sqrt_le_sqrt", "sqrt_mul", "sqrt_le_iff", "abs_le_sqrt_mul"]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/quadratic.sat", ["quadratic_form.bound.real"]))
  prefix = mode == "list" ? "list_sum" : "sum_below"
  prerequisites = ["weighted_square_expand", "weighted_cauchy", "cauchy"].map -> (name) prefix + "." + name + ".real"
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/cauchy.sat", prerequisites))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below.congr"]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/euclidean.sat", [prefix + ".weighted_cauchy_sqrt.real"]))
  lemmas = [prefix + ".weighted_sqrt_mul_le.real", prefix + ".sqrt_mul_le.real"]
  examples = ["weighted", "unweighted", "zero_weights", "zero_values"].map -> (name) mode + "_" + name
  bad = ["missing_w", "missing_f", "missing_g", "strict", "reverse", "wrong_vector"].map -> (name) mode + "_" + name
  if mode == "list"
    lemmas = lemmas + ["sqrt_mul.weighted_add_le", "sqrt_mul.add_le"]
    examples = examples + ["scalar_weighted", "scalar_unweighted", "list_repeated"]
    bad = bad + ["scalar_missing_sign", "scalar_strict_equality"]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/geometric_mean.sat", lemmas))
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_geometric.sat", examples))
  if session.failures != 0
    raise "Automatic geometric-mean proofs failed: " + mode
  (lemmas + examples).each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
      raise "Automatic geometric-mean theorem missing, open or has unexpected trust: " + name
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_geometric_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "Automatic geometric mean accepted an invalid sign, vector or strict bound: " + name
  if mode == "range"
    session.run_source("axiom false_geometric_sign (n : ℕ) (f : ℕ → ℝ) : ∀ i < n, 0 ≤ f i\n+ marked_geometric (n : ℕ) (f g : ℕ → ℝ) (hg : ∀ i < n, 0 ≤ g i) : sum_below n (fun i => sqrt (f i*g i)) ≤ sqrt ((sum_below n f)*(sum_below n g)) \n  have hf := false_geometric_sign n f\n  auto\n")
    th = session.theorems["marked_geometric"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_geometric_sign", "oracle:arith", "oracle:ring"]
      raise "Automatic geometric mean lost its sign assumption tag"
  << "Automatic geometric mean passed: " + mode

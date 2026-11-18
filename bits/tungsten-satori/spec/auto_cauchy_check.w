use ../lib/satori
use proof_source

-> check_auto_cauchy(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_list", "sum_below", "mem_nil", "mem_cons"]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below_zero", "sum_below_succ", "sum_nonneg." + suffix]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list_sum.sat", ["list_sum.nil", "list_sum.cons", "list_sum.closed", "sum_list_nonneg." + suffix]))
  form = "quadratic_form.bound." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/quadratic.sat", [form]))
  lemmas = []
  ["list_sum", "sum_below"].each -> (prefix)
    ["weighted_square_expand", "weighted_cauchy", "cauchy"].each -> (name) lemmas.push(prefix + "." + name + "." + suffix)
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/cauchy.sat", lemmas))
  examples = ["list_weighted", "list", "range_weighted", "range", "empty", "repeated", "zero_weights"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_cauchy.sat", examples))
  if session.failures != 0
    raise "Cauchy proofs failed: " + suffix
  (lemmas + examples + [form]).each -> (name)
    expected = ["oracle:arith", "oracle:ring"]
    if name == form
      expected = ["oracle:arith"]
    if name == "list_sum.weighted_square_expand." + suffix || name == "sum_below.weighted_square_expand." + suffix
      expected = ["oracle:ring"]
    if name == suffix + "_empty"
      expected = []
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "Cauchy theorem missing, open or has unexpected trust: " + name
  bad = ["missing_list_sign", "missing_range_sign", "strict_list", "strict_range", "weak_form", "wrong_diagonal"]
  bad.each -> (base)
    name = suffix + "_" + base
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_cauchy_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "Cauchy accepted an invalid sign, form or bound: " + name
  if suffix == "rat"
    session.run_source("axiom false_cauchy_weight (n : ℕ) (w : ℕ → ℚ) : ∀ i < n, 0 ≤ w i\n+ marked_cauchy (n : ℕ) (w f g : ℕ → ℚ) : (sum_below n (fun i => w i*(f i*g i)))^2 ≤ (sum_below n (fun i => w i*(f i*f i)))*(sum_below n (fun i => w i*(g i*g i))) \n  have hw := false_cauchy_weight n w\n  auto\n")
    th = session.theorems["marked_cauchy"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_cauchy_weight", "oracle:arith", "oracle:ring"]
      raise "Cauchy lost its weight assumption tag"
  << "Cauchy passed: " + suffix

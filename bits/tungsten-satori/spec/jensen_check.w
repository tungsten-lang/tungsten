use ../lib/satori
use proof_source

-> check_jensen(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  arithmetic = ["sum_below_zero", "sum_below_succ", "cast_add.int", "int_cast_zero.rat", "int_cast_nonneg.rat", "int_cast_add." + suffix, "int_cast_nonneg." + suffix, "cast_zero." + suffix, "cast_one." + suffix, "cast_add." + suffix, "cast_succ." + suffix, "cast_nonneg." + suffix, "mul_div_cancel." + suffix, "sum_const_mul." + suffix]
  if suffix == "real"
    arithmetic = arithmetic + ["rat_cast_zero.real", "rat_cast_nonneg.real"]
  else
    arithmetic = ["sum_below_zero", "sum_below_succ", "cast_add.int", "int_cast_zero.rat", "int_cast_nonneg.rat", "int_cast_add.rat", "cast_zero.rat", "cast_one.rat", "cast_add.rat", "cast_succ.rat", "cast_nonneg.rat", "mul_div_cancel.rat", "sum_const_mul.rat"]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", arithmetic))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below.le_const." + suffix, "sum_below.const_le." + suffix]))
  lemmas = ["concave_interval.sub_convex", "sum_below.concave_jensen_succ", "sum_below.concave_jensen", "sum_below.convex_jensen", "concave_interval.mono_below_max"].map -> (name) name + "." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/convex.sat", ["concave_interval." + suffix, "convex_interval." + suffix] + lemmas))
  examples = ["jensen", "convex", "succ", "sub", "empty", "shifted", "monotone", "constant"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/jensen.sat", examples))
  if session.failures != 0
    raise "Jensen proofs failed: " + suffix
  (lemmas + examples).each -> (name)
    th = session.theorems[name]
    expected = ["oracle:arith", "oracle:ring"]
    if name == "concave_interval.sub_convex." + suffix || name == suffix + "_sub" || name == suffix + "_constant"
      expected = ["oracle:arith"]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "Jensen theorem missing, open or has unexpected trust: " + name
  bad = ["strict", "wrong_mean", "missing_domain", "wrong_direction", "wrong_difference", "strict_monotone", "past_peak", "missing_max"]
  bad.each -> (base)
    name = suffix + "_" + base
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/jensen_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "Jensen accepted an invalid mean, domain or maximizer: " + name
  if suffix == "rat"
    session.run_source("axiom false_concavity (f : ℚ → ℚ) : concave_interval.rat 0 1 f\n+ marked_jensen (f : ℚ → ℚ) (n : ℕ) (p : ℕ → ℚ) (m : ℚ) (hp : ∀ j < n, 0 ≤ p j ∧ p j ≤ 1) (hm : (n : ℚ)*m = (∑ j < n, p j)) : (∑ j < n, f (p j)) ≤ (n : ℚ)*f m := sum_below.concave_jensen.rat 0 1 f (false_concavity f) n p m hp hm\n")
    th = session.theorems["marked_jensen"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_concavity", "oracle:arith", "oracle:ring"]
      raise "Jensen lost its concavity assumption tag"
  << "Jensen passed: " + suffix

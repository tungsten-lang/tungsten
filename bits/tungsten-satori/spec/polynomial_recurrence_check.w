use ../lib/satori
use proof_source

-> check_polynomial_recurrence(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  if suffix != "nat"
    casts = ["cast_add.int"]
    if suffix != "int"
      casts = casts + ["int_cast_add." + suffix, "cast_add." + suffix]
    casts = casts + ["cast_zero." + suffix, "cast_one." + suffix, "cast_succ." + suffix]
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", casts))
  lemmas = ["linear_eq", "quadratic", "cubic"].map -> (name) "recurrence." + name + "." + suffix
  if suffix == "nat"
    lemmas.push("recurrence.count")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/recurrence.sat", lemmas))
  defs = ["line", "curve", "cube", "flat"].map -> (name) name + "." + suffix
  examples = ["linear", "quadratic", "cubic", "constant", "values"].map -> (name) suffix + "_" + name
  bad = ["missing_base", "wrong_linear", "wrong_quadratic", "wrong_cubic"].map -> (name) suffix + "_" + name
  if suffix == "int"
    defs = defs + ["sj", "sj2"]
    examples = examples + ["sj_closed", "sj2_closed"]
  elsif suffix == "nat"
    defs = defs + ["plen", "cr", "kr", "cexp", "kexp"]
    examples = examples + ["plen_closed", "cr_closed", "kr_closed", "cexp_closed", "kexp_closed"]
    bad = bad + ["counter_wrong_base", "counter_wrong_step"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/polynomial_recurrence.sat", defs))
  session.run_source(proof_declarations("bits/tungsten-satori/spec/polynomial_recurrence.sat", examples))
  if session.failures != 0
    raise "polynomial recurrence proofs failed for " + suffix
  (lemmas + examples).each -> (name)
    expected = ["oracle:ring"]
    if name == "recurrence.count" || name.ends_with?("_values") || name == "cr_closed" || name == "cexp_closed"
      expected = []
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "polynomial recurrence theorem is missing, open or has unexpected trust: " + name
  if suffix == "real"
    session.run_source("axiom false_polynomial_base : (1 : ℝ) = 0\n+ marked_polynomial : (1 : ℝ) = 0 := recurrence.linear_eq.real (fun i => (1 : ℝ)) 0 0 false_polynomial_base (by intro i; decide) 2\n")
    th = session.theorems["marked_polynomial"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_polynomial_base", "oracle:ring"]
      raise "polynomial recurrence lost its base assumption tag"
  elsif suffix == "nat"
    session.run_source("axiom false_counter_base : (1 : ℕ) = 0\n+ marked_counter : (2 : ℕ) = 1 := recurrence.count (fun i => i + 1) false_counter_base (by intro i; rfl) 1\n")
    th = session.theorems["marked_counter"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_counter_base"]
      raise "counter recognition lost its base assumption tag"
  session.run_source(proof_declarations("bits/tungsten-satori/spec/polynomial_recurrence_failure.sat", bad))
  if session.failures != bad.size
    raise "polynomial recurrence accepted an invalid base or increment"
  << "Polynomial recurrences passed: " + suffix

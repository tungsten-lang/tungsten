use ../lib/satori
use proof_source

-> check_auto_polynomial_recurrence(suffix)
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
  if suffix == "nat"
    examples = examples + ["nat_symbolic", "nat_reverse", "nat_power", "nat_quantified"]
    bad = bad + ["nat_missing_step", "nat_wrong_index", "nat_point_step", "nat_wrong_base", "nat_wrong_power", "nat_truncated"]
  if suffix == "int"
    examples = examples + ["int_symbolic", "int_reverse", "int_power", "int_quantified"]
    bad = bad + ["int_missing_step", "int_wrong_index", "int_point_step", "int_wrong_base", "int_wrong_power"]
  if suffix == "rat"
    examples = examples + ["rat_symbolic", "rat_reverse", "rat_power", "rat_quantified", "rat_half"]
    bad = bad + ["rat_missing_step", "rat_wrong_index", "rat_point_step", "rat_wrong_base", "rat_wrong_power"]
  if suffix == "real"
    examples = examples + ["real_symbolic", "real_reverse", "real_power", "real_quantified", "real_half"]
    bad = bad + ["real_missing_step", "real_wrong_index", "real_point_step", "real_wrong_base", "real_wrong_power"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_polynomial_recurrence.sat", defs))
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_polynomial_recurrence.sat", examples))
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
  if suffix == "rat"
    session.run_source("opaque marked_curve : ℕ → ℚ\naxiom marked_base : marked_curve 0 = 7\naxiom marked_step : ∀ i, marked_curve (i+1) = marked_curve i+2*(i : ℚ)+4\n")
    previous = session.failures
    session.run_source("+ unsupplied (n : ℕ) : marked_curve n = (n : ℚ)^2+3*(n : ℚ)+7 := by auto\n")
    if session.failures != previous + 1 || session.theorems["unsupplied"] != nil
      raise "polynomial automation used an unsupplied axiom"
    session.run_source("+ marked (n : ℕ) : marked_curve n = (n : ℚ)^2+3*(n : ℚ)+7 := by auto \[marked_base, marked_step]\n+ local_marked (n : ℕ) : marked_curve n = (n : ℚ)^2+3*(n : ℚ)+7\n  have base := marked_base\n  have step := marked_step\n  auto\n")
    ["marked", "local_marked"].each -> (name)
      th = session.theorems[name]
      if th == nil || th.hyps.size != 0 || th.tags != ["axiom:marked_base", "axiom:marked_step", "oracle:ring"]
        raise "polynomial automation lost supplied assumption tags"
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_polynomial_recurrence_failure.sat", bad))
  if session.failures != bad.size + (suffix == "rat" ? 1 : 0)
    raise "polynomial recurrence accepted an invalid base or increment"
  << "Automatic polynomial recurrences passed: " + suffix

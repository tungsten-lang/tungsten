use ../lib/satori
use proof_source

-> check_progression(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  prerequisites = ["sum_below_zero", "sum_below_succ"]
  if suffix != "nat"
    prerequisites.push("cast_add.int")
    if suffix != "int"
      prerequisites = prerequisites + ["int_cast_add." + suffix, "cast_add." + suffix, "pow_two." + suffix]
    prerequisites = prerequisites + ["cast_zero." + suffix, "cast_one." + suffix, "cast_succ." + suffix]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", prerequisites))
  lemmas = ["sum_below.arithmetic.", "sum_below.arithmetic_squares.", "recurrence.arithmetic_shift.", "recurrence.square_shift."].map -> (name) name + suffix
  if suffix == "real" || suffix == "rat"
    lemmas = lemmas + ["sum_below.index." + suffix, "sum_below.index_squares." + suffix]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/progression.sat", lemmas))
  defs = ["shift_linear." + suffix, "shift_square." + suffix]
  examples = ["direct_linear", "direct_square", "shift_linear", "shift_square", "constant", "empty_shift", "values"].map -> (name) suffix + "_" + name
  if suffix == "real"
    examples.push("real_index_sums")
  elsif suffix == "rat"
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/recurrence.sat", ["recurrence.linear_eq.rat"]))
    defs = defs + ["ssum", "nq", "csum", "c2sum", "cnt"]
    examples = examples + ["nq_eq", "sum_id", "sum_sq", "cnt_eq", "csum_closed", "c2sum_closed"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/progression.sat", defs))
  session.run_source(proof_declarations("bits/tungsten-satori/spec/progression.sat", examples))
  if session.failures != 0
    raise "progression proofs failed for " + suffix
  (lemmas + examples).each -> (name)
    expected = name.ends_with?("_values") ? [] : ["oracle:ring"]
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "progression theorem is missing, open or has unexpected trust: " + name
  if suffix == "real"
    session.run_source("axiom false_progression_base : (1 : ℝ) = 0\n+ marked_progression_base : (1 : ℝ) = 0 := recurrence.arithmetic_shift.real (fun n a => shift_linear.real 0 n a + 1) 0 (by intro a; exact false_progression_base) (by intro i a; unfold shift_linear.real; ring) 0 0\n")
    th = session.theorems["marked_progression_base"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_progression_base", "oracle:ring"]
      raise "progression lost its initial assumption tag"
    session.run_source("axiom false_progression_step : ∀ (i : ℕ) (a : ℝ), (0 : ℝ) = a + 0\n+ marked_progression_step : (0 : ℝ) = 1 := recurrence.arithmetic_shift.real (fun n a => (0 : ℝ)) 0 (by intro a; rfl) false_progression_step 1 1\n")
    th = session.theorems["marked_progression_step"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_progression_step", "oracle:ring"]
      raise "progression lost its step assumption tag"
  bad = ["wrong_length", "wrong_shift", "missing_base", "wrong_base", "wrong_square", "local_step"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/progression_failure.sat", bad))
  if session.failures != bad.size
    raise "progression accepted an invalid length, base, summand or shift"
  << "Progressions passed: " + suffix

use ../lib/satori
use proof_source

-> check_recurrence(suffix)
  cases = {
    "real" => [["real_drift", "real_negative_bound", "real_geometric_lower", "faa_recurrence", "real_equal_rates"], ["real_negative_rate", "real_reversed_gap", "real_missing_initial"]],
    "rat" => [["rational_zero_rate", "rational_negative_drift", "rational_signed_forcing", "rational_unit_rate", "rational_zero_forcing"], ["rational_positive_initial", "rational_missing_step", "rational_wrong_multiplier"]],
    "int" => [["integer_oscillation", "integer_falling", "integer_lower_zero", "integer_forcing"], ["integer_inequality_is_equality", "integer_negative_rate", "integer_reversed_step"]],
    "nat" => [["natural_exact", "natural_drift", "natural_geometric", "natural_zero_rate"], ["natural_reversed_step", "natural_wrong_exponent", "natural_missing_initial"]]
  }
  family = cases[suffix]
  lemmas = ["linear_lower", "linear_upper", "geometric_eq", "geometric_upper", "geometric_lower"].map -> (name) "recurrence." + name + "." + suffix
  if suffix != "nat"
    lemmas.push("recurrence.geometric_forcing." + suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  if suffix != "nat"
    casts = ["cast_add.int"]
    if suffix == "rat" || suffix == "real"
      casts = casts + ["int_cast_add." + suffix, "cast_add." + suffix]
    casts = casts + ["cast_one." + suffix, "cast_succ." + suffix]
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", casts))
  else
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["mul_le_mul_left.nat"]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["mul_le_mul_of_nonneg_left." + suffix]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/recurrence.sat", lemmas))
  if suffix == "int"
    session.run_source(proof_declarations("bits/tungsten-satori/spec/recurrence.sat", ["oscillating"]))
  elsif suffix == "nat"
    session.run_source(proof_declarations("bits/tungsten-satori/spec/recurrence.sat", ["triple_steps"]))
  session.run_source(proof_declarations("bits/tungsten-satori/spec/recurrence.sat", family[0]))
  if session.failures != 0
    raise "recurrence proofs failed for " + suffix
  (lemmas + family[0]).each -> (name)
    expected = ["oracle:arith"]
    if name.starts_with?("recurrence.geometric_eq.") || name == "integer_oscillation" || name == "natural_exact"
      expected = ["oracle:ring"]
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "recurrence theorem is missing, open or has unexpected trust: " + name
  if suffix == "real"
    session.run_source("axiom false_initial : (1 : ℝ) ≤ 0\n+ marked_geometric : (1 : ℝ) ≤ 0 := recurrence.geometric_upper.real (fun n => (1 : ℝ)) 1 0 (by decide) false_initial (by intro i; decide) 2\n")
    th = session.theorems["marked_geometric"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_initial", "oracle:arith"]
      raise "recurrence comparison lost its assumption tag"
  session.run_source(proof_declarations("bits/tungsten-satori/spec/recurrence_failure.sat", family[1]))
  if session.failures != family[1].size
    raise "recurrence rules accepted an invalid rate or missing premise"
  << "Recurrence patterns passed: " + suffix

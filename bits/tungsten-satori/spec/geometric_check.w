use ../lib/satori
use proof_source

-> check_geometric(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  casts = ["cast_add.int"]
  if suffix != "int"
    casts = casts + ["int_cast_add." + suffix, "cast_add." + suffix]
  casts = casts + ["cast_one." + suffix, "cast_succ." + suffix]
  prerequisites = ["sum_below_zero", "sum_below_succ"] + casts
  ["mul_le_mul_of_nonneg_left", "pow_nonneg", "sum_add", "sum_le", "geom_sum_mul"].each -> (name)
    prerequisites.push(name + "." + suffix)
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/power.sat", ["mul_pow." + suffix]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", prerequisites))
  lemmas = ["geometric_step", "arithmetic_geometric", "geometric_bound", "geometric_bound_add", "weighted_geometric_bound"].map -> (name) "sum_below." + name + "." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/geometric.sat", lemmas))
  examples = ["zero_rate", "unit_rate", "signed_weights", "empty_bound", "zero_weight"].map -> (name) suffix + "_" + name
  if suffix == "real"
    session.run_source(proof_declarations("bits/tungsten-satori/spec/geometric.sat", ["iterm"]))
    examples.push("geom_step")
  elsif suffix == "rat"
    session.run_source(proof_declarations("bits/tungsten-satori/spec/geometric.sat", ["quarter", "weighted"]))
    examples = examples + ["mass_closed", "entropy_closed"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/geometric.sat", examples))
  if session.failures != 0
    raise "geometric proofs failed for " + suffix
  (lemmas + examples).each -> (name)
    expected = ["oracle:arith", "oracle:ring"]
    if name.starts_with?("sum_below.geometric_step.") || name.ends_with?("_zero_rate")
      expected = ["oracle:ring"]
    elsif name.starts_with?("sum_below.arithmetic_geometric.") || name.ends_with?("_unit_rate") || name == "mass_closed" || name == "entropy_closed"
      expected = ["oracle:arith"]
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "geometric theorem is missing, open or has unexpected trust: " + name
  if suffix == "real"
    session.run_source("axiom false_sum_bound : (1 : ℝ) ≤ 0\n+ marked_geometric_sum : (1 : ℝ) ≤ 0 := sum_below.geometric_bound.real (fun i => (1 : ℝ)) 1 1 1 (by intro i hi; linarith \[false_sum_bound])\n")
    th = session.theorems["marked_geometric_sum"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_sum_bound", "oracle:arith", "oracle:ring"]
      raise "geometric bound lost its assumption tag"
  bad = ["negative_weight", "missing_endpoint", "reversed_bound"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/geometric_failure.sat", bad))
  if session.failures != bad.size
    raise "geometric bounds accepted an invalid premise"
  << "Geometric sums passed: " + suffix

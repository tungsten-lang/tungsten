use ../lib/satori
use proof_source

-> check_forcing_recurrence(suffix)
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
  lemmas = ["geometric_linear", "geometric_linear_succ"].map -> (name) "recurrence." + name + "." + suffix
  defs = ["driven." + suffix]
  examples = ["zero_first", "zero_later", "unit_rate"].map -> (name) suffix + "_" + name
  bad = ["wrong_exponent", "discard_initial", "wrong_index"].map -> (name) suffix + "_" + name
  if suffix == "nat"
    lemmas.push("recurrence.geometric_eq.nat")
    defs = defs + ["kmuls", "bfly"]
    examples = examples + ["nat_nonzero_initial", "kmuls_closed", "bfly_closed"]
  else
    lemmas = lemmas + ["geometric_forcing_eq", "geometric_sum"].map -> (name) "recurrence." + name + "." + suffix
    defs = defs + ["mixed." + suffix, "sum_powers." + suffix]
    examples = examples + ["negative_rate", "mixed_rates", "forcing_zero_rate", "negative_sum", "empty_sum"].map -> (name) suffix + "_" + name
    bad = bad + ["wrong_multiplier", "wrong_sum_base"].map -> (name) suffix + "_" + name
  if suffix == "rat"
    defs = defs + ["gsum", "gs"]
    examples = examples + ["gsum_closed", "geometric"]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/recurrence.sat", lemmas))
  session.run_source(proof_declarations("bits/tungsten-satori/spec/forcing_recurrence.sat", defs))
  session.run_source(proof_declarations("bits/tungsten-satori/spec/forcing_recurrence.sat", examples))
  if session.failures != 0
    raise "forcing recurrence proofs failed for " + suffix
  (lemmas + examples).each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:ring"]
      raise "forcing recurrence theorem is missing, open or has unexpected trust: " + name
  if suffix == "real"
    session.run_source("axiom false_forcing_step : ∀ i, (1 : ℝ) = 0 * (1 : ℝ) + 0 * (0 : ℝ) ^ i\n+ marked_forcing : (1 : ℝ) = 0 := recurrence.geometric_linear_succ.real (fun i => (1 : ℝ)) 0 0 false_forcing_step 0\n")
    th = session.theorems["marked_forcing"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_forcing_step", "oracle:ring"]
      raise "forcing recurrence lost its step assumption tag"
    session.run_source("axiom false_sum_base : (1 : ℝ) = 0\n+ marked_geometric_sum : (1 - 2) * (1 : ℝ) = 1 - 2 ^ 0 := recurrence.geometric_sum.real (fun i => (2 : ℝ) ^ i) 2 false_sum_base (by intro i; rw \[pow_succ.real]; ring) 0\n")
    th = session.theorems["marked_geometric_sum"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_sum_base", "oracle:ring"]
      raise "geometric sum recognition lost its initial assumption tag"
  session.run_source(proof_declarations("bits/tungsten-satori/spec/forcing_recurrence_failure.sat", bad))
  if session.failures != bad.size
    raise "forcing recurrence accepted an invalid step, initial value or index"
  << "Forcing recurrences passed: " + suffix

use ../lib/satori
use proof_source

-> check_affine_recurrence(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  lemmas = ["recurrence.geometric_eq." + suffix, "recurrence.affine_transform." + suffix]
  examples = ["zero_rate", "unit_rate", "zero_scale"].map -> (name) suffix + "_" + name
  bad = ["wrong_balance", "missing_step", "wrong_initial"].map -> (name) suffix + "_" + name
  if suffix != "nat"
    lemmas = lemmas + ["recurrence.affine_closed." + suffix, "recurrence.affine_zero." + suffix]
    examples = examples + ["negative_rate", "nonzero_initial", "zero_initial"].map -> (name) suffix + "_" + name
    bad.push(suffix + "_wrong_offset")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/recurrence.sat", lemmas))
  if suffix == "real"
    session.run_source(proof_declarations("bits/tungsten-satori/spec/affine_recurrence.sat", ["dd"]))
    examples.push("dd_closed")
  elsif suffix == "rat"
    session.run_source(proof_declarations("bits/tungsten-satori/spec/affine_recurrence.sat", ["gsum"]))
    examples.push("gsum_closed")
  elsif suffix == "nat"
    session.run_source(proof_declarations("bits/tungsten-satori/spec/affine_recurrence.sat", ["ep", "chacon"]))
    examples = examples + ["ep_closed", "chacon_closed"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/affine_recurrence.sat", examples))
  if session.failures != 0
    raise "affine recurrence proofs failed for " + suffix
  (lemmas + examples).each -> (name)
    expected = name == "gsum_closed" ? ["oracle:arith", "oracle:ring"] : ["oracle:ring"]
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "affine recurrence theorem is missing, open or has unexpected trust: " + name
  if suffix == "real"
    session.run_source("axiom false_affine_initial : (1 : ℝ) = 0\n+ marked_affine : (1 : ℝ) = 0 := recurrence.affine_zero.real (fun i => (1 : ℝ)) 1 0 1 false_affine_initial (by decide) (by intro i; decide) 2\n")
    th = session.theorems["marked_affine"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_affine_initial", "oracle:ring"]
      raise "affine closed form lost its initial assumption tag"
  session.run_source(proof_declarations("bits/tungsten-satori/spec/affine_recurrence_failure.sat", bad))
  if session.failures != bad.size
    raise "affine recurrence accepted an invalid balance, initial value or step"
  << "Affine recurrences passed: " + suffix

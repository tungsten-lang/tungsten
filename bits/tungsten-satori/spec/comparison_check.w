use ../lib/satori
use proof_source

-> check_comparison(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  prerequisites = ["le_induction.nat"]
  if suffix == "nat"
    prerequisites.push("mul_le_mul_left.nat")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", prerequisites))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/sequence_order.sat", ["nat.interval_induct"]))
  lemma = "recurrence.compare." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/comparison.sat", [lemma]))
  good = ["compare", "empty", "zero_rate", "variable_rate"].map -> (name) suffix + "_" + name
  bad = ["wrong_base", "wrong_upper", "missing_last", "wrong_lower"].map -> (name) suffix + "_" + name
  if suffix != "nat"
    good.push(suffix + "_negative_values")
    bad.push(suffix + "_negative_rate")
  session.run_source(proof_declarations("bits/tungsten-satori/spec/comparison.sat", good))
  if session.failures != 0
    raise "recurrence comparison proofs failed"
  ([lemma] + good).each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
      raise "comparison theorem missing, open or has unexpected trust: " + name
  if suffix == "rat"
    session.run_source("axiom false_comparison_rate : ∀ i < 1, (0 : ℚ) ≤ -1\n+ marked_rate : (0 : ℚ) ≤ -1 := recurrence.compare.rat (fun i => 0) (fun i => if i = 0 then 1 else -1) (fun i => -1) (fun i => 0) 1 false_comparison_rate (by decide) (by decide) (by decide)\n")
    th = session.theorems["marked_rate"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_comparison_rate", "oracle:arith"]
      raise "comparison lost its rate assumption tag"
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/comparison_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "comparison accepted an invalid premise: " + name
  << "Recurrence comparison passed: " + suffix

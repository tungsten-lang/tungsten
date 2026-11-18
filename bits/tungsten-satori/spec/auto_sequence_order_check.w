use ../lib/satori
use proof_source

-> check_auto_sequence_order(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["le_induction.nat"]))
  rules = ["nat.interval_induct", "sequence.monotone_on." + suffix, "sequence.antitone_on." + suffix]
  if suffix == "nat"
    rules = rules + ["sequence.descent_on.nat", "sequence.descent_length.nat"]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/sequence_order.sat", rules))
  good = ["up", "down", "global_up", "global_down", "prefix", "quantified", "wider", "strict_step"]
  bad = ["missing_step", "missing_order", "missing_last", "missing_first", "wrong_direction", "strict_conclusion", "cycle"]
  if suffix == "nat"
    good = good + ["descent", "length", "strict_descent", "descent_quantified"]
    bad = bad + ["descent_missing_last", "descent_weak", "descent_too_long", "descent_wrong_direction"]
  good = good.map -> (name) suffix + "_" + name
  bad = bad.map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sequence_order.sat", good))
  if session.failures != 0
    raise "automatic interval order failed: " + suffix
  (rules + good).each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
      raise "interval order missing, open or has unexpected trust: " + name
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sequence_order_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "interval order accepted an invalid premise or bound: " + name
  if suffix == "rat"
    session.run_source("opaque marked_sequence : ℕ → ℚ\naxiom marked_step : ∀ i, marked_sequence i ≤ marked_sequence (i+1)\n")
    previous = session.failures
    session.run_source("+ unsupplied_order (a b : ℕ) (ab : a ≤ b) : marked_sequence a ≤ marked_sequence b := by auto\n")
    if session.failures != previous + 1 || session.theorems["unsupplied_order"] != nil
      raise "interval order used an unsupplied user axiom"
    session.run_source("+ marked_order (a b : ℕ) (ab : a ≤ b) : marked_sequence a ≤ marked_sequence b := by auto \[marked_step]\n+ local_marked_order (a b : ℕ) (ab : a ≤ b) : marked_sequence a ≤ marked_sequence b\n  have step := marked_step\n  auto \[step]\n")
    ["marked_order", "local_marked_order"].each -> (name)
      th = session.theorems[name]
      if th == nil || th.hyps.size != 0 || th.tags != ["axiom:marked_step", "oracle:arith"]
        raise "interval order lost an explicit assumption tag: " + name
  if suffix == "nat"
    session.run_source("opaque marked_rank : ℕ → ℕ\naxiom rank_step : ∀ i < 5, marked_rank (i+1)+1 ≤ marked_rank i\n+ marked_descent : 5 ≤ marked_rank 0 := by auto \[rank_step]\n")
    th = session.theorems["marked_descent"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:rank_step", "oracle:arith"]
      raise "descent bound lost its explicit assumption tag"
  << "Automatic interval order passed: " + suffix

use ../lib/satori
use proof_source

-> check_sequence_order(suffix)
  cases = {
    "real" => [["real_local", "real_global_down", "real_negative_prefix", "real_equal_endpoints"], ["real_missing_first", "real_prefix_only"]],
    "rat" => [["rational_local_down", "rational_global", "rational_sum_tail", "rational_empty", "rational_cycle"], ["rational_wrong_direction", "rational_negative_tail"]],
    "int" => [["integer_local", "integer_global_down", "integer_sum_singleton", "integer_plateau"], ["integer_weak_strict", "integer_sum_reversed"]],
    "nat" => [["natural_local_down", "natural_global", "cum_mono", "natural_zero_tail"], ["natural_beyond_interval", "natural_sum_backwards"]]
  }
  family = cases[suffix]
  good = ["interval_constant", "interval_empty"] + family[0]
  bad = ["interval_missing_base", "interval_reversed", "interval_missing_last"] + family[1]
  lemmas = ["nat.interval_induct"] + ["monotone_on", "antitone_on", "monotone", "antitone"].map -> (name) "sequence." + name + "." + suffix
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["le_induction.nat", "sum_below_zero", "sum_below_succ"]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/sequence_order.sat", lemmas))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below.mono." + suffix]))
  if suffix == "real"
    session.run_source(proof_declarations("bits/tungsten-satori/spec/sequence_order.sat", ["signed_terms"]))
  session.run_source(proof_declarations("bits/tungsten-satori/spec/sequence_order.sat", good))
  if session.failures != 0
    raise "sequence order proofs failed for " + suffix
  (lemmas + ["sum_below.mono." + suffix] + good).each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
      raise "sequence order theorem is missing, open or has unexpected trust: " + name
  session.run_source("axiom bad_interval_base : False\n+ marked_interval : False := nat.interval_induct (fun n => False) 2 5 (by decide) bad_interval_base (by intro i hi hb ih; exact ih)\n")
  th = session.theorems["marked_interval"]
  if th == nil || th.hyps.size != 0 || th.tags != ["axiom:bad_interval_base", "oracle:arith"]
    raise "interval induction lost an assumption tag"
  session.run_source(proof_declarations("bits/tungsten-satori/spec/sequence_order_failure.sat", bad))
  if session.failures != bad.size
    raise "sequence order accepted an invalid interval or premise"
  << "Sequence order passed: " + suffix

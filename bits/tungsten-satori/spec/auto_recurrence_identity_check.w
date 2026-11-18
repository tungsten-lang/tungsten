use ../lib/satori
use proof_source

-> check_auto_recurrence_identity(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  if suffix == "rat"
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  if suffix != "nat"
    casts = ["cast_add.int"]
    if suffix != "int"
      casts = casts + ["int_cast_add." + suffix, "cast_add." + suffix]
    casts = casts + ["cast_one." + suffix, "cast_succ." + suffix]
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", casts))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/recurrence.sat", ["recurrence.identity"]))
  rule = session.theorems["recurrence.identity"]
  if rule == nil || rule.hyps.size != 0 || rule.tags != []
    raise "sequence identity induction is not kernel-only"
  if suffix == "nat"
    defs = ["butterfly.nat", "weighted.nat", "chacon", "merge_cost"]
    good = ["nat_defined", "nat_reverse", "nat_forcing", "nat_first_index", "nat_product_rates", "nat_two_rates", "nat_weighted", "nat_shift1", "nat_shift2", "nat_shift3", "chacon_closed", "merge_cost_closed"]
    bad = ["nat_missing_base", "nat_missing_step", "nat_wrong_base", "nat_wrong_forcing", "nat_point_step", "nat_wrong_index", "nat_wrong_exponent", "nat_late_step", "nat_wrong_parameter", "nat_guarded_step"]
  if suffix == "int"
    defs = ["butterfly.int", "weighted.int"]
    good = ["int_defined", "int_reverse", "int_forcing", "int_first_index", "int_product_rates", "int_two_rates", "int_weighted", "int_shift1", "int_shift2", "int_shift3"]
    bad = ["int_missing_base", "int_missing_step", "int_wrong_base", "int_wrong_forcing", "int_point_step", "int_wrong_index", "int_wrong_exponent", "int_late_step", "int_wrong_parameter", "int_guarded_step"]
  if suffix == "rat"
    defs = ["butterfly.rat", "weighted.rat", "quarter", "weight"]
    good = ["rat_defined", "rat_reverse", "rat_forcing", "rat_first_index", "rat_product_rates", "rat_two_rates", "rat_weighted", "rat_shift1", "rat_shift2", "rat_shift3", "mass_closed", "entropy_closed"]
    bad = ["rat_missing_base", "rat_missing_step", "rat_wrong_base", "rat_wrong_forcing", "rat_point_step", "rat_wrong_index", "rat_wrong_exponent", "rat_late_step", "rat_wrong_parameter", "rat_guarded_step"]
  if suffix == "real"
    defs = ["butterfly.real", "weighted.real"]
    good = ["real_defined", "real_reverse", "real_forcing", "real_first_index", "real_product_rates", "real_two_rates", "real_weighted", "real_shift1", "real_shift2", "real_shift3"]
    bad = ["real_missing_base", "real_missing_step", "real_wrong_base", "real_wrong_forcing", "real_point_step", "real_wrong_index", "real_wrong_exponent", "real_late_step", "real_wrong_parameter", "real_guarded_step"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_recurrence_identity.sat", defs + good))
  if session.failures != 0
    raise "automatic recurrence identity failed: " + suffix
  good.each -> (name)
    th = session.theorems[name]
    expected = ["oracle:ring"]
    if name.ends_with?("_two_rates") || name.ends_with?("_weighted") || name == "chacon_closed" || name == "merge_cost_closed"
      expected = ["oracle:arith"]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "recurrence identity missing, open or has unexpected trust: " + name
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_recurrence_identity_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "recurrence identity accepted an invalid base or step: " + name
  if suffix == "rat"
    session.run_source("opaque marked_sequence : ℕ → ℚ\naxiom sequence_base : marked_sequence 0 = 0\naxiom sequence_step : ∀ i, marked_sequence (i+1) = 2*marked_sequence i+2^i\n")
    previous = session.failures
    session.run_source("+ unsupplied (n : ℕ) : 2*marked_sequence n = (n : ℚ)*2^n := by auto\n")
    if session.failures != previous + 1 || session.theorems["unsupplied"] != nil
      raise "recurrence identity used an unsupplied axiom"
    session.run_source("+ marked (n : ℕ) : 2*marked_sequence n = (n : ℚ)*2^n := by auto \[sequence_base, sequence_step]\n+ local_marked (n : ℕ) : 2*marked_sequence n = (n : ℚ)*2^n\n  have base := sequence_base\n  have step := sequence_step\n  auto\n")
    ["marked", "local_marked"].each -> (name)
      th = session.theorems[name]
      if th == nil || th.hyps.size != 0 || th.tags != ["axiom:sequence_base", "axiom:sequence_step", "oracle:ring"]
        raise "recurrence identity lost its base or step tags"
  << "Automatic recurrence identities passed: " + suffix

use ../lib/satori
use proof_source

-> check_auto_affine_geometric(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  rule = "recurrence.geometric_eq." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/recurrence.sat", [rule]))
  if suffix == "nat"
    defs = ["affine.nat", "ep"]
    good = ["nat_defined", "nat_reverse", "nat_symbolic", "nat_zero_rate", "nat_unit_rate", "nat_shifted_left", "nat_partial", "nat_zero_coefficient", "ep_closed"]
    bad = ["nat_missing_base", "nat_missing_step", "nat_wrong_base", "nat_wrong_rate", "nat_wrong_index", "nat_point_step", "nat_two_rates", "nat_wrong_offset", "nat_shifted_exponent", "nat_indexed_rate", "nat_squared_power"]
  if suffix == "int"
    defs = ["affine.int"]
    good = ["int_defined", "int_reverse", "int_symbolic", "int_zero_rate", "int_unit_rate", "int_shifted_left", "int_partial", "int_zero_coefficient", "int_negative_rate", "int_shifted"]
    bad = ["int_missing_base", "int_missing_step", "int_wrong_base", "int_wrong_rate", "int_wrong_index", "int_point_step", "int_two_rates", "int_wrong_offset", "int_shifted_exponent", "int_indexed_rate", "int_squared_power"]
  if suffix == "rat"
    defs = ["affine.rat"]
    good = ["rat_defined", "rat_reverse", "rat_symbolic", "rat_zero_rate", "rat_unit_rate", "rat_shifted_left", "rat_partial", "rat_zero_coefficient", "rat_negative_rate", "rat_shifted"]
    bad = ["rat_missing_base", "rat_missing_step", "rat_wrong_base", "rat_wrong_rate", "rat_wrong_index", "rat_point_step", "rat_two_rates", "rat_wrong_offset", "rat_shifted_exponent", "rat_indexed_rate", "rat_squared_power"]
  if suffix == "real"
    defs = ["affine.real", "cc"]
    good = ["real_defined", "real_reverse", "real_symbolic", "real_zero_rate", "real_unit_rate", "real_shifted_left", "real_partial", "real_zero_coefficient", "real_negative_rate", "real_shifted", "cc_closed"]
    bad = ["real_missing_base", "real_missing_step", "real_wrong_base", "real_wrong_rate", "real_wrong_index", "real_point_step", "real_two_rates", "real_wrong_offset", "real_shifted_exponent", "real_indexed_rate", "real_squared_power"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_affine_geometric.sat", defs + good))
  if session.failures != 0
    raise "automatic affine geometric recurrence failed: " + suffix
  good.each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:ring"]
      raise "affine geometric theorem is missing, open or has unexpected trust: " + name
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_affine_geometric_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "affine geometric recurrence accepted a missing premise or wrong formula: " + name
  if suffix == "rat"
    session.run_source("opaque marked_affine : ℕ → ℚ\naxiom affine_base : marked_affine 0 = 2\naxiom affine_step : ∀ i, marked_affine (i+1) = 3*marked_affine i+4\n")
    previous = session.failures
    session.run_source("+ unsupplied (n : ℕ) : marked_affine n = 4*3^n-2 := by auto\n")
    if session.failures != previous + 1 || session.theorems["unsupplied"] != nil
      raise "affine automation used an unsupplied axiom"
    session.run_source("+ marked (n : ℕ) : marked_affine n = 4*3^n-2 := by auto \[affine_base, affine_step]\n+ local_marked (n : ℕ) : marked_affine n = 4*3^n-2\n  have base := affine_base\n  have step := affine_step\n  auto\n")
    ["marked", "local_marked"].each -> (name)
      th = session.theorems[name]
      if th == nil || th.hyps.size != 0 || th.tags != ["axiom:affine_base", "axiom:affine_step", "oracle:ring"]
        raise "affine automation lost supplied assumption tags"
  << "Automatic affine geometric recurrences passed: " + suffix

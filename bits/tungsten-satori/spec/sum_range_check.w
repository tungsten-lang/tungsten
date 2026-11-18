use ../lib/satori
use proof_source

-> check_sum_range(suffix)
  cases = {
    "generic" => [["range_congruence", "local_total_eq"], ["invalid_congruence", "invalid_total_base", "invalid_total_step", "invalid_total_index"]],
    "real" => [["real_strict_witness", "real_negative_band", "real_empty", "real_split", "real_front_empty"], ["invalid_empty_strict", "invalid_unbounded_other_terms", "invalid_front_real"]],
    "rat" => [["rational_negative", "rational_singleton", "rational_split", "rational_front"], ["invalid_outside_witness", "invalid_reversed_bound", "invalid_front_rat"]],
    "int" => [["integer_lower", "integer_equal_rest", "integer_split", "integer_front_negative"], ["invalid_no_strict_term", "invalid_shift", "invalid_front_int"]],
    "nat" => [["natural_strict", "natural_empty", "natural_split", "natural_front_singleton"], ["invalid_weak_is_strict", "invalid_natural_empty", "invalid_front_nat"]]
  }
  family = cases[suffix]
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below_zero", "sum_below_succ"]))
  lemmas = ["sum_below.congr", "sum_below.eq_of_recurrence"]
  if suffix == "generic"
    session.run_source(proof_declarations("bits/tungsten-satori/spec/sum_range.sat", ["local_total"]))
  if suffix != "generic"
    if suffix != "nat"
      casts = ["cast_add.int"]
      if suffix == "rat" || suffix == "real"
        casts = casts + ["int_cast_add." + suffix, "cast_add." + suffix]
      casts = casts + ["cast_one." + suffix, "cast_succ." + suffix]
      session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", casts))
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_const." + suffix, "sum_le." + suffix]))
    lemmas = ["split", "lt_of_le_of_exists_lt", "lt", "le_const", "const_le", "lt_const", "const_lt", "succ_front"].map -> (name) "sum_below." + name + "." + suffix
  basics = ["sum_below.congr", "sum_below.eq_of_recurrence"]
  advanced = lemmas.reject -> (name) basics.include?(name)
  if suffix != "generic"
    basics = ["split", "le_const", "const_le", "succ_front"].map -> (name) "sum_below." + name + "." + suffix
    advanced = lemmas.reject -> (name) basics.include?(name)
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", basics))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/sum_range.sat", advanced))
  session.run_source(proof_declarations("bits/tungsten-satori/spec/sum_range.sat", family[0]))
  if session.failures != 0
    raise "finite range sums failed for " + suffix
  (lemmas + family[0]).each -> (name)
    expected = ["oracle:arith", "oracle:ring"]
    if name == "sum_below.eq_of_recurrence" || name == "local_total_eq"
      expected = []
    elsif name.starts_with?("sum_below.split.") || name.ends_with?("_split") || name.starts_with?("sum_below.succ_front.") || name.include?("_front")
      expected = ["oracle:ring"]
    elsif name == "sum_below.congr" || name.starts_with?("sum_below.lt.") || name.starts_with?("sum_below.lt_of_le_of_exists_lt.") || name.starts_with?("sum_below.le_const.") || name.starts_with?("sum_below.const_le.") || ["range_congruence", "real_strict_witness", "integer_equal_rest", "natural_strict", "real_negative_band", "real_empty", "natural_empty"].include?(name)
      expected = ["oracle:arith"]
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "range sum theorem is missing, open or has unexpected trust: " + name
  if suffix == "rat"
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below.eq_of_recurrence"]))
    session.run_source(proof_declarations("bits/tungsten-satori/spec/sum_range_examples.sat", ["qtw", "zalt", "yalt", "tel", "alt_telescope"]))
    th = session.theorems["alt_telescope"]
    if session.failures != 0 || th == nil || th.hyps.size != 0 || th.tags != ["oracle:ring"]
      raise "cumulative cut identity is missing, open or has unexpected trust"
  session.run_source(proof_declarations("bits/tungsten-satori/spec/sum_range_failure.sat", family[1]))
  if session.failures != family[1].size
    raise "range sums accepted an invalid goal for " + suffix
  if suffix == "generic"
    session.run_source("axiom false_total_base : (1 : ℕ) = 0\n+ marked_total : (1 : ℕ) = sum_below 0 (fun (i : ℕ) => (0 : ℕ)) := sum_below.eq_of_recurrence (fun i => (0 : ℕ)) (fun i => (1 : ℕ)) false_total_base (by intro i; simp) 0\n")
    th = session.theorems["marked_total"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_total_base"]
      raise "cumulative sum recognition lost an assumption tag"
  << "Finite range sums passed: " + suffix

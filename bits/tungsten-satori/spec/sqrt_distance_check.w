use ../lib/satori
use proof_source

-> check_sqrt_distance(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  prerequisites = ["abs_cases", "abs_of_nonpos"].map -> (name) name + "." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", prerequisites))
  lemmas = ["square_gap.le_abs." + suffix]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/square_gap.sat", lemmas))
  examples = ["gap", "swapped", "zero", "equality"].map -> (name) suffix + "_" + name
  bad = ["missing_left", "missing_right", "strict"].map -> (name) suffix + "_" + name
  if suffix == "real"
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_list", "sum_below", "mem_nil", "mem_cons"]))
    session.run_import("real")
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["pow_two.real", "abs_sq.real", "sq_abs.real", "sum_below_zero", "sum_below_succ", "sum_le.real", "mul_le_mul_of_nonneg_left.real"]))
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/list_sum.sat", ["list_sum.nil", "list_sum.cons", "sum_list_le.real", "sum_list_weighted_le.real"]))
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/realx.sat", ["le_sqrt_iff"]))
    roots = ["sqrt_sub_sq_le_abs", "sqrt_sub_abs_le", "list_sum.weighted_sqrt_distance.real", "list_sum.sqrt_distance.real", "sum_below.weighted_sqrt_distance.real", "sum_below.sqrt_distance.real"]
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/sqrt_distance.sat", roots))
    lemmas = lemmas + roots
    examples = examples + ["root_squared", "root_holder", "root_zero", "root_equal", "list_weighted", "list_unweighted", "range_weighted", "range_unweighted"]
    bad = bad + ["root_missing_left", "root_missing_right", "root_strict", "root_lipschitz", "list_negative_weight", "list_strict", "range_negative_weight", "range_strict"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/sqrt_distance.sat", examples))
  if session.failures != 0
    raise "Square-gap/root-distance proofs failed: " + suffix
  (lemmas + examples).each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
      raise "Square-gap/root theorem missing, open or has unexpected trust: " + name
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/sqrt_distance_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "Square-gap/root distance accepted an invalid sign or bound: " + name
  if suffix == "real"
    session.run_source("axiom false_root_sign (x : ℝ) : 0 ≤ x\n+ marked_distance (x y : ℝ) (hy : 0 ≤ y) : |sqrt x-sqrt y| ≤ sqrt (|x-y|) := sqrt_sub_abs_le x y (false_root_sign x) hy\n")
    th = session.theorems["marked_distance"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_root_sign", "oracle:arith", "oracle:ring"]
      raise "Root distance lost its sign assumption tag"
  << "Square-gap/root distance passed: " + suffix

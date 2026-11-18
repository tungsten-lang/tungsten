use ../lib/satori
use proof_source

-> check_sum_squares(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_list", "mem_nil", "mem_cons"]))
  arithmetic = ["pow_two." + suffix]
  if suffix == "nat"
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/logic.sat", ["or_self"]))
    arithmetic = ["mul_le_mul_left.nat", "mul_le_mul_right.nat", "mul_le_mul.nat", "mul_eq_zero.nat"] + arithmetic
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", arithmetic))
  prerequisites = ["sum_list_member_le." + suffix]
  if suffix != "nat"
    prerequisites = ["list_sum.nil", "list_sum.cons", "list_sum.closed", "sum_list_nonneg." + suffix] + prerequisites
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list_sum.sat", prerequisites))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/sum_support.sat", ["list_sum.eq_zero." + suffix, "list_sum.eq_zero_iff." + suffix]))
  lemmas = ["squares_nonneg", "squares_eq_zero_iff", "weighted_squares_nonneg", "weighted_squares_eq_zero_iff"].map -> (name) "list_sum." + name + "." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/sum_squares.sat", lemmas))
  examples = ["nonneg", "terms", "zero", "weighted_nonneg", "weighted_terms", "weighted_zero", "powers", "empty", "repeated", "zero_weights"].map -> (name) suffix + "_" + name
  if suffix != "nat"
    examples.push(suffix + "_signed_cancellation")
  session.run_source(proof_declarations("bits/tungsten-satori/spec/sum_squares.sat", examples))
  if session.failures != 0
    raise "sum of squares proofs failed for " + suffix
  (lemmas + examples).each -> (name)
    expected = ["oracle:arith"]
    if suffix == "nat" || name == suffix + "_powers"
      expected = ["oracle:arith", "oracle:ring"]
    if [suffix + "_empty", suffix + "_zero_weights", suffix + "_signed_cancellation"].include?(name) || (suffix == "nat" && ["list_sum.squares_nonneg.nat", "list_sum.weighted_squares_nonneg.nat", "nat_nonneg", "nat_weighted_nonneg"].include?(name))
      expected = []
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "sum of squares theorem is missing, open or has unexpected trust: " + name
  if suffix == "rat"
    session.run_source("axiom false_square_weight : ∀ x ∈ ((1 : ℚ) :: []), (0 : ℚ) > 0\n+ marked_square_weight : (1 : ℚ) = 0 := (list_sum.weighted_squares_eq_zero_iff.rat ((1 : ℚ) :: []) (fun x => 0) (fun x => x) false_square_weight).mp (by decide) 1 (by simp)\n")
    th = session.theorems["marked_square_weight"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_square_weight", "oracle:arith"]
      raise "sum of squares lost its positive-weight assumption tag"
  if suffix == "nat"
    session.run_source("axiom false_square_total : sum_list (1 :: []) (fun (x : ℕ) => x * x) = 0\n+ marked_square_total : (1 : ℕ) = 0 := (list_sum.squares_eq_zero_iff.nat (1 :: []) (fun x => x)).mp false_square_total 1 (by simp)\n")
    th = session.theorems["marked_square_total"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_square_total", "oracle:arith", "oracle:ring"]
      raise "sum of squares lost its total assumption tag"
  bad = ["weak_weights", "zero_weight", "outside_member", "wrong_total", "one_zero", "changed_weight"]
  if suffix != "nat"
    bad = bad + ["missing_sign", "negative_weight"]
  bad.each -> (base)
    name = suffix + "_" + base
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/sum_squares_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "sum of squares accepted an invalid weight, member or total: " + name
  << "Sum of squares passed: " + suffix

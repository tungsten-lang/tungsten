use ../lib/satori
use proof_source

-> check_sum_support(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below", "sum_list", "mem_nil", "mem_cons"]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below_zero", "sum_below_succ", "sum_nonneg." + suffix, "single_le_sum." + suffix]))
  prerequisites = ["sum_list_member_le." + suffix]
  if suffix != "nat"
    prerequisites = ["list_sum.nil", "list_sum.cons", "list_sum.closed", "sum_list_nonneg." + suffix] + prerequisites
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list_sum.sat", prerequisites))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below.congr"]))
  lemmas = ["sum_below.zero", "sum_below.eq_zero", "sum_below.eq_zero_iff", "sum_below.pos_iff", "sum_below.pos", "list_sum.eq_zero", "list_sum.eq_zero_iff", "list_sum.pos_iff"].map -> (name) name + "." + suffix
  basics = ["sum_below.zero." + suffix, "sum_below.eq_zero." + suffix]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", basics))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/sum_support.sat", lemmas.reject -> (name) basics.include?(name)))
  examples = ["constant", "bounded_zero", "bounded_terms", "bounded_positive", "bounded_witness", "bounded_find", "list_zero", "list_terms", "list_witness", "list_find", "empty", "repeated"].map -> (name) suffix + "_" + name
  if suffix != "nat"
    examples.push(suffix + "_signed_cancellation")
  session.run_source(proof_declarations("bits/tungsten-satori/spec/sum_support.sat", examples))
  if session.failures != 0
    raise "finite sum support proofs failed for " + suffix
  (lemmas + examples).each -> (name)
    expected = ["oracle:arith"]
    if name == "sum_below.zero." + suffix || name == suffix + "_constant" || name == "list_sum.eq_zero." + suffix || name == suffix + "_list_zero" || name == suffix + "_repeated" || name == suffix + "_signed_cancellation"
      expected = []
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "sum support theorem is missing, open or has unexpected trust: " + name
  if suffix == "rat"
    session.run_source("axiom false_sum_sign : ∀ i < 2, 0 ≤ (if i = 0 then 1 else -1 : ℚ)\n+ marked_sum_sign : (1 : ℚ) = 0 := by\n  have h := (sum_below.eq_zero_iff.rat (fun i => if i = 0 then 1 else -1) 2 false_sum_sign).mp (by decide) 0 (by decide)\n  simpa using h\n")
    th = session.theorems["marked_sum_sign"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_sum_sign", "oracle:arith"]
      raise "sum vanishing lost its nonnegativity assumption tag"
  if suffix == "nat"
    session.run_source("axiom false_list_total : sum_list (1 :: []) (fun (i : ℕ) => i) = 0\n+ marked_list_total : (1 : ℕ) = 0 := (list_sum.eq_zero_iff.nat (1 :: []) (fun i => i)).mp false_list_total 1 (by simp)\n")
    th = session.theorems["marked_list_total"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_list_total", "oracle:arith"]
      raise "sum vanishing lost its total assumption tag"
  bad = ["outside_bound", "wrong_total", "weak_positive", "empty_positive", "outside_member", "wrong_list_total"]
  if suffix != "nat"
    bad = bad + ["missing_sign", "missing_list_sign"]
  bad.each -> (base)
    name = suffix + "_" + base
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/sum_support_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "sum support accepted an invalid index, sign or total: " + name
  << "Finite sum support passed: " + suffix

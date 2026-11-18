use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_file("bits/tungsten-satori/spec/linear_combination.sat")
if session.failures != 0
  raise "linear combination proofs failed"
names = ["scaled_int", "scaled_rat", "scaled_real", "scaled_nat", "sum_int", "subtract_int", "reverse_int", "cancel_nat", "difference_nat", "reverse_nat", "nested_real", "scaled_twice", "fraction_rat", "cast_coefficient", "opaque_coefficient", "projection", "beta_eta", "coefficient_beta", "under_binder", "identity", "identity_nat", "large_coefficient", "lc_identity", "applied_theorem", "local_coefficient", "centred_squares", "blaschke_modulus", "koebe_q_circle"]
natural = ["scaled_nat", "cancel_nat", "difference_nat", "reverse_nat"]
names.each -> (name)
  th = session.theorems[name]
  expected = natural.include?(name) ? ["oracle:arith", "oracle:ring"] : ["oracle:ring"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "linear combination theorem is missing, open or has unexpected trust: " + name
session.run_source("axiom false_combination : (1 : ℤ) = 0\n+ marked_combination : (2 : ℤ) = 0 := by linear_combination 2 * false_combination\n+ marked_zero : (0 : ℤ) = 0 := by linear_combination 0 * false_combination\n")
["marked_combination", "marked_zero"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_combination", "oracle:ring"]
    raise "linear combination lost its supplied assumption tag: " + name
session.run_source("axiom false_nat_combination (a b : ℕ) : a = b\n+ marked_nat_combination (a b : ℕ) : 2 * a = 2 * b := by linear_combination 2 * (false_nat_combination a b)\n")
th = session.theorems["marked_nat_combination"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_nat_combination", "oracle:arith", "oracle:ring"]
  raise "natural combination lost its supplied assumption tag"
bad = ["wrong_coefficient", "wrong_sign", "wrong_goal", "not_equation", "inequality_input", "proposition_input", "boolean_equation", "mixed_types", "coefficient_type", "unknown_proof", "unknown_zero_proof", "unknown_coefficient", "missing_proof", "proof_product", "unspecialized", "wrong_argument", "captured_argument", "bad_projection", "bad_identity", "natural_subtraction", "natural_negative", "natural_wrong_balance", "wrong_centered_squares", "zero_denominator", "variable_denominator", "natural_unknown_zero"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/linear_combination_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "linear combination accepted an invalid certificate: " + name
<< "Linear combination passed"

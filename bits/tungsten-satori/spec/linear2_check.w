use ../lib/satori
use proof_source

-> check_linear2(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["mul_eq_zero." + suffix]))
  lemmas = ["eliminate", "unique", "zero"].map -> (name) "linear2." + name + "." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/linear2.sat", lemmas))
  good = ["eliminate", "unique", "zero", "swap", "nonunit", "singular_elimination"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/linear2.sat", good))
  if session.failures != 0
    raise "two-equation proofs failed"
  (lemmas + good).each -> (name)
    expected = ["oracle:arith", "oracle:ring"]
    if name == "linear2.eliminate." + suffix || name == suffix + "_eliminate" || name == suffix + "_singular_elimination"
      expected = ["oracle:ring"]
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "two-equation theorem missing, open or has unexpected trust: " + name
  if suffix == "rat"
    session.run_source("axiom false_determinant : (0 : ℚ) ≠ 0\n+ marked_determinant : (1 : ℚ) = 0 ∧ (0 : ℚ) = 0 := linear2.zero.rat 0 0 0 0 1 0 (by simpa using false_determinant) (by decide) (by decide)\n")
    th = session.theorems["marked_determinant"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_determinant", "oracle:arith", "oracle:ring"]
      raise "two-equation proof lost its determinant assumption tag"
  ["singular_unique", "weak_det", "wrong_row", "wrong_output"].each -> (base)
    name = suffix + "_" + base
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/linear2_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "two-equation rule accepted an invalid premise: " + name
  << "Two-equation proofs passed: " + suffix

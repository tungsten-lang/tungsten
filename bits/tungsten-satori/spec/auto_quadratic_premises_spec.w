use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
session.run_import("real")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/realx.sat", ["sqrt_le_iff", "le_sqrt_iff"]))
session.run_source(File.read("bits/tungsten-satori/spec/auto_quadratic_premises.sat").replace("import realx\n", ""))
if session.failures != 0
  raise "quadratic premise proofs failed"
examples = ["norm_sum", "norm_lower", "alias_sum", "alias_lower", "scaled_bound", "function_bound", "shifted_bound", "degenerate_bound", "int_product", "rat_square"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith"]
  if name == "int_product"
    expected = ["axiom:int_product_rule", "oracle:arith"]
  if name == "rat_square"
    expected = ["axiom:rat_square_rule", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "quadratic premise missing, open or has unexpected trust: " + name
bad = ["missing_sum_sign", "missing_one_sign", "strict_sum", "wrong_lower", "wrong_scale", "missing_scale_bound", "wrong_function", "wrong_shift", "weak_product", "missing_product_sign", "wrong_instance"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_quadratic_premises_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid quadratic premise: " + name
session.run_source("axiom assumed_sign (a : ℝ) : 0 ≤ a\n+ marked_norm (a b : ℝ) (hb : 0 ≤ b) : norm a b ≤ a+b\n  have ha := assumed_sign a\n  auto\n")
th = session.theorems["marked_norm"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:assumed_sign", "oracle:arith"]
  raise "quadratic premises lost a local sign assumption"
<< "quadratic premises passed"

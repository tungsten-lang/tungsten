use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("order")
session.run_source(File.read("bits/tungsten-satori/spec/auto_equality_products.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "automatic equality products failed"
examples = ["coupling_rat", "coupling_int", "coupling_real", "coupling_nat", "distribute", "right_factor", "negative_factor", "affine_factor", "two_equalities", "conjunction", "strict_bound", "explicit_balance"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith"]
  if name == "coupling_nat"
    expected = ["oracle:arith", "oracle:ring"]
  if name == "explicit_balance"
    expected = ["axiom:supplied_balance", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "equality product missing, open or has unexpected trust: " + name
bad = ["wrong_constant", "inequality_as_equality", "unknown_sign", "negative_sign", "missing_equality", "wrong_factor", "branch_leak", "natural_truncation", "wrong_coupling", "missing_coupling_sign", "weak_strict", "no_global_balance"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_equality_products_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid equality product: " + name
<< "automatic equality products passed"

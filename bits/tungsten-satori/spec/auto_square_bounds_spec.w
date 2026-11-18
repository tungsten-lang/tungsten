use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("order")
session.run_source(File.read("bits/tungsten-satori/spec/auto_square_bounds.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "automatic square bounds failed"
examples = ["coupling_rat", "coupling_int", "coupling_real", "coupling_nat", "two_bounds", "two_bounds_nat", "weighted", "strict_weighted", "mixed_spelling", "shifted_bases", "conjunction", "explicit_bounds"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith"]
  if name == "coupling_nat" || name == "two_bounds_nat"
    expected = ["oracle:arith", "oracle:ring"]
  if name == "explicit_bounds"
    expected = ["axiom:supplied_squares", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "square bound missing, open or has unexpected trust: " + name
bad = ["missing_sign", "negative_roots", "negative_weight", "weak_strict", "zero_weight", "missing_second", "reversed_second", "wrong_coupling", "wrong_shift", "branch_leak", "natural_weak_strict", "no_global_bounds"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_square_bounds_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid square bound: " + name
<< "automatic square bounds passed"

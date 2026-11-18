use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("order")
session.run_source(File.read("bits/tungsten-satori/spec/auto_structured_guards.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "automatic structured guards failed"
examples = ["total_nonneg_nat", "total_nonneg_int", "total_nonneg_rat", "total_nonneg_real", "restricted", "strict_restricted", "conditional", "paired", "vacuous", "nested", "hinted"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith"]
  if name == "hinted"
    expected = ["axiom:supplied_step", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "structured guard missing, open or has unexpected trust: " + name
bad = ["missing", "wrong_range", "wrong_sign", "weak_strict", "escaped", "missing_pair", "cycle", "branch_leak", "wrong_function", "no_global_step"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_structured_guards_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid structured guard: " + name
<< "automatic structured guards passed"

use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("order")
session.run_source(File.read("bits/tungsten-satori/spec/auto_arithmetic_congruence.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "arithmetic congruence failed"
["transport_nat", "transport_int", "transport_rat", "transport_real", "reverse", "transitive", "nested", "two_arguments", "strict", "two_functions", "abstract_domain", "guarded", "cancellation", "hinted", "hinted_terms", "bundled", "conditional_equality"].each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith"]
  if name == "hinted"
    expected = ["axiom:supplied_index", "oracle:arith"]
  if name == "hinted_terms"
    expected = ["axiom:supplied_bound", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "arithmetic congruence missing, open or has unexpected trust: " + name
["missing", "ordered", "unequal", "different_function", "incomplete_chain", "missing_argument", "weak_strict", "changed_bound", "branch_leak", "missing_sign", "no_global_index", "no_global_bound"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_arithmetic_congruence_failure.sat", [name]))
  if session.failures != before + 1 || session.theorems[name] != nil
    raise "auto accepted invalid arithmetic congruence: " + name
<< "Arithmetic congruence passed"

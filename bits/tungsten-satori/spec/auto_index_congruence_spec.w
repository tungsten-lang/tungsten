use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("order")
session.run_source(File.read("bits/tungsten-satori/spec/auto_index_congruence.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "arithmetic index congruence failed"
["nat_reassociate", "nat_balanced", "nat_bound", "int_reassociate", "int_balanced", "int_bound", "rat_reassociate", "rat_balanced", "rat_bound", "real_reassociate", "real_balanced", "real_bound", "nested", "two_arguments", "squeezed", "conditional", "strict", "scaled", "branch", "hinted", "explicit"].each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith"]
  if name == "hinted"
    expected = ["axiom:given_index", "oracle:arith"]
  if name == "explicit"
    expected = []
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "arithmetic index congruence missing, open or has unexpected trust: " + name
["wrong_shift", "wrong_function", "one_bound", "wrong_balance", "missing_argument", "missing_guard", "truncated_subtraction", "ordered_images", "strict_from_weak", "branch_leak", "unproved_condition", "wrong_nested", "missing_index_fact", "int_wrong_shift", "rat_wrong_shift", "real_wrong_shift"].each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_index_congruence_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "arithmetic index congruence accepted an invalid proof: " + name
<< "Arithmetic index congruence passed"

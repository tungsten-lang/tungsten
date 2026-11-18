use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(File.read("bits/tungsten-satori/spec/auto_forward_arith.sat"))
if session.failures != 0
  raise "forward arithmetic failed"
["nat_weaken", "nat_combine", "nat_equality", "int_weaken", "int_combine", "int_equality", "rat_weaken", "rat_combine", "rat_equality", "real_weaken", "real_combine", "real_equality", "predicate_guard", "two_stage", "branches", "marked"].each -> (name)
  th = session.theorems[name]
  expected = ["oracle:arith"]
  if name == "marked"
    expected = ["axiom:supplied_forward", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "forward arithmetic missing, open or wrong trust: " + name
["nat_missing_guard", "nat_too_strong", "nat_wrong_index", "int_missing_guard", "int_too_strong", "int_wrong_index", "rat_missing_guard", "rat_too_strong", "rat_wrong_index", "real_missing_guard", "real_too_strong", "real_wrong_index", "branch_leak", "circular", "no_global_axiom"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_forward_arith_failure.sat", [name]))
  if session.failures != before + 1 || session.theorems[name] != nil
    raise "forward arithmetic accepted invalid goal: " + name
<< "Forward arithmetic passed"

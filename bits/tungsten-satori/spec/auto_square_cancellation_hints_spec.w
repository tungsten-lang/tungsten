use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_square_cancellation_hints.sat")
if session.failures != 0
  raise "square cancellation hints failed"
["supplied", "local_bound", "unused", "partial", "local_rule"].each -> (name)
  th = session.theorems[name]
  expected = name == "local_rule" ? ["oracle:arith"] : ["axiom:supplied_square_bound", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != expected
    raise "square cancellation lost a dependency: " + name
["unsupplied", "missing_guard", "wrong_guard", "wrong_strict", "local_wrong_guard"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_square_cancellation_hints_failure.sat", [name]))
  if session.failures != before + 1 || session.theorems[name] != nil
    raise "square cancellation ignored a guard: " + name
<< "Square cancellation hints passed"

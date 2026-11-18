use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_compound_hints.sat")
if session.failures != 0
  raise "compound arithmetic hints failed"
["supplied", "local_supplied"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != ["axiom:zero_when", "oracle:arith"]
    raise "compound abstraction lost its original proof dependency"
["unsupplied", "missing_guard", "wrong_guard", "wrong_component"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_compound_hints_failure.sat", [name]))
  if session.failures != before+1 || session.theorems[name] != nil
    raise "compound abstraction bypassed an axiom or guard: " + name
<< "Compound arithmetic hints passed"

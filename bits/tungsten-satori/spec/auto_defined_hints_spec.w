use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_defined_hints.sat")
if session.failures != 0
  raise "defined arithmetic hints failed"
["supplied", "applied", "local_supplied"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["axiom:ordered_if", "oracle:arith"]
    raise "normalization lost a supplied axiom or its original local hypothesis"
["unsupplied", "missing_guard", "wrong_guard", "too_strong"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_defined_hints_failure.sat", [name]))
  if session.failures != before+1 || session.theorems[name] != nil
    raise "normalization accepted an invalid hint or missing guard: " + name
<< "Defined arithmetic hints passed"

use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_enum_list_hints.sat")
if session.failures != 0
  raise "enum list guarded hints failed"
["supplied", "local_supplied"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["axiom:measure_base", "axiom:measure_step", "oracle:ring"]
    raise "enum list hint lost its required axiom dependencies"
["unsupplied", "missing_guard", "point_guard", "missing_base", "wrong_tail"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_enum_list_hints_failure.sat", [name]))
  if session.failures != before+1 || session.theorems[name] != nil
    raise "enum list hint bypassed a missing assumption: " + name
<< "Enum list guarded hints passed"

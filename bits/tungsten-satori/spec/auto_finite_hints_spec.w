use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_finite_hints.sat")
if session.failures != 0
  raise "finite case hints failed"
["supplied", "local_supplied"].each -> (name)
  th = session.theorems[name]
  tags = ["axiom:score_a", "axiom:score_b"]
  if name == "supplied"
    tags.push("oracle:arith")
  if th == nil || th.hyps.size != 0 || th.tags != tags
    raise "finite cases lost a guarded axiom dependency"
th = session.theorems["direct_hint_after_cases"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:every_pair"]
  raise "finite cases starved direct hint search or changed its trust"
["unsupplied", "missing_case", "missing_guard", "wrong_guard"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_finite_hints_failure.sat", [name]))
  if session.failures != before+1 || session.theorems[name] != nil
    raise "finite cases bypassed a guard or a missing constructor fact"
<< "Finite case hints passed"

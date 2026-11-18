use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_relation_guards.sat")
if session.failures != 0
  raise "guarded traversal relation failed"
names = ["first_part", "second_part", "supplied", "local_supplied"]
names.each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["axiom:guarded"]
    raise "guarded relation lost a named axiom tag"
prover = Prover.new(session)
parts = prover.auto_relation_parts(session.theorems["guarded"], [8])
if parts.size != 2
  raise "guarded coordinate projection lost a component"
parts.each_with_index -> (part, i)
  expected = session.theorems[names[i]]
  if !tm_eq(part.concl, expected.concl) || part.hyps.size != 0 || part.tags != expected.tags
    raise "coordinate projection changed quantifiers, guards or trust"
limited = false
begin
  prover.auto_relation_parts(session.theorems["guarded"], [1])
rescue e
  limited = true
if !limited
  raise "coordinate projection ignored its limit"
["unsupplied", "missing_guard", "point_guard"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_relation_guards_failure.sat", [name]))
  if session.failures != before+1 || session.theorems[name] != nil
    raise "traversal relation bypassed a guard or used an unsupplied axiom"
<< "Guarded relation projections passed"

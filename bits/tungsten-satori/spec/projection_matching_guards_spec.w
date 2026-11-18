use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(File.read("bits/tungsten-satori/spec/projection_matching_guards.sat"))
if session.failures != 0
  raise "projection trust setup failed"
["reflexive_rule", "actual_projection", "explicit_projection"].each -> (name)
  th = session.theorems[name]
  expected = name == "explicit_projection" ? ["axiom:fake_projection"] : []
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "projection rule has unexpected trust: " + name
["hidden_projection", "hidden_projection_apply", "swapped_projection"].each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/projection_matching_guards_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "matching used an unrelated projection assumption: " + name
<< "projection matching guards passed"

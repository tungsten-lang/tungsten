use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_registered_chains_hints.sat")
if session.failures != 0
  raise "registered arithmetic with hints failed"
["supplied_chain", "unused_hint"].each -> (name)
  th = session.theorems[name]
  tags = name == "supplied_chain" ? ["axiom:supplied_form", "oracle:arith"] : ["oracle:arith"]
  if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != tags
    raise "registered arithmetic changed hint dependencies: " + name
["unsupplied", "wrong_endpoint", "missing_ready"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_registered_chains_hints_failure.sat", [name]))
  if session.failures != before + 1 || session.theorems[name] != nil
    raise "registered arithmetic used a missing hint or wrong bound: " + name
<< "Registered arithmetic hint dependencies passed"

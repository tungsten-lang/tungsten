use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/recurrence.sat", ["recurrence.count"]))
session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_counter.sat", ["count", "marked_counter", "counter_base", "counter_step", "named_count", "local_count"]))
if session.failures != 0
  raise "automatic counter recognition failed"
["count", "named_count", "local_count"].each -> (name)
  expected = name == "count" ? [] : ["axiom:counter_base", "axiom:counter_step"]
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "automatic counter lost assumptions or introduced an oracle"
session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_counter_failure.sat", ["unsupplied_count"]))
if session.failures != 1 || session.theorems["unsupplied_count"] != nil
  raise "automatic counter used an unsupplied axiom"
<< "Automatic counter trust passed"

use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(File.read("bits/tungsten-satori/spec/auto_local_arith.sat"))
if session.failures != 0
  raise "local arithmetic guards failed"
["guarded_bound", "two_guards", "marked_bound"].each -> (name)
  expected = ["oracle:arith"]
  if name == "marked_bound"
    expected = ["axiom:supplied_bound", "oracle:arith"]
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "local guard theorem missing, open or has wrong trust: " + name
["missing_guard", "unused_axiom", "wrong_alias"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_local_arith_failure.sat", [name]))
  if session.failures != before + 1 || session.theorems[name] != nil
    raise "local arithmetic accepted missing guard or wrong alias: " + name
<< "Local arithmetic inference passed"

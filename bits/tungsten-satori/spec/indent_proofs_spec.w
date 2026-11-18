use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(File.read("bits/tungsten-satori/spec/indent_proofs.sat"))
if session.failures != 0
  raise "indented proof layout failed"
["pair", "arrows", "nested", "choice", "implications", "continuation", "sequence", "applied", "mixed", "witness", "cases_layout", "induction_layout", "quantified", "own_have"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != []
    raise "indented proof missing, open or has unexpected trust: " + name
["ignored_invalid", "ignored_admit", "open_nested", "sibling_escape", "branch_scope", "wrong_nested", "nested_universal"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/indent_proofs_failure.sat", [name]))
  if session.failures != before + 1 || session.theorems[name] != nil
    raise "indented proof ignored code or escaped scope: " + name
<< "Indented proof layout passed"

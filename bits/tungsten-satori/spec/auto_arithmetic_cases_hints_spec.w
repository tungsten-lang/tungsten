use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_arithmetic_cases_hints.sat")
if session.failures != 0
  raise "arithmetic case hints failed"
["supplied_bound", "local_bound", "supplied_nonzero", "local_nonzero", "unused_hint", "two_supplied"].each -> (name)
  tags = ["axiom:case_nonzero", "oracle:arith"]
  if name.ends_with?("_bound")
    tags = ["axiom:case_upper", "oracle:arith"]
  if name == "two_supplied"
    tags = ["axiom:case_nonzero", "axiom:case_other_nonzero", "oracle:arith"]
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != tags
    raise "arithmetic cases lost a dependency or added an unused axiom: " + name
["unsupplied_bound", "missing_guard", "wrong_guard", "unsupplied_nonzero", "wrong_nonzero_guard", "nonzero_product", "missing_second_guard"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_arithmetic_cases_hints_failure.sat", [name]))
  if session.failures != before + 1 || session.theorems[name] != nil
    raise "arithmetic cases bypassed an axiom or guard: " + name
<< "Arithmetic case hints passed"

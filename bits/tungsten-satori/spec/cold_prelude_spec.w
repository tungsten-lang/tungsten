use ../lib/satori

# Exercise the default import from source under the interpreted spec runner's cap.
session = Session.new(".")
session.no_cache = true
session.quiet = true
session.load_prelude
session.run_source("+ from_prelude (a : ℤ) : 0 ≤ a ^ 2 := sq_nonneg.int a\n")
th = session.theorems["from_prelude"]
if session.failures != 0 || th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
  raise "cold prelude failed to supply its checked square bound"
<< "Cold prelude passed"

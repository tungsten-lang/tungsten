use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_arithmetic_cases_corpus.sat")
if session.failures != 0
  raise "compact corpus inequalities failed"
["moment_ratio", "union_bound"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "compact inequality missing, open or unexpectedly trusted: " + name
<< "Compact arithmetic cases passed"

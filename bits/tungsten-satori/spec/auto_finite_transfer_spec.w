use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_finite_transfer.sat")
if session.failures != 0
  raise "compact finite transfer proofs failed"
["step_inv", "run_inv", "step_act", "run_act"].each -> (name)
  th = session.theorems[name]
  tags = ["step_inv", "run_inv"].include?(name) ? ["oracle:arith"] : ["oracle:ring"]
  if th == nil || th.hyps.size != 0 || th.tags != tags
    raise "finite transfer proof changed its statement's trust"
<< "Compact finite transfer proofs passed"

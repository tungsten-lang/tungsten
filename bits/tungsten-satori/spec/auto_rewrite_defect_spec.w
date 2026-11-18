use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_rewrite_defect.sat")
if session.failures != 0
  raise "compact disjoint-support proof failed"
th = session.theorems["disjoint_criterion4"]
if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
  raise "disjoint-support theorem missing, open or changed trust"
<< "Supplied disjoint-support formula passed"

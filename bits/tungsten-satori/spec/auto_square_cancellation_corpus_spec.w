use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_square_cancellation_corpus.sat")
th = session.theorems["gershgorin_ring3"]
if session.failures != 0 || th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != ["oracle:arith"]
  raise "copied Anderson bound failed or changed trust"
<< "Copied Anderson bound passed"

use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_defined_transfer.sat")
if session.failures != 0
  raise "compact trace bound failed"
th = session.theorems["trace_pos"]
if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
  raise "trace bound missing, open or unexpectedly trusted"
<< "Compact trace bound passed"

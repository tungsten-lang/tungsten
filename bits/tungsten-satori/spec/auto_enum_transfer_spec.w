use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_enum_transfer.sat")
if session.failures != 0
  raise "compact determinant word identity failed"
["det_mul", "det_word"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:ring"]
    raise "determinant word identity missing, open or changed trust"
<< "Compact determinant word identity passed"

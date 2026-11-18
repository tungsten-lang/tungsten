use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_list_transfer.sat")
if session.failures != 0
  raise "automatic transfer relation failed"
["step_act", "run_act"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:ring"]
    raise "transfer relation changed trust"
<< "Automatic transfer relation passed"

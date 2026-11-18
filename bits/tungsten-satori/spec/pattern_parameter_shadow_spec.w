use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/pattern_parameter_shadow.sat")
if session.failures != 0
  raise "explicit pattern parameters did not shadow global names"
[["walk", 2], ["counted", 2], ["head_default", 2], ["identity", 1]].each -> (entry)
  equations = session.eqns_of(entry[0])
  if equations.size != entry[1]
    raise "shadowed parameter lost a defining equation"
  equations.each -> (th)
    if th.hyps.size != 0 || th.tags != []
      raise "shadowed parameter equation has unexpected trust"
["parameter_function", "parameter_zero", "parameter_nil", "constructor_nil", "parameter_simple"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != []
    raise "parameter shadowing proof has unexpected trust"
session.run_source("+ incorrect (xs : list ℕ) : counted 7 xs = counted 8 xs := by auto\n")
if session.failures != 1 || session.theorems["incorrect"] != nil
  raise "parameter shadowing erased an argument"
<< "Pattern parameter shadowing passed"

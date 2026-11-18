use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_file("bits/tungsten-satori/spec/natural_nlinarith.sat")
if session.failures != 0
  raise "natural nonlinear arithmetic failed"
["natural_scale", "natural_function_weight", "natural_product_weight", "natural_sub_weight", "natural_product_mono", "dimension_gap"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
    raise "natural nonlinear arithmetic produced an open theorem or unexpected trust"
session.run_file("bits/tungsten-satori/spec/natural_nlinarith_failure.sat")
if session.failures != 8
  raise "natural nonlinear arithmetic accepted an invalid goal"
<< "Natural nonlinear arithmetic passed"

use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_file("bits/tungsten-satori/spec/absolute_layout.sat")
if session.failures != 0
  raise "absolute-value continuation or pattern layout failed"
["continued_abs", "continued_value_eq", "continued_sum", "layout_pattern_ok", "layout_choice_ok", "layout_pattern_abs_ok"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != []
    raise "layout theorem missing, open or has unexpected trust: " + name
previous = session.failures
session.run_source("+ missing_bar (x : ℝ) :\n    |x = x\n  rfl\n")
if session.failures != previous + 1 || session.theorems["missing_bar"] != nil
  raise "layout accepted an unclosed absolute value"
<< "Absolute-value layout passed"

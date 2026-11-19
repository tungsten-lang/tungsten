use ../lib/satori

s = Session.new(".")
s.quiet = true
s.no_cache = true
s.run_source(File.read("bits/tungsten-satori/examples/compact_power_steps.sat"))
s.run_source(File.read("bits/tungsten-satori/spec/power_steps.sat"))
if s.failures != 0
  raise "power step proof failed"
names = ["nat_mul_power", "power_backward_weight", "positive", "successor", "offset", "opposite", "hinted", "masked", "sum_weight"]
names.each -> (name)
  tags = ["oracle:arith", "oracle:ring"]
  if name == "successor" || name == "opposite"
    tags = ["oracle:ring"]
  if name == "hinted"
    tags = ["axiom:neighbor", "oracle:arith", "oracle:ring"]
  th = s.theorems[name]
  if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != tags
    raise "unexpected power step dependencies: " + name
parse_program(File.read("bits/tungsten-satori/spec/power_steps_failure.sat")).each -> (cmd)
  s.elab.reset_counter
  msg = ""
  begin
    s.exec(cmd)
  rescue e
    msg = e.to_s
  if !msg.include?("auto failed") || s.theorems[cmd.name] != nil
    raise "expected an open power step: " + cmd.name + " " + msg
s.run_source("axiom pow_succ.int (a : ℤ) (n : ℕ) : a^(n+1) = a^n*a\n")
s.run_source("+ shadowed (a k : ℤ) (n : ℕ) : k*a^(n+1) = a^n*k*a := by auto\n")
if s.failures != 1 || s.theorems["shadowed"] != nil
  raise "power step silently used a shadowing axiom"
<< "Power steps passed"

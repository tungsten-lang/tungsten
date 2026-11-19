use ../lib/satori

s = Session.new(".")
s.quiet = true
s.no_cache = true
s.run_source(File.read("bits/tungsten-satori/examples/compact_interval_witnesses.sat"))
s.run_source(File.read("bits/tungsten-satori/spec/auto_interval_witnesses.sat"))
if s.failures != 0
  raise "interval proof failed"
names = ["exists_inner_disk_scale", "exists_endpoint_count_exponent", "rational_between",
         "negative_slope", "touching", "separated", "negated_bound", "fixed_value", "only_lower", "only_upper",
         "cancelled", "intersection", "hinted", "guarded"]
names.each -> (name)
  th = s.theorems[name]
  tags = ["oracle:arith"]
  if name == "hinted" || name == "guarded"
    tags = [name == "hinted" ? "axiom:gap" : "axiom:guarded_gap", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != tags
    raise "unexpected interval proof dependencies: " + name
parse_program(File.read("bits/tungsten-satori/spec/auto_interval_witnesses_failure.sat")).each -> (cmd)
  s.elab.reset_counter
  msg = ""
  begin
    s.exec(cmd)
  rescue e
    msg = e.to_s
  if !msg.include?("auto failed") || s.theorems[cmd.name] != nil
    raise "expected open interval obligation: " + cmd.name + " " + msg
<< "Interval witnesses passed"

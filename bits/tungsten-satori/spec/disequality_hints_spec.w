use ../lib/satori

s = Session.new(".")
s.quiet = true
s.no_cache = true
s.run_import("order")
s.run_source(File.read("bits/tungsten-satori/spec/disequality_hints.sat"))
if s.failures != 0
  raise "arithmetic with disequality hints failed"
sources = {"applied" => "apart", "quantified" => "apart", "widened" => "apart", "guarded_reverse" => "guarded", "bundled" => "packet", "unused" => "",
           "strict_of_separated" => "", "strict_of_injective" => "", "at_least_three" => ""}
sources.each -> (name, source)
  th = s.theorems[name]
  tags = source == "" ? ["oracle:arith"] : ["axiom:" + source, "oracle:arith"]
  if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != tags
    raise "unexpected proof dependencies: " + name
parse_program(File.read("bits/tungsten-satori/spec/disequality_hints_failure.sat")).each -> (cmd)
  s.elab.reset_counter
  msg = ""
  begin
    s.exec(cmd)
  rescue e
    msg = e.to_s
  expected = cmd.name == "can_be_two" ? "linarith failed" : "auto failed"
  if !msg.include?(expected) || s.theorems[cmd.name] != nil
    raise "expected arithmetic goal to remain open: " + cmd.name + " " + msg
<< "Disequality hints passed"

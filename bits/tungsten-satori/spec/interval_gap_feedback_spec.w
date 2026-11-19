use ../lib/satori
use proof_source

s = Session.new(".")
s.quiet = true
s.no_cache = true
s.run_import("core")
bounds = {"open_gap" => "a ≤ b", "rescaled" => "2 * a ≤ 3 * b", "chained" => "a ≤ b",
          "hinted" => "f i ≤ g i", "side_condition" => "c ≤ d"}
proof_source_blocks("bits/tungsten-satori/spec/interval_gap_feedback.sat").each -> (entry)
  name = entry[0]
  src = entry[1].join("\n") + "\n"
  if !src.starts_with?("+ ")
    s.run_source(src)
    next
  s.elab.reset_counter
  msg = ""
  begin
    s.exec(parse_program(src)[0])
  rescue e
    msg = e.to_s
  if !msg.include?("auto failed\n") || s.theorems[name] != nil
    raise "expected an open interval: " + name
  bound = bounds[name]
  if bound == nil
    if msg.include?("\n  proved ") || msg.include?("\n  need ")
      raise "unjustified repair: " + name + " " + msg
  else
    if !msg.include?("\n  proved " + bound + "\n  need " + bound.gsub(" ≤ ", " ≠ ") + "\n")
      raise "wrong interval gap: " + name + " " + msg
    # Apply the printed condition to the source, then check the same proof.
    need = msg.split("\n  need ")[1].split("\n")[0]
    s.run_source(src.replace(" : ∃", " (repair : " + need + ") : ∃"))
    th = s.theorems[name]
    tags = name == "hinted" ? ["axiom:ordered", "oracle:arith"] : ["oracle:arith"]
    if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != tags
      raise "printed interval repair failed: " + name
if s.failures != 0
  raise "interval repair replay failed"
<< "Interval gap feedback passed"

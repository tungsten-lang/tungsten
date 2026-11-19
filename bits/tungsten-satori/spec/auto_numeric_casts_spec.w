use ../lib/satori

s = Session.new(".")
s.quiet = true
s.no_cache = true
s.run_import("order")
s.run_source(File.read("bits/tungsten-satori/examples/compact_numeric_casts.sat"))
s.run_source(File.read("bits/tungsten-satori/spec/auto_numeric_casts.sat"))
if s.failures != 0
  raise "widening cast proofs failed"
["nat_int", "nat_rat", "nat_real", "int_rat", "int_real", "rat_real", "weighted", "strict_shift", "cast_step", "cast_polynomial",
 "marked", "use_bound", "cast_order", "reflect_strict", "reflect_eq", "mixed_bound", "fractional", "opaque_order",
 "reflect_literal", "cast_sum_bound", "discrete_gap", "cone_coefficient", "same_domain", "inconsistent", "separated"].each -> (name)
  th = s.theorems[name]
  tags = []
  if ["weighted", "strict_shift", "mixed_bound", "cone_coefficient", "inconsistent", "separated"].include?(name)
    tags = ["oracle:arith"]
  if name == "marked"
    tags = ["axiom:sample_sign"]
  if name == "use_bound"
    tags = ["axiom:sample_bound", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != tags
    raise "unexpected assumptions or dependencies: " + name
bad = parse_program(File.read("bits/tungsten-satori/spec/auto_numeric_casts_failure.sat"))
bad.each -> (cmd)
  s.elab.reset_counter
  msg = ""
  begin
    s.exec(cmd)
  rescue e
    msg = e.to_s
  failure = cmd.name == "wrong_hint" ? "linarith failed" : "auto failed"
  if !msg.include?(failure) || s.theorems[cmd.name] != nil
    raise "expected cast proof to fail: " + cmd.name + " " + msg
  if cmd.name == "strict_cast" && !msg.include?("\n  proved (m : ℝ) ≤ (n : ℝ)\n  need m ≠ n\n")
    raise "missing strictness feedback: " + msg
  if cmd.name == "strict_cast"
    s.run_source("+ repaired (m n : ℕ) (h : m ≤ n) (apart : m ≠ n) : (m : ℝ) < (n : ℝ) := by auto\n")
    th = s.theorems["repaired"]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
      raise "the reported strictness condition failed to close the proof"
<< "Numeric cast proofs passed"

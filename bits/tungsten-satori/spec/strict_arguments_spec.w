use ../lib/satori
use proof_source

s = Session.new(".")
s.quiet = true
s.no_cache = true
s.run_import("order")
rules = ["mul_le_mul_of_nonneg_left.real", "mul_le_mul_of_nonneg_right.real",
         "mul_lt_mul_of_pos_left.real", "mul_lt_mul_of_pos_right.real"]
s.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", rules))
if s.failures != 0
  raise "strict argument prerequisites failed"
notes = {
  "possible_zero" => ["a * c ≤ b * c", "c ≠ 0"], "possible_tie" => ["c * a ≤ c * b", "a ≠ b"],
  "unknown_sign" => ["a < b", "0 < c"], "zero_factor" => ["a * c = b * c", nil],
  "two_gaps" => ["a * c ≤ b * c", "a * c ≠ b * c"], "shifted" => ["t + a ≤ t + b", "a ≠ b"],
  "flat" => ["f i ≤ f j", "f i ≠ f j"], "injective" => ["f i ≤ f j", "i ≠ j"],
  "square_tie" => ["a ^ 2 ≤ b ^ 2", "a ^ 2 ≠ b ^ 2"],
  "slope" => ["d * (1 + l) * z ≤ (l / z - 1) * z", "z ≠ 0"]}
src = File.read("bits/tungsten-satori/spec/strict_arguments.sat").replace("import arith\n", "")
parse_program(src).each -> (cmd)
  s.elab.reset_counter
  pair = notes[cmd.name]
  if pair == nil
    s.exec(cmd)
    th = s.theorems[cmd.name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
      raise "strict argument repair left unexpected dependencies: " + cmd.name
    next
  msg = ""
  begin
    s.exec(cmd)
  rescue e
    msg = e.to_s
  expected = "auto failed\n  proved " + pair[0] + "\n"
  if pair[1] != nil
    expected += "  need " + pair[1] + "\n"
  if !msg.include?(expected) || (pair[1] == nil && msg.include?("  need ")) || s.theorems[cmd.name] != nil
    raise "incorrect strict argument feedback: " + cmd.name + " " + msg
<< "Strict argument feedback passed"

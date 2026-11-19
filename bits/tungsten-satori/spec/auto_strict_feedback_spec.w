use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("order")
proved = {"squares" => "b ^ 2 ≤ d", "reversed" => "y ≤ x", "supplied" => "score x ≤ x", "focused" => "x ≤ y"}
ordinary = ["no_bound", "wrong_direction", "unrelated", "alternative", "implicit_tie"]
proved["padded"] = "x + 0 ≤ y"
proved["guarded"] = "score x ≤ score y"
commands = parse_program(File.read("bits/tungsten-satori/spec/auto_strict_feedback.sat"))
commands.each -> (cmd)
  session.elab.reset_counter
  if !proved.has_key?(cmd.name) && !ordinary.include?(cmd.name)
    session.exec(cmd)
  else
    msg = ""
    begin
      session.exec(cmd)
    rescue e
      msg = e.to_s
    if !msg.include?("auto failed\n") || session.theorems[cmd.name] != nil
      raise "expected auto to leave the claim open: " + cmd.name
    bound = proved[cmd.name]
    if bound != nil
      missing = cmd.name == "padded" ? "x ≠ y" : bound.gsub(" ≤ ", " ≠ ")
      expected = "\n  proved " + bound + "\n  need " + missing + "\n"
      if !msg.include?(expected) || !msg.include?("⊢ " + bound.gsub(" ≤ ", " < "))
        raise "wrong partial bound or focused goal: " + msg
    elsif msg.include?("\n  proved ") || msg.include?("\n  need ")
      raise "reported an unproved or speculative bound: " + msg
if session.theorems["strict"] == nil
  raise "a provable strict inequality failed"
# Division by zero is total in each numeric domain. Strictness is impossible
# here, so a disequality would be a misleading repair.
["ℕ", "ℤ", "ℚ", "ℝ"].each_with_index -> (ty, i)
  name = "zero_quotient_" + i.to_s
  cmd = parse_program("+ " + name + " (a : " + ty + ") : 0 < a/0 := by auto")[0]
  msg = ""
  begin
    session.exec(cmd)
  rescue e
    msg = e.to_s
  if !msg.include?("auto failed\n  proved 0 = a / 0\n") || msg.include?("  need ") || session.theorems[name] != nil
    raise "strict zero quotient feedback: " + msg
<< "Strict bound feedback passed"

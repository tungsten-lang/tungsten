use ../lib/satori

s = Session.new(".")
s.quiet = true
s.no_cache = true
s.run_import("core")
notes = {
  "guarded" => ["k", "k ≤ n ∧ active k", "ready k"],
  "compound" => ["f k", "active (f k)", "ready (f k)"],
  "nested" => ["k", "active k ∧ signed k", "ready k"],
  "ranked" => ["y", "active y ∧ signed y", "ready y"],
  "supplied" => ["x", "active x", "ready x"],
  "two_missing" => ["x", "active x", "ready x ∧ signed x"],
  "alternative" => ["y", "active y", "ready y"],
  "repeated" => ["k", "active k", "ready k"]}
silent = ["independent", "no_fact", "refuted", "refuted_neg", "impossible", "outside", "unrelated", "no_refl", "negated_guard"]
parse_program(File.read("bits/tungsten-satori/spec/auto_witness_feedback.sat")).each -> (cmd)
  s.elab.reset_counter
  if notes.has_key?(cmd.name) || silent.include?(cmd.name)
    msg = ""
    begin
      s.exec(cmd)
    rescue e
      msg = e.to_s
    if !msg.include?("auto failed\n") || s.theorems[cmd.name] != nil
      raise "expected an open existential: " + cmd.name + " " + msg
    if notes.has_key?(cmd.name)
      parts = notes[cmd.name]
      note = "\n  witness " + parts[0] + "\n  proved " + parts[1] + "\n  need " + parts[2] + "\n"
      if !msg.include?(note)
        raise "wrong witness obligations: " + cmd.name + " " + msg
    elsif msg.include?("\n  witness ") || msg.include?("\n  proved ")
      raise "unsupported witness: " + cmd.name + " " + msg
  else
    s.exec(cmd)
["repaired", "repaired_pair"].each -> (name)
  th = s.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != (name == "repaired" ? ["oracle:arith"] : [])
    raise "witness repair failed: " + name
<< "Witness feedback passed"

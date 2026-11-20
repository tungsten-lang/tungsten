use ../lib/satori
use proof_source

s = Session.new(".")
s.quiet = true
s.no_cache = true
s.load_prelude
rules = ["max_cases.real", "le_max_left.real", "mul_le_mul_of_nonneg_right.real"]
rules = rules + ["pow_nonneg.real", "pow_le_pow_left.real", "one_div_pos.real", "one_div_nonneg.real", "mul_div_cancel.real", "mul_div_cancel_right.real", "div_le_div_of_nonneg_right.real", "div_le_iff.real"]
s.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", rules))
if s.failures != 0
  raise "hint feedback fixtures failed to load"
notes = {
  "use_context" => ["base_load n ≤ 2 ∧ extra_load n ≤ 1", "3 ≤ b"],
  "use_named" => ["base_load n ≤ 2", "2 + extra_load n ≤ b"],
  "batch_gap" => ["(∀ j < n, ready j) ∧ (∀ k < n, mark k)", "∀ j < n, active j"],
  "batch_other_range" => ["(∀ j < n, ready j ∧ active j ∧ mark j) → done_at n", "∀ j < n, ready j ∧ active j ∧ mark j"],
  "quotient" => ["a ≤ b * c", "0 < c"],
  "edge_bound" => ["C ≤ 8 * a * N", "0 < N"],
  "power_guard" => ["a ≤ b", "0 ≤ a"],
  "local_evidence" => ["A ≤ B * C", "0 < C"],
  "supplied_quotient" => ["A ≤ B * C", "0 < C"],
  "clamp" => ["1 ≤ A", "0 ≤ max lo (min hi y)"],
  "first_missing" => ["active i", "ready i"],
  "supplied" => ["ready i", "active i"],
  "second_path" => ["mark i → done_at i", "mark i"],
  "unordered" => ["a ≠ b", "a ≤ b"],
  "cast_guard" => ["0 ≤ q → 0 ≤ (q : ℝ)", "0 ≤ q"],
  "registered_clamp" => ["1 ≤ A", "0 ≤ max lo (min hi y)"],
  "quantified" => ["(∀ i < n, 0 ≤ f i) → 0 ≤ aggregate f n", "∀ i < n, 0 ≤ f i"]}
silent = ["unsupported_quotient", "unrelated_guard", "refuted_guard", "refuted", "batch_refuted", "two_missing", "other_index", "circular", "backwards", "shadowed_scale"]
fixture = File.read("bits/tungsten-satori/spec/hint_feedback.sat").replace("import arith\n", "")
parse_program(fixture).each -> (cmd)
  s.elab.reset_counter
  if !notes.has_key?(cmd.name) && !silent.include?(cmd.name)
    s.exec(cmd)
    next
  msg = ""
  begin
    s.exec(cmd)
  rescue e
    msg = e.to_s
  if !msg.include?("auto failed\n") || s.theorems[cmd.name] != nil
    raise "expected an open goal: " + cmd.name + " " + msg
  pair = notes[cmd.name]
  if pair != nil
    if !msg.include?("\n  proved " + pair[0] + "\n  need " + pair[1] + "\n")
      raise "incorrect hint feedback: " + cmd.name + " " + msg
  elsif msg.include?("\n  proved ") || msg.include?("\n  need ")
    raise "unsupported hint repair: " + cmd.name + " " + msg
expected = {"clamp_repaired" => ["oracle:arith"], "repaired" => ["axiom:finish", "axiom:visible"], "quantified_repaired" => ["axiom:aggregate_nonneg"]}
expected["quotient_repaired"] = ["oracle:arith", "oracle:ring"]
expected["batch_repaired"] = ["axiom:checked_batch"]
expected["registered_repair"] = ["oracle:arith"]
expected.keys.each -> (name)
  th = s.theorems[name]
  if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != expected[name]
    raise "unexpected repair dependencies: " + name
<< "Hint feedback passed"

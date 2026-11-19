use ../lib/satori
use proof_source

s = Session.new(".")
s.quiet = true
s.no_cache = true
s.run_import("core")
rules = ["abs_cases", "le_abs_self", "mul_le_mul_of_nonneg_right", "one_div_pos", "one_div_nonneg",
         "mul_div_cancel", "mul_div_cancel_right", "div_pos", "div_le_div_of_nonneg_right", "le_div_iff", "affine_step_radius"]
["rat", "real"].each -> (field)
  s.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", rules.map -> (name) name + "." + field))
s.run_source(File.read("bits/tungsten-satori/examples/compact_affine_steps.sat").replace("import arith\n", ""))
s.run_source("+ reflected (a b : ℚ) (h : 0 < a) : ∃ t, 0 < t ∧ t < 1 ∧ t*b < (1-t)*a := by auto\n")
s.run_source("+ weak_conclusion (m n : ℝ) : ∃ t, 0 < t ∧ m*t ≤ 2 ∧ n*t < 1 := by auto\n")
s.run_source("opaque limit : ℕ → ℚ\naxiom room (i : ℕ) : 0 < limit i\n")
s.run_source("+ supplied (i : ℕ) (m : ℚ) : ∃ t, 0 < t ∧ m*t < limit i := by auto \[room]\n")
if s.failures != 0
  raise "affine endpoint proof failed"
names = ["exists_gap_parameter", "interior_bound", "common_step", "reflected", "weak_conclusion", "supplied"]
names.each -> (name)
  th = s.theorems[name]
  expected = name == "supplied" ? ["axiom:room", "oracle:arith", "oracle:ring"] : ["oracle:arith", "oracle:ring"]
  if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != expected
    raise "unexpected affine endpoint dependencies: " + name
parse_program(File.read("bits/tungsten-satori/spec/affine_steps_failure.sat")).each -> (cmd)
  s.elab.reset_counter
  msg = ""
  begin
    s.exec(cmd)
  rescue e
    msg = e.to_s
  if !msg.include?("auto failed") || s.theorems[cmd.name] != nil
    raise "expected an open affine endpoint goal: " + cmd.name + " " + msg
# A shadowing axiom cannot silently replace the checked radius lemma.
s.run_source("axiom affine_step_radius.real (m e : ℝ) (he : 0 < e) : 0 < e / (|m|+1) ∧ ∀ t, 0 < t → t ≤ e / (|m|+1) → m*t < e\n")
s.run_source("+ shadowed (m n : ℝ) : ∃ t, 0 < t ∧ m*t < 2 ∧ n*t < 1 := by auto\n")
if s.failures != 1 || s.theorems["shadowed"] != nil
  raise "affine endpoint search used a shadowing axiom"
<< "Affine endpoint steps passed"

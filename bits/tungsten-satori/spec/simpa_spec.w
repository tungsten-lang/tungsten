use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("logic")
session.run_file("bits/tungsten-satori/spec/simpa.sat")
if session.failures != 0
  raise "simpa proofs failed"
["unchanged", "simplify_goal", "simplify_proof", "simplify_both", "close_true", "close_assumption", "only_rule", "reverse_rule", "all_hypotheses", "empty_rules", "empty_no_using", "explicit_default", "unfold_alias", "under_forall", "under_exists", "beta_eta", "function_rule", "function_rule_binder", "function_rule_chain", "function_rule_lambda", "proof_projection", "wrap_proof", "application", "inferred_argument", "conditional_rule", "bound_names", "zero_add", "closed_using"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags.size != 0
    raise "simpa theorem is missing, open or has unexpected trust: " + name
session.run_source("axiom marked_simpa_source : False ∧ True\n+ marked_simpa_result : False := by simpa using marked_simpa_source\n")
th = session.theorems["marked_simpa_result"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:marked_simpa_source"]
  raise "simpa lost the supplied proof's assumption tag"
session.run_source("axiom marked_simpa_rule (p q : Prop) : p = q\n+ marked_simpa_rewrite (p q : Prop) (h : p) : q := by simpa only \[marked_simpa_rule p q] using h\n")
th = session.theorems["marked_simpa_rewrite"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:marked_simpa_rule"]
  raise "simpa lost a simplification rule's assumption tag"
session.run_source("+ simpa_arithmetic (p : Prop) (x : ℝ) (rule : 0 ≤ x → p = True) (hx : 1 ≤ x) : p := by simpa only \[rule] using close_true\n")
th = session.theorems["simpa_arithmetic"]
if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
  raise "simpa lost its conditional arithmetic dependency"
session.run_file("bits/tungsten-satori/spec/simpa_failure.sat")
if session.failures != 16
  raise "simpa accepted an invalid proof or left a goal unfinished"
<< "Simpa passed"

use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_file("bits/tungsten-satori/spec/rewrite_conditions.sat")
if session.failures != 0
  raise "conditional rewriting failed to infer a premise argument"
["from_guard", "same_guard_names", "renamed_guard", "guard_in_hyp", "guard_after_decoy", "explicit_guard"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags.size != 0
    raise "conditional rewrite is missing, open or has unexpected trust: " + name
["missing_guard", "wrong_guard", "wrong_result", "fixed_argument"].each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/rewrite_conditions_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "conditional rewriting accepted a missing or inconsistent premise: " + name
session.run_source("axiom named_step (f : ℕ → ℕ) (n : ℕ) : f n = n+1\n+ marked_guard (next : ℕ → ℕ) (index : ℕ) : index+1 = next index := by have step := named_step next index; rw \[from_guard]\n")
marked = session.theorems["marked_guard"]
if marked == nil || marked.hyps.size != 0 || marked.tags != ["axiom:named_step"]
  raise "conditional rewriting lost its guard's axiom tag"
<< "Conditional rewriting passed"

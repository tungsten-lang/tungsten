use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_file("bits/tungsten-satori/spec/rewrite_functions.sat")
if session.failures != 0
  raise "function rewriting failed"
["eta_rewrite", "eta_target", "beta_target", "eta_in_hyp", "eta_under_binder", "eta_conditional", "eta_simp", "function_head_simp", "function_head_simp_hyp", "definition_induction", "definition_conditional", "eta_alias_exact", "eta_alias_wrapped", "bare_unfold", "bare_unfold_binary", "bare_unfold_under_binder"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags.size != 0
    raise "function rewrite is missing, open or has unexpected trust: " + name
["eta_linear", "eta_ring", "bare_unfold_bound", "bare_unfold_hyp"].each -> (name)
  th = session.theorems[name]
  expected = name == "eta_ring" ? ["oracle:ring"] : ["oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "arithmetic conversion has unexpected trust: " + name
session.run_source("axiom marked_function (F : (α → β) → γ) (f : α → β) (y : γ) : F (fun x => f x) = y\n+ marked_rewrite (F : (α → β) → γ) (f : α → β) (y : γ) : F f = y := by rw \[marked_function F f y]\n")
marked = session.theorems["marked_rewrite"]
if marked == nil || marked.tags != ["axiom:marked_function"]
  raise "function rewriting lost an axiom tag"
session.run_source("axiom marked_unfold (F : (ℕ → ℕ) → ℚ) : F unfold_increment ≤ 0\n+ marked_unfold_result (F : (ℕ → ℕ) → ℚ) : F (fun n => n + 1) ≤ 0 := by have h := marked_unfold F; unfold unfold_increment at h; linarith\n")
marked = session.theorems["marked_unfold_result"]
if marked == nil || marked.hyps.size != 0 || marked.tags != ["axiom:marked_unfold", "oracle:arith"]
  raise "unfolding a function lost an axiom tag"
session.run_file("bits/tungsten-satori/spec/rewrite_functions_failure.sat")
if session.failures != 11
  raise "function rewriting accepted an invalid proof"
<< "Function rewriting passed"

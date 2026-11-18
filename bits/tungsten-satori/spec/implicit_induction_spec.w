use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(File.read("bits/tungsten-satori/spec/implicit_induction.sat"))
if session.failures != 0
  raise "implicit induction setup failed"
["named_nat", "named_cases", "earlier_binder", "preceding_guard", "step_guard", "increasing", "already_local", "local_priority", "list_identity", "earlier_list_parameter", "bullet_compat"].each -> (name)
  expected = []
  if name == "earlier_binder"
    expected = ["oracle:ring"]
  if name == "increasing"
    expected = ["oracle:arith"]
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "implicit induction missing, open or has unexpected trust: " + name
["unknown_name", "missing_target", "extra_target", "expression_target", "missing_case", "invalid_step", "inside_disjunction", "inside_negation", "wrong_type", "cases_extra"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/implicit_induction_failure.sat", [name]))
  if session.failures != before + 1 || session.theorems[name] != nil
    raise "implicit induction accepted invalid target, scope or proof: " + name
session.run_source("axiom supplied_growth (f : ℕ → ℕ) : ∀ i, f i < f (i+1)\n+ marked_growth (f : ℕ → ℕ) : ∀ i, i ≤ f i\n  have step := supplied_growth f\n  induction i\n    linarith\n    auto\n")
th = session.theorems["marked_growth"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:supplied_growth", "oracle:arith"]
  raise "implicit induction lost its supplied assumption tag"
<< "Implicit induction setup passed"

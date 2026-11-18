use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
rule = session.theorems["list.recursive_invariant"]
if rule == nil || rule.hyps.size != 0 || rule.tags != []
  raise "recursive traversal invariant is not kernel-only"
session.run_file("bits/tungsten-satori/spec/auto_fold_invariant.sat")
session.run_file("bits/tungsten-satori/spec/auto_fold_transfer.sat")
if session.failures != 0
  raise "automatic traversal invariants failed"
good = ["capture_names", "three_properties"]
["l", "r"].each -> (kind)
  ["direct", "recursive", "alias"].each -> (form)
    ["", "_paired", "_members"].each -> (suffix)
      good.push(kind + "_" + form + suffix)
  ["history", "swap", "unchanged", "fixed"].each -> (suffix)
    good.push(kind + "_" + suffix)
good.each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != []
    raise "traversal invariant missing, open or unexpectedly trusted: " + name
["nat_advance", "int_advance", "rat_advance", "real_advance", "step_inv", "run_inv"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "arithmetic traversal invariant has unexpected trust: " + name
session.run_file("bits/tungsten-satori/spec/auto_fold_invariant_failure.sat")
if session.failures != 29
  raise "traversal invariant accepted missing or incorrect premises"
session.run_source("opaque transition : ℕ → ℚ → ℚ\nopaque property : ℚ → Prop\naxiom preserve : ∀ x s, property s → property (transition x s)\n-> travel : list ℕ → ℚ → ℚ\n  | \[], s => s\n  | x :: xs, s => travel xs (transition x s)\n")
before = session.failures
session.run_source("+ unsupplied (xs : list ℕ) (s : ℚ) (h : property s) : property (travel xs s) := by auto\n")
if session.failures != before+1 || session.theorems["unsupplied"] != nil
  raise "traversal used an unsupplied axiom"
session.run_source("+ marked (xs : list ℕ) (s : ℚ) (h : property s) : property (travel xs s) := by auto \[preserve]\n+ local_marked (xs : list ℕ) (s : ℚ) (h : property s) : property (travel xs s)\n  have step := preserve\n  auto\n+ marked_fold (xs : list ℕ) (s : ℚ) (h : property s) : property (list.foldl transition xs s) := by auto \[preserve]\n")
["marked", "local_marked", "marked_fold"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["axiom:preserve"]
    raise "traversal lost an explicit axiom tag"
<< "Automatic traversal invariants passed"

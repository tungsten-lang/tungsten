use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("logic")
session.run_import("nat")
session.run_file("bits/tungsten-satori/spec/nat_witness.sat")
session.run_file("bits/tungsten-satori/spec/nat_witness_examples.sat")
if session.failures != 0
  raise "natural witness and descent proofs failed"
lemmas = ["strong_induct", "reverse_induct", "exists_least_of", "exists_least", "least_le", "least_unique", "infinite_descent", "descent_bound", "no_infinite_descent"].map -> (name) "nat." + name
applications = ["witness", "existential_witness", "zero_witness", "threshold_minimum", "least_bound", "strong_zero_and_step", "reverse_zero", "reverse_endpoint", "empty_prefix", "finite_prefix", "impossible_chain", "measure_descent", "yslices_disjoint", "sslices_disjoint", "least_below", "slices_cover", "descent_bound", "no_infinite_descent", "descent_drop", "no_cyclic_descent"]
(lemmas + applications).each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "natural pattern is missing, open or has unexpected trust: " + name
["descending_strong", "every_level"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["axiom:base_case", "axiom:induction_step", "oracle:arith"]
    raise "reverse induction lost a model assumption: " + name
session.run_source("axiom bad_step : ∀ n : ℕ, True → ∃ m, m < n ∧ True\n+ marked_descent : ¬ True := nat.infinite_descent (fun n => True) bad_step 0\n")
marked = session.theorems["marked_descent"]
if marked == nil || marked.hyps.size != 0 || marked.tags != ["axiom:bad_step", "oracle:arith"]
  raise "descent lost its assumption tag"
session.run_file("bits/tungsten-satori/spec/nat_witness_failure.sat")
if session.failures != 10
  raise "natural patterns accepted an invalid bound or missing premise"
<< "Natural witness and descent patterns passed"

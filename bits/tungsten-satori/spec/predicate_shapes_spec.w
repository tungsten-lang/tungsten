use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_file("bits/tungsten-satori/spec/predicate_shapes.sat")
if session.failures != 0
  raise "applied predicate shapes failed"
names = ["lambda_left", "lambda_right", "lambda_nested", "lambda_mp", "lambda_mpr", "lambda_symm", "lambda_rfl", "lambda_rfl_term", "lambda_constructor", "lambda_intro", "lambda_tuple", "lambda_witness", "lambda_equivalence", "lambda_obtain", "lambda_obtain_witness", "lambda_obtain_or", "lambda_obtain_iff", "lambda_subst"]
names.each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags.size != 0
    raise "predicate proof is missing, open or has unexpected trust: " + name
session.run_source("axiom marked : (fun p => p ∧ p) False\n+ marked_projection : False := marked.1\n")
marked = session.theorems["marked_projection"]
if marked == nil || marked.tags != ["axiom:marked"]
  raise "predicate conversion lost its assumption tag"
session.run_file("bits/tungsten-satori/spec/predicate_shapes_failure.sat")
if session.failures != 6
  raise "applied predicate shapes accepted an invalid proof"
<< "Applied predicate shapes passed"

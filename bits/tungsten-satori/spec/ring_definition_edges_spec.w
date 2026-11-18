use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/ring_definition_edges.sat")
if session.failures != 0
  raise "ring entry points or opaque atoms failed"
["numeric_entry", "combination_entry", "opaque_atoms"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:ring"]
    raise "ring entry point lost its exact trust"
["truncated_subtraction", "missing_denominator", "zero_denominator", "unsupplied_axiom", "unused_hypothesis"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/ring_definition_edges_failure.sat", [name]))
  if session.failures != before+1 || session.theorems[name] != nil
    raise "ring crossed its algebraic or assumption boundary: " + name
<< "Ring definition boundaries passed"

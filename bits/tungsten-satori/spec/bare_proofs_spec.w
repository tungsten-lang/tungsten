use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(File.read("bits/tungsten-satori/spec/bare_proofs.sat"))
if session.failures != 0
  raise "bare proof terms failed"
["direct", "projected", "nested_projection", "pair", "tuple", "witness", "applied", "instantiate", "symmetry", "flipped", "projected_application", "saved_application", "implication", "parenthesized", "explicit_keyword", "nested_have", "global_fact"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != []
    raise "bare proof missing, open or has unexpected trust: " + name
["typo", "wrong_proof", "missing_premise", "wrong_argument", "wrong_projection", "wrong_witness", "term_is_not_proof", "tactic_precedence", "scope", "overclosed", "shadowed"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/bare_proofs_failure.sat", [name]))
  if session.failures != before + 1 || session.theorems[name] != nil
    raise "bare proof accepted invalid syntax, proof or scope: " + name
session.run_source("axiom supplied_proof (p : Prop) : p\n+ marked (p : Prop) : p\n  supplied_proof p\n")
th = session.theorems["marked"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:supplied_proof"]
  raise "bare proof lost its named assumption tag"
<< "Bare proof terms passed"

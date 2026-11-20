use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_file("bits/tungsten-satori/spec/application_types.sat")
if session.failures != 0
  raise "polymorphic proof applications failed"
["flip_eq", "flip_forward", "flip_backward", "flip_tactic", "flip_saved", "predicate_iff", "predicate_forward", "relation_iff", "relation_forward", "exists_iff", "exists_backward", "quantified_iff", "quantified_forward", "closed_then_applied", "map_forward", "nested_application", "inferred_pair", "inferred_value", "pair_value", "pair_field", "pair_witness", "iff_value", "iff_field", "pair_constructor", "ordinary_iff"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags.size != 0
    raise "polymorphic application is missing, open or has unexpected trust: " + name
session.run_source("axiom false_type_source (p : α → Prop) (x : α) : p x\n+ marked_type_application (p : α → Prop) (x : α) : p x := (predicate_iff p x).mp (false_type_source p x)\n")
th = session.theorems["marked_type_application"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_type_source"]
  raise "polymorphic application lost an assumption tag"
session.run_source("axiom given_pair (P Q : Prop) : paired P Q\n+ projected_pair (P Q : Prop) : Q := (given_pair P Q).2\n")
th = session.theorems["projected_pair"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:given_pair"]
  raise "projection through a defined predicate lost its source"
bad = ["change_fixed", "wrong_premise", "change_predicate", "change_argument", "change_type", "swap_types", "wrong_witness", "captured_binder", "ambiguous_pair", "ambiguous_value", "pair_missing", "invalid_field", "wrong_direction"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/application_types_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "polymorphic application accepted a changed variable or type: " + name
<< "Polymorphic applications passed"

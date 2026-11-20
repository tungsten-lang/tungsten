use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_file("bits/tungsten-satori/spec/application_literals.sat")
if session.failures != 0
  raise "literal argument inference failed"
good = ["nat_literal", "int_literal", "rat_literal", "real_literal", "binder_literal", "offset_right", "offset_left", "successor", "same_offset"]
good.each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags.size != 0
    raise "literal inference theorem missing, open or has unexpected trust: " + name
bad = ["nat_wrong", "nat_missing", "int_wrong", "int_missing", "rat_wrong", "rat_missing", "real_wrong", "real_missing", "binder_capture", "too_small", "disagree"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/application_literals_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "literal inference accepted an incorrect value or missing premise: " + name
session.run_source("opaque literal_P : ℕ → Prop\naxiom literal_pair (n : ℕ) : literal_P n ∧ literal_P (n+1)\n")
previous = session.failures
session.run_source("+ literal_unsupplied : literal_P 3 ∧ literal_P 4 := by auto\n")
if session.failures != previous + 1 || session.theorems["literal_unsupplied"] != nil
  raise "literal inference used an unsupplied axiom"
session.run_source("+ literal_marked : literal_P 3 ∧ literal_P 4 := literal_pair\n")
th = session.theorems["literal_marked"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:literal_pair"]
  raise "literal argument inference lost its axiom tag"
<< "Literal argument inference passed"

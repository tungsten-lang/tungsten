use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
good = ["chord_contradiction", "real_triple", "real_weak", "rat_triple", "rat_weak", "int_triple", "int_weak", "equal_factors", "chained_factors", "negated_factors"]
session.run_file("bits/tungsten-satori/spec/nlinarith_cubic.sat")
if session.failures != 0
  raise "cubic arithmetic failed"
good.each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "cubic proof missing, open or has unexpected trust: " + name
session.run_source("axiom false_cubic_equality (x y : ℚ) : x = y\n+ marked_cubic (x y a b : ℚ) (hx : 0 < x) (ha : 0 < a) (hb : 0 < b) : 0 < y * a * b := by nlinarith \[false_cubic_equality x y]\n")
th = session.theorems["marked_cubic"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_cubic_equality", "oracle:arith"]
  raise "cubic substitution lost its assumption tag"
["weak_strict", "missing_factor", "wrong_sign", "unrelated_equality", "zero_factor", "weak_chord"].each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/nlinarith_cubic_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "cubic search accepted an invalid inequality: " + name
<< "Cubic arithmetic passed"

use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
good = ["real_midpoint", "rat_midpoint", "functions"]
bad = []
["real", "rat", "int"].each -> (kind)
  ["amgm", "negative", "three", "scaled"].each -> (name) good.push(kind + "_" + name)
  ["strict", "wrong_constant", "wrong_negative", "wrong_three"].each -> (name) bad.push(kind + "_" + name)
session.run_file("bits/tungsten-satori/spec/nlinarith_cross_squares.sat")
if session.failures != 0
  raise "cross-square proofs failed"
good.each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "cross-square proof missing, open or has unexpected trust: " + name
session.run_source("axiom false_cross_bound (a b : ℚ) : a*a+b*b < 2*a*b\n+ marked_cross (a b : ℚ) : False := by nlinarith \[false_cross_bound a b]\n")
th = session.theorems["marked_cross"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_cross_bound", "oracle:arith"]
  raise "cross-square proof lost its assumption tag"
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/nlinarith_cross_squares_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "cross-square search accepted an invalid inequality: " + name
<< "Cross-square proofs passed"

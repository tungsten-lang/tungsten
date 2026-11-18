use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
good = ["mixed_types", "function_square"]
bad = ["wrong_function_sign"]
["real", "rat", "int"].each -> (kind)
  ["square", "power", "shift", "nonlinear", "impossible"].each -> (name) good.push(kind + "_" + name)
  ["strict", "negative", "mixed", "opposite"].each -> (name) bad.push(kind + "_" + name)
session.run_file("bits/tungsten-satori/spec/nlinarith_squares.sat")
if session.failures != 0
  raise "automatic square proofs failed"
good.each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "square proof missing, open or has unexpected trust: " + name
session.run_source("axiom false_square_bound (x : ℚ) : x*x < 0\n+ marked_square (x : ℚ) : False := by nlinarith \[false_square_bound x]\n")
th = session.theorems["marked_square"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_square_bound", "oracle:arith"]
  raise "square proof lost its assumption tag"
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/nlinarith_squares_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "square search accepted an invalid inequality: " + name
<< "Automatic square proofs passed"

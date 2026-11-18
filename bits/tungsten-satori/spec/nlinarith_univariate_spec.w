use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
good = ["real_fraction", "rat_fraction", "functions", "siegel"]
bad = []
["real", "rat", "int"].each -> (kind)
  ["unit", "negative", "shift", "strict", "reordered"].each -> (name) good.push(kind + "_" + name)
  ["strict", "constant", "negative", "concave"].each -> (name) bad.push(kind + "_wrong_" + name)
session.run_file("bits/tungsten-satori/spec/nlinarith_univariate.sat")
if session.failures != 0
  raise "univariate-square proofs failed"
good.each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "univariate-square proof missing, open or has unexpected trust: " + name
session.run_source("axiom false_cross_bound (a b : ℚ) : a*a+1 < 2*a\n+ marked_cross (a b : ℚ) : False := by nlinarith \[false_cross_bound a b]\n")
th = session.theorems["marked_cross"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_cross_bound", "oracle:arith"]
  raise "univariate-square proof lost its assumption tag"
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/nlinarith_univariate_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "univariate-square search accepted an invalid inequality: " + name
<< "Univariate-square proofs passed"

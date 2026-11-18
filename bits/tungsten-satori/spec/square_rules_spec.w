use ../lib/satori
use proof_source

# Load only core axioms so the new square proofs cannot use earlier imports
# of themselves or the positivity lemmas they are supposed to establish.
session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
nonneg = ["sq_nonneg.int", "sq_nonneg.rat", "sq_nonneg.real"]
positive = ["sq_pos_of_ne_zero.int", "sq_pos_of_ne_zero.rat", "sq_pos_of_ne_zero.real"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/order.sat", nonneg))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", positive))
if session.failures != 0
  raise "square library rules failed"
(nonneg + positive).each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "square library rule missing, open or has unexpected trust: " + name
session.run_source("+ square_positivity (x : ℝ) : 0 ≤ x ^ 2 := by positivity\n")
th = session.theorems["square_positivity"]
if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
  raise "positivity did not replay the compact square rule"
<< "Square library rules passed"

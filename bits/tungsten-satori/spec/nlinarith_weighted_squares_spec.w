use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/nlinarith_weighted_squares.sat")
if session.failures != 0
  raise "weighted square detection failed"
["int", "rat", "real"].each -> (suffix)
  ["zero", "weighted_nonnegative"].each -> (part)
    th = session.theorems[suffix + "_" + part]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
      raise "weighted square proof missing, open or unexpectedly trusted"
  before = session.failures
  name = suffix + "_negative"
  session.run_source(proof_declarations("bits/tungsten-satori/spec/nlinarith_weighted_squares_failure.sat", [name]))
  if session.failures != before+1 || session.theorems[name] != nil
    raise "weighted square detection discarded a negative coefficient"
<< "Weighted square detection passed"

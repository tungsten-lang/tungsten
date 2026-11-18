use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(File.read("bits/tungsten-satori/spec/simp_false_hyp.sat"))
if session.failures != 0
  raise "simplifying False did not close the goal"
["false_simp", "false_norm_num", "false_all", "true_kept"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != []
    raise "false-hypothesis simplification changed trust"
["false_missing", "norm_num_missing"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/simp_false_hyp_failure.sat", [name]))
  if session.failures != before+1 || session.theorems[name] != nil
    raise "true hypothesis closed an unrelated goal"
<< "False hypothesis simplification passed"

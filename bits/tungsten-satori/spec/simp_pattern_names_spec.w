use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below_zero", "sum_below_succ", "sum_below.single_out.int", "sum_below.single.int"]))
session.run_source(File.read("bits/tungsten-satori/spec/simp_pattern_names.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "conditional simp depends on variable spelling"
["guarded_add", "unused_guard", "same_names", "swapped_names", "renamed", "under_binder", "selected_names"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "conditional simp missing, open or has unexpected trust: " + name
["missing_guard", "wrong_guard", "unmatched_guard", "outside_selection"].each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/simp_pattern_names_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "conditional simp accepted a missing guard or unresolved binder: " + name
<< "Conditional simp names passed"

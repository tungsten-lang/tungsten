use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("logic")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
session.run_import("real")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/realx.sat", ["sqrt_le_iff", "le_sqrt_iff"]))
session.run_source(File.read("bits/tungsten-satori/spec/auto_polymorphic_facts.sat").replace("import realx\n", ""))
if session.failures != 0
  raise "polymorphic hint facts failed"
examples = ["nat_norm", "int_norm", "rat_norm", "real_norm", "generic_norm", "function_norm", "pair_norm", "mixed_types", "two_parameters", "partially_applied", "local_fixed", "guard_supplied", "swapped_parameters", "bundled_types", "pure_logic"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["axiom:measure_nonneg", "oracle:arith"]
  if name == "two_parameters" || name == "partially_applied" || name == "swapped_parameters"
    expected = ["axiom:paired_nonneg", "oracle:arith"]
  if name == "local_fixed"
    expected = ["oracle:arith"]
  if name == "guard_supplied"
    expected = ["axiom:guarded_measure", "oracle:arith"]
  if name == "bundled_types"
    expected = ["axiom:bundled_measure", "oracle:arith"]
  if name == "pure_logic"
    expected = ["axiom:universally_ready"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "polymorphic fact missing, open or has unexpected trust: " + name
bad = ["local_type_fixed", "partial_type_fixed", "no_global_search", "wrong_instance", "guard_missing", "strict_bound", "wrong_result", "branch_leak", "wrong_guard"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_polymorphic_facts_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "polymorphic facts accepted an invalid proof: " + name
<< "polymorphic hint facts passed"

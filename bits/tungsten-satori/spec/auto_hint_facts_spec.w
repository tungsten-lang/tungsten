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
session.run_source(File.read("bits/tungsten-satori/spec/auto_hint_facts.sat").replace("import realx\n", ""))
if session.failures != 0
  raise "explicit hint facts failed"
examples = ["upper", "lower", "linear", "guarded", "bundled", "chained", "specialized", "quantified", "irrelevant_hint", "mixed_contradiction", "function_arguments", "pair_arguments", "local_quantified"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["axiom:u_sign", "axiom:v_sign", "oracle:arith"]
  if name == "function_arguments" || name == "pair_arguments"
    expected = ["axiom:nu_sign", "axiom:nv_sign", "oracle:arith"]
  if name == "local_quantified"
    expected = ["oracle:arith"]
  if name == "lower"
    expected = ["axiom:v_sign", "oracle:arith"]
  if name == "guarded"
    expected = ["axiom:guarded_sign", "axiom:v_sign", "oracle:arith"]
  if name == "bundled"
    expected = ["axiom:both_signs", "oracle:arith"]
  if name == "mixed_contradiction"
    expected = ["axiom:accepted_rule", "oracle:arith"]
  if name == "chained"
    expected = ["axiom:ready_at", "axiom:ready_sign", "axiom:v_sign", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "hint fact proof missing, open or has unexpected trust: " + name
bad = ["missing_hint", "missing_guard", "weak_guard", "strict_bound", "wrong_instance", "missing_chain", "branch_leak", "no_global_search", "wrong_result"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_hint_facts_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "hint facts accepted an invalid proof: " + name
<< "explicit hint facts passed"

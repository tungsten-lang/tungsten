use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("order")
session.run_source(File.read("bits/tungsten-satori/spec/auto_quantified_hints.sat").replace("import arith\n", ""))
if session.failures != 0
  raise "quantified arithmetic hints failed"
["generic_int", "generic_rat", "generic_real", "generic_nat", "partially_applied", "local_rule", "local_fixed_function", "polymorphic", "fixed_polymorphic", "concrete_domain", "irrelevant_hint", "fallback", "nested_domain", "mixed_hints"].each -> (name)
  th = session.theorems[name]
  expected = ["axiom:aggregate_nonneg_rat", "oracle:arith"]
  if name == "generic_int" || name == "generic_real"
    suffix = name == "generic_int" ? "int" : "real"
    expected = ["axiom:aggregate_nonneg_" + suffix, "oracle:arith"]
  if name == "generic_nat"
    expected = ["axiom:aggregate_lower_nat", "oracle:arith"]
  if name == "local_rule" || name == "local_fixed_function"
    expected = ["oracle:arith"]
  if ["polymorphic", "fixed_polymorphic", "concrete_domain", "nested_domain"].include?(name)
    expected = ["axiom:folded_nonneg", "oracle:arith"]
  if name == "fallback"
    expected = ["axiom:aggregate_nonneg_rat"]
  if name == "mixed_hints"
    expected = ["axiom:aggregate_nonneg_rat", "axiom:stored_zero", "oracle:arith"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "quantified hint missing, open or has unexpected trust: " + name
["missing_guard", "wrong_range", "wrong_sign", "wrong_function", "missing_index", "wrong_sum", "weak_nat", "wrong_partial", "escaped_premise", "unsupplied", "fixed_type", "conditional_leak"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_quantified_hints_failure.sat", [name]))
  if session.failures != before + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid quantified hint: " + name
<< "Quantified arithmetic hints passed"

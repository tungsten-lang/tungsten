use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
session.run_import("real")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["pow_two.real", "abs_cases.real", "abs_sq.real"]))
lemmas = ["sq_sqrt", "sqrt_eq_of_mul_self", "sqrt_sq", "sqrt_sq_eq_abs", "sqrt_pos", "sqrt_le_sqrt", "sqrt_lt_sqrt", "sqrt_mul", "sqrt_le_iff", "le_sqrt_iff", "sqrt_lt_iff", "lt_sqrt_iff"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/realx.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/square_matching.sat").replace("import realx\n", ""))
if session.failures != 0
  raise "square matching failed"
examples = ["upper_product", "lower_product", "root_product", "product_root", "product_abs", "exact_root", "applied_root", "opaque_argument", "opposite_spelling", "guarded", "quantified", "function_argument", "capture_safe", "nat_argument", "int_argument", "rat_argument", "alias_root", "local_square", "local_product", "automatic_assumption", "automatic_quantified", "automatic_guard", "closed_literal"]
examples.each -> (name)
  th = session.theorems[name]
  expected = ["oracle:ring"]
  if ["upper_product", "lower_product", "root_product", "product_abs", "exact_root", "applied_root", "alias_root"].include?(name)
    expected = ["oracle:arith", "oracle:ring"]
  if name == "opaque_argument"
    expected = ["axiom:accept_square", "oracle:ring"]
  if name == "opposite_spelling"
    expected = ["axiom:accept_product", "oracle:ring"]
  if name == "closed_literal"
    expected = []
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "square matching proof missing, open or has unexpected trust: " + name
bad = ["unequal_factors", "wrong_exponent", "wrong_sign", "missing_domain", "missing_guard", "wrong_guard", "capture_leak", "wrong_argument", "no_cancellation", "no_global_hint", "automatic_wrong_factor", "automatic_wrong_guard"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/square_matching_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "square matching accepted an invalid application: " + name
<< "square matching passed"

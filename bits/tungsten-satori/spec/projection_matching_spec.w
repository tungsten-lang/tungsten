use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_list", "sum_below", "mem_nil", "mem_cons"]))
session.run_import("real")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below_zero", "sum_below_succ", "sum_nonneg.real", "pow_two.real", "abs_cases.real", "abs_sq.real", "le_abs_self.real"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list_sum.sat", ["list_sum.nil", "list_sum.cons", "list_sum.closed", "sum_list_nonneg.real"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/realx.sat", ["sq_sqrt", "sqrt_eq_of_mul_self", "sqrt_sq_eq_abs", "sqrt_le_sqrt", "sqrt_mul", "sqrt_le_iff", "abs_le_sqrt_mul"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/quadratic.sat", ["quadratic_form.bound.real"]))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/cauchy.sat", ["list_sum.weighted_square_expand.real", "list_sum.weighted_cauchy.real", "list_sum.cauchy.real", "sum_below.weighted_square_expand.real", "sum_below.weighted_cauchy.real", "sum_below.cauchy.real"]))
lemmas = ["list_sum.weighted_cauchy_sqrt.real", "list_sum.cauchy_sqrt.real", "list_sum.weighted_add_square_expand.real", "list_sum.weighted_minkowski.real", "list_sum.minkowski.real", "sum_below.weighted_cauchy_sqrt.real", "sum_below.cauchy_sqrt.real", "sum_below.weighted_add_square_expand.real", "sum_below.weighted_minkowski.real", "sum_below.minkowski.real", "norm2.add_le", "norm2.sub_le"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/euclidean.sat", lemmas))
session.run_source(File.read("bits/tungsten-satori/spec/projection_matching.sat").replace("import euclidean\n", ""))
if session.failures != 0
  raise "projection matching failed"
examples = ["triangle", "reverse_triangle", "boxed_triangle", "function_field", "applied_triangle", "exact_triangle", "bare_triangle", "partially_applied"]
examples.each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
    raise "projection proof missing, open or has unexpected trust: " + name
session.run_source("opaque unknown_pair : complex_pair → complex_pair → complex_pair\n")
session.run_source(proof_declarations("bits/tungsten-satori/spec/projection_matching_failure.sat", ["wrong_add"]))
if session.failures != 0
  raise "projection rejection setup failed"
bad = ["wrong_constructor", "wrong_field", "strict_triangle", "opaque_constructor", "wrong_apply", "wrong_partial", "wrong_function_field"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/projection_matching_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "projection matching accepted an invalid proof: " + name
session.run_source("axiom supplied_triangle (a b c d : ℝ) : sqrt ((a+c)^2+(b+d)^2) ≤ sqrt (a^2+b^2)+sqrt (c^2+d^2)\n+ marked_triangle (z w : complex_pair) : magnitude (add_pair z w) ≤ magnitude z + magnitude w\n  exact supplied_triangle\n")
th = session.theorems["marked_triangle"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:supplied_triangle"]
  raise "projection matching lost the supplied theorem's tag"
<< "projection matching passed"

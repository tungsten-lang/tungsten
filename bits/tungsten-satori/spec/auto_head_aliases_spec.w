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
defs = ["inner", "norm", "norm_again", "norm_third", "weighted_norm", "plane_norm", "norm_total", "identity"]
examples = ["range_triangle", "weighted_triangle", "chain_triangle", "left_alias", "right_alias", "both_aliases", "polymorphic_alias", "repeated_alias", "reverse_alias"]
session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_head_aliases.sat", defs + examples))
if session.failures != 0
  raise "auto head aliases failed"
examples.each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
    raise "auto alias missing, open or has unexpected provenance: " + name
session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_head_aliases_failure.sat", ["offset_norm"]))
session.run_source("opaque unknown_norm : ℝ → ℝ → ℝ\n")
if session.failures != 0
  raise "auto alias negative-test setup failed"
bad = ["wrong_vector", "missing_weight_sign", "strict_triangle", "wrong_direction", "misleading_definition", "opaque_definition", "local_shadow", "false_alias_equality"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_head_aliases_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto accepted an invalid alias proof: " + name
session.run_source("axiom false_alias_weight (n : ℕ) (w : ℕ → ℝ) : ∀ i < n, 0 ≤ w i\n+ marked_alias (n : ℕ) (w f g : ℕ → ℝ) : weighted_norm n w (fun i => f i+g i) ≤ weighted_norm n w f + weighted_norm n w g\n  have hw := false_alias_weight n w\n  auto\n")
th = session.theorems["marked_alias"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_alias_weight", "oracle:arith", "oracle:ring"]
  raise "auto alias lost its supplied weight assumption"
<< "auto head aliases passed"

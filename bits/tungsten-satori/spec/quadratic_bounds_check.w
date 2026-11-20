use ../lib/satori
use proof_source

# Replay each numeric family independently: all four together exceed the
# interpreter's memory limit. This selects the actual source declarations,
# including their proof bodies; no imported quadratic theorem is cached.
-> check_quadratic_family(suffix)
  cases = {
    "real" => [["remove_square", "product_lower", "negative_factors", "zero_weight", "negative_left_value"], ["invalid_remove_square", "invalid_product_sign"]],
    "rat" => [["remove_strict_square", "product_upper", "opposite_factors_upper"], ["invalid_upper_weight"]],
    "int" => [["signed_square_order", "negative_bound"], ["invalid_square_forward", "invalid_one_square"]],
    "nat" => [["natural_square_order", "natural_product_lower", "natural_product_upper"], ["invalid_strict_bound", "invalid_strict_product", "invalid_weight_changed"]]
  }
  family = cases[suffix]
  lemmas = ["le_of_mul_self_le_mul_self", "lt_of_mul_self_lt_mul_self", "mul_self_le_mul_self_iff", "mul_self_lt_mul_self_iff", "le_mul_of_le_mul_self", "mul_le_of_mul_self_le"].map -> (name) name + "." + suffix
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_import("order")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/quadratic.sat", lemmas))
  session.run_source(proof_declarations("bits/tungsten-satori/spec/quadratic_bounds.sat", family[0]))
  if session.failures != 0
    raise "quadratic bounds failed for " + suffix
  (lemmas + family[0]).each -> (name)
    th = session.theorems[name]
    expected = ["oracle:arith"]
    if suffix == "nat"
      expected = ["oracle:arith", "oracle:ring"]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "quadratic bound is missing, open or has unexpected trust: " + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/quadratic_bounds_failure.sat", family[1]))
  if session.failures != family[1].size
    raise "quadratic bounds accepted an invalid goal for " + suffix
  if suffix != "nat"
    forms = {
      "int" => ["odd_cross", "wrong_cross"],
      "rat" => ["singular_allowed", "missing_diagonal"],
      "real" => ["ellipticity", "missing_determinant"]
    }[suffix]
    rules = ["quadratic_form.nonneg_of_pos." + suffix, "quadratic_form.nonneg." + suffix]
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/quadratic_form.sat", rules))
    session.run_source(proof_declarations("bits/tungsten-satori/spec/quadratic_form.sat", [forms[0]]))
    (rules + [forms[0]]).each -> (name)
      th = session.theorems[name]
      if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
        raise "binary quadratic form is missing, open or has unexpected trust: " + name
    before = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/quadratic_form_failure.sat", [forms[1]]))
    if session.failures != before + 1 || session.theorems[forms[1]] != nil
      raise "accepted invalid binary form: " + forms[1]
  << "Quadratic bounds passed: " + suffix

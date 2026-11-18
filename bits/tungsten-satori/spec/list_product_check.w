use ../lib/satori
use proof_source

-> check_product_family(suffix)
  cases = {
    "generic" => [["memberwise_product", "product_map", "multiplicative_invariant", "empty_product"], ["invalid_product_congruence", "invalid_empty_invariant"]],
    "real" => [["real_nonnegative", "real_bernoulli", "append_product"], ["invalid_signed_bernoulli"]],
    "rat" => [["rational_comparison", "zero_increments", "lsum_nonneg", "prod_ge_one_add_sum"], ["invalid_product_sign"]],
    "int" => [["integer_unit_bound", "integer_bernoulli", "multiply_products"], ["invalid_unit_bound"]],
    "nat" => [["natural_comparison", "natural_bernoulli", "repeated_factors", "zero_factor"], ["invalid_strict_bound", "invalid_empty_product", "invalid_multiplicity"]]
  }
  family = cases[suffix]
  generic = ["list_product.nil", "list_product.cons", "list_product.congr", "list_product.map", "list_product.closed"]
  lemmas = ["prod_list_nonneg", "prod_list_one_le", "prod_list_le", "prod_list_append", "prod_list_mul", "one_add_sum_list_le_prod_list"].map -> (name) name + "." + suffix
  if suffix == "generic"
    lemmas = []
  else
    generic = ["list_product.nil", "list_product.cons", "list_product.closed"]
  session = Session.new(".")
  session.quiet = true
  # Separate generic proofs from numeric families to keep each source replay
  # within interpreter memory limits, without relying on a warm module cache.
  session.no_cache = true
  session.run_import("core")
  # Select only the list operators and simp rule these proofs use, rather
  # than replaying unrelated prelude inductions in every numeric shard.
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["append", "map", "sum_list", "prod_list", "mem_cons", "mem_nil"]))
  if suffix == "nat"
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/order.sat", ["nl_cross.nat"]))
  if suffix == "rat"
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/logic.sat", ["or_self"]))
  if suffix != "generic" && suffix != "nat"
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/list_sum.sat", ["list_sum.nil", "list_sum.cons", "list_sum.closed"]))
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/list_sum.sat", ["sum_list_nonneg." + suffix]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list_product.sat", generic + lemmas))
  if suffix == "rat"
    session.run_source(proof_declarations("bits/tungsten-satori/spec/list_product_patterns.sat", ["nonneg_all", "lsum", "lprod1"]))
  session.run_source(proof_declarations("bits/tungsten-satori/spec/list_product_patterns.sat", family[0]))
  if session.failures != 0
    raise "list product proofs failed for " + suffix
  (generic + lemmas + family[0]).each -> (name)
    expected = ["oracle:arith"]
    if generic.include?(name) || name.starts_with?("prod_list_nonneg.") || ["memberwise_product", "product_map", "multiplicative_invariant", "empty_product", "real_nonnegative", "repeated_factors", "zero_factor"].include?(name)
      expected = []
    elsif name.starts_with?("prod_list_append.") || name.starts_with?("prod_list_mul.") || ["append_product", "multiply_products"].include?(name)
      expected = ["oracle:ring"]
    elsif suffix == "nat"
      expected = ["oracle:arith", "oracle:ring"]
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "list product theorem is missing, open or has unexpected trust: " + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/list_product_patterns_failure.sat", family[1]))
  if session.failures != family[1].size
    raise "list product proofs accepted an invalid goal for " + suffix
  << "List product patterns passed: " + suffix

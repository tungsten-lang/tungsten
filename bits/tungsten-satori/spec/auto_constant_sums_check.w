use ../lib/satori
use proof_source

-> check_auto_constant_sums(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  casts = []
  if suffix != "nat"
    casts = ["cast_add", "cast_one", "cast_succ"].map -> (name) name + "." + suffix
    if suffix != "int"
      casts = ["cast_add.int", "int_cast_add." + suffix] + casts
  rules = ["sum_const", "sum_below.eq_const", "sum_below.eq_one"].map -> (name) name + "." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", casts + ["sum_below_zero", "sum_below_succ", "sum_below.congr"] + rules))
  names = ["direct", "termwise", "offset", "larger", "one", "alias", "reverse", "empty"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_constant_sums.sat", [suffix + "_uniform"] + names.map(-> (name) suffix + "_" + name)))
  if session.failures != 0
    raise "automatic constant sums failed: " + suffix
  names.each -> (name)
    th = session.theorems[suffix + "_" + name]
    expected = ["oracle:arith", "oracle:ring"]
    if ["direct", "alias"].include?(name)
      expected = ["oracle:ring"]
    if name == "empty"
      expected = []
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "constant sum missing, open or has unexpected trust: " + name
  ["sum_below.eq_const", "sum_below.eq_one"].each -> (name)
    th = session.theorems[name + "." + suffix]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
      raise "constant sum library rule missing, open or has unexpected trust"
  ["missing", "wrong_value", "short_range", "upper_only", "lower_only", "wrong_length", "one_missing"].each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_constant_sums_failure.sat", [suffix + "_" + name]))
    if session.failures != previous + 1 || session.theorems[suffix + "_" + name] != nil
      raise "constant sum accepted a missing premise or wrong value/range: " + name
  if suffix == "real"
    previous = session.failures
    session.run_source("opaque marked_f : ℕ → ℝ\naxiom marked_constant : ∀ i, marked_f i = 2\n+ marked_total (n : ℕ) : (∑ i < n, marked_f i) = (n : ℝ)*2 := by auto \[marked_constant]\n")
    th = session.theorems["marked_total"]
    if session.failures != previous || th == nil || th.hyps.size != 0 || th.tags != ["axiom:marked_constant", "oracle:ring"]
      raise "constant sum lost its pointwise assumption tag"
  << "Automatic constant sums passed: " + suffix

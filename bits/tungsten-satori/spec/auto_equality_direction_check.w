use ../lib/satori
use proof_source

-> check_auto_equality_direction(suffix)
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
  rules = ["sum_const", "sum_below.eq_const", "sum_below.eq_one", "sum_add", "sum_const_mul", "sum_below.scale", "sum_below.add", "sum_below.zero", "sum_below.eq_zero"].map -> (name) name + "." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", casts + ["sum_below_zero", "sum_below_succ", "sum_below.congr"] + rules))
  names = ["constant", "one", "scale", "add", "larger", "zero"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_equality_direction.sat", names.map(-> (name) suffix + "_" + name)))
  if session.failures != 0
    raise "automatic equality direction failed: " + suffix
  names.each -> (name)
    th = session.theorems[suffix + "_" + name]
    expected = ["oracle:arith", "oracle:ring"]
    if name == "zero"
      expected = ["oracle:arith"]
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "equality direction missing, open or has unexpected trust: " + name
  ["missing", "wrong_value", "short_range", "upper_only", "cycle"].each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_equality_direction_failure.sat", [suffix + "_" + name]))
    if session.failures != previous + 1 || session.theorems[suffix + "_" + name] != nil
      raise "equality direction accepted a missing premise or wrong value/range: " + name
  if suffix == "real"
    previous = session.failures
    session.run_source("opaque marked_f : ℕ → ℝ\naxiom marked_constant : ∀ i, marked_f i = 2\n+ marked_total (n : ℕ) : (n : ℝ)*2 = (∑ i < n, marked_f i) := by auto \[marked_constant]\n")
    th = session.theorems["marked_total"]
    if session.failures != previous || th == nil || th.hyps.size != 0 || th.tags != ["axiom:marked_constant", "oracle:arith", "oracle:ring"]
      raise "equality direction lost its pointwise assumption tag"
  << "Automatic equality direction passed: " + suffix

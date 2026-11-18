use ../lib/satori
use proof_source

-> check_auto_sums(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  if suffix != "nat"
    casts = ["cast_add.int"]
    if suffix == "rat" || suffix == "real"
      casts = casts + ["int_cast_add." + suffix, "cast_add." + suffix]
    casts = casts + ["cast_one." + suffix, "cast_succ." + suffix]
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", casts))
  arithmetic = ["sum_const_mul", "sum_mul_const", "sum_add", "sum_le", "sum_nonneg"].map -> (name) name + "." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below_zero", "sum_below_succ", "le_induction.nat"] + arithmetic))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["split", "const_le", "le_const", "mono"].map -> (name) "sum_below." + name + "." + suffix))
  good = ["sum_split", "sum_scaled", "sum_nonneg_all", "sum_lo", "sum_hi", "sum_mono", "add", "right_scale", "pointwise", "guarded", "alias_chain", "alias_exact", "alias_apply"]
  names = good.map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sums.sat", [suffix + "_shifted", suffix + "_scaled", suffix + "_scaled_again"] + names))
  if session.failures != 0
    raise "automatic sum examples failed: " + suffix
  good.each -> (name)
    th = session.theorems[suffix + "_" + name]
    expected = ["oracle:arith"]
    if ["sum_split", "sum_scaled", "add", "right_scale", "alias_chain", "alias_exact", "alias_apply"].include?(name)
      expected = ["oracle:ring"]
    if suffix == "nat" && name == "sum_nonneg_all"
      expected = []
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "automatic sum missing, open or has unexpected trust: " + suffix + "_" + name
  ["missing_range", "wrong_upper", "wrong_shift", "wrong_scale", "cycle"].each -> (name)
    full = suffix + "_" + name
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sums_failure.sat", [full]))
    if session.failures != previous + 1 || session.theorems[full] != nil
      raise "automatic sums accepted invalid guard, formula or cycle: " + full
  << "Automatic finite sums passed: " + suffix

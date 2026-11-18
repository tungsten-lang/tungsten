use ../lib/satori
use proof_source

-> check_auto_sum_aliases(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  rules = ["sum_below_zero", "sum_below_succ", "sum_below.congr"]
  casts = []
  if suffix != "generic"
    rules = rules + ["sum_const", "sum_const_mul", "sum_below.eq_const", "sum_below.scale", "sum_below.le_const"].map -> (name) name + "." + suffix
    if suffix != "nat"
      casts = ["cast_add", "cast_one", "cast_succ"].map -> (name) name + "." + suffix
      if suffix != "int"
        casts = ["cast_add.int", "int_cast_add." + suffix] + casts
      rules.push("sum_telescope." + suffix)
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", casts + rules))
  names = ["constant", "scale", "bound", "hyp", "quantified", "nested"]
  if suffix == "generic"
    names = ["congr", "reverse"]
  elsif suffix != "nat"
    names.push("telescope")
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_aliases.sat", ["accum", "wrapped"] + names.map(-> (name) suffix + "_" + name)))
  if session.failures != 0
    raise "automatic custom sums failed: " + suffix
  names.each -> (name)
    th = session.theorems[suffix + "_" + name]
    expected = ["oracle:arith", "oracle:ring"]
    if name == "bound" || suffix == "generic"
      expected = ["oracle:arith"]
    if name == "telescope"
      expected = ["oracle:ring"]
    if ["hyp", "quantified"].include?(name)
      expected = []
    if th == nil || th.hyps.size != 0 || th.tags != expected
      raise "custom sum missing, open or has unexpected trust: " + name
  bad = ["missing", "wrong_value", "short_range", "wrong_guard", "cycle"].map -> (name) suffix + "_" + name
  if suffix == "generic"
    bad = ["generic_missing"]
  if suffix == "nat"
    bad.push("natural_telescope")
  if suffix == "int"
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_aliases_failure.sat", ["bad_seed", "bad_index", "bad_weight"]))
    bad = bad + ["bad_seed_reject", "bad_index_reject", "bad_weight_reject"]
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_aliases_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "custom sum accepted a wrong definition, guard or cyclic premise: " + name
  if suffix == "real"
    session.run_source("opaque marked_f : ℕ → ℕ → ℝ\naxiom marked_inner : ∀ j, accum (marked_f j) 3 = 2\n")
    previous = session.failures
    session.run_source("+ unsupplied (n : ℕ) : accum (fun j => accum (marked_f j) 3) n = (n : ℝ)*2 := by auto\n")
    if session.failures != previous + 1 || session.theorems["unsupplied"] != nil
      raise "custom sum used an unsupplied axiom"
    session.run_source("+ marked_hint (n : ℕ) : accum (fun j => accum (marked_f j) 3) n = (n : ℝ)*2 := by auto \[marked_inner]\n+ marked_local (n : ℕ) : accum (fun j => accum (marked_f j) 3) n = (n : ℝ)*2 := by have h := marked_inner; auto \[h]\n")
    ["marked_hint", "marked_local"].each -> (name)
      th = session.theorems[name]
      if th == nil || th.hyps.size != 0 || th.tags != ["axiom:marked_inner", "oracle:arith", "oracle:ring"]
        raise "custom sum lost a supplied or local proof's hypothesis tag"
  << "Automatic custom sums passed: " + suffix

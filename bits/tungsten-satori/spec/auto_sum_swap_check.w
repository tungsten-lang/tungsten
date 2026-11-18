use ../lib/satori
use proof_source

-> check_auto_sum_swap(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  basics = ["sum_below_zero", "sum_below_succ", "sum_below.congr", "sum_add." + suffix, "sum_below.zero." + suffix, "sum_below.swap." + suffix]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", basics))
  good = ["direct", "reverse", "weighted", "triple", "alias"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_swap.sat", [suffix + "_rows", suffix + "_cols"] + good))
  if session.failures != 0
    raise "automatic sum interchange failed: " + suffix
  (good + ["sum_below.swap." + suffix]).each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:ring"]
      raise "automatic sum interchange missing, open or has unexpected trust: " + name
  bad = ["wrong_bounds", "wrong_indices", "wrong_function", "dependent_bound", "extra_row", "strict"].map -> (name) suffix + "_" + name
  if suffix == "nat"
    bad.push("generic_swap")
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_swap_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "automatic interchange accepted invalid indices, bounds or types: " + name
  << "Automatic sum interchange passed: " + suffix

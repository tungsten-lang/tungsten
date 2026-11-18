use ../lib/satori
use proof_source

-> check_auto_sum_front(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", ["sum_below_zero", "sum_below_succ", "sum_below.succ_front." + suffix]))
  good = ["direct", "alias", "product", "nested"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_front.sat", [suffix + "_tail"] + good))
  if session.failures != 0
    raise "automatic first summand failed: " + suffix
  (good + ["sum_below.succ_front." + suffix]).each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:ring"]
      raise "automatic first summand missing, open or has unexpected trust: " + name
  bad = ["wrong_shift", "wrong_first", "extra_tail", "missing_term"].map -> (name) suffix + "_" + name
  if suffix == "nat"
    bad.push("generic")
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_sum_front_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "automatic first summand accepted invalid terms or ranges: " + name
  << "Automatic first summand passed: " + suffix

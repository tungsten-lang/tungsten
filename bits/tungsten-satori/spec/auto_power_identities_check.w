use ../lib/satori
use proof_source

-> check_auto_power_identities(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  rules = ["pow_add", "pow_mul", "mul_pow"].map -> (name) name + "." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/power.sat", rules))
  good = ["add", "add_reverse", "multiply", "multiply_reverse", "product", "product_reverse", "expression_base", "expression_exponent"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_power_identities.sat", good))
  if session.failures != 0
    raise "automatic power identities failed: " + suffix
  (rules + good).each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:ring"]
      raise "power identity missing, open or has unexpected trust: " + name
  bad = ["sum_base", "wrong_add", "wrong_multiply", "wrong_index", "wrong_nesting"].map -> (name) suffix + "_" + name
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_power_identities_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "automatic power identities accepted false algebra: " + name
  << "Automatic power identities passed: " + suffix

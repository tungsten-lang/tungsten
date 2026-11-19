use ../lib/satori
use proof_source

-> check_auto_registration(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("prelude")
  registered = session.auto_rules.size
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/quadratic.sat", ["quadratic_form.bound." + suffix]))
  good = ["form", "product", "guarded"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_registration.sat", good))
  if session.failures != 0 || session.auto_rules.size != registered + 1
    raise "registered quadratic rules failed: " + suffix
  good.each -> (name)
    th = session.theorems[name]
    expected = name == suffix + "_product" ? ["oracle:arith", "oracle:ring"] : ["oracle:arith"]
    if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != expected
      raise "registered proof missing, open or has unexpected trust: " + name
  ["missing", "strict", "wrong_cross", "missing_guard"].each -> (part)
    name = suffix + "_" + part
    before = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_registration_failure.sat", [name]))
    if session.failures != before + 1 || session.theorems[name] != nil
      raise "registered rule accepted a false or unguarded claim: " + name
  << "Registered quadratic rules passed: " + suffix

use ../lib/satori
use proof_source

-> check_ring_definitions(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("prelude")
  defs = ["blend", "nested", "fourth", "pair", "total", "pick"].map -> (name) name + "." + suffix
  good = ["nested", "fourth", "projection", "list_head", "opaque_arguments", "closed_condition"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/ring_definitions.sat", defs + good))
  if session.failures != 0
    raise "ring definitions failed: " + suffix
  good.each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:ring"]
      raise "ring identity missing, open or unexpectedly trusted: " + name
  ["wrong_nested", "wrong_fourth", "wrong_projection", "wrong_tail", "wrong_argument", "missing_condition"].each -> (part)
    name = suffix + "_" + part
    before = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/ring_definitions_failure.sat", [name]))
    if session.failures != before+1 || session.theorems[name] != nil
      raise "ring definitions accepted an invalid identity: " + name
  << "Ring definitions passed: " + suffix

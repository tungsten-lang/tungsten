use ../lib/satori
use proof_source

-> check_auto_enum_list(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("prelude")
  defs = ["token"] + (["count", "twice", "scaled", "coordinates", "wrong_last"].map -> (name) name + "." + suffix)
  good = ["twice", "reverse", "scaled", "first", "second", "sum"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_enum_list.sat", defs + good))
  if session.failures != 0
    raise "automatic enum list identities failed: " + suffix
  good.each -> (name)
    tags = ["oracle:ring"]
    if name.ends_with?("_first") || name.ends_with?("_second")
      tags = []
    if name.ends_with?("_reverse") || name.ends_with?("_sum")
      tags = ["oracle:arith"]
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != tags
      raise "enum list identity missing, open or unexpectedly trusted: " + name
  bad = ["wrong_factor", "last_case", "wrong_projection", "wrong_initial", "wrong_list", "wrong_scale"].map -> (name) suffix + "_" + name
  bad.each -> (name)
    before = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_enum_list_failure.sat", [name]))
    if session.failures != before+1 || session.theorems[name] != nil
      raise "enum list induction accepted an invalid premise: " + name
  << "Enum list identities passed: " + suffix

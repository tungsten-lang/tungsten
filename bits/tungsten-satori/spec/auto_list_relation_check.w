use ../lib/satori
use proof_source

-> check_auto_list_relation(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("prelude")
  rule = session.theorems["list.recursive_relation"]
  if rule == nil || rule.hyps.size != 0 || rule.tags != []
    raise "recursive relation pattern is not kernel-only"
  defs = []
  good = []
  bad = []
  if suffix == "generic"
    defs = ["traverse_l", "traverse_r"]
    ["l", "r"].each -> (kind)
      ["equivalent", "projection", "commutes", "commutes_reverse", "paired", "guarded"].each -> (name)
        good.push(kind + "_" + name)
      ["no_step", "point_step", "wrong_update", "missing_guard", "wrong_initial", "missing_second"].each -> (name)
        bad.push(kind + "_" + name)
  else
    defs = ["accumulate", "weighted", "subtotal"].map -> (name) name + "." + suffix
    good = ["total", "reverse", "weighted", "paired", "four_coordinates"].map -> (name) suffix + "_" + name
    bad = ["missing_initial", "wrong_scale", "wrong_coordinate", "wrong_base", "wrong_state"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_list_relation.sat", defs + good))
  if session.failures != 0
    raise "automatic list relation failed: " + suffix
  tags = suffix == "generic" ? [] : ["oracle:ring"]
  good.each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != tags
      raise "list relation missing, open or unexpectedly trusted: " + name
  # Exercise the complete conjunction before ordinary auto can split it.
  name = suffix == "generic" ? "l_projection" : suffix + "_four_coordinates"
  body = session.d.spec_all(session.theorems[name]).concl
  fixes = tm_frees(body).map -> (v) [v.name, v]
  prover = Prover.new(session)
  result = prover.auto_list_relation(Goal.new(fixes, [], body), [], [24, 4])
  if result == nil || !tm_eq(result.concl, body) || result.hyps.size != 0 || result.tags != tags || prover.goals.size != 0
    raise "whole list relation was not checked independently: " + suffix
  bad.each -> (name)
    before = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_list_relation_failure.sat", [name]))
    if session.failures != before+1 || session.theorems[name] != nil
      raise "list relation accepted an invalid base, step or coordinate: " + name
  << "Automatic list relations passed: " + suffix

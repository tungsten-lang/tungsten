use ../lib/satori
use proof_source

-> check_auto_compound_squares(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("prelude")
  parts = ["pair_zero", "weighted_three", "nonnegative", "ordered_squares", "shifted", "fresh_names", "nested_base"]
  if suffix != "nat"
    parts.push("amgm")
  good = parts.map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_compound_squares.sat", good))
  if session.failures != 0
    raise "compound square automation failed: " + suffix
  good.each -> (name)
    tags = ["oracle:arith"]
    if suffix == "nat" || name.ends_with?("_nonnegative")
      tags = ["oracle:arith", "oracle:ring"]
    if name == "nat_nonnegative"
      tags = []
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != tags
      raise "compound proof missing, open, has a fresh variable or wrong trust: " + name
  ["negative_weight", "zero_weight", "strict_bound", "wrong_component", "nonzero_total", "inconsistent_substitution"].each -> (part)
    name = suffix + "_" + part
    before = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_compound_squares_failure.sat", [name]))
    if session.failures != before+1 || session.theorems[name] != nil
      raise "compound abstraction accepted an invalid implication: " + name
  << "Compound square proofs passed: " + suffix

use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/nat.sat", ["min", "max"]))
["real", "rat"].each -> (suffix)
  prerequisites = ["min_cases", "max_cases", "min_le_left", "min_le_right", "le_max_left", "le_max_right"].map -> (name) name + "." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", prerequisites))
  lemmas = ["convex_interval.affine", "concave_interval.affine", "convex_interval.square"].map -> (name) name + "." + suffix
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/convex.sat", ["concave_interval." + suffix, "convex_interval." + suffix] + lemmas))
  examples = ["convex_affine", "concave_affine", "square", "negative_slope", "weighted_square"].map -> (name) suffix + "_" + name
  session.run_source(proof_declarations("bits/tungsten-satori/spec/convex_instances.sat", examples))
  if session.failures != (suffix == "real" ? 0 : 4)
    raise "polynomial convexity proofs failed: " + suffix
  (lemmas + examples).each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
      raise "polynomial convexity theorem missing, open or has unexpected trust: " + name
  ["concave_square", "negative_square", "strict_square", "missing_square_sign"].each -> (base)
    name = suffix + "_" + base
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/convex_instances_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "polynomial convexity accepted an invalid bound: " + name
<< "Polynomial convexity passed"

use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("logic")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["append", "map", "mem_cons", "mem_nil"]))
lemmas = []
["list.foldl", "list.foldr"].each -> (base)
  ["nil", "cons", "append", "map", "invariant_on", "invariant", "invariants", "commutes", "preserves", "fixed"].each -> (suffix)
    lemmas.push(base + "_" + suffix)
session.run_source(proof_declarations("bits/tungsten-satori/prelude/fold.sat", ["list.foldl", "list.foldr"] + lemmas))
session.run_file("bits/tungsten-satori/spec/list_fold.sat")
session.run_file("bits/tungsten-satori/spec/fold_transfer.sat")
if session.failures != 0
  raise "list fold proofs failed"
lemmas.each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags.size != 0
    raise "fold theorem is missing, open or has unexpected trust: " + name
["left_history", "right_history", "left_swap", "right_swap", "left_projection", "right_projection", "left_unchanged", "right_unchanged", "left_fixed", "right_fixed", "paired_right", "run_equivalent"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags.size != 0
    raise "fold application is missing, open or has unexpected trust: " + name
["step_inv", "run_inv"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "transfer invariant has unexpected trust: " + name
session.run_file("bits/tungsten-satori/spec/list_fold_failure.sat")
if session.failures != 10
  raise "list folds accepted an invalid order or missing premise"
<< "List fold patterns passed"

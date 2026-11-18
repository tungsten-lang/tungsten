use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
good = ["kesten_contracts", "distance_positive", "net_bound_eps", "small_product", "epsilon_small", "chord_contradiction"]
session.run_source(proof_declarations("bits/tungsten-satori/examples/compact_inequalities.sat", good))
if session.failures != 0
  raise "compact inequality examples failed"
good.each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith"]
    raise "compact inequality missing, open or has unexpected trust: " + name
<< "Compact inequality examples passed"

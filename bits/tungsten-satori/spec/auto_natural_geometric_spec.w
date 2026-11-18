use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
rules = ["recurrence.geometric_sum.nat", "recurrence.geometric_sum_of_pos.nat"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/recurrence.sat", rules))
good = ["generic", "reverse", "positive", "four", "eight", "defined", "quantified"].map -> (name) "nat_geometric_" + name
session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_natural_geometric.sat", ["partial_nat"] + good))
if session.failures != 0
  raise "automatic natural geometric sums failed"
(rules + good).each -> (name)
  expected = ["oracle:ring"]
  if name == "recurrence.geometric_sum_of_pos.nat" || ["nat_geometric_reverse", "nat_geometric_positive", "nat_geometric_quantified"].include?(name)
    expected = ["oracle:arith", "oracle:ring"]
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "natural geometric sum missing, open or has unexpected trust: " + name
bad = ["missing_base", "missing_step", "wrong_index", "wrong_coefficient", "missing_positive", "zero_rate", "wrong_base"].map -> (name) "nat_geometric_" + name
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_natural_geometric_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "natural geometric sum accepted missing premises or a wrong index: " + name
session.run_source("opaque marked_natural : ℕ → ℕ\naxiom natural_base : marked_natural 0 = 0\naxiom natural_step : ∀ i, marked_natural (i+1) = marked_natural i+4^i\n")
previous = session.failures
session.run_source("+ natural_unsupplied (n : ℕ) : 3*marked_natural n+1 = 4^n := by auto\n")
if session.failures != previous + 1 || session.theorems["natural_unsupplied"] != nil
  raise "natural geometric sum used unsupplied axioms"
session.run_source("+ natural_marked (n : ℕ) : 3*marked_natural n+1 = 4^n := by auto \[natural_base, natural_step]\n+ natural_local (n : ℕ) : 3*marked_natural n+1 = 4^n\n  have base := natural_base\n  have step := natural_step\n  auto \[base, step]\n")
["natural_marked", "natural_local"].each -> (name)
  th = session.theorems[name]
  expected = ["axiom:natural_base", "axiom:natural_step", "oracle:ring"]
  if name == "natural_marked"
    expected = ["axiom:natural_base", "axiom:natural_step", "oracle:arith", "oracle:ring"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "natural geometric sum lost explicit or local axiom tags: " + name
<< "Automatic natural geometric sums passed"

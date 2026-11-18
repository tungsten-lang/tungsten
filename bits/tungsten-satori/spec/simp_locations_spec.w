use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("logic")
session.run_source(File.read("bits/tungsten-satori/spec/simp_locations.sat").replace("import logic\n", ""))
if session.failures != 0
  raise "simplifier locations failed"
["both", "hypotheses_only", "unchanged", "no_hypotheses", "contradiction", "selected_rule", "reverse_rule", "all_rules", "under_binder", "branch_local", "unfold_everywhere", "named_locations", "goal_location", "continued_product", "marked", "named_rule", "simplified_conditions", "marked_rule"].each -> (name)
  th = session.theorems[name]
  expected = []
  if name == "continued_product"
    expected = ["oracle:ring"]
  if name == "marked"
    expected = ["axiom:location_source"]
  if name == "marked_rule"
    expected = ["axiom:location_rewrite"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "location theorem missing, open or has unexpected trust: " + name
["missing_fact", "unrelated", "unsupplied_rule", "missing_location", "mixed_location", "mixed_goal", "unknown_rule", "branch_escape", "unclosed", "plain_no_progress"].each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/simp_locations_failure.sat", [name]))
  if session.failures != before + 1 || session.theorems[name] != nil
    raise "simplifier accepted an invalid location or proof: " + name
<< "Simplifier locations passed"

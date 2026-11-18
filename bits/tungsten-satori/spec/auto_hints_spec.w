use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
session.run_import("real")
exp_rules = ["exp_tangent_le", "one_add_lt_exp", "exp_tangent_lt", "exp_weighted_jensen_lt", "exp_midpoint_lt"]
session.run_source(proof_declarations("bits/tungsten-satori/prelude/exp_convex.sat", exp_rules))
session.run_source("opaque marked : ℝ → Prop\nopaque finished : ℝ → Prop\nopaque wrapped : α → Prop\n")
assumptions = ["mark_nonneg", "mark_negative", "mark_finish", "finish_loop", "mark_two_sides", "finish_all", "wrap_rule"]
examples = ["direct", "arithmetic", "retry", "chain", "loop_then_rule", "partial", "introduced", "paired", "alternative", "local_rule", "aesop_hint", "tauto_hint", "empty_hints", "exp_library", "exp_sign", "exp_support", "retry_partial", "quantified_premise", "poly_real", "poly_nat"]
session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_hints.sat", assumptions + examples))
if session.failures != 0
  raise "auto with library hints failed"
examples.each -> (name)
  th = session.theorems[name]
  expected = ["axiom:mark_nonneg"]
  if ["chain", "loop_then_rule", "introduced", "paired"].include?(name)
    expected = ["axiom:mark_finish", "axiom:mark_nonneg"]
  if ["local_rule", "empty_hints"].include?(name)
    expected = []
  if name == "quantified_premise"
    expected = ["axiom:finish_all", "axiom:mark_nonneg"]
  if ["poly_real", "poly_nat"].include?(name)
    expected = ["axiom:wrap_rule"]
  if name == "arithmetic"
    expected = ["axiom:mark_nonneg", "oracle:arith"]
  if ["exp_library", "exp_sign", "exp_support"].include?(name)
    expected = ["oracle:arith", "oracle:ring"]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "auto hint theorem missing, open or has unexpected trust: " + name
bad = ["missing_premise", "wrong_sign", "missing_chain", "loop_only", "unfinished_pair", "wrong_instance", "false_exp", "ignored_bare", "ignored_unknown", "trailing_tokens", "missing_bracket", "empty_entry", "open_partial", "leaked_universal", "wrong_type"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_hints_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto hints accepted an invalid or malformed proof: " + name
<< "auto library hints passed"

use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
session.run_import("real")
prerequisites = ["mul_le_mul_of_nonneg_right", "mul_lt_mul_of_pos_right", "one_div_pos", "one_div_nonneg", "mul_div_cancel", "mul_div_cancel_right", "div_le_div_of_nonneg_right", "div_lt_div_of_pos_right", "div_le_iff", "le_div_iff", "div_lt_iff", "lt_div_iff", "div_le_div_iff", "div_lt_div_iff"].map -> (name) name + ".real"
session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", prerequisites))
session.run_source(proof_declarations("bits/tungsten-satori/prelude/realx.sat", ["sqrt_pos", "one_div_sqrt_le_div_iff", "one_div_sqrt_lt_div_iff", "div_le_one_div_sqrt_iff"]))
session.run_source("opaque iff_left : α → Prop\nopaque iff_right : α → Prop\nopaque iff_last : α → Prop\n")
rules = ["iff_rule", "iff_next", "iff_guarded", "iff_interleaved", "iff_guard_is_left"]
examples = ["forward", "backward", "natural", "chained", "reverse_chain", "guarded", "partial_guard", "interleaved", "same_guard", "introduced", "whole_equivalence", "under_forall", "root_lower", "root_certificate", "root_strict", "root_upper", "fresh_binder", "fixed_local_type"]
session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_iff.sat", rules + examples))
if session.failures != 0
  raise "auto iff directions failed"
examples.each -> (name)
  expected = ["axiom:iff_rule"]
  if ["chained", "reverse_chain"].include?(name)
    expected = ["axiom:iff_next", "axiom:iff_rule"]
  if name == "guarded"
    expected = ["axiom:iff_guarded", "oracle:arith"]
  if name == "partial_guard"
    expected = ["axiom:iff_guarded"]
  if name == "interleaved"
    expected = ["axiom:iff_interleaved"]
  if name == "same_guard"
    expected = ["axiom:iff_guard_is_left"]
  if name.starts_with?("root_")
    expected = ["oracle:arith", "oracle:ring"]
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags != expected
    raise "auto iff theorem missing, open or has unexpected trust: " + name
bad = ["no_premise", "no_guard", "false_guard", "interleaved_no_guard", "circular_guard", "wrong_instance", "wrong_type", "leaked_binder", "root_no_sign", "root_zero_denominator", "root_weak_to_strict", "root_wrong_direction"]
bad.each -> (name)
  previous = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_iff_failure.sat", [name]))
  if session.failures != previous + 1 || session.theorems[name] != nil
    raise "auto iff accepted an invalid guard, binder or direction: " + name
<< "auto iff directions passed"

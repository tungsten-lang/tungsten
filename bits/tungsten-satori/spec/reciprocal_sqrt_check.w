use ../lib/satori
use proof_source

-> check_reciprocal_sqrt(suffix)
  session = Session.new(".")
  session.quiet = true
  session.no_cache = true
  session.run_import("core")
  if suffix == "real"
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/list.sat", ["sum_below"]))
    session.run_import("real")
  prerequisites = ["mul_le_mul_of_nonneg_right", "mul_lt_mul_of_pos_right", "one_div_pos", "one_div_nonneg", "mul_div_cancel", "mul_div_cancel_right", "div_le_div_of_nonneg_right", "div_lt_div_of_pos_right", "div_le_iff", "le_div_iff", "div_lt_iff", "lt_div_iff"].map -> (name) name + "." + suffix
  lemmas = ["div_le_div_iff." + suffix, "div_lt_div_iff." + suffix]
  session.run_source(proof_declarations("bits/tungsten-satori/prelude/arith.sat", prerequisites + lemmas))
  examples = ["le_forward", "le_backward", "lt_forward", "lt_backward", "negative_numerators"].map -> (name) suffix + "_" + name
  bad = ["negative_denominator", "zero_denominator", "weak_to_strict"].map -> (name) suffix + "_" + name
  if suffix == "real"
    roots = ["one_div_sqrt_le_div_iff", "one_div_sqrt_lt_div_iff", "div_le_one_div_sqrt_iff", "div_lt_one_div_sqrt_iff"]
    session.run_source(proof_declarations("bits/tungsten-satori/prelude/realx.sat", ["sqrt_pos"] + roots))
    lemmas = lemmas + roots
    ["lower", "upper"].each -> (direction)
      ["le", "lt"].each -> (cmp)
        ["forward", "backward"].each -> (way) examples.push(direction + "_" + cmp + "_" + way)
    examples = examples + ["equality_lower", "equality_upper", "zero_numerator"]
    bad = bad + ["missing_numerator_sign", "zero_radicand", "zero_root_denominator", "negative_numerator", "strict_lower_equality", "strict_upper_equality"]
  session.run_source(proof_declarations("bits/tungsten-satori/spec/reciprocal_sqrt.sat", examples))
  if session.failures != 0
    raise "fraction/root comparisons failed: " + suffix
  (lemmas + examples).each -> (name)
    th = session.theorems[name]
    if th == nil || th.hyps.size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
      raise "fraction/root theorem missing, open or has unexpected trust: " + name
  bad.each -> (name)
    previous = session.failures
    session.run_source(proof_declarations("bits/tungsten-satori/spec/reciprocal_sqrt_failure.sat", [name]))
    if session.failures != previous + 1 || session.theorems[name] != nil
      raise "fraction/root comparison accepted an invalid sign or strictness: " + name
  if suffix == "real"
    session.run_source("axiom false_root_polynomial (B m c : ℝ) : c*c ≤ m*m*B\n+ marked_root (B m c : ℝ) (hB : 0 < B) (hm : 0 ≤ m) (hc : 0 < c) : 1/sqrt B ≤ m/c := (one_div_sqrt_le_div_iff B m c hB hm hc).mpr (false_root_polynomial B m c)\n")
    th = session.theorems["marked_root"]
    if th == nil || th.hyps.size != 0 || th.tags != ["axiom:false_root_polynomial", "oracle:arith", "oracle:ring"]
      raise "root comparison lost its polynomial assumption tag"
  << "Fraction/root comparisons passed: " + suffix

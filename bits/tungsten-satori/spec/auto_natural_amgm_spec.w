use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/auto_natural_amgm.sat")
if session.failures != 0
  raise "natural AM–GM failed"
names = ["two_mul_le_add_sq.nat", "natural_square", "natural_power", "renamed_bound", "compound_product", "compound_power", "reversed_product", "reversed_sum", "shifted_inputs", "function_inputs", "added_bound", "strict_margin", "subtraction_inputs"]
names.each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || tm_frees(th.concl).size != 0 || th.tags != ["oracle:arith", "oracle:ring"]
    raise "natural AM–GM missing, open or has unexpected trust: " + name
bad = ["excessive_factor", "strict_equality", "missing_square", "wrong_direction", "compound_excess", "compound_strict", "false_shift", "mismatched_functions", "missing_margin", "unrelated_square"]
bad.each -> (name)
  before = session.failures
  session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_natural_amgm_failure.sat", [name]))
  if session.failures != before + 1 || session.theorems[name] != nil
    raise "natural AM–GM accepted a false inequality: " + name
# Reusing the library name must not make an unproved axiom an implicit rule.
session.run_source("axiom two_mul_le_add_sq.nat (a b : ℕ) : 3*a*b ≤ a^2+b^2\n")
before = session.failures
session.run_source("+ poisoned_square (a b : ℕ) : 3*a*b ≤ a^2+b^2 := by auto\n")
if session.failures != before + 1 || session.theorems["poisoned_square"] != nil
  raise "auto silently selected a named square axiom"
session.run_source("+ explicit_square (a b : ℕ) : 3*a*b ≤ a^2+b^2 := by auto \[two_mul_le_add_sq.nat]\n")
th = session.theorems["explicit_square"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:two_mul_le_add_sq.nat"]
  raise "explicit square axiom lost its dependency"
<< "Natural AM–GM passed"

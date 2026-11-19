use ../lib/satori
use proof_source

s = Session.new(".")
s.quiet = true
s.no_cache = true
s.run_import("core")
examples = "bits/tungsten-satori/examples/premise_selection.sat"
s.run_source(proof_declarations(examples, ["lit"]))
s.run_source(proof_declarations(examples, ["sum_lit"]))
if s.failures != 1 || s.theorems["sum_lit"] != nil
  raise "proof unexpectedly succeeded before the induction lemma"
s.run_source(proof_declarations(examples, ["lantern", "sum_lit"]))
th = s.theorems["sum_lit"]
if s.failures != 1 || th == nil || th.tags.size != 0 || th.hyps.size != 0
  raise "unregistered induction lemma did not close the instantiated goal"

s.run_source("+ missing_base (n : ℕ) (step : ∀ j : ℕ, lit j → lit (succ j)) : lit n := by auto\n")
if s.failures != 2 || s.theorems["missing_base"] != nil
  raise "selected lemma dropped its base case"

cases = "bits/tungsten-satori/spec/auto_selection_failure.sat"
s.run_source(proof_declarations(cases, ["marked", "seed", "via_seed", "via_previous", "blue", "admitted", "red"]))
if s.failures != 2
  raise "selection trust fixtures failed"
["excluded_axiom", "excluded_sorry", "unfinished", "excluded_failure"].each -> (name)
  before = s.failures
  s.run_source(proof_declarations(cases, [name]))
  if s.failures != before + 1 || s.theorems[name] != nil
    raise "auto accepted " + name
# All candidates share the conclusion symbol. Only the last uses the symbol
# in the local hypothesis, and it must survive the eight-candidate cutoff.
s.run_source("opaque beacon : ℕ → Prop\nopaque spark : ℕ → Prop\n")
before = s.failures
i = 0
while i < 10
  s.run_source("+ distractor" + i.to_s + " (n : ℕ) (h : False) : beacon n := by contradiction\n")
  i += 1
s.run_source("+ z_bridge (n : ℕ) (h : spark n) (f : ∀ m : ℕ, spark m → beacon m) : beacon n := f n h\n")
x = mk_var("x", ty_nat)
pred = ty_fun(ty_nat, ty_bool)
hyp = mk_app_raw(s.k.mk_const("spark", pred), x)
target = mk_app_raw(s.k.mk_const("beacon", pred), x)
choices = s.selected_premises(Goal.new([["x", x]], [["h", hyp]], target))
if s.failures != before || choices.size != 8 || choices[0] != s.theorems["z_bridge"]
  raise "context did not rank the relevant lemma in the bounded shortlist"
<< "Premise selection passed"

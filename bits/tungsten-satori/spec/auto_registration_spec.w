use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
registered = session.auto_rules.size
session.run_source(File.read("bits/tungsten-satori/spec/auto_registration_library.sat"))
if session.failures != 0 || session.auto_rules.size != registered + 2
  raise "local rules were not registered"
if session.auto_rules["classical_pattern"].tags != ["oracle:sat"]
  raise "checked SAT registration lost its dependency"
session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_registration_local.sat", ["registered_use"]))
if session.failures != 0 || session.theorems["registered_use"].tags != ["oracle:arith"]
  raise "local conjunction registration failed"

k = session.k
th = session.theorems["registered_use"]
fixes = []
["orchid", "maple", "willow"].each -> (name)
  v = mk_var(name, ty_rat)
  fixes.push([name, v])
  th = k.spec(v, th)
parts = dest_binop(th.concl, "⇒")
goal = Goal.new(fixes, [["q", parts[0]]], parts[1])
prover = Prover.new(session)
ref = GoalRef.new(goal, nil, 0)
prover.goals = [ref]
choices = prover.auto_registered_hints(goal)
if choices.size != 1
  raise "registered conjunction was not indexed by its bound"
proof = prover.auto_hint_proof(goal, choices, [], [24, 4], [])
if proof == nil || prover.fit(ref, proof).tags != ["oracle:arith"]
  raise "renamed registered bound failed"
if prover.auto_hint_proof(goal, choices, [], [0, 0], []) != nil
  raise "registered search ignored exhausted fuel"
if prover.auto_hint_proof(goal, choices, [], [24, 4], [goal.concl]) != nil
  raise "registered search ignored a cycle"
if prover.goals.size != 1 || prover.goals[0] != ref || ref.thm != nil
  raise "detached registered search changed the caller"

# The index must not reuse a replaced declaration, even if already populated.
original = session.theorems["registered_pair"]
poison = k.new_axiom("replacement", original.concl, false)
session.add_theorem("registered_pair", poison)
if prover.auto_registered_hints(goal).size != 0
  raise "shadowing inherited an old registration"
session.add_theorem("renamed_pair", original)
session.register_auto_rule("renamed_pair", original)
if prover.auto_registered_hints(goal).size != 1
  raise "a later registration did not invalidate the index"

# Failed attributes must leave no theorem, definition, or registration behind.
session.run_source("axiom untrusted : False\n")
bad = [
  ["bad_axiom", "@\[auto] axiom bad_axiom : False\n"],
  ["bad_def", "@\[auto] def bad_def : ℕ := 1\n"],
  ["bad_sorry", "@\[auto] + bad_sorry : False\n  sorry\n"],
  ["bad_trust", "@\[auto] + bad_trust : False\n  exact untrusted\n"],
  ["bad_proof", "@\[auto] + bad_proof : False\n  assumption\n"]]
bad.each -> (entry)
  before = session.failures
  session.run_source(entry[1])
  if session.failures != before + 1 || session.theorems[entry[0]] != nil || session.auto_rules[entry[0]] != nil || k.defs[entry[0]] != nil
    raise "invalid registration changed the session: " + entry[0]

v = mk_var("free", ty_rat)
[k.refl(v), k.assume(goal.concl), poison].each -> (invalid)
  rejected = false
  begin
    session.register_auto_rule("invalid", invalid)
  rescue e
    rejected = true
  if !rejected || session.auto_rules["invalid"] != nil
    raise "registration accepted an open or untrusted rule"

# Polymorphic and equivalence entries are selected by structure, not names.
session.run_source("@\[auto] + universal_identity (x : α) : x = x\n  rfl\n@\[auto] + swap_iff (P Q : Prop) (h : P ↔ Q) : Q ↔ P\n  auto\n")
eq_goal = Goal.new([["free", v]], [], k.eq_tm(v, v))
if !prover.auto_registered_hints(eq_goal).any?(-> (rule) tm_eq(rule.concl, session.theorems["universal_identity"].concl))
  raise "polymorphic registration was not selected"
prop = mk_var("proposition", ty_bool)
if prover.auto_registered_hints(Goal.new([], [], prop)).size < 2
  raise "equivalence directions were not indexed"
<< "Auto registration policy, selection and state passed"

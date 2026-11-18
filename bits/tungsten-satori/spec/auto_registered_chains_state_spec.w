use ../lib/satori
use proof_source

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
source = File.read("bits/tungsten-satori/spec/auto_registration_library.sat").gsub("registered_pair", "orchid_bound")
session.run_source(source)
session.run_source(proof_declarations("bits/tungsten-satori/spec/auto_registered_chains.sat", ["rat_scaled"]))
if session.failures != 0 || session.theorems["rat_scaled"].tags != ["oracle:arith"]
  raise "renamed conjunction did not supply an arithmetic bound"
k = session.k
th = session.theorems["rat_scaled"]
fixes = []
["elm", "larch", "oak", "pine"].each -> (name)
  v = mk_var(name, ty_rat)
  fixes.push([name, v])
  th = k.spec(v, th)
hyps = []
parts = dest_binop(th.concl, "⇒")
while parts != nil
  hyps.push(["h" + hyps.size.to_s, parts[0]])
  th = session.d.undisch(th)
  parts = dest_binop(th.concl, "⇒")
goal = Goal.new(fixes, hyps, th.concl)
ref = GoalRef.new(goal, nil, 0)
prover = Prover.new(session)
prover.goals = [ref]
proof = prover.auto_registered_arithmetic(goal, [], [24, 4])
if proof == nil || prover.fit(ref, proof).tags != ["oracle:arith"]
  raise "detached registered arithmetic failed"
if prover.auto_registered_arithmetic(goal, [], [0, 0]) != nil
  raise "registered arithmetic ignored exhausted fuel"
if prover.auto_registered_arithmetic(Goal.new(fixes, [hyps[1]], goal.concl), [], [24, 4]) != nil
  raise "a provisional arithmetic bound escaped without its guard"
large = mk_apps(k.mk_const("+", ty_funs([ty_rat, ty_rat], ty_rat)), [fixes[0][1], fixes[1][1]])
8.times -> (_)
  large = mk_apps(k.mk_const("+", ty_funs([ty_rat, ty_rat], ty_rat)), [large, large])
if prover.auto_registered_arithmetic(goal.with_concl(k.eq_tm(large, large)), [], [24, 4]) != nil
  raise "registered arithmetic ignored its goal-size limit"
original = session.theorems["orchid_bound"]
session.add_theorem("orchid_bound", k.new_axiom("poison", original.concl, false))
if prover.auto_registered_arithmetic(goal, [], [24, 4]) != nil
  raise "registered arithmetic used a shadowed rule"
session.add_theorem("maple_bound", original)
session.register_auto_rule("maple_bound", original)
if prover.auto_registered_arithmetic(goal, [], [24, 4]) == nil
  raise "registered arithmetic missed a later registration"
if prover.goals.size != 1 || prover.goals[0] != ref || ref.thm != nil
  raise "detached registered arithmetic changed the caller"
<< "Registered arithmetic state and selection passed"

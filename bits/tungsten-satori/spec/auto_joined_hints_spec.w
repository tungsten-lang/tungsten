use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_source("opaque left_value : ℚ → ℚ\nopaque right_value : ℚ → ℚ\naxiom guarded_pair (a b : ℚ) (hb : 0 < b) (hab : a ≤ b) : left_value a ≤ right_value b\n")
k = session.k
prover = Prover.new(session)
x = mk_var("x", ty_rat)
y = mk_var("y", ty_rat)
left = mk_app(k.mk_const("left_value", ty_fun(ty_rat, ty_rat)), x)
right = mk_app(k.mk_const("right_value", ty_fun(ty_rat, ty_rat)), y)
le = k.mk_const("≤", ty_funs([ty_rat, ty_rat], ty_bool))
goal = Goal.new([["x", x], ["y", y]], [], mk_apps(le, [left, right]))
hint = session.theorems["guarded_pair"]
instances = prover.auto_hint_instances(goal, [hint], [left, right])
expected = k.spec(y, k.spec(x, hint))
if instances.size != 1 || !tm_eq(instances[0].concl, expected.concl) || instances[0].tags != ["axiom:guarded_pair"] || instances[0].hyps.size != 0
  raise "independent operand matches lost a guard or an axiom tag"
if prover.auto_hint_instances(goal, [hint], [left]).size != 0
  raise "joined hint invented its missing operand"
if prover.auto_hint_instances(goal, [hint], [left, right], true).size != 0
  raise "joined hint changed left-only matching"
# The instantiated implication is a candidate; its guards still need proofs.
session.run_source("+ guarded (a b c : ℚ) (hb : 0 < b) (hab : a ≤ b) : left_value a+c ≤ right_value b+c := by auto \[guarded_pair]\n")
if session.failures != 0 || session.theorems["guarded"] == nil
  raise "guarded pair did not prove its arithmetic consequence"
before = session.failures
session.run_source("+ missing_guard (a b c : ℚ) (hb : 0 < b) : left_value a+c ≤ right_value b+c := by auto \[guarded_pair]\n")
if session.failures != before+1 || session.theorems["missing_guard"] != nil
  raise "joined operand hint bypassed a guard"
<< "Joined operand hint checks passed"

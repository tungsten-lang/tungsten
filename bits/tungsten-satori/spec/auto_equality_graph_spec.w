use ../lib/satori

session = Session.new(".")
k = session.k
prover = Prover.new(session)
a = mk_var("a", ty_nat)
b = mk_var("b", ty_nat)
c = mk_var("c", ty_nat)
facts = [k.assume(k.eq_tm(a, b)), k.assume(k.eq_tm(b, c))]
graph = prover.auto_equality_graph(facts)
forward = prover.auto_equal(a, c, facts, 16, graph)
backward = prover.auto_equal(c, a, facts, 16, graph)
if forward == nil || backward == nil || forward.hyps.size != 2 || backward.hyps.size != 2 || forward.tags != [] || !tm_eq(forward.concl, k.eq_tm(a, c)) || !tm_eq(backward.concl, k.eq_tm(c, a))
  raise "indexed equality paths lost their endpoints or assumptions"
f = mk_var("f", ty_fun(ty_nat, ty_nat))
congruent = prover.auto_equal(mk_app(f, a), mk_app(f, c), facts, 16, graph)
if congruent == nil || congruent.hyps.size != 2 || !tm_eq(congruent.concl, k.eq_tm(mk_app(f, a), mk_app(f, c)))
  raise "indexed equality failed application congruence"
# Aa and BB collide under the term-name hash; their edges must stay distinct.
x = mk_var("Aa", ty_nat)
y = mk_var("BB", ty_nat)
if x.h != y.h || tm_eq(x, y)
  raise "equality graph collision fixture is invalid"
collisions = [k.assume(k.eq_tm(x, a)), k.assume(k.eq_tm(y, b))]
collision_graph = prover.auto_equality_graph(collisions)
if prover.auto_equal(x, b, collisions, 16, collision_graph) != nil || prover.auto_equal(x, a, collisions, 16, collision_graph) == nil
  raise "indexed equality confused colliding terms"
if prover.auto_equal(a, c, [], 16) != nil || prover.auto_equal(a, c, facts, 0, graph) != nil
  raise "indexed equality leaked facts or ignored its depth limit"
# A partial application can change the head of a proposition.
pred_ty = ty_fun(ty_nat, ty_bool)
p = mk_var("P", ty_fun(ty_nat, pred_ty))
q = mk_var("Q", pred_ty)
pa = mk_app(p, a)
known = k.assume(mk_app(pa, b))
equal = k.assume(k.eq_tm(pa, q))
guard = mk_app(q, b)
result = mk_var("result", ty_bool)
[k.bin("⇒", guard, result), k.neg_tm(guard)].each -> (rule)
  context = [known, equal, k.assume(rule)]
  expected = dest_unop(rule, "¬") == nil ? result : k.false_tm
  if !prover.auto_equal_mp(context) || !tm_eq(context[3].concl, expected) || context[3].hyps.size != 3 || context[3].tags != []
    raise "equality matching skipped a rule with a rewritable function head"
<< "Indexed equality graph checks passed"

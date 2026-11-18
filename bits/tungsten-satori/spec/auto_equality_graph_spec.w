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
<< "Indexed equality graph checks passed"

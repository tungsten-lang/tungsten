use ../lib/satori

session = Session.new(".")
k = session.k
k.declare_const("p", ty_bool)
k.declare_const("q", ty_bool)
p = k.mk_const("p", ty_bool)
q = k.mk_const("q", ty_bool)
[q, k.neg_tm(q)].each -> (known)
  prover = Prover.new(session)
  budget = [12]
  goal = Goal.new([], [["known", known]], p)
  result = prover.auto_classical(goal, [k.assume(known)], [q], [], 3, budget, false)
  if result != nil || budget[0] != 12
    raise "auto split an atom whose truth value was already known"
<< "Known atom splitting bounds passed"

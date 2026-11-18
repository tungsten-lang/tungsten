use ../lib/satori

session = Session.new(".")
k = session.k
prover = Prover.new(session)
i = mk_var("i", ty_nat)
n = mk_var("stage", ty_nat)
r = mk_var("coefficient", ty_nat)
f = mk_var("f", ty_fun(ty_nat, ty_nat))
plus = k.mk_const("+", ty_funs([ty_nat, ty_nat], ty_nat))
times = k.mk_const("*", ty_funs([ty_nat, ty_nat], ty_nat))
zero = mk_lit(0, ty_nat)
one = mk_lit(1, ty_nat)
current = mk_app(f, i)
successor_value = mk_app(f, mk_apps(plus, [i, one]))
step = k.eq_tm(successor_value, mk_apps(times, [r, current]))
terms = [r, n, zero, one, mk_app(f, n), mk_app(f, zero), mk_apps(times, [r, r])]
[step, k.eq_tm(mk_apps(times, [r, current]), successor_value)].each -> (equation)
  selected = prover.auto_recurrence_witnesses(mk_lam(i, equation), terms)
  if selected == nil || selected.size != 3 || !selected.any?(-> (term) tm_eq(term, n)) || !selected.any?(-> (term) tm_eq(term, zero)) || !selected.any?(-> (term) tm_eq(term, one)) || selected.any?(-> (term) tm_eq(term, r))
    raise "recurrence instantiation confused coefficients with sequence indices"
# A compound index already used by the sequence is relevant too.
compound = mk_apps(times, [r, r])
selected = prover.auto_recurrence_witnesses(mk_lam(i, step), [mk_app(f, compound)])
if selected == nil || selected.size != 1 || !tm_eq(selected[0], compound)
  raise "recurrence instantiation lost a compound sequence index"
if prover.auto_recurrence_witnesses(mk_lam(i, step), [r, n]) != nil
  raise "recurrence specialization changed a context with no sequence applications"
if prover.auto_recurrence_witnesses(mk_lam(i, k.eq_tm(successor_value, r)), terms) != nil
  raise "recurrence specialization classified a non-recurrent equation"
family = mk_var("family", ty_funs([ty_nat, ty_nat], ty_nat))
a = mk_var("a", ty_nat)
b = mk_var("b", ty_nat)
fstep = k.eq_tm(mk_apps(family, [mk_apps(plus, [i, one]), a]), mk_apps(plus, [mk_apps(family, [i, a]), one]))
selected = prover.auto_recurrence_witnesses(mk_lam(i, fstep), [mk_apps(family, [n, a]), mk_apps(family, [r, b])])
if selected == nil || selected.size != 1 || !tm_eq(selected[0], n)
  raise "recurrence instantiation confused different sequence parameters"
<< "Recurrence witness selection checks passed"

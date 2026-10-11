use ../lib/satori
k = KKernel.new
p = mk_var("p", ty_bool)
q = mk_var("q", ty_bool)
th = k.disch(p, k.assume(p))
<< th.to_s
pq = k.conj(k.assume(p), k.assume(q))
<< pq.to_s
x = mk_var("x", ty_nat)
plus = k.mk_const("+", ty_funs([ty_nat, ty_nat], ty_nat))
t = mk_apps(plus, [mk_nat(2), mk_nat(40)])
<< k.compute(t).to_s
lt = k.mk_const("<", ty_funs([ty_int, ty_int], ty_bool))
<< k.compute(mk_apps(lt, [mk_lit(-3, ty_int), mk_lit(2, ty_int)])).to_s
g = k.gen(x, k.refl(x))
<< g.to_s
<< k.spec(mk_nat(7), g).to_s
lst = k.inductive("list", ["a"], [["nil", []], ["cons", [ty_var("a"), ty_con("list", [ty_var("a")])]]])
<< k.axiom("list_induct").to_s
<< k.axiom("list_rec_cons").to_s
<< k.axiom("list_inj_cons").to_s
y = mk_var("y", ty_int)
z = mk_var("z", ty_int)
pl = k.mk_const("+", ty_funs([ty_int, ty_int], ty_int))
ml = k.mk_const("*", ty_funs([ty_int, ty_int], ty_int))
l = mk_apps(ml, [mk_apps(pl, [y, z]), mk_apps(pl, [y, z])])
r = mk_apps(pl, [mk_apps(ml, [y, y]), mk_apps(pl, [mk_apps(ml, [mk_lit(2, ty_int), mk_apps(ml, [y, z])]), mk_apps(ml, [z, z])])])
<< k.ring_eq(l, r).to_s
<< k.ring_eq(l, r).tags.join(",")

use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("prelude")
session.run_file("bits/tungsten-satori/spec/simp_binder_names.sat")
if session.failures != 0
  raise "binder-name proof failed"
proof = session.theorems["binder_guard"]
if proof == nil || proof.hyps.size != 0 || proof.tags != ["axiom:conditional"]
  raise "binder-name proof has wrong dependencies"
k = session.k
d = session.d
x = mk_var("x", ty_rat)
z = mk_var("z", ty_rat)
f = k.mk_const("f", ty_fun(ty_rat, ty_rat))
p = k.mk_const("p", ty_fun(ty_rat, ty_bool))
term = mk_lam(x, mk_app(f, x))
fixed = k.assume(k.eq_tm(mk_app(f, x), mk_lit(Q_ZERO, ty_rat)))
rule = make_rule(d, fixed, "fixed")
# A fact at one free x cannot rewrite every bound x. Exercise direct and cached
# rule collections, then add a rule after the binder-name cache has been used.
simplifiers = [Simp.new(d, [rule]), Simp.new(d, [], {"f": [rule]}), Simp.new(d, [], nil, [rule])]
late = Simp.new(d, [])
late.simp_conv(term)
late.add_rule(rule)
simplifiers.push(late)
simplifiers.each -> (simplifier)
  conversion = simplifier.simp_conv(term)
  if !tm_eq(conversion.concl, k.eq_tm(term, term)) || conversion.hyps.size != 0 || conversion.tags.size != 0
    raise "a fixed local equation escaped under a binder"
conditional = make_rule(d, session.theorems["conditional"], "conditional")
simplifier = Simp.new(d, [conditional])
simplifier.simp_conv(term)
simplifier.hyp_rules = [k.assume(mk_app(p, x))]
conversion = simplifier.simp_conv(term)
if !tm_eq(conversion.concl, k.eq_tm(term, term)) || conversion.hyps.size != 0 || conversion.tags.size != 0
  raise "a local guard escaped under a binder"
# A fixed free value on a rewrite's right side must remain free in the result.
body = k.eq_tm(mk_app(f, z), x)
all = k.quant("∀", z, body)
right_rule = make_rule(d, k.assume(all), "fixed right side")
conversion = Simp.new(d, [right_rule]).simp_conv(term)
expected = k.eq_tm(term, mk_lam(z, x))
if !tm_eq(conversion.concl, expected) || conversion.hyps.size != 1 || !tm_eq(conversion.hyps[0], all)
  raise "rewriting captured a fixed right-hand-side variable"
<< "Simplifier binder names passed"

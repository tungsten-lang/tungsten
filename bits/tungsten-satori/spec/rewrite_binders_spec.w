use ../lib/satori

+ RewriteTestSession
  ro :k, :d
  -> new
    @k = KKernel.new
    @d = Derived.new(@k)

s = RewriteTestSession.new
k = s.k
prover = Prover.new(s)
a = mk_var("a", ty_nat)
y = mk_var("y", ty_nat)
z = mk_var("z", ty_nat)
eq = k.eq_tm(a, y)
rule = make_rule(s.d, k.assume(eq), "h")
# The bound variable's hint is the same name as the free replacement.
body = k.eq_tm(a, y)
term = mk_lam(y, body)
expected = mk_lam(z, k.eq_tm(y, z))
goal = Goal.new([], [["h", eq]], k.eq_tm(term, expected))
conv = prover.rewrite_once(rule, term, goal)
if conv == nil
  raise "rw did not search beneath a binder"
sides = k.dest_eq(conv.concl)
if !tm_eq(sides[0], term) || !tm_eq(sides[1], expected)
  raise "rw captured a free replacement"
if conv.hyps.size != 1 || !tm_eq(conv.hyps[0], eq) || conv.tags.size != 0
  raise "rw lost its hypothesis or added a trust tag"
if !tm_closed_bound?(conv.concl)
  raise "rw produced a loose bound index"
# A pattern must not be instantiated at a dangling bound variable.
beta = k.gen(z, k.beta(mk_app(mk_lam(y, y), z)))
beta_rule = make_rule(s.d, beta, "beta")
loose = mk_app(mk_lam(y, y), mk_bnd(0, ty_nat))
simp = Simp.new(s.d, [beta_rule])
if prover.find_instance_with_simp(simp, beta_rule, loose) != nil
  raise "rw instantiated a pattern with a loose bound index"
# Traversal still finds an independent subterm beside a bound one.
pair = mk_var("pair", ty_funs([ty_nat, ty_nat], ty_nat))
mixed = mk_lam(y, mk_apps(pair, [y, a]))
conv = prover.rewrite_once(rule, mixed, goal)
want = mk_lam(z, mk_apps(pair, [z, y]))
if conv == nil || !tm_eq(k.dest_eq(conv.concl)[1], want)
  raise "rw skipped an independent sibling beneath a binder"
<< "Binder rewrite checks passed"

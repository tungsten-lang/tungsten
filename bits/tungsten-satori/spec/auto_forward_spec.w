use ../lib/satori

+ AutoTestSession
  ro :k, :d
  -> new
    @k = KKernel.new
    @d = Derived.new(@k)

s = AutoTestSession.new
k = s.k
p = mk_var("p", ty_bool)
q = mk_var("q", ty_bool)
r = mk_var("r", ty_bool)
eta_f = mk_var("f", ty_fun(ty_nat, ty_nat))
eta_x = mk_var("z", ty_nat)
eta_lambda = mk_lam(eta_x, mk_app(eta_f, eta_x))
eta_proof = s.d.eta_norm_opt(eta_lambda)
if eta_proof == nil || !tm_eq(k.dest_eq(eta_proof.concl)[1], eta_f)
  raise "eta conversion failed"
non_eta = mk_lam(eta_x, mk_app(eta_f, mk_app(eta_f, eta_x)))
if s.d.eta_norm_opt(non_eta) != nil
  raise "eta conversion removed a dependent argument"
context = k.bin("∧", p, k.bin("⇒", p, q))
goal = Goal.new([], [["h", context], ["k", k.bin("⇒", q, r)]], r)
prover = Prover.new(s)
th = prover.auto_forward(goal)
if th == nil || !tm_eq(th.concl, r) || th.hyps.size != 2
  raise "auto failed to derive an implication chain from a conjunction"
bad = Goal.new([], [["h", k.bin("⇒", p, q)]], q)
if prover.auto_forward(bad) != nil
  raise "auto derived an implication's conclusion without its premise"
contradiction = Goal.new([], [["h", k.bin("∧", p, k.neg_tm(p))]], r)
th = prover.auto_forward(contradiction)
if th == nil || !tm_eq(th.concl, r)
  raise "auto failed to derive a contradiction"
x = mk_var("x", ty_nat)
n = mk_var("n", ty_nat)
pred = mk_var("P", ty_fun(ty_nat, ty_bool))
conclusion = mk_app(pred, x)
universal = k.quant("∀", n, mk_app(pred, n))
quant_goal = Goal.new([["x", x]], [["h", k.bin("∧", universal, p)]], conclusion)
th = prover.auto_forward(quant_goal)
if th == nil || !tm_eq(th.concl, conclusion) || th.hyps.size != 1
  raise "auto failed to specialize a quantified conjunct"
a = mk_var("a", ty_nat)
b = mk_var("b", ty_nat)
c = mk_var("c", ty_nat)
ab = k.eq_tm(a, b)
bc = k.eq_tm(b, c)
equal_goal = Goal.new([], [["h", k.bin("∧", ab, bc)]], k.eq_tm(mk_app(pred, a), mk_app(pred, c)))
th = prover.auto_forward(equal_goal)
if th == nil || !tm_eq(th.concl, equal_goal.concl) || th.hyps.size != 1
  raise "auto failed to chain equalities under a function"
invalid_goal = Goal.new([], [["h", ab]], k.eq_tm(a, c))
if prover.auto_forward(invalid_goal) != nil
  raise "auto invented an equality"
subst_goal = Goal.new([], [["h", k.bin("∧", ab, mk_app(pred, a))]], mk_app(pred, b))
th = prover.auto_forward(subst_goal)
if th == nil || !tm_eq(th.concl, subst_goal.concl)
  raise "auto failed to substitute in a proposition"
apply_goal = Goal.new([], [["h", k.bin("∧", ab, mk_app(pred, a))], ["imp", k.bin("⇒", mk_app(pred, b), r)]], r)
th = prover.auto_forward(apply_goal)
if th == nil || !tm_eq(th.concl, r) || th.hyps.size != 2
  raise "auto failed to apply an implication after substitution"
chain_goal = Goal.new([], [["h", k.bin("∧", ab, mk_app(pred, a))], ["imp", k.bin("⇒", mk_app(pred, b), q)], ["next", k.bin("⇒", q, r)]], r)
th = prover.auto_forward(chain_goal)
if th == nil || !tm_eq(th.concl, r) || th.hyps.size != 3
  raise "auto failed to continue after an equality-based implication"
bad_apply = Goal.new([], [["h", k.bin("∧", ab, mk_app(pred, a))], ["imp", k.bin("⇒", mk_app(pred, c), r)]], r)
if prover.auto_forward(bad_apply) != nil
  raise "auto applied an implication to an unrelated premise"
eq_contra = Goal.new([], [["eq", ab], ["pos", mk_app(pred, a)], ["neg", k.neg_tm(mk_app(pred, b))]], r)
th = prover.auto_forward(eq_contra)
if th == nil || !tm_eq(th.concl, r) || th.hyps.size != 3
  raise "auto failed to find a contradiction after substitution"
bad_contra = Goal.new([], [["eq", ab], ["pos", mk_app(pred, a)], ["neg", k.neg_tm(mk_app(pred, c))]], r)
if prover.auto_forward(bad_contra) != nil
  raise "auto found a contradiction between unrelated propositions"
disjunction = k.bin("∨", p, q)
case_goal = Goal.new([], [["h", disjunction], ["hp", k.bin("⇒", p, r)], ["hq", k.bin("⇒", q, r)]], r)
th = prover.auto_forward(case_goal)
if th == nil || !tm_eq(th.concl, r) || th.hyps.size != 3
  raise "auto failed to prove both disjunction cases"
bad_case = Goal.new([], [["h", disjunction], ["hp", k.bin("⇒", p, r)]], r)
if prover.auto_forward(bad_case) != nil
  raise "auto accepted an unproved disjunction case"
exists_p = k.quant("∃", n, mk_app(pred, n))
exists_goal = Goal.new([["x", x]], [["h", mk_app(pred, x)]], exists_p)
th = prover.auto_forward(exists_goal)
if th == nil || !tm_eq(th.concl, exists_p) || th.hyps.size != 1
  raise "auto failed to supply an existing witness"
exists_both = k.quant("∃", n, k.bin("∧", mk_app(pred, n), q))
project_goal = Goal.new([], [["h", exists_both]], exists_p)
th = prover.auto_forward(project_goal)
if th == nil || !tm_eq(th.concl, exists_p) || th.hyps.size != 1 || !tm_eq(th.hyps[0], exists_both)
  raise "auto failed to eliminate and reuse an existential witness"
escape_goal = Goal.new([["x", x]], [["h", exists_p]], mk_app(pred, x))
if prover.auto_forward(escape_goal) != nil
  raise "auto allowed an existential witness to escape"
backward_goal = Goal.new([["x", x]], [["hx", mk_app(pred, x)], ["imp", k.bin("⇒", exists_p, r)]], r)
th = prover.auto_forward(backward_goal)
if th == nil || !tm_eq(th.concl, r) || th.hyps.size != 2
  raise "auto failed to construct an existential premise"
cycle_goal = Goal.new([], [["h", k.bin("⇒", p, q)], ["k", k.bin("⇒", q, p)]], q)
if prover.auto_forward(cycle_goal) != nil
  raise "auto proved a cyclic implication without a premise"
identity = k.quant("∀", n, k.bin("⇒", mk_app(pred, n), mk_app(pred, n)))
intro_goal = Goal.new([], [["h", k.bin("⇒", identity, r)]], r)
th = prover.auto_forward(intro_goal)
if th == nil || !tm_eq(th.concl, r) || th.hyps.size != 1
  raise "auto failed to introduce a quantified implication premise"
invalid_intro = Goal.new([], [["h", k.bin("⇒", universal, r)]], r)
if prover.auto_forward(invalid_intro) != nil
  raise "auto invented a universal premise"
double_neg = k.neg_tm(k.neg_tm(p))
classical_goal = Goal.new([], [["h", double_neg]], p)
th = prover.auto_forward(classical_goal)
if th == nil || !tm_eq(th.concl, p) || th.hyps.size != 1 || !tm_eq(th.hyps[0], double_neg)
  raise "auto failed to derive double negation"
not_pair = k.neg_tm(k.bin("∧", p, q))
de_morgan_goal = Goal.new([], [["h", not_pair]], k.bin("∨", k.neg_tm(p), k.neg_tm(q)))
th = prover.auto_forward(de_morgan_goal)
if th == nil || !tm_eq(th.concl, de_morgan_goal.concl) || th.hyps.size != 1 || !tm_eq(th.hyps[0], not_pair)
  raise "auto failed to derive De Morgan's law"
invalid_classical = Goal.new([], [], k.bin("∨", p, q))
if prover.auto_forward(invalid_classical) != nil
  raise "auto proved an invalid classical disjunction"
<< "auto forward reasoning passed"

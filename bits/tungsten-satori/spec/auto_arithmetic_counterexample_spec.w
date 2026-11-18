use ../lib/satori

session = Session.new(".")
prover = Prover.new(session)
d = mk_var("d", ty_int)
goal = Goal.new([["d", d]], [], session.k.eq_tm(d, d))
parse = -> (source) prover.elab_term(goal, lex_source(source)[0].toks, ty_bool)
goal = goal.with_concl(parse.call("d ≤ 0"))
fact = -> (source) session.k.assume(parse.call(source))

identity = fact.call("∀ x : ℤ, x + d = d + x")
if !prover.auto_arithmetic_counterexample(goal, [identity])
  raise "missed d = 1 with a universally true premise"
if prover.auto_arithmetic_counterexample(goal, [identity, fact.call("d < 0")])
  raise "counterexample ignored a premise"
# True at both universal probes, false at x = 2. Sampling cannot establish it.
if prover.auto_arithmetic_counterexample(goal, [fact.call("∀ x : ℤ, x * (x - 1) = 0")])
  raise "finite probes established a universal premise"
<< "Arithmetic counterexample checks passed"

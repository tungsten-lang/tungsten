use ../lib/satori

session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("logic")
session.run_file("bits/tungsten-satori/spec/local_binding.sat")
if session.failures != 0
  raise "local binding proofs failed"
# Compare the elaborated statement against a kernel term with explicit scope.
n = mk_var("n", ty_nat)
t = mk_var("t", ty_nat)
constant = mk_lam(t, n)
expected = mk_app(session.k.mk_const("∀", ty_fun(ty_fun(ty_nat, ty_bool), ty_bool)), mk_lam(n, session.k.eq_tm(constant, constant)))
th = session.theorems["let_keeps_outer"]
if !tm_eq(th.concl, expected) || th.hyps.size != 0 || th.tags.size != 0
  raise "saved outer variable was captured by a lambda"
session.run_source("axiom supplied : ∀ n : ℕ, n = 0\n+ retained (n : ℕ) : n+1 = 0\n  set t := n+1\n  exact supplied t\n")
th = session.theorems["retained"]
if th == nil || th.hyps.size != 0 || th.tags != ["axiom:supplied"]
  raise "set failed to discharge its definition or lost a dependency"
session.run_file("bits/tungsten-satori/spec/local_binding_failure.sat")
if session.failures != 9
  raise "local binding accepted an invalid proof"
<< "Local binding proofs passed"

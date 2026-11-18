use ../lib/satori

k = KKernel.new
d = Derived.new(k)
ty = ty_var("§a")
p = mk_var("?p", ty_fun(ty, ty_bool))
x = mk_var("?x", ty)
a = mk_var("a", ty_nat)
b = mk_var("b", ty_nat)
z = mk_var("z", ty_nat)
mt = Matcher.new({p.vkey => true, x.vkey => true}, {"§a" => true})
if !mt.bind(p, mk_lam(z, k.eq_tm(z, z)))
  raise "failed to bind a predicate argument"
pattern = mk_app(p, x)
result = mt.match_instantiated(d, pattern, k.eq_tm(a, a))
if result == nil || !tm_eq(result.tm[x.vkey], a) || !ty_eq(result.ty["§a"], ty_nat)
  raise "lambda matching failed to infer a term and retain its original variable key"
# Failure must not contaminate the matcher used by later alternatives.
if mt.match_instantiated(d, pattern, k.eq_tm(a, b)) != nil || mt.tm.size != 1
  raise "lambda matching accepted conflicting occurrences or changed the input matcher"
integer = mk_var("integer", ty_int)
if mt.match_instantiated(d, pattern, k.eq_tm(integer, integer)) != nil
  raise "lambda matching changed the supplied predicate's type"
# Replay the inferred substitution through kernel specialization and conversion.
th = k.gen(p, k.gen(x, k.disch(pattern, k.assume(pattern))))
th = k.inst_type(th, result.ty)
th = k.spec(result.tm[p.vkey], th)
th = k.spec(result.tm[x.vkey], th)
th = d.beta_norm_thm(th)
expected = k.bin("⇒", k.eq_tm(a, a), k.eq_tm(a, a))
if !tm_eq(th.concl, expected) || th.hyps.size != 0 || th.tags.size != 0
  raise "lambda match did not replay as a closed kernel proof"
# Exercise elaboration and proof replay as well as the matcher itself.
session = Session.new(".")
session.quiet = true
session.no_cache = true
session.run_import("core")
session.run_import("logic")
session.run_file("bits/tungsten-satori/spec/application_lambda.sat")
if session.failures != 0
  raise "lambda application proofs failed"
["stored_implication", "stored_forall", "stored_negation"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags.size != 0
    raise "stored predicate application is missing, open or has unexpected trust: " + name
["lambda_alias", "lambda_alias_applied", "partial_projection", "mixed_binders", "explicit_premise", "exposed_implication", "exposed_negation", "exposed_forall", "exposed_have", "exposed_not_have", "exposed_apply", "exposed_apply_open", "exposed_twice", "partial_unused", "alias_under_exists", "alias_under_forall", "exposed_apply_true", "alias_proof_argument", "alias_projection_argument", "alias_quantified_argument"].each -> (name)
  th = session.theorems[name]
  if th == nil || th.hyps.size != 0 || th.tags.size != 0
    raise "application proof is missing, open or has unexpected trust: " + name
session.run_source("axiom marked_functions : ∀ n : ℕ, True → False\n+ marked_exposed : False := expose (fun n => True → False) marked_functions 0 trivial\n")
marked = session.theorems["marked_exposed"]
if marked == nil || marked.hyps.size != 0 || marked.tags != ["axiom:marked_functions"]
  raise "resumed application lost its assumption tag"
session.run_source("axiom marked_alias : ∃ x : ℕ, x = successor_alias 0\n+ marked_alias_transport : ∃ x : ℕ, x = 1 := marked_alias\n")
marked = session.theorems["marked_alias_transport"]
if marked == nil || marked.hyps.size != 0 || marked.tags != ["axiom:marked_alias"]
  raise "conversion beneath a binder lost its assumption tag"
session.run_source("axiom marked_premise : premise_alias (fun (x : ℕ) => False) 0\n+ marked_premise_transport : False := preserve (fun (x : ℕ) => False) 0 marked_premise\n")
marked = session.theorems["marked_premise_transport"]
if marked == nil || marked.hyps.size != 0 || marked.tags != ["axiom:marked_premise"]
  raise "proof argument conversion lost its assumption tag"
session.run_source("axiom marked_stored : True → False\n+ marked_stored_application : False\n  have k := preserve (fun (n : ℕ) => True → False) 0 marked_stored\n  exact k trivial\n")
marked = session.theorems["marked_stored_application"]
if marked == nil || marked.hyps.size != 0 || marked.tags != ["axiom:marked_stored"]
  raise "stored application lost its assumption tag"
session.run_file("bits/tungsten-satori/spec/application_lambda_failure.sat")
if session.failures != 21
  raise "lambda application accepted an invalid proof"
<< "Lambda application matching passed"

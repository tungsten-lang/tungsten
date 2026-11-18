use ../lib/satori
use ../lib/eval_ref

session = Session.new(".")
session.quiet = true
# Closed evaluation must agree across the signed 64-bit boundary on both engines.
claims = [
  "(10 : ℕ) * 9223372036854775000 = 92233720368547750000",
  "(9223372036854775807 : ℤ) + 1 = 9223372036854775808",
  "(-9223372036854775808 : ℤ) - 1 = -9223372036854775809",
  "-(-9223372036854775808 : ℤ) = 9223372036854775808",
  "(-9223372036854775808 : ℤ) / (-1) = 9223372036854775808",
  "(2 : ℤ) ^ 64 = 18446744073709551616",
  "(9223372036854775807 : ℚ)/2 + 1/3 = 27670116110564327423/6",
  "(9223372036854775807 : ℚ)/3 > 9223372036854775807/4",
  "(9223372036854775807.5 : ℝ) * 2 = 18446744073709551615",
  "∃ i : ℕ, i ≤ 9223372036854775807 ∧ i = 0"
]
claims.each_with_index -> (claim, i)
  name = "wide" + i.to_s
  session.run_source("+ " + name + " : " + claim + " := by decide\n")
  th = session.theorems[name]
  if th == nil || !th.hyps.empty?() || !th.tags.empty?()
    raise "wide literal evaluation failed: " + claim
  reference = KEvalRef.new(session.k)
  if !reference.true?(reference.eval(th.concl))
    raise "reference evaluator disagrees: " + claim
session.run_source("+ wrapped : (10 : ℕ) * 9223372036854775000 < 0 := by decide\n")
if session.failures != 1 || session.theorems["wrapped"] != nil
  raise "natural multiplication accepted a negative result"
session.run_source("+ all_positive : ∀ i : ℕ, i ≤ 9223372036854775807 → 0 < i := by decide\n")
if session.failures != 2 || session.theorems["all_positive"] != nil
  raise "bounded quantification skipped zero"
# Literals that differ by the structural hash modulus share a hash. Replaying
# the first application must never substitute its literal for the second.
f = mk_var("f", ty_fun(ty_nat, ty_nat))
a = mk_app_raw(f, mk_nat(7))
b = mk_app_raw(f, mk_nat(7 + HASH_MOD))
if a.h != b.h || tm_eq(a, b) || b.b.val != 7 + HASH_MOD
  raise "application cache confused colliding terms"
first = mk_lam_raw("x", ty_nat, a)
last = mk_lam_raw("y", ty_nat, a)
if !tm_eq(first, last) || last.name != "y"
  raise "lambda cache lost the binder spelling"
<< "Wide arithmetic passed"

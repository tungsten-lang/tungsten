# Loop-carried BigInt overwrite release (E4 stage 4): `r = <arithmetic>` on a
# local the mutate-if-unique walker proved this scope owns releases r's dead
# previous value once the new one exists. Every shape here must stay
# numerically exact whether or not the release fires; the adversarial cases
# are the ones where a wrong ownership proof would free a live buffer.

BIG = (1 << 200) + 12345
BIG2 = (1 << 190) + 777

-> churn_and(a, b, n)
  acc = 0
  i = 0
  while i < n
    acc = a & b
    i += 1
  acc

-> churn_mixed(a, b, n)
  acc = 0
  i = 0
  while i < n
    acc = (a | b) - (a & acc) + 1
    i += 1
  acc

-> churn_neg(a, n)
  acc = 0
  i = 0
  while i < n
    acc = -a
    i += 1
  acc

-> identity_alias(a, n)
  # `acc = a & -1` hands back `a` itself as a shared-marked alias; the
  # release of the previous acc must never touch the caller's `a`.
  acc = 0
  i = 0
  while i < n
    acc = a & -1
    i += 1
  acc

-> self_read(a, n)
  acc = 0
  i = 0
  while i < n
    acc = (acc | a) & a
    i += 1
  acc

-> demote_and_regrow(a, n)
  acc = 0
  i = 0
  while i < n
    acc = a - a + 5
    acc = acc + a
    i += 1
  acc

-> bare_copy_kills(a, b, n)
  # `y = acc` is a slot copy: an unmarked alias. The walker must refuse acc
  # (and y) so the later overwrite cannot free y's buffer.
  acc = 0
  y = 0
  i = 0
  while i < n
    acc = a & b
    y = acc
    acc = a | b
    i += 1
  [y, acc]

-> array_store_kills(a, b, n)
  acc = 0
  keep = []
  i = 0
  while i < n
    acc = a & b
    keep.push(acc)
    acc = a | b
    i += 1
  [keep[0], acc]

-> closure_kills(a, b, n)
  acc = 0
  sum = 0
  i = 0
  while i < n
    acc = a & b
    [1].each -> (z)
      sum = sum + acc
    acc = a | b
    i += 1
  [sum, acc]

-> param_not_seeded(acc, a, n)
  # No literal seed: the incoming value is caller-owned and never released.
  i = 0
  while i < n
    acc = acc & a
    i += 1
  acc

failures = 0
-> check(name, got, want)
  if got != want
    << "FAIL " + name + ": got " + got.to_s() + " want " + want.to_s()
    return 1
  0

a = BIG
b = BIG2
failures = failures + check("churn_and", churn_and(a, b, 5000), a & b)
# Reference recurrence at top level (main never takes the release path).
ref = 0
ri = 0
while ri < 3000
  ref = (a | b) - (a & ref) + 1
  ri += 1
failures = failures + check("churn_mixed", churn_mixed(a, b, 3000), ref)
failures = failures + check("churn_neg", churn_neg(a, 5000), 0 - a)
failures = failures + check("identity_alias", identity_alias(a, 5000), a)
failures = failures + check("identity_alias.source_intact", a, BIG)
failures = failures + check("self_read", self_read(a, 5000), a)
failures = failures + check("demote_and_regrow", demote_and_regrow(a, 5000), a + 5)
bc = bare_copy_kills(a, b, 5000)
failures = failures + check("bare_copy.y", bc[0], a & b)
failures = failures + check("bare_copy.acc", bc[1], a | b)
asr = array_store_kills(a, b, 2000)
failures = failures + check("array_store.kept", asr[0], a & b)
failures = failures + check("array_store.acc", asr[1], a | b)
ck = closure_kills(a, b, 2000)
failures = failures + check("closure.sum", ck[0], (a & b) * 2000)
failures = failures + check("closure.acc", ck[1], a | b)
seed = a | b
failures = failures + check("param_not_seeded", param_not_seeded(seed, a, 3000), a)
failures = failures + check("param_not_seeded.source_intact", seed, a | b)
failures = failures + check("operands_intact", [a, b], [BIG, BIG2])

if failures == 0
  << "bigint_release_reassign_spec: all checks passed"
else
  << "bigint_release_reassign_spec: " + failures.to_s() + " failures"
  exit(1)

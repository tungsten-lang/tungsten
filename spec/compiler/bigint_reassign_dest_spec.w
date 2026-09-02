# Round-2 items 8-10: tail readers keep the reassignment-release candidate
# alive, `r = a + b` / `r = a - b` over BigInt-typed vars write into r's
# dying buffer through the dest entries, and the inline tag guard skips the
# release for inline ints. Every shape must stay exact with the entries
# refusing (capacity growth, aliasing) or accepting.

-> churn_add(a, b, n)(BigInt BigInt i64)
  acc = 0
  i = 0 ## i64
  while i < n
    acc = a + b
    i = i + 1
  acc.to_s()

-> churn_sub(a, b, n)(BigInt BigInt i64)
  acc = 0
  i = 0 ## i64
  while i < n
    acc = a - b
    i = i + 1
  << acc.bit_length
  acc

-> churn_grow(a, n)(BigInt i64)
  # The sum grows past the dying buffer's capacity every few iterations,
  # so the dest entry refuses and the fallback path must release cleanly.
  acc = 0
  step = a
  i = 0 ## i64
  while i < n
    acc = acc + step
    step = step + step
    i = i + 1
  acc

-> alias_operand(a, n)(BigInt i64)
  # `acc = a + a` with a pointer-identical pair; the dest is neither.
  acc = 0
  i = 0 ## i64
  while i < n
    acc = a + a
    i = i + 1
  acc

-> demoted_between(a, n)(BigInt i64)
  acc = 0
  small = a - a + 3
  i = 0 ## i64
  while i < n
    acc = a + small
    acc = small - small
    acc = a - small
    i = i + 1
  acc

failures = 0
-> check(name, got, want)
  if got != want
    << "FAIL " + name + ": got " + got.to_s() + " want " + want.to_s()
    return 1
  0

big = (1 << 200) + 12345
big2 = (1 << 190) + 777
failures = failures + check("churn_add", churn_add(big, big2, 3000), (big + big2).to_s())
failures = failures + check("churn_sub", churn_sub(big, big2, 3000), big - big2)
ref = 0
step_ref = big
ri = 0
while ri < 40
  ref = ref + step_ref
  step_ref = step_ref + step_ref
  ri += 1
failures = failures + check("churn_grow", churn_grow(big, 40), ref)
failures = failures + check("alias_operand", alias_operand(big, 3000), big + big)
failures = failures + check("demoted_between", demoted_between(big, 3000), big - 3)
failures = failures + check("operands_intact", [big, big2], [(1 << 200) + 12345, (1 << 190) + 777])

if failures == 0
  << "bigint_reassign_dest_spec: all checks passed"
else
  << "bigint_reassign_dest_spec: " + failures.to_s() + " failures"
  exit(1)

# Compile-only fixture for scripts/test-carry-unroll.sh. The loop contains a
# real carry dependency, so lowering must attach the configured unroll count to
# its latch while leaving ordinary loops alone.

-> carry_unroll_fixture(out, left, right, n) (u64[] u64[] u64[] i64) i64
  carry = 0 ## u64
  i = 0 ## i64
  while i < n
    x = left[i] ## u64
    y = right[i] ## u64
    first = x + carry
    c1 = addcarry(x, carry)
    result = first + y
    c2 = addcarry(first, y)
    out[i] = result
    carry = c1 + c2
    i += 1
  carry

# Exercise a latch that carries both the masked-index vectorizer opt-out and
# the configurable carry-chain unroll tuple.
-> carry_unroll_masked_fixture(out, left, right, n) (u64[] u64[] u64[] i64) i64
  carry = 0 ## u64
  i = 0 ## i64
  while i < n
    slot = i & 7
    x = left[slot] ## u64
    y = right[slot] ## u64
    first = x + carry
    c1 = addcarry(x, carry)
    result = first + y
    c2 = addcarry(first, y)
    out[slot] = result
    carry = c1 + c2
    i += 1
  carry

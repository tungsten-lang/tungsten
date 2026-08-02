# The sticky shared bit in the WBigint header (R2 of the tag-sign design).
#
# `shared` marks a buffer that may have an alias (a tag-flipped negate, or
# escape-site instrumentation). The contract this spec pins:
#   * fresh values are unshared;
#   * marking is sticky and queryable;
#   * a shared buffer is never reclaimed by the recycler
#     (bigint_release_if_live bails), so aliases can't be freed underneath
#     — observed here as value stability across churn that would otherwise
#     recycle the buffer;
#   * recycled buffers come back unshared (pool invariant: parked implies
#     unshared, maintained by the release guards).

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

# fresh values are unshared
a = (1 << 200) + 7
check("fresh.unshared", ccall("w_bigint_shared_value", a), "false")

# marking is sticky and queryable
ccall("w_bigint_mark_shared_value", a)
check("marked.shared", ccall("w_bigint_shared_value", a), "true")
check("marked.value_intact", a.to_s(), ((1 << 200) + 7).to_s())

# non-bigints: mark is a no-op, query answers false
small = 42
ccall("w_bigint_mark_shared_value", small)
check("smallint.unshared", ccall("w_bigint_shared_value", small), "false")

# a shared buffer survives allocation churn that recycles same-class
# buffers: if the release guard failed, the churn below would take a's
# buffer and overwrite its limbs.
snapshot = a.to_s()
i = 0 ## i64
noise = 0 ## i64
while i < 100000
  t = (1 << 200) + i
  if t.odd?
    noise = noise + 1
  i = i + 1
check("shared.survives_churn", a.to_s(), snapshot)

# recycled buffers come back unshared
b = (1 << 200) + 99
check("recycled.unshared", ccall("w_bigint_shared_value", b), "false")

<< "bigint_shared_bit_spec: all checks passed"

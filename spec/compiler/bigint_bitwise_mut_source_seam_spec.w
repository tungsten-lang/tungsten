# Consumed BigInt bitwise compound assignment. These literal-seeded locals
# satisfy the compiler's liveness proof and therefore exercise the stable
# preserve_most source seams in emitted IR. The value checks also pin language
# semantics independently of whether the runtime can reuse the receiver.

-> check(label, value)
  if !value
    << "FAIL " + label
    exit(1)

-> consumed_and
  r = (1 << 256) + (1 << 130) + 255
  r &= (1 << 200) + (1 << 130) + 15
  r == (1 << 130) + 15

-> consumed_or
  r = (1 << 256) + (1 << 130) + 255
  r |= (1 << 200) + (1 << 130) + 15
  r == (1 << 256) + (1 << 200) + (1 << 130) + 255

-> consumed_xor
  r = (1 << 256) + (1 << 130) + 255
  r ^= (1 << 200) + (1 << 130) + 15
  r == (1 << 256) + (1 << 200) + 240

-> consumed_identity
  r = (1 << 256) + 99
  r &= r
  and_ok = r == (1 << 256) + 99
  r ^= r
  if !and_ok
    return false
  r == 0

# Identities that transfer the consumed receiver back into its own binding do
# not publish a second alias. The direct source-mut acceptance gate inspects
# the shared bit; this syntax-level chain keeps the compiler's liveness proof
# intact and verifies all four compound operations retain the value.
-> consumed_identity_chain_stays_unique(and_identity, or_identity, xor_identity)
  r = (1 << 256) + (1 << 130) + 255
  r &= and_identity
  r |= or_identity
  r ^= xor_identity
  r &= r
  r == (1 << 256) + (1 << 130) + 255

-> aliased_receiver_stays_immutable
  r = (1 << 256) + 255
  snapshot = r
  r &= 15
  snapshot == (1 << 256) + 255 && r == 15

# Width-one heap receivers can shrink to a nonzero inline result. AND/XOR
# must normalize even when the published top word is nonzero. The full
# source/C gate separately checks the representation; these tail comparisons
# keep the receiver eligible for the consumed seam in this focused spec.
-> consumed_and_one_limb
  r = (1 << 63) + 15
  r &= (1 << 62) + 15
  r == 15 && type(r) == "Integer"

-> consumed_xor_one_limb
  r = (1 << 63) + 31
  r ^= (1 << 63) + 16
  r == 15 && type(r) == "Integer"

# An opaque rhs leaves compound lowering unable to prove its dynamic type.
# Floats retain the public runtime's truncating bitwise coercion; invalid text
# must raise instead of having its tag bits reinterpreted as an inline integer.
-> opaque_and(rhs)
  r = (1 << 256) + (1 << 130) + 255
  r &= rhs
  r == 15

-> opaque_or(rhs)
  r = (1 << 256) + (1 << 130) + 255
  r |= rhs
  r == (1 << 256) + (1 << 130) + 511

-> opaque_xor(rhs)
  r = (1 << 256) + (1 << 130) + 255
  r ^= rhs
  r == (1 << 256) + (1 << 130)

-> invalid_and(rhs)
  begin
    opaque_and(rhs)
    false
  rescue error
    true

-> invalid_or(rhs)
  begin
    opaque_or(rhs)
    false
  rescue error
    true

-> invalid_xor(rhs)
  begin
    opaque_xor(rhs)
    false
  rescue error
    true

check("consumed and", consumed_and())
check("consumed or", consumed_or())
check("consumed xor", consumed_xor())
check("consumed identity", consumed_identity())
check("consumed identity chain", consumed_identity_chain_stays_unique(-1, 0, 0))
check("aliased receiver", aliased_receiver_stays_immutable())
and_one = consumed_and_one_limb()
xor_one = consumed_xor_one_limb()
check("one-limb and value", and_one)
check("one-limb xor value", xor_one)
check("opaque Float and", opaque_and(~15.75))
check("opaque Float or", opaque_or(~256.75))
check("opaque Float xor", opaque_xor(~255.75))
check("opaque String and raises", invalid_and("15"))
check("opaque String or raises", invalid_or("15"))
check("opaque String xor raises", invalid_xor("15"))

<< "PASS consumed BigInt bitwise source seams"

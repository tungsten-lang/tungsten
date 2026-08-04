# Compile-time power-of-two modulus context. The specialized compiled path
# must match ordinary truncated `%` for boundary exponents and preserve value
# aliases when compound assignment rebinds its left-hand side.

-> check(name, got, want)
  if got.to_s() == want.to_s()
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

p = ((1 << 520) + (1 << 257) + (1 << 129) + 123456789) ## big
n = 0 - p ## big

m1 = 1 << 1
m46 = 1 << 46
m63 = 1 << 63
m64 = 1 << 64
m65 = 1 << 65
m127 = 1 << 127
m128 = 1 << 128
m129 = 1 << 129
m521 = 1 << 521

check("pow2.positive.1", p % (1 << 1), p % m1)
check("pow2.positive.46", p % (1 << 46), p % m46)
check("pow2.positive.63", p % (1 << 63), p % m63)
check("pow2.positive.64", p % (1 << 64), p % m64)
check("pow2.positive.65", p % (1 << 65), p % m65)
check("pow2.positive.127", p % (1 << 127), p % m127)
check("pow2.positive.128", p % (1 << 128), p % m128)
check("pow2.positive.129", p % (1 << 129), p % m129)
check("pow2.positive.identity", p % (1 << 521), p % m521)

check("pow2.negative.1", n % (1 << 1), n % m1)
check("pow2.negative.63", n % (1 << 63), n % m63)
check("pow2.negative.64", n % (1 << 64), n % m64)
check("pow2.negative.65", n % (1 << 65), n % m65)
check("pow2.negative.128", n % (1 << 128), n % m128)
check("pow2.negative.identity", n % (1 << 521), n % m521)
check("pow2.modulus.one", p % (1 << 0), 0)

-> compound_positive
  r = ((1 << 520) + (1 << 257) + 987654321) ## big
  r %= 1 << 129
  r

-> assignment_negative
  r = (0 - ((1 << 520) + (1 << 257) + 987654321)) ## big
  r = r % (1 << 129)
  r

cp_ref = ((1 << 520) + (1 << 257) + 987654321) % m129
an_ref = (0 - ((1 << 520) + (1 << 257) + 987654321)) % m129
check("pow2.compound.consume", compound_positive(), cp_ref)
check("pow2.assignment.consume", assignment_negative(), an_ref)

aliased = ((1 << 300) + 77) ## big
snapshot = aliased
aliased %= 1 << 128
check("pow2.compound.alias.old", snapshot, (1 << 300) + 77)
check("pow2.compound.alias.result", aliased, 77)

identity = ((1 << 200) + 99) ## big
identity_snapshot = identity
identity %= 1 << 256
check("pow2.identity.alias.old", identity_snapshot, (1 << 200) + 99)
check("pow2.identity.result", identity, (1 << 200) + 99)

zeroed = ((1 << 200) + 99) ## big
zeroed %= 1 << 0
check("pow2.compound.zero", zeroed, 0)

# Adjacent modular context: the compiled engine may fuse these two statements
# only when the receiver is proven dead. Variable-modulus twins keep the
# arithmetic reference on the ordinary two-operation path.
-> fused_chain(n)
  r = ((1 << 257) + 12345) ## big
  bump = (1 << 127) + 98765
  i = 0 ## i64
  while i < n
    r += bump
    r %= 1 << 128
    i += 1
  r % 1000000007

-> fused_chain_ref(n)
  r = ((1 << 257) + 12345) ## big
  bump = (1 << 127) + 98765
  modulus = 1 << 128
  i = 0 ## i64
  while i < n
    r += bump
    r %= modulus
    i += 1
  r % 1000000007

-> fused_negative_receiver(n)
  r = (0 - ((1 << 257) + 12345)) ## big
  bump = (1 << 127) + 98765
  i = 0 ## i64
  while i < n
    r += bump
    r %= 1 << 128
    i += 1
  r % 1000000007

-> fused_negative_receiver_ref(n)
  r = (0 - ((1 << 257) + 12345)) ## big
  bump = (1 << 127) + 98765
  modulus = 1 << 128
  i = 0 ## i64
  while i < n
    r += bump
    r %= modulus
    i += 1
  r % 1000000007

-> fused_negative_rhs(n)
  r = ((1 << 257) + 12345) ## big
  bump = 0 - ((1 << 127) + 98765)
  i = 0 ## i64
  while i < n
    r += bump
    r %= 1 << 128
    i += 1
  r % 1000000007

-> fused_negative_rhs_ref(n)
  r = ((1 << 257) + 12345) ## big
  bump = 0 - ((1 << 127) + 98765)
  modulus = 1 << 128
  i = 0 ## i64
  while i < n
    r += bump
    r %= modulus
    i += 1
  r % 1000000007

-> fused_self(n)
  r = ((1 << 200) + 17) ## big
  i = 0 ## i64
  while i < n
    r += r
    r %= 1 << 129
    i += 1
  r % 1000000007

-> fused_self_ref(n)
  r = ((1 << 200) + 17) ## big
  modulus = 1 << 129
  i = 0 ## i64
  while i < n
    r += r
    r %= modulus
    i += 1
  r % 1000000007

-> fused_capacity_fallback
  r = ((1 << 63) + 7) ## big
  i = 0 ## i64
  while i < 1
    r += (1 << 500) + 11
    r %= 1 << 512
    i += 1
  r % 1000000007

check("ring.fused.positive", fused_chain(33), fused_chain_ref(33))
check("ring.fused.negative_receiver", fused_negative_receiver(33), fused_negative_receiver_ref(33))
check("ring.fused.negative_rhs", fused_negative_rhs(33), fused_negative_rhs_ref(33))
check("ring.fused.self", fused_self(9), fused_self_ref(9))
check("ring.fused.capacity_fallback", fused_capacity_fallback(), ((1 << 500) + (1 << 63) + 18) % 1000000007)

ring_alias = ((1 << 300) + 31) ## big
ring_snapshot = ring_alias
ring_alias += (1 << 200) + 7
ring_alias %= 1 << 129
check("ring.alias.old", ring_snapshot, (1 << 300) + 31)
check("ring.alias.result", ring_alias, 38)

ring_zero = ((1 << 200) + 9) ## big
ring_zero += (1 << 100) + 5
ring_zero %= 1 << 0
check("ring.modulus.one", ring_zero, 0)

<< "bigint_mod_pow2_context_spec: all checks passed"

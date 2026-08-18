# Exact `(BigInt)` signature parameters may select the guarded stable `+`
# source seam.  Other operators and an untyped sibling deliberately retain
# ordinary polymorphic dispatch until their matching fixed arms migrate.

-> typed_add(a, b)(BigInt BigInt)
  a + b

-> typed_sub(a, b)(BigInt BigInt)
  a - b

-> untyped_add(a, b)
  a + b

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

a = (1 << 191) + (1 << 70) + 17
b = (1 << 63) + 23
check("typed.add", typed_add(a, b), ccall("w_bigint_add", a, b))
check("typed.sub", typed_sub(a, b), ccall("w_bigint_sub", a, b))
check("typed.negative", typed_add(0 - a, b), ccall("w_bigint_add", 0 - a, b))
check("untyped.control", untyped_add(a, b), ccall("w_bigint_add", a, b))

<< "bigint_signature_type_fact_spec: all checks passed"

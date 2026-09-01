use core/algebra/finite_field
use core/algebra/polynomial

modulus = 1000003
field = FiniteField.new(modulus)
ring = PolynomialRing.new([:x], field, :grevlex)

# A sparse degree-5000 polynomial with 1001 canonical terms. At x=1 the
# expected value is simply the modular sum of its coefficients.
terms = []
expected = 0
exponent = 5000
index = 0
while exponent >= 0
  coefficient = (index * 7919 + 17) % modulus
  coefficient = 1 if coefficient == 0
  terms.push([coefficient, [exponent]])
  expected = (expected + coefficient) % modulus
  exponent -= 5
  index += 1
polynomial = Polynomial.new(ring, terms, true)

warm = polynomial.at_raw(1)
raise "gap-Horner warmup mismatch" if warm != expected

iterations = 12
t0 = ccall("__w_clock_ms")
i = 0
checksum = 0
while i < iterations
  checksum = (checksum + polynomial.at_raw(1)) % modulus
  i += 1
t1 = ccall("__w_clock_ms")

expected_checksum = (expected * iterations) % modulus
raise "gap-Horner checksum mismatch" if checksum != expected_checksum
<< "checksum=" + checksum.to_s()
<< "elapsed_ms=" + (t1 - t0).to_s()

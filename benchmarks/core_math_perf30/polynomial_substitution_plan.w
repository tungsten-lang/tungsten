use core/algebra/finite_field
use core/algebra/polynomial

modulus = 65537
field = FiniteField.new(modulus)
ring = PolynomialRing.new([:x, :y], field, :grevlex)

terms = []
x_power = 0
while x_power < 24
  y_power = 0
  while y_power < 48
    coefficient = (x_power * 97 + y_power * 193 + 11) % modulus
    coefficient = 1 if coefficient == 0
    terms.push([coefficient, [x_power, y_power]])
    y_power += 1
  x_power += 1
polynomial = Polynomial.new(ring, terms)

warm = polynomial.substitute_raw(0, 3)
raise "substitution warmup shape mismatch" if warm.terms.size != 48

iterations = 30
t0 = ccall("__w_clock_ms")
i = 0
last = warm
while i < iterations
  last = polynomial.substitute_raw(0, i + 2)
  i += 1
t1 = ccall("__w_clock_ms")

scalar = iterations + 1
expected = 0
x_power = 0
while x_power < 24
  y_power = 0
  while y_power < 48
    coefficient = (x_power * 97 + y_power * 193 + 11) % modulus
    coefficient = 1 if coefficient == 0
    expected = field.add(
      expected, field.multiply(coefficient, field.power(scalar, x_power)))
    y_power += 1
  x_power += 1
checksum = last.evaluate_raw([0, 1])
raise "substitution checksum mismatch" if checksum != expected
<< "checksum=" + checksum.to_s()
<< "terms=" + last.terms.size.to_s()
<< "elapsed_ms=" + (t1 - t0).to_s()

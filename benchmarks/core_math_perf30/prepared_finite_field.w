use core/algebra/finite_field

# F_2^8 with x^8 + x^4 + x^3 + x + 1.
field = FiniteField.new(2, [1, 1, 0, 1, 1, 0, 0, 0, 1])
field.prepare_arithmetic!

rounds = 1000
t0 = ccall("__w_clock_ms")
round = 0
checksum = 0
while round < rounds
  value = 1
  while value < field.order
    inverse = field.inverse(value)
    raise "prepared-field inverse mismatch" if field.multiply(value, inverse) != 1
    frobenius = field.frobenius(value)
    restored = field.inverse_frobenius(frobenius)
    raise "prepared-field Frobenius mismatch" if restored != value
    checksum = field.add(checksum, field.add(inverse, frobenius))
    value += 1
  round += 1
t1 = ccall("__w_clock_ms")

<< "checksum=" + checksum.to_s()
<< "elapsed_ms=" + (t1 - t0).to_s()

use algebra

field = FiniteField.new(2)
ring = PolynomialRing.new([:x], field, :grevlex)
receiver = ring.one
code = 2097151
degree = 21

warm = receiver.finite_factor_candidate(code, degree)
raise "finite-factor warmup terms mismatch" if warm.terms.size != 21
raise "finite-factor warmup value mismatch" if warm.at_raw(1) != 1

iterations = 10000
t0 = ccall("__w_clock_ms")
i = 0
last = warm
while i < iterations
  last = receiver.finite_factor_candidate(code, degree)
  i += 1
t1 = ccall("__w_clock_ms")

checksum = last.terms.size * 10 + last.at_raw(1)
raise "finite-factor checksum mismatch" if checksum != 211
<< "checksum=" + checksum.to_s()
<< "elapsed_ms=" + (t1 - t0).to_s()

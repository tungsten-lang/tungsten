# Matched single-thread guard for publishing the Polynomial substitution plan
# and ArithmeticCircuit evaluation tape as one immutable cache pair. The
# fixtures mirror the retained perf30 workloads; each timed loop stays on one
# warmed key so it measures the cache-hit path changed by the publication fix.

use core/algebra/finite_field
use core/algebra/polynomial
use core/algebra/arithmetic_circuit

field = FiniteField.new(65537)
ring = PolynomialRing.new([:x, :y], field, :grevlex)
terms = []
x_power = 0
while x_power < 24
  y_power = 0
  while y_power < 48
    coefficient = (x_power * 97 + y_power * 193 + 11) % 65537
    coefficient = 1 if coefficient == 0
    terms.push([coefficient, [x_power, y_power]])
    y_power += 1
  x_power += 1
polynomial = Polynomial.new(ring, terms)

warm_polynomial = polynomial.substitute_raw(0, 3)
raise "substitution warmup shape mismatch" if warm_polynomial.terms.size != 48

polynomial_iterations = 6000 ## i64
started = ccall_nobox("__w_clock_ns_raw") ## i64
i = 0 ## i64
polynomial_checksum = 0
while i < polynomial_iterations
  specialized = polynomial.substitute_raw(0, (i % 251) + 2)
  polynomial_checksum += specialized.terms.size
  i += 1
polynomial_ns = ccall_nobox("__w_clock_ns_raw") - started ## i64
raise "substitution checksum mismatch" if polynomial_checksum != polynomial_iterations * 48

circuit = ArithmeticCircuit.new([:x, :one])
x = circuit.variable(:x)
one = circuit.variable(:one)
current = x
i = 0
while i < 400
  current = circuit.add([current, one])
  i += 1
circuit.set_output(current)
assignments = {:x => 7, :one => 1}
raise "arithmetic-circuit warmup mismatch" if circuit.evaluate(assignments) != 407

circuit_iterations = 50000 ## i64
started = ccall_nobox("__w_clock_ns_raw") ## i64
i = 0
circuit_checksum = 0
while i < circuit_iterations
  circuit_checksum += circuit.evaluate(assignments)
  i += 1
circuit_ns = ccall_nobox("__w_clock_ns_raw") - started ## i64
raise "arithmetic-circuit checksum mismatch" if circuit_checksum != circuit_iterations * 407

<< "polynomial_checksum=" + polynomial_checksum.to_s()
<< "polynomial_ns_per_call=" + (polynomial_ns / polynomial_iterations).to_s()
<< "circuit_checksum=" + circuit_checksum.to_s()
<< "circuit_ns_per_call=" + (circuit_ns / circuit_iterations).to_s()

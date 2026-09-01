# A Polynomial and ArithmeticCircuit are immutable during these calls, but
# their one-entry MRU caches are intentionally contended by different keys.
# The start gate makes every run exercise true overlap. Each worker validates
# both the selected cache summary and the public calculation on every turn.

use core/atomic
use core/thread
use core/algebra/finite_field
use core/algebra/polynomial
use core/algebra/arithmetic_circuit

-> cache_thread_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

field = FiniteField.new(65537)
ring = PolynomialRing.new([:x, :y, :z], field, :grevlex)
terms = []
x_power = 0
while x_power < 7
  y_power = 0
  while y_power < 5
    z_power = 0
    while z_power < 3
      coefficient = (x_power * 97 + y_power * 31 + z_power * 11 + 1) % 65537
      terms.push([coefficient, [x_power, y_power, z_power]])
      z_power += 1
    y_power += 1
  x_power += 1
polynomial = Polynomial.new(ring, terms)

# Full Cartesian support gives every substitution key a distinct, cheaply
# checked plan signature: [group count, maximum power].
polynomial_group_counts = [15, 21, 35]
polynomial_maximum_powers = [6, 4, 2]
polynomial_scalars = [2, 3, 5]
polynomial_coordinates = [11, 13, 17]

circuit = ArithmeticCircuit.new([:x, :one])
circuit_x = circuit.variable(:x)
circuit_one = circuit.variable(:one)
circuit_current = circuit_x
circuit_targets = []
i = 0
while i < 180
  circuit_current = circuit.add([circuit_current, circuit_one])
  if i == 23 || i == 71 || i == 179
    circuit_targets.push(circuit_current)
  i += 1
circuit_tape_sizes = [26, 74, 182]
circuit_expected = [25, 73, 181]

worker_count = 9 ## i64
iterations = 1200 ## i64
ready = Atomic.new(0)
start = Atomic.new(0)
polynomial_ok = i64[worker_count]
circuit_ok = i64[worker_count]
workers = []
i = 0 ## i64
while i < worker_count
  slot = i ## i64
  key = (i % 3) ## i64
  worker = Thread.new ->
    polynomial_good = 1 ## i64
    circuit_good = 1 ## i64
    ready.increment()
    wait_spins = 0 ## i64
    while start.load() == 0
      # Spin only until all workers are resident at the same gate.
      wait_spins += 1
    turn = 0 ## i64
    while turn < iterations
      plan = polynomial.substitution_plan(key)
      if (plan[0].size != polynomial_group_counts[key] ||
          plan[1] != polynomial_maximum_powers[key])
        polynomial_good = 0
      else
        scalar = polynomial_scalars[key]
        specialized = polynomial.substitute_raw(key, scalar)
        point = [polynomial_coordinates[0],
                 polynomial_coordinates[1],
                 polynomial_coordinates[2]]
        point[key] = scalar
        if (specialized.evaluate_raw(polynomial_coordinates) !=
            polynomial.evaluate_raw(point))
          polynomial_good = 0
      tape = circuit.evaluation_tape(circuit_targets[key])
      last = tape[0].size - 1
      if (tape[0].size != circuit_tape_sizes[key] ||
          tape[0][last] != circuit_targets[key])
        circuit_good = 0
      else
        got = circuit.evaluate_at([
          {:x => 1, :one => 1}, circuit_targets[key]])
        if got != circuit_expected[key]
          circuit_good = 0
      turn += 1
    polynomial_ok[slot] = polynomial_good
    circuit_ok[slot] = circuit_good
  workers.push(worker)
  i += 1

barrier_spins = 0 ## i64
while ready.load() < worker_count
  # Deterministic barrier: no worker enters either cache before all are ready.
  barrier_spins += 1
start.store(1)

i = 0
while i < worker_count
  workers[i].join()
  i += 1

i = 0
while i < worker_count
  if polynomial_ok[i] != 1
    raise "FAIL polynomial cache pair concurrent selection worker " + i.to_s()
  if circuit_ok[i] != 1
    raise "FAIL arithmetic-circuit cache pair concurrent selection worker " + i.to_s()
  i += 1

cache_thread_check("polynomial substitution plan concurrent selection", true)
cache_thread_check("arithmetic-circuit tape concurrent selection", true)
<< "algebra_cache_thread_safety_spec: 9 workers x 1200 exact checks passed"

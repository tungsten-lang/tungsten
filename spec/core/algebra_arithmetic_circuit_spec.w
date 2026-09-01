# Exact finite arithmetic-circuit semantics and structure.
# Run in both engines:
#   bin/tungsten run spec/core/algebra_arithmetic_circuit_spec.w
#   bin/tungsten compile spec/core/algebra_arithmetic_circuit_spec.w \
#     --out /tmp/algebra-arithmetic-circuit-spec --no-lto

use core/numeric/rational
use core/algebra/arithmetic_circuit

-> circuit_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

circuit = ArithmeticCircuit.new([:x, :y])
x = circuit.variable(:x)
y = circuit.variable(:y)
product = circuit.multiply([x, y])
two = circuit.constant(Rational.new(2))
output = circuit.add([product, two])

circuit_check("evaluate", circuit.evaluate(
  {:x => Rational.new(3), :y => Rational.new(4)}) == Rational.new(14))
circuit_check("node_count", circuit.node_count == 5)
circuit_check("operation_count", circuit.operation_count == 2)
circuit_check("depth", circuit.depth == 2)
circuit_check("division_free", circuit.division_free?)
circuit_check("formula", circuit.formula?)
circuit_check("degree", circuit.degree_bound == 2)
circuit_check("formula_size", circuit.expanded_formula_size == 2)
evaluation = circuit.evaluation_certificate([
  {:x => Rational.new(3), :y => Rational.new(4)}, Rational.new(14)])
circuit_check("evaluation_certificate.circuit", evaluation.circuit == circuit)
circuit_check("evaluation_certificate.claim", evaluation.claimed_value == Rational.new(14))
circuit_check("evaluation_certificate.output", evaluation.output_index == output)
circuit_check("evaluation_certificate.assignments",
              evaluation.assignments[:x] == Rational.new(3))
circuit_check("evaluation_certificate.replay",
              evaluation.replay_value == Rational.new(14))
circuit_check("evaluation_certificate", evaluation.verified?)

# The cached tape is observable for inspection, but callers must receive
# owned columns rather than a handle that can rewrite later evaluations.
tape_copy = circuit.evaluation_tape(output)
tape_copy[1][tape_copy[1].size - 1] = 0
circuit_check("evaluation_tape inspection is owned", circuit.evaluate(
  {:x => Rational.new(3), :y => Rational.new(4)}) == Rational.new(14))

shared = ArithmeticCircuit.new([:x, :y])
shared_x = shared.variable(:x)
shared_y = shared.variable(:y)
sum = shared.add([shared_x, shared_y])
shared.multiply([sum, sum])
circuit_check("shared.not_formula", !shared.formula?)
circuit_check("shared.operation_count", shared.operation_count == 2)
circuit_check("shared.expanded_size", shared.expanded_formula_size == 3)

rational_formula = ArithmeticCircuit.new([:x, :y])
numerator = rational_formula.variable(:x)
denominator = rational_formula.variable(:y)
rational_formula.divide([numerator, denominator])
circuit_check("division.evaluate",
              rational_formula.evaluate({:x => 6, :y => 3}) == 2)
circuit_check("division.present", !rational_formula.division_free?)
circuit_check("division.degree_unknown", rational_formula.degree_bound == nil)
circuit_check("division.defined", rational_formula.defined_at?({:x => 6, :y => 3}))
circuit_check("division.zero_rejected",
              !rational_formula.defined_at?({:x => 6, :y => 0}))

unused = ArithmeticCircuit.new([:x])
unused_x = unused.variable(:x)
unused_one = unused.constant(1)
usable_output = unused.add([unused_x, unused_one])
unused_zero = unused.constant(0)
unused.divide([unused_one, unused_zero])
unused.set_output(usable_output)
circuit_check("unreachable.division_ignored", unused.evaluate({:x => 2}) == 3)
circuit_check("unreachable.degree", unused.degree_bound == 1)

bad_assignment = circuit.evaluation_certificate([
  {:x => Rational.new(3), :y => Rational.new(4)}, Rational.new(15)])
circuit_check("bad_claim_rejected", !bad_assignment.verified?)

<< "algebra_arithmetic_circuit_spec: all checks passed"

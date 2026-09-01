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

# Repeated single-point evaluation may reuse caller-owned node storage.
evaluation_workspace = circuit.evaluation_workspace
circuit_check("evaluate_into.exact", circuit.evaluate_into(
  {:x => Rational.new(3), :y => Rational.new(4)},
  evaluation_workspace) == Rational.new(14))
circuit_check("evaluate_into.reuse", circuit.evaluate_into(
  {:x => Rational.new(-2), :y => Rational.new(5)},
  evaluation_workspace) == Rational.new(-8))
circuit_check("evaluate_into.output_stored",
              evaluation_workspace[output] == Rational.new(-8))

# Batch scratch is column-major: opcode dispatch happens once per instruction,
# while each point still receives exact arithmetic in the same DAG.
batch_assignments = [
  {:x => Rational.new(3), :y => Rational.new(4)},
  {:x => Rational.new(-2), :y => Rational.new(5)},
  {:x => Rational.new(0), :y => Rational.new(7)}]
batch_outputs = [nil, nil, nil]
batch_workspace = circuit.evaluation_batch_workspace(4)
batch_result = circuit.evaluate_batch_into(
  batch_assignments, batch_outputs, batch_workspace)
circuit_check("evaluate_batch_into.exact", batch_result == [
  Rational.new(14), Rational.new(-8), Rational.new(2)])
circuit_check("evaluate_batch_into.workspace_reuse",
              circuit.evaluate_batch_into(
                [batch_assignments[1]], batch_outputs,
                batch_workspace)[0] == Rational.new(-8))
empty_outputs = []
circuit_check("evaluate_batch_into.empty",
              circuit.evaluate_batch_into(
                [], empty_outputs,
                circuit.evaluation_batch_workspace(0)) == [])

short_workspace_rejected = false
begin
  circuit.evaluate_into(batch_assignments[0], [])
rescue error
  short_workspace_rejected = true
circuit_check("evaluate_into.short_workspace_rejected",
              short_workspace_rejected)

short_batch_workspace_rejected = false
begin
  circuit.evaluate_batch_into(batch_assignments, batch_outputs, [])
rescue error
  short_batch_workspace_rejected = true
circuit_check("evaluate_batch_into.short_workspace_rejected",
              short_batch_workspace_rejected)

shared = ArithmeticCircuit.new([:x, :y])
shared_x = shared.variable(:x)
shared_y = shared.variable(:y)
sum = shared.add([shared_x, shared_y])
shared.multiply([sum, sum])
circuit_check("shared.not_formula", !shared.formula?)
circuit_check("shared.operation_count", shared.operation_count == 2)
circuit_check("shared.expanded_size", shared.expanded_formula_size == 3)

all_ops = ArithmeticCircuit.new([:x, :y])
all_x = all_ops.variable(:x)
all_y = all_ops.variable(:y)
all_sum = all_ops.add([all_x, all_y])
all_difference = all_ops.subtract([all_x, all_y])
all_product = all_ops.multiply([all_sum, all_difference])
all_two = all_ops.constant(Rational.new(2))
all_quotient = all_ops.divide([all_product, all_two])
all_ops.negate(all_quotient)
all_points = [
  {:x => Rational.new(7), :y => Rational.new(3)},
  {:x => Rational.new(-4), :y => Rational.new(2)},
  {:x => Rational.new(5), :y => Rational.new(-1)}]
all_expected = []
all_points.each -> (point)
  all_expected.push(all_ops.evaluate(point))
all_outputs = [nil, nil, nil]
all_workspace = all_ops.evaluation_workspace
circuit_check("evaluate_into.all_opcodes",
              all_ops.evaluate_into(all_points[0], all_workspace) ==
              all_expected[0])
circuit_check("evaluate_batch_into.all_opcodes",
              all_ops.evaluate_batch_into(
                all_points, all_outputs,
                all_ops.evaluation_batch_workspace(all_points.size)) ==
              all_expected)

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
division_batch = [{:x => 6, :y => 3}, {:x => 15, :y => 5}]
division_outputs = [nil, nil]
division_workspace = rational_formula.evaluation_batch_workspace(2)
circuit_check("division.batch_exact", rational_formula.evaluate_batch_into(
  division_batch, division_outputs, division_workspace) == [2, 3])
rational_division_batch = [
  {:x => Rational.new(1), :y => Rational.new(3)},
  {:x => Rational.new(-7), :y => Rational.new(5)}]
division_single_workspace = rational_formula.evaluation_workspace
circuit_check("division.into_rational_exact",
              rational_formula.evaluate_into(
                rational_division_batch[0], division_single_workspace) ==
              Rational.new(1, 3))
division_into_zero_rejected = false
begin
  rational_formula.evaluate_into(
    {:x => Rational.new(1), :y => Rational.new(0)},
    division_single_workspace)
rescue error
  division_into_zero_rejected = true
circuit_check("division.into_zero_rejected", division_into_zero_rejected)
circuit_check("division.batch_rational_exact",
              rational_formula.evaluate_batch_into(
                rational_division_batch, division_outputs,
                division_workspace) ==
              [Rational.new(1, 3), Rational.new(-7, 5)])
division_batch_zero_rejected = false
begin
  rational_formula.evaluate_batch_into(
    [{:x => 6, :y => 3}, {:x => 1, :y => 0}],
    division_outputs, division_workspace)
rescue error
  division_batch_zero_rejected = true
circuit_check("division.batch_zero_rejected", division_batch_zero_rejected)

short_batch_output_rejected = false
begin
  rational_formula.evaluate_batch_into(
    division_batch, [], division_workspace)
rescue error
  short_batch_output_rejected = true
circuit_check("evaluate_batch_into.short_output_rejected",
              short_batch_output_rejected)

short_batch_column = rational_formula.evaluation_batch_workspace(2)
short_batch_column[rational_formula.output_index] = []
short_batch_column_rejected = false
begin
  rational_formula.evaluate_batch_into(
    division_batch, division_outputs, short_batch_column)
rescue error
  short_batch_column_rejected = true
circuit_check("evaluate_batch_into.short_column_rejected",
              short_batch_column_rejected)

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

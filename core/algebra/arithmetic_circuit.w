# Exact finite arithmetic-circuit DAGs.
#
# Circuits are built in topological order from constants, named variables,
# addition, subtraction, multiplication, negation, and division. Evaluation
# is exact whenever the supplied coefficient objects are exact. A successful
# evaluation is a finite semantic replay at one assignment; it is not a
# polynomial-identity proof or an arithmetic-formula lower bound.

use core/combinatorics/support

+ ArithmeticCircuitNode
  -> new(record)
    @kind = record[0]
    @payload = record[1]
    @inputs = Combinatorics.copy_vector(record[2])

  -> kind
    @kind

  -> payload
    @payload

  -> inputs
    Combinatorics.copy_vector(@inputs)


+ ArithmeticCircuit
  -> new(variable_names = [])
    if variable_names.class_name != "Array"
      raise "arithmetic-circuit variable names must be an Array"
    @variable_names = []
    variable_names.each -> (name)
      if @variable_names.include?(name)
        raise "arithmetic-circuit variable names must be distinct"
      @variable_names.push(name)
    @nodes = []
    @output_index = nil

  -> variable_names
    Combinatorics.copy_vector(@variable_names)

  -> node_count
    @nodes.size

  -> output_index
    @output_index

  -> node(index)
    require_node(index)
    @nodes[index]

  -> append_node(record)
    kind = record[0]
    payload = record[1]
    inputs = record[2]
    inputs.each -> (index)
      require_node(index)
    @nodes.push(ArithmeticCircuitNode.new([kind, payload, inputs]))
    @output_index = @nodes.size - 1
    @output_index

  -> constant(value)
    append_node([:constant, value, []])

  -> variable(name)
    if !@variable_names.include?(name)
      raise "unknown arithmetic-circuit variable"
    append_node([:variable, name, []])

  -> require_pair(inputs)
    if inputs.class_name != "Array" || inputs.size != 2
      raise "binary arithmetic-circuit operation needs two node indices"
    inputs

  -> add(inputs)
    append_node([:add, nil, require_pair(inputs)])

  -> subtract(inputs)
    append_node([:subtract, nil, require_pair(inputs)])

  -> multiply(inputs)
    append_node([:multiply, nil, require_pair(inputs)])

  -> divide(inputs)
    append_node([:divide, nil, require_pair(inputs)])

  -> negate(value)
    append_node([:negate, nil, [value]])

  -> set_output(index)
    require_node(index)
    @output_index = index
    self

  -> require_node(index)
    if (!Combinatorics.integer?(index) || index < 0 ||
        index >= @nodes.size)
      raise "arithmetic-circuit node index is out of range"
    index

  -> require_output(output)
    index = output == nil ? @output_index : output
    raise "arithmetic circuit has no output" if index == nil
    require_node(index)

  -> assignment_value(assignments, name)
    if assignments.class_name != "Hash" || !assignments.has_key?(name)
      raise "missing arithmetic-circuit variable assignment: " + name.to_s
    assignments[name]

  -> values_at(assignments, output = nil)
    target = require_output(output)
    reachable = reachable_mask(target)
    values = []
    index = 0
    while index < @nodes.size
      current = @nodes[index]
      if !reachable[index]
        values.push(nil)
      else
        kind = current.kind
        inputs = current.inputs
        if kind == :constant
          values.push(current.payload)
        elsif kind == :variable
          values.push(assignment_value(assignments, current.payload))
        elsif kind == :add
          values.push(values[inputs[0]] + values[inputs[1]])
        elsif kind == :subtract
          values.push(values[inputs[0]] - values[inputs[1]])
        elsif kind == :multiply
          values.push(values[inputs[0]] * values[inputs[1]])
        elsif kind == :divide
          denominator = values[inputs[1]]
          if denominator == 0
            raise "arithmetic circuit is undefined: division by zero"
          values.push(values[inputs[0]] / denominator)
        elsif kind == :negate
          values.push(0 - values[inputs[0]])
        else
          raise "unsupported arithmetic-circuit node kind"
      index += 1
    values

  -> evaluate(assignments)
    index = require_output(nil)
    values_at(assignments, index)[index]

  -> evaluate_at(record)
    if record.class_name != "Array" || record.size != 2
      raise "evaluate_at needs assignments and an output index"
    index = require_output(record[1])
    values_at(record[0], index)[index]

  -> defined_at?(assignments)
    begin
      evaluate(assignments)
    rescue error
      return false
    true

  -> operation_count(output = nil)
    reachable = reachable_mask(require_output(output))
    count = 0
    i = 0
    while i < @nodes.size
      if reachable[i]
        kind = @nodes[i].kind
        if kind != :constant && kind != :variable
          count += 1
      i += 1
    count

  -> depth(output = nil)
    target = require_output(output)
    depths = []
    @nodes.each -> (current)
      if current.inputs.size == 0
        depths.push(0)
      elsif current.inputs.size == 1
        depths.push(depths[current.inputs[0]] + 1)
      else
        left = depths[current.inputs[0]]
        right = depths[current.inputs[1]]
        maximum = left > right ? left : right
        depths.push(maximum + 1)
    depths[target]

  -> division_free?(output = nil)
    reachable = reachable_mask(require_output(output))
    i = 0
    while i < @nodes.size
      return false if reachable[i] && @nodes[i].kind == :divide
      i += 1
    true

  # True exactly when the reachable DAG has no shared child. A caller that
  # wants repeated variables in a formula must create distinct variable
  # leaves; reusing one variable node is circuit fan-out.
  -> formula?(output = nil)
    target = require_output(output)
    reachable = reachable_mask(target)
    references = []
    @nodes.size.times -> references.push(0)
    i = 0
    while i < @nodes.size
      if reachable[i]
        @nodes[i].inputs.each -> (child)
          references[child] += 1
      i += 1
    i = 0
    while i < @nodes.size
      if reachable[i] && i != target && references[i] > 1
        return false
      i += 1
    true

  -> expanded_formula_size(limit = 16_777_216, output = nil)
    Combinatorics.require_nonnegative_integer(limit, "formula size limit")
    target = require_output(output)
    reachable = reachable_mask(target)
    sizes = []
    index = 0
    while index < @nodes.size
      current = @nodes[index]
      if !reachable[index]
        sizes.push(nil)
      elsif current.inputs.size == 0
        sizes.push(0)
      elsif current.inputs.size == 1
        sizes.push(sizes[current.inputs[0]] + 1)
      else
        size = sizes[current.inputs[0]] + sizes[current.inputs[1]] + 1
        if size > limit
          raise "expanded arithmetic formula exceeds its explicit size limit"
        sizes.push(size)
      index += 1
    sizes[target]

  # Syntactic total-degree upper bound for division-free circuits.
  -> degree_bound(output = nil)
    target = require_output(output)
    reachable = reachable_mask(target)
    degrees = []
    index = 0
    while index < @nodes.size
      current = @nodes[index]
      if !reachable[index]
        degrees.push(nil)
      else
        kind = current.kind
        inputs = current.inputs
        if kind == :constant
          degrees.push(0)
        elsif kind == :variable
          degrees.push(1)
        elsif kind == :add || kind == :subtract
          left = degrees[inputs[0]]
          right = degrees[inputs[1]]
          if left == nil || right == nil
            degrees.push(nil)
          else
            degrees.push(left > right ? left : right)
        elsif kind == :multiply
          left = degrees[inputs[0]]
          right = degrees[inputs[1]]
          if left == nil || right == nil
            degrees.push(nil)
          else
            degrees.push(left + right)
        elsif kind == :negate
          degrees.push(degrees[inputs[0]])
        elsif kind == :divide
          degrees.push(nil)
        else
          degrees.push(nil)
      index += 1
    degrees[target]

  -> evaluation_certificate(record)
    if record.class_name != "Array" || record.size != 2
      raise "evaluation certificate needs assignments and a claimed value"
    ArithmeticCircuitEvaluationCertificate.new(
      self, [record[0], record[1], require_output(nil)])

  -> proof_kind
    :exact_finite_arithmetic_circuit_dag

  -> reachable_mask(target)
    reachable = []
    @nodes.size.times -> reachable.push(false)
    stack = [target]
    while stack.size > 0
      index = stack.pop
      if !reachable[index]
        reachable[index] = true
        @nodes[index].inputs.each -> (child)
          stack.push(child)
    reachable


+ ArithmeticCircuitEvaluationCertificate
  -> new(@circuit, record)
    @assignments = {}
    record[0].each -> (name, value)
      @assignments[name] = value
    @claimed_value = record[1]
    @output_index = record[2]

  -> circuit
    @circuit

  -> assignments
    copy = {}
    @assignments.each -> (name, value)
      copy[name] = value
    copy

  -> claimed_value
    @claimed_value

  -> output_index
    @output_index

  -> proof_kind
    :exact_point_evaluation_replay

  -> replay_value
    @circuit.evaluate_at([@assignments, @output_index])

  -> verified?
    value = nil
    begin
      value = self.replay_value
    rescue error
      return false
    value == @claimed_value

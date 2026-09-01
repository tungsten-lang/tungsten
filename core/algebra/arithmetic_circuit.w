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
    # Evaluation tapes are immutable summaries of the reachable prefix for a
    # chosen output. Appending a node invalidates them; repeated evaluations
    # otherwise avoid graph discovery and per-node input-array copies.
    @evaluation_tape_target = nil
    @evaluation_tape = nil

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
    @evaluation_tape_target = nil
    @evaluation_tape = nil
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
    ensure_evaluation_tape(target)
    tape = @evaluation_tape
    node_indices = tape[0]
    opcodes = tape[1]
    left_inputs = tape[2]
    right_inputs = tape[3]
    payloads = tape[4]
    values = []
    @nodes.size.times -> values.push(nil)
    instruction = 0
    while instruction < node_indices.size
      index = node_indices[instruction]
      opcode = opcodes[instruction]
      left = left_inputs[instruction]
      right = right_inputs[instruction]
      payload = payloads[instruction]
      if opcode == 0
        values[index] = payload
      elsif opcode == 1
        values[index] = assignment_value(assignments, payload)
      elsif opcode == 2
        values[index] = values[left] + values[right]
      elsif opcode == 3
        values[index] = values[left] - values[right]
      elsif opcode == 4
        values[index] = values[left] * values[right]
      elsif opcode == 5
        denominator = values[right]
        if denominator == 0
          raise "arithmetic circuit is undefined: division by zero"
        values[index] = values[left] / denominator
      elsif opcode == 6
        values[index] = 0 - values[left]
      else
        raise "unsupported arithmetic-circuit opcode"
      instruction += 1
    values

  # Flat, cached instruction columns. Opcodes are constant=0, variable=1,
  # add=2, subtract=3, multiply=4, divide=5, negate=6.
  -> ensure_evaluation_tape(target)
    if @evaluation_tape != nil && @evaluation_tape_target == target
      return nil
    reachable = reachable_mask(target)
    node_indices = []
    opcodes = []
    left_inputs = []
    right_inputs = []
    payloads = []
    index = 0
    while index < @nodes.size
      if reachable[index]
        current = @nodes[index]
        kind = current.kind
        inputs = current.inputs
        opcode = -1
        if kind == :constant
          opcode = 0
        elsif kind == :variable
          opcode = 1
        elsif kind == :add
          opcode = 2
        elsif kind == :subtract
          opcode = 3
        elsif kind == :multiply
          opcode = 4
        elsif kind == :divide
          opcode = 5
        elsif kind == :negate
          opcode = 6
        else
          raise "unsupported arithmetic-circuit node kind"
        node_indices.push(index)
        opcodes.push(opcode)
        left_inputs.push(inputs.size > 0 ? inputs[0] : -1)
        right_inputs.push(inputs.size > 1 ? inputs[1] : -1)
        payloads.push(current.payload)
      index += 1
    tape = [node_indices, opcodes, left_inputs, right_inputs, payloads]
    # One-entry MRU keeps repeated evaluation allocation-free without an O(n^2)
    # cache when callers probe many different output nodes.
    @evaluation_tape_target = target
    @evaluation_tape = tape
    nil

  # Inspection returns owned columns. The evaluator consumes @evaluation_tape
  # directly so repeated execution remains allocation-free, while callers
  # cannot mutate the cached opcode/input columns and alter later results.
  -> evaluation_tape(target)
    ensure_evaluation_tape(require_node(target))
    out = []
    @evaluation_tape.each -> (column)
      out.push(column.dup)
    out

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

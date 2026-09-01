use core/algebra/arithmetic_circuit

mode = ARGV[0] == nil ? "evaluate" : ARGV[0]
depth = ARGV[1] == nil ? 400 : ARGV[1].to_i
batch_size = ARGV[2] == nil ? 64 : ARGV[2].to_i
repetitions = ARGV[3] == nil ? 400 : ARGV[3].to_i

circuit = ArithmeticCircuit.new([:x, :one])
x = circuit.variable(:x)
one = circuit.variable(:one)
current = x
i = 0
while i < depth
  current = circuit.add([current, one])
  i += 1
circuit.set_output(current)

assignments_batch = []
i = 0
while i < batch_size
  assignments_batch.push({:x => i % 17, :one => 1})
  i += 1

workspace = circuit.evaluation_workspace
batch_workspace = circuit.evaluation_batch_workspace(batch_size)
outputs = []
batch_size.times -> outputs.push(nil)

# Warm every lane before timing so tape construction is outside the sample.
raise "arithmetic-circuit evaluate warmup mismatch" if (
  circuit.evaluate(assignments_batch[0]) != depth)
raise "arithmetic-circuit evaluate_into warmup mismatch" if (
  circuit.evaluate_into(assignments_batch[0], workspace) != depth)
circuit.evaluate_batch_into(assignments_batch, outputs, batch_workspace)
raise "arithmetic-circuit batch warmup mismatch" if outputs[0] != depth

checksum = 0
t0 = ccall("__w_clock_ms")
repetition = 0
while repetition < repetitions
  if mode == "evaluate"
    i = 0
    while i < batch_size
      checksum += circuit.evaluate(assignments_batch[i])
      i += 1
  elsif mode == "into"
    i = 0
    while i < batch_size
      checksum += circuit.evaluate_into(assignments_batch[i], workspace)
      i += 1
  elsif mode == "batch_into"
    circuit.evaluate_batch_into(assignments_batch, outputs, batch_workspace)
    i = 0
    while i < batch_size
      checksum += outputs[i]
      i += 1
  else
    raise "unknown arithmetic-circuit batch benchmark mode"
  repetition += 1
t1 = ccall("__w_clock_ms")

one_batch = 0
i = 0
while i < batch_size
  one_batch += depth + (i % 17)
  i += 1
expected = repetitions * one_batch
raise "arithmetic-circuit batch checksum mismatch" if checksum != expected

<< "mode=" + mode
<< "depth=" + depth.to_s
<< "batch_size=" + batch_size.to_s
<< "evaluations=" + (batch_size * repetitions).to_s
<< "checksum=" + checksum.to_s
<< "elapsed_ms=" + (t1 - t0).to_s

use core/algebra/arithmetic_circuit

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

iterations = 2000
t0 = ccall("__w_clock_ms")
i = 0
checksum = 0
while i < iterations
  checksum += circuit.evaluate(assignments)
  i += 1
t1 = ccall("__w_clock_ms")

raise "arithmetic-circuit checksum mismatch" if checksum != 814000
<< "checksum=" + checksum.to_s()
<< "elapsed_ms=" + (t1 - t0).to_s()

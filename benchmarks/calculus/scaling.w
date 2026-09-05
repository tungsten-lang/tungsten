# Native scaling probe. Arguments: add|gk size repetitions.
# Compare binaries compiled from the baseline and candidate with identical flags.
use calculus

mode = argv()[0]
n = argv()[1].to_i
repeats = argv()[2].to_i
checksum = ~0.0
if mode == "add"
  a = Differential.variable(~2.0, n, 0)
  b = Differential.variable(~3.0, n, n - 1)
  repeats.times ->
    c = a + b
    checksum += c.value + c.gradient[0] + c.hessian[0][0]
else
  repeats.times ->
    q = Calculus.integrate_gk15(
      -> (x) Math.sin(~1000000.0*x), ~0.0, ~1.0,
      ~1.0e-30, ~0.0, n, 30*n)
    checksum += q.value + q.intervals
<< checksum

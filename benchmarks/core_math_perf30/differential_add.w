use calculus

dimension = 20
gradient_a = []
gradient_b = []
hessian_a = []
hessian_b = []
i = 0
while i < dimension
  gradient_a.push(i + ~0.25)
  gradient_b.push(i + ~0.75)
  row_a = []
  row_b = []
  j = 0
  while j < dimension
    row_a.push(i * dimension + j + ~0.125)
    row_b.push(i * dimension + j + ~0.875)
    j += 1
  hessian_a.push(row_a)
  hessian_b.push(row_b)
  i += 1

left = Differential.new(~1.25, gradient_a, hessian_a)
right = Differential.new(~2.75, gradient_b, hessian_b)

# Warm the generated path before timing.
warm = left + right
iterations = 120
t0 = ccall("__w_clock_ms")
k = 0
result = warm
while k < iterations
  result = left + right
  k += 1
t1 = ccall("__w_clock_ms")

gradient = result.gradient
hessian = result.hessian
checksum = result.value + gradient[0] + gradient[dimension - 1] + hessian[0][0] + hessian[dimension - 1][dimension - 1]
<< "checksum=" + checksum.to_s()
<< "elapsed_ms=" + (t1 - t0).to_s()

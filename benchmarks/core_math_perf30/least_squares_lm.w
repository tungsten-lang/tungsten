use core/optim

dimension = 16
target = []
i = 0
while i < dimension
  target.push((i + 1) * ~0.25)
  i += 1

residual = -> (x)
  out = []
  j = 0
  while j < dimension
    out.push(x[j] - target[j])
    j += 1
  out

start = []
dimension.times -> start.push(~0.0)

warm = Optim.least_squares(residual, start, 800)
raise "least-squares warmup mismatch" if warm[:fun] > ~1.0e-10

runs = 5
t0 = ccall("__w_clock_ms")
k = 0
result = warm
while k < runs
  result = Optim.least_squares(residual, start, 800)
  k += 1
t1 = ccall("__w_clock_ms")

raise "least-squares objective mismatch" if result[:fun] > ~1.0e-10
checksum = result[:fun]
i = 0
while i < dimension
  checksum += result[:x][i] * (i + 1)
  i += 1
raise "least-squares solution mismatch" if (checksum - ~374.0).abs > ~1.0e-3
<< "checksum=" + checksum.to_s()
<< "objective=" + result[:fun].to_s()
<< "elapsed_ms=" + (t1 - t0).to_s()

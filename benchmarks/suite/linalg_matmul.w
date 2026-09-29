# High-level f32 GEMM: Tensor.matmul → CBLAS (Accelerate / OpenBLAS).
n = 512
k_iters = 8
a = Tensor.zeros_cpu(Tensor.f32, [n, n])
b = Tensor.zeros_cpu(Tensor.f32, [n, n])
i = 0
nn = n * n
while i < nn
  a.buffer[i] = ((i * 31 + 7) % 17).to_f / ~17.0
  b.buffer[i] = ((i * 13 + 3) % 19).to_f / ~19.0
  i = i + 1
c = a.matmul(b)
t0 = clock()
iter = 0
while iter < k_iters
  c = a.matmul(b)
  iter = iter + 1
t1 = clock()
chk = (c.at([0, 0]) * ~1000000.0).to_i
<< chk
<< "elapsed: [t1 - t0]s"

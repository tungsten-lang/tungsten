# Sparse iterative-solve benchmark: 1-D Dirichlet Laplacian.
#
# The matrix has 3n-2 nonzeros and is never densified. The exact solution is
# the all-ones vector, so b = A*1 has nonzero entries only at the boundaries.
#
#   bin/tungsten -o /tmp/sparse_iter benchmarks/sparse/iterative_solve.w
#   /tmp/sparse_iter 10000 jacobi
#   /tmp/sparse_iter 10000 ichol0

use core/sparse

n = 10000
if ARGV.size() > 0
  n = ARGV[0].to_i()

preconditioner = :jacobi
if ARGV.size() > 1
  if ARGV[1] == "none"
    preconditioner = :none
  elsif ARGV[1] == "ichol0"
    preconditioner = :ichol0
  elsif ARGV[1] != "jacobi"
    raise "iterative_solve: preconditioner must be none, jacobi, or ichol0"

ptr = [0]
indices = []
values = []
i = 0
while i < n
  if i > 0
    indices = indices.push(i - 1)
    values = values.push(~-1.0)
  indices = indices.push(i)
  values = values.push(~2.0)
  if i + 1 < n
    indices = indices.push(i + 1)
    values = values.push(~-1.0)
  ptr = ptr.push(values.size())
  i = i + 1

rhs = []
i = 0
while i < n
  value = ~0.0
  if i == 0 || i + 1 == n
    value = ~1.0
  rhs = rhs.push(value)
  i = i + 1

matrix = SparseMatrix.csr(n, n, ptr, indices, values)
max_iterations = n * 10
if max_iterations < 50
  max_iterations = 50
criteria = SparseSolveCriteria.new(~1.0e-8, ~0.0, max_iterations, preconditioner)
t0 = ccall("__w_clock_ms")
result = matrix.cg(rhs, criteria)
elapsed = ccall("__w_clock_ms") - t0

max_error = ~0.0
i = 0
while i < n
  error = result.x[i] - ~1.0
  if error < ~0.0
    error = ~0.0 - error
  if error > max_error
    max_error = error
  i = i + 1

summary = "sparse_cg n=" + n.to_s() + " nnz=" + matrix.nnz.to_s() + " preconditioner=" + preconditioner.to_s()
summary = summary + " status=" + result.status.to_s() + " iterations=" + result.iterations.to_s()
summary = summary + " residual=" + result.residual_norm.to_s() + " max_error=" + max_error.to_s()
<< summary + " elapsed_ms=" + elapsed.to_s()

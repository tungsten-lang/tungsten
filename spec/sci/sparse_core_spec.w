# Portable sparse foundation checks.
# Run both engines:
#   bin/tungsten spec/sci/sparse_core_spec.w
#   bin/tungsten -o /tmp/sparse_core_spec spec/sci/sparse_core_spec.w && /tmp/sparse_core_spec

use core/sparse

-> sparse_expect(label, condition)
  if condition == false
    raise "sparse_core_spec: " + label

-> sparse_near(left, right, tolerance)
  delta = left - right
  if delta < ~0.0
    delta = ~0.0 - delta
  delta <= tolerance

# COO conversion canonicalizes: sort columns, coalesce duplicates, and remove
# a coordinate whose duplicate values cancel.
a = SparseMatrix.coo(2, 3,
  [0, 0, 0, 1],
  [2, 0, 2, 1],
  [~2.0, ~1.0, ~-2.0, ~3.0]).to_csr
sparse_expect("canonical nnz", a.nnz == 2)
sparse_expect("canonical first value", a.at(0, 0) == ~1.0)
sparse_expect("canonical cancelled duplicate", a.at(0, 2) == ~0.0)
sparse_expect("shape", a.shape.to_s() == "\[2, 3\]")

# Constructors own their canonical arrays instead of retaining mutable caller
# storage, and malformed storage fails at the Core boundary.
caller_data = [~4.0]
owned = SparseMatrix.csr(1, 1, [0, 1], [0], caller_data)
caller_data[0] = ~9.0
sparse_expect("constructor copies storage", owned.at(0, 0) == ~4.0)

invalid_rejected = false
begin
  SparseMatrix.csr(2, 2, [0, 2, 1], [0], [~1.0])
rescue error
  invalid_rejected = true
sparse_expect("invalid csr rejected", invalid_rejected)

ragged_rejected = false
begin
  SparseMatrix.from_dense([[~1.0, ~2.0], [~3.0]])
rescue error
  ragged_rejected = true
sparse_expect("ragged dense input rejected", ragged_rejected)

at = a.transpose
sparse_expect("transpose shape", at.shape.to_s() == "\[3, 2\]")
sparse_expect("transpose value", at.at(1, 1) == ~3.0)
buffer = [~99.0, ~99.0]
a.matvec_into([~2.0, ~3.0, ~4.0], buffer)
sparse_expect("reusable matvec output", buffer.to_s() == "\[2, 9\]")

i3 = SparseMatrix.eye(3)
sum = i3.add(i3.scale(~2.0))
sparse_expect("add and scale", sum.diagonal.to_s() == "\[3, 3, 3\]")
product = a.matmul(at)
sparse_expect("sparse product shape", product.shape.to_s() == "\[2, 2\]")
sparse_expect("sparse product 00", product.at(0, 0) == ~1.0)
sparse_expect("sparse product 11", product.at(1, 1) == ~9.0)

rank_one = SparseMatrix.coo(2, 2, [0, 1], [0, 0], [~1.0, ~2.0]).to_csr
sparse_expect("structural rank", rank_one.structural_rank == 1)
sparse_expect("structural full rank", rank_one.structurally_full_rank? == false)
numeric_dependent = SparseMatrix.from_dense([[~1.0, ~1.0], [~2.0, ~2.0]])
sparse_expect("structural rank is pattern-only", numeric_dependent.structural_rank == 2)

# SPD tridiagonal system with exact solution [1, 2, 3].
spd = SparseMatrix.csr(3, 3,
  [0, 2, 5, 7],
  [0, 1, 0, 1, 2, 1, 2],
  [~2.0, ~-1.0, ~-1.0, ~2.0, ~-1.0, ~-1.0, ~2.0])
cg = spd.cg([~0.0, ~0.0, ~4.0])
sparse_expect("cg converged", cg.converged?)
sparse_expect("cg is not certified", cg.certified? == false)
sparse_expect("cg x0", sparse_near(cg.x[0], ~1.0, ~1.0e-8))
sparse_expect("cg x1", sparse_near(cg.x[1], ~2.0, ~1.0e-8))
sparse_expect("cg x2", sparse_near(cg.x[2], ~3.0, ~1.0e-8))

# IC(0) is exact for this tridiagonal SPD pattern. Its construction and both
# triangular applications remain sparse, so CG should finish in one step.
ichol_rule = SparseSolveCriteria.new(~1.0e-10, ~0.0, 10, :ichol0)
ichol_cg = spd.cg([~0.0, ~0.0, ~4.0], ichol_rule)
sparse_expect("ichol0 cg converged", ichol_cg.converged?)
sparse_expect("ichol0 exact-pattern iteration", ichol_cg.iterations == 1)
sparse_expect("ichol0 cg x2", sparse_near(ichol_cg.x[2], ~3.0, ~1.0e-8))

# A 2-D four-node grid produces Cholesky fill outside the CSR pattern, so this
# exercises a genuine incomplete (rather than exact) factorization.
grid = SparseMatrix.from_dense([
  [~4.0, ~-1.0, ~-1.0, ~0.0],
  [~-1.0, ~4.0, ~0.0, ~-1.0],
  [~-1.0, ~0.0, ~4.0, ~-1.0],
  [~0.0, ~-1.0, ~-1.0, ~4.0]])
grid_cg = grid.cg([~-1.0, ~3.0, ~7.0, ~11.0], ichol_rule)
sparse_expect("ichol0 incomplete-pattern converged", grid_cg.converged?)
sparse_expect("ichol0 incomplete-pattern x0", sparse_near(grid_cg.x[0], ~1.0, ~1.0e-8))
sparse_expect("ichol0 incomplete-pattern x3", sparse_near(grid_cg.x[3], ~4.0, ~1.0e-8))

# General nonsymmetric system, again with exact solution [1, 2, 3].
general = SparseMatrix.csr(3, 3,
  [0, 2, 4, 6],
  [0, 1, 1, 2, 0, 2],
  [~4.0, ~1.0, ~3.0, ~1.0, ~2.0, ~5.0])
bi = general.bicgstab([~6.0, ~9.0, ~17.0])
sparse_expect("bicgstab converged", bi.converged?)
sparse_expect("bicgstab x0", sparse_near(bi.x[0], ~1.0, ~1.0e-8))
sparse_expect("bicgstab x1", sparse_near(bi.x[1], ~2.0, ~1.0e-8))
sparse_expect("bicgstab x2", sparse_near(bi.x[2], ~3.0, ~1.0e-8))

stopped = spd.cg([~0.0, ~0.0, ~4.0], SparseSolveCriteria.new(~0.0, ~0.0, 0, :none))
sparse_expect("iteration limit status", stopped.status == :max_iterations)
zero_diagonal = SparseMatrix.from_dense([[~0.0, ~1.0], [~1.0, ~2.0]])
broken = zero_diagonal.bicgstab([~1.0, ~1.0])
sparse_expect("jacobi zero diagonal breakdown", broken.status == :breakdown)

# IC(0) setup rejects matrices outside its explicit contract before iterating:
# exact symmetry and finite positive pivots are required.
asymmetric_ichol = general.bicgstab([~6.0, ~9.0, ~17.0], ichol_rule)
sparse_expect("ichol0 asymmetric breakdown", asymmetric_ichol.status == :breakdown)
sparse_expect("ichol0 asymmetric setup iteration", asymmetric_ichol.iterations == 0)
indefinite = SparseMatrix.from_dense([[~1.0, ~2.0], [~2.0, ~1.0]])
indefinite_ichol = indefinite.cg([~1.0, ~1.0], ichol_rule)
sparse_expect("ichol0 nonpositive pivot breakdown", indefinite_ichol.status == :breakdown)
sparse_expect("ichol0 nonpositive pivot setup iteration", indefinite_ichol.iterations == 0)

unknown_preconditioner_rejected = false
begin
  SparseSolveCriteria.new(~1.0e-8, ~0.0, 10, :ilu0)
rescue error
  unknown_preconditioner_rejected = true
sparse_expect("unknown preconditioner rejected", unknown_preconditioner_rejected)

<< "SPARSE_CORE_OK"

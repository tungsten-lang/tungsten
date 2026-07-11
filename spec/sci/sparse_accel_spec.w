# Apple SparseBLAS SpMV smoke (compiled — needs Accelerate).
# Run: bin/tungsten -o /tmp/spmv spec/sci/sparse_accel_spec.w && /tmp/spmv

use core/blas
use core/sparse

# A = [[2, 0, 1], [0, 3, 0], [4, 0, 5]]  CSR
# x = [1, 1, 1]  → Ax = [3, 3, 9]
A = SparseMatrix.coo(3, 3,
  [0, 0, 1, 2, 2],
  [0, 2, 1, 0, 2],
  [~2.0, ~1.0, ~3.0, ~4.0, ~5.0]).to_csr

pure = A.matvec([~1.0, ~1.0, ~1.0])
<< pure[0]
<< pure[1]
<< pure[2]

# @w_sparse_ pulls Accelerate + sparse/blas bridges after stage-1 rebuild.
acc = A.matvec_accel([~1.0, ~1.0, ~1.0])
<< acc[0]
<< acc[1]
<< acc[2]

ok = pure[0] == acc[0] && pure[1] == acc[1] && pure[2] == acc[2]
if ok
  << "SPARSE_ACCEL_OK"
else
  << "SPARSE_ACCEL_MISMATCH"

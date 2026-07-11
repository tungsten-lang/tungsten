# Apple Sparse Solvers QR/Cholesky smoke (compiled — needs Accelerate).
# Run: bin/tungsten -o /tmp/ssol spec/sci/sparse_solve_spec.w && /tmp/ssol
#
# A = [[2, 0, 1], [0, 3, 0], [4, 0, 5]]
# b = [3, 3, 9]  →  x = [1, 1, 1]  (since A*[1,1,1] = b)

use core/blas
use core/sparse

A = SparseMatrix.coo(3, 3,
  [0, 0, 1, 2, 2],
  [0, 2, 1, 0, 2],
  [~2.0, ~1.0, ~3.0, ~4.0, ~5.0]).to_csr

b = [~3.0, ~3.0, ~9.0]

-> near(a, b)
  d = a - b
  if d < ~0.0
    d = ~0.0 - d
  d < ~1.0e-9

pure = A.solve(b)
<< pure[0]
<< pure[1]
<< pure[2]

qr = A.solve_qr(b)
<< qr[0]
<< qr[1]
<< qr[2]

# SPD diagonal for Cholesky: diag(4, 9, 16), b = [8, 18, 48] → x = [2, 2, 3]
S = SparseMatrix.coo(3, 3,
  [0, 1, 2],
  [0, 1, 2],
  [~4.0, ~9.0, ~16.0])
b2 = [~8.0, ~18.0, ~48.0]
chol = S.solve_chol(b2)
<< chol[0]
<< chol[1]
<< chol[2]

ok = near(pure[0], ~1.0) && near(pure[1], ~1.0) && near(pure[2], ~1.0)
ok = ok && near(qr[0], ~1.0) && near(qr[1], ~1.0) && near(qr[2], ~1.0)
ok = ok && near(chol[0], ~2.0) && near(chol[1], ~2.0) && near(chol[2], ~3.0)
if ok
  << "SPARSE_SOLVE_OK"
else
  << "SPARSE_SOLVE_MISMATCH"

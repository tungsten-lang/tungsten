# Scientific computing smoke tests.
# Run: bin/tungsten spec/sci/smoke_spec.w

use core/linalg
use core/fft
use core/special
use core/stats
use core/autodiff
use core/solve
use core/optim
use core/interpolate
use core/plot
use core/sparse

<< "--- linalg ---"
A = [[~3.0, ~1.0], [~1.0, ~2.0]]
sol = LinAlg.solve(A, [~9.0, ~8.0])
<< sol[0]
<< sol[1]
<< LinAlg.det(A)

C = LinAlg.matmul([[~1.0, ~2.0], [~3.0, ~4.0]], [[~5.0, ~6.0], [~7.0, ~8.0]])
<< C[0][0]
<< C[1][1]

<< "--- fft ---"
re = [~1.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
im = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
ft = FFT.fft(re, im)
<< ft[0][0]
back = FFT.ifft(ft[0], ft[1])
<< back[0][0]

<< "--- special ---"
<< Special.erf(~0.0)
<< Special.gamma(~5.0)
<< Special.logistic(~0.0)

<< "--- stats ---"
<< Stats.mean([~1.0, ~2.0, ~3.0, ~4.0])
<< Stats.norm_pdf(~0.0)
rng = Stats.rng(42)
<< rng.random

<< "--- autodiff ---"
u = Dual.new(~3.0, ~1.0)
p = u * u
<< p.value
<< p.eps

<< "--- solve ode ---"
f = -> (t, y)
  out = []
  out = out.push(~0.0 - y[0])
  out
res = Solve.rk4(f, ~0.0, ~1.0, [~1.0], ~0.05)
<< res[:y][res[:y].size() - 1][0]

<< "--- optim ---"
g = -> (x)
  x * x - ~2.0
<< Optim.root_bisection(g, ~0.0, ~2.0)

<< "--- interpolate ---"
<< Interpolate.linear([~0.0, ~1.0, ~2.0], [~0.0, ~1.0, ~4.0], ~1.5)
<< Interpolate.quad(-> (x) x * x, ~0.0, ~1.0, 200)

<< "--- plot ---"
<< Plot.sparkline([~1.0, ~2.0, ~3.0, ~2.0, ~1.0])

<< "--- sparse ---"
I = Sparse.eye(3)
y = I.matvec([~1.0, ~2.0, ~3.0])
<< y[0]
<< y[2]
<< SparseMatrix.eye(2).nnz

<< "SMOKE DONE"
# SciIO native round-trips: bin/tungsten -o /tmp/ion spec/sci/io_native_spec.w && /tmp/ion

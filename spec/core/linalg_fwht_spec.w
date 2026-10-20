# spec: compiled
use core/blas
use core/linalg
use core/tensor

-> expect(name, cond)
  if cond
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> close?(actual, expected)
  delta = actual - expected
  delta = ~0.0 - delta if delta < ~0.0
  delta < ~0.00001

v = [~1.0, ~2.0, ~3.0, ~4.0]
u = LinAlg.fwht(v, false)
expect("linalg.fwht unnormalized", close?(u[0], ~10.0) && close?(u[1], ~-2.0) && close?(u[2], ~-4.0) && close?(u[3], ~0.0))

y = LinAlg.fwht(v, true)
expect("linalg.fwht normalized", close?(y[0], ~5.0) && close?(y[1], ~-1.0) && close?(y[2], ~-2.0) && close?(y[3], ~0.0))

rt = LinAlg.fwht(y, true)
expect("linalg.fwht involution", close?(rt[0], ~1.0) && close?(rt[1], ~2.0) && close?(rt[2], ~3.0) && close?(rt[3], ~4.0))

h4 = LinAlg.hadamard_matrix(4, true)
row = [[~1.0, ~-2.0, ~0.5, ~3.0]]
prod = LinAlg.matmul(row, h4)
fw = LinAlg.fwht_rows(row, true)
expect("linalg.fwht matches hadamard_matrix", close?(fw[0][0], prod[0][0]) && close?(fw[0][1], prod[0][1]) && close?(fw[0][2], prod[0][2]) && close?(fw[0][3], prod[0][3]))

signs = [~1.0, ~-1.0, ~-1.0, ~1.0, ~-1.0, ~1.0, ~1.0, ~-1.0]
a = [[~1.0, ~2.0, ~3.0, ~4.0, ~-1.0, ~0.5, ~2.5, ~-3.0]]
fwd = LinAlg.block_fwht_rows(a, 4, signs, false)
inv = LinAlg.block_fwht_rows(fwd, 4, signs, true)
all_ok = true
j = 0
while j < 8
  all_ok = false if !close?(inv[0][j], a[0][j])
  j += 1
expect("linalg.block_fwht_rows signed roundtrip", all_ok)

raw_t = f64_array(8)
i = 0
while i < 8
  raw_t[i] = (i + 1).to_f
  i += 1
t = Tensor.wrap_cpu(raw_t, Tensor.f64, [2, 4], [4, 1], 0)
t_signs = [~1.0, ~-1.0, ~1.0, ~-1.0]
tf = t.fwht(4, t_signs, false)
ti = tf.fwht(4, t_signs, true)
expect("tensor.fwht roundtrip row 0", close?(ti.at([0, 0]), ~1.0) && close?(ti.at([0, 3]), ~4.0))
expect("tensor.fwht roundtrip row 1", close?(ti.at([1, 0]), ~5.0) && close?(ti.at([1, 3]), ~8.0))

tx = Tensor.cpu_zeros(Tensor.i8, [2, 4])
tx.write_flat(0, 1)
tx.write_flat(1, -2)
tx.write_flat(2, 3)
tx.write_flat(3, -4)
tx.write_flat(4, 5)
tx.write_flat(5, 6)
tx.write_flat(6, -7)
tx.write_flat(7, 8)

tw = Tensor.cpu_zeros(Tensor.i8, [2, 4])
tw.write_flat(0, 2)
tw.write_flat(1, 1)
tw.write_flat(2, -1)
tw.write_flat(3, 3)
tw.write_flat(4, -3)
tw.write_flat(5, 2)
tw.write_flat(6, 4)
tw.write_flat(7, -1)

ty = tx.linear(tw)
expect("tensor.linear i8->i32 dtype", ty.dtype == Tensor.i32)
expect("tensor.linear i8->i32 values", ty.at([0, 0]) == -15 && ty.at([0, 1]) == 9 && ty.at([1, 0]) == 47 && ty.at([1, 1]) == -39)

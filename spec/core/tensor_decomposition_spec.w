use core/tensor/decomposition

-> check(name, ok)
  if !ok
    << "FAIL " + name
    exit 1
  << "PASS " + name

-> close_tensor(a, b, tolerance = ~1e-9)
  TensorDecomposition.relative_error(a, b) < tolerance

-> orthogonal(f)
  gram = f.transpose.matmul(f)
  i = 0
  while i < gram.shape[0]
    j = 0
    while j < gram.shape[1]
      expected = i == j ? ~1.0 : ~0.0
      return false if (gram.at([i, j]) - expected).abs > ~1e-9
      j += 1
    i += 1
  true

fa = Tensor.from_rows([[~1.0], [~-2.0], [~3.0]], Tensor.f64)
fb = Tensor.from_rows([[~2.0], [~1.0]], Tensor.f64)
fc = Tensor.from_rows([[~-1.0], [~4.0]], Tensor.f64)
x = TensorDecomposition.cp_tensor([~2.5], [fa, fb, fc])
x.unit = "m"
before = TensorDecomposition.copy_tensor(x)
cp = TensorDecomposition.cpd(x, 1)
check("CP rank-one reconstruction", close_tensor(x, cp.reconstruct))
check("CP status and iteration budget", cp.converged? && cp.iterations > 0 && cp.iterations <= 100)
check("CP no certification claim", !cp.certified? && cp.algorithm == :cp_als && cp.rank == 1)
check("CP f64 and units", cp.reconstruct.dtype == Tensor.f64 && cp.reconstruct.unit == "m")
check("CP input not mutated", close_tensor(x, before))
cp.factors.each -> check("CP unit columns", orthogonal(item))
repeat = TensorDecomposition.cpd(x, 1)
check("CP deterministic seed", repeat.weights == cp.weights && close_tensor(repeat.reconstruct, cp.reconstruct))

diagonal = Tensor.zeros_cpu(Tensor.f64, [2, 2, 2])
diagonal.set([0, 0, 0], ~3.0)
diagonal.set([1, 1, 1], ~1.0)
cp2 = TensorDecomposition.cpd(diagonal, 2, 100, ~1e-9, 7)
check("CP rank-two ALS", close_tensor(diagonal, cp2.reconstruct, ~1e-7))
check("CP reported error", (cp2.relative_error - TensorDecomposition.relative_error(diagonal, cp2.reconstruct)).abs < ~1e-10)
cp3 = TensorDecomposition.cpd(diagonal, 3, 100, ~1e-8, 4)
check("CP overcomplete rank supported", cp3.rank == 3 && close_tensor(diagonal, cp3.reconstruct, ~1e-6))

initial = [Tensor.from_rows([[~2.5], [~-5.0], [~7.5]], Tensor.f64), fb, fc]
initial_copy = TensorDecomposition.copy_tensor(initial[0])
supplied = TensorDecomposition.cpd(x, 1, 0, ~1e-8, 1, ~1e-12, initial)
check("CP supplied factors at zero budget", supplied.iterations == 0 && supplied.converged? && close_tensor(x, supplied.reconstruct))
check("CP supplied factors copied", close_tensor(initial[0], initial_copy))
limited = TensorDecomposition.cpd(diagonal, 1, 0)
check("CP budget exhaustion explicit", limited.iterations == 0 && limited.status == :max_iterations && !limited.converged?)
stalled = TensorDecomposition.cpd(diagonal, 1, 100)
check("CP bad-rank stagnation not success", stalled.status == :stalled && !stalled.converged? && stalled.relative_error > ~0.1)

data = Tensor.zeros_cpu(Tensor.f64, [2, 3, 4])
i = 0
while i < data.size
  data.buffer[i] = i.to_f + ~1.0
  i += 1
unfolded = TensorDecomposition.unfold(data, 1)
check("mode unfolding order", unfolded.shape == [3, 8] && unfolded.at([1, 6]) == data.at([1, 1, 2]))
swap = Tensor.from_rows([[~0.0, ~0.0, ~1.0], [~0.0, ~1.0, ~0.0], [~1.0, ~0.0, ~0.0]], Tensor.f64)
swapped = TensorDecomposition.mode_product(data, swap, 1)
check("mode product preserves axis order", swapped.shape == data.shape && swapped.at([1, 0, 2]) == data.at([1, 2, 2]))

tuck = TensorDecomposition.tucker(data, [2, 3, 4])
check("Tucker full-rank reconstruction", close_tensor(data, tuck.reconstruct))
check("Tucker ranks and certificate boundary", tuck.ranks == [2, 3, 4] && !tuck.certified?)
tuck.factors.each -> check("Tucker orthonormal factors", orthogonal(item))
hos = TensorDecomposition.hosvd(diagonal, [1, 1, 1])
check("HOSVD known truncation error", (hos.relative_error - ~1.0 / Math.sqrt(~10.0)).abs < ~1e-10)
check("HOSVD status", hos.algorithm == :hosvd && hos.status == :hosvd && hos.iterations == 0)

noisy = Tensor.zeros_cpu(Tensor.f64, [3, 4, 5])
i = 0
while i < noisy.size
  noisy.buffer[i] = Math.sin(i.to_f * ~0.37) + Math.cos(i.to_f * ~0.13)
  i += 1
h0 = TensorDecomposition.hosvd(noisy, [2, 2, 2])
h1 = TensorDecomposition.tucker(noisy, [2, 2, 2], 10, ~1e-10)
check("HOOI improves HOSVD", h1.relative_error <= h0.relative_error + ~1e-12 && h1.iterations > 0)
check("HOOI error matches reconstruction", (h1.relative_error - TensorDecomposition.relative_error(noisy, h1.reconstruct)).abs < ~1e-10)

wide = Tensor.zeros_cpu(Tensor.f64, [8, 2, 2])
i = 0
while i < wide.size
  wide.buffer[i] = Math.sin(i.to_f)
  i += 1
wide_result = TensorDecomposition.hosvd(wide, [8, 2, 2])
check("Tucker orthogonal completion", orthogonal(wide_result.factors[0]) && close_tensor(wide, wide_result.reconstruct))

four = Tensor.zeros_cpu(Tensor.f32, [2, 2, 2, 3])
i = 0
while i < four.size
  four.buffer[i] = (i % 7).to_f
  i += 1
view = four.permute([3, 1, 0, 2])
four_result = TensorDecomposition.tucker(view, [3, 2, 2, 2])
check("f32 four-dimensional strided view", close_tensor(view, four_result.reconstruct) && four_result.core.dtype == Tensor.f64)
offset_view = data.slice(0, 1, 1).permute([2, 1, 0])
offset_result = TensorDecomposition.hosvd(offset_view, [4, 3, 1])
check("offset and singleton view", close_tensor(offset_view, offset_result.reconstruct))
view_cp = TensorDecomposition.cpd(x.permute([2, 0, 1]), 1)
check("CP strided view", close_tensor(x.permute([2, 0, 1]), view_cp.reconstruct))
matrix = Tensor.from_rows([[~2.0, ~1.0, ~3.0], [~4.0, ~2.0, ~6.0]], Tensor.f64)
check("CP order two", close_tensor(matrix, TensorDecomposition.cpd(matrix, 1).reconstruct))
check("Tucker order two", close_tensor(matrix, TensorDecomposition.hosvd(matrix, [2, 3]).reconstruct))
scales = [~1e200, ~1e-200]
scales.each -> (scale)
  scaled = TensorDecomposition.copy_tensor(x)
  i = 0
  while i < scaled.size
    scaled.buffer[i] *= scale
    i += 1
  check("CP scale robustness", close_tensor(scaled, TensorDecomposition.cpd(scaled, 1).reconstruct))
  check("Tucker scale robustness", close_tensor(scaled, TensorDecomposition.tucker(scaled, [1, 1, 1]).reconstruct))
zero = Tensor.zeros_cpu(Tensor.f64, [2, 3, 2])
zc = TensorDecomposition.cpd(zero, 2)
zt = TensorDecomposition.tucker(zero, [2, 2, 2])
check("zero CP", zc.relative_error == ~0.0 && zc.iterations == 0 && close_tensor(zero, zc.reconstruct))
check("zero Tucker", zt.relative_error == ~0.0 && zt.iterations == 0 && close_tensor(zero, zt.reconstruct))
unit_result = TensorDecomposition.tucker(x, [1, 1, 1])
check("Tucker units", unit_result.core.unit == "m" && unit_result.reconstruct.unit == "m")

failed = false
begin
  TensorDecomposition.cpd(x, 0)
rescue err
  failed = true
check("invalid CP rank rejected", failed)
failed = false
begin
  TensorDecomposition.tucker(x, [4, 1, 1])
rescue err
  failed = true
check("invalid Tucker ranks rejected", failed)
failed = false
begin
  TensorDecomposition.tucker(x, [1, 1, 1], -1)
rescue err
  failed = true
check("invalid iteration budget rejected", failed)
failed = false
begin
  TensorDecomposition.cpd(x, 1, 10, ~0.0)
rescue err
  failed = true
check("invalid tolerance rejected", failed)
bad = Tensor.zeros_cpu(Tensor.f64, [2, 2])
bad.buffer[0] = Math.exp(~1000.0)
failed = false
begin
  TensorDecomposition.cpd(bad, 1)
rescue err
  failed = true
check("nonfinite input rejected", failed)
failed = false
begin
  TensorDecomposition.cpd(data, 1, 10, ~1e-8, 1, ~1.0)
rescue err
  failed = true
check("invalid SVD cutoff rejected", failed)
failed = false
begin
  TensorDecomposition.cpd(data, 1, 10, ~1e-8, 1, ~1e-12, [fa, fb, fc])
rescue err
  failed = true
check("invalid initial factor shape rejected", failed)
failed = false
begin
  TensorDecomposition.hosvd(data, [1, 1])
rescue err
  failed = true
check("wrong Tucker rank count rejected", failed)
failed = false
begin
  TensorDecomposition.cpd(data.slice(0, 0, 0), 1)
rescue err
  failed = true
check("empty axis rejected", failed)
failed = false
begin
  TensorDecomposition.cpd(Tensor.zeros_cpu(Tensor.f64, [3]), 1)
rescue err
  failed = true
check("order-one input rejected", failed)
bad_device = Tensor.new(:metal, data.buffer, data.dtype, data.shape, data.strides, data.offset, nil)
failed = false
begin
  TensorDecomposition.hosvd(bad_device, [1, 1, 1])
rescue err
  failed = true
check("non-CPU input rejected without device access", failed)
<< "tensor_decomposition_spec complete"

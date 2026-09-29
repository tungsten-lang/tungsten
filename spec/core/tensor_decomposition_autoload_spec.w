# All three public classes must be discoverable without an explicit use.
if TensorDecomposition.class_name != "Class" || CPDecomposition.class_name != "Class" || TuckerDecomposition.class_name != "Class"
  << "FAIL decomposition autoload"
  exit 1
x = Tensor.from_rows([[~1.0, ~2.0], [~2.0, ~4.0]], Tensor.f64)
cp = TensorDecomposition.cpd(x, 1)
tucker = TensorDecomposition.tucker(x, [1, 1])
if cp.relative_error > ~1e-8 || tucker.relative_error > ~1e-8
  << "FAIL decomposition autoload execution"
  exit 1
<< "PASS decomposition autoload and execution"

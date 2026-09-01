# Public factor classes must be discoverable through Core without an explicit
# `use core/linalg`; direct references are part of the public API surface.

-> expect(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

expect("linalg DenseLUFactor autoload", DenseLUFactor.class_name == "Class")
expect("linalg DenseCholeskyFactor autoload", DenseCholeskyFactor.class_name == "Class")
expect("linalg DenseQRFactor autoload", DenseQRFactor.class_name == "Class")

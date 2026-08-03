# Core Tensor <-> Koala Matrix bridge benchmark (compiled only).
#
# Run from the repository root:
#   bin/tungsten compile bits/tungsten-koala/benchmarks/tensor_matrix_bridge.w \
#     --out /tmp/koala-tensor-matrix-bridge
#   /tmp/koala-tensor-matrix-bridge
#
# This reports the reusable Core f64 matmul alone and the complete legacy
# Matrix#matmul_accel adapter separately. The two checksums must agree; the
# difference is the intentional nested-row <-> Tensor packing boundary, not a
# second dense-math implementation in Koala.

use koala

-> bridge_matrix(n, salt)
  rows = []
  i = 0
  while i < n
    row = []
    j = 0
    while j < n
      row.push(((i * 17 + j * 31 + salt) % 97).to_f)
      j = j + 1
    rows.push(row)
    i = i + 1
  Matrix.new(rows)

n = 128
rounds = 32
left = bridge_matrix(n, 7)
right = bridge_matrix(n, 19)

# Warm Core linkage and both adapters before starting the timer.
core_left = left.to_tensor
core_right = right.to_tensor
core_product = core_left.matmul(core_right)
bridge_product = left.matmul_accel(right)

started = ccall("__w_clock_ms")
i = 0
while i < rounds
  core_product = core_left.matmul(core_right)
  i = i + 1
core_ms = ccall("__w_clock_ms") - started

started = ccall("__w_clock_ms")
i = 0
while i < rounds
  bridge_product = left.matmul_accel(right)
  i = i + 1
bridge_ms = ccall("__w_clock_ms") - started

core_checksum = core_product.at([0, 0]) + core_product.at([n - 1, n - 1])
bridge_checksum = bridge_product.at(0, 0) + bridge_product.at(n - 1, n - 1)

<< "tensor_matrix_n," + n.to_s
<< "tensor_matrix_rounds," + rounds.to_s
<< "tensor_f64_matmul_ms," + core_ms.to_s
<< "koala_matrix_tensor_bridge_ms," + bridge_ms.to_s
<< "tensor_f64_checksum," + core_checksum.to_s
<< "koala_bridge_checksum," + bridge_checksum.to_s
<< "tensor_matrix_checksums_equal," + (core_checksum == bridge_checksum).to_s

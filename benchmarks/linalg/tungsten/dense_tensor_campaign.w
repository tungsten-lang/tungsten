# Focused correctness and performance probes for the perf30 dense campaign.
#
# Compile once per revision, then select a mode:
#   dense_tensor_campaign cpu-ops
#   dense_tensor_campaign view-oracle
#   dense_tensor_campaign metadata [iterations]
#   dense_tensor_campaign view-matmul [iterations]
#   dense_tensor_campaign unary [iterations]
#   dense_tensor_campaign reductions [iterations]
#   dense_tensor_campaign axis-reductions [iterations]
#   dense_tensor_campaign blas1-scalar [iterations]
#   dense_tensor_campaign blas1-native [iterations]
#   dense_tensor_campaign blas2-scalar [iterations]
#   dense_tensor_campaign blas2-native [iterations]
#   dense_tensor_campaign zeros-cold [side]
#   dense_tensor_campaign zeros-warm [iterations]
#   dense_tensor_campaign matmul-output [iterations]
#   dense_tensor_campaign blas-structured [iterations]
#   dense_tensor_campaign matmul-into [iterations]
#   dense_tensor_campaign softmax-gpu-check [rows] [cols] [threads]
#   dense_tensor_campaign softmax-gpu-bench [serial|parallel] [rows] [cols] [threads] [iterations]
#   dense_tensor_campaign softmax-gpu-paired [rows] [cols] [threads] [iterations] [serial-first|parallel-first]

use core/blas
use core/tensor

-> assert_close(actual, expected, label)
  delta = actual - expected
  delta = ~0.0 - delta if delta < ~0.0
  raise label + ": got " + actual.to_s + ", expected " + expected.to_s if delta > ~0.00001

-> filled_tensor(rows, cols, dtype)
  data = dtype == Tensor.f64 ? f64_array(rows * cols) : f32_array(rows * cols)
  i = 0
  while i < rows * cols
    data[i] = ((i % 97) + 1).to_f / ~97.0
    i += 1
  Tensor.wrap_cpu(data, dtype, [rows, cols], [cols, 1], 0)

-> filled_gpu_tensor(rows, cols)
  device = metal_device()
  data = metal_array(-32, rows * cols)
  i = 0
  while i < rows * cols
    # Cover a broad finite input range while keeping every row distinct.
    data[i] = (((i * 13 + i / cols * 17) % 257) - 128).to_f / ~17.0
    i += 1
  [Tensor.from_array(device, data, Tensor.f32, [rows, cols]), data]

-> scalar_dot_f64(a, b, n)
  total = ~0.0
  i = 0
  while i < n
    total += a[i] * b[i]
    i += 1
  total

-> scalar_gemv_f64(a, x, y, rows, cols)
  i = 0
  while i < rows
    total = ~0.0
    j = 0
    while j < cols
      total += a[i * cols + j] * x[j]
      j += 1
    y[i] = total
    i += 1
  y

-> scalar_scal_f64(alpha, x, n)
  i = 0
  while i < n
    x[i] = alpha * x[i]
    i += 1
  x

-> scalar_symv_f64(a, x, y, n)
  i = 0
  while i < n
    total = ~0.0
    j = 0
    while j < n
      total += a[i * n + j] * x[j]
      j += 1
    y[i] = total
    i += 1
  y

-> scalar_trsm_lower_f64(a, b, m, n)
  col = 0
  while col < n
    row = 0
    while row < m
      total = b[row * n + col]
      k = 0
      while k < row
        total -= a[row * m + k] * b[k * n + col]
        k += 1
      b[row * n + col] = total / a[row * m + row]
      row += 1
    col += 1
  b

mode = ARGV[0]
raise "mode required" if mode == nil

if mode == "cpu-ops"
  x = filled_tensor(2, 3, Tensor.f64)
  scaled = x.scale(~2.0)
  assert_close(scaled.at([1, 2]), ~12.0 / ~97.0, "scale")
  root = scaled.sqrt
  assert_close(root.at([0, 0]), Math.sqrt(~2.0 / ~97.0), "sqrt")
  sums = x.sum_axis(1)
  assert_close(sums.at([0]), ~6.0 / ~97.0, "sum_axis row 0")
  assert_close(sums.at([1]), ~15.0 / ~97.0, "sum_axis row 1")
  maxima = x.max_axis(1)
  assert_close(maxima.at([1]), ~6.0 / ~97.0, "max_axis")
  means = x.mean_axis(1)
  assert_close(means.at([0]), ~2.0 / ~97.0, "mean_axis")
  probabilities = x.softmax(1)
  assert_close(probabilities.sum_axis(1).at([0]), ~1.0, "softmax row 0")
  assert_close(probabilities.sum_axis(1).at([1]), ~1.0, "softmax row 1")
  << "CPU_OPS_OK"
elsif mode == "view-oracle"
  raw = f64_array(8)
  i = 0
  while i < 8
    raw[i] = (i + 1).to_f
    i += 1
  whole = Tensor.wrap_cpu(raw, Tensor.f64, [4, 2], [2, 1], 0)
  view = whole.slice(0, 1, 2)
  ident = Tensor.from_rows([[~1.0, ~0.0], [~0.0, ~1.0]], Tensor.f64)
  product = view.matmul(ident)
  assert_close(product.at([0, 0]), ~3.0, "offset matmul 00")
  assert_close(product.at([0, 1]), ~4.0, "offset matmul 01")
  assert_close(product.at([1, 0]), ~5.0, "offset matmul 10")
  assert_close(product.at([1, 1]), ~6.0, "offset matmul 11")
  left_base = Tensor.from_rows([[~1.0, ~2.0, ~3.0], [~4.0, ~5.0, ~6.0]], Tensor.f64)
  left_t = left_base.transpose
  right = Tensor.from_rows([[~7.0, ~8.0], [~9.0, ~10.0]], Tensor.f64)
  left_t_product = left_t.matmul(right)
  assert_close(left_t_product.at([0, 0]), ~43.0, "left transpose 00")
  assert_close(left_t_product.at([2, 1]), ~84.0, "left transpose 21")
  packed_left = Tensor.from_rows([[~1.0, ~2.0], [~3.0, ~4.0], [~5.0, ~6.0]], Tensor.f64)
  right_base = Tensor.from_rows([[~7.0, ~9.0], [~8.0, ~10.0]], Tensor.f64)
  right_t_product = packed_left.matmul(right_base.transpose)
  assert_close(right_t_product.at([0, 0]), ~25.0, "right transpose 00")
  assert_close(right_t_product.at([2, 1]), ~100.0, "right transpose 21")
  << "VIEW_ORACLE_OK"
elsif mode == "metadata"
  iterations = ARGV[1] == nil ? 1000000 : ARGV[1].to_i
  x = filled_tensor(8, 16, Tensor.f64)
  checksum = 0
  t0 = clock()
  i = 0
  while i < iterations
    checksum += x.size
    checksum += 1 if x.contiguous?
    i += 1
  elapsed = clock() - t0
  << "METADATA ns/op=" + (elapsed * ~1000000000.0 / iterations).round(2).to_s + " checksum=" + checksum.to_s
elsif mode == "view-matmul"
  iterations = ARGV[1] == nil ? 20 : ARGV[1].to_i
  # The logical left operand is 192x128, represented as the zero-copy
  # transpose of a packed 128x192 tensor. The old route materializes that
  # view on every matmul call before entering dgemm.
  left = filled_tensor(128, 192, Tensor.f64).transpose
  right = filled_tensor(128, 160, Tensor.f64)
  product = nil
  t0 = clock()
  i = 0
  while i < iterations
    product = left.matmul(right)
    i += 1
  elapsed = clock() - t0
  raise "view matmul produced wrong shape" if product.shape != [192, 160]
  << "VIEW_MATMUL ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + product.at([0, 0]).round(6).to_s
elsif mode == "unary"
  iterations = ARGV[1] == nil ? 20 : ARGV[1].to_i
  x = filled_tensor(256, 256, Tensor.f64)
  y = nil
  t0 = clock()
  i = 0
  while i < iterations
    y = x.exp
    i += 1
  elapsed = clock() - t0
  assert_close(y.at([0, 0]), Math.exp(~1.0 / ~97.0), "unary exp")
  << "UNARY ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s
elsif mode == "reductions"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  x = filled_tensor(256, 256, Tensor.f64)
  checksum = ~0.0
  t0 = clock()
  i = 0
  while i < iterations
    checksum += x.sum
    i += 1
  elapsed = clock() - t0
  << "REDUCTIONS ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + checksum.round(3).to_s
elsif mode == "axis-reductions"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  x = filled_tensor(256, 256, Tensor.f64)
  sums = nil
  maxima = nil
  t0 = clock()
  i = 0
  while i < iterations
    sums = x.sum_axis(1)
    maxima = x.max_axis(1)
    i += 1
  elapsed = clock() - t0
  assert_close(sums.at([0]), ~118.13402061855675, "axis sum")
  assert_close(maxima.at([0]), ~1.0, "axis max")
  << "AXIS_REDUCTIONS ms/pair=" + (elapsed * ~1000.0 / iterations).round(3).to_s
elsif mode == "blas1-scalar"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  n = 65536
  a = f64_array(n)
  b = f64_array(n)
  i = 0
  while i < n
    a[i] = ((i % 97) + 1).to_f / ~97.0
    b[i] = ((i % 89) + 1).to_f / ~89.0
    i += 1
  answer = ~0.0
  t0 = clock()
  i = 0
  while i < iterations
    answer = scalar_dot_f64(a, b, n)
    i += 1
  elapsed = clock() - t0
  << "BLAS1_SCALAR ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + answer.round(6).to_s
elsif mode == "blas1-native"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  n = 65536
  a = f64_array(n)
  b = f64_array(n)
  i = 0
  while i < n
    a[i] = ((i % 97) + 1).to_f / ~97.0
    b[i] = ((i % 89) + 1).to_f / ~89.0
    i += 1
  answer = ~0.0
  t0 = clock()
  i = 0
  while i < iterations
    answer = ddot(a, b, n)
    i += 1
  elapsed = clock() - t0
  << "BLAS1_NATIVE ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + answer.round(6).to_s + " norm=" + dnrm2(a, n).round(6).to_s
elsif mode == "blas2-scalar"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  rows = 512
  cols = 512
  a = f64_array(rows * cols)
  x = f64_array(cols)
  y = f64_array(rows)
  i = 0
  while i < rows * cols
    a[i] = ((i % 97) + 1).to_f / ~97.0
    i += 1
  i = 0
  while i < cols
    x[i] = ((i % 89) + 1).to_f / ~89.0
    i += 1
  t0 = clock()
  i = 0
  while i < iterations
    scalar_gemv_f64(a, x, y, rows, cols)
    i += 1
  elapsed = clock() - t0
  << "BLAS2_SCALAR ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + y[0].round(6).to_s
elsif mode == "blas2-native"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  rows = 512
  cols = 512
  a = f64_array(rows * cols)
  x = f64_array(cols)
  y = f64_array(rows)
  i = 0
  while i < rows * cols
    a[i] = ((i % 97) + 1).to_f / ~97.0
    i += 1
  i = 0
  while i < cols
    x[i] = ((i % 89) + 1).to_f / ~89.0
    i += 1
  t0 = clock()
  i = 0
  while i < iterations
    dgemv(a, x, y, rows, cols)
    i += 1
  elapsed = clock() - t0
  << "BLAS2_NATIVE ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + y[0].round(6).to_s
elsif mode == "zeros-cold"
  side = ARGV[1] == nil ? 2048 : ARGV[1].to_i
  t0 = clock()
  z = Tensor.zeros_cpu(Tensor.f64, [side, side])
  elapsed = clock() - t0
  assert_close(z.at([0, 0]), ~0.0, "zeros cold first")
  assert_close(z.at([side - 1, side - 1]), ~0.0, "zeros cold last")
  << "ZEROS_COLD ms=" + (elapsed * ~1000.0).round(3).to_s
elsif mode == "zeros-warm"
  iterations = ARGV[1] == nil ? 1000 : ARGV[1].to_i
  z = nil
  t0 = clock()
  i = 0
  while i < iterations
    z = Tensor.zeros_cpu(Tensor.f64, [256, 256])
    i += 1
  elapsed = clock() - t0
  assert_close(z.at([0, 0]), ~0.0, "zeros warm first")
  assert_close(z.at([255, 255]), ~0.0, "zeros warm last")
  << "ZEROS_WARM us/op=" + (elapsed * ~1000000.0 / iterations).round(3).to_s
elsif mode == "matmul-output"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  left = filled_tensor(256, 256, Tensor.f64)
  right = filled_tensor(256, 256, Tensor.f64)
  product = nil
  t0 = clock()
  i = 0
  while i < iterations
    product = left.matmul(right)
    i += 1
  elapsed = clock() - t0
  assert_close(product.at([0, 0]), ~60.19290041449671, "matmul output")
  << "MATMUL_OUTPUT ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s
elsif mode == "blas-structured"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  vec_n = 65536
  scale_ref = f64_array(vec_n)
  scale_native = f64_array(vec_n)
  i = 0
  while i < vec_n
    value = ((i % 97) + 1).to_f / ~97.0
    scale_ref[i] = value
    scale_native[i] = value
    i += 1
  t0 = clock()
  i = 0
  while i < iterations * 10
    scalar_scal_f64(~0.999999, scale_ref, vec_n)
    i += 1
  scale_ref_elapsed = clock() - t0
  t0 = clock()
  i = 0
  while i < iterations * 10
    dscal(~0.999999, scale_native, vec_n)
    i += 1
  scale_native_elapsed = clock() - t0
  assert_close(scale_ref[1234], scale_native[1234], "dscal structured")

  sym_n = 512
  sym = f64_array(sym_n * sym_n)
  sym_x = f64_array(sym_n)
  sym_ref = f64_array(sym_n)
  sym_native = f64_array(sym_n)
  i = 0
  while i < sym_n
    sym_x[i] = ((i % 31) + 1).to_f / ~31.0
    j = i
    while j < sym_n
      value = ((i + j) % 67 + 1).to_f / ~67.0
      sym[i * sym_n + j] = value
      sym[j * sym_n + i] = value
      j += 1
    i += 1
  t0 = clock()
  i = 0
  while i < iterations
    scalar_symv_f64(sym, sym_x, sym_ref, sym_n)
    i += 1
  sym_ref_elapsed = clock() - t0
  t0 = clock()
  i = 0
  while i < iterations
    dsymv(sym, sym_x, sym_native, sym_n)
    i += 1
  sym_native_elapsed = clock() - t0
  assert_close(sym_ref[77], sym_native[77], "dsymv structured")

  rank_n = 256
  rank_k = 256
  rank_a = f64_array(rank_n * rank_k)
  rank_at = f64_array(rank_k * rank_n)
  rank_general = f64_array(rank_n * rank_n)
  rank_structured = f64_array(rank_n * rank_n)
  i = 0
  while i < rank_n
    j = 0
    while j < rank_k
      value = ((i * 7 + j * 11) % 97 + 1).to_f / ~97.0
      rank_a[i * rank_k + j] = value
      rank_at[j * rank_n + i] = value
      j += 1
    i += 1
  t0 = clock()
  i = 0
  while i < iterations
    dgemm(rank_a, rank_at, rank_general, rank_n, rank_n, rank_k)
    i += 1
  syrk_general_elapsed = clock() - t0
  t0 = clock()
  i = 0
  while i < iterations
    dsyrk(rank_a, rank_structured, rank_n, rank_k, ~1.0, ~0.0)
    i += 1
  syrk_structured_elapsed = clock() - t0
  assert_close(rank_general[123], rank_structured[123], "dsyrk structured")

  tri_m = 256
  tri_n = 32
  tri = f64_array(tri_m * tri_m)
  tri_ref = f64_array(tri_m * tri_n)
  tri_native = f64_array(tri_m * tri_n)
  i = 0
  while i < tri_m
    j = 0
    while j <= i
      tri[i * tri_m + j] = i == j ? ~2.0 : (((i + j) % 13) + 1).to_f / ~10000.0
      j += 1
    i += 1
  t0 = clock()
  i = 0
  while i < iterations
    j = 0
    while j < tri_m * tri_n
      tri_ref[j] = ((j % 43) + 1).to_f / ~43.0
      j += 1
    scalar_trsm_lower_f64(tri, tri_ref, tri_m, tri_n)
    i += 1
  trsm_ref_elapsed = clock() - t0
  t0 = clock()
  i = 0
  while i < iterations
    j = 0
    while j < tri_m * tri_n
      tri_native[j] = ((j % 43) + 1).to_f / ~43.0
      j += 1
    dtrsm(tri, tri_native, tri_m, tri_n, ~1.0)
    i += 1
  trsm_native_elapsed = clock() - t0
  assert_close(tri_ref[4000], tri_native[4000], "dtrsm structured")

  << "DSCAL scalar_us=" + (scale_ref_elapsed * ~1000000.0 / (iterations * 10)).to_s + " native_us=" + (scale_native_elapsed * ~1000000.0 / (iterations * 10)).to_s
  << "DSYMV scalar_us=" + (sym_ref_elapsed * ~1000000.0 / iterations).to_s + " native_us=" + (sym_native_elapsed * ~1000000.0 / iterations).to_s
  << "DSYRK dgemm_us=" + (syrk_general_elapsed * ~1000000.0 / iterations).to_s + " native_us=" + (syrk_structured_elapsed * ~1000000.0 / iterations).to_s
  << "DTRSM scalar_us=" + (trsm_ref_elapsed * ~1000000.0 / iterations).to_s + " native_us=" + (trsm_native_elapsed * ~1000000.0 / iterations).to_s
elsif mode == "matmul-into"
  iterations = ARGV[1] == nil ? 10000 : ARGV[1].to_i
  left = filled_tensor(64, 64, Tensor.f64).transpose
  right = filled_tensor(64, 64, Tensor.f64)
  allocated = nil
  t0 = clock()
  i = 0
  while i < iterations
    allocated = left.matmul(right)
    i += 1
  allocated_elapsed = clock() - t0
  into = Tensor.zeros_cpu(Tensor.f64, [64, 64])
  t0 = clock()
  i = 0
  while i < iterations
    left.matmul_into(right, into, ~1.0, ~0.0)
    i += 1
  into_elapsed = clock() - t0
  assert_close(allocated.at([17, 29]), into.at([17, 29]), "matmul_into benchmark")
  scaled = Tensor.zeros_cpu(Tensor.f64, [64, 64])
  scaled.buffer[17 * 64 + 29] = ~10.0
  left.matmul_into(right, scaled, ~2.0, ~0.5)
  assert_close(scaled.at([17, 29]), allocated.at([17, 29]) * ~2.0 + ~5.0, "matmul_into alpha beta")
  << "MATMUL_INTO allocated_us=" + (allocated_elapsed * ~1000000.0 / iterations).to_s + " into_us=" + (into_elapsed * ~1000000.0 / iterations).to_s
elsif mode == "softmax-gpu-check"
  rows = ARGV[1] == nil ? 7 : ARGV[1].to_i
  cols = ARGV[2] == nil ? 1537 : ARGV[2].to_i
  threads = ARGV[3] == nil ? 256 : ARGV[3].to_i
  pair = filled_gpu_tensor(rows, cols)
  x = pair[0]
  input = pair[1]
  serial = x.gpu_softmax_rows_serial()
  cooperative = x.gpu_softmax_rows_parallel(threads)
  max_serial_error = ~0.0
  max_parallel_error = ~0.0
  max_pair_error = ~0.0
  max_row_sum_error = ~0.0
  r = 0
  while r < rows
    mx = input[r * cols]
    c = 1
    while c < cols
      value = input[r * cols + c]
      mx = value if value > mx
      c += 1
    sm = ~0.0
    c = 0
    while c < cols
      sm += Math.exp(input[r * cols + c] - mx)
      c += 1
    row_sum = ~0.0
    c = 0
    while c < cols
      expected = Math.exp(input[r * cols + c] - mx) / sm
      sv = serial.at([r, c])
      pv = cooperative.at([r, c])
      se = (sv - expected).abs
      pe = (pv - expected).abs
      pair_error = (pv - sv).abs
      max_serial_error = se if se > max_serial_error
      max_parallel_error = pe if pe > max_parallel_error
      max_pair_error = pair_error if pair_error > max_pair_error
      row_sum += pv
      c += 1
    row_sum_error = (row_sum - ~1.0).abs
    max_row_sum_error = row_sum_error if row_sum_error > max_row_sum_error
    r += 1
  raise "parallel softmax diverged" if max_parallel_error > ~0.000002 || max_row_sum_error > ~0.00001
  << "SOFTMAX_GPU_CHECK rows=" + rows.to_s + " cols=" + cols.to_s + " threads=" + threads.to_s + " serial_err=" + max_serial_error.to_s + " parallel_err=" + max_parallel_error.to_s + " pair_err=" + max_pair_error.to_s + " row_sum_err=" + max_row_sum_error.to_s
elsif mode == "softmax-gpu-bench"
  variant = ARGV[1]
  rows = ARGV[2] == nil ? 128 : ARGV[2].to_i
  cols = ARGV[3] == nil ? 1024 : ARGV[3].to_i
  threads = ARGV[4] == nil ? 256 : ARGV[4].to_i
  iterations = ARGV[5] == nil ? 1000 : ARGV[5].to_i
  pair = filled_gpu_tensor(rows, cols)
  x = pair[0]
  out = nil
  if variant == "serial"
    out = x.gpu_softmax_rows_serial()
  elsif variant == "parallel"
    out = x.gpu_softmax_rows_parallel(threads)
  else
    raise "softmax-gpu-bench variant must be serial or parallel"
  t0 = clock()
  i = 0
  while i < iterations
    if variant == "serial"
      out = x.gpu_softmax_rows_serial()
    else
      out = x.gpu_softmax_rows_parallel(threads)
    i += 1
  elapsed = clock() - t0
  checksum = out.at([rows / 2, cols / 3])
  << "SOFTMAX_GPU_BENCH variant=" + variant + " rows=" + rows.to_s + " cols=" + cols.to_s + " threads=" + threads.to_s + " us/op=" + (elapsed * ~1000000.0 / iterations).round(3).to_s + " checksum=" + checksum.to_s
elsif mode == "softmax-gpu-paired"
  rows = ARGV[1] == nil ? 128 : ARGV[1].to_i
  cols = ARGV[2] == nil ? 1024 : ARGV[2].to_i
  threads = ARGV[3] == nil ? 256 : ARGV[3].to_i
  iterations = ARGV[4] == nil ? 1000 : ARGV[4].to_i
  order = ARGV[5] == nil ? "serial-first" : ARGV[5]
  pair = filled_gpu_tensor(rows, cols)
  x = pair[0]
  serial = x.gpu_softmax_rows_serial()
  cooperative = x.gpu_softmax_rows_parallel(threads)
  serial_elapsed = ~0.0
  cooperative_elapsed = ~0.0
  if order == "serial-first"
    t0 = clock()
    i = 0
    while i < iterations
      serial = x.gpu_softmax_rows_serial()
      i += 1
    serial_elapsed = clock() - t0
    t0 = clock()
    i = 0
    while i < iterations
      cooperative = x.gpu_softmax_rows_parallel(threads)
      i += 1
    cooperative_elapsed = clock() - t0
  elsif order == "parallel-first"
    t0 = clock()
    i = 0
    while i < iterations
      cooperative = x.gpu_softmax_rows_parallel(threads)
      i += 1
    cooperative_elapsed = clock() - t0
    t0 = clock()
    i = 0
    while i < iterations
      serial = x.gpu_softmax_rows_serial()
      i += 1
    serial_elapsed = clock() - t0
  else
    raise "softmax-gpu-paired order must be serial-first or parallel-first"
  serial_checksum = serial.at([rows / 2, cols / 3])
  parallel_checksum = cooperative.at([rows / 2, cols / 3])
  raise "softmax paired checksum mismatch" if (serial_checksum - parallel_checksum).abs > ~0.000002
  << "SOFTMAX_GPU_PAIRED rows=" + rows.to_s + " cols=" + cols.to_s + " threads=" + threads.to_s + " serial_us=" + (serial_elapsed * ~1000000.0 / iterations).round(3).to_s + " parallel_us=" + (cooperative_elapsed * ~1000000.0 / iterations).round(3).to_s + " serial_checksum=" + serial_checksum.to_s + " parallel_checksum=" + parallel_checksum.to_s
else
  raise "unknown mode: " + mode

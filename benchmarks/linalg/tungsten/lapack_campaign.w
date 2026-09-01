# Focused QR/SVD/eigensolver probes for the perf30 dense campaign.

use core/linalg

-> campaign_matrix(m, n)
  out = []
  i = 0
  while i < m
    row = []
    j = 0
    while j < n
      value = ((i * 17 + j * 13) % 101).to_f / ~101.0
      value += ~2.0 if i == j
      row.push(value)
      j += 1
    out.push(row)
    i += 1
  out

-> qr_errors(a, q, r)
  m = a.size()
  n = a[0].size()
  orth = ~0.0
  i = 0
  while i < n
    j = 0
    while j < n
      value = ~0.0
      k = 0
      while k < m
        value += q[k][i] * q[k][j]
        k += 1
      target = i == j ? ~1.0 : ~0.0
      error = (value - target).abs
      orth = error if error > orth
      j += 1
    i += 1
  recon = ~0.0
  i = 0
  while i < m
    j = 0
    while j < n
      value = ~0.0
      k = 0
      while k < n
        value += q[i][k] * r[k][j]
        k += 1
      error = (value - a[i][j]).abs
      recon = error if error > recon
      j += 1
    i += 1
  [orth, recon]

-> symmetric_matrix(n)
  a = campaign_matrix(n, n)
  out = []
  i = 0
  while i < n
    row = []
    j = 0
    while j < n
      row.push((a[i][j] + a[j][i]) / ~2.0)
      j += 1
    out.push(row)
    i += 1
  out

-> spd_matrix(n)
  out = []
  i = 0
  while i < n
    row = []
    j = 0
    while j < n
      value = ((i + j) % 29 + 1).to_f / (~100.0 * n)
      value += ~2.0 if i == j
      row.push(value)
      j += 1
    out.push(row)
    i += 1
  out

mode = ARGV[0]
raise "mode required" if mode == nil

if mode == "qr" || mode == "qr-reference" || mode == "qr-lapack"
  iterations = ARGV[1] == nil ? 10 : ARGV[1].to_i
  m = ARGV[2] == nil ? 128 : ARGV[2].to_i
  n = ARGV[3] == nil ? 64 : ARGV[3].to_i
  a = campaign_matrix(m, n)
  result = nil
  started = clock()
  i = 0
  while i < iterations
    if mode == "qr-reference"
      result = LinAlg.qr_reference(a)
    elsif mode == "qr-lapack"
      result = LinAlg.qr_lapack(a)
    else
      result = LinAlg.qr(a)
    i += 1
  elapsed = clock() - started
  errors = qr_errors(a, result[0], result[1])
  raise "QR orthogonality error " + errors[0].to_s if errors[0] > ~0.00000001
  raise "QR reconstruction error " + errors[1].to_s if errors[1] > ~0.00000001
  << "QR ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " orth=" + errors[0].to_s + " recon=" + errors[1].to_s
elsif mode == "eigh-general"
  iterations = ARGV[1] == nil ? 20 : ARGV[1].to_i
  n = ARGV[2] == nil ? 96 : ARGV[2].to_i
  a = symmetric_matrix(n)
  values = nil
  started = clock()
  i = 0
  while i < iterations
    values = LinAlg.eigenvalues_lapack(a)
    i += 1
  elapsed = clock() - started
  checksum = ~0.0
  i = 0
  while i < values.size()
    checksum += values[i][0]
    raise "symmetric matrix produced complex eigenvalue" if values[i][1].abs > ~0.00000001
    i += 1
  << "EIGH_GENERAL ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + checksum.round(6).to_s
elsif mode == "eigh-native"
  iterations = ARGV[1] == nil ? 20 : ARGV[1].to_i
  n = ARGV[2] == nil ? 96 : ARGV[2].to_i
  a = symmetric_matrix(n)
  values = nil
  started = clock()
  i = 0
  while i < iterations
    values = LinAlg.eigh_values(a)
    i += 1
  elapsed = clock() - started
  checksum = ~0.0
  i = 0
  while i < values.size()
    checksum += values[i]
    raise "eigh values not sorted" if i > 0 && values[i] < values[i - 1]
    i += 1
  << "EIGH_NATIVE ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + checksum.round(6).to_s
elsif mode == "svd-normal"
  iterations = ARGV[1] == nil ? 20 : ARGV[1].to_i
  m = ARGV[2] == nil ? 128 : ARGV[2].to_i
  n = ARGV[3] == nil ? 64 : ARGV[3].to_i
  a = campaign_matrix(m, n)
  values = nil
  started = clock()
  i = 0
  while i < iterations
    normal = LinAlg.matmul(LinAlg.transpose(a), a)
    values = LinAlg.eigenvalues_lapack(normal)
    i += 1
  elapsed = clock() - started
  checksum = ~0.0
  i = 0
  while i < values.size()
    value = values[i][0]
    value = ~0.0 if value < ~0.0 && value > ~-0.00000001
    raise "normal matrix has negative eigenvalue" if value < ~0.0
    checksum += Math.sqrt(value)
    i += 1
  << "SVD_NORMAL ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + checksum.round(6).to_s
elsif mode == "svd-native"
  iterations = ARGV[1] == nil ? 20 : ARGV[1].to_i
  m = ARGV[2] == nil ? 128 : ARGV[2].to_i
  n = ARGV[3] == nil ? 64 : ARGV[3].to_i
  a = campaign_matrix(m, n)
  values = nil
  started = clock()
  i = 0
  while i < iterations
    values = LinAlg.singular_values(a)
    i += 1
  elapsed = clock() - started
  checksum = ~0.0
  i = 0
  while i < values.size()
    checksum += values[i]
    raise "singular values not sorted" if i > 0 && values[i] > values[i - 1]
    i += 1
  << "SVD_NATIVE ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + checksum.round(6).to_s
elsif mode == "lstsq-normal"
  iterations = ARGV[1] == nil ? 20 : ARGV[1].to_i
  m = ARGV[2] == nil ? 512 : ARGV[2].to_i
  n = ARGV[3] == nil ? 64 : ARGV[3].to_i
  a = campaign_matrix(m, n)
  b = []
  i = 0
  while i < m
    b.push(((i * 19) % 103).to_f / ~103.0)
    i += 1
  solution = nil
  started = clock()
  i = 0
  while i < iterations
    at = LinAlg.transpose(a)
    gram = LinAlg.matmul(at, a)
    rhs = LinAlg.mat_vec(at, b)
    solution = LinAlg.solve(gram, rhs)
    i += 1
  elapsed = clock() - started
  << "LSTSQ_NORMAL ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + solution[0].round(6).to_s
elsif mode == "lstsq-native"
  iterations = ARGV[1] == nil ? 20 : ARGV[1].to_i
  m = ARGV[2] == nil ? 512 : ARGV[2].to_i
  n = ARGV[3] == nil ? 64 : ARGV[3].to_i
  a = campaign_matrix(m, n)
  b = []
  i = 0
  while i < m
    b.push(((i * 19) % 103).to_f / ~103.0)
    i += 1
  solution = nil
  started = clock()
  i = 0
  while i < iterations
    solution = LinAlg.least_squares(a, b)
    i += 1
  elapsed = clock() - started
  << "LSTSQ_NATIVE ms/op=" + (elapsed * ~1000.0 / iterations).round(3).to_s + " checksum=" + solution[0].round(6).to_s
elsif mode == "qr-factor"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  m = ARGV[2] == nil ? 512 : ARGV[2].to_i
  n = ARGV[3] == nil ? 64 : ARGV[3].to_i
  count = ARGV[4] == nil ? 32 : ARGV[4].to_i
  a = campaign_matrix(m, n)
  rhs_list = []
  i = 0
  while i < m
    rhs_list.push(((i * 19) % 103).to_f / ~103.0)
    i += 1

  build_iterations = iterations / 5
  build_iterations = 1 if build_iterations < 1
  started = clock()
  i = 0
  while i < build_iterations
    factor = LinAlg.factor_qr(a)
    i += 1
  build_elapsed = clock() - started
  factor = LinAlg.factor_qr(a)

  ref_solution = nil
  started = clock()
  i = 0
  while i < iterations
    ref_solution = LinAlg.least_squares(a, rhs_list)
    i += 1
  refactor_elapsed = clock() - started

  rhs = ccall("w_array_new_aligned", -64, m)
  out = ccall("w_array_new_aligned", -64, m)
  i = 0
  while i < m
    rhs[i] = rhs_list[i]
    i += 1
  started = clock()
  i = 0
  while i < iterations
    factor.solve_into(rhs, out)
    i += 1
  factor_elapsed = clock() - started
  raise "QR factor mismatch" if (out[0] - ref_solution[0]).abs > ~0.000000001

  many_rhs = ccall("w_array_new_aligned", -64, m * count)
  many_out = ccall("w_array_new_aligned", -64, m * count)
  rhs_vectors = []
  out_vectors = []
  r = 0
  while r < count
    rhs_vector = ccall("w_array_new_aligned", -64, m)
    out_vector = ccall("w_array_new_aligned", -64, m)
    i = 0
    while i < m
      value = rhs[i] + r * ~0.000001
      many_rhs[r * m + i] = value
      rhs_vector[i] = value
      i += 1
    rhs_vectors.push(rhs_vector)
    out_vectors.push(out_vector)
    r += 1
  started = clock()
  i = 0
  while i < iterations
    r = 0
    while r < count
      factor.solve_into(rhs_vectors[r], out_vectors[r])
      r += 1
    i += 1
  sequential_elapsed = clock() - started
  started = clock()
  i = 0
  while i < iterations
    factor.solve_many_into(many_rhs, many_out, count)
    i += 1
  batch_elapsed = clock() - started
  raise "QR batch mismatch" if (many_out[(count - 1) * m] - out_vectors[count - 1][0]).abs > ~0.000000001
  << "QR_FACTOR build_us=" + (build_elapsed * ~1000000.0 / build_iterations).to_s + " refactor_us=" + (refactor_elapsed * ~1000000.0 / iterations).to_s + " solve_into_us=" + (factor_elapsed * ~1000000.0 / iterations).to_s
  << "QR_BATCH sequential_us=" + (sequential_elapsed * ~1000000.0 / iterations).to_s + " batch_us=" + (batch_elapsed * ~1000000.0 / iterations).to_s
elsif mode == "lu-refactor" || mode == "lu-factor" || mode == "lu-factor-into"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  n = ARGV[2] == nil ? 256 : ARGV[2].to_i
  a = campaign_matrix(n, n)
  b = []
  i = 0
  while i < n
    b.push(((i * 19) % 103).to_f / ~103.0)
    i += 1
  factor = LinAlg.factor_lu(a)
  solution = nil
  if mode == "lu-factor-into"
    rhs = ccall("w_array_new_aligned", -64, n)
    solution = ccall("w_array_new_aligned", -64, n)
    i = 0
    while i < n
      rhs[i] = b[i]
      i += 1
  started = clock()
  i = 0
  while i < iterations
    b[0] = ~1.0 + i * ~0.000001
    if mode == "lu-refactor"
      solution = LinAlg.solve(a, b)
    elsif mode == "lu-factor"
      solution = factor.solve(b)
    else
      rhs[0] = b[0]
      factor.solve_into(rhs, solution)
    i += 1
  elapsed = clock() - started
  << "LU " + mode + " us/op=" + (elapsed * ~1000000.0 / iterations).round.to_s + " checksum=" + solution[0].round(6).to_s
elsif mode == "dense-factors"
  iterations = ARGV[1] == nil ? 100 : ARGV[1].to_i
  n = ARGV[2] == nil ? 256 : ARGV[2].to_i
  count = ARGV[3] == nil ? 32 : ARGV[3].to_i
  a = spd_matrix(n)
  build_iterations = iterations / 5
  build_iterations = 1 if build_iterations < 1
  started = clock()
  i = 0
  while i < build_iterations
    lu = LinAlg.factor_lu(a)
    i += 1
  lu_build_elapsed = clock() - started
  started = clock()
  i = 0
  while i < build_iterations
    chol = LinAlg.factor_cholesky(a)
    i += 1
  chol_build_elapsed = clock() - started

  lu = LinAlg.factor_lu(a)
  chol = LinAlg.factor_cholesky(a)
  rhs_vectors = []
  out_vectors = []
  rhs_flat = ccall("w_array_new_aligned", -64, n * count)
  out_flat = ccall("w_array_new_aligned", -64, n * count)
  r = 0
  while r < count
    rhs = ccall("w_array_new_aligned", -64, n)
    out = ccall("w_array_new_aligned", -64, n)
    i = 0
    while i < n
      value = ((r * 17 + i * 13) % 101 + 1).to_f / ~101.0
      rhs[i] = value
      rhs_flat[r * n + i] = value
      i += 1
    rhs_vectors.push(rhs)
    out_vectors.push(out)
    r += 1

  started = clock()
  i = 0
  while i < iterations
    r = 0
    while r < count
      lu.solve_into(rhs_vectors[r], out_vectors[r])
      r += 1
    i += 1
  lu_sequential_elapsed = clock() - started
  started = clock()
  i = 0
  while i < iterations
    lu.solve_many_into(rhs_flat, out_flat, count)
    i += 1
  lu_batch_elapsed = clock() - started
  lu_expected = out_vectors[count - 1][n - 1]
  raise "LU batch mismatch" if (lu_expected - out_flat[(count - 1) * n + n - 1]).abs > ~0.000000001

  started = clock()
  i = 0
  while i < iterations
    r = 0
    while r < count
      chol.solve_into(rhs_vectors[r], out_vectors[r])
      r += 1
    i += 1
  chol_sequential_elapsed = clock() - started
  started = clock()
  i = 0
  while i < iterations
    chol.solve_many_into(rhs_flat, out_flat, count)
    i += 1
  chol_batch_elapsed = clock() - started
  chol_expected = out_vectors[count - 1][n - 1]
  raise "Cholesky batch mismatch" if (chol_expected - out_flat[(count - 1) * n + n - 1]).abs > ~0.000000001

  << "FACTOR_BUILD lu_us=" + (lu_build_elapsed * ~1000000.0 / build_iterations).to_s + " chol_us=" + (chol_build_elapsed * ~1000000.0 / build_iterations).to_s
  << "LU_BATCH sequential_us=" + (lu_sequential_elapsed * ~1000000.0 / iterations).to_s + " batch_us=" + (lu_batch_elapsed * ~1000000.0 / iterations).to_s
  << "CHOL_BATCH sequential_us=" + (chol_sequential_elapsed * ~1000000.0 / iterations).to_s + " batch_us=" + (chol_batch_elapsed * ~1000000.0 / iterations).to_s
else
  raise "unknown mode: " + mode

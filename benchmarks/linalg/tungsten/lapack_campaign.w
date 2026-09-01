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
else
  raise "unknown mode: " + mode

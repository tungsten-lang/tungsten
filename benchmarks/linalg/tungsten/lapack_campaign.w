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
else
  raise "unknown mode: " + mode

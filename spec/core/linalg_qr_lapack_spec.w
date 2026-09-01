use core/linalg

-> expect(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

-> matrix(m, n)
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

a = matrix(16, 8)
qr = LinAlg.qr(a)
qtq = LinAlg.matmul(LinAlg.transpose(qr[0]), qr[0])
reconstructed = LinAlg.matmul(qr[0], qr[1])
expect("linalg.qr lapack orthogonal", (qtq[0][0] - ~1.0).abs < ~0.0000000001 && qtq[0][1].abs < ~0.0000000001)
expect("linalg.qr lapack reconstruct", (reconstructed[0][0] - a[0][0]).abs < ~0.0000000001 && (reconstructed[15][7] - a[15][7]).abs < ~0.0000000001)

dependent = matrix(8, 8)
i = 0
while i < 8
  dependent[i][7] = dependent[i][0]
  i += 1
dependent_qr = LinAlg.qr(dependent)
zero_column = true
i = 0
while i < 8
  zero_column = false if dependent_qr[0][i][7] != ~0.0
  i += 1
expect("linalg.qr dependent fallback", zero_column && dependent_qr[1][7][7] == ~0.0)

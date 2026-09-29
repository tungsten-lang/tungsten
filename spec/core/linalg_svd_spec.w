use core/linalg

-> check(name, ok)
  if !ok
    << "FAIL " + name
    exit 1
  << "PASS " + name

-> check_svd(a)
  pieces = LinAlg.svd(a)
  u = pieces[0]
  s = pieces[1]
  vt = pieces[2]
  us = LinAlg.copy_mat(u)
  i = 0
  while i < u.size
    j = 0
    while j < s.size
      us[i][j] *= s[j]
      j += 1
    i += 1
  replay = LinAlg.matmul(us, vt)
  i = 0
  while i < a.size
    j = 0
    while j < a[i].size
      check("SVD reconstruction", (replay[i][j] - a[i][j]).abs < ~1e-10)
      j += 1
    i += 1
  uu = LinAlg.matmul(LinAlg.transpose(u), u)
  vv = LinAlg.matmul(vt, LinAlg.transpose(vt))
  i = 0
  while i < s.size
    check("SVD nonnegative descending", s[i] >= ~0.0 && (i == 0 || s[i-1] >= s[i]))
    j = 0
    while j < s.size
      target = i == j ? ~1.0 : ~0.0
      check("SVD orthonormal", (uu[i][j]-target).abs < ~1e-10 && (vv[i][j]-target).abs < ~1e-10)
      j += 1
    i += 1

check_svd([[~3.0, ~1.0], [~2.0, ~4.0], [~0.0, ~2.0]])
check_svd([[~3.0, ~1.0, ~2.0], [~0.0, ~4.0, ~1.0]])
check_svd([[~1.0, ~2.0], [~2.0, ~4.0]])
check_svd([[~0.0, ~0.0], [~0.0, ~0.0]])
check_svd([[~7.0]])
check("SVD empty", LinAlg.svd([]) == [[], [], []])
check("SVD zero-width rows", LinAlg.svd([[], []]) == [[[], []], [], []])
failed = false
begin
  LinAlg.svd([[~1.0], [~1.0, ~2.0]])
rescue err
  failed = true
check("SVD ragged rejected", failed)
failed = false
begin
  LinAlg.svd([[], [~1.0]])
rescue err
  failed = true
check("SVD ragged zero-width rejected", failed)
failed = false
begin
  LinAlg.svd([[Math.exp(~1000.0)]])
rescue err
  failed = true
check("SVD infinity rejected", failed)

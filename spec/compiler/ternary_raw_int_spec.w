# Regression (2026-10-21): a ternary over machine ints inside a typed function
# must stay a machine int. `q = c ? lo[j] : hi[j]` was boxed (infer_type had
# no :if arm and int_shaped_node? rejected the conditional), so every
# operation it fed went through the promoting w_* helpers: values past 2^47
# became heap BigInts, about 0.5 MB leaked per call in a hot loop, and the
# result differed from the identical if/else statement form, which wraps at
# 2^64 like the rest of the typed function (and like the interpreter).

-> check(name, got, want)
  if got.to_s() == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want
    exit 1

-> pick_sq(lo, hi, j, c) (i64[] i64[] i64 i64) i64
  q = (c & 1) == 0 ? lo[j] : hi[j]
  q * q

-> pick_sq_stmt(lo, hi, j, c) (i64[] i64[] i64 i64) i64
  if (c & 1) == 0
    q = lo[j]
  else
    q = hi[j]
  q * q

# The corner loop of a box determinant bound (heilbronn_upper's tri_max).
-> corner_max(lo, hi) (i64[] i64[]) i64
  best = 0
  cq = 0
  while cq < 4
    qx = (cq & 1) == 0 ? lo[0] : hi[0]
    qy = (cq & 2) == 0 ? lo[1] : hi[1]
    d = qx * qy - qy * 3
    best = d > best ? d : best
    cq += 1
  best

lo = i64[2]
hi = i64[2]
lo[0] = 3000000000
hi[0] = 5000000000
lo[1] = 1000000000
hi[1] = 1500000000

check("ternary in range", pick_sq(lo, hi, 0, 0), "9000000000000000000")
check("ternary wraps like i64", pick_sq(lo, hi, 0, 1), "6553255926290448384")
check("statement form agrees", pick_sq_stmt(lo, hi, 0, 1), pick_sq(lo, hi, 0, 1).to_s())
check("loop of ternaries", corner_max(lo, hi), "7499999995500000000")

# Outside typed code a ternary of int literals behaves exactly like the
# statement form, including past i64 (whatever that engine does there).
-> scale(c, big)
  x = c ? 3 : 5
  x * big

-> scale_stmt(c, big)
  if c
    x = 3
  else
    x = 5
  x * big

big = 4611686018427387904
check("untyped ternary, small", scale(true, 7), "21")
check("untyped ternary = statement (then)", scale(true, big), scale_stmt(true, big).to_s())
check("untyped ternary = statement (else)", scale(false, big), scale_stmt(false, big).to_s())

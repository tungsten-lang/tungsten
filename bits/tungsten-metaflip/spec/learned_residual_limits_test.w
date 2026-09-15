use ../tools/learned_residual/native/search

model = f64[517]
if fflr_load(__DIR__ + "/../tools/learned_residual/model-v1.mfl", model) != 1
  exit(1)
dims = i64[3]
dims[0] = 2
dims[1] = 2
dims[2] = 2
out = i64[18]
stats = i64[5]
if fflr_search(256, dims, 3, model, out, stats, 12000, 200, "", 1) != 0-2
  << "FAIL invalid high bits"
  exit(1)
if fflr_search(1, dims, 7, model, out, stats, 12000, 200, "", 1) != 0-2
  << "FAIL invalid term budget"
  exit(1)
if fflr_search(129, dims, 1, model, out, stats, 12000, 200, "", 1) != 0-1 || stats[4] != 2
  << "FAIL flattening bound"
  exit(1)
# An existing path is enough to exercise the stop-file predicate, including
# cancellation before the zero/rank-one fast path. This writes nothing.
if fflr_search(1, dims, 1, model, out, stats, 12000, 200, __FILE__, 1) != 0-1 || stats[4] != 7
  << "FAIL cancellation"
  exit(1)
if fflr_search(129, dims, 3, model, out, stats, 1, 200, "", 1) < 0 && stats[4] != 4
  << "FAIL work cap"
  exit(1)
if stats[0] > 1
  << "FAIL work overshoot"
  exit(1)
<< "PASS learned residual limits: malformed core, flattening bound, cancellation, work cap"

# Typed code reading object fields and module-level typed arrays takes the
# inline typed-array path:
# - `@b = h.arr` where `arr` is a field accessor of exactly one class whose
#   ivar is a typed array, and `@d = h.arr ## i32[]`, type @b / @d;
# - `TAB[i]` on a module-level typed array assigned once is read inline
#   inside a typed fn (it went through the dynamic w_index_raw_i64 path).
# This spec pins the values; scripts/test-typed-raw-wire.sh pins the WIRE.

$failures = 0

-> check(label, got, want)
  if got != want
    << "FAIL [label]: got [got], want [want]"
    $failures = $failures + 1

+ FieldHolder
  rw :arr
  -> new(n)
    @arr = i32[n]

+ FieldReader
  -> new(h)
    @b = h.arr
    @d = h.arr ## i32[]
  -> sum_b(n) (i64) i64
    s = 0 ## i64
    i = 0 ## i64
    while i < n
      s += @b[i & 7]
      i += 1
    s
  -> sum_d(n) (i64) i64
    s = 0 ## i64
    i = 0 ## i64
    while i < n
      s += @d[i & 7]
      i += 1
    s

TAB = i32[8]
-> sum_tab(n) (i64) i64
  s = 0 ## i64
  i = 0 ## i64
  while i < n
    s += TAB[i & 7]
    i += 1
  s

h = FieldHolder.new(8)
k = 0
while k < 8
  h.arr[k] = k * 3 - 4
  TAB[k] = 100 - k
  k += 1
r = FieldReader.new(h)
check("field accessor ivar", r.sum_b(16), 2 * (3 * 28 - 32))
check("hinted field ivar", r.sum_d(8), 3 * 28 - 32)
check("module typed array", sum_tab(16), 2 * (800 - 28))

if $failures > 0
  exit(1)
<< "PASS typed field global access"

# spec: compiled -- inline typed-array bounds checks exist only in compiled non-release builds
# Inline typed-array element reads, writes and compound updates check the
# index against the live size outside --release and raise IndexError naming
# the index and the size. (--release keeps them unchecked; the spec suite
# compiles without --release.)

$failures = 0

-> check(label, got, want)
  if got != want
    << "FAIL [label]: got [got], want [want]"
    $failures = $failures + 1

-> read_at(a, i) (i32[] i64) i64
  a[i]

-> write_at(a, i) (u8[] i64) i64
  a[i] = 7
  0

-> bump_at(a, i) (i64[] i64) i64
  a[i] += 1
  a[i]

-> caught(f)
  begin
    f.call
    "none"
  rescue e: IndexError
    e.message

a = i32[5]
u = u8[3]
w = i64[2]
check("read in range", read_at(a, 4), 0)
check("read past end", caught(->() read_at(a, 5)), "index 5 out of bounds for typed array of size 5")
check("read negative", caught(->() read_at(a, -1)), "index -1 out of bounds for typed array of size 5")
check("write past end", caught(->() write_at(u, 3)), "index 3 out of bounds for typed array of size 3")
check("compound in range", bump_at(w, 1), 1)
check("compound past end", caught(->() bump_at(w, 2)), "index 2 out of bounds for typed array of size 2")

if $failures > 0
  exit(1)
<< "PASS typed array bounds check"

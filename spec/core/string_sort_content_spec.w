# String storage must not affect ordering (ropes, flat strings and NUL bytes).
use core/char
-> check(label, got, want)
  if got != want
    << "FAIL " + label + " got " + got.to_s + " want " + want.to_s
    exit 1
  << "PASS " + label

prefix = "00000000000"
one = prefix + "1-one/one.arr:1-one/one.arr"
two_source = prefix + "2-two/sources/alternate.arr:2-two/sources/alternate.arr"
two = prefix + "2-two/two.arr:2-two/two.arr"
ten = "000000000010-ten/ten.arr:10-ten/ten.arr"
src = [two_source, ten, two, one]
want = [one, two_source, two, ten]
check("mixed rope/flat path sort", src.sort, want)
check("rope minimum", src.min, one)
check("rope maximum", src.max, ten)
check("nested rope keys", [[two, 2], [one, 1]].sort, [[one, 1], [two, 2]])
src.sort!
check("in-place rope sort", src, want)

large = []
i = 0
while i < 40
  large.push(ten)
  large.push(two)
  large.push(one)
  i += 1
sorted = large.sort
i = 1
while i < sorted.size
  if sorted[i - 1] > sorted[i]
    << "FAIL large rope ordering"
    exit 1
  i += 1
<< "PASS large rope ordering"

zero = Char.new(0).to_s
az = "a" + zero + "z"
aa = "a" + zero + "a"
check("embedded NUL is content", [az, aa, "a"].sort, ["a", aa, az])

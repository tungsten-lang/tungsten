# Array#slice answers a zero-copy view. Growing one used to raise "typed array
# push: cannot grow a borrowed view"; push/unshift now move the view into its
# own storage first. Writes before the growth alias the parent; the parent never
# sees the pushed elements.

$failures = 0

-> check(label, got, want)
  if got.to_s != want
    << "FAIL [label]: got [got], want [want]"
    $failures = $failures + 1

a = []
k = 0
while k < 300
  a.push(k)
  k += 1
a = a.slice(0, 257)
a.push(1)
check("inferred int slice push size", a.size, "258")
check("inferred int slice push last", a[257], "1")

p = i64[6]
p[0] = 5
v = p.slice(0, 2)
v[1] = 3
check("view aliases before growth", p[1], "3")
v.push(9)
v.unshift(4)
check("grown view", v, "\[4, 5, 3, 9]")
check("parent untouched by growth", p, "\[5, 3, 0, 0, 0, 0]")
v[1] = 77
check("grown view no longer aliases", p[0], "5")

w = [1, 2, 3].slice(1, 2)
w.push(4)
check("plain array slice push", w, "\[2, 3, 4]")

b = u8[4]
bv = b.slice(1, 2)
bv.push(7)
check("u8 slice push size", bv.size, "3")
check("u8 slice push value", bv[2], "7")

if $failures > 0
  exit(1)
<< "PASS array slice view grow"

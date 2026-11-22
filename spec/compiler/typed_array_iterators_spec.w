# Typed-array iterators with a literal block compile to raw index loops with
# no closure, no boxing and no per-element bounds check (the index is proven
# in range when the body cannot resize the array): each, each_with_index,
# each_index, map, map!, reduce, and a.zip(b).each over equal sizes. Values
# must match the generic Enumerable versions the interpreter runs.

$failures = 0

-> check(label, got, want)
  if got != want
    << "FAIL [label]: got [got], want [want]"
    $failures = $failures + 1

-> sum_each(a) (i32[]) i64
  s = 0 ## i64
  a.each -> (v)
    s += v
  s

-> sum_ewi(a) (i32[]) i64
  s = 0 ## i64
  a.each_with_index -> (v, i)
    s += v * i
  s

-> sum_idx(a) (i32[]) i64
  s = 0 ## i64
  a.each_index -> (i)
    s += a[i]
  s

-> doubled(a) (i32[]) i64
  a.map! -> (v) v * 2
  a[1]

-> total(a) (i32[]) i64
  a.reduce(0 ## i64) -> (acc, v) acc + v

-> dot(a, b) (i32[] i32[]) i64
  s = 0 ## i64
  a.zip(b).each -> (x, y)
    s += x * y
  s

-> grow_in_each(a) (i64[]) i64
  n = 0 ## i64
  a.each -> (v)
    n += 1
    a.push(v) if n < 3
  n

a = i32[5]
b = i32[5]
k = 0
while k < 5
  a[k] = k + 1
  b[k] = 10 - k
  k += 1

check("each", sum_each(a), 15)
check("each_with_index", sum_ewi(a), 40)
check("each_index", sum_idx(a), 15)
check("reduce", total(a), 15)
check("zip dot", dot(a, b), 110)
c = a.map -> (v) v + 100
check("map", c.to_s, "\[101, 102, 103, 104, 105]")
check("map leaves receiver", a[0], 1)
check("map!", doubled(a), 4)
check("map! in place", a.to_s, "\[2, 4, 6, 8, 10]")
g = i64[2]
check("resizing body keeps checks", grow_in_each(g) >= 2, true)

if $failures > 0
  exit(1)
<< "PASS typed array iterators"

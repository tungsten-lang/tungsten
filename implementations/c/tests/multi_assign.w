# Multiple assignment: `a, b = b, a`, from an Array, literal lists, nested
# targets, splats, ivar/attribute/index targets. spec/parity/multi_assign_spec.w
# reuses this fixture on the other engines.

a = 1
b = 2
a, b = b, a
<< a
<< b
-> pair
  [10, 20]
x, y = pair()
<< x + y
p, q = 1, 2
<< p * 10 + q
(m, n), o = [[1, 2], 3]
<< m + n * 10 + o * 100
f, *rest = [1, 2, 3, 4]
<< f
<< rest.size
<< rest[2]
*init, last = [1, 2, 3, 4]
<< init.size
<< last
h1, *mid, t1 = [1]
<< h1
<< mid.size
<< t1 == nil
s1, s2 = 5
<< s1
<< s2 == nil
+ Box
  rw :v
  -> new(@v, @w)
  -> swap
    @v, @w = @w, @v
    @v * 10 + @w
bx = Box.new(1, 2)
<< bx.swap
hh = {}
arr = [0, 0]
hh[:k], arr[1], bx.v = 7, 8, 9
<< hh[:k]
<< arr[1]
<< bx.v
i, j = 0, 1
i, j = j, i + j
i, j = j, i + j
<< i * 10 + j
a, (b, *c), d = 1, [2, 3, 4], 5
<< a
<< b
<< c.size
<< d
u, arr[0] = 3, 4
<< u
<< arr[0]

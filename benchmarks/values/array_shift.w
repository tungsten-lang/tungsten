t0 = clock

n = 10000000 ## u32
a = u4[n]

0...n ->
  a.push(i % 10)

b = u4[n]
while a.size > 0
  b.push(a.shift)

t1 = clock
<< "length=[b.size] first=[b[0]] last=[b[n - 1]]"
<< "elapsed: [t1 - t0]s"

# f16 typed-array kernels that only the compiled engine routes (dot/scale —
# same engine surface as bf16; the interpreter has no IC rows for the float
# array reduction/scale family). Run compiled: tungsten -o out <this>; ./out
# The .dot path exercises the NEON fcvtl+fmla widening kernel when n >= 16.

a = f16[4]
a[0] = 1.5
a[1] = -3.25
a[2] = 0.5
a[3] = 2.0

b = f16[4]
b[0] = 2.0
b[1] = 1.0
b[2] = -2.0
b[3] = 0.5

<< "dot " + a.dot(b).to_s()

# scale returns a fresh f16 array; scale! mutates in place.
sc = a.scale(2.0)
<< "scale " + sc[0].to_s() + " " + sc[3].to_s()
a.scale!(0.5)
<< "scale! " + a[0].to_s() + " " + a[1].to_s()

# Long-vector dot: hits the 8-lane NEON loop (n=32 >= 16) plus tail.
n = 32
la = f16[n]
lb = f16[n]
i = 0
while i < n
  la[i] = 0.5
  lb[i] = 2.0
  i += 1
<< "longdot " + la.dot(lb).to_s()

# fastsum / sumsq compiled fast paths.
<< "fastsum " + la.fastsum().to_s()
<< "sumsq " + lb.sumsq().to_s()

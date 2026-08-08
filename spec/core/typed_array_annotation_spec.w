# Redundant `## T[]` annotations on typed-array literals must not fight the
# small-array stack-promotion tier: `a = bf16[4] ## bf16[]` used to seed
# :typed_array_bf16 while the value stack-promoted to a SmallArray, so every
# element access ran heap-WArray offsets against the SmallArray handle and
# segfaulted compiled. Annotated and unannotated forms must behave identically.

a = bf16[4] ## bf16[]
a[0] = 1.5
a[1] = -2.0
<< "bf16 " + a[0].to_s() + " " + a[1].to_s() + " " + a.size().to_s()

h = f16[4] ## f16[]
h[0] = 0.5
h[1] = -3.25
<< "f16 " + h[0].to_s() + " " + h[1].to_s() + " " + h.size().to_s()

b = i8[4] ## i8[]
b[0] = -128
b[1] = 127
<< "i8 " + b[0].to_s() + " " + b[1].to_s() + " " + b.size().to_s()

f = f64[4] ## f64[]
f[0] = 2.5
<< "f64 " + f[0].to_s() + " " + f.size().to_s()

# Large enough that stack promotion declines — the annotation's
# :typed_array_* seeding is the correct tier there and must keep working.
g = f64[512] ## f64[]
g[511] = 9.25
<< "f64big " + g[511].to_s() + " " + g.size().to_s()

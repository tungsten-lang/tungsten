# f16 (IEEE half, ebits -16) typed arrays — storage, conversion, reductions,
# sort, and typed-overload dispatch. Mirrors bf16's depth: storage is u16,
# arithmetic widens through f32 (fcvt on AArch64), so every exactly-
# representable half value round-trips bit-exactly.

-> id_f16(x) (f16) f16
  x

-> tag_f16(x) (f16) i64
  12

a = f16[4]
a[0] = 1.5
a[1] = -3.25
a[2] = 0.5
a[3] = 2.0

<< "roundtrip " + a[0].to_s() + " " + a[1].to_s() + " " + a[2].to_s() + " " + a[3].to_s()

# RNE on an inexact value: 0.1 is not representable in half; the nearest
# half is 0x2E66 = 0.0999755859375.
r = f16[1]
r[0] = 0.1
<< "rne " + r[0].to_s()

# 1.0 + 2^-11 rounds to 1.0 (ties-to-even at the 10-bit mantissa boundary).
t = f16[1]
t[0] = 1.00048828125
<< "tie " + t[0].to_s()

# Reductions. (dot/scale/fastsum are compiled-engine fast paths — matching
# bf16, the interpreter doesn't route them; see f16_array_native_spec.w.)
<< "sum " + a.sum().to_s()
<< "min " + a.min().to_s()
<< "max " + a.max().to_s()

# Typed-overload dispatch on (f16) — unboxed element flows through a user fn.
<< "id " + id_f16(a[0]).to_s()
<< "tag " + tag_f16(a[1]).to_s()

# Sort: negatives before positives, total order.
s = f16[5]
s[0] = 2.5
s[1] = -1.5
s[2] = 0.0
s[3] = -3.0
s[4] = 1.0
sorted = s.sort()
<< "sorted " + sorted[0].to_s() + " " + sorted[1].to_s() + " " + sorted[2].to_s() + " " + sorted[3].to_s() + " " + sorted[4].to_s()

# push / each yield the (widened) float value.
p = f16[0]
p.push(1.5)
p.push(-0.5)
acc = 0.0
p.each -> (v)
  acc = acc + v
<< "each " + acc.to_s()

# Regression (studio engine, 2026-10-22): `a[i] = v ## T` ascribes the stored
# value, exactly as `x = v ## T` does. The parser left the trailing hint for the
# statement wrapper, which ascribed the whole `a[i] = v` call instead, so v went
# into the array unconverted: compiled typed code stored the boxed double's
# bits (a u8 slot read 0 for 100.0, an i64 slot 4637018766331346944) and the
# interpreter stopped with "expected int, got double".

-> iaa_check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit(1)

# The engine's shape: scale u8 pixels in place, rounding through f64.
-> iaa_scale_u8(out, n, s) (u8[] i64 f64) i64
  i = 0
  while i < n
    v = (out[i] ## f64) * s
    out[i] = Math.floor(v + ~0.5) ## i64
    i += 1
  0

-> iaa_store_i64(out, v) (i64[] f64) i64
  out[0] = Math.floor(v + ~0.5) ## i64
  0

-> iaa_store_u16(out, i, v) (u16[] i64 f64) i64
  out[i] = Math.floor(v) ## i64
  0

px = u8[3]
px[0] = 200
px[1] = 100
px[2] = 255
iaa_scale_u8(px, 3, ~0.5)
iaa_check("u8 scaled in place [0]", px[0], 100)
iaa_check("u8 scaled in place [1]", px[1], 50)
iaa_check("u8 scaled in place [2]", px[2], 128)

wide = i64[1]
iaa_store_i64(wide, ~99.7)
iaa_check("i64 slot", wide[0], 100)

half = u16[2]
iaa_store_u16(half, 1, ~65535.9)
iaa_check("u16 slot", half[1], 65535)

# Untyped arrays get the converted Int, not the Float.
xs = [0, 0]
f = ~41.6
xs[1] = Math.floor(f + ~0.5) ## i64
iaa_check("array slot value", xs[1], 42)
iaa_check("array slot type", type(xs[1]), "Int")

# A chained index assignment ascribes the innermost value once.
ys = [0]
zs = [0]
ys[0] = zs[0] = Math.floor(f) ## i64
iaa_check("chained inner", zs[0], 41)
iaa_check("chained outer", ys[0], 41)
iaa_check("chained type", type(ys[0]), "Int")

# Hash element assignment takes the same postfix path.
h = {}
h["k"] = Math.floor(f) ## i64
iaa_check("hash slot type", type(h["k"]), "Int")

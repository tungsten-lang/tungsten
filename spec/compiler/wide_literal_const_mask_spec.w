# spec: compiled -- measures the compiled build's allocations
# A top-level integer constant past the 48-bit inline range (M51 = 2^51 - 1)
# folds to an immediate beside a machine-int operand, so `(r ## i64) & M51`
# stays native.
# Regression: only constants in the inline range folded, so the mask loaded
# the global's boxed value and `&` went generic: the raw operand was boxed
# into a fresh BigInt on every evaluation and never freed (~3 KB per
# curve25519 fe_mul, 14 MB per X25519; it looked like `## u128` boxing).
#
# Run:
#   bin/tungsten spec/compiler/wide_literal_const_mask_spec.w

M51 = 2251799813685247

-> check(name, got, want)
  if got != want
    << "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
    exit 1
  << "PASS " + name

-> carry51(h, f, g) (i64[] i64[] i64[]) i64
  r0 = f[0] * g[0] + f[1] * g[1] ## u128
  c = (r0 >> 51) ## i64
  h[0] = (r0 ## i64) & M51
  r1 = f[1] * g[0] + c ## u128
  h[1] = (r1 ## i64) & M51
  h[2] = (r1 >> 51) ## i64
  0

f = i64[2]
g = i64[2]
h = i64[3]
f[0] = 2251799813685200
f[1] = 2251799813685199
g[0] = 2251799813680000
g[1] = 2251799813680001
carry51(h, f, g)
check("low limb", h[0], 509007)
check("middle limb", h[1], 246560)
check("high limb", h[2], 2251799813679953)

m0 = Process.memory_footprint
i = 0
while i < 200000
  carry51(h, f, g)
  i += 1
grown = (Process.memory_footprint - m0) / 1048576
check("no per-call allocation", grown < 16, true)

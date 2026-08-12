# Elementwise fusion (lowering/ops.w try_fuse_elementwise): trees of f64[]
# DOT ops (.+ .- .* ./) and array sin/cos/sqrt collapse into one raw loop —
# no temporaries, no boxing — with kernel-identical semantics (scalar
# broadcast, size-parity raise, lhs-array requirement). Values here are
# checked against libm-computed scalars, so they hold whether the loop
# stays scalar or LLVM vectorizes it (-fveclib).

n = 8
x = f64[n]
i = 0 ## i64
while i < n
  x[i] = (i + ~1.0) * ~0.25
  i = i + 1

a = ~2.0
b = ~0.5
c = ~0.1

-> close?(u, v)
  Math.abs(u - v) < ~0.0000000001

# Fused broadcast chain + sin — reference values via scalar Math.* calls.
y = (x .* a .+ b).sin() .+ c
ok = true
i = 0 ## i64
while i < n
  ref = Math.sin(a * x[i] + b) + c
  if !close?(y[i], ref)
    ok = false
  i = i + 1
<< (ok ? "PASS fuse.broadcast_sin" : "FAIL fuse.broadcast_sin")

# Fused array-array operands + sqrt.
z = (x .* x .+ x).sqrt()
ok = true
i = 0 ## i64
while i < n
  ref = Math.sqrt(x[i] * x[i] + x[i])
  if !close?(z[i], ref)
    ok = false
  i = i + 1
<< (ok ? "PASS fuse.array_array_sqrt" : "FAIL fuse.array_array_sqrt")

# Bare .cos() on an f64 array (single-libm tree still fuses).
q = x.cos()
<< (close?(q[3], Math.cos(x[3])) ? "PASS fuse.bare_cos" : "FAIL fuse.bare_cos")

# Single DOT op keeps the runtime kernel — values must agree anyway.
w = x .* a
<< (close?(w[3], x[3] * a) ? "PASS fuse.single_op_kernel" : "FAIL fuse.single_op_kernel")

# A fused result is a normal f64[] — feeds another fused tree.
r = (z .* w) ./ ~2.0
<< (close?(r[5], z[5] * w[5] / ~2.0) ? "PASS fuse.chained_result" : "FAIL fuse.chained_result")

# Size mismatch raises with the kernel's message.
short = f64[3]
caught = false
begin
  bad = (x .+ short).sin()
  << bad[0]
rescue e
  caught = true
<< (caught ? "PASS fuse.size_mismatch_raises" : "FAIL fuse.size_mismatch_raises")

# Regression: an unboxed loop counter + float literal must take the float
# path — `i + ~1.0` inside a while loop silently became `i + 0` (the raw-int
# shortcut nanunbox-INTed the boxed float). Guarded by the x[] fill above,
# but assert directly too.
acc = ~0.0
i = 0 ## i64
while i < 3
  acc = acc + (i + ~1.5)
  i = i + 1
<< (close?(acc, ~7.5) ? "PASS loop.counter_plus_float" : "FAIL loop.counter_plus_float " + acc.to_s())

# Math annotations: core-defined Math methods (f64 return annotations) keep
# correct values through float-typed arithmetic.
t = Math.tanh(~0.3) + ~1.0
<< (close?(t, ~1.2913126124515909) ? "PASS math.tanh_annotated" : "FAIL math.tanh_annotated")
h = Math.hypot(~3.0, ~4.0) + ~0.5
<< (close?(h, ~5.5) ? "PASS math.hypot_annotated" : "FAIL math.hypot_annotated")

# Auto-parallel path: n above the MT threshold (32768 default) routes the
# fused loop through the outlined worker + w_fused_parallel_run. Values
# must be identical to the scalar reference.
np = 40000
xp = f64[np]
i = 0 ## i64
while i < np
  xp[i] = (i + ~0.0) / (np + ~0.0) * ~2.0
  i = i + 1
yp = (xp .* a .+ b).sin() .+ c
ok = true
i = 0 ## i64
while i < np
  if !close?(yp[i], Math.sin(a * xp[i] + b) + c)
    ok = false
  i = i + 1
<< (ok ? "PASS fuse.auto_parallel" : "FAIL fuse.auto_parallel")

# f32 trees: arithmetic keeps f32 output (kernel: out ebits = lhs ebits);
# a libm node promotes the output to f64 (kernel: array_map_f64 → -64).
xf = f32[8]
i = 0 ## i64
while i < 8
  xf[i] = (i + ~1.0) * ~0.25
  i = i + 1
yf32 = xf .* ~2.0 .+ ~0.5
<< (close?(yf32[3], ~2.5) ? "PASS fuse.f32_arith" : "FAIL fuse.f32_arith")
yf64 = (xf .* ~2.0).sin() .+ ~0.1
<< (close?(yf64[3], Math.sin(~2.0) + ~0.1) ? "PASS fuse.f32_sin_promotes_f64" : "FAIL fuse.f32_sin_promotes_f64")

# Integer typed-array trees fuse too. Compare each fused expression with the
# same operations split across single-op kernel calls. Besides all storage
# widths, these cases pin intermediate fixed-width wrapping, signed division,
# zero divisors, bitwise ops, shifts, scalar broadcast, and mixed integer
# array widths.
-> same_values?(left, right)
  if left.size() != right.size()
    return false
  j = 0 ## i64
  while j < left.size()
    if left[j] != right[j]
      return false
    j = j + 1
  true

si8 = i8[4]
si8[0] = 120
si8[1] = -120
si8[2] = 10
si8[3] = -11
si8_tmp = si8 .+ 10
si8_ref = si8_tmp ./ 2
si8_fused = (si8 .+ 10) ./ 2
<< (same_values?(si8_fused, si8_ref) ? "PASS fuse.i8_wrap_div" : "FAIL fuse.i8_wrap_div")
si8_sin = si8.sin()
<< (close?(si8_sin[2], Math.sin(~10.0)) ? "PASS fuse.integer_libm_kernel_fallback" : "FAIL fuse.integer_libm_kernel_fallback")

su8 = u8[4]
su8[0] = 250
su8[1] = 1
su8[2] = 128
su8[3] = 0
su8_tmp = su8 .+ 10
su8_ref = su8_tmp .>> 1
su8_fused = (su8 .+ 10) .>> 1
<< (same_values?(su8_fused, su8_ref) ? "PASS fuse.u8_wrap_shift" : "FAIL fuse.u8_wrap_shift")

si16 = i16[4]
su8b = u8[4]
i = 0 ## i64
while i < 4
  si16[i] = (i + 1) * 10000
  su8b[i] = (i + 1) * 7
  i = i + 1
si16_tmp = si16 .+ su8b
si16_ref = si16_tmp .^ 255
si16_fused = (si16 .+ su8b) .^ 255
<< (same_values?(si16_fused, si16_ref) ? "PASS fuse.i16_mixed_xor" : "FAIL fuse.i16_mixed_xor")

su16 = u16[4]
i = 0 ## i64
while i < 4
  su16[i] = 60000 + i
  i = i + 1
su16_tmp = su16 .* 3
su16_ref = su16_tmp .+ 19
su16_fused = (su16 .* 3) .+ 19
<< (same_values?(su16_fused, su16_ref) ? "PASS fuse.u16_wrap_arith" : "FAIL fuse.u16_wrap_arith")

si32 = i32[4]
div32 = i32[4]
si32[0] = -2147483648
si32[1] = -99
si32[2] = 99
si32[3] = 7
div32[0] = -1
div32[1] = 0
div32[2] = 3
div32[3] = 2
si32_tmp = si32 ./ div32
si32_ref = si32_tmp .+ 7
si32_fused = (si32 ./ div32) .+ 7
<< (same_values?(si32_fused, si32_ref) ? "PASS fuse.i32_div_zero" : "FAIL fuse.i32_div_zero")

su32 = u32[4]
i = 0 ## i64
while i < 4
  su32[i] = 4000000000 + i
  i = i + 1
su32_tmp = su32 .<< 3
su32_ref = su32_tmp .| 5
su32_fused = (su32 .<< 3) .| 5
<< (same_values?(su32_fused, su32_ref) ? "PASS fuse.u32_shift_or" : "FAIL fuse.u32_shift_or")

si64 = i64[4]
i = 0 ## i64
while i < 4
  si64[i] = i - 2
  i = i + 1
si64_tmp = si64 .* 11
si64_ref = si64_tmp .- 3
si64_fused = (si64 .* 11) .- 3
<< (same_values?(si64_fused, si64_ref) ? "PASS fuse.i64_arith" : "FAIL fuse.i64_arith")

su64 = u64[4]
i = 0 ## i64
while i < 4
  su64[i] = i + 10
  i = i + 1
su64_tmp = su64 .& 14
su64_ref = su64_tmp .^ 3
su64_fused = (su64 .& 14) .^ 3
<< (same_values?(su64_fused, su64_ref) ? "PASS fuse.u64_bitwise" : "FAIL fuse.u64_bitwise")

short_i64 = i64[3]
integer_caught = false
begin
  bad_i64 = (si64 .+ short_i64) .* 2
  << bad_i64[0]
rescue e
  integer_caught = true
<< (integer_caught ? "PASS fuse.integer_size_mismatch_raises" : "FAIL fuse.integer_size_mismatch_raises")

ni = 40000
parallel_u8 = u8[ni]
i = 0 ## i64
while i < ni
  parallel_u8[i] = i
  i = i + 1
parallel_u8_fused = (parallel_u8 .+ 251) .* 3
parallel_u8_tmp = parallel_u8 .+ 251
parallel_u8_ref = parallel_u8_tmp .* 3
<< (same_values?(parallel_u8_fused, parallel_u8_ref) ? "PASS fuse.integer_auto_parallel" : "FAIL fuse.integer_auto_parallel")

reuse_i64 = si64
k = 0 ## i64
while k < 3
  reuse_i64 = (si64 .* 7) .+ k ## reuse
  k = k + 1
reuse_i64_tmp = si64 .* 7
reuse_i64_ref = reuse_i64_tmp .+ 2
<< (same_values?(reuse_i64, reuse_i64_ref) ? "PASS fuse.integer_reuse_out" : "FAIL fuse.integer_reuse_out")

# `## reuse` on a fused expression: per-site persistent output buffer.
# Values must stay correct across repeated executions (buffer rewritten
# in place each time).
yr = xf
k = 0
while k < 3
  yr = (xp .* a .+ b).sin() .+ c ## reuse
  k = k + 1
ok = true
i = 0 ## i64
while i < np
  if !close?(yr[i], Math.sin(a * xp[i] + b) + c)
    ok = false
  i = i + 1
<< (ok ? "PASS fuse.reuse_out" : "FAIL fuse.reuse_out")

# exp/log/tan array methods — same libm-direct criterion as sin/cos/sqrt
# (their scalar Math.* counterparts are direct math.h intercepts, so array
# and scalar stay bit-identical per element). Fused chains + bare calls.
ex = (xf .* ~2.0).exp() .+ ~0.5
<< (close?(ex[3], Math.exp(~2.0) + ~0.5) ? "PASS fuse.exp" : "FAIL fuse.exp")
lg = (xf .+ ~1.0).log() .* ~2.0
<< (close?(lg[3], Math.log(~2.0) * ~2.0) ? "PASS fuse.log" : "FAIL fuse.log")
tn = (xf .* ~0.3).tan() .+ ~0.1
<< (close?(tn[3], Math.tan(~0.3) + ~0.1) ? "PASS fuse.tan" : "FAIL fuse.tan")
be = xf.exp()
<< (close?(be[2], Math.exp(~0.75)) ? "PASS fuse.bare_exp" : "FAIL fuse.bare_exp")

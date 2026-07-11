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

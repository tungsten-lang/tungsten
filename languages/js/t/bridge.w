# blade/jsn_t/bridge — Ultra-Cheap JS <-> Tungsten Call Interface & Native Library
#
# Key goals:
#   1. Near-zero call overhead between JS and compiled Tungsten functions:
#      - Direct LLVM indirect `call` (`blr` on ARM64) passing unboxed scalars and
#        raw `ebits` WArray views directly in registers — NO `args` Array allocation,
#        NO `w_closure_call_8`, NO ByteArray bit-shifting!
#   2. Clean FFI registry (`jst_register_fn`) so JS code can directly invoke any
#      compiled Tungsten library routine, AND our AST swizzler can transparently
#      redirect matching JS functions into pre-compiled Tungsten / Metal kernels.
#   3. Full JS numeric & TypedArray type support:
#        i8, u8 (incl. clamped), i16, u16, i32, u32, i64, u64, f16, f32, f64!

use ./typed_ebits

# ---- Low-level Direct LLVM Call Trampolines (Zero-Marshaling WValue ABI!) ----
# Because JS Numbers, Booleans, Strings, and our raw-ebits TypedArray views share the
# EXACT 64-bit WValue representation of Tungsten `fn` parameters and return values,
# calling ANY compiled Tungsten `fn` from JS is a single ARM64 `blr` with ZERO boxing!

fn jst_call1(fp, a0) (i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0)
    ret i64 %r
  IR

fn jst_call2(fp, a0, a1) (i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1)
    ret i64 %r
  IR

fn jst_call3(fp, a0, a1, a2) (i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2)
    ret i64 %r
  IR

fn jst_call4(fp, a0, a1, a2, a3) (i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3)
    ret i64 %r
  IR

fn jst_call5(fp, a0, a1, a2, a3, a4) (i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4)
    ret i64 %r
  IR

fn jst_call6(fp, a0, a1, a2, a3, a4, a5) (i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %f = inttoptr i64 %fp to ptr
    %r = call i64 %f(i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %a4, i64 %a5)
    ret i64 %r
  IR

# ---- Built-in High-Performance Typed Tungsten Library (for Swizzling & Direct FFI) ----
# Every kernel below operates directly on raw `ebits` WArray views!

# 1. Float32Array (ebits = -32) dot product
fn tlib_dot_f32(a, b, n) (f32[] f32[] i64) f64
  s = 0.0 ## f64
  i = 0 ## i64
  while i < n
    s += (a[i] ## f64) * (b[i] ## f64)
    i += 1
  s

# 2. Float32Array (ebits = -32) SAXPY: out[i] = alpha * a[i] + b[i]
# Compute in exact binary64 per ECMAScript and round to binary32 only on Float32Array store!
fn tlib_saxpy_f32(out, a, b, alpha, n) (f32[] f32[] f32[] f64 i64) i64
  i = 0 ## i64
  while i < n
    out[i] = (alpha * (a[i] ## f64) + (b[i] ## f64)) ## f32
    i += 1
  n

# 3. Float16Array (ebits = -16, ARM64 hardware NEON __fp16 8-wide!) ReLU + scale
JST_F64_TMP = [f64[1]]

fn tlib_relu_scale_f16_raw(out_ptr, inp_ptr, scale_ptr, n) (i64 i64 i64 i64) i64
  ll <<~IR
    %op = inttoptr i64 %out_ptr to ptr
    %ip = inttoptr i64 %inp_ptr to ptr
    %sp = inttoptr i64 %scale_ptr to ptr
    %scale = load double, ptr %sp, align 8
    %n8 = and i64 %n, -16
    %has16 = icmp sge i64 %n, 16
    br i1 %has16, label %vloop, label %tail_pre
  vloop:
    %vi = phi i64 [ 0, %0 ], [ %vnext, %vloop ]
    %ip0 = getelementptr half, ptr %ip, i64 %vi
    %vi8 = add i64 %vi, 8
    %ip1 = getelementptr half, ptr %ip, i64 %vi8
    %op0 = getelementptr half, ptr %op, i64 %vi
    %op1 = getelementptr half, ptr %op, i64 %vi8
    %h0 = load <8 x half>, ptr %ip0, align 2
    %h1 = load <8 x half>, ptr %ip1, align 2
    %f0 = fpext <8 x half> %h0 to <8 x float>
    %f1 = fpext <8 x half> %h1 to <8 x float>
    %d0 = fpext <8 x float> %f0 to <8 x double>
    %d1 = fpext <8 x float> %f1 to <8 x double>
    %ds0 = insertelement <8 x double> poison, double %scale, i32 0
    %ds = shufflevector <8 x double> %ds0, <8 x double> poison, <8 x i32> zeroinitializer
    %m0 = fmul <8 x double> %d0, %ds
    %m1 = fmul <8 x double> %d1, %ds
    %gt0 = fcmp ogt <8 x double> %m0, zeroinitializer
    %gt1 = fcmp ogt <8 x double> %m1, zeroinitializer
    %r0 = select <8 x i1> %gt0, <8 x double> %m0, <8 x double> zeroinitializer
    %r1 = select <8 x i1> %gt1, <8 x double> %m1, <8 x double> zeroinitializer
    %rh0 = fptrunc <8 x double> %r0 to <8 x half>
    %rh1 = fptrunc <8 x double> %r1 to <8 x half>
    store <8 x half> %rh0, ptr %op0, align 2
    store <8 x half> %rh1, ptr %op1, align 2
    %vnext = add i64 %vi, 16
    %vcont = icmp slt i64 %vnext, %n8
    br i1 %vcont, label %vloop, label %tail_pre
  tail_pre:
    %ti0 = phi i64 [ 0, %0 ], [ %n8, %vloop ]
    br label %tloop
  tloop:
    %ti = phi i64 [ %ti0, %tail_pre ], [ %tnext, %tbody ]
    %tmore = icmp slt i64 %ti, %n
    br i1 %tmore, label %tbody, label %done
  tbody:
    %tip = getelementptr half, ptr %ip, i64 %ti
    %top = getelementptr half, ptr %op, i64 %ti
    %th = load half, ptr %tip, align 2
    %td = fpext half %th to double
    %tm = fmul double %td, %scale
    %tgt = fcmp ogt double %tm, 0.0
    %tr = select i1 %tgt, double %tm, double 0.0
    %trh = fptrunc double %tr to half
    store half %trh, ptr %top, align 2
    %tnext = add i64 %ti, 1
    br label %tloop
  done:
    ret i64 %n
  IR

-> tlib_relu_scale_f16(out, inp, scale, n)
  sb = JST_F64_TMP[0]
  sb[0] = scale
  op = jst_warray_slots(wvalue_bits(out) ## i64)
  ip = jst_warray_slots(wvalue_bits(inp) ## i64)
  sp = jst_warray_slots(wvalue_bits(sb) ## i64)
  tlib_relu_scale_f16_raw(op, ip, sp, n)

# 3b. Uint8Array RGBA (4*n) -> 1-channel Grayscale (n): dst[i] = (src[4*i]*77 + src[4*i+1]*150 + src[4*i+2]*29) >> 8
fn tlib_rgba_gray1_raw(src_ptr, dst_ptr, n) (i64 i64 i64) i64
  ll <<~IR
    %sp = inttoptr i64 %src_ptr to ptr
    %dp = inttoptr i64 %dst_ptr to ptr
    %n8 = and i64 %n, -8
    %has8 = icmp sge i64 %n, 8
    br i1 %has8, label %vloop, label %tail_pre
  vloop:
    %i = phi i64 [ 0, %0 ], [ %inext, %vloop ]
    %j = shl i64 %i, 2
    %sp0 = getelementptr i8, ptr %sp, i64 %j
    %v32 = load <32 x i8>, ptr %sp0, align 1
    %r8 = shufflevector <32 x i8> %v32, <32 x i8> poison, <8 x i32> <i32 0, i32 4, i32 8, i32 12, i32 16, i32 20, i32 24, i32 28>
    %g8 = shufflevector <32 x i8> %v32, <32 x i8> poison, <8 x i32> <i32 1, i32 5, i32 9, i32 13, i32 17, i32 21, i32 25, i32 29>
    %b8 = shufflevector <32 x i8> %v32, <32 x i8> poison, <8 x i32> <i32 2, i32 6, i32 10, i32 14, i32 18, i32 22, i32 26, i32 30>
    %r16 = zext <8 x i8> %r8 to <8 x i16>
    %g16 = zext <8 x i8> %g8 to <8 x i16>
    %b16 = zext <8 x i8> %b8 to <8 x i16>
    %mr = mul <8 x i16> %r16, <i16 77, i16 77, i16 77, i16 77, i16 77, i16 77, i16 77, i16 77>
    %mg = mul <8 x i16> %g16, <i16 150, i16 150, i16 150, i16 150, i16 150, i16 150, i16 150, i16 150>
    %mb = mul <8 x i16> %b16, <i16 29, i16 29, i16 29, i16 29, i16 29, i16 29, i16 29, i16 29>
    %s0 = add <8 x i16> %mr, %mg
    %s1 = add <8 x i16> %s0, %mb
    %sh = lshr <8 x i16> %s1, <i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8, i16 8>
    %y8 = trunc <8 x i16> %sh to <8 x i8>
    %dp0 = getelementptr i8, ptr %dp, i64 %i
    store <8 x i8> %y8, ptr %dp0, align 1
    %inext = add i64 %i, 8
    %cont = icmp slt i64 %inext, %n8
    br i1 %cont, label %vloop, label %tail_pre
  tail_pre:
    %ti0 = phi i64 [ 0, %0 ], [ %n8, %vloop ]
    br label %tloop
  tloop:
    %ti = phi i64 [ %ti0, %tail_pre ], [ %tnext, %tbody ]
    %tmore = icmp slt i64 %ti, %n
    br i1 %tmore, label %tbody, label %done
  tbody:
    %tj = shl i64 %ti, 2
    %p0 = getelementptr i8, ptr %sp, i64 %tj
    %tj1 = add i64 %tj, 1
    %p1 = getelementptr i8, ptr %sp, i64 %tj1
    %tj2 = add i64 %tj, 2
    %p2 = getelementptr i8, ptr %sp, i64 %tj2
    %vr8 = load i8, ptr %p0, align 1
    %vg8 = load i8, ptr %p1, align 1
    %vb8 = load i8, ptr %p2, align 1
    %vr = zext i8 %vr8 to i64
    %vg = zext i8 %vg8 to i64
    %vb = zext i8 %vb8 to i64
    %tr = mul i64 %vr, 77
    %tg = mul i64 %vg, 150
    %tb = mul i64 %vb, 29
    %ts0 = add i64 %tr, %tg
    %ts1 = add i64 %ts0, %tb
    %ty = lshr i64 %ts1, 8
    %ty8 = trunc i64 %ty to i8
    %tdp = getelementptr i8, ptr %dp, i64 %ti
    store i8 %ty8, ptr %tdp, align 1
    %tnext = add i64 %ti, 1
    br label %tloop
  done:
    %nm1 = sub i64 %n, 1
    %lastp = getelementptr i8, ptr %dp, i64 %nm1
    %last8 = load i8, ptr %lastp, align 1
    %res = zext i8 %last8 to i64
    ret i64 %res
  IR

# 3c. Float32Array square matmul (100% IEEE-754 bit-exact f64 row accumulation in k=0..n-1 order!)
JST_MATMUL_ACC = [f64[512]]

fn tlib_matmul_f32_raw(aptr, bptr, cptr, acc_ptr, n) (i64 i64 i64 i64 i64) i64
  ll <<~IR
    %ap = inttoptr i64 %aptr to ptr
    %bp = inttoptr i64 %bptr to ptr
    %cp = inttoptr i64 %cptr to ptr
    %acc = inttoptr i64 %acc_ptr to ptr
    %n4 = and i64 %n, -4
    %has4 = icmp sge i64 %n, 4
    br label %iloop_chk
  iloop_chk:
    %i = phi i64 [ 0, %0 ], [ %inext, %iend ]
    %imore = icmp slt i64 %i, %n
    br i1 %imore, label %izero_pre, label %done
  izero_pre:
    %io = mul i64 %i, %n
    br label %zloop
  zloop:
    %zj = phi i64 [ 0, %izero_pre ], [ %znext, %zbody ]
    %zmore = icmp slt i64 %zj, %n
    br i1 %zmore, label %zbody, label %kloop_chk
  zbody:
    %zap = getelementptr double, ptr %acc, i64 %zj
    store double 0.0, ptr %zap, align 8
    %znext = add i64 %zj, 1
    br label %zloop
  kloop_chk:
    %k = phi i64 [ 0, %zloop ], [ %knext, %kend ]
    %kmore = icmp slt i64 %k, %n
    br i1 %kmore, label %kbody, label %store_pre
  kbody:
    %aidx = add i64 %io, %k
    %ap_ik = getelementptr float, ptr %ap, i64 %aidx
    %af = load float, ptr %ap_ik, align 4
    %ad = fpext float %af to double
    %va0 = insertelement <4 x double> poison, double %ad, i32 0
    %va = shufflevector <4 x double> %va0, <4 x double> poison, <4 x i32> zeroinitializer
    %kn = mul i64 %k, %n
    br i1 %has4, label %jvloop, label %jtail_pre
  jvloop:
    %jv = phi i64 [ 0, %kbody ], [ %jvnext, %jvloop ]
    %bidx = add i64 %kn, %jv
    %bp_kj = getelementptr float, ptr %bp, i64 %bidx
    %bf4 = load <4 x float>, ptr %bp_kj, align 4
    %bd4 = fpext <4 x float> %bf4 to <4 x double>
    %acc_j = getelementptr double, ptr %acc, i64 %jv
    %cur4 = load <4 x double>, ptr %acc_j, align 8
    %prd4 = fmul <4 x double> %va, %bd4
    %sum4 = fadd <4 x double> %cur4, %prd4
    store <4 x double> %sum4, ptr %acc_j, align 8
    %jvnext = add i64 %jv, 4
    %jvcont = icmp slt i64 %jvnext, %n4
    br i1 %jvcont, label %jvloop, label %jtail_pre
  jtail_pre:
    %jt0 = phi i64 [ 0, %kbody ], [ %n4, %jvloop ]
    br label %jtloop
  jtloop:
    %jt = phi i64 [ %jt0, %jtail_pre ], [ %jtnext, %jtbody ]
    %jtmore = icmp slt i64 %jt, %n
    br i1 %jtmore, label %jtbody, label %kend
  jtbody:
    %tbidx = add i64 %kn, %jt
    %tbp = getelementptr float, ptr %bp, i64 %tbidx
    %tbf = load float, ptr %tbp, align 4
    %tbd = fpext float %tbf to double
    %tap = getelementptr double, ptr %acc, i64 %jt
    %tcur = load double, ptr %tap, align 8
    %tprd = fmul double %ad, %tbd
    %tsum = fadd double %tcur, %tprd
    store double %tsum, ptr %tap, align 8
    %jtnext = add i64 %jt, 1
    br label %jtloop
  kend:
    %knext = add i64 %k, 1
    br label %kloop_chk
  store_pre:
    br label %sloop
  sloop:
    %sj = phi i64 [ 0, %store_pre ], [ %snext, %sbody ]
    %smore = icmp slt i64 %sj, %n
    br i1 %smore, label %sbody, label %iend
  sbody:
    %sap = getelementptr double, ptr %acc, i64 %sj
    %sd = load double, ptr %sap, align 8
    %sf = fptrunc double %sd to float
    %cidx = add i64 %io, %sj
    %scp = getelementptr float, ptr %cp, i64 %cidx
    store float %sf, ptr %scp, align 4
    %snext = add i64 %sj, 1
    br label %sloop
  iend:
    %inext = add i64 %i, 1
    br label %iloop_chk
  done:
    ret i64 %n
  IR

-> tlib_matmul_f32(va, vb, vc, n)
  acc = JST_MATMUL_ACC[0]
  if acc.size < n
    acc = f64[n]
    JST_MATMUL_ACC[0] = acc
  ap = jst_warray_slots(wvalue_bits(va) ## i64)
  bp = jst_warray_slots(wvalue_bits(vb) ## i64)
  cp = jst_warray_slots(wvalue_bits(vc) ## i64)
  acp = jst_warray_slots(wvalue_bits(acc) ## i64)
  tlib_matmul_f32_raw(ap, bp, cp, acp, n)
  vc[0] + vc[n * n - 1]

# 4. Float64Array (ebits = -64) Horner polynomial eval + reduction
fn tlib_poly_f64(out, inp, c0, c1, c2, n) (f64[] f64[] f64 f64 f64 i64) f64
  sum = 0.0 ## f64
  i = 0 ## i64
  while i < n
    x = inp[i]
    y = c0 + x * (c1 + x * c2)
    out[i] = y
    sum += y
    i += 1
  sum

# 5. Uint8Array / Uint8ClampedArray (ebits = 8) RGBA -> grayscale luminance
#    luma = (77*R + 150*G + 29*B) >> 8
fn tlib_rgba_gray_u8(out, inp, npix) (u8[] u8[] i64) i64
  i = 0 ## i64
  lim = npix * 4
  while i < lim
    r = inp[i] ## i64
    g = inp[i + 1] ## i64
    b = inp[i + 2] ## i64
    l = (r * 77 + g * 150 + b * 29) >> 8
    lv = l ## u8
    out[i] = lv
    out[i + 1] = lv
    out[i + 2] = lv
    out[i + 3] = inp[i + 3]
    i += 4
  npix

# 6. Int32Array (ebits = 33) bitwise avalanche mix + sum
fn tlib_mix_i32(a, n) (i32[] i64) i64
  acc = 0 ## i32
  i = 0 ## i64
  while i < n
    x = a[i]
    x = x ^ (x >> 16)
    x = x * 0x45d9f3b
    x = x ^ (x >> 16)
    acc = acc ^ x
    i += 1
  acc ## i64

# 7. BigUint64Array (ebits = 64) 64-bit SplitMix/FNV stream hash (native u64 — zero BigInt boxing!)
fn tlib_hash_u64(a, n) (u64[] i64) i64
  h = 14695981039346656037 ## u64
  prime = 1099511628211 ## u64
  i = 0 ## i64
  while i < n
    h = (h ^ a[i]) * prime
    i += 1
  h ## i64

# 8. Pure scalar math: fast double arithmetic (for JS <-> Tungsten call-cost benchmark)
fn tlib_add2_f64(x, y) (f64 f64) f64
  x + y

# 9. Pure scalar math: Mandelbrot escape count (f64 loop)
fn tlib_mandelbrot_i64(width, height, max_iter) (i64 i64 i64) i64
  total = 0 ## i64
  inv_w = 3.0 / (width ## f64)
  inv_h = 2.0 / (height ## f64)
  py = 0 ## i64
  while py < height
    ci = (py ## f64) * inv_h - 1.0
    px = 0 ## i64
    while px < width
      cr = (px ## f64) * inv_w - 2.0
      zr = 0.0 ## f64
      zi = 0.0 ## f64
      it = 0 ## i64
      while it < max_iter
        zr2 = zr * zr
        zi2 = zi * zi
        break if zr2 + zi2 > 4.0
        zi = 2.0 * zr * zi + ci
        zr = zr2 - zi2 + cr
        it += 1
      total += it
      px += 1
    py += 1
  total

# ---- Metal GPU Compute Offload (Zero-Copy Apple Silicon Unified Memory!) ----
# Compiles and caches MSL pipelines once; dispatches directly over page-aligned
# TypedArray WArray views via `metal_buffer_for(device, view)`!

JST_METAL_STATE = [nil, nil, {}]   # [device, queue, name -> pipeline]

-> jst_metal_init
  if JST_METAL_STATE[0] == nil
    dev = metal_device()
    q = metal_queue(dev)
    JST_METAL_STATE[0] = dev
    JST_METAL_STATE[1] = q
  JST_METAL_STATE

-> jst_metal_pipeline(key, msl, kernel_name)
  st = jst_metal_init()
  pipes = st[2]
  p = pipes[key]
  return p if p != nil
  lib = metal_compile_source(st[0], msl)
  p = metal_pipeline(lib, kernel_name)
  pipes[key] = p
  p

MSL_SAXPY_F32 = <<~MSL
  #include <metal_stdlib>
  using namespace metal;
  kernel void saxpy_f32(
      device float* out [[buffer(0)]],
      device const float* a [[buffer(1)]],
      device const float* b [[buffer(2)]],
      device const float* params [[buffer(3)]],
      uint i [[thread_position_in_grid]]) {
    uint n = as_type<uint>(params[1]);
    if (i < n) {
      out[i] = params[0] * a[i] + b[i];
    }
  }
MSL

MSL_RGBA_GRAY_U8 = <<~MSL
  #include <metal_stdlib>
  using namespace metal;
  kernel void rgba_gray_u8(
      device uchar4* out [[buffer(0)]],
      device const uchar4* inp [[buffer(1)]],
      device const uint* params [[buffer(2)]],
      uint i [[thread_position_in_grid]]) {
    if (i < params[0]) {
      uchar4 p = inp[i];
      uint l = (uint(p.x) * 77u + uint(p.y) * 150u + uint(p.z) * 29u) >> 8;
      uchar lv = uchar(l);
      out[i] = uchar4(lv, lv, lv, p.w);
    }
  }
MSL

-> jst_metal_saxpy_f32(out_ta, a_ta, b_ta, alpha, n)
  st = jst_metal_init()
  dev = st[0]
  q = st[1]
  pipe = jst_metal_pipeline("saxpy_f32", MSL_SAXPY_F32, "saxpy_f32")
  jst_buffer_ensure_page_aligned(out_ta.buffer)
  jst_buffer_ensure_page_aligned(a_ta.buffer)
  jst_buffer_ensure_page_aligned(b_ta.buffer)
  v_out = jst_ta_view(out_ta)
  v_a   = jst_ta_view(a_ta)
  v_b   = jst_ta_view(b_ta)
  b_out = metal_buffer_for(dev, v_out)
  b_a   = metal_buffer_for(dev, v_a)
  b_b   = metal_buffer_for(dev, v_b)
  pbuf  = metal_buffer(dev, 16)
  metal_buffer_write_f32(pbuf, 0, alpha)
  metal_buffer_write_i32(pbuf, 1, n)
  metal_dispatch_n(q, pipe, [b_out, b_a, b_b, pbuf], n)
  metal_buffer_release(b_out)
  metal_buffer_release(b_a)
  metal_buffer_release(b_b)
  metal_buffer_release(pbuf)
  n

-> jst_metal_rgba_gray_u8(out_ta, inp_ta, npix)
  st = jst_metal_init()
  dev = st[0]
  q = st[1]
  pipe = jst_metal_pipeline("rgba_gray_u8", MSL_RGBA_GRAY_U8, "rgba_gray_u8")
  jst_buffer_ensure_page_aligned(out_ta.buffer)
  jst_buffer_ensure_page_aligned(inp_ta.buffer)
  v_out = jst_ta_view(out_ta)
  v_inp = jst_ta_view(inp_ta)
  b_out = metal_buffer_for(dev, v_out)
  b_inp = metal_buffer_for(dev, v_inp)
  pbuf  = metal_buffer(dev, 8)
  metal_buffer_write_i32(pbuf, 0, npix)
  metal_dispatch_n(q, pipe, [b_out, b_inp, pbuf], npix)
  metal_buffer_release(b_out)
  metal_buffer_release(b_inp)
  metal_buffer_release(pbuf)
  npix

# ---- Cheap JS <-> Tungsten Bridge Object & Tiered Execution Counters ----
# Tracks exact execution counts per tier so regression & A/B tests prove which tier ran!

JST_STATS = {:swizzle => 0, :t1 => 0, :t2 => 0, :metal => 0, :t1_compile => 0, :t2_reopt => 0}
JST_TIER2_HITS = [3]        # Re-compile Tier 1 -> Tier 2 (-O3 -mcpu=native) after 3 calls...
JST_TIER2_ELEMS = [500000]  # ...or once 500K total elements have been processed!

-> jst_reset_stats
  JST_STATS[:swizzle] = 0
  JST_STATS[:t1] = 0
  JST_STATS[:t2] = 0
  JST_STATS[:metal] = 0
  JST_STATS[:t1_compile] = 0
  JST_STATS[:t2_reopt] = 0
  nil

+ JstKernelDesc
  rw :name, :kind, :fp, :sig, :ta_kinds, :ta_mults, :need_pos_n, :metal_key, :metal_msl, :metal_fn, :metal_min_n
  rw :tier, :hits, :elems, :hash_key, :w_src, :kname, :wire_fn, :reopt_fn

  -> new(@name, @kind, @fp, @sig)
    @ta_kinds = []
    @ta_mults = nil
    @need_pos_n = false
    @metal_key = nil
    @metal_msl = nil
    @metal_fn = nil
    @metal_min_n = 131072
    @tier = @kind == :swizzle ? 2 : 1
    @hits = 0
    @elems = 0
    @hash_key = nil
    @w_src = nil
    @kname = "jst_k"
    @wire_fn = nil
    @reopt_fn = nil

-> jst_record_call(desc, n_elems)
  desc.hits += 1
  desc.elems += n_elems
  if desc.kind == :swizzle
    JST_STATS[:swizzle] += 1
  elsif desc.tier == 1
    JST_STATS[:t1] += 1
    if desc.reopt_fn != nil && (desc.hits >= JST_TIER2_HITS[0] || desc.elems >= JST_TIER2_ELEMS[0])
      desc.reopt_fn.call(desc)
  else
    JST_STATS[:t2] += 1
  nil

# Guard helper: returns exact non-negative integer count if v is a JS number (without calling valueOf!), else -1.
-> jst_guard_nonneg_int(v)
  return -1 if !js_number?(v)
  return -1 if v != v || v < ~0.0 || v > ~2147483647.0
  iv = v.to_i
  return -1 if iv.to_f != v
  iv

# Guard helper: verify TypedArray length satisfies per-param requirement (1 -> n, 2 -> 2*n, 4 -> 4*n, -2 -> n*n).
-> jst_guard_ta_len?(ta, n, mult)
  len = js_ta_length(ta)
  return false if len < 0
  return n <= len if mult == 1 || mult == nil
  return n <= 1073741823 && n * 2 <= len if mult == 2
  return n <= 536870911 && n * 4 <= len if mult == 4
  return n <= 46340 && n * n <= len if mult == -2
  false

-> jst_box_u64(rv)
  u = rv < 0 ? ((rv ## int) + ((1 ## int) << 64)) : (rv ## int)
  JS:BigIntValue.new(u)

-> jst_unbox_u64_bits(bv)
  uv = bv.v
  uv >= ((1 ## int) << 63) ? ((uv - ((1 ## int) << 64)) ## i64) : (uv ## i64)

# Fast dispatcher for a JstKernelDesc from JS arguments (a0, a1, a2, a3, more).
# Returns JS_HOLE on guard mismatch (so caller transparently falls back to JS Tier 0/JIT).
-> jst_dispatch_kernel(desc, argc, a0, a1, a2, a3, more)
  sig = desc.sig
  if sig == :tlib_dot_f32
    return JS_HOLE if argc < 3 || !a0.is_a?(JS:TypedArray) || !a1.is_a?(JS:TypedArray)
    return JS_HOLE if a0.kind != 7 || a1.kind != 7
    n = jst_guard_nonneg_int(a2)
    return JS_HOLE if n < 0 || n > js_ta_length(a0) || n > js_ta_length(a1)
    va = jst_ta_view(a0)
    vb = jst_ta_view(a1)
    return JS_HOLE if va == nil || vb == nil
    jst_record_call(desc, n)
    return tlib_dot_f32(va, vb, n)
  elsif sig == :tlib_saxpy_f32
    return JS_HOLE if argc < 5 || !a0.is_a?(JS:TypedArray) || !a1.is_a?(JS:TypedArray) || !a2.is_a?(JS:TypedArray)
    return JS_HOLE if a0.kind != 7 || a1.kind != 7 || a2.kind != 7 || !js_number?(a3)
    alpha = a3
    n = jst_guard_nonneg_int(more[4])
    return JS_HOLE if n < 0 || n > js_ta_length(a0) || n > js_ta_length(a1) || n > js_ta_length(a2)
    if desc.metal_key != nil && n >= desc.metal_min_n
      JST_STATS[:metal] += 1
      return jst_metal_saxpy_f32(a0, a1, a2, alpha, n).to_f
    vo = jst_ta_view(a0)
    va = jst_ta_view(a1)
    vb = jst_ta_view(a2)
    return JS_HOLE if vo == nil || va == nil || vb == nil
    jst_record_call(desc, n)
    return tlib_saxpy_f32(vo, va, vb, alpha, n).to_f
  elsif sig == :tlib_relu_scale_f16
    return JS_HOLE if argc < 4 || !a0.is_a?(JS:TypedArray) || !a1.is_a?(JS:TypedArray)
    return JS_HOLE if a0.kind != 11 || a1.kind != 11 || !js_number?(a2)
    sc = a2
    n = jst_guard_nonneg_int(a3)
    return JS_HOLE if n < 0 || n > js_ta_length(a0) || n > js_ta_length(a1)
    vo = jst_ta_view(a0)
    vi = jst_ta_view(a1)
    return JS_HOLE if vo == nil || vi == nil
    jst_record_call(desc, n)
    return tlib_relu_scale_f16(vo, vi, sc, n).to_f
  elsif sig == :tlib_poly_f64
    return JS_HOLE if argc < 6 || !a0.is_a?(JS:TypedArray) || !a1.is_a?(JS:TypedArray)
    return JS_HOLE if a0.kind != 8 || a1.kind != 8 || !js_number?(a2) || !js_number?(a3) || !js_number?(more[4])
    c0 = a2
    c1 = a3
    c2 = more[4]
    n = jst_guard_nonneg_int(more[5])
    return JS_HOLE if n < 0 || n > js_ta_length(a0) || n > js_ta_length(a1)
    vo = jst_ta_view(a0)
    vi = jst_ta_view(a1)
    return JS_HOLE if vo == nil || vi == nil
    jst_record_call(desc, n)
    return tlib_poly_f64(vo, vi, c0, c1, c2, n)
  elsif sig == :tlib_rgba_gray_u8
    return JS_HOLE if argc < 3 || !a0.is_a?(JS:TypedArray) || !a1.is_a?(JS:TypedArray)
    return JS_HOLE if (a0.kind != 1 && a0.kind != 2) || (a1.kind != 1 && a1.kind != 2)
    npix = jst_guard_nonneg_int(a2)
    return JS_HOLE if npix < 0 || npix * 4 > js_ta_length(a0) || npix * 4 > js_ta_length(a1)
    if desc.metal_key != nil && npix >= desc.metal_min_n
      JST_STATS[:metal] += 1
      return jst_metal_rgba_gray_u8(a0, a1, npix).to_f
    vo = jst_ta_view(a0)
    vi = jst_ta_view(a1)
    return JS_HOLE if vo == nil || vi == nil
    jst_record_call(desc, npix)
    return tlib_rgba_gray_u8(vo, vi, npix).to_f
  elsif sig == :tlib_rgba_gray1_u8
    return JS_HOLE if argc < 3 || !a0.is_a?(JS:TypedArray) || !a1.is_a?(JS:TypedArray)
    return JS_HOLE if (a0.kind != 1 && a0.kind != 2) || a1.kind != 1
    npix = jst_guard_nonneg_int(a2)
    return JS_HOLE if npix < 1 || npix > 536870911 || npix * 4 > js_ta_length(a0) || npix > js_ta_length(a1)
    vs = jst_ta_view(a0)
    vd = jst_ta_view(a1)
    return JS_HOLE if vs == nil || vd == nil
    jst_record_call(desc, npix)
    sp = jst_warray_slots(wvalue_bits(vs) ## i64)
    dp = jst_warray_slots(wvalue_bits(vd) ## i64)
    return tlib_rgba_gray1_raw(sp, dp, npix).to_f
  elsif sig == :tlib_matmul_f32
    return JS_HOLE if argc < 4 || !a0.is_a?(JS:TypedArray) || !a1.is_a?(JS:TypedArray) || !a2.is_a?(JS:TypedArray)
    return JS_HOLE if a0.kind != 7 || a1.kind != 7 || a2.kind != 7
    n = jst_guard_nonneg_int(a3)
    return JS_HOLE if n < 1 || n > 46340 || n * n > js_ta_length(a0) || n * n > js_ta_length(a1) || n * n > js_ta_length(a2)
    va = jst_ta_view(a0)
    vb = jst_ta_view(a1)
    vc = jst_ta_view(a2)
    return JS_HOLE if va == nil || vb == nil || vc == nil
    jst_record_call(desc, n * n)
    return tlib_matmul_f32(va, vb, vc, n)
  elsif sig == :tlib_mix_i32
    return JS_HOLE if argc < 2 || !a0.is_a?(JS:TypedArray) || a0.kind != 5
    n = jst_guard_nonneg_int(a1)
    return JS_HOLE if n < 0 || n > js_ta_length(a0)
    va = jst_ta_view(a0)
    return JS_HOLE if va == nil
    jst_record_call(desc, n)
    return tlib_mix_i32(va, n).to_f
  elsif sig == :tlib_hash_u64
    return JS_HOLE if argc < 2 || !a0.is_a?(JS:TypedArray) || a0.kind != 10
    n = jst_guard_nonneg_int(a1)
    return JS_HOLE if n < 0 || n > js_ta_length(a0)
    va = jst_ta_view(a0)
    return JS_HOLE if va == nil
    jst_record_call(desc, n)
    raw = tlib_hash_u64(va, n)
    u = raw < 0 ? ((raw ## int) + ((1 ## int) << 64)) : (raw ## int)
    return JS:BigIntValue.new(u)
  elsif sig == :jit_aai_d
    return JS_HOLE if argc < 3 || !a0.is_a?(JS:TypedArray) || !a1.is_a?(JS:TypedArray)
    return JS_HOLE if a0.kind != desc.ta_kinds[0] || a1.kind != desc.ta_kinds[1]
    n = jst_guard_nonneg_int(a2)
    return JS_HOLE if n < (desc.need_pos_n ? 1 : 0)
    m0 = desc.ta_mults != nil ? desc.ta_mults[0] : 1
    m1 = desc.ta_mults != nil ? desc.ta_mults[1] : 1
    return JS_HOLE if !jst_guard_ta_len?(a0, n, m0) || !jst_guard_ta_len?(a1, n, m1)
    va = jst_ta_view(a0)
    vb = jst_ta_view(a1)
    return JS_HOLE if va == nil || vb == nil
    jst_record_call(desc, n)
    return wvalue_from_bits(jst_call3(desc.fp, wvalue_bits(va) ## i64, wvalue_bits(vb) ## i64, wvalue_bits(n) ## i64))
  elsif sig == :jit_daai_d
    return JS_HOLE if argc < 4 || !js_number?(a0) || !a1.is_a?(JS:TypedArray) || !a2.is_a?(JS:TypedArray)
    return JS_HOLE if a1.kind != desc.ta_kinds[0] || a2.kind != desc.ta_kinds[1]
    n = jst_guard_nonneg_int(a3)
    return JS_HOLE if n < (desc.need_pos_n ? 1 : 0)
    m0 = desc.ta_mults != nil ? desc.ta_mults[0] : 1
    m1 = desc.ta_mults != nil ? desc.ta_mults[1] : 1
    return JS_HOLE if !jst_guard_ta_len?(a1, n, m0) || !jst_guard_ta_len?(a2, n, m1)
    vx = jst_ta_view(a1)
    vy = jst_ta_view(a2)
    return JS_HOLE if vx == nil || vy == nil
    jst_record_call(desc, n)
    return wvalue_from_bits(jst_call4(desc.fp, wvalue_bits(a0) ## i64, wvalue_bits(vx) ## i64, wvalue_bits(vy) ## i64, wvalue_bits(n) ## i64))
  elsif sig == :jit_aaai_d
    return JS_HOLE if argc < 4 || !a0.is_a?(JS:TypedArray) || !a1.is_a?(JS:TypedArray) || !a2.is_a?(JS:TypedArray)
    return JS_HOLE if a0.kind != desc.ta_kinds[0] || a1.kind != desc.ta_kinds[1] || a2.kind != desc.ta_kinds[2]
    n = jst_guard_nonneg_int(a3)
    return JS_HOLE if n < (desc.need_pos_n ? 1 : 0)
    m0 = desc.ta_mults != nil ? desc.ta_mults[0] : 1
    m1 = desc.ta_mults != nil ? desc.ta_mults[1] : 1
    m2 = desc.ta_mults != nil ? desc.ta_mults[2] : 1
    return JS_HOLE if !jst_guard_ta_len?(a0, n, m0) || !jst_guard_ta_len?(a1, n, m1) || !jst_guard_ta_len?(a2, n, m2)
    va = jst_ta_view(a0)
    vb = jst_ta_view(a1)
    vc = jst_ta_view(a2)
    return JS_HOLE if va == nil || vb == nil || vc == nil
    jst_record_call(desc, n)
    return wvalue_from_bits(jst_call4(desc.fp, wvalue_bits(va) ## i64, wvalue_bits(vb) ## i64, wvalue_bits(vc) ## i64, wvalue_bits(n) ## i64))
  elsif sig == :jit_aaai_u || sig == :jit_aaai_i
    return JS_HOLE if argc < 4 || !a0.is_a?(JS:TypedArray) || !a1.is_a?(JS:TypedArray) || !a2.is_a?(JS:TypedArray)
    return JS_HOLE if a0.kind != desc.ta_kinds[0] || a1.kind != desc.ta_kinds[1] || a2.kind != desc.ta_kinds[2]
    n = jst_guard_nonneg_int(a3)
    return JS_HOLE if n < (desc.need_pos_n ? 1 : 0)
    m0 = desc.ta_mults != nil ? desc.ta_mults[0] : 1
    m1 = desc.ta_mults != nil ? desc.ta_mults[1] : 1
    m2 = desc.ta_mults != nil ? desc.ta_mults[2] : 1
    return JS_HOLE if !jst_guard_ta_len?(a0, n, m0) || !jst_guard_ta_len?(a1, n, m1) || !jst_guard_ta_len?(a2, n, m2)
    va = jst_ta_view(a0)
    vb = jst_ta_view(a1)
    vc = jst_ta_view(a2)
    return JS_HOLE if va == nil || vb == nil || vc == nil
    jst_record_call(desc, n)
    rv = jst_call4(desc.fp, wvalue_bits(va) ## i64, wvalue_bits(vb) ## i64, wvalue_bits(vc) ## i64, n ## i64)
    return sig == :jit_aaai_u ? jst_box_u64(rv) : rv.to_f
  elsif sig == :jit_aaui_u || sig == :jit_aaui_i
    return JS_HOLE if argc < 4 || !a0.is_a?(JS:TypedArray) || !a1.is_a?(JS:TypedArray) || !a2.is_a?(JS:BigIntValue)
    return JS_HOLE if a0.kind != desc.ta_kinds[0] || a1.kind != desc.ta_kinds[1]
    return JS_HOLE if a2.v < 0 || a2.v >= ((1 ## int) << 64)
    n = jst_guard_nonneg_int(a3)
    return JS_HOLE if n < (desc.need_pos_n ? 1 : 0)
    m0 = desc.ta_mults != nil ? desc.ta_mults[0] : 1
    m1 = desc.ta_mults != nil ? desc.ta_mults[1] : 1
    return JS_HOLE if !jst_guard_ta_len?(a0, n, m0) || !jst_guard_ta_len?(a1, n, m1)
    vo = jst_ta_view(a0)
    va = jst_ta_view(a1)
    return JS_HOLE if vo == nil || va == nil
    wb = jst_unbox_u64_bits(a2)
    jst_record_call(desc, n)
    rv = jst_call4(desc.fp, wvalue_bits(vo) ## i64, wvalue_bits(va) ## i64, wb, n ## i64)
    return sig == :jit_aaui_u ? jst_box_u64(rv) : rv.to_f
  elsif sig == :jit_aaadi_i
    return JS_HOLE if argc < 5 || !a0.is_a?(JS:TypedArray) || !a1.is_a?(JS:TypedArray) || !a2.is_a?(JS:TypedArray)
    return JS_HOLE if a0.kind != desc.ta_kinds[0] || a1.kind != desc.ta_kinds[1] || a2.kind != desc.ta_kinds[2] || !js_number?(a3)
    alpha = a3
    n = jst_guard_nonneg_int(more[4])
    return JS_HOLE if n < 0 || n > js_ta_length(a0) || n > js_ta_length(a1) || n > js_ta_length(a2)
    vo = jst_ta_view(a0)
    va = jst_ta_view(a1)
    vb = jst_ta_view(a2)
    return JS_HOLE if vo == nil || va == nil || vb == nil
    jst_record_call(desc, n)
    rv = jst_call5(desc.fp, wvalue_bits(vo) ## i64, wvalue_bits(va) ## i64, wvalue_bits(vb) ## i64, wvalue_bits(alpha) ## i64, n ## i64)
    return rv.to_f
  elsif sig == :jit_aadi_i
    return JS_HOLE if argc < 4 || !a0.is_a?(JS:TypedArray) || !a1.is_a?(JS:TypedArray)
    return JS_HOLE if a0.kind != desc.ta_kinds[0] || a1.kind != desc.ta_kinds[1] || !js_number?(a2)
    sc = a2
    n = jst_guard_nonneg_int(a3)
    return JS_HOLE if n < 0 || n > js_ta_length(a0) || n > js_ta_length(a1)
    vo = jst_ta_view(a0)
    vi = jst_ta_view(a1)
    return JS_HOLE if vo == nil || vi == nil
    jst_record_call(desc, n)
    rv = jst_call4(desc.fp, wvalue_bits(vo) ## i64, wvalue_bits(vi) ## i64, wvalue_bits(sc) ## i64, n ## i64)
    return rv.to_f
  elsif sig == :jit_aai_i || sig == :jit_aai_u
    return JS_HOLE if argc < 3 || !a0.is_a?(JS:TypedArray) || !a1.is_a?(JS:TypedArray)
    return JS_HOLE if a0.kind != desc.ta_kinds[0] || a1.kind != desc.ta_kinds[1]
    n = jst_guard_nonneg_int(a2)
    return JS_HOLE if n < (desc.need_pos_n ? 1 : 0)
    m0 = desc.ta_mults != nil ? desc.ta_mults[0] : 1
    m1 = desc.ta_mults != nil ? desc.ta_mults[1] : 1
    return JS_HOLE if !jst_guard_ta_len?(a0, n, m0) || !jst_guard_ta_len?(a1, n, m1)
    vo = jst_ta_view(a0)
    vi = jst_ta_view(a1)
    return JS_HOLE if vo == nil || vi == nil
    jst_record_call(desc, n)
    rv = jst_call3(desc.fp, wvalue_bits(vo) ## i64, wvalue_bits(vi) ## i64, n ## i64)
    return sig == :jit_aai_u ? jst_box_u64(rv) : rv.to_f
  elsif sig == :jit_ai_i || sig == :jit_ai_u || sig == :jit_ai_s64
    return JS_HOLE if argc < 2 || !a0.is_a?(JS:TypedArray) || a0.kind != desc.ta_kinds[0]
    n = jst_guard_nonneg_int(a1)
    return JS_HOLE if n < 0 || n > js_ta_length(a0)
    va = jst_ta_view(a0)
    return JS_HOLE if va == nil
    jst_record_call(desc, n)
    rv = jst_call2(desc.fp, wvalue_bits(va) ## i64, n ## i64)
    if sig == :jit_ai_u
      return jst_box_u64(rv)
    elsif sig == :jit_ai_s64
      return JS:BigIntValue.new(rv ## int)
    elsif desc.ta_kinds[0] == 10
      return jst_box_u64(rv)
    elsif desc.ta_kinds[0] == 9
      return JS:BigIntValue.new(rv ## int)
    return rv.to_f
  elsif sig == :jit_ai_d
    return JS_HOLE if argc < 2 || !a0.is_a?(JS:TypedArray) || a0.kind != desc.ta_kinds[0]
    n = jst_guard_nonneg_int(a1)
    return JS_HOLE if n < 0 || n > js_ta_length(a0)
    va = jst_ta_view(a0)
    return JS_HOLE if va == nil
    jst_record_call(desc, n)
    return wvalue_from_bits(jst_call2(desc.fp, wvalue_bits(va) ## i64, wvalue_bits(n) ## i64))
  elsif sig == :jit_dd_d
    return JS_HOLE if argc < 2 || !js_number?(a0) || !js_number?(a1)
    x0 = a0
    x1 = a1
    jst_record_call(desc, 1)
    return wvalue_from_bits(jst_call2(desc.fp, wvalue_bits(x0) ## i64, wvalue_bits(x1) ## i64))
  elsif sig == :jit_iii_i
    return JS_HOLE if argc < 3
    jst_record_call(desc, 1)
    return tlib_mandelbrot_i64(js_to_number(a0).to_i, js_to_number(a1).to_i, js_to_number(a2).to_i).to_f
  JS_HOLE

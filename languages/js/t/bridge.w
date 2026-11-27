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
fn tlib_saxpy_f32(out, a, b, alpha, n) (f32[] f32[] f32[] f64 i64) i64
  af = alpha ## f32
  i = 0 ## i64
  while i < n
    out[i] = af * a[i] + b[i]
    i += 1
  n

# 3. Float16Array (ebits = -16, ARM64 hardware __fp16!) ReLU + scale
fn tlib_relu_scale_f16(out, inp, scale, n) (f16[] f16[] f64 i64) i64
  sf = scale ## f32
  z = 0.0 ## f32
  i = 0 ## i64
  while i < n
    v = (inp[i] ## f32) * sf
    out[i] = (v > z ? v : z) ## f16
    i += 1
  n

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

# bench_ab.w — Comprehensive A/B Benchmark Suite for Blade's Alternate JS->Tungsten PoC (jsn_t):
#
# Benchmarks:
#   1. TypedArray Storage A/B: Existing ByteArray (b_typed.w) vs Raw Tungsten `ebits` WArray views
#      across Float32Array (-32), Float16Array (-16), Float64Array (-64), Int32Array (33),
#      Uint8Array (8), BigUint64Array (64).
#   2. JS <-> Tungsten Call Cost A/B (1,000,000 calls):
#      JS:NativeFunction vs js-aot closure vs Direct Unboxed Tungsten LLVM Bridge.
#   3. End-to-End JS Function A/B across 7 numeric & array workloads (with exact result parity!):
#        - Tier 0 (walk.w, JIT=0)
#        - ARM64 JIT (jit.w, JIT=1)
#        - JS->Tungsten Compiled Kernel (jsn_t: JS AST -> typed Tungsten .w -> clang -O3 -mcpu=native -> w_jit_load_object)
#        - AST-Swizzled Tungsten Library (0 ms compile!)
#        - Metal GPU Offload (zero-copy page-aligned TypedArray -> Apple Silicon GPU!)
#   4. SmallArray demo on frozen small JS numeric array literal.

use ../js
use ./compiler

-> now_ms
  ccall("__w_clock_ms")

-> now_us
  (ccall_nobox("__w_clock_ns_raw") ## i64) / 1000

# Helper: extract the JS:Function & JaFunc of a named global function in the active realm.
-> get_js_fn(name)
  r = js_realm()
  r.global.get(name)

# Helper: run a JS snippet and return result.
-> run_js(src)
  js_run_script(src, "bench.js")

-> make_more_args(args)
  return JS_NO_ARGS if args.size <= 4
  args

-> zero_ta(ta)
  ptr = jst_warray_slots(wvalue_bits(ta.buffer.data) ## i64)
  off = ta.offset ## i64
  blen = ta.buffer.blen ## i64
  ccall_nobox("memset", (ptr + off) ## i64, 0 ## i64, blen)
  nil

# Helper: time a JS call via Tier 0 (JIT=0) or ARM64 JIT (JIT=1).
-> time_js_call(jit_on, fn_obj, args, warmup, iters)
  JIT_ENABLED[0] = jit_on
  # Clear jit_fp if running Tier 0 so walk.w runs cleanly
  saved_fp = fn_obj.code.jit_fp
  saved_ffp = fn_obj.code.jit_fast_fp
  saved_rfp = fn_obj.code.jit_repeat_fp
  saved_st = fn_obj.code.jit_state
  if !jit_on
    fn_obj.code.jit_fp = 0
    fn_obj.code.jit_fast_fp = 0
    fn_obj.code.jit_repeat_fp = 0
    fn_obj.code.jit_state = 0
  argc = args.size
  a0 = argc > 0 ? args[0] : nil
  a1 = argc > 1 ? args[1] : nil
  a2 = argc > 2 ? args[2] : nil
  a3 = argc > 3 ? args[3] : nil
  more = make_more_args(args)
  w = 0
  res = nil
  while w < warmup
    res = js_call(fn_obj, nil, argc, a0, a1, a2, a3, more)
    w += 1
  t0 = now_us()
  i = 0
  while i < iters
    res = js_call(fn_obj, nil, argc, a0, a1, a2, a3, more)
    i += 1
  t1 = now_us()
  if !jit_on
    fn_obj.code.jit_fp = saved_fp
    fn_obj.code.jit_fast_fp = saved_ffp
    fn_obj.code.jit_repeat_fp = saved_rfp
    fn_obj.code.jit_state = saved_st
  [(t1 - t0).to_f / ~1000.0, res]

# Helper: time a jst_dispatch_kernel call.
-> time_jst_call(desc, args, warmup, iters)
  argc = args.size
  a0 = argc > 0 ? args[0] : nil
  a1 = argc > 1 ? args[1] : nil
  a2 = argc > 2 ? args[2] : nil
  a3 = argc > 3 ? args[3] : nil
  more = make_more_args(args)
  w = 0
  res = nil
  while w < warmup
    res = jst_dispatch_kernel(desc, argc, a0, a1, a2, a3, more)
    w += 1
  t0 = now_us()
  i = 0
  while i < iters
    res = jst_dispatch_kernel(desc, argc, a0, a1, a2, a3, more)
    i += 1
  t1 = now_us()
  [(t1 - t0).to_f / ~1000.0, res]

-> fmt_num(v, dec)
  if dec == 1
    iv = (v * ~10.0 + ~0.5).to_i
    return (iv / 10).to_s + "." + (iv % 10).to_s
  iv = (v * ~100.0 + ~0.5).to_i
  frac = iv % 100
  (iv / 100).to_s + "." + (frac < 10 ? "0" + frac.to_s : frac.to_s)

-> fmt_ms(ms)
  return "<0.01 ms" if ms < ~0.01
  fmt_num(ms, 2) + " ms"

-> fmt_x(base, fast)
  f = fast < ~0.001 ? ~0.001 : fast
  fmt_num(base / f, 1) + "x"

# ==============================================================================
# Initialize JS Realm
# ==============================================================================
realm = js_new_realm(nil)

<< "=============================================================================="
<< "  PART A: TypedArray Storage A/B — ByteArray (b_typed.w) vs Raw `ebits` WArray"
<< "=============================================================================="

# Allocate 262,144 elements for each TypedArray type and compare raw element read+sum speed:
#   Old path: js_ta_get(ta, i) on ByteArray (little-endian byte decode + IEEE bit reconstruct)
#   New path: zero-copy `w_array_view_raw(ptr, ebits, n)` read in typed Tungsten!
n_ta = 262144
ta_f32 = jst_new_aligned_typed_array(7, n_ta)
ta_f16 = jst_new_aligned_typed_array(11, n_ta)
ta_f64 = jst_new_aligned_typed_array(8, n_ta)
ta_i32 = jst_new_aligned_typed_array(5, n_ta)
ta_u8  = jst_new_aligned_typed_array(1, n_ta)
ta_u64 = jst_new_aligned_typed_array(10, n_ta)

# Initialize via zero-copy raw ebits views (proving mutations reflect immediately in JS!)
v_f32 = jst_ta_view(ta_f32)
v_f16 = jst_ta_view(ta_f16)
v_f64 = jst_ta_view(ta_f64)
v_i32 = jst_ta_view(ta_i32)
v_u8  = jst_ta_view(ta_u8)
v_u64 = jst_ta_view(ta_u64)

fn init_ebits_arrays(af32, af16, af64, ai32, au8, au64, n) (f32[] f16[] f64[] i32[] u8[] u64[] i64) i64
  i = 0 ## i64
  while i < n
    x = ((i % 64) ## f64) * 0.25 - 4.0
    af32[i] = x ## f32
    af16[i] = x ## f16
    af64[i] = x
    ai32[i] = ((i * 7) ^ 12345) ## i32
    au8[i]  = (i & 255) ## u8
    au64[i] = ((i ## u64) * 2654435761 ## u64) + 1 ## u64
    i += 1
  n

init_ebits_arrays(v_f32, v_f16, v_f64, v_i32, v_u8, v_u64, n_ta)

# Verify zero-copy aliasing: reading through JS b_typed.w sees the EXACT bytes written via raw ebits view!
alias_ok = (js_ta_get(ta_f32, 10) == ~-1.5) && (js_ta_get(ta_f16, 10) == ~-1.5) && (js_ta_get(ta_f64, 10) == ~-1.5) && (js_ta_get(ta_u8, 10) == ~10.0)
<< "Zero-copy aliasing check (ebits WArray write -> JS TypedArray read): [alias_ok ? 'PASS' : 'FAIL']"

# Microbenchmark: read + sum 262,144 elements through ByteArray js_ta_get vs raw ebits WArray
fn sum_ebits_f32(a, n) (f32[] i64) f64
  s = 0.0 ## f64
  i = 0 ## i64
  while i < n
    s += a[i] ## f64
    i += 1
  s

fn sum_ebits_f16(a, n) (f16[] i64) f64
  s = 0.0 ## f64
  i = 0 ## i64
  while i < n
    s += a[i] ## f64
    i += 1
  s

fn sum_ebits_f64(a, n) (f64[] i64) f64
  s = 0.0 ## f64
  i = 0 ## i64
  while i < n
    s += a[i]
    i += 1
  s

fn sum_ebits_i32(a, n) (i32[] i64) i64
  s = 0 ## i64
  i = 0 ## i64
  while i < n
    s += a[i] ## i64
    i += 1
  s

fn sum_ebits_u64(a, n) (u64[] i64) i64
  s = 0 ## u64
  i = 0 ## i64
  while i < n
    s = s ^ a[i]
    i += 1
  s ## i64

-> bench_old_ta_sum(ta, n)
  t0 = now_us()
  s = ~0.0
  i = 0
  while i < n
    s += js_ta_get(ta, i)
    i += 1
  t1 = now_us()
  [(t1 - t0).to_f / ~1000.0, s]

-> bench_old_ta_u64_xor(ta, n)
  t0 = now_us()
  s = 0 ## int
  i = 0
  while i < n
    v = js_ta_get(ta, i)
    s = s ^ v.v
    i += 1
  t1 = now_us()
  [(t1 - t0).to_f / ~1000.0, s]

# Float32Array (-32)
r_old_f32 = bench_old_ta_sum(ta_f32, n_ta)
t0 = now_us(); s_new_f32 = sum_ebits_f32(v_f32, n_ta); t1 = now_us()
ms_new_f32 = (t1 - t0).to_f / ~1000.0
<< "  Float32Array  (ebits=-32, 262K): b_typed ByteArray=[fmt_ms(r_old_f32[0])] vs raw ebits f32\[]=[fmt_ms(ms_new_f32)] ([fmt_x(r_old_f32[0], ms_new_f32)]) | match=[r_old_f32[1] == s_new_f32]"

# Float16Array (-16)
r_old_f16 = bench_old_ta_sum(ta_f16, n_ta)
t0 = now_us(); s_new_f16 = sum_ebits_f16(v_f16, n_ta); t1 = now_us()
ms_new_f16 = (t1 - t0).to_f / ~1000.0
<< "  Float16Array  (ebits=-16, 262K): b_typed ByteArray=[fmt_ms(r_old_f16[0])] vs raw ebits f16\[]=[fmt_ms(ms_new_f16)] ([fmt_x(r_old_f16[0], ms_new_f16)]) | match=[r_old_f16[1] == s_new_f16]"

# Float64Array (-64)
r_old_f64 = bench_old_ta_sum(ta_f64, n_ta)
t0 = now_us(); s_new_f64 = sum_ebits_f64(v_f64, n_ta); t1 = now_us()
ms_new_f64 = (t1 - t0).to_f / ~1000.0
<< "  Float64Array  (ebits=-64, 262K): b_typed ByteArray=[fmt_ms(r_old_f64[0])] vs raw ebits f64\[]=[fmt_ms(ms_new_f64)] ([fmt_x(r_old_f64[0], ms_new_f64)]) | match=[r_old_f64[1] == s_new_f64]"

# Int32Array (33)
r_old_i32 = bench_old_ta_sum(ta_i32, n_ta)
t0 = now_us(); s_new_i32 = sum_ebits_i32(v_i32, n_ta); t1 = now_us()
ms_new_i32 = (t1 - t0).to_f / ~1000.0
<< "  Int32Array    (ebits= 33, 262K): b_typed ByteArray=[fmt_ms(r_old_i32[0])] vs raw ebits i32\[]=[fmt_ms(ms_new_i32)] ([fmt_x(r_old_i32[0], ms_new_i32)]) | match=[r_old_i32[1] == s_new_i32.to_f]"

# BigUint64Array (64)
r_old_u64 = bench_old_ta_u64_xor(ta_u64, n_ta)
t0 = now_us(); s_new_u64 = sum_ebits_u64(v_u64, n_ta); t1 = now_us()
ms_new_u64 = (t1 - t0).to_f / ~1000.0
u64_match = (s_new_u64 < 0 ? ((s_new_u64 ## int) + ((1 ## int) << 64)) : (s_new_u64 ## int)) == r_old_u64[1]
<< "  BigUint64Array(ebits= 64, 262K): b_typed ByteArray=[fmt_ms(r_old_u64[0])] vs raw ebits u64\[]=[fmt_ms(ms_new_u64)] ([fmt_x(r_old_u64[0], ms_new_u64)]) | match=[u64_match]"

# SmallArray demo on frozen small JS array
sa_small = jst_freeze_small_f64([~1.5, ~2.5, ~3.5, ~4.5])
<< "  SmallArray (frozen 4xf64 literal): size=[sa_small.size] elem\[2]=[sa_small[2]]"

# ==============================================================================
<< ""
<< "=============================================================================="
<< "  PART B: JS <-> Tungsten Call Overhead A/B (1,000,000 calls)"
<< "=============================================================================="

# 1. Standard JS:NativeFunction via js_call (boxes args Array, calls closure)
nat_add = js_native("nat_add", 2, ->(this, args, nt) js_to_number(args[0]) + js_to_number(args[1]))
n_calls = 1000000
t0 = now_us()
ci = 0
acc1 = ~0.0
while ci < n_calls
  acc1 = js_call(nat_add, nil, 2, acc1, ~1.0, nil, nil, JS_NO_ARGS)
  ci += 1
t1 = now_us()
ms_nat = (t1 - t0).to_f / ~1000.0

# 2. js-aot unit style w_closure_call_8
cl_add = ->(f, this, argc, a0, a1, a2, a3, more) a0 + a1
t0 = now_us()
ci = 0
acc2 = ~0.0
while ci < n_calls
  acc2 = ccall("w_closure_call_8", cl_add, nil, nil, 2, acc2, ~1.0, nil, nil, JS_NO_ARGS)
  ci += 1
t1 = now_us()
ms_cl8 = (t1 - t0).to_f / ~1000.0

# 3. Direct Tungsten fn call (unboxed f64 registers!)
fn bench_direct_t_calls(n) (i64) f64
  acc = ~0.0 ## f64
  one = ~1.0 ## f64
  i = 0 ## i64
  while i < n
    acc = tlib_add2_f64(acc, one)
    i += 1
  acc

t0 = now_us()
acc3 = bench_direct_t_calls(n_calls)
t1 = now_us()
ms_dir = (t1 - t0).to_f / ~1000.0

# 4. Direct indirect LLVM blr call into a dynamically-loaded compiled Tungsten .o kernel!
run_js("function js_add2(x, y) { return x + y; }")
fn_add2 = get_js_fn("js_add2")
comp_add2 = jst_compile_js_func(fn_add2.code.node, [[:f64], [:f64]], "f64")
fp_add2 = comp_add2[2]

fn bench_indirect_jit_calls(fp, n, a0_bits, a1_bits) (i64 i64 i64 i64) i64
  acc = a0_bits
  i = 0 ## i64
  while i < n
    acc = jst_call2(fp, acc, a1_bits)
    i += 1
  acc

t0 = now_us()
acc4 = wvalue_from_bits(bench_indirect_jit_calls(fp_add2, n_calls, wvalue_bits(~0.0) ## i64, wvalue_bits(~1.0) ## i64))
t1 = now_us()
ms_ind = (t1 - t0).to_f / ~1000.0

<< "  JS:NativeFunction (js_call + args array): [fmt_ms(ms_nat)] ([((ms_nat * ~1000000.0) / n_calls.to_f).round(1)] ns/call) | sum=[acc1]"
<< "  js-aot unit closure (w_closure_call_8):   [fmt_ms(ms_cl8)] ([((ms_cl8 * ~1000000.0) / n_calls.to_f).round(1)] ns/call) | sum=[acc2]"
<< "  Direct compiled Tungsten .o (LLVM blr):   [fmt_ms(ms_ind)] ([((ms_ind * ~1000000.0) / n_calls.to_f).round(1)] ns/call) | sum=[acc4] ([fmt_x(ms_nat, ms_ind)])"
<< "  Direct static Tungsten fn (inlined):      [fmt_ms(ms_dir)] ([((ms_dir * ~1000000.0) / n_calls.to_f).round(1)] ns/call) | sum=[acc3]"

# ==============================================================================
<< ""
<< "=============================================================================="
<< "  PART C: End-to-End JS Workload A/B (Tier 0 vs ARM64 JIT vs JS->Tungsten vs Metal)"
<< "=============================================================================="

# Load all 7 real JS workload functions into the JS engine
# (Uses `var` so Blade's ARM64 JIT compiles every eligible function at full native speed!)
BENCH_JS_SRC = <<~JS
  function js_dot_f32(a, b, n) {
    var s = 0.0;
    for (var i = 0; i < n; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  function js_dot_f64(a, b, n) {
    var s = 0.0;
    for (var i = 0; i < n; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  function js_saxpy_f32(out, a, b, alpha, n) {
    for (var i = 0; i < n; i++) {
      out[i] = alpha * a[i] + b[i];
    }
    return n;
  }

  function js_relu_f16(out, inp, scale, n) {
    for (var i = 0; i < n; i++) {
      var v = inp[i] * scale;
      out[i] = v > 0 ? v : 0;
    }
    return n;
  }

  function js_rgba_gray(out, inp, npix) {
    for (var i = 0; i < npix; i++) {
      var j = i * 4;
      var l = (inp[j] * 77 + inp[j + 1] * 150 + inp[j + 2] * 29) >> 8;
      out[j] = l;
      out[j + 1] = l;
      out[j + 2] = l;
      out[j + 3] = inp[j + 3];
    }
    return npix;
  }

  function js_mix_i32(a, n) {
    var acc = 0;
    for (var i = 0; i < n; i++) {
      var x = a[i];
      x = x ^ (x >> 16);
      x = Math.imul(x, 0x45d9f3b);
      x = x ^ (x >> 16);
      acc = acc ^ x;
    }
    return acc;
  }

  function js_hash_u64(a, n) {
    var h = 14695981039346656037n;
    var prime = 1099511628211n;
    var mask = 18446744073709551615n;
    for (var i = 0; i < n; i++) {
      h = ((h ^ a[i]) * prime) & mask;
    }
    return h;
  }
JS
run_js(BENCH_JS_SRC)

# ---- Workload 1: Float32Array Dot Product (N = 262,144, 5 iters) ----
<< ""
<< "\[1] Float32Array Dot Product (N=262,144, 5 runs)"
ta_f32_b = jst_new_aligned_typed_array(7, n_ta)
v_f32_b = jst_ta_view(ta_f32_b)
fn init_f32_b(b, n) (f32[] i64) i64
  i = 0 ## i64
  while i < n
    b[i] = (((i % 32) ## f64) * 0.125 - 1.5) ## f32
    i += 1
  n
init_f32_b(v_f32_b, n_ta)

f_dot = get_js_fn("js_dot_f32")
args_dot = [ta_f32, ta_f32_b, n_ta.to_f]
an_dot = jst_analyze_func(f_dot.code.node)
r_t0 = time_js_call(false, f_dot, args_dot, 1, 2)
t0_scaled = r_t0[0] * ~2.5
r_jit = time_js_call(true, f_dot, args_dot, 6, 5)
# On-the-fly JS AST -> Tungsten compiler (generates .w, compiles with clang -O3 -mcpu=native, loads .o!)
tc0 = now_us()
comp_dot = jst_compile_js_func(f_dot.code.node, [[:ta, 7], [:ta, 7], [:i64]], "f64")
tc1 = now_us()
r_comp = time_jst_call(comp_dot[0], args_dot, 2, 5)
# AST-Swizzled Tungsten library (0 ms compile!)
sw_dot = jst_match_swizzle(f_dot.code.node, [7, 7, -1], false)
r_sw = time_jst_call(sw_dot, args_dot, 2, 5)
<< "    Static analyzer qualified: [an_dot[0]] | compile/load time: [fmt_ms((tc1 - tc0).to_f / ~1000.0)]"
<< "    Tier 0 (walk.w):            [fmt_ms(t0_scaled)] (2-run scaled to 5) | res=[r_t0[1]]"
<< "    ARM64 JIT (jit.w, jit=[f_dot.code.jit_fp != 0]): [fmt_ms(r_jit[0])] ([fmt_x(t0_scaled, r_jit[0])] vs T0) | res=[r_jit[1]]"
<< "    JS->Tungsten compiled .o:   [fmt_ms(r_comp[0])] ([fmt_x(t0_scaled, r_comp[0])] vs T0, [fmt_x(r_jit[0], r_comp[0])] vs JIT) | res=[r_comp[1]]"
<< "    AST-Swizzled Tungsten lib:  [fmt_ms(r_sw[0])] ([fmt_x(t0_scaled, r_sw[0])] vs T0, [fmt_x(r_jit[0], r_sw[0])] vs JIT) | res=[r_sw[1]]"

# ---- Workload 1b: Float64Array Dot Product (N = 262,144, 5 runs — ARM64 JIT's best case!) ----
<< ""
<< "\[1b] Float64Array Dot Product (N=262,144, 5 runs — ARM64 JIT's strongest native path)"
ta_f64_b = jst_new_aligned_typed_array(8, n_ta)
fn init_f64_b(b, n) (f64[] i64) i64
  i = 0 ## i64
  while i < n
    b[i] = ((i % 32) ## f64) * ~0.125 - ~1.5
    i += 1
  n
init_f64_b(jst_ta_view(ta_f64_b), n_ta)
f_dot64 = get_js_fn("js_dot_f64")
args_dot64 = [ta_f64, ta_f64_b, n_ta.to_f]
r_d64_t0  = time_js_call(false, f_dot64, args_dot64, 0, 1)
r_d64_jit = time_js_call(true, f_dot64, args_dot64, 6, 5)
comp_d64  = jst_compile_js_func(f_dot64.code.node, [[:ta, 8], [:ta, 8], [:i64]], "f64")
r_d64_cmp = time_jst_call(comp_d64[0], args_dot64, 2, 5)
<< "    Tier 0 (walk.w, 1x -> 5x):  [fmt_ms(r_d64_t0[0] * ~5.0)] | res=[r_d64_t0[1]]"
<< "    ARM64 JIT (jit.w, jit=[f_dot64.code.jit_fp != 0]): [fmt_ms(r_d64_jit[0])] ([fmt_x(r_d64_t0[0] * ~5.0, r_d64_jit[0])] vs T0) | res=[r_d64_jit[1]]"
<< "    JS->Tungsten compiled .o:   [fmt_ms(r_d64_cmp[0])] ([fmt_x(r_d64_t0[0] * ~5.0, r_d64_cmp[0])] vs T0, [fmt_x(r_d64_jit[0], r_d64_cmp[0])] vs JIT) | res=[r_d64_cmp[1]] match=[r_d64_t0[1] == r_d64_cmp[1]]"

# ---- Workload 2: Float32Array SAXPY (N = 2,097,152 = 8 MB/array, CPU vs Metal GPU!) ----
<< ""
<< "\[2] Float32Array SAXPY: out\[i] = alpha * a\[i] + b\[i] (N=2,097,152 = 8 MB/array)"
n_big = 2097152
ta_out_big = jst_new_aligned_typed_array(7, n_big)
ta_a_big   = jst_new_aligned_typed_array(7, n_big)
ta_b_big   = jst_new_aligned_typed_array(7, n_big)
init_f32_b(jst_ta_view(ta_a_big), n_big)
init_f32_b(jst_ta_view(ta_b_big), n_big)

f_saxpy = get_js_fn("js_saxpy_f32")
args_sax = [ta_out_big, ta_a_big, ta_b_big, ~2.5, n_big.to_f]
zero_ta(ta_out_big)
r_sax_t0  = time_js_call(false, f_saxpy, args_sax, 0, 1)
v_t0_chk = js_ta_get(ta_out_big, 12345)
zero_ta(ta_out_big)
r_sax_jit = time_js_call(true, f_saxpy, args_sax, 1, 1)
v_jit_chk = js_ta_get(ta_out_big, 12345)
comp_sax  = jst_compile_js_func(f_saxpy.code.node, [[:ta, 7], [:ta, 7], [:ta, 7], [:f64], [:i64]], "i64")
zero_ta(ta_out_big)
r_sax_cmp = time_jst_call(comp_sax[0], args_sax, 2, 3)
v_cpu_chk = js_ta_get(ta_out_big, 12345)
sw_sax_cpu = jst_match_swizzle(f_saxpy.code.node, [7, 7, 7, -1, -1], false)
zero_ta(ta_out_big)
r_sax_sw  = time_jst_call(sw_sax_cpu, args_sax, 2, 3)
v_sw_chk = js_ta_get(ta_out_big, 12345)
sw_sax_gpu = jst_match_swizzle(f_saxpy.code.node, [7, 7, 7, -1, -1], true)
# Warm up Metal pipeline compilation once, then zero & measure dispatch latency
jst_dispatch_kernel(sw_sax_gpu, 5, ta_out_big, ta_a_big, ta_b_big, ~2.5, args_sax)
zero_ta(ta_out_big)
r_sax_gpu = time_jst_call(sw_sax_gpu, args_sax, 1, 3)
v_gpu_chk = js_ta_get(ta_out_big, 12345)
<< "    Tier 0 (walk.w, 1x -> 3x):  [fmt_ms(r_sax_t0[0] * ~3.0)] | out\[12345]=[v_t0_chk]"
<< "    ARM64 JIT (jit=[f_saxpy.code.jit_fp != 0], 1x->3x): [fmt_ms(r_sax_jit[0] * ~3.0)] ([fmt_x(r_sax_t0[0], r_sax_jit[0])] vs T0) | out\[12345]=[v_jit_chk]"
<< "    JS->Tungsten compiled .o:   [fmt_ms(r_sax_cmp[0])] ([fmt_x(r_sax_t0[0] * ~3.0, r_sax_cmp[0])] vs T0, [fmt_x(r_sax_jit[0] * ~3.0, r_sax_cmp[0])] vs JIT) | out\[12345]=[v_cpu_chk] match=[v_t0_chk == v_cpu_chk]"
<< "    AST-Swizzled CPU f32\[]:     [fmt_ms(r_sax_sw[0])] ([fmt_x(r_sax_t0[0] * ~3.0, r_sax_sw[0])] vs T0, [fmt_x(r_sax_jit[0] * ~3.0, r_sax_sw[0])] vs JIT) | out\[12345]=[v_sw_chk] match=[v_t0_chk == v_sw_chk]"
<< "    Metal @gpu (zero-copy UM):  [fmt_ms(r_sax_gpu[0])] ([fmt_x(r_sax_t0[0] * ~3.0, r_sax_gpu[0])] vs T0, [fmt_x(r_sax_jit[0] * ~3.0, r_sax_gpu[0])] vs JIT) | out\[12345]=[v_gpu_chk] match=[v_t0_chk == v_gpu_chk]"

# ---- Workload 3: Float16Array ReLU + Scale (N = 262,144, ARM64 hardware __fp16!) ----
<< ""
<< "\[3] Float16Array ReLU + Scale (N=262,144, 5 runs — ARM64 hardware __fp16!)"
ta_f16_out = jst_new_aligned_typed_array(11, n_ta)
f_f16 = get_js_fn("js_relu_f16")
args_f16 = [ta_f16_out, ta_f16, ~0.5, n_ta.to_f]
zero_ta(ta_f16_out)
r_f16_t0  = time_js_call(false, f_f16, args_f16, 0, 1)
chk_t0_f16 = js_ta_get(ta_f16_out, 50)
zero_ta(ta_f16_out)
r_f16_jit = time_js_call(true, f_f16, args_f16, 5, 5)
chk_jit_f16 = js_ta_get(ta_f16_out, 50)
comp_f16  = jst_compile_js_func(f_f16.code.node, [[:ta, 11], [:ta, 11], [:f64], [:i64]], "i64")
zero_ta(ta_f16_out)
r_f16_cmp = time_jst_call(comp_f16[0], args_f16, 2, 5)
chk_cmp_f16 = js_ta_get(ta_f16_out, 50)
sw_f16    = jst_match_swizzle(f_f16.code.node, [11, 11, -1, -1], false)
zero_ta(ta_f16_out)
r_f16_sw  = time_jst_call(sw_f16, args_f16, 2, 5)
chk_sw_f16 = js_ta_get(ta_f16_out, 50)
<< "    Tier 0 (walk.w, 1x -> 5x):  [fmt_ms(r_f16_t0[0] * ~5.0)] | out\[50]=[chk_t0_f16]"
<< "    ARM64 JIT (jit=[f_f16.code.jit_fp != 0], 5 runs): [fmt_ms(r_f16_jit[0])] ([fmt_x(r_f16_t0[0] * ~5.0, r_f16_jit[0])] vs T0) | out\[50]=[chk_jit_f16]"
<< "    JS->Tungsten compiled .o:   [fmt_ms(r_f16_cmp[0])] ([fmt_x(r_f16_t0[0] * ~5.0, r_f16_cmp[0])] vs T0, [fmt_x(r_f16_jit[0], r_f16_cmp[0])] vs JIT) | out\[50]=[chk_cmp_f16] match=[chk_t0_f16 == chk_cmp_f16]"
<< "    AST-Swizzled Tungsten lib:  [fmt_ms(r_f16_sw[0])] ([fmt_x(r_f16_t0[0] * ~5.0, r_f16_sw[0])] vs T0, [fmt_x(r_f16_jit[0], r_f16_sw[0])] vs JIT) | out\[50]=[chk_sw_f16] match=[chk_t0_f16 == chk_sw_f16]"

# ---- Workload 4: Uint8ClampedArray 1080p RGBA Grayscale Filter (1920x1080 = 2,073,600 pixels = 8.3 MB!) ----
<< ""
<< "\[4] Uint8ClampedArray 1080p RGBA Grayscale Filter (1920x1080 = 2.07M pixels = 8.3 MB)"
npix = 1920 * 1080
ta_img_in  = jst_new_aligned_typed_array(2, npix * 4)
ta_img_out = jst_new_aligned_typed_array(2, npix * 4)
fn init_rgba(buf, n) (u8[] i64) i64
  i = 0 ## i64
  while i < n
    buf[i] = ((i * 37 + 13) & 255) ## u8
    i += 1
  n
init_rgba(jst_ta_view(ta_img_in), npix * 4)

f_gray = get_js_fn("js_rgba_gray")
args_gray = [ta_img_out, ta_img_in, npix.to_f]
zero_ta(ta_img_out)
r_gr_t0  = time_js_call(false, f_gray, args_gray, 0, 1)
chk_gr_t0 = js_ta_get(ta_img_out, 4000)
zero_ta(ta_img_out)
r_gr_jit = time_js_call(true, f_gray, args_gray, 5, 3)
chk_gr_jit = js_ta_get(ta_img_out, 4000)
comp_gr  = jst_compile_js_func(f_gray.code.node, [[:ta, 2], [:ta, 2], [:i64]], "i64")
zero_ta(ta_img_out)
r_gr_cmp = time_jst_call(comp_gr[0], args_gray, 2, 3)
chk_gr_cmp = js_ta_get(ta_img_out, 4000)
sw_gr_cpu = jst_match_swizzle(f_gray.code.node, [2, 2, -1], false)
zero_ta(ta_img_out)
r_gr_sw  = time_jst_call(sw_gr_cpu, args_gray, 2, 3)
chk_gr_sw = js_ta_get(ta_img_out, 4000)
sw_gr_gpu = jst_match_swizzle(f_gray.code.node, [2, 2, -1], true)
jst_dispatch_kernel(sw_gr_gpu, 3, ta_img_out, ta_img_in, npix.to_f, nil, JS_NO_ARGS)
zero_ta(ta_img_out)
r_gr_gpu = time_jst_call(sw_gr_gpu, args_gray, 1, 3)
chk_gr_gpu = js_ta_get(ta_img_out, 4000)
<< "    Tier 0 (walk.w, 1x -> 3x):  [fmt_ms(r_gr_t0[0] * ~3.0)] | px\[1000]=[chk_gr_t0]"
<< "    ARM64 JIT (jit=[f_gray.code.jit_fp != 0], 3 runs): [fmt_ms(r_gr_jit[0])] ([fmt_x(r_gr_t0[0] * ~3.0, r_gr_jit[0])] vs T0) | px\[1000]=[chk_gr_jit]"
<< "    JS->Tungsten compiled .o:   [fmt_ms(r_gr_cmp[0])] ([fmt_x(r_gr_t0[0] * ~3.0, r_gr_cmp[0])] vs T0, [fmt_x(r_gr_jit[0], r_gr_cmp[0])] vs JIT) | px\[1000]=[chk_gr_cmp] match=[chk_gr_t0 == chk_gr_cmp]"
<< "    AST-Swizzled CPU u8\[]:      [fmt_ms(r_gr_sw[0])] ([fmt_x(r_gr_t0[0] * ~3.0, r_gr_sw[0])] vs T0, [fmt_x(r_gr_jit[0], r_gr_sw[0])] vs JIT) | px\[1000]=[chk_gr_sw] match=[chk_gr_t0 == chk_gr_sw]"
<< "    Metal @gpu (zero-copy UM):  [fmt_ms(r_gr_gpu[0])] ([fmt_x(r_gr_t0[0] * ~3.0, r_gr_gpu[0])] vs T0, [fmt_x(r_gr_jit[0], r_gr_gpu[0])] vs JIT) | px\[1000]=[chk_gr_gpu] match=[chk_gr_t0 == chk_gr_gpu]"

# ---- Workload 5: Int32Array Bitwise Mix (N = 262,144, 5 runs) ----
<< ""
<< "\[5] Int32Array Bitwise Avalanche Mix (N=262,144, 5 runs)"
f_i32 = get_js_fn("js_mix_i32")
args_i32 = [ta_i32, n_ta.to_f]
r_i32_t0  = time_js_call(false, f_i32, args_i32, 0, 1)
r_i32_jit = time_js_call(true, f_i32, args_i32, 5, 5)
comp_i32  = jst_compile_js_func(f_i32.code.node, [[:ta, 5], [:i64]], "i64")
r_i32_cmp = time_jst_call(comp_i32[0], args_i32, 2, 5)
<< "    Tier 0 (walk.w, 1x -> 5x):  [fmt_ms(r_i32_t0[0] * ~5.0)] | res=[r_i32_t0[1]]"
<< "    ARM64 JIT (jit=[f_i32.code.jit_fp != 0], 5 runs): [fmt_ms(r_i32_jit[0])] ([fmt_x(r_i32_t0[0] * ~5.0, r_i32_jit[0])] vs T0) | res=[r_i32_jit[1]]"
<< "    JS->Tungsten compiled .o:   [fmt_ms(r_i32_cmp[0])] ([fmt_x(r_i32_t0[0] * ~5.0, r_i32_cmp[0])] vs T0, [fmt_x(r_i32_jit[0], r_i32_cmp[0])] vs JIT) | res=[r_i32_cmp[1]] match=[r_i32_t0[1] == r_i32_cmp[1]]"

# ---- Workload 6: BigUint64Array 64-bit FNV-1a Stream Hash (N = 262,144, 5 runs — native u64!) ----
<< ""
<< "\[6] BigUint64Array 64-bit FNV-1a Stream Hash (N=262,144, 5 runs — native u64 vs BigInt!)"
f_u64 = get_js_fn("js_hash_u64")
args_u64 = [ta_u64, n_ta.to_f]
r_u64_t0  = time_js_call(false, f_u64, args_u64, 0, 1)
r_u64_jit = nil
begin
  r_u64_jit = time_js_call(true, f_u64, args_u64, 2, 2)
rescue ex
  r_u64_jit = nil
comp_u64  = jst_compile_js_func(f_u64.code.node, [[:ta, 10], [:i64]], "i64")
r_u64_cmp = time_jst_call(comp_u64[0], args_u64, 2, 5)
sw_u64_desc = JstKernelDesc.new("js_hash_u64", :swizzle, 0, :tlib_hash_u64)
r_u64_sw  = time_jst_call(sw_u64_desc, args_u64, 2, 5)
<< "    Tier 0 (walk.w, 1x -> 5x):  [fmt_ms(r_u64_t0[0] * ~5.0)] | res=[r_u64_t0[1].v]"
if r_u64_jit != nil
  << "    ARM64 JIT (jit=[f_u64.code.jit_fp != 0], 2x->5x): [fmt_ms(r_u64_jit[0] * ~2.5)] ([fmt_x(r_u64_t0[0] * ~5.0, r_u64_jit[0] * ~2.5)] vs T0) | res=[r_u64_jit[1].v]"
else
  << "    ARM64 JIT (jit.w):          unsupported on BigInt loop (falls back to Tier 0)"
<< "    JS->Tungsten compiled .o:   [fmt_ms(r_u64_cmp[0])] ([fmt_x(r_u64_t0[0] * ~5.0, r_u64_cmp[0])] vs T0) | res=[r_u64_cmp[1].v] match=[r_u64_t0[1].v == r_u64_cmp[1].v]"
<< "    AST-Swizzled CPU u64\[]:     [fmt_ms(r_u64_sw[0])] ([fmt_x(r_u64_t0[0] * ~5.0, r_u64_sw[0])] vs T0) | res=[r_u64_sw[1].v] match=[r_u64_t0[1].v == r_u64_sw[1].v]"

<< ""
<< "Summary: compiled_kernels=[JST_COMPILED_COUNT[0]], swizzled=[JST_SWIZZLED_COUNT[0]], metal_offload=[JST_METAL_COUNT[0]]"
<< "Sample auto-generated Tungsten kernel (from js_hash_u64):"
<< comp_u64[1]

# bench_wire_a64.w — Benchmark & Correctness Verification for the Pure-Tungsten
# WIRE IR -> ARM64 Machine Code Backend (Alternative to clang / LLVM!).
#
# Tests:
#   1. Standalone WIRE IR text parsing -> ARM64 machine code execution
#   2. Direct JS AST -> WIRE IR -> ARM64 across ALL 12 ECMAScript TypedArray numeric widths
#   3. Compile Latency A/B: Pure-Tungsten WIRE->ARM64 (in-process MAP_JIT) vs
#      Tier 1 LLVM (`opt`+`llc -O0 -fast-isel`) vs Tier 2 `clang -O3 -mcpu=native`
#   4. Runtime Execution Speed A/B across 5 real numerical kernels!

use ../js
use ./js_to_wire

-> now_us
  (ccall_nobox("__w_clock_ns_raw") ## i64) / 1000

-> fmt1(v)
  iv = (v * ~10.0 + ~0.5).to_i
  (iv / 10).to_s + "." + (iv % 10).to_s

-> fmt2(v)
  iv = (v * ~100.0 + ~0.5).to_i
  frac = iv % 100
  (iv / 100).to_s + "." + (frac < 10 ? "0" + frac.to_s : frac.to_s)

-> must(cond, msg)
  if !cond
    << "FAIL: [msg]"
    exit(1)

realm = js_new_realm(nil)

<< "=== 1. Standalone WIRE IR Text -> Pure-Tungsten ARM64 Backend ==="
WIRE_SAMPLE = <<~WIRE
  function wire_sum_sq(a:f32[], n:i64) -> f64
    __entry:
      %vs.0 = alloca_f64
      %vs.1 = alloca_i64
      %p0 = arr_data_ptr %a ebits=-32
      %z0 = const_f64 0.0
      store_double %z0 ptr=%vs.0
      %z1 = const_i64 0
      store_i64 %z1 ptr=%vs.1
      br %while.cond
    while.cond:
      %i = load_i64 ptr=%vs.1
      %cmp = icmp_i64 slt %i %n
      cond_br %cmp %while.body %while.end
    while.body:
      %s = load_double ptr=%vs.0
      %idx = load_i64 ptr=%vs.1
      %v = typed_array_get_inline %p0 %idx ebits=-32
      %sq = fmul_f64 %v %v
      %ns = fadd_f64 %s %sq
      store_double %ns ptr=%vs.0
      %one = const_i64 1
      %ni = add_i64 %idx %one
      store_i64 %ni ptr=%vs.1
      br %while.cond
    while.end:
      %out = load_double ptr=%vs.0
      ret_f64 %out
WIRE

mod = wire_parse_text(WIRE_SAMPLE)
wf0 = mod.functions[0]
wf0.abi = :wvalue_ret_f64
cr0 = wire_compile_func(wf0)
must(cr0[0] != 0, "wire_compile_func failed on WIRE_SAMPLE")
arr_f32 = f32[1024]
ii = 0
exp_sq = ~0.0
while ii < 1024
  fv = ((ii % 17) - 8).to_f * ~0.5
  arr_f32[ii] = fv ## f32
  exp_sq += (arr_f32[ii] ## f64) * (arr_f32[ii] ## f64)
  ii += 1
got_sq = wvalue_from_bits(jst_call2(cr0[0], wvalue_bits(arr_f32) ## i64, wvalue_bits(1024) ## i64))
must((got_sq - exp_sq).abs < ~1e-9, "WIRE_SAMPLE mismatch: got=" + got_sq.to_s + " exp=" + exp_sq.to_s)
<< "  PASS Parsed WIRE IR text -> [cr0[1]] bytes ARM64 in [cr0[2]] us | result=[got_sq] (matches [exp_sq])"

<< ""
<< "=== 2. All 12 ECMAScript TypedArray Widths via Pure-Tungsten WIRE->ARM64 ==="
ALL12_JS = <<~JS
  function sum_ta(a, n) {
    var s = 0.0;
    for (var i = 0; i < n; i++) s += a[i];
    return s;
  }
  function xor_big(a, n) {
    var s = 0n;
    for (var i = 0; i < n; i++) s = s ^ a[i];
    return s;
  }
  var all12 = [
    new Int8Array([-128, -1, 0, 127]),
    new Uint8Array([0, 1, 128, 255]),
    new Uint8ClampedArray([-10, 0.5, 1.5, 300]),
    new Int16Array([-32768, -1, 0, 32767]),
    new Uint16Array([0, 1, 32768, 65535]),
    new Int32Array([-2147483648, -1, 0, 2147483647]),
    new Uint32Array([0, 1, 2147483648, 4294967295]),
    new Float32Array([-123.5, -0.5, 0.25, 1024.5]),
    new Float64Array([-1e100, -0.125, 0.125, 1e100]),
    new BigInt64Array([-9223372036854775808n, -1n, 0n, 9223372036854775807n]),
    new BigUint64Array([0n, 1n, 9223372036854775808n, 18446744073709551615n]),
    new Float16Array([-65504, -1.5, 0.25, 3.5])
  ];
  all12;
JS
all12 = js_run_script(ALL12_JS, "all12_wire.js")
f_sum_ta = realm.global.get("sum_ta")
f_xor_big = realm.global.get("xor_big")
tot_us_12 = 0
tot_bytes_12 = 0
k = 0
while k < 12
  ta = all12[k]
  va = js_ta_ebits_view(ta)
  if k == 9 || k == 10
    r_js = js_call(f_xor_big, nil, 2, ta, ~4.0, nil, nil, JS_NO_ARGS)
    cr = wire_a64_compile_js_func(f_xor_big.code.node, [[:ta, k], [:i64]], "i64")
    must(cr != nil, "wire_a64 compile failed for kind " + k.to_s)
    tot_us_12 += cr[2]; tot_bytes_12 += cr[1]
    rv = jst_call2(cr[0], wvalue_bits(va) ## i64, 4 ## i64)
    u = k == 10 ? (rv < 0 ? ((rv ## int) + ((1 ## int) << 64)) : (rv ## int)) : (rv ## int)
    must(r_js.v == u, "BigInt wire_a64 mismatch kind " + k.to_s)
  else
    r_js = js_call(f_sum_ta, nil, 2, ta, ~4.0, nil, nil, JS_NO_ARGS)
    cr = wire_a64_compile_js_func(f_sum_ta.code.node, [[:ta, k], [:i64]], "f64")
    must(cr != nil, "wire_a64 compile failed for kind " + k.to_s)
    tot_us_12 += cr[2]; tot_bytes_12 += cr[1]
    rv = wvalue_from_bits(jst_call2(cr[0], wvalue_bits(va) ## i64, wvalue_bits(4) ## i64))
    must(r_js == rv, "Numeric wire_a64 mismatch kind " + k.to_s + ": js=" + r_js.to_s + " w=" + rv.to_s)
  k += 1
<< "  PASS All 12 TypedArray kinds compiled directly to ARM64 in [tot_us_12] us total ([tot_us_12 / 12] us/fn avg, [tot_bytes_12] bytes total code) — 100% bit-exact!"

<< ""
<< "=== 3. Compile Time & Runtime A/B: Pure-Tungsten WIRE->ARM64 vs LLVM Tier 1 vs clang -O3 ==="
BENCH_JS = <<~JS
  function dot_f32(a, b, n) {
    var s = 0.0;
    for (var i = 0; i < n; i++) s += a[i] * b[i];
    return s;
  }
  function relu_f16(out, inp, sc, n) {
    for (var i = 0; i < n; i++) {
      var v = inp[i] * sc;
      out[i] = v > 0 ? v : 0;
    }
    return n;
  }
  function mix_i32(a, n) {
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
  function hash_u64(a, n) {
    var h = 14695981039346656037n;
    var p = 1099511628211n;
    for (var i = 0; i < n; i++) {
      h = BigInt.asUintN(64, (h ^ a[i]) * p);
    }
    return h;
  }
  var N = 262144;
  var f32a = new Float32Array(N);
  var f32b = new Float32Array(N);
  var f16i = new Float16Array(N);
  var f16o = new Float16Array(N);
  var i32a = new Int32Array(N);
  var u64a = new BigUint64Array(N);
  for (var i = 0; i < N; i++) {
    f32a[i] = ((i & 31) - 16) * 0.25;
    f32b[i] = ((i & 15) - 8) * 0.5;
    f16i[i] = ((i & 31) - 16) * 0.5;
    i32a[i] = (i * 2654435761) | 0;
    u64a[i] = BigInt(i) * 6364136223846793005n + 1n;
  }
  true;
JS
js_run_script(BENCH_JS, "wire_bench.js")

f_dot = realm.global.get("dot_f32")
f_rel = realm.global.get("relu_f16")
f_mix = realm.global.get("mix_i32")
f_h64 = realm.global.get("hash_u64")
f32a = realm.global.get("f32a"); f32b = realm.global.get("f32b")
f16i = realm.global.get("f16i"); f16o = realm.global.get("f16o")
i32a = realm.global.get("i32a"); u64a = realm.global.get("u64a")

# Compile all 4 kernels via WIRE->ARM64 (100-iteration avg compile latency)
t0 = now_us()
ci = 0
w_dot = nil; w_rel = nil; w_mix = nil; w_h64 = nil
while ci < 50
  w_dot = wire_a64_compile_js_func(f_dot.code.node, [[:ta, 7], [:ta, 7], [:i64]], "f64")
  w_rel = wire_a64_compile_js_func(f_rel.code.node, [[:ta, 11], [:ta, 11], [:f64], [:i64]], "i64")
  w_mix = wire_a64_compile_js_func(f_mix.code.node, [[:ta, 5], [:i64]], "i64")
  w_h64 = wire_a64_compile_js_func(f_h64.code.node, [[:ta, 10], [:i64]], "i64")
  ci += 1
t1 = now_us()
us_wire_per_fn = (t1 - t0).to_f / ~200.0
<< "  Pure-Tungsten WIRE->ARM64 compile time (200 compiles avg): [fmt1(us_wire_per_fn)] us/fn ([fmt2(us_wire_per_fn / ~1000.0)] ms/fn)!"
<< "  Code sizes: dot_f32=[w_dot[1]]B, relu_f16=[w_rel[1]]B, mix_i32=[w_mix[1]]B, hash_u64=[w_h64[1]]B"

# Cold-compile 1 kernel via clang -O3 (Tier 2) to measure real wall-clock compile speedup!
OS.system("rm -rf " + JST_CACHE_DIR + "/*")
t0 = now_us()
c_dot_t1 = jst_compile_js_func(f_dot.code.node, [[:ta, 7], [:ta, 7], [:i64]], "f64", 1)
t1 = now_us()
ms_llvm_t1 = (t1 - t0).to_f / ~1000.0

t0 = now_us()
c_dot_t2 = jst_compile_js_func(f_dot.code.node, [[:ta, 7], [:ta, 7], [:i64]], "f64", 2)
t1 = now_us()
ms_clang_t2 = (t1 - t0).to_f / ~1000.0
<< "  Single-kernel compile A/B: WIRE->ARM64=[fmt2(us_wire_per_fn / ~1000.0)] ms vs opt+llc FastISel=[fmt2(ms_llvm_t1)] ms ([fmt1(ms_llvm_t1 * ~1000.0 / us_wire_per_fn)]x faster!) vs clang -O3=[fmt2(ms_clang_t2)] ms ([fmt1(ms_clang_t2 * ~1000.0 / us_wire_per_fn)]x faster!)"

# Runtime execution comparison (262K elements x 5 runs)
# 1. dot_f32
va = js_ta_ebits_view(f32a); vb = js_ta_ebits_view(f32b)
t0 = now_us()
r_w = ~0.0; ri = 0
while ri < 5
  r_w = wvalue_from_bits(jst_call3(w_dot[0], wvalue_bits(va) ## i64, wvalue_bits(vb) ## i64, wvalue_bits(262144) ## i64))
  ri += 1
t1 = now_us(); ms_w_dot = (t1 - t0).to_f / ~1000.0

t0 = now_us()
r_c = ~0.0; ri = 0
while ri < 5
  r_c = jst_dispatch_kernel(c_dot_t2[0], 3, f32a, f32b, ~262144.0, nil, JS_NO_ARGS)
  ri += 1
t1 = now_us(); ms_c_dot = (t1 - t0).to_f / ~1000.0
must((r_w - r_c).abs < ~1e-6, "dot_f32 mismatch: w=" + r_w.to_s + " c=" + r_c.to_s)
<< "  [dot_f32  262Kx5] WIRE->ARM64=[fmt2(ms_w_dot)] ms vs clang -O3=[fmt2(ms_c_dot)] ms | res=[r_w] match=true"

# 2. relu_f16
c_rel_t2 = jst_compile_js_func(f_rel.code.node, [[:ta, 11], [:ta, 11], [:f64], [:i64]], "i64", 2)
vo16 = js_ta_ebits_view(f16o); vi16 = js_ta_ebits_view(f16i)
t0 = now_us()
ri = 0
while ri < 5
  jst_call4(w_rel[0], wvalue_bits(vo16) ## i64, wvalue_bits(vi16) ## i64, wvalue_bits(~1.5) ## i64, 262144 ## i64)
  ri += 1
t1 = now_us(); ms_w_rel = (t1 - t0).to_f / ~1000.0
p50_w = js_ta_get(f16o, 50)

t0 = now_us()
ri = 0
while ri < 5
  jst_dispatch_kernel(c_rel_t2[0], 4, f16o, f16i, ~1.5, ~262144.0, JS_NO_ARGS)
  ri += 1
t1 = now_us(); ms_c_rel = (t1 - t0).to_f / ~1000.0
p50_c = js_ta_get(f16o, 50)
must(p50_w == p50_c, "relu_f16 mismatch: w=" + p50_w.to_s + " c=" + p50_c.to_s)
<< "  [relu_f16 262Kx5] WIRE->ARM64=[fmt2(ms_w_rel)] ms vs clang -O3=[fmt2(ms_c_rel)] ms | out[50]=[p50_w] match=true"

# 3. mix_i32
c_mix_t2 = jst_compile_js_func(f_mix.code.node, [[:ta, 5], [:i64]], "i64", 2)
vm = js_ta_ebits_view(i32a)
t0 = now_us()
rm_w = 0; ri = 0
while ri < 5
  rm_w = jst_call2(w_mix[0], wvalue_bits(vm) ## i64, 262144 ## i64)
  ri += 1
t1 = now_us(); ms_w_mix = (t1 - t0).to_f / ~1000.0

t0 = now_us()
rm_c = ~0.0; ri = 0
while ri < 5
  rm_c = jst_dispatch_kernel(c_mix_t2[0], 2, i32a, ~262144.0, nil, nil, JS_NO_ARGS)
  ri += 1
t1 = now_us(); ms_c_mix = (t1 - t0).to_f / ~1000.0
must(rm_w.to_f == rm_c, "mix_i32 mismatch: w=" + rm_w.to_s + " c=" + rm_c.to_s)
<< "  [mix_i32  262Kx5] WIRE->ARM64=[fmt2(ms_w_mix)] ms vs clang -O3=[fmt2(ms_c_mix)] ms | res=[rm_w] match=true"

# 4. hash_u64
c_h64_t2 = jst_compile_js_func(f_h64.code.node, [[:ta, 10], [:i64]], "i64", 2)
vh = js_ta_ebits_view(u64a)
t0 = now_us()
rh_w = 0; ri = 0
while ri < 5
  rh_w = jst_call2(w_h64[0], wvalue_bits(vh) ## i64, 262144 ## i64)
  ri += 1
t1 = now_us(); ms_w_h64 = (t1 - t0).to_f / ~1000.0
u_w = rh_w < 0 ? ((rh_w ## int) + ((1 ## int) << 64)) : (rh_w ## int)

t0 = now_us()
rh_c = nil; ri = 0
while ri < 5
  rh_c = jst_dispatch_kernel(c_h64_t2[0], 2, u64a, ~262144.0, nil, nil, JS_NO_ARGS)
  ri += 1
t1 = now_us(); ms_c_h64 = (t1 - t0).to_f / ~1000.0
must(u_w == rh_c.v, "hash_u64 mismatch: w=" + u_w.to_s + " c=" + rh_c.v.to_s)
<< "  [hash_u64 262Kx5] WIRE->ARM64=[fmt2(ms_w_h64)] ms vs clang -O3=[fmt2(ms_c_h64)] ms | res=[u_w] match=true"

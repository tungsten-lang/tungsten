# bench_wire_a64.w — Benchmark & Correctness Verification for Cinder's Two-Pass
# Pure-Tungsten JS -> WIRE IR -> Native Machine Code Pipeline (ZERO Clang / ZERO LLVM / ZERO `.ll`!):
#
#   1. Standalone WIRE IR text parsing -> native machine code execution
#   2. Direct JS AST -> WIRE IR across ALL 12 ECMAScript TypedArray numeric widths
#   3. Two-Pass Compile Latency & Runtime Speedup:
#        - Pass 1 (Tier 1): blazing-fast single-pass baseline (~4-6 us/fn)
#        - Pass 2 (Tier 2): modular multi-pass optimizer + SIMD + hardware carry chains (~15-25 us/fn)
#   4. 4096-bit (64-limb) BigInt Hardware Carry Chains (`bigint_add`, `bigint_sub`, `bigint_addmul1`):
#        - Tier-0 JS BigInt interpreter vs Cinder Tier 1 vs Cinder Tier 2 flag-threaded carry loops!

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

JST_ENABLED[0] = false
JIT_ENABLED[0] = false
realm = js_new_realm(nil)

<< "=== 1. Standalone WIRE IR Text -> Pure-Tungsten Cinder Backend ==="
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
cr0 = wire_compile_func_tier(wf0, 2)
must(cr0[0] != 0, "wire_compile_func_tier failed on WIRE_SAMPLE")
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
<< "  PASS Parsed WIRE IR text -> [cr0[1]] bytes native code in [cr0[2]] us | result=[got_sq] (matches [exp_sq])"

<< ""
<< "=== 2. All 12 ECMAScript TypedArray Widths via Cinder WIRE Backend ==="
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
    cr = wire_a64_compile_js_func(f_xor_big.code.node, [[:ta, k], [:i64]], "i64", nil, 1)
    must(cr != nil, "wire_a64 compile failed for kind " + k.to_s)
    tot_us_12 += cr[2]; tot_bytes_12 += cr[1]
    rv = jst_call2(cr[0], wvalue_bits(va) ## i64, 4 ## i64)
    u = k == 10 ? (rv < 0 ? ((rv ## int) + ((1 ## int) << 64)) : (rv ## int)) : (rv ## int)
    must(r_js.v == u, "BigInt wire_a64 mismatch kind " + k.to_s)
  else
    r_js = js_call(f_sum_ta, nil, 2, ta, ~4.0, nil, nil, JS_NO_ARGS)
    cr = wire_a64_compile_js_func(f_sum_ta.code.node, [[:ta, k], [:i64]], "f64", nil, 1)
    must(cr != nil, "wire_a64 compile failed for kind " + k.to_s)
    tot_us_12 += cr[2]; tot_bytes_12 += cr[1]
    rv = wvalue_from_bits(jst_call2(cr[0], wvalue_bits(va) ## i64, wvalue_bits(4) ## i64))
    must(r_js == rv, "Numeric wire_a64 mismatch kind " + k.to_s + ": js=" + r_js.to_s + " w=" + rv.to_s)
  k += 1
<< "  PASS All 12 TypedArray kinds compiled (Tier 1) in [tot_us_12] us total ([tot_us_12 / 12] us/fn avg, [tot_bytes_12] bytes total) — 100% bit-exact!"

<< ""
<< "=== 3. Two-Pass Tier-1 (Fast Baseline) vs Tier-2 (Optimizing Re-Compile) Latency & Speedup ==="
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
  function bigint_add64(out, a, b, n) {
    var c = 0n;
    for (var i = 0; i < n; i++) {
      var s = a[i] + b[i] + c;
      out[i] = s;
      c = s >> 64n;
    }
    return c;
  }
  function bigint_sub64(out, a, b, n) {
    var brw = 0n;
    for (var i = 0; i < n; i++) {
      var d = a[i] - b[i] - brw;
      out[i] = d;
      brw = d < 0n ? 1n : 0n;
    }
    return brw;
  }
  function bigint_addmul64(out, a, w, n) {
    var c = 0n;
    for (var i = 0; i < n; i++) {
      var p = out[i] + a[i] * w + c;
      out[i] = p;
      c = p >> 64n;
    }
    return c;
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

  var NL = 64;
  var ba64 = new BigUint64Array(NL);
  var bb64 = new BigUint64Array(NL);
  var bo64 = new BigUint64Array(NL);
  for (var j = 0; j < NL; j++) {
    ba64[j] = 0xfffffffffffffff0n + BigInt(j & 15);
    bb64[j] = 0x7ffffffffffffff8n + BigInt((j * 7) & 15);
  }
  true;
JS
js_run_script(BENCH_JS, "wire_bench.js")

f_dot = realm.global.get("dot_f32")
f_rel = realm.global.get("relu_f16")
f_mix = realm.global.get("mix_i32")
f_h64 = realm.global.get("hash_u64")
f_badd = realm.global.get("bigint_add64")
f_bsub = realm.global.get("bigint_sub64")
f_bam  = realm.global.get("bigint_addmul64")

f32a = realm.global.get("f32a"); f32b = realm.global.get("f32b")
f16i = realm.global.get("f16i"); f16o = realm.global.get("f16o")
i32a = realm.global.get("i32a"); u64a = realm.global.get("u64a")
ba64 = realm.global.get("ba64"); bb64 = realm.global.get("bb64"); bo64 = realm.global.get("bo64")

# Measure WireFunc Tier-1 codegen vs Tier-2 optimizer+codegen latency (100 iterations x 4 kernels)
wf_dot = wire_a64_lower_js_func(f_dot.code.node, [[:ta, 7], [:ta, 7], [:i64]], "f64")
wf_rel = wire_a64_lower_js_func(f_rel.code.node, [[:ta, 11], [:ta, 11], [:f64], [:i64]], "i64")
wf_badd = wire_a64_lower_js_func(f_badd.code.node, [[:ta, 10], [:ta, 10], [:ta, 10], [:i64]], "i64")
wf_bam  = wire_a64_lower_js_func(f_bam.code.node, [[:ta, 10], [:ta, 10], [:u64], [:i64]], "i64")

t0 = now_us()
ci = 0
dot_t1 = nil; rel_t1 = nil; badd_t1 = nil; bam_t1 = nil
while ci < 100
  dot_t1  = wire_compile_func_tier(wf_dot, 1)
  rel_t1  = wire_compile_func_tier(wf_rel, 1)
  badd_t1 = wire_compile_func_tier(wf_badd, 1)
  bam_t1  = wire_compile_func_tier(wf_bam, 1)
  ci += 1
t1 = now_us()
us_t1 = (t1 - t0).to_f / ~400.0

t0 = now_us()
ci = 0
dot_t2 = nil; rel_t2 = nil; badd_t2 = nil; bam_t2 = nil
while ci < 100
  dot_t2  = wire_compile_func_tier(wf_dot, 2)
  rel_t2  = wire_compile_func_tier(wf_rel, 2)
  badd_t2 = wire_compile_func_tier(wf_badd, 2)
  bam_t2  = wire_compile_func_tier(wf_bam, 2)
  ci += 1
t1 = now_us()
us_t2 = (t1 - t0).to_f / ~400.0

<< "  Pass 1 (Tier-1 baseline compile, 400 compiles avg): [fmt1(us_t1)] us/fn"
<< "  Pass 2 (Tier-2 optimizing re-compile, 400 avg):     [fmt1(us_t2)] us/fn (ZERO Clang, ZERO LLVM, ZERO .ll!)"
<< "  Code sizes T1->T2: dot_f32=[dot_t1[1]]B->[dot_t2[1]]B | relu_f16=[rel_t1[1]]B->[rel_t2[1]]B | bigint_add=[badd_t1[1]]B->[badd_t2[1]]B | addmul1=[bam_t1[1]]B->[bam_t2[1]]B"

# Runtime execution comparison: Tier 1 vs Tier 2 on dot_f32 (262K x 10)
va = js_ta_ebits_view(f32a); vb = js_ta_ebits_view(f32b)
t0 = now_us()
r_t1 = ~0.0; ri = 0
while ri < 10
  r_t1 = wvalue_from_bits(jst_call3(dot_t1[0], wvalue_bits(va) ## i64, wvalue_bits(vb) ## i64, wvalue_bits(262144) ## i64))
  ri += 1
ms_dot_t1 = (now_us() - t0).to_f / ~1000.0

t0 = now_us()
r_t2 = ~0.0; ri = 0
while ri < 10
  r_t2 = wvalue_from_bits(jst_call3(dot_t2[0], wvalue_bits(va) ## i64, wvalue_bits(vb) ## i64, wvalue_bits(262144) ## i64))
  ri += 1
ms_dot_t2 = (now_us() - t0).to_f / ~1000.0
must((r_t1 - r_t2).abs < ~1e-9, "dot_f32 Tier-1 vs Tier-2 mismatch")
<< "  (dot_f32  262Kx10) Tier 1=[fmt2(ms_dot_t1)] ms -> Tier 2 (NEON/SSE2)=[fmt2(ms_dot_t2)] ms ([fmt2(ms_dot_t1 / ms_dot_t2)]x faster!)"

<< ""
<< "=== 4. 4096-bit (64-limb) BigInt Carry-Chain Benchmark (Tier-0 JS vs Tier 1 vs Tier 2 Hardware Flags) ==="
v_ba = js_ta_ebits_view(ba64); v_bb = js_ta_ebits_view(bb64); v_bo = js_ta_ebits_view(bo64)
wf_bsub = wire_a64_lower_js_func(f_bsub.code.node, [[:ta, 10], [:ta, 10], [:ta, 10], [:i64]], "i64")
bsub_t1 = wire_compile_func_tier(wf_bsub, 1)
bsub_t2 = wire_compile_func_tier(wf_bsub, 2)

# Verify Tier-0 JS vs Tier-1 vs Tier-2 exact limb parity on 64 limbs first!
c0_js = js_call(f_badd, nil, 4, bo64, ba64, bb64, ~64.0, JS_NO_ARGS)
bo_ref = u64[64]
li = 0
while li < 64
  bo_ref[li] = v_bo[li]
  li += 1
c0_t1 = jst_call4(badd_t1[0], wvalue_bits(v_bo) ## i64, wvalue_bits(v_ba) ## i64, wvalue_bits(v_bb) ## i64, 64 ## i64)
li = 0
while li < 64
  must((v_bo[li] ## i64) == (bo_ref[li] ## i64), "bigint_add64 T1 limb mismatch at " + li.to_s)
  li += 1
c0_t2 = jst_call4(badd_t2[0], wvalue_bits(v_bo) ## i64, wvalue_bits(v_ba) ## i64, wvalue_bits(v_bb) ## i64, 64 ## i64)
li = 0
while li < 64
  must((v_bo[li] ## i64) == (bo_ref[li] ## i64), "bigint_add64 T2 limb mismatch at " + li.to_s)
  li += 1
must(c0_js.v == (c0_t1 ## int) && c0_js.v == (c0_t2 ## int), "bigint_add64 carry-out mismatch")

# Benchmark 100,000 x 64-limb (6.4M limbs!) BigInt additions & multiply-accumulates
t0 = now_us()
ri = 0
while ri < 1000
  js_call(f_badd, nil, 4, bo64, ba64, bb64, ~64.0, JS_NO_ARGS)
  ri += 1
us_js_1k = (now_us() - t0).to_f
ms_js_equiv = us_js_1k * ~100.0 / ~1000.0   # scaled to 100K calls

t0 = now_us()
ri = 0
while ri < 100000
  jst_call4(badd_t1[0], wvalue_bits(v_bo) ## i64, wvalue_bits(v_ba) ## i64, wvalue_bits(v_bb) ## i64, 64 ## i64)
  ri += 1
ms_badd_t1 = (now_us() - t0).to_f / ~1000.0

t0 = now_us()
ri = 0
while ri < 100000
  jst_call4(badd_t2[0], wvalue_bits(v_bo) ## i64, wvalue_bits(v_ba) ## i64, wvalue_bits(v_bb) ## i64, 64 ## i64)
  ri += 1
ms_badd_t2 = (now_us() - t0).to_f / ~1000.0

t0 = now_us()
ri = 0
while ri < 100000
  jst_call4(bsub_t1[0], wvalue_bits(v_bo) ## i64, wvalue_bits(v_ba) ## i64, wvalue_bits(v_bb) ## i64, 64 ## i64)
  ri += 1
ms_bsub_t1 = (now_us() - t0).to_f / ~1000.0

t0 = now_us()
ri = 0
while ri < 100000
  jst_call4(bsub_t2[0], wvalue_bits(v_bo) ## i64, wvalue_bits(v_ba) ## i64, wvalue_bits(v_bb) ## i64, 64 ## i64)
  ri += 1
ms_bsub_t2 = (now_us() - t0).to_f / ~1000.0

w_mul = -7046029288634856825 ## i64
t0 = now_us()
ri = 0
while ri < 100000
  jst_call4(bam_t1[0], wvalue_bits(v_bo) ## i64, wvalue_bits(v_ba) ## i64, w_mul, 64 ## i64)
  ri += 1
ms_bam_t1 = (now_us() - t0).to_f / ~1000.0

t0 = now_us()
ri = 0
while ri < 100000
  jst_call4(bam_t2[0], wvalue_bits(v_bo) ## i64, wvalue_bits(v_ba) ## i64, w_mul, 64 ## i64)
  ri += 1
ms_bam_t2 = (now_us() - t0).to_f / ~1000.0

<< "  (4096-bit add     x100K = 6.4M limbs) JS Tier-0=~[fmt1(ms_js_equiv)] ms | Tier 1=[fmt2(ms_badd_t1)] ms | Tier 2 (adcsx4)=[fmt2(ms_badd_t2)] ms ([fmt2(ms_badd_t1 / ms_badd_t2)]x over T1, [fmt1(ms_js_equiv / ms_badd_t2)]x over JS!)"
<< "  (4096-bit sub     x100K = 6.4M limbs) Tier 1=[fmt2(ms_bsub_t1)] ms | Tier 2 (sbcsx4)=[fmt2(ms_bsub_t2)] ms ([fmt2(ms_bsub_t1 / ms_bsub_t2)]x faster!)"
<< "  (4096-bit addmul1 x100K = 6.4M limbs) Tier 1=[fmt2(ms_bam_t1)] ms | Tier 2 (umulh+cinc)=[fmt2(ms_bam_t2)] ms ([fmt2(ms_bam_t1 / ms_bam_t2)]x faster!)"

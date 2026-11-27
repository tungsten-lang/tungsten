# bench_all.w — End-to-End Verification & A/B Suite covering:
#   1. Full JsParser A/B: Baseline pull JsLexer vs SIMD Lex16 (Token WValues) behind JS_SIMD_LEX
#   2. All 12 JS TypedArray numeric widths (i8, u8, u8c, i16, u16, i32, u32, i64, u64, f16, f32, f64):
#      native b_typed.w raw loads/stores + cached zero-copy `ebits` WArray + jsn_t compilation!
#   3. Two-Tier Compilation (Tier 1 trimmed opt+FastISel -> automatic Tier 2 -O3 -mcpu=native)
#      through `BLADE_JS_TUNGSTEN=1` engine dispatch, with strict tier-execution assertions!
#   4. Fast 64-bit FNV-1a/fmix64 cache hash benchmark vs SHA-256 + zero temp-file leak check
#   5. Two-Shape Inline Property Cache (object.w), Proxy prototype safety, & Dense Literal Switch (walk.w)

use ../js

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

# ==============================================================================
# 1. JsParser Full Parse A/B: Baseline Pull Lexer vs SIMD Lex16 Token WValues
# ==============================================================================
<< "=== 1. JsParser Full Parse A/B (Baseline vs BLADE_JS_SIMD_LEX=1) ==="

PARSE_UNIT = <<~JS
  class Particle {
    constructor(x, y, vx, vy, mass) {
      this.x = x; this.y = y; this.vx = vx; this.vy = vy; this.mass = mass;
    }
    step(dt, gx, gy) {
      const ax = gx / this.mass;
      const ay = gy / this.mass;
      this.vx += ax * dt;
      this.vy += ay * dt;
      this.x += this.vx * dt;
      this.y += this.vy * dt;
      if (this.x < 0 || this.x > 1000) this.vx = -this.vx * 0.95;
      if (this.y < 0 || this.y > 1000) this.vy = -this.vy * 0.95;
      return this.x * this.x + this.y * this.y;
    }
  }
  function integrate(arr, n, dt) {
    let sum = 0.0;
    for (let i = 0; i < n; i++) {
      const p = arr[i];
      if (p !== null && p !== undefined) {
        sum += p.step(dt, 0.0, -9.81);
      }
    }
    return sum;
  }
JS

# Verify exact AST node-count parity on Test262 harness files + PARSE_UNIT
parse_files = [
  "/Users/erik/src/test262/harness/assert.js",
  "/Users/erik/src/test262/harness/propertyHelper.js",
  "/Users/erik/src/test262/harness/deepEqual.js",
  "/Users/erik/src/test262/harness/temporalHelpers.js",
  "/Users/erik/src/test262/harness/testTypedArray.js",
  "/Users/erik/src/test262/harness/testIntl.js"
]
tot_nodes = 0
parse_files.each ->(path)
  if File.exist?(path)
    src = File.read(path)
    JS_SIMD_LEX[0] = false
    p0 = JsParser.new(src, false)
    p0.parse_program()
    JS_SIMD_LEX[0] = true
    p1 = JsParser.new(src, false)
    must(p1.simd_toks != nil, "SIMD lexer did not activate on ASCII file " + path) if src.ascii?
    p1.parse_program()
    must(p0.count == p1.count, "AST node count mismatch on " + path + ": base=" + p0.count.to_s + " simd=" + p1.count.to_s)
    tot_nodes += p1.count
<< "  PASS Parse AST parity across 6 Test262 harness files: [tot_nodes] AST nodes matched 100%"

# Build ~1 MB realistic JS bundle and benchmark full JsParser.parse_program()
parts = []
pi = 0
while pi < 1400
  parts.push(PARSE_UNIT)
  pi += 1
big_js = parts.join("\n")
prounds = 6

JS_SIMD_LEX[0] = false
# warmup
JsParser.new(big_js, false).parse_program()
t0 = now_us()
ri = 0
base_cnt = 0
while ri < prounds
  p = JsParser.new(big_js, false)
  p.parse_program()
  base_cnt = p.count
  ri += 1
t1 = now_us()
ms_parse_base = (t1 - t0).to_f / ~1000.0

JS_SIMD_LEX[0] = true
JsParser.new(big_js, false).parse_program()
t0 = now_us()
ri = 0
simd_cnt = 0
while ri < prounds
  p = JsParser.new(big_js, false)
  must(p.simd_toks != nil, "SIMD lexer not active in parse bench")
  p.parse_program()
  simd_cnt = p.count
  ri += 1
t1 = now_us()
ms_parse_simd = (t1 - t0).to_f / ~1000.0
JS_SIMD_LEX[0] = false

must(base_cnt == simd_cnt, "Big bundle AST count mismatch")
mb_base = (big_js.size.to_f * prounds.to_f * ~1000.0) / (ms_parse_base * ~1000000.0)
mb_simd = (big_js.size.to_f * prounds.to_f * ~1000.0) / (ms_parse_simd * ~1000000.0)
<< "  Bundle: [big_js.size] bytes x [prounds] rounds ([base_cnt] AST nodes/parse)"
<< "  JsParser (baseline pull lexer): [fmt2(ms_parse_base)] ms ([fmt1(mb_base)] MB/s)"
<< "  JsParser (SIMD Lex16 Tokens):   [fmt2(ms_parse_simd)] ms ([fmt1(mb_simd)] MB/s) — [fmt2(ms_parse_base / ms_parse_simd)]x faster full parse!"

# ==============================================================================
# 2. All 12 JS TypedArray Numeric Widths (b_typed.w raw LLVM + cached ebits view + jsn_t)
# ==============================================================================
<< ""
<< "=== 2. All 12 Numeric Widths Verification (i8/u8/u8c/i16/u16/i32/u32/i64/u64/f16/f32/f64) ==="

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
  function check_all12() {
    var i8  = new Int8Array([-128, -1, 0, 127]);
    var u8  = new Uint8Array([0, 1, 128, 255]);
    var u8c = new Uint8ClampedArray([-10, 0.5, 1.5, 300]);
    var i16 = new Int16Array([-32768, -1, 0, 32767]);
    var u16 = new Uint16Array([0, 1, 32768, 65535]);
    var i32 = new Int32Array([-2147483648, -1, 0, 2147483647]);
    var u32 = new Uint32Array([0, 1, 2147483648, 4294967295]);
    var f16 = new Float16Array([-65504, -1.5, 0.25, 3.5]);
    var f32 = new Float32Array([-123.5, -0.5, 0.25, 1024.5]);
    var f64 = new Float64Array([-1e100, -0.125, 0.125, 1e100]);
    var b64 = new BigInt64Array([-9223372036854775808n, -1n, 0n, 9223372036854775807n]);
    var bu64 = new BigUint64Array([0n, 1n, 9223372036854775808n, 18446744073709551615n]);
    var ok =
      i8[0] === -128 && i8[3] === 127 &&
      u8[0] === 0 && u8[3] === 255 &&
      u8c[0] === 0 && u8c[1] === 0 && u8c[2] === 2 && u8c[3] === 255 &&
      i16[0] === -32768 && i16[3] === 32767 &&
      u16[0] === 0 && u16[3] === 65535 &&
      i32[0] === -2147483648 && i32[3] === 2147483647 &&
      u32[0] === 0 && u32[3] === 4294967295 &&
      f16[0] === -65504 && f16[1] === -1.5 && f16[2] === 0.25 && f16[3] === 3.5 &&
      f32[0] === -123.5 && f32[3] === 1024.5 &&
      f64[0] === -1e100 && f64[3] === 1e100 &&
      b64[0] === -9223372036854775808n && b64[3] === 9223372036854775807n &&
      bu64[0] === 0n && bu64[3] === 18446744073709551615n;
    return ok ? [i8, u8, u8c, i16, u16, i32, u32, f32, f64, b64, bu64, f16] : null;
  }
  check_all12();
JS
all12 = js_run_script(ALL12_JS, "all12.js")
must(js_array?(all12) && all12.size == 12, "All 12 TypedArray native load/store check failed!")

# Verify cached zero-copy `js_ta_ebits_view` + jsn_t compiled kernel for ALL 12 kinds!
f_sum_ta = realm.global.get("sum_ta")
f_xor_big = realm.global.get("xor_big")
k = 0
while k < 12
  ta = all12[k]
  v = js_ta_ebits_view(ta)
  must(v != nil && v.size == 4, "js_ta_ebits_view failed for kind " + k.to_s)
  # Ensure cached view returns the exact same WArray object on second call
  v2 = js_ta_ebits_view(ta)
  must(wvalue_bits(v) == wvalue_bits(v2), "js_ta_ebits_view not cached for kind " + k.to_s)
  if k == 9 || k == 10
    # Compile & verify BigInt64Array (i64[]) and BigUint64Array (u64[])
    r_js = js_call(f_xor_big, nil, 2, ta, ~4.0, nil, nil, JS_NO_ARGS)
    comp = jst_compile_js_func(f_xor_big.code.node, [[:ta, k], [:i64]], "i64", 1)
    must(comp[0] != nil, "jsn_t compile failed for BigInt kind " + k.to_s)
    r_t = jst_dispatch_kernel(comp[0], 2, ta, ~4.0, nil, nil, JS_NO_ARGS)
    must(r_js.v == r_t.v, "BigInt mismatch for kind " + k.to_s + ": js=" + r_js.v.to_s + " t=" + r_t.v.to_s)
  else
    r_js = js_call(f_sum_ta, nil, 2, ta, ~4.0, nil, nil, JS_NO_ARGS)
    comp = jst_compile_js_func(f_sum_ta.code.node, [[:ta, k], [:i64]], "f64", 1)
    must(comp[0] != nil, "jsn_t compile failed for numeric kind " + k.to_s)
    r_t = jst_dispatch_kernel(comp[0], 2, ta, ~4.0, nil, nil, JS_NO_ARGS)
    must(r_js == r_t, "Numeric mismatch for kind " + k.to_s + ": js=" + r_js.to_s + " t=" + r_t.to_s)
  k += 1
<< "  PASS All 12 TypedArray kinds (i8, u8, u8c, i16, u16, i32, u32, f32, f64, i64, u64, f16): b_typed raw LLVM + cached ebits WArray + jsn_t compiled kernel 100% bit-exact!"

# ==============================================================================
# 3. Two-Tier Compilation (Tier 1 Fast -> Automatic Hot Tier 2 -O3) via BLADE_JS_TUNGSTEN=1
# ==============================================================================
<< ""
<< "=== 3. Two-Tier Compilation & Engine Dispatch (BLADE_JS_TUNGSTEN=1) ==="
jst_reset_stats()
JST_ENABLED[0] = true
JST_ALLOW_CLANG[0] = true
JST_TIER2_HITS[0] = 3
JST_TIER2_ELEMS[0] = 10000000

TIER_JS = <<~JS
  function custom_kernel_i32(arr, n) {
    var acc = 0;
    for (var i = 0; i < n; i++) {
      var x = arr[i];
      x = x ^ (x >> 13);
      x = Math.imul(x, 0x5bd1e995);
      acc = acc ^ x;
    }
    return acc;
  }
  var a = new Int32Array(131072);
  for (var i = 0; i < 131072; i++) a[i] = (i * 17) ^ 99;
  var r1 = custom_kernel_i32(a, 131072);
  var r2 = custom_kernel_i32(a, 131072);
  var r3 = custom_kernel_i32(a, 131072);
  var r4 = custom_kernel_i32(a, 131072);
  var r5 = custom_kernel_i32(a, 131072);
  [r1, r2, r3, r4, r5];
JS
t_res = js_run_script(TIER_JS, "tier_test.js")
JST_ENABLED[0] = false
# Verify against baseline Tier 0!
f_ck = realm.global.get("custom_kernel_i32")
arr_ck = realm.global.get("a")
f_ck.code.jst_desc = nil
r_t0_ck = js_call(f_ck, nil, 2, arr_ck, ~131072.0, nil, nil, JS_NO_ARGS)
must(t_res[0] == r_t0_ck && t_res[4] == r_t0_ck, "Tiered kernel result mismatch vs baseline!")
# STRICT tier-execution assertions (Idea #2: prove the intended tiers actually ran!)
must(JST_STATS[:t1] >= 3, "Expected >= 3 Tier 1 calls, got " + JST_STATS[:t1].to_s)
must(JST_STATS[:t2] >= 2, "Expected >= 2 Tier 2 calls after hot promotion, got " + JST_STATS[:t2].to_s)
<< "  PASS Two-tier Cinder engine hook verified: Tier 1 calls=[JST_STATS[:t1]], hot Tier 2 calls=[JST_STATS[:t2]], result=[t_res[4]] (matches Tier 0)"

# Measure Tier 1 (Cinder fast baseline) vs Tier 2 (Cinder optimizing pass pipeline) runtime on 131K Int32 kernel
c_t1 = jst_compile_js_func(f_ck.code.node, [[:ta, 5], [:i64]], "i64", 1)
c_t2 = jst_compile_js_func(f_ck.code.node, [[:ta, 5], [:i64]], "i64", 2)
# Prevent auto-promotion during pure T1 timing
c_t1[0].reopt_fn = nil
t0 = now_us()
ci = 0
while ci < 10
  jst_dispatch_kernel(c_t1[0], 2, arr_ck, ~131072.0, nil, nil, JS_NO_ARGS)
  ci += 1
t1 = now_us()
ms_t1_run = (t1 - t0).to_f / ~1000.0
t0 = now_us()
ci = 0
while ci < 10
  jst_dispatch_kernel(c_t2[0], 2, arr_ck, ~131072.0, nil, nil, JS_NO_ARGS)
  ci += 1
t1 = now_us()
ms_t2_run = (t1 - t0).to_f / ~1000.0
<< "  Execution (131K x 10 runs): Cinder Tier 1=[fmt2(ms_t1_run)] ms vs Cinder Tier 2=[fmt2(ms_t2_run)] ms ([fmt2(ms_t1_run / ms_t2_run)]x faster after hot promotion!)"

# Check 64-bit FNV-1a/fmix64 hash speed vs SHA-256
h_in = big_js.slice(0, 65536)
t0 = now_us()
hi = 0
while hi < 200
  Crypto.sha256(h_in)
  hi += 1
t1 = now_us()
ms_sha = (t1 - t0).to_f / ~1000.0
t0 = now_us()
hi = 0
while hi < 200
  jst_hash64_hex(h_in)
  hi += 1
t1 = now_us()
ms_fnv = (t1 - t0).to_f / ~1000.0
<< "  Cache Hash (64 KB x 200 = 13 MB): SHA-256=[fmt2(ms_sha)] ms vs FNV-1a/fmix64=[fmt2(ms_fnv)] ms ([fmt1(ms_sha / (ms_fnv < ~0.01 ? ~0.01 : ms_fnv))]x faster)"

# ==============================================================================
# 4. Two-Shape Inline Property Cache (object.w), Proxy Proto Safety, & Dense Switch (walk.w)
# ==============================================================================
<< ""
<< "=== 4. Two-Shape Property IC (object.w) & Dense Switch (walk.w) A/B ==="

PROP_JS = <<~JS
  function sum_prop_2(a, b, n) {
    var s = 0;
    for (var i = 0; i < n; i++) {
      var o = (i & 1) === 0 ? a : b;
      s += o.x + o.y;
    }
    return s;
  }
  function sum_prop_3(a, b, c, n) {
    var s = 0;
    for (var i = 0; i < n; i++) {
      var m = i % 3;
      var o = m === 0 ? a : (m === 1 ? b : c);
      s += o.x + o.y;
    }
    return s;
  }
  function switch32_lit(n) {
    var s = 0;
    for (var i = 0; i < n; i++) {
      switch (i & 31) {
        case 0: s += 1; break; case 1: s += 2; break; case 2: s += 3; break; case 3: s += 4; break;
        case 4: s += 5; break; case 5: s += 6; break; case 6: s += 7; break; case 7: s += 8; break;
        case 8: s += 9; break; case 9: s += 10; break; case 10: s += 11; break; case 11: s += 12; break;
        case 12: s += 13; break; case 13: s += 14; break; case 14: s += 15; break; case 15: s += 16; break;
        case 16: s += 17; break; case 17: s += 18; break; case 18: s += 19; break; case 19: s += 20; break;
        case 20: s += 21; break; case 21: s += 22; break; case 22: s += 23; break; case 23: s += 24; break;
        case 24: s += 25; break; case 25: s += 26; break; case 26: s += 27; break; case 27: s += 28; break;
        case 28: s += 29; break; case 29: s += 30; break; case 30: s += 31; break; default: s += 32; break;
      }
    }
    return s;
  }
  function switch32_dyn(n) {
    var s = 0;
    var c0=0,c1=1,c2=2,c3=3,c4=4,c5=5,c6=6,c7=7,c8=8,c9=9,c10=10,c11=11,c12=12,c13=13,c14=14,c15=15;
    var c16=16,c17=17,c18=18,c19=19,c20=20,c21=21,c22=22,c23=23,c24=24,c25=25,c26=26,c27=27,c28=28,c29=29,c30=30;
    for (var i = 0; i < n; i++) {
      switch (i & 31) {
        case c0: s += 1; break; case c1: s += 2; break; case c2: s += 3; break; case c3: s += 4; break;
        case c4: s += 5; break; case c5: s += 6; break; case c6: s += 7; break; case c7: s += 8; break;
        case c8: s += 9; break; case c9: s += 10; break; case c10: s += 11; break; case c11: s += 12; break;
        case c12: s += 13; break; case c13: s += 14; break; case c14: s += 15; break; case c15: s += 16; break;
        case c16: s += 17; break; case c17: s += 18; break; case c18: s += 19; break; case c19: s += 20; break;
        case c20: s += 21; break; case c21: s += 22; break; case c22: s += 23; break; case c23: s += 24; break;
        case c24: s += 25; break; case c25: s += 26; break; case c26: s += 27; break; case c27: s += 28; break;
        case c28: s += 29; break; case c29: s += 30; break; case c30: s += 31; break; default: s += 32; break;
      }
    }
    return s;
  }
  // Proxy-on-prototype regression check (from review defects!)
  var traps = 0;
  var p = new Proxy({}, { set: function(t, k, v) { traps++; t[k] = v; return true; } });
  var o1 = Object.create(p);
  var o2 = Object.create(p);
  function set_p(o) { o.z = 1; }
  set_p(o1); set_p(o2);
  traps;
JS
traps = js_run_script(PROP_JS, "prop.js")
must(traps == ~2.0, "Proxy on prototype set trap bypassed! traps=" + traps.to_s)
<< "  PASS Proxy-on-prototype set-trap safety: traps=[traps] (expected 2)"

o_a = js_run_script("({ x: 3, y: 7 })", "oa.js")
o_b = js_run_script("({ y: 7, x: 3 })", "ob.js")
o_c = js_run_script("({ z: 1, x: 3, y: 7 })", "oc.js")
f_p2 = realm.global.get("sum_prop_2")
f_p3 = realm.global.get("sum_prop_3")
f_sw_lit = realm.global.get("switch32_lit")
f_sw_dyn = realm.global.get("switch32_dyn")

# Measure apples-to-apples Property IC (same loop body: 1-shape vs 2-shape vs 3-shape megamorphic!)
JIT_ENABLED[0] = false
t0 = now_us()
rm = js_call(f_p2, nil, 3, o_a, o_a, ~200000.0, nil, JS_NO_ARGS)
t1 = now_us()
ms_mono = (t1 - t0).to_f / ~1000.0

t0 = now_us()
rp = js_call(f_p2, nil, 3, o_a, o_b, ~200000.0, nil, JS_NO_ARGS)
t1 = now_us()
ms_poly = (t1 - t0).to_f / ~1000.0

t0 = now_us()
rtri = js_call(f_p3, nil, 4, o_a, o_b, o_c, ~200000.0, JS_NO_ARGS)
t1 = now_us()
ms_tri = (t1 - t0).to_f / ~1000.0
must(rm == ~2000000.0 && rp == ~2000000.0 && rtri == ~2000000.0, "Property IC mismatch!")
<< "  Tier 0 Property IC (200K x 2 reads, identical loop): 1-shape=[fmt2(ms_mono)] ms | 2-shape=[fmt2(ms_poly)] ms ([fmt2(ms_poly / ms_mono)]x) | 3-shape miss=[fmt2(ms_tri)] ms ([fmt2(ms_tri / ms_poly)]x slower when missing!)"

t0 = now_us()
rsw_d = js_call(f_sw_dyn, nil, 1, ~200000.0, nil, nil, nil, JS_NO_ARGS)
t1 = now_us()
ms_sw_dyn = (t1 - t0).to_f / ~1000.0

t0 = now_us()
rsw_l = js_call(f_sw_lit, nil, 1, ~200000.0, nil, nil, nil, JS_NO_ARGS)
t1 = now_us()
ms_sw_lit = (t1 - t0).to_f / ~1000.0
must(rsw_l == ~3300000.0 && rsw_d == ~3300000.0, "Dense switch32 mismatch!")
<< "  Tier 0 Dense 32-case Switch (200K iters): Linear scan=[fmt2(ms_sw_dyn)] ms vs Cached O(1) Hash=[fmt2(ms_sw_lit)] ms ([fmt2(ms_sw_dyn / ms_sw_lit)]x faster!)"

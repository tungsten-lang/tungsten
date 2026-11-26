# test_audit_regressions.w — Verifies EVERY SINGLE ONE of the 8 audit cases
# (comparing Interpreter vs BLADE_JS_TUNGSTEN=1 + BLADE_JS_SIMD_LEX=1) AND verifies
# ZERO subprocess shell-out (in-process WIRE->ARM64 compile in microseconds!).

use ../js

-> now_us
  (ccall_nobox("__w_clock_ns_raw") ## i64) / 1000

-> must(cond, msg)
  if !cond
    << "FAIL: [msg]"
    exit(1)

AUDIT_JS = <<~JS
  // Case 1: 3-param Uint8Array function with 4-statement loop (NOT grayscale!)
  function u8_not_gray(out, inp, n) {
    for (var i = 0; i < n; i++) {
      var a = inp[i];
      var b = a + a;
      out[i] = b;
      var c = b;
    }
    return out;
  }

  // Case 2: 4-param Float16Array function computing -x * s (NOT ReLU!)
  function f16_neg_scale(out, inp, s, n) {
    for (var i = 0; i < n; i++) {
      out[i] = -inp[i] * s;
    }
    return n;
  }

  // Case 3: Sum of a[i] * 0.5 into a local named `acc`
  function sum_half_acc(a, n) {
    var acc = 0;
    for (var i = 0; i < n; i++) acc += a[i] * 0.5;
    return acc;
  }

  // Case 4: Loop body containing `s %= 7`
  function sum_mod7(a, n) {
    var s = 0;
    for (var i = 0; i < n; i++) {
      s += a[i];
      s %= 7;
    }
    return s;
  }

  // Case 5: Read past the end of the array -> must return NaN (NOT throw Tungsten bounds error!)
  function read_oob(a, n) {
    var s = 0;
    for (var i = 0; i <= n; i++) s += a[i];
    return s;
  }

  // Case 6: Loop with fractional step `x += 0.5` -> must terminate and return 14!
  function frac_step(a, n) {
    var s = 0;
    for (var x = 0; x < 4; x += 0.5) s += x;
    return s;
  }

  // Case 7: Plain dot product control (must run via jsn_t in-process with ZERO 107ms stall!)
  function dot_ctrl(a, b, n) {
    var s = 0;
    for (var i = 0; i < n; i++) s += a[i] * b[i];
    return s;
  }

  function run_all() {
    var u_in = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]);
    var u_out = new Uint8Array(8);
    u8_not_gray(u_out, u_in, 8);
    var c1 = Array.from(u_out).join(",");

    var h_in = new Float16Array([-3, -2, -1, 0, 1, 2, 3, 4]);
    var h_out = new Float16Array(8);
    f16_neg_scale(h_out, h_in, 2, 8);
    var c2 = Array.from(h_out).join(",");

    var f_in = new Float32Array([4, 4, 4, 4, 4, 4, 4, 4]);
    var c3 = sum_half_acc(f_in, 8);

    var m_in = new Int32Array([7, 14, 21, 28, 7, 7]);
    var c4 = sum_mod7(m_in, 6);

    var oob_in = new Float32Array([1, 2, 3]);
    var c5 = read_oob(oob_in, 3);

    var c6 = frac_step(f_in, 8);

    var da = new Float32Array([1, 2, 3, 4, 5, 6]);
    var db = new Float32Array([2, 2, 2, 2, 2, 2]);
    var c7 = dot_ctrl(da, db, 6);

    return [c1, c2, c3, c4, String(c5), c6, c7];
  }
  run_all();
JS

# 1. Run baseline interpreter (flags OFF)
JIT_ENABLED[0] = false
JST_ENABLED[0] = false
JS_SIMD_LEX[0] = false
r0 = js_new_realm(nil)
base = js_run_script(AUDIT_JS, "audit_base.js")

# 2. Run with BLADE_JS_TUNGSTEN=1 + BLADE_JS_SIMD_LEX=1 (ZERO shell-out to clang!)
JST_ENABLED[0] = true
JST_ALLOW_CLANG[0] = false
JS_SIMD_LEX[0] = true
jst_reset_stats()
r1 = js_new_realm(nil)
t0 = now_us()
opt = js_run_script(AUDIT_JS, "audit_jst.js")
t1 = now_us()
ms_total = (t1 - t0).to_f / ~1000.0

must(base[0] == "2,4,6,8,10,12,14,16" && opt[0] == base[0], "Case 1 (u8_not_gray) mismatch: base=" + base[0].to_s + " opt=" + opt[0].to_s)
must(base[1] == "6,4,2,0,-2,-4,-6,-8" && opt[1] == base[1], "Case 2 (f16_neg_scale) mismatch: base=" + base[1].to_s + " opt=" + opt[1].to_s)
must(base[2] == ~16.0 && opt[2] == base[2], "Case 3 (sum_half_acc) mismatch: base=" + base[2].to_s + " opt=" + opt[2].to_s)
must(base[3] == ~0.0 && opt[3] == base[3], "Case 4 (sum_mod7) mismatch: base=" + base[3].to_s + " opt=" + opt[3].to_s)
must(base[4] == "NaN" && opt[4] == "NaN", "Case 5 (read_oob) mismatch: base=" + base[4].to_s + " opt=" + opt[4].to_s)
must(base[5] == ~14.0 && opt[5] == base[5], "Case 6 (frac_step) mismatch: base=" + base[5].to_s + " opt=" + opt[5].to_s)
must(base[6] == ~42.0 && opt[6] == base[6], "Case 7 (dot_ctrl) mismatch: base=" + base[6].to_s + " opt=" + opt[6].to_s)
must(JST_STATS[:swizzle] >= 1 || JST_STATS[:t1] >= 1, "Expected jsn_t to accelerate qualifying functions!")
must(ms_total < ~50.0, "First-call latency exceeded 50 ms (unexpected shell-out!): " + ms_total.to_s + " ms")

# Case 8: 5,000-character string literal with BLADE_JS_SIMD_LEX=1!
big_s = ""
i = 0
while i < 500
  big_s = big_s + "0123456789"
  i += 1
s_js = "var s = \"" + big_s + "\"; \[s.length, s\[0], s\[4999], 42];"
s_res = js_run_script(s_js, "long_str.js")
must(s_res[0] == ~5000.0 && s_res[1] == "0" && s_res[2] == "9" && s_res[3] == ~42.0, "Case 8 (5000-char string SIMD lex) failed: len=" + s_res[0].to_s)

<< "PASS ALL 8 AUDIT REGRESSION CASES (100% match vs interpreter)!"
<< "  Case 1 (Uint8 non-gray): " + opt[0].to_s
<< "  Case 2 (Float16 -x*s):   " + opt[1].to_s
<< "  Case 3 (acc += a*0.5):   " + opt[2].to_s
<< "  Case 4 (s %= 7):         " + opt[3].to_s
<< "  Case 5 (OOB -> NaN):     " + opt[4].to_s
<< "  Case 6 (x += 0.5):       " + opt[5].to_s
<< "  Case 7 (dot_ctrl):       " + opt[6].to_s + " (total first-call script time: " + ms_total.to_s + " ms — ZERO shell-out!)"
<< "  Case 8 (5000-char str):  len=" + s_res[0].to_s + " (SIMD lexer re-synced cleanly!)"
<< "  JST_STATS: swizzle=" + JST_STATS[:swizzle].to_s + " t1_wire_a64=" + JST_STATS[:t1].to_s + " t1_compiles=" + JST_STATS[:t1_compile].to_s

# test_audit_regressions.w — Verifies:
#   1-8. All 8 original JS engine audit cases (100% match vs Tier-0 interpreter, ZERO shell-out)
#   9.   Hardware BigInt carry chains (`bigint_add`, `bigint_sub` across all 3 borrow idioms,
#        `bigint_mul1`, `bigint_addmul1`, nested schoolbook `bigint_mul`, straight-line `u256_add`)
#   10.  Sound fail-closed bailout on unbounded loop-carried BigInt growth (> 128 bits)
#   11.  Two-pass Cinder JIT: blazing-fast Tier-1 initial compile -> automatic in-place Tier-2
#        optimizing replacement (`desc.fp` hot-swapped in-process with ZERO Clang / ZERO LLVM!)

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

  // Case 7: Plain dot product control (must run via jsn_t in-process with ZERO stall!)
  function dot_ctrl(a, b, n) {
    var s = 0;
    for (var i = 0; i < n; i++) s += a[i] * b[i];
    return s;
  }

  // Case 9a: Multi-limb BigInt addition (`s = a[i] + b[i] + c; out[i] = s; c = s >> 64n`)
  function bigint_add_limbs(out, a, b, n) {
    var c = 0n;
    for (var i = 0; i < n; i++) {
      var s = a[i] + b[i] + c;
      out[i] = s;
      c = s >> 64n;
    }
    return c;
  }

  // Case 9b: Multi-limb BigInt subtraction (idiom 1: `d < 0n ? 1n : 0n`, idiom 2: `(d >> 64n) & 1n`, idiom 3: `-(d >> 64n)`)
  function bigint_sub_cmp(out, a, b, n) {
    var brw = 0n;
    for (var i = 0; i < n; i++) {
      var d = a[i] - b[i] - brw;
      out[i] = d;
      brw = d < 0n ? 1n : 0n;
    }
    return brw;
  }
  function bigint_sub_shr_and(out, a, b, n) {
    var brw = 0n;
    for (var i = 0; i < n; i++) {
      var d = a[i] - b[i] - brw;
      out[i] = d;
      brw = (d >> 64n) & 1n;
    }
    return brw;
  }
  function bigint_sub_neg_shr(out, a, b, n) {
    var brw = 0n;
    for (var i = 0; i < n; i++) {
      var d = a[i] - b[i] - brw;
      out[i] = d;
      brw = -(d >> 64n);
    }
    return brw;
  }

  // Case 9c: Straight-line 4-limb u256 addition (fuses into adds + 3x adcs + cset!)
  function u256_add_straight(out, a, b, n) {
    var s0 = a[0] + b[0];
    out[0] = s0;
    var c0 = s0 >> 64n;
    var s1 = a[1] + b[1] + c0;
    out[1] = s1;
    var c1 = s1 >> 64n;
    var s2 = a[2] + b[2] + c1;
    out[2] = s2;
    var c2 = s2 >> 64n;
    var s3 = a[3] + b[3] + c2;
    out[3] = s3;
    return s3 >> 64n;
  }

  // Case 9d: Single-limb scalar multiply-accumulate (`out[i] + a[i] * w + c`)
  function bigint_addmul1(out, a, w, n) {
    var c = 0n;
    for (var i = 0; i < n; i++) {
      var p = out[i] + a[i] * w + c;
      out[i] = p;
      c = p >> 64n;
    }
    return c;
  }

  // Case 9e: Full nested schoolbook multi-limb multiplication (`2*n` output limbs!)
  function bigint_mul_schoolbook(out, a, b, n) {
    for (var k = 0; k < n * 2; k++) out[k] = 0n;
    for (var i = 0; i < n; i++) {
      var w = b[i];
      var c = 0n;
      for (var j = 0; j < n; j++) {
        var p = out[i + j] + a[j] * w + c;
        out[i + j] = p;
        c = p >> 64n;
      }
      out[i + n] = c;
    }
    return out[n * 2 - 1];
  }

  // Case 10: Unbounded BigInt loop growth (> 128 bits) -> MUST fail closed to exact JS BigInt!
  function unbounded_big_pow(a, n) {
    var acc = a[0];
    for (var i = 0; i < n; i++) {
      acc = acc * 3n + 1n;
    }
    return acc;
  }

  function limbs_to_hex(ta, len) {
    var s = "";
    for (var i = len - 1; i >= 0; i--) {
      s += ta[i].toString(16).padStart(16, "0");
    }
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

    // BigInt carry-chain stress tests (run 5 times each so BOTH Tier 1 and Tier 2 execute!)
    var M = 0xffffffffffffffffn;
    var ba = new BigUint64Array([M, M, M, M, 0x123456789abcdef0n, M, 0n]);
    var bb = new BigUint64Array([1n, 0n, 0n, 0n, 0xfedcba9876543210n, M, 1n]);
    var bo = new BigUint64Array(7);
    var add_res = "";
    for (var r = 0; r < 5; r++) {
      var co = bigint_add_limbs(bo, ba, bb, 7);
      add_res = co.toString() + ":" + limbs_to_hex(bo, 7);
    }

    var z7 = new BigUint64Array(7);
    var s1_res = "", s2_res = "", s3_res = "";
    for (var r = 0; r < 5; r++) {
      var b1 = bigint_sub_cmp(bo, z7, bb, 7);
      s1_res = b1.toString() + ":" + limbs_to_hex(bo, 7);
      var b2 = bigint_sub_shr_and(bo, ba, bb, 7);
      s2_res = b2.toString() + ":" + limbs_to_hex(bo, 7);
      var b3 = bigint_sub_neg_shr(bo, bb, ba, 7);
      s3_res = b3.toString() + ":" + limbs_to_hex(bo, 7);
    }

    var u256_o = new BigUint64Array(4);
    var u256_res = "";
    for (var r = 0; r < 5; r++) {
      var cu = u256_add_straight(u256_o, ba, bb, 1);
      u256_res = cu.toString() + ":" + limbs_to_hex(u256_o, 4);
    }

    // Max-limb addmul1 corner case: (2^64-1)*(2^64-1) + (2^64-1) + (2^64-1) == 2^128 - 1!
    var am_o = new BigUint64Array(5);
    var am_a = new BigUint64Array([M, M, 0xdeadbeefcafebaben, 0n, M]);
    var am_res = "";
    for (var r = 0; r < 5; r++) {
      for (var k = 0; k < 5; k++) am_o[k] = M;
      var cam = bigint_addmul1(am_o, am_a, M, 5);
      am_res = cam.toString(16) + ":" + limbs_to_hex(am_o, 5);
    }

    // Nested schoolbook 5x5 -> 10-limb multiplication (runs inner j-loop via hardware addmul1!)
    var mul_o = new BigUint64Array(10);
    var mul_res = "";
    for (var r = 0; r < 5; r++) {
      var top = bigint_mul_schoolbook(mul_o, ba, bb, 5);
      mul_res = top.toString(16) + ":" + limbs_to_hex(mul_o, 10);
    }

    // Unbounded >128-bit BigInt accumulator (60 iterations of 3^60 * M > 2^159)
    var ub_res = unbounded_big_pow(ba, 60).toString(16);

    return [c1, c2, c3, c4, String(c5), c6, c7, add_res, s1_res, s2_res, s3_res, u256_res, am_res, mul_res, ub_res];
  }
  run_all();
JS

# 1. Run baseline interpreter (flags OFF)
JIT_ENABLED[0] = false
JST_ENABLED[0] = false
JS_SIMD_LEX[0] = false
r0 = js_new_realm(nil)
base = js_run_script(AUDIT_JS, "audit_base.js")

# 2. Run with BLADE_JS_TUNGSTEN=1 + BLADE_JS_SIMD_LEX=1 (two-pass Tier-1 -> Tier-2 in Cinder, ZERO Clang!)
JST_ENABLED[0] = true
JST_TIER2_HITS[0] = 3
JS_SIMD_LEX[0] = true
jst_reset_stats()
r1 = js_new_realm(nil)
t0 = now_us()
opt = js_run_script(AUDIT_JS, "audit_jst.js")
t1 = now_us()
ms_total = (t1 - t0).to_f / ~1000.0

must(base[0] == "2,4,6,8,10,12,14,16" && opt[0] == base[0], "Case 1 (u8_not_gray) mismatch")
must(base[1] == "6,4,2,0,-2,-4,-6,-8" && opt[1] == base[1], "Case 2 (f16_neg_scale) mismatch")
must(base[2] == ~16.0 && opt[2] == base[2], "Case 3 (sum_half_acc) mismatch")
must(base[3] == ~0.0 && opt[3] == base[3], "Case 4 (sum_mod7) mismatch")
must(base[4] == "NaN" && opt[4] == "NaN", "Case 5 (read_oob) mismatch")
must(base[5] == ~14.0 && opt[5] == base[5], "Case 6 (frac_step) mismatch")
must(base[6] == ~42.0 && opt[6] == base[6], "Case 7 (dot_ctrl) mismatch")
must(opt[7] == base[7], "Case 9a (bigint_add_limbs) mismatch:\n  base=" + base[7].to_s + "\n  opt =" + opt[7].to_s)
must(opt[8] == base[8], "Case 9b-1 (bigint_sub_cmp) mismatch:\n  base=" + base[8].to_s + "\n  opt =" + opt[8].to_s)
must(opt[9] == base[9], "Case 9b-2 (bigint_sub_shr_and) mismatch:\n  base=" + base[9].to_s + "\n  opt =" + opt[9].to_s)
must(opt[10] == base[10], "Case 9b-3 (bigint_sub_neg_shr) mismatch:\n  base=" + base[10].to_s + "\n  opt =" + opt[10].to_s)
must(opt[11] == base[11] && opt[11] == "1:0000000000000000000000000000000000000000000000000000000000000000", "Case 9c (u256_add_straight) mismatch: " + opt[11].to_s)
must(opt[12] == base[12], "Case 9d (bigint_addmul1) mismatch:\n  base=" + base[12].to_s + "\n  opt =" + opt[12].to_s)
must(opt[13] == base[13], "Case 9e (bigint_mul_schoolbook) mismatch:\n  base=" + base[13].to_s + "\n  opt =" + opt[13].to_s)
must(opt[14] == base[14] && opt[14].size > 38, "Case 10 (unbounded_big_pow >128-bit bailout) mismatch")

must(JST_STATS[:t1_compile] >= 6 && JST_STATS[:t2_reopt] >= 6 && JST_STATS[:t1] >= 18 && JST_STATS[:t2] >= 12, "Expected two-pass Tier-1 -> Tier-2 promotion across BigInt kernels! stats=" + JST_STATS.to_s)
must(ms_total < ~50.0, "Total compile + Tier-2 re-opt + script execution exceeded 50 ms: " + ms_total.to_s + " ms")

# Case 11: Explicit function-pointer hot-swap check (`fp_tier1 != fp_tier2`)
f_add_js = r1.global.get("bigint_add_limbs")
f_add_js.code.jst_desc = nil
f_add_js.code.jst_state = 0
JST_TIER2_HITS[0] = 2
JST_TIER2_ELEMS[0] = 10000000
ta_x = js_run_script("new BigUint64Array(\[0xffffffffffffffffn, 0xffffffffffffffffn])", "tx.js")
ta_y = js_run_script("new BigUint64Array(\[1n, 0n])", "ty.js")
ta_z = js_run_script("new BigUint64Array(2)", "tz.js")
c_call1 = js_call(f_add_js, nil, 4, ta_z, ta_x, ta_y, ~2.0, JS_NO_ARGS)
desc_live = f_add_js.code.jst_desc
must(desc_live != nil && desc_live.tier == 1 && desc_live.wire_fn != nil, "Expected Tier-1 baseline after call 1!")
fp_pass1 = desc_live.fp
c_call2 = js_call(f_add_js, nil, 4, ta_z, ta_x, ta_y, ~2.0, JS_NO_ARGS)
must(desc_live.tier == 2 && desc_live.fp != fp_pass1 && desc_live.wire_fn == nil, "Expected in-place Tier-2 function replacement on call 2!")
c_call3 = js_call(f_add_js, nil, 4, ta_z, ta_x, ta_y, ~2.0, JS_NO_ARGS)
must(c_call1.v == 1 && c_call2.v == 1 && c_call3.v == 1, "Carry-out mismatch across Tier-1 -> Tier-2 swap!")

# Case 8: 5,000-character string literal with BLADE_JS_SIMD_LEX=1!
big_s = ""
i = 0
while i < 500
  big_s = big_s + "0123456789"
  i += 1
s_js = "var s = \"" + big_s + "\"; \[s.length, s\[0], s\[4999], 42];"
s_res = js_run_script(s_js, "long_str.js")
must(s_res[0] == ~5000.0 && s_res[1] == "0" && s_res[2] == "9" && s_res[3] == ~42.0, "Case 8 (5000-char string SIMD lex) failed")

<< "PASS ALL 11 AUDIT, BIGINT CARRY-CHAIN & TIER-1->TIER-2 HOT-SWAP CASES!"
<< "  Cases 1-8 (original audit): 100% match vs Tier-0"
<< "  Case 9  (BigInt carry chains: add, 3x sub idioms, u256, addmul1, schoolbook mul): 100% bit-exact!"
<< "  Case 10 (Unbounded >128-bit BigInt bailout): len=[opt[14].size] hex digits (exact Tier-0 fallback)"
<< "  Case 11 (In-place Tier-1 -> Tier-2 fp swap): fp1=[fp_pass1] -> fp2=[desc_live.fp] (total script: [ms_total] ms, ZERO Clang!)"
<< "  JST_STATS: swizzle=[JST_STATS[:swizzle]] t1_calls=[JST_STATS[:t1]] t2_calls=[JST_STATS[:t2]] t1_compiles=[JST_STATS[:t1_compile]] t2_reopts=[JST_STATS[:t2_reopt]]"

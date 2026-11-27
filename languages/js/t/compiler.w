# blade/jsn_t/compiler — Sound JS -> WIRE IR -> Cinder Native Compiler & Swizzler.
#
# Key design principles (100% sound, fail-closed, ZERO Clang / ZERO LLVM):
#   1. Static Purity, Sound Fixed-Point Type Inference & Static Bounds Proof:
#      - NEVER guesses variable types from variable names! Infers :f64 / :i64 / :u64 /
#        wide 128-bit BigInt carry ranges (:u128_*, :i128_sub*) from ALL declarations &
#        assignments, rejecting unbounded BigInt loop accumulators so they fall back cleanly
#        to arbitrary-precision Tier-0 JS BigInt.
#      - Rejects ALL unhandled syntax (`do_while`, expression-position `++`/`--`, unsupported
#        compound ops like `%=`, non-monotonic/unproved array indices) — failing closed to
#        JS Tier 0 / JIT with 100% ECMAScript semantics (including OOB -> `undefined`/`NaN`).
#   2. 100% Structurally Exact AST Pattern Swizzler:
#      - Verifies every loop bound, operator, operand, and constant before swizzling into
#        pre-compiled Tungsten / Metal GPU library kernels (ZERO false positives!).
#   3. Two-Pass In-Process Cinder Native Compilation (`bits/tungsten-cinder`):
#      - Tier 1 (`wire_compile_func_tier(wf, 1)`): blazing-fast single-pass baseline compile
#        (~4-6 us, zero IR passes, zero `.ll`, zero subprocesses!) installed on first call.
#      - Tier 2 (`wire_compile_func_tier(wf, 2)`): once hot (`hits >= JST_TIER2_HITS` or
#        `elems >= JST_TIER2_ELEMS`), runs Cinder's modular optimizing pass pipeline (constant
#        fold/hoist, slot SROA & store->load forwarding, LICM/CSE, carry canonicalization,
#        straight-line carry-chain fusion, DCE, hardware 4x-unrolled `adcs`/`sbcs` & `umulh`
#        carry loops, and NEON/SSE2 SIMD) and hot-swaps `desc.fp` in-place!

use ./bridge
use ../wire_a64/js_to_wire

JST_ENABLED = [Env.get("BLADE_JS_TUNGSTEN", "1") != "0"]
JST_ALLOW_CLANG = [false]   # Legacy flag kept as no-op for caller compatibility; Cinder skips Clang/LLVM 100%.
JST_CACHE_DIR = Env.get("HOME", "/tmp") + "/Library/Caches/Blade/js-t-kernels"
JST_COMPILED_CACHE = {}
JST_SWIZZLED_COUNT = [0]
JST_COMPILED_COUNT = [0]
JST_METAL_COUNT    = [0]

# Ultra-fast 4-lane parallel 64-bit hash directly over String bytes (32 bytes/iter,
# unaligned 64-bit loads + SplitMix/XXH3-style 4-accumulator multiply-xorshift mix).
fn jst_hash64_raw(ptr, len) (i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %ptr to ptr
    %p1 = add i64 0, -7046029288634856825
    %p2 = add i64 0, -4417276706812531889
    %p3 = add i64 0, 1609587929392839161
    %p4 = add i64 0, -8796714831421723037
    %seed = xor i64 %len, %p1
    %has32 = icmp sge i64 %len, 32
    br i1 %has32, label %loop32_pre, label %tail8_pre
  loop32_pre:
    %end32 = sub i64 %len, 32
    br label %loop32
  loop32:
    %i = phi i64 [ 0, %loop32_pre ], [ %inext, %loop32 ]
    %a0 = phi i64 [ %seed, %loop32_pre ], [ %na0, %loop32 ]
    %a1 = phi i64 [ %p2, %loop32_pre ], [ %na1, %loop32 ]
    %a2 = phi i64 [ %p3, %loop32_pre ], [ %na2, %loop32 ]
    %a3 = phi i64 [ %p4, %loop32_pre ], [ %na3, %loop32 ]
    %q0 = getelementptr i8, ptr %base, i64 %i
    %i8 = add i64 %i, 8
    %q1 = getelementptr i8, ptr %base, i64 %i8
    %i16 = add i64 %i, 16
    %q2 = getelementptr i8, ptr %base, i64 %i16
    %i24 = add i64 %i, 24
    %q3 = getelementptr i8, ptr %base, i64 %i24
    %v0 = load i64, ptr %q0, align 1
    %v1 = load i64, ptr %q1, align 1
    %v2 = load i64, ptr %q2, align 1
    %v3 = load i64, ptr %q3, align 1
    %x0 = xor i64 %a0, %v0
    %na0 = mul i64 %x0, %p1
    %x1 = xor i64 %a1, %v1
    %na1 = mul i64 %x1, %p2
    %x2 = xor i64 %a2, %v2
    %na2 = mul i64 %x2, %p3
    %x3 = xor i64 %a3, %v3
    %na3 = mul i64 %x3, %p4
    %inext = add i64 %i, 32
    %cont32 = icmp sle i64 %inext, %end32
    br i1 %cont32, label %loop32, label %merge32
  merge32:
    %m01 = xor i64 %na0, %na1
    %m23 = xor i64 %na2, %na3
    %m0123 = xor i64 %m01, %m23
    br label %tail8_pre
  tail8_pre:
    %ti0 = phi i64 [ 0, %0 ], [ %inext, %merge32 ]
    %th0 = phi i64 [ %seed, %0 ], [ %m0123, %merge32 ]
    br label %tail8
  tail8:
    %ti = phi i64 [ %ti0, %tail8_pre ], [ %tinext, %tail8_body ]
    %th = phi i64 [ %th0, %tail8_pre ], [ %thnext, %tail8_body ]
    %rem8 = sub i64 %len, %ti
    %has8 = icmp sge i64 %rem8, 8
    br i1 %has8, label %tail8_body, label %tail1_pre
  tail8_body:
    %qp = getelementptr i8, ptr %base, i64 %ti
    %vw = load i64, ptr %qp, align 1
    %tx = xor i64 %th, %vw
    %thnext = mul i64 %tx, %p1
    %tinext = add i64 %ti, 8
    br label %tail8
  tail1_pre:
    br label %tail1
  tail1:
    %bi = phi i64 [ %ti, %tail1_pre ], [ %binext, %tail1_body ]
    %bh = phi i64 [ %th, %tail1_pre ], [ %bhnext, %tail1_body ]
    %has1 = icmp slt i64 %bi, %len
    br i1 %has1, label %tail1_body, label %fmix
  tail1_body:
    %bp = getelementptr i8, ptr %base, i64 %bi
    %bv8 = load i8, ptr %bp, align 1
    %bv = zext i8 %bv8 to i64
    %bx = xor i64 %bh, %bv
    %bhnext = mul i64 %bx, %p2
    %binext = add i64 %bi, 1
    br label %tail1
  fmix:
    %s1 = lshr i64 %bh, 33
    %f1 = xor i64 %bh, %s1
    %f2 = mul i64 %f1, -49064778989728563
    %s2 = lshr i64 %f2, 33
    %f3 = xor i64 %f2, %s2
    %f4 = mul i64 %f3, -4265267296055464877
    %s3 = lshr i64 %f4, 33
    %f5 = xor i64 %f4, %s3
    ret i64 %f5
  IR

HEX_DIGITS = "0123456789abcdef"

-> jst_hash64_hex(s)
  n = s.size
  h = 0 ## i64
  if n >= 6
    ptr = ccall_nobox("w_string_data_ptr", s) ## i64
    h = jst_hash64_raw(ptr, n ## i64)
  else
    u = 14695981039346656037 ## int
    i = 0
    while i < n
      u = ((u ^ (s.byte_at(i) ## int)) * (1099511628211 ## int)) & (((1 ## int) << 64) - 1)
      i += 1
    h = u >= ((1 ## int) << 63) ? ((u - ((1 ## int) << 64)) ## i64) : (u ## i64)
  out = ""
  sh = 60
  while sh >= 0
    nib = (h >> sh) & 15
    out = out + HEX_DIGITS.slice(nib, 1)
    sh -= 4
  out

# ---- 1. Strict Fail-Closed Purity, Type Inference & Static Bounds Verification ----

JST_ALLOWED_BINOPS = {
  "+" => true, "-" => true, "*" => true, "/" => true,
  "|" => true, "&" => true, "^" => true, "<<" => true, ">>" => true, ">>>" => true,
  "==" => true, "===" => true, "!=" => true, "!==" => true,
  "<" => true, "<=" => true, ">" => true, ">=" => true
}
JST_ALLOWED_ASSIGN = {
  "=" => true, "+=" => true, "-=" => true, "*=" => true, "/=" => true,
  "^=" => true, "|=" => true, "&=" => true
}

-> jst_is_pure_math_call?(node)
  return false if node.kind != :call
  cal = node.a
  return false if cal.kind != :member || cal.has?(F_COMPUTED)
  return false if cal.a.kind != :ident || cal.a.str != "Math"
  m = cal.b.str
  n = node.list.size
  return n == 1 if m == "sqrt" || m == "abs" || m == "floor" || m == "ceil" || m == "fround" || m == "f16round" || m == "sin" || m == "cos"
  return n == 2 if m == "min" || m == "max" || m == "imul"
  false

-> jst_check_expr(node, info, allow_update = false)
  return false if node == nil
  k = node.kind
  if k == :ident || k == :num || k == :true || k == :false
    return true
  elsif k == :bigint
    u = js_bigint_literal(node.str).v
    return false if u < 0 || u >= ((1 ## int) << 64)
    info[:has_bigint] = true
    return true
  elsif k == :unary
    op = node.str
    return false if op != "-" && op != "+" && op != "~" && op != "!"
    return jst_check_expr(node.a, info, false)
  elsif k == :update
    return false if !allow_update
    return node.a.kind == :ident && (node.str == "++" || node.str == "--")
  elsif k == :binary
    op = node.str
    return false if !JST_ALLOWED_BINOPS[op]
    info[:has_bitops] = true if op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>" || op == ">>>"
    return jst_check_expr(node.a, info, false) && jst_check_expr(node.b, info, false)
  elsif k == :cond
    return jst_check_expr(node.a, info, false) && jst_check_expr(node.b, info, false) && jst_check_expr(node.c, info, false)
  elsif k == :member
    if node.has?(F_COMPUTED)
      info[:reads_arr] = true
      return node.a.kind == :ident && jst_check_expr(node.b, info, false)
    return node.a.kind == :ident && node.b.kind == :ident && node.b.str == "length"
  elsif k == :call
    if jst_is_pure_math_call?(node)
      info[:has_math] = true
      i = 0
      while i < node.list.size
        return false if !jst_check_expr(node.list[i], info, false)
        i += 1
      return true
    cal = node.a
    if cal.kind == :member && !cal.has?(F_COMPUTED) && cal.a.kind == :ident && cal.a.str == "BigInt" && (cal.b.str == "asUintN" || cal.b.str == "asIntN") && node.list.size == 2
      return false if node.list[0].kind != :num || node.list[0].a != ~64.0
      info[:has_bigint] = true
      return jst_check_expr(node.list[1], info, false)
    return false
  false

-> jst_check_stmt(node, info)
  return true if node == nil
  k = node.kind
  if k == :block
    i = 0
    while i < node.list.size
      return false if !jst_check_stmt(node.list[i], info)
      i += 1
    return true
  elsif k == :var_decl
    i = 0
    while i < node.list.size
      d = node.list[i]
      return false if d.a.kind != :ident
      return false if d.b != nil && !jst_check_expr(d.b, info, false)
      i += 1
    return true
  elsif k == :expr_stmt
    e = node.a
    return false if e == nil
    if e.kind == :assign
      return false if !JST_ALLOWED_ASSIGN[e.str]
      if e.a.kind == :member && e.a.has?(F_COMPUTED)
        return false if e.str != "=" || e.a.a.kind != :ident
        info[:writes_arr] = true
        return jst_check_expr(e.a.b, info, false) && jst_check_expr(e.b, info, false)
      elsif e.a.kind == :ident
        return jst_check_expr(e.b, info, false)
      return false
    elsif e.kind == :update
      return e.a.kind == :ident && (e.str == "++" || e.str == "--")
    return false
  elsif k == :return
    return node.a == nil ? true : jst_check_expr(node.a, info, false)
  elsif k == :empty || k == :break || k == :continue
    return true
  elsif k == :if
    return jst_check_expr(node.a, info, false) && jst_check_stmt(node.b, info) && jst_check_stmt(node.c, info)
  elsif k == :for
    info[:loops] += 1
    if node.a != nil
      if node.a.kind == :var_decl
        return false if !jst_check_stmt(node.a, info)
      else
        return false if !jst_check_stmt(JsNode.new(:expr_stmt, 0, 0, nil, node.a, nil, nil, nil, 0), info)
    return false if node.b != nil && !jst_check_expr(node.b, info, false)
    if node.c != nil
      return false if !jst_check_stmt(JsNode.new(:expr_stmt, 0, 0, nil, node.c, nil, nil, nil, 0), info)
    return jst_check_stmt(node.d, info)
  elsif k == :while
    info[:loops] += 1
    return jst_check_expr(node.a, info, false) && jst_check_stmt(node.b, info)
  # Explicitly reject do_while, try, throw, switch, closures, etc.!
  false

-> jst_analyze_func(jf)
  fn_node = jf.node
  return [false, nil] if fn_node == nil
  return [false, nil] if fn_node.has?(F_ASYNC) || fn_node.has?(F_GENERATOR) || fn_node.has?(F_HAS_EVAL) || fn_node.has?(F_USES_ARGS)
  params = []
  i = 0
  while i < fn_node.list.size
    p = fn_node.list[i]
    return [false, nil] if p.kind != :ident
    params.push(p.str)
    i += 1
  info = {:loops => 0, :reads_arr => false, :writes_arr => false, :has_bitops => false, :has_bigint => false, :has_math => false, :params => params}
  body = fn_node.b
  if body.is_a?(Array)
    i = 0
    while i < body.size
      return [false, nil] if !jst_check_stmt(body[i], info)
      i += 1
  else
    return [false, nil] if !jst_check_stmt(body, info)
  [true, info]

# ---- Sound Fixed-Point Type Inference & Static Bounds Proof ----
# Finite BigInt range lattice for exact hardware 128-bit limb arithmetic:
#   `:u1_big`      in [0, 1]
#   `:u64`         in [0, 2^64 - 1]
#   `:u128_add2`   in [0, 2*2^64 - 2]            (`a + b`)
#   `:u128_add2_c` in [0, 2*2^64 - 1]            (`a + b + c_u1`, carry out in {0, 1}!)
#   `:u128_add3`   in [0, 3*2^64 - 3]            (`a + b + c_u64`)
#   `:u128_mul`    in [0, (2^64 - 1)^2]          (`a * w`)
#   `:u128_mul1`   in [0, 2^128 - 2^64]          (`a * w + c`)
#   `:u128_mul2`   in [0, 2^128 - 1]             (`out[i] + a * w + c` — exact max of u128!)
#   `:i128_sub1`   in [-(2^64 - 1), 2^64 - 1]    (`a - b`, borrow in {0, 1})
#   `:i128_sub2`   in [-2^64, 2^64 - 1]          (`a - b - b_u1`, borrow in {0, 1})
#   `:i64_big`     signed 64-bit (`BigInt64Array` / `BigInt.asIntN(64, ...)`)
# Any unbounded loop accumulation (`acc = acc + a[i]`, `acc = acc * 3n + 1n`) climbs out of
# the lattice into `:bad` within <= 3 iterations and soundly falls back to Tier-0 JS BigInt!

-> jst_is_int_lit?(n)
  n != nil && n.kind == :num && n.a == n.a.to_i.to_f && n.a >= ~-2147483648.0 && n.a <= ~2147483647.0

-> jst_u64_like?(t)
  t == :u1_big || t == :u64

-> jst_u128_rank(t)
  return 1 if t == :u128_add2
  return 2 if t == :u128_add2_c
  return 3 if t == :u128_add3
  return 4 if t == :u128_mul
  return 5 if t == :u128_mul1
  return 6 if t == :u128_mul2
  0

-> jst_i128_sub?(t)
  t == :i128_sub1 || t == :i128_sub2

-> jst_any_big?(t)
  t == :u1_big || t == :u64 || t == :i64_big || jst_u128_rank(t) > 0 || jst_i128_sub?(t)

-> jst_join_type(t1, t2)
  return t2 if t1 == nil
  return t1 if t2 == nil
  return t1 if t1 == t2
  return :bad if t1 == :bad || t2 == :bad
  if jst_any_big?(t1) || jst_any_big?(t2)
    return :bad if !jst_any_big?(t1) || !jst_any_big?(t2)
    return :u64 if jst_u64_like?(t1) && jst_u64_like?(t2)
    return :i64_big if (t1 == :i64_big && t2 == :u1_big) || (t1 == :u1_big && t2 == :i64_big)
    r1 = jst_u128_rank(t1)
    r2 = jst_u128_rank(t2)
    if (r1 > 0 || jst_u64_like?(t1)) && (r2 > 0 || jst_u64_like?(t2))
      mx = r1 > r2 ? r1 : r2
      return :u128_add2   if mx == 1
      return :u128_add2_c if mx == 2
      return :u128_add3   if mx == 3
      return :u128_mul    if mx == 4
      return :u128_mul1   if mx == 5
      return :u128_mul2   if mx == 6
    if jst_i128_sub?(t1) && jst_i128_sub?(t2)
      return :i128_sub2
    return :bad
  :f64   # :i64 joined with :f64 widens soundly to :f64!

-> jst_big_add_ty(lt, rt)
  if jst_u64_like?(lt) && jst_u64_like?(rt)
    return :u128_add2
  if (lt == :u128_add2 && rt == :u1_big) || (lt == :u1_big && rt == :u128_add2)
    return :u128_add2_c
  if (lt == :u128_add2 && rt == :u64) || (lt == :u64 && rt == :u128_add2) || (lt == :u128_add2_c && rt == :u1_big) || (lt == :u1_big && rt == :u128_add2_c)
    return :u128_add3
  if (lt == :u128_mul && jst_u64_like?(rt)) || (jst_u64_like?(lt) && rt == :u128_mul)
    return :u128_mul1
  if (lt == :u128_mul1 && jst_u64_like?(rt)) || (jst_u64_like?(lt) && rt == :u128_mul1) || (lt == :u128_add2 && rt == :u128_mul) || (lt == :u128_mul && rt == :u128_add2) || (lt == :u128_add2_c && rt == :u128_mul) || (lt == :u128_mul && rt == :u128_add2_c)
    return :u128_mul2
  :bad

-> jst_infer_expr_ty(n, vtypes, ta_kinds)
  return :f64 if n == nil
  k = n.kind
  if k == :ident
    t = vtypes[n.str]
    return t != nil ? t : :bad
  elsif k == :bigint
    u = js_bigint_literal(n.str).v
    return :bad if u < 0 || u >= ((1 ## int) << 64)
    return (u == 0 || u == 1) ? :u1_big : :u64
  elsif k == :num
    return jst_is_int_lit?(n) ? :i64 : :f64
  elsif k == :true || k == :false
    return :i64
  elsif k == :member
    if n.has?(F_COMPUTED)
      tk = ta_kinds[n.a.str]
      return :bad if tk == nil
      return :u64 if tk == 10
      return :i64_big if tk == 9
      return :i64 if tk == 0 || tk == 1 || tk == 2 || tk == 3 || tk == 4 || tk == 5 || tk == 6
      return :f64
    return :i64
  elsif k == :unary
    op = n.str
    return :i64 if op == "~" || op == "!"
    if op == "-"
      # `-(d >> 64n)` on `:i128_sub*` extracts exact borrow in {0, 1}!
      if n.a != nil && n.a.kind == :binary && n.a.str == ">>" && jst_i128_sub?(jst_infer_expr_ty(n.a.a, vtypes, ta_kinds)) && n.a.b.kind == :bigint && n.a.b.str == "64"
        return :u1_big
      at = jst_infer_expr_ty(n.a, vtypes, ta_kinds)
      return :bad if jst_any_big?(at)
      return at
    at = jst_infer_expr_ty(n.a, vtypes, ta_kinds)
    return :bad if jst_any_big?(at)
    return at
  elsif k == :binary
    op = n.str
    # `0n - (d >> 64n)` on `:i128_sub*` extracts exact borrow in {0, 1}!
    if op == "-" && n.a.kind == :bigint && n.a.str == "0" && n.b.kind == :binary && n.b.str == ">>" && jst_i128_sub?(jst_infer_expr_ty(n.b.a, vtypes, ta_kinds)) && n.b.b.kind == :bigint && n.b.b.str == "64"
      return :u1_big
    if op == "&" && n.b.kind == :bigint && n.b.str == "1" && n.a.kind == :binary && n.a.str == ">>" && jst_i128_sub?(jst_infer_expr_ty(n.a.a, vtypes, ta_kinds)) && n.a.b.kind == :bigint && n.a.b.str == "64"
      return :u1_big
    lt = jst_infer_expr_ty(n.a, vtypes, ta_kinds)
    rt = jst_infer_expr_ty(n.b, vtypes, ta_kinds)
    return :bad if lt == :bad || rt == :bad
    if op == "==" || op == "===" || op == "!=" || op == "!==" || op == "<" || op == "<=" || op == ">" || op == ">="
      if jst_any_big?(lt) || jst_any_big?(rt)
        return :i64 if jst_u64_like?(lt) && jst_u64_like?(rt)
        return :i64 if op == "<" && jst_i128_sub?(lt) && n.b.kind == :bigint && n.b.str == "0"
        return :i64 if op == ">" && jst_i128_sub?(rt) && n.a.kind == :bigint && n.a.str == "0"
        return :bad
      return :i64
    if op == ">>" && (jst_any_big?(lt) || jst_any_big?(rt))
      if n.b.kind == :bigint && js_bigint_literal(n.b.str).v == 64
        return :u1_big if lt == :u128_add2 || lt == :u128_add2_c
        return :u64 if jst_u128_rank(lt) > 0
        return :bad
      return :u64 if jst_u64_like?(lt) && jst_u64_like?(rt) && n.b.kind == :bigint && js_bigint_literal(n.b.str).v < 64
      return :bad
    if op == "|" || op == "&" || op == "^" || op == "<<" || op == ">>" || op == ">>>"
      if jst_any_big?(lt) || jst_any_big?(rt)
        return :bad if op == ">>>" || !jst_any_big?(lt) || !jst_any_big?(rt)
        if op == "<<"
          # Left-shift on 64-bit BigInt can exceed 2^64 unless wrapped in BigInt.asUintN(64, ...)
          return :bad
        if op == "&" && n.b.kind == :bigint && n.b.str == "18446744073709551615" && (jst_u128_rank(lt) > 0 || jst_i128_sub?(lt) || jst_u64_like?(lt))
          return :u64
        if (lt == :i64_big || jst_u64_like?(lt)) && (rt == :i64_big || jst_u64_like?(rt))
          return (lt == :i64_big || rt == :i64_big) ? :i64_big : :u64
        return :bad
      return :i64
    if jst_any_big?(lt) || jst_any_big?(rt)
      return :bad if !jst_any_big?(lt) || !jst_any_big?(rt)
      return jst_big_add_ty(lt, rt) if op == "+"
      if op == "*"
        return :u128_mul if jst_u64_like?(lt) && jst_u64_like?(rt)
        return :bad
      if op == "-"
        return :i128_sub1 if jst_u64_like?(lt) && jst_u64_like?(rt)
        return :i128_sub2 if lt == :i128_sub1 && rt == :u1_big
        return :bad
      if op == "/"
        return :u64 if jst_u64_like?(lt) && jst_u64_like?(rt)
        return :bad
      return :bad
    return :f64 if op == "/" || lt == :f64 || rt == :f64
    return :i64 if (op == "+" || op == "-") && lt == :i64 && rt == :i64
    return :i64 if op == "*" && lt == :i64 && rt == :i64 && ((n.a.kind == :ident && n.b.kind == :ident) || (jst_is_int_lit?(n.b) && n.b.a.to_i >= -256 && n.b.a.to_i <= 256) || (jst_is_int_lit?(n.a) && n.a.a.to_i >= -256 && n.a.a.to_i <= 256))
    :f64
  elsif k == :cond
    ct = jst_infer_expr_ty(n.a, vtypes, ta_kinds)
    return :bad if ct == :bad
    tt = jst_infer_expr_ty(n.b, vtypes, ta_kinds)
    ft = jst_infer_expr_ty(n.c, vtypes, ta_kinds)
    return jst_join_type(tt, ft)
  elsif k == :call
    cal = n.a
    if cal.kind == :member && cal.a.kind == :ident && cal.a.str == "BigInt" && n.list.size == 2
      # Allow exact modular wrapping `BigInt.asUintN(64, expr)` on 64-bit or wide-128 BigInt expressions
      arg = n.list[1]
      if arg.kind == :binary && (arg.str == "+" || arg.str == "-" || arg.str == "*" || arg.str == "<<")
        la_t = jst_infer_expr_ty(arg.a, vtypes, ta_kinds)
        rb_t = jst_infer_expr_ty(arg.b, vtypes, ta_kinds)
        if (jst_u64_like?(la_t) || la_t == :i64_big || jst_u128_rank(la_t) > 0 || jst_i128_sub?(la_t)) && (jst_u64_like?(rb_t) || rb_t == :i64_big || jst_u128_rank(rb_t) > 0)
          return cal.b.str == "asUintN" ? :u64 : :i64_big
      at = jst_infer_expr_ty(arg, vtypes, ta_kinds)
      return :bad if at == :bad || !jst_any_big?(at)
      return cal.b.str == "asUintN" ? :u64 : :i64_big
    if cal.kind == :member && cal.a.kind == :ident && cal.a.str == "Math"
      return :i64 if cal.b.str == "imul"
      return :f64
  :bad

-> jst_collect_mutated_vars(node, mut)
  return nil if node == nil
  k = node.kind
  if k == :block
    node.list.each ->(s) jst_collect_mutated_vars(s, mut)
  elsif k == :expr_stmt
    e = node.a
    if e != nil && (e.kind == :assign || e.kind == :update) && e.a.kind == :ident
      mut[e.a.str] = true
  elsif k == :if
    jst_collect_mutated_vars(node.b, mut)
    jst_collect_mutated_vars(node.c, mut)
  elsif k == :for
    jst_collect_mutated_vars(node.d, mut)
    mut[node.c.a.str] = true if node.c != nil && (node.c.kind == :assign || node.c.kind == :update) && node.c.a.kind == :ident
  elsif k == :while
    jst_collect_mutated_vars(node.b, mut)
  nil

-> jst_infer_stmts_pass(stmts, vtypes, ta_kinds, changed)
  i = 0
  while i < stmts.size
    s = stmts[i]
    if s != nil
      k = s.kind
      if k == :block
        jst_infer_stmts_pass(s.list, vtypes, ta_kinds, changed)
      elsif k == :var_decl
        s.list.each ->(d)
          nm = d.a.str
          nt = d.b != nil ? jst_infer_expr_ty(d.b, vtypes, ta_kinds) : :f64
          prev = vtypes[nm]
          jt = jst_join_type(prev, nt)
          if jt != prev
            vtypes[nm] = jt
            changed[0] = true
      elsif k == :expr_stmt
        e = s.a
        if e != nil && e.kind == :assign
          if e.a.kind == :member && e.a.has?(F_COMPUTED)
            # Also validate RHS expression type on array element stores!
            rt_elem = jst_infer_expr_ty(e.b, vtypes, ta_kinds)
            tk_dst = ta_kinds[e.a.a.str]
            if rt_elem == :bad || ((tk_dst == 9 || tk_dst == 10) && !jst_any_big?(rt_elem)) || (tk_dst != 9 && tk_dst != 10 && jst_any_big?(rt_elem))
              vtypes["__elem_bad__"] = :bad
              changed[0] = true
          elsif e.a.kind == :ident
            nm = e.a.str
            rt = jst_infer_expr_ty(e.b, vtypes, ta_kinds)
            nt = rt
            if e.str != "="
              bop = e.str.slice(0, e.str.size - 1)
              cur = vtypes[nm]
              if bop == "^" || bop == "|" || bop == "&"
                if jst_any_big?(cur) || jst_any_big?(rt)
                  nt = ((cur == :i64_big || jst_u64_like?(cur)) && (rt == :i64_big || jst_u64_like?(rt))) ? ((cur == :i64_big || rt == :i64_big) ? :i64_big : :u64) : :bad
                else
                  nt = :i64
              elsif bop == "/"
                nt = (jst_any_big?(cur) || jst_any_big?(rt)) ? :bad : :f64
              elsif jst_any_big?(cur) || jst_any_big?(rt)
                nt = bop == "+" ? jst_big_add_ty(cur, rt) : :bad
              else
                nt = jst_join_type(cur, rt)
            prev = vtypes[nm]
            jt = jst_join_type(prev, nt)
            if jt != prev
              vtypes[nm] = jt
              changed[0] = true
      elsif k == :if
        jst_infer_stmts_pass([s.b], vtypes, ta_kinds, changed) if s.b != nil
        jst_infer_stmts_pass([s.c], vtypes, ta_kinds, changed) if s.c != nil
      elsif k == :while
        jst_infer_stmts_pass([s.b], vtypes, ta_kinds, changed) if s.b != nil
      elsif k == :for
        jst_infer_stmts_pass([s.a], vtypes, ta_kinds, changed) if s.a != nil && s.a.kind == :var_decl
        jst_infer_stmts_pass([JsNode.new(:expr_stmt, 0, 0, nil, s.a, nil, nil, nil, 0)], vtypes, ta_kinds, changed) if s.a != nil && s.a.kind != :var_decl
        jst_infer_stmts_pass([JsNode.new(:expr_stmt, 0, 0, nil, s.c, nil, nil, nil, 0)], vtypes, ta_kinds, changed) if s.c != nil
        jst_infer_stmts_pass([s.d], vtypes, ta_kinds, changed) if s.d != nil
    i += 1
  nil

# Helper: record per-array length requirement (`1` = n, `2` = 2*n, `4` = 4*n, `-2` = n*n)
-> jst_record_arr_req(req_map, arr_nm, scale)
  prev = req_map[arr_nm]
  if scale == -2 || prev == -2
    req_map[arr_nm] = -2
  elsif prev == nil || scale > prev
    req_map[arr_nm] = scale
  nil

# Check that every computed array access in `node` is statically proved in-bounds under `env_bounds`!
# `env_bounds`: var_name -> [limit_var_name, max_offset_above_idx, scale]
#   scale: 1 -> 0 <= v < n;  2 -> 0 <= v < 2*n;  4 -> 0 <= v + max_off < 4*n;  -2 -> v = i * n (0 <= i < n)
-> jst_check_bounds_expr(n, ta_kinds, env_bounds, n_param, req_map, need_pos)
  return true if n == nil
  k = n.kind
  if k == :member && n.has?(F_COMPUTED)
    arr_nm = n.a.str
    return false if ta_kinds[arr_nm] == nil
    idx = n.b
    # Case 1: a[i] where i is proved 0 <= i < n_param * scale
    if idx.kind == :ident
      bd = env_bounds[idx.str]
      if bd != nil && bd[0] == n_param && bd[2] > 0
        jst_record_arr_req(req_map, arr_nm, bd[2])
        return true
      return false
    # Case 2: a[k] for constant integer literal k >= 0 (e.g. a[0]..a[3] for u256 when k < 4 -> scale 4, k == 0 -> scale 1)
    if jst_is_int_lit?(idx)
      kv = idx.a.to_i
      if kv == 0
        need_pos[0] = true
        jst_record_arr_req(req_map, arr_nm, 1)
        return true
      elsif kv >= 1 && kv <= 3
        need_pos[0] = true
        jst_record_arr_req(req_map, arr_nm, 4)
        return true
      return false
    # Case 3: a[n - 1] (in-bounds when n >= 1)
    if idx.kind == :binary && idx.str == "-" && idx.a.kind == :ident && idx.a.str == n_param && jst_is_int_lit?(idx.b) && idx.b.a.to_i == 1
      need_pos[0] = true
      jst_record_arr_req(req_map, arr_nm, 1)
      return true
    # Case 4a: a[n * n - 1] (in-bounds when n >= 1 and arr.len >= n * n)
    if idx.kind == :binary && idx.str == "-" && jst_is_int_lit?(idx.b) && idx.b.a.to_i == 1 && idx.a.kind == :binary && idx.a.str == "*" && idx.a.a.kind == :ident && idx.a.a.str == n_param && idx.a.b.kind == :ident && idx.a.b.str == n_param
      need_pos[0] = true
      jst_record_arr_req(req_map, arr_nm, -2)
      return true
    # Case 4b: a[n * 2 - 1] or a[2 * n - 1] (in-bounds when n >= 1 and arr.len >= 2 * n)
    if idx.kind == :binary && idx.str == "-" && jst_is_int_lit?(idx.b) && idx.b.a.to_i == 1 && idx.a.kind == :binary && idx.a.str == "*"
      if (idx.a.a.kind == :ident && idx.a.a.str == n_param && jst_is_int_lit?(idx.a.b) && idx.a.b.a.to_i == 2) || (idx.a.b.kind == :ident && idx.a.b.str == n_param && jst_is_int_lit?(idx.a.a) && idx.a.a.a.to_i == 2)
        need_pos[0] = true
        jst_record_arr_req(req_map, arr_nm, 2)
        return true
    # Case 5: a[i + k] where k is integer literal 0 <= k <= bd[1]
    if idx.kind == :binary && idx.str == "+" && idx.a.kind == :ident && jst_is_int_lit?(idx.b)
      bd = env_bounds[idx.a.str]
      k_off = idx.b.a.to_i
      if bd != nil && bd[0] == n_param && bd[2] > 0 && k_off >= 0 && k_off <= bd[1]
        jst_record_arr_req(req_map, arr_nm, bd[2])
        return true
      return false
    # Case 6: a[i + j] or a[i + n] or a[io + k]:
    if idx.kind == :binary && idx.str == "+" && idx.a.kind == :ident && idx.b.kind == :ident
      ba = env_bounds[idx.a.str]
      bb = env_bounds[idx.b.str]
      if ba != nil && bb != nil && ba[0] == n_param && bb[0] == n_param
        if ba[2] == -2 && bb[2] == 1
          jst_record_arr_req(req_map, arr_nm, -2)
          return true
        # `i + j` where 0 <= i < n and 0 <= j < n -> 0 <= i + j <= 2*n - 2 < 2*n!
        if ba[2] == 1 && bb[2] == 1
          jst_record_arr_req(req_map, arr_nm, 2)
          return true
      # `i + n` or `n + i` where 0 <= i < n -> 0 <= i + n <= 2*n - 1 < 2*n!
      if ba != nil && ba[0] == n_param && ba[2] == 1 && idx.b.str == n_param
        jst_record_arr_req(req_map, arr_nm, 2)
        return true
      if bb != nil && bb[0] == n_param && bb[2] == 1 && idx.a.str == n_param
        jst_record_arr_req(req_map, arr_nm, 2)
        return true
    # Case 7: a[k * n + j] where 0 <= k < n and 0 <= j < n
    if idx.kind == :binary && idx.str == "+" && idx.a.kind == :binary && idx.a.str == "*" && idx.a.a.kind == :ident && idx.a.b.kind == :ident && idx.a.b.str == n_param && idx.b.kind == :ident
      bk = env_bounds[idx.a.a.str]
      bj = env_bounds[idx.b.str]
      if bk != nil && bj != nil && bk[0] == n_param && bj[0] == n_param && bk[2] == 1 && bj[2] == 1
        jst_record_arr_req(req_map, arr_nm, -2)
        return true
    return false
  elsif k == :unary
    return jst_check_bounds_expr(n.a, ta_kinds, env_bounds, n_param, req_map, need_pos)
  elsif k == :binary
    return jst_check_bounds_expr(n.a, ta_kinds, env_bounds, n_param, req_map, need_pos) && jst_check_bounds_expr(n.b, ta_kinds, env_bounds, n_param, req_map, need_pos)
  elsif k == :cond
    return jst_check_bounds_expr(n.a, ta_kinds, env_bounds, n_param, req_map, need_pos) && jst_check_bounds_expr(n.b, ta_kinds, env_bounds, n_param, req_map, need_pos) && jst_check_bounds_expr(n.c, ta_kinds, env_bounds, n_param, req_map, need_pos)
  elsif k == :call
    i = 0
    while i < n.list.size
      return false if !jst_check_bounds_expr(n.list[i], ta_kinds, env_bounds, n_param, req_map, need_pos)
      i += 1
    return true
  true

-> jst_check_bounds_stmt(s, ta_kinds, env_bounds, n_param, scale_vars, req_map, need_pos, all_mut)
  return true if s == nil
  k = s.kind
  if k == :block
    added = []
    i = 0
    while i < s.list.size
      sub = s.list[i]
      return false if !jst_check_bounds_stmt(sub, ta_kinds, env_bounds, n_param, scale_vars, req_map, need_pos, all_mut)
      if sub != nil && sub.kind == :var_decl
        sub.list.each ->(d)
          if d.b != nil && !all_mut[d.a.str] && d.b.kind == :binary && d.b.str == "*" && d.b.a.kind == :ident
            bi = env_bounds[d.b.a.str]
            if bi != nil && bi[0] == n_param && bi[2] == 1
              if jst_is_int_lit?(d.b.b) && d.b.b.a.to_i == 4
                env_bounds[d.a.str] = [n_param, 3, 4]
                added.push(d.a.str)
              elsif d.b.b.kind == :ident && d.b.b.str == n_param
                env_bounds[d.a.str] = [n_param, 0, -2]
                added.push(d.a.str)
      i += 1
    added.each ->(nm) env_bounds.delete(nm)
    return true
  elsif k == :var_decl
    i = 0
    while i < s.list.size
      d = s.list[i]
      return false if !jst_check_bounds_expr(d.b, ta_kinds, env_bounds, n_param, req_map, need_pos)
      # Recognize `var lim = n * 4` or `var lim2 = n * 2` (when immutable!)
      if d.b != nil && !all_mut[d.a.str] && d.b.kind == :binary && d.b.str == "*" && d.b.a.kind == :ident && d.b.a.str == n_param && jst_is_int_lit?(d.b.b)
        kv = d.b.b.a.to_i
        scale_vars[d.a.str] = kv if kv == 2 || kv == 4
      i += 1
    return true
  elsif k == :expr_stmt
    e = s.a
    if e.kind == :assign
      return false if !jst_check_bounds_expr(e.a, ta_kinds, env_bounds, n_param, req_map, need_pos)
      return jst_check_bounds_expr(e.b, ta_kinds, env_bounds, n_param, req_map, need_pos)
    return true
  elsif k == :return
    return jst_check_bounds_expr(s.a, ta_kinds, env_bounds, n_param, req_map, need_pos)
  elsif k == :if
    return jst_check_bounds_expr(s.a, ta_kinds, env_bounds, n_param, req_map, need_pos) && jst_check_bounds_stmt(s.b, ta_kinds, env_bounds, n_param, scale_vars, req_map, need_pos, all_mut) && jst_check_bounds_stmt(s.c, ta_kinds, env_bounds, n_param, scale_vars, req_map, need_pos, all_mut)
  elsif k == :while
    return jst_check_bounds_expr(s.a, ta_kinds, env_bounds, n_param, req_map, need_pos) && jst_check_bounds_stmt(s.b, ta_kinds, env_bounds, n_param, scale_vars, req_map, need_pos, all_mut)
  elsif k == :for
    iv = nil
    init_ok = false
    if s.a != nil && s.a.kind == :var_decl && s.a.list.size == 1 && jst_is_int_lit?(s.a.list[0].b) && s.a.list[0].b.a.to_i == 0
      iv = s.a.list[0].a.str
      init_ok = true
    elsif s.a != nil && s.a.kind == :assign && s.a.str == "=" && s.a.a.kind == :ident && jst_is_int_lit?(s.a.b) && s.a.b.a.to_i == 0
      iv = s.a.a.str
      init_ok = true
    new_bound = nil
    if init_ok && iv != nil && s.b != nil && s.b.kind == :binary && s.b.str == "<" && s.b.a.kind == :ident && s.b.a.str == iv
      body_mut = {}
      jst_collect_mutated_vars(s.d, body_mut)
      if !body_mut[iv]
        step = 0
        if s.c != nil && s.c.kind == :update && s.c.str == "++" && s.c.a.kind == :ident && s.c.a.str == iv
          step = 1
        elsif s.c != nil && s.c.kind == :assign && s.c.str == "+=" && s.c.a.kind == :ident && s.c.a.str == iv && jst_is_int_lit?(s.c.b)
          step = s.c.b.a.to_i
        if step == 1 && s.b.b.kind == :ident && s.b.b.str == n_param
          new_bound = [n_param, 0, 1]
        elsif step == 1 && s.b.b.kind == :ident && scale_vars[s.b.b.str] == 2
          new_bound = [n_param, 0, 2]
        elsif step == 1 && s.b.b.kind == :binary && s.b.b.str == "*" && s.b.b.a.kind == :ident && s.b.b.a.str == n_param && jst_is_int_lit?(s.b.b.b) && s.b.b.b.a.to_i == 2
          new_bound = [n_param, 0, 2]
        elsif step == 4 && s.b.b.kind == :ident && scale_vars[s.b.b.str] == 4
          new_bound = [n_param, 3, 4]
        elsif step == 4 && s.b.b.kind == :binary && s.b.b.str == "*" && s.b.b.a.kind == :ident && s.b.b.a.str == n_param && jst_is_int_lit?(s.b.b.b) && s.b.b.b.a.to_i == 4
          new_bound = [n_param, 3, 4]
    prev_b = iv != nil ? env_bounds[iv] : nil
    env_bounds[iv] = new_bound if iv != nil && new_bound != nil
    ok = jst_check_bounds_stmt(s.d, ta_kinds, env_bounds, n_param, scale_vars, req_map, need_pos, all_mut)
    if iv != nil
      if prev_b != nil
        env_bounds[iv] = prev_b
      else
        env_bounds.delete(iv)
    return ok
  true

# Full sound verification: returns [ok, inferred_vtypes, req_map, need_pos_n]
-> jst_verify_soundness(jf, param_specs)
  fn_node = jf.node
  return [false, nil, nil, false] if fn_node == nil || !fn_node.b.is_a?(Array)
  params = fn_node.list.map(->(p) p.str)
  vtypes = {}
  ta_kinds = {}
  n_param = nil
  i = 0
  while i < params.size
    sp = param_specs[i]
    nm = params[i]
    if sp[0] == :ta
      ta_kinds[nm] = sp[1]
      vtypes[nm] = :arr
    elsif sp[0] == :u64
      vtypes[nm] = :u64
    elsif sp[0] == :i64
      vtypes[nm] = :i64
      n_param = nm
    else
      vtypes[nm] = :f64
    i += 1

  # Fixed-point type inference (up to 8 passes so unbounded BigInt loops climb to :bad!)
  it = 0
  while it < 8
    changed = [false]
    jst_infer_stmts_pass(fn_node.b, vtypes, ta_kinds, changed)
    break if !changed[0]
    it += 1

  # Reject if not converged or any variable/store reached :bad!
  return [false, nil, nil, false] if it >= 8
  bad_found = false
  vtypes.each ->(k, v)
    bad_found = true if v == :bad
  return [false, nil, nil, false] if bad_found

  # Reject if any `return expr` tries to return an un-narrowed wide 128-bit BigInt or `:bad`!
  ret_box = [nil]
  jst_collect_ret_type(fn_node.b, vtypes, ta_kinds, ret_box)
  rt_chk = ret_box[0]
  return [false, nil, nil, false] if rt_chk == :bad || jst_u128_rank(rt_chk) > 0 || jst_i128_sub?(rt_chk)

  # Reject if any array access cannot be statically proved in-bounds!
  req_map = {}
  need_pos = [false]
  if ta_kinds.size > 0
    return [false, nil, nil, false] if n_param == nil
    all_mut = {}
    fn_node.b.each ->(st) jst_collect_mutated_vars(st, all_mut)
    return [false, nil, nil, false] if all_mut[n_param]
    env_bounds = {}
    scale_vars = {}
    bi = 0
    while bi < fn_node.b.size
      return [false, nil, nil, false] if !jst_check_bounds_stmt(fn_node.b[bi], ta_kinds, env_bounds, n_param, scale_vars, req_map, need_pos, all_mut)
      bi += 1
    return [true, vtypes, req_map, need_pos[0]]
  [true, vtypes, req_map, false]

# ---- 2. 100% Structurally Exact AST Pattern Swizzler ----

-> jst_is_canonical_for?(st, limit_name, step)
  return false if st == nil || st.kind != :for
  return false if st.a == nil || st.a.kind != :var_decl || st.a.list.size != 1
  iv = st.a.list[0].a.str
  return false if !jst_is_int_lit?(st.a.list[0].b) || st.a.list[0].b.a.to_i != 0
  return false if st.b == nil || st.b.kind != :binary || st.b.str != "<" || st.b.a.kind != :ident || st.b.a.str != iv
  return false if st.b.b.kind != :ident || st.b.b.str != limit_name
  if step == 1
    upd_ok = (st.c != nil && st.c.kind == :update && st.c.str == "++" && st.c.a.kind == :ident && st.c.a.str == iv) || (st.c != nil && st.c.kind == :assign && st.c.str == "+=" && st.c.a.kind == :ident && st.c.a.str == iv && jst_is_int_lit?(st.c.b) && st.c.b.a.to_i == 1)
    return false if !upd_ok
  else
    return false if st.c == nil || st.c.kind != :assign || st.c.str != "+=" || st.c.a.kind != :ident || st.c.a.str != iv || !jst_is_int_lit?(st.c.b) || st.c.b.a.to_i != step
  iv

-> jst_is_arr_at?(n, arr_name, idx_name, off = 0)
  return false if n == nil || n.kind != :member || !n.has?(F_COMPUTED) || n.a.kind != :ident || n.a.str != arr_name
  if off == 0
    return n.b.kind == :ident && n.b.str == idx_name
  n.b.kind == :binary && n.b.str == "+" && n.b.a.kind == :ident && n.b.a.str == idx_name && jst_is_int_lit?(n.b.b) && n.b.b.a.to_i == off

-> jst_match_swizzle(jf, param_kinds, metal_ok)
  fn_node = jf.node
  return nil if fn_node == nil || !fn_node.b.is_a?(Array)
  params = fn_node.list.map(->(p) p.kind == :ident ? p.str : "")
  stmts = fn_node.b

  # Pattern B: Exact Float32 SAXPY (`out[i] = alpha * a[i] + b[i]`)
  if params.size == 5 && param_kinds[0] == 7 && param_kinds[1] == 7 && param_kinds[2] == 7 && stmts.size == 2
    iv = jst_is_canonical_for?(stmts[0], params[4], 1)
    if iv != false && stmts[1].kind == :return && stmts[1].a != nil && stmts[1].a.kind == :ident && stmts[1].a.str == params[4]
      fbody = stmts[0].d
      inner = fbody.kind == :block && fbody.list.size == 1 ? fbody.list[0] : fbody
      if inner.kind == :expr_stmt && inner.a.kind == :assign && inner.a.str == "=" && jst_is_arr_at?(inner.a.a, params[0], iv, 0)
        rhs = inner.a.b
        if rhs.kind == :binary && rhs.str == "+" && rhs.a.kind == :binary && rhs.a.str == "*" && rhs.a.a.kind == :ident && rhs.a.a.str == params[3] && jst_is_arr_at?(rhs.a.b, params[1], iv, 0) && jst_is_arr_at?(rhs.b, params[2], iv, 0)
          JST_SWIZZLED_COUNT[0] += 1
          d = JstKernelDesc.new(jf.name, :swizzle, 0, :tlib_saxpy_f32)
          if metal_ok
            d.metal_key = "saxpy_f32"
            d.metal_min_n = 131072
            JST_METAL_COUNT[0] += 1
          return d

  # Pattern C: Exact Float16 ReLU + Scale (`var v = inp[i] * scale; out[i] = v > 0 ? v : 0`)
  if params.size == 4 && param_kinds[0] == 11 && param_kinds[1] == 11 && stmts.size == 2
    iv = jst_is_canonical_for?(stmts[0], params[3], 1)
    if iv != false && stmts[1].kind == :return && stmts[1].a != nil && stmts[1].a.kind == :ident && stmts[1].a.str == params[3]
      fbody = stmts[0].d
      if fbody.kind == :block && fbody.list.size == 2
        s0 = fbody.list[0]; s1 = fbody.list[1]
        if s0.kind == :var_decl && s0.list.size == 1 && s0.list[0].b != nil && s0.list[0].b.kind == :binary && s0.list[0].b.str == "*"
          vnm = s0.list[0].a.str
          mul = s0.list[0].b
          mul_ok = (jst_is_arr_at?(mul.a, params[1], iv, 0) && mul.b.kind == :ident && mul.b.str == params[2]) || (jst_is_arr_at?(mul.b, params[1], iv, 0) && mul.a.kind == :ident && mul.a.str == params[2])
          if mul_ok && s1.kind == :expr_stmt && s1.a.kind == :assign && s1.a.str == "=" && jst_is_arr_at?(s1.a.a, params[0], iv, 0)
            c = s1.a.b
            if c.kind == :cond && c.a.kind == :binary && c.a.str == ">" && c.a.a.kind == :ident && c.a.a.str == vnm && jst_is_int_lit?(c.a.b) && c.a.b.a == ~0.0 && c.b.kind == :ident && c.b.str == vnm && jst_is_int_lit?(c.c) && c.c.a == ~0.0
              JST_SWIZZLED_COUNT[0] += 1
              return JstKernelDesc.new(jf.name, :swizzle, 0, :tlib_relu_scale_f16)

  # Pattern D: Exact RGBA Luminance Grayscale (`(77*R + 150*G + 29*B) >> 8`)
  if params.size == 3 && (param_kinds[0] == 1 || param_kinds[0] == 2) && (param_kinds[1] == 1 || param_kinds[1] == 2) && stmts.size == 3
    if stmts[0].kind == :var_decl && stmts[0].list.size == 1 && stmts[0].list[0].b != nil && stmts[0].list[0].b.kind == :binary && stmts[0].list[0].b.str == "*" && stmts[0].list[0].b.a.kind == :ident && stmts[0].list[0].b.a.str == params[2] && jst_is_int_lit?(stmts[0].list[0].b.b) && stmts[0].list[0].b.b.a.to_i == 4
      lim_nm = stmts[0].list[0].a.str
      iv = jst_is_canonical_for?(stmts[1], lim_nm, 4)
      if iv != false && stmts[2].kind == :return && stmts[2].a != nil && stmts[2].a.kind == :ident && stmts[2].a.str == params[2]
        fbody = stmts[1].d
        if fbody.kind == :block && fbody.list.size == 5
          l0 = fbody.list[0]
          if l0.kind == :var_decl && l0.list.size == 1 && l0.list[0].b != nil && l0.list[0].b.kind == :binary && l0.list[0].b.str == ">>" && jst_is_int_lit?(l0.list[0].b.b) && l0.list[0].b.b.a.to_i == 8
            lnm = l0.list[0].a.str
            sum_e = l0.list[0].b.a
            if sum_e.kind == :binary && sum_e.str == "+" && sum_e.a.kind == :binary && sum_e.a.str == "+"
              t0 = sum_e.a.a; t1 = sum_e.a.b; t2 = sum_e.b
              ok0 = t0.kind == :binary && t0.str == "*" && jst_is_arr_at?(t0.a, params[1], iv, 0) && jst_is_int_lit?(t0.b) && t0.b.a.to_i == 77
              ok1 = t1.kind == :binary && t1.str == "*" && jst_is_arr_at?(t1.a, params[1], iv, 1) && jst_is_int_lit?(t1.b) && t1.b.a.to_i == 150
              ok2 = t2.kind == :binary && t2.str == "*" && jst_is_arr_at?(t2.a, params[1], iv, 2) && jst_is_int_lit?(t2.b) && t2.b.a.to_i == 29
              w0 = fbody.list[1]; w1 = fbody.list[2]; w2 = fbody.list[3]; w3 = fbody.list[4]
              wok0 = w0.kind == :expr_stmt && w0.a.kind == :assign && w0.a.str == "=" && jst_is_arr_at?(w0.a.a, params[0], iv, 0) && w0.a.b.kind == :ident && w0.a.b.str == lnm
              wok1 = w1.kind == :expr_stmt && w1.a.kind == :assign && w1.a.str == "=" && jst_is_arr_at?(w1.a.a, params[0], iv, 1) && w1.a.b.kind == :ident && w1.a.b.str == lnm
              wok2 = w2.kind == :expr_stmt && w2.a.kind == :assign && w2.a.str == "=" && jst_is_arr_at?(w2.a.a, params[0], iv, 2) && w2.a.b.kind == :ident && w2.a.b.str == lnm
              wok3 = w3.kind == :expr_stmt && w3.a.kind == :assign && w3.a.str == "=" && jst_is_arr_at?(w3.a.a, params[0], iv, 3) && jst_is_arr_at?(w3.a.b, params[1], iv, 3)
              if ok0 && ok1 && ok2 && wok0 && wok1 && wok2 && wok3
                JST_SWIZZLED_COUNT[0] += 1
                d = JstKernelDesc.new(jf.name, :swizzle, 0, :tlib_rgba_gray_u8)
                if metal_ok
                  d.metal_key = "rgba_gray_u8"
                  d.metal_min_n = 131072
                  JST_METAL_COUNT[0] += 1
                return d

  # Pattern D2: Exact 1-byte RGBA -> Grayscale (`var j = i * 4; dst[i] = (src[j]*77 + src[j+1]*150 + src[j+2]*29) >> 8; return dst[n - 1]`)
  if params.size == 3 && (param_kinds[0] == 1 || param_kinds[0] == 2) && param_kinds[1] == 1 && stmts.size == 2
    iv = jst_is_canonical_for?(stmts[0], params[2], 1)
    if iv != false && stmts[1].kind == :return && stmts[1].a != nil && stmts[1].a.kind == :member && stmts[1].a.has?(F_COMPUTED) && stmts[1].a.a.kind == :ident && stmts[1].a.a.str == params[1]
      ridx = stmts[1].a.b
      if ridx.kind == :binary && ridx.str == "-" && ridx.a.kind == :ident && ridx.a.str == params[2] && jst_is_int_lit?(ridx.b) && ridx.b.a.to_i == 1
        fbody = stmts[0].d
        if fbody.kind == :block && fbody.list.size == 2
          s0 = fbody.list[0]; s1 = fbody.list[1]
          if s0.kind == :var_decl && s0.list.size == 1 && s0.list[0].b != nil && s0.list[0].b.kind == :binary && s0.list[0].b.str == "*" && s0.list[0].b.a.kind == :ident && s0.list[0].b.a.str == iv && jst_is_int_lit?(s0.list[0].b.b) && s0.list[0].b.b.a.to_i == 4
            jnm = s0.list[0].a.str
            if s1.kind == :expr_stmt && s1.a.kind == :assign && s1.a.str == "=" && jst_is_arr_at?(s1.a.a, params[1], iv, 0)
              rhs = s1.a.b
              if rhs.kind == :binary && rhs.str == ">>" && jst_is_int_lit?(rhs.b) && rhs.b.a.to_i == 8
                se = rhs.a
                if se.kind == :binary && se.str == "+" && se.a.kind == :binary && se.a.str == "+"
                  t0 = se.a.a; t1 = se.a.b; t2 = se.b
                  ok0 = t0.kind == :binary && t0.str == "*" && jst_is_arr_at?(t0.a, params[0], jnm, 0) && jst_is_int_lit?(t0.b) && t0.b.a.to_i == 77
                  ok1 = t1.kind == :binary && t1.str == "*" && jst_is_arr_at?(t1.a, params[0], jnm, 1) && jst_is_int_lit?(t1.b) && t1.b.a.to_i == 150
                  ok2 = t2.kind == :binary && t2.str == "*" && jst_is_arr_at?(t2.a, params[0], jnm, 2) && jst_is_int_lit?(t2.b) && t2.b.a.to_i == 29
                  if ok0 && ok1 && ok2
                    JST_SWIZZLED_COUNT[0] += 1
                    return JstKernelDesc.new(jf.name, :swizzle, 0, :tlib_rgba_gray1_u8)

  # Pattern E: Exact Dense Square Float32Array Matmul (`c[io + j] = sum_k a[io + k] * b[k * n + j]; return c[0] + c[n * n - 1]`)
  if params.size == 4 && param_kinds[0] == 7 && param_kinds[1] == 7 && param_kinds[2] == 7 && stmts.size == 2
    iv = jst_is_canonical_for?(stmts[0], params[3], 1)
    ret_e = stmts[1].kind == :return ? stmts[1].a : nil
    if iv != false && ret_e != nil && ret_e.kind == :binary && ret_e.str == "+"
      ra = ret_e.a; rb = ret_e.b
      ret_ok = ra.kind == :member && ra.has?(F_COMPUTED) && ra.a.kind == :ident && ra.a.str == params[2] && jst_is_int_lit?(ra.b) && ra.b.a.to_i == 0 && rb.kind == :member && rb.has?(F_COMPUTED) && rb.a.kind == :ident && rb.a.str == params[2] && rb.b.kind == :binary && rb.b.str == "-" && jst_is_int_lit?(rb.b.b) && rb.b.b.a.to_i == 1 && rb.b.a.kind == :binary && rb.b.a.str == "*" && rb.b.a.a.kind == :ident && rb.b.a.a.str == params[3] && rb.b.a.b.kind == :ident && rb.b.a.b.str == params[3]
      ob = stmts[0].d
      if ret_ok && ob.kind == :block && ob.list.size == 2
        io_st = ob.list[0]; j_for = ob.list[1]
        if io_st.kind == :var_decl && io_st.list.size == 1 && io_st.list[0].b != nil && io_st.list[0].b.kind == :binary && io_st.list[0].b.str == "*" && io_st.list[0].b.a.kind == :ident && io_st.list[0].b.a.str == iv && io_st.list[0].b.b.kind == :ident && io_st.list[0].b.b.str == params[3]
          io_nm = io_st.list[0].a.str
          jv = jst_is_canonical_for?(j_for, params[3], 1)
          jb = jv != false ? j_for.d : nil
          if jb != nil && jb.kind == :block && jb.list.size == 3
            s_decl = jb.list[0]; k_for = jb.list[1]; c_st = jb.list[2]
            if s_decl.kind == :var_decl && s_decl.list.size == 1 && s_decl.list[0].b != nil && s_decl.list[0].b.kind == :num && s_decl.list[0].b.a == ~0.0
              s_nm = s_decl.list[0].a.str
              kv = jst_is_canonical_for?(k_for, params[3], 1)
              if kv != false && kv != iv && kv != jv && jv != iv
                kb = k_for.d
                kb = kb.list[0] if kb.kind == :block && kb.list.size == 1
                if kb.kind == :expr_stmt && kb.a.kind == :assign && kb.a.str == "+=" && kb.a.a.kind == :ident && kb.a.a.str == s_nm && kb.a.b.kind == :binary && kb.a.b.str == "*"
                  ma = kb.a.b.a; mb = kb.a.b.b
                  a_ok = ma.kind == :member && ma.has?(F_COMPUTED) && ma.a.kind == :ident && ma.a.str == params[0] && ma.b.kind == :binary && ma.b.str == "+" && ma.b.a.kind == :ident && ma.b.a.str == io_nm && ma.b.b.kind == :ident && ma.b.b.str == kv
                  b_ok = mb.kind == :member && mb.has?(F_COMPUTED) && mb.a.kind == :ident && mb.a.str == params[1] && mb.b.kind == :binary && mb.b.str == "+" && mb.b.a.kind == :binary && mb.b.a.str == "*" && mb.b.a.a.kind == :ident && mb.b.a.a.str == kv && mb.b.a.b.kind == :ident && mb.b.a.b.str == params[3] && mb.b.b.kind == :ident && mb.b.b.str == jv
                  c_ok = c_st.kind == :expr_stmt && c_st.a.kind == :assign && c_st.a.str == "=" && c_st.a.a.kind == :member && c_st.a.a.has?(F_COMPUTED) && c_st.a.a.a.kind == :ident && c_st.a.a.a.str == params[2] && c_st.a.a.b.kind == :binary && c_st.a.a.b.str == "+" && c_st.a.a.b.a.kind == :ident && c_st.a.a.b.a.str == io_nm && c_st.a.a.b.b.kind == :ident && c_st.a.a.b.b.str == jv && c_st.a.b.kind == :ident && c_st.a.b.str == s_nm
                  if a_ok && b_ok && c_ok
                    JST_SWIZZLED_COUNT[0] += 1
                    return JstKernelDesc.new(jf.name, :swizzle, 0, :tlib_matmul_f32)
  nil

# ---- 3. Two-Pass In-Process Cinder Compilation (Tier 1 Fast Baseline -> Tier 2 Hot-Swap) ----

# Promote a hot Tier-1 `JstKernelDesc` to Tier 2 in-process via Cinder's optimizing pass pipeline
# and replace `desc.fp` in-place (ZERO Clang, ZERO LLVM, ZERO `.ll`!).
-> jst_reopt_to_tier2(desc)
  return false if desc.tier >= 2 || desc.wire_fn == nil
  wres = wire_compile_func_tier(desc.wire_fn, 2)
  return false if wres == nil || wres[0] == 0
  desc.fp = wres[0] ## i64
  desc.tier = 2
  desc.wire_fn = nil
  desc.reopt_fn = nil
  JST_STATS[:t2_reopt] += 1
  true

# Sound compile entry: verifies purity + fixed-point types + static bounds proof FIRST!
#   `initial_tier == 1` (default): blazing-fast single-pass Cinder baseline (~4-6 us),
#     retains `wf` on `desc.wire_fn` so `jst_reopt_to_tier2` hot-swaps `desc.fp` once hot!
#   `initial_tier == 2`: runs full Tier-2 optimizer immediately.
-> jst_compile_js_func(jf, param_specs, ret_type, initial_tier = 1)
  an = jst_analyze_func(jf)
  return [nil, "", 0] if !an[0]
  ver = jst_verify_soundness(jf, param_specs)
  return [nil, "", 0] if !ver[0]
  vtypes = ver[1]
  req_map = ver[2]
  need_pos = ver[3]

  fn_node = jf.node
  params = fn_node.list.map(->(p) p.str)
  ta_kinds_map = {}
  ta_kinds_list = []
  ta_mults_list = []
  i = 0
  while i < params.size
    sp = param_specs[i]
    if sp[0] == :ta
      tk = sp[1]
      ta_kinds_map[params[i]] = tk
      ta_kinds_list.push(tk)
      rm = req_map != nil && req_map[params[i]] != nil ? req_map[params[i]] : 1
      ta_mults_list.push(rm)
    i += 1

  ret_ty_inf_box = [nil]
  jst_collect_ret_type(fn_node.b, vtypes, ta_kinds_map, ret_ty_inf_box)
  ret_inf = ret_ty_inf_box[0]
  ret_is_u64 = (ret_type == "u64") || (ret_type == "auto" && jst_u64_like?(ret_inf))
  ret_is_s64_big = (ret_type == "auto" && ret_inf == :i64_big)
  if ret_type == "auto"
    ret_type = ret_inf == :f64 ? "f64" : "i64"
  elsif ret_type == "u64"
    ret_type = "i64"

  # Determine dispatch signature tag
  sig = :unknown
  if param_specs.size == 3 && param_specs[0][0] == :ta && param_specs[1][0] == :ta && param_specs[2][0] == :i64
    sig = ret_type == "f64" ? :jit_aai_d : (ret_is_u64 ? :jit_aai_u : :jit_aai_i)
  elsif param_specs.size == 4 && param_specs[0][0] == :f64 && param_specs[1][0] == :ta && param_specs[2][0] == :ta && param_specs[3][0] == :i64 && ret_type == "f64"
    sig = :jit_daai_d
  elsif param_specs.size == 4 && param_specs[0][0] == :ta && param_specs[1][0] == :ta && param_specs[2][0] == :ta && param_specs[3][0] == :i64
    sig = ret_type == "f64" ? :jit_aaai_d : (ret_is_u64 ? :jit_aaai_u : :jit_aaai_i)
  elsif param_specs.size == 4 && param_specs[0][0] == :ta && param_specs[1][0] == :ta && param_specs[2][0] == :u64 && param_specs[3][0] == :i64 && ret_type != "f64"
    sig = ret_is_u64 ? :jit_aaui_u : :jit_aaui_i
  elsif param_specs.size == 5 && param_specs[0][0] == :ta && param_specs[1][0] == :ta && param_specs[2][0] == :ta && param_specs[3][0] == :f64 && param_specs[4][0] == :i64
    sig = :jit_aaadi_i
  elsif param_specs.size == 4 && param_specs[0][0] == :ta && param_specs[1][0] == :ta && param_specs[2][0] == :f64 && param_specs[3][0] == :i64
    sig = :jit_aadi_i
  elsif param_specs.size == 2 && param_specs[0][0] == :ta && param_specs[1][0] == :i64
    sig = ret_type == "f64" ? :jit_ai_d : (ret_is_u64 ? :jit_ai_u : (ret_is_s64_big ? :jit_ai_s64 : :jit_ai_i))
  elsif param_specs.size == 2 && param_specs[0][0] == :f64 && param_specs[1][0] == :f64
    sig = :jit_dd_d
  has_non1_mult = false
  ta_mults_list.each ->(m) has_non1_mult = true if m != 1
  if sig == :unknown || (has_non1_mult && sig != :jit_aai_i && sig != :jit_aai_u && sig != :jit_aai_d && sig != :jit_daai_d && sig != :jit_aaai_d && sig != :jit_aaai_u && sig != :jit_aaai_i && sig != :jit_aaui_u && sig != :jit_aaui_i)
    return [nil, "", 0]

  wf = wire_a64_lower_js_func(jf, param_specs, ret_type, vtypes)
  return [nil, "", 0] if wf == nil
  tier = initial_tier >= 2 ? 2 : 1
  wres = wire_compile_func_tier(wf, tier)
  return [nil, "", 0] if wres == nil || wres[0] == 0

  fp = wres[0] ## i64
  if tier == 1
    JST_STATS[:t1_compile] += 1
  else
    JST_STATS[:t2_reopt] += 1
  JST_COMPILED_COUNT[0] += 1

  desc = JstKernelDesc.new(jf.name, :compiled, fp, sig)
  desc.ta_kinds = ta_kinds_list
  desc.ta_mults = ta_mults_list
  desc.need_pos_n = need_pos
  desc.tier = tier
  if tier == 1
    desc.wire_fn = wf
    desc.reopt_fn = ->(d) jst_reopt_to_tier2(d)
  [desc, "", fp]

# Collect exact inferred return type across all `return` statements in a function body.
-> jst_collect_ret_type(stmts, vtypes, ta_kinds, out_box)
  return nil if stmts == nil
  i = 0
  while i < stmts.size
    s = stmts[i]
    if s != nil
      if s.kind == :return
        rt = s.a != nil ? jst_infer_expr_ty(s.a, vtypes, ta_kinds) : :f64
        out_box[0] = jst_join_type(out_box[0], rt)
      elsif s.kind == :block
        jst_collect_ret_type(s.list, vtypes, ta_kinds, out_box)
      elsif s.kind == :if
        jst_collect_ret_type([s.b], vtypes, ta_kinds, out_box) if s.b != nil
        jst_collect_ret_type([s.c], vtypes, ta_kinds, out_box) if s.c != nil
      elsif s.kind == :for
        jst_collect_ret_type([s.d], vtypes, ta_kinds, out_box) if s.d != nil
      elsif s.kind == :while
        jst_collect_ret_type([s.b], vtypes, ta_kinds, out_box) if s.b != nil
    i += 1
  nil

# ---- 4. Opt-in Engine Integration Hook (BLADE_JS_TUNGSTEN=1) ----
-> jst_infer_specs_and_ret(jf, info, argc, a0, a1, a2, a3, more)
  np = jf.nparams
  return nil if np < 2 || np > 5 || argc < np
  args = [a0, a1, a2, a3]
  if argc > 4 && more.is_a?(Array) && more.size > 4
    args.push(more[4])
  has_ta = false
  specs = []
  pkinds = []
  i = 0
  while i < np
    v = args[i]
    if v.is_a?(JS:TypedArray)
      has_ta = true
      specs.push([:ta, v.kind])
      pkinds.push(v.kind)
    elsif v.is_a?(JS:BigIntValue)
      return nil if v.v < 0 || v.v >= ((1 ## int) << 64)
      specs.push([:u64])
      pkinds.push(-2)
    elsif js_number?(v)
      if i == np - 1 && v == Math.floor(v) && v >= ~0.0 && v <= ~2147483647.0
        specs.push([:i64])
      else
        specs.push([:f64])
      pkinds.push(-1)
    else
      return nil
    i += 1
  return nil if !has_ta
  [specs, pkinds, "auto"]

-> jst_try_dispatch(c, argc, a0, a1, a2, a3, more)
  return JS_HOLE if JS_NEW_TARGET[0] != nil
  d = c.jst_desc
  if d != nil
    return jst_dispatch_kernel(d, argc, a0, a1, a2, a3, more)
  return JS_HOLE if c.jst_state != 0
  jf = c.node
  if !jf.is_a?(JaFunc) || jf.script || jf.dynamic
    c.jst_state = -1
    return JS_HOLE
  an = jst_analyze_func(jf)
  if !an[0]
    c.jst_state = -1
    return JS_HOLE
  # Compile loop kernels and straight-line BigInt limb chains (e.g. u256_add / u256_sub)!
  if an[1][:loops] == 0 && !(an[1][:has_bigint] && an[1][:reads_arr])
    c.jst_state = -1
    return JS_HOLE
  inf = jst_infer_specs_and_ret(jf, an[1], argc, a0, a1, a2, a3, more)
  return JS_HOLE if inf == nil
  # 1. Try 100% structurally exact AST swizzle (0 ms compile time, includes Metal GPU offload!)
  sw = jst_match_swizzle(jf, inf[1], true)
  if sw != nil
    c.jst_desc = sw
    c.jst_state = 1
    return jst_dispatch_kernel(sw, argc, a0, a1, a2, a3, more)
  # 2. Sound two-pass Cinder compilation: Tier 1 (~5 us) now -> Tier 2 hot-swap once hot!
  comp = jst_compile_js_func(jf, inf[0], inf[2], 1)
  if comp[0] != nil && comp[0].sig != :unknown
    c.jst_desc = comp[0]
    c.jst_state = 1
    return jst_dispatch_kernel(comp[0], argc, a0, a1, a2, a3, more)
  c.jst_state = -1
  JS_HOLE

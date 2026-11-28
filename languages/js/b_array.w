# runtime/b_array — Array and Array.prototype (through ES2023), plus array-likes.
# (Ported from blade/js/b_array.w.)
#
# Every method works on any array-like `this`; JS arrays (flagged core Arrays, array.w)
# take fast paths, and plain ones (no side object: extensible, writable length, the
# realm's Array.prototype) take the core Array operations directly. Callbacks are called
# through js_call with the arguments in registers (no argument Array per element).
#
# Array.prototype itself is a JS:Special with cls "Array" (prototypes must be JS:Base
# objects), so Array.isArray and Object.prototype.toString check that class too.

in JS

# A JS array with no side object: extensible, length writable, not frozen or sealed, and
# the realm's Array.prototype as its prototype.
-> js_plain_array?(o)
  f = jsr_aflags(wvalue_bits(o) ## i64)
  (f & JS_AF_ARRAY) != 0 && (f & JS_AF_EXT) == 0

# Do Array.prototype and Object.prototype hold no index-like keys? Then a write past a
# plain array's end cannot meet a setter or a read-only property on its chain. Cached per
# prototype epoch (both are marked as prototypes, so any change to their keys bumps it).
JS_PROTO_CLEAN = [-1, false, nil]

-> js_array_protos_clean?
  e = JS_EPOCH[0]
  c = JS_PROTO_CLEAN
  r = js_realm()
  return c[1] if c[0] == e && c[2] == r
  ok = !js_has_index_key?(r.array_proto) && !js_has_index_key?(r.object_proto)
  c[0] = e
  c[1] = ok
  c[2] = r
  ok

-> js_has_index_key?(o)
  ks = o.own_keys
  i = 0
  while i < ks.size
    return true if js_string?(ks[i]) && js_array_index?(ks[i])
    i += 1
  false

# A plain array that can grow without the generic algorithm.
-> js_growable_array?(o)
  js_plain_array?(o) && js_array_protos_clean?

-> js_len_of(o)
  return js_arr_len(o) if js_array?(o)
  js_to_length(jget(o, "length"))

# Element i of an array-like (holes read through the prototype chain, as [[Get]] does).
-> js_el(o, i)
  if js_array?(o) && i < o.size
    v = o[i]
    return v if v != JS_HOLE
  jget(o, i.to_s)

-> js_has_el?(o, i)
  return true if js_array?(o) && i < o.size && o[i] != JS_HOLE
  jhas_property?(o, i.to_s)

-> js_put_el(o, i, v)
  if js_plain_array?(o) && i < o.size
    o[i] = v
    return nil
  ok = jset(o, i.to_s, v)
  js_set_failed(o, i.to_s) if !ok
  nil

-> js_put_el_set(o, i, v)
  ok = jset(o, i.to_s, v)
  js_set_failed(o, i.to_s) if !ok
  nil

-> js_set_len(o, n)
  ok = jset(o, "length", n + ~0.0)
  js_set_failed(o, "length") if !ok
  nil

-> js_fn_arg(args, i, what)
  f = js_arg(args, i)
  js_throw_type(js_err_display(f) + " is not a function") if !js_callable?(f)
  f

-> js_rel_index(v, len, dflt)
  return dflt if v == nil
  n = js_to_integer(v)
  if n < ~0.0
    n = n + len
    return 0 if n < ~0.0
    return n.to_i
  return len if n > len + ~0.0
  n.to_i

# A JS array that may hold holes (the flag lets reads skip the hole check when clear).
-> js_holey_array(elems)
  js_mark_holey(elems)

# ArraySpeciesCreate (§10.4.2.3)
-> js_species_create(o, n)
  r = js_realm()
  if js_is_array(o)
    c = jget(o, "constructor")
    if js_is_constructor?(c)
      cr = js_get_function_realm(c)
      c = nil if cr != r && c == cr.intrinsic("Array")
    if js_object?(c)
      c = jget(c, SYM_SPECIES)
      c = nil if c == JS_NULL
    if c != nil && c != r.intrinsic("Array")
      js_throw_type("object.constructor\[Symbol.species] is not a constructor") if !js_is_constructor?(c)
      return js_construct(c, [n + ~0.0], nil)
  js_throw_range("Invalid array length") if n > 4294967295
  a = js_mark_array([])
  js_array_set_length(a, n + ~0.0, false) if n > 0
  a

-> js_array_ctor(args, nt)
  r = js_realm()
  proto = nt == nil ? r.array_proto : r.proto_from(nt, "Array")
  a = nil
  if args.size == 1 && js_number?(args[0])
    n = args[0]
    len = js_to_uint32(n)
    js_throw_range("Invalid array length") if len + ~0.0 != n
    a = js_mark_array([])
    js_array_set_length(a, n, false)
  else
    a = js_mark_array(args.dup)
  js_array_set_proto(a, proto) if proto != r.array_proto
  a

-> js_array_from(this, items, mapfn, this_arg)
  r = js_realm()
  js_throw_type(js_err_display(mapfn) + " is not a function") if mapfn != nil && !js_callable?(mapfn)
  ctor = this != r.intrinsic("Array") && js_is_constructor?(this)
  usable = js_nullish?(items) ? nil : js_get_method(items, SYM_ITERATOR)
  if usable != nil
    a = ctor ? js_construct(this, [], nil) : js_mark_array([])
    # the mapper runs as each value is read (it may change the source)
    k = 0
    if !ctor && mapfn == nil && js_array?(items) && js_array_iter_pristine?(items)
      while k < js_arr_len(items)
        a.push(js_arr_elem(items, k))
        k += 1
      return a
    rec = js_get_iterator_with(items, usable)
    begin
      while true
        x = js_iter_step(rec)
        break if x == JS_ITER_DONE
        x = js_call(mapfn, this_arg, 2, x, k + ~0.0, nil, nil, nil) if mapfn != nil
        js_create_data(a, k.to_s, x)
        k += 1
    rescue e
      js_iter_close_quiet(rec) if !rec.done
      raise e
    js_set_len(a, k)
    return a
  o = js_to_obj(items)
  n = js_len_of(o)
  js_throw_range("Invalid array length") if !ctor && n > 4294967295
  a = ctor ? js_construct(this, [n + ~0.0], nil) : js_mark_array([])
  k = 0
  while k < n
    x = js_el(o, k)
    x = js_call(mapfn, this_arg, 2, x, k + ~0.0, nil, nil, nil) if mapfn != nil
    js_create_data(a, k.to_s, x)
    k += 1
  js_set_len(a, n)
  a

# Array.fromAsync (ES2026 §23.1.2.2)
-> js_array_from_async(this, items, mapfn, this_arg)
  r = js_realm()
  q = r.jobs
  prom = JS:Promise.new(r.promise_shape)
  begin
    mapping = mapfn != nil
    js_throw_type(js_err_display(mapfn) + " is not a function") if mapping && !js_callable?(mapfn)
    using_async = js_nullish?(items) ? nil : js_get_method(items, SYM_ASYNC_ITERATOR)
    using_sync = nil
    if using_async == nil
      using_sync = js_nullish?(items) ? nil : js_get_method(items, SYM_ITERATOR)
    ctor = js_is_constructor?(this)
    if using_async != nil || using_sync != nil
      a = ctor ? js_construct(this, [], nil) : js_mark_array([])
      rec = nil
      if using_async != nil
        it = js_call_arr(using_async, items, JS_NO_ARGS)
        js_throw_type("Result of Symbol.asyncIterator is not an object") if !js_object?(it)
        rec = JS:IterRecord.new(it, jget(it, "next"))
      else
        it = js_call_arr(using_sync, items, JS_NO_ARGS)
        js_throw_type("Result of Symbol.iterator is not an object") if !js_object?(it)
        rec = js_create_async_from_sync_iter(JS:IterRecord.new(it, jget(it, "next")))
      js_from_async_iter_step(rec, a, 0, mapping ? mapfn : nil, this_arg, prom)
    else
      o = js_to_obj(items)
      n = js_len_of(o)
      js_throw_range("Invalid array length") if !ctor && n > 4294967295
      a = ctor ? js_construct(this, [n + ~0.0], nil) : js_mark_array([])
      js_from_async_like_step(o, n, a, 0, mapping ? mapfn : nil, this_arg, prom)
  rescue ex
    js_promise_reject_fast(prom, js_error_value(ex), q)
  prom

-> js_from_async_close_and_reject(rec, err, prom)
  r = js_realm()
  q = r.jobs
  begin
    ret = js_get_method(rec.iterator, "return")
    if ret == nil
      js_promise_reject_fast(prom, err, q)
      return nil
    res = js_call_arr(ret, rec.iterator, JS_NO_ARGS)
    js_promise_then_native(res, ->(v) js_promise_reject_fast(prom, err, q), ->(e2) js_promise_reject_fast(prom, err, q), [prom, err])
  rescue ex2
    js_promise_reject_fast(prom, err, q)
  nil

-> js_from_async_iter_step(rec, a, k, mapfn, this_arg, prom)
  r = js_realm()
  q = r.jobs
  if k >= 9007199254740991
    js_from_async_close_and_reject(rec, js_make_error("TypeError", "Array.fromAsync length exceeded"), prom)
    return nil
  begin
    res_p = js_call_arr(rec.next_fn, rec.iterator, JS_NO_ARGS)
    js_promise_then_native(res_p, ->(res) js_from_async_iter_got(rec, a, k, mapfn, this_arg, prom, res), ->(err) js_promise_reject_fast(prom, err, q), [rec, a, mapfn, this_arg, prom])
  rescue ex
    js_promise_reject_fast(prom, js_error_value(ex), q)
  nil

-> js_from_async_iter_got(rec, a, k, mapfn, this_arg, prom, res)
  r = js_realm()
  q = r.jobs
  begin
    js_throw_type("Iterator result is not an object") if !js_object?(res)
    if js_truthy(jget(res, "done"))
      js_set_len(a, k)
      js_promise_fulfill_fast(prom, a, q)
      return nil
    nv = jget(res, "value")
    if mapfn != nil
      mv = nil
      begin
        mv = js_call(mapfn, this_arg, 2, nv, k + ~0.0, nil, nil, nil)
      rescue ex
        js_from_async_close_and_reject(rec, js_error_value(ex), prom)
        return nil
      js_promise_then_native(mv, ->(mapped) js_from_async_iter_store(rec, a, k, mapfn, this_arg, prom, mapped), ->(err) js_from_async_close_and_reject(rec, err, prom), [rec, a, mapfn, this_arg, prom])
    else
      js_from_async_iter_store(rec, a, k, mapfn, this_arg, prom, nv)
  rescue ex
    js_promise_reject_fast(prom, js_error_value(ex), q)
  nil

-> js_from_async_iter_store(rec, a, k, mapfn, this_arg, prom, val)
  begin
    js_create_data(a, k.to_s, val)
  rescue ex
    js_from_async_close_and_reject(rec, js_error_value(ex), prom)
    return nil
  js_from_async_iter_step(rec, a, k + 1, mapfn, this_arg, prom)
  nil

-> js_from_async_like_step(o, n, a, k, mapfn, this_arg, prom)
  r = js_realm()
  q = r.jobs
  begin
    if k >= n
      js_set_len(a, k)
      js_promise_fulfill_fast(prom, a, q)
      return nil
    v = js_el(o, k)
    js_promise_then_native(v, ->(av) js_from_async_like_got(o, n, a, k, mapfn, this_arg, prom, av), ->(err) js_promise_reject_fast(prom, err, q), [o, a, mapfn, this_arg, prom])
  rescue ex
    js_promise_reject_fast(prom, js_error_value(ex), q)
  nil

-> js_from_async_like_got(o, n, a, k, mapfn, this_arg, prom, av)
  r = js_realm()
  q = r.jobs
  begin
    if mapfn != nil
      mv = js_call(mapfn, this_arg, 2, av, k + ~0.0, nil, nil, nil)
      js_promise_then_native(mv, ->(mapped) js_from_async_like_store(o, n, a, k, mapfn, this_arg, prom, mapped), ->(err) js_promise_reject_fast(prom, err, q), [o, a, mapfn, this_arg, prom])
    else
      js_from_async_like_store(o, n, a, k, mapfn, this_arg, prom, av)
  rescue ex
    js_promise_reject_fast(prom, js_error_value(ex), q)
  nil

-> js_from_async_like_store(o, n, a, k, mapfn, this_arg, prom, val)
  r = js_realm()
  q = r.jobs
  begin
    js_create_data(a, k.to_s, val)
  rescue ex
    js_promise_reject_fast(prom, js_error_value(ex), q)
    return nil
  js_from_async_like_step(o, n, a, k + 1, mapfn, this_arg, prom)
  nil

-> js_array_of(this, args)
  r = js_realm()
  if this != r.intrinsic("Array") && js_is_constructor?(this)
    a = js_construct(this, [args.size + ~0.0], nil)
    j = 0
    while j < args.size
      js_create_data(a, j.to_s, args[j])
      j += 1
    js_set_len(a, args.size)
    return a
  js_mark_array(args.dup)

# IsArray (§7.2.2): arrays, Array.prototype, and proxies of either.
-> js_is_array(v)
  return true if js_array?(v)
  return false if !v.is_a?(JS:Base)
  return true if js_special?(v, "Array")
  if js_proxy?(v)
    js_throw_type("Cannot perform 'IsArray' on a proxy that has been revoked") if v.handler == nil
    return js_is_array(js_proxy_target(v))
  false

# ---- Fast Native LLVM Dense-Array map / filter / reduce (100% spec-exact for numeric arrays!) ----

fn jsr_map_f64_k(src, dst, n, op, kb, nan_b) (i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %ku = sub i64 %kb, 281474976710656
    %dk = bitcast i64 %ku to double
    %sp = inttoptr i64 %src to ptr
    %dp = inttoptr i64 %dst to ptr
    br label %init
  init:
    br label %loop
  loop:
    %i = phi i64 [ 0, %init ], [ %ni, %next ]
    %done = icmp sge i64 %i, %n
    br i1 %done, label %ok, label %body
  body:
    %pe = getelementptr i64, ptr %sp, i64 %i
    %v = load i64, ptr %pe, align 8
    %u = sub i64 %v, 281474976710656
    %ok1 = icmp ult i64 %u, -4503599627370495
    br i1 %ok1, label %chk_ord, label %fail
  chk_ord:
    %dx = bitcast i64 %u to double
    %ord = fcmp ord double %dx, %dx
    br i1 %ord, label %calc, label %fail
  calc:
    %is_mul = icmp eq i64 %op, 1
    br i1 %is_mul, label %do_mul, label %chk_add
  do_mul:
    %rm = fmul double %dx, %dk
    br label %store
  chk_add:
    %is_add = icmp eq i64 %op, 2
    br i1 %is_add, label %do_add, label %chk_sub
  do_add:
    %ra = fadd double %dx, %dk
    br label %store
  chk_sub:
    %is_sub = icmp eq i64 %op, 3
    br i1 %is_sub, label %do_sub, label %do_div
  do_sub:
    %rs = fsub double %dx, %dk
    br label %store
  do_div:
    %rd = fdiv double %dx, %dk
    br label %store
  store:
    %res = phi double [ %rm, %do_mul ], [ %ra, %do_add ], [ %rs, %do_sub ], [ %rd, %do_div ]
    %rord = fcmp ord double %res, %res
    %rb0 = bitcast double %res to i64
    %rb1 = add i64 %rb0, 281474976710656
    %rb = select i1 %rord, i64 %rb1, i64 %nan_b
    %pd = getelementptr i64, ptr %dp, i64 %i
    store i64 %rb, ptr %pd, align 8
    br label %next
  next:
    %ni = add i64 %i, 1
    br label %loop
  ok:
    ret i64 1
  fail:
    ret i64 0
  IR

fn jsr_filter_f64_mod(src, dst, n, eq_mode, k_i, c_i) (i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %dk = sitofp i64 %k_i to double
    %dc = sitofp i64 %c_i to double
    %sp = inttoptr i64 %src to ptr
    %dp = inttoptr i64 %dst to ptr
    br label %init
  init:
    br label %loop
  loop:
    %i = phi i64 [ 0, %init ], [ %ni, %next ]
    %to = phi i64 [ 0, %init ], [ %nto, %next ]
    %done = icmp sge i64 %i, %n
    br i1 %done, label %ok, label %body
  body:
    %pe = getelementptr i64, ptr %sp, i64 %i
    %v = load i64, ptr %pe, align 8
    %u = sub i64 %v, 281474976710656
    %ok1 = icmp ult i64 %u, -4503599627370495
    br i1 %ok1, label %chk_ord, label %fail
  chk_ord:
    %dx = bitcast i64 %u to double
    %ord = fcmp ord double %dx, %dx
    br i1 %ord, label %chk_int, label %fail
  chk_int:
    %xi = fptosi double %dx to i64
    %xf = sitofp i64 %xi to double
    %exact = fcmp oeq double %xf, %dx
    br i1 %exact, label %int_mod, label %fp_mod
  int_mod:
    %ir = srem i64 %xi, %k_i
    %ieq = icmp eq i64 %ir, %c_i
    br label %decide
  fp_mod:
    %fr = frem double %dx, %dk
    %feq = fcmp oeq double %fr, %dc
    br label %decide
  decide:
    %eqv = phi i1 [ %ieq, %int_mod ], [ %feq, %fp_mod ]
    %want_eq = icmp eq i64 %eq_mode, 1
    %inv = xor i1 %eqv, true
    %keep = select i1 %want_eq, i1 %eqv, i1 %inv
    br i1 %keep, label %emit, label %skip
  emit:
    %pd = getelementptr i64, ptr %dp, i64 %to
    store i64 %v, ptr %pd, align 8
    %to1 = add i64 %to, 1
    br label %next
  skip:
    br label %next
  next:
    %nto = phi i64 [ %to1, %emit ], [ %to, %skip ]
    %ni = add i64 %i, 1
    br label %loop
  ok:
    ret i64 %to
  fail:
    ret i64 -1
  IR

fn jsr_reduce_f64_op(src, n, acc_b, op) (i64 i64 i64 i64) i64
  ll <<~IR
    %au0 = sub i64 %acc_b, 281474976710656
    %da0 = bitcast i64 %au0 to double
    %sp = inttoptr i64 %src to ptr
    br label %init
  init:
    br label %loop
  loop:
    %i = phi i64 [ 0, %init ], [ %ni, %next ]
    %acc = phi double [ %da0, %init ], [ %nacc, %next ]
    %done = icmp sge i64 %i, %n
    br i1 %done, label %ok, label %body
  body:
    %pe = getelementptr i64, ptr %sp, i64 %i
    %v = load i64, ptr %pe, align 8
    %u = sub i64 %v, 281474976710656
    %ok1 = icmp ult i64 %u, -4503599627370495
    br i1 %ok1, label %chk_ord, label %fail
  chk_ord:
    %dx = bitcast i64 %u to double
    %ord = fcmp ord double %dx, %dx
    br i1 %ord, label %calc, label %fail
  calc:
    %is_add = icmp eq i64 %op, 1
    br i1 %is_add, label %do_add, label %do_mul
  do_add:
    %ra = fadd double %acc, %dx
    br label %next
  do_mul:
    %rm = fmul double %acc, %dx
    br label %next
  next:
    %nacc = phi double [ %ra, %do_add ], [ %rm, %do_mul ]
    %ni = add i64 %i, 1
    br label %loop
  ok:
    %aord = fcmp ord double %acc, %acc
    br i1 %aord, label %ret_ok, label %fail
  ret_ok:
    %ab = bitcast double %acc to i64
    %res = add i64 %ab, 281474976710656
    ret i64 %res
  fail:
    ret i64 0
  IR

fn jsr_copy_u64s(dst, src, n) (i64 i64 i64) i64
  ll <<~IR
    %dp = inttoptr i64 %dst to ptr
    %sp = inttoptr i64 %src to ptr
    br label %init
  init:
    br label %loop
  loop:
    %i = phi i64 [ 0, %init ], [ %ni, %body ]
    %done = icmp sge i64 %i, %n
    br i1 %done, label %ok, label %body
  body:
    %ps = getelementptr i64, ptr %sp, i64 %i
    %pd = getelementptr i64, ptr %dp, i64 %i
    %v = load i64, ptr %ps, align 8
    store i64 %v, ptr %pd, align 8
    %ni = add i64 %i, 1
    br label %loop
  ok:
    ret i64 0
  IR

-> js_hof_single_ret(f, nparams)
  return nil if !f.is_a?(JS:Function) || f.code == nil || (f.code.flags & CODE_CLASS) != 0
  jf = f.code.node
  return nil if !jf.is_a?(JaFunc) || !jf.simple || jf.dynamic || jf.free.size > 0 || jf.params.size != nparams
  n = jf.node
  re = nil
  if jf.arrow && n.has?(F_EXPR_BODY)
    re = n.b
  elsif n.b.is_a?(Array) && n.b.size == 1 && n.b[0].kind == :return
    re = n.b[0].a
  return nil if re == nil
  [jf, re]

-> js_arr_map_fast(o, f)
  return nil if !js_default_species?(o)
  ob = wvalue_bits(o) ## i64
  return nil if (jsr_aflags(ob) & 15) != JS_AF_ARRAY || jsr_arr_start(ob) != 0
  info = js_hof_single_ret(f, 1)
  return nil if info == nil
  jf = info[0]
  re = info[1]
  return nil if re.kind != :binary
  op_s = re.str
  op = op_s == "*" ? 1 : (op_s == "+" ? 2 : (op_s == "-" ? 3 : (op_s == "/" ? 4 : 0)))
  return nil if op == 0
  p0 = jf.params[0]
  kv = nil
  if re.a.kind == :ident && re.a.x != nil && re.a.x.binding == p0 && re.b.kind == :num
    kv = re.b.a
  elsif (op == 1 || op == 2) && re.b.kind == :ident && re.b.x != nil && re.b.x.binding == p0 && re.a.kind == :num
    kv = re.a.a
  return nil if kv == nil || kv != kv
  n = o.size
  out = Array.new(n, nil)
  if n > 0
    ok = jsr_map_f64_k(jsr_arr_slots_ptr(ob), jsr_arr_slots_ptr(wvalue_bits(out) ## i64), n, op, wvalue_bits(kv) ## i64, wvalue_bits(js_nan()) ## i64)
    return nil if ok == 0
  js_mark_array(out)

-> js_arr_filter_fast(o, f)
  return nil if !js_default_species?(o)
  ob = wvalue_bits(o) ## i64
  return nil if (jsr_aflags(ob) & 15) != JS_AF_ARRAY || jsr_arr_start(ob) != 0
  info = js_hof_single_ret(f, 1)
  return nil if info == nil
  jf = info[0]
  re = info[1]
  return nil if re.kind != :binary || (re.str != "===" && re.str != "!==" && re.str != "==" && re.str != "!=")
  eq_mode = (re.str == "===" || re.str == "==") ? 1 : 0
  p0 = jf.params[0]
  lhs = re.a
  rhs = re.b
  if rhs.kind == :binary && rhs.str == "%"
    t_sw = lhs; lhs = rhs; rhs = t_sw
  return nil if lhs.kind != :binary || lhs.str != "%" || rhs.kind != :num
  return nil if lhs.a.kind != :ident || lhs.a.x == nil || lhs.a.x.binding != p0 || lhs.b.kind != :num
  kf = lhs.b.a
  cf = rhs.a
  return nil if kf != kf || cf != cf || kf == ~0.0
  ki = kf.to_i
  ci = cf.to_i
  return nil if ki == 0 || ki.to_f != kf || ci.to_f != cf || kf < ~-2147483648.0 || kf > ~2147483647.0 || cf < ~-2147483648.0 || cf > ~2147483647.0
  n = o.size
  return js_mark_array([]) if n == 0
  buf = JS_SORT_SCRATCH[0]
  if buf.size < n
    buf = i64[n]
    JS_SORT_SCRATCH[0] = buf
  dst_p = jsr_arr_slots_ptr(wvalue_bits(buf) ## i64)
  cnt = jsr_filter_f64_mod(jsr_arr_slots_ptr(ob), dst_p, n, eq_mode, ki, ci)
  return nil if cnt < 0
  out = Array.new(cnt, nil)
  jsr_copy_u64s(jsr_arr_slots_ptr(wvalue_bits(out) ## i64), dst_p, cnt) if cnt > 0
  js_mark_array(out)

-> js_arr_reduce_fast(o, f, acc)
  return JS_HOLE if !js_plain_array?(o) || !js_number?(acc) || acc != acc
  ob = wvalue_bits(o) ## i64
  return JS_HOLE if (jsr_aflags(ob) & 15) != JS_AF_ARRAY || jsr_arr_start(ob) != 0
  info = js_hof_single_ret(f, 2)
  return JS_HOLE if info == nil
  jf = info[0]
  re = info[1]
  return JS_HOLE if re.kind != :binary || (re.str != "+" && re.str != "*")
  op = re.str == "+" ? 1 : 2
  p0 = jf.params[0]
  p1 = jf.params[1]
  return JS_HOLE if re.a.kind != :ident || re.b.kind != :ident || re.a.x == nil || re.b.x == nil
  ba = re.a.x.binding
  bb = re.b.x.binding
  return JS_HOLE if !((ba == p0 && bb == p1) || (ba == p1 && bb == p0))
  n = o.size
  return acc if n == 0
  rb = jsr_reduce_f64_op(jsr_arr_slots_ptr(ob), n, wvalue_bits(acc) ## i64, op)
  return JS_HOLE if rb == 0
  wvalue_from_bits(rb)

# ---- iteration-style methods: f.call(thisArg, value, index, obj) ----

-> js_arr_each(this, args, mode)
  o = js_to_obj(this)
  n = js_len_of(o)
  f = js_fn_arg(args, 0, mode.to_s)
  t = js_arg(args, 1)
  if mode == :map
    fast = js_arr_map_fast(o, f)
    return fast if fast != nil
  elsif mode == :filter
    fast = js_arr_filter_fast(o, f)
    return fast if fast != nil
  out = nil
  if mode == :map
    out = js_species_create(o, n)
  elsif mode == :filter
    out = js_species_create(o, 0)
  to = 0
  filled = 0
  i = 0
  while i < n
    if js_has_el?(o, i)
      v = js_el(o, i)
      res = js_call(f, t, 3, v, i + ~0.0, o, nil, nil)
      if mode == :map
        if js_plain_array?(out) && (js_array_flags(out) & JS_AF_SPARSE) == 0 && i < out.size
          out[i] = res
        else
          js_create_data(out, i.to_s, res)
        filled += 1
      elsif mode == :filter
        if js_truthy(res)
          if js_plain_array?(out) && (js_array_flags(out) & JS_AF_SPARSE) == 0 && out.size == to
            out.push(v)
          else
            js_create_data(out, to.to_s, v)
          to += 1
      elsif mode == :some
        return true if js_truthy(res)
      elsif mode == :every
        return false if !js_truthy(res)
    i += 1
  if mode == :map && filled == n && js_plain_array?(out) && out.size == n
    # every slot was written: reads need no hole check
    ob = wvalue_bits(out) ## i64
    jsr_set_aflags(ob, JS_AF_ARRAY)
  return out if mode == :map || mode == :filter
  return false if mode == :some
  return true if mode == :every
  nil

-> js_arr_find(this, args, from_end, want_index)
  o = js_to_obj(this)
  n = js_len_of(o)
  f = js_fn_arg(args, 0, "find")
  t = js_arg(args, 1)
  i = from_end ? n - 1 : 0
  while from_end ? i >= 0 : i < n
    v = js_el(o, i)
    if js_truthy(js_call(f, t, 3, v, i + ~0.0, o, nil, nil))
      return want_index ? i + ~0.0 : v
    i += from_end ? -1 : 1
  want_index ? ~-1.0 : nil

-> js_arr_reduce(this, args, right)
  o = js_to_obj(this)
  n = js_len_of(o)
  f = js_fn_arg(args, 0, "reduce")
  if !right && args.size >= 2
    fast_r = js_arr_reduce_fast(o, f, args[1])
    return fast_r if fast_r != JS_HOLE
  i = right ? n - 1 : 0
  acc = nil
  if args.size >= 2
    acc = args[1]
  else
    found = false
    while (right ? i >= 0 : i < n) && !found
      if js_has_el?(o, i)
        acc = js_el(o, i)
        found = true
      i += right ? -1 : 1
    js_throw_type("Reduce of empty array with no initial value") if !found
  while right ? i >= 0 : i < n
    if js_has_el?(o, i)
      acc = js_call(f, nil, 4, acc, js_el(o, i), i + ~0.0, o, nil)
    i += right ? -1 : 1
  acc

-> js_arr_index_of(this, args, last)
  o = js_to_obj(this)
  n = js_len_of(o)
  return ~-1.0 if n == 0
  x = js_arg(args, 0)
  if last
    i = args.size > 1 ? js_to_integer(args[1]) : n - ~1.0
    i = i < ~0.0 ? i + n : (i > n - ~1.0 ? n - ~1.0 : i)
    k = i.to_i
    return ~-1.0 if k < 0
    if js_array?(o) && (js_array_flags(o) & JS_AF_SPARSE) != 0 && !JS_PROTO_INDEX[0]
      idxs = js_array_sparse_indices(o)
      j = idxs.size - 1
      while j >= 0
        idx = idxs[j]
        if idx <= k && js_has_el?(o, idx) && js_strict_eq(js_el(o, idx), x)
          return idx + ~0.0
        j -= 1
      return ~-1.0
    while k >= 0
      return k + ~0.0 if js_has_el?(o, k) && js_strict_eq(js_el(o, k), x)
      k -= 1
    return ~-1.0
  k = js_rel_index(js_arg(args, 1), n, 0)
  return ~-1.0 if k >= n
  if js_array?(o)
    f = js_array_flags(o)
    if (f & (JS_AF_HOLES | JS_AF_EXT | JS_AF_SPARSE)) == 0
      lim = o.size < n ? o.size : n
      while k < lim
        return k + ~0.0 if js_strict_eq(o[k], x)
        k += 1
      return ~-1.0
    if (f & JS_AF_SPARSE) != 0 && !JS_PROTO_INDEX[0]
      idxs = js_array_sparse_indices(o)
      j = 0
      while j < idxs.size
        idx = idxs[j]
        if idx >= k && idx < n && js_has_el?(o, idx) && js_strict_eq(js_el(o, idx), x)
          return idx + ~0.0
        j += 1
      return ~-1.0
  while k < n
    return k + ~0.0 if js_has_el?(o, k) && js_strict_eq(js_el(o, k), x)
    k += 1
  ~-1.0

-> js_arr_includes(this, args)
  o = js_to_obj(this)
  n = js_len_of(o)
  return false if n == 0
  x = js_arg(args, 0)
  k = js_rel_index(js_arg(args, 1), n, 0)
  while k < n
    return true if js_same_value_zero(js_el(o, k), x)
    k += 1
  false

# Arrays being joined (a cycle joins as the empty string, as engines do).
JS_JOIN_GUARD = []

-> js_arr_join(this, sep_v)
  # Ultra-fast single-pass flat join for plain dense string arrays (zero StringBuffer overhead!)
  sep_done = false
  sep = ","
  if js_array?(this) && (js_array_flags(this) & 15) == JS_AF_ARRAY && JS_JOIN_GUARD.size == 0
    sep = sep_v == nil ? "," : (js_string?(sep_v) ? sep_v : js_to_string(sep_v))
    sep_done = true
    return "" if this.size == 0
    res = jit_arr_join_flat(this, sep)
    return res if res != nil
    return this.join(sep) if jsr_all_flat_strs(wvalue_bits(this) ## i64) != 0
  o = js_to_obj(this)
  n = js_len_of(o)
  sep = (sep_v == nil ? "," : js_to_string(sep_v)) if !sep_done
  g = JS_JOIN_GUARD
  i = 0
  while i < g.size
    return "" if js_ident?(g[i], o)
    i += 1
  g.push(o)
  sb = StringBuffer()
  begin
    i = 0
    while i < n
      sb.append(sep) if i > 0
      v = js_el(o, i)
      sb.append(js_string?(v) ? v : js_to_string(v)) if !js_nullish?(v)
      i += 1
  rescue e
    g.pop
    ccall("w_value_free_w", sb)
    raise e
  g.pop
  r = sb.to_s
  ccall("w_value_free_w", sb)
  r

-> js_arr_to_string(this)
  o = js_to_obj(this)
  j = jget(o, "join")
  return js_call_arr(j, o, JS_NO_ARGS) if js_callable?(j)
  js_object_to_string(o)

-> js_arr_to_locale_string(this)
  o = js_to_obj(this)
  n = js_len_of(o)
  parts = []
  i = 0
  while i < n
    v = js_el(o, i)
    parts.push(js_nullish?(v) ? "" : js_to_string(js_invoke(v, "toLocaleString", JS_NO_ARGS)))
    i += 1
  parts.join(",")

-> js_arr_push(this, args)
  if js_growable_array?(this)
    if JS_ARENA_STATE[0] != 0 && jsr_arr_is_arena(wvalue_bits(this) ## i64) != 0
      i = 0
      n_out = this.size ## i64
      while i < args.size
        n_out = js_arena_push_one(this, args[i])
        i += 1
      return n_out + ~0.0
    i = 0
    while i < args.size
      this.push(args[i])
      i += 1
    return this.size + ~0.0
  o = js_to_obj(this)
  n = js_len_of(o)
  js_throw_type("Pushing " + args.size.to_s + " elements on an array-like of length " + n.to_s + " is disallowed") if n + args.size > 9007199254740991
  i = 0
  while i < args.size
    js_put_el_set(o, n, args[i])
    n += 1
    i += 1
  js_set_len(o, n)
  n + ~0.0

-> js_arr_pop(this)
  if js_plain_array?(this) && (js_array_flags(this) & JS_AF_HOLES) == 0
    return nil if this.size == 0
    v = js_arr_elem(this, this.size - 1)
    this.pop
    return v
  o = js_to_obj(this)
  n = js_len_of(o)
  if n == 0
    js_set_len(o, 0)
    return nil
  v = js_el(o, n - 1)
  js_delete(o, (n - 1).to_s, true)
  js_set_len(o, n - 1)
  v

-> js_arr_shift(this)
  if js_plain_array?(this) && (js_array_flags(this) & JS_AF_HOLES) == 0
    return nil if this.size == 0
    v = js_arr_elem(this, 0)
    this.shift
    return v
  o = js_to_obj(this)
  n = js_len_of(o)
  if n == 0
    js_set_len(o, 0)
    return nil
  first = js_el(o, 0)
  k = 1
  while k < n
    if js_has_el?(o, k)
      js_put_el_set(o, k - 1, js_el(o, k))
    else
      js_delete(o, (k - 1).to_s, true)
    k += 1
  js_delete(o, (n - 1).to_s, true)
  js_set_len(o, n - 1)
  first

-> js_arr_unshift(this, args)
  if js_growable_array?(this)
    i = args.size - 1
    while i >= 0
      this.unshift(args[i])
      i -= 1
    return this.size + ~0.0
  o = js_to_obj(this)
  n = js_len_of(o)
  c = args.size
  if c > 0
    js_throw_type("Unshifting " + c.to_s + " elements on an array-like of length " + n.to_s + " is disallowed") if n + c > 9007199254740991
    k = n
    while k > 0
      if js_has_el?(o, k - 1)
        js_put_el_set(o, k + c - 1, js_el(o, k - 1))
      else
        js_delete(o, (k + c - 1).to_s, true)
      k -= 1
    j = 0
    while j < c
      js_put_el_set(o, j, args[j])
      j += 1
  js_set_len(o, n + c)
  (n + c) + ~0.0

# Is this array's species the intrinsic Array (so a plain copy is the right result)?
-> js_default_species?(o)
  return false if !js_plain_array?(o)
  r = js_realm()
  c = r.array_proto.get_own("constructor")
  c == r.intrinsic("Array") && jget(c, SYM_SPECIES) == c

-> js_arr_slice(this, args)
  o = js_to_obj(this)
  n = js_len_of(o)
  a = js_rel_index(js_arg(args, 0), n, 0)
  b = js_rel_index(js_arg(args, 1), n, n)
  if js_default_species?(o) && b <= o.size && (js_array_flags(o) & JS_AF_HOLES) == 0
    return js_mark_array(b > a ? js_arr_copy(o, a, b - a) : [])
  res = js_species_create(o, b > a ? b - a : 0)
  k = a
  j = 0
  while k < b
    js_create_data(res, j.to_s, js_el(o, k)) if js_has_el?(o, k)
    k += 1
    j += 1
  js_set_len(res, j)
  res

-> js_arr_splice(this, args)
  o = js_to_obj(this)
  n = js_len_of(o)
  start = js_rel_index(js_arg(args, 0), n, 0)
  dc = 0
  if args.size == 0
    dc = 0
  elsif args.size == 1
    dc = n - start
  else
    d = js_to_integer(args[1])
    d = ~0.0 if d < ~0.0
    dc = d > (n - start) + ~0.0 ? n - start : d.to_i
  items = args.size > 2 ? js_arr_copy(args, 2, args.size - 2) : JS_NO_ARGS
  js_throw_type("Splice result length exceeds 2^53-1") if n + items.size - dc > 9007199254740991
  if js_default_species?(o) && (js_array_flags(o) & JS_AF_HOLES) == 0 && js_array_protos_clean?
    el = o
    # copies: avoid Array#slice views and keep storage independent of pushes below
    removed = js_arr_copy(el, start, dc)
    tail = js_arr_copy(el, start + dc, el.size - start - dc)
    while el.size > start
      el.pop
    i = 0
    while i < items.size
      el.push(items[i])
      i += 1
    i = 0
    while i < tail.size
      el.push(tail[i])
      i += 1
    return js_mark_array(removed)
  removed = js_species_create(o, dc)
  k = 0
  while k < dc
    js_create_data(removed, k.to_s, js_el(o, start + k)) if js_has_el?(o, start + k)
    k += 1
  js_set_len(removed, dc)
  ic = items.size
  if ic < dc
    k = start
    while k < n - dc
      if js_has_el?(o, k + dc)
        js_put_el_set(o, k + ic, js_el(o, k + dc))
      else
        js_delete(o, (k + ic).to_s, true)
      k += 1
    k = n
    while k > n - dc + ic
      js_delete(o, (k - 1).to_s, true)
      k -= 1
  elsif ic > dc
    k = n - dc
    while k > start
      if js_has_el?(o, k + dc - 1)
        js_put_el_set(o, k + ic - 1, js_el(o, k + dc - 1))
      else
        js_delete(o, (k + ic - 1).to_s, true)
      k -= 1
  j = 0
  while j < ic
    js_put_el_set(o, start + j, items[j])
    j += 1
  js_set_len(o, n - dc + ic)
  removed

-> js_arr_concat(this, args)
  o = js_to_obj(this)
  a = js_species_create(o, 0)
  plain = js_plain_array?(a) && a.size == 0
  n = 0
  holes = false
  j = -1
  while j < args.size
    x = j < 0 ? o : args[j]
    if js_spreadable?(x)
      len = js_len_of(x)
      js_throw_type("Concatenated length exceeds 2^53-1") if n + len > 9007199254740991
      if plain && js_array?(x) && (js_array_flags(x) & JS_AF_SPARSE) == 0
        k = 0
        while k < x.size
          e = x[k]
          if e == JS_HOLE
            if js_has_el?(x, k)
              e = js_el(x, k)
            else
              holes = true
          a.push(e)
          k += 1
        n += x.size
      else
        k = 0
        while k < len
          if js_has_el?(x, k)
            if plain
              while a.size < n + k
                a.push(JS_HOLE)
                holes = true
              a.push(js_el(x, k))
            else
              js_create_data(a, (n + k).to_s, js_el(x, k))
          k += 1
        n += len
    else
      js_throw_type("Concatenated length exceeds 2^53-1") if n >= 9007199254740991
      if plain
        while a.size < n
          a.push(JS_HOLE)
          holes = true
        a.push(x)
      else
        js_create_data(a, n.to_s, x)
      n += 1
    j += 1
  if plain
    while a.size < n
      a.push(JS_HOLE)
      holes = true
    js_mark_holey(a) if holes
    return a
  js_set_len(a, n)
  a

-> js_spreadable?(x)
  return false if !js_object?(x)
  s = jget(x, SYM_IS_CONCAT_SPREADABLE)
  return js_to_boolean(s) if s != nil
  js_is_array(x)

-> js_arr_reverse(this)
  o = js_to_obj(this)
  if js_plain_array?(o) && (js_array_flags(o) & JS_AF_HOLES) == 0
    el = o
    i = 0
    j = el.size - 1
    while i < j
      t = el[i]
      el[i] = el[j]
      el[j] = t
      i += 1
      j -= 1
    return o
  n = js_len_of(o)
  lo = 0
  hi = n - 1
  while lo < hi
    # HasProperty then Get, lower before upper (§23.1.3.26): a getter may change the array
    le = js_has_el?(o, lo)
    lv = le ? js_el(o, lo) : nil
    he = js_has_el?(o, hi)
    hv = he ? js_el(o, hi) : nil
    if le && he
      js_put_el_set(o, lo, hv)
      js_put_el_set(o, hi, lv)
    elsif !le && he
      js_put_el_set(o, lo, hv)
      js_delete(o, hi.to_s, true)
    elsif le && !he
      js_delete(o, lo.to_s, true)
      js_put_el_set(o, hi, lv)
    lo += 1
    hi -= 1
  o

-> js_arr_fill(this, args)
  o = js_to_obj(this)
  n = js_len_of(o)
  v = js_arg(args, 0)
  a = js_rel_index(js_arg(args, 1), n, 0)
  b = js_rel_index(js_arg(args, 2), n, n)
  k = a
  if js_plain_array?(o)
    while k < b && k < o.size
      o[k] = v
      k += 1
  while k < b
    js_put_el_set(o, k, v)
    k += 1
  o

-> js_arr_copy_within(this, args)
  o = js_to_obj(this)
  n = js_len_of(o)
  to = js_rel_index(js_arg(args, 0), n, 0)
  from = js_rel_index(js_arg(args, 1), n, 0)
  fin = js_rel_index(js_arg(args, 2), n, n)
  count = fin - from
  count = n - to if n - to < count
  return o if count <= 0
  if from < to && to < from + count
    # overlapping, moving right: copy from the end (§23.1.3.4 step 16)
    k = count - 1
    while k >= 0
      if js_has_el?(o, from + k)
        js_put_el_set(o, to + k, js_el(o, from + k))
      else
        js_delete(o, (to + k).to_s, true)
      k -= 1
    return o
  k = 0
  while k < count
    if js_has_el?(o, from + k)
      js_put_el_set(o, to + k, js_el(o, from + k))
    else
      js_delete(o, (to + k).to_s, true)
    k += 1
  o

# ---- Fast Native Stable Numeric Sort (LLVM-compiled, zero allocations, 100% spec-exact!) ----

# Check if a raw WValue is a non-NaN biased double (1) or not (0).
fn jsr_is_nonnan_num(v) (i64) i64
  ll <<~IR
    %u = sub i64 %v, 281474976710656
    %ok1 = icmp ult i64 %u, -4503599627370495
    %d = bitcast i64 %u to double
    %ord = fcmp ord double %d, %d
    %ok = and i1 %ok1, %ord
    %r = zext i1 %ok to i64
    ret i64 %r
  IR

fn jsr_all_nonnan_nums(slots, n) (i64 i64) i64
  i = 0
  while i < n
    return 0 if jsr_is_nonnan_num(jsr_slot_u64(slots, i)) == 0
    i += 1
  1

# Compare two non-NaN biased double WValues: returns 1 if f64(a) < f64(b), else 0 (handles -0.0 == +0.0).
fn jsr_wval_lt(a, b) (i64 i64) i64
  ll <<~IR
    %ua = sub i64 %a, 281474976710656
    %ub = sub i64 %b, 281474976710656
    %da = bitcast i64 %ua to double
    %db = bitcast i64 %ub to double
    %c = fcmp olt double %da, %db
    %r = zext i1 %c to i64
    ret i64 %r
  IR

fn jsr_slot_u64(slots, i) (i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %slots to ptr
    %p = getelementptr i64, ptr %base, i64 %i
    %v = load i64, ptr %p, align 8
    ret i64 %v
  IR

fn jsr_slot_set_u64(slots, i, v) (i64 i64 i64) i64
  ll <<~IR
    %base = inttoptr i64 %slots to ptr
    %p = getelementptr i64, ptr %base, i64 %i
    store i64 %v, ptr %p, align 8
    ret i64 0
  IR

# Bottom-up stable merge sort on raw WValue* slots of non-NaN doubles (dir=1 asc, dir=-1 desc).
# Uses insertion sort for runs of 32, then ping-pong merges between `slots` and `tmp`!
fn jsr_sort_f64_raw(slots, tmp, n, dir) (i64 i64 i64 i64) i64
  # Pass 1: insertion sort each run of size 32 directly in `slots`
  run = 32
  lo = 0
  while lo < n
    hi = lo + run
    hi = n if hi > n
    i = lo + 1
    while i < hi
      kv = jsr_slot_u64(slots, i)
      j = i - 1
      if dir > 0
        while j >= lo && jsr_wval_lt(kv, jsr_slot_u64(slots, j)) != 0
          jsr_slot_set_u64(slots, j + 1, jsr_slot_u64(slots, j))
          j -= 1
      else
        while j >= lo && jsr_wval_lt(jsr_slot_u64(slots, j), kv) != 0
          jsr_slot_set_u64(slots, j + 1, jsr_slot_u64(slots, j))
          j -= 1
      jsr_slot_set_u64(slots, j + 1, kv)
      i += 1
    lo += run
  return 0 if n <= run
  # Pass 2: bottom-up ping-pong merge (zero allocations!)
  src = slots
  dst = tmp
  width = run
  while width < n
    step = width + width
    lo = 0
    while lo < n
      mid = lo + width
      hi = lo + step
      hi = n if hi > n
      if mid >= hi
        k = lo
        while k < hi
          jsr_slot_set_u64(dst, k, jsr_slot_u64(src, k))
          k += 1
      else
        alast = jsr_slot_u64(src, mid - 1)
        bfirst = jsr_slot_u64(src, mid)
        ordered = dir > 0 ? (jsr_wval_lt(bfirst, alast) == 0) : (jsr_wval_lt(alast, bfirst) == 0)
        if ordered
          k = lo
          while k < hi
            jsr_slot_set_u64(dst, k, jsr_slot_u64(src, k))
            k += 1
        else
          i = lo
          j = mid
          k = lo
          if dir > 0
            while i < mid && j < hi
              vi = jsr_slot_u64(src, i)
              vj = jsr_slot_u64(src, j)
              if jsr_wval_lt(vj, vi) != 0
                jsr_slot_set_u64(dst, k, vj)
                j += 1
              else
                jsr_slot_set_u64(dst, k, vi)
                i += 1
              k += 1
          else
            while i < mid && j < hi
              vi = jsr_slot_u64(src, i)
              vj = jsr_slot_u64(src, j)
              if jsr_wval_lt(vi, vj) != 0
                jsr_slot_set_u64(dst, k, vj)
                j += 1
              else
                jsr_slot_set_u64(dst, k, vi)
                i += 1
              k += 1
          while i < mid
            jsr_slot_set_u64(dst, k, jsr_slot_u64(src, i))
            i += 1
            k += 1
          while j < hi
            jsr_slot_set_u64(dst, k, jsr_slot_u64(src, j))
            j += 1
            k += 1
      lo += step
    sw = src
    src = dst
    dst = sw
    width = step
  if src != slots
    k = 0
    while k < n
      jsr_slot_set_u64(slots, k, jsr_slot_u64(src, k))
      k += 1
  0

# Detect pure 2-arg numeric subtraction comparator: `(a, b) => a - b` (1) or `(a, b) => b - a` (-1), else 0.
-> js_sort_cmp_dir(cmp)
  return 0 if !cmp.is_a?(JS:Function) || cmp.code == nil || (cmp.code.flags & CODE_CLASS) != 0
  jf = cmp.code.node
  return 0 if !jf.is_a?(JaFunc) || !jf.simple || jf.free.size > 0 || jf.params.size != 2
  n = jf.node
  re = nil
  if jf.arrow && n.has?(F_EXPR_BODY)
    re = n.b
  elsif n.b.is_a?(Array) && n.b.size == 1 && n.b[0].kind == :return
    re = n.b[0].a
  return 0 if re == nil || re.kind != :binary || re.str != "-"
  return 0 if re.a.kind != :ident || re.b.kind != :ident || re.a.x == nil || re.b.x == nil
  ba = re.a.x.binding
  bb = re.b.x.binding
  p0 = jf.params[0]
  p1 = jf.params[1]
  return 1 if ba == p0 && bb == p1
  return -1 if ba == p1 && bb == p0
  0

# Reusable scratch buffer for native numeric sort (grown on demand).
JS_SORT_SCRATCH = [i64[4096]]

-> js_sort_dense_fast?(o, cmp)
  return false if cmp == nil || !js_plain_array?(o)
  ab = wvalue_bits(o) ## i64
  return false if (jsr_aflags(ab) & 15) != JS_AF_ARRAY
  n = o.size
  return true if n < 2
  dir = js_sort_cmp_dir(cmp)
  return false if dir == 0
  # Require WArray start == 0 so slots[0..n-1] are contiguous at slots_ptr
  st = jsr_arr_start(ab)
  return false if st != 0
  slots = jsr_arr_slots_ptr(ab)
  return false if jsr_all_nonnan_nums(slots, n) == 0
  buf = JS_SORT_SCRATCH[0]
  if buf.size < n
    buf = i64[n]
    JS_SORT_SCRATCH[0] = buf
  tmp = jsr_arr_slots_ptr(wvalue_bits(buf) ## i64)
  if !jit_sort_f64_arm64(slots, tmp, n, dir)
    jsr_sort_f64_raw(slots, tmp, n, dir)
  true

fn jsr_arr_slots_ptr(arr_bits) (i64) i64
  ll <<~IR
    %p = and i64 %arr_bits, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 16
    %s = load i64, ptr %a, align 8
    ret i64 %s
  IR

fn jsr_arr_start(arr_bits) (i64) i64
  ll <<~IR
    %p = and i64 %arr_bits, 140737488355312
    %q = inttoptr i64 %p to ptr
    %a = getelementptr i8, ptr %q, i64 4
    %s = load i32, ptr %a, align 4
    %r = sext i32 %s to i64
    ret i64 %r
  IR

# Stable merge sort with a JS comparator; undefined last (holes are dropped by the caller).
-> js_sort_values(vals, cmp)
  defined = []
  undef = 0
  i = 0
  while i < vals.size
    if vals[i] == nil
      undef += 1
    else
      defined.push(vals[i])
    i += 1
  sorted = js_merge_sort(defined, cmp)
  while undef > 0
    sorted.push(nil)
    undef -= 1
  sorted

-> js_sort_cmp(a, b, cmp)
  if cmp == nil
    return js_str_cmp(a, b) if js_string?(a) && js_string?(b)
    if js_number?(a) && js_number?(b) && js_int_like?(a) && js_int_like?(b) && a >= ~0.0 && b >= ~0.0 && js_digits_eq(a, b)
      return a < b ? -1 : (a > b ? 1 : 0)
    sa = js_to_string(a)
    sb = js_to_string(b)
    return js_str_cmp(sa, sb)
  v = js_to_number(js_call(cmp, nil, 2, a, b, nil, nil, nil))
  return 0 if v != v
  v < ~0.0 ? -1 : (v > ~0.0 ? 1 : 0)

-> js_int_like?(x)
  x == Math.floor(x) && x < ~1.0e15

# Same number of decimal digits: then numeric order equals string order.
-> js_digits_eq(a, b)
  js_ndigits(a) == js_ndigits(b)

-> js_ndigits(x)
  n = 1
  t = ~10.0
  while x >= t
    n += 1
    t = t * ~10.0
  n

-> js_merge_sort(a, cmp)
  n = a.size
  return a if n < 2
  if n <= 10
    # insertion sort for short runs
    out = a.dup
    i = 1
    while i < n
      x = out[i]
      j = i - 1
      while j >= 0 && js_sort_cmp(out[j], x, cmp) > 0
        out[j + 1] = out[j]
        j -= 1
      out[j + 1] = x
      i += 1
    return out
  mid = n / 2
  l = js_merge_sort(js_arr_copy(a, 0, mid), cmp)
  rr = js_merge_sort(js_arr_copy(a, mid, n - mid), cmp)
  out = Array.new(n, nil)
  i = 0
  j = 0
  k = 0
  while i < l.size && j < rr.size
    if js_sort_cmp(rr[j], l[i], cmp) < 0
      out[k] = rr[j]
      j += 1
    else
      out[k] = l[i]
      i += 1
    k += 1
  while i < l.size
    out[k] = l[i]
    i += 1
    k += 1
  while j < rr.size
    out[k] = rr[j]
    j += 1
    k += 1
  out

-> js_check_cmp(cmp)
  js_throw_type("The comparison function must be either a function or undefined") if cmp != nil && !js_callable?(cmp)

-> js_arr_sort(this, cmp)
  js_check_cmp(cmp)
  return this if js_sort_dense_fast?(this, cmp)
  o = js_to_obj(this)
  n = js_len_of(o)
  vals = []
  k = 0
  while k < n
    vals.push(js_el(o, k)) if js_has_el?(o, k)
    k += 1
  sorted = js_sort_values(vals, cmp)
  k = 0
  while k < sorted.size
    js_put_el_set(o, k, sorted[k])
    k += 1
  while k < n
    js_delete(o, k.to_s, true)
    k += 1
  o

# FlattenIntoArray (§23.1.3.13.1): appends o's elements (flattened depth levels) to out
# from index start; returns the next index.
-> js_arr_flat_into(out, o, depth, n, start)
  n = js_len_of(o) if n < 0
  t = start
  k = 0
  while k < n
    if js_has_el?(o, k)
      v = js_el(o, k)
      if depth > 0 && js_is_array(v)
        t = js_arr_flat_into(out, v, depth - 1, -1, t)
      else
        js_throw_type("Flattened array exceeds 2^53-1 elements") if t >= 9007199254740991
        js_create_data(out, t.to_s, v)
        t += 1
    k += 1
  t

-> js_arr_flat(this, d)
  o = js_to_obj(this)
  n = js_len_of(o)
  depth = d == nil ? ~1.0 : js_to_integer(d)
  depth = ~0.0 if depth < ~0.0
  dd = depth > ~1000000.0 ? 1000000 : depth.to_i
  out = js_species_create(o, 0)
  js_arr_flat_into(out, o, dd, n, 0)
  out

-> js_arr_flat_map(this, args)
  o = js_to_obj(this)
  n = js_len_of(o)
  f = js_fn_arg(args, 0, "flatMap")
  t = js_arg(args, 1)
  out = js_species_create(o, 0)
  ti = 0
  k = 0
  while k < n
    if js_has_el?(o, k)
      v = js_call(f, t, 3, js_el(o, k), k + ~0.0, o, nil, nil)
      if js_is_array(v)
        ti = js_arr_flat_into(out, v, 0, -1, ti)
      else
        js_create_data(out, ti.to_s, v)
        ti += 1
    k += 1
  out

-> js_arr_values_list(o)
  n = js_len_of(o)
  js_throw_range("Invalid array length") if n > 4294967295
  out = Array.new(n, nil)
  k = 0
  while k < n
    out[k] = js_el(o, k)
    k += 1
  out

-> js_arr_with(this, idx, v)
  o = js_to_obj(this)
  n = js_len_of(o)
  i = js_to_integer(idx)
  i = i + n if i < ~0.0
  js_throw_range("Invalid index : " + js_number_to_s(js_to_integer(idx))) if i < ~0.0 || i >= n + ~0.0
  js_throw_range("Invalid array length") if n > 4294967295
  vals = Array.new(n, nil)
  k = 0
  while k < n
    vals[k] = k == i.to_i ? v : js_el(o, k)
    k += 1
  js_mark_array(vals)

-> js_arr_to_spliced(this, args)
  o = js_to_obj(this)
  n = js_len_of(o)
  start = js_rel_index(js_arg(args, 0), n, 0)
  skip = 0
  if args.size == 0
    skip = 0
  elsif args.size == 1
    skip = n - start
  else
    d = js_to_integer(args[1])
    d = ~0.0 if d < ~0.0
    skip = d > (n - start) + ~0.0 ? n - start : d.to_i
  ins = args.size > 2 ? args.size - 2 : 0
  nl = n + ins - skip
  js_throw_type("Invalid array length") if nl > 9007199254740991
  js_throw_range("Invalid array length") if nl > 4294967295
  out = []
  k = 0
  while k < start
    out.push(js_el(o, k))
    k += 1
  j = 2
  while j < args.size
    out.push(args[j])
    j += 1
  k = start + skip
  while k < n
    out.push(js_el(o, k))
    k += 1
  js_mark_array(out)

-> js_arr_to_sorted(this, cmp)
  js_check_cmp(cmp)
  o = js_to_obj(this)
  vals = js_arr_values_list(o)
  js_mark_array(js_sort_values(vals, cmp))

-> js_arr_to_reversed(this)
  o = js_to_obj(this)
  n = js_len_of(o)
  js_throw_range("Invalid array length") if n > 4294967295
  out = Array.new(n, nil)
  k = 0
  while k < n
    out[k] = js_el(o, n - 1 - k)
    k += 1
  js_mark_array(out)

-> js_arr_at(this, idx)
  o = js_to_obj(this)
  n = js_len_of(o)
  i = js_to_integer(idx)
  i = i + n if i < ~0.0
  return nil if i < ~0.0 || i >= n + ~0.0
  js_el(o, i.to_i)

+ ArrayProto < JS:Special
  -> new(@shape, @cls)
    @ext = nil
    @internal = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_EXOTIC)

  -> define_own_property(key, desc)
    if key.is_a?(String)
      if key == "length"
        cur_d = get_own_property("length")
        cur_len = cur_d != nil && js_number?(cur_d.value) ? cur_d.value.to_i : 0
        cur_w = cur_d != nil && cur_d.writable == true
        len = -1
        if desc.has_value
          len = js_to_uint32(desc.value)
          n = js_to_number(desc.value)
          js_throw_range("Invalid array length") if len.to_f != n
        return false if desc.accessor? || desc.configurable == true || desc.enumerable == true
        return false if desc.writable == true && !cur_w
        if len >= 0 && len != cur_len
          return false if !cur_w
          if len < cur_len
            ks = own_keys
            sidx = []
            ks.each ->(k)
              if k.is_a?(String) && js_array_index?(k)
                idx = k.to_i
                sidx.push(idx) if idx >= len
            js_sort_ints_desc(sidx)
            i = 0
            while i < sidx.size
              idx = sidx[i]
              if !delete_own(idx.to_s)
                nd = JS:PropDesc.new
                nd.value = (idx + 1).to_f
                nd.has_value = true
                nd.writable = false if desc.writable == false
                super("length", nd)
                return false
              i += 1
          nd = JS:PropDesc.new
          nd.value = len.to_f
          nd.has_value = true
          nd.writable = false if desc.writable == false
          return super("length", nd)
        return super("length", desc)
      if js_array_index?(key)
        idx = key.to_i
        cur_d = get_own_property("length")
        cur_len = cur_d != nil && js_number?(cur_d.value) ? cur_d.value.to_i : 0
        cur_w = cur_d != nil && cur_d.writable == true
        return false if idx >= cur_len && !cur_w
        ok = super(key, desc)
        return false if !ok
        if idx >= cur_len
          nd = JS:PropDesc.new
          nd.value = (idx + 1).to_f
          nd.has_value = true
          super("length", nd)
        return true
    super(key, desc)

  -> set(key, v, receiver = JS_HOLE)
    r = receiver == JS_HOLE ? self : receiver
    if r == self && key.is_a?(String) && (key == "length" || js_array_index?(key))
      d = get_own_property(key)
      if d != nil
        if d.accessor?
          return false if d.setter == nil
          js_call_arr(d.setter, self, [v])
          return true
        return false if d.writable != true
        nd = JS:PropDesc.new
        nd.value = v
        nd.has_value = true
        return define_own_property(key, nd)
      return define_own_property(key, JS:PropDesc.data(v, ATTR_DEFAULT))
    super(key, v, r)

js_install(->(r) js_install_array(r))

-> js_install_array(r)
  op = r.object_proto
  ap = JS:ArrayProto.new(js_root_shape(op, SP_INLINE, SP_IBASE), "Array")
  r.array_proto = ap
  js_mark_proto(ap)
  js_mark_proto(op)
  ap.define("length", ~0.0, ATTR_W)
  ac = r.constructor("Array", 1, ->(this, args, nt) js_array_ctor(args, nt), ap)
  r.method(ac, "isArray", 1, ->(this, args, nt) js_is_array(js_arg(args, 0)))
  r.method(ac, "of", 0, ->(this, args, nt) js_array_of(this, args))
  r.method(ac, "from", 1, ->(this, args, nt) js_array_from(this, js_arg(args, 0), js_arg(args, 1), js_arg(args, 2)))
  r.method(ac, "fromAsync", 1, ->(this, args, nt) js_array_from_async(this, js_arg(args, 0), js_arg(args, 1), js_arg(args, 2)))
  r.getter(ac, SYM_SPECIES, ->(this, args, nt) this)
  r.method(ap, "at", 1, ->(this, args, nt) js_arr_at(this, js_arg(args, 0)))
  r.method(ap, "concat", 1, ->(this, args, nt) js_arr_concat(this, args))
  r.method(ap, "copyWithin", 2, ->(this, args, nt) js_arr_copy_within(this, args))
  r.method(ap, "every", 1, ->(this, args, nt) js_arr_each(this, args, :every))
  r.method(ap, "some", 1, ->(this, args, nt) js_arr_each(this, args, :some))
  r.method(ap, "forEach", 1, ->(this, args, nt) js_arr_each(this, args, :each))
  r.method(ap, "map", 1, ->(this, args, nt) js_arr_each(this, args, :map))
  r.method(ap, "filter", 1, ->(this, args, nt) js_arr_each(this, args, :filter))
  r.method(ap, "fill", 1, ->(this, args, nt) js_arr_fill(this, args))
  r.method(ap, "find", 1, ->(this, args, nt) js_arr_find(this, args, false, false))
  r.method(ap, "findIndex", 1, ->(this, args, nt) js_arr_find(this, args, false, true))
  r.method(ap, "findLast", 1, ->(this, args, nt) js_arr_find(this, args, true, false))
  r.method(ap, "findLastIndex", 1, ->(this, args, nt) js_arr_find(this, args, true, true))
  r.method(ap, "flat", 0, ->(this, args, nt) js_arr_flat(this, js_arg(args, 0)))
  r.method(ap, "flatMap", 1, ->(this, args, nt) js_arr_flat_map(this, args))
  r.method(ap, "includes", 1, ->(this, args, nt) js_arr_includes(this, args))
  r.method(ap, "indexOf", 1, ->(this, args, nt) js_arr_index_of(this, args, false))
  r.method(ap, "lastIndexOf", 1, ->(this, args, nt) js_arr_index_of(this, args, true))
  r.method(ap, "join", 1, ->(this, args, nt) js_arr_join(this, js_arg(args, 0)))
  r.method(ap, "pop", 0, ->(this, args, nt) js_arr_pop(this))
  r.method(ap, "push", 1, ->(this, args, nt) js_arr_push(this, args))
  r.method(ap, "reduce", 1, ->(this, args, nt) js_arr_reduce(this, args, false))
  r.method(ap, "reduceRight", 1, ->(this, args, nt) js_arr_reduce(this, args, true))
  r.method(ap, "reverse", 0, ->(this, args, nt) js_arr_reverse(this))
  r.method(ap, "shift", 0, ->(this, args, nt) js_arr_shift(this))
  r.method(ap, "unshift", 1, ->(this, args, nt) js_arr_unshift(this, args))
  r.method(ap, "slice", 2, ->(this, args, nt) js_arr_slice(this, args))
  r.method(ap, "sort", 1, ->(this, args, nt) js_arr_sort(this, js_arg(args, 0)))
  r.method(ap, "splice", 2, ->(this, args, nt) js_arr_splice(this, args))
  r.method(ap, "toLocaleString", 0, ->(this, args, nt) js_arr_to_locale_string(this))
  ts = r.method(ap, "toString", 0, ->(this, args, nt) js_arr_to_string(this))
  r.set_intrinsic("%ArrayProto_toString%", ts)
  r.method(ap, "toReversed", 0, ->(this, args, nt) js_arr_to_reversed(this))
  r.method(ap, "toSorted", 1, ->(this, args, nt) js_arr_to_sorted(this, js_arg(args, 0)))
  r.method(ap, "toSpliced", 2, ->(this, args, nt) js_arr_to_spliced(this, args))
  r.method(ap, "with", 2, ->(this, args, nt) js_arr_with(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(ap, "keys", 0, ->(this, args, nt) js_array_iter(js_to_obj(this), :keys))
  r.method(ap, "entries", 0, ->(this, args, nt) js_array_iter(js_to_obj(this), :entries))
  vals = r.method(ap, "values", 0, ->(this, args, nt) js_array_iter(js_to_obj(this), :values))
  ap.define(SYM_ITERATOR, vals, BUILTIN_ATTRS)
  r.set_intrinsic("%ArrayProto_values%", vals)
  r.set_intrinsic("%Array.prototype.values%", vals)
  un = js_new_object(nil)
  ks = ["at", "copyWithin", "entries", "fill", "find", "findIndex", "findLast", "findLastIndex", "flat", "flatMap", "includes", "keys", "toReversed", "toSorted", "toSpliced", "values"]
  i = 0
  while i < ks.size
    un.define(ks[i], true)
    i += 1
  ap.define(SYM_UNSCOPABLES, un, ATTR_C)
  nil

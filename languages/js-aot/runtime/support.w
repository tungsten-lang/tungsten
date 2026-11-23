# runtime/support — entry points the translator emits that are not operators or
# property access: environments, literals, `this`, and running a script.

in JS

# ---- environments (JS:Env: @up then seven variables; JS:EnvN beyond seven) ----

-> js_env_get(e, i)
  return e.vars[i - 7] if i >= 7
  eb = wvalue_bits(e) ## i64
  wvalue_from_bits(jsr_ivar(eb, i + 1))

-> js_env_set(e, i, v)
  if i >= 7
    e.vars[i - 7] = v
    return v
  ccall("w_ivar_set_idx", e, i + 1, v)
  v

-> js_env_up(e)
  eb = wvalue_bits(e) ## i64
  wvalue_from_bits(jsr_ivar(eb, 0))

# A copy of a loop's environment for the next iteration (per-iteration let bindings).
-> js_env_copy(e)
  n = nil
  if e.is_a?(JS:EnvN)
    n = JS:EnvN.new(e.up, 0)
    n.vars = e.vars.dup
  else
    n = JS:Env.new(e.up)
  n.v0 = e.v0
  n.v1 = e.v1
  n.v2 = e.v2
  n.v3 = e.v3
  n.v4 = e.v4
  n.v5 = e.v5
  n.v6 = e.v6
  n

# ---- literals ----

# The final shape of an object literal with these keys (computed once per site).
-> js_lit_shape(keys)
  s = js_root_shape(js_realm().object_proto, OBJ_INLINE, OBJ_IBASE)
  i = 0
  while i < keys.size
    s = s.add(keys[i], ATTR_DEFAULT)
    i += 1
  s

# An object literal of up to six properties: one block.
-> js_lit(shape, a, b, c, d, e, g)
  o = JS:Object.new(shape)
  o.s0 = a
  o.s1 = b
  o.s2 = c
  o.s3 = d
  o.s4 = e
  o.s5 = g
  o

-> js_lit_n(shape, vals)
  o = JS:Object.new(shape)
  i = 0
  while i < vals.size
    o.slot_set(i, vals[i])
    i += 1
  o

-> js_define_literal(o, key, v)
  o.define(key, v, ATTR_DEFAULT)
  nil

-> js_mark_holey(a)
  ab = wvalue_bits(a) ## i64
  jsr_set_aflags(ab, JS_AF_ARRAY | JS_AF_HOLES)
  a

# A compiled unit's entry (runtime/units.w): fp(ctx, f, this, argc, a0..a3, more), all
# raw WValue bits.
fn jsu_call_entry(fp, ctx, f, th, argc, a0, a1, a2, a3, more) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ll <<~IR
    %fn = inttoptr i64 %fp to ptr
    %r = call i64 %fn(i64 %ctx, i64 %f, i64 %th, i64 %argc, i64 %a0, i64 %a1, i64 %a2, i64 %a3, i64 %more)
    ret i64 %r
  IR

# ---- the JS call stack (positions for Error.stack and host tools) ----

# The innermost running activation of tier 0 (each links to its caller), nil outside JS.
JS_CUR_ACT = [nil]
# ->() the stack lines, ->() [url, line, column]: set by tier 0.
JS_STACK_HOOK = [nil]
JS_LOCATION_HOOK = [nil]

-> js_stack_lines
  JS_STACK_HOOK[0] == nil ? "" : JS_STACK_HOOK[0].call()

-> js_top_location
  JS_LOCATION_HOOK[0] == nil ? ["", 1, 1] : JS_LOCATION_HOOK[0].call()

-> js_src_location(src, url, p)
  return "\[native code]" if src == nil
  lc = js_src_linecol(src, p)
  (url == nil ? "" : url) + ":" + lc[0].to_s + ":" + lc[1].to_s

# Line and column (1-based) of byte offset p; the newline index of the last few sources
# is kept (a stack walks frames of a few big scripts).
JS_LINE_CACHE = [[], []]

-> js_src_linecol(src, p)
  return [1, 1] if src == nil
  srcs = JS_LINE_CACHE[0]
  nls = nil
  ci = 0
  while ci < srcs.size && nls == nil
    nls = JS_LINE_CACHE[1][ci] if js_ident?(srcs[ci], src)
    ci += 1
  if nls == nil
    nls = []
    i = 0
    n = src.size
    while i < n
      nls.push(i) if src.byte_at(i) == 10
      i += 1
    if srcs.size >= 8
      srcs.shift
      JS_LINE_CACHE[1].shift
    srcs.push(src)
    JS_LINE_CACHE[1].push(nls)
  lo = 0
  hi = nls.size
  while lo < hi
    mid = (lo + hi) / 2
    if nls[mid] < p
      lo = mid + 1
    else
      hi = mid
  [lo + 1, lo == 0 ? p + 1 : p - nls[lo - 1]]

# ---- script-level lexical bindings (top-level let, const, class) ----

JS_LEXICAL = {}

-> js_lcell(name)
  c = JS_LEXICAL[name]
  if c == nil
    c = JS:GlobalCell.new(name)
    c.put(JS_HOLE, ATTR_W + ATTR_E)
    JS_LEXICAL[name] = c
  c

# Initializing a script-level let/const/class (its declaration runs).
-> js_linit(c, v, is_const)
  c.put(v, is_const ? ATTR_E : ATTR_W + ATTR_E)
  v

# Assigning one: TDZ before its declaration, TypeError for a const.
-> js_lset(c, v)
  js_throw_reference("Cannot access '" + c.name + "' before initialization") if c.value == JS_HOLE
  js_throw_type("Assignment to constant variable.") if (c.attrs & ATTR_W) == 0
  c.value = v
  v

# ---- this, calls, operators on objects ----

# A sloppy-mode function's this: undefined and null become the global object.
-> js_sloppy_this(t)
  return js_realm().global if t == nil || t == JS_NULL
  t

-> js_tonumeric(v)
  return v if js_number?(v)
  js_numeric_value(v)

# o[key](args)
-> js_call_computed(o, key, argc, a0, a1, a2, a3, more)
  f = js_getv(o, key)
  js_call(f, o, argc, a0, a1, a2, a3, more)

-> js_delete(o, key, strict)
  k = js_to_property_key(key)
  if js_array?(o)
    if k.is_a?(String) && js_array_index?(k)
      i = k.to_i
      if i < o.size && o[i] != JS_HOLE
        if js_array_sealed?(o)
          js_throw_type("Cannot delete property '" + k + "' of \[object Array]") if strict
          return false
        o[i] = JS_HOLE
        ab = wvalue_bits(o) ## i64
        jsr_set_aflags(ab, jsr_aflags(ab) | JS_AF_HOLES)
        return true
      x = js_array_slow_elem(o, k)
      return true if x == nil
      ok = x.delete_own(k)
      js_throw_type("Cannot delete property '" + k + "' of \[object Array]") if !ok && strict
      return ok
    if k == "length"
      js_throw_type("Cannot delete property 'length' of \[object Array]") if strict
      return false
    return true if (js_array_flags(o) & JS_AF_EXT) == 0
    ok = js_array_ext(o, false).delete_own(k)
    js_throw_type("Cannot delete property '" + js_to_display(js_key_display(k)) + "'") if !ok && strict
    return ok
  return true if !o.is_a?(JS:Base)
  ok = o.delete_own(k)
  js_throw_type("Cannot delete property '" + js_to_display(js_key_display(k)) + "'") if !ok && strict
  ok

-> js_in(key, o)
  js_throw_type("Cannot use 'in' operator to search for a key in " + js_to_display(o)) if !js_object?(o)
  k = js_to_property_key(key)
  return jhas_property?(o, k) if js_array?(o)
  js_has_property(o, k)

-> js_has_property(o, k)
  return false if o == nil
  o.has_property?(k)

# v instanceof f (§13.10.2): f's @@hasInstance when it is not Function.prototype's own.
-> js_instanceof(v, f)
  js_throw_type("Right-hand side of 'instanceof' is not an object") if !js_object?(f)
  h = js_get_method(f, SYM_HAS_INSTANCE)
  return js_truthy(js_call_arr(h, f, [v])) if h != nil && h != js_realm().intrinsics["%FunctionProto_hasInstance%"]
  js_throw_type("Right-hand side of 'instanceof' is not callable") if !js_callable?(f)
  js_ordinary_has_instance(f, v)

# ---- running a script ----

JS_EXIT = [0]

# After the script: flush output and exit (1 when an exception was uncaught).
JS_T0 = [clock_ms()]

-> js_finish
  js_realm().run_jobs
  << "(" + (clock_ms() - JS_T0[0]).to_s + " ms)" if Env.get("JSRUN_TIME", "") == "1"
  ccall("w_flush")
  if Env.get("JSRUN_PAUSE", "") == "1"
    # tools/memstat.sh --heap: hold the heap still for `heap` until killed
    ccall("w_eputs", "jsrun: paused")
    while true
      sleep(1)
  exit(JS_EXIT[0])

-> js_report_uncaught(e)
  v = js_error_value(e)
  # an error prints as toString and its stack (frames only, as JavaScriptCore keeps them)
  << "Uncaught " + js_inspect(v, 1)
  JS_EXIT[0] = 1
  nil

# Called by the entry of a function this program does not compile (partial builds).
-> js_tier0_only(i)
  js_throw_type("function " + i.to_s + " is not compiled in this build")

# The code descriptor of a function this program does not compile (partial builds; in a
# unit the host hands these over).
JS_CODE_AT = {}

-> js_code_at(i)
  c = JS_CODE_AT[i]
  if c == nil
    c = JS:Code.new("", 0, -1, 8)
    JS_CODE_AT[i] = c
  c

# ---- for-in (§14.7.5.9 EnumerateObjectProperties) ----

# The string keys a for-in over v visits: own enumerable keys first, then each
# prototype's, without duplicates (a non-enumerable own key still shadows). The loop
# checks each key is still present before visiting it.
-> js_for_in_keys(v)
  return [] if js_nullish?(v)
  o = js_object?(v) ? v : js_realm().wrap_primitive(v)
  seen = {}
  out = []
  while o != nil
    ks = jown_keys(o)
    i = 0
    while i < ks.size
      k = ks[i]
      if js_string?(k) && !seen.has_key?(k)
        seen[k] = true
        out.push(k) if jenumerable?(o, k)
      i += 1
    o = jproto(o)
  out

# ---- template literals ----

# The template object of a tagged template site (§13.2.8.4): a frozen array of the cooked
# strings with a frozen raw array, made once per site.
-> js_template_object(cooked, raw)
  c = js_mark_array(cooked)
  rw = js_mark_array(raw)
  js_array_ext(c, true).define("raw", rw, 0)
  js_array_freeze(rw)
  js_array_freeze(c)
  c

-> js_array_freeze(a)
  js_array_ext(a, true).define(JS_AK_FROZEN, true, 0)
  js_array_ext(a, true).define(JS_AK_LENRO, true, 0)
  js_array_ext(a, true).prevent_extensions
  nil

# ---- shared by both tiers (moved from tier0/walk.w) ----

# A substitution in a template literal: ToString, which a Symbol refuses.
-> js_template_string(v)
  return v if js_string?(v)
  js_to_string(v)

# CopyDataProperties (spread in object literals and rest patterns).
-> js_copy_data_properties(o, src, excluded)
  return o if js_nullish?(src)
  from = js_object?(src) ? src : js_realm().wrap_primitive(src)
  ks = jown_keys(from)
  j = 0
  while j < ks.size
    kk = ks[j]
    if !excluded.include?(kk) && jenumerable?(from, kk)
      o.define(kk, jget(from, kk, src), ATTR_DEFAULT)
    j += 1
  o

# SetFunctionName for a computed key (the static ones are named by the analysis).
-> js_set_fn_name(f, key, prefix)
  return nil if !f.is_a?(JS:Function)
  nm = key.is_a?(JS:Symbol) ? (key.description == nil ? "" : "\[" + key.description + "]") : js_to_string(key)
  nm = prefix + " " + nm if prefix != nil
  f.define("name", nm, ATTR_C)
  nil

-> js_priv_get(o, pn)
  js_throw_type("Cannot read private member " + pn.to_s + " from an object whose class did not declare it") if !o.is_a?(JS:Base)
  o.priv_get(pn)

-> js_priv_set(o, pn, v)
  js_throw_type("Cannot write private member " + pn.to_s + " to an object whose class did not declare it") if !o.is_a?(JS:Base)
  o.priv_set(pn, v)

-> js_bigint_literal(s)
  t = s
  base = 10
  if t.size > 2 && t.byte_at(0) == 48
    b = t.byte_at(1) | 32
    base = b == 120 ? 16 : (b == 111 ? 8 : (b == 98 ? 2 : 10))
    t = t.slice(2, t.size - 2) if base != 10
  v = 0
  i = 0
  while i < t.size
    v = v * base + js_digit(t.byte_at(i))
    i += 1
  JS:BigIntValue.new(v)

# ---- compiled code (tier 1): helpers the translator emits for the rarer constructs ----

# The unmapped arguments object of a compiled function (strict code or non-simple
# parameters; a mapped one keeps the function in tier 0).
-> js_args_object(argc, a0, a1, a2, a3, more)
  js_arguments(js_args_array(argc, a0, a1, a2, a3, more).dup, nil, false, nil, nil)

# A rest parameter: the arguments from index i on, as a JS array.
-> js_rest_args(i, argc, a0, a1, a2, a3, more)
  out = []
  j = i
  while j < argc
    out.push(j == 0 ? a0 : (j == 1 ? a1 : (j == 2 ? a2 : (j == 3 ? a3 : more[j]))))
    j += 1
  js_mark_array(out)

# new.target of the running function, taken (and cleared) once at its entry. Functions
# that never read it have CODE_NONT, so js_new does not set it for them.
-> js_take_nt
  v = JS_NEW_TARGET[0]
  JS_NEW_TARGET[0] = nil
  v

# for-in: is key k (from js_for_in_keys) still present when its turn comes?
-> js_for_in_has?(o, k)
  !js_object?(o) || jhas_property?(o, k)

# for-of: nil when v is an array iterated in place (its iterator is still the intrinsic
# one, which has no return method), else v's iterator record.
-> js_for_of_iter(v)
  return nil if js_array?(v) && js_array_iter_pristine?(v)
  js_get_iterator(v)

# The next value of a for-of (rec from js_for_of_iter, i the index for arrays), or
# JS_ITER_DONE.
-> js_for_of_step(v, rec, i)
  if rec == nil
    return JS_ITER_DONE if i >= v.size
    return js_arr_elem(v, i)
  js_iter_step(rec)

-> js_for_of_close(rec)
  js_iter_close(rec) if rec != nil
  nil

-> js_for_of_close_quiet(rec)
  js_iter_close_quiet(rec) if rec != nil
  nil

# Array destructuring: the array itself when it is iterated in place, else an iterator
# record. js_pat_step reads element i (an array) or takes the next value (a record).
-> js_pat_iter(v)
  return v if js_array?(v) && js_array_iter_pristine?(v)
  js_get_iterator(v)

-> js_pat_step(it, i)
  if js_array?(it)
    return nil if i >= it.size
    return js_arr_elem(it, i)
  return nil if it.done
  x = js_iter_step(it)
  x == JS_ITER_DONE ? nil : x

# An elision ([a, , b]): consumes a value of an iterator.
-> js_pat_skip(it)
  js_pat_step(it, 0) if !js_array?(it)
  nil

-> js_pat_rest(it, i)
  out = []
  if js_array?(it)
    while i < it.size
      out.push(js_arr_elem(it, i))
      i += 1
    return js_mark_array(out)
  while !it.done
    x = js_iter_step(it)
    out.push(x) if x != JS_ITER_DONE
  js_mark_array(out)

-> js_pat_close(it)
  js_iter_close(it) if !js_array?(it)
  nil

-> js_pat_close_quiet(it)
  js_iter_close_quiet(it) if !js_array?(it)
  nil

# Object destructuring of v (TypeError for undefined and null).
-> js_req_coercible(v)
  js_throw_type("Cannot destructure '" + js_to_display(v) + "' as it is " + (v == nil ? "undefined" : "null") + ".") if js_nullish?(v)
  v

# {...rest}: the own enumerable properties of v not named in used.
-> js_object_rest(v, used)
  js_copy_data_properties(js_new_object(js_realm().object_proto), v, used)

# get/set key(){} in an object literal: an accessor merged with the other half, if any.
-> js_lit_accessor(o, key, f, is_get)
  cur = o.get_own_property(key)
  g = is_get ? f : (cur != nil && cur.accessor? ? cur.getter : nil)
  st = is_get ? (cur != nil && cur.accessor? ? cur.setter : nil) : f
  o.define_accessor(key, g, st, ATTR_E + ATTR_C)
  nil

# __proto__: v in an object literal.
-> js_lit_proto(o, v)
  o.set_prototype_of(v) if js_object?(v) || v == JS_NULL
  nil

# #x in o
-> js_priv_in(o, pn)
  js_throw_type("Cannot use 'in' operator to search for a private field in a non-object") if !js_object?(o)
  o.is_a?(JS:Base) && o.priv_has?(pn)

# ---- classes (§15.7.14 ClassDefinitionEvaluation, as tier 0's wk_class) ----

# The constructor of a class (a JS:Method whose home is the new prototype object).
-> js_class_create(code, env, has_super, sup)
  r = js_realm()
  proto_parent = r.object_proto
  ctor_parent = r.function_proto
  if has_super
    if sup == JS_NULL
      proto_parent = nil
    else
      js_throw_type("Class extends value " + js_to_display_short(sup) + " is not a constructor or null") if !js_is_constructor?(sup)
      pp = jget(sup, "prototype")
      js_throw_type("Class extends value does not have valid prototype property " + js_to_display_short(pp)) if !js_object?(pp) && pp != JS_NULL
      proto_parent = pp == JS_NULL ? nil : pp
      ctor_parent = sup
  proto = js_new_object(proto_parent)
  f = js_method_closure(code, env, proto)
  f.set_prototype_of(ctor_parent) if ctor_parent != r.function_proto
  f.define("prototype", proto, 0)
  proto.define("constructor", f, ATTR_W + ATTR_C)
  f

-> js_home(f)
  f.home

# A public method or accessor of a class on target (the prototype, or the constructor).
-> js_class_method(target, key, fo, kind, computed)
  js_set_fn_name(fo, key, kind == "method" ? nil : kind) if computed
  if kind == "method"
    target.define(key, fo, ATTR_W + ATTR_C)
    return nil
  cur = target.get_own_property(key)
  g = kind == "get" ? fo : (cur != nil && cur.accessor? ? cur.getter : nil)
  sx = kind == "set" ? fo : (cur != nil && cur.accessor? ? cur.setter : nil)
  target.define_accessor(key, g, sx, ATTR_C)
  nil

# A private method or accessor: on the constructor (static) or for every instance.
-> js_class_priv_method(f, is_static, pn, fo, kind)
  if is_static
    if kind == "method"
      f.priv_add_method(pn, fo)
    else
      f.priv_add_accessor(pn, kind == "get" ? fo : nil, kind == "set" ? fo : nil)
    return nil
  f.privs = [] if f.privs == nil
  f.privs.push([pn, fo, kind])
  nil

-> js_class_add_field(f, key, init)
  f.fields = [] if f.fields == nil
  f.fields.push([key, init])
  nil

# A static field, defined once the class is complete (this = the constructor).
-> js_class_static_field(f, key, init)
  v = init == nil ? nil : js_call(init, f, 0, nil, nil, nil, nil, nil)
  if key.is_a?(JS:PrivateName)
    f.priv_add(key, v)
  else
    jdefine_own_or_throw(f, key, v)
  nil

# The default constructor of a class (§15.7.14 step 10).
-> js_default_ctor(fobj, this, nt, derived, argc, a0, a1, a2, a3, more)
  if derived
    parent = fobj.get_prototype_of
    js_throw_type("Super constructor " + js_to_display_short(parent) + " of anonymous class is not a constructor") if !js_is_constructor?(parent)
    obj = js_construct(parent, js_args_array(argc, a0, a1, a2, a3, more).dup, nt)
    js_init_fields(obj, fobj)
    return obj
  js_init_fields(this, fobj)
  this

# What a class constructor's [[Construct]] returns for `return r` (or the end, r nil)
# when its this is t.
-> js_ctor_result(r, t, derived)
  return r if js_object?(r)
  js_throw_type("Derived constructors may only return object or undefined") if derived && r != nil
  js_throw_reference("Must call super constructor in derived class before accessing 'this' or returning from derived constructor") if t == nil
  t

# super.x / super[x] in a method whose object is fo, with receiver this.
-> js_super_get(fo, key, this)
  p = jget_prototype_of(fo.home)
  return nil if p == JS_NULL
  jget(p, key, this)

-> js_super_set(fo, key, v, this, strict)
  p = jget_prototype_of(fo.home)
  ok = p == JS_NULL ? false : jset(p, key, v, this)
  js_throw_type("Cannot assign to read only property '" + js_to_display(js_key_display(key)) + "' of object") if !ok && strict
  v

# super(...args): the parent constructor's object (the caller binds this, then
# initializes fields).
-> js_super_construct(fo, nt, args)
  parent = fo.get_prototype_of
  js_throw_type("Super constructor " + js_to_display_short(parent) + " of anonymous class is not a constructor") if !js_is_constructor?(parent)
  js_construct(parent, args, nt)

# A second super() call (this already bound).
-> js_super_bound(cur)
  js_throw_reference("Super constructor may only be called once") if cur != nil
  nil

# Function.prototype.toString for compiled code: the script's text (one per program)
# and each code's span in it.
JS_SCRIPT_SOURCE = [nil]

-> js_set_source(src)
  JS_SCRIPT_SOURCE[0] = src
  JS_FN_SOURCE_HOOK[0] = ->(f) js_code_source(f)
  nil

-> js_code_span(c, start, fin)
  c.start = start
  c.fin = fin
  c

-> js_code_source(f)
  c = f.code
  s = JS_SCRIPT_SOURCE[0]
  return nil if s == nil || c.fin <= c.start
  s.slice(c.start, c.fin - c.start)

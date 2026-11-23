# runtime/support — entry points the translator emits that are not operators or
# property access: environments, literals, `this`, and running a script.

in JS

# ---- environments (JS:Env: @up then seven variables; JS:EnvN beyond seven) ----

-> js_env_get(e, i)
  eb = wvalue_bits(e) ## i64
  wvalue_from_bits(jsr_ivar(eb, i + 1))

-> js_env_set(e, i, v)
  ccall("w_ivar_set_idx", e, i + 1, v)
  v

-> js_env_up(e)
  eb = wvalue_bits(e) ## i64
  wvalue_from_bits(jsr_ivar(eb, 0))

# A copy of a loop's environment for the next iteration (per-iteration let bindings).
-> js_env_copy(e)
  if e.is_a?(JS:EnvN)
    n = JS:EnvN.new(e.up, 0)
    n.vars = e.vars.dup
    return n
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
  return v if v.is_a?(JS:BigIntValue)
  js_to_number(v)

# o[key](args)
-> js_call_computed(o, key, argc, a0, a1, a2, a3, more)
  f = js_getv(o, key)
  js_call(f, o, argc, a0, a1, a2, a3, more)

-> js_delete(o, key, strict)
  k = js_to_property_key(key)
  if js_array?(o)
    if k.is_a?(String) && js_array_index?(k)
      i = k.to_i
      if i < o.size
        o[i] = JS_HOLE
        ab = wvalue_bits(o) ## i64
        jsr_set_aflags(ab, jsr_aflags(ab) | JS_AF_HOLES)
      return true
    return false if k == "length"
    return true if (js_array_flags(o) & JS_AF_EXT) == 0
    return js_array_ext(o, false).delete_own(k)
  return true if !o.is_a?(JS:Base)
  ok = o.delete_own(k)
  js_throw_type("Cannot delete property '" + js_to_display(js_key_display(k)) + "'") if !ok && strict
  ok

-> js_in(key, o)
  js_throw_type("Cannot use 'in' operator to search for a key in " + js_to_display(o)) if !js_object?(o)
  k = js_to_property_key(key)
  if js_array?(o)
    return true if js_array_get(o, k) != nil || k == "length"
    return js_has_property(js_array_proto(o), k)
  js_has_property(o, k)

-> js_has_property(o, k)
  while o != nil
    return true if o.has_own?(k) || o.get_virtual(k) != JS_HOLE
    o = o.proto
  false

-> js_instanceof(v, f)
  js_throw_type("Right-hand side of 'instanceof' is not callable") if !js_callable?(f)
  return false if !js_object?(v)
  p = js_get_value(f, "prototype")
  js_throw_type("Function has non-object prototype in instanceof check") if !js_object?(p)
  o = js_array?(v) ? js_array_proto(v) : v.proto
  while o != nil
    return true if o == p
    o = o.proto
  false

# ---- running a script ----

JS_EXIT = [0]

# After the script: flush output and exit (1 when an exception was uncaught).
JS_T0 = [clock_ms()]

-> js_finish
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
  if v.is_a?(JS:Base)
    st = v.get("stack", v)
    << "Uncaught " + (js_string?(st) ? st : js_to_display(v))
  else
    << "Uncaught " + js_to_display(v)
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

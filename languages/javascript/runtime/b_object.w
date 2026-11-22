# blade/js/b_object — Object, Function, Boolean, Symbol, the Error types, global functions.

-> js_req_obj(v, what)
  js_throw_type(what + " called on non-object") if !v.is_a?(JsObject)
  v

# ToPropertyDescriptor
-> js_to_desc(v)
  js_throw_type("Property description must be an object: " + js_to_display(v)) if !v.is_a?(JsObject)
  d = JsPropDesc.new
  if v.has_property?("enumerable")
    d.enumerable = js_to_boolean(v.get("enumerable"))
  if v.has_property?("configurable")
    d.configurable = js_to_boolean(v.get("configurable"))
  if v.has_property?("value")
    d.value = v.get("value")
    d.has_value = true
  if v.has_property?("writable")
    d.writable = js_to_boolean(v.get("writable"))
  if v.has_property?("get")
    g = v.get("get")
    js_throw_type("Getter must be a function: " + js_to_display(g)) if g != nil && !(g.is_a?(JsObject) && g.callable?)
    d.getter = g
    d.has_get = true
  if v.has_property?("set")
    st = v.get("set")
    js_throw_type("Setter must be a function: " + js_to_display(st)) if st != nil && !(st.is_a?(JsObject) && st.callable?)
    d.setter = st
    d.has_set = true
  js_throw_type("Invalid property descriptor. Cannot both specify accessors and a value or writable attribute") if (d.has_get || d.has_set) && (d.has_value || d.writable != nil)
  d

# FromPropertyDescriptor
-> js_from_desc(d)
  return nil if d == nil
  o = JS_REALM[0].new_object
  if d.accessor?
    o.put_own("get", d.getter)
    o.put_own("set", d.setter)
  else
    o.put_own("value", d.value)
    o.put_own("writable", d.writable == true)
  o.put_own("enumerable", d.enumerable == true)
  o.put_own("configurable", d.configurable == true)
  o

-> js_define_property_or_throw(o, k, d)
  ok = o.define_own_property(k, d)
  js_throw_type("Cannot redefine property: " + js_key_display(k).to_s) if !ok
  o

-> js_object_define_properties(o, props)
  p = js_to_object(props)
  descs = []
  p.own_keys.each ->(k)
    pd = p.get_own_property(k)
    if pd != nil && pd.enumerable == true
      descs.push([k, js_to_desc(p.get(k, p))])
  descs.each ->(kd) js_define_property_or_throw(o, kd[0], kd[1])
  o

-> js_set_integrity(o, level)
  return o if !o.is_a?(JsObject)
  js_throw_type("Cannot prevent extensions") if !o.prevent_extensions
  o.own_keys.each ->(k)
    d = o.get_own_property(k)
    if d != nil
      nd = JsPropDesc.new
      nd.configurable = false
      nd.writable = false if level == :frozen && !d.accessor?
      o.define_own_property(k, nd)
  o

-> js_freeze(o)
  js_set_integrity(o, :frozen)

-> js_test_integrity(o, level)
  return true if !o.is_a?(JsObject)
  return false if o.is_extensible?
  o.own_keys.each ->(k)
    d = o.get_own_property(k)
    if d != nil
      return false if d.configurable == true
      return false if level == :frozen && !d.accessor? && d.writable == true
  true

-> js_own_enum_keys(o)
  out = []
  o.own_keys.each ->(k)
    if k.is_a?(String)
      d = o.get_own_property(k)
      out.push(k) if d != nil && d.enumerable == true
  out

-> js_object_keys(v, kind)
  o = js_to_object(v)
  r = JS_REALM[0]
  if kind == :keys && !o.proxy? && !(o.is_a?(JsArray)) && o.attrs == nil && o.getters == nil && o.class_name == "JsObject"
    return r.new_array(o.own_keys.select(->(k) k.is_a?(String)))
  out = []
  js_own_enum_keys(o).each ->(k)
    if kind == :keys
      out.push(k)
    elsif kind == :values
      out.push(o.get(k, o))
    else
      out.push(r.new_array([k, o.get(k, o)]))
  r.new_array(out)

-> js_object_assign(target, sources)
  to = js_to_object(target)
  sources.each ->(src)
    if !js_nullish?(src)
      from = js_to_object(src)
      from.own_keys.each ->(k)
        d = from.get_own_property(k)
        if d != nil && d.enumerable == true
          ok = to.set(k, from.get(k, from), to)
          js_set_failed(to, k) if !ok
  to

-> js_object_ctor(this, args, nt)
  r = JS_REALM[0]
  if nt != nil && nt != r.intrinsic("Object")
    return JsObject.new(r.proto_from(nt, "Object"), "Object")
  v = js_arg(args, 0)
  return r.new_object if js_nullish?(v)
  js_to_object(v)

-> js_object_create(p, props)
  js_throw_type("Object prototype may only be an Object or null: " + js_to_display(p)) if !(p.is_a?(JsObject) || p == JS_NULL)
  o = JsObject.new(p, "Object")
  js_object_define_properties(o, props) if props != nil
  o

-> js_object_set_proto(o, p)
  js_throw_type("Object.setPrototypeOf called on null or undefined") if js_nullish?(o)
  js_throw_type("Object prototype may only be an Object or null: " + js_to_display(p)) if !(p.is_a?(JsObject) || p == JS_NULL)
  return o if !o.is_a?(JsObject)
  js_throw_type("Cyclic __proto__ value") if !o.set_prototype_of(p)
  o

-> js_object_from_entries(it)
  o = JS_REALM[0].new_object
  js_for_of(it, ->(e) js_create_data(o, js_to_property_key(js_getidx(e, ~0.0)), js_getidx(e, ~1.0)))
  o

-> js_object_group_by(items, cb, as_map)
  r = JS_REALM[0]
  groups = []
  index = {}
  list = js_to_list(items)
  i = 0
  while i < list.size
    js_group_add(groups, index, js_call(cb, nil, [list[i], js_f(i)]), list[i], as_map)
    i += 1
  if as_map
    m = js_map_new()
    groups.each ->(g) js_map_set(m, g[0], r.new_array(g[1]))
    return m
  o = JsObject.new(JS_NULL, "Object")
  groups.each ->(g) js_create_data(o, g[0], r.new_array(g[1]))
  o

-> js_group_add(groups, index, k, x, as_map)
  key = as_map ? k : js_to_property_key(k)
  hk = as_map ? js_map_key(key) : key
  g = index[hk]
  if g == nil
    g = [key, []]
    index[hk] = g
    groups.push(g)
  g[1].push(x)
  0

-> js_builtin_tag(o)
  return "Array" if o.is_a?(JsArray)
  return "Function" if o.is_a?(JsObject) && o.callable?
  c = o.cls
  return c if c == "Error" || c == "Boolean" || c == "Number" || c == "String" || c == "Date" || c == "RegExp" || c == "Arguments"
  "Object"

-> js_object_to_string(this)
  return "\[object Undefined]" if this == nil
  return "\[object Null]" if this == JS_NULL
  o = js_to_object(this)
  tag = js_builtin_tag(o)
  t = o.get(SYM_TO_STRING_TAG, o)
  tag = t if t.is_a?(String)
  "\[object " + tag + "]"

-> js_proto_getter(this)
  o = js_to_object(this)
  o.get_prototype_of

-> js_proto_setter(this, p)
  js_throw_type("Object.prototype.__proto__ called on null or undefined") if js_nullish?(this)
  return nil if !(p.is_a?(JsObject) || p == JS_NULL) || !this.is_a?(JsObject)
  js_throw_type("Object.prototype.__proto__ setter failed") if !this.set_prototype_of(p)
  nil

-> js_is_proto_of(this, v)
  return false if !v.is_a?(JsObject)
  o = js_to_object(this)
  p = v.get_prototype_of
  while p != JS_NULL && p != nil
    return true if p == o
    p = p.get_prototype_of
  false

-> js_lookup_accessor(this, k, getter)
  o = js_to_object(this)
  key = js_to_property_key(k)
  while o != nil && o != JS_NULL
    d = o.get_own_property(key)
    if d != nil
      return nil if !d.accessor?
      return getter ? d.getter : d.setter
    o = o.get_prototype_of
  nil

-> js_define_legacy_accessor(this, k, f, getter)
  o = js_to_object(this)
  js_throw_type("Object.prototype.__defineGetter__: Expecting function") if !(f.is_a?(JsObject) && f.callable?)
  d = JsPropDesc.new
  if getter
    d.getter = f
    d.has_get = true
  else
    d.setter = f
    d.has_set = true
  d.enumerable = true
  d.configurable = true
  js_define_property_or_throw(o, js_to_property_key(k), d)
  nil

-> js_has_own(v, k)
  o = js_to_object(v)
  key = js_to_property_key(k)
  return o.has_own?(key) if !o.proxy?
  o.get_own_property(key) != nil

js_install(->(r) js_install_object(r))

-> js_install_object(r)
  op = r.object_proto
  fp = r.function_proto
  # Object
  oc = r.constructor("Object", 1, ->(this, args, nt) js_object_ctor(this, args, nt), op)
  r.method(oc, "keys", 1, ->(this, args, nt) js_object_keys(js_arg(args, 0), :keys))
  r.method(oc, "values", 1, ->(this, args, nt) js_object_keys(js_arg(args, 0), :values))
  r.method(oc, "entries", 1, ->(this, args, nt) js_object_keys(js_arg(args, 0), :entries))
  r.method(oc, "assign", 2, ->(this, args, nt) js_object_assign(js_arg(args, 0), args.size > 1 ? args.slice(1, args.size - 1) : []))
  r.method(oc, "freeze", 1, ->(this, args, nt) js_freeze(js_arg(args, 0)))
  r.method(oc, "seal", 1, ->(this, args, nt) js_set_integrity(js_arg(args, 0), :sealed))
  r.method(oc, "preventExtensions", 1, ->(this, args, nt) js_prevent_ext(js_arg(args, 0)))
  r.method(oc, "isFrozen", 1, ->(this, args, nt) js_test_integrity(js_arg(args, 0), :frozen))
  r.method(oc, "isSealed", 1, ->(this, args, nt) js_test_integrity(js_arg(args, 0), :sealed))
  r.method(oc, "isExtensible", 1, ->(this, args, nt) js_arg(args, 0).is_a?(JsObject) && js_arg(args, 0).is_extensible?)
  r.method(oc, "getPrototypeOf", 1, ->(this, args, nt) js_to_object(js_arg(args, 0)).get_prototype_of)
  r.method(oc, "setPrototypeOf", 2, ->(this, args, nt) js_object_set_proto(js_arg(args, 0), js_arg(args, 1)))
  r.method(oc, "create", 2, ->(this, args, nt) js_object_create(js_arg(args, 0), js_arg(args, 1)))
  r.method(oc, "defineProperty", 3, ->(this, args, nt) js_define_property_or_throw(js_req_obj(js_arg(args, 0), "Object.defineProperty"), js_to_property_key(js_arg(args, 1)), js_to_desc(js_arg(args, 2))))
  r.method(oc, "defineProperties", 2, ->(this, args, nt) js_object_define_properties(js_req_obj(js_arg(args, 0), "Object.defineProperties"), js_arg(args, 1)))
  r.method(oc, "getOwnPropertyNames", 1, ->(this, args, nt) r.new_array(js_to_object(js_arg(args, 0)).own_keys.select(->(k) k.is_a?(String))))
  r.method(oc, "getOwnPropertySymbols", 1, ->(this, args, nt) r.new_array(js_to_object(js_arg(args, 0)).own_keys.select(->(k) k.is_a?(JsSymbol))))
  r.method(oc, "getOwnPropertyDescriptor", 2, ->(this, args, nt) js_from_desc(js_to_object(js_arg(args, 0)).get_own_property(js_to_property_key(js_arg(args, 1)))))
  r.method(oc, "getOwnPropertyDescriptors", 1, ->(this, args, nt) js_get_own_descs(js_to_object(js_arg(args, 0))))
  r.method(oc, "is", 2, ->(this, args, nt) js_same_value(js_arg(args, 0), js_arg(args, 1)))
  r.method(oc, "fromEntries", 1, ->(this, args, nt) js_object_from_entries(js_arg(args, 0)))
  r.method(oc, "hasOwn", 2, ->(this, args, nt) js_has_own(js_arg(args, 0), js_arg(args, 1)))
  r.method(oc, "groupBy", 2, ->(this, args, nt) js_object_group_by(js_arg(args, 0), js_arg(args, 1), false))
  # Object.prototype
  r.method(op, "hasOwnProperty", 1, ->(this, args, nt) js_has_own(this, js_arg(args, 0)))
  r.method(op, "isPrototypeOf", 1, ->(this, args, nt) js_is_proto_of(this, js_arg(args, 0)))
  r.method(op, "propertyIsEnumerable", 1, ->(this, args, nt) js_prop_is_enum(this, js_arg(args, 0)))
  r.method(op, "toString", 0, ->(this, args, nt) js_object_to_string(this))
  r.method(op, "toLocaleString", 0, ->(this, args, nt) js_call_method(this, "toString", []))
  r.method(op, "valueOf", 0, ->(this, args, nt) js_to_object(this))
  r.method(op, "__defineGetter__", 2, ->(this, args, nt) js_define_legacy_accessor(this, js_arg(args, 0), js_arg(args, 1), true))
  r.method(op, "__defineSetter__", 2, ->(this, args, nt) js_define_legacy_accessor(this, js_arg(args, 0), js_arg(args, 1), false))
  r.method(op, "__lookupGetter__", 1, ->(this, args, nt) js_lookup_accessor(this, js_arg(args, 0), true))
  r.method(op, "__lookupSetter__", 1, ->(this, args, nt) js_lookup_accessor(this, js_arg(args, 0), false))
  r.getter(op, "__proto__", ->(this, args, nt) js_proto_getter(this), ->(this, args, nt) js_proto_setter(this, js_arg(args, 0)))
  # Function
  fc = r.constructor("Function", 1, ->(this, args, nt) js_function_ctor(args, :normal), fp)
  fp.define("name", "", ATTR_C)
  fp.define("length", ~0.0, ATTR_C)
  r.method(fp, "call", 1, ->(this, args, nt) js_call_named(this, js_arg(args, 0), args.size > 1 ? args.slice(1, args.size - 1) : [], "Function.prototype.call"))
  r.method(fp, "apply", 2, ->(this, args, nt) js_call_named(this, js_arg(args, 0), js_list_from_array_like(js_arg(args, 1)), "Function.prototype.apply"))
  r.method(fp, "bind", 1, ->(this, args, nt) js_bind(this, js_arg(args, 0), args.size > 1 ? args.slice(1, args.size - 1) : []))
  r.method(fp, "toString", 0, ->(this, args, nt) js_fn_to_string(this))
  hi = r.native("\[Symbol.hasInstance]", 1, ->(this, args, nt) js_ordinary_has_instance(this, js_arg(args, 0)))
  fp.define(SYM_HAS_INSTANCE, hi, 0)
  r.set_intrinsic("%FunctionProto_hasInstance%", hi)
  tte = r.native("", 0, ->(this, args, nt) js_throw_type("'caller', 'callee', and 'arguments' properties may not be accessed on strict mode functions or the arguments objects for calls to them"))
  tte.extensible = false
  r.set_intrinsic("%ThrowTypeError%", tte)
  # Boolean
  bp = JsObject.new(op, "Boolean")
  bp.internal = false
  r.constructor("Boolean", 1, ->(this, args, nt) js_boolean_ctor(args, nt), bp)
  r.method(bp, "toString", 0, ->(this, args, nt) js_this_bool(this) ? "true" : "false")
  r.method(bp, "valueOf", 0, ->(this, args, nt) js_this_bool(this))
  # Symbol
  sp = JsObject.new(op, "Symbol")
  sc = r.constructor("Symbol", 0, ->(this, args, nt) js_symbol_ctor(args, nt), sp)
  [["iterator", SYM_ITERATOR], ["asyncIterator", SYM_ASYNC_ITERATOR], ["toPrimitive", SYM_TO_PRIMITIVE], ["toStringTag", SYM_TO_STRING_TAG], ["hasInstance", SYM_HAS_INSTANCE], ["species", SYM_SPECIES], ["unscopables", SYM_UNSCOPABLES], ["isConcatSpreadable", SYM_IS_CONCAT_SPREADABLE], ["match", SYM_MATCH], ["matchAll", SYM_MATCH_ALL], ["replace", SYM_REPLACE], ["search", SYM_SEARCH], ["split", SYM_SPLIT]].each ->(p)
    sc.define(p[0], p[1], 0)
  r.method(sc, "for", 1, ->(this, args, nt) r.symbol_for(js_to_string(js_arg(args, 0))))
  r.method(sc, "keyFor", 1, ->(this, args, nt) js_symbol_key_for(r, js_arg(args, 0)))
  r.method(sp, "toString", 0, ->(this, args, nt) js_this_symbol(this).to_s)
  r.method(sp, "valueOf", 0, ->(this, args, nt) js_this_symbol(this))
  r.getter(sp, "description", ->(this, args, nt) js_this_symbol(this).description)
  tp = r.native("\[Symbol.toPrimitive]", 1, ->(this, args, nt) js_this_symbol(this))
  sp.define(SYM_TO_PRIMITIVE, tp, ATTR_C)
  sp.define(SYM_TO_STRING_TAG, "Symbol", ATTR_C)
  # Errors
  ep = JsObject.new(op, "Object")
  ec = r.constructor("Error", 1, ->(this, args, nt) js_error_ctor("Error", args, nt), ep)
  ep.define("name", "Error", BUILTIN_ATTRS)
  ep.define("message", "", BUILTIN_ATTRS)
  r.method(ep, "toString", 0, ->(this, args, nt) js_error_to_string(this))
  r.method(ec, "captureStackTrace", 1, ->(this, args, nt) js_capture_stack(js_arg(args, 0)))
  ec.define("stackTraceLimit", ~100.0, ATTR_ALL)
  ["TypeError", "RangeError", "SyntaxError", "ReferenceError", "EvalError", "URIError"].each ->(nm)
    js_install_error_kind(r, nm, ec, ep)
  agp = JsObject.new(ep, "Object")
  agc = r.constructor("AggregateError", 2, ->(this, args, nt) js_aggregate_error_ctor(args, nt), agp)
  agc.proto = ec
  agp.define("name", "AggregateError", BUILTIN_ATTRS)
  agp.define("message", "", BUILTIN_ATTRS)
  # globals
  g = r.global
  g.define("NaN", js_nan(), 0)
  g.define("Infinity", INF, 0)
  g.define("undefined", nil, 0)
  ev = r.method(g, "eval", 1, ->(this, args, nt) js_indirect_eval(js_arg(args, 0)))
  r.set_intrinsic("eval", ev)
  r.method(g, "parseInt", 2, ->(this, args, nt) js_parse_int(js_to_string(js_arg(args, 0)), js_arg(args, 1)))
  r.method(g, "parseFloat", 1, ->(this, args, nt) js_parse_float(js_to_string(js_arg(args, 0))))
  r.method(g, "isNaN", 1, ->(this, args, nt) js_is_nan?(js_to_number(js_arg(args, 0))))
  r.method(g, "isFinite", 1, ->(this, args, nt) js_finite?(js_to_number(js_arg(args, 0))))
  r.method(g, "encodeURIComponent", 1, ->(this, args, nt) js_uri_encode(js_to_string(js_arg(args, 0)), JS_URI_UNRESERVED_COMP))
  r.method(g, "encodeURI", 1, ->(this, args, nt) js_uri_encode(js_to_string(js_arg(args, 0)), JS_URI_UNRESERVED_FULL))
  r.method(g, "decodeURIComponent", 1, ->(this, args, nt) js_uri_decode(js_to_string(js_arg(args, 0)), ""))
  r.method(g, "decodeURI", 1, ->(this, args, nt) js_uri_decode(js_to_string(js_arg(args, 0)), ";/?:@&=+$,#"))
  r.method(g, "escape", 1, ->(this, args, nt) js_escape(js_to_string(js_arg(args, 0))))
  r.method(g, "unescape", 1, ->(this, args, nt) js_unescape(js_to_string(js_arg(args, 0))))
  nil

-> js_prevent_ext(o)
  if o.is_a?(JsObject)
    js_throw_type("Cannot prevent extensions") if !o.prevent_extensions
  o

-> js_prop_is_enum(this, k)
  o = js_to_object(this)
  d = o.get_own_property(js_to_property_key(k))
  d != nil && d.enumerable == true

-> js_get_own_descs(o)
  out = JS_REALM[0].new_object
  o.own_keys.each ->(k)
    d = o.get_own_property(k)
    js_create_data(out, k, js_from_desc(d)) if d != nil
  out

-> js_finite?(n)
  n == n && n != INF && n != NEG_INF

-> js_this_bool(v)
  return v if v == true || v == false
  return v.internal if v.is_a?(JsObject) && v.cls == "Boolean"
  js_throw_type("Boolean.prototype.valueOf requires that 'this' be a Boolean")

-> js_boolean_ctor(args, nt)
  b = js_to_boolean(js_arg(args, 0))
  return b if nt == nil
  o = JsObject.new(JS_REALM[0].proto_from(nt, "Boolean"), "Boolean")
  o.internal = b
  o

-> js_this_symbol(v)
  return v if v.is_a?(JsSymbol)
  return v.internal if v.is_a?(JsObject) && v.cls == "Symbol" && v.internal.is_a?(JsSymbol)
  js_throw_type("Symbol.prototype.valueOf requires that 'this' be a Symbol")

-> js_symbol_ctor(args, nt)
  js_throw_type("Symbol is not a constructor") if nt != nil
  d = js_arg(args, 0)
  JsSymbol.new(d == nil ? nil : js_to_string(d))

-> js_symbol_key_for(r, s)
  js_throw_type(js_to_display(s) + " is not a symbol") if !s.is_a?(JsSymbol)
  r.symbol_registry.each ->(k, v)
    return k if v == s
  nil

# ---- errors ----

-> js_install_error_kind(r, nm, ec, ep)
  p = JsObject.new(ep, "Object")
  c = r.constructor(nm, 1, ->(this, args, nt) js_error_ctor(nm, args, nt), p)
  c.proto = ec
  p.define("name", nm, BUILTIN_ATTRS)
  p.define("message", "", BUILTIN_ATTRS)

-> js_error_ctor(kind, args, nt)
  r = JS_REALM[0]
  e = JsObject.new(r.proto_from(nt == nil ? r.intrinsic(kind) : nt, kind), "Error")
  m = js_arg(args, 0)
  e.define("message", js_to_string(m), ATTR_W + ATTR_C) if m != nil
  opts = js_arg(args, 1)
  if opts.is_a?(JsObject) && opts.has_property?("cause")
    e.define("cause", opts.get("cause"), ATTR_W + ATTR_C)
  js_error_locate(e)
  e

-> js_aggregate_error_ctor(args, nt)
  e = js_error_ctor("AggregateError", [js_arg(args, 1), js_arg(args, 2)], nt)
  e.define("errors", JS_REALM[0].new_array(js_to_list(js_arg(args, 0))), ATTR_W + ATTR_C)
  e

-> js_capture_stack(o)
  return nil if !o.is_a?(JsObject)
  o.define("stack", js_stack_lines(), ATTR_W + ATTR_C)
  nil

-> js_error_to_string(this)
  js_throw_type("Error.prototype.toString requires that 'this' be an Object") if !this.is_a?(JsObject)
  n = this.get("name")
  n = n == nil ? "Error" : js_to_string(n)
  m = this.get("message")
  m = m == nil ? "" : js_to_string(m)
  return m if n == ""
  return n if m == ""
  n + ": " + m

# ---- functions ----

-> js_fn_to_string(f)
  if f.is_a?(JsFunction)
    if f.code != nil
      return js_function_source(f)
    return "function " + f.fname.to_s + "() { \[native code] }"
  return "function () { \[native code] }" if f.is_a?(JsObject) && f.callable?
  js_throw_type("Function.prototype.toString requires that 'this' be a Function")

-> js_list_from_array_like(v)
  return [] if js_nullish?(v)
  js_throw_type("CreateListFromArrayLike called on non-object") if !v.is_a?(JsObject)
  if v.is_a?(JsArray) && v.slen == nil
    # holes read through the prototype chain ([[Get]])
    return v.elems.map(->(x) x) if !v.elems.include?(JS_HOLE)
    out0 = []
    i0 = 0
    while i0 < v.length
      out0.push(js_arr_elem(v, i0))
      i0 += 1
    return out0
  n = js_to_length(v.get("length", v))
  out = Array.new(n, nil)
  i = 0
  while i < n
    out[i] = v.get_idx(i)
    i += 1
  out

-> js_to_length(v)
  n = js_to_integer(v)
  return 0 if n <= ~0.0
  return 9007199254740991 if n > ~9007199254740991.0
  n.to_i

-> js_bind(target, this_arg, bound_args)
  js_throw_type("Bind must be called on a function") if !(target.is_a?(JsObject) && target.callable?)
  r = JS_REALM[0]
  ctor = js_is_constructor?(target)
  len = ~0.0
  if target.has_own?("length")
    l = target.get("length")
    if l.is_a?(Float)
      len = l == INF ? INF : js_to_integer(l) - bound_args.size
      len = ~0.0 if len < ~0.0
  nm = target.get("name")
  nm = "" if !nm.is_a?(String)
  f = JsFunction.new(target.get_prototype_of, nil, "bound " + nm, 0, ctor)
  f.define("length", len, ATTR_C)
  f.bound = [target, this_arg, bound_args]
  f.native = ->(this, args, nt) js_bound_call(f, args, nt)
  f

-> js_bound_call(f, args, nt)
  b = f.bound
  all = b[2].size == 0 ? args : b[2] + args
  if nt != nil
    t = nt == f ? b[0] : nt
    return js_construct(b[0], all, t)
  js_call(b[0], b[1], all)

# new Function(p1, ..., body) / GeneratorFunction / AsyncFunction
-> js_function_ctor(args, kind)
  params = []
  body = ""
  if args.size > 0
    i = 0
    while i < args.size - 1
      params.push(js_to_string(args[i]))
      i += 1
    body = js_to_string(args[args.size - 1])
  prefix = kind == :generator ? "function*" : (kind == :async ? "async function" : (kind == :async_gen ? "async function*" : "function"))
  src = "(" + prefix + " anonymous(" + params.join(",") + "\n) {\n" + body + "\n})"
  prog = js_parse_or_throw(src, false)
  comp = JsCompiler.new(src)
  run = comp.compile_script(prog)
  f = run.call(nil)
  f.define("name", "anonymous", ATTR_C) if f.is_a?(JsObject)
  f

# Trusted Types: eval of a TrustedScript compiles its text (PerformEval with a trusted value).
-> js_eval_source(v)
  return v if !v.is_a?(JsObject)
  r = JS_REALM[0]
  c = r.global.get_own("TrustedScript")
  return v if !c.is_a?(JsObject)
  p = c.get("prototype", c)
  o = v.proto
  n = 0
  while o.is_a?(JsObject) && n < 20
    return js_to_string(v) if o == p
    o = o.proto
    n += 1
  v

-> js_indirect_eval(src)
  src = js_eval_source(src)
  return src if !src.is_a?(String)
  prog = js_parse_or_throw(src, false)
  comp = JsCompiler.new(src)
  comp.lazy = src.size >= JS_LAZY_MIN[0]
  run = comp.compile_script(prog)
  run.call(nil)

# Run a script source in the realm (the embedder's entry point). Returns the completion value.
JS_PHASES = [~0.0, ~0.0, ~0.0]
# BLADE_JS_PHASES=1: one stderr line per script with its parse / compile / run milliseconds.
JS_PHASE_LOG = [Env.get("BLADE_JS_PHASES", "") == "1"]

# Builtins written in JavaScript: their functions print as native code and their
# frames show as [native code], like the engine's own.
-> js_run_builtin(src, name)
  comp = JsCompiler.new(src)
  comp.url = name
  comp.builtin = true
  run = comp.compile_script(js_parse_or_throw(src, false))
  JS_DEPTH[0] = 0
  run.call(nil)

-> js_run_script(src, name = "script")
  t0 = (clock_ms() * 1000000)
  prog = js_parse_or_throw(src, false)
  t1 = (clock_ms() * 1000000)
  comp = JsCompiler.new(src)
  comp.url = name == "script" ? "" : name
  comp.lazy = src.size >= JS_LAZY_MIN[0]
  comp.unit = js_aot_unit_for(src, comp.url) if src.size >= JS_AOT_MIN[0]
  run = comp.compile_script(prog)
  t2 = (clock_ms() * 1000000)
  JS_PHASES[0] = JS_PHASES[0] + (t1 - t0) / ~1000000.0
  JS_PHASES[1] = JS_PHASES[1] + (t2 - t1) / ~1000000.0
  JS_DEPTH[0] = 0
  otop0 = JS_TOP[0]
  otop1 = JS_TOP[1]
  opos = JS_POS[0]
  JS_TOP[0] = src
  JS_TOP[1] = comp.url
  JS_POS[0] = -1
  v = nil
  begin
    v = run.call(nil)
  rescue e
    JS_TOP[0] = otop0
    JS_TOP[1] = otop1
    JS_POS[0] = opos
    raise e
  JS_TOP[0] = otop0
  JS_TOP[1] = otop1
  JS_POS[0] = opos
  t3 = (clock_ms() * 1000000)
  JS_PHASES[2] = JS_PHASES[2] + (t3 - t2) / ~1000000.0
  if JS_PHASE_LOG[0] && src.size > 2000
    ccall("w_eputs", "\[js lazy] so far: " + JS_LAZY_STATS[1].to_s + " bodies compiled in " + (JS_LAZY_T[0] * 1000).round.to_s + " ms (parse " + (JS_LAZY_T[1] * 1000).round.to_s + " ms), " + JS_LAZY_STATS[0].to_s + " deferred; aot " + JS_AOT_STATS.to_s)
    ccall("w_eputs", "\[js phases] parse " + ((t1 - t0) / 1000000).to_s + " compile " + ((t2 - t1) / 1000000).to_s + " run " + ((t3 - t2) / 1000000).to_s + " ms  " + src.size.to_s + " B  " + name.slice(0, 90))
  v

# ---- global functions ----

-> js_parse_int(s, radix_v)
  t = js_trim(s)
  sign = ~1.0
  i = 0
  n = t.size
  if n > 0 && (t.byte_at(0) == 45 || t.byte_at(0) == 43)
    sign = ~-1.0 if t.byte_at(0) == 45
    i = 1
  r = js_to_int32(radix_v)
  strip = true
  if r != 0
    return js_nan() if r < 2 || r > 36
    strip = false if r != 16
  else
    r = 10
  if strip && i + 1 < n && t.byte_at(i) == 48 && (t.byte_at(i + 1) | 32) == 120
    i += 2
    r = 16
  v = ~0.0
  start = i
  while i < n
    d = js_digit(t.byte_at(i))
    break if d < 0 || d >= r
    v = v * r + d
    i += 1
  return js_nan() if i == start
  if r == 10 && i - start > 15
    v = t.slice(start, i - start).to_f
  sign * v

-> js_parse_float(s)
  t = js_trim(s)
  n = t.size
  i = 0
  i += 1 if i < n && (t.byte_at(i) == 43 || t.byte_at(i) == 45)
  return (t.byte_at(0) == 45 ? NEG_INF : INF) if t.slice(i, 8) == "Infinity"
  ds = i
  while i < n && t.byte_at(i) >= 48 && t.byte_at(i) <= 57
    i += 1
  if i < n && t.byte_at(i) == 46
    i += 1
    while i < n && t.byte_at(i) >= 48 && t.byte_at(i) <= 57
      i += 1
  digits = t.slice(ds, i - ds)
  return js_nan() if digits == "" || digits == "."
  if i < n && (t.byte_at(i) | 32) == 101
    j = i + 1
    j += 1 if j < n && (t.byte_at(j) == 43 || t.byte_at(j) == 45)
    k = j
    while k < n && t.byte_at(k) >= 48 && t.byte_at(k) <= 57
      k += 1
    i = k if k > j
  js_string_to_number(t.slice(0, i))

JS_URI_UNRESERVED_COMP = "-_.!~*'()"
JS_URI_UNRESERVED_FULL = "-_.!~*'();/?:@&=+$,#"
JS_HEX = "0123456789ABCDEF"

-> js_uri_encode(s, keep)
  sb = StringBuffer()
  u = js_ascii?(s) ? nil : js_units(s)
  if u == nil
    i = 0
    while i < s.size
      b = s.byte_at(i)
      if (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || (b >= 48 && b <= 57) || keep.index(s.slice(i, 1)) != nil
        sb.append(s.slice(i, 1))
      else
        sb.append("%" + JS_HEX.slice(b >> 4, 1) + JS_HEX.slice(b & 15, 1))
      i += 1
    return sb.to_s
  i = 0
  while i < u.size
    c = u[i]
    if c < 128 && ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || keep.index(c.chr) != nil)
      sb.append(c.chr)
      i += 1
    else
      cp = c
      if c >= 0xDC00 && c <= 0xDFFF
        raise JsThrow.new(js_make_error("URIError", "URI malformed"))
      if c >= 0xD800 && c <= 0xDBFF
        raise JsThrow.new(js_make_error("URIError", "URI malformed")) if i + 1 >= u.size || u[i + 1] < 0xDC00 || u[i + 1] > 0xDFFF
        cp = 0x10000 + ((c - 0xD800) << 10) + (u[i + 1] - 0xDC00)
        i += 1
      bs = js_chr(cp)
      j = 0
      while j < bs.size
        b = bs.byte_at(j)
        sb.append("%" + JS_HEX.slice(b >> 4, 1) + JS_HEX.slice(b & 15, 1))
        j += 1
      i += 1
  sb.to_s

-> js_uri_decode(s, reserved)
  return s if s.index("%") == nil
  sb = StringBuffer()
  n = s.size
  i = 0
  while i < n
    b = s.byte_at(i)
    if b != 37
      sb.append(s.slice(i, 1))
      i += 1
    else
      bytes = []
      raw_start = i
      h = js_hex2(s, i + 1)
      raise JsThrow.new(js_make_error("URIError", "URI malformed")) if h < 0
      i += 3
      need = h < 0x80 ? 0 : (h >= 0xF0 ? 3 : (h >= 0xE0 ? 2 : (h >= 0xC0 ? 1 : -1)))
      raise JsThrow.new(js_make_error("URIError", "URI malformed")) if need < 0
      bytes.push(h)
      k = 0
      while k < need
        raise JsThrow.new(js_make_error("URIError", "URI malformed")) if i >= n || s.byte_at(i) != 37
        h2 = js_hex2(s, i + 1)
        raise JsThrow.new(js_make_error("URIError", "URI malformed")) if h2 < 0 || (h2 & 0xC0) != 0x80
        bytes.push(h2)
        i += 3
        k += 1
      if need == 0 && reserved.index(h.chr) != nil
        sb.append(s.slice(raw_start, 3))
      else
        cp = js_utf8_cp(bytes)
        sb.append(js_chr(cp))
  sb.to_s

-> js_hex2(s, i)
  return -1 if i + 1 >= s.size
  a = js_hex_val(s.byte_at(i))
  b = js_hex_val(s.byte_at(i + 1))
  return -1 if a < 0 || b < 0
  a * 16 + b

-> js_utf8_cp(bytes)
  b0 = bytes[0]
  return b0 if bytes.size == 1
  return ((b0 & 0x1F) << 6) | (bytes[1] & 0x3F) if bytes.size == 2
  return ((b0 & 0x0F) << 12) | ((bytes[1] & 0x3F) << 6) | (bytes[2] & 0x3F) if bytes.size == 3
  ((b0 & 0x07) << 18) | ((bytes[1] & 0x3F) << 12) | ((bytes[2] & 0x3F) << 6) | (bytes[3] & 0x3F)

-> js_escape(s)
  sb = StringBuffer()
  js_units(s).each ->(c)
    if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 64 || c == 42 || c == 95 || c == 43 || c == 45 || c == 46 || c == 47
      sb.append(c.chr)
    elsif c < 256
      sb.append("%" + JS_HEX.slice(c >> 4, 1) + JS_HEX.slice(c & 15, 1))
    else
      sb.append("%u" + JS_HEX.slice((c >> 12) & 15, 1) + JS_HEX.slice((c >> 8) & 15, 1) + JS_HEX.slice((c >> 4) & 15, 1) + JS_HEX.slice(c & 15, 1))
  sb.to_s

-> js_unescape(s)
  u = js_units(s)
  out = []
  i = 0
  while i < u.size
    c = u[i]
    if c == 37 && i + 5 < u.size + 0 && u[i + 1] == 117
      v = js_hex_units(u, i + 2, 4)
      if v >= 0
        out.push(v)
        i += 6
      else
        out.push(c)
        i += 1
    elsif c == 37 && i + 2 < u.size
      v = js_hex_units(u, i + 1, 2)
      if v >= 0
        out.push(v)
        i += 3
      else
        out.push(c)
        i += 1
    else
      out.push(c)
      i += 1
  js_from_units(out)

-> js_hex_units(u, at, n)
  return -1 if at + n > u.size
  v = 0
  k = 0
  while k < n
    h = u[at + k] < 128 ? js_hex_val(u[at + k]) : -1
    return -1 if h < 0
    v = v * 16 + h
    k += 1
  v

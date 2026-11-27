# runtime/b_object — Object, Function, Boolean, Symbol, the Error types, global functions.
# (Ported from blade/js/b_object.w.)

in JS

-> js_req_obj(v, what)
  js_throw_type(what + " called on non-object") if !js_object?(v)
  v

# A Proxy (its internal methods are traps, so no fast paths apply).
-> js_proxy?(o)
  (jsr_kind(wvalue_bits(o) ## i64) & 15) == KIND_EXOTIC && o.proxy?

# ToPropertyDescriptor
-> js_to_desc(v)
  js_throw_type("Property description must be an object: " + js_err_display(v)) if !js_object?(v)
  d = JS:PropDesc.new
  if jhas_property?(v, "enumerable")
    d.enumerable = js_to_boolean(jget(v, "enumerable"))
  if jhas_property?(v, "configurable")
    d.configurable = js_to_boolean(jget(v, "configurable"))
  if jhas_property?(v, "value")
    d.value = jget(v, "value")
    d.has_value = true
  if jhas_property?(v, "writable")
    d.writable = js_to_boolean(jget(v, "writable"))
  if jhas_property?(v, "get")
    g = jget(v, "get")
    js_throw_type("Getter must be a function: " + js_err_display(g)) if g != nil && !js_callable?(g)
    d.getter = g
    d.has_get = true
  if jhas_property?(v, "set")
    st = jget(v, "set")
    js_throw_type("Setter must be a function: " + js_err_display(st)) if st != nil && !js_callable?(st)
    d.setter = st
    d.has_set = true
  js_throw_type("Invalid property descriptor. Cannot both specify accessors and a value or writable attribute") if (d.has_get || d.has_set) && (d.has_value || d.writable != nil)
  d

# FromPropertyDescriptor
-> js_from_desc(d)
  return nil if d == nil
  o = js_realm().new_object
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
  ok = jdefine_own_property(o, k, d)
  js_throw_type("Cannot redefine property: " + js_to_display(js_key_display(k))) if !ok
  o

-> js_object_define_properties(o, props)
  p = js_to_obj(props)
  descs = []
  ks = jown_keys(p)
  i = 0
  while i < ks.size
    k = ks[i]
    pd = jget_own_property(p, k)
    if pd != nil && pd.enumerable == true
      descs.push([k, js_to_desc(jget(p, k))])
    i += 1
  i = 0
  while i < descs.size
    js_define_property_or_throw(o, descs[i][0], descs[i][1])
    i += 1
  o

# SetIntegrityLevel. Arrays keep their elements dense and record the level as flags in
# their side object (array.w: JS_AK_SEALED, JS_AK_FROZEN, JS_AK_LENRO).
-> js_set_integrity(o, level)
  return o if !js_object?(o)
  js_throw_type("Cannot prevent extensions") if !jprevent_extensions(o)
  t = o
  if js_array?(o)
    t = js_array_ext(o, true)
    t.define(JS_AK_SEALED, true, 0)
    if level == :frozen
      t.define(JS_AK_FROZEN, true, 0)
      t.define(JS_AK_LENRO, true, 0)
  ks = jown_keys(t)
  i = 0
  while i < ks.size
    k = ks[i]
    d = jget_own_property(t, k)
    if d != nil
      nd = JS:PropDesc.new
      nd.configurable = false
      nd.writable = false if level == :frozen && !d.accessor?
      js_define_property_or_throw(t, k, nd)
    i += 1
  o

-> js_freeze(o)
  js_set_integrity(o, :frozen)

-> js_test_integrity(o, level)
  return true if !js_object?(o)
  return false if jextensible?(o)
  ks = jown_keys(o)
  i = 0
  while i < ks.size
    d = jget_own_property(o, ks[i])
    if d != nil
      return false if d.configurable == true
      return false if level == :frozen && !d.accessor? && d.writable == true
    i += 1
  true

# The own enumerable string keys, in order.
-> js_own_enum_keys(o)
  out = []
  if js_array?(o)
    if (js_array_flags(o) & JS_AF_EXT) == 0
      i = 0
      while i < o.size
        out.push(i.to_s) if o[i] != JS_HOLE
        i += 1
      return out
    # elements may live in the side object (array.w): its own keys keep index order
    ak = js_array_own_keys(o)
    i = 0
    while i < ak.size
      k = ak[i]
      out.push(k) if js_string?(k) && jenumerable?(o, k)
      i += 1
    return out
  if o.is_a?(JS:Object) && !o.shape.dict
    return o.shape.enum_str_keys().dup
  ex = js_proxy?(o)
  ks = jown_keys(o)
  i = 0
  while i < ks.size
    k = ks[i]
    if js_string?(k)
      if ex
        d = o.get_own_property(k)
        out.push(k) if d != nil && d.enumerable == true
      elsif jenumerable?(o, k)
        out.push(k)
    i += 1
  out

-> js_object_keys(v, kind)
  o = js_to_obj(v)
  r = js_realm()
  return r.adopt_array(js_own_enum_keys(o)) if kind == :keys
  ks = jown_keys(o)
  out = []
  i = 0
  while i < ks.size
    k = ks[i]
    if js_string?(k)
      d = jget_own_property(o, k)
      if d != nil && d.enumerable == true
        val = jget(o, k)
        if kind == :values
          out.push(val)
        else
          out.push(r.adopt_array([k, val]))
    i += 1
  r.adopt_array(out)

-> js_object_assign(target, sources, start = 0)
  to = js_to_obj(target)
  j = start
  while j < sources.size
    src = sources[j]
    if !js_nullish?(src)
      from = js_to_obj(src)
      ks = jown_keys(from)
      i = 0
      while i < ks.size
        k = ks[i]
        d = jget_own_property(from, k)
        if d != nil && d.enumerable == true
          ok = jset(to, k, jget(from, k))
          js_set_failed(to, k) if !ok
        i += 1
    j += 1
  to

-> js_object_ctor(this, args, nt)
  r = js_realm()
  if nt != nil && nt != r.intrinsic("Object")
    return js_new_object(r.proto_from(nt, "Object"))
  v = js_arg(args, 0)
  return r.new_object if js_nullish?(v)
  js_to_obj(v)

-> js_object_create(p, props)
  js_throw_type("Object prototype may only be an Object or null: " + js_err_display(p)) if !(js_object?(p) || p == JS_NULL)
  o = js_new_object(p == JS_NULL ? nil : p)
  js_object_define_properties(o, props) if props != nil
  o

-> js_object_set_proto(o, p)
  js_throw_type("Object.setPrototypeOf called on null or undefined") if js_nullish?(o)
  js_throw_type("Object prototype may only be an Object or null: " + js_err_display(p)) if !(js_object?(p) || p == JS_NULL)
  return o if !js_object?(o)
  js_throw_type("Cyclic __proto__ value") if !jset_prototype_of(o, p)
  o

-> js_object_from_entries(it)
  js_throw_type("Object.fromEntries requires an iterable") if js_nullish?(it)
  o = js_realm().new_object
  rec = js_get_iterator(it)
  begin
    while true
      e = js_iter_step(rec)
      break if e == JS_ITER_DONE
      js_throw_type("Iterator value " + js_err_display(e) + " is not an entry object") if !js_object?(e)
      k = jget(e, "0")
      v = jget(e, "1")
      js_create_data(o, js_to_property_key(k), v)
  rescue ex
    js_iter_close_quiet(rec) if !rec.done
    raise ex
  o

-> js_object_group_by(items, cb, as_map)
  r = js_realm()
  js_throw_type("groupBy called on null or undefined") if js_nullish?(items)
  js_throw_type(js_err_display(cb) + " is not a function") if !js_callable?(cb)
  rec = js_get_iterator(items)
  if as_map
    m = js_map_new()
    md = m.internal
    i = 0
    begin
      while true
        x = js_iter_step(rec)
        break if x == JS_ITER_DONE
        k = js_call_arr(cb, nil, [x, js_f(i)])
        grp = js_map_get(md, k)
        if grp == nil
          grp = r.adopt_array([x])
          js_map_put(md, k, grp)
        else
          grp.push(x)
        i += 1
    rescue ex
      js_iter_close_quiet(rec) if !rec.done
      raise ex
    return m
  groups = []
  index = {}
  i = 0
  begin
    while true
      x = js_iter_step(rec)
      break if x == JS_ITER_DONE
      k = js_to_property_key(js_call_arr(cb, nil, [x, js_f(i)]))
      g = index[k]
      if g == nil
        g = [k, []]
        index[k] = g
        groups.push(g)
      g[1].push(x)
      i += 1
  rescue ex
    js_iter_close_quiet(rec) if !rec.done
    raise ex
  o = js_new_object(nil)
  i = 0
  while i < groups.size
    js_create_data(o, groups[i][0], r.adopt_array(groups[i][1]))
    i += 1
  o

-> js_builtin_tag(o)
  return "Array" if js_is_array(o)
  return "Function" if js_callable?(o)
  c = js_cls(o)
  return c if c == "Error" || c == "Boolean" || c == "Number" || c == "String" || c == "Date" || c == "RegExp" || c == "Arguments"
  "Object"

-> js_object_to_string(this)
  return "\[object Undefined]" if this == nil
  return "\[object Null]" if this == JS_NULL
  o = js_to_obj(this)
  tag = js_builtin_tag(o)
  t = jget(o, SYM_TO_STRING_TAG)
  tag = t if js_string?(t)
  "\[object " + tag + "]"

-> js_proto_getter(this)
  o = js_to_obj(this)
  jget_prototype_of(o)

-> js_proto_setter(this, p)
  js_throw_type("Object.prototype.__proto__ called on null or undefined") if js_nullish?(this)
  return nil if !(js_object?(p) || p == JS_NULL) || !js_object?(this)
  js_throw_type("Object.prototype.__proto__ setter failed") if !jset_prototype_of(this, p)
  nil

-> js_is_proto_of(this, v)
  return false if !js_object?(v)
  o = js_to_obj(this)
  p = jget_prototype_of(v)
  while p != JS_NULL && p != nil
    return true if p == o
    p = jget_prototype_of(p)
  false

-> js_lookup_accessor(this, k, getter)
  o = js_to_obj(this)
  key = js_to_property_key(k)
  while o != nil && o != JS_NULL
    d = jget_own_property(o, key)
    if d != nil
      return nil if !d.accessor?
      return getter ? d.getter : d.setter
    o = jget_prototype_of(o)
  nil

-> js_define_legacy_accessor(this, k, f, getter)
  o = js_to_obj(this)
  js_throw_type("Object.prototype.__defineGetter__: Expecting function") if !js_callable?(f)
  d = JS:PropDesc.new
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
  key = js_to_property_key(k)
  o = js_to_obj(v)
  return jget_own_property(o, key) != nil if js_proxy?(o)
  jhas_own?(o, key)

-> js_object_has_own(v, k)
  o = js_to_obj(v)
  key = js_to_property_key(k)
  return jget_own_property(o, key) != nil if js_proxy?(o)
  jhas_own?(o, key)

-> js_fn_call(f, args)
  js_throw_type("Function.prototype.call is not a function") if !js_callable?(f)
  n = args.size
  return js_call(f, nil, 0, nil, nil, nil, nil, nil) if n == 0
  this = args[0]
  return js_call(f, this, 0, nil, nil, nil, nil, nil) if n == 1
  return js_call(f, this, 1, args[1], nil, nil, nil, nil) if n == 2
  return js_call(f, this, 2, args[1], args[2], nil, nil, nil) if n == 3
  return js_call(f, this, 3, args[1], args[2], args[3], nil, nil) if n == 4
  return js_call(f, this, 4, args[1], args[2], args[3], args[4], nil) if n == 5
  rest = js_arr_copy(args, 1, n - 1)
  js_call(f, this, n - 1, rest[0], rest[1], rest[2], rest[3], rest)

# o[key](...args) for any value o.
-> js_invoke(o, key, args)
  f = js_get_value(o, key)
  js_call_named(f, o, args, js_to_display(js_key_display(key)))

js_install(->(r) js_install_object(r))

-> js_install_object(r)
  op = r.object_proto
  fp = r.function_proto
  # Object
  oc = r.constructor("Object", 1, ->(this, args, nt) js_object_ctor(this, args, nt), op)
  r.method(oc, "keys", 1, ->(this, args, nt) js_object_keys(js_arg(args, 0), :keys))
  r.method(oc, "values", 1, ->(this, args, nt) js_object_keys(js_arg(args, 0), :values))
  r.method(oc, "entries", 1, ->(this, args, nt) js_object_keys(js_arg(args, 0), :entries))
  r.method(oc, "assign", 2, ->(this, args, nt) js_object_assign(js_arg(args, 0), args, 1))
  r.method(oc, "freeze", 1, ->(this, args, nt) js_freeze(js_arg(args, 0)))
  r.method(oc, "seal", 1, ->(this, args, nt) js_set_integrity(js_arg(args, 0), :sealed))
  r.method(oc, "preventExtensions", 1, ->(this, args, nt) js_prevent_ext(js_arg(args, 0)))
  r.method(oc, "isFrozen", 1, ->(this, args, nt) js_test_integrity(js_arg(args, 0), :frozen))
  r.method(oc, "isSealed", 1, ->(this, args, nt) js_test_integrity(js_arg(args, 0), :sealed))
  r.method(oc, "isExtensible", 1, ->(this, args, nt) js_object?(js_arg(args, 0)) && jextensible?(js_arg(args, 0)))
  r.method(oc, "getPrototypeOf", 1, ->(this, args, nt) jget_prototype_of(js_to_obj(js_arg(args, 0))))
  r.method(oc, "setPrototypeOf", 2, ->(this, args, nt) js_object_set_proto(js_arg(args, 0), js_arg(args, 1)))
  r.method(oc, "create", 2, ->(this, args, nt) js_object_create(js_arg(args, 0), js_arg(args, 1)))
  r.method(oc, "defineProperty", 3, ->(this, args, nt) js_define_property_or_throw(js_req_obj(js_arg(args, 0), "Object.defineProperty"), js_to_property_key(js_arg(args, 1)), js_to_desc(js_arg(args, 2))))
  r.method(oc, "defineProperties", 2, ->(this, args, nt) js_object_define_properties(js_req_obj(js_arg(args, 0), "Object.defineProperties"), js_arg(args, 1)))
  r.method(oc, "getOwnPropertyNames", 1, ->(this, args, nt) r.adopt_array(jown_keys(js_to_obj(js_arg(args, 0))).select(->(k) js_string?(k))))
  r.method(oc, "getOwnPropertySymbols", 1, ->(this, args, nt) r.adopt_array(jown_keys(js_to_obj(js_arg(args, 0))).select(->(k) k.is_a?(JS:Symbol))))
  r.method(oc, "getOwnPropertyDescriptor", 2, ->(this, args, nt) js_get_own_desc(js_arg(args, 0), js_arg(args, 1)))
  r.method(oc, "getOwnPropertyDescriptors", 1, ->(this, args, nt) js_get_own_descs(js_to_obj(js_arg(args, 0))))
  r.method(oc, "is", 2, ->(this, args, nt) js_same_value(js_arg(args, 0), js_arg(args, 1)))
  r.method(oc, "fromEntries", 1, ->(this, args, nt) js_object_from_entries(js_arg(args, 0)))
  r.method(oc, "hasOwn", 2, ->(this, args, nt) js_object_has_own(js_arg(args, 0), js_arg(args, 1)))
  r.method(oc, "groupBy", 2, ->(this, args, nt) js_object_group_by(js_arg(args, 0), js_arg(args, 1), false))
  # Object.prototype
  r.method(op, "hasOwnProperty", 1, ->(this, args, nt) js_has_own(this, js_arg(args, 0)))
  r.method(op, "isPrototypeOf", 1, ->(this, args, nt) js_is_proto_of(this, js_arg(args, 0)))
  r.method(op, "propertyIsEnumerable", 1, ->(this, args, nt) js_prop_is_enum(this, js_arg(args, 0)))
  r.method(op, "toString", 0, ->(this, args, nt) js_object_to_string(this))
  r.method(op, "toLocaleString", 0, ->(this, args, nt) js_invoke(this, "toString", []))
  r.method(op, "valueOf", 0, ->(this, args, nt) js_to_obj(this))
  r.method(op, "__defineGetter__", 2, ->(this, args, nt) js_define_legacy_accessor(this, js_arg(args, 0), js_arg(args, 1), true))
  r.method(op, "__defineSetter__", 2, ->(this, args, nt) js_define_legacy_accessor(this, js_arg(args, 0), js_arg(args, 1), false))
  r.method(op, "__lookupGetter__", 1, ->(this, args, nt) js_lookup_accessor(this, js_arg(args, 0), true))
  r.method(op, "__lookupSetter__", 1, ->(this, args, nt) js_lookup_accessor(this, js_arg(args, 0), false))
  r.getter(op, "__proto__", ->(this, args, nt) js_proto_getter(this), ->(this, args, nt) js_proto_setter(this, js_arg(args, 0)))
  # Function
  r.constructor("Function", 1, ->(this, args, nt) js_function_ctor(args, :normal, nt), fp)
  fp.define("name", "", ATTR_C)
  fp.define("length", ~0.0, ATTR_C)
  # (copies, not slices: a slice registers a persistent view and borrows the caller's list)
  r.method(fp, "call", 1, ->(this, args, nt) js_fn_call(this, args))
  r.method(fp, "apply", 2, ->(this, args, nt) js_call_named(this, js_arg(args, 0), js_list_from_array_like(js_arg(args, 1)), "Function.prototype.apply"))
  r.method(fp, "bind", 1, ->(this, args, nt) js_bind(this, js_arg(args, 0), args.size > 1 ? js_arr_copy(args, 1, args.size - 1) : JS_NO_ARGS))
  r.method(fp, "toString", 0, ->(this, args, nt) js_fn_to_string(this))
  hi = r.native("\[Symbol.hasInstance]", 1, ->(this, args, nt) js_ordinary_has_instance(this, js_arg(args, 0)))
  fp.define(SYM_HAS_INSTANCE, hi, 0)
  r.set_intrinsic("%FunctionProto_hasInstance%", hi)
  tte = r.native("", 0, ->(this, args, nt) js_throw_type("'caller', 'callee', and 'arguments' properties may not be accessed on strict mode functions or the arguments objects for calls to them"))
  tte.define("length", ~0.0, 0)
  tte.define("name", "", 0)
  tte.prevent_extensions
  r.set_intrinsic("%ThrowTypeError%", tte)
  # AddRestrictedFunctionProperties (§10.2.4)
  fp.define_accessor("caller", tte, tte, ATTR_C)
  fp.define_accessor("arguments", tte, tte, ATTR_C)
  # Boolean
  bp = js_new_special(op, "Boolean")
  bp.internal = false
  r.constructor("Boolean", 1, ->(this, args, nt) js_boolean_ctor(args, nt), bp)
  r.method(bp, "toString", 0, ->(this, args, nt) js_this_bool(this) ? "true" : "false")
  r.method(bp, "valueOf", 0, ->(this, args, nt) js_this_bool(this))
  # Symbol
  sp = js_new_special(op, "Symbol")
  sc = r.constructor("Symbol", 0, ->(this, args, nt) js_symbol_ctor(args, nt), sp)
  wk = [["iterator", SYM_ITERATOR], ["asyncIterator", SYM_ASYNC_ITERATOR], ["toPrimitive", SYM_TO_PRIMITIVE], ["toStringTag", SYM_TO_STRING_TAG], ["hasInstance", SYM_HAS_INSTANCE], ["species", SYM_SPECIES], ["unscopables", SYM_UNSCOPABLES], ["isConcatSpreadable", SYM_IS_CONCAT_SPREADABLE], ["match", SYM_MATCH], ["matchAll", SYM_MATCH_ALL], ["replace", SYM_REPLACE], ["search", SYM_SEARCH], ["split", SYM_SPLIT], ["dispose", SYM_DISPOSE], ["asyncDispose", SYM_ASYNC_DISPOSE]]
  i = 0
  while i < wk.size
    sc.define(wk[i][0], wk[i][1], 0)
    i += 1
  r.method(sc, "for", 1, ->(this, args, nt) r.symbol_for(js_to_string(js_arg(args, 0))))
  r.method(sc, "keyFor", 1, ->(this, args, nt) js_symbol_key_for(r, js_arg(args, 0)))
  r.method(sp, "toString", 0, ->(this, args, nt) js_this_symbol(this).to_s)
  r.method(sp, "valueOf", 0, ->(this, args, nt) js_this_symbol(this))
  r.getter(sp, "description", ->(this, args, nt) js_this_symbol(this).description)
  tp = r.native("\[Symbol.toPrimitive]", 1, ->(this, args, nt) js_this_symbol(this))
  sp.define(SYM_TO_PRIMITIVE, tp, ATTR_C)
  sp.define(SYM_TO_STRING_TAG, "Symbol", ATTR_C)
  # Errors
  ep = js_new_object(op)
  ec = r.constructor("Error", 1, ->(this, args, nt) js_error_ctor("Error", args, nt), ep)
  ep.define("name", "Error", BUILTIN_ATTRS)
  ep.define("message", "", BUILTIN_ATTRS)
  r.getter(ep, "stack", ->(this, args, nt) js_error_stack_get(this), ->(this, args, nt) js_error_stack_set(this, ep, js_arg(args, 0)))
  r.method(ep, "toString", 0, ->(this, args, nt) js_error_to_string(this))
  r.method(ec, "captureStackTrace", 1, ->(this, args, nt) js_capture_stack(js_arg(args, 0)))
  r.method(ec, "isError", 1, ->(this, args, nt) js_special?(js_arg(args, 0), "Error"))
  ec.define("stackTraceLimit", ~100.0, ATTR_ALL)
  kinds = ["TypeError", "RangeError", "SyntaxError", "ReferenceError", "EvalError", "URIError"]
  i = 0
  while i < kinds.size
    js_install_error_kind(r, kinds[i], ec, ep)
    i += 1
  agp = js_new_object(ep)
  agc = r.constructor("AggregateError", 2, ->(this, args, nt) js_aggregate_error_ctor(args, nt), agp)
  agc.set_prototype_of(ec)
  agp.define("name", "AggregateError", BUILTIN_ATTRS)
  agp.define("message", "", BUILTIN_ATTRS)
  sep = js_new_object(ep)
  sec = r.constructor("SuppressedError", 3, ->(this, args, nt) js_suppressed_error_ctor(args, nt), sep)
  sec.set_prototype_of(ec)
  sep.define("name", "SuppressedError", BUILTIN_ATTRS)
  sep.define("message", "", BUILTIN_ATTRS)
  # globals (NaN, Infinity and undefined are defined by js_new_realm)
  g = r.global
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
  if js_object?(o)
    js_throw_type("Cannot prevent extensions") if !jprevent_extensions(o)
  o

-> js_prop_is_enum(this, k)
  key = js_to_property_key(k)
  o = js_to_obj(this)
  d = jget_own_property(o, key)
  d != nil && d.enumerable == true

-> js_get_own_desc(v, k)
  o = js_to_obj(v)
  js_from_desc(jget_own_property(o, js_to_property_key(k)))

-> js_get_own_descs(o)
  out = js_realm().new_object
  ks = jown_keys(o)
  i = 0
  while i < ks.size
    d = jget_own_property(o, ks[i])
    js_create_data(out, ks[i], js_from_desc(d)) if d != nil
    i += 1
  out

-> js_finite?(n)
  n == n && n != INF && n != NEG_INF

-> js_this_bool(v)
  return v if v == true || v == false
  return v.internal if js_special?(v, "Boolean")
  js_throw_type("Boolean.prototype.valueOf requires that 'this' be a Boolean")

-> js_boolean_ctor(args, nt)
  b = js_to_boolean(js_arg(args, 0))
  return b if nt == nil
  o = js_new_special(js_realm().proto_from(nt, "Boolean"), "Boolean")
  o.internal = b
  o

-> js_this_symbol(v)
  return v if v.is_a?(JS:Symbol)
  return v.internal if js_special?(v, "Symbol") && v.internal.is_a?(JS:Symbol)
  js_throw_type("Symbol.prototype.valueOf requires that 'this' be a Symbol")

-> js_symbol_ctor(args, nt)
  js_throw_type("Symbol is not a constructor") if nt != nil
  d = js_arg(args, 0)
  JS:Symbol.new(d == nil ? nil : js_to_string(d))

-> js_symbol_key_for(r, s)
  js_throw_type(js_err_display(s) + " is not a symbol") if !s.is_a?(JS:Symbol)
  ks = r.symbol_registry.keys
  i = 0
  while i < ks.size
    return ks[i] if r.symbol_registry[ks[i]] == s
    i += 1
  nil

# OrdinaryHasInstance (§7.3.21)
-> js_ordinary_has_instance(c, v)
  return false if !js_callable?(c)
  if (jsr_kind(wvalue_bits(c) ## i64) & 15) == KIND_BOUND
    return js_instance_of(v, c.target)
  return false if !js_object?(v)
  p = jget(c, "prototype")
  js_throw_type("Function has non-object prototype '" + js_err_display(p) + "' in instanceof check") if !js_object?(p)
  o = jget_prototype_of(v)
  while o != JS_NULL && o != nil
    return true if o == p
    o = jget_prototype_of(o)
  false

# InstanceofOperator (§13.10.2): Symbol.hasInstance, else OrdinaryHasInstance.
-> js_instance_of(v, target)
  js_throw_type("Right-hand side of 'instanceof' is not an object") if !js_object?(target)
  h = js_get_method(target, SYM_HAS_INSTANCE)
  return js_truthy(js_call_arr(h, target, [v])) if h != nil
  js_throw_type("Right-hand side of 'instanceof' is not callable") if !js_callable?(target)
  js_ordinary_has_instance(target, v)

# ---- errors ----

-> js_install_error_kind(r, nm, ec, ep)
  p = js_new_object(ep)
  c = r.constructor(nm, 1, ->(this, args, nt) js_error_ctor(nm, args, nt), p)
  c.set_prototype_of(ec)
  p.define("name", nm, BUILTIN_ATTRS)
  p.define("message", "", BUILTIN_ATTRS)

-> js_error_ctor(kind, args, nt)
  r = js_realm()
  e = js_new_special(r.proto_from(nt == nil ? r.intrinsic(kind) : nt, kind), "Error")
  m = js_arg(args, 0)
  e.define("message", js_to_string(m), ATTR_W + ATTR_C) if m != nil
  opts = js_arg(args, 1)
  if js_object?(opts) && jhas_property?(opts, "cause")
    e.define("cause", jget(opts, "cause"), ATTR_W + ATTR_C)
  js_error_locate(e)
  e

# The stack property of a new error (stored in [[ErrorData]] internal slot; accessed via Error.prototype.stack).
-> js_error_locate(e)
  if JS_STACK_HOOK[0] == nil
    e.internal = js_error_to_string(e)
    return nil
  loc = js_top_location()
  e.define("line", loc[1].to_f, ATTR_W + ATTR_C)
  e.define("column", loc[2].to_f, ATTR_W + ATTR_C)
  e.define("sourceURL", loc[0], ATTR_W + ATTR_C) if loc[0] != ""
  e.internal = js_stack_lines()
  nil

-> js_error_stack_get(this)
  js_throw_type("get Error.prototype.stack requires that 'this' be an Object") if !js_object?(this)
  return nil if !js_special?(this, "Error")
  st = this.internal
  js_string?(st) ? st : ""

-> js_error_stack_set(this, home, v)
  js_throw_type("set Error.prototype.stack requires that 'this' be an Object") if !js_object?(this)
  js_throw_type("Error.prototype.stack value must be a String") if !js_string?(v)
  # SetterThatIgnoresPrototypeProperties(this, home, "stack", v)
  js_throw_type("Cannot assign to 'stack' on Error.prototype") if this == home
  desc = jget_own_property(this, "stack")
  if desc == nil
    js_define_property_or_throw(this, "stack", JS:PropDesc.data(v, ATTR_ALL))
  else
    ok = jset(this, "stack", v)
    js_set_failed(this, "stack") if !ok
  nil

-> js_aggregate_error_ctor(args, nt)
  e = js_error_ctor("AggregateError", [js_arg(args, 1), js_arg(args, 2)], nt)
  e.define("errors", js_realm().adopt_array(js_to_list(js_arg(args, 0))), ATTR_W + ATTR_C)
  e

-> js_suppressed_error_ctor(args, nt)
  r = js_realm()
  e = js_new_special(r.proto_from(nt == nil ? r.intrinsic("SuppressedError") : nt, "SuppressedError"), "Error")
  js_error_locate(e)
  m = js_arg(args, 2)
  e.define("message", js_to_string(m), ATTR_W + ATTR_C) if m != nil
  e.define("error", js_arg(args, 0), ATTR_W + ATTR_C)
  e.define("suppressed", js_arg(args, 1), ATTR_W + ATTR_C)
  e

-> js_suppressed_error_new(err, suppressed)
  r = js_realm()
  e = js_new_special(r.proto_from(r.intrinsic("SuppressedError"), "SuppressedError"), "Error")
  js_error_locate(e)
  e.define("error", err, ATTR_W + ATTR_C)
  e.define("suppressed", suppressed, ATTR_W + ATTR_C)
  e

-> js_capture_stack(o)
  return nil if !js_object?(o)
  jdefine(o, "stack", js_error_to_string(o), ATTR_W + ATTR_C)
  nil

-> js_error_to_string(this)
  js_throw_type("Error.prototype.toString requires that 'this' be an Object") if !js_object?(this)
  n = jget(this, "name")
  n = n == nil ? "Error" : js_to_string(n)
  m = jget(this, "message")
  m = m == nil ? "" : js_to_string(m)
  return m if n == ""
  return n if m == ""
  n + ": " + m

# ---- functions ----

# Source text of a function made from script, when tier 0 can give it (a ->(f) hook).
JS_FN_SOURCE_HOOK = [nil]

-> js_valid_native_fn_name?(nm)
  s = nm
  if s.starts_with?("get ") || s.starts_with?("set ")
    s = s.slice(4, s.size - 4)
  return true if s.size == 0
  b0 = s.byte_at(0)
  if b0 == 91 && s.byte_at(s.size - 1) == 93
    depth = 0
    i = 0
    while i < s.size
      b = s.byte_at(i)
      return false if b == 10 || b == 13
      depth += 1 if b == 91
      depth -= 1 if b == 93
      return false if depth < 0 || (depth == 0 && i < s.size - 1)
      i += 1
    return depth == 0
  ok0 = (b0 >= 65 && b0 <= 90) || (b0 >= 97 && b0 <= 122) || b0 == 95 || b0 == 36
  return false if !ok0
  i = 1
  while i < s.size
    b = s.byte_at(i)
    ok = (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || (b >= 48 && b <= 57) || b == 95 || b == 36
    return false if !ok
    i += 1
  true

-> js_fn_to_string(f)
  k = jsr_kind(wvalue_bits(f) ## i64) & 15
  if k == KIND_FUNCTION
    if JS_FN_SOURCE_HOOK[0] != nil
      s = JS_FN_SOURCE_HOOK[0].call(f)
      return s if s != nil
    return "function " + f.code.name.to_s + "() { \[native code] }"
  if k == KIND_NATIVE
    nm = js_to_string(jget(f, "name"))
    return "function " + (js_valid_native_fn_name?(nm) ? nm : "") + "() { \[native code] }"
  return "function () { \[native code] }" if js_callable?(f)
  js_throw_type("Function.prototype.toString requires that 'this' be a Function")

-> js_list_from_array_like(v)
  return [] if js_nullish?(v)
  js_throw_type("CreateListFromArrayLike called on non-object") if !js_object?(v)
  if js_array?(v)
    return v.dup if (js_array_flags(v) & (JS_AF_HOLES | JS_AF_SPARSE)) == 0
    # holes read through the prototype chain ([[Get]])
    len0 = js_arr_len(v)
    out0 = []
    i0 = 0
    while i0 < len0
      out0.push(js_arr_elem(v, i0))
      i0 += 1
    return out0
  n = js_to_length(jget(v, "length"))
  out = Array.new(n, nil)
  i = 0
  while i < n
    out[i] = jget(v, i.to_s)
    i += 1
  out

-> js_to_length(v)
  n = js_to_integer(v)
  return 0 if n <= ~0.0
  return 9007199254740991 if n > ~9007199254740991.0
  n.to_i

-> js_bind(target, this_arg, bound_args)
  js_throw_type("Bind must be called on a function") if !js_callable?(target)
  len = ~0.0
  if jhas_own?(target, "length")
    l = jget(target, "length")
    if js_number?(l)
      len = l == INF ? INF : js_to_integer(l) - bound_args.size.to_f
      len = ~0.0 if len < ~0.0
  nm = jget(target, "name")
  nm = "" if !js_string?(nm)
  f = js_bound_function(target, this_arg, bound_args)
  f.define("length", len, ATTR_C)
  f.define("name", "bound " + nm, ATTR_C)
  f

# eval and new Function need a compiler for source text: tier 0 installs these hooks
# (->(src) for eval; ->(src) for a function expression's source).
JS_EVAL_HOOK = [nil]
JS_FUNCTION_HOOK = [nil]
JS_FUNCTION_CHECK_HOOK = [nil]

# new Function(p1, ..., body) / GeneratorFunction / AsyncFunction
-> js_function_ctor(args, kind, nt = nil)
  params = []
  body = ""
  if args.size > 0
    i = 0
    while i < args.size - 1
      params.push(js_to_string(args[i]))
      i += 1
    body = js_to_string(args[args.size - 1])
  prefix = kind == :generator ? "function*" : (kind == :async ? "async function" : (kind == :async_gen ? "async function*" : "function"))
  pstr = params.join(",")
  js_throw(js_make_error("EvalError", "Function constructor is not available")) if JS_FUNCTION_HOOK[0] == nil
  JS_FUNCTION_CHECK_HOOK[0].call(prefix, pstr, body) if JS_FUNCTION_CHECK_HOOK[0] != nil
  src = "(" + prefix + "(" + pstr + "\n) {\n" + body + "\n})"
  f = JS_FUNCTION_HOOK[0].call(src)
  if js_object?(f)
    f.code.src_text = prefix + " anonymous(" + pstr + "\n) {\n" + body + "\n}" if f.is_a?(JS:Function) && f.code != nil
    jdefine(f, "name", "anonymous", ATTR_C)
    if nt != nil
      fb = kind == :generator ? "%GeneratorFunction.prototype%" : (kind == :async ? "%AsyncFunction.prototype%" : (kind == :async_gen ? "%AsyncGeneratorFunction.prototype%" : "Function.prototype"))
      p = jget(nt, "prototype")
      p = js_get_function_realm(nt).intrinsic(fb) if !js_object?(p)
      f.set_prototype_of(p)
  f

-> js_indirect_eval(src)
  return src if !js_string?(src)
  js_throw(js_make_error("EvalError", "eval is not available")) if JS_EVAL_HOOK[0] == nil
  JS_EVAL_HOOK[0].call(src)

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

-> js_uri_error
  js_throw(js_make_error("URIError", "URI malformed"))

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
    r = sb.to_s
    ccall("w_value_free_w", sb)
    return r
  i = 0
  while i < u.size
    c = u[i]
    if c < 128 && ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || keep.index(js_cp_str(c)) != nil)
      sb.append(js_cp_str(c))
      i += 1
    else
      cp = c
      js_uri_error() if c >= 56320 && c <= 57343
      if c >= 55296 && c <= 56319
        js_uri_error() if i + 1 >= u.size || u[i + 1] < 56320 || u[i + 1] > 57343
        cp = 65536 + ((c - 55296) << 10) + (u[i + 1] - 56320)
        i += 1
      bs = js_cp_str(cp)
      j = 0
      while j < bs.size
        b = bs.byte_at(j)
        sb.append("%" + JS_HEX.slice(b >> 4, 1) + JS_HEX.slice(b & 15, 1))
        j += 1
      i += 1
  r = sb.to_s
  ccall("w_value_free_w", sb)
  r

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
      js_uri_error() if h < 0
      i += 3
      need = h < 128 ? 0 : (h >= 240 ? 3 : (h >= 224 ? 2 : (h >= 192 ? 1 : -1)))
      js_uri_error() if need < 0 || h >= 248
      bytes.push(h)
      k = 0
      while k < need
        js_uri_error() if i >= n || s.byte_at(i) != 37
        h2 = js_hex2(s, i + 1)
        js_uri_error() if h2 < 0 || (h2 & 192) != 128
        bytes.push(h2)
        i += 3
        k += 1
      if need == 0 && reserved.index(js_cp_str(h)) != nil
        sb.append(s.slice(raw_start, 3))
      else
        cp = js_utf8_cp(bytes)
        # overlong forms, surrogates and values past U+10FFFF are malformed
        js_uri_error() if (need == 1 && cp < 128) || (need == 2 && cp < 2048) || (need == 3 && cp < 65536) || (cp >= 55296 && cp <= 57343) || cp > 1114111
        sb.append(js_cp_str(cp))
  r = sb.to_s
  ccall("w_value_free_w", sb)
  r

-> js_hex2(s, i)
  return -1 if i + 1 >= s.size
  a = js_hexv(s.byte_at(i))
  b = js_hexv(s.byte_at(i + 1))
  return -1 if a < 0 || b < 0
  a * 16 + b

-> js_utf8_cp(bytes)
  b0 = bytes[0]
  return b0 if bytes.size == 1
  return ((b0 & 31) << 6) | (bytes[1] & 63) if bytes.size == 2
  return ((b0 & 15) << 12) | ((bytes[1] & 63) << 6) | (bytes[2] & 63) if bytes.size == 3
  ((b0 & 7) << 18) | ((bytes[1] & 63) << 12) | ((bytes[2] & 63) << 6) | (bytes[3] & 63)

-> js_escape(s)
  sb = StringBuffer()
  u = js_units(s)
  i = 0
  while i < u.size
    c = u[i]
    if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 64 || c == 42 || c == 95 || c == 43 || c == 45 || c == 46 || c == 47
      sb.append(js_cp_str(c))
    elsif c < 256
      sb.append("%" + JS_HEX.slice(c >> 4, 1) + JS_HEX.slice(c & 15, 1))
    else
      sb.append("%u" + JS_HEX.slice((c >> 12) & 15, 1) + JS_HEX.slice((c >> 8) & 15, 1) + JS_HEX.slice((c >> 4) & 15, 1) + JS_HEX.slice(c & 15, 1))
    i += 1
  r = sb.to_s
  ccall("w_value_free_w", sb)
  r

-> js_unescape(s)
  u = js_units(s)
  out = []
  i = 0
  while i < u.size
    c = u[i]
    if c == 37 && i + 5 < u.size && u[i + 1] == 117
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
    h = u[at + k] < 128 ? js_hexv(u[at + k]) : -1
    return -1 if h < 0
    v = v * 16 + h
    k += 1
  v

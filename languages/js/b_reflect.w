# runtime/b_reflect — Proxy (all traps, the main invariants) and Reflect.
# (Ported from blade/js/b_reflect.w.)
#
# A JS:Proxy is an exotic object (kind KIND_EXOTIC): every internal method is a trap.
# Its target may be a JS array, so the target is reached through the j* functions.

in JS

+ Proxy < JS:Base
  rw :target, :handler, :is_callable, :is_ctor

  -> new(@shape, @target, @handler)
    @ext = nil
    # [[Call]] and [[Construct]] exist from creation on (a revoked target keeps them)
    @is_callable = js_callable?(@target)
    @is_ctor = @is_callable && js_is_constructor?(@target)
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_EXOTIC)

  -> proxy?
    true

  -> callable?
    @is_callable

  -> constructor?
    @is_ctor

  -> proxy_target
    @target

  -> check
    js_throw_type("Cannot perform operation on a revoked proxy") if @handler == nil
    nil

  -> trap(name)
    check()
    t = jget(@handler, name)
    return nil if js_nullish?(t)
    js_throw_type("proxy trap " + name + " is not a function") if !js_callable?(t)
    t

  -> get_prototype_of
    check()
    tgt = @target
    h = @handler
    t = trap("getPrototypeOf")
    return jget_prototype_of(tgt) if t == nil
    p = js_call_arr(t, h, [tgt])
    js_throw_type("'getPrototypeOf' on proxy: trap returned neither object nor null") if !(js_object?(p) || p == JS_NULL)
    if !jextensible?(tgt)
      js_throw_type("'getPrototypeOf' on proxy: proxy target is non-extensible but the trap did not return its actual prototype") if p != jget_prototype_of(tgt)
    p

  -> proto
    p = get_prototype_of
    p == JS_NULL ? nil : p

  -> set_prototype_of(p)
    p = JS_NULL if p == nil
    check()
    tgt = @target
    h = @handler
    t = trap("setPrototypeOf")
    return jset_prototype_of(tgt, p) if t == nil
    ok = js_to_boolean(js_call_arr(t, h, [tgt, p]))
    return false if !ok
    if !jextensible?(tgt)
      js_throw_type("'setPrototypeOf' on proxy: trap returned truish for setting a new prototype on the non-extensible proxy target") if p != jget_prototype_of(tgt)
    true

  -> is_extensible?
    check()
    tgt = @target
    h = @handler
    t = trap("isExtensible")
    return jextensible?(tgt) if t == nil
    v = js_to_boolean(js_call_arr(t, h, [tgt]))
    js_throw_type("'isExtensible' on proxy: trap result does not reflect extensibility of proxy target") if v != jextensible?(tgt)
    v

  -> prevent_extensions
    check()
    tgt = @target
    h = @handler
    t = trap("preventExtensions")
    return jprevent_extensions(tgt) if t == nil
    v = js_to_boolean(js_call_arr(t, h, [tgt]))
    js_throw_type("'preventExtensions' on proxy: trap returned truish but the proxy target is extensible") if v && jextensible?(tgt)
    v

  -> get_own_property(k)
    check()
    tgt = @target
    h = @handler
    t = trap("getOwnPropertyDescriptor")
    return jget_own_property(tgt, k) if t == nil
    res = js_call_arr(t, h, [tgt, k])
    js_throw_type("'getOwnPropertyDescriptor' on proxy: trap returned neither object nor undefined for property '" + js_to_display(js_key_display(k)) + "'") if res != nil && !js_object?(res)
    td = jget_own_property(tgt, k)
    if res == nil
      return nil if td == nil
      js_throw_type("'getOwnPropertyDescriptor' on proxy: trap returned undefined for property '" + js_to_display(js_key_display(k)) + "' which is non-configurable in the proxy target") if td.configurable == false
      js_throw_type("'getOwnPropertyDescriptor' on proxy: trap returned undefined for property '" + js_to_display(js_key_display(k)) + "' which exists in the non-extensible proxy target") if !jextensible?(tgt)
      return nil
    ext = jextensible?(tgt)
    d = js_to_desc(res)
    d.configurable = false if d.configurable == nil
    d.enumerable = false if d.enumerable == nil
    if !d.accessor?
      d.has_value = true
      d.writable = false if d.writable == nil
    js_throw_type("'getOwnPropertyDescriptor' on proxy: trap returned descriptor for property '" + js_to_display(js_key_display(k)) + "' that is incompatible with the existing property in the proxy target") if !js_desc_compatible?(ext, d, td)
    if d.configurable == false
      js_throw_type("'getOwnPropertyDescriptor' on proxy: trap reported non-configurability for property '" + js_to_display(js_key_display(k)) + "' which is either non-existent or configurable in the proxy target") if td == nil || td.configurable == true
      if d.writable == false && td.writable == true
        js_throw_type("'getOwnPropertyDescriptor' on proxy: trap reported non-configurable and writable for property '" + js_to_display(js_key_display(k)) + "' which is non-configurable, non-writable in the proxy target")
    d

  -> define_own_property(k, desc)
    check()
    tgt = @target
    h = @handler
    t = trap("defineProperty")
    return jdefine_own_property(tgt, k, desc) if t == nil
    ok = js_to_boolean(js_call_arr(t, h, [tgt, k, js_from_partial_desc(desc)]))
    return false if !ok
    td = jget_own_property(tgt, k)
    if td == nil
      js_throw_type("'defineProperty' on proxy: trap returned truish for adding property '" + js_to_display(js_key_display(k)) + "'  to the non-extensible proxy target") if !jextensible?(tgt)
      js_throw_type("'defineProperty' on proxy: trap returned truish for defining non-configurable property '" + js_to_display(js_key_display(k)) + "' which is either non-existent or configurable in the proxy target") if desc.configurable == false
    else
      js_throw_type("'defineProperty' on proxy: trap returned truish for adding property '" + js_to_display(js_key_display(k)) + "'  that is incompatible with the existing property in the proxy target") if !js_desc_compatible?(jextensible?(tgt), desc, td)
      js_throw_type("'defineProperty' on proxy: trap returned truish for defining non-configurable property '" + js_to_display(js_key_display(k)) + "' which is either non-existent or configurable in the proxy target") if desc.configurable == false && td.configurable == true
      if !td.accessor? && td.configurable == false && td.writable == true
        js_throw_type("'defineProperty' on proxy: trap returned truish for defining non-configurable property '" + js_to_display(js_key_display(k)) + "' which cannot be non-writable, unless there exists a corresponding non-configurable, non-writable own property of the target object.") if desc.writable == false
    true

  -> define(k, v, flags = ATTR_DEFAULT)
    define_own_property(k, JS:PropDesc.data(v, flags))
    v

  -> has_own?(k)
    get_own_property(k) != nil

  -> has_own_slot?(k)
    true

  -> get_own(k)
    d = get_own_property(k)
    return JS_HOLE if d == nil
    d.accessor? ? nil : d.value

  -> has_property?(k)
    check()
    tgt = @target
    h = @handler
    t = trap("has")
    return jhas_property?(tgt, k) if t == nil
    v = js_to_boolean(js_call_arr(t, h, [tgt, k]))
    if !v
      td = jget_own_property(tgt, k)
      if td != nil
        js_throw_type("'has' on proxy: trap returned falsish for property '" + js_to_display(js_key_display(k)) + "' which exists in the proxy target as non-configurable") if td.configurable == false
        js_throw_type("'has' on proxy: trap returned falsish for property '" + js_to_display(js_key_display(k)) + "' but the proxy target is not extensible") if !jextensible?(tgt)
    v

  -> get(k, receiver = JS_HOLE)
    receiver = self if receiver == JS_HOLE
    check()
    tgt = @target
    h = @handler
    t = trap("get")
    return jget(tgt, k, receiver) if t == nil
    v = js_call_arr(t, h, [tgt, k, js_dec_recv(receiver)])
    td = jget_own_property(tgt, k)
    if td != nil && td.configurable == false
      if !td.accessor? && td.writable == false
        js_throw_type("'get' on proxy: property '" + js_to_display(js_key_display(k)) + "' is a read-only and non-configurable data property on the proxy target but the proxy did not return its actual value") if !js_same_value(v, td.value)
      if td.accessor? && td.getter == nil
        js_throw_type("'get' on proxy: property '" + js_to_display(js_key_display(k)) + "' is a non-configurable accessor property on the proxy target and does not have a getter function, but the trap did not return 'undefined'") if v != nil
    v

  -> set(k, v, receiver = JS_HOLE)
    receiver = self if receiver == JS_HOLE
    check()
    tgt = @target
    h = @handler
    t = trap("set")
    return jset(tgt, k, v, receiver) if t == nil
    ok = js_to_boolean(js_call_arr(t, h, [tgt, k, v, js_dec_recv(receiver)]))
    return false if !ok
    td = jget_own_property(tgt, k)
    if td != nil && td.configurable == false
      if !td.accessor? && td.writable == false
        js_throw_type("'set' on proxy: trap returned truish for property '" + js_to_display(js_key_display(k)) + "' which exists in the proxy target as a non-configurable and non-writable data property with a different value") if !js_same_value(v, td.value)
      if td.accessor? && td.setter == nil
        js_throw_type("'set' on proxy: trap returned truish for property '" + js_to_display(js_key_display(k)) + "' which exists in the proxy target as a non-configurable and non-writable accessor property without a setter")
    true

  -> put_own(k, v)
    set(k, v, self)

  -> delete_own(k)
    check()
    tgt = @target
    h = @handler
    t = trap("deleteProperty")
    return jdelete(tgt, k) if t == nil
    ok = js_to_boolean(js_call_arr(t, h, [tgt, k]))
    return false if !ok
    td = jget_own_property(tgt, k)
    if td != nil
      js_throw_type("'deleteProperty' on proxy: trap returned truish for property '" + js_to_display(js_key_display(k)) + "' which is non-configurable in the proxy target") if td.configurable == false
      js_throw_type("'deleteProperty' on proxy: trap returned truish for property '" + js_to_display(js_key_display(k)) + "' but the proxy target is non-extensible") if !jextensible?(tgt)
    true

  -> own_keys
    check()
    tgt = @target
    h = @handler
    t = trap("ownKeys")
    return jown_keys(tgt) if t == nil
    res = js_call_arr(t, h, [tgt])
    js_throw_type("CreateListFromArrayLike called on non-object") if !js_object?(res)
    keys = []
    lst = js_list_from_array_like(res)
    i = 0
    while i < lst.size
      k = lst[i]
      js_throw_type(js_err_display(k) + " is not a valid property name") if !(js_string?(k) || k.is_a?(JS:Symbol))
      js_throw_type("'ownKeys' on proxy: trap returned duplicate entries") if keys.include?(k)
      keys.push(k)
      i += 1
    ext = jextensible?(tgt)
    tk = jown_keys(tgt)
    i = 0
    while i < tk.size
      k = tk[i]
      d = jget_own_property(tgt, k)
      if (d != nil && d.configurable == false) || !ext
        js_throw_type("'ownKeys' on proxy: trap result did not include '" + js_to_display(js_key_display(k)) + "'") if !keys.include?(k)
      i += 1
    if !ext
      i = 0
      while i < keys.size
        js_throw_type("'ownKeys' on proxy: trap returned extra keys but proxy target is non-extensible") if !tk.include?(keys[i])
        i += 1
    keys

  -> enumerable?(k)
    d = get_own_property(k)
    d != nil && d.enumerable == true

  -> accessor?(k)
    false

  -> attr(k)
    d = get_own_property(k)
    return ATTR_DEFAULT if d == nil
    d.flags | (d.accessor? ? ATTR_ACCESSOR : 0)

  -> call_obj(this, args)
    check()
    tgt = @target
    h = @handler
    t = trap("apply")
    return js_call_arr(tgt, this, args) if t == nil
    js_call_arr(t, h, [tgt, this, js_realm().adopt_array(args.dup)])

  -> construct(args, nt)
    check()
    tgt = @target
    h = @handler
    t = trap("construct")
    return js_construct(tgt, args, nt) if t == nil
    o = js_call_arr(t, h, [tgt, js_realm().adopt_array(args.dup), nt])
    js_throw_type("proxy \[\[Construct]] must return an object") if !js_object?(o)
    o

# IsCompatiblePropertyDescriptor (§10.1.6.2): would ValidateAndApplyPropertyDescriptor
# accept desc over current (nil: absent) on an object with this extensibility?
-> js_desc_compatible?(ext, desc, cur)
  return ext if cur == nil
  if cur.configurable == false
    return false if desc.configurable == true
    return false if desc.enumerable != nil && desc.enumerable != cur.enumerable
    if desc.accessor? || desc.data?
      return false if desc.accessor? != cur.accessor?
    if cur.accessor?
      return false if desc.has_get && desc.getter != cur.getter
      return false if desc.has_set && desc.setter != cur.setter
    elsif cur.writable == false
      return false if desc.writable == true
      return false if desc.has_value && !js_same_value(desc.value, cur.value)
  true

-> js_from_partial_desc(d)
  o = js_realm().new_object
  o.put_own("value", d.value) if d.has_value
  o.put_own("writable", d.writable) if d.writable != nil
  o.put_own("get", d.getter) if d.has_get
  o.put_own("set", d.setter) if d.has_set
  o.put_own("enumerable", d.enumerable) if d.enumerable != nil
  o.put_own("configurable", d.configurable) if d.configurable != nil
  o

# Proxies own no properties; they share one root shape with a null prototype.
JS_PROXY_SHAPE = [nil]

-> js_proxy_create(target, handler, nt)
  js_throw_type("Constructor Proxy requires 'new'") if nt == nil
  js_throw_type("Cannot create proxy with a non-object as target or handler") if !js_object?(target) || !js_object?(handler)
  JS_PROXY_SHAPE[0] = js_root_shape(nil, 0, 4) if JS_PROXY_SHAPE[0] == nil
  JS:Proxy.new(JS_PROXY_SHAPE[0], target, handler)

-> js_proxy_revocable(target, handler)
  r = js_realm()
  p = js_proxy_create(target, handler, true)
  res = r.new_object
  res.put_own("proxy", p)
  rv = js_keep(r.native("", 0, ->(this, args, nt) js_proxy_revoke(p)), [p])
  res.put_own("revoke", rv)
  res

-> js_proxy_revoke(p)
  p.handler = nil
  p.target = nil
  nil

js_install(->(r) js_install_reflect(r))

-> js_install_reflect(r)
  pc = r.native("Proxy", 2, ->(this, args, nt) js_proxy_create(js_arg(args, 0), js_arg(args, 1), nt), true)
  r.global.define("Proxy", pc, BUILTIN_ATTRS)
  r.method(pc, "revocable", 2, ->(this, args, nt) js_proxy_revocable(js_arg(args, 0), js_arg(args, 1)))
  rf = js_new_object(r.object_proto)
  r.global.define("Reflect", rf, BUILTIN_ATTRS)
  rf.define(SYM_TO_STRING_TAG, "Reflect", ATTR_C)
  r.method(rf, "apply", 3, ->(this, args, nt) js_reflect_apply(args))
  r.method(rf, "construct", 2, ->(this, args, nt) js_reflect_construct(args))
  r.method(rf, "defineProperty", 3, ->(this, args, nt) js_reflect_define(js_arg(args, 0), js_arg(args, 1), js_arg(args, 2)))
  r.method(rf, "deleteProperty", 2, ->(this, args, nt) js_reflect_delete(js_arg(args, 0), js_arg(args, 1)))
  r.method(rf, "get", 2, ->(this, args, nt) js_reflect_get(args))
  r.method(rf, "getOwnPropertyDescriptor", 2, ->(this, args, nt) js_reflect_gopd(js_arg(args, 0), js_arg(args, 1)))
  r.method(rf, "getPrototypeOf", 1, ->(this, args, nt) jget_prototype_of(js_req_obj(js_arg(args, 0), "Reflect.getPrototypeOf")))
  r.method(rf, "has", 2, ->(this, args, nt) js_reflect_has(js_arg(args, 0), js_arg(args, 1)))
  r.method(rf, "isExtensible", 1, ->(this, args, nt) jextensible?(js_req_obj(js_arg(args, 0), "Reflect.isExtensible")))
  r.method(rf, "ownKeys", 1, ->(this, args, nt) r.adopt_array(jown_keys(js_req_obj(js_arg(args, 0), "Reflect.ownKeys")).dup))
  r.method(rf, "preventExtensions", 1, ->(this, args, nt) jprevent_extensions(js_req_obj(js_arg(args, 0), "Reflect.preventExtensions")))
  r.method(rf, "set", 3, ->(this, args, nt) js_reflect_set(args))
  r.method(rf, "setPrototypeOf", 2, ->(this, args, nt) js_reflect_set_proto(js_arg(args, 0), js_arg(args, 1)))
  nil

-> js_reflect_apply(args)
  fn = js_arg(args, 0)
  js_throw_type("Reflect.apply target is not a function") if !js_callable?(fn)
  js_call_arr(fn, js_arg(args, 1), js_list_from_array_like(js_req_obj(js_arg(args, 2), "Reflect.apply")))

-> js_reflect_define(o, k, d)
  js_req_obj(o, "Reflect.defineProperty")
  key = js_to_property_key(k)
  jdefine_own_property(o, key, js_to_desc(d))

-> js_reflect_delete(o, k)
  js_req_obj(o, "Reflect.deleteProperty")
  jdelete(o, js_to_property_key(k))

-> js_reflect_get(args)
  o = js_req_obj(js_arg(args, 0), "Reflect.get")
  key = js_to_property_key(js_arg(args, 1))
  jget(o, key, args.size > 2 ? js_enc_recv(args[2]) : o)

-> js_reflect_gopd(o, k)
  js_req_obj(o, "Reflect.getOwnPropertyDescriptor")
  js_from_desc(jget_own_property(o, js_to_property_key(k)))

-> js_reflect_has(o, k)
  js_req_obj(o, "Reflect.has")
  jhas_property?(o, js_to_property_key(k))

-> js_reflect_set(args)
  o = js_req_obj(js_arg(args, 0), "Reflect.set")
  key = js_to_property_key(js_arg(args, 1))
  jset(o, key, js_arg(args, 2), args.size > 3 ? js_enc_recv(args[3]) : o)

-> js_reflect_construct(args)
  t = js_arg(args, 0)
  js_throw_type(js_err_display(t) + " is not a constructor") if !js_is_constructor?(t)
  nt = args.size > 2 ? args[2] : t
  js_throw_type(js_err_display(nt) + " is not a constructor") if !js_is_constructor?(nt)
  js_construct(t, js_list_from_array_like(js_req_obj(js_arg(args, 1), "Reflect.construct")), nt)

-> js_reflect_set_proto(o, p)
  js_req_obj(o, "Reflect.setPrototypeOf")
  js_throw_type("Object prototype may only be an Object or null: " + js_err_display(p)) if !(js_object?(p) || p == JS_NULL)
  jset_prototype_of(o, p)

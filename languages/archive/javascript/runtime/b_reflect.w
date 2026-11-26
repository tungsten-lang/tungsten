# blade/js/b_reflect — Proxy (all traps, the main invariants) and Reflect.

+ JsProxy < JsObject
  rw :target, :handler

  -> proxy?
    true

  -> callable?
    @target != nil && @target.callable?

  -> is_constructor?
    @target != nil && js_is_constructor?(@target)

  -> target_obj
    @target

  -> check
    js_throw_type("Cannot perform operation on a revoked proxy") if @handler == nil
    nil

  -> trap(name)
    check()
    t = @handler.get(name, @handler)
    return nil if js_nullish?(t)
    js_throw_type("proxy trap " + name + " is not a function") if !(t.is_a?(JsObject) && t.callable?)
    t

  -> get_prototype_of
    t = trap("getPrototypeOf")
    return @target.get_prototype_of if t == nil
    p = js_call(t, @handler, [@target])
    js_throw_type("'getPrototypeOf' on proxy: trap returned neither object nor null") if !(p.is_a?(JsObject) || p == JS_NULL)
    if !@target.is_extensible?
      js_throw_type("'getPrototypeOf' on proxy: proxy target is non-extensible but the trap did not return its actual prototype") if p != @target.get_prototype_of
    p

  -> set_prototype_of(p)
    t = trap("setPrototypeOf")
    return @target.set_prototype_of(p) if t == nil
    ok = js_to_boolean(js_call(t, @handler, [@target, p]))
    return false if !ok
    if !@target.is_extensible?
      js_throw_type("'setPrototypeOf' on proxy: trap returned truish for setting a new prototype on the non-extensible proxy target") if p != @target.get_prototype_of
    true

  -> is_extensible?
    t = trap("isExtensible")
    return @target.is_extensible? if t == nil
    v = js_to_boolean(js_call(t, @handler, [@target]))
    js_throw_type("'isExtensible' on proxy: trap result does not reflect extensibility of proxy target") if v != @target.is_extensible?
    v

  -> prevent_extensions
    t = trap("preventExtensions")
    return @target.prevent_extensions if t == nil
    v = js_to_boolean(js_call(t, @handler, [@target]))
    js_throw_type("'preventExtensions' on proxy: trap returned truish but the proxy target is extensible") if v && @target.is_extensible?
    v

  -> extensible
    is_extensible?

  -> get_own_property(k)
    t = trap("getOwnPropertyDescriptor")
    return @target.get_own_property(k) if t == nil
    res = js_call(t, @handler, [@target, k])
    td = @target.get_own_property(k)
    if res == nil
      return nil if td == nil
      js_throw_type("'getOwnPropertyDescriptor' on proxy: trap returned undefined for property '" + js_key_display(k).to_s + "' which is non-configurable in the proxy target") if td.configurable == false
      js_throw_type("'getOwnPropertyDescriptor' on proxy: trap returned undefined for property '" + js_key_display(k).to_s + "' which exists in the non-extensible proxy target") if !@target.is_extensible?
      return nil
    js_throw_type("'getOwnPropertyDescriptor' on proxy: trap returned neither object nor undefined for property '" + js_key_display(k).to_s + "'") if !res.is_a?(JsObject)
    d = js_to_desc(res)
    d.configurable = false if d.configurable == nil
    d.enumerable = false if d.enumerable == nil
    if !d.accessor?
      d.has_value = true
      d.writable = false if d.writable == nil
    js_throw_type("'getOwnPropertyDescriptor' on proxy: trap reported non-configurability for property '" + js_key_display(k).to_s + "' which is either non-existent or configurable in the proxy target") if d.configurable == false && (td == nil || td.configurable == true)
    js_throw_type("'getOwnPropertyDescriptor' on proxy: trap returned descriptor for property '" + js_key_display(k).to_s + "' that is incompatible with the existing property in the proxy target") if td == nil && !@target.is_extensible?
    d

  -> define_own_property(k, desc)
    t = trap("defineProperty")
    return @target.define_own_property(k, desc) if t == nil
    ok = js_to_boolean(js_call(t, @handler, [@target, k, js_from_partial_desc(desc)]))
    return false if !ok
    td = @target.get_own_property(k)
    if td == nil
      js_throw_type("'defineProperty' on proxy: trap returned truish for adding property '" + js_key_display(k).to_s + "'  to the non-extensible proxy target") if !@target.is_extensible?
      js_throw_type("'defineProperty' on proxy: trap returned truish for defining non-configurable property '" + js_key_display(k).to_s + "' which is either non-existent or configurable in the proxy target") if desc.configurable == false
    else
      js_throw_type("'defineProperty' on proxy: trap returned truish for defining non-configurable property '" + js_key_display(k).to_s + "' which is either non-existent or configurable in the proxy target") if desc.configurable == false && td.configurable == true
    true

  -> has_own?(k)
    get_own_property(k) != nil

  -> has_own_slot?(k)
    true

  -> own_value(k, receiver)
    get(k, receiver)

  -> has_property?(k)
    t = trap("has")
    return @target.has_property?(k) if t == nil
    v = js_to_boolean(js_call(t, @handler, [@target, k]))
    if !v
      td = @target.get_own_property(k)
      if td != nil
        js_throw_type("'has' on proxy: trap returned falsish for property '" + js_key_display(k).to_s + "' which exists in the proxy target as non-configurable") if td.configurable == false
        js_throw_type("'has' on proxy: trap returned falsish for property '" + js_key_display(k).to_s + "' but the proxy target is not extensible") if !@target.is_extensible?
    v

  -> get(k, receiver = nil)
    receiver = self if receiver == nil
    t = trap("get")
    return @target.get(k, receiver) if t == nil
    v = js_call(t, @handler, [@target, k, receiver])
    td = @target.get_own_property(k)
    if td != nil && td.configurable == false
      if !td.accessor? && td.writable == false
        js_throw_type("'get' on proxy: property '" + js_key_display(k).to_s + "' is a read-only and non-configurable data property on the proxy target but the proxy did not return its actual value") if !js_same_value(v, td.value)
      if td.accessor? && td.getter == nil
        js_throw_type("'get' on proxy: property '" + js_key_display(k).to_s + "' is a non-configurable accessor property on the proxy target and does not have a getter function, but the trap did not return 'undefined'") if v != nil
    v

  -> get_idx(i)
    get(i.to_s, self)

  -> set(k, v, receiver = nil)
    receiver = self if receiver == nil
    t = trap("set")
    return @target.set(k, v, receiver) if t == nil
    ok = js_to_boolean(js_call(t, @handler, [@target, k, v, receiver]))
    return false if !ok
    td = @target.get_own_property(k)
    if td != nil && td.configurable == false
      if !td.accessor? && td.writable == false
        js_throw_type("'set' on proxy: trap returned truish for property '" + js_key_display(k).to_s + "' which exists in the proxy target as a non-configurable and non-writable data property with a different value") if !js_same_value(v, td.value)
      if td.accessor? && td.setter == nil
        js_throw_type("'set' on proxy: trap returned truish for property '" + js_key_display(k).to_s + "' which exists in the proxy target as a non-configurable and non-writable accessor property without a setter")
    true

  -> set_idx(i, v)
    set(i.to_s, v, self)

  -> put_own(k, v)
    set(k, v, self)

  -> delete_own(k)
    t = trap("deleteProperty")
    return @target.delete_own(k) if t == nil
    ok = js_to_boolean(js_call(t, @handler, [@target, k]))
    return false if !ok
    td = @target.get_own_property(k)
    if td != nil
      js_throw_type("'deleteProperty' on proxy: trap returned truish for property '" + js_key_display(k).to_s + "' which is non-configurable in the proxy target") if td.configurable == false
      js_throw_type("'deleteProperty' on proxy: trap returned truish for property '" + js_key_display(k).to_s + "' but the proxy target is non-extensible") if !@target.is_extensible?
    true

  -> own_keys
    t = trap("ownKeys")
    return @target.own_keys if t == nil
    res = js_call(t, @handler, [@target])
    js_throw_type("CreateListFromArrayLike called on non-object") if !res.is_a?(JsObject)
    keys = []
    js_list_from_array_like(res).each ->(k)
      js_throw_type(js_to_display(k) + " is not a valid property name") if !(k.is_a?(String) || k.is_a?(JsSymbol))
      js_throw_type("'ownKeys' on proxy: trap returned duplicate entries") if keys.include?(k)
      keys.push(k)
    tk = @target.own_keys
    ext = @target.is_extensible?
    tk.each ->(k)
      d = @target.get_own_property(k)
      if (d != nil && d.configurable == false) || !ext
        js_throw_type("'ownKeys' on proxy: trap result did not include '" + js_key_display(k).to_s + "'") if !keys.include?(k)
    if !ext
      keys.each ->(k)
        js_throw_type("'ownKeys' on proxy: trap returned extra keys but proxy target is non-extensible") if !tk.include?(k)
    keys

  -> enumerable?(k)
    d = get_own_property(k)
    d != nil && d.enumerable == true

  -> accessor?(k)
    false

  -> call_obj(this, args)
    check()
    t = trap("apply")
    return js_call(@target, this, args) if t == nil
    js_call(t, @handler, [@target, this, JS_REALM[0].new_array(args)])

  -> construct_obj(args, nt)
    check()
    t = trap("construct")
    return js_construct(@target, args, nt == self ? @target : nt) if t == nil
    o = js_call(t, @handler, [@target, JS_REALM[0].new_array(args), nt])
    js_throw_type("proxy \[\[Construct]] must return an object") if !o.is_a?(JsObject)
    o

-> js_from_partial_desc(d)
  o = JS_REALM[0].new_object
  o.put_own("value", d.value) if d.has_value
  o.put_own("writable", d.writable) if d.writable != nil
  o.put_own("get", d.getter) if d.has_get
  o.put_own("set", d.setter) if d.has_set
  o.put_own("enumerable", d.enumerable) if d.enumerable != nil
  o.put_own("configurable", d.configurable) if d.configurable != nil
  o

-> js_proxy_create(target, handler, nt)
  js_throw_type("Constructor Proxy requires 'new'") if nt == nil
  js_throw_type("Cannot create proxy with a non-object as target or handler") if !target.is_a?(JsObject) || !handler.is_a?(JsObject)
  p = JsProxy.new(JS_NULL, target.callable? ? "Function" : "Object")
  p.target = target
  p.handler = handler
  p

-> js_proxy_revocable(target, handler)
  r = JS_REALM[0]
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
  rf = JsObject.new(r.object_proto, "Object")
  r.global.define("Reflect", rf, BUILTIN_ATTRS)
  rf.define(SYM_TO_STRING_TAG, "Reflect", ATTR_C)
  r.method(rf, "apply", 3, ->(this, args, nt) js_call_named(js_arg(args, 0), js_arg(args, 1), js_list_from_array_like(js_req_obj(js_arg(args, 2), "Reflect.apply")), "Reflect.apply target"))
  r.method(rf, "construct", 2, ->(this, args, nt) js_reflect_construct(args))
  r.method(rf, "defineProperty", 3, ->(this, args, nt) js_req_obj(js_arg(args, 0), "Reflect.defineProperty").define_own_property(js_to_property_key(js_arg(args, 1)), js_to_desc(js_arg(args, 2))))
  r.method(rf, "deleteProperty", 2, ->(this, args, nt) js_req_obj(js_arg(args, 0), "Reflect.deleteProperty").delete_own(js_to_property_key(js_arg(args, 1))))
  r.method(rf, "get", 2, ->(this, args, nt) js_req_obj(js_arg(args, 0), "Reflect.get").get(js_to_property_key(js_arg(args, 1)), args.size > 2 ? args[2] : args[0]))
  r.method(rf, "getOwnPropertyDescriptor", 2, ->(this, args, nt) js_from_desc(js_req_obj(js_arg(args, 0), "Reflect.getOwnPropertyDescriptor").get_own_property(js_to_property_key(js_arg(args, 1)))))
  r.method(rf, "getPrototypeOf", 1, ->(this, args, nt) js_req_obj(js_arg(args, 0), "Reflect.getPrototypeOf").get_prototype_of)
  r.method(rf, "has", 2, ->(this, args, nt) js_req_obj(js_arg(args, 0), "Reflect.has").has_property?(js_to_property_key(js_arg(args, 1))))
  r.method(rf, "isExtensible", 1, ->(this, args, nt) js_req_obj(js_arg(args, 0), "Reflect.isExtensible").is_extensible?)
  r.method(rf, "ownKeys", 1, ->(this, args, nt) r.new_array(js_req_obj(js_arg(args, 0), "Reflect.ownKeys").own_keys))
  r.method(rf, "preventExtensions", 1, ->(this, args, nt) js_req_obj(js_arg(args, 0), "Reflect.preventExtensions").prevent_extensions)
  r.method(rf, "set", 3, ->(this, args, nt) js_req_obj(js_arg(args, 0), "Reflect.set").set(js_to_property_key(js_arg(args, 1)), js_arg(args, 2), args.size > 3 ? args[3] : args[0]))
  r.method(rf, "setPrototypeOf", 2, ->(this, args, nt) js_reflect_set_proto(js_arg(args, 0), js_arg(args, 1)))
  nil

-> js_reflect_construct(args)
  t = js_arg(args, 0)
  js_throw_type(js_to_display(t) + " is not a constructor") if !(t.is_a?(JsObject) && js_is_constructor?(t))
  nt = args.size > 2 ? args[2] : t
  js_throw_type(js_to_display(nt) + " is not a constructor") if !(nt.is_a?(JsObject) && js_is_constructor?(nt))
  js_construct(t, js_list_from_array_like(js_req_obj(js_arg(args, 1), "Reflect.construct")), nt)

-> js_reflect_set_proto(o, p)
  js_req_obj(o, "Reflect.setPrototypeOf")
  js_throw_type("Object prototype may only be an Object or null: " + js_to_display(p)) if !(p.is_a?(JsObject) || p == JS_NULL)
  o.set_prototype_of(p)

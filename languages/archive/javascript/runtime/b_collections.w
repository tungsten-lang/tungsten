# blade/js/b_collections — Map, Set, WeakMap, WeakSet, WeakRef, FinalizationRegistry.
#
# Entries form a doubly linked list in insertion order with a hash index. A deleted entry
# keeps its forward link, so iterators parked on it continue correctly.

+ JsMapEntry
  rw :key, :value, :next, :prev, :dead
  -> new(@key, @value)
    @next = nil
    @prev = nil
    @dead = false

+ JsMapData
  rw :index, :big, :head, :tail, :size
  -> new
    @index = {}
    @big = nil
    @head = nil
    @tail = nil
    @size = 0

+ JsMapObj < JsObject
  rw :data

+ JsNanKey
  -> new
JS_NAN_KEY = JsNanKey.new

# The hash key for a JS value under SameValueZero.
-> js_map_key(k)
  if k.is_a?(Float)
    return JS_NAN_KEY if k != k
    return ~0.0 if k == ~0.0
  k

-> js_map_find(d, k)
  if k.is_a?(JsBigInt)
    return nil if d.big == nil
    return d.big[k.v]
  d.index[js_map_key(k)]

-> js_map_put(d, k, v)
  e = js_map_find(d, k)
  if e != nil
    e.value = v
    return nil
  k = ~0.0 if k.is_a?(Float) && k == ~0.0
  e = JsMapEntry.new(k, v)
  if k.is_a?(JsBigInt)
    d.big = {} if d.big == nil
    d.big[k.v] = e
  else
    d.index[js_map_key(k)] = e
  if d.tail == nil
    d.head = e
  else
    d.tail.next = e
    e.prev = d.tail
  d.tail = e
  d.size += 1
  nil

-> js_map_remove(d, k)
  e = js_map_find(d, k)
  return false if e == nil
  if k.is_a?(JsBigInt)
    d.big.delete(k.v)
  else
    d.index.delete(js_map_key(k))
  e.dead = true
  if e.prev != nil
    e.prev.next = e.next
  else
    d.head = e.next
  if e.next != nil
    e.next.prev = e.prev
  else
    d.tail = e.prev
  d.size -= 1
  true

-> js_map_clear(d)
  e = d.head
  while e != nil
    e.dead = true
    e = e.next
  d.index = {}
  d.big = nil
  d.head = nil
  d.tail = nil
  d.size = 0
  nil

-> js_map_new
  m = JsMapObj.new(JS_REALM[0].intrinsic("Map.prototype"), "Map")
  m.data = JsMapData.new
  m

-> js_map_set(m, k, v)
  js_map_put(m.data, k, v)
  m

-> js_this_map(v, cls)
  js_throw_type("Method " + cls + ".prototype method called on incompatible receiver " + js_to_display(v)) if !(v.is_a?(JsMapObj) && v.cls == cls)
  v.data

-> js_coll_ctor(cls, args, nt, adder_name, pairs)
  js_throw_type("Constructor " + cls + " requires 'new'") if nt == nil
  r = JS_REALM[0]
  m = JsMapObj.new(r.proto_from(nt, cls), cls)
  m.data = JsMapData.new
  it = js_arg(args, 0)
  return m if js_nullish?(it)
  adder = m.get(adder_name, m)
  js_throw_type("'" + js_to_display(adder) + "' returned for property '" + adder_name + "' of object '#<" + cls + ">' is not callable") if !(adder.is_a?(JsObject) && adder.callable?)
  native_add = adder.is_a?(JsFunction) && adder.native != nil && adder == r.intrinsic("%" + cls + "_" + adder_name + "%")
  js_for_of(it, ->(e) js_coll_add_item(m, adder, native_add, e, pairs, cls))
  m

-> js_coll_add_item(m, adder, native_add, e, pairs, cls)
  if pairs
    js_throw_type("Iterator value " + js_to_display(e) + " is not an entry object") if !e.is_a?(JsObject)
    k = js_getidx(e, ~0.0)
    v = js_getidx(e, ~1.0)
    if native_add
      js_weak_check(k, cls) if cls == "WeakMap"
      js_map_put(m.data, k, v)
    else
      js_call(adder, m, [k, v])
  else
    if native_add
      js_weak_check(e, cls) if cls == "WeakSet"
      js_map_put(m.data, e, e)
    else
      js_call(adder, m, [e])
  nil

-> js_weak_check(k, cls)
  js_throw_type("Invalid value used " + (cls == "WeakMap" ? "as weak map key" : "in weak set")) if !(k.is_a?(JsObject) || (k.is_a?(JsSymbol) && !js_registered_symbol?(k)))

-> js_registered_symbol?(s)
  found = false
  JS_REALM[0].symbol_registry.each ->(k, v)
    found = true if v == s
  found

+ JsMapIter < JsObject
  rw :map, :cur, :kind, :started, :done

-> js_map_iter(m, kind, proto_name)
  it = JsMapIter.new(JS_REALM[0].intrinsic(proto_name), "Map Iterator")
  it.map = m
  it.cur = nil
  it.kind = kind
  it.started = false
  it.done = false
  it

-> js_map_iter_next(it)
  js_throw_type("next method called on incompatible receiver") if !it.is_a?(JsMapIter)
  return js_iter_result(nil, true) if it.done
  d = it.map.data
  e = nil
  if !it.started
    it.started = true
    e = d.head
  else
    e = it.cur.next
  while e != nil && e.dead
    e = e.next
  if e == nil
    it.done = true
    it.cur = nil
    return js_iter_result(nil, true)
  it.cur = e
  k = it.kind
  return js_iter_result(e.key, false) if k == :keys
  return js_iter_result(e.value, false) if k == :values
  js_iter_result(JS_REALM[0].new_array([e.key, e.value]), false)

-> js_coll_for_each(m, cls, f, t)
  d = js_this_map(m, cls)
  js_throw_type(js_to_display(f) + " is not a function") if !(f.is_a?(JsObject) && f.callable?)
  e = d.head
  while e != nil
    if !e.dead
      js_call(f, t, [e.value, e.key, m])
    nx = e.next
    # skip forward over entries deleted during the callback
    while nx != nil && nx.dead
      nx = nx.next
    e = nx
  nil

-> js_set_op(this, other, op)
  d = js_this_map(this, "Set")
  r = JS_REALM[0]
  js_throw_type("other is not an object") if !other.is_a?(JsObject)
  osize = js_to_number(other.get("size", other))
  js_throw_type("The 'size' property must be a number") if osize != osize
  has = other.get("has", other)
  keys = other.get("keys", other)
  js_throw_type("other.has is not a function") if !(has.is_a?(JsObject) && has.callable?)
  js_throw_type("other.keys is not a function") if !(keys.is_a?(JsObject) && keys.callable?)
  mine = []
  e = d.head
  while e != nil
    mine.push(e.key) if !e.dead
    e = e.next
  theirs = js_to_list_iter(js_call(keys, other, JS_NO_ARGS))
  out = js_set_new_empty()
  od = out.data
  if op == :union
    mine.each ->(k) js_map_put(od, k, k)
    theirs.each ->(k) js_map_put(od, k, k)
  elsif op == :intersection
    mine.each ->(k)
      js_map_put(od, k, k) if js_truthy(js_call(has, other, [k]))
  elsif op == :difference
    mine.each ->(k)
      js_map_put(od, k, k) if !js_truthy(js_call(has, other, [k]))
  elsif op == :symmetric
    mine.each ->(k) js_map_put(od, k, k)
    theirs.each ->(k)
      if js_map_find(d, k) != nil
        js_map_remove(od, k)
      else
        js_map_put(od, k, k)
  elsif op == :subset
    return mine.all?(->(k) js_truthy(js_call(has, other, [k])))
  elsif op == :superset
    return theirs.all?(->(k) js_map_find(d, k) != nil)
  elsif op == :disjoint
    return !mine.any?(->(k) js_truthy(js_call(has, other, [k])))
  out

-> js_to_list_iter(it)
  out = []
  nx = it.get("next", it)
  rec = JsIterRecord.new(it, nx)
  while true
    x = js_iter_step(rec)
    break if x == JS_ITER_DONE
    out.push(x)
  out

-> js_set_new_empty
  s = JsMapObj.new(JS_REALM[0].intrinsic("Set.prototype"), "Set")
  s.data = JsMapData.new
  s

+ JsWeakRef < JsObject
  rw :target

js_install(->(r) js_install_collections(r))

-> js_install_collections(r)
  op = r.object_proto
  # Map
  mp = JsObject.new(op, "Object")
  mc = r.constructor("Map", 0, ->(this, args, nt) js_coll_ctor("Map", args, nt, "set", true), mp)
  r.method(mp, "get", 1, ->(this, args, nt) js_map_get(js_this_map(this, "Map"), js_arg(args, 0)))
  ms = r.method(mp, "set", 2, ->(this, args, nt) js_map_set_m(this, "Map", js_arg(args, 0), js_arg(args, 1)))
  r.set_intrinsic("%Map_set%", ms)
  r.method(mp, "has", 1, ->(this, args, nt) js_map_find(js_this_map(this, "Map"), js_arg(args, 0)) != nil)
  r.method(mp, "delete", 1, ->(this, args, nt) js_map_remove(js_this_map(this, "Map"), js_arg(args, 0)))
  r.method(mp, "clear", 0, ->(this, args, nt) js_map_clear(js_this_map(this, "Map")))
  r.method(mp, "forEach", 1, ->(this, args, nt) js_coll_for_each(this, "Map", js_arg(args, 0), js_arg(args, 1)))
  r.getter(mp, "size", ->(this, args, nt) js_this_map(this, "Map").size + ~0.0)
  r.method(mp, "keys", 0, ->(this, args, nt) js_map_iter_checked(this, "Map", :keys))
  r.method(mp, "values", 0, ->(this, args, nt) js_map_iter_checked(this, "Map", :values))
  me = r.method(mp, "entries", 0, ->(this, args, nt) js_map_iter_checked(this, "Map", :entries))
  mp.define(SYM_ITERATOR, me, BUILTIN_ATTRS)
  mp.define(SYM_TO_STRING_TAG, "Map", ATTR_C)
  r.method(mc, "groupBy", 2, ->(this, args, nt) js_object_group_by(js_arg(args, 0), js_arg(args, 1), true))
  r.getter(mc, SYM_SPECIES, ->(this, args, nt) this)
  mip = JsObject.new(r.intrinsic("%IteratorPrototype%"), "Object")
  r.set_intrinsic("%MapIteratorPrototype%", mip)
  r.method(mip, "next", 0, ->(this, args, nt) js_map_iter_next(this))
  mip.define(SYM_TO_STRING_TAG, "Map Iterator", ATTR_C)
  # Set
  sp = JsObject.new(op, "Object")
  sc = r.constructor("Set", 0, ->(this, args, nt) js_coll_ctor("Set", args, nt, "add", false), sp)
  sa = r.method(sp, "add", 1, ->(this, args, nt) js_map_set_m(this, "Set", js_arg(args, 0), js_arg(args, 0)))
  r.set_intrinsic("%Set_add%", sa)
  r.method(sp, "has", 1, ->(this, args, nt) js_map_find(js_this_map(this, "Set"), js_arg(args, 0)) != nil)
  r.method(sp, "delete", 1, ->(this, args, nt) js_map_remove(js_this_map(this, "Set"), js_arg(args, 0)))
  r.method(sp, "clear", 0, ->(this, args, nt) js_map_clear(js_this_map(this, "Set")))
  r.method(sp, "forEach", 1, ->(this, args, nt) js_coll_for_each(this, "Set", js_arg(args, 0), js_arg(args, 1)))
  r.getter(sp, "size", ->(this, args, nt) js_this_map(this, "Set").size + ~0.0)
  r.method(sp, "entries", 0, ->(this, args, nt) js_map_iter_checked(this, "Set", :entries))
  sv = r.method(sp, "values", 0, ->(this, args, nt) js_map_iter_checked(this, "Set", :keys))
  sp.define("keys", sv, BUILTIN_ATTRS)
  sp.define(SYM_ITERATOR, sv, BUILTIN_ATTRS)
  sp.define(SYM_TO_STRING_TAG, "Set", ATTR_C)
  r.method(sp, "union", 1, ->(this, args, nt) js_set_op(this, js_arg(args, 0), :union))
  r.method(sp, "intersection", 1, ->(this, args, nt) js_set_op(this, js_arg(args, 0), :intersection))
  r.method(sp, "difference", 1, ->(this, args, nt) js_set_op(this, js_arg(args, 0), :difference))
  r.method(sp, "symmetricDifference", 1, ->(this, args, nt) js_set_op(this, js_arg(args, 0), :symmetric))
  r.method(sp, "isSubsetOf", 1, ->(this, args, nt) js_set_op(this, js_arg(args, 0), :subset))
  r.method(sp, "isSupersetOf", 1, ->(this, args, nt) js_set_op(this, js_arg(args, 0), :superset))
  r.method(sp, "isDisjointFrom", 1, ->(this, args, nt) js_set_op(this, js_arg(args, 0), :disjoint))
  r.getter(sc, SYM_SPECIES, ->(this, args, nt) this)
  sip = JsObject.new(r.intrinsic("%IteratorPrototype%"), "Object")
  r.set_intrinsic("%SetIteratorPrototype%", sip)
  r.method(sip, "next", 0, ->(this, args, nt) js_map_iter_next(this))
  sip.define(SYM_TO_STRING_TAG, "Set Iterator", ATTR_C)
  # WeakMap / WeakSet (strong references: Blade pages are short-lived)
  wmp = JsObject.new(op, "Object")
  r.constructor("WeakMap", 0, ->(this, args, nt) js_coll_ctor("WeakMap", args, nt, "set", true), wmp)
  r.method(wmp, "get", 1, ->(this, args, nt) js_map_get(js_this_map(this, "WeakMap"), js_arg(args, 0)))
  wms = r.method(wmp, "set", 2, ->(this, args, nt) js_weak_set(this, "WeakMap", js_arg(args, 0), js_arg(args, 1)))
  r.set_intrinsic("%WeakMap_set%", wms)
  r.method(wmp, "has", 1, ->(this, args, nt) js_map_find(js_this_map(this, "WeakMap"), js_arg(args, 0)) != nil)
  r.method(wmp, "delete", 1, ->(this, args, nt) js_map_remove(js_this_map(this, "WeakMap"), js_arg(args, 0)))
  wmp.define(SYM_TO_STRING_TAG, "WeakMap", ATTR_C)
  wsp = JsObject.new(op, "Object")
  r.constructor("WeakSet", 0, ->(this, args, nt) js_coll_ctor("WeakSet", args, nt, "add", false), wsp)
  wsa = r.method(wsp, "add", 1, ->(this, args, nt) js_weak_set(this, "WeakSet", js_arg(args, 0), js_arg(args, 0)))
  r.set_intrinsic("%WeakSet_add%", wsa)
  r.method(wsp, "has", 1, ->(this, args, nt) js_map_find(js_this_map(this, "WeakSet"), js_arg(args, 0)) != nil)
  r.method(wsp, "delete", 1, ->(this, args, nt) js_map_remove(js_this_map(this, "WeakSet"), js_arg(args, 0)))
  wsp.define(SYM_TO_STRING_TAG, "WeakSet", ATTR_C)
  # WeakRef / FinalizationRegistry
  wrp = JsObject.new(op, "Object")
  r.constructor("WeakRef", 1, ->(this, args, nt) js_weakref_ctor(args, nt), wrp)
  r.method(wrp, "deref", 0, ->(this, args, nt) this.is_a?(JsWeakRef) ? this.target : js_throw_type("WeakRef.prototype.deref called on incompatible receiver"))
  wrp.define(SYM_TO_STRING_TAG, "WeakRef", ATTR_C)
  frp = JsObject.new(op, "Object")
  r.constructor("FinalizationRegistry", 1, ->(this, args, nt) js_fin_reg_ctor(args, nt), frp)
  r.method(frp, "register", 2, ->(this, args, nt) nil)
  r.method(frp, "unregister", 1, ->(this, args, nt) false)
  frp.define(SYM_TO_STRING_TAG, "FinalizationRegistry", ATTR_C)
  nil

-> js_map_get(d, k)
  e = js_map_find(d, k)
  e == nil ? nil : e.value

-> js_map_set_m(m, cls, k, v)
  js_map_put(js_this_map(m, cls), k, v)
  m

-> js_weak_set(m, cls, k, v)
  d = js_this_map(m, cls)
  js_weak_check(k, cls)
  js_map_put(d, k, v)
  m

-> js_map_iter_checked(m, cls, kind)
  js_this_map(m, cls)
  js_map_iter(m, kind, cls == "Map" ? "%MapIteratorPrototype%" : "%SetIteratorPrototype%")

-> js_weakref_ctor(args, nt)
  js_throw_type("Constructor WeakRef requires 'new'") if nt == nil
  t = js_arg(args, 0)
  js_throw_type("WeakRef: target must be an object") if !t.is_a?(JsObject) && !t.is_a?(JsSymbol)
  w = JsWeakRef.new(JS_REALM[0].proto_from(nt, "WeakRef"), "WeakRef")
  w.target = t
  w

-> js_fin_reg_ctor(args, nt)
  js_throw_type("Constructor FinalizationRegistry requires 'new'") if nt == nil
  f = js_arg(args, 0)
  js_throw_type("FinalizationRegistry: cleanup must be callable") if !(f.is_a?(JsObject) && f.callable?)
  JsObject.new(JS_REALM[0].proto_from(nt, "FinalizationRegistry"), "FinalizationRegistry")

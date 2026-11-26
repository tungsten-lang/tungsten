# runtime/b_collections — Map, Set, WeakMap, WeakSet, WeakRef, FinalizationRegistry.
# (Ported from blade/js/b_collections.w.)
#
# A collection is a JS:Special (cls "Map", "Set", …) whose internal is a JS:MapData.
# Entries form a doubly linked list in insertion order with a hash index. A deleted entry
# keeps its forward link, so iterators parked on it continue correctly.

in JS

+ MapEntry
  rw :key, :value, :next, :prev, :dead
  -> new(@key, @value)
    @next = nil
    @prev = nil
    @dead = false

+ MapData
  rw :index, :big, :head, :tail, :size
  -> new
    @index = {}
    @big = nil
    @head = nil
    @tail = nil
    @size = 0

+ NanKey
  -> new
    nil
JS_NAN_KEY = JS:NanKey.new

# The hash key for a JS value under SameValueZero. A JS array is a core Array, which a
# Hash would key by contents, so it is keyed by its address (an Int: JS numbers are
# always Floats, so no number collides with it).
-> js_map_key(k)
  if js_number?(k)
    if k != k
      k = JS_NAN_KEY
    elsif k == ~0.0
      k = ~0.0
  elsif js_array?(k)
    k = (wvalue_bits(k) ## i64) & 140737488355312
  k

-> js_map_find(d, k)
  if k.is_a?(JS:BigIntValue)
    return nil if d.big == nil
    return d.big[k.v]
  d.index[js_map_key(k)]

-> js_map_put(d, k, v)
  e = js_map_find(d, k)
  if e != nil
    e.value = v
    return nil
  k = ~0.0 if js_number?(k) && k == ~0.0
  e = JS:MapEntry.new(k, v)
  if k.is_a?(JS:BigIntValue)
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
  if k.is_a?(JS:BigIntValue)
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

-> js_coll_new(proto, cls)
  m = js_new_special(proto, cls)
  m.internal = JS:MapData.new
  m

-> js_map_new
  js_coll_new(js_realm().intrinsic("Map.prototype"), "Map")

-> js_map_set(m, k, v)
  js_map_put(m.internal, k, v)
  m

-> js_this_map(v, cls)
  js_throw_type("Method " + cls + ".prototype method called on incompatible receiver " + js_err_display(v)) if !(js_special?(v, cls) && v.internal.is_a?(JS:MapData))
  v.internal

-> js_coll_ctor(cls, args, nt, adder_name, pairs)
  js_throw_type("Constructor " + cls + " requires 'new'") if nt == nil
  r = js_realm()
  m = js_coll_new(r.proto_from(nt, cls), cls)
  it = js_arg(args, 0)
  return m if js_nullish?(it)
  adder = m.get(adder_name, m)
  js_throw_type("'" + js_err_display(adder) + "' returned for property '" + adder_name + "' of object '#<" + cls + ">' is not callable") if !js_callable?(adder)
  native_add = adder == r.intrinsic("%" + cls + "_" + adder_name + "%")
  if js_array?(it) && js_array_iter_pristine?(it)
    i = 0
    while i < it.size
      js_coll_add_item(m, adder, native_add, js_arr_elem(it, i), pairs, cls)
      i += 1
    return m
  rec = js_get_iterator(it)
  begin
    while true
      e = js_iter_step(rec)
      break if e == JS_ITER_DONE
      js_coll_add_item(m, adder, native_add, e, pairs, cls)
  rescue ex
    js_iter_close_quiet(rec) if !rec.done
    raise ex
  m

-> js_coll_add_item(m, adder, native_add, e, pairs, cls)
  if pairs
    js_throw_type("Iterator value " + js_err_display(e) + " is not an entry object") if !js_object?(e)
    k = jget(e, "0")
    v = jget(e, "1")
    if native_add
      js_weak_check(k, cls) if cls == "WeakMap"
      js_map_put(m.internal, k, v)
    else
      js_call_arr(adder, m, [k, v])
  else
    if native_add
      js_weak_check(e, cls) if cls == "WeakSet"
      js_map_put(m.internal, e, e)
    else
      js_call_arr(adder, m, [e])
  nil

-> js_weak_check(k, cls)
  js_throw_type("Invalid value used " + (cls == "WeakMap" ? "as weak map key" : "in weak set")) if !(js_object?(k) || (k.is_a?(JS:Symbol) && !js_registered_symbol?(k)))

-> js_registered_symbol?(s)
  reg = js_realm().symbol_registry
  ks = reg.keys
  i = 0
  while i < ks.size
    return true if reg[ks[i]] == s
    i += 1
  false

# A Map or Set iterator's state (the internal of a "Map Iterator" / "Set Iterator").
+ MapIterState
  rw :map, :cur, :kind, :started, :done
  -> new(@map, @kind)
    @cur = nil
    @started = false
    @done = false

-> js_map_iter(m, kind, proto_name)
  it = js_new_special(js_realm().intrinsic(proto_name), proto_name == "%MapIteratorPrototype%" ? "Map Iterator" : "Set Iterator")
  it.internal = JS:MapIterState.new(m, kind)
  it

-> js_map_iter_next(this, cls)
  js_throw_type("next method called on incompatible receiver " + js_err_display(this)) if !(js_special?(this, cls) && this.internal.is_a?(JS:MapIterState))
  it = this.internal
  return js_iter_result(nil, true) if it.done
  d = it.map.internal
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
  js_iter_result(js_realm().adopt_array([e.key, e.value]), false)

-> js_coll_for_each(m, cls, f, t)
  d = js_this_map(m, cls)
  js_throw_type(js_err_display(f) + " is not a function") if !js_callable?(f)
  e = d.head
  while e != nil
    if !e.dead
      js_call_arr(f, t, [e.value, e.key, m])
    nx = e.next
    # skip forward over entries deleted during the callback
    while nx != nil && nx.dead
      nx = nx.next
    e = nx
  nil

# GetSetRecord (§24.2.1.2): [size, has, keys].
-> js_set_record(other)
  js_throw_type("other is not an object") if !js_object?(other)
  rs = jget(other, "size")
  n = js_to_number(rs)
  js_throw_type("The 'size' property must be a number") if n != n
  sz = js_to_integer(n)
  js_throw_range("The 'size' property must not be negative") if sz < ~0.0
  has = jget(other, "has")
  js_throw_type("other.has is not a function") if !js_callable?(has)
  keys = jget(other, "keys")
  js_throw_type("other.keys is not a function") if !js_callable?(keys)
  [sz, has, keys]

# GetIteratorFromMethod on the record's keys.
-> js_set_keys_iter(other, keys)
  it = js_call_arr(keys, other, JS_NO_ARGS)
  js_throw_type("keys() result is not an object") if !js_object?(it)
  nx = jget(it, "next")
  js_throw_type("keys() iterator's next is not a function") if !js_callable?(nx)
  JS:IterRecord.new(it, nx)

# The next live entry of a set's list after e (nil: start), skipping deleted ones.
-> js_set_next_live(d, e)
  x = e == nil ? d.head : e.next
  while x != nil && x.dead
    x = x.next
  x

-> js_set_copy_data(d)
  out = JS:MapData.new
  e = d.head
  while e != nil
    js_map_put(out, e.key, e.key) if !e.dead
    e = e.next
  out

# (-0 becomes +0. No early `return ~0.0`: a Float literal on an early return types the
# whole function as Float in compiled code.)
-> js_set_canon(k)
  k = ~0.0 if js_number?(k) && k == ~0.0
  k

# The Set methods of ES2025 (§24.2.4): union, intersection, difference,
# symmetricDifference, isSubsetOf, isSupersetOf, isDisjointFrom.
-> js_set_op(this, other, op)
  d = js_this_map(this, "Set")
  rec = js_set_record(other)
  osize = rec[0]
  has = rec[1]
  keys = rec[2]
  this_size = d.size + ~0.0
  if op == :union
    out = js_set_copy_data(d)
    it = js_set_keys_iter(other, keys)
    while true
      k = js_iter_step(it)
      break if k == JS_ITER_DONE
      k = js_set_canon(k)
      js_map_put(out, k, k)
    return js_set_from_data(out)
  if op == :intersection
    out = JS:MapData.new
    if this_size <= osize
      e = js_set_next_live(d, nil)
      while e != nil
        k = e.key
        if js_truthy(js_call_arr(has, other, [k]))
          js_map_put(out, k, k) if js_map_find(out, k) == nil
        e = js_set_next_live(d, e)
    else
      it = js_set_keys_iter(other, keys)
      while true
        k = js_iter_step(it)
        break if k == JS_ITER_DONE
        k = js_set_canon(k)
        js_map_put(out, k, k) if js_map_find(d, k) != nil && js_map_find(out, k) == nil
    return js_set_from_data(out)
  if op == :difference
    out = js_set_copy_data(d)
    if this_size <= osize
      e = js_set_next_live(d, nil)
      while e != nil
        k = e.key
        js_map_remove(out, k) if js_truthy(js_call_arr(has, other, [k]))
        e = js_set_next_live(d, e)
    else
      it = js_set_keys_iter(other, keys)
      while true
        k = js_iter_step(it)
        break if k == JS_ITER_DONE
        js_map_remove(out, js_set_canon(k))
    return js_set_from_data(out)
  if op == :symmetric
    it = js_set_keys_iter(other, keys)
    out = js_set_copy_data(d)
    while true
      k = js_iter_step(it)
      break if k == JS_ITER_DONE
      k = js_set_canon(k)
      if js_map_find(d, k) != nil
        js_map_remove(out, k)
      elsif js_map_find(out, k) == nil
        js_map_put(out, k, k)
    return js_set_from_data(out)
  if op == :subset
    return false if this_size > osize
    e = js_set_next_live(d, nil)
    while e != nil
      return false if !js_truthy(js_call_arr(has, other, [e.key]))
      e = js_set_next_live(d, e)
    return true
  if op == :superset
    return false if this_size < osize
    it = js_set_keys_iter(other, keys)
    while true
      k = js_iter_step(it)
      break if k == JS_ITER_DONE
      if js_map_find(d, k) == nil
        js_iter_close(it)
        return false
    return true
  # :disjoint
  if this_size <= osize
    e = js_set_next_live(d, nil)
    while e != nil
      return false if js_truthy(js_call_arr(has, other, [e.key]))
      e = js_set_next_live(d, e)
  else
    it = js_set_keys_iter(other, keys)
    while true
      k = js_iter_step(it)
      break if k == JS_ITER_DONE
      if js_map_find(d, k) != nil
        js_iter_close(it)
        return false
  true

-> js_set_from_data(data)
  s = js_set_new_empty()
  s.internal = data
  s

-> js_set_new_empty
  js_coll_new(js_realm().intrinsic("Set.prototype"), "Set")

js_install(->(r) js_install_collections(r))

-> js_install_collections(r)
  op = r.object_proto
  ip = r.intrinsics["%IteratorPrototype%"]
  ip = op if ip == nil
  # Map
  mp = js_new_object(op)
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
  mip = js_new_object(ip)
  r.set_intrinsic("%MapIteratorPrototype%", mip)
  r.method(mip, "next", 0, ->(this, args, nt) js_map_iter_next(this, "Map Iterator"))
  mip.define(SYM_TO_STRING_TAG, "Map Iterator", ATTR_C)
  # Set
  sp = js_new_object(op)
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
  sip = js_new_object(ip)
  r.set_intrinsic("%SetIteratorPrototype%", sip)
  r.method(sip, "next", 0, ->(this, args, nt) js_map_iter_next(this, "Set Iterator"))
  sip.define(SYM_TO_STRING_TAG, "Set Iterator", ATTR_C)
  # WeakMap / WeakSet (strong references for now)
  wmp = js_new_object(op)
  r.constructor("WeakMap", 0, ->(this, args, nt) js_coll_ctor("WeakMap", args, nt, "set", true), wmp)
  r.method(wmp, "get", 1, ->(this, args, nt) js_map_get(js_this_map(this, "WeakMap"), js_arg(args, 0)))
  wms = r.method(wmp, "set", 2, ->(this, args, nt) js_weak_set(this, "WeakMap", js_arg(args, 0), js_arg(args, 1)))
  r.set_intrinsic("%WeakMap_set%", wms)
  r.method(wmp, "has", 1, ->(this, args, nt) js_map_find(js_this_map(this, "WeakMap"), js_arg(args, 0)) != nil)
  r.method(wmp, "delete", 1, ->(this, args, nt) js_map_remove(js_this_map(this, "WeakMap"), js_arg(args, 0)))
  wmp.define(SYM_TO_STRING_TAG, "WeakMap", ATTR_C)
  wsp = js_new_object(op)
  r.constructor("WeakSet", 0, ->(this, args, nt) js_coll_ctor("WeakSet", args, nt, "add", false), wsp)
  wsa = r.method(wsp, "add", 1, ->(this, args, nt) js_weak_set(this, "WeakSet", js_arg(args, 0), js_arg(args, 0)))
  r.set_intrinsic("%WeakSet_add%", wsa)
  r.method(wsp, "has", 1, ->(this, args, nt) js_map_find(js_this_map(this, "WeakSet"), js_arg(args, 0)) != nil)
  r.method(wsp, "delete", 1, ->(this, args, nt) js_map_remove(js_this_map(this, "WeakSet"), js_arg(args, 0)))
  wsp.define(SYM_TO_STRING_TAG, "WeakSet", ATTR_C)
  # WeakRef / FinalizationRegistry
  wrp = js_new_object(op)
  r.constructor("WeakRef", 1, ->(this, args, nt) js_weakref_ctor(args, nt), wrp)
  r.method(wrp, "deref", 0, ->(this, args, nt) js_special?(this, "WeakRef") ? this.internal : js_throw_type("WeakRef.prototype.deref called on incompatible receiver"))
  wrp.define(SYM_TO_STRING_TAG, "WeakRef", ATTR_C)
  frp = js_new_object(op)
  r.constructor("FinalizationRegistry", 1, ->(this, args, nt) js_fin_reg_ctor(args, nt), frp)
  r.method(frp, "register", 2, ->(this, args, nt) js_fin_reg_check(this, js_arg(args, 0), js_arg(args, 1)))
  r.method(frp, "unregister", 1, ->(this, args, nt) js_fin_reg_unregister(this, js_arg(args, 0)))
  r.method(frp, "cleanupSome", 0, ->(this, args, nt) nil)
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
  js_throw_type("WeakRef: target must be an object") if !(js_object?(t) || (t.is_a?(JS:Symbol) && !js_registered_symbol?(t)))
  w = js_new_special(js_realm().proto_from(nt, "WeakRef"), "WeakRef")
  w.internal = t
  w

-> js_fin_reg_ctor(args, nt)
  js_throw_type("Constructor FinalizationRegistry requires 'new'") if nt == nil
  f = js_arg(args, 0)
  js_throw_type("FinalizationRegistry: cleanup must be callable") if !js_callable?(f)
  o = js_new_special(js_realm().proto_from(nt, "FinalizationRegistry"), "FinalizationRegistry")
  o.internal = f
  o

-> js_fin_reg_this(v)
  js_throw_type("FinalizationRegistry method called on incompatible receiver") if !js_special?(v, "FinalizationRegistry")
  v

-> js_can_be_held_weakly?(v)
  js_object?(v) || (v.is_a?(JS:Symbol) && !js_registered_symbol?(v))

-> js_fin_reg_check(this, target, held)
  js_fin_reg_this(this)
  js_throw_type("FinalizationRegistry.prototype.register: invalid target") if !js_can_be_held_weakly?(target)
  js_throw_type("FinalizationRegistry.prototype.register: target and holdings must not be same") if js_same_value(target, held)
  nil

-> js_fin_reg_unregister(this, token)
  js_fin_reg_this(this)
  js_throw_type("Invalid unregisterToken ('" + js_err_display(token) + "')") if !js_can_be_held_weakly?(token)
  false

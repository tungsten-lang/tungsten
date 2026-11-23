# runtime/object — the JS object model: shapes, objects, inline caches.
#
# A JS object is a Tungsten instance whose ivar 0 is its JS:Shape. The shape holds the
# prototype, the key → slot layout and per-key attributes, and is shared by every object
# built the same way (hidden classes: V8's maps, JSC's structures, SpiderMonkey's shapes
# all put the prototype in the shape too, so a cached shape check also fixes the chain).
#
#   JS:Base     @shape @ext                      (abstract)
#   JS:Object   @shape @ext @s0 … @s5            72 bytes, six inline property slots
#
# Property slot i lives in ivar shape.ibase + i while i < shape.inline, else in @ext
# (a core Array allocated on the first overflow). Subclasses (JS:Function, …) put their
# own fields after @ext and start their inline slots later; the shape says where.
#
# Shapes form a transition tree from one root per (prototype, layout). Adding a key with
# default attributes follows or creates a child. A delete, or more than JS_DICT_KEYS
# properties, gives the object a private dictionary shape (@dict) whose index it owns;
# inline caches never cache a dictionary shape.
#
# Inline caches (one per property site) live in the program's JS_IC table, 4 words per
# site, as raw bits:
#   get:  [shape, ivar (>= 1) or -1 - ext index, holder (0: own property), proto epoch]
#   set:  [shape, ivar, new shape (0: existing property), 0]
# A prototype hit is valid while JS_EPOCH[0] is unchanged; any layout change on an
# object that serves as a prototype bumps it (V8 guards the same with prototype
# validity cells; one global epoch is the simple form).

in JS

ATTR_W = 1
ATTR_E = 2
ATTR_C = 4
ATTR_DEFAULT = 7
ATTR_ALL = 7
ATTR_ACCESSOR = 8     # the slot holds a JS:Accessor

# Kind byte in the instance header (jsr_kind). 0x80 marks an object used as a prototype.
KIND_OBJECT = 1
KIND_FUNCTION = 2
KIND_NATIVE = 3
KIND_BOUND = 4
KIND_EXOTIC = 5
KIND_PROTO = 128

JS_DICT_KEYS = 64

# Bumped when an object that is some shape's prototype changes layout.
JS_EPOCH = i64[1]

# JS_IC, the program's inline-cache table (an i64[] of 4 words per property site), is
# declared by the compiled program *before* it uses this runtime: typed arrays read on
# fast paths must be declared ahead of the functions that read them, or the reads lower
# to boxed generic access (and a module global cannot be resized from a function).

# Words 0..7 of JS_IC are scratch caches for runtime callers.
JS_IC_SCRATCH = 0

+ Shape
  rw :proto, :parent, :key, :kattrs, :count, :inline, :ibase, :index, :trans, :alt, :keys, :dict, :attrs, :nonext

  -> new(@proto, @parent, @key, @kattrs, @count, @inline, @ibase)
    @index = nil
    @trans = nil
    @alt = nil
    @keys = nil
    @dict = false
    @attrs = nil
    @nonext = false

  # The same layout under another prototype: the keys replayed from that prototype's
  # root (a dictionary shape keeps its table and only changes its prototype).
  -> with_proto(p)
    if @dict
      @proto = p
      return self
    s = js_root_shape(p, @inline, @ibase)
    pairs = index_keys()
    i = 0
    while i < pairs.size
      s = s.add(pairs[i][0], pairs[i][1].kattrs)
      i += 1
    s

  # Slot of key, or -1. Builds the key → defining-shape index on first use.
  -> slot_of(key)
    return dict_slot(key) if @dict
    return -1 if @count == 0
    return @count - 1 if @key == key
    ix = index()
    d = ix[key]
    d == nil ? -1 : d.count - 1

  -> attrs_of(key)
    if @dict
      a = @attrs == nil ? nil : @attrs[key]
      return a == nil ? ATTR_DEFAULT : a
    return @kattrs if @key == key
    d = index()[key]
    d == nil ? ATTR_DEFAULT : d.kattrs

  -> index
    if @index == nil
      h = {}
      if @parent != nil && @parent.count > 0
        pk = @parent.index_keys()
        i = 0
        while i < pk.size
          h[pk[i][0]] = pk[i][1]
          i += 1
      h[@key] = self if @key != nil
      @index = h
    @index

  # [key, defining shape] pairs in slot order.
  -> index_keys
    out = []
    s = self
    while s != nil && s.count > 0
      out.push([s.key, s])
      s = s.parent
    out.reverse

  # Keys in slot order (property creation order).
  -> key_list
    if @keys == nil
      out = []
      s = self
      while s != nil && s.count > 0
        out.push(s.key)
        s = s.parent
      @keys = out.reverse
    @keys

  # The child shape adding key with attrs.
  -> add(key, attrs)
    c = @trans == nil ? nil : @trans[key]
    return c if c != nil && c.kattrs == attrs
    if @alt != nil
      i = 0
      while i < @alt.size
        a = @alt[i]
        return a if a.key == key && a.kattrs == attrs
        i += 1
    c = JS:Shape.new(@proto, self, key, attrs, @count + 1, @inline, @ibase)
    if @trans == nil
      @trans = {}
    if @trans[key] == nil
      @trans[key] = c
    else
      @alt = [] if @alt == nil
      @alt.push(c)
    c

  # ---- dictionary shapes (private to one object) ----

  -> dict_slot(key)
    s = @index[key]
    s == nil ? -1 : s

  # A dictionary copy of this shape's layout (same slots).
  -> to_dict
    d = JS:Shape.new(@proto, nil, nil, ATTR_DEFAULT, @count, @inline, @ibase)
    d.dict = true
    d.nonext = @nonext
    h = {}
    ks = []
    at = nil
    s = self
    pairs = index_keys()
    i = 0
    while i < pairs.size
      k = pairs[i][0]
      h[k] = i
      ks.push(k)
      a = pairs[i][1].kattrs
      if a != ATTR_DEFAULT
        at = {} if at == nil
        at[k] = a
      i += 1
    d.index = h
    d.keys = ks
    d.attrs = at
    d

# Root shapes: one per (prototype, layout). Stored on the prototype's side table.
JS_ROOTS = {}

-> js_root_shape(proto, inline, ibase)
  key = inline * 64 + ibase
  per = proto == nil ? JS_NULL_ROOTS : js_proto_roots(proto)
  s = per[key]
  if s == nil
    s = JS:Shape.new(proto, nil, nil, ATTR_DEFAULT, 0, inline, ibase)
    per[key] = s
  s

JS_NULL_ROOTS = {}

# Per-prototype root shapes, kept in an identity side table keyed by the proto's bits.
-> js_proto_roots(proto)
  pb = wvalue_bits(proto) ## i64
  h = JS_ROOTS[pb]
  if h == nil
    h = {}
    JS_ROOTS[pb] = h
    JS_ROOT_KEEP.push(proto)
    js_mark_proto(proto)
  h

JS_ROOT_KEEP = []

-> js_mark_proto(o)
  ob = wvalue_bits(o) ## i64
  k = jsr_kind(ob)
  if k != 0 && (k & KIND_PROTO) == 0
    jsr_set_kind(ob, k | KIND_PROTO)
  nil

-> js_is_proto?(o)
  (jsr_kind(wvalue_bits(o) ## i64) & KIND_PROTO) != 0

-> js_exotic_bits?(ob)
  (jsr_kind(ob) & 127) == KIND_EXOTIC

-> js_bump_epoch
  JS_EPOCH[0] = JS_EPOCH[0] + 1
  nil

+ Base
  rw :shape, :ext

  # ---- slots ----

  -> slot_get(i)
    s = @shape
    if i < s.inline
      return wvalue_from_bits(jsr_ivar(wvalue_bits(self) ## i64, s.ibase + i))
    @ext[i - s.inline]

  -> slot_set(i, v)
    s = @shape
    if i < s.inline
      ccall("w_ivar_set_idx", self, (s.ibase + i) ## i64, v)
      return v
    e = i - s.inline
    @ext = [] if @ext == nil
    while @ext.size < e
      @ext.push(nil)
    if @ext.size == e
      @ext.push(v)
    else
      @ext[e] = v
    v

  # ---- the internal methods (ECMA-262 §10.1; exotic subclasses override these) ----
  # Names and receiver defaults follow Blade's engine (blade/js/value.w), whose bindings
  # call them. The prototype is nil for a null prototype (JS code sees JS_NULL).

  -> proto
    @shape.proto

  -> get_prototype_of
    p = @shape.proto
    p == nil ? JS_NULL : p

  -> callable?
    false

  -> htmldda?
    false

  -> proxy?
    false

  # Properties some classes compute until written (a function's name, length, prototype).
  -> get_virtual(key)
    JS_HOLE

  -> has_own?(key)
    @shape.slot_of(key) >= 0 || get_virtual(key) != JS_HOLE

  -> has_own_slot?(key)
    @shape.slot_of(key) >= 0

  -> accessor?(key)
    @shape.slot_of(key) >= 0 && (@shape.attrs_of(key) & ATTR_ACCESSOR) != 0

  # The attribute bits of an own property (ATTR_W/E/C, plus ATTR_ACCESSOR).
  -> attr(key)
    @shape.attrs_of(key)

  -> enumerable?(key)
    (@shape.attrs_of(key) & ATTR_E) != 0

  # The value of an own data property, accessors not called; JS_HOLE when absent.
  -> get_own(key)
    i = @shape.slot_of(key)
    return get_virtual(key) if i < 0
    slot_get(i)

  -> getter_of(key)
    i = @shape.slot_of(key)
    return nil if i < 0
    a = slot_get(i)
    a.is_a?(JS:Accessor) ? a.getter : nil

  -> setter_of(key)
    i = @shape.slot_of(key)
    return nil if i < 0
    a = slot_get(i)
    a.is_a?(JS:Accessor) ? a.setter : nil

  # [[Get]]
  -> get(key, receiver = nil)
    r = receiver == nil ? self : receiver
    o = self
    while o != nil
      return o.get(key, r) if o != self && js_exotic_bits?(wvalue_bits(o) ## i64)
      s = o.shape
      i = s.slot_of(key)
      if i >= 0
        v = o.slot_get(i)
        return js_accessor_get(v, r) if (s.attrs_of(key) & ATTR_ACCESSOR) != 0
        return v
      v = o.get_virtual(key)
      return v if v != JS_HOLE
      o = s.proto
    nil

  -> exotic?
    js_exotic_bits?(wvalue_bits(self) ## i64)

  # [[Set]]: own writable data property, an inherited setter, or a new own property.
  -> set(key, v, receiver = nil)
    r = receiver == nil ? self : receiver
    o = self
    while o != nil
      return o.set(key, v, r) if o != self && js_exotic_bits?(wvalue_bits(o) ## i64)
      s = o.shape
      i = s.slot_of(key)
      if i >= 0
        a = s.attrs_of(key)
        return js_accessor_set(o.slot_get(i), r, v) if (a & ATTR_ACCESSOR) != 0
        return false if (a & ATTR_W) == 0
        break
      gv = o.get_virtual(key)
      if gv != JS_HOLE
        break
      o = s.proto
    return js_set_on_receiver(r, key, v) if r != self
    i = @shape.slot_of(key)
    if i >= 0
      slot_set(i, v)
      return true
    return false if !is_extensible?
    add_property(key, v, ATTR_DEFAULT)
    true

  # Create or update a data property without setters or writability checks.
  -> put_own(key, v)
    i = @shape.slot_of(key)
    if i >= 0
      slot_set(i, v)
    else
      add_property(key, v, ATTR_DEFAULT)
    v

  # Define an own data property with the given attributes.
  -> define(key, v, flags = ATTR_DEFAULT)
    i = @shape.slot_of(key)
    if i >= 0
      if @shape.attrs_of(key) != flags
        change_attrs(key, flags)
      slot_set(i, v)
      return v
    add_property(key, v, flags)
    v

  -> define_accessor(key, g, st, flags = ATTR_E + ATTR_C)
    a = JS:Accessor.new(g, st)
    fl = (flags & (ATTR_E + ATTR_C)) | ATTR_ACCESSOR
    i = @shape.slot_of(key)
    if i >= 0
      change_attrs(key, fl) if @shape.attrs_of(key) != fl
      slot_set(i, a)
      return nil
    add_property(key, a, fl)
    nil

  -> change_attrs(key, flags)
    to_dictionary()
    @shape.attrs = {} if @shape.attrs == nil
    @shape.attrs[key] = flags
    js_bump_epoch() if js_is_proto?(self)
    nil

  -> add_property(key, v, attrs)
    s = @shape
    js_bump_epoch() if js_is_proto?(self)
    if s.dict
      i = s.count
      s.index[key] = i
      s.keys.push(key)
      if attrs != ATTR_DEFAULT
        s.attrs = {} if s.attrs == nil
        s.attrs[key] = attrs
      s.count = i + 1
      slot_set(i, v)
      return v
    if s.count >= JS_DICT_KEYS
      to_dictionary()
      return add_property(key, v, attrs)
    ns = s.add(key, attrs)
    @shape = ns
    slot_set(ns.count - 1, v)
    v

  -> to_dictionary
    @shape = @shape.to_dict if !@shape.dict
    nil

  -> delete_own(key)
    s = @shape
    i = s.slot_of(key)
    return true if i < 0
    return false if (s.attrs_of(key) & ATTR_C) == 0
    to_dictionary()
    s = @shape
    js_bump_epoch() if js_is_proto?(self)
    # compact: move every later slot down one
    n = s.count
    j = i
    while j < n - 1
      slot_set(j, slot_get(j + 1))
      j += 1
    slot_set(n - 1, nil)
    s.count = n - 1
    s.index.delete(key)
    s.attrs.delete(key) if s.attrs != nil
    ks = []
    q = 0
    while q < s.keys.size
      ks.push(s.keys[q]) if s.keys[q] != key
      q += 1
    s.keys = ks
    q = 0
    while q < ks.size
      s.index[ks[q]] = q
      q += 1
    true

  # Own keys in spec order: integer-like keys ascending, then strings, then symbols
  # (private names never appear).
  -> own_keys
    ks = @shape.dict ? @shape.keys : @shape.key_list
    ints = []
    strs = []
    syms = []
    i = 0
    while i < ks.size
      k = ks[i]
      if js_string?(k)
        if js_array_index?(k)
          ints.push(k)
        else
          strs.push(k)
      elsif !k.is_a?(JS:PrivateName)
        syms.push(k)
      i += 1
    if ints.size > 1
      ints = ints.sort_by(->(k) k.to_i)
    ints + strs + syms

  -> get_own_property(key)
    i = @shape.slot_of(key)
    if i < 0
      v = get_virtual(key)
      return nil if v == JS_HOLE
      return JS:PropDesc.data(v, ATTR_C)
    a = @shape.attrs_of(key)
    d = JS:PropDesc.new
    if (a & ATTR_ACCESSOR) != 0
      acc = slot_get(i)
      d.getter = acc.getter
      d.setter = acc.setter
      d.has_get = true
      d.has_set = true
    else
      d.value = slot_get(i)
      d.has_value = true
      d.writable = (a & ATTR_W) != 0
    d.enumerable = (a & ATTR_E) != 0
    d.configurable = (a & ATTR_C) != 0
    d

  # ValidateAndApplyPropertyDescriptor (§10.1.6.3). Returns false when not allowed.
  -> define_own_property(key, desc)
    cur = get_own_property(key)
    if cur == nil
      return false if !is_extensible?
      if desc.accessor?
        define_accessor(key, desc.getter, desc.setter, desc.flags & (ATTR_E + ATTR_C))
      else
        define(key, desc.value, desc.flags)
      return true
    if cur.configurable == false
      return false if desc.configurable == true
      return false if desc.enumerable != nil && desc.enumerable != cur.enumerable
      if desc.accessor? || desc.data?
        return false if desc.accessor? != cur.accessor?
      if cur.accessor? && desc.accessor?
        return false if desc.has_get && desc.getter != cur.getter
        return false if desc.has_set && desc.setter != cur.setter
      elsif !cur.accessor? && cur.writable == false
        return false if desc.writable == true
        return false if desc.has_value && !js_same_value(desc.value, cur.value)
    en = desc.enumerable == nil ? cur.enumerable : desc.enumerable
    co = desc.configurable == nil ? cur.configurable : desc.configurable
    fl = (en ? ATTR_E : 0) | (co ? ATTR_C : 0)
    if desc.accessor?
      g = desc.has_get ? desc.getter : (cur.accessor? ? cur.getter : nil)
      st = desc.has_set ? desc.setter : (cur.accessor? ? cur.setter : nil)
      define_accessor(key, g, st, fl)
    elsif desc.data? || !cur.accessor?
      w = desc.writable == nil ? (cur.accessor? ? false : cur.writable) : desc.writable
      v = desc.has_value ? desc.value : (cur.accessor? ? nil : cur.value)
      define(key, v, fl | (w ? ATTR_W : 0))
    else
      define_accessor(key, cur.getter, cur.setter, fl)
    true

  -> has_property?(key)
    o = self
    while o != nil
      return o.has_property?(key) if o != self && js_exotic_bits?(wvalue_bits(o) ## i64)
      return true if o.has_own?(key)
      o = o.proto
    false

  -> is_extensible?
    !@shape.nonext

  -> prevent_extensions
    to_dictionary()
    @shape.nonext = true
    true

  # [[SetPrototypeOf]]: false when not allowed (non-extensible, or a cycle).
  -> set_prototype_of(p)
    p = nil if p == JS_NULL
    cur = @shape.proto
    return true if cur == p
    return false if !is_extensible?
    q = p
    while q != nil
      return false if q == self
      break if js_exotic_bits?(wvalue_bits(q) ## i64)
      q = q.proto
    js_bump_epoch() if js_is_proto?(self)
    @shape = @shape.with_proto(p)
    true

  # ---- private names (#x): own properties keyed by a JS:PrivateName ----

  -> priv_has?(pn)
    @shape.slot_of(pn) >= 0

  -> priv_get(pn)
    i = @shape.slot_of(pn)
    js_throw_type("Cannot read private member " + pn.to_s + " from an object whose class did not declare it") if i < 0
    v = slot_get(i)
    return js_accessor_get(v, self) if (@shape.attrs_of(pn) & ATTR_ACCESSOR) != 0
    v

  -> priv_set(pn, v)
    i = @shape.slot_of(pn)
    js_throw_type("Cannot write private member " + pn.to_s + " to an object whose class did not declare it") if i < 0
    a = @shape.attrs_of(pn)
    if (a & ATTR_ACCESSOR) != 0
      js_throw_type("'" + pn.to_s + "' was defined without a setter") if !js_accessor_set(slot_get(i), self, v)
      return v
    js_throw_type("Private method is not writable") if (a & ATTR_W) == 0
    slot_set(i, v)
    v

  -> priv_add(pn, v)
    js_throw_type("Cannot initialize " + pn.to_s + " twice on the same object") if @shape.slot_of(pn) >= 0
    add_property(pn, v, ATTR_W)
    v

  # A private method (not writable) or accessor pair; a getter and setter of one name
  # share the entry.
  -> priv_add_method(pn, f)
    js_throw_type("Cannot initialize " + pn.to_s + " twice on the same object") if @shape.slot_of(pn) >= 0
    add_property(pn, f, 0)
    f

  -> priv_add_accessor(pn, g, st)
    i = @shape.slot_of(pn)
    if i >= 0
      a = slot_get(i)
      js_throw_type("Cannot initialize " + pn.to_s + " twice on the same object") if !a.is_a?(JS:Accessor)
      a.getter = g if g != nil
      a.setter = st if st != nil
      return nil
    add_property(pn, JS:Accessor.new(g, st), ATTR_ACCESSOR)
    nil

+ Object < JS:Base
  rw :s0, :s1, :s2, :s3, :s4, :s5

  -> new(@shape)
    @ext = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    @s4 = nil
    @s5 = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_OBJECT)

OBJ_INLINE = 6
OBJ_IBASE = 2

# A new ordinary object with the given prototype (nil: null prototype).
-> js_new_object(proto)
  JS:Object.new(js_root_shape(proto, OBJ_INLINE, OBJ_IBASE))

# A property descriptor (§6.2.6); nil fields are absent.
+ PropDesc
  rw :value, :getter, :setter, :writable, :enumerable, :configurable, :has_value, :has_get, :has_set

  -> new
    @value = nil
    @getter = nil
    @setter = nil
    @writable = nil
    @enumerable = nil
    @configurable = nil
    @has_value = false
    @has_get = false
    @has_set = false

  -> accessor?
    @has_get || @has_set

  -> data?
    @has_value || @writable != nil

  -> .data(v, flags)
    d = JS:PropDesc.new
    d.value = v
    d.has_value = true
    d.writable = (flags & ATTR_W) != 0
    d.enumerable = (flags & ATTR_E) != 0
    d.configurable = (flags & ATTR_C) != 0
    d

  -> flags
    f = 0
    f = f | ATTR_W if @writable == true
    f = f | ATTR_E if @enumerable == true
    f = f | ATTR_C if @configurable == true
    f

+ PrivateName
  rw :description, :is_method
  -> new(@description)
    @is_method = false
  -> to_s
    "#" + @description.to_s

# OrdinarySet's last step when the receiver is another object (§10.1.9.2 3.d-e).
-> js_set_on_receiver(r, key, v)
  return false if !js_object?(r)
  return js_array_set(r, key, v) if js_array?(r)
  d = r.get_own_property(key)
  if d != nil
    return false if d.accessor? || d.writable == false
    vd = JS:PropDesc.new
    vd.value = v
    vd.has_value = true
    return r.define_own_property(key, vd)
  return false if !r.is_extensible?
  r.define_own_property(key, JS:PropDesc.data(v, ATTR_DEFAULT))

# Holes in arrays and absent results of get_own.
+ Hole
  -> new
    nil
JS_HOLE = JS:Hole.new

+ Null
  -> new
    nil
  -> to_s
    "null"
JS_NULL = JS:Null.new

# ---- getters and setters ----

+ Accessor
  rw :getter, :setter
  -> new(@getter, @setter)
    nil

-> js_accessor_get(acc, receiver)
  return nil if !acc.is_a?(JS:Accessor) || acc.getter == nil
  js_call_arr(acc.getter, receiver, [])

-> js_accessor_set(acc, receiver, v)
  return false if !acc.is_a?(JS:Accessor) || acc.setter == nil
  js_call_arr(acc.setter, receiver, [v])
  true

# ---- inline cache fast paths ----

# Own or prototype data property hit, as raw bits; JSR_SLOW on a miss.
fn jsr_ic_get(ic, k, ob, epoch) (i64[] i64 i64 i64) i64
  s = jsr_shape(ob)
  if s == 0 || s != ic[k]
    return 6
  i = ic[k + 1]
  h = ic[k + 2]
  if h == 0
    if i > 0
      return jsr_ivar(ob, i)
    return 6
  if ic[k + 3] != epoch || i <= 0
    return 6
  jsr_ivar(h, i)

# Existing own writable slot: the ivar to store into; or for an add, the ivar with the
# new shape already installed. 0 on a miss.
fn jsr_ic_set(ic, k, ob, epoch) (i64[] i64 i64 i64) i64
  s = jsr_shape(ob)
  if s == 0 || s != ic[k]
    return 0
  ns = ic[k + 2]
  if ns != 0
    if ic[k + 3] != epoch
      return 0
    jsr_set_shape(ob, ns)
  ic[k + 1]

-> js_ic_fill_get(ic, k, s, ivar, holder, epoch)
  ic[k] = s
  ic[k + 1] = ivar
  ic[k + 2] = holder
  ic[k + 3] = epoch
  nil

# o[key] for a site with cache k (k = 4 × site number) in the program's table.
-> js_getp(o, key, k)
  r = jsr_ic_get(JS_IC, k, wvalue_bits(o) ## i64, JS_EPOCH[0])
  return wvalue_from_bits(r) if r != JSR_SLOW
  js_get_miss(o, key, JS_IC, k)

# The same with a cache of the caller's own (tier 0 keeps one per property node).
-> js_getp_ic(o, key, ic)
  r = jsr_ic_get(ic, 0, wvalue_bits(o) ## i64, JS_EPOCH[0])
  return wvalue_from_bits(r) if r != JSR_SLOW
  js_get_miss(o, key, ic, 0)

-> js_get_miss(o, key, ic, k)
  return js_get_prim(o, key) if !o.is_a?(JS:Base)
  s = o.shape
  if !s.dict && js_ivar_cacheable?(o)
    i = s.slot_of(key)
    if i >= 0
      if s.attrs_of(key) & ATTR_ACCESSOR == 0 && i < s.inline
        js_ic_fill_get(ic, k, wvalue_bits(s) ## i64, (s.ibase + i) ## i64, 0 ## i64, 0 ## i64)
    else
      p = s.proto
      if p != nil && p.is_a?(JS:Base) && js_ivar_cacheable?(p) && p.get_virtual(key) == JS_HOLE && o.get_virtual(key) == JS_HOLE
        ps = p.shape
        j = ps.slot_of(key)
        if j >= 0 && !ps.dict && ps.attrs_of(key) & ATTR_ACCESSOR == 0 && j < ps.inline
          js_ic_fill_get(ic, k, wvalue_bits(s) ## i64, (ps.ibase + j) ## i64, wvalue_bits(p) ## i64, JS_EPOCH[0])
  o.get(key, o)

# Objects whose properties all live in plain slots (exotic classes override get).
-> js_ivar_cacheable?(o)
  k = jsr_kind(wvalue_bits(o) ## i64) & 127
  k == KIND_OBJECT || k == KIND_FUNCTION

# o[key] = v for a site with cache k. Returns v.
-> js_setp(o, key, v, k)
  i = jsr_ic_set(JS_IC, k, wvalue_bits(o) ## i64, JS_EPOCH[0])
  if i > 0
    ccall("w_ivar_set_idx", o, i, v)
    return v
  js_set_miss(o, key, v, JS_IC, k, false)

-> js_setp_ic(o, key, v, ic, strict)
  i = jsr_ic_set(ic, 0, wvalue_bits(o) ## i64, JS_EPOCH[0])
  if i > 0
    ccall("w_ivar_set_idx", o, i, v)
    return v
  js_set_miss(o, key, v, ic, 0, strict)

-> js_set_miss(o, key, v, ic, k, strict)
  if !o.is_a?(JS:Base)
    js_setv(o, key, v, strict)
    return v
  s = o.shape
  cache = !s.dict && js_ivar_cacheable?(o) && !js_is_proto?(o)
  i = s.slot_of(key)
  if i >= 0
    if cache && s.attrs_of(key) == ATTR_DEFAULT && i < s.inline
      ic[k] = wvalue_bits(s) ## i64
      ic[k + 1] = (s.ibase + i) ## i64
      ic[k + 2] = 0 ## i64
    js_set_checked(o, key, v, strict)
    return v
  js_set_checked(o, key, v, strict)
  ns = o.shape
  if cache && ns != s && !ns.dict && ns.parent == s && ns.key == key && ns.count - 1 < ns.inline && js_proto_chain_plain?(s.proto, key)
    ic[k] = wvalue_bits(s) ## i64
    ic[k + 1] = (ns.ibase + ns.count - 1) ## i64
    ic[k + 2] = wvalue_bits(ns) ## i64
    ic[k + 3] = JS_EPOCH[0]
  v

-> js_set_checked(o, key, v, strict)
  ok = o.set(key, v, o)
  js_throw_type("Cannot assign to read only property '" + js_to_display(js_key_display(key)) + "' of object") if !ok && strict
  ok

# No setter or read-only property for key anywhere on the chain (so adding it to the
# receiver is always right while the prototypes keep their layout).
-> js_proto_chain_plain?(p, key)
  while p != nil
    return false if !p.is_a?(JS:Base)
    ps = p.shape
    j = ps.slot_of(key)
    return false if j >= 0
    p = ps.proto
  true

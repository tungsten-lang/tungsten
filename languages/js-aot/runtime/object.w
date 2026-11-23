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
  rw :proto, :parent, :key, :kattrs, :count, :inline, :ibase, :index, :trans, :alt, :keys, :dict, :attrs

  -> new(@proto, @parent, @key, @kattrs, @count, @inline, @ibase)
    @index = nil
    @trans = nil
    @alt = nil
    @keys = nil
    @dict = false
    @attrs = nil

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

  # ---- the internal methods (exotic subclasses override these) ----

  -> proto
    @shape.proto

  -> get_own_slot(key)
    @shape.slot_of(key)

  -> has_own?(key)
    @shape.slot_of(key) >= 0

  # The value of an own data property (accessors are not called), or JS_HOLE.
  -> get_own(key)
    i = @shape.slot_of(key)
    return JS_HOLE if i < 0
    slot_get(i)

  # [[Get]] with receiver.
  -> get(key, receiver)
    o = self
    while o != nil
      s = o.shape
      i = s.slot_of(key)
      if i >= 0
        v = o.slot_get(i)
        return js_accessor_get(v, receiver) if (s.attrs_of(key) & ATTR_ACCESSOR) != 0
        return v
      v = o.get_virtual(key)
      return v if v != JS_HOLE
      o = s.proto
    nil

  # Properties some classes compute until written (a function's name, length, prototype).
  -> get_virtual(key)
    JS_HOLE

  # [[Set]]: own writable data property, an inherited setter, or a new own property.
  -> set(key, v, receiver)
    s = @shape
    i = s.slot_of(key)
    if i >= 0
      a = s.attrs_of(key)
      if (a & ATTR_ACCESSOR) != 0
        return js_accessor_set(slot_get(i), receiver, v)
      return false if (a & ATTR_W) == 0
      slot_set(i, v)
      return true
    p = s.proto
    while p != nil
      ps = p.shape
      j = ps.slot_of(key)
      if j >= 0
        pa = ps.attrs_of(key)
        return js_accessor_set(p.slot_get(j), receiver, v) if (pa & ATTR_ACCESSOR) != 0
        return false if (pa & ATTR_W) == 0
        break
      p = ps.proto
    return receiver.set(key, v, receiver) if receiver != self
    add_property(key, v, ATTR_DEFAULT)
    true

  # Define an own property (no setter call, no writability check on add).
  -> put_own(key, v)
    i = @shape.slot_of(key)
    if i >= 0
      slot_set(i, v)
    else
      add_property(key, v, ATTR_DEFAULT)
    v

  -> define(key, v, attrs)
    i = @shape.slot_of(key)
    if i >= 0
      if @shape.attrs_of(key) != attrs
        to_dictionary()
        @shape.attrs = {} if @shape.attrs == nil
        @shape.attrs[key] = attrs
      slot_set(i, v)
      js_bump_epoch() if js_is_proto?(self)
      return v
    add_property(key, v, attrs)
    v

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
    s.keys.each ->(k) ks.push(k) if k != key
    s.keys = ks
    q = 0
    while q < ks.size
      s.index[ks[q]] = q
      q += 1
    true

  # Own keys in spec order: integer-like keys ascending, then strings, then symbols.
  -> own_keys
    ks = @shape.dict ? @shape.keys : @shape.key_list
    ints = []
    strs = []
    syms = []
    i = 0
    while i < ks.size
      k = ks[i]
      if k.is_a?(String)
        if js_array_index?(k)
          ints.push(k)
        else
          strs.push(k)
      else
        syms.push(k)
      i += 1
    if ints.size > 1
      ints = ints.sort_by(->(k) k.to_i)
    ints + strs + syms

  -> enumerable?(key)
    (@shape.attrs_of(key) & ATTR_E) != 0

  -> callable?
    false

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

-> js_ic_fill_get(k, s, ivar, holder, epoch)
  JS_IC[k] = s
  JS_IC[k + 1] = ivar
  JS_IC[k + 2] = holder
  JS_IC[k + 3] = epoch
  nil

# o[key] for a site with cache k (k = 4 × site number).
-> js_getp(o, key, k)
  r = jsr_ic_get(JS_IC, k, wvalue_bits(o) ## i64, JS_EPOCH[0])
  return wvalue_from_bits(r) if r != JSR_SLOW
  js_get_miss(o, key, k)

-> js_get_miss(o, key, k)
  return js_get_prim(o, key) if !o.is_a?(JS:Base)
  s = o.shape
  if !s.dict && js_ivar_cacheable?(o)
    i = s.slot_of(key)
    if i >= 0
      if s.attrs_of(key) & ATTR_ACCESSOR == 0 && i < s.inline
        js_ic_fill_get(k, wvalue_bits(s) ## i64, (s.ibase + i) ## i64, 0 ## i64, 0 ## i64)
    else
      p = s.proto
      if p != nil && p.is_a?(JS:Base) && js_ivar_cacheable?(p) && p.get_virtual(key) == JS_HOLE && o.get_virtual(key) == JS_HOLE
        ps = p.shape
        j = ps.slot_of(key)
        if j >= 0 && !ps.dict && ps.attrs_of(key) & ATTR_ACCESSOR == 0 && j < ps.inline
          js_ic_fill_get(k, wvalue_bits(s) ## i64, (ps.ibase + j) ## i64, wvalue_bits(p) ## i64, JS_EPOCH[0])
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
  js_set_miss(o, key, v, k)

-> js_set_miss(o, key, v, k)
  if !o.is_a?(JS:Base)
    js_set_prim(o, key, v)
    return v
  s = o.shape
  cache = !s.dict && js_ivar_cacheable?(o) && !js_is_proto?(o)
  i = s.slot_of(key)
  if i >= 0
    if cache && s.attrs_of(key) == ATTR_DEFAULT && i < s.inline
      JS_IC[k] = wvalue_bits(s) ## i64
      JS_IC[k + 1] = (s.ibase + i) ## i64
      JS_IC[k + 2] = 0 ## i64
    o.set(key, v, o)
    return v
  o.set(key, v, o)
  ns = o.shape
  if cache && ns != s && !ns.dict && ns.parent == s && ns.key == key && ns.count - 1 < ns.inline && js_proto_chain_plain?(s.proto, key)
    JS_IC[k] = wvalue_bits(s) ## i64
    JS_IC[k + 1] = (ns.ibase + ns.count - 1) ## i64
    JS_IC[k + 2] = wvalue_bits(ns) ## i64
    JS_IC[k + 3] = JS_EPOCH[0]
  v

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

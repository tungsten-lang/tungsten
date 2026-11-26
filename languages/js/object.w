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

# Global 512-entry direct-mapped secondary property cache for polymorphic/megamorphic sites
# and Array/String prototype method lookups (List 2 #3 & #7):
#   JS_POLY_IC[4*idx + 0] = shape bits
#   JS_POLY_IC[4*idx + 1] = key WValue bits (rooted in JS_POLY_KEEP[idx])
#   JS_POLY_IC[4*idx + 2] = slot_enc (> 0 inline ivar, < 0 overflow @ext)
#   JS_POLY_IC[4*idx + 3] = holder bits (0 = own property; non-0 = prototype holder)
#   JS_POLY_EP[idx]       = JS_EPOCH[0] when holder != 0
JS_POLY_IC = i64[2048]
JS_POLY_EP = i64[512]
JS_POLY_KEEP = Array.new(512, nil)

# JS_IC, the program's inline-cache table (an i64[] of 4 words per property site), is
# declared by the compiled program *before* it uses this runtime: typed arrays read on
# fast paths must be declared ahead of the functions that read them, or the reads lower
# to boxed generic access (and a module global cannot be resized from a function).

# Words 0..7 of JS_IC are scratch caches for runtime callers.
JS_IC_SCRATCH = 0

+ Shape
  rw :proto, :parent, :key, :kattrs, :count, :inline, :ibase, :index, :trans, :alt, :t0, :keys, :dict, :attrs, :nonext, :json_plan, :json_pred

  -> new(@proto, @parent, @key, @kattrs, @count, @inline, @ibase)
    @index = nil
    @trans = nil
    @alt = nil
    @t0 = nil
    @keys = nil
    @dict = false
    @attrs = nil
    @nonext = false
    @json_plan = nil
    @json_pred = nil

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

  # Slot of key, or -1. Walks parent chain for small shapes (<= 6 keys) to avoid
  # allocating a 168-byte Hash; materializes the key -> defining-shape index only past 6 keys.
  -> slot_of(key)
    return dict_slot(key) if @dict
    return -1 if @count == 0
    return @count - 1 if @key == key
    if @index == nil && @count <= 6
      s = @parent
      while s != nil && s.count > 0
        return s.count - 1 if s.key == key
        s = s.parent
      return -1
    ix = index()
    d = ix[key]
    d == nil ? -1 : d.count - 1

  -> attrs_of(key)
    if @dict
      a = @attrs == nil ? nil : @attrs[key]
      return a == nil ? ATTR_DEFAULT : a
    return @kattrs if @key == key
    if @index == nil && @count <= 6
      s = @parent
      while s != nil && s.count > 0
        return s.kattrs if s.key == key
        s = s.parent
      return ATTR_DEFAULT
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

  # Spec-ordered own keys (cached on immutable non-dict shapes).
  -> key_list
    return JS_NO_ARGS if @count == 0
    if @keys == nil
      out = []
      s = self
      while s != nil && s.count > 0
        out.push(s.key)
        s = s.parent
      @keys = js_order_own_keys(out.reverse, false)
    @keys

  # The child shape adding key with attrs.
  # Compact representation:
  #   - 1 child:      @t0 holds the single JS:Shape (0 heap allocations!)
  #   - 2..8 children: @t0 + @alt Array hold children (@trans stays nil — no 168B Hash!)
  #   - >8 children:  promoted to @trans Hash (strictly Hash-typed) + @alt for attr collisions.
  -> add(key, attrs)
    if @trans == nil
      if @t0 == nil
        c = JS:Shape.new(@proto, self, key, attrs, @count + 1, @inline, @ibase)
        @t0 = c
        return c
      return @t0 if @t0.key == key && @t0.kattrs == attrs
      if @alt != nil
        i = 0
        n = @alt.size
        while i < n
          a = @alt[i]
          return a if a.key == key && a.kattrs == attrs
          i += 1
        if n < 7
          c = JS:Shape.new(@proto, self, key, attrs, @count + 1, @inline, @ibase)
          @alt.push(c)
          return c
        # Promote @t0 + @alt into @trans Hash
        h = {}
        new_alt = nil
        h[@t0.key] = @t0
        i = 0
        while i < n
          a = @alt[i]
          if h[a.key] == nil
            h[a.key] = a
          else
            new_alt = [] if new_alt == nil
            new_alt.push(a)
          i += 1
        c = JS:Shape.new(@proto, self, key, attrs, @count + 1, @inline, @ibase)
        if h[key] == nil
          h[key] = c
        else
          new_alt = [] if new_alt == nil
          new_alt.push(c)
        @trans = h
        @alt = new_alt
        @t0 = nil
        return c
      c = JS:Shape.new(@proto, self, key, attrs, @count + 1, @inline, @ibase)
      @alt = [c]
      return c
    c = @trans[key]
    return c if c != nil && c.kattrs == attrs
    if @alt != nil
      i = 0
      while i < @alt.size
        a = @alt[i]
        return a if a.key == key && a.kattrs == attrs
        i += 1
    c = JS:Shape.new(@proto, self, key, attrs, @count + 1, @inline, @ibase)
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

# Per-prototype root shapes, kept in an identity side table keyed by the proto's 47-bit ptr key.
-> js_proto_roots(proto)
  pb = js_gc_key(wvalue_bits(proto) ## i64)
  h = JS_ROOTS[pb]
  if h == nil
    h = {}
    JS_ROOTS[pb] = h
    JS_ROOT_KEEP.push(proto)
    js_mark_proto(proto)
  h

JS_ROOT_KEEP = []

# Some prototype has (or may have) an index-keyed property: array writes to holes and
# past the end then look up the prototype chain for setters and read-only elements
# (V8 calls the fast case's guard the no-elements protector).
JS_PROTO_INDEX = [false]

-> js_mark_proto(o)
  ob = wvalue_bits(o) ## i64
  k = jsr_kind(ob)
  if k != 0 && (k & KIND_PROTO) == 0
    jsr_set_kind(ob, k | KIND_PROTO)
    if !JS_PROTO_INDEX[0]
      if (k & 15) == KIND_EXOTIC
        JS_PROTO_INDEX[0] = true
      else
        ks = o.own_keys
        i = 0
        while i < ks.size
          JS_PROTO_INDEX[0] = true if ks[i].is_a?(String) && js_array_index?(ks[i])
          i += 1
  nil

-> js_is_proto?(o)
  (jsr_kind(wvalue_bits(o) ## i64) & KIND_PROTO) != 0

-> js_exotic_bits?(ob)
  (jsr_kind(ob) & 15) == KIND_EXOTIC

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

  # [[Construct]] exists (exotic objects that are constructors override this).
  -> constructor?
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
  -> get(key, receiver = JS_HOLE)
    r = receiver == JS_HOLE ? self : receiver
    o = self
    while o != nil
      if o != self
        return o.get(key, r) if js_exotic_bits?(wvalue_bits(o) ## i64)
        return js_array_get(o, key, r) if js_array?(o)
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
  -> set(key, v, receiver = JS_HOLE)
    r = receiver == JS_HOLE ? self : receiver
    o = self
    while o != nil
      if o != self
        return o.set(key, v, r) if js_exotic_bits?(wvalue_bits(o) ## i64)
        return js_array_proto_set(o, key, v, r) if js_array?(o)
      s = o.shape
      i = s.slot_of(key)
      if i >= 0
        a = s.attrs_of(key)
        return js_accessor_set(o.slot_get(i), r, v) if (a & ATTR_ACCESSOR) != 0
        return false if (a & ATTR_W) == 0
        break
      gv = o.get_virtual(key)
      if gv != JS_HOLE
        d = o.get_own_property(key)
        return false if d != nil && !d.accessor? && d.writable == false
        break
      o = s.proto
    return js_set_on_receiver(r, key, v) if r != self
    i = @shape.slot_of(key)
    if i >= 0
      slot_set(i, v)
      js_bump_epoch() if js_is_proto?(self)
      return true
    return false if !is_extensible?
    add_property(key, v, ATTR_DEFAULT)
    true

  # Create or update a data property without setters or writability checks.
  -> put_own(key, v)
    i = @shape.slot_of(key)
    if i >= 0
      slot_set(i, v)
      js_bump_epoch() if js_is_proto?(self)
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
      js_bump_epoch() if js_is_proto?(self)
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
      js_bump_epoch() if js_is_proto?(self)
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
    if js_is_proto?(self)
      js_bump_epoch()
      JS_PROTO_INDEX[0] = true if key.is_a?(String) && js_array_index?(key)
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
    return @shape.key_list if !@shape.dict
    return JS_NO_ARGS if @shape.keys.size == 0
    js_order_own_keys(@shape.keys, true)

  -> get_own_property(key)
    i = @shape.slot_of(key)
    if i < 0
      v = get_virtual(key)
      return nil if v == JS_HOLE
      # get_virtual may have made it a real property (a function's prototype)
      i = @shape.slot_of(key)
      return JS:PropDesc.data(v, ATTR_C) if i < 0
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
      if o != self
        return o.has_property?(key) if js_exotic_bits?(wvalue_bits(o) ## i64)
        return jhas_property?(o, key) if js_array?(o)
      return true if o.has_own?(key)
      o = o.proto
    false

  -> is_extensible?
    !@shape.nonext

  -> prevent_extensions
    to_dictionary()
    @shape.nonext = true
    true

  # [[SetPrototypeOf]]: false when not allowed (immutable Object.prototype, non-extensible, or a cycle).
  -> set_prototype_of(p)
    p = nil if p == JS_NULL
    cur = @shape.proto
    return true if cur == p
    return false if self == js_realm().object_proto
    return false if !is_extensible?
    q = p
    while q != nil
      return false if q == self
      break if js_exotic_bits?(wvalue_bits(q) ## i64) || js_array?(q)
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
    if (@shape.attrs_of(pn) & ATTR_ACCESSOR) != 0
      js_throw_type("'" + pn.to_s + "' was defined without a getter") if v.getter == nil
      return js_accessor_get(v, self)
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
    js_throw_type("Cannot add private member " + pn.to_s + " to a non-extensible object") if !is_extensible?
    js_throw_type("Cannot initialize " + pn.to_s + " twice on the same object") if @shape.slot_of(pn) >= 0
    add_property(pn, v, ATTR_W)
    v

  # A private method (not writable) or accessor pair; a getter and setter of one name
  # share the entry.
  -> priv_add_method(pn, f)
    js_throw_type("Cannot add private member " + pn.to_s + " to a non-extensible object") if !is_extensible?
    js_throw_type("Cannot initialize " + pn.to_s + " twice on the same object") if @shape.slot_of(pn) >= 0
    add_property(pn, f, 0)
    f

  -> priv_add_accessor(pn, g, st)
    i = @shape.slot_of(pn)
    if i >= 0
      a = slot_get(i)
      js_throw_type("Cannot initialize " + pn.to_s + " twice on the same object") if !a.is_a?(JS:Accessor)
      js_throw_type("Cannot initialize " + pn.to_s + " twice on the same object") if (g != nil && a.getter != nil) || (st != nil && a.setter != nil)
      a.getter = g if g != nil
      a.setter = st if st != nil
      return nil
    js_throw_type("Cannot add private member " + pn.to_s + " to a non-extensible object") if !is_extensible?
    add_property(pn, JS:Accessor.new(g, st), ATTR_ACCESSOR)
    nil

+ Object < JS:Base
  rw :s0, :s1, :s2, :s3, :s4, :s5, :s6, :s7

  -> new(@shape)
    @ext = nil
    @s0 = nil
    @s1 = nil
    @s2 = nil
    @s3 = nil
    @s4 = nil
    @s5 = nil
    @s6 = nil
    @s7 = nil
    jsr_set_kind(wvalue_bits(self) ## i64, KIND_OBJECT)

OBJ_INLINE = 8
OBJ_IBASE = 2

# A new ordinary object with the given prototype (nil: null prototype).
-> js_new_object(proto)
  o = JS:Object.new(js_root_shape(proto, OBJ_INLINE, OBJ_IBASE))
  JS_GC_ON[0] ? js_gc_reg(o) : o

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
  if js_array?(r)
    d = js_array_get_own_property(r, key)
    if d != nil
      return false if d.accessor? || d.writable == false
      vd = JS:PropDesc.new
      vd.value = v
      vd.has_value = true
      return js_array_define_own_property(r, key, vd)
    return js_array_define_own_property(r, key, JS:PropDesc.data(v, ATTR_DEFAULT))
  d = r.get_own_property(key)
  if d != nil
    return false if d.accessor? || d.writable == false
    vd = JS:PropDesc.new
    vd.value = v
    vd.has_value = true
    return r.define_own_property(key, vd)
  r.define_own_property(key, JS:PropDesc.data(v, ATTR_DEFAULT))

# Holes in arrays and absent results of get_own.
+ Hole
  -> new
    nil
JS_HOLE = JS:Hole.new
# Sentinel for an explicit JS `undefined` receiver (since passing nil triggers Tungsten default params).
JS_RECV_UNDEF = JS:Hole.new

-> js_enc_recv(r)
  r == nil ? JS_RECV_UNDEF : r

-> js_dec_recv(r)
  r == JS_RECV_UNDEF ? nil : r

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

-> js_order_own_keys(ks, copy)
  n = ks.size
  return JS_NO_ARGS if n == 0
  # Fast path: all non-index string keys (the common case for JS objects).
  simple = true
  i = 0
  while i < n
    k = ks[i]
    if !js_string?(k) || js_array_index?(k)
      simple = false
      break
    i += 1
  if simple
    return copy ? ks.dup : ks
  ints = []
  strs = []
  syms = []
  i = 0
  while i < n
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
  return strs if ints.size == 0 && syms.size == 0
  return ints if strs.size == 0 && syms.size == 0
  return syms if ints.size == 0 && strs.size == 0
  return ints + strs if syms.size == 0
  return strs + syms if ints.size == 0
  ints + strs + syms

-> js_accessor_get(acc, receiver)
  return nil if !acc.is_a?(JS:Accessor) || acc.getter == nil
  js_call(acc.getter, receiver == JS_RECV_UNDEF ? nil : receiver, 0, nil, nil, nil, nil, nil)

-> js_accessor_set(acc, receiver, v)
  return false if !acc.is_a?(JS:Accessor) || acc.setter == nil
  js_call(acc.setter, receiver == JS_RECV_UNDEF ? nil : receiver, 1, v, nil, nil, nil, nil)
  true

# ---- inline cache fast paths ----

# Own or prototype data property hit, as raw bits; JSR_SLOW on a miss.
# 4-word polymorphic layout (1-shape fast path + 2-shape own-property promotion):
#   ic[k+2] == 0          : 1-shape own property  (s1=ic[k], slot1=ic[k+1])
#   (ic[k+2] & 1) != 0    : 2-shape own property  (s1=ic[k], slot1=ic[k+1], s2=ic[k+2]^1, slot2=ic[k+3])
#   ic[k+2] != 0 & even   : prototype property    (s1=ic[k], slot1=ic[k+1], holder=ic[k+2], epoch=ic[k+3])
# slot > 0: inline ivar index; slot < 0: overflow @ext[-(slot) - 1].
fn jsr_ic_get(ic, k, ob, epoch) (i64[] i64 i64 i64) i64
  s = jsr_shape(ob)
  if s == 0
    return 6
  if s == ic[k]
    i = ic[k + 1]
    h = ic[k + 2]
    if h == 0 || (h & 1) != 0
      if i > 0
        return jsr_ivar(ob, i)
      if i < 0
        ext = jsr_ivar(ob, 1)
        return jsr_aget(ext, (0 - i) - 1)
      return 6
    if ic[k + 3] != epoch
      return 6
    if i > 0
      return jsr_ivar(h, i)
    if i < 0
      ext = jsr_ivar(h, 1)
      return jsr_aget(ext, (0 - i) - 1)
    return 6
  h2 = ic[k + 2]
  if (h2 & 1) != 0 && s == (h2 ^ 1)
    i2 = ic[k + 3]
    if i2 > 0
      return jsr_ivar(ob, i2)
    if i2 < 0
      ext = jsr_ivar(ob, 1)
      return jsr_aget(ext, (0 - i2) - 1)
  6

# Existing own writable slot (1-shape or 2-shape) or shape transition:
#   ic[k+2] == 0          : 1-shape own write
#   (ic[k+2] & 1) != 0    : 2-shape own write (s2 = ic[k+2]^1, slot2 = ic[k+3])
#   ic[k+2] != 0 & even   : transition write  (new_shape = ic[k+2], epoch = ic[k+3])
# Returns > 0 inline ivar, < 0 overflow @ext[-(r)-1], or 0 on a miss.
fn jsr_ic_set(ic, k, ob, epoch) (i64[] i64 i64 i64) i64
  s = jsr_shape(ob)
  if s == 0
    return 0
  if s == ic[k]
    ns = ic[k + 2]
    if ns != 0 && (ns & 1) == 0
      if ic[k + 3] != epoch
        return 0
      jsr_set_shape(ob, ns)
    return ic[k + 1]
  ns2 = ic[k + 2]
  if (ns2 & 1) != 0 && s == (ns2 ^ 1)
    return ic[k + 3]
  0

-> js_ic_fill_get(ic, k, s, ivar, holder, epoch)
  if holder == 0
    old_s = ic[k]
    old_h = ic[k + 2]
    if old_s != 0 && old_s != s && (old_h == 0 || (old_h & 1) != 0)
      # Promote own-property site to 2-shape polymorphic cache (most recent in slot 1)
      ic[k + 2] = old_s | 1
      ic[k + 3] = ic[k + 1]
      ic[k] = s
      ic[k + 1] = ivar
      return nil
  ic[k] = s
  ic[k + 1] = ivar
  ic[k + 2] = holder
  ic[k + 3] = epoch
  nil

-> js_ic_fill_set_own(ic, k, s, slot_enc)
  old_s = ic[k]
  old_ns = ic[k + 2]
  if old_s != 0 && old_s != s && (old_ns == 0 || (old_ns & 1) != 0)
    ic[k + 2] = old_s | 1
    ic[k + 3] = ic[k + 1]
    ic[k] = s
    ic[k + 1] = slot_enc
    return nil
  ic[k] = s
  ic[k + 1] = slot_enc
  ic[k + 2] = 0 ## i64
  ic[k + 3] = 0 ## i64
  nil

# Secondary global (shape, key) direct-mapped lookup for polymorphic/megamorphic sites.
fn jsr_poly_ic_get(pic, pep, ob, kb, epoch) (i64[] i64[] i64 i64 i64) i64
  s = jsr_shape(ob)
  if s == 0
    return 6
  idx = ((s >> 4) ^ (kb >> 4) ^ (s >> 13)) & 511
  off = idx << 2
  if pic[off] == s && pic[off + 1] == kb
    slot = pic[off + 2]
    h = pic[off + 3]
    if h == 0
      if slot > 0
        return jsr_ivar(ob, slot)
      if slot < 0
        ext = jsr_ivar(ob, 1)
        return jsr_aget(ext, (0 - slot) - 1)
      return 6
    if pep[idx] != epoch
      return 6
    if slot > 0
      return jsr_ivar(h, slot)
    if slot < 0
      ext = jsr_ivar(h, 1)
      return jsr_aget(ext, (0 - slot) - 1)
  6

-> js_poly_ic_fill(sb, key, slot_enc, holder, epoch)
  kb = wvalue_bits(key) ## i64
  idx = (((sb >> 4) ^ (kb >> 4) ^ (sb >> 13)) & 511)
  off = idx << 2
  JS_POLY_KEEP[idx] = key
  JS_POLY_IC[off] = sb
  JS_POLY_IC[off + 1] = kb
  JS_POLY_IC[off + 2] = slot_enc
  JS_POLY_IC[off + 3] = holder
  JS_POLY_EP[idx] = epoch
  nil

# Fast cached prototype lookup for non-object values (Array.prototype / String.prototype methods).
-> js_proto_get_cached(proto, key, receiver)
  pb = wvalue_bits(proto) ## i64
  kb = wvalue_bits(key) ## i64
  ep = JS_EPOCH[0]
  r = jsr_poly_ic_get(JS_POLY_IC, JS_POLY_EP, pb, kb, ep)
  return wvalue_from_bits(r) if r != JSR_SLOW
  s = proto.shape
  if !s.dict && js_ivar_cacheable?(proto)
    i = s.slot_of(key)
    if i >= 0 && (s.attrs_of(key) & ATTR_ACCESSOR) == 0
      slot_enc = i < s.inline ? (s.ibase + i) : (0 - (i - s.inline) - 1)
      js_poly_ic_fill(wvalue_bits(s) ## i64, key, slot_enc ## i64, pb, ep)
      return proto.slot_get(i)
  proto.get(key, receiver)

# o[key] for a site with cache k (k = 4 × site number) in the program's table.
-> js_getp(o, key, k)
  ob = wvalue_bits(o) ## i64
  ep = JS_EPOCH[0]
  r = jsr_ic_get(JS_IC, k, ob, ep)
  return wvalue_from_bits(r) if r != JSR_SLOW
  r2 = jsr_poly_ic_get(JS_POLY_IC, JS_POLY_EP, ob, wvalue_bits(key) ## i64, ep)
  return wvalue_from_bits(r2) if r2 != JSR_SLOW
  js_get_miss(o, key, JS_IC, k)

# The same with a cache of the caller's own (tier 0 keeps one per property node).
-> js_getp_ic(o, key, ic)
  ob = wvalue_bits(o) ## i64
  ep = JS_EPOCH[0]
  r = jsr_ic_get(ic, 0, ob, ep)
  return wvalue_from_bits(r) if r != JSR_SLOW
  r2 = jsr_poly_ic_get(JS_POLY_IC, JS_POLY_EP, ob, wvalue_bits(key) ## i64, ep)
  return wvalue_from_bits(r2) if r2 != JSR_SLOW
  js_get_miss(o, key, ic, 0)

-> js_get_miss(o, key, ic, k)
  return js_get_prim(o, key) if !o.is_a?(JS:Base)
  s = o.shape
  if !s.dict && js_ivar_cacheable?(o)
    sb = wvalue_bits(s) ## i64
    i = s.slot_of(key)
    if i >= 0
      if s.attrs_of(key) & ATTR_ACCESSOR == 0
        slot_enc = i < s.inline ? (s.ibase + i) : (0 - (i - s.inline) - 1)
        js_ic_fill_get(ic, k, sb, slot_enc ## i64, 0 ## i64, 0 ## i64)
        js_poly_ic_fill(sb, key, slot_enc ## i64, 0 ## i64, 0 ## i64)
    else
      p = s.proto
      if p != nil && p.is_a?(JS:Base) && js_ivar_cacheable?(p) && p.get_virtual(key) == JS_HOLE && o.get_virtual(key) == JS_HOLE
        ps = p.shape
        j = ps.slot_of(key)
        if j >= 0 && !ps.dict && ps.attrs_of(key) & ATTR_ACCESSOR == 0
          slot_enc = j < ps.inline ? (ps.ibase + j) : (0 - (j - ps.inline) - 1)
          pb = wvalue_bits(p) ## i64
          ep = JS_EPOCH[0]
          js_ic_fill_get(ic, k, sb, slot_enc ## i64, pb, ep)
          js_poly_ic_fill(sb, key, slot_enc ## i64, pb, ep)
  o.get(key, o)

# Objects whose properties all live in plain slots (exotic classes override get).
-> js_ivar_cacheable?(o)
  k = jsr_kind(wvalue_bits(o) ## i64) & 15
  k == KIND_OBJECT || k == KIND_FUNCTION

# o[key] = v for a site with cache k. Returns v.
-> js_setp(o, key, v, k)
  i = jsr_ic_set(JS_IC, k, wvalue_bits(o) ## i64, JS_EPOCH[0])
  if i > 0
    ccall("w_ivar_set_idx", o, i, v)
    return v
  if i < 0
    o.ext[(0 - i) - 1] = v
    return v
  js_set_miss(o, key, v, JS_IC, k, false)

-> js_setp_ic(o, key, v, ic, strict)
  i = jsr_ic_set(ic, 0, wvalue_bits(o) ## i64, JS_EPOCH[0])
  if i > 0
    ccall("w_ivar_set_idx", o, i, v)
    return v
  if i < 0
    o.ext[(0 - i) - 1] = v
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
    if cache && s.attrs_of(key) == ATTR_DEFAULT
      slot_enc = i < s.inline ? (s.ibase + i) : (0 - (i - s.inline) - 1)
      js_ic_fill_set_own(ic, k, wvalue_bits(s) ## i64, slot_enc ## i64)
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
# receiver is always right while the prototypes keep their layout). Also rejects Proxy/exotic prototypes.
-> js_proto_chain_plain?(p, key)
  while p != nil
    return false if !p.is_a?(JS:Base) || !js_ivar_cacheable?(p)
    ps = p.shape
    j = ps.slot_of(key)
    return false if j >= 0
    p = ps.proto
  true

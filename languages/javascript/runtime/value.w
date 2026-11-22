# blade/js/value — the JavaScript value model and abstract operations (ECMA-262 §6–7).
#
# Representation (chosen so the common cases are plain Tungsten values):
#   undefined → nil            null    → JS_NULL (a JsNull)
#   boolean   → true / false   number  → Float (always: JS has one number type)
#   string    → String (UTF-8; length and indexing are in UTF-16 code units, see js_len / js_char_code_at)
#   bigint    → JsBigInt (wraps a Tungsten Integer, kept distinct from number)
#   symbol    → JsSymbol       object  → JsObject and subclasses
#
# Properties: a data property with the default attributes (writable, enumerable,
# configurable) is just @props[key] = value. Non-default attributes live in
# @attrs[key] (bit flags), and accessors in @getters / @setters, so ordinary
# objects pay nothing for them. Keys are Strings or JsSymbols; array indices are
# canonical numeric strings ("0", "1", …) except in a JsArray's dense @elems.

+ JsNull
  -> new
  -> to_s
    "null"

JS_NULL = JsNull.new

# Marks an array hole (distinct from undefined).
+ JsHole
  -> new
JS_HOLE = JsHole.new

+ JsSymbol
  ro :description
  -> new(@description)
  -> to_s
    "Symbol(" + (@description == nil ? "" : @description) + ")"

+ JsBigInt
  ro :v
  -> new(@v)

# A thrown JavaScript value travelling through Tungsten's rescue.
+ JsThrow < Error
  ro :value
  -> new(@value)
  -> message
    v = @value
    if v.is_a?(JsObject)
      m = v.get_own("message")
      n = v.get_own("name")
      return (n == nil ? "Error" : n.to_s) + ": " + (m == nil ? "" : m.to_s)
    js_to_display(v)
  -> to_s
    message()

ATTR_W = 1
ATTR_E = 2
ATTR_C = 4
ATTR_ALL = 7

# Well-known symbols.
SYM_ITERATOR = JsSymbol.new("Symbol.iterator")
SYM_ASYNC_ITERATOR = JsSymbol.new("Symbol.asyncIterator")
SYM_TO_PRIMITIVE = JsSymbol.new("Symbol.toPrimitive")
SYM_TO_STRING_TAG = JsSymbol.new("Symbol.toStringTag")
SYM_HAS_INSTANCE = JsSymbol.new("Symbol.hasInstance")
SYM_SPECIES = JsSymbol.new("Symbol.species")
SYM_UNSCOPABLES = JsSymbol.new("Symbol.unscopables")
SYM_IS_CONCAT_SPREADABLE = JsSymbol.new("Symbol.isConcatSpreadable")
SYM_MATCH = JsSymbol.new("Symbol.match")
SYM_MATCH_ALL = JsSymbol.new("Symbol.matchAll")
SYM_REPLACE = JsSymbol.new("Symbol.replace")
SYM_SEARCH = JsSymbol.new("Symbol.search")
SYM_SPLIT = JsSymbol.new("Symbol.split")

# A property descriptor (§6.2.6). Absent fields are tracked with has_* flags because
# undefined (nil) is a legal value.
+ JsPropDesc
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
    d = JsPropDesc.new
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


+ JsObject
  rw :proto, :props, :attrs, :getters, :setters, :extensible, :cls, :internal, :priv, :priv_handlers, :seq

  # [[IsHTMLDDA]] (Annex B, document.all): typeof "undefined", falsy, == null.
  -> htmldda?
    false

  -> new(@proto = JS_NULL, @cls = "Object")
    @props = {}
    @attrs = nil
    @getters = nil
    @setters = nil
    @extensible = true
    @internal = nil
    @seq = nil

  -> proxy?
    false

  -> callable?
    false

  # ---- own properties (raw, no exotic behaviour beyond what subclasses add) ----

  -> has_own?(k)
    @props.has_key?(k) || (@getters != nil && @getters.has_key?(k)) || (@setters != nil && @setters.has_key?(k))

  -> accessor?(k)
    (@getters != nil && @getters.has_key?(k)) || (@setters != nil && @setters.has_key?(k))

  -> attr(k)
    return ATTR_ALL if @attrs == nil
    a = @attrs[k]
    a == nil ? ATTR_ALL : a

  # The raw own data value (no getters), or nil.
  -> get_own(k)
    @props[k]

  # Define (or redefine) a data property.
  -> define(k, v, flags = ATTR_ALL)
    ord_define(k, v, flags)

  # The ordinary definitions behind define / define_accessor / get / set. Subclasses call
  # these rather than `super` (TODO(tungsten): super(...) from an override with a default
  # parameter is dropped by the compiled engine; repro in the js-runtime README).
  -> ord_define(k, v, flags)
    js_note_proto_index(self, k)
    note_key(k) if @seq != nil
    if @getters != nil
      @getters.delete(k)
    if @setters != nil
      @setters.delete(k)
    @props[k] = v
    if flags != ATTR_ALL
      @attrs = {} if @attrs == nil
      @attrs[k] = flags
    elsif @attrs != nil && @attrs.has_key?(k)
      @attrs.delete(k)
    self

  # Define an accessor property; g / s are JsFunctions or nil.
  -> define_accessor(k, g, s, flags = ATTR_E + ATTR_C)
    ord_define_accessor(k, g, s, flags)

  -> ord_define_accessor(k, g, s, flags)
    js_note_proto_index(self, k)
    start_seq()
    note_key(k)
    @props.delete(k)
    @getters = {} if @getters == nil
    @setters = {} if @setters == nil
    @getters[k] = g
    if s == nil
      @setters.delete(k)
    else
      @setters[k] = s
    @attrs = {} if @attrs == nil
    @attrs[k] = flags & (ATTR_E + ATTR_C)
    self

  -> getter_of(k)
    @getters == nil ? nil : @getters[k]

  -> setter_of(k)
    @setters == nil ? nil : @setters[k]

  -> delete_own(k)
    return true if !has_own?(k)
    return false if (attr(k) & ATTR_C) == 0
    @props.delete(k)
    @getters.delete(k) if @getters != nil
    @setters.delete(k) if @setters != nil
    @attrs.delete(k) if @attrs != nil
    @seq.delete(k) if @seq != nil
    true

  # Insertion order across data and accessor properties, kept once an object has an accessor
  # (accessors live in their own tables): key -> creation number.
  -> note_key(k)
    if @seq != nil && !@seq.has_key?(k)
      n = @seq[:next]
      @seq[k] = n
      @seq[:next] = n + 1
    nil

  -> start_seq
    return nil if @seq != nil
    @seq = {}
    @seq[:next] = 0
    @props.keys.each ->(k) note_key(k)
    @getters.keys.each(->(k) note_key(k)) if @getters != nil
    @setters.keys.each(->(k) note_key(k)) if @setters != nil
    nil

  # Own keys in spec order: integer indices ascending, then strings in insertion order, then symbols.
  -> own_keys
    ints = nil
    strs = []
    syms = nil
    @props.keys.each ->(k)
      if k.is_a?(JsSymbol)
        syms = [] if syms == nil
        syms.push(k)
      elsif js_array_index?(k)
        ints = [] if ints == nil
        ints.push(k)
      else
        strs.push(k)
    if @getters != nil
      @getters.keys.each ->(k)
        if !@props.has_key?(k)
          if k.is_a?(JsSymbol)
            syms = [] if syms == nil
            syms.push(k)
          elsif js_array_index?(k)
            ints = [] if ints == nil
            ints.push(k)
          else
            strs.push(k)
    if @setters != nil
      @setters.keys.each ->(k)
        if !@props.has_key?(k) && (@getters == nil || !@getters.has_key?(k))
          if k.is_a?(JsSymbol)
            syms = [] if syms == nil
            syms.push(k)
          else
            strs.push(k)
    if @seq != nil
      sq = @seq
      strs = strs.sort_by(->(k) sq.has_key?(k) ? sq[k] : 0) if strs.size > 1
      syms = syms.sort_by(->(k) sq.has_key?(k) ? sq[k] : 0) if syms != nil && syms.size > 1
    return strs if ints == nil && syms == nil
    out = []
    if ints != nil
      ints = ints.sort_by(->(k) k.to_i) if ints.size > 1
      ints.each ->(k) out.push(k)
    strs.each ->(k) out.push(k)
    syms.each(->(k) out.push(k)) if syms != nil
    out

  -> enumerable?(k)
    (attr(k) & ATTR_E) != 0

  # ---- the object internal methods (§10.1); exotic objects override these ----

  -> get_prototype_of
    @proto

  -> set_prototype_of(p)
    return true if p == @proto
    return false if !@extensible
    q = p
    while q != JS_NULL && q != nil
      return false if q == self
      break if q.proxy?
      q = q.proto
    @proto = p
    true

  -> is_extensible?
    @extensible

  -> prevent_extensions
    @extensible = false
    true

  -> get_own_property(k)
    return nil if !has_own?(k)
    d = JsPropDesc.new
    a = attr(k)
    if accessor?(k)
      d.getter = getter_of(k)
      d.setter = setter_of(k)
      d.has_get = true
      d.has_set = true
    else
      d.value = get_own(k)
      d.has_value = true
      d.writable = (a & ATTR_W) != 0
    d.enumerable = (a & ATTR_E) != 0
    d.configurable = (a & ATTR_C) != 0
    d

  # ValidateAndApplyPropertyDescriptor (§10.1.6.3). Returns false when not allowed.
  -> define_own_property(k, desc)
    cur = get_own_property(k)
    if cur == nil
      return false if !is_extensible?
      if desc.accessor?
        define_accessor(k, desc.getter, desc.setter, desc.flags & (ATTR_E + ATTR_C))
      else
        define(k, desc.value, desc.flags)
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
      s = desc.has_set ? desc.setter : (cur.accessor? ? cur.setter : nil)
      define_accessor(k, g, s, fl)
    elsif desc.data? || !cur.accessor?
      w = desc.writable == nil ? (cur.accessor? ? false : cur.writable) : desc.writable
      v = desc.has_value ? desc.value : (cur.accessor? ? nil : cur.value)
      define(k, v, fl | (w ? ATTR_W : 0))
    else
      define_accessor(k, cur.getter, cur.setter, fl)
    true

  # ---- [[Get]] / [[Set]] / [[HasProperty]] with the prototype chain ----

  -> get(k, receiver = nil)
    ord_get(k, receiver)

  -> ord_get(k, receiver)
    o = self
    while o != JS_NULL && o != nil
      v = o.props[k]
      return v if v != nil
      if o.has_own_slot?(k)
        return o.own_value(k, receiver == nil ? self : receiver)
      o = o.proto
    nil

  # Is there an own slot for k (data or accessor, value possibly undefined)?
  -> has_own_slot?(k)
    has_own?(k)

  -> own_value(k, receiver)
    if accessor?(k)
      g = getter_of(k)
      return nil if g == nil
      return js_call(g, receiver, [])
    @props[k]

  # OrdinarySet: false when the assignment is not allowed (strict callers then throw).
  -> set(k, v, receiver = nil)
    ord_set(k, v, receiver)

  -> ord_set(k, v, receiver)
    receiver = self if receiver == nil
    if receiver == self && (@attrs == nil || !@attrs.has_key?(k)) && @props.has_key?(k)
      @props[k] = v
      return true
    o = self
    while o != JS_NULL && o != nil
      return o.set(k, v, receiver) if o.proxy?
      if o.has_own_slot?(k)
        if o.accessor?(k)
          s = o.setter_of(k)
          return false if s == nil
          js_call(s, receiver, [v])
          return true
        return false if (o.attr(k) & ATTR_W) == 0
        break
      o = o.proto
    return false if !receiver.is_a?(JsObject)
    return receiver.put_own(k, v) if receiver == self
    js_set_on_receiver(receiver, k, v)

  # Create or overwrite an own data property through [[Set]].
  -> put_own(k, v)
    if has_own?(k)
      return false if accessor?(k)
      return false if (attr(k) & ATTR_W) == 0
      @props[k] = v
      return true
    return false if !@extensible
    js_note_proto_index(self, k)
    note_key(k) if @seq != nil
    @props[k] = v
    true

  -> has_property?(k)
    o = self
    while o != JS_NULL && o != nil
      return o.has_property?(k) if o.proxy?
      return true if o.has_own_slot?(k)
      o = o.proto
    false

  # Integer-indexed access (i is an Int >= 0); exotic objects override for speed.
  -> get_idx(i)
    get(i.to_s, self)

  -> set_idx(i, v)
    set(i.to_s, v, self)

  # ---- private elements (#x), keyed by JsPrivateName ----

  -> priv_get(pn)
    js_throw_type("Cannot read private member #" + pn.description + " from an object whose class did not declare it") if @priv == nil || !@priv.has_key?(pn)
    e = @priv[pn]
    if e.is_a?(JsPrivAccessor)
      js_throw_type("'#" + pn.description + "' was defined without a getter") if e.getter == nil
      return js_call(e.getter, self, [])
    e

  -> priv_set(pn, v)
    js_throw_type("Cannot write private member #" + pn.description + " to an object whose class did not declare it") if @priv == nil || !@priv.has_key?(pn)
    e = @priv[pn]
    if e.is_a?(JsPrivAccessor)
      js_throw_type("'#" + pn.description + "' was defined without a setter") if e.setter == nil
      js_call(e.setter, self, [v])
      return v
    js_throw_type("Private method #" + pn.description + " is not writable") if pn.is_method
    @priv[pn] = v
    v

  -> priv_add(pn, v)
    @priv = {} if @priv == nil
    js_throw_type("Cannot initialize #" + pn.description + " twice on the same object") if @priv.has_key?(pn)
    @priv[pn] = v

  -> priv_has?(pn)
    @priv != nil && @priv.has_key?(pn)


# Set on a receiver other than the object where the lookup started (Reflect.set, super.x = v).
-> js_set_on_receiver(receiver, k, v)
  cur = receiver.get_own_property(k)
  if cur != nil
    return false if cur.accessor?
    return false if cur.writable == false
    d = JsPropDesc.new
    d.value = v
    d.has_value = true
    return receiver.define_own_property(k, d)
  receiver.define_own_property(k, JsPropDesc.data(v, ATTR_ALL))

+ JsPrivateName
  rw :description, :is_method
  -> new(@description)
    @is_method = false

+ JsPrivAccessor
  rw :getter, :setter
  -> new(@getter, @setter)


# Arrays: indices in a dense Tungsten array (holes are JS_HOLE), the rest as ordinary
# properties. An index far past the end goes to @props (sparse) and @slen keeps the length.
ARRAY_GAP = 65536

+ JsArray < JsObject
  rw :elems, :slen, :len_ro

  -> new(@proto, @elems = [])
    @cls = "Array"
    @props = {}
    @attrs = nil
    @getters = nil
    @setters = nil
    @extensible = true
    @internal = nil
    @slen = nil
    @len_ro = false

  -> length
    return @elems.size if @slen == nil
    @slen > @elems.size ? @slen : @elems.size

  -> index_of_key(k)
    return -1 if !k.is_a?(String) || k.size == 0
    b = k.byte_at(0)
    return -1 if b < 48 || b > 57
    return -1 if !js_array_index?(k)
    k.to_i

  -> has_own?(k)
    return true if k == "length"
    i = index_of_key(k)
    return i < @elems.size && @elems[i] != JS_HOLE if i >= 0 && @slen == nil
    if i >= 0 && i < @elems.size
      return @elems[i] != JS_HOLE
    super(k)

  -> has_own_slot?(k)
    has_own?(k)

  -> accessor?(k)
    return false if k == "length"
    super(k)

  -> attr(k)
    return (@len_ro ? 0 : ATTR_W) if k == "length"
    i = index_of_key(k)
    return ATTR_ALL if i >= 0 && i < @elems.size
    super(k)

  -> get_own(k)
    return (length() + ~0.0) if k == "length"
    i = index_of_key(k)
    if i >= 0 && i < @elems.size
      v = @elems[i]
      return v == JS_HOLE ? nil : v
    @props[k]

  -> get(k, receiver = nil)
    i = index_of_key(k)
    if i >= 0 && i < @elems.size
      v = @elems[i]
      return v if v != JS_HOLE
    return (length() + ~0.0) if k == "length"
    ord_get(k, receiver)

  -> own_value(k, receiver)
    return get_own(k) if k == "length"
    i = index_of_key(k)
    return get_own(k) if i >= 0 && i < @elems.size
    super(k, receiver)

  -> set(k, v, receiver = nil)
    if receiver == nil || receiver == self
      i = index_of_key(k)
      if i >= 0 && i < @elems.size && @elems[i] != JS_HOLE && @extensible
        @elems[i] = v
        return true
    ord_set(k, v, receiver)

  -> put_own(k, v)
    if k == "length"
      return false if @len_ro
      set_length(js_to_number(v))
      return true
    i = index_of_key(k)
    if i >= 0
      if i < @elems.size
        return false if @elems[i] == JS_HOLE && !@extensible
        @elems[i] = v
        return true
      # an existing sparse element is an ordinary property (attributes apply; no growth)
      return super(k, v) if @slen != nil && @props.has_key?(k)
      return false if !@extensible
      return false if @len_ro && i >= length()
      if i == @elems.size && @slen == nil
        @elems.push(v)
        return true
      if i - @elems.size < ARRAY_GAP && @slen == nil
        while @elems.size < i
          @elems.push(JS_HOLE)
        @elems.push(v)
        return true
      @props[k] = v
      @slen = i + 1 if @slen == nil || i + 1 > @slen
      return true
    super(k, v)

  -> get_idx(i)
    if i < @elems.size
      v = @elems[i]
      return v if v != JS_HOLE
    get(i.to_s, self)

  -> set_idx(i, v)
    if i < @elems.size && @elems[i] != JS_HOLE
      @elems[i] = v
      return true
    set(i.to_s, v, self)

  # Element i (an Int) for the fast paths; nil for holes and out of range.
  -> at(i)
    return nil if i < 0 || i >= @elems.size
    v = @elems[i]
    v == JS_HOLE ? nil : v

  -> define(k, v, flags = ATTR_ALL)
    i = index_of_key(k)
    if i >= 0 && flags == ATTR_ALL
      ok = @extensible
      @extensible = true
      put_own(k, v)
      @extensible = ok
      return self
    if k == "length"
      set_length(js_to_number(v))
      @len_ro = (flags & ATTR_W) == 0
      return self
    if i >= 0 && i < @elems.size
      # an index with non-default attributes: move the tail out of the dense part
      sparsify(i)
    ord_define(k, v, flags)

  -> define_accessor(k, g, s, flags = ATTR_E + ATTR_C)
    i = index_of_key(k)
    sparsify(i) if i >= 0 && i < @elems.size
    ord_define_accessor(k, g, s, flags)

  # Move elements i.. into @props so index i can carry attributes or accessors.
  -> sparsify(i)
    n = length()
    j = i
    while j < @elems.size
      @props[j.to_s] = @elems[j] if @elems[j] != JS_HOLE
      j += 1
    while @elems.size > i
      @elems.pop
    @slen = n

  # Leave sparse mode when the array is small again and its elements are plain data.
  -> densify
    return nil if @slen == nil || @slen >= ARRAY_GAP || !@extensible || @len_ro
    idx = []
    plain = true
    @props.keys.each ->(pk)
      if pk.is_a?(String) && js_array_index?(pk)
        idx.push(pk)
        plain = false if (@attrs != nil && @attrs[pk] != nil && @attrs[pk] != ATTR_ALL) || (@getters != nil && @getters.has_key?(pk)) || (@setters != nil && @setters.has_key?(pk))
    return nil if !plain
    n = @slen
    while @elems.size < n
      @elems.push(JS_HOLE)
    idx.each ->(pk)
      @elems[pk.to_i] = @props[pk]
      @props.delete(pk)
    @slen = nil
    nil

  -> delete_own(k)
    i = index_of_key(k)
    if i >= 0 && i < @elems.size
      return false if !@extensible && false
      if i == @elems.size - 1 && @slen == nil
        @elems[i] = JS_HOLE
      else
        @elems[i] = JS_HOLE
      return true
    return false if k == "length"
    super(k)

  -> get_own_property(k)
    if k == "length"
      return JsPropDesc.data(length() + ~0.0, @len_ro ? 0 : ATTR_W)
    i = index_of_key(k)
    if i >= 0 && i < @elems.size
      v = @elems[i]
      return nil if v == JS_HOLE
      return JsPropDesc.data(v, ATTR_ALL)
    super(k)

  -> define_own_property(k, desc)
    if k == "length"
      if desc.has_value
        n = js_to_number(desc.value)
        len = js_to_uint32(n)
        raise JsThrow.new(js_range_error("Invalid array length")) if len + ~0.0 != n
        return false if @len_ro && len != length()
        set_length(len + ~0.0)
      @len_ro = true if desc.writable == false
      return true
    i = index_of_key(k)
    if i >= 0
      return false if @len_ro && i >= length()
      if !desc.accessor? && (desc.flags == ATTR_ALL || (desc.writable == nil && desc.enumerable == nil && desc.configurable == nil && i < @elems.size && @elems[i] != JS_HOLE)) && (i < @elems.size || i - @elems.size < ARRAY_GAP) && @slen == nil
        return false if !@extensible && !(i < @elems.size && @elems[i] != JS_HOLE)
        cur = i < @elems.size ? @elems[i] : JS_HOLE
        val = desc.has_value ? desc.value : (cur == JS_HOLE ? nil : cur)
        ok = @extensible
        @extensible = true
        put_own(k, val)
        @extensible = ok
        return true
      sparsify(i) if i < @elems.size
      r = super(k, desc)
      @slen = i + 1 if r && (@slen == nil || i + 1 > @slen) && i >= @elems.size
      return r
    super(k, desc)

  -> set_length(n)
    len = n.to_i
    raise JsThrow.new(js_range_error("Invalid array length")) if len < 0 || n != len + ~0.0 || len > 4294967295
    if @slen != nil
      # ArraySetLength stops above the highest non-configurable element (§10.4.2.4)
      @props.keys.each ->(pk)
        if pk.is_a?(String) && js_array_index?(pk) && pk.to_i >= len && @attrs != nil && @attrs[pk] != nil && (@attrs[pk] & ATTR_C) == 0
          len = pk.to_i + 1 if pk.to_i + 1 > len
      @props.keys.each ->(pk)
        if pk.is_a?(String) && js_array_index?(pk) && pk.to_i >= len
          @props.delete(pk)
          @attrs.delete(pk) if @attrs != nil
      @slen = len
      densify()
    while @elems.size > len
      @elems.pop
    if @slen == nil && len - @elems.size < ARRAY_GAP
      while @elems.size < len
        @elems.push(JS_HOLE)
    elsif @slen == nil
      @slen = len

  -> own_keys
    out = []
    i = 0
    n = @elems.size
    while i < n
      out.push(i.to_s) if @elems[i] != JS_HOLE
      i += 1
    rest = super()
    if @slen != nil
      ints = rest.select(->(k) k.is_a?(String) && js_array_index?(k))
      ints.each ->(k) out.push(k)
      out.push("length")
      rest.each ->(k) out.push(k) if !(k.is_a?(String) && js_array_index?(k))
      return out
    out.push("length")
    rest.each ->(k) out.push(k)
    out

  -> enumerable?(k)
    return false if k == "length"
    super(k)


# Functions. A native function is a Tungsten lambda ->(this, args, new_target);
# interpreted functions carry their code and scope in @code / @scope for the interpreter.
# @lazy: the "prototype" object is made on first use (1 ordinary, 2 generator, 3 async generator).
+ JsFunction < JsObject
  rw :native, :code, :scope, :fname, :arity, :ctor, :this_mode, :home, :fields, :bound, :lazy, :cls_kind

  -> new(@proto, @native, @fname = "", @arity = 0, @ctor = false)
    @cls = "Function"
    @props = {}
    @attrs = nil
    @getters = nil
    @setters = nil
    @extensible = true
    @internal = nil
    @code = nil
    @scope = nil
    @this_mode = :normal
    @home = nil
    @fields = nil
    @bound = nil
    @lazy = 0
    @cls_kind = nil
    @props["length"] = @arity + ~0.0
    @props["name"] = @fname
    @attrs = {"length" => ATTR_C, "name" => ATTR_C}

  -> callable?
    true

  -> materialize
    kind = @lazy
    @lazy = 0
    r = JS_REALM[0]
    if kind == 1
      p = JsObject.new(r.object_proto, "Object")
      p.define("constructor", self, ATTR_W + ATTR_C)
    elsif kind == 2
      p = JsObject.new(r.intrinsic("%GeneratorPrototype%"), "Object")
    else
      p = JsObject.new(r.intrinsic("%AsyncGeneratorPrototype%"), "Object")
    @props["prototype"] = p
    @attrs["prototype"] = ATTR_W

  -> has_own?(k)
    materialize() if @lazy != 0 && k == "prototype"
    super(k)

  -> get_own(k)
    materialize() if @lazy != 0 && k == "prototype"
    @props[k]

  -> get(k, receiver = nil)
    materialize() if @lazy != 0 && k == "prototype"
    ord_get(k, receiver)

  -> own_keys
    materialize() if @lazy != 0
    super()

  -> put_own(k, v)
    materialize() if @lazy != 0 && k == "prototype"
    super(k, v)

  -> set(k, v, receiver = nil)
    materialize() if @lazy != 0 && k == "prototype"
    ord_set(k, v, receiver)

  -> define(k, v, flags = ATTR_ALL)
    @lazy = 0 if k == "prototype"
    ord_define(k, v, flags)

  -> delete_own(k)
    materialize() if @lazy != 0 && k == "prototype"
    super(k)

  -> get_own_property(k)
    materialize() if @lazy != 0 && k == "prototype"
    super(k)

  -> define_own_property(k, desc)
    materialize() if @lazy != 0 && k == "prototype"
    super(k, desc)


# The interpreter installs these: how to call an interpreted function, and the current realm.
JS_CALL_HOOK = [nil]
JS_CONSTRUCT_HOOK = [nil]
# per thread (blade/js/tls): each Web Worker thread has its own realm
JS_REALM = JsTlsCell.new(1, nil)

-> js_call(f, this, args)
  if f.is_a?(JsFunction)
    return f.native.call(this, args, nil) if f.native != nil
    return js_call_code(f, this, args)
  return f.call_obj(this, args) if f.is_a?(JsObject) && f.callable?
  raise JsThrow.new(js_type_error(js_typeof(f) == "undefined" ? "undefined is not a function" : js_to_display(f) + " is not a function"))

-> js_construct(f, args, new_target = nil)
  new_target = f if new_target == nil
  return f.construct_obj(args, new_target) if f.is_a?(JsObject) && f.proxy? && f.is_constructor?
  raise JsThrow.new(js_type_error(js_to_display(f) + " is not a constructor")) if !f.is_a?(JsFunction) || !f.ctor
  if f.native != nil
    return f.native.call(nil, args, new_target)
  js_construct_code(f, args, new_target)


# ---- errors ----

-> js_make_error(kind, msg)
  r = JS_REALM[0]
  proto = r == nil ? JS_NULL : r.proto_of(kind)
  e = JsObject.new(proto, "Error")
  e.define("message", msg, ATTR_W + ATTR_C)
  js_error_locate(e)
  e

# JSC's own properties on a new Error: line, column, sourceURL (enumerable), stack.
-> js_error_locate(e)
  loc = js_top_location()
  e.define("line", loc[1] + ~0.0, ATTR_ALL)
  e.define("column", loc[2] + ~0.0, ATTR_ALL)
  e.define("sourceURL", loc[0], ATTR_ALL) if loc[0] != ""
  e.define("stack", js_stack_lines(), ATTR_W + ATTR_C)
  nil

-> js_type_error(msg)
  js_make_error("TypeError", msg)

-> js_range_error(msg)
  js_make_error("RangeError", msg)

-> js_reference_error(msg)
  js_make_error("ReferenceError", msg)

-> js_syntax_error(msg)
  js_make_error("SyntaxError", msg)

-> js_throw_type(msg)
  raise JsThrow.new(js_type_error(msg))


# ---- type predicates and typeof ----

-> js_number?(v)
  v.is_a?(Float)

-> js_object?(v)
  v.is_a?(JsObject)

-> js_typeof(v)
  return "undefined" if v == nil || (v.is_a?(JsObject) && v.htmldda?)
  return "object" if v == JS_NULL
  return "boolean" if v == true || v == false
  return "number" if v.is_a?(Float)
  return "string" if v.is_a?(String)
  return "symbol" if v.is_a?(JsSymbol)
  return "bigint" if v.is_a?(JsBigInt)
  return "function" if v.is_a?(JsFunction)
  "object"

-> js_nullish?(v)
  v == nil || v == JS_NULL


# ---- strings (UTF-16 view over UTF-8) ----

-> js_ascii?(s)
  s.ascii?

# UTF-16 code units of s, as an Array of Ints. The last few conversions are cached, so a
# loop over charCodeAt(i) of one non-ASCII string converts it once.
JS_UNITS_CACHE = JsTlsCell.new(4, nil)

-> js_units(s)
  c = JS_UNITS_CACHE
  return c[1] if c[0] != nil && c[0] == s
  return c[3] if c[2] != nil && c[2] == s
  u = js_units_raw(s)
  c[2] = c[0]
  c[3] = c[1]
  c[0] = s
  c[1] = u
  u

-> js_units_raw(s)
  out = []
  n = s.size
  i = 0
  while i < n
    b = s.byte_at(i)
    if b < 0x80
      out.push(b)
      i += 1
    elsif b < 0xE0 && i + 1 < n
      out.push(((b & 0x1F) << 6) | (s.byte_at(i + 1) & 0x3F))
      i += 2
    elsif b < 0xF0 && i + 2 < n
      out.push(((b & 0x0F) << 12) | ((s.byte_at(i + 1) & 0x3F) << 6) | (s.byte_at(i + 2) & 0x3F))
      i += 3
    elsif i + 3 < n
      cp = ((b & 0x07) << 18) | ((s.byte_at(i + 1) & 0x3F) << 12) | ((s.byte_at(i + 2) & 0x3F) << 6) | (s.byte_at(i + 3) & 0x3F)
      c = cp - 0x10000
      out.push(0xD800 + (c >> 10))
      out.push(0xDC00 + (c & 0x3FF))
      i += 4
    else
      out.push(0xFFFD)
      i += 1
  out

-> js_len(s)
  return s.size if js_ascii?(s)
  js_units(s).size

-> js_char_code_at(s, i)
  if js_ascii?(s)
    return nil if i < 0 || i >= s.size
    return s.byte_at(i) + ~0.0
  u = js_units(s)
  return nil if i < 0 || i >= u.size
  u[i] + ~0.0

# Code units → String (lone surrogates become U+FFFD).
-> js_from_units(u)
  sb = StringBuffer()
  i = 0
  while i < u.size
    c = u[i]
    if c >= 0xD800 && c <= 0xDBFF && i + 1 < u.size && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF
      cp = 0x10000 + ((c - 0xD800) << 10) + (u[i + 1] - 0xDC00)
      sb.append(js_chr(cp))
      i += 2
      next
    # a lone surrogate stays as its WTF-8 bytes, so it survives a round trip
    sb.append(js_chr(c))
    i += 1
  sb.to_s

# s.substring(a, b) in UTF-16 units.
-> js_substring(s, a, b)
  if js_ascii?(s)
    return "" if b <= a
    return s.slice(a, b - a)
  u = js_units(s)
  return "" if b <= a
  js_from_units(u.slice(a, b - a))


# ---- numbers ----

JS_NAN = [nil]

-> js_nan
  JS_NAN[0] = ~0.0 / ~0.0 if JS_NAN[0] == nil
  JS_NAN[0]

-> js_is_nan?(x)
  x.is_a?(Float) && x != x

# Number::toString(10): the shortest digits that round-trip, in JavaScript's notation.
# Float#to_s gives a round-tripping decimal (up to 17 digits); rounding its digit string to
# 15 and then 16 digits finds the shorter forms, each checked by parsing back.
# TODO(tungsten): a correctly rounded shortest formatter is coming to core (float-bits).
-> js_number_to_s(x)
  return "NaN" if x != x
  return "Infinity" if x == ~1.0 / ~0.0
  return "-Infinity" if x == ~-1.0 / ~0.0
  return "0" if x == ~0.0
  if x == Math.floor(x) && x.abs < ~9007199254740992.0
    return x.to_i.to_s
  neg = x < ~0.0
  a = neg ? ~0.0 - x : x
  de = js_digits_exp(a)
  ds = de[0]
  e = de[1]
  if ds.size > 15
    k = 15
    found = false
    while k < ds.size && !found
      r = js_round_digits(ds, e, k)
      cand = r[0]
      ce = r[1]
      if js_digits_value(cand, ce) == a
        ds = cand
        e = ce
        found = true
      k += 1
  out = js_format_digits(ds, e)
  neg ? "-" + out : out

# [significant digits without leading/trailing zeros, n] where value = 0.d1d2... * 10^n.
-> js_digits_exp(a)
  s = a.to_s
  ep = s.index("e")
  ex = 0
  mant = s
  if ep != nil
    ex = s.slice(ep + 1, s.size - ep - 1).to_i
    mant = s.slice(0, ep)
  dot = mant.index(".")
  ip = dot == nil ? mant : mant.slice(0, dot)
  fp = dot == nil ? "" : mant.slice(dot + 1, mant.size - dot - 1)
  digits = ip + fp
  n = ip.size + ex
  # strip leading zeros (each moves the point left)
  lz = 0
  while lz < digits.size - 1 && digits.byte_at(lz) == 48
    lz += 1
  digits = digits.slice(lz, digits.size - lz)
  n -= lz
  tz = digits.size
  while tz > 1 && digits.byte_at(tz - 1) == 48
    tz -= 1
  [digits.slice(0, tz), n]

# Round digit string ds (point exponent n) to k digits, half up: [digits, n].
-> js_round_digits(ds, n, k)
  return [ds, n] if ds.size <= k
  head = ds.slice(0, k)
  up = ds.byte_at(k) >= 53
  if up
    bytes = head.bytes.to_a
    i = k - 1
    carry = true
    while i >= 0 && carry
      if bytes[i] == 57
        bytes[i] = 48
        i -= 1
      else
        bytes[i] = bytes[i] + 1
        carry = false
    sb = StringBuffer()
    sb.append("1") if carry
    bytes.each ->(b) sb.append(b.chr)
    head = sb.to_s
    n += 1 if carry
  tz = head.size
  while tz > 1 && head.byte_at(tz - 1) == 48
    tz -= 1
  [head.slice(0, tz), n]

-> js_digits_value(ds, n)
  ("0." + ds + "e" + n.to_s).to_f

# Number::toString layout for digits ds (k of them) with point position n (§6.1.6.1.20).
-> js_format_digits(ds, n)
  k = ds.size
  if k <= n && n <= 21
    return ds + "0" * (n - k)
  if 0 < n && n <= 21
    return ds.slice(0, n) + "." + ds.slice(n, k - n)
  if -6 < n && n <= 0
    return "0." + "0" * (0 - n) + ds
  ex = n - 1
  sign = ex < 0 ? "-" : "+"
  exs = (ex < 0 ? 0 - ex : ex).to_s
  return ds + "e" + sign + exs if k == 1
  ds.slice(0, 1) + "." + ds.slice(1, k - 1) + "e" + sign + exs

# StringToNumber (whitespace-trimmed decimal, hex/octal/binary, Infinity; else NaN).
-> js_string_to_number(s)
  t = js_trim(s)
  return ~0.0 if t.size == 0
  if t.size > 2 && t.byte_at(0) == 48
    b = t.byte_at(1) | 32
    if b == 120 || b == 111 || b == 98
      radix = b == 120 ? 16 : (b == 111 ? 8 : 2)
      v = ~0.0
      i = 2
      while i < t.size
        d = js_digit(t.byte_at(i))
        return js_nan() if d < 0 || d >= radix
        v = v * radix + d
        i += 1
      return v
  sign = ~1.0
  body = t
  if t.byte_at(0) == 43 || t.byte_at(0) == 45
    sign = t.byte_at(0) == 45 ? ~-1.0 : ~1.0
    body = t.slice(1, t.size - 1)
  return sign * (~1.0 / ~0.0) if body == "Infinity"
  return js_nan() if !js_decimal_literal?(body)
  sign * body.to_f

-> js_digit(b)
  return b - 48 if b >= 48 && b <= 57
  return b - 87 if b >= 97 && b <= 122
  return b - 55 if b >= 65 && b <= 90
  -1

-> js_decimal_literal?(s)
  return false if s.size == 0
  i = 0
  n = s.size
  digits = 0
  while i < n && s.byte_at(i) >= 48 && s.byte_at(i) <= 57
    i += 1
    digits += 1
  if i < n && s.byte_at(i) == 46
    i += 1
    while i < n && s.byte_at(i) >= 48 && s.byte_at(i) <= 57
      i += 1
      digits += 1
  return false if digits == 0
  if i < n && (s.byte_at(i) == 101 || s.byte_at(i) == 69)
    i += 1
    i += 1 if i < n && (s.byte_at(i) == 43 || s.byte_at(i) == 45)
    ed = 0
    while i < n && s.byte_at(i) >= 48 && s.byte_at(i) <= 57
      i += 1
      ed += 1
    return false if ed == 0
  i == n

JS_WS = [9, 10, 11, 12, 13, 32]

-> js_trim(s)
  a = 0
  b = s.size
  while a < b && (JS_WS.include?(s.byte_at(a)) || js_unicode_space_at?(s, a))
    a += js_unicode_space_at?(s, a) ? js_unicode_space_len(s, a) : 1
  while b > a && JS_WS.include?(s.byte_at(b - 1))
    b -= 1
  s.slice(a, b - a)

# U+00A0, U+FEFF, U+2028/2029 and the Zs spaces are whitespace in JS too.
-> js_unicode_space_at?(s, i)
  b = s.byte_at(i)
  return s.slice(i, 2) == " " if b == 0xC2
  if b == 0xE2 || b == 0xEF || b == 0xE3 || b == 0xE1
    t = s.slice(i, 3)
    return t == " " || t == " " || t == "﻿" || t == "　" || t == " " || t == " " || t == " " || (t >= " " && t <= " ")
  false

-> js_unicode_space_len(s, i)
  s.byte_at(i) == 0xC2 ? 2 : 3


# ---- conversions (§7.1) ----

-> js_to_primitive(v, hint = "default")
  return v if !v.is_a?(JsObject)
  ex = v.get(SYM_TO_PRIMITIVE)
  if ex != nil && ex != JS_NULL
    r = js_call(ex, v, [hint])
    js_throw_type("Cannot convert object to primitive value") if r.is_a?(JsObject)
    return r
  order = hint == "string" ? ["toString", "valueOf"] : ["valueOf", "toString"]
  order.each ->(name)
    m = v.get(name)
    if m.is_a?(JsFunction)
      r = js_call(m, v, [])
      return r if !r.is_a?(JsObject)
  js_throw_type("Cannot convert object to primitive value")

-> js_to_boolean(v)
  return false if v == nil || v == JS_NULL || v == false
  return true if v == true
  return !(v == ~0.0 || v != v) if v.is_a?(Float)
  return v.size > 0 if v.is_a?(String)
  return v.v != 0 if v.is_a?(JsBigInt)
  return false if v.is_a?(JsObject) && v.htmldda?
  true

-> js_to_number(v)
  return v if v.is_a?(Float)
  return js_nan() if v == nil
  return ~0.0 if v == JS_NULL || v == false
  return ~1.0 if v == true
  return js_string_to_number(v) if v.is_a?(String)
  js_throw_type("Cannot convert a Symbol value to a number") if v.is_a?(JsSymbol)
  js_throw_type("Cannot convert a BigInt value to a number") if v.is_a?(JsBigInt)
  return v + ~0.0 if v.is_a?(Integer)
  js_to_number(js_to_primitive(v, "number"))

# TODO(tungsten): a function that returns an object on an early path and ends in a Float
# expression gets a Float return type in compiled code ("expected numeric type"); js_dyn
# on the tail keeps the result dynamic. Repro: spec numeric_infer.w in the README.
-> js_dyn(x)
  x

-> js_numeric_value(v)
  p = js_to_primitive(v, "number")
  return p if p.is_a?(JsBigInt) || p.is_a?(Float)
  js_dyn(js_to_number(p))

# ToIntegerOrInfinity
-> js_to_integer(v)
  n = js_to_number(v)
  return ~0.0 if n != n
  return n if n == ~1.0 / ~0.0 || n == ~-1.0 / ~0.0
  n < ~0.0 ? ~0.0 - Math.floor(~0.0 - n) : Math.floor(n)

-> js_to_int32(v)
  n = js_to_number(v)
  return 0 if n != n || n == ~1.0 / ~0.0 || n == ~-1.0 / ~0.0
  i = (n < ~0.0 ? ~0.0 - Math.floor(~0.0 - n) : Math.floor(n))
  m = (i % ~4294967296.0)
  m = m + ~4294967296.0 if m < ~0.0
  r = m.to_i
  r >= 2147483648 ? r - 4294967296 : r

-> js_to_uint32(v)
  r = js_to_int32(v)
  r < 0 ? r + 4294967296 : r

-> js_to_string(v)
  return v if v.is_a?(String)
  return "undefined" if v == nil
  return "null" if v == JS_NULL
  return "true" if v == true
  return "false" if v == false
  return js_number_to_s(v) if v.is_a?(Float)
  return v.v.to_s if v.is_a?(JsBigInt)
  js_throw_type("Cannot convert a Symbol value to a string") if v.is_a?(JsSymbol)
  return js_number_to_s(v + ~0.0) if v.is_a?(Integer)
  js_to_string(js_to_primitive(v, "string"))

-> js_to_property_key(v)
  return v if v.is_a?(String)
  return v if v.is_a?(JsSymbol)
  if v.is_a?(Float) && v == Math.floor(v) && v >= ~0.0 && v < ~4294967295.0
    return v.to_i.to_s
  p = js_to_primitive(v, "string")
  return p if p.is_a?(JsSymbol)
  js_to_string(p)

-> js_array_index?(k)
  n = k.size
  return false if n == 0 || n > 10
  return k == "0" if k.byte_at(0) == 48
  i = 0
  while i < n
    b = k.byte_at(i)
    return false if b < 48 || b > 57
    i += 1
  n < 10 || k <= "4294967294"

-> js_to_object(v)
  js_throw_type("Cannot convert undefined or null to object") if js_nullish?(v)
  return v if v.is_a?(JsObject)
  JS_REALM[0].wrap_primitive(v)

-> js_key_display(k)
  k.is_a?(JsSymbol) ? k.to_s : k

# A short human rendering for error messages and console output.
-> js_to_display(v)
  return "undefined" if v == nil
  return "null" if v == JS_NULL
  return "\"" + v + "\"" if v.is_a?(String) && v.size < 60
  return js_number_to_s(v) if v.is_a?(Float)
  return v.to_s if v.is_a?(JsSymbol)
  return v.v.to_s + "n" if v.is_a?(JsBigInt)
  return v.to_s if v == true || v == false
  if v.is_a?(JsFunction)
    return "function " + v.fname.to_s
  return "\[object " + v.cls + "]" if v.is_a?(JsObject)
  v.to_s


# ---- equality (§7.2) ----

-> js_same_value(a, b)
  if a.is_a?(Float) && b.is_a?(Float)
    return true if a != a && b != b
    return false if a == ~0.0 && b == ~0.0 && (~1.0 / a) != (~1.0 / b)
    return a == b
  js_strict_eq(a, b)

-> js_same_value_zero(a, b)
  return true if a.is_a?(Float) && b.is_a?(Float) && a != a && b != b
  js_strict_eq(a, b)

-> js_strict_eq(a, b)
  return a == b if a.is_a?(Float) && b.is_a?(Float)
  return a == b if a.is_a?(String) && b.is_a?(String)
  return a.v == b.v if a.is_a?(JsBigInt) && b.is_a?(JsBigInt)
  return false if a.is_a?(Float) || b.is_a?(Float) || a.is_a?(String) || b.is_a?(String) || a.is_a?(JsBigInt) || b.is_a?(JsBigInt)
  # everything else compares by identity (objects have no == override; nil/true/false are immediates)
  a == b

-> js_loose_eq(a, b)
  return true if (js_nullish?(a) && b.is_a?(JsObject) && b.htmldda?) || (js_nullish?(b) && a.is_a?(JsObject) && a.htmldda?)
  ta = js_typeof(a)
  tb = js_typeof(b)
  ta = "object" if ta == "function"
  tb = "object" if tb == "function"
  if ta == tb && !(a == JS_NULL || b == JS_NULL) || (a == JS_NULL && b == JS_NULL)
    return js_strict_eq(a, b)
  return true if js_nullish?(a) && js_nullish?(b)
  return false if js_nullish?(a) || js_nullish?(b)
  return js_loose_eq(a, js_string_to_number(b)) if ta == "number" && tb == "string"
  return js_loose_eq(js_string_to_number(a), b) if ta == "string" && tb == "number"
  if ta == "bigint" && tb == "string"
    n = js_string_to_number(b)
    return n == n && n == Math.floor(n) && a.v == n.to_i
  return js_loose_eq(b, a) if ta == "string" && tb == "bigint"
  return js_loose_eq(js_to_number(a), b) if ta == "boolean"
  return js_loose_eq(a, js_to_number(b)) if tb == "boolean"
  return js_loose_eq(a, js_to_primitive(b)) if (ta == "number" || ta == "string" || ta == "bigint" || ta == "symbol") && tb == "object"
  return js_loose_eq(js_to_primitive(a), b) if ta == "object" && (tb == "number" || tb == "string" || tb == "bigint" || tb == "symbol")
  if (ta == "bigint" && tb == "number") || (ta == "number" && tb == "bigint")
    n = ta == "number" ? a : b
    bi = ta == "bigint" ? a : b
    return false if n != n || n == ~1.0 / ~0.0 || n == ~-1.0 / ~0.0
    return n == Math.floor(n) && bi.v == n.to_i
  false

# Element i of an array as its iterator reads it: the dense slot, else [[Get]] (holes read
# through the prototype chain; sparse-mode elements live in props).
-> js_arr_elem(v, i)
  if v.slen == nil && i < v.elems.size
    x = v.elems[i]
    return x if x != JS_HOLE
  v.get(i.to_s, v)

# Array fast paths assume no indexed properties on Array.prototype / Object.prototype;
# the first one defined there turns that assumption off (realm.array_proto_indexed).
-> js_note_proto_index(o, k)
  r = JS_REALM[0]
  return nil if r == nil || r.array_proto_indexed
  return nil if !(o == r.array_proto || o == r.object_proto)
  r.array_proto_indexed = true if k.is_a?(String) && k.size > 0 && k.byte_at(0) >= 48 && k.byte_at(0) <= 57 && js_array_index?(k)
  nil

# One code point as UTF-8 (WTF-8 for lone surrogates).
-> js_chr(cp)
  cp.chr

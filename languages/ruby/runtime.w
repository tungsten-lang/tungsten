# tungsten/languages/ruby/runtime.w — Complete Ruby 3.4 / 4.0 Runtime & Stdlib
# with direct zero-copy Tungsten interoperability.
#
# Core design:
#   - Primitives stay unboxed Tungsten values whenever semantics match 100%:
#     Integer (automatic BigInt promotion), Float, Bool, nil, Symbol.
#   - Mutable Ruby Strings (`RbString`) carry per-string `Encoding` (`UTF-8`,
#     `ASCII-8BIT`, `US-ASCII`, etc.) and `frozen?` state (`# frozen_string_literal: true`),
#     converting seamlessly to/from Tungsten String at the `Tungsten` call boundary.
#   - Exact `RbRational` (`1/3r`) and `RbComplex` (`2+3i`) plus Ruby floor division `/` and `%`
#     and `Numeric#coerce`.
#   - `RbRegexp` + `RbMatchData` backed by Tungsten's `core/regex`, with Ruby named captures
#     `(?<name>...)` (including binding local variables on `/.../ =~ str`) and `$~`/`$1..$9`/`$&`.
#   - Full Ruby object model: `RbModule`, `RbClass`, `RbObject`, eigenclasses (`class << obj`),
#     MRO (`prepend` -> class -> `include` -> superclass), `method_missing`, `Struct`, `Data.define`.
#   - Blocks, `Proc`, `lambda`, Ruby 3.4 `it` implicit block param, `_1.._9`, non-local `return`,
#     `break`, `next`, `redo`, `retry`, `begin..rescue..else..ensure`, pattern matching (`case..in`,
#     `in`, `=>`), `Enumerator`.
#   - `Tungsten` bridge: call registered Tungsten closures/objects/stdlib directly from Ruby!

use core/regex
use ast
use parser_full
use vm

# ---- Control-flow signals (thrown via Tungsten exceptions for clean stack unwinding) ----

+ RbSignal
  ro :kind, :val, :target_id, :exc

  -> new(@kind, @val = nil, @target_id = 0, @exc = nil)

  -> to_s
    @exc != nil ? ("Ruby " + @exc.inspect) : ("RbSignal(" + @kind.to_s + ")")

# ---- Ruby Encoding ----

+ RbEncoding
  ro :name

  -> new(@name)

  -> to_s
    @name

  -> inspect
    "#<Encoding:" + @name + ">"

RB_ENC_UTF8 = RbEncoding.new("UTF-8")
RB_ENC_ASCII = RbEncoding.new("US-ASCII")
RB_ENC_BINARY = RbEncoding.new("ASCII-8BIT")

-> rb_find_encoding(nm)
  u = nm.to_s.upcase
  return RB_ENC_UTF8 if u == "UTF-8" || u == "UTF8"
  return RB_ENC_ASCII if u == "US-ASCII" || u == "ASCII"
  return RB_ENC_BINARY if u == "ASCII-8BIT" || u == "BINARY"
  RbEncoding.new(nm.to_s)

# ---- Mutable Ruby String with Encoding & Frozen State ----

+ RbString
  rw :data, :encoding, :frozen

  -> new(s, enc = RB_ENC_UTF8, frozen = false)
    @data = s.to_s
    @encoding = enc
    @frozen = frozen

  -> check_mut!
    raise RbSignal.new(:raise, nil, 0, RbException.new("FrozenError", "can't modify frozen String: " + inspect())) if @frozen

  -> to_s
    @data

  -> inspect
    '"' + @data.gsub("\\", "\\\\").gsub('"', '\\"').gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r") + '"'

  -> dup
    RbString.new(@data, @encoding, false)

  -> freeze
    @frozen = true
    self

  -> ==(other)
    return @data == other.data if other.is_a?(RbString)
    return @data == other if other.is_a?(String)
    false

# ---- Ruby Symbol ----

+ RbSym
  ro :name

  -> new(@name)

  -> to_s
    @name

  -> inspect
    ":" + @name

  -> ==(other)
    return @name == other.name if other.is_a?(RbSym)
    false

# ---- Exact Ruby Rational & Complex ----

-> rb_gcd(a, b)
  a = -a if a < 0
  b = -b if b < 0
  while b != 0
    t = a % b
    a = b
    b = t
  a == 0 ? 1 : a

+ RbRational
  ro :num, :den

  -> new(n, d = 1)
    raise RbSignal.new(:raise, nil, 0, RbException.new("ZeroDivisionError", "divided by 0")) if d == 0
    if d < 0
      n = -n
      d = -d
    g = rb_gcd(n, d)
    @num = n / g
    @den = d / g

  -> to_f
    @num.to_f / @den.to_f

  -> to_i
    @num / @den

  -> to_s
    @num.to_s + "/" + @den.to_s

  -> inspect
    "(" + @num.to_s + "/" + @den.to_s + ")"

  -> ==(o)
    return @num == o.num && @den == o.den if o.is_a?(RbRational)
    return @den == 1 && @num == o if o.is_a?(Integer)
    return to_f() == o if o.is_a?(Float)
    false

+ RbComplex
  ro :real, :imag

  -> new(@real, @imag = 0)

  -> to_s
    sgn = (@imag.is_a?(Float) ? @imag < ~0.0 : (@imag.is_a?(RbRational) ? @imag.num < 0 : @imag < 0)) ? "" : "+"
    @real.to_s + sgn + @imag.to_s + "i"

  -> inspect
    "(" + to_s() + ")"

  -> ==(o)
    return @real == o.real && @imag == o.imag if o.is_a?(RbComplex)
    return @imag == 0 && @real == o if o.is_a?(Integer) || o.is_a?(Float) || o.is_a?(RbRational)
    false

# ---- Ruby Range ----

+ RbRange
  ro :lo, :hi, :excl

  -> new(@lo, @hi, @excl = false)

  -> to_s
    (@lo == nil ? "" : @lo.to_s) + (@excl ? "..." : "..") + (@hi == nil ? "" : @hi.to_s)

  -> inspect
    to_s()

  -> to_a
    out = []
    return out if @lo == nil || @hi == nil
    if @lo.is_a?(Integer) && @hi.is_a?(Integer)
      cur = @lo
      while @excl ? (cur < @hi) : (cur <= @hi)
        out.push(cur)
        cur += 1
    elsif @lo.is_a?(RbString) && @hi.is_a?(RbString) && @lo.data.size == 1 && @hi.data.size == 1
      c = @lo.data.byte_at(0)
      e = @hi.data.byte_at(0)
      while @excl ? (c < e) : (c <= e)
        out.push(RbString.new(c.chr))
        c += 1
    out

  -> include?(v)
    return false if @lo != nil && rb_cmp(v, @lo) < 0
    return true if @hi == nil
    c = rb_cmp(v, @hi)
    @excl ? c < 0 : c <= 0

  -> ==(o)
    o.is_a?(RbRange) && @lo == o.lo && @hi == o.hi && @excl == o.excl

# ---- Ruby Regexp & MatchData (backed directly by Tungsten core/regex — native (?<name>...), /x, lookbehind, atomic, possessive!) ----

+ RbRegexp
  ro :source, :flags, :compiled, :named_groups

  -> new(@source, @flags = "")
    @named_groups = {}
    # Extract named group names in order for Ruby's `/lit/ =~ str` local variable binding
    i = 0
    n = @source.size
    grp = 0
    in_cc = false
    while i < n
      b = @source.byte_at(i)
      if b == 92 && i + 1 < n
        i += 2
      elsif b == 91 && !in_cc
        in_cc = true
        i += 1
      elsif b == 93 && in_cc
        in_cc = false
        i += 1
      elsif !in_cc && b == 40
        if i + 2 < n && @source.byte_at(i + 1) == 63 && @source.byte_at(i + 2) == 60
          b3 = i + 3 < n ? @source.byte_at(i + 3) : 0
          if b3 != 61 && b3 != 33
            gt = @source.index(">", i + 3)
            if gt != nil
              grp += 1
              @named_groups[@source.slice(i + 3, gt - i - 3)] = grp
              i = gt + 1
              next
        if !(i + 1 < n && @source.byte_at(i + 1) == 63)
          grp += 1
        i += 1
      else
        i += 1
    opts = ""
    opts = opts + "i" if @flags.index("i") != nil
    opts = opts + "m" if @flags.index("m") != nil
    opts = opts + "x" if @flags.index("x") != nil
    # Pass pattern & flags directly to Tungsten core/regex without any rewriting!
    @compiled = Regex.new(@source, opts)

  -> match_str(s, pos = 0)
    sub = pos > 0 ? (pos >= s.size ? "" : s.slice(pos, s.size - pos)) : s
    m = @compiled.match_data(sub)
    return nil if m == nil
    RbMatchData.new(self, s, m, pos)

  -> inspect
    "/" + @source + "/" + @flags

  -> to_s
    "(?-" + @flags + ":" + @source + ")"

+ RbMatchData
  ro :regexp, :string, :md, :offset_shift

  -> new(@regexp, @string, @md, @offset_shift = 0)

  -> get_group(idx)
    if idx.is_a?(RbSym) || idx.is_a?(RbString) || idx.is_a?(String)
      nm = idx.to_s
      gi = @regexp.named_groups[nm]
      return nil if gi == nil
      idx = gi
    v = @md[idx]
    v == nil ? nil : RbString.new(v)

  -> captures
    out = []
    i = 1
    while true
      v = @md[i]
      break if v == nil && @md.offset(i) == nil
      out.push(v == nil ? nil : RbString.new(v))
      i += 1
    out

  -> named_captures
    h = RbHash.new
    @regexp.named_groups.each ->(nm, gi)
      h.set(RbString.new(nm), get_group(gi))
    h

  -> begin_pos(i = 0)
    b = @md.begin_offset(i)
    b == nil ? nil : b + @offset_shift

  -> end_pos(i = 0)
    e = @md.end_offset(i)
    e == nil ? nil : e + @offset_shift

  -> pre_match
    b = begin_pos(0)
    RbString.new(b == nil ? "" : @string.slice(0, b))

  -> post_match
    e = end_pos(0)
    RbString.new(e == nil || e >= @string.size ? "" : @string.slice(e, @string.size - e))

  -> to_a
    out = [get_group(0)]
    captures().each ->(c) out.push(c)
    out

  -> to_s
    v = @md[0]
    v == nil ? "" : v

  -> inspect
    "#<MatchData " + to_s().inspect + ">"

# ---- Ruby Hash (order-preserving, supporting arbitrary Ruby keys + default value/proc) ----

+ RbHash
  rw :entries, :default_val, :default_proc

  -> new
    @entries = []   # [[k, v], ...]
    @default_val = nil
    @default_proc = nil

  -> size
    @entries.size

  -> find_idx(k)
    i = 0
    while i < @entries.size
      return i if rb_eql?(@entries[i][0], k)
      i += 1
    -1

  -> get(k)
    idx = find_idx(k)
    return @entries[idx][1] if idx >= 0
    @default_val

  -> has_key?(k)
    find_idx(k) >= 0

  -> set(k, v)
    idx = find_idx(k)
    if idx >= 0
      @entries[idx][1] = v
    else
      @entries.push([k, v])
    v

  -> delete(k)
    idx = find_idx(k)
    return nil if idx < 0
    v = @entries[idx][1]
    @entries.delete_at(idx)
    v

  -> keys
    out = []
    @entries.each ->(p) out.push(p[0])
    out

  -> values
    out = []
    @entries.each ->(p) out.push(p[1])
    out

  -> dup
    h = RbHash.new
    h.default_val = @default_val
    h.default_proc = @default_proc
    @entries.each ->(p) h.entries.push([p[0], p[1]])
    h

  -> ==(o)
    return false if !o.is_a?(RbHash) || @entries.size != o.entries.size
    i = 0
    while i < @entries.size
      idx = o.find_idx(@entries[i][0])
      return false if idx < 0 || !rb_eq?(@entries[i][1], o.entries[idx][1])
      i += 1
    true

# ---- Ruby Objects, Classes, Modules, Methods, Procs, Exceptions ----

+ RbMethod
  ro :name, :params, :body, :def_env, :owner, :native_fn
  rw :bytecode, :bc_tried

  -> new(@name, @params, @body, @def_env, @owner = nil, @native_fn = nil)
    @bytecode = nil
    @bc_tried = false

+ RbProc
  ro :params, :body, :env, :self_obj, :is_lambda, :native_fn, :def_frame_id

  -> new(@params, @body, @env, @self_obj, @is_lambda = false, @native_fn = nil, @def_frame_id = 0)

+ RbModule
  rw :name, :methods, :constants, :cvars, :ivars, :prepends, :includes, :singleton_cls

  -> new(@name)
    @methods = {}
    @constants = {}
    @cvars = {}
    @ivars = {}
    @prepends = []
    @includes = []
    @singleton_cls = nil

  -> ancestors
    out = []
    @prepends.each ->(m) m.ancestors().each ->(a) out.push(a) if !out.include?(a)
    out.push(self)
    @includes.each ->(m) m.ancestors().each ->(a) out.push(a) if !out.include?(a)
    out

  -> lookup_method(nm)
    anc = ancestors()
    i = 0
    while i < anc.size
      m = anc[i].methods[nm]
      return m if m != nil
      i += 1
    nil

  -> to_s
    @name

  -> inspect
    @name

+ RbClass < RbModule
  rw :superclass, :struct_members, :is_data_class

  -> new(name, @superclass = nil)
    super(name)
    @struct_members = nil
    @is_data_class = false

  -> ancestors
    out = []
    @prepends.each ->(m) m.ancestors().each ->(a) out.push(a) if !out.include?(a)
    out.push(self)
    @includes.each ->(m) m.ancestors().each ->(a) out.push(a) if !out.include?(a)
    if @superclass != nil
      @superclass.ancestors().each ->(a) out.push(a) if !out.include?(a)
    out

  -> subclass_of?(other)
    ancestors().include?(other)

+ RbObject
  rw :klass, :ivars, :singleton_cls, :frozen

  -> new(@klass)
    @ivars = {}
    @singleton_cls = nil
    @frozen = false

  -> to_s
    "#<" + @klass.name + ">"

  -> inspect
    if @ivars.size == 0
      return "#<" + @klass.name + ">"
    parts = []
    @ivars.each ->(k, v) parts.push(k + "=" + rb_inspect(v))
    "#<" + @klass.name + " " + parts.join(", ") + ">"

+ RbException < RbObject
  rw :exc_class, :message, :backtrace

  -> new(@exc_class, @message = "", klass = nil)
    super(klass == nil ? RbClass.new(@exc_class) : klass)
    @backtrace = []

  -> to_s
    @message.size > 0 ? @message : @exc_class

  -> inspect
    "#<" + @exc_class + ": " + @message + ">"

+ RbEnumerator
  rw :items, :idx

  -> new(@items)
    @idx = 0

# ---- Lexical Scope Environment ----

+ RbEnv
  rw :vars, :parent, :self_obj, :block, :frame_id, :cref

  -> new(@parent = nil, @self_obj = nil, @block = nil, @frame_id = 0, @cref = nil)
    @vars = {}

  -> has?(nm)
    return true if @vars.has_key?(nm)
    @parent != nil && @parent.has?(nm)

  -> get(nm)
    return @vars[nm] if @vars.has_key?(nm)
    return @parent.get(nm) if @parent != nil
    nil

  -> set(nm, val)
    # Assign to enclosing block variable if it already exists there
    e = self
    while e != nil
      if e.vars.has_key?(nm)
        e.vars[nm] = val
        return val
      e = e.parent
    @vars[nm] = val
    val

# ---- Comparison, Equality & Formatting Helpers ----

-> rb_truthy?(v)
  v != nil && v != false

-> rb_eql?(a, b)
  return true if a == b
  return a.data == b.data if a.is_a?(RbString) && b.is_a?(RbString)
  return a.name == b.name if a.is_a?(RbSym) && b.is_a?(RbSym)
  return a == b if a.is_a?(RbRational) && b.is_a?(RbRational)
  return a == b if a.is_a?(RbComplex) && b.is_a?(RbComplex)
  return a == b if a.is_a?(RbRange) && b.is_a?(RbRange)
  return a == b if a.is_a?(RbHash) && b.is_a?(RbHash)
  false

-> rb_eq?(a, b)
  return true if rb_eql?(a, b)
  if a.is_a?(Array) && b.is_a?(Array)
    return false if a.size != b.size
    i = 0
    while i < a.size
      return false if !rb_eq?(a[i], b[i])
      i += 1
    return true
  if (a.is_a?(Integer) || a.is_a?(Float) || a.is_a?(RbRational)) &&
     (b.is_a?(Integer) || b.is_a?(Float) || b.is_a?(RbRational))
    return rb_num_eq?(a, b)
  if a.is_a?(RbComplex) || b.is_a?(RbComplex)
    ca = a.is_a?(RbComplex) ? a : RbComplex.new(a, 0)
    cb = b.is_a?(RbComplex) ? b : RbComplex.new(b, 0)
    return rb_eq?(ca.real, cb.real) && rb_eq?(ca.imag, cb.imag)
  false

-> rb_num_eq?(a, b)
  return a == b if a.is_a?(Integer) && b.is_a?(Integer)
  if a.is_a?(RbRational) && b.is_a?(RbRational)
    return a.num == b.num && a.den == b.den
  if a.is_a?(RbRational) && b.is_a?(Integer)
    return a.den == 1 && a.num == b
  if a.is_a?(Integer) && b.is_a?(RbRational)
    return b.den == 1 && b.num == a
  rb_to_f(a) == rb_to_f(b)

-> rb_to_f(v)
  return v if v.is_a?(Float)
  return v.to_f if v.is_a?(Integer) || v.is_a?(RbRational)
  ~0.0

-> rb_cmp(a, b)
  if a.is_a?(Integer) && b.is_a?(Integer)
    return a < b ? -1 : (a > b ? 1 : 0)
  if (a.is_a?(Integer) || a.is_a?(Float) || a.is_a?(RbRational)) &&
     (b.is_a?(Integer) || b.is_a?(Float) || b.is_a?(RbRational))
    fa = rb_to_f(a)
    fb = rb_to_f(b)
    return fa < fb ? -1 : (fa > fb ? 1 : 0)
  if a.is_a?(RbString) && b.is_a?(RbString)
    return a.data < b.data ? -1 : (a.data > b.data ? 1 : 0)
  if a.is_a?(RbSym) && b.is_a?(RbSym)
    return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
  if a.is_a?(Array) && b.is_a?(Array)
    n = a.size < b.size ? a.size : b.size
    i = 0
    while i < n
      c = rb_cmp(a[i], b[i])
      return c if c != 0
      i += 1
    return a.size < b.size ? -1 : (a.size > b.size ? 1 : 0)
  nil

# Ruby floor division (rounds toward -infinity, NOT toward zero!)
-> rb_int_div(a, b)
  raise RbSignal.new(:raise, nil, 0, RbException.new("ZeroDivisionError", "divided by 0")) if b == 0
  q = a / b
  r = a % b
  if r != 0 && ((r < 0) != (b < 0))
    q = q - 1
  q

# Ruby modulo (result has same sign as divisor b!)
-> rb_int_mod(a, b)
  raise RbSignal.new(:raise, nil, 0, RbException.new("ZeroDivisionError", "divided by 0")) if b == 0
  r = a % b
  if r != 0 && ((r < 0) != (b < 0))
    r = r + b
  r

-> rb_num_add(a, b)
  return a + b if a.is_a?(Integer) && b.is_a?(Integer)
  if a.is_a?(RbComplex) || b.is_a?(RbComplex)
    ca = a.is_a?(RbComplex) ? a : RbComplex.new(a, 0)
    cb = b.is_a?(RbComplex) ? b : RbComplex.new(b, 0)
    return RbComplex.new(rb_num_add(ca.real, cb.real), rb_num_add(ca.imag, cb.imag))
  if a.is_a?(RbRational) || b.is_a?(RbRational)
    return rb_to_f(a) + rb_to_f(b) if a.is_a?(Float) || b.is_a?(Float)
    ra = a.is_a?(RbRational) ? a : RbRational.new(a, 1)
    rb = b.is_a?(RbRational) ? b : RbRational.new(b, 1)
    return RbRational.new(ra.num * rb.den + rb.num * ra.den, ra.den * rb.den)
  rb_to_f(a) + rb_to_f(b)

-> rb_num_sub(a, b)
  return a - b if a.is_a?(Integer) && b.is_a?(Integer)
  if a.is_a?(RbComplex) || b.is_a?(RbComplex)
    ca = a.is_a?(RbComplex) ? a : RbComplex.new(a, 0)
    cb = b.is_a?(RbComplex) ? b : RbComplex.new(b, 0)
    return RbComplex.new(rb_num_sub(ca.real, cb.real), rb_num_sub(ca.imag, cb.imag))
  if a.is_a?(RbRational) || b.is_a?(RbRational)
    return rb_to_f(a) - rb_to_f(b) if a.is_a?(Float) || b.is_a?(Float)
    ra = a.is_a?(RbRational) ? a : RbRational.new(a, 1)
    rb = b.is_a?(RbRational) ? b : RbRational.new(b, 1)
    return RbRational.new(ra.num * rb.den - rb.num * ra.den, ra.den * rb.den)
  rb_to_f(a) - rb_to_f(b)

-> rb_num_mul(a, b)
  return a * b if a.is_a?(Integer) && b.is_a?(Integer)
  if a.is_a?(RbComplex) || b.is_a?(RbComplex)
    ca = a.is_a?(RbComplex) ? a : RbComplex.new(a, 0)
    cb = b.is_a?(RbComplex) ? b : RbComplex.new(b, 0)
    # (a+bi)(c+di) = (ac - bd) + (ad + bc)i
    return RbComplex.new(rb_num_sub(rb_num_mul(ca.real, cb.real), rb_num_mul(ca.imag, cb.imag)),
                         rb_num_add(rb_num_mul(ca.real, cb.imag), rb_num_mul(ca.imag, cb.real)))
  if a.is_a?(RbRational) || b.is_a?(RbRational)
    return rb_to_f(a) * rb_to_f(b) if a.is_a?(Float) || b.is_a?(Float)
    ra = a.is_a?(RbRational) ? a : RbRational.new(a, 1)
    rb = b.is_a?(RbRational) ? b : RbRational.new(b, 1)
    return RbRational.new(ra.num * rb.num, ra.den * rb.den)
  rb_to_f(a) * rb_to_f(b)

-> rb_num_div(a, b)
  return rb_int_div(a, b) if a.is_a?(Integer) && b.is_a?(Integer)
  if a.is_a?(RbComplex) || b.is_a?(RbComplex)
    ca = a.is_a?(RbComplex) ? a : RbComplex.new(a, 0)
    cb = b.is_a?(RbComplex) ? b : RbComplex.new(b, 0)
    denom = rb_num_add(rb_num_mul(cb.real, cb.real), rb_num_mul(cb.imag, cb.imag))
    re = rb_num_div(rb_num_add(rb_num_mul(ca.real, cb.real), rb_num_mul(ca.imag, cb.imag)), denom)
    im = rb_num_div(rb_num_sub(rb_num_mul(ca.imag, cb.real), rb_num_mul(ca.real, cb.imag)), denom)
    return RbComplex.new(re, im)
  if a.is_a?(RbRational) || b.is_a?(RbRational)
    return rb_to_f(a) / rb_to_f(b) if a.is_a?(Float) || b.is_a?(Float)
    ra = a.is_a?(RbRational) ? a : RbRational.new(a, 1)
    rb = b.is_a?(RbRational) ? b : RbRational.new(b, 1)
    return RbRational.new(ra.num * rb.den, ra.den * rb.num)
  rb_to_f(a) / rb_to_f(b)

-> rb_num_pow(a, b)
  if a.is_a?(Integer) && b.is_a?(Integer)
    if b >= 0
      res = 1
      base = a
      exp = b
      while exp > 0
        res = res * base if (exp & 1) == 1
        base = base * base
        exp = exp >> 1
      return res
    return RbRational.new(1, rb_num_pow(a, -b))
  if a.is_a?(RbRational) && b.is_a?(Integer)
    return b >= 0 ? RbRational.new(rb_num_pow(a.num, b), rb_num_pow(a.den, b)) : RbRational.new(rb_num_pow(a.den, -b), rb_num_pow(a.num, -b))
  Math.pow(rb_to_f(a), rb_to_f(b))

-> rb_float_to_s(f)
  s = f.to_s
  if s.index(".") == nil && s.index("e") == nil && s.index("E") == nil && s != "Infinity" && s != "-Infinity" && s != "NaN"
    return s + ".0"
  s

-> rb_to_s(v)
  return "" if v == nil
  return "true" if v == true
  return "false" if v == false
  return rb_float_to_s(v) if v.is_a?(Float)
  return v.data if v.is_a?(RbString)
  return v.name if v.is_a?(RbSym)
  return "main" if v.is_a?(RbObject) && v.ivars["__is_main__"] == true
  return rb_inspect(v) if v.is_a?(Array) || v.is_a?(RbHash)
  v.to_s

-> rb_inspect(v)
  return "nil" if v == nil
  return "true" if v == true
  return "false" if v == false
  return rb_float_to_s(v) if v.is_a?(Float)
  return "main" if v.is_a?(RbObject) && v.ivars["__is_main__"] == true
  return v.inspect if v.is_a?(RbString) || v.is_a?(RbSym) || v.is_a?(RbRational) || v.is_a?(RbComplex) || v.is_a?(RbRange) || v.is_a?(RbRegexp) || v.is_a?(RbMatchData) || v.is_a?(RbEncoding) || v.is_a?(RbModule) || v.is_a?(RbObject)
  if v.is_a?(Array)
    parts = []
    v.each ->(x) parts.push(rb_inspect(x))
    return '[' + parts.join(", ") + ']'
  if v.is_a?(RbHash)
    parts = []
    v.entries.each ->(p)
      if p[0].is_a?(RbSym)
        parts.push(p[0].name + ": " + rb_inspect(p[1]))
      else
        parts.push(rb_inspect(p[0]) + " => " + rb_inspect(p[1]))
    return "{" + parts.join(", ") + "}"
  v.to_s

# Zero-copy conversion between Ruby runtime values and native Tungsten values
-> rb_to_tungsten(v)
  return nil if v == nil
  return v.data if v.is_a?(RbString)
  return v.name if v.is_a?(RbSym)
  if v.is_a?(Array)
    out = []
    v.each ->(x) out.push(rb_to_tungsten(x))
    return out
  if v.is_a?(RbHash)
    h = {}
    v.entries.each ->(p) h[rb_to_tungsten(p[0])] = rb_to_tungsten(p[1])
    return h
  v

-> rb_from_tungsten(v)
  return nil if v == nil
  return RbString.new(v) if v.is_a?(String)
  if v.is_a?(Array)
    out = []
    v.each ->(x) out.push(rb_from_tungsten(x))
    return out
  if v.is_a?(Hash)
    h = RbHash.new
    v.each ->(k, val) h.set(rb_from_tungsten(k), rb_from_tungsten(val))
    return h
  v

# ---- Ruby 3.4 / 4.0 Virtual Machine ----

+ RbVM
  rw :globals, :constants, :stdout, :next_frame_id, :tungsten_fns, :max_steps, :steps, :method_epoch, :reg_stack
  ro :c_basic_object, :c_object, :c_module, :c_class, :c_kernel, :c_comparable, :c_enumerable
  ro :c_true_class, :c_false_class, :c_nil_class
  ro :c_numeric, :c_integer, :c_float, :c_rational, :c_complex, :c_string, :c_symbol
  ro :c_array, :c_hash, :c_range, :c_regexp, :c_match_data, :c_proc, :c_exception
  ro :c_standard_error, :c_struct, :c_data, :c_encoding, :c_enumerator, :c_math, :c_json, :c_tungsten
  ro :main_obj, :top_env

  -> new
    @globals = {}
    @constants = {}
    @stdout = []
    @next_frame_id = 1
    @tungsten_fns = {}
    @last_match = nil
    @last_exc = nil
    @steps = 0
    @max_steps = 0
    @method_epoch = 1
    @reg_stack = Array.new(16384, nil)
    init_core_classes()
    @main_obj = RbObject.new(@c_object)
    @main_obj.ivars["__is_main__"] = true
    @top_env = RbEnv.new(nil, @main_obj, nil, 0, [@c_object])

  -> init_core_classes
    @c_basic_object = RbClass.new("BasicObject", nil)
    @c_object = RbClass.new("Object", @c_basic_object)
    @c_kernel = RbModule.new("Kernel")
    @c_object.includes.push(@c_kernel)
    @c_module = RbClass.new("Module", @c_object)
    @c_class = RbClass.new("Class", @c_module)
    @c_true_class = RbClass.new("TrueClass", @c_object)
    @c_false_class = RbClass.new("FalseClass", @c_object)
    @c_nil_class = RbClass.new("NilClass", @c_object)
    @c_comparable = RbModule.new("Comparable")
    @c_enumerable = RbModule.new("Enumerable")
    @c_numeric = RbClass.new("Numeric", @c_object)
    @c_numeric.includes.push(@c_comparable)
    @c_integer = RbClass.new("Integer", @c_numeric)
    @c_float = RbClass.new("Float", @c_numeric)
    @c_rational = RbClass.new("Rational", @c_numeric)
    @c_complex = RbClass.new("Complex", @c_numeric)
    @c_string = RbClass.new("String", @c_object)
    @c_string.includes.push(@c_comparable)
    @c_symbol = RbClass.new("Symbol", @c_object)
    @c_array = RbClass.new("Array", @c_object)
    @c_array.includes.push(@c_enumerable)
    @c_hash = RbClass.new("Hash", @c_object)
    @c_hash.includes.push(@c_enumerable)
    @c_range = RbClass.new("Range", @c_object)
    @c_range.includes.push(@c_enumerable)
    @c_regexp = RbClass.new("Regexp", @c_object)
    @c_match_data = RbClass.new("MatchData", @c_object)
    @c_proc = RbClass.new("Proc", @c_object)
    @c_struct = RbClass.new("Struct", @c_object)
    @c_data = RbClass.new("Data", @c_object)
    @c_encoding = RbClass.new("Encoding", @c_object)
    @c_encoding.constants["UTF_8"] = RB_ENC_UTF8
    @c_encoding.constants["US_ASCII"] = RB_ENC_ASCII
    @c_encoding.constants["ASCII_8BIT"] = RB_ENC_BINARY
    @c_encoding.constants["BINARY"] = RB_ENC_BINARY
    @c_enumerator = RbClass.new("Enumerator", @c_object)
    @c_enumerator.includes.push(@c_enumerable)
    @c_math = RbModule.new("Math")
    @c_math.constants["PI"] = ~3.141592653589793
    @c_math.constants["E"] = ~2.718281828459045
    @c_json = RbModule.new("JSON")
    @c_tungsten = RbModule.new("Tungsten")

    @c_exception = RbClass.new("Exception", @c_object)
    @c_standard_error = RbClass.new("StandardError", @c_exception)

    [
      @c_basic_object, @c_object, @c_kernel, @c_module, @c_class, @c_comparable, @c_enumerable,
      @c_true_class, @c_false_class, @c_nil_class,
      @c_numeric, @c_integer, @c_float, @c_rational, @c_complex, @c_string, @c_symbol,
      @c_array, @c_hash, @c_range, @c_regexp, @c_match_data, @c_proc, @c_struct, @c_data,
      @c_encoding, @c_enumerator, @c_math, @c_json, @c_tungsten, @c_exception, @c_standard_error
    ].each ->(c)
      @c_object.constants[c.name] = c
      @constants[c.name] = c

    ["RuntimeError", "TypeError", "ArgumentError", "NameError", "NoMethodError",
     "ZeroDivisionError", "IndexError", "KeyError", "RangeError", "FrozenError",
     "StopIteration", "NoMatchingPatternError", "RegexpError", "LocalJumpError", "UncaughtThrowError"].each ->(enm)
      ec = RbClass.new(enm, @c_standard_error)
      @c_object.constants[enm] = ec
      @constants[enm] = ec

    @c_object.constants["RUBY_VERSION"] = RbString.new("4.0.9", RB_ENC_UTF8, true)
    @c_object.constants["RUBY_ENGINE"] = RbString.new("tungsten-ruby", RB_ENC_UTF8, true)
    @c_object.constants["NIL"] = nil
    @c_object.constants["TRUE"] = true
    @c_object.constants["FALSE"] = false

  -> class_of(v)
    return @c_nil_class if v == nil
    return @c_true_class if v == true
    return @c_false_class if v == false
    return @c_integer if v.is_a?(Integer)
    return @c_float if v.is_a?(Float)
    return @c_rational if v.is_a?(RbRational)
    return @c_complex if v.is_a?(RbComplex)
    return @c_string if v.is_a?(RbString)
    return @c_symbol if v.is_a?(RbSym)
    return @c_array if v.is_a?(Array)
    return @c_hash if v.is_a?(RbHash)
    return @c_range if v.is_a?(RbRange)
    return @c_regexp if v.is_a?(RbRegexp)
    return @c_match_data if v.is_a?(RbMatchData)
    return @c_proc if v.is_a?(RbProc)
    return @c_encoding if v.is_a?(RbEncoding)
    return @c_enumerator if v.is_a?(RbEnumerator)
    return @c_class if v.is_a?(RbClass)
    return @c_module if v.is_a?(RbModule)
    return v.klass if v.is_a?(RbObject)
    @c_object

  -> singleton_class_of(obj)
    if obj.is_a?(RbModule) || obj.is_a?(RbObject)
      if obj.singleton_cls == nil
        sup = obj.is_a?(RbClass) ? (obj.superclass != nil ? singleton_class_of(obj.superclass) : @c_class) : class_of(obj)
        obj.singleton_cls = RbClass.new("#<Class:" + obj.to_s + ">", sup)
      return obj.singleton_cls
    raise_exc("TypeError", "can't define singleton on " + rb_inspect(obj))

  -> raise_exc(cls_name, msg)
    cls = @constants[cls_name]
    cls = @c_standard_error if cls == nil
    exc = RbException.new(cls_name, msg, cls)
    @last_exc = exc
    raise RbSignal.new(:raise, nil, 0, exc)

  # Register a Tungsten closure to be callable from Ruby via `Tungsten.call(:name, *args)` or `Tungsten.<name>(*args)`!
  -> register(name, fn)
    @tungsten_fns[name.to_s] = fn
    self

  -> eval_source(src)
    ast = rb_parse(src)
    eval_node(ast, @top_env)

  -> eval_stmts(stmts, env)
    res = nil
    i = 0
    while i < stmts.size
      res = eval_node(stmts[i], env)
      i += 1
    res

  -> resolve_const(nm, env)
    if env.cref != nil
      ci = env.cref.size - 1
      while ci >= 0
        m = env.cref[ci]
        return m.constants[nm] if m.constants.has_key?(nm)
        ci -= 1
    # Check ancestor chain of current module/class
    if env.cref != nil && env.cref.size > 0
      anc = env.cref[env.cref.size - 1].ancestors()
      anc.each ->(a)
        return a.constants[nm] if a.constants.has_key?(nm)
    return @constants[nm] if @constants.has_key?(nm)
    raise_exc("NameError", "uninitialized constant " + nm)

  -> parse_rational_lit(raw, extra)
    is_f = extra[0]
    base = extra[1]
    if !is_f
      clean = base == 10 ? raw : raw.slice(2, raw.size - 2)
      return RbRational.new(rb_parse_int(clean, base), 1)
    # Handle exact decimal & scientific notation (e.g. `1.0000000000000000001r`, `1e-3r`, `1.2e3r`)
    s = raw.downcase
    exp_val = 0
    ep = s.index("e")
    mant = s
    if ep != nil
      mant = s.slice(0, ep)
      exp_val = rb_parse_int(s.slice(ep + 1, s.size - ep - 1), 10)
    dot = mant.index(".")
    frac_len = 0
    num = 0
    if dot != nil
      frac_len = mant.size - dot - 1
      num = rb_parse_int(mant.gsub(".", ""), 10)
    else
      num = rb_parse_int(mant, 10)
    shift = exp_val - frac_len
    if shift >= 0
      return RbRational.new(num * rb_num_pow(10, shift), 1)
    RbRational.new(num, rb_num_pow(10, -shift))

  -> eval_node(n, env)
    return nil if n == nil
    if @max_steps > 0
      @steps += 1
      raise_exc("RuntimeError", "step limit exceeded") if @steps > @max_steps
    case n.kind
    when :program
      eval_stmts(n.a, env)
    when :int
      n.a
    when :float
      n.a
    when :rational
      parse_rational_lit(n.a, n.b)
    when :complex
      is_f = n.b[0]
      is_r = n.b[1]
      base = n.b[2]
      im = is_r ? parse_rational_lit(n.a, [is_f, base]) : (is_f ? n.a.to_f : rb_parse_int(base == 10 ? n.a : n.a.slice(2, n.a.size - 2), base))
      RbComplex.new(0, im)
    when :string
      RbString.new(n.a, RB_ENC_UTF8, n.b == true)
    when :string_interp
      sb = StringBuffer()
      n.a.each ->(p) sb << rb_to_s(eval_node(p, env))
      RbString.new(sb.to_s, RB_ENC_UTF8, n.b == true)
    when :symbol
      RbSym.new(n.a)
    when :regex
      RbRegexp.new(n.a, n.b == nil ? "" : n.b)
    when :dregex
      pat_s = rb_to_s(eval_node(n.a, env))
      RbRegexp.new(pat_s, n.b == nil ? "" : n.b)
    when :splat
      sv = eval_node(n.a, env)
      return sv if sv.is_a?(Array)
      return [] if sv == nil
      return sv.to_a if sv.is_a?(RbRange)
      [sv]
    when :bool
      n.a
    when :nil
      nil
    when :self
      env.self_obj
    when :var
      return env.get(n.a) if env.has?(n.a)
      # Implicit zero-arg method call on self!
      call_method(env.self_obj, n.a, [], {}, nil, env)
    when :ivar
      o = env.self_obj
      (o.is_a?(RbObject) || o.is_a?(RbModule)) ? o.ivars[n.a] : nil
    when :cvar
      cur_c = env.cref != nil && env.cref.size > 0 ? env.cref[env.cref.size - 1] : class_of(env.self_obj)
      anc = cur_c.ancestors()
      i = 0
      while i < anc.size
        return anc[i].cvars[n.a] if anc[i].cvars.has_key?(n.a)
        i += 1
      nil
    when :gvar
      return @last_match if n.a == "$~"
      return (@last_match == nil ? nil : @last_match.get_group(0)) if n.a == "$&"
      return (@last_match == nil ? nil : @last_match.pre_match()) if n.a == "$`"
      return (@last_match == nil ? nil : @last_match.post_match()) if n.a == "$'"
      return @last_exc if n.a == "$!"
      if n.a.size >= 2 && n.a.byte_at(1) >= 49 && n.a.byte_at(1) <= 57
        gi = n.a.slice(1, n.a.size - 1).to_i
        return @last_match == nil ? nil : @last_match.get_group(gi)
      @globals[n.a]
    when :const_ref
      resolve_const(n.a, env)
    when :const_path
      if n.a == nil
        return @constants[n.b] if @constants.has_key?(n.b)
        raise_exc("NameError", "uninitialized constant ::" + n.b)
      base = eval_node(n.a, env)
      if base.is_a?(RbModule) && base.constants.has_key?(n.b)
        return base.constants[n.b]
      raise_exc("NameError", "uninitialized constant " + rb_to_s(base) + "::" + n.b)
    when :array
      out = []
      n.a.each ->(el)
        if el.is_a?(RbNode) && el.kind == :splat
          sv = eval_node(el.a, env)
          if sv.is_a?(Array)
            sv.each ->(x) out.push(x)
          elsif sv.is_a?(RbRange)
            sv.to_a.each ->(x) out.push(x)
          elsif sv != nil
            out.push(sv)
        else
          out.push(eval_node(el, env))
      out
    when :hash
      h = RbHash.new
      n.a.each ->(p)
        if p[0] == nil
          sv = eval_node(p[1], env)
          if sv.is_a?(RbHash)
            sv.entries.each ->(e) h.set(e[0], e[1])
        else
          h.set(eval_node(p[0], env), eval_node(p[1], env))
      h
    when :range
      RbRange.new(eval_node(n.a, env), eval_node(n.b, env), n.c == true)
    when :assign
      val = eval_node(n.b, env)
      if n.a.kind == :splat
        arr = n.b.kind == :splat ? val : (val.is_a?(Array) ? val : [val])
        assign_target(n.a.a, arr, env)
        return val
      assign_target(n.a, val, env)
    when :compound_assign
      op = n.a
      if op == "||="
        cur_v = read_assign_target(n.b, env)
        return cur_v if rb_truthy?(cur_v)
        return assign_target(n.b, eval_node(n.c, env), env)
      if op == "&&="
        cur_v = read_assign_target(n.b, env)
        return cur_v if !rb_truthy?(cur_v)
        return assign_target(n.b, eval_node(n.c, env), env)
      cur_v = read_assign_target(n.b, env)
      rhs = eval_node(n.c, env)
      bop = op.slice(0, op.size - 1)
      res = eval_binop(bop, cur_v, rhs, env)
      assign_target(n.b, res, env)
    when :multi_assign
      rhs = eval_node(n.b, env)
      vals = rhs.is_a?(Array) ? rhs : [rhs]
      lhs = n.a
      splat_i = -1
      si = 0
      while si < lhs.size
        splat_i = si if lhs[si].kind == :splat
        si += 1
      if splat_i < 0
        i = 0
        while i < lhs.size
          assign_target(lhs[i], i < vals.size ? vals[i] : nil, env)
          i += 1
      else
        post_n = lhs.size - 1 - splat_i
        i = 0
        while i < splat_i
          assign_target(lhs[i], i < vals.size ? vals[i] : nil, env)
          i += 1
        mid_end = vals.size - post_n
        mid_end = splat_i if mid_end < splat_i
        mid = []
        k = splat_i
        while k < mid_end
          mid.push(vals[k])
          k += 1
        assign_target(lhs[splat_i].a, mid, env)
        j = 0
        while j < post_n
          vi = mid_end + j
          assign_target(lhs[splat_i + 1 + j], vi < vals.size ? vals[vi] : nil, env)
          j += 1
      rhs
    when :and
      l = eval_node(n.a, env)
      rb_truthy?(l) ? eval_node(n.b, env) : l
    when :or
      l = eval_node(n.a, env)
      rb_truthy?(l) ? l : eval_node(n.b, env)
    when :not
      !rb_truthy?(eval_node(n.a, env))
    when :unary_op
      v = eval_node(n.b, env)
      if n.a == "!"
        return !rb_truthy?(v)
      if n.a == "-@"
        return -v if v.is_a?(Integer) || v.is_a?(Float)
        return RbRational.new(-v.num, v.den) if v.is_a?(RbRational)
        return RbComplex.new(rb_num_sub(0, v.real), rb_num_sub(0, v.imag)) if v.is_a?(RbComplex)
      if n.a == "+@"
        return v if v.is_a?(Integer) || v.is_a?(Float) || v.is_a?(RbRational) || v.is_a?(RbComplex)
      if n.a == "~" && v.is_a?(Integer)
        return -1 - v
      call_method(v, n.a, [], {}, nil, env)
    when :binary_op
      l = eval_node(n.b, env)
      r = eval_node(n.c, env)
      # Special Ruby rule: `/literal_with_named_captures/ =~ str` binds named captures as locals!
      if n.a == "=~" && n.b.kind == :regex && l.is_a?(RbRegexp) && r.is_a?(RbString)
        md = l.match_str(r.data)
        @last_match = md
        if md != nil
          l.named_groups.each ->(gnm, gi) env.set(gnm, md.get_group(gi))
          return md.begin_pos(0)
        l.named_groups.each ->(gnm, gi) env.set(gnm, nil)
        return nil
      eval_binop(n.a, l, r, env)
    when :if
      if rb_truthy?(eval_node(n.a, env))
        eval_stmts(n.b, env)
      elsif n.c != nil
        eval_stmts(n.c, env)
      else
        nil
    when :case
      subj = n.a != nil ? eval_node(n.a, env) : nil
      i = 0
      while i < n.b.size
        w = n.b[i]
        matched = false
        j = 0
        while j < w[0].size
          wv = eval_node(w[0][j], env)
          if n.a == nil
            matched = rb_truthy?(wv)
          else
            matched = rb_truthy?(eval_case_eq(wv, subj, env))
          break if matched
          j += 1
        return eval_stmts(w[1], env) if matched
        i += 1
      n.c != nil ? eval_stmts(n.c, env) : nil
    when :case_in
      subj = eval_node(n.a, env)
      i = 0
      while i < n.b.size
        arm = n.b[i]
        binds = {}
        if match_pattern(arm[0], subj, env, binds)
          binds.each ->(k, v) env.set(k, v)
          ok_g = true
          if arm[1] != nil
            gv = rb_truthy?(eval_node(arm[1][1], env))
            ok_g = arm[1][0] == :if ? gv : !gv
          return eval_stmts(arm[2], env) if ok_g
        i += 1
      return eval_stmts(n.c, env) if n.c != nil
      raise_exc("NoMatchingPatternError", rb_inspect(subj))
    when :pat_test
      subj = eval_node(n.a, env)
      binds = {}
      ok = match_pattern(n.b, subj, env, binds)
      if ok
        binds.each ->(k, v) env.set(k, v)
        return n.c == true ? nil : true
      return false if n.c != true
      raise_exc("NoMatchingPatternError", rb_inspect(subj))
    when :while
      is_until = n.c == true
      while true
        c = rb_truthy?(eval_node(n.a, env))
        break if is_until ? c : !c
        begin
          eval_stmts(n.b, env)
        rescue sig
          if sig.is_a?(RbSignal)
            return sig.val if sig.kind == :break
            next if sig.kind == :next
            if sig.kind == :redo
              # redo skips condition check and re-runs body
              while true
                begin
                  eval_stmts(n.b, env)
                  break
                rescue sig2
                  if sig2.is_a?(RbSignal) && sig2.kind == :redo
                    next
                  raise sig2
              next
          raise sig
      nil
    when :for
      coll = eval_node(n.b, env)
      items = coll.is_a?(Array) ? coll : (coll.is_a?(RbRange) ? coll.to_a : [])
      items.each ->(el)
        if n.a.size == 1
          env.set(n.a[0], el)
        else
          arr = el.is_a?(Array) ? el : [el]
          k = 0
          while k < n.a.size
            env.set(n.a[k], k < arr.size ? arr[k] : nil)
            k += 1
        eval_stmts(n.c, env)
      coll
    when :begin
      # Pre-declare rescue => var locals in enclosing scope (Ruby semantics: nil if rescue not entered)
      n.b.each ->(rc)
        env.vars[rc[1]] = nil if rc[1] != nil && !env.has?(rc[1])
      res = nil
      while true
        do_retry = false
        rescued = false
        prev_exc = @last_exc
        begin
          res = eval_stmts(n.a, env)
        rescue sig
          if sig.is_a?(RbSignal) && sig.kind == :raise
            exc = sig.exc
            @last_exc = exc
            ri = 0
            while ri < n.b.size
              rc = n.b[ri]
              klasses = rc[0]
              matches = klasses.size == 0 ? (exc.klass.subclass_of?(@c_standard_error) || exc.exc_class != "Exception") : false
              if !matches && klasses.size > 0
                klasses.each ->(kn)
                  kv = eval_node(kn, env)
                  if kv.is_a?(RbClass)
                    matches = true if exc.klass.subclass_of?(kv) || exc.exc_class == kv.name || (kv == @c_standard_error && exc.exc_class != "Exception") || kv == @c_exception
                  elsif kv != nil
                    matches = true if rb_truthy?(eval_case_eq(kv, exc, env))
              if matches
                rescued = true
                env.set(rc[1], exc) if rc[1] != nil
                begin
                  res = eval_stmts(rc[2], env)
                rescue rsig
                  @last_exc = prev_exc
                  if rsig.is_a?(RbSignal) && rsig.kind == :retry
                    do_retry = true
                  else
                    eval_stmts(n.d, env) if n.d != nil
                    raise rsig
                @last_exc = prev_exc
                break
              ri += 1
            if !rescued
              @last_exc = prev_exc
              eval_stmts(n.d, env) if n.d != nil
              raise sig
          else
            eval_stmts(n.d, env) if n.d != nil
            raise sig
        if do_retry
          next
        if !rescued && n.c != nil
          res = eval_stmts(n.c, env)
        eval_stmts(n.d, env) if n.d != nil
        break
      res
    when :return
      val = n.a != nil ? eval_node(n.a, env) : nil
      raise RbSignal.new(:return, val, env.frame_id)
    when :break
      val = n.a != nil ? eval_node(n.a, env) : nil
      raise RbSignal.new(:break, val, 0)
    when :next
      val = n.a != nil ? eval_node(n.a, env) : nil
      raise RbSignal.new(:next, val, 0)
    when :redo
      raise RbSignal.new(:redo, nil, 0)
    when :retry
      raise RbSignal.new(:retry, nil, 0)
    when :lambda
      RbProc.new(n.a, n.b, env, env.self_obj, true, nil, env.frame_id)
    when :yield
      raise_exc("LocalJumpError", "no block given (yield)") if env.block == nil
      yargs = eval_pos_args(n.a, env)
      ykw = eval_kw_args(n.b, env)
      call_proc(env.block, yargs, ykw)
    when :defined
      eval_defined(n.a, env)
    when :alias
      cur_c = env.cref != nil && env.cref.size > 0 ? env.cref[env.cref.size - 1] : @c_object
      m = cur_c.lookup_method(n.b)
      raise_exc("NameError", "undefined method `" + n.b + "'") if m == nil
      cur_c.methods[n.a] = m
      @method_epoch += 1
      nil
    when :undef
      cur_c = env.cref != nil && env.cref.size > 0 ? env.cref[env.cref.size - 1] : @c_object
      n.a.each ->(nm) cur_c.methods.delete(nm)
      @method_epoch += 1
      nil
    when :method_def
      target_cls = nil
      if n.d != nil
        ro = eval_node(n.d, env)
        target_cls = singleton_class_of(ro)
      elsif env.cref != nil && env.cref.size > 0
        target_cls = env.cref[env.cref.size - 1]
      else
        target_cls = @c_object
      target_cls.methods[n.a] = RbMethod.new(n.a, n.b, n.c, env, target_cls)
      @method_epoch += 1
      RbSym.new(n.a)
    when :class_def
      sup = n.b != nil ? eval_node(n.b, env) : @c_object
      parent_m = env.cref != nil && env.cref.size > 0 ? env.cref[env.cref.size - 1] : @c_object
      cls = nil
      if parent_m.constants.has_key?(n.a) && parent_m.constants[n.a].is_a?(RbClass)
        cls = parent_m.constants[n.a]
      else
        cls = RbClass.new(n.a, sup)
        parent_m.constants[n.a] = cls
        @constants[n.a] = cls if parent_m == @c_object
      nc = env.cref == nil ? [cls] : env.cref + [cls]
      cenv = RbEnv.new(nil, cls, nil, 0, nc)
      eval_stmts(n.c, cenv)
    when :singleton_class
      obj = eval_node(n.a, env)
      sc = singleton_class_of(obj)
      nc = env.cref == nil ? [sc] : env.cref + [sc]
      cenv = RbEnv.new(nil, sc, nil, 0, nc)
      eval_stmts(n.b, cenv)
    when :module_def
      parent_m = env.cref != nil && env.cref.size > 0 ? env.cref[env.cref.size - 1] : @c_object
      mod = nil
      if parent_m.constants.has_key?(n.a) && parent_m.constants[n.a].is_a?(RbModule)
        mod = parent_m.constants[n.a]
      else
        mod = RbModule.new(n.a)
        parent_m.constants[n.a] = mod
        @constants[n.a] = mod if parent_m == @c_object
      nc = env.cref == nil ? [mod] : env.cref + [mod]
      menv = RbEnv.new(nil, mod, nil, 0, nc)
      eval_stmts(n.b, menv)
    when :call, :safe_nav
      recv = n.a == nil ? env.self_obj : eval_node(n.a, env)
      return nil if n.kind == :safe_nav && recv == nil
      spec = n.c
      args = eval_pos_args(spec[0], env)
      kw = eval_kw_args(spec[1], env)
      blk = nil
      if spec[3] != nil
        bn = spec[3]
        blk = RbProc.new(bn.a, bn.b, env, env.self_obj, false, nil, env.frame_id)
      elsif spec[2] != nil
        bp = eval_node(spec[2], env)
        if bp.is_a?(RbProc)
          blk = bp
        elsif bp.is_a?(RbSym)
          snm = bp.name
          blk = RbProc.new([], nil, env, env.self_obj, true, ->(pargs, pkw) call_method(pargs[0], snm, pargs.size > 1 ? pargs.slice(1, pargs.size - 1) : [], pkw, nil, env), 0)
        elsif bp != nil
          blk = call_method(bp, "to_proc", [], {}, nil, env)
      call_method(recv, n.b, args, kw, blk, env)
    when :super
      # Resolve next method in ancestor chain past current owner
      cur_m = env.vars["__super_owner__"]
      cur_nm = env.vars["__super_name__"]
      args = n.a != nil ? eval_pos_args(n.a[0], env) : env.vars["__super_args__"]
      kw = n.a != nil ? eval_kw_args(n.a[1], env) : {}
      blk = n.b != nil ? RbProc.new(n.b.a, n.b.b, env, env.self_obj, false, nil, env.frame_id) : env.block
      anc = class_of(env.self_obj).ancestors()
      found_cur = false
      i = 0
      while i < anc.size
        if found_cur
          m = anc[i].methods[cur_nm]
          return invoke_rb_method(m, env.self_obj, args, kw, blk) if m != nil
        found_cur = true if anc[i] == cur_m
        i += 1
      raise_exc("NoMethodError", "super: no superclass method `" + cur_nm.to_s + "'")
    else
      nil

  -> eval_pos_args(arg_nodes, env)
    out = []
    arg_nodes.each ->(an)
      if an.is_a?(RbNode) && an.kind == :splat
        sv = eval_node(an.a, env)
        if sv.is_a?(Array)
          sv.each ->(x) out.push(x)
        elsif sv.is_a?(RbRange)
          sv.to_a.each ->(x) out.push(x)
        elsif sv != nil
          out.push(sv)
      elsif an.is_a?(RbNode) && an.kind == :arg_forward
        fa = env.vars["__fwd_args__"]
        fa.each ->(x) out.push(x) if fa != nil
      else
        out.push(eval_node(an, env))
    out

  -> eval_kw_args(kw_pairs, env)
    out = {}
    kw_pairs.each ->(kp)
      if kp[0] == nil
        hv = eval_node(kp[1], env)
        if hv.is_a?(RbHash)
          hv.entries.each ->(e) out[rb_to_s(e[0])] = e[1]
      elsif kp[0].is_a?(String)
        out[kp[0]] = eval_node(kp[1], env)
      else
        k = eval_node(kp[0], env)
        out[rb_to_s(k)] = eval_node(kp[1], env)
    out

  -> read_assign_target(t, env)
    return env.get(t.a) if t.kind == :var
    return eval_node(t, env)

  -> assign_target(t, val, env)
    case t.kind
    when :var
      env.set(t.a, val)
    when :ivar
      env.self_obj.ivars[t.a] = val if env.self_obj.is_a?(RbObject) || env.self_obj.is_a?(RbModule)
      val
    when :cvar
      cur_c = env.cref != nil && env.cref.size > 0 ? env.cref[env.cref.size - 1] : class_of(env.self_obj)
      cur_c.cvars[t.a] = val
    when :gvar
      @globals[t.a] = val
    when :const_ref
      parent_m = env.cref != nil && env.cref.size > 0 ? env.cref[env.cref.size - 1] : @c_object
      parent_m.constants[t.a] = val
      @constants[t.a] = val if parent_m == @c_object
      val
    when :const_path
      base = t.a == nil ? @c_object : eval_node(t.a, env)
      base.constants[t.b] = val if base.is_a?(RbModule)
      @constants[t.b] = val if t.a == nil
      val
    else
      val

  -> eval_defined(n, env)
    return RbString.new("nil") if n.kind == :nil
    return RbString.new("true") if n.kind == :bool && n.a == true
    return RbString.new("false") if n.kind == :bool && n.a == false
    return RbString.new("self") if n.kind == :self
    return RbString.new("local-variable") if n.kind == :var && env.has?(n.a)
    if n.kind == :ivar
      return (env.self_obj.is_a?(RbObject) && env.self_obj.ivars.has_key?(n.a)) ? RbString.new("instance-variable") : nil
    if n.kind == :gvar
      return @globals.has_key?(n.a) ? RbString.new("global-variable") : nil
    if n.kind == :const_ref
      return @constants.has_key?(n.a) ? RbString.new("constant") : nil
    RbString.new("expression")

  # Pattern matching (Ruby 3.0-4.0)
  -> match_pattern(pat, val, env, binds)
    case pat.kind
    when :var
      return true if pat.a == "_"
      binds[pat.a] = val
      true
    when :pat_pin
      pv = eval_node(pat.a, env)
      rb_truthy?(eval_case_eq(pv, val, env))
    when :pat_alt
      pat.a.each ->(alt)
        sub = {}
        if match_pattern(alt, val, env, sub)
          sub.each ->(k, v) binds[k] = v
          return true
      false
    when :pat_as
      return false if !match_pattern(pat.a, val, env, binds)
      binds[pat.b] = val
      true
    when :pat_array
      arr = val.is_a?(Array) ? val : nil
      return false if arr == nil
      pats = pat.a
      si = -1
      i = 0
      while i < pats.size
        si = i if pats[i].kind == :splat
        i += 1
      if si < 0
        return false if arr.size != pats.size
        i = 0
        while i < pats.size
          return false if !match_pattern(pats[i], arr[i], env, binds)
          i += 1
        return true
      post = pats.size - 1 - si
      return false if arr.size < si + post
      i = 0
      while i < si
        return false if !match_pattern(pats[i], arr[i], env, binds)
        i += 1
      mid_end = arr.size - post
      mid = []
      k = si
      while k < mid_end
        mid.push(arr[k])
        k += 1
      binds[pats[si].a] = mid if pats[si].a != "_"
      j = 0
      while j < post
        return false if !match_pattern(pats[si + 1 + j], arr[mid_end + j], env, binds)
        j += 1
      true
    when :pat_hash
      return false if !val.is_a?(RbHash)
      used = {}
      i = 0
      while i < pat.a.size
        kstr = pat.a[i][0]
        ksym = RbSym.new(kstr)
        return false if !val.has_key?(ksym)
        used[kstr] = true
        return false if !match_pattern(pat.a[i][1], val.get(ksym), env, binds)
        i += 1
      if pat.b == :nil
        return false if val.size != used.size
      elsif pat.b != nil && pat.b != "_"
        rest = RbHash.new
        val.entries.each ->(e)
          rest.set(e[0], e[1]) if !used.has_key?(rb_to_s(e[0]))
        binds[pat.b] = rest
      true
    else
      pv = eval_node(pat, env)
      rb_truthy?(eval_case_eq(pv, val, env))

  -> eval_case_eq(pat, val, env)
    if pat.is_a?(RbObject) && lookup_method_on(pat, "===") != nil
      return call_method(pat, "===", [val], {}, nil, env)
    return class_of(val).subclass_of?(pat) if pat.is_a?(RbClass)
    return class_of(val).ancestors().include?(pat) if pat.is_a?(RbModule)
    return pat.include?(val) if pat.is_a?(RbRange)
    if pat.is_a?(RbRegexp)
      md = pat.match_str(rb_to_s(val))
      @last_match = md
      return md != nil
    if pat.is_a?(RbProc)
      return rb_truthy?(call_proc(pat, [val], {}))
    rb_eq?(pat, val)

  -> eval_binop(op, l, r, env)
    if op == "=="
      return rb_eq?(l, r) if !(l.is_a?(RbObject) && lookup_method_on(l, "==") != nil)
      return call_method(l, "==", [r], {}, nil, env)
    if op == "!="
      return !rb_truthy?(eval_binop("==", l, r, env))
    if op == "==="
      return eval_case_eq(l, r, env)
    if op == "<=>"
      c = rb_cmp(l, r)
      return c if c != nil
      return call_method(l, "<=>", [r], {}, nil, env)
    if op == "=~"
      if l.is_a?(RbRegexp) && r.is_a?(RbString)
        md = l.match_str(r.data)
        @last_match = md
        return md == nil ? nil : md.begin_pos(0)
      if l.is_a?(RbString) && r.is_a?(RbRegexp)
        md = r.match_str(l.data)
        @last_match = md
        return md == nil ? nil : md.begin_pos(0)
      return nil
    if op == "!~"
      return !rb_truthy?(eval_binop("=~", l, r, env))

    # Numeric fast paths + coercion
    if (l.is_a?(Integer) || l.is_a?(Float) || l.is_a?(RbRational) || l.is_a?(RbComplex)) &&
       (r.is_a?(Integer) || r.is_a?(Float) || r.is_a?(RbRational) || r.is_a?(RbComplex))
      case op
      when "+" then return rb_num_add(l, r)
      when "-" then return rb_num_sub(l, r)
      when "*" then return rb_num_mul(l, r)
      when "/" then return rb_num_div(l, r)
      when "%"
        return rb_int_mod(l, r) if l.is_a?(Integer) && r.is_a?(Integer)
        fa = rb_to_f(l); fb = rb_to_f(r)
        rem = fa - (fa / fb).floor * fb
        return rem
      when "**" then return rb_num_pow(l, r)
      when "<" then return rb_cmp(l, r) < 0
      when "<=" then return rb_cmp(l, r) <= 0
      when ">" then return rb_cmp(l, r) > 0
      when ">=" then return rb_cmp(l, r) >= 0
      when "&" then return l & r
      when "|" then return l | r
      when "^" then return l ^ r
      when "<<" then return l << r
      when ">>" then return l >> r

    # String & Array operators
    if l.is_a?(RbString)
      if op == "+" && r.is_a?(RbString)
        return RbString.new(l.data + r.data, l.encoding)
      if op == "*" && r.is_a?(Integer)
        sb = StringBuffer()
        r.times -> sb << l.data
        return RbString.new(sb.to_s, l.encoding)
      if op == "<<"
        l.check_mut!
        l.data = l.data + (r.is_a?(Integer) ? Codepoint.new(r).to_s : rb_to_s(r))
        return l
      if op == "<" || op == "<=" || op == ">" || op == ">="
        c = rb_cmp(l, r)
        return op == "<" ? c < 0 : (op == "<=" ? c <= 0 : (op == ">" ? c > 0 : c >= 0))
      if op == "%"
        return rb_sprintf(l.data, r)
    if l.is_a?(Array)
      if op == "+" && r.is_a?(Array) then return l + r
      if op == "-" && r.is_a?(Array)
        out = []
        l.each ->(x)
          found = false
          r.each ->(y) found = true if rb_eq?(x, y)
          out.push(x) if !found
        return out
      if op == "&" && r.is_a?(Array)
        out = []
        l.each ->(x)
          in_r = false; r.each ->(y) in_r = true if rb_eq?(x, y)
          in_o = false; out.each ->(y) in_o = true if rb_eq?(x, y)
          out.push(x) if in_r && !in_o
        return out
      if op == "|" && r.is_a?(Array)
        out = []
        (l + r).each ->(x)
          in_o = false; out.each ->(y) in_o = true if rb_eq?(x, y)
          out.push(x) if !in_o
        return out
      if op == "*" && r.is_a?(Integer)
        out = []
        r.times -> l.each ->(x) out.push(x)
        return out
      if op == "*" && r.is_a?(RbString)
        parts = []
        l.each ->(x) parts.push(rb_to_s(x))
        return RbString.new(parts.join(r.data))
      if op == "<<"
        l.push(r)
        return l

    call_method(l, op, [r], {}, nil, env)

  -> rb_sprintf(fmt, arg)
    args = arg.is_a?(Array) ? arg : [arg]
    out = StringBuffer()
    i = 0
    ai = 0
    while i < fmt.size
      b = fmt.byte_at(i)
      if b == 37 && i + 1 < fmt.size
        i += 1
        nb = fmt.byte_at(i)
        if nb == 37
          out << "%"
        else
          # Optional width/precision like %.2f or %04d
          pad_zero = false
          width = 0
          prec = -1
          if nb == 48
            pad_zero = true; i += 1; nb = i < fmt.size ? fmt.byte_at(i) : 0
          while nb >= 48 && nb <= 57
            width = width * 10 + (nb - 48); i += 1; nb = i < fmt.size ? fmt.byte_at(i) : 0
          if nb == 46
            prec = 0; i += 1; nb = i < fmt.size ? fmt.byte_at(i) : 0
            while nb >= 48 && nb <= 57
              prec = prec * 10 + (nb - 48); i += 1; nb = i < fmt.size ? fmt.byte_at(i) : 0
          v = ai < args.size ? args[ai] : nil
          ai += 1
          s = ""
          if nb == 115 # %s
            s = rb_to_s(v)
          elsif nb == 100 || nb == 105 # %d / %i
            s = (v.is_a?(Integer) ? v : rb_to_f(v).to_i).to_s
          elsif nb == 120 # %x
            s = (v.is_a?(Integer) ? v : 0).to_s(16)
          elsif nb == 88 # %X
            s = (v.is_a?(Integer) ? v : 0).to_s(16).upcase
          elsif nb == 102 # %f
            fv = rb_to_f(v)
            p_n = prec >= 0 ? prec : 6
            mul = rb_num_pow(10, p_n).to_f
            sc = (fv * mul).round
            neg = sc < 0
            sc = -sc if neg
            ip = sc / rb_num_pow(10, p_n)
            fp = sc % rb_num_pow(10, p_n)
            fs = fp.to_s
            while fs.size < p_n
              fs = "0" + fs
            s = (neg ? "-" : "") + ip.to_s + (p_n > 0 ? "." + fs : "")
          else
            s = rb_to_s(v)
          pc = pad_zero ? "0" : " "
          while s.size < width
            s = pc + s
          out << s
      else
        out << fmt.slice(i, 1)
      i += 1
    RbString.new(out.to_s)

  -> bind_params(params, args, kw, blk, target_env, def_env)
    # Ruby 3.4 `it` implicit block parameter & `_1.._9` numbered parameters!
    if params.size == 0
      target_env.vars["it"] = args.size > 0 ? args[0] : nil
      n_args = (args.size == 1 && args[0].is_a?(Array)) ? args[0] : args
      k = 0
      while k < 9 && k < n_args.size
        target_env.vars["_" + (k + 1).to_s] = n_args[k]
        k += 1
    ai = 0
    used_kw = {}
    params.each ->(p)
      pk = p[0]
      pnm = p[1]
      pd = p[2]
      if pk == :forward
        target_env.vars["__fwd_args__"] = args.slice(ai, args.size - ai)
        ai = args.size
      elsif pk == :req
        target_env.vars[pnm] = ai < args.size ? args[ai] : nil
        ai += 1
      elsif pk == :opt
        if ai < args.size
          target_env.vars[pnm] = args[ai]
          ai += 1
        else
          target_env.vars[pnm] = eval_node(pd, target_env)
      elsif pk == :splat
        rest = ai < args.size ? args.slice(ai, args.size - ai) : []
        target_env.vars[pnm] = rest if pnm != "*"
        ai = args.size
      elsif pk == :kw_req
        raise_exc("ArgumentError", "missing keyword: :" + pnm) if !kw.has_key?(pnm)
        target_env.vars[pnm] = kw[pnm]
        used_kw[pnm] = true
      elsif pk == :kw_opt || pk == :kw
        if kw.has_key?(pnm)
          target_env.vars[pnm] = kw[pnm]
          used_kw[pnm] = true
        else
          target_env.vars[pnm] = pd != nil ? eval_node(pd, target_env) : nil
      elsif pk == :kw_splat
        rh = RbHash.new
        kw.each ->(k, v) rh.set(RbSym.new(k), v) if !used_kw.has_key?(k)
        target_env.vars[pnm] = rh if pnm != "**"
      elsif pk == :block
        target_env.vars[pnm] = blk if pnm != "&"
      elsif pk == :destruct
        av = ai < args.size ? args[ai] : nil
        ai += 1
        arr = av.is_a?(Array) ? av : [av]
        di = 0
        while di < pnm.size
          target_env.vars[pnm[di]] = di < arr.size ? arr[di] : nil
          di += 1
    nil

  -> call_proc(pr, args, kw = {})
    return pr.native_fn.call(args, kw) if pr.native_fn != nil
    fid = pr.def_frame_id
    if pr.is_lambda
      @next_frame_id += 1
      fid = @next_frame_id
    penv = RbEnv.new(pr.env, pr.self_obj, pr.env.block, fid, pr.env.cref)
    # Ruby block auto-unpacking: `[[1, 2]].map { |a, b| a + b }`
    if !pr.is_lambda && pr.params.size > 1 && args.size == 1 && args[0].is_a?(Array)
      args = args[0]
    bind_params(pr.params, args, kw, nil, penv, pr.env)
    while true
      begin
        return eval_stmts(pr.body, penv)
      rescue sig
        if sig.is_a?(RbSignal)
          return sig.val if sig.kind == :next
          return sig.val if sig.kind == :return && pr.is_lambda && sig.target_id == fid
          next if sig.kind == :redo
        raise sig

  # Fast Flat-Register Bytecode VM execution engine (ZERO RbEnv / Hash / Array allocs per call!)
  -> exec_bytecode(bc, recv, fp, arg0, arg1, args_arr)
    fsize = bc.frame_size
    if fp + fsize + 64 >= @reg_stack.size
      # Grow register stack if deep recursion
      extra = @reg_stack.size
      ei = 0
      while ei < extra
        @reg_stack.push(nil)
        ei += 1
    stk = @reg_stack
    ar = bc.arity
    if ar == 1
      stk[fp] = arg0
    elsif ar == 2
      stk[fp] = arg0
      stk[fp + 1] = arg1
    elsif ar > 2 && args_arr != nil
      ai = 0
      while ai < ar
        stk[fp + ai] = args_arr[ai]
        ai += 1
    ops = bc.ops ## i64[]
    aa = bc.a ## i64[]
    bb = bc.b ## i64[]
    cc = bc.c ## i64[]
    consts = bc.consts
    names = bc.names
    aux = bc.aux
    ic_ep = bc.ic_epoch ## i64[]
    ic_cls = bc.ic_cls
    ic_code = bc.ic_code
    nops = bc.nops ## i64
    fp_i = fp ## i64
    pc = 0 ## i64
    while pc < nops
      op = ops[pc] ## i64
      a = aa[pc] ## i64
      b = bb[pc] ## i64
      c = cc[pc] ## i64
      if op == RB_OP_JGE_IMM
        v1 = stk[fp_i + a]
        if v1.is_a?(Integer)
          if v1 >= b
            pc = c
            next
        elsif rb_cmp(v1, b) >= 0
          pc = c
          next
        pc += 1
      elsif op == RB_OP_JGT_IMM
        v1 = stk[fp_i + a]
        if v1.is_a?(Integer)
          if v1 > b
            pc = c
            next
        elsif rb_cmp(v1, b) > 0
          pc = c
          next
        pc += 1
      elsif op == RB_OP_JGE
        v1 = stk[fp_i + a]
        v2 = stk[fp_i + b]
        if v1.is_a?(Integer) && v2.is_a?(Integer)
          if v1 >= v2
            pc = c
            next
        elsif rb_cmp(v1, v2) >= 0
          pc = c
          next
        pc += 1
      elsif op == RB_OP_JGT
        v1 = stk[fp_i + a]
        v2 = stk[fp_i + b]
        if v1.is_a?(Integer) && v2.is_a?(Integer)
          if v1 > v2
            pc = c
            next
        elsif rb_cmp(v1, v2) > 0
          pc = c
          next
        pc += 1
      elsif op == RB_OP_ADD_IMM
        v1 = stk[fp_i + b]
        stk[fp_i + a] = v1.is_a?(Integer) ? (v1 + c) : rb_num_add(v1, c)
        pc += 1
      elsif op == RB_OP_SUB_IMM
        v1 = stk[fp_i + b]
        stk[fp_i + a] = v1.is_a?(Integer) ? (v1 - c) : rb_num_sub(v1, c)
        pc += 1
      elsif op == RB_OP_ADD
        v1 = stk[fp_i + b]
        v2 = stk[fp_i + c]
        stk[fp_i + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 + v2) : eval_binop("+", v1, v2, @top_env)
        pc += 1
      elsif op == RB_OP_SUB
        v1 = stk[fp_i + b]
        v2 = stk[fp_i + c]
        stk[fp_i + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 - v2) : eval_binop("-", v1, v2, @top_env)
        pc += 1
      elsif op == RB_OP_MUL
        v1 = stk[fp_i + b]
        v2 = stk[fp_i + c]
        stk[fp_i + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 * v2) : eval_binop("*", v1, v2, @top_env)
        pc += 1
      elsif op == RB_OP_CALL_SELF_1
        ep = @method_epoch
        rcls = class_of(recv)
        tbc = nil
        if ic_ep[pc] == ep && ic_cls[pc] == rcls
          tbc = ic_code[pc]
        else
          tm = lookup_method_on(recv, names[b])
          if tm != nil && tm.native_fn == nil
            if !tm.bc_tried
              tm.bc_tried = true
              tm.bytecode = rb_compile_method_bytecode(tm)
            if tm.bytecode != nil && tm.bytecode.arity == 1
              tbc = tm.bytecode
              ic_ep[pc] = ep
              ic_cls[pc] = rcls
              ic_code[pc] = tbc
        if tbc != nil
          stk[fp_i + a] = exec_bytecode(tbc, recv, fp_i + fsize, stk[fp_i + c], nil, nil)
        else
          stk[fp_i + a] = call_method(recv, names[b], [stk[fp_i + c]], {}, nil, @top_env)
        pc += 1
      elsif op == RB_OP_CALL_SELF_2
        ep = @method_epoch
        rcls = class_of(recv)
        tbc = nil
        if ic_ep[pc] == ep && ic_cls[pc] == rcls
          tbc = ic_code[pc]
        else
          tm = lookup_method_on(recv, names[b])
          if tm != nil && tm.native_fn == nil
            if !tm.bc_tried
              tm.bc_tried = true
              tm.bytecode = rb_compile_method_bytecode(tm)
            if tm.bytecode != nil && tm.bytecode.arity == 2
              tbc = tm.bytecode
              ic_ep[pc] = ep
              ic_cls[pc] = rcls
              ic_code[pc] = tbc
        if tbc != nil
          stk[fp_i + a] = exec_bytecode(tbc, recv, fp_i + fsize, stk[fp_i + c], stk[fp_i + c + 1], nil)
        else
          stk[fp_i + a] = call_method(recv, names[b], [stk[fp_i + c], stk[fp_i + c + 1]], {}, nil, @top_env)
        pc += 1
      elsif op == RB_OP_JMP
        pc = a
      elsif op == RB_OP_RET
        return stk[fp_i + a]
      elsif op == RB_OP_INT
        stk[fp_i + a] = b
        pc += 1
      elsif op == RB_OP_MOV
        stk[fp_i + a] = stk[fp_i + b]
        pc += 1
      elsif op == RB_OP_IDX_GET
        arr = stk[fp_i + b]
        idx = stk[fp_i + c]
        if arr.is_a?(Array) && idx.is_a?(Integer)
          ii = idx < 0 ? arr.size + idx : idx
          stk[fp_i + a] = (ii >= 0 && ii < arr.size) ? arr[ii] : nil
        else
          stk[fp_i + a] = call_method(arr, '[]', [idx], {}, nil, @top_env)
        pc += 1
      elsif op == RB_OP_IDX_SET
        arr = stk[fp_i + a]
        idx = stk[fp_i + b]
        val = stk[fp_i + c]
        if arr.is_a?(Array) && idx.is_a?(Integer)
          ii = idx < 0 ? arr.size + idx : idx
          while arr.size <= ii
            arr.push(nil)
          arr[ii] = val
        else
          call_method(arr, '[]=', [idx, val], {}, nil, @top_env)
        pc += 1
      elsif op == RB_OP_CONST_GET
        stk[fp_i + a] = resolve_const(names[b], @top_env)
        pc += 1
      elsif op == RB_OP_STR_PUSH
        dst_v = stk[fp + a]
        rhs_v = stk[fp + b]
        if dst_v.is_a?(RbString)
          dst_v.check_mut!
          dst_v.data = dst_v.data + (rhs_v.is_a?(RbString) ? rhs_v.data : rb_to_s(rhs_v))
        elsif dst_v.is_a?(Array)
          dst_v.push(rhs_v)
        else
          call_method(dst_v, "<<", [rhs_v], {}, nil, @top_env)
        pc += 1
      elsif op == RB_OP_JMP_FALSE
        v1 = stk[fp + a]
        pc = (v1 == nil || v1 == false) ? b : pc + 1
      elsif op == RB_OP_JMP_TRUE
        v1 = stk[fp + a]
        pc = (v1 != nil && v1 != false) ? b : pc + 1
      elsif op == RB_OP_EQ_IMM
        v1 = stk[fp + b]
        stk[fp + a] = v1.is_a?(Integer) ? (v1 == c) : rb_eq?(v1, c)
        pc += 1
      elsif op == RB_OP_LT_IMM
        v1 = stk[fp + b]
        stk[fp + a] = v1.is_a?(Integer) ? (v1 < c) : (rb_cmp(v1, c) < 0)
        pc += 1
      elsif op == RB_OP_LE_IMM
        v1 = stk[fp + b]
        stk[fp + a] = v1.is_a?(Integer) ? (v1 <= c) : (rb_cmp(v1, c) <= 0)
        pc += 1
      elsif op == RB_OP_NIL
        stk[fp + a] = nil
        pc += 1
      elsif op == RB_OP_BOOL
        stk[fp + a] = (b != 0)
        pc += 1
      elsif op == RB_OP_SELF
        stk[fp + a] = recv
        pc += 1
      elsif op == RB_OP_CONST
        stk[fp + a] = consts[b]
        pc += 1
      elsif op == RB_OP_STR_LIT
        stk[fp + a] = RbString.new(consts[b], RB_ENC_UTF8, c != 0)
        pc += 1
      elsif op == RB_OP_DIV
        v1 = stk[fp + b]; v2 = stk[fp + c]
        stk[fp + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? rb_int_div(v1, v2) : eval_binop("/", v1, v2, @top_env)
        pc += 1
      elsif op == RB_OP_MOD
        v1 = stk[fp + b]; v2 = stk[fp + c]
        stk[fp + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? rb_int_mod(v1, v2) : eval_binop("%", v1, v2, @top_env)
        pc += 1
      elsif op == RB_OP_LT
        v1 = stk[fp + b]; v2 = stk[fp + c]
        stk[fp + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 < v2) : (rb_cmp(v1, v2) < 0)
        pc += 1
      elsif op == RB_OP_LE
        v1 = stk[fp + b]; v2 = stk[fp + c]
        stk[fp + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 <= v2) : (rb_cmp(v1, v2) <= 0)
        pc += 1
      elsif op == RB_OP_GT
        v1 = stk[fp + b]; v2 = stk[fp + c]
        stk[fp + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 > v2) : (rb_cmp(v1, v2) > 0)
        pc += 1
      elsif op == RB_OP_GE
        v1 = stk[fp + b]; v2 = stk[fp + c]
        stk[fp + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 >= v2) : (rb_cmp(v1, v2) >= 0)
        pc += 1
      elsif op == RB_OP_EQ
        v1 = stk[fp + b]; v2 = stk[fp + c]
        stk[fp + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 == v2) : rb_eq?(v1, v2)
        pc += 1
      elsif op == RB_OP_NEQ
        v1 = stk[fp + b]; v2 = stk[fp + c]
        stk[fp + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 != v2) : !rb_eq?(v1, v2)
        pc += 1
      elsif op == RB_OP_NOT
        v1 = stk[fp + b]
        stk[fp + a] = (v1 == nil || v1 == false)
        pc += 1
      elsif op == RB_OP_NEG
        v1 = stk[fp + b]
        stk[fp + a] = (v1.is_a?(Integer) || v1.is_a?(Float)) ? -v1 : call_method(v1, "-@", [], {}, nil, @top_env)
        pc += 1
      elsif op == RB_OP_BIT_AND
        stk[fp + a] = stk[fp + b] & stk[fp + c]; pc += 1
      elsif op == RB_OP_BIT_OR
        stk[fp + a] = stk[fp + b] | stk[fp + c]; pc += 1
      elsif op == RB_OP_BIT_XOR
        stk[fp + a] = stk[fp + b] ^ stk[fp + c]; pc += 1
      elsif op == RB_OP_SHL
        stk[fp + a] = stk[fp + b] << stk[fp + c]; pc += 1
      elsif op == RB_OP_SHR
        stk[fp + a] = stk[fp + b] >> stk[fp + c]; pc += 1
      elsif op == RB_OP_IVAR_GET
        stk[fp + a] = (recv.is_a?(RbObject) || recv.is_a?(RbModule)) ? recv.ivars[names[b]] : nil
        pc += 1
      elsif op == RB_OP_IVAR_SET
        recv.ivars[names[a]] = stk[fp + b] if recv.is_a?(RbObject) || recv.is_a?(RbModule)
        pc += 1
      elsif op == RB_OP_ARRAY_NEW
        arr = []
        k = 0
        while k < c
          arr.push(stk[fp + b + k])
          k += 1
        stk[fp + a] = arr
        pc += 1
      elsif op == RB_OP_CALL_SELF_0
        stk[fp + a] = call_method(recv, names[b], [], {}, nil, @top_env)
        pc += 1
      elsif op == RB_OP_CALL_SELF_N
        argc = aux[pc]
        cargs = []
        k = 0
        while k < argc
          cargs.push(stk[fp + c + k])
          k += 1
        stk[fp + a] = call_method(recv, names[b], cargs, {}, nil, @top_env)
        pc += 1
      elsif op == RB_OP_SEND
        spec = aux[pc]
        base = spec[0]
        argc = spec[1]
        sargs = []
        k = 0
        while k < argc
          sargs.push(stk[fp + base + k])
          k += 1
        stk[fp + a] = call_method(stk[fp + b], names[c], sargs, {}, nil, @top_env)
        pc += 1
      else
        pc += 1
    nil

  -> invoke_rb_method(m, recv, args, kw, blk)
    return m.native_fn.call(recv, args, kw, blk) if m.native_fn != nil
    if kw.size == 0 && blk == nil && @max_steps == 0
      if !m.bc_tried
        m.bc_tried = true
        m.bytecode = rb_compile_method_bytecode(m)
      if m.bytecode != nil && args.size == m.bytecode.arity
        a0 = args.size > 0 ? args[0] : nil
        a1 = args.size > 1 ? args[1] : nil
        return exec_bytecode(m.bytecode, recv, 0, a0, a1, args)
    @next_frame_id += 1
    fid = @next_frame_id
    cref = m.def_env != nil ? m.def_env.cref : [m.owner]
    menv = RbEnv.new(nil, recv, blk, fid, cref)
    menv.vars["__super_owner__"] = m.owner
    menv.vars["__super_name__"] = m.name
    menv.vars["__super_args__"] = args
    bind_params(m.params, args, kw, blk, menv, m.def_env)
    begin
      eval_stmts(m.body, menv)
    rescue sig
      if sig.is_a?(RbSignal) && sig.kind == :return && sig.target_id == fid
        return sig.val
      raise sig

  -> lookup_method_on(recv, nm)
    if (recv.is_a?(RbObject) || recv.is_a?(RbModule)) && recv.singleton_cls != nil
      sm = recv.singleton_cls.lookup_method(nm)
      return sm if sm != nil
    class_of(recv).lookup_method(nm)

  # Main Ruby method dispatch: user-defined methods -> builtin stdlib -> Tungsten bridge -> method_missing
  -> call_method(recv, nm, args, kw, blk, env)
    # 1. Check singleton class & user-defined class/module MRO first (supports open classes & monkey-patching!)
    m = lookup_method_on(recv, nm)
    if m != nil
      if blk != nil
        begin
          return invoke_rb_method(m, recv, args, kw, blk)
        rescue sig
          return sig.val if sig.is_a?(RbSignal) && sig.kind == :break
          raise sig
      return invoke_rb_method(m, recv, args, kw, blk)

    # 2. Direct Tungsten interop module `Tungsten.<fn>(*args)` / `Tungsten.call(:fn, *args)`!
    if recv == @c_tungsten
      return dispatch_tungsten_bridge(nm, args, kw, blk)

    # 3. Builtin dispatch by receiver class (catching :break when a block was given!)
    if blk != nil
      begin
        res = dispatch_builtin(recv, nm, args, kw, blk, env)
        return res[1] if res[0]
      rescue sig
        return sig.val if sig.is_a?(RbSignal) && sig.kind == :break
        raise sig
    else
      res = dispatch_builtin(recv, nm, args, kw, blk, env)
      return res[1] if res[0]

    # 3b. Enumerable module fallback for any class that includes Enumerable and defines #each
    if class_of(recv).ancestors().include?(@c_enumerable) && nm != "each" &&
       (nm == "map" || nm == "collect" || nm == "select" || nm == "find_all" || nm == "reject" || nm == "find" || nm == "detect" || nm == "any?" || nm == "all?" || nm == "none?" || nm == "inject" || nm == "reduce" || nm == "to_a" || nm == "entries" || nm == "count" || nm == "first" || nm == "take" || nm == "drop" || nm == "include?" || nm == "min" || nm == "max" || nm == "sum")
      collected = []
      coll_fn = ->(pargs, pkw)
        collected.push(pargs.size == 1 ? pargs[0] : pargs)
        nil
      coll_blk = RbProc.new([], nil, env, recv, false, coll_fn, 0)
      call_method(recv, "each", [], {}, coll_blk, env)
      return collected if nm == "to_a" || nm == "entries"
      return call_method(collected, nm, args, kw, blk, env)

    # 4. method_missing hook
    mm = lookup_method_on(recv, "method_missing")
    if mm != nil
      return invoke_rb_method(mm, recv, [RbSym.new(nm)] + args, kw, blk)

    raise_exc("NoMethodError", "undefined method `" + nm + "' for " + rb_inspect(recv) + ":" + class_of(recv).name)

  -> dispatch_tungsten_bridge(nm, args, kw, blk)
    if nm == "call" && args.size >= 1
      fn_nm = rb_to_s(args[0])
      fn = @tungsten_fns[fn_nm]
      raise_exc("NameError", "no registered Tungsten function `" + fn_nm + "'") if fn == nil
      targs = []
      i = 1
      while i < args.size
        targs.push(rb_to_tungsten(args[i]))
        i += 1
      return rb_from_tungsten(fn.call(targs))
    if @tungsten_fns.has_key?(nm)
      targs = []
      args.each ->(a) targs.push(rb_to_tungsten(a))
      return rb_from_tungsten(@tungsten_fns[nm].call(targs))
    if nm == "version"
      return RbString.new("tungsten-ruby-bridge/1.0")
    if nm == "methods" || nm == "registered"
      out = []
      @tungsten_fns.each ->(k, v) out.push(RbSym.new(k))
      return out
    raise_exc("NoMethodError", "undefined Tungsten bridge method `" + nm + "'")

  -> dispatch_builtin(recv, nm, args, kw, blk, env)
    # --- Class / Module methods ---
    if recv.is_a?(RbClass)
      if nm == "new"
        if recv == @c_struct
          # Struct.new(:a, :b)
          sc = RbClass.new("Struct", @c_struct)
          mems = []
          args.each ->(a) mems.push(rb_to_s(a))
          sc.struct_members = mems
          mems.each ->(mn)
            sc.methods[mn] = RbMethod.new(mn, [], nil, nil, sc, ->(r, a, k, b) r.ivars["@" + mn])
            sc.methods[mn + "="] = RbMethod.new(mn + "=", [], nil, nil, sc, ->(r, a, k, b) r.ivars["@" + mn] = a[0])
          if blk != nil
            cenv = RbEnv.new(nil, sc, nil, 0, [sc])
            eval_stmts(blk.body, cenv)
          return [true, sc]
        if recv == @c_proc
          return [true, blk]
        if recv == @c_array
          n = args.size > 0 ? args[0] : 0
          out = []
          i = 0
          while i < n
            out.push(blk != nil ? call_proc(blk, [i]) : (args.size > 1 ? args[1] : nil))
            i += 1
          return [true, out]
        if recv == @c_hash
          h = RbHash.new
          h.default_val = args[0] if args.size > 0
          h.default_proc = blk if blk != nil
          return [true, h]
        if recv == @c_string
          return [true, RbString.new(args.size > 0 ? rb_to_s(args[0]) : "")]
        if recv == @c_regexp
          return [true, RbRegexp.new(rb_to_s(args[0]), args.size > 1 ? rb_to_s(args[1]) : "")]
        if recv == @c_range
          return [true, RbRange.new(args[0], args[1], args.size > 2 && rb_truthy?(args[2]))]
        if recv.struct_members != nil
          obj = RbObject.new(recv)
          i = 0
          while i < recv.struct_members.size
            mn = recv.struct_members[i]
            v = kw.has_key?(mn) ? kw[mn] : (i < args.size ? args[i] : nil)
            obj.ivars["@" + mn] = v
            i += 1
          obj.frozen = true if recv.is_data_class
          return [true, obj]
        if recv.subclass_of?(@c_exception)
          return [true, RbException.new(recv.name, args.size > 0 ? rb_to_s(args[0]) : "", recv)]
        obj = RbObject.new(recv)
        im = recv.lookup_method("initialize")
        invoke_rb_method(im, obj, args, kw, blk) if im != nil
        return [true, obj]
      if recv == @c_data && nm == "define"
        # Ruby 3.2-4.0 Data.define(:x, :y) — immutable value objects!
        dc = RbClass.new("Data", @c_data)
        dc.is_data_class = true
        mems = []
        args.each ->(a) mems.push(rb_to_s(a))
        dc.struct_members = mems
        mems.each ->(mn)
          dc.methods[mn] = RbMethod.new(mn, [], nil, nil, dc, ->(r, a, k, b) r.ivars["@" + mn])
        with_fn = ->(r, a, k, b)
          obj = RbObject.new(dc)
          mems.each ->(mn) obj.ivars["@" + mn] = k.has_key?(mn) ? k[mn] : r.ivars["@" + mn]
          obj.frozen = true
          obj
        dc.methods["with"] = RbMethod.new("with", [], nil, nil, dc, with_fn)
        eq_fn = ->(r, a, k, b)
          o = a[0]
          if !o.is_a?(RbObject) || o.klass != dc
            false
          else
            ok = true
            mems.each ->(mn) ok = false if !rb_eq?(r.ivars["@" + mn], o.ivars["@" + mn])
            ok
        dc.methods["=="] = RbMethod.new("==", [], nil, nil, dc, eq_fn)
        if blk != nil
          cenv = RbEnv.new(nil, dc, nil, 0, [dc])
          eval_stmts(blk.body, cenv)
        return [true, dc]
      return [true, recv.superclass] if nm == "superclass"
    if recv.is_a?(RbModule)
      if nm == "attr" || nm == "attr_reader" || nm == "attr_accessor" || nm == "attr_writer"
        if nm == "attr"
          an = rb_to_s(args[0])
          getter_fn = ->(r, aa, kk, bb)
            raise_exc("ArgumentError", "wrong number of arguments (given " + aa.size.to_s + ", expected 0)") if aa.size > 0
            r.ivars["@" + an]
          recv.methods[an] = RbMethod.new(an, [], nil, nil, recv, getter_fn)
          if args.size > 1 && rb_truthy?(args[1])
            recv.methods[an + "="] = RbMethod.new(an + "=", [], nil, nil, recv, ->(r, aa, kk, bb) r.ivars["@" + an] = aa[0])
          return [true, nil]
        args.each ->(a)
          an = rb_to_s(a)
          if nm == "attr_reader" || nm == "attr_accessor"
            recv.methods[an] = RbMethod.new(an, [], nil, nil, recv, ->(r, aa, kk, bb) r.ivars["@" + an])
          if nm == "attr_writer" || nm == "attr_accessor"
            recv.methods[an + "="] = RbMethod.new(an + "=", [], nil, nil, recv, ->(r, aa, kk, bb) r.ivars["@" + an] = aa[0])
        return [true, nil]
      if nm == "const_defined?"
        cn = rb_to_s(args[0])
        return [true, recv.constants.has_key?(cn) || (recv == @c_object && @constants.has_key?(cn))]
      if nm == "const_get"
        cn = rb_to_s(args[0])
        return [true, recv.constants[cn]] if recv.constants.has_key?(cn)
        return [true, @constants[cn]] if recv == @c_object && @constants.has_key?(cn)
        raise_exc("NameError", "uninitialized constant " + cn)
      if nm == "const_set"
        cn = rb_to_s(args[0])
        recv.constants[cn] = args[1]
        @constants[cn] = args[1] if recv == @c_object
        return [true, args[1]]
      if nm == "remove_const"
        cn = rb_to_s(args[0])
        old = recv.constants[cn]
        recv.constants.delete(cn)
        @constants.delete(cn) if recv == @c_object
        return [true, old]
      if nm == "include"
        args.each ->(m) recv.includes.unshift(m) if m.is_a?(RbModule)
        return [true, recv]
      if nm == "prepend"
        args.each ->(m) recv.prepends.unshift(m) if m.is_a?(RbModule)
        return [true, recv]
      if nm == "alias_method"
        m = recv.lookup_method(rb_to_s(args[1]))
        recv.methods[rb_to_s(args[0])] = m if m != nil
        return [true, RbSym.new(rb_to_s(args[0]))]
      if nm == "define_method"
        mnm = rb_to_s(args[0])
        pr = blk != nil ? blk : args[1]
        if pr.is_a?(RbProc)
          recv.methods[mnm] = RbMethod.new(mnm, pr.params, pr.body, pr.env, recv)
        return [true, RbSym.new(mnm)]
      if nm == "ancestors" then return [true, recv.ancestors()]
      if nm == "name" then return [true, RbString.new(recv.name)]
      if nm == "private" || nm == "protected" || nm == "public" || nm == "module_function"
        if nm == "module_function" && args.size > 0
          sc = singleton_class_of(recv)
          args.each ->(a)
            an = rb_to_s(a)
            m = recv.methods[an]
            sc.methods[an] = m if m != nil
        return [true, recv]
      if recv == @c_math
        x = args.size > 0 ? rb_to_f(args[0]) : ~0.0
        case nm
        when "sqrt" then return [true, Math.sqrt(x)]
        when "sin" then return [true, Math.sin(x)]
        when "cos" then return [true, Math.cos(x)]
        when "tan" then return [true, Math.tan(x)]
        when "exp" then return [true, Math.exp(x)]
        when "log" then return [true, args.size > 1 ? Math.log(x) / Math.log(rb_to_f(args[1])) : Math.log(x)]
        when "log2" then return [true, Math.log(x) / Math.log(~2.0)]
        when "log10" then return [true, Math.log(x) / Math.log(~10.0)]
        when "hypot" then return [true, Math.sqrt(x * x + rb_to_f(args[1]) * rb_to_f(args[1]))]
      if recv == @c_json
        if nm == "parse"
          return [true, rb_from_tungsten(JSON.parse(rb_to_s(args[0])))]
        if nm == "generate" || nm == "dump"
          return [true, RbString.new(JSON.encode(rb_to_tungsten(args[0])))]
      if recv == @c_encoding && nm == "find"
        return [true, rb_find_encoding(rb_to_s(args[0]))]

    # --- Integer ---
    if recv.is_a?(Integer)
      case nm
      when "abs" then return [true, recv < 0 ? -recv : recv]
      when "even?" then return [true, (recv & 1) == 0]
      when "odd?" then return [true, (recv & 1) == 1]
      when "zero?" then return [true, recv == 0]
      when "positive?" then return [true, recv > 0]
      when "negative?" then return [true, recv < 0]
      when "to_i", "floor", "ceil", "round" then return [true, recv]
      when "to_f" then return [true, recv.to_f]
      when "to_r" then return [true, RbRational.new(recv, 1)]
      when "to_c" then return [true, RbComplex.new(recv, 0)]
      when "to_s" then return [true, RbString.new(args.size > 0 ? recv.to_s(args[0]) : recv.to_s)]
      when "chr" then return [true, RbString.new(Codepoint.new(recv).to_s)]
      when "gcd" then return [true, rb_gcd(recv, args[0])]
      when "lcm"
        g = rb_gcd(recv, args[0])
        p = (recv * args[0]) / g
        return [true, p < 0 ? -p : p]
      when "divmod" then return [true, [rb_int_div(recv, args[0]), rb_int_mod(recv, args[0])]]
      when "fdiv" then return [true, recv.to_f / rb_to_f(args[0])]
      when "pow"
        if args.size == 2
          # Modular exponentiation a^e mod m
          res = 1; b = rb_int_mod(recv, args[1]); e = args[0]; md = args[1]
          while e > 0
            res = rb_int_mod(res * b, md) if (e & 1) == 1
            b = rb_int_mod(b * b, md)
            e = e >> 1
          return [true, res]
        return [true, rb_num_pow(recv, args[0])]
      when "digits"
        base = args.size > 0 ? args[0] : 10
        return [true, [0]] if recv == 0
        out = []; v = recv
        while v > 0
          out.push(v % base); v = v / base
        return [true, out]
      when "times"
        if blk == nil
          a = []
          i = 0
          while i < recv
            a.push(i)
            i += 1
          return [true, RbEnumerator.new(a)]
        i = 0
        while i < recv
          begin
            call_proc(blk, [i])
          rescue sig
            return [true, sig.val] if sig.is_a?(RbSignal) && sig.kind == :break
            raise sig
          i += 1
        return [true, recv]
      when "upto"
        hi = args[0]
        if blk == nil
          a = []
          i = recv
          while i <= hi
            a.push(i)
            i += 1
          return [true, RbEnumerator.new(a)]
        i = recv
        while i <= hi
          begin
            call_proc(blk, [i])
          rescue sig
            return [true, sig.val] if sig.is_a?(RbSignal) && sig.kind == :break
            raise sig
          i += 1
        return [true, recv]
      when "downto"
        lo = args[0]
        i = recv
        while i >= lo
          begin
            call_proc(blk, [i])
          rescue sig
            return [true, sig.val] if sig.is_a?(RbSignal) && sig.kind == :break
            raise sig
          i -= 1
        return [true, recv]
      when "between?" then return [true, rb_cmp(recv, args[0]) >= 0 && rb_cmp(recv, args[1]) <= 0]
      when "clamp"
        v = recv
        v = args[0] if args[0] != nil && rb_cmp(v, args[0]) < 0
        v = args[1] if args[1] != nil && rb_cmp(v, args[1]) > 0
        return [true, v]
      when "coerce"
        o = args[0]
        return [true, [o, recv]] if o.is_a?(Integer)
        return [true, [rb_to_f(o), recv.to_f]]

    # --- Float ---
    if recv.is_a?(Float)
      case nm
      when "abs" then return [true, recv < ~0.0 ? -recv : recv]
      when "floor" then return [true, recv.floor]
      when "ceil" then return [true, recv.ceil]
      when "round"
        if args.size > 0 && args[0] > 0
          m = rb_num_pow(10, args[0]).to_f
          return [true, (recv * m).round.to_f / m]
        return [true, recv.round]
      when "to_i" then return [true, recv.to_i]
      when "to_f" then return [true, recv]
      when "nan?" then return [true, recv != recv]
      when "infinite?" then return [true, (recv > ~1.0e308) ? 1 : (recv < ~-1.0e308 ? -1 : nil)]
      when "finite?" then return [true, recv == recv && recv <= ~1.0e308 && recv >= ~-1.0e308]
      when "zero?" then return [true, recv == ~0.0]

    # --- Rational & Complex ---
    if recv.is_a?(RbRational)
      case nm
      when "numerator" then return [true, recv.num]
      when "denominator" then return [true, recv.den]
      when "to_f" then return [true, recv.to_f()]
      when "to_i" then return [true, recv.to_i()]
      when "to_r" then return [true, recv]
      when "abs" then return [true, RbRational.new(recv.num < 0 ? -recv.num : recv.num, recv.den)]
    if recv.is_a?(RbComplex)
      case nm
      when "real" then return [true, recv.real]
      when "imag", "imaginary" then return [true, recv.imag]
      when "conj", "conjugate" then return [true, RbComplex.new(recv.real, rb_num_sub(0, recv.imag))]
      when "abs" then return [true, Math.sqrt(rb_to_f(recv.real) * rb_to_f(recv.real) + rb_to_f(recv.imag) * rb_to_f(recv.imag))]
      when "rect", "rectangular" then return [true, [recv.real, recv.imag]]

    # --- Mutable Ruby String ---
    if recv.is_a?(RbString)
      s = recv.data
      case nm
      when "length", "size" then return [true, s.chars.size]
      when "bytesize" then return [true, s.size]
      when "empty?" then return [true, s.size == 0]
      when "encoding" then return [true, recv.encoding]
      when "force_encoding"
        recv.check_mut!
        recv.encoding = args[0].is_a?(RbEncoding) ? args[0] : rb_find_encoding(rb_to_s(args[0]))
        return [true, recv]
      when "encode"
        enc = args[0].is_a?(RbEncoding) ? args[0] : rb_find_encoding(rb_to_s(args[0]))
        return [true, RbString.new(s, enc, false)]
      when "valid_encoding?" then return [true, true]
      when "ascii_only?"
        i = 0
        while i < s.size
          return [true, false] if s.byte_at(i) >= 128
          i += 1
        return [true, true]
      when "frozen?" then return [true, recv.frozen]
      when "freeze" then return [true, recv.freeze()]
      when "dup", "clone" then return [true, recv.dup()]
      when "upcase" then return [true, RbString.new(s.upcase, recv.encoding)]
      when "upcase!"
        recv.check_mut!
        recv.data = s.upcase
        return [true, recv]
      when "downcase" then return [true, RbString.new(s.downcase, recv.encoding)]
      when "downcase!"
        recv.check_mut!
        recv.data = s.downcase
        return [true, recv]
      when "capitalize" then return [true, RbString.new(s.size == 0 ? "" : s.slice(0, 1).upcase + s.slice(1, s.size - 1).downcase, recv.encoding)]
      when "strip" then return [true, RbString.new(s.strip, recv.encoding)]
      when "lstrip" then return [true, RbString.new(s.lstrip, recv.encoding)]
      when "rstrip" then return [true, RbString.new(s.rstrip, recv.encoding)]
      when "chomp"
        sep = args.size > 0 ? rb_to_s(args[0]) : "\n"
        out = s
        if sep == "\n"
          out = out.slice(0, out.size - 1) if out.ends_with?("\n")
          out = out.slice(0, out.size - 1) if out.ends_with?("\r")
        elsif out.ends_with?(sep)
          out = out.slice(0, out.size - sep.size)
        return [true, RbString.new(out, recv.encoding)]
      when "reverse"
        ch = s.chars
        out = StringBuffer()
        i = ch.size - 1
        while i >= 0
          out << ch[i]
          i -= 1
        return [true, RbString.new(out.to_s, recv.encoding)]
      when "chars"
        out = []
        s.chars.each ->(c) out.push(RbString.new(c, recv.encoding))
        return [true, out]
      when "bytes"
        out = []
        i = 0
        while i < s.size
          out.push(s.byte_at(i))
          i += 1
        return [true, out]
      when "ord" then return [true, s.size > 0 ? s.chars[0].codepoints[0] : 0]
      when "lines"
        out = []
        s.split("\n").each ->(l) out.push(RbString.new(l + "\n", recv.encoding))
        return [true, out]
      when "split"
        sep = args.size == 0 ? nil : args[0]
        if sep == nil
          parts = s.strip.split(" ").select ->(x) x.size > 0
          return [true, parts.map ->(x) RbString.new(x, recv.encoding)]
        if sep.is_a?(RbRegexp)
          raw_p = sep.compiled.split(s)
          return [true, raw_p.map ->(x) RbString.new(x, recv.encoding)]
        ss = rb_to_s(sep)
        raw_p = ss == "" ? s.chars : s.split(ss)
        return [true, raw_p.map ->(x) RbString.new(x, recv.encoding)]
      when "include?" then return [true, s.index(rb_to_s(args[0])) != nil]
      when "start_with?"
        ok = false
        args.each ->(a) ok = true if s.starts_with?(rb_to_s(a))
        return [true, ok]
      when "end_with?"
        ok = false
        args.each ->(a) ok = true if s.ends_with?(rb_to_s(a))
        return [true, ok]
      when "index"
        if args[0].is_a?(RbRegexp)
          md = args[0].match_str(s, args.size > 1 ? args[1] : 0)
          return [true, md == nil ? nil : md.begin_pos(0)]
        return [true, s.index(rb_to_s(args[0]), args.size > 1 ? args[1] : 0)]
      when "match"
        rx = args[0].is_a?(RbRegexp) ? args[0] : RbRegexp.new(rb_to_s(args[0]))
        md = rx.match_str(s, args.size > 1 ? args[1] : 0)
        @last_match = md
        return [true, md != nil && blk != nil ? call_proc(blk, [md]) : md]
      when "match?"
        rx = args[0].is_a?(RbRegexp) ? args[0] : RbRegexp.new(rb_to_s(args[0]))
        return [true, rx.match_str(s, args.size > 1 ? args[1] : 0) != nil]
      when "scan"
        rx = args[0].is_a?(RbRegexp) ? args[0] : RbRegexp.new(rb_to_s(args[0]))
        out = []
        pos = 0
        while pos <= s.size
          md = rx.match_str(s, pos)
          break if md == nil
          caps = md.captures()
          out.push(caps.size > 0 ? caps : md.get_group(0))
          ep = md.end_pos(0)
          pos = (ep != nil && ep > pos) ? ep : pos + 1
        return [true, out]
      when "gsub", "sub"
        pat = args[0]
        is_all = nm == "gsub"
        if pat.is_a?(RbString)
          if blk != nil
            return [true, RbString.new(rb_gsub_str_blk(s, pat.data, is_all, blk), recv.encoding)]
          rep = rb_to_s(args[1])
          if is_all
            return [true, RbString.new(s.gsub(pat.data, rep), recv.encoding)]
          idx = s.index(pat.data)
          return [true, recv.dup()] if idx == nil
          return [true, RbString.new(s.slice(0, idx) + rep + s.slice(idx + pat.data.size, s.size - idx - pat.data.size), recv.encoding)]
        if pat.is_a?(RbRegexp)
          return [true, RbString.new(rb_gsub_rx(s, pat, args.size > 1 ? args[1] : nil, is_all, blk), recv.encoding)]
      when "tr" then return [true, RbString.new(s.tr(rb_to_s(args[0]), rb_to_s(args[1])), recv.encoding)]
      when "concat"
        recv.check_mut!
        args.each ->(a) recv.data = recv.data + rb_to_s(a)
        return [true, recv]
      when '[]', "slice"
        if args[0].is_a?(RbRange)
          ch = s.chars
          lo = args[0].lo == nil ? 0 : args[0].lo
          lo = ch.size + lo if lo < 0
          hi = args[0].hi == nil ? ch.size - 1 : args[0].hi
          hi = ch.size + hi if hi < 0
          hi -= 1 if args[0].excl && args[0].hi != nil
          return [true, RbString.new("", recv.encoding)] if lo < 0 || lo >= ch.size || hi < lo
          hi = ch.size - 1 if hi >= ch.size
          return [true, RbString.new(ch.slice(lo, hi - lo + 1).join(""), recv.encoding)]
        if args[0].is_a?(RbRegexp)
          md = args[0].match_str(s)
          @last_match = md
          return [true, md == nil ? nil : md.get_group(args.size > 1 ? args[1] : 0)]
        ch = s.chars
        idx = args[0]
        idx = ch.size + idx if idx < 0
        return [true, nil] if idx < 0 || idx >= ch.size
        if args.size == 1
          return [true, RbString.new(ch[idx], recv.encoding)]
        ln = args[1]
        return [true, nil] if ln < 0
        ln = ch.size - idx if idx + ln > ch.size
        return [true, RbString.new(ch.slice(idx, ln).join(""), recv.encoding)]
      when '[]='
        recv.check_mut!
        idx = args[0]
        rep = rb_to_s(args[args.size - 1])
        ch = s.chars
        idx = ch.size + idx if idx < 0
        ln = args.size == 3 ? args[1] : 1
        pre = idx > 0 ? ch.slice(0, idx).join("") : ""
        suf = (idx + ln) < ch.size ? ch.slice(idx + ln, ch.size - idx - ln).join("") : ""
        recv.data = pre + rep + suf
        return [true, args[args.size - 1]]
      when "to_i" then return [true, rb_parse_int(s.strip, args.size > 0 ? args[0] : 10)]
      when "to_f" then return [true, s.strip.to_f]
      when "to_sym", "intern" then return [true, RbSym.new(s)]
      when "to_r"
        sl = s.index("/")
        return [true, sl != nil ? RbRational.new(s.slice(0, sl).to_i, s.slice(sl + 1, s.size - sl - 1).to_i) : RbRational.new(s.to_i, 1)]

    # --- Symbol ---
    if recv.is_a?(RbSym)
      case nm
      when "to_s", "name" then return [true, RbString.new(recv.name, RB_ENC_UTF8, true)]
      when "to_sym" then return [true, recv]
      when "length", "size" then return [true, recv.name.size]
      when "upcase" then return [true, RbSym.new(recv.name.upcase)]
      when "downcase" then return [true, RbSym.new(recv.name.downcase)]
      when "to_proc"
        snm = recv.name
        return [true, RbProc.new([], nil, env, env.self_obj, true, ->(pargs, pkw) call_method(pargs[0], snm, pargs.size > 1 ? pargs.slice(1, pargs.size - 1) : [], pkw, nil, env), 0)]

    # --- Regexp & MatchData ---
    if recv.is_a?(RbRegexp)
      case nm
      when "source" then return [true, RbString.new(recv.source)]
      when "names"
        out = []
        recv.named_groups.each ->(k, v) out.push(RbString.new(k))
        return [true, out]
      when "match"
        md = recv.match_str(rb_to_s(args[0]), args.size > 1 ? args[1] : 0)
        @last_match = md
        return [true, md != nil && blk != nil ? call_proc(blk, [md]) : md]
      when "match?"
        return [true, recv.match_str(rb_to_s(args[0]), args.size > 1 ? args[1] : 0) != nil]
    if recv.is_a?(RbMatchData)
      case nm
      when '[]' then return [true, recv.get_group(args[0])]
      when "captures" then return [true, recv.captures()]
      when "named_captures" then return [true, recv.named_captures()]
      when "names"
        out = []
        recv.regexp.named_groups.each ->(k, v) out.push(RbString.new(k))
        return [true, out]
      when "begin" then return [true, recv.begin_pos(args.size > 0 ? args[0] : 0)]
      when "end" then return [true, recv.end_pos(args.size > 0 ? args[0] : 0)]
      when "offset"
        gi = args.size > 0 ? args[0] : 0
        return [true, [recv.begin_pos(gi), recv.end_pos(gi)]]
      when "pre_match" then return [true, recv.pre_match()]
      when "post_match" then return [true, recv.post_match()]
      when "to_a" then return [true, recv.to_a()]

    # --- Proc / Lambda ---
    if recv.is_a?(RbProc)
      case nm
      when "call", '[]', "yield" then return [true, call_proc(recv, args, kw)]
      when "lambda?" then return [true, recv.is_lambda]
      when "arity" then return [true, recv.params.size]
      when "curry"
        target_arity = (args.size > 0 && args[0].is_a?(Integer)) ? args[0] : recv.params.size
        return [true, make_curried(recv, [], target_arity, env)]

    # --- Array ---
    if recv.is_a?(Array)
      case nm
      when "length", "size", "count"
        if nm == "count" && (args.size > 0 || blk != nil)
          c = 0
          recv.each ->(x)
            ok = blk != nil ? rb_truthy?(call_proc(blk, [x])) : rb_eq?(x, args[0])
            c += 1 if ok
          return [true, c]
        return [true, recv.size]
      when "empty?" then return [true, recv.size == 0]
      when "first"
        return [true, recv.size == 0 ? nil : recv[0]] if args.size == 0
        return [true, recv.slice(0, args[0] > recv.size ? recv.size : args[0])]
      when "last"
        return [true, recv.size == 0 ? nil : recv[recv.size - 1]] if args.size == 0
        k = args[0] > recv.size ? recv.size : args[0]
        return [true, recv.slice(recv.size - k, k)]
      when "push", "append"
        args.each ->(a) recv.push(a)
        return [true, recv]
      when "pop" then return [true, recv.size == 0 ? nil : recv.pop]
      when "shift" then return [true, recv.size == 0 ? nil : recv.shift]
      when "unshift", "prepend"
        i = args.size - 1
        while i >= 0
          recv.unshift(args[i]); i -= 1
        return [true, recv]
      when '[]'
        if args[0].is_a?(RbRange)
          lo = args[0].lo == nil ? 0 : args[0].lo
          lo = recv.size + lo if lo < 0
          hi = args[0].hi == nil ? recv.size - 1 : args[0].hi
          hi = recv.size + hi if hi < 0
          hi -= 1 if args[0].excl && args[0].hi != nil
          return [true, []] if lo < 0 || lo >= recv.size || hi < lo
          hi = recv.size - 1 if hi >= recv.size
          return [true, recv.slice(lo, hi - lo + 1)]
        idx = args[0]
        idx = recv.size + idx if idx < 0
        return [true, nil] if idx < 0 || idx >= recv.size
        return [true, recv[idx]] if args.size == 1
        ln = args[1]
        ln = recv.size - idx if idx + ln > recv.size
        return [true, recv.slice(idx, ln)]
      when '[]='
        idx = args[0]
        idx = recv.size + idx if idx < 0
        while recv.size <= idx
          recv.push(nil)
        recv[idx] = args[1]
        return [true, args[1]]
      when "fetch"
        idx = args[0]
        idx = recv.size + idx if idx < 0
        return [true, recv[idx]] if idx >= 0 && idx < recv.size
        return [true, call_proc(blk, [args[0]])] if blk != nil
        return [true, args[1]] if args.size >= 2
        raise_exc("IndexError", "index " + args[0].to_s + " outside of array bounds")
      when "dig"
        cur = recv
        args.each ->(k)
          return [true, nil] if cur == nil
          cur = call_method(cur, '[]', [k], {}, nil, env)
        return [true, cur]
      when "join"
        sep = args.size > 0 ? rb_to_s(args[0]) : ""
        parts = []
        recv.each ->(x) parts.push(x.is_a?(Array) ? call_method(x, "join", args, {}, nil, env).data : rb_to_s(x))
        return [true, RbString.new(parts.join(sep))]
      when "reverse"
        out = []; i = recv.size - 1
        while i >= 0
          out.push(recv[i]); i -= 1
        return [true, out]
      when "flatten"
        out = []
        rb_flatten_into(recv, out, args.size > 0 ? args[0] : -1)
        return [true, out]
      when "compact"
        out = []; recv.each ->(x) out.push(x) if x != nil
        return [true, out]
      when "uniq"
        out = []
        recv.each ->(x)
          seen = false
          out.each ->(y) seen = true if rb_eq?(x, y)
          out.push(x) if !seen
        return [true, out]
      when "zip"
        out = []
        i = 0
        while i < recv.size
          row = [recv[i]]
          args.each ->(a) row.push(i < a.size ? a[i] : nil)
          out.push(row)
          i += 1
        return [true, out]
      when "include?"
        recv.each ->(x) return [true, true] if rb_eq?(x, args[0])
        return [true, false]
      when "index"
        i = 0
        while i < recv.size
          ok = blk != nil ? rb_truthy?(call_proc(blk, [recv[i]])) : rb_eq?(recv[i], args[0])
          return [true, i] if ok
          i += 1
        return [true, nil]
      when "sum"
        acc = args.size > 0 ? args[0] : 0
        recv.each ->(x)
          v = blk != nil ? call_proc(blk, [x]) : x
          acc = rb_num_add(acc, v)
        return [true, acc]
      when "sort"
        return [true, rb_sort_array(recv, blk)]
      when "sort_by"
        pairs = []
        recv.each ->(x) pairs.push([call_proc(blk, [x]), x])
        sorted = rb_sort_pairs(pairs)
        return [true, sorted.map ->(p) p[1]]
      when "min", "max"
        return [true, nil] if recv.size == 0
        best = recv[0]
        i = 1
        while i < recv.size
          c = blk != nil ? call_proc(blk, [recv[i], best]) : rb_cmp(recv[i], best)
          best = recv[i] if (nm == "min" ? c < 0 : c > 0)
          i += 1
        return [true, best]
      when "each"
        return [true, RbEnumerator.new(recv)] if blk == nil
        recv.each ->(x)
          begin
            call_proc(blk, [x])
          rescue sig
            return [true, sig.val] if sig.is_a?(RbSignal) && sig.kind == :break
            raise sig
        return [true, recv]
      when "each_with_index"
        i = 0
        while i < recv.size
          begin
            call_proc(blk, [recv[i], i])
          rescue sig
            return [true, sig.val] if sig.is_a?(RbSignal) && sig.kind == :break
            raise sig
          i += 1
        return [true, recv]
      when "map", "collect"
        out = []
        recv.each ->(x)
          begin
            out.push(call_proc(blk, [x]))
          rescue sig
            return [true, sig.val] if sig.is_a?(RbSignal) && sig.kind == :break
            raise sig
        return [true, out]
      when "filter_map"
        out = []
        recv.each ->(x)
          r = call_proc(blk, [x])
          out.push(r) if rb_truthy?(r)
        return [true, out]
      when "flat_map", "collect_concat"
        out = []
        recv.each ->(x)
          r = call_proc(blk, [x])
          if r.is_a?(Array)
            r.each ->(e) out.push(e)
          else
            out.push(r)
        return [true, out]
      when "select", "filter", "find_all"
        out = []
        recv.each ->(x) out.push(x) if rb_truthy?(call_proc(blk, [x]))
        return [true, out]
      when "reject"
        out = []
        recv.each ->(x) out.push(x) if !rb_truthy?(call_proc(blk, [x]))
        return [true, out]
      when "find", "detect"
        recv.each ->(x) return [true, x] if rb_truthy?(call_proc(blk, [x]))
        return [true, nil]
      when "reduce", "inject"
        acc = nil
        start = 0
        sym_op = nil
        if args.size == 2
          acc = args[0]; sym_op = rb_to_s(args[1])
        elsif args.size == 1 && blk == nil && (args[0].is_a?(RbSym) || args[0].is_a?(RbString))
          sym_op = rb_to_s(args[0]); acc = recv.size > 0 ? recv[0] : nil; start = 1
        elsif args.size == 1
          acc = args[0]
        else
          acc = recv.size > 0 ? recv[0] : nil; start = 1
        i = start
        while i < recv.size
          acc = sym_op != nil ? eval_binop(sym_op, acc, recv[i], env) : call_proc(blk, [acc, recv[i]])
          i += 1
        return [true, acc]
      when "any?"
        recv.each ->(x) return [true, true] if (blk != nil ? rb_truthy?(call_proc(blk, [x])) : rb_truthy?(x))
        return [true, false]
      when "all?"
        recv.each ->(x) return [true, false] if !(blk != nil ? rb_truthy?(call_proc(blk, [x])) : rb_truthy?(x))
        return [true, true]
      when "none?"
        recv.each ->(x) return [true, false] if (blk != nil ? rb_truthy?(call_proc(blk, [x])) : rb_truthy?(x))
        return [true, true]
      when "group_by"
        h = RbHash.new
        recv.each ->(x)
          gk = call_proc(blk, [x])
          arr = h.has_key?(gk) ? h.get(gk) : []
          arr.push(x)
          h.set(gk, arr)
        return [true, h]
      when "tally"
        h = RbHash.new
        recv.each ->(x) h.set(x, (h.has_key?(x) ? h.get(x) : 0) + 1)
        return [true, h]
      when "partition"
        t_arr = []; f_arr = []
        recv.each ->(x)
          if rb_truthy?(call_proc(blk, [x])) then t_arr.push(x) else f_arr.push(x)
        return [true, [t_arr, f_arr]]
      when "take" then return [true, recv.slice(0, args[0] > recv.size ? recv.size : args[0])]
      when "drop" then return [true, args[0] >= recv.size ? [] : recv.slice(args[0], recv.size - args[0])]
      when "to_h"
        h = RbHash.new
        recv.each ->(x)
          pair = blk != nil ? call_proc(blk, [x]) : x
          h.set(pair[0], pair[1]) if pair.is_a?(Array) && pair.size >= 2
        return [true, h]
      when "to_a" then return [true, recv]

    # --- Hash ---
    if recv.is_a?(RbHash)
      case nm
      when "size", "length" then return [true, recv.size]
      when "empty?" then return [true, recv.size == 0]
      when '[]'
        return [true, recv.get(args[0])] if recv.has_key?(args[0])
        return [true, call_proc(recv.default_proc, [recv, args[0]])] if recv.default_proc != nil
        return [true, recv.default_val]
      when '[]=' then return [true, recv.set(args[0], args[1])]
      when "fetch"
        return [true, recv.get(args[0])] if recv.has_key?(args[0])
        return [true, call_proc(blk, [args[0]])] if blk != nil
        return [true, args[1]] if args.size >= 2
        raise_exc("KeyError", "key not found: " + rb_inspect(args[0]))
      when "dig"
        cur = recv
        args.each ->(k)
          return [true, nil] if cur == nil
          cur = call_method(cur, '[]', [k], {}, nil, env)
        return [true, cur]
      when "key?", "has_key?", "include?" then return [true, recv.has_key?(args[0])]
      when "keys" then return [true, recv.keys()]
      when "values" then return [true, recv.values()]
      when "delete" then return [true, recv.delete(args[0])]
      when "merge"
        out = recv.dup()
        args.each ->(o)
          if o.is_a?(RbHash)
            o.entries.each ->(p)
              if blk != nil && out.has_key?(p[0])
                out.set(p[0], call_proc(blk, [p[0], out.get(p[0]), p[1]]))
              else
                out.set(p[0], p[1])
        return [true, out]
      when "each", "each_pair"
        recv.entries.each ->(p) call_proc(blk, [p[0], p[1]])
        return [true, recv]
      when "map", "collect"
        out = []
        recv.entries.each ->(p) out.push(call_proc(blk, [p[0], p[1]]))
        return [true, out]
      when "select", "filter"
        out = RbHash.new
        recv.entries.each ->(p) out.set(p[0], p[1]) if rb_truthy?(call_proc(blk, [p[0], p[1]]))
        return [true, out]
      when "transform_values"
        out = RbHash.new
        recv.entries.each ->(p) out.set(p[0], call_proc(blk, [p[1]]))
        return [true, out]
      when "transform_keys"
        out = RbHash.new
        recv.entries.each ->(p) out.set(call_proc(blk, [p[0]]), p[1])
        return [true, out]
      when "slice"
        out = RbHash.new
        args.each ->(k) out.set(k, recv.get(k)) if recv.has_key?(k)
        return [true, out]
      when "to_a"
        out = []
        recv.entries.each ->(p) out.push([p[0], p[1]])
        return [true, out]

    # --- Range ---
    if recv.is_a?(RbRange)
      case nm
      when "begin", "first" then return [true, recv.lo]
      when "end", "last" then return [true, recv.hi]
      when "exclude_end?" then return [true, recv.excl]
      when "include?", "cover?", "member?" then return [true, recv.include?(args[0])]
      when "to_a" then return [true, recv.to_a()]
      when "each", "map", "select", "reject", "reduce", "inject", "sum", "count", "any?", "all?", "find", "take", "drop"
        return dispatch_builtin(recv.to_a(), nm, args, kw, blk, env)

    # --- Enumerator ---
    if recv.is_a?(RbEnumerator)
      case nm
      when "next"
        raise_exc("StopIteration", "iteration reached an end") if recv.idx >= recv.items.size
        v = recv.items[recv.idx]
        recv.idx += 1
        return [true, v]
      when "peek"
        raise_exc("StopIteration", "iteration reached an end") if recv.idx >= recv.items.size
        return [true, recv.items[recv.idx]]
      when "rewind"
        recv.idx = 0
        return [true, recv]
      when "to_a" then return [true, recv.items]
      when "each", "map", "select", "take", "with_index"
        if nm == "with_index"
          off = args.size > 0 ? args[0] : 0
          out = []
          i = 0
          while i < recv.items.size
            out.push(blk != nil ? call_proc(blk, [recv.items[i], i + off]) : [recv.items[i], i + off])
            i += 1
          return [true, blk != nil ? recv : RbEnumerator.new(out)]
        return dispatch_builtin(recv.items, nm, args, kw, blk, env)

    # --- Exception ---
    if recv.is_a?(RbException)
      return [true, RbString.new(recv.message)] if nm == "message"
      return [true, recv.backtrace] if nm == "backtrace"

    # --- Kernel / Object universal methods ---
    case nm
    when "puts"
      if args.size == 0
        @stdout.push("")
      else
        args.each ->(a)
          if a.is_a?(Array)
            a.each ->(x) @stdout.push(rb_to_s(x))
          else
            @stdout.push(rb_to_s(a))
      return [true, nil]
    when "print"
      args.each ->(a) @stdout.push(rb_to_s(a))
      return [true, nil]
    when "p"
      args.each ->(a) @stdout.push(rb_inspect(a))
      return [true, args.size == 1 ? args[0] : args]
    when "raise", "fail"
      if args.size == 0
        raise_exc("RuntimeError", "")
      elsif args[0].is_a?(RbException)
        @last_exc = args[0]
        raise RbSignal.new(:raise, nil, 0, args[0])
      elsif args[0].is_a?(RbClass)
        raise_exc(args[0].name, args.size > 1 ? rb_to_s(args[1]) : "")
      else
        raise_exc("RuntimeError", rb_to_s(args[0]))
    when "lambda" then return [true, RbProc.new(blk.params, blk.body, blk.env, blk.self_obj, true, blk.native_fn, blk.def_frame_id)]
    when "proc" then return [true, blk]
    when "block_given?" then return [true, env.block != nil]
    when "Rational" then return [true, RbRational.new(args[0], args.size > 1 ? args[1] : 1)]
    when "Complex" then return [true, RbComplex.new(args[0], args.size > 1 ? args[1] : 0)]
    when "Integer" then return [true, args[0].is_a?(Integer) ? args[0] : rb_parse_int(rb_to_s(args[0]).strip, args.size > 1 ? args[1] : 10)]
    when "Float" then return [true, args[0].is_a?(Float) ? args[0] : rb_to_s(args[0]).strip.to_f]
    when "String" then return [true, RbString.new(rb_to_s(args[0]))]
    when "Array" then return [true, args[0].is_a?(Array) ? args[0] : (args[0] == nil ? [] : [args[0]])]
    when "sprintf", "format" then return [true, rb_sprintf(rb_to_s(args[0]), args.slice(1, args.size - 1))]
    when "eval" then return [true, eval_node(rb_parse(rb_to_s(args[0])), env)]
    when "`"
      cmd = rb_to_s(args[0])
      out = ""
      begin
        out = OS.capture(cmd)
      rescue e
        out = ""
      return [true, RbString.new(out == nil ? "" : out)]
    when "catch"
      tag = args.size > 0 ? args[0] : RbObject.new(@c_object)
      begin
        return [true, call_proc(blk, [tag])]
      rescue sig
        if sig.is_a?(RbSignal) && sig.kind == :throw && rb_eql?(sig.exc, tag)
          return [true, sig.val]
        raise sig
    when "throw"
      tag = args.size > 0 ? args[0] : nil
      val = args.size > 1 ? args[1] : nil
      raise RbSignal.new(:throw, val, 0, tag)
    when "instance_eval"
      if blk != nil
        ienv = RbEnv.new(blk.env, recv, blk.env.block, blk.def_frame_id, recv.is_a?(RbModule) ? [recv] : blk.env.cref)
        return [true, eval_stmts(blk.body, ienv)]
      if args.size > 0
        ienv = RbEnv.new(env, recv, nil, env.frame_id, recv.is_a?(RbModule) ? [recv] : env.cref)
        return [true, eval_node(rb_parse(rb_to_s(args[0])), ienv)]
      return [true, nil]
    when "dup", "clone"
      return [true, recv.dup()] if recv.is_a?(RbString) || recv.is_a?(RbHash)
      return [true, recv.dup] if recv.is_a?(Array)
      return [true, recv]
    when "class" then return [true, class_of(recv)]
    when "is_a?", "kind_of?"
      c = class_of(recv)
      return [true, args[0].is_a?(RbModule) && c.ancestors().include?(args[0])]
    when "instance_of?" then return [true, class_of(recv) == args[0]]
    when "nil?" then return [true, recv == nil]
    when "to_s" then return [true, RbString.new(rb_to_s(recv))]
    when "inspect" then return [true, RbString.new(rb_inspect(recv))]
    when "respond_to?"
      tn = rb_to_s(args[0])
      return [true, lookup_method_on(recv, tn) != nil]
    when "send", "public_send", "__send__"
      return [true, call_method(recv, rb_to_s(args[0]), args.slice(1, args.size - 1), kw, blk, env)]
    when "tap"
      call_proc(blk, [recv]) if blk != nil
      return [true, recv]
    when "then", "yield_self"
      return [true, blk != nil ? call_proc(blk, [recv]) : RbEnumerator.new([recv])]
    when "itself" then return [true, recv]
    when "extend"
      sc = singleton_class_of(recv)
      args.each ->(m) sc.includes.unshift(m) if m.is_a?(RbModule)
      return [true, recv]
    when "freeze"
      recv.frozen = true if recv.is_a?(RbObject) || recv.is_a?(RbString)
      return [true, recv]
    when "frozen?"
      return [true, recv.frozen] if recv.is_a?(RbObject) || recv.is_a?(RbString)
      return [true, recv.is_a?(Integer) || recv.is_a?(Float) || recv.is_a?(RbSym) || recv == nil || recv == true || recv == false]
    when "eql?" then return [true, rb_eql?(recv, args[0])]
    when "equal?" then return [true, recv == args[0]]
    when "instance_variable_get"
      return [true, recv.is_a?(RbObject) ? recv.ivars[rb_to_s(args[0])] : nil]
    when "instance_variable_set"
      recv.ivars[rb_to_s(args[0])] = args[1] if recv.is_a?(RbObject)
      return [true, args[1]]
    else
      return [false, nil]

  -> make_curried(pr, bound, arity, env)
    cfn = ->(pargs, pkw)
      all = bound + pargs
      if all.size >= arity
        call_proc(pr, all, pkw)
      else
        make_curried(pr, all, arity, env)
    RbProc.new([], nil, env, env.self_obj, true, cfn, 0)

  -> rb_flatten_into(arr, out, depth)
    arr.each ->(x)
      if x.is_a?(Array) && depth != 0
        rb_flatten_into(x, out, depth < 0 ? -1 : depth - 1)
      else
        out.push(x)

  -> rb_sort_array(arr, blk)
    out = arr.dup
    # Insertion/merge sort using Ruby <=> or block
    i = 1
    while i < out.size
      key = out[i]
      j = i - 1
      while j >= 0
        c = blk != nil ? call_proc(blk, [out[j], key]) : rb_cmp(out[j], key)
        break if c <= 0
        out[j + 1] = out[j]
        j -= 1
      out[j + 1] = key
      i += 1
    out

  -> rb_sort_pairs(pairs)
    out = pairs.dup
    i = 1
    while i < out.size
      key = out[i]
      j = i - 1
      while j >= 0 && rb_cmp(out[j][0], key[0]) > 0
        out[j + 1] = out[j]
        j -= 1
      out[j + 1] = key
      i += 1
    out

  -> rb_gsub_str_blk(s, pat, is_all, blk)
    return s if pat.size == 0
    out = StringBuffer()
    pos = 0
    while pos <= s.size
      idx = s.index(pat, pos)
      if idx == nil
        out << s.slice(pos, s.size - pos)
        break
      out << s.slice(pos, idx - pos)
      out << rb_to_s(call_proc(blk, [RbString.new(pat)]))
      pos = idx + pat.size
      if !is_all
        out << s.slice(pos, s.size - pos)
        break
    out.to_s

  -> rb_gsub_rx(s, rx, rep_arg, is_all, blk)
    out = StringBuffer()
    pos = 0
    while pos <= s.size
      md = rx.match_str(s, pos)
      if md == nil
        out << s.slice(pos, s.size - pos)
        break
      @last_match = md
      bp = md.begin_pos(0)
      ep = md.end_pos(0)
      out << s.slice(pos, bp - pos)
      if blk != nil
        out << rb_to_s(call_proc(blk, [md.get_group(0)]))
      else
        rs = rb_to_s(rep_arg)
        # Support \1..\9 backreferences in replacement string
        ri = 0
        while ri < rs.size
          if rs.byte_at(ri) == 92 && ri + 1 < rs.size
            nb = rs.byte_at(ri + 1)
            if nb >= 49 && nb <= 57
              gv = md.get_group(nb - 48)
              out << (gv == nil ? "" : gv.data)
              ri += 2
              next
          out << rs.slice(ri, 1)
          ri += 1
      pos = ep > pos ? ep : pos + 1
      if !is_all
        out << s.slice(pos, s.size - pos)
        break
    out.to_s

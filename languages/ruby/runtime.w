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
  return RB_ENC_UTF8 if u == "UTF-8" || u == "UTF8" || u == "LOCALE" || u == "EXTERNAL" || u == "FILESYSTEM"
  return RB_ENC_ASCII if u == "US-ASCII" || u == "ASCII" || u == "ANSI_X3.4-1968"
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

RB_EMPTY_KW = {}

-> rb_fast_str_to_i(s)
  n = s.size ## i64
  return 0 if n == 0
  i = 0 ## i64
  while i < n
    b = s.byte_at(i) ## i64
    break if b != 32 && b != 9 && b != 10 && b != 13
    i += 1
  return 0 if i >= n
  neg = false
  b0 = s.byte_at(i) ## i64
  if b0 == 45
    neg = true
    i += 1
  elsif b0 == 43
    i += 1
  acc = 0 ## i64
  digits = 0 ## i64
  while i < n
    d = (s.byte_at(i) ## i64) - 48
    if d >= 0 && d <= 9
      if digits >= 18
        return rb_parse_int(s.strip, 10)
      acc = acc * 10 + d
      digits += 1
      i += 1
    elsif d == 47 # '_'
      return rb_parse_int(s.strip, 10)
    else
      break
  neg ? -acc : acc

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
    return [] if @lo == nil || @hi == nil
    if @lo.is_a?(Integer) && @hi.is_a?(Integer)
      lo_i = @lo ## i64
      hi_i = @hi ## i64
      len = (@excl ? (hi_i - lo_i) : (hi_i - lo_i + 1)) ## i64
      return [] if len <= 0
      raise "Range too large for to_a" if len > 2000000
      out = Array.new(len, nil)
      k = 0 ## i64
      while k < len
        out[k] = lo_i + k
        k += 1
      return out
    out = []
    if @lo.is_a?(RbString) && @hi.is_a?(RbString) && @lo.data.size == 1 && @hi.data.size == 1
      c = @lo.data.byte_at(0)
      e = @hi.data.byte_at(0)
      while @excl ? (c < e) : (c <= e)
        out.push(RbString.new(c.chr))
        c += 1
    out

  -> include?(v)
    if @lo != nil
      c1 = rb_cmp(v, @lo)
      return false if c1 == nil || c1 < 0
    return true if @hi == nil
    c2 = rb_cmp(v, @hi)
    return false if c2 == nil
    @excl ? c2 < 0 : c2 <= 0

  -> ==(o)
    o.is_a?(RbRange) && @lo == o.lo && @hi == o.hi && @excl == o.excl

# ---- Ruby Regexp & MatchData (backed directly by Tungsten core/regex — native (?<name>...), /x, lookbehind, atomic, possessive!) ----

+ RbRegexp
  ro :source, :flags, :compiled, :named_groups, :compile_err

  -> new(@source, @flags = "")
    @named_groups = {}
    @compile_err = nil
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
    begin
      @compiled = Regex.new(@source, opts)
    rescue e
      @compiled = nil
      @compile_err = e.to_s

  -> match_str(s, pos = 0)
    return nil if @compiled == nil
    sub = pos > 0 ? (pos >= s.size ? "" : s.slice(pos, s.size - pos)) : s
    m = nil
    begin
      m = @compiled.match_data(sub)
    rescue e
      return nil
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
    if idx.is_a?(RbSym)
      gi = @regexp.named_groups[idx.name]
      return nil if gi == nil
      idx = gi
    elsif idx.is_a?(RbString)
      gi = @regexp.named_groups[idx.data]
      return nil if gi == nil
      idx = gi
    elsif idx.is_a?(String)
      gi = @regexp.named_groups[idx]
      return nil if gi == nil
      idx = gi
    v = nil
    begin
      v = @md[idx]
    rescue e
      return nil
    v == nil ? nil : RbString.new(v)

  -> captures
    out = []
    i = 1
    while true
      v = nil
      off = nil
      begin
        v = @md[i]
        off = @md.offset(i)
      rescue e
        break
      break if v == nil && off == nil
      out.push(v == nil ? nil : RbString.new(v))
      i += 1
    out

  -> named_captures
    h = RbHash.new
    @regexp.named_groups.each ->(nm, gi)
      h.set(RbString.new(nm), get_group(gi))
    h

  -> begin_pos(i = 0)
    b = nil
    begin
      b = @md.begin_offset(i)
    rescue e
      return nil
    b == nil ? nil : b + @offset_shift

  -> end_pos(i = 0)
    e = nil
    begin
      e = @md.end_offset(i)
    rescue err
      return nil
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
    "#<MatchData " + rb_inspect(RbString.new(to_s())) + ">"

# ---- Ruby Hash (order-preserving, supporting arbitrary Ruby keys + default value/proc) ----

+ RbHash
  rw :entries, :default_val, :default_proc, :ruby2_kw

  -> new
    @entries = []   # [[k, v], ...]
    @default_val = nil
    @default_proc = nil
    @ruby2_kw = false

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
    eq_d(o, 0)

  -> eq_d(o, depth)
    return true if depth > 16
    return false if !o.is_a?(RbHash) || @entries.size != o.entries.size
    i = 0
    while i < @entries.size
      idx = o.find_idx(@entries[i][0])
      return false if idx < 0 || !rb_eq?(@entries[i][1], o.entries[idx][1], depth + 1)
      i += 1
    true

# ---- Ruby Objects, Classes, Modules, Methods, Procs, Exceptions ----

+ RbMethod
  ro :name, :params, :body, :def_env, :owner, :native_fn
  rw :bytecode, :bc_tried, :is_closure

  -> new(@name, @params, @body, @def_env, @owner = nil, @native_fn = nil, @is_closure = false)
    @bytecode = nil
    @bc_tried = false

+ RbProc
  ro :params, :body, :env, :self_obj, :is_lambda, :native_fn, :def_frame_id
  rw :bytecode, :bc_tried

  -> new(@params, @body, @env, @self_obj, @is_lambda = false, @native_fn = nil, @def_frame_id = 0)
    @bytecode = nil
    @bc_tried = false

+ RbModule
  rw :name, :methods, :constants, :cvars, :ivars, :prepends, :includes, :singleton_cls, :mod_fn_mode

  -> new(@name)
    @methods = {}
    @constants = {}
    @cvars = {}
    @ivars = {}
    @prepends = []
    @includes = []
    @singleton_cls = nil
    @mod_fn_mode = false

  -> ancestors
    out = []
    @prepends.each ->(m) m.ancestors().each ->(a) out.push(a) if !out.include?(a)
    out.push(self)
    @includes.each ->(m) m.ancestors().each ->(a) out.push(a) if !out.include?(a)
    out

  # Zero-allocation method lookup across prepends -> self -> includes.
  -> lookup_method(nm)
    if @prepends.size > 0
      pi = 0
      while pi < @prepends.size
        m = @prepends[pi].lookup_method(nm)
        return m if m != nil
        pi += 1
    if @methods.size > 0
      m = @methods[nm]
      return m if m != nil
    if @includes.size > 0
      ii = 0
      while ii < @includes.size
        m = @includes[ii].lookup_method(nm)
        return m if m != nil
        ii += 1
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

  # Zero-allocation MRO lookup across prepends -> self -> includes -> superclass chain.
  -> lookup_method(nm)
    cur = self
    while cur != nil
      if cur.prepends.size > 0
        pi = 0
        while pi < cur.prepends.size
          m = cur.prepends[pi].lookup_method(nm)
          return m if m != nil
          pi += 1
      if cur.methods.size > 0
        m = cur.methods[nm]
        return m if m != nil
      if cur.includes.size > 0
        ii = 0
        while ii < cur.includes.size
          m = cur.includes[ii].lookup_method(nm)
          return m if m != nil
          ii += 1
      cur = cur.is_a?(RbClass) ? cur.superclass : nil
    nil

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
    inspect_d(0)

  -> inspect_d(depth)
    return "#<" + @klass.name + ":...>" if depth > 5
    if @ivars.size == 0
      return "#<" + @klass.name + ">"
    ks = @ivars.keys
    parts = []
    i = 0
    while i < ks.size
      k = ks[i]
      if !k.starts_with?("__")
        v = @ivars[k]
        vs = v == self ? "#<" + @klass.name + ":...>" : rb_inspect(v, depth + 1)
        parts.push(k + "=" + vs)
      i += 1
    return "#<" + @klass.name + ">" if parts.size == 0
    "#<" + @klass.name + " " + parts.join(", ") + ">"

+ RbBinding
  rw :env

  -> new(@env)

  -> to_s
    "#<Binding>"

  -> inspect
    "#<Binding>"

+ RbStringIO
  rw :buf, :pos, :closed, :encoding

  -> new(s = "")
    @buf = s
    @pos = 0
    @closed = false
    @encoding = RB_ENC_UTF8

  -> to_s
    "#<StringIO>"

  -> inspect
    "#<StringIO>"

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
  rw :items, :idx, :recv_obj, :meth_name, :enum_args, :gen_proc

  -> new(@items = nil, @recv_obj = nil, @meth_name = "each", @enum_args = nil, @gen_proc = nil)
    @idx = 0

# ---- Lexical Scope Environment ----

+ RbEnv
  rw :vars, :parent, :self_obj, :block, :frame_id, :cref, :def_target

  -> new(@parent = nil, @self_obj = nil, @block = nil, @frame_id = 0, @cref = nil, @def_target = nil)
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

-> rb_str_hash(s)
  h = 5381
  i = 0
  n = s.size
  while i < n
    h = ((h << 5) + h + s.byte_at(i)) & 0x7FFFFFFFFFFFFFFF
    i += 1
  h

-> rb_hash_code(v, depth = 0)
  return 0 if v == nil
  return 1 if v == true
  return 2 if v == false
  return v if v.is_a?(Integer)
  return (v != v ? 9999991 : rb_str_hash(rb_float_to_s(v))) if v.is_a?(Float)
  return rb_str_hash(v.data) if v.is_a?(RbString)
  return rb_str_hash(v.name) ^ 0x55555555 if v.is_a?(RbSym)
  if v.is_a?(RbRational)
    return v.num if v.den == 1
    return (rb_hash_code(v.num) * 31) ^ rb_hash_code(v.den)
  if v.is_a?(RbComplex)
    return rb_hash_code(v.real) if v.imag == 0
    return (rb_hash_code(v.real) * 37) ^ rb_hash_code(v.imag)
  return 42 if depth > 6
  if v.is_a?(Array)
    h = 17
    i = 0
    while i < v.size
      h = ((h * 31) ^ rb_hash_code(v[i], depth + 1)) & 0x7FFFFFFFFFFFFFFF
      i += 1
    return h
  if v.is_a?(RbHash)
    h = 23
    i = 0
    while i < v.entries.size
      p = v.entries[i]
      h = (h ^ ((rb_hash_code(p[0], depth + 1) * 31) ^ rb_hash_code(p[1], depth + 1))) & 0x7FFFFFFFFFFFFFFF
      i += 1
    return h
  if v.is_a?(RbRange)
    return ((rb_hash_code(v.lo, depth + 1) * 31) ^ rb_hash_code(v.hi, depth + 1) ^ (v.excl ? 1 : 0)) & 0x7FFFFFFFFFFFFFFF
  if v.is_a?(RbRegexp)
    return rb_str_hash(v.source + "/" + v.flags)
  wvalue_bits(v) ## int

-> rb_eql?(a, b, depth = 0)
  return true if a == b
  return true if depth > 16
  return a.data == b.data if a.is_a?(RbString) && b.is_a?(RbString)
  return a.name == b.name if a.is_a?(RbSym) && b.is_a?(RbSym)
  return a == b if a.is_a?(RbRational) && b.is_a?(RbRational)
  return a == b if a.is_a?(RbComplex) && b.is_a?(RbComplex)
  return a == b if a.is_a?(RbRange) && b.is_a?(RbRange)
  return a.eq_d(b, depth + 1) if a.is_a?(RbHash) && b.is_a?(RbHash)
  return a.source == b.source && a.flags == b.flags if a.is_a?(RbRegexp) && b.is_a?(RbRegexp)
  if a.is_a?(Array) && b.is_a?(Array)
    return false if a.size != b.size
    i = 0
    while i < a.size
      return false if !rb_eql?(a[i], b[i], depth + 1)
      i += 1
    return true
  false

-> rb_eq?(a, b, depth = 0)
  return true if rb_eql?(a, b)
  return true if depth > 16
  if a.is_a?(Array) && b.is_a?(Array)
    return false if a.size != b.size
    i = 0
    while i < a.size
      return false if !rb_eq?(a[i], b[i], depth + 1)
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

-> rb_cmp(a, b, depth = 0)
  return 0 if depth > 16
  if a.is_a?(Integer) && b.is_a?(Integer)
    return a < b ? -1 : (a > b ? 1 : 0)
  if (a.is_a?(Integer) || a.is_a?(Float) || a.is_a?(RbRational)) &&
     (b.is_a?(Integer) || b.is_a?(Float) || b.is_a?(RbRational))
    fa = rb_to_f(a)
    fb = rb_to_f(b)
    return nil if fa != fa || fb != fb
    return fa < fb ? -1 : (fa > fb ? 1 : 0)
  if a.is_a?(RbString) && b.is_a?(RbString)
    return a.data < b.data ? -1 : (a.data > b.data ? 1 : 0)
  if a.is_a?(RbSym) && b.is_a?(RbSym)
    return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0)
  if a.is_a?(Array) && b.is_a?(Array)
    n = a.size < b.size ? a.size : b.size
    i = 0
    while i < n
      c = rb_cmp(a[i], b[i], depth + 1)
      return nil if c == nil
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

-> rb_inspect(v, depth = 0)
  return "nil" if v == nil
  return "true" if v == true
  return "false" if v == false
  return rb_float_to_s(v) if v.is_a?(Float)
  return "main" if v.is_a?(RbObject) && v.ivars["__is_main__"] == true
  return v.inspect_d(depth) if v.is_a?(RbObject) && !v.is_a?(RbException)
  return v.inspect if v.is_a?(RbString) || v.is_a?(RbSym) || v.is_a?(RbRational) || v.is_a?(RbComplex) || v.is_a?(RbRange) || v.is_a?(RbRegexp) || v.is_a?(RbMatchData) || v.is_a?(RbEncoding) || v.is_a?(RbModule) || v.is_a?(RbException) || v.is_a?(RbBinding) || v.is_a?(RbStringIO)
  if v.is_a?(Array)
    return '[...]' if depth > 6
    parts = []
    i = 0
    while i < v.size
      parts.push(rb_inspect(v[i], depth + 1))
      i += 1
    return '[' + parts.join(", ") + ']'
  if v.is_a?(RbHash)
    return "{...}" if depth > 6
    parts = []
    i = 0
    while i < v.entries.size
      p = v.entries[i]
      if p[0].is_a?(RbSym)
        parts.push(p[0].name + ": " + rb_inspect(p[1], depth + 1))
      else
        parts.push(rb_inspect(p[0], depth + 1) + " => " + rb_inspect(p[1], depth + 1))
      i += 1
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
  rw :globals, :constants, :stdout, :out_buf, :next_frame_id, :tungsten_fns, :max_steps, :steps, :method_epoch, :reg_stack, :call_depth, :load_path, :loaded_features, :file_stack
  ro :c_basic_object, :c_object, :c_module, :c_class, :c_kernel, :c_comparable, :c_enumerable
  ro :c_true_class, :c_false_class, :c_nil_class
  ro :c_numeric, :c_integer, :c_float, :c_rational, :c_complex, :c_string, :c_symbol
  ro :c_array, :c_hash, :c_range, :c_regexp, :c_match_data, :c_proc, :c_exception
  ro :c_standard_error, :c_struct, :c_data, :c_encoding, :c_enumerator, :c_math, :c_json, :c_tungsten
  ro :c_io, :c_file, :c_dir, :c_file_test, :c_time, :c_method, :c_unbound_method, :c_binding, :c_errno, :c_env_obj
  ro :main_obj, :top_env

  -> new
    @globals = {}
    @constants = {}
    @stdout = []
    @out_buf = StringBuffer()
    @next_frame_id = 1
    @tungsten_fns = {}
    @last_match = nil
    @last_exc = nil
    @steps = 0
    @max_steps = 0
    @call_depth = 0
    @method_epoch = 1
    @reg_stack = Array.new(16384, nil)
    @load_path = []
    @loaded_features = []
    @file_stack = ["(eval)"]
    @catch_tags = []
    @active_frames = {}
    @global_aliases = {}
    @at_exit_blocks = []
    @flipflops = {}
    @singleton_map = {}
    @is_main_eval = false
    init_core_classes()
    @main_obj = RbObject.new(@c_object)
    @main_obj.ivars["__is_main__"] = true
    @top_env = RbEnv.new(nil, @main_obj, nil, 0, [@c_object])
    @toplevel_binding = RbBinding.new(@top_env)
    @c_object.constants["TOPLEVEL_BINDING"] = @toplevel_binding
    @constants["TOPLEVEL_BINDING"] = @toplevel_binding
    @globals["$:"] = @load_path
    @globals["$LOAD_PATH"] = @load_path
    @globals["$\""] = @loaded_features
    @globals["$LOADED_FEATURES"] = @loaded_features
    @globals["$0"] = RbString.new("tungsten-ruby")
    @globals["$PROGRAM_NAME"] = @globals["$0"]
    @globals["$VERBOSE"] = false
    @globals["$DEBUG"] = false
    @globals["$/"] = RbString.new("\n")
    @globals["$\\"] = nil
    @globals["$,"] = nil
    @globals["$;"] = nil
    @globals["$$"] = 1
    @globals["$stdout"] = RbObject.new(@c_io)
    @globals["$stderr"] = RbObject.new(@c_io)
    @globals["$stdin"] = RbObject.new(@c_io)
    @c_object.constants["STDOUT"] = @globals["$stdout"]
    @c_object.constants["STDERR"] = @globals["$stderr"]
    @c_object.constants["STDIN"] = @globals["$stdin"]
    @constants["STDOUT"] = @globals["$stdout"]
    @constants["STDERR"] = @globals["$stderr"]
    @constants["STDIN"] = @globals["$stdin"]
    @c_object.constants["ARGV"] = []
    @constants["ARGV"] = @c_object.constants["ARGV"]
    @c_env_obj = RbObject.new(@c_object)
    @c_env_obj.ivars["__is_env__"] = true
    @c_object.constants["ENV"] = @c_env_obj
    @constants["ENV"] = @c_env_obj

  -> init_core_classes
    @c_basic_object = RbClass.new("BasicObject", nil)
    @c_object = RbClass.new("Object", @c_basic_object)
    @c_kernel = RbModule.new("Kernel")
    @c_object.includes.push(@c_kernel)
    @c_module = RbClass.new("Module", @c_object)
    inc_fn = ->(r, aa, kk, bb)
      aa.each ->(m) r.includes.unshift(m) if m.is_a?(RbModule)
      r
    @c_module.methods["include"] = RbMethod.new("include", [], nil, nil, @c_module, inc_fn)
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
    @c_stringio = RbClass.new("StringIO", @c_object)
    @c_stringio.includes.push(@c_enumerable)
    @c_encoding.constants["UTF_8"] = RB_ENC_UTF8
    @c_encoding.constants["US_ASCII"] = RB_ENC_ASCII
    @c_encoding.constants["ASCII"] = RB_ENC_ASCII
    @c_encoding.constants["ASCII_8BIT"] = RB_ENC_BINARY
    @c_encoding.constants["BINARY"] = RB_ENC_BINARY
    ["EUC_JP", "Windows_31J", "Shift_JIS", "ISO_8859_1", "UTF_16LE", "UTF_16BE", "UTF_32LE", "UTF_32BE", "CP1252", "IBM437", "KOI8_R", "Big5", "GBK", "UTF_7"].each ->(enm)
      @c_encoding.constants[enm] = RbEncoding.new(enm.gsub("_", "-"))
    @c_enumerator = RbClass.new("Enumerator", @c_object)
    @c_enumerator.includes.push(@c_enumerable)
    @c_math = RbModule.new("Math")
    @c_math.constants["PI"] = ~3.141592653589793
    @c_math.constants["E"] = ~2.718281828459045
    @c_json = RbModule.new("JSON")
    @c_tungsten = RbModule.new("Tungsten")
    @c_io = RbClass.new("IO", @c_object)
    @c_io.includes.push(@c_enumerable)
    @c_file = RbClass.new("File", @c_io)
    @c_file_test = RbModule.new("FileTest")
    @c_file.includes.push(@c_file_test)
    @c_file.constants["SEPARATOR"] = RbString.new("/", RB_ENC_UTF8, true)
    @c_file.constants["Separator"] = @c_file.constants["SEPARATOR"]
    @c_file.constants["ALT_SEPARATOR"] = nil
    @c_file.constants["PATH_SEPARATOR"] = RbString.new(":", RB_ENC_UTF8, true)
    @c_file.constants["NULL"] = RbString.new("/dev/null", RB_ENC_UTF8, true)
    @c_dir = RbClass.new("Dir", @c_object)
    @c_dir.includes.push(@c_enumerable)
    @c_time = RbClass.new("Time", @c_object)
    @c_time.includes.push(@c_comparable)
    @c_method = RbClass.new("Method", @c_object)
    @c_unbound_method = RbClass.new("UnboundMethod", @c_object)
    @c_binding = RbClass.new("Binding", @c_object)
    @c_errno = RbModule.new("Errno")
    @c_thread = RbClass.new("Thread", @c_object)
    @c_thread.ivars["@report_on_exception"] = true
    @c_fiber = RbClass.new("Fiber", @c_object)
    @c_mutex = RbClass.new("Mutex", @c_object)
    @c_gc = RbModule.new("GC")
    @c_object_space = RbModule.new("ObjectSpace")
    @c_process = RbModule.new("Process")
    @c_process_status = RbClass.new("Process::Status", @c_object)
    @c_process.constants["Status"] = @c_process_status
    @c_rbconfig = RbModule.new("RbConfig")
    rbcfg = RbHash.new
    rbcfg.set(RbString.new("RUBY_INSTALL_NAME"), RbString.new("tungsten-ruby"))
    rbcfg.set(RbString.new("bindir"), RbString.new("/Users/erik/.gemini/antigravity-cli/brain/94e02ee5-d675-4128-b5ee-5adac4b6718e/scratch"))
    rbcfg.set(RbString.new("host_os"), RbString.new("darwin24"))
    rbcfg.set(RbString.new("arch"), RbString.new("arm64-darwin24"))
    rbcfg.set(RbString.new("EXEEXT"), RbString.new(""))
    rbcfg.set(RbString.new("DLEXT"), RbString.new("bundle"))
    rbcfg.set(RbString.new("SOEXT"), RbString.new("dylib"))
    @c_rbconfig.constants["CONFIG"] = rbcfg
    @c_rbconfig.constants["TOPDIR"] = RbString.new("/Users/erik/src/ruby-4.0.9")
    @c_signal = RbModule.new("Signal")
    @c_warning = RbModule.new("Warning")
    @c_set = RbClass.new("Set", @c_object)
    @c_set.includes.push(@c_enumerable)
    @c_random = RbClass.new("Random", @c_object)

    @c_exception = RbClass.new("Exception", @c_object)
    @c_standard_error = RbClass.new("StandardError", @c_exception)

    [
      @c_basic_object, @c_object, @c_kernel, @c_module, @c_class, @c_comparable, @c_enumerable,
      @c_true_class, @c_false_class, @c_nil_class,
      @c_numeric, @c_integer, @c_float, @c_rational, @c_complex, @c_string, @c_symbol,
      @c_array, @c_hash, @c_range, @c_regexp, @c_match_data, @c_proc, @c_struct, @c_data,
      @c_encoding, @c_enumerator, @c_math, @c_json, @c_tungsten,
      @c_io, @c_file, @c_file_test, @c_dir, @c_time, @c_method, @c_unbound_method, @c_binding, @c_errno,
      @c_thread, @c_fiber, @c_mutex, @c_gc, @c_object_space, @c_process, @c_signal, @c_warning, @c_set, @c_random,
      @c_exception, @c_standard_error
    ].each ->(c)
      @c_object.constants[c.name] = c
      @constants[c.name] = c

    # Full Ruby 4.0 Exception hierarchy!
    c_script_err = RbClass.new("ScriptError", @c_exception)
    c_load_err = RbClass.new("LoadError", c_script_err)
    c_syntax_err = RbClass.new("SyntaxError", c_script_err)
    c_not_impl = RbClass.new("NotImplementedError", c_script_err)
    c_sys_exit = RbClass.new("SystemExit", @c_exception)
    c_sys_stack = RbClass.new("SystemStackError", @c_exception)
    c_no_mem = RbClass.new("NoMemoryError", @c_exception)
    c_sig_exc = RbClass.new("SignalException", @c_exception)
    c_intr = RbClass.new("Interrupt", c_sig_exc)
    c_sec_err = RbClass.new("SecurityError", @c_exception)

    c_runtime_err = RbClass.new("RuntimeError", @c_standard_error)
    c_frozen_err = RbClass.new("FrozenError", c_runtime_err)
    c_type_err = RbClass.new("TypeError", @c_standard_error)
    c_arg_err = RbClass.new("ArgumentError", @c_standard_error)
    c_uncaught_throw = RbClass.new("UncaughtThrowError", c_arg_err)
    c_name_err = RbClass.new("NameError", @c_standard_error)
    c_no_meth = RbClass.new("NoMethodError", c_name_err)
    c_zero_div = RbClass.new("ZeroDivisionError", @c_standard_error)
    c_idx_err = RbClass.new("IndexError", @c_standard_error)
    c_key_err = RbClass.new("KeyError", c_idx_err)
    c_stop_iter = RbClass.new("StopIteration", c_idx_err)
    c_range_err = RbClass.new("RangeError", @c_standard_error)
    c_flt_dom = RbClass.new("FloatDomainError", c_range_err)
    c_io_err = RbClass.new("IOError", @c_standard_error)
    c_eof_err = RbClass.new("EOFError", c_io_err)
    c_syscall_err = RbClass.new("SystemCallError", @c_standard_error)
    c_rx_err = RbClass.new("RegexpError", @c_standard_error)
    c_lj_err = RbClass.new("LocalJumpError", @c_standard_error)
    c_nomatch_err = RbClass.new("NoMatchingPatternError", @c_standard_error)
    c_nomatch_key_err = RbClass.new("NoMatchingPatternKeyError", c_nomatch_err)
    c_enc_err = RbClass.new("EncodingError", @c_standard_error)
    c_thr_err = RbClass.new("ThreadError", @c_standard_error)
    c_fib_err = RbClass.new("FiberError", @c_standard_error)
    c_math_dom = RbClass.new("DomainError", c_arg_err)
    @c_math.constants["DomainError"] = c_math_dom

    [
      c_script_err, c_load_err, c_syntax_err, c_not_impl, c_sys_exit, c_sys_stack,
      c_no_mem, c_sig_exc, c_intr, c_sec_err,
      c_runtime_err, c_frozen_err, c_type_err, c_arg_err, c_uncaught_throw,
      c_name_err, c_no_meth, c_zero_div, c_idx_err, c_key_err, c_stop_iter,
      c_range_err, c_flt_dom, c_io_err, c_eof_err, c_syscall_err,
      c_rx_err, c_lj_err, c_nomatch_err, c_nomatch_key_err, c_enc_err, c_thr_err, c_fib_err
    ].each ->(ec)
      @c_object.constants[ec.name] = ec
      @constants[ec.name] = ec

    ["ENOENT", "EACCES", "EISDIR", "EEXIST", "EINVAL", "ENOTDIR", "ENOTEMPTY", "EPIPE", "EBADF", "EPERM"].each ->(en)
      ec = RbClass.new("Errno::" + en, c_syscall_err)
      @c_errno.constants[en] = ec

    ["CompatibilityError", "UndefinedConversionError", "InvalidByteSequenceError", "ConverterNotFoundError"].each ->(en)
      @c_encoding.constants[en] = RbClass.new("Encoding::" + en, c_enc_err)

    @c_float.constants["INFINITY"] = ~1.0 / ~0.0
    @c_float.constants["NAN"] = ~0.0 / ~0.0
    @c_float.constants["EPSILON"] = ~2.220446049250313e-16
    @c_float.constants["MAX"] = ~1.7976931348623157e+308
    @c_float.constants["MIN"] = ~2.2250738585072014e-308
    @c_float.constants["DIG"] = 15
    @c_float.constants["MANT_DIG"] = 53

    @c_object.constants["RUBY_VERSION"] = RbString.new("4.0.9", RB_ENC_UTF8, true)
    @c_object.constants["RUBY_ENGINE"] = RbString.new("tungsten-ruby", RB_ENC_UTF8, true)
    @c_object.constants["RUBY_ENGINE_VERSION"] = RbString.new("4.0.9", RB_ENC_UTF8, true)
    @c_object.constants["RUBY_PLATFORM"] = RbString.new("arm64-darwin24", RB_ENC_UTF8, true)
    @c_object.constants["RUBY_DESCRIPTION"] = RbString.new('tungsten-ruby 4.0.9 [arm64-darwin24]', RB_ENC_UTF8, true)
    @c_object.constants["RUBY_RELEASE_DATE"] = RbString.new("2026-01-01", RB_ENC_UTF8, true)
    @c_object.constants["RUBY_PATCHLEVEL"] = 0
    @c_object.constants["RUBY_REVISION"] = RbString.new("tungsten", RB_ENC_UTF8, true)
    @c_object.constants["NIL"] = nil
    @c_object.constants["TRUE"] = true
    @c_object.constants["FALSE"] = false
    ["RUBY_VERSION", "RUBY_ENGINE", "RUBY_ENGINE_VERSION", "RUBY_PLATFORM", "RUBY_DESCRIPTION", "RUBY_RELEASE_DATE", "RUBY_PATCHLEVEL", "RUBY_REVISION", "NIL", "TRUE", "FALSE"].each ->(cn)
      @constants[cn] = @c_object.constants[cn]

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
    return @c_binding if v.is_a?(RbBinding)
    return @c_stringio if v.is_a?(RbStringIO)
    return @c_class if v.is_a?(RbClass)
    return @c_module if v.is_a?(RbModule)
    return v.klass if v.is_a?(RbObject)
    @c_object

  -> singleton_class_of(obj)
    return @c_true_class if obj == true
    return @c_false_class if obj == false
    return @c_nil_class if obj == nil
    if obj.is_a?(RbModule) || obj.is_a?(RbObject)
      if obj.singleton_cls == nil
        sup = obj.is_a?(RbClass) ? (obj.superclass != nil ? singleton_class_of(obj.superclass) : @c_class) : class_of(obj)
        obj.singleton_cls = RbClass.new("#<Class:" + obj.to_s + ">", sup)
      return obj.singleton_cls
    if obj.is_a?(Array) || obj.is_a?(RbString) || obj.is_a?(RbHash) || obj.is_a?(RbRange) || obj.is_a?(RbRegexp) || obj.is_a?(RbProc) || obj.is_a?(RbMatchData) || obj.is_a?(RbEnumerator) || obj.is_a?(RbBinding) || obj.is_a?(RbStringIO)
      oid = wvalue_bits(obj) ## int
      if !@singleton_map.has_key?(oid)
        @singleton_map[oid] = RbClass.new("#<Class:" + class_of(obj).name + ">", class_of(obj))
      return @singleton_map[oid]
    raise_exc("TypeError", "can't define singleton on " + rb_inspect(obj))

  -> rb_parse_safe(src, filename = "(eval)")
    begin
      return rb_parse(src, filename)
    rescue e
      raise e if e.is_a?(RbSignal)
      raise_exc("SyntaxError", e.to_s)

  -> rb_make_regexp(src, flags = "")
    rx = RbRegexp.new(src, flags)
    raise_exc("RegexpError", rx.compile_err) if rx.compile_err != nil
    rx

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

  -> eval_source(src, filename = "(eval)", is_main = false)
    ast = rb_parse(src, filename)
    @file_stack.push(filename)
    prev_main = @is_main_eval
    @is_main_eval = is_main
    res = nil
    begin
      res = eval_node(ast, @top_env)
    rescue e
      @is_main_eval = prev_main
      @file_stack.pop
      raise e
    @is_main_eval = prev_main
    @file_stack.pop
    res

  -> run_at_exit
    while @at_exit_blocks.size > 0
      b = @at_exit_blocks.pop
      call_proc(b, [])
    nil

  -> eval_file(path, is_main = false)
    full = File.expand_path(path)
    src = File.read(full)
    ast = rb_parse_safe(src, full)
    @file_stack.push(full)
    prev_main = @is_main_eval
    @is_main_eval = is_main
    res = nil
    begin
      res = eval_node(ast, @top_env)
    rescue e
      @is_main_eval = prev_main
      @file_stack.pop
      if e.is_a?(RbSignal) && e.kind == :return
        return e.val
      raise e
    @is_main_eval = prev_main
    @file_stack.pop
    res

  -> resolve_require_path(feat, base_dir = nil)
    # Try exact or +.rb relative to base_dir or $LOAD_PATH
    cands = []
    if base_dir != nil
      cands.push(File.expand_path(feat, base_dir))
      cands.push(File.expand_path(feat + ".rb", base_dir)) if !feat.ends_with?(".rb")
    elsif feat.starts_with?("/") || feat.starts_with?("./") || feat.starts_with?("../")
      cands.push(File.expand_path(feat))
      cands.push(File.expand_path(feat + ".rb")) if !feat.ends_with?(".rb")
    else
      @load_path.each ->(lp)
        dir = rb_to_s(lp)
        cands.push(File.expand_path(feat, dir))
        cands.push(File.expand_path(feat + ".rb", dir)) if !feat.ends_with?(".rb")
    i = 0
    while i < cands.size
      p = cands[i]
      if File.exists?(p) && File.type(p) == "file"
        return p
      i += 1
    nil

  -> rb_require(feat, base_dir = nil)
    if feat == "stringio" || feat == "stringio.so" || feat == "stringio.rb"
      @c_object.constants["StringIO"] = @c_stringio
      @constants["StringIO"] = @c_stringio
      i = 0
      while i < @loaded_features.size
        return false if rb_to_s(@loaded_features[i]) == "stringio.so"
        i += 1
      @loaded_features.push(RbString.new("stringio.so"))
      return true
    if feat == "rbconfig" || feat == "rbconfig.rb"
      @c_object.constants["RbConfig"] = @c_rbconfig
      @constants["RbConfig"] = @c_rbconfig
      i = 0
      while i < @loaded_features.size
        return false if rb_to_s(@loaded_features[i]) == "rbconfig.rb"
        i += 1
      @loaded_features.push(RbString.new("rbconfig.rb"))
      return true
    if feat == "json" || feat == "json.rb"
      @c_object.constants["JSON"] = @c_json
      @constants["JSON"] = @c_json
      i = 0
      while i < @loaded_features.size
        return false if rb_to_s(@loaded_features[i]) == "json.rb"
        i += 1
      @loaded_features.push(RbString.new("json.rb"))
      return true
    path = resolve_require_path(feat, base_dir)
    raise_exc("LoadError", "cannot load such file -- " + feat) if path == nil
    # Check $LOADED_FEATURES
    i = 0
    while i < @loaded_features.size
      return false if rb_to_s(@loaded_features[i]) == path
      i += 1
    @loaded_features.push(RbString.new(path))
    begin
      eval_file(path)
    rescue e
      @loaded_features.pop
      raise e
    true

  -> hoist_locals_node(n, env)
    return nil if n == nil || !n.is_a?(RbNode)
    case n.kind
    when :assign
      if n.a.is_a?(RbNode)
        if n.a.kind == :var && !env.has?(n.a.a)
          env.vars[n.a.a] = nil
        elsif n.a.kind == :splat && n.a.a != nil && n.a.a.kind == :var && !env.has?(n.a.a.a)
          env.vars[n.a.a.a] = nil
      hoist_locals_node(n.b, env)
    when :compound_assign
      if n.b.is_a?(RbNode) && n.b.kind == :var && !env.has?(n.b.a)
        env.vars[n.b.a] = nil
      hoist_locals_node(n.c, env)
    when :multi_assign
      hoist_mlhs(n.a, env)
      hoist_locals_node(n.b, env)
    when :if
      hoist_locals_node(n.a, env)
      hoist_locals(n.b, env)
      hoist_locals(n.c, env) if n.c != nil
    when :while
      hoist_locals_node(n.a, env)
      hoist_locals(n.b, env)
    when :for
      hoist_mlhs(n.a, env)
      hoist_locals_node(n.b, env)
      hoist_locals(n.c, env)
    when :begin
      hoist_locals(n.a, env)
      if n.b != nil
        n.b.each ->(rc)
          env.vars[rc[1]] = nil if rc[1] != nil && !env.has?(rc[1])
          hoist_locals(rc[2], env)
      hoist_locals(n.c, env) if n.c != nil
      hoist_locals(n.d, env) if n.d != nil
    when :case
      hoist_locals_node(n.a, env)
      n.b.each ->(w)
        w[0].each ->(v) hoist_locals_node(v, env)
        hoist_locals(w[1], env)
      hoist_locals(n.c, env) if n.c != nil
    when :case_in
      hoist_locals_node(n.a, env)
      n.b.each ->(arm)
        hoist_pat_vars(arm[0], env)
        hoist_locals(arm[2], env)
      hoist_locals(n.c, env) if n.c != nil
    when :pat_test
      hoist_locals_node(n.a, env)
      hoist_pat_vars(n.b, env)
    when :and, :or
      hoist_locals_node(n.a, env)
      hoist_locals_node(n.b, env)
    when :not
      hoist_locals_node(n.a, env)
    when :binary_op
      hoist_locals_node(n.b, env)
      hoist_locals_node(n.c, env)
    when :call, :safe_nav
      hoist_locals_node(n.a, env)
      if n.c != nil
        n.c[0].each ->(an) hoist_locals_node(an, env)
        n.c[1].each ->(kp) hoist_locals_node(kp[1], env)
    when :array
      n.a.each ->(el) hoist_locals_node(el, env)
    when :return, :break, :next
      hoist_locals_node(n.a, env)
    else
      nil

  -> hoist_mlhs(lhs, env)
    return nil if lhs == nil
    lhs.each ->(t)
      if t.is_a?(RbNode)
        if t.kind == :var && !env.has?(t.a)
          env.vars[t.a] = nil
        elsif t.kind == :splat && t.a != nil && t.a.kind == :var && !env.has?(t.a.a)
          env.vars[t.a.a] = nil
        elsif t.kind == :mlhs_group
          hoist_mlhs(t.a, env)

  -> hoist_pat_vars(pat, env)
    return nil if pat == nil || !pat.is_a?(RbNode)
    case pat.kind
    when :var
      env.vars[pat.a] = nil if pat.a != "_" && !env.has?(pat.a)
    when :pat_as
      hoist_pat_vars(pat.a, env)
      env.vars[pat.b] = nil if pat.b != "_" && !env.has?(pat.b)
    when :pat_alt
      pat.a.each ->(alt) hoist_pat_vars(alt, env)
    when :pat_array
      pat.a.each ->(el)
        if el.is_a?(RbNode) && el.kind == :splat
          env.vars[el.a] = nil if el.a.is_a?(String) && el.a != "_" && !env.has?(el.a)
        else
          hoist_pat_vars(el, env)
    when :pat_hash
      pat.a.each ->(p) hoist_pat_vars(p[1], env)
      env.vars[pat.b] = nil if pat.b.is_a?(String) && pat.b != "_" && !env.has?(pat.b)
    else
      nil

  -> hoist_locals(stmts, env)
    return nil if stmts == nil
    i = 0
    while i < stmts.size
      hoist_locals_node(stmts[i], env)
      i += 1
    nil

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
      if @is_main_eval && n.c != nil
        data_io = RbStringIO.new(n.c)
        @c_object.constants["DATA"] = data_io
        @constants["DATA"] = data_io
      # Run hoisted BEGIN { ... } hooks first (FIFO)
      has_begin = false
      n.a.each ->(st)
        if st.is_a?(RbNode) && st.kind == :begin_hook
          has_begin = true
          hoist_locals(st.a, @top_env)
          eval_stmts(st.a, @top_env)
      if @max_steps == 0 && env == @top_env && !has_begin
        seed = env.vars.size > 0 ? env.vars.keys : nil
        bc = rb_compile_stmts_bytecode(n.a, seed)
        if bc != nil
          lnames = bc.local_names
          if lnames != nil && env.vars.size > 0
            li = 0
            while li < lnames.size
              nm = lnames[li]
              @reg_stack[li] = env.vars.has_key?(nm) ? env.vars[nm] : nil
              li += 1
          res = exec_bytecode(bc, env.self_obj, 0, nil, nil, nil)
          if lnames != nil
            li = 0
            while li < lnames.size
              env.vars[lnames[li]] = @reg_stack[li]
              li += 1
          return res
      hoist_locals(n.a, env)
      eval_stmts(n.a, env)
    when :begin_hook
      nil
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
      rb_make_regexp(n.a, n.b == nil ? "" : n.b)
    when :dregex
      pat_s = rb_to_s(eval_node(n.a, env))
      rb_make_regexp(pat_s, n.b == nil ? "" : n.b)
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
      return env.get("__it_val__") if n.a == "it" && env.has?("__it_val__")
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
      gnm = @global_aliases.has_key?(n.a) ? @global_aliases[n.a] : n.a
      return @last_match if gnm == "$~"
      return (@last_match == nil ? nil : @last_match.get_group(0)) if gnm == "$&"
      return (@last_match == nil ? nil : @last_match.pre_match()) if gnm == "$`"
      return (@last_match == nil ? nil : @last_match.post_match()) if gnm == "$'"
      return @last_exc if gnm == "$!"
      if gnm.size >= 2 && gnm.byte_at(1) >= 49 && gnm.byte_at(1) <= 57
        gi = gnm.slice(1, gnm.size - 1).to_i
        return @last_match == nil ? nil : @last_match.get_group(gi)
      @globals[gnm]
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
      t = n.b
      if t.is_a?(RbNode) && (t.kind == :call || t.kind == :safe_nav)
        recv = t.a == nil ? env.self_obj : eval_node(t.a, env)
        return nil if t.kind == :safe_nav && recv == nil
        if t.b == "[]"
          idx_args = eval_pos_args(t.c[0], env)
          cur_v = call_method(recv, "[]", idx_args, RB_EMPTY_KW, nil, env)
          if op == "||="
            return cur_v if rb_truthy?(cur_v)
            nv = eval_node(n.c, env)
            call_method(recv, "[]=", idx_args + [nv], RB_EMPTY_KW, nil, env)
            return nv
          if op == "&&="
            return cur_v if !rb_truthy?(cur_v)
            nv = eval_node(n.c, env)
            call_method(recv, "[]=", idx_args + [nv], RB_EMPTY_KW, nil, env)
            return nv
          rhs = eval_node(n.c, env)
          bop = op.slice(0, op.size - 1)
          res = eval_binop(bop, cur_v, rhs, env)
          call_method(recv, "[]=", idx_args + [res], RB_EMPTY_KW, nil, env)
          return res
        else
          cur_v = call_method(recv, t.b, [], RB_EMPTY_KW, nil, env)
          if op == "||="
            return cur_v if rb_truthy?(cur_v)
            nv = eval_node(n.c, env)
            call_method(recv, t.b + "=", [nv], RB_EMPTY_KW, nil, env)
            return nv
          if op == "&&="
            return cur_v if !rb_truthy?(cur_v)
            nv = eval_node(n.c, env)
            call_method(recv, t.b + "=", [nv], RB_EMPTY_KW, nil, env)
            return nv
          rhs = eval_node(n.c, env)
          bop = op.slice(0, op.size - 1)
          res = eval_binop(bop, cur_v, rhs, env)
          call_method(recv, t.b + "=", [res], RB_EMPTY_KW, nil, env)
          return res
      if op == "||="
        cur_v = read_assign_target_or_nil(n.b, env)
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
      # Ruby evaluates LHS receivers left-to-right BEFORE evaluating RHS!
      pre_lhs = pre_eval_mlhs(n.a, env)
      rhs = eval_node(n.b, env)
      vals = nil
      if rhs.is_a?(Array)
        vals = rhs
      elsif rhs == nil || rhs == true || rhs == false || rhs.is_a?(Integer) || rhs.is_a?(Float) || rhs.is_a?(RbString) || rhs.is_a?(RbSym)
        vals = [rhs]
      else
        has_ta = lookup_method_on(rhs, "to_ary") != nil
        if !has_ta
          rm = lookup_method_on(rhs, "respond_to?")
          has_ta = rb_truthy?(invoke_rb_method(rm, rhs, [RbSym.new("to_ary"), true], RB_EMPTY_KW, nil)) if rm != nil
        if has_ta
          ary = call_method(rhs, "to_ary", [], RB_EMPTY_KW, nil, env)
          if ary == nil
            vals = [rhs]
          elsif ary.is_a?(Array)
            vals = ary
          else
            raise_exc("TypeError", "can't convert " + class_of(rhs).name + " to Array (" + class_of(rhs).name + "#to_ary gives " + class_of(ary).name + ")")
        else
          vals = [rhs]
      assign_multi_pre(pre_lhs, vals, env)
      rhs
    when :and
      l = eval_node(n.a, env)
      rb_truthy?(l) ? eval_node(n.b, env) : l
    when :or
      l = eval_node(n.a, env)
      rb_truthy?(l) ? l : eval_node(n.b, env)
    when :not
      !eval_cond(n.a, env)
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
      if eval_cond(n.a, env)
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
        c = eval_cond(n.a, env)
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
      for_vars = n.a
      for_body = n.c
      for_fn = ->(pargs, pkw)
        if for_vars.size == 1
          assign_target(for_vars[0], pargs.size > 0 ? pargs[0] : nil, env)
        else
          arr = (pargs.size == 1 && pargs[0].is_a?(Array)) ? pargs[0] : pargs
          assign_multi(for_vars, arr, env)
        res = nil
        while true
          done = true
          begin
            res = eval_stmts(for_body, env)
          rescue sig
            if sig.is_a?(RbSignal)
              if sig.kind == :next
                res = sig.val
              elsif sig.kind == :redo
                done = false
              else
                raise sig
            else
              raise sig
          break if done
        res
      for_blk = RbProc.new([], nil, env, env.self_obj, false, for_fn, env.frame_id)
      begin
        call_method(coll, "each", [], RB_EMPTY_KW, for_blk, env)
      rescue sig
        return sig.val if sig.is_a?(RbSignal) && sig.kind == :break
        raise sig
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
              matches = klasses.size == 0 ? exc.klass.subclass_of?(@c_standard_error) : false
              if !matches && klasses.size > 0
                klasses.each ->(kn)
                  kv = eval_node(kn, env)
                  if kv.is_a?(RbClass)
                    matches = true if exc.klass.subclass_of?(kv) || exc.exc_class == kv.name || kv == @c_exception
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
      an = n.a.is_a?(RbNode) ? rb_to_s(eval_node(n.a, env)) : n.a.to_s
      bn = n.b.is_a?(RbNode) ? rb_to_s(eval_node(n.b, env)) : n.b.to_s
      if an.starts_with?("$") && bn.starts_with?("$")
        target_g = @global_aliases.has_key?(bn) ? @global_aliases[bn] : bn
        @global_aliases[an] = target_g
        return nil
      cur_c = env.def_target != nil ? env.def_target : (env.cref != nil && env.cref.size > 0 ? env.cref[env.cref.size - 1] : @c_object)
      m = cur_c.lookup_method(bn)
      raise_exc("NameError", "undefined method `" + bn + "' for class `" + cur_c.name + "'") if m == nil
      cur_c.methods[an] = m
      @method_epoch += 1
      nil
    when :undef
      cur_c = env.def_target != nil ? env.def_target : (env.cref != nil && env.cref.size > 0 ? env.cref[env.cref.size - 1] : @c_object)
      n.a.each ->(raw_nm)
        unm = raw_nm.is_a?(RbNode) ? rb_to_s(eval_node(raw_nm, env)) : raw_nm.to_s
        raise_exc("NameError", "undefined method `" + unm + "' for class `" + cur_c.name + "'") if cur_c.lookup_method(unm) == nil
        cur_c.methods.delete(unm)
      @method_epoch += 1
      nil
    when :method_def
      target_cls = nil
      if n.d != nil
        ro = eval_node(n.d, env)
        target_cls = singleton_class_of(ro)
      elsif env.def_target != nil
        target_cls = env.def_target
      elsif env.cref != nil && env.cref.size > 0
        target_cls = env.cref[env.cref.size - 1]
      else
        target_cls = @c_object
      rm = RbMethod.new(n.a, n.b, n.c, env, target_cls)
      target_cls.methods[n.a] = rm
      if n.d == nil && target_cls.mod_fn_mode
        singleton_class_of(target_cls).methods[n.a] = rm
      @method_epoch += 1
      RbSym.new(n.a)
    when :class_def
      ns = resolve_const_parent(n.a, env)
      parent_m = ns[0]
      leaf = ns[1]
      sup = n.b != nil ? eval_node(n.b, env) : nil
      if sup != nil && !sup.is_a?(RbClass)
        raise_exc("TypeError", "superclass must be an instance of Class (given an instance of " + class_of(sup).name + ")")
      cls = nil
      if parent_m.constants.has_key?(leaf)
        existing = parent_m.constants[leaf]
        raise_exc("TypeError", leaf + " is not a class") if !existing.is_a?(RbClass)
        if sup != nil && existing.superclass != sup
          raise_exc("TypeError", "superclass mismatch for class " + leaf)
        cls = existing
      else
        full_nm = (parent_m == @c_object || parent_m.name == nil || parent_m.name.starts_with?("#<")) ? leaf : (parent_m.name + "::" + leaf)
        cls = RbClass.new(full_nm, sup == nil ? @c_object : sup)
        parent_m.constants[leaf] = cls
        @constants[leaf] = cls if parent_m == @c_object
      nc = env.cref == nil ? [cls] : env.cref + [cls]
      cenv = RbEnv.new(nil, cls, nil, 0, nc)
      hoist_locals(n.c, cenv)
      eval_stmts(n.c, cenv)
    when :singleton_class
      obj = eval_node(n.a, env)
      sc = singleton_class_of(obj)
      nc = env.cref == nil ? [sc] : env.cref + [sc]
      cenv = RbEnv.new(nil, sc, nil, env.frame_id, nc)
      hoist_locals(n.b, cenv)
      eval_stmts(n.b, cenv)
    when :module_def
      ns = resolve_const_parent(n.a, env)
      parent_m = ns[0]
      leaf = ns[1]
      mod = nil
      if parent_m.constants.has_key?(leaf)
        existing = parent_m.constants[leaf]
        raise_exc("TypeError", leaf + " is not a module") if !existing.is_a?(RbModule) || existing.is_a?(RbClass)
        mod = existing
      else
        full_nm = (parent_m == @c_object || parent_m.name == nil || parent_m.name.starts_with?("#<")) ? leaf : (parent_m.name + "::" + leaf)
        mod = RbModule.new(full_nm)
        parent_m.constants[leaf] = mod
        @constants[leaf] = mod if parent_m == @c_object
      nc = env.cref == nil ? [mod] : env.cref + [mod]
      menv = RbEnv.new(nil, mod, nil, 0, nc)
      hoist_locals(n.b, menv)
      eval_stmts(n.b, menv)
    when :call, :safe_nav
      recv = n.a == nil ? env.self_obj : eval_node(n.a, env)
      return nil if n.kind == :safe_nav && recv == nil
      spec = n.c
      has_fwd = false
      spec[0].each ->(an) has_fwd = true if an.is_a?(RbNode) && an.kind == :arg_forward
      args = eval_pos_args(spec[0], env)
      kw = eval_call_kw(spec[1], args, env)
      if has_fwd && env.has?("__fwd_kw__")
        fkw = env.get("__fwd_kw__")
        if fkw != nil && fkw.size > 0
          kw = {} if kw == RB_EMPTY_KW
          fkw.each ->(fk, fv) kw[fk] = fv if !kw.has_key?(fk)
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
          if lookup_method_on(bp, "to_proc") == nil && !has_builtin_method?(bp, "to_proc")
            raise_exc("TypeError", "wrong argument type " + class_of(bp).name + " (expected Proc)")
          tp_res = call_method(bp, "to_proc", [], {}, nil, env)
          if !tp_res.is_a?(RbProc)
            raise_exc("TypeError", "can't convert " + class_of(bp).name + " to Proc (" + class_of(bp).name + "#to_proc gives " + class_of(tp_res).name + ")")
          blk = tp_res
      elsif has_fwd && env.has?("__fwd_blk__")
        blk = env.get("__fwd_blk__")
      res_c = call_method(recv, n.b, args, kw, blk, env)
      n.d == :assign_ret && args.size > 0 ? args[args.size - 1] : res_c
    when :super
      # Resolve next method in ancestor chain past current owner
      cur_m = env.vars["__super_owner__"]
      cur_nm = env.vars["__super_name__"]
      args = n.a != nil ? eval_pos_args(n.a[0], env) : env.vars["__super_args__"]
      kw = n.a != nil ? eval_kw_args(n.a[1], env) : {}
      blk = n.b != nil ? RbProc.new(n.b.a, n.b.b, env, env.self_obj, false, nil, env.frame_id) : env.block
      anc = nil
      if (env.self_obj.is_a?(RbObject) || env.self_obj.is_a?(RbModule)) && env.self_obj.singleton_cls != nil
        sanc = env.self_obj.singleton_cls.ancestors()
        anc = sanc.include?(cur_m) ? sanc : class_of(env.self_obj).ancestors()
      else
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

  -> eval_cond(n, env)
    return false if n == nil
    if n.kind == :range
      fid = wvalue_bits(n) ## int
      st = @flipflops.has_key?(fid) && @flipflops[fid] == true
      if !st
        if eval_cond(n.a, env)
          @flipflops[fid] = true
          if n.c != true
            # Inclusive `..`: check right side immediately too
            @flipflops[fid] = false if eval_cond(n.b, env)
          return true
        return false
      else
        @flipflops[fid] = false if eval_cond(n.b, env)
        return true
    if n.kind == :not || (n.kind == :unary_op && n.a == "!")
      return !eval_cond(n.kind == :not ? n.a : n.b, env)
    if n.kind == :and
      return eval_cond(n.a, env) && eval_cond(n.b, env)
    if n.kind == :or
      return eval_cond(n.a, env) || eval_cond(n.b, env)
    rb_truthy?(eval_node(n, env))

  -> eval_pos_args(arg_nodes, env)
    out = []
    arg_nodes.each ->(an)
      if an.is_a?(RbNode) && an.kind == :splat
        sv = eval_node(an.a, env)
        if sv.is_a?(Array)
          sv.each ->(x) out.push(x)
        elsif sv.is_a?(RbRange)
          sv.to_a.each ->(x) out.push(x)
        elsif sv == nil
          nil
        elsif sv.is_a?(RbObject) && (lookup_method_on(sv, "to_a") != nil)
          arr = call_method(sv, "to_a", [], RB_EMPTY_KW, nil, env)
          if arr == nil
            out.push(sv)
          elsif arr.is_a?(Array)
            arr.each ->(x) out.push(x)
          else
            raise_exc("TypeError", "can't convert " + class_of(sv).name + " to Array (" + class_of(sv).name + "#to_a gives " + class_of(arr).name + ")")
        else
          out.push(sv)
      elsif an.is_a?(RbNode) && an.kind == :arg_forward
        fa = env.vars["__fwd_args__"]
        fa.each ->(x) out.push(x) if fa != nil
      else
        out.push(eval_node(an, env))
    out

  -> pre_eval_mlhs(lhs, env)
    out = []
    i = 0
    while i < lhs.size
      t = lhs[i]
      if t.is_a?(RbNode) && t.kind == :mlhs_group
        out.push([:group, pre_eval_mlhs(t.a, env)])
      elsif t.is_a?(RbNode) && t.kind == :splat
        if t.a != nil && t.a.is_a?(RbNode) && (t.a.kind == :call || t.a.kind == :safe_nav)
          out.push([:splat_pre, pre_eval_target(t.a, env)])
        else
          out.push([:splat, t.a])
      elsif t.is_a?(RbNode) && (t.kind == :call || t.kind == :safe_nav)
        out.push([:pre, pre_eval_target(t, env)])
      else
        out.push([:raw, t])
      i += 1
    out

  -> pre_eval_target(t, env)
    recv = t.a == nil ? env.self_obj : eval_node(t.a, env)
    if t.kind == :safe_nav && recv == nil
      return [:skip, nil, nil, nil]
    if t.b == "[]"
      idx_args = eval_pos_args(t.c[0], env)
      return [:idx, recv, idx_args, nil]
    [:attr, recv, t.b + "=", nil]

  -> assign_pre_item(item, val, env)
    k = item[0]
    if k == :raw
      assign_target(item[1], val, env)
    elsif k == :group
      sub_vals = val.is_a?(Array) ? val : [val]
      assign_multi_pre(item[1], sub_vals, env)
    elsif k == :pre
      p = item[1]
      if p[0] == :idx
        call_method(p[1], "[]=", p[2] + [val], RB_EMPTY_KW, nil, env)
      elsif p[0] == :attr
        call_method(p[1], p[2], [val], RB_EMPTY_KW, nil, env)
    elsif k == :splat
      assign_target(item[1], val.is_a?(Array) ? val : [val], env) if item[1] != nil
    elsif k == :splat_pre
      p = item[1]
      av = val.is_a?(Array) ? val : [val]
      if p[0] == :idx
        call_method(p[1], "[]=", p[2] + [av], RB_EMPTY_KW, nil, env)
      elsif p[0] == :attr
        call_method(p[1], p[2], [av], RB_EMPTY_KW, nil, env)
    nil

  -> assign_multi_pre(pre_lhs, vals, env)
    splat_i = -1
    si = 0
    while si < pre_lhs.size
      splat_i = si if pre_lhs[si][0] == :splat || pre_lhs[si][0] == :splat_pre
      si += 1
    if splat_i < 0
      i = 0
      while i < pre_lhs.size
        assign_pre_item(pre_lhs[i], i < vals.size ? vals[i] : nil, env)
        i += 1
    else
      post_n = pre_lhs.size - 1 - splat_i
      i = 0
      while i < splat_i
        assign_pre_item(pre_lhs[i], i < vals.size ? vals[i] : nil, env)
        i += 1
      mid_end = vals.size - post_n
      mid_end = splat_i if mid_end < splat_i
      mid = []
      k = splat_i
      while k < mid_end
        mid.push(vals[k])
        k += 1
      assign_pre_item(pre_lhs[splat_i], mid, env)
      j = 0
      while j < post_n
        vi = mid_end + j
        assign_pre_item(pre_lhs[splat_i + 1 + j], vi < vals.size ? vals[vi] : nil, env)
        j += 1
    nil

  -> eval_call_kw(kw_pairs, args_out, env)
    return RB_EMPTY_KW if kw_pairs.size == 0
    out = {}
    pos_h = nil
    kw_pairs.each ->(kp)
      if kp[0] == nil
        hv = eval_node(kp[1], env)
        if hv.is_a?(RbHash)
          hv.entries.each ->(e)
            if e[0].is_a?(RbSym)
              out[e[0].name] = e[1]
            else
              pos_h = RbHash.new if pos_h == nil
              pos_h.set(e[0], e[1])
      elsif kp[0].is_a?(String)
        out[kp[0]] = eval_node(kp[1], env)
      else
        k = eval_node(kp[0], env)
        v = eval_node(kp[1], env)
        if k.is_a?(RbSym)
          out[k.name] = v
        else
          pos_h = RbHash.new if pos_h == nil
          pos_h.set(k, v)
    args_out.push(pos_h) if pos_h != nil
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

  -> assign_multi(lhs, vals, env)
    splat_i = -1
    si = 0
    while si < lhs.size
      splat_i = si if lhs[si].is_a?(RbNode) && lhs[si].kind == :splat
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
      assign_target(lhs[splat_i].a, mid, env) if lhs[splat_i].a != nil
      j = 0
      while j < post_n
        vi = mid_end + j
        assign_target(lhs[splat_i + 1 + j], vi < vals.size ? vals[vi] : nil, env)
        j += 1
    nil

  -> read_assign_target_or_nil(t, env)
    return env.get(t.a) if t.kind == :var
    if t.kind == :const_ref
      return nil if eval_defined(t, env) == nil
      return eval_node(t, env)
    if t.kind == :const_path
      if t.a == nil
        return @constants.has_key?(t.b) ? @constants[t.b] : nil
      base = eval_node(t.a, env)
      raise_exc("TypeError", rb_inspect(base) + " is not a class/module") if !base.is_a?(RbModule)
      return base.constants.has_key?(t.b) ? base.constants[t.b] : nil
    eval_node(t, env)

  -> read_assign_target(t, env)
    return env.get(t.a) if t.kind == :var
    return eval_node(t, env)

  -> assign_target(t, val, env)
    return val if t == nil
    return env.set(t, val) if t.is_a?(String)
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
      gnm = @global_aliases.has_key?(t.a) ? @global_aliases[t.a] : t.a
      if gnm == "$~"
        raise_exc("TypeError", "wrong argument type " + class_of(val).name + " (expected MatchData)") if val != nil && !val.is_a?(RbMatchData)
        @last_match = val
        return val
      @globals[gnm] = val
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
    when :splat
      assign_target(t.a, val.is_a?(Array) ? val : [val], env) if t.a != nil
      val
    when :mlhs_group
      sub_vals = val.is_a?(Array) ? val : [val]
      assign_multi(t.a, sub_vals, env)
      val
    when :call, :safe_nav
      recv = t.a == nil ? env.self_obj : eval_node(t.a, env)
      return nil if t.kind == :safe_nav && recv == nil
      if t.b == "[]"
        args = eval_pos_args(t.c[0], env)
        args.push(val)
        call_method(recv, "[]=", args, {}, nil, env)
      else
        call_method(recv, t.b + "=", [val], {}, nil, env)
      val
    else
      val

  -> resolve_const_parent(cname, env)
    parts = cname.split("::")
    if parts.size == 1
      pm = env.cref != nil && env.cref.size > 0 ? env.cref[env.cref.size - 1] : @c_object
      return [pm, parts[0]]
    cur = nil
    si = 0
    if parts[0] == ""
      cur = @c_object
      si = 1
    else
      p0 = parts[0]
      if p0 == "nil"
        raise_exc("TypeError", "nil is not a class/module")
      elsif p0 == "self"
        cur = env.self_obj
      elsif p0.starts_with?("@")
        cur = (env.self_obj.is_a?(RbObject) || env.self_obj.is_a?(RbModule)) ? env.self_obj.ivars[p0] : nil
      elsif p0.size > 0 && p0.byte_at(0) >= 65 && p0.byte_at(0) <= 90
        cur = resolve_const(p0, env)
      else
        cur = env.has?(p0) ? env.get(p0) : call_method(env.self_obj, p0, [], RB_EMPTY_KW, nil, env)
      raise_exc("TypeError", rb_inspect(cur) + " is not a class/module") if !cur.is_a?(RbModule)
      si = 1
    while si < parts.size - 1
      pn = parts[si]
      raise_exc("NameError", "uninitialized constant " + cur.name + "::" + pn) if !cur.constants.has_key?(pn)
      cur = cur.constants[pn]
      raise_exc("TypeError", rb_inspect(cur) + " is not a class/module") if !cur.is_a?(RbModule)
      si += 1
    [cur, parts[parts.size - 1]]

  -> eval_defined(n, env)
    return nil if n == nil
    case n.kind
    when :nil then return RbString.new("nil", RB_ENC_UTF8, true)
    when :bool then return RbString.new(n.a == true ? "true" : "false", RB_ENC_UTF8, true)
    when :self then return RbString.new("self", RB_ENC_UTF8, true)
    when :var
      return RbString.new("local-variable", RB_ENC_UTF8, true) if env.has?(n.a)
      return RbString.new("method", RB_ENC_UTF8, true) if lookup_method_on(env.self_obj, n.a) != nil || has_builtin_method?(env.self_obj, n.a)
      return nil
    when :ivar
      return ((env.self_obj.is_a?(RbObject) || env.self_obj.is_a?(RbModule)) && env.self_obj.ivars.has_key?(n.a)) ? RbString.new("instance-variable", RB_ENC_UTF8, true) : nil
    when :cvar
      cur_c = env.cref != nil && env.cref.size > 0 ? env.cref[env.cref.size - 1] : class_of(env.self_obj)
      anc = cur_c.ancestors()
      i = 0
      while i < anc.size
        return RbString.new("class variable", RB_ENC_UTF8, true) if anc[i].cvars.has_key?(n.a)
        i += 1
      return nil
    when :gvar
      gnm = @global_aliases.has_key?(n.a) ? @global_aliases[n.a] : n.a
      if gnm == "$~" || gnm == "$&" || gnm == "$`" || gnm == "$'"
        return @last_match != nil ? RbString.new("global-variable", RB_ENC_UTF8, true) : nil
      if gnm == "$!"
        return @last_exc != nil ? RbString.new("global-variable", RB_ENC_UTF8, true) : nil
      if gnm.size >= 2 && gnm.byte_at(1) >= 49 && gnm.byte_at(1) <= 57
        gi = gnm.slice(1, gnm.size - 1).to_i
        return (@last_match != nil && @last_match.get_group(gi) != nil) ? RbString.new("global-variable", RB_ENC_UTF8, true) : nil
      return @globals.has_key?(gnm) ? RbString.new("global-variable", RB_ENC_UTF8, true) : nil
    when :const_ref
      if env.cref != nil
        ci = env.cref.size - 1
        while ci >= 0
          return RbString.new("constant", RB_ENC_UTF8, true) if env.cref[ci].constants.has_key?(n.a)
          ci -= 1
      if env.cref != nil && env.cref.size > 0
        anc = env.cref[env.cref.size - 1].ancestors()
        i = 0
        while i < anc.size
          return RbString.new("constant", RB_ENC_UTF8, true) if anc[i].constants.has_key?(n.a)
          i += 1
      return @constants.has_key?(n.a) ? RbString.new("constant", RB_ENC_UTF8, true) : nil
    when :const_path
      if n.a == nil
        return @constants.has_key?(n.b) ? RbString.new("constant", RB_ENC_UTF8, true) : nil
      return nil if eval_defined(n.a, env) == nil
      begin
        base = eval_node(n.a, env)
        return (base.is_a?(RbModule) && base.constants.has_key?(n.b)) ? RbString.new("constant", RB_ENC_UTF8, true) : nil
      rescue e
        return nil
    when :assign, :compound_assign, :multi_assign
      return RbString.new("assignment", RB_ENC_UTF8, true)
    when :yield
      return env.block != nil ? RbString.new("yield", RB_ENC_UTF8, true) : nil
    when :super
      cur_m = env.vars["__super_owner__"]
      cur_nm = env.vars["__super_name__"]
      return nil if cur_m == nil || cur_nm == nil
      anc = class_of(env.self_obj).ancestors()
      found_cur = false
      i = 0
      while i < anc.size
        return RbString.new("super", RB_ENC_UTF8, true) if found_cur && anc[i].methods.has_key?(cur_nm)
        found_cur = true if anc[i] == cur_m
        i += 1
      return nil
    when :call, :safe_nav
      if n.a != nil
        return nil if eval_defined(n.a, env) == nil
      spec = n.c
      if spec != nil
        i = 0
        while i < spec[0].size
          an = spec[0][i]
          an = an.a if an.is_a?(RbNode) && an.kind == :splat
          return nil if an != nil && eval_defined(an, env) == nil
          i += 1
      begin
        recv = n.a == nil ? env.self_obj : eval_node(n.a, env)
        return nil if n.kind == :safe_nav && recv == nil
        return RbString.new("method", RB_ENC_UTF8, true) if lookup_method_on(recv, n.b) != nil || has_builtin_method?(recv, n.b)
        return nil
      rescue e
        return nil
    when :binary_op
      return nil if eval_defined(n.b, env) == nil || eval_defined(n.c, env) == nil
      begin
        l = eval_node(n.b, env)
        return RbString.new("method", RB_ENC_UTF8, true) if lookup_method_on(l, n.a) != nil || has_builtin_method?(l, n.a)
        return nil
      rescue e
        return nil
    when :array
      i = 0
      while i < n.a.size
        el = n.a[i]
        el = el.a if el.is_a?(RbNode) && el.kind == :splat
        return nil if el != nil && eval_defined(el, env) == nil
        i += 1
      return RbString.new("expression", RB_ENC_UTF8, true)
    when :stmts, :begin
      return RbString.new("expression", RB_ENC_UTF8, true) if n.a == nil || n.a.size == 0
      return eval_defined(n.a[n.a.size - 1], env)
    else
      return RbString.new("expression", RB_ENC_UTF8, true)

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
      arr = nil
      if val.is_a?(Array)
        arr = val
      elsif val.is_a?(RbObject) && lookup_method_on(val, "deconstruct") != nil
        dc = call_method(val, "deconstruct", [], RB_EMPTY_KW, nil, env)
        raise_exc("TypeError", "deconstruct must return Array") if !dc.is_a?(Array)
        arr = dc
      return false if arr == nil
      pats = pat.a
      splat_indices = []
      i = 0
      while i < pats.size
        splat_indices.push(i) if pats[i].is_a?(RbNode) && pats[i].kind == :splat
        i += 1
      # Ruby 3.0+ Find Pattern: `[*pre, mid..., *post]` (2 splats: first & last)
      if splat_indices.size == 2 && splat_indices[0] == 0 && splat_indices[1] == pats.size - 1
        mid_pats = pats.slice(1, pats.size - 2)
        mlen = mid_pats.size
        return false if arr.size < mlen
        start = 0
        while start + mlen <= arr.size
          sub_binds = {}
          ok = true
          j = 0
          while j < mlen
            if !match_pattern(mid_pats[j], arr[start + j], env, sub_binds)
              ok = false
              break
            j += 1
          if ok
            pre_nm = pats[0].a
            post_nm = pats[pats.size - 1].a
            binds[pre_nm] = arr.slice(0, start) if pre_nm.is_a?(String) && pre_nm != "_"
            sub_binds.each ->(k, v) binds[k] = v
            binds[post_nm] = arr.slice(start + mlen, arr.size - start - mlen) if post_nm.is_a?(String) && post_nm != "_"
            return true
          start += 1
        return false
      si = splat_indices.size == 1 ? splat_indices[0] : -1
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
      binds[pats[si].a] = mid if pats[si].a.is_a?(String) && pats[si].a != "_"
      j = 0
      while j < post
        return false if !match_pattern(pats[si + 1 + j], arr[mid_end + j], env, binds)
        j += 1
      true
    when :pat_hash
      hv = nil
      if val.is_a?(RbHash)
        hv = val
      elsif val.is_a?(RbObject) && lookup_method_on(val, "deconstruct_keys") != nil
        req_keys = pat.b != nil ? nil : pat.a.map ->(pp) RbSym.new(pp[0])
        dk = call_method(val, "deconstruct_keys", [req_keys], RB_EMPTY_KW, nil, env)
        raise_exc("TypeError", "deconstruct_keys must return Hash") if !dk.is_a?(RbHash)
        hv = dk
      return false if hv == nil
      used = {}
      i = 0
      while i < pat.a.size
        kstr = pat.a[i][0]
        ksym = RbSym.new(kstr)
        return false if !hv.has_key?(ksym)
        used[kstr] = true
        return false if !match_pattern(pat.a[i][1], hv.get(ksym), env, binds)
        i += 1
      if pat.b == :nil
        return false if hv.size != used.size
      elsif pat.b != nil && pat.b != "_"
        rest = RbHash.new
        hv.entries.each ->(e)
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

  -> bind_params(params, args, kw, blk, target_env, def_env, check_arity = false)
    min_req = 0
    max_pos = 0
    has_splat = false
    has_fwd = false
    has_kw_any = false
    has_kw_splat = false
    has_kw_nil = false
    params.each ->(p)
      pk = p[0]
      if pk == :req || pk == :destruct
        min_req += 1
        max_pos += 1
      elsif pk == :opt
        max_pos += 1
      elsif pk == :splat
        has_splat = true
      elsif pk == :forward
        has_fwd = true
      elsif pk == :kw_req || pk == :kw_opt || pk == :kw
        has_kw_any = true
      elsif pk == :kw_splat
        if p[1] == :nil
          has_kw_nil = true
        else
          has_kw_splat = true
    # Ruby 3.0-4.0 keyword separation:
    # 1. If callee accepts **nil and caller passes kw, raise ArgumentError!
    if has_kw_nil && kw.size > 0
      raise_exc("ArgumentError", "no keywords accepted")
    # 2. If callee takes NO keywords (and not ...) and caller passed kw, pack kw into trailing positional Hash!
    if !has_kw_any && !has_kw_splat && !has_fwd && kw.size > 0
      kh = RbHash.new
      ks = kw.keys
      ki = 0
      while ki < ks.size
        kh.set(RbSym.new(ks[ki]), kw[ks[ki]])
        ki += 1
      args = args + [kh]
      kw = RB_EMPTY_KW
    # 3. If callee takes keywords and caller passed a ruby2_keywords Hash as last positional arg, unpack it!
    elsif (has_kw_any || has_kw_splat) && kw.size == 0 && args.size > 0 && args[args.size - 1].is_a?(RbHash) && args[args.size - 1].ruby2_kw
      last_h = args[args.size - 1]
      args = args.slice(0, args.size - 1)
      nkw = {}
      last_h.entries.each ->(e) nkw[rb_to_s(e[0])] = e[1]
      kw = nkw
    if check_arity && !has_fwd
      if args.size < min_req
        raise_exc("ArgumentError", "wrong number of arguments (given " + args.size.to_s + ", expected " + min_req.to_s + (has_splat ? "+" : (max_pos > min_req ? ".." + max_pos.to_s : "")) + ")")
      if !has_splat && args.size > max_pos
        raise_exc("ArgumentError", "wrong number of arguments (given " + args.size.to_s + ", expected " + min_req.to_s + (max_pos > min_req ? ".." + max_pos.to_s : "") + ")")
    # Ruby 3.4 `it` implicit block parameter & `_1.._9` numbered parameters!
    if params.size == 0
      target_env.vars["__it_val__"] = args.size > 0 ? args[0] : nil
      n_args = (args.size == 1 && args[0].is_a?(Array)) ? args[0] : args
      k = 0
      while k < 9 && k < n_args.size
        target_env.vars["_" + (k + 1).to_s] = n_args[k]
        k += 1
    splat_idx = -1
    post_req = 0
    pi = 0
    while pi < params.size
      if params[pi][0] == :splat
        splat_idx = pi
      elsif splat_idx >= 0 && (params[pi][0] == :req || params[pi][0] == :destruct)
        post_req += 1
      pi += 1
    ai = 0
    used_kw = kw.size > 0 ? {} : nil
    params.each ->(p)
      pk = p[0]
      pnm = p[1]
      pd = p[2]
      if pk == :forward
        target_env.vars["__fwd_args__"] = args.slice(ai, args.size - ai)
        target_env.vars["__fwd_kw__"] = kw
        target_env.vars["__fwd_blk__"] = blk
        ai = args.size
      elsif pk == :req
        target_env.vars[pnm] = ai < args.size ? args[ai] : nil
        ai += 1
      elsif pk == :opt
        avail = args.size - ai - post_req
        if avail > 0
          target_env.vars[pnm] = args[ai]
          ai += 1
        else
          target_env.vars[pnm] = eval_node(pd, target_env)
      elsif pk == :splat
        take = args.size - ai - post_req
        take = 0 if take < 0
        rest = take > 0 ? args.slice(ai, take) : []
        target_env.vars[pnm] = rest if pnm != "*"
        ai += take
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
        kw.each ->(k, v) rh.set(RbSym.new(k), v) if used_kw == nil || !used_kw.has_key?(k)
        target_env.vars[pnm] = rh if pnm != "**"
      elsif pk == :block
        target_env.vars[pnm] = blk if pnm != "&"
      elsif pk == :block_local
        target_env.vars[pnm] = nil
      elsif pk == :trailing_comma
        nil
      elsif pk == :destruct
        av = ai < args.size ? args[ai] : nil
        ai += 1
        arr = av.is_a?(Array) ? av : [av]
        di = 0
        while di < pnm.size
          target_env.vars[pnm[di]] = di < arr.size ? arr[di] : nil
          di += 1
    if (has_kw_any) && !has_kw_splat && !has_fwd && kw.size > 0
      ks = kw.keys
      ki = 0
      while ki < ks.size
        if used_kw == nil || !used_kw.has_key?(ks[ki])
          raise_exc("ArgumentError", "unknown keyword: :" + ks[ki])
        ki += 1
    nil

  -> call_proc(pr, args, kw = {}, blk = nil)
    raise_exc("LocalJumpError", "no block given") if pr == nil
    return pr.native_fn.call(args, kw) if pr.native_fn != nil
    raise_exc("SystemStackError", "stack level too deep") if @call_depth >= 250
    @call_depth += 1
    fid = pr.def_frame_id
    if pr.is_lambda
      @next_frame_id += 1
      fid = @next_frame_id
      @active_frames[fid] = true
    penv = RbEnv.new(pr.env, pr.self_obj, pr.env.block, fid, pr.env.cref, pr.env.def_target)
    # Ruby block auto-unpacking: only count positional params (:req/:opt/:destruct/:splat) + trailing comma!
    if !pr.is_lambda && args.size == 1 && args[0].is_a?(Array)
      pos_n = 0
      has_tc = false
      pr.params.each ->(pp)
        pk = pp[0]
        pos_n += 1 if pk == :req || pk == :opt || pk == :destruct || pk == :splat
        has_tc = true if pk == :trailing_comma
      if pos_n > 1 || has_tc
        args = args[0]
    begin
      bind_params(pr.params, args, kw, blk, penv, pr.env, pr.is_lambda)
      hoist_locals(pr.body, penv)
      while true
        begin
          res = eval_stmts(pr.body, penv)
          @active_frames.delete(fid) if pr.is_lambda
          @call_depth -= 1
          return res
        rescue sig
          if sig.is_a?(RbSignal)
            if sig.kind == :next
              @active_frames.delete(fid) if pr.is_lambda
              @call_depth -= 1
              return sig.val
            if sig.kind == :return
              if pr.is_lambda && sig.target_id == fid
                @active_frames.delete(fid)
                @call_depth -= 1
                return sig.val
              if sig.target_id == 0 || !@active_frames.has_key?(sig.target_id)
                @active_frames.delete(fid) if pr.is_lambda
                @call_depth -= 1
                raise_exc("LocalJumpError", "unexpected return")
            if sig.kind == :break && pr.is_lambda
              @active_frames.delete(fid)
              @call_depth -= 1
              return sig.val
            next if sig.kind == :redo
          @active_frames.delete(fid) if pr.is_lambda
          @call_depth -= 1
          raise sig
    rescue e
      @active_frames.delete(fid) if pr.is_lambda
      @call_depth -= 1
      raise e

  # Fast hoisted map/select bytecode executor (hoists ops/consts/stk ONCE across the whole array!).
  -> exec_bytecode_iter(bc, recv_arr, mode)
    # mode: 0 = map, 1 = select, 2 = reject
    n = recv_arr.size ## i64
    out = mode == 0 ? Array.new(n, nil) : []
    return out if n == 0
    fsize = bc.frame_size ## i64
    if fsize + 64 >= @reg_stack.size
      extra = @reg_stack.size
      ei = 0
      while ei < extra
        @reg_stack.push(nil)
        ei += 1
    stk = @reg_stack
    ops = bc.ops ## i64[]
    aa = bc.a ## i64[]
    bb = bc.b ## i64[]
    cc = bc.c ## i64[]
    consts = bc.consts
    nops = bc.nops ## i64
    i = 0 ## i64
    while i < n
      elem = recv_arr[i]
      stk[0] = elem
      pc = 0 ## i64
      res = nil
      while pc < nops
        op = ops[pc] ## i64
        a = aa[pc] ## i64
        b = bb[pc] ## i64
        c = cc[pc] ## i64
        case op
        when RB_OP_RET
          res = stk[a]
          break
        when RB_OP_ADD_IMM
          v1 = stk[b]
          stk[a] = v1.is_a?(Integer) ? (v1 + c) : rb_num_add(v1, c)
          pc += 1
        when RB_OP_SUB_IMM
          v1 = stk[b]
          stk[a] = v1.is_a?(Integer) ? (v1 - c) : rb_num_sub(v1, c)
          pc += 1
        when RB_OP_MUL_IMM
          v1 = stk[b]
          stk[a] = v1.is_a?(Integer) ? (v1 * c) : eval_binop("*", v1, c, @top_env)
          pc += 1
        when RB_OP_MOD_IMM
          v1 = stk[b]
          if v1.is_a?(Integer)
            r = v1 % c
            stk[a] = r < 0 ? (r + c) : r
          else
            stk[a] = eval_binop("%", v1, c, @top_env)
          pc += 1
        when RB_OP_EQ_IMM
          v1 = stk[b]
          stk[a] = v1.is_a?(Integer) ? (v1 == c) : rb_eq?(v1, c)
          pc += 1
        when RB_OP_LT_IMM
          v1 = stk[b]
          stk[a] = v1.is_a?(Integer) ? (v1 < c) : (rb_cmp(v1, c) < 0)
          pc += 1
        when RB_OP_LE_IMM
          v1 = stk[b]
          stk[a] = v1.is_a?(Integer) ? (v1 <= c) : (rb_cmp(v1, c) <= 0)
          pc += 1
        when RB_OP_ADD
          v1 = stk[b]; v2 = stk[c]
          stk[a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 + v2) : eval_binop("+", v1, v2, @top_env)
          pc += 1
        when RB_OP_SUB
          v1 = stk[b]; v2 = stk[c]
          stk[a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 - v2) : eval_binop("-", v1, v2, @top_env)
          pc += 1
        when RB_OP_MUL
          v1 = stk[b]; v2 = stk[c]
          stk[a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 * v2) : eval_binop("*", v1, v2, @top_env)
          pc += 1
        when RB_OP_MOV
          stk[a] = stk[b]
          pc += 1
        when RB_OP_INT
          stk[a] = b
          pc += 1
        when RB_OP_CONST
          stk[a] = consts[b]
          pc += 1
        when RB_OP_NIL
          stk[a] = nil
          pc += 1
        when RB_OP_BOOL
          stk[a] = (b != 0)
          pc += 1
        when RB_OP_NOT
          v1 = stk[b]
          stk[a] = (v1 == nil || v1 == false)
          pc += 1
        when RB_OP_NEG
          v1 = stk[b]
          stk[a] = (v1.is_a?(Integer) || v1.is_a?(Float)) ? -v1 : call_method(v1, "-@", [], RB_EMPTY_KW, nil, @top_env)
          pc += 1
        when RB_OP_JMP
          pc = a
        when RB_OP_JMP_FALSE
          v1 = stk[a]
          pc = (v1 == nil || v1 == false) ? b : pc + 1
        when RB_OP_JMP_TRUE
          v1 = stk[a]
          pc = (v1 != nil && v1 != false) ? b : pc + 1
        when RB_OP_JGE_IMM
          v1 = stk[a]
          if v1.is_a?(Integer)
            if v1 >= b then pc = c; next
          elsif rb_cmp(v1, b) >= 0
            pc = c; next
          pc += 1
        when RB_OP_JGT_IMM
          v1 = stk[a]
          if v1.is_a?(Integer)
            if v1 > b then pc = c; next
          elsif rb_cmp(v1, b) > 0
            pc = c; next
          pc += 1
        else
          # Fallback to full exec_bytecode for complex ops (method calls, ivars, etc.)
          res = exec_bytecode(bc, @main_obj, 0, elem, nil, nil)
          break
      if mode == 0
        out[i] = res
      elsif mode == 1
        out.push(elem) if res != nil && res != false
      else
        out.push(elem) if res == nil || res == false
      i += 1
    out

  # Check if a block bytecode only uses inline-safe pure ops (no self/call/ivar) so exec_bytecode_iter can hoist it.
  -> bc_pure_inline?(bc)
    ops = bc.ops ## i64[]
    nops = bc.nops ## i64
    i = 0 ## i64
    while i < nops
      op = ops[i] ## i64
      if op == RB_OP_SELF || op == RB_OP_CALL_SELF_0 || op == RB_OP_CALL_SELF_1 || op == RB_OP_CALL_SELF_2 ||
         op == RB_OP_CALL_SELF_N || op == RB_OP_SEND || op == RB_OP_IVAR_GET || op == RB_OP_IVAR_SET ||
         op == RB_OP_CONST_GET || op == RB_OP_ARRAY_NEW || op == RB_OP_IDX_GET || op == RB_OP_IDX_SET ||
         op == RB_OP_STR_LIT || op == RB_OP_STR_PUSH || op == RB_OP_MATCH || op == RB_OP_TO_I || op == RB_OP_SIZE
        return false
      i += 1
    true

  # Compile a pure Ruby block lazily to flat-register bytecode when safe (no closure captures or non-local jumps).
  -> block_bytecode_1(blk)
    return nil if blk == nil || blk.native_fn != nil || @max_steps > 0
    if !blk.bc_tried
      blk.bc_tried = true
      blk.bytecode = rb_compile_block_bytecode(blk)
    bc = blk.bytecode
    (bc != nil && bc.arity == 1) ? bc : nil

  # Fast Flat-Register Bytecode VM execution engine (ZERO RbEnv / Hash / Array allocs per call!)
  -> exec_bytecode(bc, recv, fp, arg0, arg1, args_arr)
    fsize = bc.frame_size ## i64
    fp_i = fp ## i64
    raise_exc("SystemStackError", "stack level too deep") if fp_i > 12000
    if fp_i + fsize + 64 >= @reg_stack.size
      extra = @reg_stack.size
      ei = 0
      while ei < extra
        @reg_stack.push(nil)
        ei += 1
    stk = @reg_stack
    ar = bc.arity ## i64
    if ar == 1
      stk[fp_i] = arg0
    elsif ar == 2
      stk[fp_i] = arg0
      stk[fp_i + 1] = arg1
    elsif ar > 2 && args_arr != nil
      ai = 0
      while ai < ar
        stk[fp_i + ai] = args_arr[ai]
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
    rcls = class_of(recv)
    pc = 0 ## i64
    while pc < nops
      op = ops[pc] ## i64
      a = aa[pc] ## i64
      b = bb[pc] ## i64
      c = cc[pc] ## i64
      case op
      when RB_OP_RET
        return stk[fp_i + a]
      when RB_OP_MOV
        stk[fp_i + a] = stk[fp_i + b]
        pc += 1
      when RB_OP_INT
        stk[fp_i + a] = b
        pc += 1
      when RB_OP_CONST
        stk[fp_i + a] = consts[b]
        pc += 1
      when RB_OP_NIL
        stk[fp_i + a] = nil
        pc += 1
      when RB_OP_BOOL
        stk[fp_i + a] = (b != 0)
        pc += 1
      when RB_OP_SELF
        stk[fp_i + a] = recv
        pc += 1
      when RB_OP_ADD
        v1 = stk[fp_i + b]
        v2 = stk[fp_i + c]
        stk[fp_i + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 + v2) : eval_binop("+", v1, v2, @top_env)
        pc += 1
      when RB_OP_SUB
        v1 = stk[fp_i + b]
        v2 = stk[fp_i + c]
        stk[fp_i + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 - v2) : eval_binop("-", v1, v2, @top_env)
        pc += 1
      when RB_OP_MUL
        v1 = stk[fp_i + b]
        v2 = stk[fp_i + c]
        stk[fp_i + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 * v2) : eval_binop("*", v1, v2, @top_env)
        pc += 1
      when RB_OP_DIV
        v1 = stk[fp_i + b]
        v2 = stk[fp_i + c]
        stk[fp_i + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? rb_int_div(v1, v2) : eval_binop("/", v1, v2, @top_env)
        pc += 1
      when RB_OP_MOD
        v1 = stk[fp_i + b]
        v2 = stk[fp_i + c]
        stk[fp_i + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? rb_int_mod(v1, v2) : eval_binop("%", v1, v2, @top_env)
        pc += 1
      when RB_OP_ADD_IMM
        v1 = stk[fp_i + b]
        stk[fp_i + a] = v1.is_a?(Integer) ? (v1 + c) : rb_num_add(v1, c)
        pc += 1
      when RB_OP_SUB_IMM
        v1 = stk[fp_i + b]
        stk[fp_i + a] = v1.is_a?(Integer) ? (v1 - c) : rb_num_sub(v1, c)
        pc += 1
      when RB_OP_MUL_IMM
        v1 = stk[fp_i + b]
        stk[fp_i + a] = v1.is_a?(Integer) ? (v1 * c) : eval_binop("*", v1, c, @top_env)
        pc += 1
      when RB_OP_MOD_IMM
        v1 = stk[fp_i + b]
        if v1.is_a?(Integer)
          r = v1 % c
          stk[fp_i + a] = r < 0 ? (r + c) : r
        else
          stk[fp_i + a] = eval_binop("%", v1, c, @top_env)
        pc += 1
      when RB_OP_LT
        v1 = stk[fp_i + b]
        v2 = stk[fp_i + c]
        stk[fp_i + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 < v2) : (rb_cmp(v1, v2) < 0)
        pc += 1
      when RB_OP_LE
        v1 = stk[fp_i + b]
        v2 = stk[fp_i + c]
        stk[fp_i + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 <= v2) : (rb_cmp(v1, v2) <= 0)
        pc += 1
      when RB_OP_GT
        v1 = stk[fp_i + b]
        v2 = stk[fp_i + c]
        stk[fp_i + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 > v2) : (rb_cmp(v1, v2) > 0)
        pc += 1
      when RB_OP_GE
        v1 = stk[fp_i + b]
        v2 = stk[fp_i + c]
        stk[fp_i + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 >= v2) : (rb_cmp(v1, v2) >= 0)
        pc += 1
      when RB_OP_EQ
        v1 = stk[fp_i + b]
        v2 = stk[fp_i + c]
        stk[fp_i + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 == v2) : rb_eq?(v1, v2)
        pc += 1
      when RB_OP_NEQ
        v1 = stk[fp_i + b]
        v2 = stk[fp_i + c]
        stk[fp_i + a] = (v1.is_a?(Integer) && v2.is_a?(Integer)) ? (v1 != v2) : !rb_eq?(v1, v2)
        pc += 1
      when RB_OP_LT_IMM
        v1 = stk[fp_i + b]
        stk[fp_i + a] = v1.is_a?(Integer) ? (v1 < c) : (rb_cmp(v1, c) < 0)
        pc += 1
      when RB_OP_LE_IMM
        v1 = stk[fp_i + b]
        stk[fp_i + a] = v1.is_a?(Integer) ? (v1 <= c) : (rb_cmp(v1, c) <= 0)
        pc += 1
      when RB_OP_EQ_IMM
        v1 = stk[fp_i + b]
        stk[fp_i + a] = v1.is_a?(Integer) ? (v1 == c) : rb_eq?(v1, c)
        pc += 1
      when RB_OP_NOT
        v1 = stk[fp_i + b]
        stk[fp_i + a] = (v1 == nil || v1 == false)
        pc += 1
      when RB_OP_NEG
        v1 = stk[fp_i + b]
        stk[fp_i + a] = (v1.is_a?(Integer) || v1.is_a?(Float)) ? -v1 : call_method(v1, "-@", [], RB_EMPTY_KW, nil, @top_env)
        pc += 1
      when RB_OP_BIT_AND
        stk[fp_i + a] = stk[fp_i + b] & stk[fp_i + c]
        pc += 1
      when RB_OP_BIT_OR
        stk[fp_i + a] = stk[fp_i + b] | stk[fp_i + c]
        pc += 1
      when RB_OP_BIT_XOR
        stk[fp_i + a] = stk[fp_i + b] ^ stk[fp_i + c]
        pc += 1
      when RB_OP_SHL
        stk[fp_i + a] = stk[fp_i + b] << stk[fp_i + c]
        pc += 1
      when RB_OP_SHR
        stk[fp_i + a] = stk[fp_i + b] >> stk[fp_i + c]
        pc += 1
      when RB_OP_JMP
        pc = a
      when RB_OP_JMP_FALSE
        v1 = stk[fp_i + a]
        pc = (v1 == nil || v1 == false) ? b : pc + 1
      when RB_OP_JMP_TRUE
        v1 = stk[fp_i + a]
        pc = (v1 != nil && v1 != false) ? b : pc + 1
      when RB_OP_JGE
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
      when RB_OP_JGT
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
      when RB_OP_JGE_IMM
        v1 = stk[fp_i + a]
        if v1.is_a?(Integer)
          if v1 >= b
            pc = c
            next
        elsif rb_cmp(v1, b) >= 0
          pc = c
          next
        pc += 1
      when RB_OP_JGT_IMM
        v1 = stk[fp_i + a]
        if v1.is_a?(Integer)
          if v1 > b
            pc = c
            next
        elsif rb_cmp(v1, b) > 0
          pc = c
          next
        pc += 1
      when RB_OP_CALL_SELF_0
        stk[fp_i + a] = call_method(recv, names[b], [], RB_EMPTY_KW, nil, @top_env)
        pc += 1
      when RB_OP_CALL_SELF_1
        ep = @method_epoch
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
          stk[fp_i + a] = call_method(recv, names[b], [stk[fp_i + c]], RB_EMPTY_KW, nil, @top_env)
        pc += 1
      when RB_OP_CALL_SELF_2
        ep = @method_epoch
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
          stk[fp_i + a] = call_method(recv, names[b], [stk[fp_i + c], stk[fp_i + c + 1]], RB_EMPTY_KW, nil, @top_env)
        pc += 1
      when RB_OP_CALL_SELF_N
        argc = aux[pc]
        cargs = []
        k = 0
        while k < argc
          cargs.push(stk[fp_i + c + k])
          k += 1
        stk[fp_i + a] = call_method(recv, names[b], cargs, RB_EMPTY_KW, nil, @top_env)
        pc += 1
      when RB_OP_SEND
        spec = aux[pc]
        base = spec[0]
        argc = spec[1]
        sargs = []
        k = 0
        while k < argc
          sargs.push(stk[fp_i + base + k])
          k += 1
        stk[fp_i + a] = call_method(stk[fp_i + b], names[c], sargs, RB_EMPTY_KW, nil, @top_env)
        pc += 1
      when RB_OP_ARRAY_NEW
        arr = []
        k = 0
        while k < c
          arr.push(stk[fp_i + b + k])
          k += 1
        stk[fp_i + a] = arr
        pc += 1
      when RB_OP_IDX_GET
        arr = stk[fp_i + b]
        idx = stk[fp_i + c]
        if arr.is_a?(Array) && idx.is_a?(Integer) && @c_array.methods.size == 0
          ii = idx ## i64
          asz = arr.size ## i64
          ii = asz + ii if ii < 0
          stk[fp_i + a] = (ii >= 0 && ii < asz) ? arr[ii] : nil
        elsif arr.is_a?(RbMatchData) && @c_match_data.methods.size == 0
          stk[fp_i + a] = arr.get_group(idx)
        else
          stk[fp_i + a] = call_method(arr, '[]', [idx], RB_EMPTY_KW, nil, @top_env)
        pc += 1
      when RB_OP_IDX_SET
        arr = stk[fp_i + a]
        idx = stk[fp_i + b]
        val = stk[fp_i + c]
        if arr.is_a?(Array) && idx.is_a?(Integer) && @c_array.methods.size == 0
          ii = idx ## i64
          asz = arr.size ## i64
          ii = asz + ii if ii < 0
          if ii >= 0 && ii < asz
            arr[ii] = val
          else
            while arr.size <= ii
              arr.push(nil)
            arr[ii] = val
        else
          call_method(arr, '[]=', [idx, val], RB_EMPTY_KW, nil, @top_env)
        pc += 1
      when RB_OP_IVAR_GET
        stk[fp_i + a] = (recv.is_a?(RbObject) || recv.is_a?(RbModule)) ? recv.ivars[names[b]] : nil
        pc += 1
      when RB_OP_IVAR_SET
        recv.ivars[names[a]] = stk[fp_i + b] if recv.is_a?(RbObject) || recv.is_a?(RbModule)
        pc += 1
      when RB_OP_STR_LIT
        stk[fp_i + a] = RbString.new(consts[b], RB_ENC_UTF8, c != 0)
        pc += 1
      when RB_OP_STR_PUSH
        dst_v = stk[fp_i + a]
        rhs_v = stk[fp_i + b]
        if dst_v.is_a?(RbString)
          dst_v.check_mut!
          dst_v.data = dst_v.data + (rhs_v.is_a?(RbString) ? rhs_v.data : rb_to_s(rhs_v))
        elsif dst_v.is_a?(Array)
          dst_v.push(rhs_v)
        else
          call_method(dst_v, "<<", [rhs_v], RB_EMPTY_KW, nil, @top_env)
        pc += 1
      when RB_OP_CONST_GET
        stk[fp_i + a] = resolve_const(names[b], @top_env)
        pc += 1
      when RB_OP_MATCH
        rx = stk[fp_i + b]
        sv = stk[fp_i + c]
        if rx.is_a?(RbRegexp) && sv.is_a?(RbString) && @c_regexp.methods.size == 0
          md = rx.compiled.match_data(sv.data)
          rmd = md == nil ? nil : RbMatchData.new(rx, sv.data, md, 0)
          @last_match = rmd
          stk[fp_i + a] = rmd
        else
          stk[fp_i + a] = call_method(rx, "match", [sv], RB_EMPTY_KW, nil, @top_env)
        pc += 1
      when RB_OP_TO_I
        v1 = stk[fp_i + b]
        if v1.is_a?(RbString) && @c_string.methods.size == 0
          stk[fp_i + a] = rb_fast_str_to_i(v1.data)
        elsif v1.is_a?(Integer) && @c_integer.methods.size == 0
          stk[fp_i + a] = v1
        else
          stk[fp_i + a] = call_method(v1, "to_i", [], RB_EMPTY_KW, nil, @top_env)
        pc += 1
      when RB_OP_SIZE
        v1 = stk[fp_i + b]
        if v1.is_a?(Array) && @c_array.methods.size == 0
          stk[fp_i + a] = v1.size
        elsif v1.is_a?(RbString) && @c_string.methods.size == 0
          stk[fp_i + a] = v1.data.size
        elsif v1.is_a?(RbHash) && @c_hash.methods.size == 0
          stk[fp_i + a] = v1.size
        else
          stk[fp_i + a] = call_method(v1, "size", [], RB_EMPTY_KW, nil, @top_env)
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
    raise_exc("SystemStackError", "stack level too deep") if @call_depth >= 250
    @call_depth += 1
    @next_frame_id += 1
    fid = @next_frame_id
    @active_frames[fid] = true
    cref = m.def_env != nil ? m.def_env.cref : [m.owner]
    menv = RbEnv.new(m.is_closure ? m.def_env : nil, recv, blk, fid, cref)
    menv.vars["__super_owner__"] = m.owner
    menv.vars["__super_name__"] = m.name
    menv.vars["__super_args__"] = args
    begin
      bind_params(m.params, args, kw, blk, menv, m.def_env, true)
      hoist_locals(m.body, menv)
      res = eval_stmts(m.body, menv)
      @active_frames.delete(fid)
      @call_depth -= 1
      return res
    rescue sig
      @active_frames.delete(fid)
      @call_depth -= 1
      if sig.is_a?(RbSignal) && sig.kind == :return && sig.target_id == fid
        return sig.val
      raise sig

  -> lookup_method_on(recv, nm)
    if recv.is_a?(RbClass)
      cur = recv
      while cur != nil
        if cur.singleton_cls != nil
          sm = cur.singleton_cls.lookup_method(nm)
          return sm if sm != nil
        cur = cur.superclass
      return @c_class.lookup_method(nm)
    if (recv.is_a?(RbObject) || recv.is_a?(RbModule)) && recv.singleton_cls != nil
      sm = recv.singleton_cls.lookup_method(nm)
      return sm if sm != nil
    elsif @singleton_map.size > 0 && (recv.is_a?(Array) || recv.is_a?(RbString) || recv.is_a?(RbHash) || recv.is_a?(RbRange) || recv.is_a?(RbRegexp) || recv.is_a?(RbProc) || recv.is_a?(RbMatchData) || recv.is_a?(RbEnumerator))
      oid = wvalue_bits(recv) ## int
      if @singleton_map.has_key?(oid)
        sm = @singleton_map[oid].lookup_method(nm)
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

    # 3c. Comparable module fallback for any class that includes Comparable and defines #<=>
    if class_of(recv).ancestors().include?(@c_comparable) &&
       (nm == "<" || nm == "<=" || nm == ">" || nm == ">=" || nm == "==" || nm == "between?" || nm == "clamp")
      if nm == "=="
        return true if recv == args[0]
        c = nil
        begin
          c = call_method(recv, "<=>", [args[0]], RB_EMPTY_KW, nil, env)
        rescue sig
          return false if sig.is_a?(RbSignal) && sig.kind == :raise
          raise sig
        return c == 0
      if nm == "between?"
        c1 = call_method(recv, "<=>", [args[0]], RB_EMPTY_KW, nil, env)
        raise_exc("ArgumentError", "comparison of " + class_of(recv).name + " with " + class_of(args[0]).name + " failed") if c1 == nil
        return false if c1 < 0
        c2 = call_method(recv, "<=>", [args[1]], RB_EMPTY_KW, nil, env)
        raise_exc("ArgumentError", "comparison of " + class_of(recv).name + " with " + class_of(args[1]).name + " failed") if c2 == nil
        return c2 <= 0
      if nm == "clamp"
        lo = args[0]
        hi = args.size > 1 ? args[1] : nil
        if lo.is_a?(RbRange)
          hi = lo.hi
          lo = lo.lo
        if lo != nil
          c1 = call_method(recv, "<=>", [lo], RB_EMPTY_KW, nil, env)
          return lo if c1 != nil && c1 < 0
        if hi != nil
          c2 = call_method(recv, "<=>", [hi], RB_EMPTY_KW, nil, env)
          return hi if c2 != nil && c2 > 0
        return recv
      c = call_method(recv, "<=>", [args[0]], RB_EMPTY_KW, nil, env)
      raise_exc("ArgumentError", "comparison of " + class_of(recv).name + " with " + class_of(args[0]).name + " failed") if c == nil
      return c < 0 if nm == "<"
      return c <= 0 if nm == "<="
      return c > 0 if nm == ">"
      return c >= 0 if nm == ">="

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
        if recv == @c_class
          sup = args.size > 0 && args[0].is_a?(RbClass) ? args[0] : @c_object
          cls = RbClass.new("#<Class:anon>", sup)
          if blk != nil
            cenv = RbEnv.new(blk.env, cls, nil, 0, [cls])
            eval_stmts(blk.body, cenv)
          return [true, cls]
        if recv == @c_module
          mod = RbModule.new("#<Module:anon>")
          if blk != nil
            menv = RbEnv.new(blk.env, mod, nil, 0, [mod])
            eval_stmts(blk.body, menv)
          return [true, mod]
        if recv == @c_struct
          # Struct.new(:a, :b)
          sc = RbClass.new("Struct", @c_struct)
          mems = []
          args.each ->(a) mems.push(rb_to_s(a))
          sc.struct_members = mems
          mems.each ->(mn)
            sc.methods[mn] = make_attr_reader(mn, sc)
            sc.methods[mn + "="] = make_attr_writer(mn, sc)
          if blk != nil
            cenv = RbEnv.new(nil, sc, nil, 0, [sc])
            eval_stmts(blk.body, cenv)
          return [true, sc]
        if recv == @c_proc
          raise_exc("ArgumentError", "tried to create Proc object without a block") if blk == nil
          return [true, blk]
        if recv == @c_array
          n = args.size > 0 ? args[0] : 0
          if blk == nil
            return [true, Array.new(n, args.size > 1 ? args[1] : nil)]
          out = Array.new(n, nil)
          bc = block_bytecode_1(blk)
          if bc != nil
            bs = blk.self_obj
            i = 0 ## i64
            while i < n
              out[i] = exec_bytecode(bc, bs, 0, i, nil, nil)
              i += 1
          else
            i = 0
            while i < n
              out[i] = call_proc(blk, [i])
              i += 1
          return [true, out]
        if recv == @c_hash
          h = RbHash.new
          h.default_val = args[0] if args.size > 0
          h.default_proc = blk if blk != nil
          return [true, h]
        if recv == @c_stringio
          return [true, RbStringIO.new(args.size > 0 ? rb_to_s(args[0]) : "")]
        if recv == @c_string
          return [true, RbString.new(args.size > 0 ? rb_to_s(args[0]) : "")]
        if recv == @c_regexp
          return [true, rb_make_regexp(rb_to_s(args[0]), args.size > 1 ? rb_to_s(args[1]) : "")]
        if recv == @c_range
          return [true, RbRange.new(args[0], args[1], args.size > 2 && rb_truthy?(args[2]))]
        if recv == @c_enumerator
          return [true, RbEnumerator.new(nil, nil, "each", nil, blk)]
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
          dc.methods[mn] = make_attr_reader(mn, dc)
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
          recv.methods[an] = make_attr_reader(an, recv)
          if args.size > 1 && rb_truthy?(args[1])
            recv.methods[an + "="] = make_attr_writer(an, recv)
          return [true, nil]
        args.each ->(a)
          an = rb_to_s(a)
          if nm == "attr_reader" || nm == "attr_accessor"
            recv.methods[an] = make_attr_reader(an, recv)
          if nm == "attr_writer" || nm == "attr_accessor"
            recv.methods[an + "="] = make_attr_writer(an, recv)
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
          recv.methods[mnm] = RbMethod.new(mnm, pr.params, pr.body, pr.env, recv, nil, true)
        return [true, RbSym.new(mnm)]
      if nm == "ancestors" then return [true, recv.ancestors()]
      if nm == "name" then return [true, RbString.new(recv.name)]
      if nm == "private" || nm == "protected" || nm == "public" || nm == "module_function"
        if nm == "module_function"
          if args.size == 0
            recv.mod_fn_mode = true
          else
            sc = singleton_class_of(recv)
            args.each ->(a)
              an = rb_to_s(a)
              m = recv.methods[an]
              sc.methods[an] = m if m != nil
        elsif args.size == 0
          recv.mod_fn_mode = false
        return [true, args.size == 1 ? args[0] : (args.size > 1 ? args : recv)]
      if nm == "private_constant" || nm == "public_constant" || nm == "deprecate_constant" || nm == "ruby2_keywords" || nm == "private_class_method" || nm == "public_class_method"
        return [true, recv]
      if nm == "class_variables"
        inc_inh = args.size == 0 || rb_truthy?(args[0])
        out = []
        seen = {}
        ms = inc_inh ? recv.ancestors() : [recv]
        ms.each ->(m)
          ks = m.cvars.keys
          ki = 0
          while ki < ks.size
            k = ks[ki]
            if !seen.has_key?(k)
              seen[k] = true
              out.push(RbSym.new(k))
            ki += 1
        return [true, out]
      if nm == "class_variable_defined?"
        cvn = rb_to_s(args[0])
        anc = recv.ancestors()
        i = 0
        while i < anc.size
          return [true, true] if anc[i].cvars.has_key?(cvn)
          i += 1
        return [true, false]
      if nm == "class_variable_get"
        cvn = rb_to_s(args[0])
        anc = recv.ancestors()
        i = 0
        while i < anc.size
          return [true, anc[i].cvars[cvn]] if anc[i].cvars.has_key?(cvn)
          i += 1
        raise_exc("NameError", "uninitialized class variable " + cvn + " in " + recv.name)
      if nm == "class_variable_set"
        cvn = rb_to_s(args[0])
        recv.cvars[cvn] = args[1]
        return [true, args[1]]
      if nm == "remove_class_variable"
        cvn = rb_to_s(args[0])
        raise_exc("NameError", "class variable " + cvn + " not defined for " + recv.name) if !recv.cvars.has_key?(cvn)
        v = recv.cvars[cvn]
        recv.cvars.delete(cvn)
        return [true, v]
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
      if nm == "class_eval" || nm == "module_eval"
        if blk != nil
          cenv = RbEnv.new(blk.env, recv, blk.env.block, blk.def_frame_id, [recv], recv)
          return [true, eval_stmts(blk.body, cenv)]
        if args.size > 0
          fnm = args.size > 1 ? rb_to_s(args[1]) : "(eval)"
          cenv = RbEnv.new(env, recv, nil, env.frame_id, [recv], recv)
          return [true, eval_node(rb_parse_safe(rb_to_s(args[0]), fnm), cenv)]
        return [true, nil]
      if nm == "class_exec" || nm == "module_exec"
        if blk != nil
          cenv = RbEnv.new(blk.env, recv, blk.env.block, blk.def_frame_id, [recv], recv)
          bind_params(blk.params, args, kw, nil, cenv, blk.env)
          return [true, eval_stmts(blk.body, cenv)]
        return [true, nil]
      if nm == "constants"
        inc_inh = args.size == 0 || rb_truthy?(args[0])
        out = []
        seen = {}
        ms = inc_inh ? recv.ancestors() : [recv]
        ms.each ->(m)
          m.constants.each ->(k, v)
            if !seen.has_key?(k)
              seen[k] = true
              out.push(RbSym.new(k))
        return [true, out]
      if nm == "instance_methods" || nm == "public_instance_methods"
        inc_inh = args.size == 0 || rb_truthy?(args[0])
        out = []
        seen = {}
        ms = inc_inh ? recv.ancestors() : [recv]
        ms.each ->(m)
          m.methods.each ->(k, v)
            if !seen.has_key?(k)
              seen[k] = true
              out.push(RbSym.new(k))
        return [true, out]
      if nm == "private_instance_methods" || nm == "protected_instance_methods"
        return [true, []]
      if nm == "method_defined?" || nm == "public_method_defined?"
        mnm = rb_to_s(args[0])
        inc_inh = args.size < 2 || rb_truthy?(args[1])
        return [true, inc_inh ? (recv.lookup_method(mnm) != nil) : recv.methods.has_key?(mnm)]
      if nm == "private_method_defined?" || nm == "protected_method_defined?"
        return [true, false]
      if nm == "undef_method" || nm == "remove_method"
        args.each ->(a) recv.methods.delete(rb_to_s(a))
        @method_epoch += 1
        return [true, recv]
      if nm == "include?"
        return [true, args[0].is_a?(RbModule) && recv.ancestors().include?(args[0]) && recv != args[0]]
      if nm == "<" || nm == "<=" || nm == ">" || nm == ">=" || nm == "<=>"
        o = args[0]
        return [true, nil] if !o.is_a?(RbModule)
        if recv == o
          return [true, 0] if nm == "<=>"
          return [true, nm == "<=" || nm == ">="]
        if recv.ancestors().include?(o)
          return [true, -1] if nm == "<=>"
          return [true, nm == "<" || nm == "<="]
        if o.ancestors().include?(recv)
          return [true, 1] if nm == "<=>"
          return [true, nm == ">" || nm == ">="]
        return [true, nil]
      if recv == @c_file || recv == @c_file_test
        case nm
        when "expand_path", "absolute_path", "realpath"
          p = rb_to_s(args[0])
          if args.size > 1 && args[1] != nil
            return [true, RbString.new(File.expand_path(p, rb_to_s(args[1])))]
          return [true, RbString.new(File.expand_path(p))]
        when "join"
          parts = []
          args.each ->(a)
            if a.is_a?(Array)
              a.each ->(x) parts.push(rb_to_s(x))
            else
              parts.push(rb_to_s(a))
          return [true, RbString.new(parts.size == 0 ? "" : parts.join("/").gsub("//", "/"))]
        when "dirname"
          p = rb_to_s(args[0])
          while p.size > 1 && p.ends_with?("/")
            p = p.slice(0, p.size - 1)
          sl = p.rindex("/")
          return [true, RbString.new(sl == nil ? "." : (sl == 0 ? "/" : p.slice(0, sl)))]
        when "basename"
          p = rb_to_s(args[0])
          while p.size > 1 && p.ends_with?("/")
            p = p.slice(0, p.size - 1)
          sl = p.rindex("/")
          b = sl == nil ? p : (sl == p.size - 1 ? "/" : p.slice(sl + 1, p.size - sl - 1))
          if args.size > 1
            ext = rb_to_s(args[1])
            if ext == ".*"
              d = b.rindex(".")
              b = b.slice(0, d) if d != nil && d > 0
            elsif b.ends_with?(ext)
              b = b.slice(0, b.size - ext.size)
          return [true, RbString.new(b)]
        when "extname"
          p = rb_to_s(args[0])
          sl = p.rindex("/")
          b = sl == nil ? p : p.slice(sl + 1, p.size - sl - 1)
          d = b.rindex(".")
          return [true, RbString.new((d == nil || d == 0 || d == b.size - 1) ? "" : b.slice(d, b.size - d))]
        when "exist?", "exists?" then return [true, File.exists?(rb_to_s(args[0]))]
        when "file?" then return [true, File.exists?(rb_to_s(args[0])) && File.type(rb_to_s(args[0])) == "file"]
        when "directory?" then return [true, File.exists?(rb_to_s(args[0])) && File.type(rb_to_s(args[0])) == "directory"]
        when "symlink?" then return [true, File.exists?(rb_to_s(args[0])) && File.type(rb_to_s(args[0])) == "symlink"]
        when "readable?" then return [true, File.exists?(rb_to_s(args[0]))]
        when "writable?" then return [true, File.exists?(rb_to_s(args[0]))]
        when "size", "size?"
          p = rb_to_s(args[0])
          return [true, nil] if nm == "size?" && !File.exists?(p)
          return [true, File.size(p)]
        when "read", "binread"
          return [true, RbString.new(File.read(rb_to_s(args[0])), nm == "binread" ? RB_ENC_BINARY : RB_ENC_UTF8)]
        when "write", "binwrite"
          data = rb_to_s(args[1])
          File.write(rb_to_s(args[0]), data)
          return [true, data.size]
        when "delete", "unlink"
          n_del = 0
          args.each ->(a)
            File.delete(rb_to_s(a)) if File.exists?(rb_to_s(a))
            n_del += 1
          return [true, n_del]
      if recv == @c_dir
        case nm
        when "pwd", "getwd" then return [true, RbString.new(File.expand_path("."))]
        when "chdir"
          return [true, blk != nil ? call_proc(blk, [args.size > 0 ? args[0] : RbString.new(File.expand_path("."))]) : 0]
        when "exist?", "exists?" then return [true, File.exists?(rb_to_s(args[0])) && File.type(rb_to_s(args[0])) == "directory"]
        when "entries", "children"
          ents = File.entries(rb_to_s(args[0]))
          out = []
          ents.each ->(e)
            next if nm == "children" && (e == "." || e == "..")
            out.push(RbString.new(e))
          return [true, out]
      if recv == @c_io
        if nm == "popen"
          cmd_arg = args[0]
          cmd_s = ""
          if cmd_arg.is_a?(Array)
            parts = []
            cmd_arg.each ->(ca)
              cs = rb_to_s(ca)
              parts.push("'" + cs.gsub("'", "'\\''") + "'")
            cmd_s = parts.join(" ")
          else
            cmd_s = rb_to_s(cmd_arg)
          p_out = ""
          begin
            p_out = OS.capture(cmd_s)
          rescue e
            p_out = ""
          sio = RbStringIO.new(p_out == nil ? "" : p_out)
          if blk != nil
            r_io = call_proc(blk, [sio])
            sio.closed = true
            return [true, r_io]
          return [true, sio]
      if recv == @c_thread
        case nm
        when "report_on_exception" then return [true, @c_thread.ivars["@report_on_exception"]]
        when "report_on_exception="
          @c_thread.ivars["@report_on_exception"] = rb_truthy?(args[0])
          return [true, args[0]]
        when "current", "main"
          @main_thread = RbObject.new(@c_thread) if @main_thread == nil
          return [true, @main_thread]
        when "list"
          @main_thread = RbObject.new(@c_thread) if @main_thread == nil
          return [true, [@main_thread]]
        when "pass" then return [true, nil]
      if recv == @c_gc
        case nm
        when "start" then return [true, nil]
        when "stress" then return [true, false]
        when "stress=" then return [true, args[0]]
        when "disable", "enable" then return [true, false]
      if recv == @c_hash
        case nm
        when "ruby2_keywords_hash?"
          return [true, args.size > 0 && args[0].is_a?(RbHash) && args[0].ruby2_kw]
        when "ruby2_keywords_hash"
          raise_exc("TypeError", "no implicit conversion into Hash") if args.size == 0 || !args[0].is_a?(RbHash)
          nh = args[0].dup()
          nh.ruby2_kw = true
          return [true, nh]
      if recv == @c_warning
        case nm
        when "[]" then return [true, false]
        when "[]=" then return [true, args[1]]
        when "warn" then return [true, nil]
      if recv == @c_regexp && nm == "linear_time?"
        return [true, true]
    if recv == @c_env_obj
      case nm
      when "[]"
        v = Env.get(rb_to_s(args[0]), nil)
        return [true, v == nil ? nil : RbString.new(v)]
      when "[]="
        k = rb_to_s(args[0])
        if args[1] == nil
          Env.delete(k)
          return [true, nil]
        Env.set(k, rb_to_s(args[1]))
        return [true, args[1]]
      when "key?", "has_key?", "include?", "member?"
        return [true, Env.get(rb_to_s(args[0]), nil) != nil]
      when "fetch"
        k = rb_to_s(args[0])
        v = Env.get(k, nil)
        return [true, RbString.new(v)] if v != nil
        return [true, call_proc(blk, [args[0]])] if blk != nil
        return [true, args[1]] if args.size >= 2
        raise_exc("KeyError", "key not found: " + rb_inspect(args[0]))
      when "delete"
        k = rb_to_s(args[0])
        v = Env.get(k, nil)
        Env.delete(k) if v != nil
        return [true, v == nil ? (blk != nil ? call_proc(blk, [args[0]]) : nil) : RbString.new(v)]
    if recv.is_a?(Integer) || recv.is_a?(Float) || recv.is_a?(RbRational) || recv.is_a?(RbComplex)
      r_num = dispatch_numeric(recv, nm, args, kw, blk, env)
      return r_num if r_num[0]
    if recv.is_a?(RbString)
      r_str = dispatch_string(recv, nm, args, kw, blk, env)
      return r_str if r_str[0]
    if recv.is_a?(Array)
      r_arr = dispatch_array(recv, nm, args, kw, blk, env)
      return r_arr if r_arr[0]
    if recv.is_a?(RbHash)
      r_hsh = dispatch_hash(recv, nm, args, kw, blk, env)
      return r_hsh if r_hsh[0]
    r_misc = dispatch_misc(recv, nm, args, kw, blk, env)
    return r_misc if r_misc[0]
    dispatch_kernel_object(recv, nm, args, kw, blk, env)

  -> rb_to_int(v, env)
    return v if v.is_a?(Integer)
    return v.to_i if v.is_a?(Float) || v.is_a?(RbRational)
    if v != nil && v != true && v != false && !v.is_a?(RbString) && !v.is_a?(RbSym)
      if lookup_method_on(v, "to_int") != nil
        iv = call_method(v, "to_int", [], RB_EMPTY_KW, nil, env)
        return iv if iv.is_a?(Integer)
        raise_exc("TypeError", "can't convert " + class_of(v).name + " to Integer (" + class_of(v).name + "#to_int gives " + class_of(iv).name + ")")
    raise_exc("TypeError", "no implicit conversion of " + class_of(v).name + " into Integer")

  -> rb_to_ary(v, env)
    return v if v.is_a?(Array)
    if v != nil && v != true && v != false && !v.is_a?(Integer) && !v.is_a?(Float) && !v.is_a?(RbString) && !v.is_a?(RbSym)
      if lookup_method_on(v, "to_ary") != nil
        av = call_method(v, "to_ary", [], RB_EMPTY_KW, nil, env)
        return av if av.is_a?(Array)
        raise_exc("TypeError", "can't convert " + class_of(v).name + " to Array (" + class_of(v).name + "#to_ary gives " + class_of(av).name + ")")
    raise_exc("TypeError", "no implicit conversion of " + class_of(v).name + " into Array")

  -> rb_cmp_any(a, b, env)
    c = rb_cmp(a, b)
    return c if c != nil
    if lookup_method_on(a, "<=>") != nil
      return call_method(a, "<=>", [b], RB_EMPTY_KW, nil, env)
    nil

  -> rb_join_array(arr, sep, seen, env)
    oid = wvalue_bits(arr) ## int
    raise_exc("ArgumentError", "recursive array join") if seen.has_key?(oid)
    seen[oid] = true
    parts = []
    i = 0
    while i < arr.size
      x = arr[i]
      if x.is_a?(Array)
        parts.push(rb_join_array(x, sep, seen, env))
      else
        parts.push(rb_to_s(x))
      i += 1
    seen.delete(oid)
    parts.join(sep)

  -> materialize_enum(en, env)
    return en.items if en.items != nil
    items = []
    if en.gen_proc != nil
      y_obj = RbObject.new(@c_object)
      y_fn = ->(r, aa, kk, bb)
        items.push(aa.size <= 1 ? (aa.size == 1 ? aa[0] : nil) : aa)
        r
      sc = singleton_class_of(y_obj)
      sc.methods["<<"] = RbMethod.new("<<", [], nil, nil, sc, y_fn)
      sc.methods["yield"] = RbMethod.new("yield", [], nil, nil, sc, y_fn)
      call_proc(en.gen_proc, [y_obj])
      en.items = items
      return items
    if en.recv_obj != nil
      coll_fn = ->(pargs, pkw)
        items.push(pargs.size == 1 ? pargs[0] : (pargs.size == 0 ? nil : pargs))
        nil
      coll_blk = RbProc.new([], nil, env, en.recv_obj, false, coll_fn, 0)
      eargs = en.enum_args == nil ? [] : en.enum_args
      call_method(en.recv_obj, en.meth_name, eargs, RB_EMPTY_KW, coll_blk, env)
      en.items = items
      return items
    en.items = items
    items

  -> dispatch_numeric(recv, nm, args, kw, blk, env)
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
      when "gcd"
        b_i = rb_to_int(args[0], env)
        return [true, rb_gcd(recv, b_i)]
      when "lcm"
        b_i = rb_to_int(args[0], env)
        return [true, 0] if recv == 0 || b_i == 0
        g = rb_gcd(recv, b_i)
        p = (recv * b_i) / g
        return [true, p < 0 ? -p : p]
      when "divmod"
        b_i = rb_to_int(args[0], env)
        return [true, [rb_int_div(recv, b_i), rb_int_mod(recv, b_i)]]
      when "fdiv" then return [true, recv.to_f / rb_to_f(args[0])]
      when "pow"
        exp_i = rb_to_int(args[0], env)
        if args.size == 2
          md = rb_to_int(args[1], env)
          raise_exc("ZeroDivisionError", "divided by 0") if md == 0
          raise_exc("RangeError", "Integer#pow() 1st argument cannot be negative when 2nd argument is present") if exp_i < 0
          res = 1; b = rb_int_mod(recv, md); e = exp_i
          while e > 0
            res = rb_int_mod(res * b, md) if (e & 1) == 1
            b = rb_int_mod(b * b, md)
            e = e >> 1
          return [true, rb_int_mod(res, md)]
        return [true, rb_num_pow(recv, exp_i)]
      when "digits"
        raise_exc("DomainError", "out of domain") if recv < 0
        base = args.size > 0 ? rb_to_int(args[0], env) : 10
        raise_exc("ArgumentError", "invalid radix " + base.to_s) if base < 2
        return [true, [0]] if recv == 0
        out = []; v = recv
        while v > 0
          out.push(v % base); v = v / base
        return [true, out]
      when "times"
        if blk == nil
          cap_n = recv > 100000 ? 100000 : (recv < 0 ? 0 : recv)
          a = []
          i = 0
          while i < cap_n
            a.push(i)
            i += 1
          return [true, RbEnumerator.new(a)]
        i = 0
        while i < recv
          if @max_steps > 0
            @steps += 1
            raise_exc("RuntimeError", "step limit exceeded") if @steps > @max_steps
          begin
            call_proc(blk, [i])
          rescue sig
            return [true, sig.val] if sig.is_a?(RbSignal) && sig.kind == :break
            raise sig
          i += 1
        return [true, recv]
      when "upto"
        hi = rb_to_int(args[0], env)
        if blk == nil
          cnt = hi - recv + 1
          cnt = 100000 if cnt > 100000
          a = []
          i = 0
          while i < cnt
            a.push(recv + i)
            i += 1
          return [true, RbEnumerator.new(a)]
        i = recv
        while i <= hi
          if @max_steps > 0
            @steps += 1
            raise_exc("RuntimeError", "step limit exceeded") if @steps > @max_steps
          begin
            call_proc(blk, [i])
          rescue sig
            return [true, sig.val] if sig.is_a?(RbSignal) && sig.kind == :break
            raise sig
          i += 1
        return [true, recv]
      when "downto"
        lo = rb_to_int(args[0], env)
        if blk == nil
          cnt = recv - lo + 1
          cnt = 100000 if cnt > 100000
          a = []
          i = 0
          while i < cnt
            a.push(recv - i)
            i += 1
          return [true, RbEnumerator.new(a)]
        i = recv
        while i >= lo
          if @max_steps > 0
            @steps += 1
            raise_exc("RuntimeError", "step limit exceeded") if @steps > @max_steps
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
    [false, nil]

  -> dispatch_string(recv, nm, args, kw, blk, env)
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
      when "+@" then return [true, recv.frozen ? RbString.new(s, recv.encoding, false) : recv]
      when "-@" then return [true, recv.frozen ? recv : RbString.new(s, recv.encoding, true)]
      when "b" then return [true, RbString.new(s, RB_ENC_BINARY, false)]
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
      when "lstrip"
        li = 0
        while li < s.size && (s.byte_at(li) == 32 || s.byte_at(li) == 9 || s.byte_at(li) == 10 || s.byte_at(li) == 13 || s.byte_at(li) == 11 || s.byte_at(li) == 12)
          li += 1
        return [true, RbString.new(li < s.size ? s.slice(li, s.size - li) : "", recv.encoding)]
      when "rstrip"
        ri = s.size
        while ri > 0 && (s.byte_at(ri - 1) == 32 || s.byte_at(ri - 1) == 9 || s.byte_at(ri - 1) == 10 || s.byte_at(ri - 1) == 13 || s.byte_at(ri - 1) == 11 || s.byte_at(ri - 1) == 12 || s.byte_at(ri - 1) == 0)
          ri -= 1
        return [true, RbString.new(ri > 0 ? s.slice(0, ri) : "", recv.encoding)]
      when "chomp"
        sep = args.size > 0 ? rb_to_s(args[0]) : "\n"
        cs = s
        if sep == "\n"
          cs = cs.slice(0, cs.size - 1) if cs.ends_with?("\n")
          cs = cs.slice(0, cs.size - 1) if cs.ends_with?("\r")
        elsif cs.ends_with?(sep)
          cs = cs.slice(0, cs.size - sep.size)
        return [true, RbString.new(cs, recv.encoding)]
      when "reverse"
        ch = s.chars
        rev_sb = StringBuffer()
        i = ch.size - 1
        while i >= 0
          rev_sb << ch[i]
          i -= 1
        return [true, RbString.new(rev_sb.to_s, recv.encoding)]
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
      when "ord" then return [true, s.size > 0 ? s.chars[0].codepoints.to_a[0] : 0]
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
    [false, nil]

  -> dispatch_misc(recv, nm, args, kw, blk, env)
    # --- Encoding ---
    if recv.is_a?(RbEncoding)
      case nm
      when "name", "to_s" then return [true, RbString.new(recv.name)]
      when "names" then return [true, [RbString.new(recv.name)]]
      when "ascii_compatible?" then return [true, true]
      when "dummy?" then return [true, false]
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
      when "call", '[]', "yield" then return [true, call_proc(recv, args, kw, blk)]
      when "lambda?" then return [true, recv.is_lambda]
      when "arity" then return [true, recv.params.size]
      when "curry"
        target_arity = (args.size > 0 && args[0].is_a?(Integer)) ? args[0] : recv.params.size
        return [true, make_curried(recv, [], target_arity, env)]
      when "ruby2_keywords"
        return [true, recv]
      when "to_proc"
        return [true, recv]
    if recv.is_a?(RbRange) || recv.is_a?(RbEnumerator) || recv.is_a?(RbBinding) || recv.is_a?(RbStringIO) || recv.is_a?(RbException) || (recv.is_a?(RbObject) && recv.klass == @c_process_status)
      return dispatch_range_enum_io(recv, nm, args, kw, blk, env)
    [false, nil]

  -> dispatch_array(recv, nm, args, kw, blk, env)
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
        nf = rb_to_int(args[0], env)
        raise_exc("ArgumentError", "negative array size") if nf < 0
        return [true, recv.slice(0, nf > recv.size ? recv.size : nf)]
      when "last"
        return [true, recv.size == 0 ? nil : recv[recv.size - 1]] if args.size == 0
        nl = rb_to_int(args[0], env)
        raise_exc("ArgumentError", "negative array size") if nl < 0
        k = nl > recv.size ? recv.size : nl
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
      when "replace"
        other = rb_to_ary(args[0], env)
        cp = other.dup
        recv.clear
        cp.each ->(x) recv.push(x)
        return [true, recv]
      when "clear"
        recv.clear
        return [true, recv]
      when "concat"
        args.each ->(a)
          oa = rb_to_ary(a, env).dup
          oa.each ->(x) recv.push(x)
        return [true, recv]
      when '[]', "slice"
        if args[0].is_a?(RbRange)
          lo = args[0].lo == nil ? 0 : rb_to_int(args[0].lo, env)
          lo = recv.size + lo if lo < 0
          hi = args[0].hi == nil ? recv.size - 1 : rb_to_int(args[0].hi, env)
          hi = recv.size + hi if hi < 0
          hi -= 1 if args[0].excl && args[0].hi != nil
          return [true, nil] if lo < 0 || lo > recv.size
          return [true, []] if lo == recv.size || hi < lo
          hi = recv.size - 1 if hi >= recv.size
          return [true, recv.slice(lo, hi - lo + 1)]
        idx = rb_to_int(args[0], env)
        idx = recv.size + idx if idx < 0
        if args.size == 1
          return [true, (idx < 0 || idx >= recv.size) ? nil : recv[idx]]
        ln = rb_to_int(args[1], env)
        return [true, nil] if ln < 0 || idx < 0 || idx > recv.size
        return [true, []] if idx == recv.size || ln == 0
        ln = recv.size - idx if idx + ln > recv.size
        return [true, recv.slice(idx, ln)]
      when '[]='
        if args[0].is_a?(RbRange)
          lo = args[0].lo == nil ? 0 : rb_to_int(args[0].lo, env)
          lo = recv.size + lo if lo < 0
          raise_exc("RangeError", "out of range") if lo < 0
          hi = args[0].hi == nil ? recv.size - 1 : rb_to_int(args[0].hi, env)
          hi = recv.size + hi if hi < 0
          hi -= 1 if args[0].excl && args[0].hi != nil
          rep = args[1].is_a?(Array) ? args[1] : (args[1] == nil ? [] : [args[1]])
          pre = lo <= recv.size ? recv.slice(0, lo) : recv + Array.new(lo - recv.size, nil)
          suf_start = hi + 1
          suf_start = lo if suf_start < lo
          suf = suf_start < recv.size ? recv.slice(suf_start, recv.size - suf_start) : []
          comb = pre + rep + suf
          recv.clear
          comb.each ->(x) recv.push(x)
          return [true, args[1]]
        idx = rb_to_int(args[0], env)
        idx = recv.size + idx if idx < 0
        raise_exc("IndexError", "index too small") if idx < 0
        if args.size == 3
          ln = rb_to_int(args[1], env)
          raise_exc("IndexError", "negative length") if ln < 0
          rep = args[2].is_a?(Array) ? args[2] : (args[2] == nil ? [] : [args[2]])
          pre = idx <= recv.size ? recv.slice(0, idx) : recv + Array.new(idx - recv.size, nil)
          suf_start = idx + ln
          suf = suf_start < recv.size ? recv.slice(suf_start, recv.size - suf_start) : []
          comb = pre + rep + suf
          recv.clear
          comb.each ->(x) recv.push(x)
          return [true, args[2]]
        while recv.size <= idx
          recv.push(nil)
        recv[idx] = args[1]
        return [true, args[1]]
      when "fetch"
        idx = rb_to_int(args[0], env)
        idx = recv.size + idx if idx < 0
        return [true, recv[idx]] if idx >= 0 && idx < recv.size
        return [true, call_proc(blk, [args[0]])] if blk != nil
        return [true, args[1]] if args.size >= 2
        raise_exc("IndexError", "index " + idx.to_s + " outside of array bounds")
      when "dig"
        cur = recv
        args.each ->(k)
          return [true, nil] if cur == nil
          cur = call_method(cur, '[]', [k], {}, nil, env)
        return [true, cur]
      when "join"
        sep = args.size > 0 && args[0] != nil ? rb_to_s(args[0]) : ""
        return [true, RbString.new(rb_join_array(recv, sep, {}, env))]
      when "reverse"
        out = []; i = recv.size - 1
        while i >= 0
          out.push(recv[i]); i -= 1
        return [true, out]
      when "flatten"
        out = []
        d_lim = args.size > 0 && args[0] != nil ? rb_to_int(args[0], env) : -1
        rb_flatten_into(recv, out, d_lim)
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
        return [true, rb_sort_array(recv, blk, env)]
      when "sort_by"
        return [true, RbEnumerator.new(nil, recv, nm, args)] if blk == nil
        pairs = []
        recv.each ->(x) pairs.push([call_proc(blk, [x]), x])
        sorted = rb_sort_pairs(pairs, env)
        return [true, sorted.map ->(p) p[1]]
      when "min", "max"
        return [true, nil] if recv.size == 0
        best = recv[0]
        i = 1
        while i < recv.size
          c = blk != nil ? call_proc(blk, [recv[i], best]) : rb_cmp_any(recv[i], best, env)
          raise_exc("ArgumentError", "comparison failed") if c == nil
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
        return [true, RbEnumerator.new(nil, recv, nm, args)] if blk == nil
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
        return [true, RbEnumerator.new(nil, recv, nm, args)] if blk == nil
        bc = block_bytecode_1(blk)
        if bc != nil
          return [true, exec_bytecode_iter(bc, recv, 0)] if bc_pure_inline?(bc)
          n = recv.size ## i64
          out = Array.new(n, nil)
          bs = blk.self_obj
          i = 0 ## i64
          while i < n
            out[i] = exec_bytecode(bc, bs, 0, recv[i], nil, nil)
            i += 1
          return [true, out]
        out = []
        recv.each ->(x)
          begin
            out.push(call_proc(blk, [x]))
          rescue sig
            return [true, sig.val] if sig.is_a?(RbSignal) && sig.kind == :break
            raise sig
        return [true, out]
      when "filter_map"
        return [true, RbEnumerator.new(nil, recv, nm, args)] if blk == nil
        bc = block_bytecode_1(blk)
        if bc != nil
          out = []
          n = recv.size ## i64
          bs = blk.self_obj
          i = 0 ## i64
          while i < n
            r = exec_bytecode(bc, bs, 0, recv[i], nil, nil)
            out.push(r) if r != nil && r != false
            i += 1
          return [true, out]
        out = []
        recv.each ->(x)
          r = call_proc(blk, [x])
          out.push(r) if rb_truthy?(r)
        return [true, out]
      when "flat_map", "collect_concat"
        return [true, RbEnumerator.new(nil, recv, nm, args)] if blk == nil
        out = []
        recv.each ->(x)
          r = call_proc(blk, [x])
          if r.is_a?(Array)
            r.each ->(e) out.push(e)
          else
            out.push(r)
        return [true, out]
      when "select", "filter", "find_all"
        return [true, RbEnumerator.new(nil, recv, nm, args)] if blk == nil
        bc = block_bytecode_1(blk)
        if bc != nil
          return [true, exec_bytecode_iter(bc, recv, 1)] if bc_pure_inline?(bc)
          out = []
          n = recv.size ## i64
          bs = blk.self_obj
          i = 0 ## i64
          while i < n
            x = recv[i]
            r = exec_bytecode(bc, bs, 0, x, nil, nil)
            out.push(x) if r != nil && r != false
            i += 1
          return [true, out]
        out = []
        recv.each ->(x) out.push(x) if rb_truthy?(call_proc(blk, [x]))
        return [true, out]
      when "reject"
        return [true, RbEnumerator.new(nil, recv, nm, args)] if blk == nil
        bc = block_bytecode_1(blk)
        if bc != nil
          return [true, exec_bytecode_iter(bc, recv, 2)] if bc_pure_inline?(bc)
          out = []
          n = recv.size ## i64
          bs = blk.self_obj
          i = 0 ## i64
          while i < n
            x = recv[i]
            r = exec_bytecode(bc, bs, 0, x, nil, nil)
            out.push(x) if r == nil || r == false
            i += 1
          return [true, out]
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
    [false, nil]

  -> dispatch_hash(recv, nm, args, kw, blk, env)
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
    [false, nil]

  -> dispatch_range_enum_io(recv, nm, args, kw, blk, env)
    # --- Range ---
    if recv.is_a?(RbRange)
      case nm
      when "begin" then return [true, recv.lo]
      when "end" then return [true, recv.hi]
      when "first"
        raise_exc("RangeError", "cannot get the first element of beginless range") if recv.lo == nil
        return [true, recv.lo] if args.size == 0
        n_take = args[0]
        raise_exc("ArgumentError", "negative array size") if n_take < 0
        out = []
        cur = recv.lo
        i = 0
        while i < n_take
          if recv.hi != nil
            c = rb_cmp(cur, recv.hi)
            break if c == nil || (recv.excl ? c >= 0 : c > 0)
          out.push(cur)
          cur = cur.is_a?(Integer) ? cur + 1 : call_method(cur, "succ", [], RB_EMPTY_KW, nil, env)
          i += 1
        return [true, out]
      when "last"
        raise_exc("RangeError", "cannot get the last element of endless range") if recv.hi == nil
        return [true, recv.hi] if args.size == 0
        return dispatch_builtin(recv.to_a(), "last", args, kw, blk, env)
      when "exclude_end?" then return [true, recv.excl]
      when "include?", "cover?", "member?" then return [true, recv.include?(args[0])]
      when "size"
        return [true, nil] if recv.lo == nil
        return [true, ~1.0 / ~0.0] if recv.hi == nil || (recv.hi.is_a?(Float) && recv.hi > ~1.0e308)
        if recv.lo.is_a?(Integer) && recv.hi.is_a?(Integer)
          sz = recv.excl ? (recv.hi - recv.lo) : (recv.hi - recv.lo + 1)
          return [true, sz < 0 ? 0 : sz]
        return [true, nil]
      when "to_a", "entries"
        raise_exc("RangeError", "cannot convert endless range to an array") if recv.hi == nil || (recv.hi.is_a?(Float) && recv.hi > ~1.0e308)
        raise_exc("TypeError", "can't iterate from NilClass") if recv.lo == nil
        return [true, recv.to_a()]
      when "take"
        return dispatch_range_enum_io(recv, "first", args, kw, blk, env)
      when "each"
        raise_exc("TypeError", "can't iterate from NilClass") if recv.lo == nil
        return [true, RbEnumerator.new(recv.hi == nil ? [] : recv.to_a())] if blk == nil
        cur = recv.lo
        while true
          if @max_steps > 0
            @steps += 1
            raise_exc("RuntimeError", "step limit exceeded") if @steps > @max_steps
          if recv.hi != nil
            c = rb_cmp(cur, recv.hi)
            break if c == nil || (recv.excl ? c >= 0 : c > 0)
          begin
            call_proc(blk, [cur])
          rescue sig
            return [true, sig.val] if sig.is_a?(RbSignal) && sig.kind == :break
            raise sig
          cur = cur.is_a?(Integer) ? cur + 1 : call_method(cur, "succ", [], RB_EMPTY_KW, nil, env)
        return [true, recv]
      when "map", "collect", "select", "reject", "reduce", "inject", "sum", "count", "any?", "all?", "find", "drop", "min", "max"
        raise_exc("RangeError", "cannot convert endless range to an array") if recv.hi == nil && (nm == "map" || nm == "collect" || nm == "to_a")
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

    # --- Binding ---
    if recv.is_a?(RbBinding)
      case nm
      when "eval"
        fnm = args.size > 1 ? rb_to_s(args[1]) : "(eval)"
        ast = rb_parse_safe(rb_to_s(args[0]), fnm)
        return [true, eval_node(ast, recv.env)]
      when "receiver" then return [true, recv.env.self_obj]
      when "local_variables"
        out = []
        e = recv.env
        seen = {}
        while e != nil
          ks = e.vars.keys
          ki = 0
          while ki < ks.size
            k = ks[ki]
            if !k.starts_with?("__") && !seen.has_key?(k)
              seen[k] = true
              out.push(RbSym.new(k))
            ki += 1
          e = e.parent
        return [true, out]
      when "local_variable_defined?"
        return [true, recv.env.has?(rb_to_s(args[0]))]
      when "local_variable_get"
        ln = rb_to_s(args[0])
        raise_exc("NameError", "local variable `" + ln + "' is not defined") if !recv.env.has?(ln)
        return [true, recv.env.get(ln)]
      when "local_variable_set"
        return [true, recv.env.set(rb_to_s(args[0]), args[1])]

    # --- StringIO ---
    if recv.is_a?(RbStringIO)
      case nm
      when "string" then return [true, RbString.new(recv.buf, recv.encoding)]
      when "string="
        recv.buf = rb_to_s(args[0])
        recv.pos = 0
        return [true, args[0]]
      when "read"
        return [true, args.size > 0 && args[0] != nil ? nil : RbString.new("", recv.encoding)] if recv.pos >= recv.buf.size
        if args.size > 0 && args[0] != nil
          ln = args[0]
          avail = recv.buf.size - recv.pos
          take = ln < avail ? ln : avail
          chunk = recv.buf.slice(recv.pos, take)
          recv.pos += take
          return [true, RbString.new(chunk, recv.encoding)]
        chunk = recv.buf.slice(recv.pos, recv.buf.size - recv.pos)
        recv.pos = recv.buf.size
        return [true, RbString.new(chunk, recv.encoding)]
      when "gets", "readline"
        if recv.pos >= recv.buf.size
          raise_exc("EOFError", "end of file reached") if nm == "readline"
          return [true, nil]
        nl = recv.buf.index("\n", recv.pos)
        if nl == nil
          chunk = recv.buf.slice(recv.pos, recv.buf.size - recv.pos)
          recv.pos = recv.buf.size
          return [true, RbString.new(chunk, recv.encoding)]
        chunk = recv.buf.slice(recv.pos, nl - recv.pos + 1)
        recv.pos = nl + 1
        return [true, RbString.new(chunk, recv.encoding)]
      when "readlines"
        out = []
        while recv.pos < recv.buf.size
          r = dispatch_builtin(recv, "gets", [], RB_EMPTY_KW, nil, env)
          break if r[1] == nil
          out.push(r[1])
        return [true, out]
      when "each", "each_line"
        while recv.pos < recv.buf.size
          r = dispatch_builtin(recv, "gets", [], RB_EMPTY_KW, nil, env)
          break if r[1] == nil
          call_proc(blk, [r[1]]) if blk != nil
        return [true, recv]
      when "write"
        written = 0
        args.each ->(a)
          s = rb_to_s(a)
          if recv.pos >= recv.buf.size
            recv.buf = recv.buf + s
          else
            pre = recv.buf.slice(0, recv.pos)
            suf_i = recv.pos + s.size
            suf = suf_i < recv.buf.size ? recv.buf.slice(suf_i, recv.buf.size - suf_i) : ""
            recv.buf = pre + s + suf
          recv.pos += s.size
          written += s.size
        return [true, written]
      when "<<"
        s = rb_to_s(args[0])
        dispatch_builtin(recv, "write", [RbString.new(s)], RB_EMPTY_KW, nil, env)
        return [true, recv]
      when "puts"
        if args.size == 0
          dispatch_builtin(recv, "write", [RbString.new("\n")], RB_EMPTY_KW, nil, env)
        else
          args.each ->(a)
            s = rb_to_s(a)
            s = s + "\n" if !s.ends_with?("\n")
            dispatch_builtin(recv, "write", [RbString.new(s)], RB_EMPTY_KW, nil, env)
        return [true, nil]
      when "print"
        args.each ->(a) dispatch_builtin(recv, "write", [a], RB_EMPTY_KW, nil, env)
        return [true, nil]
      when "pos", "tell" then return [true, recv.pos]
      when "pos="
        recv.pos = args[0]
        return [true, args[0]]
      when "rewind"
        recv.pos = 0
        return [true, 0]
      when "eof", "eof?" then return [true, recv.pos >= recv.buf.size]
      when "size", "length" then return [true, recv.buf.size]
      when "close"
        recv.closed = true
        return [true, nil]
      when "closed?" then return [true, recv.closed]
      when "flush", "binmode" then return [true, recv]
      when "sync" then return [true, true]
      when "sync=" then return [true, args[0]]
      when "external_encoding" then return [true, recv.encoding]
      when "internal_encoding" then return [true, nil]
      when "set_encoding"
        recv.encoding = args[0].is_a?(RbEncoding) ? args[0] : rb_find_encoding(rb_to_s(args[0])) if args.size > 0
        return [true, recv]
      when "truncate"
        sz = args[0]
        recv.buf = sz < recv.buf.size ? recv.buf.slice(0, sz) : recv.buf
        return [true, sz]

    # --- Exception ---
    if recv.is_a?(RbException)
      return [true, RbString.new(recv.message)] if nm == "message"
      return [true, recv.backtrace] if nm == "backtrace"
    if recv.is_a?(RbObject) && recv.klass == @c_process_status
      st_ec = recv.ivars["__exitstatus__"]
      case nm
      when "exitstatus", "to_i" then return [true, st_ec]
      when "success?" then return [true, st_ec == 0]
      when "exited?" then return [true, true]
      when "signaled?", "stopped?", "coredump?" then return [true, false]
      when "termsig", "stopsig" then return [true, nil]
      when "pid" then return [true, 1]
      when "==" then return [true, args[0] == st_ec || (args[0].is_a?(RbObject) && args[0].klass == @c_process_status && args[0].ivars["__exitstatus__"] == st_ec)]
    [false, nil]

  -> dispatch_kernel_object(recv, nm, args, kw, blk, env)
    # --- Kernel / Object universal methods ---
    case nm
    when "puts"
      if args.size == 0
        @stdout.push("")
        @out_buf << "\n"
      else
        args.each ->(a)
          if a.is_a?(Array)
            a.each ->(x)
              xs = rb_to_s(x)
              @stdout.push(xs)
              @out_buf << xs
              @out_buf << "\n" if !xs.ends_with?("\n")
          else
            xs = rb_to_s(a)
            @stdout.push(xs)
            @out_buf << xs
            @out_buf << "\n" if !xs.ends_with?("\n")
      return [true, nil]
    when "print"
      args.each ->(a)
        xs = rb_to_s(a)
        @stdout.push(xs)
        @out_buf << xs
      return [true, nil]
    when "p"
      args.each ->(a)
        xs = rb_inspect(a)
        @stdout.push(xs)
        @out_buf << xs
        @out_buf << "\n"
      return [true, args.size == 1 ? args[0] : args]
    when "raise", "fail"
      if args.size == 0
        if @last_exc != nil
          raise RbSignal.new(:raise, nil, 0, @last_exc)
        raise_exc("RuntimeError", "")
      elsif args[0].is_a?(RbException)
        @last_exc = args[0]
        raise RbSignal.new(:raise, nil, 0, args[0])
      elsif args[0].is_a?(RbClass)
        raise_exc(args[0].name, args.size > 1 ? rb_to_s(args[1]) : "")
      else
        raise_exc("RuntimeError", rb_to_s(args[0]))
    when "lambda"
      raise_exc("ArgumentError", "tried to create Proc object without a block") if blk == nil
      return [true, RbProc.new(blk.params, blk.body, blk.env, blk.self_obj, true, blk.native_fn, blk.def_frame_id)]
    when "proc"
      raise_exc("ArgumentError", "tried to create Proc object without a block") if blk == nil
      return [true, blk]
    when "block_given?" then return [true, env.block != nil]
    when "Rational" then return [true, RbRational.new(args[0], args.size > 1 ? args[1] : 1)]
    when "Complex" then return [true, RbComplex.new(args[0], args.size > 1 ? args[1] : 0)]
    when "Integer" then return [true, args[0].is_a?(Integer) ? args[0] : rb_parse_int(rb_to_s(args[0]).strip, args.size > 1 ? args[1] : 10)]
    when "Float" then return [true, args[0].is_a?(Float) ? args[0] : rb_to_s(args[0]).strip.to_f]
    when "String" then return [true, RbString.new(rb_to_s(args[0]))]
    when "Array" then return [true, args[0].is_a?(Array) ? args[0] : (args[0] == nil ? [] : [args[0]])]
    when "sprintf", "format" then return [true, rb_sprintf(rb_to_s(args[0]), args.slice(1, args.size - 1))]
    when "eval"
      target_env = (args.size > 1 && args[1].is_a?(RbBinding)) ? args[1].env : env
      fnm = args.size > 2 ? rb_to_s(args[2]) : "(eval)"
      ast = rb_parse_safe(rb_to_s(args[0]), fnm)
      begin
        return [true, eval_node(ast, target_env)]
      rescue sig
        if sig.is_a?(RbSignal)
          if sig.kind == :retry
            raise_exc("SyntaxError", "Invalid retry")
          if sig.kind == :break
            raise_exc("LocalJumpError", "break from proc-closure")
          if sig.kind == :return && (sig.target_id == 0 || !@active_frames.has_key?(sig.target_id))
            raise_exc("LocalJumpError", "unexpected return")
        raise sig
    when "binding"
      return [true, RbBinding.new(env)]
    when "exit", "exit!"
      st = 0
      if args.size > 0
        if args[0] == true
          st = 0
        elsif args[0] == false
          st = 1
        elsif args[0].is_a?(Integer)
          st = args[0]
      exc = RbException.new("SystemExit", "exit", @constants["SystemExit"])
      exc.ivars["__status__"] = st
      @last_exc = exc
      raise RbSignal.new(:raise, nil, 0, exc)
    when "abort"
      @stdout.push(rb_to_s(args[0])) if args.size > 0
      exc = RbException.new("SystemExit", args.size > 0 ? rb_to_s(args[0]) : "abort", @constants["SystemExit"])
      exc.ivars["__status__"] = 1
      @last_exc = exc
      raise RbSignal.new(:raise, nil, 0, exc)
    when "require"
      return [true, rb_require(rb_to_s(args[0]), nil)]
    when "require_relative"
      cur_f = @file_stack.size > 0 ? @file_stack[@file_stack.size - 1] : "(eval)"
      sl = cur_f.rindex("/")
      base_d = sl == nil ? "." : (sl == 0 ? "/" : cur_f.slice(0, sl))
      return [true, rb_require(rb_to_s(args[0]), base_d)]
    when "load"
      p = resolve_require_path(rb_to_s(args[0]), nil)
      raise_exc("LoadError", "cannot load such file -- " + rb_to_s(args[0])) if p == nil
      eval_file(p)
      return [true, true]
    when "__dir__"
      cur_f = @file_stack.size > 0 ? @file_stack[@file_stack.size - 1] : "(eval)"
      return [true, nil] if cur_f == "(eval)"
      sl = cur_f.rindex("/")
      return [true, RbString.new(sl == nil ? "." : (sl == 0 ? "/" : cur_f.slice(0, sl)))]
    when "at_exit"
      @at_exit_blocks.push(blk) if blk != nil
      return [true, blk]
    when "caller"
      cur_f = @file_stack.size > 0 ? @file_stack[@file_stack.size - 1] : "(eval)"
      return [true, [RbString.new(cur_f + ":1:in `<main>'")]]
    when "warn"
      return [true, nil]
    when "singleton_class"
      return [true, singleton_class_of(recv)]
    when "object_id", "__id__"
      return [true, wvalue_bits(recv) ## int]
    when "instance_exec"
      if blk != nil
        dt = recv.is_a?(RbModule) ? singleton_class_of(recv) : (recv.is_a?(RbObject) ? singleton_class_of(recv) : nil)
        ienv = RbEnv.new(blk.env, recv, blk.env.block, blk.def_frame_id, blk.env.cref, dt)
        bind_params(blk.params, args, kw, nil, ienv, blk.env)
        return [true, eval_stmts(blk.body, ienv)]
      return [true, nil]
    when "instance_variables"
      out = []
      if recv.is_a?(RbObject) || recv.is_a?(RbModule)
        recv.ivars.each ->(k, v) out.push(RbSym.new(k)) if !k.starts_with?("__")
      return [true, out]
    when "instance_variable_defined?"
      return [true, (recv.is_a?(RbObject) || recv.is_a?(RbModule)) && recv.ivars.has_key?(rb_to_s(args[0]))]
    when "remove_instance_variable"
      ivn = rb_to_s(args[0])
      if (recv.is_a?(RbObject) || recv.is_a?(RbModule)) && recv.ivars.has_key?(ivn)
        v = recv.ivars[ivn]
        recv.ivars.delete(ivn)
        return [true, v]
      raise_exc("NameError", "instance variable " + ivn + " not defined")
    when "loop"
      return [true, RbEnumerator.new([])] if blk == nil
      while true
        begin
          call_proc(blk, [])
        rescue sig
          return [true, sig.val] if sig.is_a?(RbSignal) && sig.kind == :break
          return [true, nil] if sig.is_a?(RbSignal) && sig.kind == :raise && sig.exc.klass.subclass_of?(@constants["StopIteration"])
          raise sig
    when "local_variables"
      out = []
      e = env
      seen = {}
      while e != nil
        e.vars.each ->(k, v)
          if !k.starts_with?("__") && !seen.has_key?(k)
            seen[k] = true
            out.push(RbSym.new(k))
        e = e.parent
      return [true, out]
    when "`"
      cmd = rb_to_s(args[0])
      out = ""
      rc_st = 0
      begin
        out = OS.capture(cmd + "; printf '\\n__RB_RC__:%d' $?")
        if out != nil
          mk = out.rindex("\n__RB_RC__:")
          if mk != nil
            rc_st = out.slice(mk + 11, out.size - mk - 11).strip.to_i
            out = out.slice(0, mk)
      rescue e
        out = ""
        rc_st = 127
      pst = RbObject.new(@c_process_status)
      pst.ivars["__exitstatus__"] = rc_st
      @globals["$?"] = pst
      return [true, RbString.new(out == nil ? "" : out)]
    when "system"
      cmd_s = ""
      if args.size > 1
        parts = []
        args.each ->(ca)
          cs = rb_to_s(ca)
          parts.push("'" + cs.gsub("'", "'\\''") + "'")
        cmd_s = parts.join(" ")
      else
        cmd_s = rb_to_s(args[0])
      r_bt = dispatch_kernel_object(recv, "`", [RbString.new(cmd_s)], RB_EMPTY_KW, nil, env)
      st_obj = @globals["$?"]
      ec = st_obj != nil ? st_obj.ivars["__exitstatus__"] : 1
      @out_buf << r_bt[1].data if r_bt[1].is_a?(RbString)
      return [true, ec == 0]
    when "catch"
      tag = args.size > 0 ? args[0] : RbObject.new(@c_object)
      @catch_tags.push(tag)
      begin
        res = call_proc(blk, [tag])
        @catch_tags.pop
        return [true, res]
      rescue sig
        @catch_tags.pop
        if sig.is_a?(RbSignal) && sig.kind == :throw && rb_eql?(sig.exc, tag)
          return [true, sig.val]
        raise sig
    when "throw"
      tag = args.size > 0 ? args[0] : nil
      val = args.size > 1 ? args[1] : nil
      found_tag = false
      ti = @catch_tags.size - 1
      while ti >= 0
        if rb_eql?(@catch_tags[ti], tag)
          found_tag = true
          break
        ti -= 1
      if !found_tag
        raise_exc("UncaughtThrowError", "uncaught throw " + rb_inspect(tag))
      raise RbSignal.new(:throw, val, 0, tag)
    when "instance_eval"
      if blk != nil
        dt = recv.is_a?(RbModule) ? singleton_class_of(recv) : (recv.is_a?(RbObject) ? singleton_class_of(recv) : nil)
        ienv = RbEnv.new(blk.env, recv, blk.env.block, blk.def_frame_id, blk.env.cref, dt)
        return [true, eval_stmts(blk.body, ienv)]
      if args.size > 0
        fnm = args.size > 1 ? rb_to_s(args[1]) : "(eval)"
        dt = recv.is_a?(RbModule) ? singleton_class_of(recv) : (recv.is_a?(RbObject) ? singleton_class_of(recv) : nil)
        ienv = RbEnv.new(env, recv, nil, env.frame_id, env.cref, dt)
        return [true, eval_node(rb_parse_safe(rb_to_s(args[0]), fnm), ienv)]
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
      return [true, true] if lookup_method_on(recv, tn) != nil
      return [true, true] if has_builtin_method?(recv, tn)
      rm = lookup_method_on(recv, "respond_to_missing?")
      if rm != nil
        inc_all = args.size > 1 ? rb_truthy?(args[1]) : false
        return [true, rb_truthy?(invoke_rb_method(rm, recv, [RbSym.new(tn), inc_all], RB_EMPTY_KW, nil))]
      return [true, false]
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
    when "hash" then return [true, rb_hash_code(recv)]
    when "instance_variable_get"
      return [true, (recv.is_a?(RbObject) || recv.is_a?(RbModule)) ? recv.ivars[rb_to_s(args[0])] : nil]
    when "instance_variable_set"
      recv.ivars[rb_to_s(args[0])] = args[1] if recv.is_a?(RbObject) || recv.is_a?(RbModule)
      return [true, args[1]]
    when "public", "private", "protected", "include", "define_method"
      if recv == @main_obj
        return dispatch_builtin(@c_object, nm, args, kw, blk, env)
      return [false, nil]
    else
      return [false, nil]

  -> make_attr_reader(an, owner)
    ivar = "@" + an
    getter_fn = ->(r, aa, kk, bb)
      raise_exc("ArgumentError", "wrong number of arguments (given " + aa.size.to_s + ", expected 0)") if aa.size > 0
      r.ivars[ivar]
    RbMethod.new(an, [], nil, nil, owner, getter_fn)

  -> make_attr_writer(an, owner)
    ivar = "@" + an
    setter_fn = ->(r, aa, kk, bb)
      raise_exc("ArgumentError", "wrong number of arguments (given " + aa.size.to_s + ", expected 1)") if aa.size != 1
      r.ivars[ivar] = aa[0]
    RbMethod.new(an + "=", [], nil, nil, owner, setter_fn)

  -> has_builtin_method?(recv, nm)
    return true if nm == "class" || nm == "is_a?" || nm == "kind_of?" || nm == "instance_of?" || nm == "nil?" || nm == "to_s" || nm == "inspect" || nm == "respond_to?" || nm == "send" || nm == "public_send" || nm == "__send__" || nm == "dup" || nm == "clone" || nm == "freeze" || nm == "frozen?" || nm == "eql?" || nm == "equal?" || nm == "==" || nm == "!=" || nm == "===" || nm == "!" || nm == "object_id" || nm == "__id__" || nm == "singleton_class" || nm == "tap" || nm == "then" || nm == "yield_self" || nm == "itself" || nm == "extend" || nm == "instance_eval" || nm == "instance_exec" || nm == "instance_variables" || nm == "instance_variable_defined?" || nm == "instance_variable_get" || nm == "instance_variable_set" || nm == "remove_instance_variable" || nm == "puts" || nm == "print" || nm == "p" || nm == "raise" || nm == "fail" || nm == "lambda" || nm == "proc" || nm == "block_given?" || nm == "eval" || nm == "require" || nm == "require_relative" || nm == "load" || nm == "loop" || nm == "catch" || nm == "throw" || nm == "sprintf" || nm == "format" || nm == "at_exit" || nm == "warn" || nm == "local_variables" || nm == "__dir__"
    if recv.is_a?(RbClass)
      return true if nm == "new" || nm == "superclass" || nm == "allocate"
    if recv.is_a?(RbModule)
      return true if nm == "name" || nm == "ancestors" || nm == "include" || nm == "prepend" || nm == "include?" || nm == "attr_reader" || nm == "attr_writer" || nm == "attr_accessor" || nm == "alias_method" || nm == "define_method" || nm == "public" || nm == "private" || nm == "protected" || nm == "module_function" || nm == "const_get" || nm == "const_set" || nm == "const_defined?" || nm == "remove_const" || nm == "constants" || nm == "class_eval" || nm == "module_eval" || nm == "class_exec" || nm == "module_exec" || nm == "instance_methods" || nm == "public_instance_methods" || nm == "private_instance_methods" || nm == "protected_instance_methods" || nm == "method_defined?" || nm == "undef_method" || nm == "remove_method" || nm == "<" || nm == "<=" || nm == ">" || nm == ">=" || nm == "<=>"
      if recv == @c_file || recv == @c_file_test
        return true if nm == "expand_path" || nm == "absolute_path" || nm == "realpath" || nm == "join" || nm == "dirname" || nm == "basename" || nm == "extname" || nm == "exist?" || nm == "exists?" || nm == "file?" || nm == "directory?" || nm == "symlink?" || nm == "readable?" || nm == "writable?" || nm == "size" || nm == "size?" || nm == "read" || nm == "binread" || nm == "write" || nm == "binwrite" || nm == "delete" || nm == "unlink"
      if recv == @c_dir
        return true if nm == "pwd" || nm == "getwd" || nm == "exist?" || nm == "exists?" || nm == "entries" || nm == "children"
      if recv == @c_thread
        return true if nm == "report_on_exception" || nm == "report_on_exception=" || nm == "current" || nm == "main" || nm == "list" || nm == "pass"
      if recv == @c_gc
        return true if nm == "start" || nm == "stress" || nm == "stress=" || nm == "disable" || nm == "enable"
      if recv == @c_math
        return true if nm == "sqrt" || nm == "sin" || nm == "cos" || nm == "tan" || nm == "log" || nm == "log2" || nm == "log10" || nm == "exp" || nm == "hypot" || nm == "atan2"
      if recv == @c_json
        return true if nm == "parse" || nm == "generate" || nm == "dump"
    if recv.is_a?(RbString)
      return true if nm == "length" || nm == "size" || nm == "bytesize" || nm == "empty?" || nm == "upcase" || nm == "downcase" || nm == "capitalize" || nm == "swapcase" || nm == "reverse" || nm == "strip" || nm == "lstrip" || nm == "rstrip" || nm == "chomp" || nm == "chop" || nm == "split" || nm == "chars" || nm == "bytes" || nm == "codepoints" || nm == "lines" || nm == "include?" || nm == "start_with?" || nm == "end_with?" || nm == "index" || nm == "rindex" || nm == "sub" || nm == "gsub" || nm == "scan" || nm == "match" || nm == "match?" || nm == "[]" || nm == "[]=" || nm == "slice" || nm == "+" || nm == "*" || nm == "<<" || nm == "concat" || nm == "to_i" || nm == "to_f" || nm == "to_sym" || nm == "intern" || nm == "to_str" || nm == "encoding" || nm == "force_encoding" || nm == "encode" || nm == "b" || nm == "ord" || nm == "count" || nm == "tr" || nm == "delete" || nm == "squeeze" || nm == "ljust" || nm == "rjust" || nm == "center" || nm == "each_char" || nm == "each_byte" || nm == "each_line" || nm == "replace" || nm == "clear" || nm == "unpack" || nm == "unpack1" || nm == "%"
    if recv.is_a?(Array)
      return true if nm == "length" || nm == "size" || nm == "empty?" || nm == "push" || nm == "<<" || nm == "pop" || nm == "shift" || nm == "unshift" || nm == "first" || nm == "last" || nm == "[]" || nm == "[]=" || nm == "at" || nm == "fetch" || nm == "slice" || nm == "each" || nm == "each_with_index" || nm == "reverse_each" || nm == "map" || nm == "collect" || nm == "map!" || nm == "collect!" || nm == "select" || nm == "filter" || nm == "find_all" || nm == "reject" || nm == "find" || nm == "detect" || nm == "any?" || nm == "all?" || nm == "none?" || nm == "one?" || nm == "include?" || nm == "index" || nm == "rindex" || nm == "count" || nm == "inject" || nm == "reduce" || nm == "sum" || nm == "min" || nm == "max" || nm == "minmax" || nm == "sort" || nm == "sort!" || nm == "sort_by" || nm == "reverse" || nm == "reverse!" || nm == "uniq" || nm == "uniq!" || nm == "compact" || nm == "compact!" || nm == "flatten" || nm == "flatten!" || nm == "zip" || nm == "join" || nm == "concat" || nm == "+" || nm == "-" || nm == "*" || nm == "&" || nm == "|" || nm == "take" || nm == "drop" || nm == "delete" || nm == "delete_at" || nm == "delete_if" || nm == "keep_if" || nm == "clear" || nm == "replace" || nm == "insert" || nm == "rotate" || nm == "transpose" || nm == "product" || nm == "combination" || nm == "permutation" || nm == "group_by" || nm == "partition" || nm == "flat_map" || nm == "collect_concat" || nm == "each_slice" || nm == "each_cons" || nm == "to_a" || nm == "to_ary" || nm == "to_h" || nm == "pack" || nm == "fill" || nm == "sample" || nm == "shuffle" || nm == "assoc" || nm == "rassoc" || nm == "bsearch"
    if recv.is_a?(RbHash)
      return true if nm == "length" || nm == "size" || nm == "empty?" || nm == "[]" || nm == "[]=" || nm == "store" || nm == "fetch" || nm == "delete" || nm == "key?" || nm == "has_key?" || nm == "include?" || nm == "member?" || nm == "value?" || nm == "has_value?" || nm == "keys" || nm == "values" || nm == "each" || nm == "each_pair" || nm == "each_key" || nm == "each_value" || nm == "map" || nm == "select" || nm == "filter" || nm == "reject" || nm == "merge" || nm == "merge!" || nm == "update" || nm == "invert" || nm == "to_a" || nm == "to_h" || nm == "to_hash" || nm == "clear" || nm == "replace" || nm == "dig" || nm == "slice" || nm == "except" || nm == "transform_keys" || nm == "transform_values" || nm == "default" || nm == "default=" || nm == "default_proc" || nm == "any?" || nm == "all?" || nm == "none?" || nm == "count" || nm == "first" || nm == "assoc" || nm == "rassoc" || nm == "flatten" || nm == "compact" || nm == "shift" || nm == "key" || nm == "values_at"
    if recv.is_a?(Integer) || recv.is_a?(Float)
      return true if nm == "+" || nm == "-" || nm == "*" || nm == "/" || nm == "%" || nm == "**" || nm == "<=>" || nm == "<" || nm == "<=" || nm == ">" || nm == ">=" || nm == "abs" || nm == "zero?" || nm == "positive?" || nm == "negative?" || nm == "to_i" || nm == "to_int" || nm == "to_f" || nm == "to_r" || nm == "to_c" || nm == "floor" || nm == "ceil" || nm == "round" || nm == "truncate" || nm == "divmod" || nm == "fdiv" || nm == "between?" || nm == "clamp" || nm == "nan?" || nm == "infinite?" || nm == "finite?" || nm == "even?" || nm == "odd?" || nm == "times" || nm == "upto" || nm == "downto" || nm == "step" || nm == "chr" || nm == "gcd" || nm == "lcm" || nm == "pow" || nm == "digits" || nm == "bit_length" || nm == "size" || nm == "next" || nm == "succ" || nm == "pred" || nm == "div" || nm == "modulo" || nm == "remainder" || nm == "integer?"
    if recv.is_a?(RbSym)
      return true if nm == "to_sym" || nm == "intern" || nm == "to_proc" || nm == "name" || nm == "id2name" || nm == "length" || nm == "size" || nm == "empty?" || nm == "upcase" || nm == "downcase" || nm == "capitalize" || nm == "swapcase" || nm == "start_with?" || nm == "end_with?" || nm == "match" || nm == "match?" || nm == "=~" || nm == "<=>" || nm == "[]" || nm == "slice"
    if recv.is_a?(RbProc)
      return true if nm == "call" || nm == "[]" || nm == "===" || nm == "yield" || nm == "arity" || nm == "lambda?" || nm == "to_proc" || nm == "curry" || nm == "parameters" || nm == "source_location" || nm == "<<" || nm == ">>"
    if recv.is_a?(RbRange)
      return true if nm == "begin" || nm == "first" || nm == "end" || nm == "last" || nm == "exclude_end?" || nm == "each" || nm == "to_a" || nm == "include?" || nm == "member?" || nm == "cover?" || nm == "size" || nm == "count" || nm == "min" || nm == "max" || nm == "step" || nm == "map" || nm == "select" || nm == "reject" || nm == "any?" || nm == "all?" || nm == "inject" || nm == "reduce"
    if recv.is_a?(RbRegexp)
      return true if nm == "match" || nm == "match?" || nm == "=~" || nm == "===" || nm == "source" || nm == "options" || nm == "casefold?" || nm == "names" || nm == "named_captures" || nm == "encoding"
    if recv.is_a?(RbMatchData)
      return true if nm == "[]" || nm == "to_a" || nm == "captures" || nm == "named_captures" || nm == "names" || nm == "string" || nm == "pre_match" || nm == "post_match" || nm == "begin" || nm == "end" || nm == "offset" || nm == "length" || nm == "size" || nm == "regexp" || nm == "values_at"
    if recv.is_a?(RbException)
      return true if nm == "message" || nm == "backtrace" || nm == "cause" || nm == "full_message" || nm == "exception" || nm == "set_backtrace"
    if recv == @c_env_obj
      return true if nm == "[]" || nm == "[]=" || nm == "key?" || nm == "has_key?" || nm == "include?" || nm == "member?" || nm == "fetch" || nm == "delete"
    if class_of(recv).ancestors().include?(@c_comparable)
      return true if nm == "<" || nm == "<=" || nm == ">" || nm == ">=" || nm == "==" || nm == "between?" || nm == "clamp"
    if class_of(recv).ancestors().include?(@c_enumerable)
      return true if nm == "map" || nm == "collect" || nm == "select" || nm == "find_all" || nm == "reject" || nm == "find" || nm == "detect" || nm == "any?" || nm == "all?" || nm == "none?" || nm == "inject" || nm == "reduce" || nm == "to_a" || nm == "entries" || nm == "count" || nm == "first" || nm == "take" || nm == "drop" || nm == "include?" || nm == "min" || nm == "max" || nm == "sum"
    false

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

  -> rb_sort_array(arr, blk, env = nil)
    out = arr.dup
    # Insertion/merge sort using Ruby <=> or block
    i = 1
    while i < out.size
      key = out[i]
      j = i - 1
      while j >= 0
        c = blk != nil ? call_proc(blk, [out[j], key]) : rb_cmp_any(out[j], key, env)
        raise_exc("ArgumentError", "comparison failed") if c == nil
        break if c <= 0
        out[j + 1] = out[j]
        j -= 1
      out[j + 1] = key
      i += 1
    out

  -> rb_sort_pairs(pairs, env = nil)
    out = pairs.dup
    i = 1
    while i < out.size
      key = out[i]
      j = i - 1
      while j >= 0
        c = rb_cmp_any(out[j][0], key[0], env)
        raise_exc("ArgumentError", "comparison failed") if c == nil
        break if c <= 0
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

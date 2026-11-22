# wasm/wat — the WebAssembly text format: lexer, S-expression reader and an encoder that
# turns a (module ...) into the binary format (which the decoder then reads, so the text
# path exercises the binary decoder too).
#
#   bytes = wat_to_wasm(src)            # one module (the text of "(module ...)" or its fields)
#   nodes = wat_parse(src)              # S-expressions (for the .wast script runner)
#   bytes = WatEncoder.new(node).encode # a (module ...) node
#
# Errors in the text raise WasmMalformed (the spec's assert_malformed on quoted modules).

+ WatNode
  rw :kind, :items, :text, :bytes, :pos
  # kind: 0 list, 1 atom (keyword, id, number), 2 string
  -> new(@kind, @text, @pos)
    @items = nil
    @bytes = nil

  -> list?
    @kind == 0

  -> atom?
    @kind == 1

  -> str?
    @kind == 2

  # The head keyword of a list ("module", "func", ...), or nil.
  -> head
    return nil if @kind != 0 || @items.size == 0
    h = @items[0]
    h.kind == 1 ? h.text : nil

  -> to_s
    return @text if @kind == 1
    return "\"" + w_bytes_to_s(@bytes) + "\"" if @kind == 2
    "(" + @items.map(->(x) x.to_s).join(" ") + ")"

-> w_bytes_to_s(a)
  b = ByteArray.new(a.size)
  i = 0
  while i < a.size
    b[i] = a[i]
    i += 1
  ccall("w_string_from_byte_array", b)

-> wat_fail(msg)
  raise WasmMalformed, msg

-> wat_idchar?(c)
  return true if c >= 0x30 && c <= 0x39
  return true if c >= 0x41 && c <= 0x5a
  return true if c >= 0x61 && c <= 0x7a
  c == 0x21 || c == 0x23 || c == 0x24 || c == 0x25 || c == 0x26 || c == 0x27 || c == 0x2a || c == 0x2b || c == 0x2d || c == 0x2e || c == 0x2f || c == 0x3a || c == 0x3c || c == 0x3d || c == 0x3e || c == 0x3f || c == 0x40 || c == 0x5c || c == 0x5e || c == 0x5f || c == 0x60 || c == 0x7c || c == 0x7e

-> wat_hexval(c)
  return c - 0x30 if c >= 0x30 && c <= 0x39
  return c - 0x61 + 10 if c >= 0x61 && c <= 0x66
  return c - 0x41 + 10 if c >= 0x41 && c <= 0x46
  -1

# Parse source text into a list of top-level nodes.
-> wat_parse(src)
  b = src.bytes
  n = b.size
  stack = [WatNode.new(0, nil, 0)]
  stack[0].items = []
  i = 0
  while i < n
    c = b[i]
    if c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d
      i += 1
    elsif c == 0x3b && i + 1 < n && b[i + 1] == 0x3b
      while i < n && b[i] != 0x0a && b[i] != 0x0d
        i += 1
    elsif c == 0x28 && i + 1 < n && b[i + 1] == 0x3b
      depth = 1
      i += 2
      while depth > 0
        wat_fail("unclosed comment") if i >= n
        if b[i] == 0x28 && i + 1 < n && b[i + 1] == 0x3b
          depth += 1
          i += 2
        elsif b[i] == 0x3b && i + 1 < n && b[i + 1] == 0x29
          depth -= 1
          i += 2
        else
          i += 1
    elsif c == 0x28 && i + 1 < n && b[i + 1] == 0x40
      # annotation: skip the balanced list
      depth = 0
      while true
        wat_fail("unclosed annotation") if i >= n
        d = b[i]
        if d == 0x22
          i += 1
          while i < n && b[i] != 0x22
            i += 1 if b[i] == 0x5c
            i += 1
          i += 1
        elsif d == 0x28 && !(i + 1 < n && b[i + 1] == 0x3b)
          depth += 1
          i += 1
        elsif d == 0x29
          depth -= 1
          i += 1
          break if depth == 0
        elsif d == 0x3b && i + 1 < n && b[i + 1] == 0x3b
          while i < n && b[i] != 0x0a
            i += 1
        elsif d == 0x28 && i + 1 < n && b[i + 1] == 0x3b
          cd = 1
          i += 2
          while cd > 0
            wat_fail("unclosed comment") if i >= n
            if b[i] == 0x28 && i + 1 < n && b[i + 1] == 0x3b
              cd += 1
              i += 2
            elsif b[i] == 0x3b && i + 1 < n && b[i + 1] == 0x29
              cd -= 1
              i += 2
            else
              i += 1
        else
          wat_fail("illegal character") if d < 0x20 && d != 0x09 && d != 0x0a && d != 0x0d
          i += 1
    elsif c == 0x28
      l = WatNode.new(0, nil, i)
      l.items = []
      stack[stack.size - 1].items.push(l)
      stack.push(l)
      i += 1
    elsif c == 0x29
      wat_fail("unexpected )") if stack.size <= 1
      stack.pop
      i += 1
    elsif c == 0x22
      bytes = []
      i += 1
      while true
        wat_fail("unclosed string") if i >= n
        d = b[i]
        break if d == 0x22
        wat_fail("illegal character in string") if d < 0x20 || d == 0x7f
        if d == 0x5c
          i += 1
          wat_fail("unclosed string") if i >= n
          e = b[i]
          if e == 0x6e
            bytes.push(10)
          elsif e == 0x74
            bytes.push(9)
          elsif e == 0x72
            bytes.push(13)
          elsif e == 0x22 || e == 0x27 || e == 0x5c
            bytes.push(e)
          elsif e == 0x75
            wat_fail("illegal escape") if i + 1 >= n || b[i + 1] != 0x7b
            i += 2
            cp = 0
            nd = 0
            while i < n && b[i] != 0x7d
              if b[i] != 0x5f
                h = wat_hexval(b[i])
                wat_fail("illegal escape") if h < 0
                cp = cp * 16 + h
                wat_fail("illegal escape") if cp > 0x10ffff
                nd += 1
              i += 1
            wat_fail("illegal escape") if nd == 0 || (cp >= 0xd800 && cp < 0xe000)
            w_push_utf8(bytes, cp)
          else
            h1 = wat_hexval(e)
            h2 = i + 1 < n ? wat_hexval(b[i + 1]) : -1
            wat_fail("illegal escape") if h1 < 0 || h2 < 0
            bytes.push(h1 * 16 + h2)
            i += 1
          i += 1
        else
          bytes.push(d)
          i += 1
      i += 1
      if i < n && !(b[i] == 0x20 || b[i] == 0x09 || b[i] == 0x0a || b[i] == 0x0d || b[i] == 0x28 || b[i] == 0x29 || b[i] == 0x3b)
        wat_fail("unknown operator")
      s = WatNode.new(2, nil, i)
      s.bytes = bytes
      stack[stack.size - 1].items.push(s)
    else
      st = i
      while i < n && (wat_idchar?(b[i]) || (b[i] == 0x22 && i == st + 1 && b[st] == 0x24))
        if b[i] == 0x22
          # $"..." quoted identifier
          i += 1
          while i < n && b[i] != 0x22
            i += 1 if b[i] == 0x5c
            i += 1
        i += 1
      wat_fail("unknown operator") if i == st
      if i < n && !(b[i] == 0x20 || b[i] == 0x09 || b[i] == 0x0a || b[i] == 0x0d || b[i] == 0x28 || b[i] == 0x29 || b[i] == 0x3b)
        wat_fail("unknown operator")
      txt = src.slice(st, i - st)
      if txt.size >= 2 && txt.byte_at(1) == 0x22
        sub = wat_parse(txt.slice(1, txt.size - 1))
        wat_fail("empty identifier") if sub.size != 1 || !sub[0].str? || sub[0].bytes.size == 0
        w_check_utf8_text(sub[0].bytes)
        txt = "$" + w_bytes_to_s(sub[0].bytes)
      wat_fail("empty identifier") if txt == "$"
      stack[stack.size - 1].items.push(WatNode.new(1, txt, st))
  wat_fail("unclosed (") if stack.size != 1
  stack[0].items

-> w_push_utf8(out, cp)
  if cp < 0x80
    out.push(cp)
  elsif cp < 0x800
    out.push(0xc0 | (cp >> 6))
    out.push(0x80 | (cp & 0x3f))
  elsif cp < 0x10000
    out.push(0xe0 | (cp >> 12))
    out.push(0x80 | ((cp >> 6) & 0x3f))
    out.push(0x80 | (cp & 0x3f))
  else
    out.push(0xf0 | (cp >> 18))
    out.push(0x80 | ((cp >> 12) & 0x3f))
    out.push(0x80 | ((cp >> 6) & 0x3f))
    out.push(0x80 | (cp & 0x3f))
  nil


# ---- numbers ----

# Strip underscores, checking they sit between digits.
-> wat_digits(s, hex)
  out = StringBuffer.new
  prev_digit = false
  i = 0
  n = s.size
  while i < n
    c = s.byte_at(i)
    if c == 0x5f
      wat_fail("unknown operator") if !prev_digit || i + 1 >= n
      nc = s.byte_at(i + 1)
      ok = hex ? wat_hexval(nc) >= 0 : (nc >= 0x30 && nc <= 0x39)
      wat_fail("unknown operator") if !ok
      prev_digit = false
    else
      ok = hex ? wat_hexval(c) >= 0 : (c >= 0x30 && c <= 0x39)
      wat_fail("unknown operator") if !ok
      out.append(c.chr)
      prev_digit = true
    i += 1
  wat_fail("unknown operator") if out.size == 0
  out.to_s

# An integer literal as a (big) integer, or nil if the token is not an integer.
-> wat_int(t)
  return nil if t.size == 0
  neg = false
  s = t
  c = s.byte_at(0)
  if c == 0x2b || c == 0x2d
    neg = c == 0x2d
    s = s.slice(1, s.size - 1)
  return nil if s.size == 0
  c0 = s.byte_at(0)
  return nil if c0 < 0x30 || c0 > 0x39
  v = 0 ## int
  if s.size > 2 && s.byte_at(0) == 0x30 && (s.byte_at(1) == 0x78)
    d = wat_digits(s.slice(2, s.size - 2), true)
    i = 0
    while i < d.size
      v = v * 16 + wat_hexval(d.byte_at(i))
      i += 1
  else
    i = 0
    while i < s.size
      cc = s.byte_at(i)
      return nil if !(cc >= 0x30 && cc <= 0x39) && cc != 0x5f
      i += 1
    d = wat_digits(s, false)
    i = 0
    while i < d.size
      v = v * 10 + (d.byte_at(i) - 0x30)
      i += 1
  neg ? 0 - v : v

-> wat_is_int?(t)
  begin
    wat_int(t) != nil
  rescue e
    false

# A u32 index literal.
-> wat_u32(t)
  v = wat_int(t)
  wat_fail("unknown operator") if v == nil
  wat_fail("constant out of range") if v < 0 || v > 4294967295
  v

-> wat_i32(t)
  v = wat_int(t)
  wat_fail("unknown operator") if v == nil
  wat_fail("constant out of range") if v < -2147483648 || v > 4294967295
  w_sext32(v & 0xffffffff)

-> wat_i64(t)
  v = wat_int(t)
  wat_fail("unknown operator") if v == nil
  wat_fail("constant out of range") if v < -9223372036854775808 || v > 18446744073709551615
  v ## i64

# An unsigned 64-bit literal (memory64 offsets).
-> wat_u64(t)
  v = wat_int(t)
  wat_fail("unknown operator") if v == nil
  wat_fail("constant out of range") if v < 0 || v > 18446744073709551615
  v ## i64

# IEEE bits of a float literal. wide: f64 (else f32).
-> wat_float_bits(t, wide)
  mbits = wide ? 52 : 23
  ebits = wide ? 11 : 8
  bias = wide ? 1023 : 127
  sign = 0 ## int
  s = t
  c = s.byte_at(0)
  if c == 0x2b || c == 0x2d
    sign = c == 0x2d ? 1 : 0
    s = s.slice(1, s.size - 1)
  signbit = (sign << (mbits + ebits)) ## int
  expall = (((1 << ebits) - 1) << mbits) ## int
  if s == "inf"
    return (signbit | expall) ## i64
  if s == "nan"
    return (signbit | expall | (1 << (mbits - 1))) ## i64
  if s.size > 6 && s.slice(0, 6) == "nan:0x"
    p = 0 ## int
    d = wat_digits(s.slice(6, s.size - 6), true)
    i = 0
    while i < d.size
      p = p * 16 + wat_hexval(d.byte_at(i))
      i += 1
    wat_fail("constant out of range") if p == 0 || p >= (1 << mbits)
    return (signbit | expall | p) ## i64
  wat_fail("unknown operator") if s.size == 0 || !(s.byte_at(0) >= 0x30 && s.byte_at(0) <= 0x39)
  hex = s.size > 2 && s.byte_at(0) == 0x30 && s.byte_at(1) == 0x78
  body = hex ? s.slice(2, s.size - 2) : s
  # split mantissa / exponent
  ei = -1
  i = 0
  while i < body.size
    ch = body.byte_at(i)
    if (hex && (ch == 0x70 || ch == 0x50)) || (!hex && (ch == 0x65 || ch == 0x45))
      ei = i
      break
    i += 1
  mant = ei < 0 ? body : body.slice(0, ei)
  exp10 = 0
  if ei >= 0
    es = body.slice(ei + 1, body.size - ei - 1)
    eneg = false
    if es.size > 0 && (es.byte_at(0) == 0x2b || es.byte_at(0) == 0x2d)
      eneg = es.byte_at(0) == 0x2d
      es = es.slice(1, es.size - 1)
    ed = wat_digits(es, false)
    ev = 0 ## int
    j = 0
    while j < ed.size
      ev = ev * 10 + (ed.byte_at(j) - 0x30)
      ev = 100000000 if ev > 100000000
      j += 1
    exp10 = eneg ? 0 - ev : ev
  di = mant.index(".")
  ip = di == nil ? mant : mant.slice(0, di)
  fp = di == nil ? "" : mant.slice(di + 1, mant.size - di - 1)
  wat_fail("unknown operator") if ip.size == 0
  idig = wat_digits(ip, hex)
  fdig = fp.size == 0 ? "" : wat_digits(fp, hex)
  m = 0 ## int
  base = hex ? 16 : 10
  all = idig + fdig
  j = 0
  while j < all.size
    m = m * base + wat_hexval(all.byte_at(j))
    j += 1
  return (signbit ## i64) if m == 0
  num = m
  den = 1 ## int
  e2 = 0
  if hex
    e2 = exp10 - 4 * fdig.size
  else
    e10 = exp10 - fdig.size
    if e10 >= 0
      wat_fail("constant out of range") if e10 > 400
      num = m * (10 ** e10)
    else
      return (signbit ## i64) if e10 < -800
      den = 10 ** (0 - e10)
  wat_round_float(num, den, e2, mbits, ebits, bias, signbit)

# Round num/den * 2^e2 (positive) to the nearest float with mbits fraction bits.
-> wat_round_float(num, den, e2, mbits, ebits, bias, signbit)
  p = mbits + 1
  emin = 1 - bias
  emax = bias
  lb = num.bit_length - den.bit_length + e2
  lb = lb - 1 if lb > -100000 && false
  q = 0 ## int
  r = 0 ## int
  dd = den
  ex = 0
  tries = 0
  while true
    ex = lb
    ex = emin if ex < emin
    s = (p - 1) - ex
    sh = e2 + s
    nn = num
    dd = den
    if sh >= 0
      nn = num << sh
    else
      dd = den << (0 - sh)
    q = nn / dd
    r = nn - q * dd
    if q >= (1 << p)
      lb += 1
    elsif q < (1 << (p - 1)) && lb > emin
      lb -= 1
    else
      break
    tries += 1
    wat_fail("float conversion") if tries > 8
  twice = r * 2
  if twice > dd || (twice == dd && (q & 1) == 1)
    q += 1
    if q == (1 << p)
      q = q >> 1
      ex += 1
  wat_fail("constant out of range") if ex > emax
  if q < (1 << (p - 1))
    return (signbit | q) ## i64
  bits = signbit | ((ex + bias) << mbits) | (q - (1 << (p - 1)))
  bits ## i64

-> wat_f32(t)
  wat_float_bits(t, false)

-> wat_f64(t)
  wat_float_bits(t, true)


# ---- a byte buffer ----

+ WBuf
  rw :a

  -> new
    @a = []

  -> b(x)
    @a.push(x & 0xff)
    self

  -> size
    @a.size

  -> vu32(v)
    v = v & 0xffffffff
    while true
      c = v & 0x7f
      v = v >> 7
      if v == 0
        @a.push(c)
        return self
      @a.push(c | 0x80)
    self

  -> vu64(v)
    x = v ## i64
    while true
      c = x & 0x7f
      x = (x >> 7) & 0x1ffffffffffffff
      if x == 0
        @a.push(c)
        return self
      @a.push(c | 0x80)
    self

  -> vs64(v)
    x = v ## i64
    while true
      c = x & 0x7f
      x = x >> 7
      if (x == 0 && (c & 0x40) == 0) || (x == -1 && (c & 0x40) != 0)
        @a.push(c)
        return self
      @a.push(c | 0x80)
    self

  -> vs32(v)
    vs64(v)

  -> fixed(v, n)
    k = 0
    while k < n
      @a.push((v >> (8 * k)) & 0xff)
      k += 1
    self

  -> raw(arr)
    arr.each ->(x) @a.push(x)
    self

  -> buf(o)
    o.a.each ->(x) @a.push(x)
    self

  -> name(bytes)
    vu32(bytes.size)
    raw(bytes)

  -> str(s)
    name(s.bytes.to_a)

  -> to_bytes
    r = ByteArray.new(@a.size)
    i = 0
    while i < @a.size
      r[i] = @a[i]
      i += 1
    r


# ---- module encoder ----

# A cursor over a list of nodes.
+ WatCur
  rw :items, :i
  -> new(@items, @i)

  -> more?
    @i < @items.size

  -> peek
    @i < @items.size ? @items[@i] : nil

  -> next_node
    wat_fail("unexpected end") if @i >= @items.size
    x = @items[@i]
    @i += 1
    x

  -> peek_atom
    x = peek()
    x != nil && x.atom? ? x.text : nil

  -> peek_head
    x = peek()
    x != nil ? x.head : nil

  -> peek_id
    t = peek_atom()
    t != nil && t.starts_with?("$") ? t : nil

  -> take_id
    t = peek_id()
    @i += 1 if t != nil
    t

# One type definition collected from (type ...) / (rec ...).
+ WatTypeDef
  rw :node, :name, :group, :gsize, :fields, :implicit, :params, :results
  -> new(@node, @name, @group, @gsize)
    @fields = {}
    @implicit = false
    @params = nil
    @results = nil

+ WatEncoder
  rw :mod

  -> new(@mod)
    wasm_ops_init()
    @types = []
    @type_names = {}
    @funcs = []
    @func_names = {}
    @tables = []
    @table_names = {}
    @mems = []
    @mem_names = {}
    @globals = []
    @global_names = {}
    @tags = []
    @tag_names = {}
    @elems = []
    @elem_names = {}
    @datas = []
    @data_names = {}
    @imports = []
    @exports = []
    @start = nil
    @seen_def = false
    @labels = []
    @locals = {}
    @mem64 = []
    @table64 = []
    @extra_elems = []
    @extra_datas = []
    @empty_recs = {}
    @inline_elem = {}
    @inline_data = {}

  # ---- pass 1: collect definitions and names ----

  -> add_name(h, name, idx, what)
    return nil if name == nil
    wat_fail("duplicate " + what + " " + name) if h.has_key?(name)
    h[name] = idx

  -> collect
    items = @mod.items
    i = 1
    i += 1 if i < items.size && items[i].atom? && items[i].text.starts_with?("$")
    while i < items.size
      f = items[i]
      wat_fail("unknown module field") if !f.list?
      h = f.head
      if h == "type"
        collect_type(f, @types.size, 1)
      elsif h == "rec"
        g0 = @types.size
        n = f.items.size - 1
        k = 1
        while k < f.items.size
          wat_fail("malformed rec") if f.items[k].head != "type"
          collect_type(f.items[k], g0, n)
          k += 1
        if n == 0
          @empty_recs[g0] = (@empty_recs.has_key?(g0) ? @empty_recs[g0] : 0) + 1
      elsif h == "import"
        collect_import(f)
      elsif h == "func" || h == "table" || h == "memory" || h == "global" || h == "tag"
        collect_def(f, h)
      elsif h == "export"
        @exports.push(f)
      elsif h == "start"
        wat_fail("multiple start sections") if @start != nil
        @start = f
      elsif h == "elem"
        c = WatCur.new(f.items, 1)
        add_name(@elem_names, c.take_id(), @elems.size, "elem")
        @elems.push(f)
      elsif h == "data"
        c = WatCur.new(f.items, 1)
        add_name(@data_names, c.take_id(), @datas.size, "data")
        @datas.push(f)
      else
        wat_fail("unknown module field " + h.to_s)
      i += 1
    nil

  -> collect_type(f, g0, gsize)
    c = WatCur.new(f.items, 1)
    nm = c.take_id()
    add_name(@type_names, nm, @types.size, "type")
    d = WatTypeDef.new(c.next_node(), nm, g0, gsize)
    # field names
    ct = d.node
    while ct.head == "sub"
      ct = ct.items[ct.items.size - 1]
    if ct.head == "struct"
      fi = 0
      k = 1
      while k < ct.items.size
        fl = ct.items[k]
        if fl.head == "field"
          fc = WatCur.new(fl.items, 1)
          fid = fc.take_id()
          if fid != nil
            wat_fail("duplicate field " + fid) if d.fields.has_key?(fid)
            d.fields[fid] = fi
            fi += 1
          else
            fi += fl.items.size - 1
        k += 1
    if ct.head == "func"
      d.params = []
      d.results = []
    @types.push(d)

  -> collect_import(f)
    wat_fail("import after definition") if @seen_def
    wat_fail("malformed import") if f.items.size < 4
    desc = f.items[3]
    k = desc.head
    c = WatCur.new(desc.items, 1)
    nm = c.take_id()
    if k == "func"
      add_name(@func_names, nm, @funcs.size, "func")
      @funcs.push([desc, true])
    elsif k == "table"
      add_name(@table_names, nm, @tables.size, "table")
      @tables.push([desc, true])
    elsif k == "memory"
      add_name(@mem_names, nm, @mems.size, "memory")
      @mems.push([desc, true])
    elsif k == "global"
      add_name(@global_names, nm, @globals.size, "global")
      @globals.push([desc, true])
    elsif k == "tag"
      add_name(@tag_names, nm, @tags.size, "tag")
      @tags.push([desc, true])
    else
      wat_fail("malformed import kind")
    @imports.push([f.items[1], f.items[2], k, desc, true])

  -> collect_def(f, h)
    c = WatCur.new(f.items, 1)
    nm = c.take_id()
    # inline exports, then maybe an inline import
    is_import = false
    while c.peek_head == "export"
      c.next_node()
    if c.peek_head == "import"
      is_import = true
    if is_import
      wat_fail("import after definition") if @seen_def
    else
      @seen_def = true
    if h == "func"
      add_name(@func_names, nm, @funcs.size, "func")
      @funcs.push([f, false])
    elsif h == "table"
      add_name(@table_names, nm, @tables.size, "table")
      @elems.push(@tables.size) if !is_import && w_has_inline?(f, "elem")
      @tables.push([f, false])
    elsif h == "memory"
      add_name(@mem_names, nm, @mems.size, "memory")
      @datas.push(@mems.size) if !is_import && w_has_inline?(f, "data")
      @mems.push([f, false])
    elsif h == "global"
      add_name(@global_names, nm, @globals.size, "global")
      @globals.push([f, false])
    else
      add_name(@tag_names, nm, @tags.size, "tag")
      @tags.push([f, false])
    if is_import
      imp = c.next_node()
      @imports.push([imp.items[1], imp.items[2], h, f, false])

  # ---- index resolution ----

  -> resolve(h, node, what)
    wat_fail("unknown " + what) if node == nil || !node.atom?
    t = node.text
    if t.starts_with?("$")
      wat_fail("unknown " + what + " " + t) if !h.has_key?(t)
      return h[t]
    wat_u32(t)

  -> idx_at(c, h, what)
    resolve(h, c.next_node(), what)

  -> type_idx(node)
    resolve(@type_names, node, "type")

  -> func_idx(node)
    resolve(@func_names, node, "function")

  # ---- value types ----

  -> heap_type(node)
    wat_fail("malformed heap type") if !node.atom?
    t = node.text
    return HT_FUNC if t == "func"
    return HT_EXTERN if t == "extern"
    return HT_ANY if t == "any"
    return HT_EQ if t == "eq"
    return HT_I31 if t == "i31"
    return HT_STRUCT if t == "struct"
    return HT_ARRAY if t == "array"
    return HT_EXN if t == "exn"
    return HT_NOEXN if t == "noexn"
    return HT_NOFUNC if t == "nofunc"
    return HT_NOEXTERN if t == "noextern"
    return HT_NONE if t == "none"
    type_idx(node)

  # A value type as [code bytes...] in the binary encoding.
  -> val_type(node)
    if node.atom?
      t = node.text
      return [T_I32] if t == "i32"
      return [T_I64] if t == "i64"
      return [T_F32] if t == "f32"
      return [T_F64] if t == "f64"
      return [T_V128] if t == "v128"
      return [0x70] if t == "funcref"
      return [0x6f] if t == "externref"
      return [0x6e] if t == "anyref"
      return [0x6d] if t == "eqref"
      return [0x6c] if t == "i31ref"
      return [0x6b] if t == "structref"
      return [0x6a] if t == "arrayref"
      return [0x69] if t == "exnref"
      return [0x74] if t == "nullexnref"
      return [0x73] if t == "nullfuncref"
      return [0x72] if t == "nullexternref"
      return [0x71] if t == "nullref"
      wat_fail("unknown type " + t)
    wat_fail("malformed value type") if node.head != "ref"
    c = WatCur.new(node.items, 1)
    nullable = false
    if c.peek_atom == "null"
      nullable = true
      c.next_node()
    ht = heap_type(c.next_node())
    wat_fail("malformed ref type") if c.more?
    out = [nullable ? 0x63 : 0x64]
    w = WBuf.new
    if ht >= HT_ABS
      w.b(ht - HT_ABS)
    else
      w.vs64(ht)
    out + w.a

  -> storage_type(node)
    if node.atom? && node.text == "i8"
      return [T_I8]
    if node.atom? && node.text == "i16"
      return [T_I16]
    val_type(node)

  -> heap_type_bytes(ht)
    w = WBuf.new
    if ht >= HT_ABS
      w.b(ht - HT_ABS)
    else
      w.vs64(ht)
    w.a

  # ---- type uses ----

  # Parse (param ...)* (result ...)* from the cursor: [params, results, names]
  -> sig(c, allow_names)
    params = []
    results = []
    names = []
    while c.peek_head == "param"
      p = c.next_node()
      pc = WatCur.new(p.items, 1)
      id = pc.take_id()
      if id != nil
        wat_fail("malformed param") if !allow_names
        params.push(val_type(pc.next_node()))
        names.push(id)
        wat_fail("malformed param") if pc.more?
      else
        while pc.more?
          params.push(val_type(pc.next_node()))
          names.push(nil)
    while c.peek_head == "result"
      r = c.next_node()
      rc = WatCur.new(r.items, 1)
      while rc.more?
        results.push(val_type(rc.next_node()))
    [params, results, names]

  # A type use: (type x)? params results. Returns [type index, param names, sig].
  -> type_use(c, allow_names)
    explicit = nil
    if c.peek_head == "type"
      tn = c.next_node()
      explicit = type_idx(tn.items[1])
    s = sig(c, allow_names)
    if explicit != nil
      if s[0].size > 0 || s[1].size > 0
        d = explicit < @types.size ? @types[explicit] : nil
        if d != nil && d.params != nil && !d.implicit
          ds = func_sig_of(explicit)
          wat_fail("inline function type") if ds[0] != s[0] || ds[1] != s[1]
      names = s[2]
      if s[0].size == 0
        np = explicit < @types.size && @types[explicit].params != nil ? func_sig_of(explicit)[0].size : 0
        names = []
        k = 0
        while k < np
          names.push(nil)
          k += 1
      return [explicit, names, s]
    [find_or_add_type(s[0], s[1]), s[2], s]

  # The [params, results] (as byte lists) of a func type index.
  -> func_sig_of(ti)
    w_invalid("unknown type") if ti >= @types.size
    d = @types[ti]
    return [d.params, d.results] if d.implicit
    ct = d.node
    while ct.head == "sub"
      ct = ct.items[ct.items.size - 1]
    wat_fail("not a function type") if ct.head != "func"
    if d.params == nil || d.params.size == 0 && d.results.size == 0
      s = sig(WatCur.new(ct.items, 1), true)
      d.params = s[0]
      d.results = s[1]
    [d.params, d.results]

  -> find_or_add_type(params, results)
    i = 0
    while i < @types.size
      d = @types[i]
      if d.implicit
        return i if d.params == params && d.results == results
      elsif d.gsize == 1 && d.node != nil && d.node.head == "func"
        s = func_sig_of(i)
        return i if s[0] == params && s[1] == results
      i += 1
    d = WatTypeDef.new(nil, nil, @types.size, 1)
    d.implicit = true
    d.params = params
    d.results = results
    @types.push(d)
    @types.size - 1

  # ---- limits ----

  -> limits(c, w, is64, shared, extra_flags)
    mn = wat_u64(c.next_node().text)
    mx = nil
    if c.peek_atom != nil && wat_is_int?(c.peek_atom)
      mx = wat_u64(c.next_node().text)
    if !is64
      w_invalid("table size must be at most 2^32-1") if mn > 4294967295 || (mx != nil && mx > 4294967295)
    flags = (mx != nil ? 1 : 0) | (shared ? 2 : 0) | (is64 ? 4 : 0) | extra_flags
    w.b(flags)
    w.vu64(mn)
    w.vu64(mx) if mx != nil
    [mn, mx]

  # ---- encoding ----

  -> encode
    collect()
    # resolve type definitions first (they may need implicit types? no: explicit only)
    out = WBuf.new
    imports = WBuf.new
    funcs = WBuf.new
    tables = WBuf.new
    mems = WBuf.new
    tags = WBuf.new
    globals = WBuf.new
    exports = WBuf.new
    elems = WBuf.new
    codes = WBuf.new
    datas = WBuf.new
    n_imports = 0
    n_funcs = 0
    n_tables = 0
    n_mems = 0
    n_tags = 0
    n_globals = 0
    # memory / table address types (needed for memarg and table op encodings)
    @mems.each ->(e) @mem64.push(mem_is64?(e[0]))
    @tables.each ->(e) @table64.push(table_is64?(e[0]))
    @imports.each ->(imp)
      imports.name(imp[0].bytes)
      imports.name(imp[1].bytes)
      wat_fail("malformed import name") if !imp[0].str? || !imp[1].str?
      w_check_utf8_text(imp[0].bytes)
      w_check_utf8_text(imp[1].bytes)
      k = imp[2]
      desc = imp[3]
      c = WatCur.new(desc.items, 1)
      c.take_id()
      while c.peek_head == "export"
        c.next_node()
      c.next_node() if c.peek_head == "import"
      if k == "func"
        imports.b(0)
        tu = type_use(c, true)
        imports.vu32(tu[0])
      elsif k == "table"
        imports.b(1)
        table_type(c, imports)
      elsif k == "memory"
        imports.b(2)
        mem_type(c, imports)
      elsif k == "global"
        imports.b(3)
        global_type(c, imports)
      else
        imports.b(4)
        imports.b(0)
        tu = type_use(c, false)
        imports.vu32(tu[0])
      n_imports += 1
    # definitions
    fi = 0
    @funcs.each ->(fe)
      f = fe[0]
      if !fe[1] && !w_has_import?(f)
        c = WatCur.new(f.items, 1)
        c.take_id()
        while c.peek_head == "export"
          collect_inline_export(c.next_node(), 0, fi)
        tu = type_use(c, true)
        funcs.vu32(tu[0])
        n_funcs += 1
        codes_body = encode_func(c, tu)
        codes.vu32(codes_body.size)
        codes.buf(codes_body)
      elsif !fe[1]
        c = WatCur.new(f.items, 1)
        c.take_id()
        while c.peek_head == "export"
          collect_inline_export(c.next_node(), 0, fi)
      fi += 1
    ti = 0
    @tables.each ->(fe)
      f = fe[0]
      if !fe[1]
        c = WatCur.new(f.items, 1)
        c.take_id()
        while c.peek_head == "export"
          collect_inline_export(c.next_node(), 1, ti)
        if !w_has_import?(f)
          encode_table(c, tables, ti)
          n_tables += 1
      ti += 1
    mi = 0
    @mems.each ->(fe)
      f = fe[0]
      if !fe[1]
        c = WatCur.new(f.items, 1)
        c.take_id()
        while c.peek_head == "export"
          collect_inline_export(c.next_node(), 2, mi)
        if !w_has_import?(f)
          encode_memory(c, mems, mi)
          n_mems += 1
      mi += 1
    gi = 0
    @globals.each ->(fe)
      f = fe[0]
      if !fe[1]
        c = WatCur.new(f.items, 1)
        c.take_id()
        while c.peek_head == "export"
          collect_inline_export(c.next_node(), 3, gi)
        if !w_has_import?(f)
          global_type(c, globals)
          const_expr(c, globals)
          n_globals += 1
      gi += 1
    tgi = 0
    @tags.each ->(fe)
      f = fe[0]
      if !fe[1]
        c = WatCur.new(f.items, 1)
        c.take_id()
        while c.peek_head == "export"
          collect_inline_export(c.next_node(), 4, tgi)
        if !w_has_import?(f)
          tags.b(0)
          tu = type_use(c, false)
          tags.vu32(tu[0])
          n_tags += 1
      tgi += 1
    # exports
    n_exports = 0
    seen_exports = {}
    @exports.each ->(f)
      nm = f.items[1]
      wat_fail("malformed export") if !nm.str?
      w_check_utf8_text(nm.bytes)
      key = w_bytes_to_s(nm.bytes)
      wat_fail("duplicate export name") if seen_exports.has_key?(key) && false
      seen_exports[key] = true
      d = f.items[2]
      k = d.head
      exports.name(nm.bytes)
      if k == "func"
        exports.b(0)
        exports.vu32(resolve(@func_names, d.items[1], "function"))
      elsif k == "table"
        exports.b(1)
        exports.vu32(resolve(@table_names, d.items[1], "table"))
      elsif k == "memory"
        exports.b(2)
        exports.vu32(resolve(@mem_names, d.items[1], "memory"))
      elsif k == "global"
        exports.b(3)
        exports.vu32(resolve(@global_names, d.items[1], "global"))
      elsif k == "tag"
        exports.b(4)
        exports.vu32(resolve(@tag_names, d.items[1], "tag"))
      else
        wat_fail("malformed export kind")
      n_exports += 1
    # element segments
    n_elems = 0
    @elems.each ->(f)
      if f.is_a?(Integer)
        elems.buf(@inline_elem[f])
      else
        encode_elem(f, elems)
      n_elems += 1
    n_datas = 0
    @datas.each ->(f)
      if f.is_a?(Integer)
        datas.buf(@inline_data[f])
      else
        encode_data(f, datas)
      n_datas += 1
    types = encode_types()
    # assemble
    out.raw([0, 0x61, 0x73, 0x6d, 1, 0, 0, 0])
    section(out, 1, types[1], types[0]) if types[0] > 0
    section(out, 2, imports, n_imports) if n_imports > 0
    section(out, 3, funcs, n_funcs) if n_funcs > 0
    section(out, 4, tables, n_tables) if n_tables > 0
    section(out, 5, mems, n_mems) if n_mems > 0
    section(out, 13, tags, n_tags) if n_tags > 0
    section(out, 6, globals, n_globals) if n_globals > 0
    section(out, 7, exports, n_exports) if n_exports > 0
    if @start != nil
      s = WBuf.new
      s.vu32(func_idx(@start.items[1]))
      out.b(8)
      out.vu32(s.size)
      out.buf(s)
    section(out, 9, elems, n_elems) if n_elems > 0
    if n_datas > 0 || w_uses_data_ops?(codes)
      dc = WBuf.new
      dc.vu32(n_datas)
      out.b(12)
      out.vu32(dc.size)
      out.buf(dc)
    section(out, 10, codes, n_funcs) if n_funcs > 0
    section(out, 11, datas, n_datas) if n_datas > 0
    out.to_bytes

  -> section(out, id, body, count)
    cnt = WBuf.new
    cnt.vu32(count)
    out.b(id)
    out.vu32(cnt.size + body.size)
    out.buf(cnt)
    out.buf(body)

  -> collect_inline_export(e, kind, idx)
    nm = e.items[1]
    wat_fail("malformed export") if nm == nil || !nm.str?
    kw = ["func", "table", "memory", "global", "tag"][kind]
    l = WatNode.new(0, nil, e.pos)
    l.items = [WatNode.new(1, "export", e.pos), nm, w_mk_list([WatNode.new(1, kw, e.pos), WatNode.new(1, idx.to_s, e.pos)])]
    @exports.push(l)

  -> mem_is64?(f)
    c = WatCur.new(f.items, 1)
    c.take_id()
    if f.head == "import"
      return false
    while c.peek_head == "export" || c.peek_head == "import"
      c.next_node()
    c.peek_atom == "i64"

  -> table_is64?(f)
    mem_is64?(f)

  -> table_type(c, w)
    is64 = false
    if c.peek_atom == "i64" || c.peek_atom == "i32"
      is64 = c.next_node().text == "i64"
    # limits come first, then the ref type
    lw = WBuf.new
    limits(c, lw, is64, false, 0)
    w.raw(val_type(c.next_node()))
    w.buf(lw)

  -> mem_type(c, w)
    is64 = false
    if c.peek_atom == "i64" || c.peek_atom == "i32"
      is64 = c.next_node().text == "i64"
    lw = WBuf.new
    mn = wat_u64(c.next_node().text)
    mx = nil
    if c.peek_atom != nil && wat_is_int?(c.peek_atom)
      mx = wat_u64(c.next_node().text)
    shared = false
    if c.peek_atom == "shared"
      c.next_node()
      shared = true
    elsif c.peek_atom == "unshared"
      c.next_node()
    pagesize = nil
    if c.peek_head == "pagesize"
      ps = wat_u32(c.next_node().items[1].text)
      wat_fail("invalid custom page size") if ps != 1 && ps != 65536
      pagesize = ps == 1 ? 0 : 16
    if !is64
      w_invalid("memory size must be at most 65536 pages (4GiB)") if mn > 4294967295 || (mx != nil && mx > 4294967295)
    flags = (mx != nil ? 1 : 0) | (shared ? 2 : 0) | (is64 ? 4 : 0) | (pagesize != nil ? 8 : 0)
    w.b(flags)
    w.vu64(mn)
    w.vu64(mx) if mx != nil
    w.vu32(pagesize) if pagesize != nil

  -> global_type(c, w)
    n = c.next_node()
    if n.head == "mut"
      w.raw(val_type(n.items[1]))
      w.b(1)
    else
      w.raw(val_type(n))
      w.b(0)

  -> encode_table(c, w, ti)
    is64 = false
    if c.peek_atom == "i64" || c.peek_atom == "i32"
      is64 = c.next_node().text == "i64"
    a = c.peek()
    if a != nil && (a.list? || !wat_is_int?(a.text))
      # reftype (elem ...) abbreviation
      rt = val_type(c.next_node())
      e = c.next_node()
      wat_fail("malformed table") if e.head != "elem"
      items = e.items
      n = items.size - 1
      w.raw(rt)
      w.b(is64 ? 5 : 1)
      w.vu64(n)
      w.vu64(n)
      seg = WBuf.new
      exprs = n > 0 && items[1].list?
      if exprs
        seg.b(6)
        seg.vu32(ti)
        seg.raw(is64 ? [0x42, 0, 0x0b] : [0x41, 0, 0x0b])
        seg.raw(rt)
        seg.vu32(n)
        k = 1
        while k < items.size
          it = items[k]
          if it.head == "item"
            const_expr(WatCur.new(it.items, 1), seg)
          else
            const_expr(WatCur.new([it], 0), seg)
          k += 1
      else
        seg.b(6)
        seg.vu32(ti)
        seg.raw(is64 ? [0x42, 0, 0x0b] : [0x41, 0, 0x0b])
        seg.raw(rt)
        seg.vu32(n)
        k = 1
        while k < items.size
          seg.b(0xd2)
          seg.vu32(func_idx(items[k]))
          seg.b(0x0b)
          k += 1
      @inline_elem[ti] = seg
      return nil
    lw = WBuf.new
    limits(c, lw, is64, false, 0)
    rt = val_type(c.next_node())
    if c.more?
      w.b(0x40)
      w.b(0)
      w.raw(rt)
      w.buf(lw)
      const_expr(c, w)
    else
      w.raw(rt)
      w.buf(lw)

  -> encode_memory(c, w, mi)
    is64 = false
    if c.peek_atom == "i64" || c.peek_atom == "i32"
      is64 = c.next_node().text == "i64"
    if c.peek_head == "data"
      d = c.next_node()
      bytes = []
      k = 1
      while k < d.items.size
        bytes = bytes + d.items[k].bytes
        k += 1
      pages = (bytes.size + 65535) / 65536
      w.b(is64 ? 5 : 1)
      w.vu64(pages)
      w.vu64(pages)
      seg = WBuf.new
      if mi == 0
        seg.b(0)
      else
        seg.b(2)
        seg.vu32(mi)
      seg.raw(is64 ? [0x42, 0, 0x0b] : [0x41, 0, 0x0b])
      seg.name(bytes)
      @inline_data[mi] = seg
      return nil
    if is64
      # mem_type expects to see the address type
      c.i -= 1
    mem_type(c, w)

  # A constant expression (instructions until the end of the cursor) plus `end`.
  -> const_expr(c, w)
    @labels = []
    @locals = {}
    while c.more?
      instr(c, w)
    w.b(0x0b)

  -> encode_elem(f, w)
    c = WatCur.new(f.items, 1)
    c.take_id()
    mode = 1
    table = nil
    offset = nil
    if c.peek_atom == "declare"
      c.next_node()
      mode = 2
    elsif c.peek_head == "table" || c.peek_head == "offset" || (c.peek() != nil && c.peek().list? && c.peek_head != "item" && c.peek_head != "ref")
      mode = 0
      if c.peek_head == "table"
        table = resolve(@table_names, c.next_node().items[1], "table")
      o = c.next_node()
      offset = WBuf.new
      if o.head == "offset"
        const_expr(WatCur.new(o.items, 1), offset)
      else
        const_expr(WatCur.new([o], 0), offset)
    # element list
    func_list = false
    rt = nil
    if c.peek_atom == "func"
      c.next_node()
      func_list = true
    elsif c.peek() == nil || (c.peek().atom? && (c.peek_atom.starts_with?("$") || wat_is_int?(c.peek_atom)))
      func_list = true
    else
      rt = val_type(c.next_node())
    if func_list
      if mode == 0
        if table == nil
          w.b(0)
        else
          w.b(2)
          w.vu32(table)
        w.buf(offset)
        w.b(0) if table != nil
      else
        w.b(mode == 1 ? 1 : 3)
        w.b(0)
      fl = []
      while c.more?
        fl.push(func_idx(c.next_node()))
      w.vu32(fl.size)
      fl.each ->(x) w.vu32(x)
    else
      if mode == 0
        if table == nil && rt == [0x70]
          w.b(4)
          w.buf(offset)
        else
          w.b(6)
          w.vu32(table == nil ? 0 : table)
          w.buf(offset)
          w.raw(rt)
      else
        w.b(mode == 1 ? 5 : 7)
        w.raw(rt)
      items = []
      while c.more?
        items.push(c.next_node())
      w.vu32(items.size)
      items.each ->(it)
        if it.head == "item"
          const_expr(WatCur.new(it.items, 1), w)
        else
          const_expr(WatCur.new([it], 0), w)

  -> encode_data(f, w)
    c = WatCur.new(f.items, 1)
    c.take_id()
    mem = nil
    offset = nil
    if c.peek_head == "memory"
      mem = resolve(@mem_names, c.next_node().items[1], "memory")
    if c.peek() != nil && c.peek().list?
      o = c.next_node()
      offset = WBuf.new
      if o.head == "offset"
        const_expr(WatCur.new(o.items, 1), offset)
      else
        const_expr(WatCur.new([o], 0), offset)
    bytes = []
    while c.more?
      s = c.next_node()
      wat_fail("malformed data") if !s.str?
      bytes = bytes + s.bytes
    if offset == nil
      w.b(1)
    elsif mem == nil || mem == 0
      w.b(0)
      w.buf(offset)
    else
      w.b(2)
      w.vu32(mem)
      w.buf(offset)
    w.name(bytes)

  -> encode_types
    w = WBuf.new
    count = 0
    i = 0
    while i <= @types.size
      if @empty_recs.has_key?(i)
        k = 0
        while k < @empty_recs[i]
          w.b(0x4e)
          w.b(0)
          count += 1
          k += 1
      break if i == @types.size
      d = @types[i]
      if d.implicit
        w.b(0x60)
        w.vu32(d.params.size)
        d.params.each ->(p) w.raw(p)
        w.vu32(d.results.size)
        d.results.each ->(r) w.raw(r)
        count += 1
        i += 1
      elsif d.gsize == 1
        enc_subtype(d, w)
        count += 1
        i += 1
      else
        w.b(0x4e)
        w.vu32(d.gsize)
        k = 0
        while k < d.gsize
          enc_subtype(@types[i + k], w)
          k += 1
        count += 1
        i += d.gsize
    [count, w]

  -> enc_subtype(d, w)
    n = d.node
    if n.head == "sub"
      c = WatCur.new(n.items, 1)
      final = false
      if c.peek_atom == "final"
        c.next_node()
        final = true
      sups = []
      while c.more? && c.peek().atom?
        sups.push(type_idx(c.next_node()))
      w.b(final ? 0x4f : 0x50)
      w.vu32(sups.size)
      sups.each ->(s) w.vu32(s)
      enc_comptype(c.next_node(), w)
    else
      enc_comptype(n, w)

  -> enc_comptype(n, w)
    h = n.head
    c = WatCur.new(n.items, 1)
    if h == "func"
      s = sig(c, true)
      w.b(0x60)
      w.vu32(s[0].size)
      s[0].each ->(p) w.raw(p)
      w.vu32(s[1].size)
      s[1].each ->(r) w.raw(r)
    elsif h == "struct"
      fs = []
      while c.more?
        fl = c.next_node()
        wat_fail("malformed struct") if fl.head != "field"
        fc = WatCur.new(fl.items, 1)
        fc.take_id()
        while fc.more?
          fs.push(field_type(fc.next_node()))
      w.b(0x5f)
      w.vu32(fs.size)
      fs.each ->(x) w.raw(x)
    elsif h == "array"
      fl = c.next_node()
      if fl.head == "field"
        fc = WatCur.new(fl.items, 1)
        fc.take_id()
        fl = fc.next_node()
      w.b(0x5e)
      w.raw(field_type(fl))
    else
      wat_fail("malformed type definition")

  -> field_type(n)
    if n.head == "mut"
      return storage_type(n.items[1]) + [1]
    storage_type(n) + [0]

  # ---- functions ----

  -> encode_func(c, tu)
    @locals = {}
    @labels = []
    names = tu[1]
    k = 0
    while k < names.size
      if names[k] != nil
        wat_fail("duplicate local " + names[k]) if @locals.has_key?(names[k])
        @locals[names[k]] = k
      k += 1
    nl = names.size
    body = WBuf.new
    groups = []
    while c.peek_head == "local"
      l = c.next_node()
      lc = WatCur.new(l.items, 1)
      id = lc.take_id()
      if id != nil
        wat_fail("duplicate local " + id) if @locals.has_key?(id)
        @locals[id] = nl
        groups.push([1, val_type(lc.next_node())])
        nl += 1
      else
        while lc.more?
          groups.push([1, val_type(lc.next_node())])
          nl += 1
    # merge equal neighbours
    merged = []
    groups.each ->(g)
      if merged.size > 0 && merged[merged.size - 1][1] == g[1]
        merged[merged.size - 1][0] += 1
      else
        merged.push([g[0], g[1]])
    body.vu32(merged.size)
    merged.each ->(g)
      body.vu32(g[0])
      body.raw(g[1])
    while c.more?
      instr(c, body)
    body.b(0x0b)
    body

  -> label_idx(node)
    wat_fail("unknown label") if node == nil || !node.atom?
    t = node.text
    if t.starts_with?("$")
      k = @labels.size - 1
      while k >= 0
        return @labels.size - 1 - k if @labels[k] == t
        k -= 1
      wat_fail("unknown label " + t)
    wat_u32(t)

  # Block type: returns byte list.
  -> block_type(c)
    if c.peek_head == "type"
      tu = type_use(c, false)
      return WBuf.new.vs64(tu[0]).a
    s = sig(c, false)
    return [0x40] if s[0].size == 0 && s[1].size == 0
    return s[1][0] if s[0].size == 0 && s[1].size == 1
    WBuf.new.vs64(find_or_add_type(s[0], s[1])).a

  -> emit_op(w, op)
    if op[0] == 0
      w.b(op[1])
    else
      w.b(op[0])
      w.vu32(op[1])

  -> push_label(c)
    id = c.take_id()
    @labels.push(id)

  -> check_end_label(c, kw)
    # optional label after end/else must match the block's
    id = c.peek_id()
    if id != nil
      c.next_node()
      wat_fail("mismatching label") if @labels.size == 0 || @labels[@labels.size - 1] != id

  # One instruction (plain or folded) from the cursor.
  -> instr(c, w)
    n = c.next_node()
    if n.list?
      return folded(n, w)
    name = n.text
    op = WASM_OPS[name]
    wat_fail("unknown operator " + name) if op == nil
    k = op[2]
    if k == "b"
      emit_op(w, op)
      push_label(c)
      w.raw(block_type(c))
      if name == "try"
        nil
    elsif k == "tt"
      emit_op(w, op)
      id = c.take_id()
      w.raw(block_type(c))
      catches(c, w)
      @labels.push(id)
    elsif k == "end"
      check_end_label(c, "end")
      @labels.pop if @labels.size > 0
      w.b(0x0b)
    elsif k == "else"
      check_end_label(c, "else")
      w.b(0x05)
    elsif k == "catch"
      check_end_label(c, "catch")
      w.b(0x07)
      w.vu32(resolve(@tag_names, c.next_node(), "tag"))
    elsif name == "catch_all"
      check_end_label(c, "catch_all")
      w.b(0x19)
    elsif name == "delegate"
      @labels.pop if @labels.size > 0
      w.b(0x18)
      w.vu32(label_idx(c.next_node()))
    else
      imm(c, w, op, name)
    nil

  -> catches(c, w)
    cs = []
    while c.peek_head == "catch" || c.peek_head == "catch_ref" || c.peek_head == "catch_all" || c.peek_head == "catch_all_ref"
      cs.push(c.next_node())
    w.vu32(cs.size)
    cs.each ->(cn)
      h = cn.head
      if h == "catch"
        w.b(0)
        w.vu32(resolve(@tag_names, cn.items[1], "tag"))
        w.vu32(label_idx(cn.items[2]))
      elsif h == "catch_ref"
        w.b(1)
        w.vu32(resolve(@tag_names, cn.items[1], "tag"))
        w.vu32(label_idx(cn.items[2]))
      elsif h == "catch_all"
        w.b(2)
        w.vu32(label_idx(cn.items[1]))
      else
        w.b(3)
        w.vu32(label_idx(cn.items[1]))

  # Immediates of a non-block instruction; c is positioned after the name.
  -> imm(c, w, op, name)
    k = op[2]
    if k == "-"
      emit_op(w, op)
    elsif k == "l"
      emit_op(w, op)
      w.vu32(label_idx(c.next_node()))
    elsif k == "bt"
      emit_op(w, op)
      ls = []
      while c.peek_atom != nil && (c.peek_atom.starts_with?("$") || wat_is_int?(c.peek_atom))
        ls.push(label_idx(c.next_node()))
      wat_fail("malformed br_table") if ls.size == 0
      w.vu32(ls.size - 1)
      ls.each ->(l) w.vu32(l)
    elsif k == "f"
      emit_op(w, op)
      w.vu32(func_idx(c.next_node()))
    elsif k == "ci"
      emit_op(w, op)
      t = 0
      if c.peek_atom != nil && (c.peek_atom.starts_with?("$") || wat_is_int?(c.peek_atom))
        t = resolve(@table_names, c.next_node(), "table")
      tu = type_use(c, false)
      w.vu32(tu[0])
      w.vu32(t)
    elsif k == "t"
      emit_op(w, op)
      w.vu32(type_idx(c.next_node()))
    elsif k == "lo"
      emit_op(w, op)
      w.vu32(resolve(@locals, c.next_node(), "local"))
    elsif k == "g"
      emit_op(w, op)
      w.vu32(resolve(@global_names, c.next_node(), "global"))
    elsif k == "tb"
      emit_op(w, op)
      t = 0
      if c.peek_atom != nil && (c.peek_atom.starts_with?("$") || wat_is_int?(c.peek_atom))
        t = resolve(@table_names, c.next_node(), "table")
      w.vu32(t)
    elsif k == "me"
      emit_op(w, op)
      m = 0
      if c.peek_atom != nil && (c.peek_atom.starts_with?("$") || wat_is_int?(c.peek_atom))
        m = resolve(@mem_names, c.next_node(), "memory")
      w.vu32(m)
    elsif k.starts_with?("ml") && k.size == 3
      emit_op(w, op)
      memarg_lane(c, w, k.slice(2, 1).to_i)
    elsif k.starts_with?("m") && k.size == 2 && k.byte_at(1) >= 0x30 && k.byte_at(1) <= 0x39
      emit_op(w, op)
      memarg(c, w, k.slice(1, 1).to_i, false)
    elsif k == "i32"
      emit_op(w, op)
      w.vs32(wat_i32(c.next_node().text))
    elsif k == "i64"
      emit_op(w, op)
      w.vs64(wat_i64(c.next_node().text))
    elsif k == "f32"
      emit_op(w, op)
      w.fixed(wat_f32(c.next_node().text), 4)
    elsif k == "f64"
      emit_op(w, op)
      w.fixed(wat_f64(c.next_node().text), 8)
    elsif k == "v128"
      emit_op(w, op)
      w.raw(v128_const(c))
    elsif k == "sel"
      if c.peek_head == "result"
        ts = []
        while c.peek_head == "result"
          r = c.next_node()
          j = 1
          while j < r.items.size
            ts.push(val_type(r.items[j]))
            j += 1
        w.b(0x1c)
        w.vu32(ts.size)
        ts.each ->(t) w.raw(t)
      else
        w.b(0x1b)
    elsif k == "ht"
      emit_op(w, op)
      w.raw(heap_type_bytes(heap_type(c.next_node())))
    elsif k == "rtest"
      rt = ref_type_info(c.next_node())
      emit_op(w, [op[0], op[1] + (rt[0] ? 1 : 0)])
      w.raw(heap_type_bytes(rt[1]))
    elsif k == "boc"
      emit_op(w, op)
      l = label_idx(c.next_node())
      r1 = ref_type_info(c.next_node())
      r2 = ref_type_info(c.next_node())
      w.b((r1[0] ? 1 : 0) | (r2[0] ? 2 : 0))
      w.vu32(l)
      w.raw(heap_type_bytes(r1[1]))
      w.raw(heap_type_bytes(r2[1]))
    elsif k == "tf"
      emit_op(w, op)
      t = type_idx(c.next_node())
      w.vu32(t)
      fnode = c.next_node()
      if fnode.text.starts_with?("$")
        d = @types[t]
        wat_fail("unknown field") if d == nil || !d.fields.has_key?(fnode.text)
        w.vu32(d.fields[fnode.text])
      else
        w.vu32(wat_u32(fnode.text))
    elsif k == "tn"
      emit_op(w, op)
      w.vu32(type_idx(c.next_node()))
      w.vu32(wat_u32(c.next_node().text))
    elsif k == "td"
      emit_op(w, op)
      w.vu32(type_idx(c.next_node()))
      w.vu32(resolve(@data_names, c.next_node(), "data segment"))
    elsif k == "te"
      emit_op(w, op)
      w.vu32(type_idx(c.next_node()))
      w.vu32(resolve(@elem_names, c.next_node(), "elem segment"))
    elsif k == "t2"
      emit_op(w, op)
      w.vu32(type_idx(c.next_node()))
      w.vu32(type_idx(c.next_node()))
    elsif k == "mi"
      emit_op(w, op)
      a = c.next_node()
      if c.peek_atom != nil && (c.peek_atom.starts_with?("$") || wat_is_int?(c.peek_atom))
        m = resolve(@mem_names, a, "memory")
        d = resolve(@data_names, c.next_node(), "data segment")
        w.vu32(d)
        w.vu32(m)
      else
        w.vu32(resolve(@data_names, a, "data segment"))
        w.vu32(0)
    elsif k == "mc"
      emit_op(w, op)
      m1 = 0
      m2 = 0
      if c.peek_atom != nil && (c.peek_atom.starts_with?("$") || wat_is_int?(c.peek_atom))
        m1 = resolve(@mem_names, c.next_node(), "memory")
        m2 = resolve(@mem_names, c.next_node(), "memory")
      w.vu32(m1)
      w.vu32(m2)
    elsif k == "ti"
      emit_op(w, op)
      a = c.next_node()
      if c.peek_atom != nil && (c.peek_atom.starts_with?("$") || wat_is_int?(c.peek_atom))
        t = resolve(@table_names, a, "table")
        e = resolve(@elem_names, c.next_node(), "elem segment")
        w.vu32(e)
        w.vu32(t)
      else
        w.vu32(resolve(@elem_names, a, "elem segment"))
        w.vu32(0)
    elsif k == "tc"
      emit_op(w, op)
      t1 = 0
      t2 = 0
      if c.peek_atom != nil && (c.peek_atom.starts_with?("$") || wat_is_int?(c.peek_atom))
        t1 = resolve(@table_names, c.next_node(), "table")
        t2 = resolve(@table_names, c.next_node(), "table")
      w.vu32(t1)
      w.vu32(t2)
    elsif k == "d"
      emit_op(w, op)
      w.vu32(resolve(@data_names, c.next_node(), "data segment"))
    elsif k == "e"
      emit_op(w, op)
      w.vu32(resolve(@elem_names, c.next_node(), "elem segment"))
    elsif k == "lane"
      emit_op(w, op)
      l = wat_u32(c.next_node().text)
      wat_fail("malformed lane index") if l > 255
      w.b(l)
    elsif k == "shuf"
      emit_op(w, op)
      j = 0
      while j < 16
        a = c.next_node()
        wat_fail("invalid lane length") if !a.atom?
        l = wat_u32(a.text)
        wat_fail("malformed lane index") if l > 255
        w.b(l)
        j += 1
      wat_fail("invalid lane length") if c.peek_atom != nil && wat_is_int?(c.peek_atom)
    elsif k == "tag"
      emit_op(w, op)
      w.vu32(resolve(@tag_names, c.next_node(), "tag"))
    elsif k == "fence"
      emit_op(w, op)
      w.b(0)
    else
      wat_fail("unknown operator " + name)
    nil

  -> ref_type_info(node)
    if node.atom?
      t = node.text
      v = val_type(node)
      return [true, HT_ABS + v[0]]
    c = WatCur.new(node.items, 1)
    wat_fail("malformed ref type") if node.head != "ref"
    nullable = false
    if c.peek_atom == "null"
      nullable = true
      c.next_node()
    [nullable, heap_type(c.next_node())]

  -> memarg(c, w, natural, lane)
    m = 0
    if c.peek_atom != nil && (c.peek_atom.starts_with?("$") || wat_is_int?(c.peek_atom))
      m = resolve(@mem_names, c.next_node(), "memory")
    memarg_rest(c, w, natural, m)

  -> memarg_rest(c, w, natural, m)
    off = 0
    align = 1 << natural
    if c.peek_atom != nil && c.peek_atom.starts_with?("offset=")
      t = c.next_node().text
      off = wat_u64(t.slice(7, t.size - 7))
      is64 = m < @mem64.size && @mem64[m]
      w_invalid("offset out of range") if !is64 && (off < 0 || off > 4294967295)
    if c.peek_atom != nil && c.peek_atom.starts_with?("align=")
      t = c.next_node().text
      align = wat_u32(t.slice(6, t.size - 6))
      wat_fail("alignment must be a power of two") if align == 0 || (align & (align - 1)) != 0
    a = 0
    while (1 << a) < align
      a += 1
    if m != 0
      w.vu32(a | 64)
      w.vu32(m)
    else
      w.vu32(a)
    w.vu64(off)

  -> memarg_lane(c, w, natural)
    m = 0
    a = c.peek_atom
    if a != nil && a.starts_with?("$")
      m = resolve(@mem_names, c.next_node(), "memory")
    elsif a != nil && wat_is_int?(a)
      # two integers: memory then lane
      nx = c.i + 1 < c.items.size ? c.items[c.i + 1] : nil
      if nx != nil && nx.atom? && (wat_is_int?(nx.text) || nx.text.starts_with?("offset=") || nx.text.starts_with?("align="))
        m = resolve(@mem_names, c.next_node(), "memory")
    memarg_rest(c, w, natural, m)
    l = wat_u32(c.next_node().text)
    w.b(l)

  -> v128_const(c)
    shape = c.next_node().text
    out = WBuf.new
    if shape == "i8x16"
      j = 0
      while j < 16
        v = wat_int(c.next_node().text)
        wat_fail("constant out of range") if v == nil || v < -128 || v > 255
        out.b(v & 0xff)
        j += 1
    elsif shape == "i16x8"
      j = 0
      while j < 8
        v = wat_int(c.next_node().text)
        wat_fail("constant out of range") if v == nil || v < -32768 || v > 65535
        out.fixed(v & 0xffff, 2)
        j += 1
    elsif shape == "i32x4"
      j = 0
      while j < 4
        out.fixed(wat_i32(c.next_node().text) & 0xffffffff, 4)
        j += 1
    elsif shape == "i64x2"
      j = 0
      while j < 2
        out.fixed(wat_i64(c.next_node().text), 8)
        j += 1
    elsif shape == "f32x4"
      j = 0
      while j < 4
        out.fixed(wat_f32(c.next_node().text), 4)
        j += 1
    elsif shape == "f64x2"
      j = 0
      while j < 2
        out.fixed(wat_f64(c.next_node().text), 8)
        j += 1
    else
      wat_fail("unknown operator")
    out.a

  # A folded instruction (list form).
  -> folded(n, w)
    name = n.head
    wat_fail("unknown operator") if name == nil
    op = WASM_OPS[name]
    wat_fail("unknown operator " + name) if op == nil
    c = WatCur.new(n.items, 1)
    k = op[2]
    if name == "block" || name == "loop"
      emit_op(w, op)
      push_label(c)
      w.raw(block_type(c))
      while c.more?
        instr(c, w)
      @labels.pop
      w.b(0x0b)
    elsif name == "if"
      id = c.take_id()
      bt = block_type(c)
      # condition instructions until (then ...)
      while c.more? && c.peek_head != "then"
        instr(c, w)
      emit_op(w, op)
      @labels.push(id)
      w.raw(bt)
      t = c.next_node()
      wat_fail("malformed if") if t.head != "then"
      tc = WatCur.new(t.items, 1)
      while tc.more?
        instr(tc, w)
      if c.more?
        e = c.next_node()
        wat_fail("malformed if") if e.head != "else"
        w.b(0x05)
        ec = WatCur.new(e.items, 1)
        while ec.more?
          instr(ec, w)
      @labels.pop
      w.b(0x0b)
    elsif name == "try_table"
      emit_op(w, op)
      id = c.take_id()
      w.raw(block_type(c))
      catches(c, w)
      @labels.push(id)
      while c.more?
        instr(c, w)
      @labels.pop
      w.b(0x0b)
    elsif name == "try"
      emit_op(w, op)
      push_label(c)
      w.raw(block_type(c))
      d = c.next_node()
      wat_fail("malformed try") if d.head != "do"
      dc = WatCur.new(d.items, 1)
      while dc.more?
        instr(dc, w)
      delegated = false
      while c.more?
        h = c.next_node()
        hh = h.head
        if hh == "catch"
          w.b(0x07)
          hc = WatCur.new(h.items, 1)
          w.vu32(resolve(@tag_names, hc.next_node(), "tag"))
          while hc.more?
            instr(hc, w)
        elsif hh == "catch_all"
          w.b(0x19)
          hc = WatCur.new(h.items, 1)
          while hc.more?
            instr(hc, w)
        elsif hh == "delegate"
          @labels.pop
          w.b(0x18)
          w.vu32(label_idx(h.items[1]))
          delegated = true
        else
          wat_fail("malformed try")
      if !delegated
        @labels.pop
        w.b(0x0b)
    else
      # plain op with immediates, then folded operands
      sub = WatCur.new(n.items, 1)
      tmp = WBuf.new
      imm(sub, tmp, op, name)
      while sub.more?
        x = sub.peek()
        wat_fail("unknown operator") if !x.list?
        instr(sub, w)
      w.buf(tmp)
    nil

-> w_mk_list(items)
  l = WatNode.new(0, nil, 0)
  l.items = items
  l

-> w_has_inline?(f, what)
  i = 0
  while i < f.items.size
    x = f.items[i]
    return true if x.list? && x.head == what
    i += 1
  false

-> w_has_import?(f)
  c = WatCur.new(f.items, 1)
  c.take_id()
  while c.peek_head == "export"
    c.next_node()
  c.peek_head == "import"

-> w_check_utf8_text(bytes)
  b = ByteArray.new(bytes.size)
  i = 0
  while i < bytes.size
    b[i] = bytes[i]
    i += 1
  wat_fail("malformed UTF-8 encoding") if !w_utf8_valid?(b, 0, bytes.size)
  nil

# Text of one module → binary.
-> wat_to_wasm(src)
  nodes = wat_parse(src)
  if nodes.size == 1 && nodes[0].head == "module"
    return WatEncoder.new(nodes[0]).encode
  # bare fields
  m = WatNode.new(0, nil, 0)
  m.items = [WatNode.new(1, "module", 0)] + nodes
  WatEncoder.new(m).encode

# Does encoded code use memory.init / data.drop (0xfc 8 / 0xfc 9)? (approximate byte scan:
# a data count section is harmless when it is not needed)
-> w_uses_data_ops?(codes)
  a = codes.a
  i = 0
  while i + 1 < a.size
    return true if a[i] == 0xfc && (a[i + 1] == 8 || a[i + 1] == 9)
    i += 1
  false

# wasm/reader — the binary decoder (WebAssembly 3.0 binary format, plus threads).
#
#   m = wasm_decode(bytes)      # bytes: u8[] / ByteArray; raises WasmMalformed
#
# Decoding builds a WModule: sections are parsed into tables, function bodies and
# constant expressions are left as byte ranges for the validator (which compiles bodies to
# the interpreter's code in the same pass). Value types are canonicalised as soon as the
# type section is read (see types.w).

+ WReader
  rw :b, :pos, :stop, :m, :raw_types

  -> new(@b, @pos, @stop, @m)
    @raw_types = false

  -> eof?
    @pos >= @stop

  -> byte
    w_malformed("unexpected end") if @pos >= @stop
    v = @b[@pos]
    @pos += 1
    v

  -> peek
    w_malformed("unexpected end") if @pos >= @stop
    @b[@pos]

  -> vu32
    result = 0
    shift = 0
    while true
      w_malformed("unexpected end") if @pos >= @stop
      c = @b[@pos]
      @pos += 1
      if shift == 28
        w_malformed("integer representation too long") if (c & 0x80) != 0
        w_malformed("integer too large") if (c & 0x70) != 0
      result = result | ((c & 0x7f) << shift)
      return result if (c & 0x80) == 0
      shift += 7
    0

  # u64 (memory64 offsets, limits); result wraps to a signed Int.
  -> vu64
    result = 0
    shift = 0
    while true
      w_malformed("unexpected end") if @pos >= @stop
      c = @b[@pos]
      @pos += 1
      if shift == 63
        w_malformed("integer representation too long") if (c & 0x80) != 0
        w_malformed("integer too large") if (c & 0x7e) != 0
      result = (result | ((c & 0x7f) << shift)) ## i64
      return result if (c & 0x80) == 0
      shift += 7
    0

  -> vs32
    result = 0
    shift = 0
    while true
      w_malformed("unexpected end") if @pos >= @stop
      c = @b[@pos]
      @pos += 1
      if shift == 28
        w_malformed("integer representation too long") if (c & 0x80) != 0
        hi = c & 0x78
        w_malformed("integer too large") if hi != 0 && hi != 0x78
      result = result | ((c & 0x7f) << shift)
      shift += 7
      if (c & 0x80) == 0
        if shift < 64 && (c & 0x40) != 0
          result = result | ((0 - 1) << shift)
        return w_sext32(result)
    0

  -> vs33
    result = 0
    shift = 0
    while true
      w_malformed("unexpected end") if @pos >= @stop
      c = @b[@pos]
      @pos += 1
      if shift == 28
        w_malformed("integer representation too long") if (c & 0x80) != 0
        hi = c & 0x70
        w_malformed("integer too large") if hi != 0 && hi != 0x70
      result = result | ((c & 0x7f) << shift)
      shift += 7
      if (c & 0x80) == 0
        if shift < 64 && (c & 0x40) != 0
          result = result | ((0 - 1) << shift)
        return result
    0

  -> vs64
    result = 0
    shift = 0
    while true
      w_malformed("unexpected end") if @pos >= @stop
      c = @b[@pos]
      @pos += 1
      if shift == 63
        w_malformed("integer representation too long") if (c & 0x80) != 0
        w_malformed("integer too large") if c != 0 && c != 0x7f
      result = (result | ((c & 0x7f) << shift)) ## i64
      shift += 7
      if (c & 0x80) == 0
        if shift < 64 && (c & 0x40) != 0
          result = (result | ((0 - 1) << shift)) ## i64
        return result
    0

  -> bytes(n)
    w_malformed("unexpected end") if @pos + n > @stop || n < 0
    s = @pos
    @pos += n
    s

  -> vf32
    v = 0
    k = 0
    while k < 4
      v = v | (byte() << (8 * k))
      k += 1
    v

  -> vf64
    lo = vf32()
    hi = vf32()
    (lo | (hi << 32)) ## i64

  -> name
    n = vu32()
    s = bytes(n)
    w_malformed("malformed UTF-8 encoding") if !w_utf8_valid?(@b, s, n)
    w_str_from(@b, s, n)

  # ---- types ----

  -> heap_type
    v = vs33()
    if v < 0
      c = v & 0x7f
      return HT_ABS + c if c == 0x70 || c == 0x6f || c == 0x6e || c == 0x6d || c == 0x6c || c == 0x6b || c == 0x6a || c == 0x69 || c == 0x74 || c == 0x73 || c == 0x72 || c == 0x71
      w_malformed("malformed heap type")
    concrete(v)

  -> concrete(v)
    w_invalid("unknown type " + v.to_s) if v >= HT_ABS
    if @raw_types
      return v
    w_invalid("unknown type " + v.to_s) if v >= @m.canon.size
    @m.canon[v]

  -> val_type
    c = byte()
    return c if c == T_I32 || c == T_I64 || c == T_F32 || c == T_F64 || c == T_V128
    ref_type_after(c)

  -> ref_type
    c = byte()
    ref_type_after(c)

  -> ref_type_after(c)
    return REF_BIT + NULL_BIT + HT_ABS + c if c == 0x70 || c == 0x6f || c == 0x6e || c == 0x6d || c == 0x6c || c == 0x6b || c == 0x6a || c == 0x69 || c == 0x74 || c == 0x73 || c == 0x72 || c == 0x71
    return REF_BIT + heap_type() if c == 0x64
    return REF_BIT + NULL_BIT + heap_type() if c == 0x63
    w_malformed("malformed value type")

  -> storage_type
    c = peek()
    if c == T_I8 || c == T_I16
      @pos += 1
      return c
    val_type()

  # Limits: [flags, min, max (nil if absent)]. Memory/table64 use u64 bounds.
  -> limits(is_mem)
    flags = byte()
    w_malformed("integer too large") if flags > 15 || (!is_mem && flags > 5)
    w_malformed("malformed limits flags") if !is_mem && (flags & 2) != 0
    is64 = (flags & 4) != 0
    mn = is64 ? vu64() : vu32()
    mx = nil
    if (flags & 1) != 0
      mx = is64 ? vu64() : vu32()
    [flags, mn, mx]

  -> table_type
    elem = ref_type()
    l = limits(false)
    WTableType.new(elem, l[1], l[2], (l[0] & 4) != 0)

  -> mem_type
    l = limits(true)
    mt = WMemType.new(l[1], l[2], (l[0] & 2) != 0, (l[0] & 4) != 0)
    if (l[0] & 8) != 0
      p = vu32()
      w_invalid("invalid custom page size") if p != 0 && p != 16
      mt.page_log2 = p
    mt

  -> global_type
    t = val_type()
    mu = byte()
    w_malformed("malformed mutability") if mu > 1
    WGlobalType.new(t, mu == 1)

  -> block_type
    c = peek()
    if c == 0x40
      @pos += 1
      return [-1, -1]
    if c == T_I32 || c == T_I64 || c == T_F32 || c == T_F64 || c == T_V128 || c == 0x70 || c == 0x6f || c == 0x6e || c == 0x6d || c == 0x6c || c == 0x6b || c == 0x6a || c == 0x69 || c == 0x74 || c == 0x73 || c == 0x72 || c == 0x71 || c == 0x63 || c == 0x64
      return [0, val_type()]
    v = vs33()
    w_malformed("malformed block type") if v < 0
    [1, v]

  # The end of a constant expression starting at @pos (the position after its `end`).
  -> skip_expr
    depth = 0
    while true
      op = byte()
      if op == 0x0b
        return @pos if depth == 0
        depth -= 1
      elsif op == 0x02 || op == 0x03 || op == 0x04 || op == 0x06 || op == 0x1f
        depth += 1
        skip_imm(op)
      else
        skip_imm(op)
    0

  # Skip the immediates of one instruction (opcode already read).
  -> skip_imm(op)
    if op == 0x02 || op == 0x03 || op == 0x04 || op == 0x06
      block_type()
    elsif op == 0x1f
      block_type()
      n = vu32()
      i = 0
      while i < n
        k = byte()
        w_malformed("malformed catch clause") if k > 3
        vu32() if k < 2
        vu32()
        i += 1
    elsif op == 0x07 || op == 0x08 || op == 0x09 || op == 0x18 || op == 0x0c || op == 0x0d || op == 0x10 || op == 0x12 || op == 0x14 || op == 0x15 || op == 0xd2 || op == 0xd5 || op == 0xd6 || (op >= 0x20 && op <= 0x26)
      vu32()
    elsif op == 0x0e
      n = vu32()
      i = 0
      while i <= n
        vu32()
        i += 1
    elsif op == 0x11 || op == 0x13
      vu32()
      vu32()
    elsif op == 0x1c
      n = vu32()
      i = 0
      while i < n
        val_type()
        i += 1
    elsif op >= 0x28 && op <= 0x3e
      memarg()
    elsif op == 0x3f || op == 0x40
      vu32()
    elsif op == 0x41
      vs32()
    elsif op == 0x42
      vs64()
    elsif op == 0x43
      bytes(4)
    elsif op == 0x44
      bytes(8)
    elsif op == 0xd0
      heap_type()
    elsif op == 0xfb
      skip_gc(vu32())
    elsif op == 0xfc
      sub = vu32()
      if sub == 8 || sub == 10 || sub == 12 || sub == 14
        vu32()
        vu32()
      elsif sub == 9 || sub == 11 || sub == 13 || sub == 15 || sub == 16 || sub == 17
        vu32()
      elsif sub > 22
        w_malformed("illegal opcode")
    elsif op == 0xfd
      sub = vu32()
      if sub <= 11 || sub == 92 || sub == 93
        memarg()
      elsif sub == 12 || sub == 13
        bytes(16)
      elsif sub >= 21 && sub <= 34
        byte()
      elsif sub >= 84 && sub <= 91
        memarg()
        byte()
    elsif op == 0xfe
      sub = vu32()
      if sub == 3
        byte()
      else
        memarg()
    elsif (op >= 0x45 && op <= 0xc4) || op == 0x00 || op == 0x01 || op == 0x05 || op == 0x0a || op == 0x0b || op == 0x0f || op == 0x19 || op == 0x1a || op == 0x1b || op == 0xd1 || op == 0xd3 || op == 0xd4
      nil
    else
      w_malformed("illegal opcode " + op.to_s)
    nil

  -> skip_gc(sub)
    if sub == 0 || sub == 1 || sub == 6 || sub == 7 || sub == 11 || sub == 12 || sub == 13 || sub == 14 || sub == 16
      vu32()
    elsif sub == 2 || sub == 3 || sub == 4 || sub == 5 || sub == 8 || sub == 9 || sub == 10 || sub == 17 || sub == 18 || sub == 19
      vu32()
      vu32()
    elsif sub >= 20 && sub <= 23
      heap_type()
    elsif sub == 24 || sub == 25
      byte()
      vu32()
      heap_type()
      heap_type()
    elsif sub == 15 || (sub >= 26 && sub <= 30)
      nil
    else
      w_malformed("illegal opcode")
    nil

  # [align, memidx, offset]
  -> memarg
    a = vu32()
    mi = 0
    if (a & 64) != 0
      a = a - 64
      mi = vu32()
    off = vu64()
    [a, mi, off]


-> w_sext32(v)
  v = v & 0xffffffff
  v >= 2147483648 ? v - 4294967296 : v

# Is b[s, s+n) valid UTF-8?
-> w_utf8_valid?(b, s, n)
  i = s
  e = s + n
  while i < e
    c = b[i]
    if c < 0x80
      i += 1
    else
      len = 0
      mn = 0
      if c >= 0xc2 && c <= 0xdf
        len = 1
        mn = 0x80
      elsif c >= 0xe0 && c <= 0xef
        len = 2
        mn = 0x800
      elsif c >= 0xf0 && c <= 0xf4
        len = 3
        mn = 0x10000
      else
        return false
      return false if i + len >= e
      cp = c & (len == 1 ? 0x1f : (len == 2 ? 0x0f : 0x07))
      k = 1
      while k <= len
        d = b[i + k]
        return false if (d & 0xc0) != 0x80
        cp = (cp << 6) | (d & 0x3f)
        k += 1
      return false if cp < mn || cp > 0x10ffff || (cp >= 0xd800 && cp <= 0xdfff)
      i += len + 1
  true

-> w_str_from(b, s, n)
  bs = ByteArray.new(n)
  k = 0
  while k < n
    bs[k] = b[s + k]
    k += 1
  ccall("w_string_from_byte_array", bs)

# A non-custom section's rank in the required order (type, import, function, table,
# memory, tag, global, export, start, element, datacount, code, data).
-> w_section_rank(id)
  return 1 if id == 1
  return 2 if id == 2
  return 3 if id == 3
  return 4 if id == 4
  return 5 if id == 5
  return 6 if id == 13
  return 7 if id == 6
  return 8 if id == 7
  return 9 if id == 8
  return 10 if id == 9
  return 11 if id == 12
  return 12 if id == 10
  return 13 if id == 11
  -1

-> wasm_decode(bytes)
  b = bytes
  n = b.size
  w_malformed("unexpected end") if n < 4
  w_malformed("magic header not detected") if b[0] != 0 || b[1] != 0x61 || b[2] != 0x73 || b[3] != 0x6d
  w_malformed("unexpected end") if n < 8
  w_malformed("unknown binary version") if b[4] != 1 || b[5] != 0 || b[6] != 0 || b[7] != 0
  m = WModule.new(b)
  r = WReader.new(b, 8, n, m)
  last = 0
  nfuncs_declared = nil
  while !r.eof?
    id = r.byte()
    size = r.vu32()
    start = r.pos
    w_malformed("unexpected end of section or function") if start + size > n
    if id != 0
      rank = w_section_rank(id)
      w_malformed("malformed section id") if rank < 0
      w_malformed("unexpected content after last section") if rank <= last
      last = rank
    s = WReader.new(b, start, start + size, m)
    if id == 0
      nm = s.name()
      m.customs.push([nm, s.pos, start + size - s.pos])
      w_read_names(m, s) if nm == "name"
      s.pos = start + size
    elsif id == 1
      w_read_types(m, s)
    elsif id == 2
      w_read_imports(m, s)
    elsif id == 3
      c = s.vu32()
      nfuncs_declared = c
      i = 0
      while i < c
        ti = s.vu32()
        m.funcs.push(ti)
        i += 1
    elsif id == 4
      c = s.vu32()
      i = 0
      while i < c
        if s.peek() == 0x40
          s.byte()
          z = s.byte()
          w_malformed("malformed table") if z != 0
          tt = s.table_type()
          st = s.pos
          en = s.skip_expr()
          tt.init = WConstExpr.new(st, en - 1, tt.elem)
          m.tables.push(tt)
        else
          m.tables.push(s.table_type())
        i += 1
    elsif id == 5
      c = s.vu32()
      i = 0
      while i < c
        m.mems.push(s.mem_type())
        i += 1
    elsif id == 13
      c = s.vu32()
      i = 0
      while i < c
        a = s.byte()
        w_malformed("malformed tag attribute") if a != 0
        m.tags.push(s.vu32())
        i += 1
    elsif id == 6
      c = s.vu32()
      i = 0
      while i < c
        g = s.global_type()
        st = s.pos
        en = s.skip_expr()
        g.init = WConstExpr.new(st, en - 1, g.type)
        m.globals.push(g)
        i += 1
    elsif id == 7
      c = s.vu32()
      i = 0
      while i < c
        nm = s.name()
        k = s.byte()
        w_malformed("malformed export kind") if k > 4
        m.exports.push(WExport.new(nm, k, s.vu32()))
        i += 1
    elsif id == 8
      m.start = s.vu32()
    elsif id == 9
      w_read_elems(m, s)
    elsif id == 12
      m.data_count = s.vu32()
    elsif id == 10
      c = s.vu32()
      w_malformed("function and code section have inconsistent lengths") if c != (nfuncs_declared == nil ? 0 : nfuncs_declared)
      i = 0
      while i < c
        sz = s.vu32()
        fs = s.pos
        w_malformed("unexpected end of section or function") if fs + sz > s.stop
        f = WReader.new(b, fs, fs + sz, m)
        nl = f.vu32()
        locals = []
        total = 0
        j = 0
        while j < nl
          cnt = f.vu32()
          total += cnt
          w_malformed("too many locals") if total > 4294967295
          locals.push([cnt, f.val_type()])
          j += 1
        w_malformed("too many locals") if total > 1000000
        m.codes.push(WCode.new(locals, f.pos, fs + sz))
        s.pos = fs + sz
        i += 1
    elsif id == 11
      c = s.vu32()
      w_malformed("data count and data section have inconsistent lengths") if m.data_count != nil && m.data_count != c
      i = 0
      while i < c
        flags = s.vu32()
        if flags == 0 || flags == 2
          mi = flags == 2 ? s.vu32() : 0
          st = s.pos
          en = s.skip_expr()
          off = WConstExpr.new(st, en - 1, nil)
          len = s.vu32()
          ds = s.bytes(len)
          m.datas.push(WData.new(0, mi, off, ds, len))
        elsif flags == 1
          len = s.vu32()
          ds = s.bytes(len)
          m.datas.push(WData.new(1, 0, nil, ds, len))
        else
          w_malformed("malformed data segment flags")
        i += 1
    w_malformed("section size mismatch") if s.pos != start + size
    r.pos = start + size
  if nfuncs_declared != nil && nfuncs_declared > 0 && m.codes.size == 0
    w_malformed("function and code section have inconsistent lengths")
  if m.data_count != nil && m.datas.size != m.data_count
    w_malformed("data count and data section have inconsistent lengths")
  m

-> w_read_types(m, s)
  c = s.vu32()
  defs = []
  s.raw_types = true
  i = 0
  groups = []
  while i < c
    k = s.peek()
    if k == 0x4e
      s.byte()
      n = s.vu32()
      g0 = defs.size
      j = 0
      while j < n
        defs.push(w_read_subtype(s))
        j += 1
      groups.push([g0, n])
    else
      g0 = defs.size
      defs.push(w_read_subtype(s))
      groups.push([g0, 1])
    i += 1
  s.raw_types = false
  m.types = defs
  m.canon = []
  defs.each ->(d) m.canon.push(-1)
  # validate references (forward references only within the group), then register
  groups.each ->(g)
    g0 = g[0]
    n = g[1]
    j = 0
    while j < n
      d = defs[g0 + j]
      lim = g0 + n
      d.supers.each ->(sp) w_invalid("unknown type") if sp >= lim
      d.params.each ->(t) w_check_vt_index(t, lim)
      d.results.each ->(t) w_check_vt_index(t, lim)
      d.ftypes.each ->(t) w_check_vt_index(t, lim)
      j += 1
    wt_register_group(defs, g0, n, m.canon)
  # module-level type records keep canonical value types
  tl = []
  i = 0
  while i < defs.size
    tl.push(W_TYPES.types[m.canon[i]])
    i += 1
  m.types = tl
  nil

-> w_check_vt_index(t, lim)
  if wt_ref?(t)
    h = wt_ht(t)
    w_invalid("unknown type") if h < HT_ABS && h >= lim
  nil

-> w_read_subtype(s)
  k = s.byte()
  if k == 0x50 || k == 0x4f
    n = s.vu32()
    sups = []
    j = 0
    while j < n
      sups.push(s.vu32())
      j += 1
    d = w_read_comptype(s, s.byte())
    d.supers = sups
    d.final = k == 0x4f
    return d
  w_read_comptype(s, k)

-> w_read_comptype(s, k)
  if k == 0x60
    d = WSubType.new(0)
    n = s.vu32()
    j = 0
    while j < n
      d.params.push(s.val_type())
      j += 1
    n = s.vu32()
    j = 0
    while j < n
      d.results.push(s.val_type())
      j += 1
    return d
  if k == 0x5f
    d = WSubType.new(1)
    n = s.vu32()
    j = 0
    while j < n
      d.ftypes.push(s.storage_type())
      mu = s.byte()
      w_malformed("malformed mutability") if mu > 1
      d.fmuts.push(mu == 1)
      j += 1
    return d
  if k == 0x5e
    d = WSubType.new(2)
    d.ftypes.push(s.storage_type())
    mu = s.byte()
    w_malformed("malformed mutability") if mu > 1
    d.fmuts.push(mu == 1)
    return d
  w_malformed("malformed composite type")

-> w_read_imports(m, s)
  c = s.vu32()
  i = 0
  while i < c
    mod = s.name()
    nm = s.name()
    k = s.byte()
    if k == 0
      ti = s.vu32()
      m.imports.push(WImport.new(mod, nm, 0, ti))
      m.funcs.push(ti)
      m.n_imp_funcs += 1
    elsif k == 1
      tt = s.table_type()
      m.imports.push(WImport.new(mod, nm, 1, tt))
      m.tables.push(tt)
      m.n_imp_tables += 1
    elsif k == 2
      mt = s.mem_type()
      m.imports.push(WImport.new(mod, nm, 2, mt))
      m.mems.push(mt)
      m.n_imp_mems += 1
    elsif k == 3
      gt = s.global_type()
      m.imports.push(WImport.new(mod, nm, 3, gt))
      m.globals.push(gt)
      m.n_imp_globals += 1
    elsif k == 4
      a = s.byte()
      w_malformed("malformed tag attribute") if a != 0
      ti = s.vu32()
      m.imports.push(WImport.new(mod, nm, 4, ti))
      m.tags.push(ti)
      m.n_imp_tags += 1
    else
      w_malformed("malformed import kind")
    i += 1
  nil

-> w_read_elems(m, s)
  c = s.vu32()
  i = 0
  while i < c
    flags = s.vu32()
    w_malformed("malformed elements segment kind") if flags > 7
    mode = (flags & 1) == 0 ? 0 : ((flags & 2) == 0 ? 1 : 2)
    table = 0
    off = nil
    if mode == 0
      table = s.vu32() if (flags & 2) != 0
      st = s.pos
      en = s.skip_expr()
      off = WConstExpr.new(st, en - 1, nil)
    exprs = (flags & 4) != 0
    et = FUNCREF
    if (flags & 3) != 0
      if exprs
        et = s.ref_type()
      else
        k = s.byte()
        w_malformed("malformed element kind") if k != 0
        et = REF_BIT + HT_FUNC
    elsif !exprs
      et = REF_BIT + HT_FUNC
    e = WElem.new(mode, table, off, et)
    n = s.vu32()
    j = 0
    if exprs
      while j < n
        st = s.pos
        en = s.skip_expr()
        e.items.push(WConstExpr.new(st, en - 1, et))
        j += 1
    else
      e.funcs = []
      while j < n
        e.funcs.push(s.vu32())
        j += 1
    m.elems.push(e)
    i += 1
  nil

# The name section's function names (for stack traces); malformed contents are ignored.
-> w_read_names(m, s)
  begin
    while !s.eof?
      id = s.byte()
      size = s.vu32()
      e = s.pos + size
      if id == 0
        m.name = s.name()
      elsif id == 1
        n = s.vu32()
        i = 0
        while i < n
          idx = s.vu32()
          m.func_names[idx] = s.name()
          i += 1
      s.pos = e
  rescue e
    nil
  nil

# languages/javascript/ast_codec — canonical hashing and a compact binary
# form of the JsNode AST.
#
# Every byte the codec itself writes is in 1..127 (string contents are copied
# verbatim), so images are built with StringBuffer and read back as a String
# with byte_at: whole strings are copied in one append and sliced out in one
# call. Integers are 6-bit varints: bytes 64..127 carry 6 more low bits and
# continue, a byte 1..63 ends the number with value-1 as its last digit.
#
# Canonical form. A node encodes, in pre-order, as
#
#   kind      one byte, the code (index + 1) of its kind in JS_KINDS
#   mask      one byte: 1 + slot bits (1 str, 2 a, 4 b, 8 c, 16 d, 32 list),
#             plus 64 when a flags varint follows
#   flags     varint, when present
#   str       varint length + bytes, when present
#   a b c d   one value each, for the slots present
#   list      one value (an array), when present
#
# A value is self-describing by its lead byte: a node (its kind code), 120
# array (varint count, then 119 for a nil element or a node), 121 string
# (varint length + bytes), 122 float as shortest decimal text, 123 a
# non-negative integral float below 2^53 (varint).
#
# Source positions are not part of it: pos and fin go to a separate stream.
# So a subtree's canonical bytes depend only on its kinds, names, values and
# children, never on where it sits in a file; identical functions in
# different files or sites encode to identical bytes and get the same
# wyhash64 (Digest.string64, the hash content_hash.w uses for Tungsten's own
# functions, named `__wy_<hex>` by js_wy_symbol). `js_node_hash` hashes any
# node; encoding a program also hashes every function, arrow and method.
#
# File (.jsast):
#
#   "JSAST" version-byte goal-byte ("s" script / "m" module)
#   varint structure length, varint positions length, varint function count
#   structure         the program's canonical encoding
#   positions         per node in pre-order: varint zigzag(pos - previous
#                     pos), varint (fin - pos)
#   function table    per function: varint pre-order index, 16 hex digits of
#                     its canonical wyhash64
#
# Bump JS_AST_VERSION whenever the parser's AST shape or this format changes:
# it is part of every cache key.

use parser

JS_AST_VERSION = 1

JS_KINDS = [:program, :expr_stmt, :var_decl, :declarator, :function_decl, :class_decl, :block, :empty, :if, :for, :for_in, :for_of, :while, :do_while, :return, :break, :continue, :throw, :try, :switch, :case, :labeled, :debugger, :with, :import_decl, :import_spec, :export_named, :export_spec, :export_default, :export_all, :ident, :num, :bigint, :string, :template, :quasi, :tagged_template, :regex, :null, :true, :false, :this, :super, :array, :object, :prop, :function, :arrow, :class, :method_def, :field_def, :static_block, :private_name, :unary, :update, :binary, :logical, :assign, :cond, :call, :new, :member, :chain, :seq, :spread, :yield, :await, :meta_property, :import_call, :array_pattern, :object_pattern, :assign_pattern, :rest]

-> js_kind_codes
  h = {}
  i = 0
  while i < JS_KINDS.size
    h[JS_KINDS[i]] = i + 1
    i += 1
  h

JS_KIND_CODE = js_kind_codes()

-> js_hex64(v)
  s = v.to_s(16)
  while s.size < 16
    s = "0" + s
  s

# wyhash64 of a node's canonical encoding (positions excluded).
-> js_node_hash(n)
  w = JsAstWriter.new(false)
  w.node(n)
  Digest.string64(w.sb.to_s)

-> js_byte_strings
  t = [""]
  i = 1
  while i < 128
    t.push(i.chr)
    i += 1
  t

JS_BYTE = js_byte_strings()

# Compact symbol for a canonical hash, in the style of content_hash.w.
-> js_wy_symbol(h)
  "__wy_" + js_hex64(h)

+ JsAstWriter
  ro :sb, :psb, :fns, :count

  # meta: also record positions and the functions to hash.
  -> new(@meta)
    @sb = StringBuffer()
    @psb = StringBuffer()
    @fns = []
    @count = 0
    @last = 0
    @size = 0

  -> varint(sb, v)
    while v >= 63
      sb.append(JS_BYTE[64 + (v & 63)])
      v = v >> 6
    sb.append(JS_BYTE[v + 1])

  -> node(n)
    idx = @count
    @count += 1
    sb = @sb
    start = sb.size
    if @meta
      d = n.pos - @last
      varint(@psb, d >= 0 ? d * 2 : (0 - d) * 2 - 1)
      varint(@psb, n.fin - n.pos)
      @last = n.pos
    k = n.kind
    sb.append(JS_BYTE[JS_KIND_CODE[k]])
    str = n.str
    a = n.a
    b = n.b
    c = n.c
    d = n.d
    list = n.list
    flags = n.flags
    mask = 1
    mask = 2 if str != nil
    mask = mask + 2 if a != nil
    mask = mask + 4 if b != nil
    mask = mask + 8 if c != nil
    mask = mask + 16 if d != nil
    mask = mask + 32 if list != nil
    if flags != 0
      sb.append(JS_BYTE[mask + 64])
      varint(sb, flags)
    else
      sb.append(JS_BYTE[mask])
    if str != nil
      varint(sb, str.size)
      sb.append(str)
    value(a) if a != nil
    value(b) if b != nil
    value(c) if c != nil
    value(d) if d != nil
    value(list) if list != nil
    if @meta && (k == :function || k == :function_decl || k == :arrow)
      @fns.push(idx)
      @fns.push(start)
      @fns.push(sb.size)
    nil

  -> value(x)
    if x.is_a?(JsNode)
      node(x)
    elsif x.is_a?(Array)
      sb = @sb
      sb.append(JS_BYTE[120])
      varint(sb, x.size)
      x.each ->(y)
        if y == nil
          sb.append(JS_BYTE[119])
        else
          node(y)
    elsif x.is_a?(String)
      @sb.append(JS_BYTE[121])
      varint(@sb, x.size)
      @sb.append(x)
    else
      v = x.to_f
      if v >= ~0.0 && v < ~9007199254740992.0 && v == v.floor
        @sb.append(JS_BYTE[123])
        varint(@sb, v.to_i)
      else
        t = v.to_s
        @sb.append(JS_BYTE[122])
        varint(@sb, t.size)
        @sb.append(t)

  # The whole file image, as a String. Fills @hashes: per function its
  # pre-order index and canonical wyhash64.
  -> file_image(prog, mod)
    node(prog)
    body = @sb.to_s
    out = StringBuffer()
    out.append("JSAST")
    out.append(JS_BYTE[JS_AST_VERSION])
    out.append(mod ? "m" : "s")
    varint(out, body.size)
    varint(out, @psb.size)
    varint(out, @fns.size / 3)
    out.append(body)
    out.append(@psb.to_s)
    @hashes = []
    i = 0
    while i < @fns.size
      h = Digest.string64(body.slice(@fns[i + 1], @fns[i + 2] - @fns[i + 1]))
      @hashes.push(@fns[i])
      @hashes.push(h)
      varint(out, @fns[i])
      out.append(js_hex64(h))
      i += 3
    out.to_s

  ro :hashes

# Serialise a parsed program; returns [image String, writer]. writer.hashes
# lists [pre-order index, wyhash64] pairs for every function.
-> js_ast_encode(prog, mod)
  w = JsAstWriter.new(true)
  img = w.file_image(prog, mod)
  [img, w]

+ JsAstReader
  ro :count, :fn_table, :module

  -> new(@s)
    @p = 0
    @pp = 0
    @last = 0
    @count = 0
    @fn_table = nil
    @module = false

  -> varint_at
    s = @s
    b = s.byte_at(@p)
    @p += 1
    return b - 1 if b < 64
    v = b - 64
    shift = 6
    while true
      b = s.byte_at(@p)
      @p += 1
      if b < 64
        return v | ((b - 1) << shift)
      v = v | ((b - 64) << shift)
      shift += 6

  -> pvarint
    s = @s
    b = s.byte_at(@pp)
    @pp += 1
    return b - 1 if b < 64
    v = b - 64
    shift = 6
    while true
      b = s.byte_at(@pp)
      @pp += 1
      if b < 64
        return v | ((b - 1) << shift)
      v = v | ((b - 64) << shift)
      shift += 6

  -> str_at
    n = varint_at()
    v = @s.slice(@p, n)
    @p += n
    v

  # Decodes a whole file image (a String); nil if it is not one this
  # version wrote.
  -> program
    s = @s
    return nil if s.size < 7 || s.slice(0, 5) != "JSAST" || s.byte_at(5) != JS_AST_VERSION
    @module = s.byte_at(6) == 109
    @p = 7
    slen = varint_at()
    plen = varint_at()
    nfn = varint_at()
    @pp = @p + slen
    fn_at = @pp + plen
    root = node(s.byte_at(@p))
    @p = fn_at
    t = []
    i = 0
    while i < nfn
      t.push(varint_at())
      t.push(s.slice(@p, 16))
      @p += 16
      i += 1
    @fn_table = t
    root

  # @p is at the node's kind byte.
  -> node(code)
    @count += 1
    s = @s
    @p += 1
    # positions (one-byte varints inline)
    pp = @pp
    d = s.byte_at(pp)
    if d < 64
      d -= 1
      @pp = pp + 1
    else
      d = pvarint()
    pos = @last + ((d & 1) == 0 ? d >> 1 : 0 - ((d + 1) >> 1))
    @last = pos
    pp = @pp
    e = s.byte_at(pp)
    if e < 64
      fin = pos + e - 1
      @pp = pp + 1
    else
      fin = pos + pvarint()
    p = @p
    mask = s.byte_at(p) - 1
    @p = p + 1
    flags = 0
    if mask >= 64
      mask = mask - 64
      flags = varint_at()
    str = nil
    if (mask & 1) != 0
      p = @p
      ln = s.byte_at(p)
      if ln < 64
        str = s.slice(p + 1, ln - 1)
        @p = p + ln
      else
        str = str_at()
    a = (mask & 2) != 0 ? value() : nil
    b = (mask & 4) != 0 ? value() : nil
    c = (mask & 8) != 0 ? value() : nil
    dd = (mask & 16) != 0 ? value() : nil
    list = (mask & 32) != 0 ? value() : nil
    n = JsNode.new(JS_KINDS[code - 1], pos, fin, str, a, b, c, list, flags)
    n.d = dd if dd != nil
    n

  -> value
    s = @s
    t = s.byte_at(@p)
    return node(t) if t < 119
    @p += 1
    if t == 120
      n = varint_at()
      arr = []
      i = 0
      while i < n
        e = s.byte_at(@p)
        if e == 119
          @p += 1
          arr.push(nil)
        else
          arr.push(node(e))
        i += 1
      return arr
    return str_at() if t == 121
    return varint_at().to_f if t == 123
    str_at().to_f

# Decode a .jsast image held in a String; nil when it is not a valid image.
-> js_ast_decode(s)
  JsAstReader.new(s).program()

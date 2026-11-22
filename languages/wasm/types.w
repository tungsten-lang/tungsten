# wasm/types — value types, the canonical type registry and the decoded module structure.
#
# Value types are plain integers so they compare with == and fit in typed arrays:
#   numeric  I32 0x7f, I64 0x7e, F32 0x7d, F64 0x7c, V128 0x7b; packed storage I8 0x78, I16 0x77
#   BOT      0: the bottom type validation gives values popped from an unreachable stack
#   ref      REF_BIT | (NULL_BIT if nullable) | heap type
# A heap type is either abstract (HT_ABS + its binary code, e.g. HT_ABS + 0x70 for func) or
# a canonical type id (< HT_ABS). Canonical ids are process-wide: iso-recursive type
# equivalence (GC proposal) holds across modules exactly when the ids are equal, so
# call_indirect, imports and casts compare integers.

I32 = 0x7f
I64 = 0x7e
F32 = 0x7d
F64 = 0x7c
V128 = 0x7b
I8 = 0x78
I16 = 0x77
BOT = 0

REF_BIT = 1048576     # 1 << 20
NULL_BIT = 524288     # 1 << 19
HT_ABS = 262144       # 1 << 18
HT_MASK = 524287

HT_FUNC = HT_ABS + 0x70
HT_EXTERN = HT_ABS + 0x6f
HT_ANY = HT_ABS + 0x6e
HT_EQ = HT_ABS + 0x6d
HT_I31 = HT_ABS + 0x6c
HT_STRUCT = HT_ABS + 0x6b
HT_ARRAY = HT_ABS + 0x6a
HT_EXN = HT_ABS + 0x69
HT_NOEXN = HT_ABS + 0x74
HT_NOFUNC = HT_ABS + 0x73
HT_NOEXTERN = HT_ABS + 0x72
HT_NONE = HT_ABS + 0x71
HT_BOT = HT_ABS + 0x01   # validation only: the heap type of a ref popped from an unreachable stack

FUNCREF = REF_BIT + NULL_BIT + HT_FUNC
EXTERNREF = REF_BIT + NULL_BIT + HT_EXTERN
ANYREF = REF_BIT + NULL_BIT + HT_ANY
EXNREF = REF_BIT + NULL_BIT + HT_EXN

-> wt_ref(nullable, ht)
  REF_BIT + (nullable ? NULL_BIT : 0) + ht

-> wt_ref?(t)
  t >= REF_BIT

-> wt_ht(t)
  t & (HT_ABS + HT_ABS - 1)

-> wt_nullable?(t)
  (t & NULL_BIT) != 0

-> wt_num?(t)
  t == I32 || t == I64 || t == F32 || t == F64

# Interpreter stack slots a value of this type takes (v128 is two i64 words).
-> wt_slots(t)
  t == V128 ? 2 : 1

-> wt_packed?(t)
  t == I8 || t == I16

# The value type a storage type unpacks to.
-> wt_unpack(t)
  wt_packed?(t) ? I32 : t

-> wt_name(t)
  return "i32" if t == I32
  return "i64" if t == I64
  return "f32" if t == F32
  return "f64" if t == F64
  return "v128" if t == V128
  return "i8" if t == I8
  return "i16" if t == I16
  return "bot" if t == BOT
  if wt_ref?(t)
    return "(ref " + (wt_nullable?(t) ? "null " : "") + wt_ht_name(wt_ht(t)) + ")"
  "?" + t.to_s

-> wt_ht_name(h)
  return "func" if h == HT_FUNC
  return "extern" if h == HT_EXTERN
  return "any" if h == HT_ANY
  return "eq" if h == HT_EQ
  return "i31" if h == HT_I31
  return "struct" if h == HT_STRUCT
  return "array" if h == HT_ARRAY
  return "exn" if h == HT_EXN
  return "noexn" if h == HT_NOEXN
  return "nofunc" if h == HT_NOFUNC
  return "noextern" if h == HT_NOEXTERN
  return "none" if h == HT_NONE
  return "bot" if h == HT_BOT
  "$" + h.to_s


# ---- errors ----

# The binary is not well-formed (assert_malformed).
+ WasmMalformed < StandardError
# The module is well-formed but does not validate (assert_invalid).
+ WasmInvalid < StandardError
# Instantiation failed: unknown import, incompatible import type (assert_unlinkable).
+ WasmLinkError < StandardError
# A trap (assert_trap). kind is a symbol, message the spec wording.
+ WasmTrap < StandardError
  rw :msg
  -> new(@msg)
  -> message
    @msg
  -> to_s
    @msg
# A wasm exception (exception handling proposal) propagating through host frames.
+ WasmException < StandardError
  rw :exn
  -> new(@exn)
  -> message
    "uncaught wasm exception"
  -> to_s
    "uncaught wasm exception"
# Call stack exhausted (assert_exhaustion).
+ WasmExhaustion < StandardError
  rw :msg
  -> new(@msg)
  -> message
    @msg
  -> to_s
    @msg

-> w_malformed(msg)
  raise WasmMalformed, msg

-> w_invalid(msg)
  raise WasmInvalid, msg

-> w_trap(msg)
  raise WasmTrap.new(msg)


# ---- composite types and the canonical registry ----

# One subtype definition. kind: 0 func, 1 struct, 2 array.
# func: params / results (Arrays of value types). struct: ftypes / fmuts (storage types,
# mutability). array: ftypes[0] / fmuts[0]. supers: declared supertypes (canonical ids
# once registered; module indices while decoding). final: no subtypes allowed.
+ WSubType
  rw :kind, :params, :results, :ftypes, :fmuts, :supers, :final, :canon, :depth, :slots, :key

  -> new(@kind)
    @params = []
    @results = []
    @ftypes = []
    @fmuts = []
    @supers = []
    @final = true
    @canon = -1
    @depth = 0
    @slots = nil
    @key = nil

  -> func?
    @kind == 0

  -> struct?
    @kind == 1

  -> array?
    @kind == 2

  -> param_slots
    n = 0
    @params.each ->(t) n += wt_slots(t)
    n

  -> result_slots
    n = 0
    @results.each ->(t) n += wt_slots(t)
    n

# The process-wide registry of canonical (iso-recursive) types.
+ WTypeRegistry
  rw :types, :by_key

  -> new
    @types = []
    @by_key = {}

  -> [](id)
    @types[id]

  # Is canonical type a a (reflexive, transitive) subtype of b?
  -> sub?(a, b)
    return true if a == b
    t = @types[a]
    while t.supers.size > 0
      s = t.supers[0]
      return true if s == b
      t = @types[s]
    false

W_TYPES = WTypeRegistry.new

-> wt_canon(id)
  W_TYPES.types[id]

# The abstract top of a heap type's hierarchy.
-> wt_ht_top(h)
  if h < HT_ABS
    k = W_TYPES.types[h].kind
    return k == 0 ? HT_FUNC : HT_ANY
  return HT_FUNC if h == HT_FUNC || h == HT_NOFUNC
  return HT_EXTERN if h == HT_EXTERN || h == HT_NOEXTERN
  return HT_EXN if h == HT_EXN || h == HT_NOEXN
  HT_ANY

# The bottom of a heap type's hierarchy.
-> wt_ht_bottom(h)
  top = wt_ht_top(h)
  return HT_NOFUNC if top == HT_FUNC
  return HT_NOEXTERN if top == HT_EXTERN
  return HT_NOEXN if top == HT_EXN
  HT_NONE

-> wt_heap_sub?(a, b)
  return true if a == b
  return true if a == HT_BOT
  return false if b == HT_BOT
  if b < HT_ABS
    # concrete supertype
    return W_TYPES.sub?(a, b) if a < HT_ABS
    k = W_TYPES.types[b].kind
    return a == HT_NOFUNC if k == 0
    return a == HT_NONE
  if a < HT_ABS
    k = W_TYPES.types[a].kind
    return b == HT_FUNC if k == 0
    return b == HT_STRUCT || b == HT_EQ || b == HT_ANY if k == 1
    return b == HT_ARRAY || b == HT_EQ || b == HT_ANY
  return a == HT_NONE || a == HT_I31 || a == HT_STRUCT || a == HT_ARRAY || a == HT_EQ if b == HT_ANY
  return a == HT_NONE || a == HT_I31 || a == HT_STRUCT || a == HT_ARRAY if b == HT_EQ
  return a == HT_NONE if b == HT_I31 || b == HT_STRUCT || b == HT_ARRAY
  return a == HT_NOFUNC if b == HT_FUNC
  return a == HT_NOEXTERN if b == HT_EXTERN
  return a == HT_NOEXN if b == HT_EXN
  false

-> wt_sub?(a, b)
  return true if a == b
  return true if a == BOT
  return false if b == BOT
  if wt_ref?(a) && wt_ref?(b)
    return false if wt_nullable?(a) && !wt_nullable?(b)
    return wt_heap_sub?(wt_ht(a), wt_ht(b))
  false

# Storage type subtyping for struct/array fields: immutable fields are covariant,
# mutable ones invariant.
-> wt_field_sub?(ta, ma, tb, mb)
  return false if ma != mb
  return ta == tb if ma
  wt_sub?(ta, tb)

# Do two canonical subtypes match structurally so that a may declare b as its super?
-> wt_valid_super?(a, b)
  return false if a.kind != b.kind
  return false if b.final
  if a.kind == 0
    return false if a.params.size != b.params.size || a.results.size != b.results.size
    i = 0
    while i < a.params.size
      return false if !wt_sub?(b.params[i], a.params[i])
      i += 1
    i = 0
    while i < a.results.size
      return false if !wt_sub?(a.results[i], b.results[i])
      i += 1
    return true
  return false if a.ftypes.size < b.ftypes.size
  return false if a.kind == 2 && a.ftypes.size != 1
  i = 0
  while i < b.ftypes.size
    return false if !wt_field_sub?(a.ftypes[i], a.fmuts[i], b.ftypes[i], b.fmuts[i])
    i += 1
  true

# A value type with in-group references written relative (for the rec-group key).
-> wt_key_vt(t, g0, n, canon)
  return t.to_s if !wt_ref?(t)
  h = wt_ht(t)
  pre = wt_nullable?(t) ? "n" : "r"
  return pre + "a" + h.to_s if h >= HT_ABS
  return pre + "R" + (h - g0).to_s if h >= g0 && h < g0 + n
  pre + "C" + canon[h].to_s

-> wt_map_vt(t, g0, base, canon)
  return t if !wt_ref?(t)
  h = wt_ht(t)
  return t if h >= HT_ABS
  nh = h >= g0 ? base + (h - g0) : canon[h]
  (t - h) + nh

# Register one recursion group (module type indices g0 ... g0+n, already decoded with
# module-relative indices) and fill canon[] for them. Returns nothing; raises WasmInvalid
# on bad subtyping.
-> wt_register_group(defs, g0, n, canon)
  key = StringBuffer.new
  i = 0
  while i < n
    d = defs[g0 + i]
    key.append("|" + d.kind.to_s + (d.final ? "f" : "o"))
    d.supers.each ->(s) key.append("s" + (s >= g0 ? "R" + (s - g0).to_s : "C" + canon[s].to_s))
    d.params.each ->(t) key.append("p" + wt_key_vt(t, g0, n, canon))
    d.results.each ->(t) key.append("q" + wt_key_vt(t, g0, n, canon))
    j = 0
    while j < d.ftypes.size
      key.append("f" + wt_key_vt(d.ftypes[j], g0, n, canon) + (d.fmuts[j] ? "m" : "c"))
      j += 1
    i += 1
  k = key.to_s
  base = W_TYPES.by_key[k]
  if base != nil
    i = 0
    while i < n
      canon[g0 + i] = base + i
      i += 1
    return nil
  base = W_TYPES.types.size
  i = 0
  while i < n
    canon[g0 + i] = base + i
    i += 1
  i = 0
  while i < n
    d = defs[g0 + i]
    c = WSubType.new(d.kind)
    c.final = d.final
    c.params = d.params.map ->(t) wt_map_vt(t, g0, base, canon)
    c.results = d.results.map ->(t) wt_map_vt(t, g0, base, canon)
    c.ftypes = d.ftypes.map ->(t) wt_map_vt(t, g0, base, canon)
    c.fmuts = d.fmuts.dup
    c.supers = d.supers.map ->(s) s >= g0 ? base + (s - g0) : canon[s]
    c.canon = base + i
    W_TYPES.types.push(c)
    i += 1
  # subtyping checks need the whole group registered
  i = 0
  while i < n
    c = W_TYPES.types[base + i]
    if c.supers.size > 1
      w_invalid("multiple supertypes")
    if c.supers.size == 1
      s = c.supers[0]
      w_invalid("sub type") if s >= base + i
      sup = W_TYPES.types[s]
      w_invalid("sub type") if !wt_valid_super?(c, sup)
      c.depth = sup.depth + 1
    i += 1
  W_TYPES.by_key[k] = base
  nil

# A func type's canonical id, registering a singleton group (used by the JS API and tests).
-> wt_func_type(params, results)
  d = WSubType.new(0)
  d.params = params
  d.results = results
  canon = [0]
  wt_register_group([d], 0, 1, canon)
  canon[0]


# ---- the decoded module ----

# An import. kind: 0 func, 1 table, 2 memory, 3 global, 4 tag. desc: type index (func,
# tag), WTableType, WMemType or WGlobalType.
+ WImport
  rw :mod, :name, :kind, :desc
  -> new(@mod, @name, @kind, @desc)

+ WExport
  rw :name, :kind, :index
  -> new(@name, @kind, @index)

+ WTableType
  rw :elem, :min, :max, :is64, :init
  -> new(@elem, @min, @max, @is64)
    @init = nil

+ WMemType
  rw :min, :max, :shared, :is64, :page_log2
  -> new(@min, @max, @shared, @is64)
    @page_log2 = 16

+ WGlobalType
  rw :type, :mutable, :init
  -> new(@type, @mutable)
    @init = nil

# A constant expression: the raw instruction bytes [start, stop) of the module (end excluded).
+ WConstExpr
  rw :start, :stop, :type
  -> new(@start, @stop, @type)

# mode: 0 active, 1 passive, 2 declarative.
+ WElem
  rw :mode, :table, :offset, :type, :items, :funcs
  -> new(@mode, @table, @offset, @type)
    @items = []
    @funcs = nil

+ WData
  rw :mode, :mem, :offset, :start, :size
  -> new(@mode, @mem, @offset, @start, @size)

# A function body: local declarations and the expression's byte range.
+ WCode
  rw :locals, :start, :stop, :compiled
  -> new(@locals, @start, @stop)
    @compiled = nil

+ WModule
  rw :bytes, :types, :canon, :imports, :funcs, :tables, :mems, :globals, :exports, :start, :elems, :datas, :codes, :tags, :customs, :data_count, :func_names, :n_imp_funcs, :n_imp_tables, :n_imp_mems, :n_imp_globals, :n_imp_tags, :declared_funcs, :code, :fentry, :compiled, :uses_refs, :name, :jit

  -> new(@bytes)
    @types = []
    @canon = []
    @imports = []
    @funcs = []        # type index of every function (imports first)
    @tables = []       # WTableType (imports first)
    @mems = []         # WMemType (imports first)
    @globals = []      # WGlobalType (imports first)
    @exports = []
    @start = nil
    @elems = []
    @datas = []
    @codes = []
    @tags = []         # type index of every tag (imports first)
    @customs = []      # [name, start, size]
    @data_count = nil
    @func_names = {}
    @n_imp_funcs = 0
    @n_imp_tables = 0
    @n_imp_mems = 0
    @n_imp_globals = 0
    @n_imp_tags = 0
    @declared_funcs = {}
    @code = nil
    @fentry = nil
    @compiled = false
    @uses_refs = false
    @name = nil
    @jit = nil

  # The WSubType of a module type index (canonical).
  -> type_at(i)
    W_TYPES.types[@canon[i]]

  -> func_type(fi)
    W_TYPES.types[@canon[@funcs[fi]]]

  -> tag_type(ti)
    W_TYPES.types[@canon[@tags[ti]]]

  -> custom_bytes(i)
    c = @customs[i]
    @bytes.copy(c[1], c[2])

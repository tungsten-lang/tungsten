
# ---- Device helper function emission ----
#
# Emits a `@gpu fn` with a `ret` hint as a plain device function:
#   ## vec3: p
#   ## f32: ret
#   @gpu fn sdScene(p)  →  float sdScene(float3 p) { … }
# These are emitted before the kernels so the kernels (and later helpers)
# can call them by name. Reuses the same statement/expression emitters as
# kernels — only the signature differs (typed return, no thread-id args).
-> emit_device_fn(node, gpu_fns)
  name = node.name
  params = node.params
  type_hints = node.type_hints
  if type_hints == nil
    type_hints = {}
  ret_msl = msl_scalar_type(type_hints["ret"])
  if ret_msl == nil
    gpu_kernel_error(node, "device fn `" + name + "` has unsupported return type `" + type_hints["ret"].to_s() + "`")

  param_types = {}
  param_names = []
  pi = 0
  while pi < params.size()
    p = params[pi]
    pname = p.name
    ptype = type_hints[pname]
    if ptype == nil
      gpu_kernel_error(node, "device fn `" + name + "` param `" + pname + "` needs a ## type hint")
    if !gpu_param_type_supported?(ptype)
      gpu_kernel_error(node, "device fn `" + name + "` param `" + pname + "` has unsupported type `" + ptype.to_s() + "`")
    param_types[pname] = ptype
    param_names.push(pname)
    pi += 1

  out = StringBuffer(256)
  out << ret_msl
  out << " "
  out << name
  out << "("
  pi = 0
  while pi < param_names.size()
    pname = param_names[pi]
    if pi > 0
      out << ", "
    pt = param_types[pname]
    arr_elt = msl_array_elt_type(pt)
    if arr_elt != nil
      out << gpu_param_address_space(node, pname, pt, false)
      out << " "
      out << arr_elt
      out << " *"
      out << pname
    else
      sc = msl_scalar_type(pt)
      if sc == nil
        gpu_kernel_error(node, "device fn `" + name + "` param `" + pname + "` has unsupported type")
      out << sc
      out << " "
      out << pname
    pi += 1
  out << ") {\n"

  ctx = {
    node: node,
    var_types: dup_hash(param_types),
    params: param_names,
    indent: 1,
    dialect: "metal",
    gpu_fns: gpu_fns,
    declared: {},
    hoist: [],
    tables: [],
    renames: {},
    unroll: {},
    array_bounds: gpu_param_array_bounds(param_names, param_types),
    address_spaces: gpu_param_address_spaces(node, param_names, param_types, false),
    shared_bytes: 0
  }
  body = node.body
  n = body.size()
  body_out = StringBuffer(256)
  bi = 0
  while bi < n
    stmt = body[bi]
    # Tungsten has no `return` keyword — a method yields its last
    # expression. So the FINAL body statement, when it's a value
    # expression (not an assign / if / while / store), becomes the
    # device function's `return`. Earlier statements (assigns building up
    # locals) emit normally.
    if bi == n - 1 && gpu_is_value_expr?(stmt)
      emit_indent(body_out, ctx)
      body_out << "return "
      body_out << emit_expr(ctx, stmt)
      body_out << ";\n"
    else
      emit_stmt(body_out, ctx, stmt)
    bi += 1
  gpu_emit_hoisted(out, ctx)
  out << body_out.to_s()
  out << "}\n"
  gpu_with_tables(ctx, out.to_s())

# True when a body statement is a value-producing expression eligible to
# be a device function's implicit return (vs. a control/store statement).
-> gpu_is_value_expr?(node)
  if !is_ast_node?(node)
    return false
  k = ast_kind(node)
  if k in (:binary_op :unary_op :and :or :not :int :float :decimal :bool :var)
    return true
  if k == :if && gpu_is_ternary?(node)
    return true
  if k == :call
    # A `[]=` store isn't a return value; an `[]` read or a normal call is.
    if ("" + node.name.to_s()) == "\[]="
      return false
    return true
  false

# True when an If node is a ternary (`cond ? a : b`): exactly one
# then-expression and one else-expression, no elsif clauses.
-> gpu_is_ternary?(node)
  if ast_kind(node) != :if
    return false
  ec = node.elsif_clauses
  if ec != nil && ec.size() > 0
    return false
  tb = node.then_body
  eb = node.else_body
  if tb == nil || eb == nil
    return false
  tb.size() == 1 && eb.size() == 1

# ---- Per-kernel emission ----

-> emit_kernel(node, gpu_fns)
  name = node.name
  params = node.params
  type_hints = node.type_hints
  if type_hints == nil
    type_hints = {}

  param_types = {}
  param_names = []
  pi = 0
  while pi < params.size()
    p = params[pi]
    pname = p.name
    ptype = type_hints[pname]
    if ptype == nil
      gpu_kernel_error(node, "parameter `" + pname + "` needs a ## type hint (f32[] / i32 / etc)")
    if !gpu_param_type_supported?(ptype)
      gpu_kernel_error(node, "parameter `" + pname + "` has unsupported type `" + ptype.to_s() + "`")
    param_types[pname] = ptype
    param_names.push(pname)
    pi += 1

  out = StringBuffer(512)
  # Allow the kernel to be dispatched with up to 1024 threads/TG so it
  # can use the threadgroup-wide reduction helpers (which scale up to
  # 32 simdgroups). Lower dispatch counts work fine — this is a max.
  out << "\[\[max_total_threads_per_threadgroup(1024)]]\n"
  out << "kernel void "
  out << name
  out << "(\n"
  # Signature — buffers first, then the thread_position_in_grid attribute.
  buf_index = 0
  pi = 0
  while pi < param_names.size()
    pname = param_names[pi]
    if pi > 0
      out << ",\n"
    out << "  "
    out << msl_param_decl(node, param_types[pname], pname, buf_index)
    buf_index = buf_index + 1
    pi += 1
  # Emit all the thread/group/simdgroup IDs the kernel might reference
  # (Apple Silicon, MSL 2.0+). They're free unless used and let any
  # @gpu fn reach into cooperative reductions via gpu.simd_lane / etc.
  # Declared as uint3 so 2D/3D dispatches can access .y / .z components.
  # 1D dispatches see those as 0 — same behavior as before.
  # Metal requires all grid-position-style attributes to have the same
  # vector width: __tg_size must match the others. The simdgroup-related
  # IDs are scalar by definition (different category).
  out << ",\n  uint3 __tid \[\[thread_position_in_grid]]"
  out << ",\n  uint3 __tid_in_tg \[\[thread_position_in_threadgroup]]"
  out << ",\n  uint3 __tg_id \[\[threadgroup_position_in_grid]]"
  out << ",\n  uint3 __tg_size \[\[threads_per_threadgroup]]"
  out << ",\n  uint __simd_lane \[\[thread_index_in_simdgroup]]"
  out << ",\n  uint __simd_id \[\[simdgroup_index_in_threadgroup]\]\n"
  out << ") {\n"
  # Per-type scratch arrays for tg_sum/tg_max/tg_min helpers. Sized at
  # 32 (max simdgroups per TG = 1024 / 32).
  #
  # Declared ONLY when the kernel actually reduces. These were previously
  # unconditional, on the reasoning that ~256 bytes is cheap and an unused
  # threadgroup array costs nothing. On Apple Silicon it is not free:
  # threadgroup memory is a per-core resource that bounds how many
  # threadgroups can be resident, so a kernel that never reduces was still
  # paying occupancy for scratch it never touched. Removing it from the
  # SHA-256 miner in bits/tungsten-crypto is worth 1.55x (795 -> 1236 MH/s).
  # Every `@gpu fn` that does no threadgroup reduction gets that back.
  if gpu_uses_tg_reduce?(node)
    out << "  threadgroup float __tg_scratch_f\[32];\n"
    out << "  threadgroup int   __tg_scratch_i\[32];\n"
  # Scalar total thread count — folds the uint3 __tg_size to a single
  # integer for downstream divisions (e.g. tg_sum's __tg_size / 32).
  # The compiler optimizes this away when uint3 elements are known constants.
  out << "  uint __tg_total = __tg_size.x * __tg_size.y * __tg_size.z;\n"

  # The body. Types flow through a context populated with param types
  # and local var types as assignments introduce them.
  ctx = {
    node: node,
    var_types: dup_hash(param_types),
    params: param_names,
    indent: 1,
    dialect: "metal",
    gpu_fns: gpu_fns,
    declared: {},
    hoist: [],
    tables: [],
    renames: {},
    unroll: {},
    array_bounds: gpu_param_array_bounds(param_names, param_types),
    address_spaces: gpu_param_address_spaces(node, param_names, param_types, true),
    shared_bytes: gpu_uses_tg_reduce?(node) ? 256 : 0
  }
  body = node.body
  body_out = StringBuffer(512)
  bi = 0
  while bi < body.size()
    emit_stmt(body_out, ctx, body[bi])
    bi += 1
  gpu_emit_hoisted(out, ctx)
  out << body_out.to_s()

  out << "}\n"
  gpu_with_tables(ctx, out.to_s())

# ---- Subset checker helpers ----

-> gpu_kernel_error(node, msg)
  hint = gpu_error_hint(msg)
  full = "@gpu kernel: " + msg
  if hint != nil
    full = full + "\n  help: " + hint
  raise compile_error_for_node(:E_GPU_KERNEL_UNSUPPORTED, full, nil, node)

# Short recovery hints for common GPU-subset mistakes.
-> gpu_error_hint(msg)
  if msg.include?("elsif")
    return "rewrite as nested `if` / `else` (elsif is supported as nested if/else chains in recent emitters — rebuild the compiler if you still see this)"
  if msg.include?("type hint")
    return "hint params on preceding lines (`## f32[]: x` above the @gpu fn) and locals with a trailing hint (`i = … ## i32`)"
  if msg.include?("CUDA-only")
    return "build with TUNGSTEN_GPU_DIALECTS=cuda (default) or use the Metal simdgroup_* surface"
  if msg.include?("unsupported statement") || msg.include?("unsupported expression")
    return "GPU kernels support assign, if/else, while, return, arithmetic, logic (`&&` / `||` / `!`), indexing, and gpu.* primitives — see doc/getting-started and metal_emitter.w"
  if msg.include?("unsupported")
    return "check the @gpu subset: typed arrays, scalars, and gpu.thread_position_in_grid / gpu.shared_* / barriers"
  nil

-> dup_hash(h)
  out = {}
  keys = h.keys()
  i = 0
  while i < keys.size()
    out[keys[i]] = h[keys[i]]
    i += 1
  out

# ---- Type mapping: Tungsten type-hint symbol → MSL type text ----

-> msl_scalar_type(t)
  t = gpu_hint_type(t)
  # Compare symbol-to-symbol. Tungsten's Symbol#to_s keeps the symbol
  # tag so `sym.to_s() == "literal"` can return false even when they
  # print identically; forcing symbol form sidesteps that.
  sym = t
  if type(t) == "String"
    sym = t.to_sym()
  if sym == :i8
    "char"
  elsif sym == :i16
    "short"
  elsif sym == :i32
    "int"
  elsif sym == :i64
    "long"
  elsif sym == :u8
    "uchar"
  elsif sym == :u16
    "ushort"
  elsif sym == :u32
    "uint"
  elsif sym == :u64
    "ulong"
  elsif sym in (:f16 :half)
    "half"
  elsif sym in (:f32 :float)
    "float"
  elsif sym in (:f64 :double)
    "float"
  elsif sym in (:f32x4 :float4)
    "float4"
  elsif sym in (:f32x2 :float2)
    "float2"
  elsif sym in (:f16x4 :half4)
    "half4"
  elsif sym in (:i32x4 :int4)
    "int4"
  elsif sym in (:u32x4 :uint4)
    "uint4"
  # Brain-float — Apple Silicon Metal 3.1+.
  elsif sym in (:bf16 :bfloat)
    "bfloat"
  elsif sym in (:bf16x4 :bfloat4)
    "bfloat4"
  # Hypercomplex tower. Math-Quaternion (scalar-first) does NOT map to
  # float4 — its layout doesn't match Metal's float4.w convention; call
  # `.to_metal` first to get a QuaternionMetal. Octonion and Sedenion
  # are scalar-first algebras that happen to byte-align to float4x2
  # and float4x4 contiguous storage (no layout convention to fight).
  elsif sym == :complex
    "float2"
  elsif sym == :quaternion_metal
    "float4"
  elsif sym == :octonion
    "float4x2"
  elsif sym == :sedenion
    "float4x4"
  # Vector tower — generic real-valued vectors, byte-aligned to Metal's
  # float2 / float3 / float4 family. f32 components by default;
  # parametric-T variants (e.g. Vec3<f16> → half3) land when generics ship.
  elsif sym == :vec2
    "float2"
  elsif sym == :vec3
    "float3"
  elsif sym == :vec4
    "float4"
  # Matrix tower — column-major like Metal's floatMxN; square sized
  # types (Mat2/Mat3/Mat4) plus rectangular Mat<T, M, N>.
  elsif sym == :mat2
    "float2x2"
  elsif sym == :mat3
    "float3x3"
  elsif sym == :mat4
    "float4x4"
  # SIMD-group cooperative matrix types (Apple Silicon, Metal 3+).
  # These map to the matrix-multiply accelerator HW. Each 8×8 matrix
  # is held cooperatively across a 32-thread SIMD-group's registers.
  # Pair with simdgroup_load / _multiply_accumulate / _store intrinsics.
  elsif sym in (:sg_f32 :simdgroup_float8x8)
    "simdgroup_float8x8"
  elsif sym in (:sg_bf16 :simdgroup_bfloat8x8)
    "simdgroup_bfloat8x8"
  elsif sym in (:sg_f16 :simdgroup_half8x8)
    "simdgroup_half8x8"
  elsif sym == :bool
    "bool"
  else
    nil

-> msl_array_elt_type(t)
  info = gpu_array_type_info(t)
  if info == nil
    return nil
  info[:elt]

-> gpu_array_type_info(t)
  if t == nil
    return nil
  t = gpu_hint_type(t)
  s = t.to_s()
  bytes = s.bytes()
  n = bytes.size()
  if n < 3 || bytes[n - 1] != 93
    return nil
  open = s.index("\[")
  if open == nil || open == 0
    return nil
  elt_name = s.slice(0, open)
  mapped = msl_scalar_type(elt_name.to_sym())
  if mapped == nil
    mapped = "UNMAPPED_" + elt_name
  extent_text = s.slice(open + 1, n - open - 2)
  bound = nil
  if extent_text != ""
    extent_bytes = extent_text.bytes()
    i = 0
    while i < extent_bytes.size()
      if extent_bytes[i] < 48 || extent_bytes[i] > 57
        return {elt: "UNMAPPED_" + s, bound: nil}
      i += 1
    bound = extent_text.to_i()
    if bound <= 0
      return {elt: "UNMAPPED_" + s, bound: nil}
  {elt: mapped, bound: bound}

-> gpu_array_bound(type_hint)
  info = gpu_array_type_info(type_hint)
  info == nil ? nil : info[:bound]

-> gpu_param_type_supported?(type_hint)
  arr_elt = msl_array_elt_type(type_hint)
  if arr_elt != nil
    return !arr_elt.starts_with?("UNMAPPED_")
  msl_scalar_type(type_hint) != nil

-> msl_param_decl(node, type_hint, pname, buf_index)
  arr_elt = msl_array_elt_type(type_hint)
  if arr_elt != nil
    space = gpu_param_address_space(node, pname, type_hint, true)
    return space + " " + arr_elt + " *" + pname + " \[\[buffer(" + buf_index.to_s() + ")]]"
  scalar = msl_scalar_type(type_hint)
  if scalar != nil
    return "constant " + scalar + " &" + pname + " \[\[buffer(" + buf_index.to_s() + ")]]"
  "/* unsupported type: " + type_hint.to_s() + " */ void *" + pname

# ---- Statement emission ----

-> emit_indent(out, ctx)
  n = ctx[:indent]
  i = 0
  while i < n
    out << "  "
    i += 1

# ---- Function-scoped locals ----
#
# Tungsten scopes a local to the whole enclosing function; C — and so MSL and
# CUDA — scopes it to the nearest enclosing block. Emitting the declaration
# where the first assignment happens is therefore only correct at the top
# level of a body: a variable first written inside an `if` or `while` and
# read after that block emits as `use of undeclared identifier`, and the
# .metal only fails much later, inside `xcrun metal`.
#
# So a declaration introduced at nesting depth > 1 is split — the declaration
# hoists to the top of the function and only the assignment stays where it
# was written. Declarations at the top level keep their initializer form,
# which leaves every kernel that never nests a first assignment byte-identical.

-> gpu_local_declared?(ctx, vname)
  d = ctx[:declared]
  if d == nil
    return false
  d.has_key?(vname)

# `decl` is the declarator without its trailing semicolon ("uint x",
# "int w[16]"). `value` is the initializer, or nil for a bare declaration
# such as a thread-private array.
-> gpu_declare_local(out, ctx, vname, decl, value)
  if ctx[:declared] != nil
    ctx[:declared][vname] = true
  if ctx[:hoist] != nil && ctx[:indent] > 1
    ctx[:hoist].push("  " + decl + ";\n")
    if value != nil
      emit_indent(out, ctx)
      out << vname
      out << " = "
      out << emit_expr(ctx, value)
      out << ";\n"
    return nil
  emit_indent(out, ctx)
  out << decl
  if value != nil
    out << " = "
    out << emit_expr(ctx, value)
  out << ";\n"
  nil

# Write the declarations collected while emitting a body. Called between a
# function's prologue and its body text.
-> gpu_emit_hoisted(out, ctx)
  h = ctx[:hoist]
  if h == nil
    return nil
  i = 0
  while i < h.size()
    out << h[i]
    i += 1
  nil

# ---- Type-hint flags ----
#
# A local's `## TYPE` hint may carry space-separated flags after the type:
#
#   i = 3 ## u32 unroll
#
# The type still drives the declaration; a flag is advice to the emitter.
# Flags are split here rather than in the parser, so no new surface syntax
# is introduced and a hint without a space behaves exactly as it did.
#
# `unroll` marks a loop induction variable: every `while` whose condition
# reads that variable is emitted under a full-unroll pragma. On a GPU that
# is not a micro-optimization. A thread-private array indexed by the
# induction variable (`w[i & 15]`) can only live in registers once every
# index is a compile-time constant; while the loop rolls, the array is
# stack traffic on every access. Unrolling is also what lets a constant
# table (below) fold into the instruction stream. Measured on the SHA-256
# miner in bits/tungsten-crypto: 502 -> 647 MH/s from unrolling alone, and
# the constant table only pays at all once the loop is unrolled.

-> gpu_hint_words(hint)
  if hint == nil
    return nil
  text = "" + hint.to_s()
  if text.index(" ") == nil
    return nil
  parts = text.split(" ")
  words = []
  i = 0
  while i < parts.size()
    p = parts[i].strip()
    if p != ""
      words.push(p)
    i += 1
  words

# The declaration type, with any trailing flags removed.
-> gpu_hint_type(hint)
  words = gpu_hint_words(hint)
  if words == nil || words.size() == 0
    return hint
  words[0].to_sym()

-> gpu_hint_flagged?(hint, flag)
  words = gpu_hint_words(hint)
  if words == nil
    return false
  i = 1
  while i < words.size()
    if words[i] == flag
      return true
    i += 1
  false

-> gpu_mark_unroll(ctx, vname, hint)
  if !gpu_hint_flagged?(hint, "unroll")
    return nil
  if ctx[:unroll] == nil
    ctx[:unroll] = {}
  ctx[:unroll]["" + vname.to_s()] = true
  nil

# True when `expr` reads a variable marked `unroll`. Applied to a while
# condition, this is what decides the loop carries the pragma. A bare
# identifier can reach here as either a :var or a zero-arg self-:call
# depending on parse position, so both spellings are checked.
-> gpu_reads_unroll_var?(ctx, expr)
  u = ctx[:unroll]
  if u == nil || expr == nil
    return false
  if !is_ast_node?(expr)
    return false
  k = ast_kind(expr)
  if k == :var
    return u.has_key?("" + expr.name.to_s())
  if k in (:binary_op :and :or)
    if gpu_reads_unroll_var?(ctx, expr.left)
      return true
    return gpu_reads_unroll_var?(ctx, expr.right)
  if k == :not
    return gpu_reads_unroll_var?(ctx, expr.operand)
  if k == :unary_op
    return gpu_reads_unroll_var?(ctx, expr.operand)
  if k == :call
    if expr.receiver == nil && (expr.args == nil || expr.args.size() == 0)
      return u.has_key?("" + expr.name.to_s())
    return false
  false

# ---- Program-scope constant tables ----
#
# An array literal assigned to a local inside a `@gpu fn`:
#
#   k = [0x428a2f98, 0x71374491, ...] ## u32\[]
#
# becomes a program-scope `constant` table instead of a thread-private
# array. MSL allows the `constant` address space only at program scope, so
# the table is lifted out of the body and the local name is rewritten to a
# mangled global; the kernel still reads it as `k[i]`.
#
# The alternative shapes both cost real throughput: a `## u32\[]` parameter
# is a device load on every access, and a thread-private `u32[64]` filled
# element by element is a per-thread copy. A program-scope constant is
# neither — once the reading loop is unrolled the compiler folds the
# entries into immediates. The SHA-256 round-constant table is exactly this
# shape and it is worth 647 -> 829 MH/s there.

-> gpu_const_table_name(ctx, vname)
  owner = "fn"
  if ctx[:node] != nil && ctx[:node].name != nil
    owner = "" + ctx[:node].name.to_s()
  "__gpu_const_" + owner + "_" + vname

-> gpu_declare_const_table(ctx, vname, type_hint, value)
  elt = msl_array_elt_type(type_hint)
  if elt == nil
    gpu_kernel_error(ctx[:node], "constant table `" + vname + "` needs an array type hint, e.g. `## u32\[]`")
  elems = value.elements
  if elems == nil || elems.size() == 0
    gpu_kernel_error(ctx[:node], "constant table `" + vname + "` needs at least one element")
  buf = StringBuffer(256)
  if ctx[:dialect] == "cuda"
    buf << "__device__ __constant__ "
  else
    buf << "constant "
  buf << elt
  buf << " "
  buf << gpu_const_table_name(ctx, vname)
  buf << "\["
  buf << elems.size().to_s()
  buf << "] = {"
  i = 0
  while i < elems.size()
    if i > 0
      buf << ", "
    buf << emit_expr(ctx, elems[i])
    i += 1
  buf << "};\n"
  if ctx[:tables] == nil
    ctx[:tables] = []
  ctx[:tables].push(buf.to_s())
  if ctx[:renames] == nil
    ctx[:renames] = {}
  ctx[:renames][vname] = gpu_const_table_name(ctx, vname)
  ctx[:var_types][vname] = type_hint
  ctx[:address_spaces][vname] = "constant"
  ctx[:array_bounds][vname] = elems.size()
  if ctx[:declared] != nil
    ctx[:declared][vname] = true
  nil

# A local rewritten to a program-scope table reads under its mangled name.
-> gpu_local_name(ctx, vname)
  r = ctx[:renames]
  if r != nil && r.has_key?(vname)
    return r[vname]
  vname

# Program-scope text collected while emitting a body, placed ahead of the
# function it belongs to. Returns `text` untouched when no table was
# declared, which keeps every existing kernel byte-identical.
-> gpu_with_tables(ctx, text)
  t = ctx[:tables]
  if t == nil || t.size() == 0
    return text
  out = StringBuffer(512)
  i = 0
  while i < t.size()
    out << t[i]
    i += 1
  out << "\n"
  out << text
  out.to_s()

-> emit_stmt(out, ctx, node)
  t = ast_kind(node)
  if t == :assign
    emit_assign(out, ctx, node)
  elsif t == :compound_assign
    emit_indent(out, ctx)
    out << emit_expr(ctx, node.target)
    out << " " + binop_symbol(node.op) + "= "
    out << emit_expr(ctx, node.value)
    out << ";\n"
  elsif t == :if
    emit_if(out, ctx, node)
  elsif t == :while
    emit_while(out, ctx, node)
  elsif t == :return
    emit_return(out, ctx, node)
  elsif t == :call
    emit_indent(out, ctx)
    out << emit_expr(ctx, node)
    out << ";\n"
  else
    gpu_kernel_error(ctx[:node], "unsupported statement node `" + t.to_s() + "`")

-> gpu_shared_size(kernel_node, call, dialect)
  name = "" + call.name.to_s()
  args = call.args
  if args == nil || args.size() != 1 || ast_kind(args[0]) != :int
    gpu_kernel_error(kernel_node, "gpu." + name + " takes one positive integer-literal size")
  size = args[0].value
  if size <= 0
    gpu_kernel_error(kernel_node, "gpu." + name + " size must be positive (got " + size.to_s() + ")")
  if dialect == "wgsl" && name == "shared_i64"
    gpu_kernel_error(kernel_node, "gpu.shared_i64 is not supported by the WGSL dialect")
  size

-> gpu_shared_limit(dialect)
  if dialect == "wgsl"
    return 16384
  if dialect == "cuda"
    return 49152
  32768

-> gpu_record_shared_allocation(ctx, name, size)
  bytes_per_element = name == "shared_i64" ? 8 : 4
  previous = ctx[:shared_bytes]
  if previous == nil
    previous = 0
  total = previous + size * bytes_per_element
  limit = gpu_shared_limit(ctx[:dialect])
  if total > limit
    gpu_kernel_error(ctx[:node], "aggregate workgroup memory " + total.to_s() + " bytes exceeds the " + ctx[:dialect] + " limit of " + limit.to_s() + " bytes")
  ctx[:shared_bytes] = total
  nil

-> gpu_static_index_value(node)
  if node == nil || !is_ast_node?(node)
    return nil
  kind = ast_kind(node)
  if kind == :int
    return node.value
  if kind == :unary_op && node.op == :MINUS
    operand = gpu_static_index_value(node.operand)
    return operand == nil ? nil : 0 - operand
  if kind != :binary_op
    return nil
  left = gpu_static_index_value(node.left)
  right = gpu_static_index_value(node.right)
  if left == nil || right == nil
    return nil
  if node.op == :PLUS
    return left + right
  if node.op == :MINUS
    return left - right
  if node.op == :STAR
    return left * right
  if node.op == :PERCENT && right != 0
    return left % right
  if node.op == :LSHIFT && right >= 0 && right < 63
    return left << right
  if node.op == :RSHIFT && right >= 0 && right < 63
    return left >> right
  nil

-> gpu_check_literal_bound(ctx, receiver, index)
  bounds = ctx[:array_bounds]
  if bounds == nil || receiver == nil || ast_kind(receiver) != :var
    return nil
  name = "" + receiver.name
  bound = bounds[name]
  if bound == nil
    return nil
  value = gpu_static_index_value(index)
  if value == nil
    return nil
  if value < 0 || value >= bound
    shape = ast_kind(index) == :int ? "literal" : "constant-computed"
    gpu_kernel_error(ctx[:node], "array `" + name + "` " + shape + " index " + value.to_s() + " is outside 0..." + bound.to_s())
  nil

-> gpu_param_array_bounds(param_names, param_types)
  bounds = {}
  i = 0
  while i < param_names.size()
    pname = param_names[i]
    bound = gpu_array_bound(param_types[pname])
    if bound != nil
      bounds[pname] = bound
    i += 1
  bounds

-> gpu_param_address_space(node, pname, type_hint, entry_kernel)
  words = gpu_hint_words(type_hint)
  address_space = nil
  if words != nil
    i = 1
    while i < words.size()
      word = words[i]
      if !(word in ("device" "constant" "threadgroup" "thread"))
        gpu_kernel_error(node, "parameter `" + pname + "` has unsupported address-space annotation `" + word + "`")
      if address_space != nil
        gpu_kernel_error(node, "parameter `" + pname + "` has multiple address-space annotations")
      address_space = word
      i += 1
  is_array = msl_array_elt_type(type_hint) != nil
  if !is_array
    if address_space != nil
      gpu_kernel_error(node, "scalar parameter `" + pname + "` cannot use the `" + address_space + "` address space")
    return nil
  if address_space == nil
    address_space = "device"
  if entry_kernel && address_space in ("threadgroup" "thread")
    gpu_kernel_error(node, "entry parameter `" + pname + "` cannot use the `" + address_space + "` address space; allocate it inside the kernel or pass it to a device helper")
  address_space

-> gpu_param_address_spaces(node, param_names, param_types, entry_kernel)
  spaces = {}
  i = 0
  while i < param_names.size()
    pname = param_names[i]
    space = gpu_param_address_space(node, pname, param_types[pname], entry_kernel)
    if space != nil
      spaces[pname] = space
    i += 1
  spaces

-> gpu_validate_device_call(ctx, name, args)
  signature = ctx[:gpu_fns][name]
  expected = signature[:param_types]
  actual_size = args == nil ? 0 : args.size()
  if actual_size != expected.size()
    gpu_kernel_error(ctx[:node], "device fn `" + name + "` expects " + expected.size().to_s() + " args (got " + actual_size.to_s() + ")")
  spaces = ctx[:address_spaces]
  expected_spaces = signature[:param_spaces]
  i = 0
  while i < expected.size()
    if msl_array_elt_type(expected[i]) != nil && ast_kind(args[i]) == :var
      arg_name = "" + args[i].name
      actual_space = spaces[arg_name]
      param_name = signature[:param_names][i]
      expected_space = expected_spaces == nil ? "device" : expected_spaces[param_name]
      if actual_space != nil && expected_space != nil && actual_space != expected_space
        gpu_kernel_error(ctx[:node], "device fn `" + name + "` parameter `" + param_name + "` expects " + expected_space + " memory, but `" + arg_name + "` is " + actual_space + " memory")
    i += 1
  nil

-> emit_assign(out, ctx, node)
  target = node.target
  value = node.value
  type_hint = node.type_hint
  # Threadgroup/shared memory declaration:
  #   tile = gpu.shared_f32(256)  →  threadgroup float tile[256];   (MSL)
  #                               →  __shared__ float tile[256];    (CUDA)
  # The size must be a compile-time integer literal.
  if ast_kind(target) == :var && value != nil && is_ast_node?(value) && ast_kind(value) == :call
    vrecv = value.receiver
    vname = "" + value.name.to_s()
    # Tensor-core fragment declarations (CUDA dialect only; the Metal path
    # uses the simdgroup_float8x8 surface instead):
    #   am = gpu.wmma_frag_a_bf16()   → wmma::fragment<matrix_a, 16,16,16, __nv_bfloat16, row_major>
    #   bm = gpu.wmma_frag_b_bf16()   → wmma::fragment<matrix_b, …>
    #   cm = gpu.wmma_frag_acc_f32()  → wmma::fragment<accumulator, 16,16,16, float>
    if vrecv != nil && is_ast_node?(vrecv) && ast_kind(vrecv) == :var && vrecv.name == "gpu" && (vname == "wmma_frag_a_bf16" || vname == "wmma_frag_b_bf16" || vname == "wmma_frag_acc_f32")
      if ctx[:dialect] != "cuda"
        gpu_kernel_error(ctx[:node], "gpu." + vname + " is CUDA-only (use simdgroup_* for Metal)")
      sname = target.name
      ctx[:var_types][sname] = :wmma_frag
      emit_indent(out, ctx)
      if vname == "wmma_frag_a_bf16"
        out << "wmma::fragment<wmma::matrix_a, 16, 16, 16, __nv_bfloat16, wmma::row_major> "
      elsif vname == "wmma_frag_b_bf16"
        out << "wmma::fragment<wmma::matrix_b, 16, 16, 16, __nv_bfloat16, wmma::row_major> "
      else
        out << "wmma::fragment<wmma::accumulator, 16, 16, 16, float> "
      out << sname
      out << ";\n"
      return nil
    if vrecv != nil && is_ast_node?(vrecv) && ast_kind(vrecv) == :var && vrecv.name == "gpu" && (vname == "shared_f32" || vname == "shared_i32" || vname == "shared_i64")
      shared_size = gpu_shared_size(ctx[:node], value, ctx[:dialect])
      gpu_record_shared_allocation(ctx, vname, shared_size)
      sname = target.name
      elt = "int"
      atype = "i32\[]".to_sym()
      if vname == "shared_f32"
        elt = "float"
        atype = "f32\[]".to_sym()
      elsif vname == "shared_i64"
        elt = "long"
        atype = "i64\[]".to_sym()
      ctx[:var_types][sname] = atype
      ctx[:array_bounds][sname] = shared_size
      ctx[:address_spaces][sname] = "threadgroup"
      emit_indent(out, ctx)
      if ctx[:dialect] == "cuda"
        out << "__shared__ "
      else
        out << "threadgroup "
      out << elt
      out << " "
      out << sname
      out << "\["
      out << shared_size.to_s()
      out << "];\n"
      return nil
  if ast_kind(target) == :var
    vname = target.name
    # A hint may carry flags after the type (`## u32 unroll`); consume them
    # before the type is used for anything.
    gpu_mark_unroll(ctx, vname, type_hint)
    type_hint = gpu_hint_type(type_hint)
    value_type = infer_expr_type(ctx, value)
    if ast_kind(value) == :array
      # `k = [..] ## u32[]` — a program-scope constant table, not a local.
      gpu_declare_const_table(ctx, vname, type_hint, value)
    elsif ast_kind(value) == :typed_array
      # Thread-private fixed-size local array: `buf = i32[64]` → `int buf[64];`
      elt = value.element_type
      esc = msl_scalar_type(elt)
      if esc == nil
        gpu_kernel_error(ctx[:node], "unsupported local array element type `" + elt.to_s() + "`")
      ctx[:var_types][vname] = ("" + elt.to_s() + "\[]").to_sym()
      ctx[:address_spaces][vname] = "thread"
      if ast_kind(ast_get(value, :size)) == :int
        ctx[:array_bounds][vname] = ast_get(value, :size).value
      gpu_declare_local(out, ctx, vname, esc + " " + vname + "\[" + emit_expr(ctx, ast_get(value, :size)) + "]", nil)
    elsif gpu_local_declared?(ctx, vname)
      # Already declared in this function. A local is function-scoped, so a
      # repeated `## T` hint names the same variable, not a new one — and
      # re-declaring it would either shadow the first (wrong) or collide.
      emit_indent(out, ctx)
      out << vname
      out << " = "
      out << emit_expr(ctx, value)
      out << ";\n"
    elsif type_hint != nil
      ctx[:var_types][vname] = type_hint
      scalar = msl_scalar_type(type_hint)
      if scalar == nil
        gpu_kernel_error(ctx[:node], "unsupported assign type `" + type_hint.to_s() + "`")
      gpu_declare_local(out, ctx, vname, scalar + " " + vname, value)
    elsif ctx[:var_types].has_key?(vname)
      emit_indent(out, ctx)
      out << vname
      out << " = "
      out << emit_expr(ctx, value)
      out << ";\n"
    else
      # First-seen var without hint — infer from RHS (limited).
      if value_type == nil
        gpu_kernel_error(ctx[:node], "variable `" + vname + "` needs a ## type hint")
      ctx[:var_types][vname] = value_type
      scalar = msl_scalar_type(value_type)
      if scalar == nil
        gpu_kernel_error(ctx[:node], "cannot infer MSL type for `" + vname + "`")
      gpu_declare_local(out, ctx, vname, scalar + " " + vname, value)
  elsif ast_kind(target) == :call && target.name in ("\[]" "\[]=")
    # Array subscript assignment — fall through via call handling.
    gpu_kernel_error(ctx[:node], "use `a[i] = v` shape, not `a.\[]=`")
  else
    gpu_kernel_error(ctx[:node], "unsupported assignment target")

-> emit_if(out, ctx, node)
  emit_indent(out, ctx)
  out << "if ("
  out << emit_expr(ctx, node.condition)
  out << ") {\n"
  ctx[:indent] = ctx[:indent] + 1
  body = node.then_body
  if body == nil
    body = []
  bi = 0
  while bi < body.size()
    emit_stmt(out, ctx, body[bi])
    bi += 1
  ctx[:indent] = ctx[:indent] - 1
  emit_indent(out, ctx)
  out << "}"
  # elsif → else if chain (MSL and CUDA both accept `else if`).
  # Parser stores each elsif as [condition, body_array] (see parser.w).
  elsif_clauses = node.elsif_clauses
  if elsif_clauses != nil
    ei = 0
    while ei < elsif_clauses.size()
      clause = elsif_clauses[ei]
      cond = nil
      cbody = nil
      if type(clause) == "Array"
        cond = clause[0]
        cbody = clause[1]
      else
        # Defensive: accept If-shaped nodes if the AST ever changes.
        cond = clause.condition
        cbody = clause.then_body
      out << " else if ("
      out << emit_expr(ctx, cond)
      out << ") {\n"
      ctx[:indent] = ctx[:indent] + 1
      if cbody == nil
        cbody = []
      ci = 0
      while ci < cbody.size()
        emit_stmt(out, ctx, cbody[ci])
        ci += 1
      ctx[:indent] = ctx[:indent] - 1
      emit_indent(out, ctx)
      out << "}"
      ei += 1
  eb = node.else_body
  if eb != nil && eb.size() > 0
    out << " else {\n"
    ctx[:indent] = ctx[:indent] + 1
    ei = 0
    while ei < eb.size()
      emit_stmt(out, ctx, eb[ei])
      ei += 1
    ctx[:indent] = ctx[:indent] - 1
    emit_indent(out, ctx)
    out << "}"
  out << "\n"

-> emit_while(out, ctx, node)
  # A loop over an induction variable tagged `## <type> unroll` is emitted
  # fully unrolled. See gpu_mark_unroll for why that matters on a GPU.
  if gpu_reads_unroll_var?(ctx, node.condition)
    emit_indent(out, ctx)
    if ctx[:dialect] == "cuda"
      out << "#pragma unroll\n"
    else
      out << "#pragma clang loop unroll(full)\n"
  emit_indent(out, ctx)
  out << "while ("
  out << emit_expr(ctx, node.condition)
  out << ") {\n"
  ctx[:indent] = ctx[:indent] + 1
  body = node.body
  bi = 0
  while bi < body.size()
    emit_stmt(out, ctx, body[bi])
    bi += 1
  ctx[:indent] = ctx[:indent] - 1
  emit_indent(out, ctx)
  out << "}\n"

-> emit_return(out, ctx, node)
  emit_indent(out, ctx)
  out << "return"
  if node.value != nil
    out << " "
    out << emit_expr(ctx, node.value)
  out << ";\n"

# ---- Expression emission ----

-> emit_expr(ctx, node)
  t = ast_kind(node)
  if t == :int
    node.value.to_s()
  elsif t == :float
    node.value.to_s() + "f"
  elsif t == :decimal
    # Decimal literals (e.g. `1.0`) are convenient in GPU source.
    # Emit as float literal — precision is preserved from the Tungsten
    # representation since MSL has no decimal type.
    node.value.to_s() + "f"
  elsif t == :bool
    if node.value
      "true"
    else
      "false"
  elsif t == :var
    emit_var(ctx, node)
  elsif t == :binary_op
    if node.op == :POW
      "pow(" + emit_expr(ctx, node.left) + ", " + emit_expr(ctx, node.right) + ")"
    else
      "(" + emit_expr(ctx, node.left) + " " + binop_symbol(node.op) + " " + emit_expr(ctx, node.right) + ")"
  elsif t == :unary_op
    uop_symbol(node.op) + "(" + emit_expr(ctx, node.operand) + ")"
  # Short-circuit logic. MSL and CUDA are both C++ dialects, so `&&`, `||`
  # and `!` are native and implicitly convert scalar operands to bool —
  # these pass straight through instead of forcing the caller to nest ifs.
  # (`!x` parses to a :not node, never :unary_op, so uop_symbol's :BANG arm
  # never sees it.) Every arm self-parenthesizes, so nesting is
  # precedence-safe. Note Tungsten's `a && b` evaluates to b's *value* while
  # C++'s yields a bool; inside the GPU scalar subset — conditions and bool
  # locals — the two agree, and the C semantics are what MSL wants.
  elsif t == :and
    "(" + emit_expr(ctx, node.left) + " && " + emit_expr(ctx, node.right) + ")"
  elsif t == :or
    "(" + emit_expr(ctx, node.left) + " || " + emit_expr(ctx, node.right) + ")"
  elsif t == :not
    "(!" + emit_expr(ctx, node.operand) + ")"
  elsif t == :call
    emit_call(ctx, node)
  elsif t == :if && gpu_is_ternary?(node)
    # `cond ? a : b` parses to an If node; in expression position emit a
    # C ternary. (Statement-position ifs go through emit_stmt/emit_if.)
    tb = node.then_body
    eb = node.else_body
    "(" + emit_expr(ctx, node.condition) + " ? " + emit_expr(ctx, tb[0]) + " : " + emit_expr(ctx, eb[0]) + ")"
  else
    gpu_kernel_error(ctx[:node], "unsupported expression node `" + t.to_s() + "`")
    ""

-> emit_var(ctx, node)
  gpu_local_name(ctx, node.name)

-> binop_symbol(sym)
  # Direct symbol comparison — Tungsten's sym.to_s() can disagree with
  # a literal string of the same characters, so keep the comparison at
  # the symbol level.
  if sym == :PLUS
    "+"
  elsif sym == :MINUS
    "-"
  elsif sym == :STAR
    "*"
  elsif sym == :SLASH
    "/"
  elsif sym == :PERCENT
    "%"
  elsif sym == :EQ
    "=="
  elsif sym == :NEQ
    "!="
  elsif sym == :LT
    "<"
  elsif sym == :GT
    ">"
  elsif sym == :LTE
    "<="
  elsif sym == :GTE
    ">="
  elsif sym == :AMPERSAND
    "&"
  elsif sym == :PIPE
    "|"
  elsif sym == :CARET
    "^"
  elsif sym == :LSHIFT
    "<<"
  elsif sym == :RSHIFT
    ">>"
  else
    sym.to_s()

-> uop_symbol(sym)
  if sym == :MINUS
    "-"
  elsif sym == :BANG
    "!"
  else
    sym.to_s()

# ---- Calls: `gpu.thread_position_in_grid.x`, array subscript, arith ----

-> emit_call(ctx, node)
  name = node.name
  recv = node.receiver
  args = node.args

  # A bare local/parameter reference. The parser turns an identifier used
  # as a call argument (`normalize(ro)`) into a zero-arg self-call rather
  # than a :var node, so a no-receiver no-arg call whose name is a known
  # local or param is really a variable read — emit the bare name.
  if recv == nil && (args == nil || args.size() == 0) && ctx[:var_types] != nil && ctx[:var_types].has_key?("" + name.to_s())
    return gpu_local_name(ctx, "" + name.to_s())

  if name == "\[]"
    if args == nil || args.size() != 1
      gpu_kernel_error(ctx[:node], "unsupported array-get arity")
    gpu_check_literal_bound(ctx, recv, args[0])
    # `"\["` avoids triggering Tungsten's own string-interp tokenizer
    # inside this source file; the emitted text is just `[`.
    return emit_expr(ctx, recv) + "\[" + emit_expr(ctx, args[0]) + "]"
  if name == "\[]=" && args != nil && args.size() == 2
    gpu_check_literal_bound(ctx, recv, args[0])
    return emit_expr(ctx, recv) + "\[" + emit_expr(ctx, args[0]) + "] = " + emit_expr(ctx, args[1])

  # gpu.* namespaced primitives.
  #
  # Nested-call form:
  #   gpu.thread_position_in_grid.x → int(__tid)
  #   gpu.thread_position_in_threadgroup.x → int(__tid_in_tg)
  #   gpu.threadgroup_position_in_grid.x → int(__tg_id)
  if recv != nil && ast_kind(recv) == :call && recv.name != nil
    inner = recv
    if inner.receiver != nil && ast_kind(inner.receiver) == :var && inner.receiver.name == "gpu"
      mname = inner.name
      base = nil
      if mname == "thread_position_in_grid"
        base = "__tid"
      elsif mname == "thread_position_in_threadgroup"
        base = "__tid_in_tg"
      elsif mname == "threadgroup_position_in_grid"
        base = "__tg_id"
      if base != nil
        # Built-ins are uint3 so .x / .y / .z access dispatch dimensions.
        # 1D dispatches see y = z = 0; 2D dispatches set y; 3D sets z.
        if name == "x"
          return "int(" + base + ".x)"
        elsif name == "y"
          return "int(" + base + ".y)"
        elsif name == "z"
          return "int(" + base + ".z)"
        gpu_kernel_error(ctx[:node], "unknown " + mname + " component `" + name + "`")
  # Bare `gpu.x` scalar primitives:
  #   gpu.thread_index_in_simdgroup → int(__simd_lane)
  #   gpu.simdgroup_index_in_threadgroup → int(__simd_id)
  if recv != nil && ast_kind(recv) == :var && recv.name == "gpu"
    # Vectorized 128-bit memory ops. Index is in FLOAT4 units.
    #   gpu.load_f4(buf, i)      → ((device const float4*)buf)[i]   (MSL)
    #                            → ((const float4*)buf)[i]          (CUDA)
    #   gpu.store_f4(buf, i, v)  → ((device float4*)buf)[i] = v
    #   gpu.f4(a, b, c, d)       → float4(a,b,c,d) / make_float4(a,b,c,d)
    # Tensor-core ops (CUDA dialect). Offsets are in ELEMENTS; ld is the
    # leading dimension (row stride) of the source/destination matrix.
    if name in ("wmma_fill" "wmma_load" "wmma_mma" "wmma_store")
      if ctx[:dialect] != "cuda"
        gpu_kernel_error(ctx[:node], "gpu." + name + " is CUDA-only (use simdgroup_* for Metal)")
      if name == "wmma_fill" && args.size() == 2
        return "wmma::fill_fragment(" + emit_expr(ctx, args[0]) + ", " + emit_expr(ctx, args[1]) + ")"
      if name == "wmma_load" && args.size() == 4
        return "wmma::load_matrix_sync(" + emit_expr(ctx, args[0]) + ", " + emit_expr(ctx, args[1]) + " + " + emit_expr(ctx, args[2]) + ", " + emit_expr(ctx, args[3]) + ")"
      if name == "wmma_mma" && args.size() == 4
        return "wmma::mma_sync(" + emit_expr(ctx, args[0]) + ", " + emit_expr(ctx, args[1]) + ", " + emit_expr(ctx, args[2]) + ", " + emit_expr(ctx, args[3]) + ")"
      if name == "wmma_store" && args.size() == 4
        return "wmma::store_matrix_sync(" + emit_expr(ctx, args[0]) + " + " + emit_expr(ctx, args[1]) + ", " + emit_expr(ctx, args[3]) + ", " + emit_expr(ctx, args[2]) + ", wmma::mem_row_major)"
      gpu_kernel_error(ctx[:node], "bad arity for gpu." + name)
    if name == "load_f4" && args != nil && args.size() == 2
      cast = ctx[:dialect] == "cuda" ? "const float4*" : "device const float4*"
      return "((" + cast + ")" + emit_expr(ctx, args[0]) + ")\[" + emit_expr(ctx, args[1]) + "]"
    if name == "store_f4" && args != nil && args.size() == 3
      cast = ctx[:dialect] == "cuda" ? "float4*" : "device float4*"
      return "((" + cast + ")" + emit_expr(ctx, args[0]) + ")\[" + emit_expr(ctx, args[1]) + "] = " + emit_expr(ctx, args[2])
    if name == "f4" && args != nil && args.size() == 4
      ctor = ctx[:dialect] == "cuda" ? "make_float4" : "float4"
      return ctor + "(" + emit_expr(ctx, args[0]) + ", " + emit_expr(ctx, args[1]) + ", " + emit_expr(ctx, args[2]) + ", " + emit_expr(ctx, args[3]) + ")"
    # Device-scope relaxed i32 atomics. Arrays retain their ordinary pointer
    # ABI; only the individual access is cast to an atomic pointer.
    if name in ("atomic_load_i32" "atomic_store_i32" "atomic_exchange_i32" "atomic_fetch_add_i32" "atomic_min_i32")
      expected = 2
      if name == "atomic_store_i32" || name == "atomic_exchange_i32" || name == "atomic_fetch_add_i32" || name == "atomic_min_i32"
        expected = 3
      if args == nil || args.size() != expected
        gpu_kernel_error(ctx[:node], "gpu." + name + " takes " + expected.to_s() + " args")
      buffer = emit_expr(ctx, args[0])
      index = emit_expr(ctx, args[1])
      if ctx[:dialect] == "cuda"
        pointer = "((int*)" + buffer + " + " + index + ")"
        if name == "atomic_load_i32"
          return "atomicAdd(" + pointer + ", 0)"
        value = emit_expr(ctx, args[2])
        if name == "atomic_store_i32" || name == "atomic_exchange_i32"
          return "atomicExch(" + pointer + ", " + value + ")"
        if name == "atomic_fetch_add_i32"
          return "atomicAdd(" + pointer + ", " + value + ")"
        return "atomicMin(" + pointer + ", " + value + ")"
      pointer = "((device atomic_int*)" + buffer + " + " + index + ")"
      if name == "atomic_load_i32"
        return "atomic_load_explicit(" + pointer + ", memory_order_relaxed)"
      value = emit_expr(ctx, args[2])
      if name == "atomic_store_i32"
        return "atomic_store_explicit(" + pointer + ", " + value + ", memory_order_relaxed)"
      if name == "atomic_exchange_i32"
        return "atomic_exchange_explicit(" + pointer + ", " + value + ", memory_order_relaxed)"
      if name == "atomic_fetch_add_i32"
        return "atomic_fetch_add_explicit(" + pointer + ", " + value + ", memory_order_relaxed)"
      return "atomic_fetch_min_explicit(" + pointer + ", " + value + ", memory_order_relaxed)"
    if name == "thread_index_in_simdgroup"
      return "int(__simd_lane)"
    if name == "simdgroup_index_in_threadgroup"
      return "int(__simd_id)"
    if name == "threads_per_threadgroup"
      return "int(__tg_total)"
    gpu_kernel_error(ctx[:node], "unsupported gpu primitive `" + name + "`")

  # Vector swizzle: `vec.x`, `vec.xyz`, `vec.rgb`, `vec.wzyx`, … on any
  # vector-typed expression. MSL accepts these as direct member access on
  # float2/3/4 / half4 / etc., so we pass the swizzle through verbatim.
  # Fires only with empty args (no parens). Covers the position set
  # (xyzw) and the color set (rgba), length 1–4 — which subsumes the old
  # single-component x/y/z/w case.
  if recv != nil && (args == nil || args.size() == 0) && gpu_is_swizzle?(name)
    return emit_expr(ctx, recv) + "." + name.to_s()

  # Tungsten-to-MSL intrinsic remaps for a handful of common ones.
  if recv == nil
    # User device helper functions — a `@gpu fn` declared with a `ret`
    # hint. Emitted as a device function earlier; here a call to one just
    # passes through as `name(args…)`.
    if ctx[:gpu_fns] != nil && ctx[:gpu_fns].has_key?("" + name.to_s())
      gpu_validate_device_call(ctx, "" + name.to_s(), args)
      return name.to_s() + "(" + gpu_arglist(ctx, args) + ")"
    # Vector constructors: vec2/vec3/vec4 → float2/float3/float4.
    if name in ("vec2" "vec3" "vec4")
      ctor = "float2"
      if name == "vec3"
        ctor = "float3"
      elsif name == "vec4"
        ctor = "float4"
      return ctor + "(" + gpu_arglist(ctx, args) + ")"
    # Numeric / vector casts — valid MSL conversion syntax.
    if name in ("int" "uint" "float" "half" "int2" "int3" "float2" "float3" "float4")
      return name.to_s() + "(" + gpu_arglist(ctx, args) + ")"
    # Extended MSL math intrinsics (geometry + common scalar/vector math).
    if gpu_extra_intrinsic?(name)
      return name.to_s() + "(" + gpu_arglist(ctx, args) + ")"
    # SIMD-group reductions: `simd_sum(x)`, `simd_max(x)`, `simd_min(x)`,
    # `simd_prefix_inclusive_sum(x)`. Operate within a 32-lane SIMD group.
    if name in ("simd_sum" "simd_max" "simd_min" "simd_prefix_inclusive_sum" "simd_broadcast_first")
      if ctx[:dialect] == "cuda"
        gpu_kernel_error(ctx[:node], "`" + name + "` is Metal-only; CUDA warp lowering is not implemented")
      if args.size() != 1
        gpu_kernel_error(ctx[:node], "`" + name + "` takes 1 arg")
      return name + "(" + emit_expr(ctx, args[0]) + ")"
    # Threadgroup-wide reductions: `tg_sum(x)`, `tg_max(x)`, `tg_min(x)`.
    # Operate across the entire threadgroup (up to 1024 threads / 32
    # simdgroups). Routed by inferred arg type to the right helper +
    # scratch buffer (f32 or i32).
    if name in ("tg_sum" "tg_max" "tg_min")
      if ctx[:dialect] == "cuda"
        gpu_kernel_error(ctx[:node], "`" + name + "` is not supported by the CUDA dialect")
      if args.size() != 1
        gpu_kernel_error(ctx[:node], "`" + name + "` takes 1 arg")
      arg_type = infer_expr_type(ctx, args[0])
      # Normalize String → Symbol; type-hint values from the parser arrive
      # as Strings while inferred types are Symbols.
      arg_sym = arg_type
      if type(arg_type) == "String"
        arg_sym = arg_type.to_sym()
      type_suffix = "f32"
      scratch = "__tg_scratch_f"
      if arg_sym == :i32
        type_suffix = "i32"
        scratch = "__tg_scratch_i"
      helper = "__" + name + "_" + type_suffix
      return helper + "(" + emit_expr(ctx, args[0]) + ", " + scratch + ", __simd_lane, __simd_id, __tg_total / 32)"
    # Threadgroup barrier: `threadgroup_barrier()` → all-mem fence.
    if name == "threadgroup_barrier"
      if ctx[:dialect] == "cuda"
        return "__syncthreads()"
      return "threadgroup_barrier(mem_flags::mem_threadgroup)"
    # SIMD-group cooperative matrix intrinsics.
    #
    # Tungsten doesn't expose pointer arithmetic, so simdgroup_load /
    # simdgroup_store take 4 Tungsten args (matrix, array, offset, stride)
    # which fold to MSL's 3-arg form `simdgroup_load(matrix, array + offset, stride)`.
    #
    # The user can also pass 3 args if they prefer raw MSL-style: it
    # passes through unchanged.
    if name in ("simdgroup_load" "simdgroup_store")
      if ctx[:dialect] == "cuda"
        gpu_kernel_error(ctx[:node], "`" + name + "` is Metal-only; use gpu.wmma_* for CUDA matrices")
      if args.size() == 4
        m  = emit_expr(ctx, args[0])
        p  = emit_expr(ctx, args[1])
        off = emit_expr(ctx, args[2])
        st = emit_expr(ctx, args[3])
        return name + "(" + m + ", " + p + " + " + off + ", " + st + ")"
      argtext = ""
      ai = 0
      while ai < args.size()
        if ai > 0
          argtext = argtext + ", "
        argtext = argtext + emit_expr(ctx, args[ai])
        ai += 1
      return name + "(" + argtext + ")"
    # mma: pass through; constructor: pass through.
    #   simdgroup_multiply_accumulate(dest, a, b, c)  (dest = a·b + c)
    #   simdgroup_float8x8(0.0)
    if name in ("simdgroup_multiply_accumulate" "simdgroup_float8x8" "simdgroup_bfloat8x8" "simdgroup_half8x8")
      if ctx[:dialect] == "cuda"
        gpu_kernel_error(ctx[:node], "`" + name + "` is Metal-only; use gpu.wmma_* for CUDA matrices")
      argtext = ""
      ai = 0
      while ai < args.size()
        if ai > 0
          argtext = argtext + ", "
        argtext = argtext + emit_expr(ctx, args[ai])
        ai += 1
      return name + "(" + argtext + ")"
    if name in ("sqrt" "abs" "floor" "ceil" "exp" "log" "sin" "cos")
      argtext = ""
      ai = 0
      while ai < args.size()
        if ai > 0
          argtext = argtext + ", "
        argtext = argtext + emit_expr(ctx, args[ai])
        ai += 1
      return name + "(" + argtext + ")"

  # Vector component access: v.x / v.y / v.z / v.w on a float4-typed local
  # (same syntax in MSL and CUDA).
  if recv != nil && ast_kind(recv) == :var && (args == nil || args.size() == 0)
    rname = recv.name
    rt = ctx[:var_types][rname]
    if rt != nil && msl_scalar_type(rt) == "float4" && ("" + name.to_s()) in ("x" "y" "z" "w")
      return rname + "." + name.to_s()

  gpu_kernel_error(ctx[:node], "unsupported call to `" + name.to_s() + "`")
  ""

# True when `name` is a vector swizzle: 1–4 letters drawn from the
# position set (x y z w) or the color set (r g b a). MSL accepts the same
# swizzle on float2/3/4, so the emitter just forwards `recv.swizzle`.
-> gpu_is_swizzle?(name)
  s = "" + name.to_s()
  n = s.size()
  if n < 1 || n > 4
    return false
  bytes = s.bytes()
  i = 0
  while i < n
    c = bytes[i]
    # x=120 y=121 z=122 w=119  r=114 g=103 b=98 a=97
    if !(c == 120 || c == 121 || c == 122 || c == 119 || c == 114 || c == 103 || c == 98 || c == 97)
      return false
    i += 1
  true

# Comma-join the emitted forms of a call's args.
-> gpu_arglist(ctx, args)
  if args == nil
    return ""
  s = ""
  ai = 0
  while ai < args.size()
    if ai > 0
      s = s + ", "
    s = s + emit_expr(ctx, args[ai])
    ai += 1
  s

# MSL math intrinsics passed through by name (beyond the core
# sqrt/abs/floor/ceil/exp/log/sin/cos already handled inline above).
-> gpu_extra_intrinsic?(name)
  name in ("min" "max" "clamp" "mix" "step" "smoothstep" "fract" "sign" "rsqrt" "pow" "exp2" "log2" "tan" "asin" "acos" "atan" "atan2" "sinh" "cosh" "tanh" "dot" "cross" "normalize" "length" "distance" "reflect" "refract" "fmod" "saturate" "round" "trunc" "powr")

# Intrinsics whose result type matches their (first vector) argument —
# used by type inference so shader locals rarely need explicit hints.
-> gpu_vec_preserving?(name)
  name in ("normalize" "cross" "reflect" "refract" "min" "max" "clamp" "mix" "abs" "floor" "ceil" "fract" "sign" "step" "smoothstep" "saturate" "pow" "sqrt" "sin" "cos" "exp" "log" "rsqrt" "tan" "tanh" "fmod" "round" "trunc")

-> gpu_is_vec_type?(t)
  t in (:vec2 :vec3 :vec4 :float2 :float3 :float4 :half4 :f32x4 :f32x2 :i32x4 :u32x4)

-> gpu_infer_first_arg_type(ctx, args)
  if args == nil || args.size() == 0
    return nil
  best = nil
  ai = 0
  while ai < args.size()
    at = infer_expr_type(ctx, args[ai])
    if gpu_is_vec_type?(at)
      return at
    if best == nil
      best = at
    ai += 1
  best

# ---- Type inference (very narrow) ----

-> infer_expr_type(ctx, node)
  t = ast_kind(node)
  if t == :int
    :i32
  elsif t in (:float :decimal)
    :f32
  elsif t == :var
    ctx[:var_types][node.name]
  elsif t == :call && node.name == "\[]"
    # x[i] → element type of x
    recv_type = infer_expr_type(ctx, node.receiver)
    if recv_type == nil
      return nil
    s = recv_type.to_s()
    if s.ends_with?("\[]")
      s.slice(0, s.size() - 2).to_sym()
    else
      nil
  elsif t == :call && node.receiver != nil && ast_kind(node.receiver) == :call && node.receiver.receiver != nil && ast_kind(node.receiver.receiver) == :var && node.receiver.receiver.name == "gpu"
    # gpu.{thread_position_in_grid,thread_position_in_threadgroup,
    #      threadgroup_position_in_grid}.x → i32 (the int(__id) cast).
    # Guarded to ONLY a `gpu.*` inner call — a swizzle on any other call
    # result (e.g. `map_scene(p).x`) falls through to the swizzle arm.
    mname = node.receiver.name
    if mname in ("thread_position_in_grid" "thread_position_in_threadgroup" "threadgroup_position_in_grid")
      :i32
    else
      nil
  elsif t == :call && node.receiver != nil && ast_kind(node.receiver) == :var && node.receiver.name == "gpu"
    # gpu.thread_index_in_simdgroup / gpu.simdgroup_index_in_threadgroup
    # / gpu.threads_per_threadgroup → i32
    if node.name in ("thread_index_in_simdgroup" "simdgroup_index_in_threadgroup" "threads_per_threadgroup")
      :i32
    else
      nil
  elsif t == :call && node.receiver == nil && node.name in ("simd_sum" "simd_max" "simd_min" "simd_prefix_inclusive_sum" "simd_broadcast_first" "tg_sum" "tg_max" "tg_min")
    # simd_*(x) and tg_*(x) return the same scalar type as x.
    if node.args != nil && node.args.size() >= 1
      infer_expr_type(ctx, node.args[0])
    else
      nil
  elsif t == :call && node.receiver == nil && node.name == "simdgroup_float8x8"
    # simdgroup_float8x8(...) constructor → :sg_f32
    :sg_f32
  elsif t == :call && node.receiver == nil && node.name == "simdgroup_bfloat8x8"
    :sg_bf16
  elsif t == :call && node.receiver == nil && node.name == "simdgroup_half8x8"
    :sg_f16
  elsif t == :call && node.receiver == nil && node.name == "simdgroup_multiply_accumulate"
    # mma returns the same type as its first arg (accumulator).
    if node.args != nil && node.args.size() >= 1
      infer_expr_type(ctx, node.args[0])
    else
      nil
  # Bare local/param reference (parsed as a zero-arg self-call).
  elsif t == :call && node.receiver == nil && (node.args == nil || node.args.size() == 0) && ctx[:var_types] != nil && ctx[:var_types].has_key?("" + node.name.to_s())
    ctx[:var_types]["" + node.name.to_s()]
  # Vector constructors → their vec type.
  elsif t == :call && node.receiver == nil && node.name == "vec2"
    :vec2
  elsif t == :call && node.receiver == nil && node.name == "vec3"
    :vec3
  elsif t == :call && node.receiver == nil && node.name == "vec4"
    :vec4
  # Numeric casts.
  elsif t == :call && node.receiver == nil && node.name == "int"
    :i32
  elsif t == :call && node.receiver == nil && node.name == "uint"
    :u32
  elsif t == :call && node.receiver == nil && node.name in ("float" "half")
    :f32
  # Reductions to a scalar.
  elsif t == :call && node.receiver == nil && node.name in ("dot" "length" "distance")
    :f32
  # Calls to user device helper functions return their declared type.
  elsif t == :call && node.receiver == nil && ctx[:gpu_fns] != nil && ctx[:gpu_fns].has_key?("" + node.name.to_s())
    ctx[:gpu_fns]["" + node.name.to_s()][:ret]
  # Vector-preserving intrinsics return the type of their first vector arg.
  elsif t == :call && node.receiver == nil && gpu_vec_preserving?(node.name)
    gpu_infer_first_arg_type(ctx, node.args)
  # Swizzle access: length determines the result vec width (1 → scalar).
  elsif t == :call && node.receiver != nil && (node.args == nil || node.args.size() == 0) && gpu_is_swizzle?(node.name)
    sz = ("" + node.name.to_s()).size()
    if sz == 1
      :f32
    elsif sz == 2
      :vec2
    elsif sz == 3
      :vec3
    else
      :vec4
  elsif t == :if && gpu_is_ternary?(node)
    # `cond ? a : b` — take the then-branch's type (both branches should
    # agree); fall back to the else-branch.
    tb = node.then_body
    bt = infer_expr_type(ctx, tb[0])
    if bt != nil
      bt
    else
      infer_expr_type(ctx, node.else_body[0])
  elsif t in (:and :or :not)
    # Logical operators are bool-valued in C++, so `flag = a && b` declares
    # as `bool flag` without needing a `## bool` hint from the author.
    :bool
  elsif t == :binary_op
    lt = infer_expr_type(ctx, node.left)
    rt = infer_expr_type(ctx, node.right)
    # Vector arithmetic keeps the vector type even when the other side is
    # a scalar (e.g. `dir * t`), so prefer whichever operand is a vector.
    if gpu_is_vec_type?(lt)
      lt
    elsif gpu_is_vec_type?(rt)
      rt
    elsif lt != nil
      lt
    else
      rt
  else
    nil

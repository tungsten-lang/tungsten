# Metal Shading Language emitter for `@gpu fn` kernels.
#
# v0 scope — Phase 0 kernel provenance smoke: walk a `:gpu_kernel_def`
# AST node and produce a minimal .metal source string sufficient for
#
#   @gpu fn add_one(x ## f32[], y ## f32[], n ## i32)
#     i ## i32 = gpu.thread_position_in_grid.x
#     if i < n
#       y[i] = x[i] + 1.0
#
# Anything outside the supported subset raises a compile-time error with
# the usual `-->` formatter. The emitter is NOT the eventual 5-dialect
# pipeline — that lands in later phases per doc/gpu-dialects.md. This
# pass is the provenance smoke: source → MSL text that `xcrun metal`
# compiles, wired up enough to dispatch one trivial kernel.

use ast

# ---- Public entry points ----

# Emit full .metal source for a list of `@gpu fn` AST nodes.
# Returns the text, or nil when `kernels` is empty.
-> emit_gpu_kernels_metal(kernels)
  if kernels == nil || kernels.size() == 0
    return nil
  out = StringBuffer(1024)
  out << "// Tungsten @gpu kernel output — do not edit by hand\n"
  out << "#include <metal_stdlib>\n"
  # simdgroup_matrix types live in this header. Always include — it's
  # tiny in terms of compile time and lets `@gpu fn`s reach for the
  # matmul accelerator HW without per-kernel feature detection.
  out << "#include <metal_simdgroup_matrix>\n"
  out << "using namespace metal;\n\n"
  out << gpu_tg_reduce_helpers()
  # A `@gpu fn` declared with a `## TYPE: ret` hint is a DEVICE HELPER
  # FUNCTION (e.g. `float map(float3 p)`), not a `kernel void` entry
  # point. They compile to plain device functions so kernels — and other
  # helpers — can call them. This is what lets a raymarcher factor out
  # its scene `map()`, `calcNormal()`, `softShadow()` etc. instead of
  # inlining them everywhere. Build a name→return-type registry first so
  # calls and type inference resolve, then emit helpers before kernels.
  gpu_fns = {}
  i = 0
  while i < kernels.size()
    rt = gpu_fn_return_type(kernels[i])
    if rt != nil
      gpu_fns["" + kernels[i].name.to_s()] = rt
    i += 1
  i = 0
  while i < kernels.size()
    if gpu_fn_return_type(kernels[i]) != nil
      out << emit_device_fn(kernels[i], gpu_fns)
      out << "\n"
    i += 1
  i = 0
  while i < kernels.size()
    if gpu_fn_return_type(kernels[i]) == nil
      if kernel_uses_wmma?(kernels[i])
        out << "// kernel `"
        out << kernels[i].name
        out << "` skipped: CUDA-only (wmma tensor-core ops)\n"
      else
        out << emit_kernel(kernels[i], gpu_fns)
      out << "\n"
    i += 1
  out.to_s()

# The declared return type of a `@gpu fn`, or nil if it's a void kernel.
# A device helper function declares its return type with a `ret` pseudo-
# parameter type hint: `## vec3: ret` over `@gpu fn map(p)`.
-> gpu_fn_return_type(node)
  hints = node.type_hints
  if hints == nil
    return nil
  if hints.has_key?("ret")
    return hints["ret"]
  nil

# True when a kernel body references any gpu.wmma_* op — those have no MSL
# mapping (Metal's equivalent is the simdgroup_* surface), so the .metal
# sidecar skips them instead of erroring the whole compile.
-> kernel_uses_wmma?(node)
  wmma_scan(node.body)

-> wmma_scan(x)
  if x == nil
    return false
  if type(x) == "Array"
    i = 0
    while i < x.size()
      if wmma_scan(x[i])
        return true
      i += 1
    return false
  if !is_ast_node?(x)
    return false
  k = ast_kind(x)
  if k == :call
    nm = "" + x.name.to_s()
    if nm.starts_with?("wmma_")
      return true
    if wmma_scan(x.receiver)
      return true
    if wmma_scan(x.args)
      return true
    return false
  if k == :assign
    if wmma_scan(x.value)
      return true
    return false
  if k == :if
    if wmma_scan(x.condition) || wmma_scan(x.then_body) || wmma_scan(x.else_body)
      return true
    return false
  if k == :while
    if wmma_scan(x.condition) || wmma_scan(x.body)
      return true
    return false
  false

# Threadgroup-wide reduction helpers — emitted into every kernel file
# (always; unused inline functions cost nothing). Lifts the 32-lane
# simdgroup-scope reductions to TG-wide reductions over up to 1024
# threads (= 32 simdgroups). Each kernel gets per-type scratch arrays
# at body start; helpers take a pointer to the right scratch + the
# simd lane and simd index, do simdgroup reduce → cross-simdgroup
# reduce → broadcast back via threadgroup memory.
-> gpu_tg_reduce_helpers
  # 2-barrier reductions over up to 1024 threads (32 simdgroups). Each
  # helper takes the per-type scratch[32], simd lane/index, and n_simds
  # (= TG size / 32). No init pass needed — the final-reduce gates lanes
  # >= n_simds with the identity value, so unused scratch slots are
  # ignored without prior zeroing.
  s = StringBuffer(1024)
  s << "// Threadgroup-wide reductions across up to 1024 threads (32 simdgroups).\n"
  s << "inline float __tg_sum_f32(float v, threadgroup float *s, uint sl, uint si, uint n_simds) {\n"
  s << "  float sm = simd_sum(v);\n"
  s << "  if (sl == 0) { s\[si] = sm; }\n"
  s << "  threadgroup_barrier(mem_flags::mem_threadgroup);\n"
  s << "  float partial = (sl < n_simds) ? s\[sl] : 0.0f;\n"
  s << "  float total = (si == 0) ? simd_sum(partial) : 0.0f;\n"
  s << "  if (si == 0 && sl == 0) { s\[0] = total; }\n"
  s << "  threadgroup_barrier(mem_flags::mem_threadgroup);\n"
  s << "  return s\[0];\n"
  s << "}\n"
  s << "inline float __tg_max_f32(float v, threadgroup float *s, uint sl, uint si, uint n_simds) {\n"
  s << "  float sm = simd_max(v);\n"
  s << "  if (sl == 0) { s\[si] = sm; }\n"
  s << "  threadgroup_barrier(mem_flags::mem_threadgroup);\n"
  s << "  float partial = (sl < n_simds) ? s\[sl] : -INFINITY;\n"
  s << "  float total = (si == 0) ? simd_max(partial) : -INFINITY;\n"
  s << "  if (si == 0 && sl == 0) { s\[0] = total; }\n"
  s << "  threadgroup_barrier(mem_flags::mem_threadgroup);\n"
  s << "  return s\[0];\n"
  s << "}\n"
  s << "inline int __tg_min_i32(int v, threadgroup int *s, uint sl, uint si, uint n_simds) {\n"
  s << "  int sm = simd_min(v);\n"
  s << "  if (sl == 0) { s\[si] = sm; }\n"
  s << "  threadgroup_barrier(mem_flags::mem_threadgroup);\n"
  s << "  int partial = (sl < n_simds) ? s\[sl] : INT_MAX;\n"
  s << "  int total = (si == 0) ? simd_min(partial) : INT_MAX;\n"
  s << "  if (si == 0 && sl == 0) { s\[0] = total; }\n"
  s << "  threadgroup_barrier(mem_flags::mem_threadgroup);\n"
  s << "  return s\[0];\n"
  s << "}\n\n"
  s.to_s()

# Walk an AST program tree and collect every `:gpu_kernel_def` node,
# top-level and nested. Currently `@gpu fn` only parses at top level
# but this stays robust if that changes.
#
# When `@schedule kernel.variant` blocks accompany a kernel, this also
# expands the kernel into multiple variants (one per schedule), each
# with the schedule applied. The default-no-schedule kernel is always
# emitted as well.
-> collect_gpu_kernels(ast)
  kernels = []
  if ast == nil
    return kernels
  if ast_kind(ast) == :program
    exprs = program_body(ast)
    i = 0
    while i < exprs.size()
      collect_gpu_kernels_into(exprs[i], kernels)
      i += 1
  else
    collect_gpu_kernels_into(ast, kernels)

  # Expand each kernel into variants based on @schedule and @layout
  # blocks. The un-scheduled, un-relaid kernel is always kept as the
  # default; each schedule and layout produces an additional emitted
  # kernel suffixed `_<variant>`.
  schedules = collect_gpu_schedules(ast)
  layouts   = collect_gpu_layouts(ast)
  if schedules.size() == 0 && layouts.size() == 0
    return kernels
  variants = []
  ki = 0
  while ki < kernels.size()
    variants.push(kernels[ki])
    ki += 1
  si = 0
  while si < schedules.size()
    sched = schedules[si]
    target_kernel = nil
    ki = 0
    while ki < kernels.size()
      if kernels[ki].name == sched.kernel
        target_kernel = kernels[ki]
      ki += 1
    if target_kernel != nil
      transformed = apply_schedule_to_kernel(target_kernel, sched, layouts)
      variants.push(transformed)
    si += 1
  li = 0
  while li < layouts.size()
    layout = layouts[li]
    target_kernel = nil
    ki = 0
    while ki < kernels.size()
      if kernels[ki].name == layout.kernel
        target_kernel = kernels[ki]
      ki += 1
    if target_kernel != nil
      transformed = apply_layout_to_kernel(target_kernel, layout)
      variants.push(transformed)
    li += 1
  variants

-> collect_gpu_kernels_into(node, out)
  if node == nil
    return nil
  if !is_ast_node?(node)
    return nil
  if ast_kind(node) == :gpu_kernel_def
    out.push(node)
    return nil
  if ast_kind(node) in (:fastmath_block :strictmath_block :overflow_block)
    body = node[:body]
    if body != nil && type(body) == "Array"
      i = 0
      while i < body.size()
        collect_gpu_kernels_into(body[i], out)
        i += 1
    return nil
  # Recurse into known child shapes — only enough to catch nested
  # cases if we ever allow them. For now @gpu fn is top-level only.
  body = node.body
  if body != nil && type(body) == "Array"
    i = 0
    while i < body.size()
      collect_gpu_kernels_into(body[i], out)
      i += 1
  exprs = node.expressions
  if exprs != nil && type(exprs) == "Array"
    i = 0
    while i < exprs.size()
      collect_gpu_kernels_into(exprs[i], out)
      i += 1

# Collect every `:schedule_def` node, top-level and nested.
-> collect_gpu_schedules(ast)
  schedules = []
  if ast == nil
    return schedules
  if ast_kind(ast) == :program
    exprs = program_body(ast)
    i = 0
    while i < exprs.size()
      if exprs[i] != nil && is_ast_node?(exprs[i]) && ast_kind(exprs[i]) == :schedule_def
        schedules.push(exprs[i])
      i += 1
  schedules

# Collect every `:layout_def` node.
-> collect_gpu_layouts(ast)
  layouts = []
  if ast == nil
    return layouts
  if ast_kind(ast) == :program
    exprs = program_body(ast)
    i = 0
    while i < exprs.size()
      if exprs[i] != nil && is_ast_node?(exprs[i]) && ast_kind(exprs[i]) == :layout_def
        layouts.push(exprs[i])
      i += 1
  layouts

# ---- Schedule application: kernel AST + schedule AST → transformed kernel AST ----
#
# Slice 3 of P3.4: implements just `axis :name, parallelize: :threadgroup`.
# Walks the kernel body looking for assigns tagged `## axis :<name>`;
# rewrites the binding from `gpu.thread_position_in_grid.x` to
# `gpu.threadgroup_position_in_grid.x`. Future slices add the b-axis
# rewrites (stride init/increment) and the simd_sum reduction.
-> apply_schedule_to_kernel(kernel, schedule, all_layouts)
  # Deep-clone the kernel so mutations don't leak back to the unscheduled variant.
  out = ast_clone(kernel)
  out.name = kernel.name + "_" + schedule.variant
  directives = schedule.directives
  i = 0
  while i < directives.size()
    apply_directive(out, directives[i], all_layouts)
    i += 1
  out

-> apply_directive(kernel, directive, all_layouts)
  if directive == nil || !is_ast_node?(directive) || ast_kind(directive) != :call
    return nil
  # `use_layout :variant_name` — reference a previously-defined
  # @layout block by its variant name. Applies that layout's directives
  # to the current kernel before any axis directives that follow.
  # Composability: lets a @schedule produce a variant that combines a
  # buffer reshape with parallelization in a single emitted kernel.
  if directive.name == "use_layout"
    apply_use_layout(kernel, directive, all_layouts)
    return nil
  if directive.name != "axis"
    return nil
  args = directive.args
  if args == nil || args.size() < 2
    return nil
  axis_arg = args[0]
  kwargs = args[1]
  if axis_arg == nil || ast_kind(axis_arg) != :symbol
    return nil
  axis_name = axis_arg.value
  parallelize_to = lookup_kwarg(kwargs, "parallelize")
  if parallelize_to == "threadgroup"
    rewrite_axis_to_threadgroup(kernel.body, axis_name)
  if parallelize_to == "simdgroup_lane"
    stride = lookup_kwarg_int(kwargs, "stride")
    if stride == nil
      stride = 32
    rewrite_axis_to_simdgroup_lane(kernel.body, axis_name, stride)
  reduce_with = lookup_kwarg(kwargs, "reduce")
  if reduce_with != nil
    target_var = lookup_kwarg(kwargs, "into")
    if target_var != nil
      rebuilt_body = apply_simd_reduce(kernel.body, axis_name, reduce_with, target_var)
      if rebuilt_body != nil
        kernel.body = rebuilt_body
  vec_factor = lookup_kwarg_int(kwargs, "vectorize")
  if vec_factor != nil && vec_factor > 1
    rewrite_axis_to_vectorize(kernel.body, axis_name, vec_factor)
  nil

# Look up the named @layout for this kernel and apply its directives.
# `directive` is a `use_layout :variant_name` call node.
-> apply_use_layout(kernel, directive, all_layouts)
  args = directive.args
  if args == nil || args.size() < 1
    return nil
  variant_arg = args[0]
  if variant_arg == nil || ast_kind(variant_arg) != :symbol
    return nil
  variant_name = variant_arg.value
  kernel_name = kernel.name
  # Strip any `_<variant>` suffix that schedule expansion already added,
  # so we can match against the original kernel name in @layout's
  # `kernel:` field.
  base_name = kernel_name
  underscore_pos = base_name.index("_")
  while underscore_pos != nil
    candidate = base_name.slice(0, underscore_pos)
    base_name = candidate
    underscore_pos = nil
  # Walk all layouts looking for one with matching kernel + variant.
  if all_layouts == nil
    return nil
  i = 0
  while i < all_layouts.size()
    lay = all_layouts[i]
    if lay.variant == variant_name
      # Apply the layout's directives to the current kernel.
      ldirs = lay.directives
      j = 0
      while j < ldirs.size()
        apply_layout_directive(kernel, ldirs[j])
        j += 1
      return nil
    i += 1
  nil

# Look up a keyword arg in a from_kwargs hash_literal node. Returns
# the value's symbol name (string) or nil.
-> lookup_kwarg(kwargs_node, key_name)
  if kwargs_node == nil || ast_kind(kwargs_node) != :hash_literal
    return nil
  entries = kwargs_node.entries
  if entries == nil
    return nil
  i = 0
  while i < entries.size()
    pair = entries[i]
    if pair != nil && pair.size() >= 2
      k = pair[0]
      v = pair[1]
      if k != nil && ast_kind(k) == :symbol && k.value == key_name
        if v != nil && ast_kind(v) == :symbol
          return v.value
    i += 1
  nil

# Like lookup_kwarg but accepts string-literal values too. Used by
# @layout where buffer-type names like "i32[]" are passed as strings
# (the symbol form `:i32[]` doesn't parse — `[]` collides with array
# subscript syntax).
-> lookup_kwarg_str_or_sym(kwargs_node, key_name)
  if kwargs_node == nil || ast_kind(kwargs_node) != :hash_literal
    return nil
  entries = kwargs_node.entries
  if entries == nil
    return nil
  i = 0
  while i < entries.size()
    pair = entries[i]
    if pair != nil && pair.size() >= 2
      k = pair[0]
      v = pair[1]
      if k != nil && ast_kind(k) == :symbol && k.value == key_name
        if v != nil
          if ast_kind(v) == :symbol
            return v.value
          if ast_kind(v) == :string
            return v.value
    i += 1
  nil

# Same as lookup_kwarg but returns int values for ints (e.g. `stride: 32`).
-> lookup_kwarg_int(kwargs_node, key_name)
  if kwargs_node == nil || ast_kind(kwargs_node) != :hash_literal
    return nil
  entries = kwargs_node.entries
  if entries == nil
    return nil
  i = 0
  while i < entries.size()
    pair = entries[i]
    if pair != nil && pair.size() >= 2
      k = pair[0]
      v = pair[1]
      if k != nil && ast_kind(k) == :symbol && k.value == key_name
        if v != nil && ast_kind(v) == :int
          return v.value
    i += 1
  nil

# Walk the kernel body. For every assign with `axis_name == :a` whose
# RHS is `gpu.thread_position_in_grid.x`, rewrite the inner call name
# to `threadgroup_position_in_grid`. Mutates in place — caller has
# already deep-cloned.
-> rewrite_axis_to_threadgroup(node, axis_name)
  if node == nil
    return nil
  if type(node) == "Array"
    i = 0
    while i < node.size()
      rewrite_axis_to_threadgroup(node[i], axis_name)
      i += 1
    return nil
  if !is_ast_node?(node)
    return nil
  if ast_kind(node) == :assign && node.axis_name == axis_name
    v = node.value
    if v != nil && ast_kind(v) == :call && v.receiver != nil
      inner = v.receiver
      if ast_kind(inner) == :call && inner.name == "thread_position_in_grid"
        inner.name = "threadgroup_position_in_grid"
  # Recurse into all AST children (Arrays are walked into; single
  # AST children get visited directly).
  ast_children(node).each -> (c)
    rewrite_axis_to_threadgroup(c, axis_name)

# `axis :b, parallelize: :simdgroup_lane, stride: N` rewrites:
#   1. The init assign tagged `## axis :b` from `b = <expr>` to
#      `b = gpu.thread_index_in_simdgroup`.
#   2. The b-loop body's increment of `b`. Originals like `b = b + 1`
#      become `b = b + N`. Detected by walking the while-loop body
#      that immediately follows the b-init assign.
-> rewrite_axis_to_simdgroup_lane(body, axis_name, stride)
  if body == nil || type(body) != "Array"
    return nil
  i = 0
  while i < body.size()
    stmt = body[i]
    if stmt != nil && is_ast_node?(stmt) && ast_kind(stmt) == :assign && stmt.axis_name == axis_name
      stmt.value = Tungsten:AST:Call.new(Tungsten:AST:Var.new("gpu"), "thread_index_in_simdgroup", [], nil)
      # Look at subsequent siblings for the matching while-loop.
      j = i + 1
      while j < body.size()
        if body[j] != nil && ast_kind(body[j]) == :while
          rewrite_loop_increment(body[j].body, axis_name, stride)
          j = body.size()
        j += 1
    # Recurse into nested bodies (if/while/etc.).
    if stmt != nil && is_ast_node?(stmt)
      ast_array_fields(stmt).each -> (kv)
        rewrite_axis_to_simdgroup_lane(kv, axis_name, stride)
    i += 1

# Find `var = var + N` (any `N`) inside `body` and replace `N` with
# `stride`. Mutates the matching int-literal RHS in place.
-> rewrite_loop_increment(body, var_name, stride)
  if body == nil || type(body) != "Array"
    return nil
  i = 0
  while i < body.size()
    stmt = body[i]
    if stmt != nil && ast_kind(stmt) == :assign
      tgt = stmt.target
      val = stmt.value
      if tgt != nil && ast_kind(tgt) == :var && tgt.name == var_name
        if val != nil && ast_kind(val) == :binary_op && val.op == :PLUS
          # Pattern: var = var + INT or var = INT + var. Replace the int.
          left = val.left
          right = val.right
          if left != nil && ast_kind(left) == :var && left.name == var_name && right != nil && ast_kind(right) == :int
            right.value = stride
            right.raw = stride
          elsif right != nil && ast_kind(right) == :var && right.name == var_name && left != nil && ast_kind(left) == :int
            left.value = stride
            left.raw = stride
    # Recurse — handles nested loops if any.
    if stmt != nil && is_ast_node?(stmt)
      ast_array_fields(stmt).each -> (kv)
        rewrite_loop_increment(kv, var_name, stride)
    i += 1

# `axis :i, vectorize: N` unrolls the loop body N times with each copy
# substituting `i` → `i + k` for k in 0..N-1, and updates the increment
# from `i = i + 1` to `i = i + N`. The resulting MSL gets a wide loop
# body that the Metal compiler is much more likely to auto-vectorize
# into vec4 loads + FMA chains than the scalar version.
#
# Limitations: only fires when the loop's natural increment is `i = i + 1`
# (or the post-stride value if combined with parallelize). The body must
# be straight-line code without nested conditionals on `i` — the rewrite
# duplicates statements blindly. Q8 matvec inner loops fit this shape.
-> rewrite_axis_to_vectorize(body, axis_name, factor)
  if body == nil || type(body) != "Array"
    return nil
  i = 0
  while i < body.size()
    stmt = body[i]
    if stmt != nil && is_ast_node?(stmt) && ast_kind(stmt) == :assign && stmt.axis_name == axis_name
      # Find the matching while-loop sibling and unroll its body.
      j = i + 1
      while j < body.size()
        if body[j] != nil && ast_kind(body[j]) == :while
          unroll_while_body(body[j], axis_name, factor)
          j = body.size()
        j += 1
    if stmt != nil && is_ast_node?(stmt)
      ast_array_fields(stmt).each -> (kv)
        rewrite_axis_to_vectorize(kv, axis_name, factor)
    i += 1

# Replace the `while`'s body with N concatenated copies of the body,
# minus the induction-variable increment in each copy, then append one
# rewritten increment at the very end. Each copy k = 0..N-1 substitutes
# `axis_name` with `axis_name + k` so the duplicated reads/writes index
# the right elements.
-> unroll_while_body(while_node, axis_name, factor)
  orig_body = while_node.body
  if orig_body == nil
    return nil
  unrolled = []
  saved_increment = nil
  k = 0
  while k < factor
    bi = 0
    while bi < orig_body.size()
      stmt = orig_body[bi]
      if is_axis_increment(stmt, axis_name)
        if saved_increment == nil
          saved_increment = ast_clone(stmt)
      else
        cloned = ast_clone(stmt)
        if k > 0
          replaced = substitute_var_with_offset(cloned, axis_name, k)
          if replaced != nil
            cloned = replaced
        unrolled.push(cloned)
      bi += 1
    k += 1
  if saved_increment != nil
    unrolled.push(saved_increment)
  while_node.body = unrolled
  rewrite_loop_increment([while_node], axis_name, factor)

-> is_axis_increment(stmt, axis_name)
  if stmt == nil || ast_kind(stmt) != :assign
    return false
  tgt = stmt.target
  if tgt == nil || ast_kind(tgt) != :var || tgt.name != axis_name
    return false
  val = stmt.value
  if val == nil || ast_kind(val) != :binary_op || val.op != :PLUS
    return false
  l = val.left
  r = val.right
  if l != nil && ast_kind(l) == :var && l.name == axis_name
    return true
  if r != nil && ast_kind(r) == :var && r.name == axis_name
    return true
  false

# Walk a node tree replacing every var read of `var_name` with the
# expression `var_name + offset`. Skips assign-target positions
# (we only rewrite reads, not writes — the lone write site is the
# induction-variable increment which is preserved by unroll_while_body).
# A W_PACKED_NODE's kind and size class live in the WValue's tag bits,
# so a node can never change kind in place: when `node` itself is the
# var being replaced, the fresh binary_op comes back through the return
# value and the PARENT stores it into the slot it read the child from.
# Interior nodes rewrite their children in place and return nil.
-> substitute_var_with_offset(node, var_name, offset)
  if node == nil || !is_ast_node?(node)
    return nil
  if ast_kind(node) == :var && node.name == var_name
    return Tungsten:AST:BinaryOp.new(Tungsten:AST:Var.new(var_name), :PLUS, Tungsten:AST:Int.new(offset, nil, offset))
  # For assigns, recurse into value but skip target (don't substitute
  # writes of var_name with a binary expression — that's invalid).
  if ast_kind(node) == :assign
    replaced = substitute_var_with_offset(node.value, var_name, offset)
    if replaced != nil
      node.value = replaced
    return nil
  substitute_children_with_offset(node, var_name, offset)
  nil

# Parent-side store for substitute_var_with_offset: walk every schema
# field of `node`, recurse, and overwrite the field (or array element)
# whenever the recursion hands back a replacement node.
-> substitute_children_with_offset(node, var_name, offset)
  kid = kind_id_table[ast_kind(node)]
  if kid == nil
    return nil
  fields = slab_keys_table[kid]
  if fields == nil
    return nil
  fi = 0
  while fi < fields.size()
    v = ast_get(node, fields[fi])
    if type(v) == "Array"
      # Child-list arrays are immutable once frozen into a node's slot
      # (same discipline as the single-node branch below) — build a
      # replacement array whenever any element changes and write the
      # whole field back, rather than index-assigning into `v` in place.
      any_replaced = false
      rebuilt_arr = []
      vi = 0
      while vi < v.size()
        elt = v[vi]
        replaced = substitute_var_with_offset(elt, var_name, offset)
        if replaced != nil
          rebuilt_arr.push(replaced)
          any_replaced = true
        else
          rebuilt_arr.push(elt)
        vi += 1
      if any_replaced
        ast_set(node, fields[fi], rebuilt_arr)
    elsif is_ast_node?(v)
      replaced = substitute_var_with_offset(v, var_name, offset)
      if replaced != nil
        ast_set(node, fields[fi], replaced)
    fi += 1
  nil

# `axis :b, reduce: :simd_sum, into: :acc` injects two new statements
# right after the b-axis loop:
#   1. `acc = simd_sum(acc)`  — reduces partials across the SIMD group.
#   2. `if gpu.thread_index_in_simdgroup == 0` wrapping every statement
#      that follows in the same body — the lane-0 guard around the
#      writeback.
#
# Only :simd_sum is implemented in slice 4; :simd_max/:simd_min/etc.
# would be similar one-line additions to the dispatch below.
-> apply_simd_reduce(body, axis_name, reduce_with, target_var)
  if body == nil || type(body) != "Array"
    return nil
  reduce_fn = nil
  if reduce_with in ("simd_sum" "simd_max" "simd_min")
    reduce_fn = reduce_with
  if reduce_fn == nil
    return nil
  i = 0
  while i < body.size()
    stmt = body[i]
    # Find the b-axis init assign.
    if stmt != nil && is_ast_node?(stmt) && ast_kind(stmt) == :assign && stmt.axis_name == axis_name
      # The next while-loop is the b-loop. Inject after it.
      j = i + 1
      loop_idx = -1
      while j < body.size()
        if body[j] != nil && ast_kind(body[j]) == :while
          loop_idx = j
          j = body.size()
        j += 1
      if loop_idx >= 0
        # Build the two new statements:
        #   acc = simd_sum(acc)
        reduce_call = Tungsten:AST:Call.new(nil, reduce_fn, [Tungsten:AST:Var.new(target_var)], nil)
        reduce_assign = Tungsten:AST:Assign.new(Tungsten:AST:Var.new(target_var), reduce_call, nil)
        # Wrap whatever sits after the b-loop in `if lane == 0 ... end`.
        # That captures the writeback (e.g. `y[m] = acc`) without us
        # having to know exactly what shape it takes.
        tail = []
        ti = loop_idx + 1
        while ti < body.size()
          tail.push(body[ti])
          ti += 1
        # Truncate body in place: drop tail, append reduce_assign + if-block.
        # The simplest portable mutation is to clear & rebuild.
        rebuilt = []
        ri = 0
        while ri <= loop_idx
          rebuilt.push(body[ri])
          ri += 1
        rebuilt.push(reduce_assign)
        if tail.size() > 0
          lane_call = Tungsten:AST:Call.new(Tungsten:AST:Var.new("gpu"), "thread_index_in_simdgroup", [], nil)
          cond = Tungsten:AST:BinaryOp.new(lane_call, :EQ, Tungsten:AST:Int.new(0))
          rebuilt.push(Tungsten:AST:If.new(cond, tail, [], nil))
        # Return the replacement list — child-list arrays are immutable
        # once frozen into a node's slot (same discipline as node-kind
        # changes), so the caller reassigns `kernel.body = rebuilt`
        # rather than this function mutating `body` in place.
        return rebuilt
    i += 1

# ---- Layout pass: kernel AST + layout AST → transformed kernel AST ----
#
# Slice 5 of P3.4: implements `buffer :name, from: ..., to: ...,
# unpack: :sign_extend_per_byte`.
#   1. Updates the parameter's type hint (`i8[]` → `i32[]`), changing
#      the emitted MSL signature from `device char *buf` to
#      `device int *buf`.
#   2. Rewrites every `buf[idx]` read to
#      `((buf[idx/4] << ((3 - idx%4) * 8)) >> 24)` — sign-extend the
#      byte at position `idx%4` of the int word at position `idx/4`.
#      The MSL/clang compiler folds the index arithmetic for constant
#      indices and recognizes the byte-extract pattern.
-> apply_layout_to_kernel(kernel, layout)
  out = ast_clone(kernel)
  out.name = kernel.name + "_" + layout.variant
  directives = layout.directives
  i = 0
  while i < directives.size()
    apply_layout_directive(out, directives[i])
    i += 1
  out

-> apply_layout_directive(kernel, directive)
  if directive == nil || !is_ast_node?(directive) || ast_kind(directive) != :call
    return nil
  if directive.name != "buffer"
    return nil
  args = directive.args
  if args == nil || args.size() < 2
    return nil
  buf_arg = args[0]
  kwargs = args[1]
  if buf_arg == nil || ast_kind(buf_arg) != :symbol
    return nil
  buf_name = buf_arg.value
  to_type = lookup_kwarg_str_or_sym(kwargs, "to")
  unpack_method = lookup_kwarg(kwargs, "unpack")
  # Update the parameter's type hint.
  if to_type != nil && kernel.type_hints != nil
    kernel.type_hints[buf_name] = to_type
  # Rewrite reads.
  if unpack_method == "sign_extend_per_byte"
    rewrite_byte_reads_to_packed(kernel.body, buf_name)
  nil

# Walk the kernel body. For every call(name="[]", recv=var(buf_name),
# args=[idx]), replace with the packed-int unpack expression:
#   ((buf[idx/4] << ((3 - idx%4) * 8)) >> 24)
# Same replacement protocol as substitute_var_with_offset: a packed
# node can't change kind in place, so a rewritten read is RETURNED and
# the parent stores it into the field / array slot it came from; nil
# means nothing at this position changed. The top-level caller passes
# the kernel body Array, whose elements the Array branch writes back.
-> rewrite_byte_reads_to_packed(node, buf_name)
  if node == nil
    return nil
  if type(node) == "Array"
    i = 0
    while i < node.size()
      replaced = rewrite_byte_reads_to_packed(node[i], buf_name)
      if replaced != nil
        node[i] = replaced
      i += 1
    return nil
  if !is_ast_node?(node)
    return nil
  # Recurse into all AST children first (rewrites operate bottom-up
  # so nested byte reads inside compound expressions get caught),
  # storing any replacement back into the schema field it came from.
  kid = kind_id_table[ast_kind(node)]
  fields = nil
  if kid != nil
    fields = slab_keys_table[kid]
  if fields != nil
    fi = 0
    while fi < fields.size()
      v = ast_get(node, fields[fi])
      if type(v) == "Array"
        rewrite_byte_reads_to_packed(v, buf_name)
      elsif is_ast_node?(v)
        replaced = rewrite_byte_reads_to_packed(v, buf_name)
        if replaced != nil
          ast_set(node, fields[fi], replaced)
      fi += 1
  # If THIS node is a buf_name byte read, hand back the unpack expr.
  if ast_kind(node) == :call && node.name == "\[]"
    recv = node.receiver
    if recv != nil && ast_kind(recv) == :var && recv.name == buf_name
      args = node.args
      if args != nil && args.size() == 1
        idx = args[0]
        # Step 1: word_idx = idx / 4
        word_idx = Tungsten:AST:BinaryOp.new(ast_clone(idx), :SLASH, Tungsten:AST:Int.new(4))
        # Step 2: word_load = buf[word_idx]
        word_load = Tungsten:AST:Call.new(Tungsten:AST:Var.new(buf_name), "\[]", [word_idx], nil)
        # Step 3: byte_in_word = idx % 4
        byte_pos = Tungsten:AST:BinaryOp.new(ast_clone(idx), :PERCENT, Tungsten:AST:Int.new(4))
        # Step 4: shift = (3 - byte_in_word) * 8
        three_minus = Tungsten:AST:BinaryOp.new(Tungsten:AST:Int.new(3), :MINUS, byte_pos)
        shift = Tungsten:AST:BinaryOp.new(three_minus, :STAR, Tungsten:AST:Int.new(8))
        # Step 5: shifted = word_load << shift
        shifted = Tungsten:AST:BinaryOp.new(word_load, :LSHIFT, shift)
        # Step 6: result = shifted >> 24
        return Tungsten:AST:BinaryOp.new(shifted, :RSHIFT, Tungsten:AST:Int.new(24))

# Deep-clone an AST subtree. The old local hash-walking clone predated
# the slab flip and silently returned packed nodes UNCLONED (type() of a
# W_PACKED_NODE is not "Hash"), aliasing every "copy" the scheduler made.
# ast.w's ast_deep_clone allocates fresh slab nodes and copies slots +
# sparse meta, so schedule rewrites mutate real copies.
-> ast_clone(node)
  ast_deep_clone(node)

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
      out << "device "
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
    gpu_fns: gpu_fns
  }
  body = node.body
  n = body.size()
  bi = 0
  while bi < n
    stmt = body[bi]
    # Tungsten has no `return` keyword — a method yields its last
    # expression. So the FINAL body statement, when it's a value
    # expression (not an assign / if / while / store), becomes the
    # device function's `return`. Earlier statements (assigns building up
    # locals) emit normally.
    if bi == n - 1 && gpu_is_value_expr?(stmt)
      emit_indent(out, ctx)
      out << "return "
      out << emit_expr(ctx, stmt)
      out << ";\n"
    else
      emit_stmt(out, ctx, stmt)
    bi += 1
  out << "}\n"
  out.to_s()

# True when a body statement is a value-producing expression eligible to
# be a device function's implicit return (vs. a control/store statement).
-> gpu_is_value_expr?(node)
  if !is_ast_node?(node)
    return false
  k = ast_kind(node)
  if k in (:binary_op :unary_op :int :float :decimal :bool :var)
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
    out << msl_param_decl(param_types[pname], pname, buf_index)
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
  # 32 (max simdgroups per TG = 1024 / 32). Cheap (~256B) and unused if
  # no tg_* call is made.
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
    gpu_fns: gpu_fns
  }
  body = node.body
  bi = 0
  while bi < body.size()
    emit_stmt(out, ctx, body[bi])
    bi += 1

  out << "}\n"
  out.to_s()

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
    return "annotate parameters and locals: `x ## f32[]`, `i ## i32 = …`"
  if msg.include?("CUDA-only")
    return "build with TUNGSTEN_GPU_DIALECTS=cuda (default) or use the Metal simdgroup_* surface"
  if msg.include?("unsupported statement") || msg.include?("unsupported expression")
    return "GPU kernels support assign, if/else, while, return, arithmetic, indexing, and gpu.* primitives — see doc/getting-started and metal_emitter.w"
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
  if t == nil
    return nil
  s = t.to_s()
  bytes = s.bytes()
  n = bytes.size()
  if n < 2
    return nil
  if bytes[n - 2] == 91 && bytes[n - 1] == 93
    elt_name = s.slice(0, n - 2)
    mapped = msl_scalar_type(elt_name.to_sym())
    if mapped == nil
      return "UNMAPPED_" + elt_name
    return mapped
  nil

-> msl_param_decl(type_hint, pname, buf_index)
  arr_elt = msl_array_elt_type(type_hint)
  if arr_elt != nil
    # Output buffers are mutable device pointers; the restriction is
    # loosened in a later phase when we add `in`/`out` annotations.
    return "device " + arr_elt + " *" + pname + " \[\[buffer(" + buf_index.to_s() + ")]]"
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

-> emit_stmt(out, ctx, node)
  t = ast_kind(node)
  if t == :assign
    emit_assign(out, ctx, node)
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
      vargs = value.args
      if vargs == nil || vargs.size() != 1 || ast_kind(vargs[0]) != :int
        gpu_kernel_error(ctx[:node], "gpu." + vname + " takes one integer-literal size")
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
      emit_indent(out, ctx)
      if ctx[:dialect] == "cuda"
        out << "__shared__ "
      else
        out << "threadgroup "
      out << elt
      out << " "
      out << sname
      out << "\["
      out << vargs[0].value.to_s()
      out << "];\n"
      return nil
  if ast_kind(target) == :var
    vname = target.name
    value_type = infer_expr_type(ctx, value)
    if ast_kind(value) == :typed_array
      # Thread-private fixed-size local array: `buf = i32[64]` → `int buf[64];`
      elt = value.element_type
      esc = msl_scalar_type(elt)
      if esc == nil
        gpu_kernel_error(ctx[:node], "unsupported local array element type `" + elt.to_s() + "`")
      ctx[:var_types][vname] = ("" + elt.to_s() + "\[]").to_sym()
      emit_indent(out, ctx)
      out << esc
      out << " "
      out << vname
      out << "\["
      out << emit_expr(ctx, ast_get(value, :size))
      out << "];\n"
    elsif type_hint != nil
      ctx[:var_types][vname] = type_hint
      scalar = msl_scalar_type(type_hint)
      if scalar == nil
        gpu_kernel_error(ctx[:node], "unsupported assign type `" + type_hint.to_s() + "`")
      emit_indent(out, ctx)
      out << scalar
      out << " "
      out << vname
      out << " = "
      out << emit_expr(ctx, value)
      out << ";\n"
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
      emit_indent(out, ctx)
      out << scalar
      out << " "
      out << vname
      out << " = "
      out << emit_expr(ctx, value)
      out << ";\n"
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
  node.name

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
    return name.to_s()

  if name == "\[]"
    if args == nil || args.size() != 1
      gpu_kernel_error(ctx[:node], "unsupported array-get arity")
    # `"\["` avoids triggering Tungsten's own string-interp tokenizer
    # inside this source file; the emitted text is just `[`.
    return emit_expr(ctx, recv) + "\[" + emit_expr(ctx, args[0]) + "]"
  if name == "\[]=" && args != nil && args.size() == 2
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
      if args.size() != 1
        gpu_kernel_error(ctx[:node], "`" + name + "` takes 1 arg")
      return name + "(" + emit_expr(ctx, args[0]) + ")"
    # Threadgroup-wide reductions: `tg_sum(x)`, `tg_max(x)`, `tg_min(x)`.
    # Operate across the entire threadgroup (up to 1024 threads / 32
    # simdgroups). Routed by inferred arg type to the right helper +
    # scratch buffer (f32 or i32).
    if name in ("tg_sum" "tg_max" "tg_min")
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
    ctx[:gpu_fns]["" + node.name.to_s()]
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

# ---- CUDA C emission (second GPU dialect, v0) ----
# The statement/expression emitters above generate C, and every gpu.*
# builtin flows through the __tid/__tg_id/__simd_* locals — so CUDA reuses
# them wholesale; only the signature and the prologue that derives those
# locals from blockIdx/blockDim/threadIdx differ. Metal-only features
# (threadgroup scratch, simdgroup matrices, tg_* reduction helpers) are
# not mapped in v0 — kernels that use them get a skip comment.

-> cuda_elt_name(msl_name)
  if msl_name == "bfloat"
    return "__nv_bfloat16"
  if msl_name == "half"
    return "__half"
  msl_name

-> cuda_param_decl(type_hint, pname)
  arr_elt = msl_array_elt_type(type_hint)
  if arr_elt != nil
    return cuda_elt_name(arr_elt) + " *" + pname
  scalar = msl_scalar_type(type_hint)
  if scalar != nil
    return scalar + " " + pname
  "/* unsupported type: " + type_hint.to_s() + " */ void *" + pname

-> emit_kernel_cuda(node)
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
    param_types[pname] = ptype
    param_names.push(pname)
    pi += 1

  out = StringBuffer(512)
  out << "extern \"C\" __global__ void "
  out << name
  out << "(\n"
  pi = 0
  while pi < param_names.size()
    pname = param_names[pi]
    if pi > 0
      out << ",\n"
    out << "  "
    out << cuda_param_decl(param_types[pname], pname)
    pi += 1
  out << "\n) {\n"
  out << "  const uint3 __tid = make_uint3(blockIdx.x * blockDim.x + threadIdx.x, blockIdx.y * blockDim.y + threadIdx.y, blockIdx.z * blockDim.z + threadIdx.z);\n"
  out << "  const uint3 __tid_in_tg = threadIdx;\n"
  out << "  const uint3 __tg_id = blockIdx;\n"
  out << "  const uint3 __tg_size = blockDim;\n"
  out << "  const unsigned int __simd_lane = threadIdx.x & 31u;\n"
  out << "  const unsigned int __simd_id = threadIdx.x >> 5;\n"
  out << "  (void)__tid_in_tg; (void)__tg_id; (void)__tg_size; (void)__simd_lane; (void)__simd_id;\n"

  ctx = {
    node: node,
    var_types: dup_hash(param_types),
    params: param_names,
    indent: 1,
    dialect: "cuda"
  }
  body = node.body
  bi = 0
  while bi < body.size()
    emit_stmt(out, ctx, body[bi])
    bi += 1
  out << "}\n"
  out.to_s()

# Emit a `@gpu fn` with `## TYPE: ret` as a CUDA `__device__` helper.
-> emit_device_fn_cuda(node, gpu_fns)
  name = node.name
  params = node.params
  type_hints = node.type_hints
  if type_hints == nil
    type_hints = {}
  ret = type_hints["ret"]
  ret_c = msl_scalar_type(ret)
  if ret_c == nil
    arr = msl_array_elt_type(ret)
    if arr != nil
      ret_c = cuda_elt_name(arr) + " *"
    else
      gpu_kernel_error(node, "device fn `" + name + "` has unsupported return type `" + ret.to_s() + "`")
  out = StringBuffer(512)
  out << "__device__ "
  out << ret_c
  out << " "
  out << name
  out << "("
  param_types = {}
  param_names = []
  pi = 0
  while pi < params.size()
    p = params[pi]
    pname = p.name
    ptype = type_hints[pname]
    if ptype == nil
      gpu_kernel_error(node, "device fn `" + name + "` param `" + pname + "` needs a ## type hint")
    param_types[pname] = ptype
    param_names.push(pname)
    if pi > 0
      out << ", "
    out << cuda_param_decl(ptype, pname)
    pi += 1
  out << ") {\n"
  ctx = {
    node: node,
    var_types: dup_hash(param_types),
    params: param_names,
    indent: 1,
    dialect: "cuda",
    gpu_fns: gpu_fns
  }
  body = node.body
  bi = 0
  while bi < body.size()
    emit_stmt(out, ctx, body[bi])
    bi += 1
  out << "}\n"
  out.to_s()

-> emit_gpu_kernels_cuda(kernels)
  if kernels == nil || kernels.size() == 0
    return nil
  out = StringBuffer(1024)
  out << "// Tungsten @gpu kernel output (CUDA C dialect) — do not edit by hand\n"
  out << "#include <cuda_runtime.h>\n"
  out << "#include <cuda_bf16.h>\n"
  out << "#include <device_launch_parameters.h>\n"
  out << "#include <mma.h>\n"
  out << "using namespace nvcuda;\n\n"
  # Cooperative-group / shared-memory helpers used by gpu.barrier etc.
  out << "__device__ inline void __w_gpu_barrier() { __syncthreads(); }\n\n"
  gpu_fns = {}
  i = 0
  while i < kernels.size()
    rt = gpu_fn_return_type(kernels[i])
    if rt != nil
      gpu_fns["" + kernels[i].name.to_s()] = rt
    i += 1
  # Device helpers first so kernels can call them.
  i = 0
  while i < kernels.size()
    if gpu_fn_return_type(kernels[i]) != nil
      out << emit_device_fn_cuda(kernels[i], gpu_fns)
      out << "\n"
    i += 1
  i = 0
  while i < kernels.size()
    if gpu_fn_return_type(kernels[i]) == nil
      out << emit_kernel_cuda(kernels[i])
      out << "\n"
    i += 1
  # Host-side launch helper stub (optional include for hand-written hosts).
  out << "// Host launch pattern (link with cudart):\n"
  out << "//   kernel<<<grid, block, shared_bytes, stream>>>(args...);\n"
  out << "//   cudaDeviceSynchronize();\n"
  out.to_s()

# ---- WGSL emission (WebGPU dialect, v0 — restricted subset) ----
# WGSL is not C: buffers are module-scope bindings, locals declare with
# `var`, and there's no pointer syntax. v0 translates the elementwise
# kernel shape (assignments, if, indexing, arithmetic, the global thread
# id); kernels outside the subset are skipped with a comment.

-> wgsl_elt_name(msl_name)
  if msl_name == "float"
    return "f32"
  if msl_name == "int"
    return "i32"
  if msl_name == "uint"
    return "u32"
  if msl_name == "half"
    return "f16"
  msl_name

-> wgsl_scalar(type_hint)
  if type_hint == :i32 || type_hint == :u32
    return "i32"
  if type_hint == :f32
    return "f32"
  nil

-> wgsl_expr(ctx, node)
  t = ast_kind(node)
  if t == :int
    return node.value.to_s()
  if t == :float || t == :decimal
    s = node.value.to_s()
    if s.include?(".")
      return s
    return s + ".0"
  if t == :var
    return "" + node.name
  if t == :binary_op
    return "(" + wgsl_expr(ctx, node.left) + " " + binop_symbol(node.op) + " " + wgsl_expr(ctx, node.right) + ")"
  if t == :call
    recv = node.receiver
    nm = "" + node.name.to_s()
    # gpu.thread_position_in_grid.x — global invocation id component.
    if recv != nil && is_ast_node?(recv) && ast_kind(recv) == :call && ("" + recv.name.to_s()) == "thread_position_in_grid"
      return "i32(__tid." + nm + ")"
    # Array element read: receiver[idx] arrives as a `[]` call.
    if nm == "\[]" && recv != nil
      cargs = node.args
      if cargs != nil && cargs.size() == 1
        base = wgsl_expr(ctx, recv)
        idx = wgsl_expr(ctx, cargs[0])
        if base != nil && idx != nil
          return base + "\[" + idx + "\]"
    return nil
  if t == :index
    base = wgsl_expr(ctx, node.receiver)
    idx = wgsl_expr(ctx, ast_get(node, :index))
    if base == nil || idx == nil
      return nil
    return base + "\[" + idx + "\]"
  nil

-> wgsl_stmt(out, ctx, node, declared)
  t = ast_kind(node)
  if t == :assign
    target = node.target
    value = wgsl_expr(ctx, node.value)
    if value == nil
      return false
    tk = ast_kind(target)
    if tk == :var
      vname = "" + target.name
      emit_indent(out, ctx)
      if declared[vname] == nil && !ctx[:params].include?(vname)
        declared[vname] = true
        out << "var "
      out << vname
      out << " = "
      out << value
      out << ";\n"
      return true
    if tk == :index
      lhs = wgsl_expr(ctx, target)
      if lhs == nil
        return false
      emit_indent(out, ctx)
      out << lhs
      out << " = "
      out << value
      out << ";\n"
      return true
    return false
  if t == :call && ("" + node.name.to_s()) == "\[]="
    # Indexed store: receiver[idx] = value arrives as a `[]=` call.
    recv = node.receiver
    cargs = node.args
    if recv == nil || cargs == nil || cargs.size() != 2
      return false
    base = wgsl_expr(ctx, recv)
    idx = wgsl_expr(ctx, cargs[0])
    value = wgsl_expr(ctx, cargs[1])
    if base == nil || idx == nil || value == nil
      return false
    emit_indent(out, ctx)
    out << base
    out << "\[" + idx + "\] = "
    out << value
    out << ";\n"
    return true
  if t == :if
    cond = wgsl_expr(ctx, node.condition)
    if cond == nil
      return false
    emit_indent(out, ctx)
    out << "if ("
    out << cond
    out << ") {\n"
    ctx[:indent] = ctx[:indent] + 1
    body = node.then_body
    bi = 0
    while bi < body.size()
      if !wgsl_stmt(out, ctx, body[bi], declared)
        ctx[:indent] = ctx[:indent] - 1
        return false
      bi += 1
    ctx[:indent] = ctx[:indent] - 1
    emit_indent(out, ctx)
    out << "}\n"
    return true
  false

-> emit_kernel_wgsl(node, group_base)
  name = node.name
  params = node.params
  type_hints = node.type_hints
  if type_hints == nil
    type_hints = {}
  out = StringBuffer(512)
  binding = 0
  pnames = []
  pi = 0
  while pi < params.size()
    p = params[pi]
    pname = p.name
    ptype = type_hints[pname]
    pnames.push(pname)
    arr_elt = msl_array_elt_type(ptype)
    out << "@group(0) @binding("
    out << binding.to_s()
    out << ") "
    if arr_elt != nil
      out << "var<storage, read_write> "
      out << pname
      out << " : array<"
      out << wgsl_elt_name(arr_elt)
      out << ">;\n"
    else
      sc = wgsl_scalar(ptype)
      if sc == nil
        return "// kernel `" + name + "` skipped: unsupported param type for WGSL v0\n"
      out << "var<uniform> "
      out << pname
      out << " : "
      out << sc
      out << ";\n"
    binding = binding + 1
    pi += 1
  out << "@compute @workgroup_size(256)\n"
  out << "fn "
  out << name
  out << "(@builtin(global_invocation_id) __tid : vec3<u32>) {\n"
  ctx = {node: node, var_types: {}, params: pnames, indent: 1}
  declared = {}
  body_out = StringBuffer(256)
  body = node.body
  bi = 0
  while bi < body.size()
    if !wgsl_stmt(body_out, ctx, body[bi], declared)
      return "// kernel `" + name + "` skipped: outside the WGSL v0 subset (stmt " + ast_kind(body[bi]).to_s() + ")\n"
    bi += 1
  out << body_out.to_s()
  out << "}\n"
  out.to_s()

-> emit_gpu_kernels_wgsl(kernels)
  if kernels == nil || kernels.size() == 0
    return nil
  out = StringBuffer(1024)
  out << "// Tungsten @gpu kernel output (WGSL dialect) — do not edit by hand\n\n"
  i = 0
  while i < kernels.size()
    # Skip device helper functions (ret-hinted) in the WGSL v0 path.
    if gpu_fn_return_type(kernels[i]) == nil
      out << emit_kernel_wgsl(kernels[i], i)
      out << "\n"
    i += 1
  out.to_s()

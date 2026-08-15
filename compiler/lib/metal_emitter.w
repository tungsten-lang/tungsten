# Metal Shading Language emitter for `@gpu fn` kernels.
#
# Portable kernel emitter: walk a `:gpu_kernel_def` AST node and produce
# MSL/CUDA source plus an opt-in WGSL sidecar. The common statement surface
# includes assignments, scalar control flow, returns, and indexed buffers;
# backend-specific primitives are checked by their dialect arms.
#
#   @gpu fn add_one(x ## f32[], y ## f32[], n ## i32)
#     i ## i32 = gpu.thread_position_in_grid.x
#     if i < n
#       y[i] = x[i] + 1.0
#
# Anything outside the supported subset raises a compile-time error with
# the usual `-->` formatter. The emitter is multi-dialect: MSL is always
# emitted when kernels are present, CUDA C by default (sharing the kernel
# AST and statement emitters, switched on ctx[:dialect]), and WGSL when
# TUNGSTEN_GPU_DIALECTS includes it — see doc/gpu-cuda.md.

use ast

# ---- Public entry points ----

# Emit full .metal source for a list of `@gpu fn` AST nodes.
# Returns the text, or nil when `kernels` is empty.
-> emit_gpu_kernels_metal(kernels, only_index = nil)
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
      gpu_fns["" + kernels[i].name.to_s()] = gpu_fn_signature(kernels[i])
    i += 1
  i = 0
  while i < kernels.size()
    if gpu_fn_return_type(kernels[i]) != nil && (only_index == nil || only_index == i)
      out << emit_device_fn(kernels[i], gpu_fns)
      out << "\n"
    i += 1
  i = 0
  while i < kernels.size()
    if gpu_fn_return_type(kernels[i]) == nil && (only_index == nil || only_index == i)
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

-> gpu_fn_signature(node)
  hints = node.type_hints
  if hints == nil
    hints = {}
  names = []
  types = []
  params = node.params
  i = 0
  while i < params.size()
    name = "" + params[i].name
    names.push(name)
    types.push(hints[name])
    i += 1
  {ret: gpu_fn_return_type(node), param_names: names, param_types: types, param_spaces: gpu_param_address_spaces(node, names, hints, false)}

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
  if k in (:and :or)
    if wmma_scan(x.left) || wmma_scan(x.right)
      return true
    return false
  if k == :not
    return wmma_scan(x.operand)
  false

# True when a kernel body calls tg_sum / tg_max / tg_min — the only
# constructs that read the threadgroup scratch arrays, and so the only
# reason to declare them. Deliberately more thorough than wmma_scan: every
# node kind that can hold a subexpression is walked, because a missed use
# would emit MSL referencing an undeclared array.
-> gpu_uses_tg_reduce?(node)
  tg_reduce_scan(node.body)

-> tg_reduce_scan(x)
  if x == nil
    return false
  if type(x) == "Array"
    i = 0
    while i < x.size()
      if tg_reduce_scan(x[i])
        return true
      i += 1
    return false
  if !is_ast_node?(x)
    return false
  k = ast_kind(x)
  if k == :call
    if ("" + x.name.to_s()) in ("tg_sum" "tg_max" "tg_min")
      return true
    if tg_reduce_scan(x.receiver)
      return true
    return tg_reduce_scan(x.args)
  if k == :assign
    if tg_reduce_scan(x.target)
      return true
    return tg_reduce_scan(x.value)
  if k == :if
    if tg_reduce_scan(x.condition) || tg_reduce_scan(x.then_body) || tg_reduce_scan(x.else_body)
      return true
    return tg_reduce_scan(x.elsif_clauses)
  if k == :while
    if tg_reduce_scan(x.condition)
      return true
    return tg_reduce_scan(x.body)
  if k in (:binary_op :and :or)
    if tg_reduce_scan(x.left)
      return true
    return tg_reduce_scan(x.right)
  if k in (:not :unary_op)
    return tg_reduce_scan(x.operand)
  if k == :return
    return tg_reduce_scan(x.value)
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
use metal_emitter/transforms
use metal_emitter/msl
use metal_emitter/dialects

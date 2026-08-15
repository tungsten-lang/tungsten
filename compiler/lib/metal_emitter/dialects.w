
# ---- CUDA C emission (second GPU dialect, v0) ----
# The statement/expression emitters above generate C, and every gpu.*
# builtin flows through the __tid/__tg_id/__simd_* locals — so CUDA reuses
# them wholesale; only the signature and the prologue that derives those
# locals from blockIdx/blockDim/threadIdx differ. Metal-only reduction and
# simdgroup-matrix calls are rejected while emitting CUDA so invalid MSL names
# never leak into a .cu sidecar and fail later inside nvcc.

-> cuda_type_name(msl_name)
  if msl_name == "bfloat"
    return "__nv_bfloat16"
  if msl_name == "half"
    return "__half"
  if msl_name == "long"
    return "long long"
  if msl_name == "ulong"
    return "unsigned long long"
  if msl_name == "uchar"
    return "unsigned char"
  if msl_name == "ushort"
    return "unsigned short"
  if msl_name == "uint"
    return "unsigned int"
  if msl_name in ("char" "short" "int" "float" "float2" "float3" "float4" "int4" "uint4" "bool")
    return msl_name
  nil

-> cuda_param_type_supported?(type_hint)
  arr_elt = msl_array_elt_type(type_hint)
  if arr_elt != nil
    return cuda_type_name(arr_elt) != nil
  scalar = msl_scalar_type(type_hint)
  scalar != nil && cuda_type_name(scalar) != nil

-> cuda_param_decl(node, type_hint, pname, entry_kernel)
  arr_elt = msl_array_elt_type(type_hint)
  if arr_elt != nil
    space = gpu_param_address_space(node, pname, type_hint, entry_kernel)
    prefix = space == "constant" ? "const " : ""
    return prefix + cuda_type_name(arr_elt) + " *" + pname
  scalar = msl_scalar_type(type_hint)
  if scalar != nil
    return cuda_type_name(scalar) + " " + pname
  "/* unsupported type: " + type_hint.to_s() + " */ void *" + pname

-> emit_kernel_cuda(node, gpu_fns)
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
    if !cuda_param_type_supported?(ptype)
      gpu_kernel_error(node, "parameter `" + pname + "` type `" + ptype.to_s() + "` is not supported by the CUDA dialect")
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
    out << cuda_param_decl(node, param_types[pname], pname, true)
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
    dialect: "cuda",
    gpu_fns: gpu_fns,
    declared: {},
    hoist: [],
    tables: [],
    renames: {},
    unroll: {},
    array_bounds: gpu_param_array_bounds(param_names, param_types),
    address_spaces: gpu_param_address_spaces(node, param_names, param_types, true),
    shared_bytes: 0
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

# Emit a `@gpu fn` with `## TYPE: ret` as a CUDA `__device__` helper.
-> emit_device_fn_cuda(node, gpu_fns)
  name = node.name
  params = node.params
  type_hints = node.type_hints
  if type_hints == nil
    type_hints = {}
  ret = type_hints["ret"]
  ret_msl = msl_scalar_type(ret)
  ret_c = cuda_type_name(ret_msl)
  if ret_c == nil
    arr = msl_array_elt_type(ret)
    arr_c = cuda_type_name(arr)
    if arr_c != nil
      ret_c = arr_c + " *"
    else
      gpu_kernel_error(node, "device fn `" + name + "` return type `" + ret.to_s() + "` is not supported by the CUDA dialect")
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
    if !gpu_param_type_supported?(ptype)
      gpu_kernel_error(node, "device fn `" + name + "` param `" + pname + "` has unsupported type `" + ptype.to_s() + "`")
    if !cuda_param_type_supported?(ptype)
      gpu_kernel_error(node, "device fn `" + name + "` param `" + pname + "` type `" + ptype.to_s() + "` is not supported by the CUDA dialect")
    param_types[pname] = ptype
    param_names.push(pname)
    if pi > 0
      out << ", "
    out << cuda_param_decl(node, ptype, pname, false)
    pi += 1
  out << ") {\n"
  ctx = {
    node: node,
    var_types: dup_hash(param_types),
    params: param_names,
    indent: 1,
    dialect: "cuda",
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
  body_out = StringBuffer(256)
  bi = 0
  while bi < body.size()
    emit_stmt(body_out, ctx, body[bi])
    bi += 1
  gpu_emit_hoisted(out, ctx)
  out << body_out.to_s()
  out << "}\n"
  gpu_with_tables(ctx, out.to_s())

-> emit_gpu_kernels_cuda(kernels, only_index = nil)
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
      gpu_fns["" + kernels[i].name.to_s()] = gpu_fn_signature(kernels[i])
    i += 1
  # Device helpers first so kernels can call them.
  i = 0
  while i < kernels.size()
    if gpu_fn_return_type(kernels[i]) != nil && (only_index == nil || only_index == i)
      out << emit_device_fn_cuda(kernels[i], gpu_fns)
      out << "\n"
    i += 1
  i = 0
  while i < kernels.size()
    if gpu_fn_return_type(kernels[i]) == nil && (only_index == nil || only_index == i)
      out << emit_kernel_cuda(kernels[i], gpu_fns)
      out << "\n"
    i += 1
  # Host-side launch helper stub (optional include for hand-written hosts).
  out << "// Host launch pattern (link with cudart):\n"
  out << "//   kernel<<<grid, block, shared_bytes, stream>>>(args...);\n"
  out << "//   cudaDeviceSynchronize();\n"
  out.to_s()

# ---- WGSL emission (WebGPU dialect) ----
# WGSL is not C: buffers are module-scope bindings, locals declare with
# `var`, and there's no pointer syntax. The supported portable subset covers
# scalar control flow, storage/workgroup arrays, barriers, and i32 atomics;
# kernels using dialect-only features fail preflight with a source diagnostic.

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
  if type_hint == nil
    return nil
  name = gpu_hint_type(type_hint).to_s()
  if name == "i32"
    return "i32"
  if name == "u32"
    return "u32"
  if name == "f32"
    return "f32"
  nil

# Storage buffers touched through gpu.atomic_* must be declared with atomic
# elements in WGSL. Collect only direct local/parameter buffer references; a
# computed pointer shape is outside the portable subset and remains rejected
# by wgsl_expr.
-> wgsl_collect_atomic_buffers(node, found)
  if node == nil || !is_ast_node?(node)
    return nil
  t = ast_kind(node)
  if t == :call
    recv = node.receiver
    name = "" + node.name.to_s()
    if recv != nil && ast_kind(recv) == :var && recv.name == "gpu" && name in ("atomic_load_i32" "atomic_store_i32" "atomic_exchange_i32" "atomic_fetch_add_i32" "atomic_min_i32")
      args = node.args
      if args != nil && args.size() > 0 && ast_kind(args[0]) == :var
        found[args[0].name] = true
    wgsl_collect_atomic_buffers(recv, found)
    args = node.args
    if args != nil
      ai = 0
      while ai < args.size()
        wgsl_collect_atomic_buffers(args[ai], found)
        ai += 1
    return nil
  if t == :assign || t == :compound_assign
    wgsl_collect_atomic_buffers(node.target, found)
    wgsl_collect_atomic_buffers(node.value, found)
    return nil
  if t in (:binary_op :and :or)
    wgsl_collect_atomic_buffers(node.left, found)
    wgsl_collect_atomic_buffers(node.right, found)
    return nil
  if t == :not || t == :unary_op
    wgsl_collect_atomic_buffers(node.operand, found)
    return nil
  if t == :return
    wgsl_collect_atomic_buffers(node.value, found)
    return nil
  if t == :if
    wgsl_collect_atomic_buffers(node.condition, found)
    groups = [node.then_body, node.else_body]
    if node.elsif_clauses != nil
      ei = 0
      while ei < node.elsif_clauses.size()
        clause = node.elsif_clauses[ei]
        wgsl_collect_atomic_buffers(clause[0], found)
        groups.push(clause[1])
        ei += 1
    gi = 0
    while gi < groups.size()
      body = groups[gi]
      if body != nil
        bi = 0
        while bi < body.size()
          wgsl_collect_atomic_buffers(body[bi], found)
          bi += 1
      gi += 1
    return nil
  if t == :while
    wgsl_collect_atomic_buffers(node.condition, found)
    body = node.body
    bi = 0
    while bi < body.size()
      wgsl_collect_atomic_buffers(body[bi], found)
      bi += 1
  nil

-> wgsl_expr(ctx, node)
  if node == nil
    return nil
  t = ast_kind(node)
  if t == :int
    return node.value.to_s()
  if t == :float || t == :decimal
    s = node.value.to_s()
    if s.include?(".")
      return s
    return s + ".0"
  if t == :var
    name = "" + node.name
    renamed = ctx[:renames][name]
    return renamed == nil ? name : renamed
  if t == :binary_op
    l = wgsl_expr(ctx, node.left)
    r = wgsl_expr(ctx, node.right)
    if l == nil || r == nil || node.op == :POW
      return nil
    return "(" + l + " " + binop_symbol(node.op) + " " + r + ")"
  if t == :unary_op
    value = wgsl_expr(ctx, node.operand)
    if value == nil
      return nil
    return "(" + uop_symbol(node.op) + value + ")"
  if t == :bool
    return node.value ? "true" : "false"
  # WGSL has native short-circuit `&&`/`||`/`!` over bool. Keeping the
  # dialect at parity with MSL/CUDA here stops a kernel that uses logic
  # from being silently skipped on the WebGPU path.
  if t == :and || t == :or
    l = wgsl_expr(ctx, node.left)
    r = wgsl_expr(ctx, node.right)
    if l == nil || r == nil
      return nil
    if t == :and
      return "(" + l + " && " + r + ")"
    return "(" + l + " || " + r + ")"
  if t == :not
    o = wgsl_expr(ctx, node.operand)
    if o == nil
      return nil
    return "(!" + o + ")"
  if t == :call
    recv = node.receiver
    nm = "" + node.name.to_s()
    # gpu.{thread_position_in_grid,thread_position_in_threadgroup,
    # threadgroup_position_in_grid}.x/y/z builtins.
    if nm in ("x" "y" "z") && recv != nil && is_ast_node?(recv) && ast_kind(recv) == :call && recv.receiver != nil && ast_kind(recv.receiver) == :var && recv.receiver.name == "gpu"
      builtin = "" + recv.name.to_s()
      if builtin == "thread_position_in_grid"
        return "i32(tungsten_internal_tid." + nm + ")"
      if builtin == "thread_position_in_threadgroup"
        return "i32(tungsten_internal_tid_local." + nm + ")"
      if builtin == "threadgroup_position_in_grid"
        return "i32(tungsten_internal_group_id." + nm + ")"
    # Array element read: receiver[idx] arrives as a `[]` call.
    if nm == "\[]" && recv != nil
      cargs = node.args
      if cargs != nil && cargs.size() == 1
        gpu_check_literal_bound(ctx, recv, cargs[0])
        base = wgsl_expr(ctx, recv)
        idx = wgsl_expr(ctx, cargs[0])
        if base != nil && idx != nil
          return base + "\[" + idx + "\]"
    if recv != nil && ast_kind(recv) == :var && recv.name == "gpu"
      if nm == "threads_per_threadgroup"
        return "256"
      if nm in ("atomic_load_i32" "atomic_store_i32" "atomic_exchange_i32" "atomic_fetch_add_i32" "atomic_min_i32")
        cargs = node.args
        expected = nm == "atomic_load_i32" ? 2 : 3
        if cargs == nil || cargs.size() != expected || ast_kind(cargs[0]) != :var
          return nil
        buffer = wgsl_expr(ctx, cargs[0])
        index = wgsl_expr(ctx, cargs[1])
        if buffer == nil || index == nil
          return nil
        pointer = "&" + buffer + "\[" + index + "\]"
        if nm == "atomic_load_i32"
          return "atomicLoad(" + pointer + ")"
        value = wgsl_expr(ctx, cargs[2])
        if value == nil
          return nil
        if nm == "atomic_store_i32"
          return "atomicStore(" + pointer + ", " + value + ")"
        if nm == "atomic_exchange_i32"
          return "atomicExchange(" + pointer + ", " + value + ")"
        if nm == "atomic_fetch_add_i32"
          return "atomicAdd(" + pointer + ", " + value + ")"
        return "atomicMin(" + pointer + ", " + value + ")"
    if recv == nil && nm == "threadgroup_barrier" && (node.args == nil || node.args.size() == 0)
      return "workgroupBarrier()"
    return nil
  if t == :index
    gpu_check_literal_bound(ctx, node.receiver, ast_get(node, :index))
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
    # WGSL workgroup variables live at module scope. Keep the source-local
    # name through a rename map and emit one kernel-qualified declaration
    # before the entry point.
    if ast_kind(target) == :var && node.value != nil && is_ast_node?(node.value) && ast_kind(node.value) == :call
      shared_call = node.value
      shared_recv = shared_call.receiver
      shared_name = "" + shared_call.name.to_s()
      if shared_recv != nil && ast_kind(shared_recv) == :var && shared_recv.name == "gpu" && shared_name in ("shared_f32" "shared_i32" "shared_i64")
        shared_size = gpu_shared_size(ctx[:node], shared_call, "wgsl")
        gpu_record_shared_allocation(ctx, shared_name, shared_size)
        source_name = "" + target.name
        global_name = "tungsten_internal_wg_" + ctx[:kernel_name] + "_" + source_name
        elt = shared_name == "shared_f32" ? "f32" : "i32"
        ctx[:renames][source_name] = global_name
        ctx[:array_bounds][source_name] = shared_size
        ctx[:shared_decls] << "var<workgroup> " + global_name + " : array<" + elt + ", " + shared_size.to_s() + ">;\n"
        declared[source_name] = true
        return true
    value = wgsl_expr(ctx, node.value)
    if value == nil
      return false
    tk = ast_kind(target)
    if tk == :var
      vname = "" + target.name
      output_name = ctx[:renames][vname]
      if output_name == nil
        output_name = vname
      emit_indent(out, ctx)
      if declared[vname] == nil && !ctx[:params].include?(vname)
        declared[vname] = true
        out << "var "
      out << output_name
      out << " = "
      out << value
      out << ";\n"
      return true
    if tk == :index
      gpu_check_literal_bound(ctx, target.receiver, ast_get(target, :index))
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
  if t == :compound_assign
    lhs = wgsl_expr(ctx, node.target)
    rhs = wgsl_expr(ctx, node.value)
    if lhs == nil || rhs == nil
      return false
    emit_indent(out, ctx)
    out << lhs
    out << " " + binop_symbol(node.op) + "= "
    out << rhs
    out << ";\n"
    return true
  if t == :call && ("" + node.name.to_s()) == "\[]="
    # Indexed store: receiver[idx] = value arrives as a `[]=` call.
    recv = node.receiver
    cargs = node.args
    if recv == nil || cargs == nil || cargs.size() != 2
      return false
    gpu_check_literal_bound(ctx, recv, cargs[0])
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
    if body == nil
      body = []
    branch_declared = dup_hash(declared)
    bi = 0
    while bi < body.size()
      if !wgsl_stmt(out, ctx, body[bi], branch_declared)
        ctx[:indent] = ctx[:indent] - 1
        return false
      bi += 1
    ctx[:indent] = ctx[:indent] - 1
    emit_indent(out, ctx)
    out << "}"
    elsif_clauses = node.elsif_clauses
    if elsif_clauses != nil
      ei = 0
      while ei < elsif_clauses.size()
        clause = elsif_clauses[ei]
        clause_cond = wgsl_expr(ctx, clause[0])
        if clause_cond == nil
          return false
        out << " else if (" + clause_cond + ") {\n"
        ctx[:indent] = ctx[:indent] + 1
        clause_body = clause[1]
        if clause_body == nil
          clause_body = []
        branch_declared = dup_hash(declared)
        ci = 0
        while ci < clause_body.size()
          if !wgsl_stmt(out, ctx, clause_body[ci], branch_declared)
            ctx[:indent] = ctx[:indent] - 1
            return false
          ci += 1
        ctx[:indent] = ctx[:indent] - 1
        emit_indent(out, ctx)
        out << "}"
        ei += 1
    else_body = node.else_body
    if else_body != nil && else_body.size() > 0
      out << " else {\n"
      ctx[:indent] = ctx[:indent] + 1
      branch_declared = dup_hash(declared)
      ei = 0
      while ei < else_body.size()
        if !wgsl_stmt(out, ctx, else_body[ei], branch_declared)
          ctx[:indent] = ctx[:indent] - 1
          return false
        ei += 1
      ctx[:indent] = ctx[:indent] - 1
      emit_indent(out, ctx)
      out << "}"
    out << "\n"
    return true
  if t == :while
    cond = wgsl_expr(ctx, node.condition)
    if cond == nil
      return false
    emit_indent(out, ctx)
    out << "loop {\n"
    ctx[:indent] = ctx[:indent] + 1
    emit_indent(out, ctx)
    out << "if (!(" + cond + ")) { break; }\n"
    body = node.body
    loop_declared = dup_hash(declared)
    bi = 0
    while bi < body.size()
      if !wgsl_stmt(out, ctx, body[bi], loop_declared)
        ctx[:indent] = ctx[:indent] - 1
        return false
      bi += 1
    ctx[:indent] = ctx[:indent] - 1
    emit_indent(out, ctx)
    out << "}\n"
    return true
  if t == :return
    if node.value != nil && ast_kind(node.value) != :nil_lit
      return false
    emit_indent(out, ctx)
    out << "return;\n"
    return true
  if t == :break || t == :next
    emit_indent(out, ctx)
    out << (t == :break ? "break;\n" : "continue;\n")
    return true
  if t == :call
    expr = wgsl_expr(ctx, node)
    if expr == nil
      return false
    emit_indent(out, ctx)
    out << expr
    out << ";\n"
    return true
  false

-> emit_kernel_wgsl(node, binding_base)
  name = node.name
  params = node.params
  type_hints = node.type_hints
  if type_hints == nil
    type_hints = {}
  out = StringBuffer(512)
  binding = binding_base
  pnames = []
  param_renames = {}
  atomic_buffers = {}
  body = node.body
  abi = 0
  while abi < body.size()
    wgsl_collect_atomic_buffers(body[abi], atomic_buffers)
    abi += 1
  pi = 0
  while pi < params.size()
    p = params[pi]
    pname = p.name
    binding_name = "tungsten_internal_bind_" + name + "_" + pname
    param_renames[pname] = binding_name
    ptype = type_hints[pname]
    space = gpu_param_address_space(node, pname, ptype, true)
    pnames.push(pname)
    arr_elt = msl_array_elt_type(ptype)
    out << "@group(0) @binding("
    out << binding.to_s()
    out << ") "
    if arr_elt != nil
      wgsl_elt = wgsl_elt_name(arr_elt)
      if !(wgsl_elt in ("f32" "i32" "u32"))
        gpu_kernel_error(node, "storage parameter `" + pname + "` type `" + ptype.to_s() + "` is not supported by the WGSL dialect")
      if space == "constant"
        out << "var<storage, read> "
      else
        out << "var<storage, read_write> "
      out << binding_name
      out << " : array<"
      if atomic_buffers[pname] == true
        if wgsl_elt != "i32"
          gpu_kernel_error(node, "WGSL atomics require an i32[] buffer (parameter `" + pname + "` is `" + ptype.to_s() + "`)")
        out << "atomic<i32>"
      else
        out << wgsl_elt
      out << ">;\n"
    else
      sc = wgsl_scalar(ptype)
      if sc == nil
        gpu_kernel_error(node, "parameter `" + pname + "` type `" + ptype.to_s() + "` is not supported by the WGSL dialect")
      out << "var<uniform> "
      out << binding_name
      out << " : "
      out << sc
      out << ";\n"
    binding = binding + 1
    pi += 1
  out << "@compute @workgroup_size(256)\n"
  out << "fn "
  out << name
  out << "(@builtin(global_invocation_id) tungsten_internal_tid : vec3<u32>,\n"
  out << "   @builtin(local_invocation_id) tungsten_internal_tid_local : vec3<u32>,\n"
  out << "   @builtin(workgroup_id) tungsten_internal_group_id : vec3<u32>) {\n"
  ctx = {node: node, kernel_name: name, var_types: {}, params: pnames, indent: 1, dialect: "wgsl", renames: param_renames, shared_decls: StringBuffer(128), array_bounds: gpu_param_array_bounds(pnames, type_hints), address_spaces: gpu_param_address_spaces(node, pnames, type_hints, true), shared_bytes: 0}
  declared = {}
  body_out = StringBuffer(256)
  bi = 0
  while bi < body.size()
    if !wgsl_stmt(body_out, ctx, body[bi], declared)
      gpu_kernel_error(node, "statement `" + ast_kind(body[bi]).to_s() + "` is outside the portable WGSL subset")
    bi += 1
  if ctx[:shared_decls].size() > 0
    with_shared = StringBuffer(out.size() + ctx[:shared_decls].size() + body_out.size() + 8)
    with_shared << ctx[:shared_decls].to_s()
    with_shared << out.to_s()
    with_shared << body_out.to_s()
    with_shared << "}\n"
    return with_shared.to_s()
  out << body_out.to_s()
  out << "}\n"
  out.to_s()

-> emit_gpu_kernels_wgsl(kernels, only_index = nil)
  if kernels == nil || kernels.size() == 0
    return nil
  out = StringBuffer(1024)
  out << "// Tungsten @gpu kernel output (WGSL dialect) — do not edit by hand\n\n"
  i = 0
  binding_base = 0
  while i < kernels.size()
    # Device helper functions remain outside the portable WGSL path.
    if gpu_fn_return_type(kernels[i]) == nil
      if only_index == nil || only_index == i
        out << emit_kernel_wgsl(kernels[i], binding_base)
        out << "\n"
      binding_base += kernels[i].params.size()
    i += 1
  out.to_s()
# ---- SPIR-V / Vulkan GLSL emission (fourth GPU dialect) ----

-> emit_gpu_kernels_spirv(kernels, only_index = nil)
  if kernels == nil || kernels.size() == 0
    return nil
  out = StringBuffer(1024)
  out << "// Tungsten @gpu kernel output (SPIR-V / Vulkan GLSL dialect) — do not edit by hand\n"
  out << "#version 450\n\n"
  i = 0
  binding_base = 0
  while i < kernels.size()
    if gpu_fn_return_type(kernels[i]) == nil
      if only_index == nil || only_index == i
        out << "layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;\n"
        params = kernels[i].params
        p = 0
        while p < params.size()
          pname = "" + params[p].name
          out << "layout(std430, set = 0, binding = " + (binding_base + p).to_s() + ") buffer Block_" + pname + " { float " + pname + "[]; };\n"
          p += 1
        out << "void main() {\n"
        out << "  uint thread_x = gl_GlobalInvocationID.x;\n"
        out << "}\n\n"
      binding_base += kernels[i].params.size()
    i += 1
  out.to_s()

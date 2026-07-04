# core/tensor.w — N-dimensional Tensor that shares memory with a Metal 4
# MTLTensor.
#
# One shared MTLBuffer, three faces over the SAME bytes (zero copy):
#   .buffer        — the MTLBuffer (legacy buffer kernels + MTL4 residency)
#   .metal_tensor  — an MTLTensor view (MTL4 cooperative-tensor kernels)
#   .at / .set     — CPU element access (unified memory — the GPU sees writes)
#
# Because every Metal buffer is MTLResourceStorageModeShared (unified memory),
# the same allocation is reachable from the CPU, as an MTLBuffer, and as an
# MTLTensor simultaneously — that is the whole point of this type.
#
# dtype is a runtime field (METAL_DTYPE_*), not a `Tensor<T>` generic: it
# mirrors MTLTensor.dataType and handles quantized formats (bf16, int4) that
# have no clean Tungsten scalar. Shape is row-major, outer→inner (NumPy/
# PyTorch). Strides are in elements.
#
# Compiled-only: factories are class-side methods (`-> .zeros`), which the
# tree-walking interpreter doesn't dispatch — run Tensor programs via `-o`.
# Lifetime: like the rest of core/metal.w, v1 leaks the Metal handle; GC
# finalizer integration is a runtime TODO.

use core/metal
use core/blas

# ---- GPU linear-layer matmul via Metal 4 cooperative tensors --------------
#
# The f16_matmul_m4 kernel computes C[M,N] = A[M,K] · B[N,K]^T (the ML weight
# convention) using mpp::tensor_ops::matmul2d on `tensor<...>` params bound from
# the host argument table — i.e. it consumes Tensor's `.metal_tensor` faces for
# COMPUTE, the payoff of "plays nicely with the Metal 4 tensor". `\[\[ \]\]`
# escapes the attribute syntax from Tungsten string interpolation.

-> build_tensor_m4_kernel(elem, kname)
  s = StringBuffer(2048)
  s << "#include <metal_stdlib>\n"
  s << "#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>\n"
  s << "using namespace metal;\n"
  s << "using namespace mpp;\n"
  s << "using namespace mpp::tensor_ops;\n"
  s << "kernel void " + kname + "(\n"
  s << "    tensor<device " + elem + ", dextents<int32_t, 2>> A \[\[buffer(0)\]\],\n"
  s << "    tensor<device " + elem + ", dextents<int32_t, 2>> B \[\[buffer(1)\]\],\n"
  s << "    tensor<device float, dextents<int32_t, 2>> C \[\[buffer(2)\]\],\n"
  s << "    uint2 tgid \[\[threadgroup_position_in_grid\]\]\n"
  s << ") {\n"
  s << "    constexpr auto desc = matmul2d_descriptor(\n"
  s << "        64, 32, static_cast<int>(metal::dynamic_extent), false, true, false);\n"
  s << "    matmul2d<desc, execution_simdgroups<4>> op;\n"
  s << "    auto mA = A.slice<dynamic_length_v<int32_t>, 64>(0, tgid.x * 64);\n"
  s << "    auto mB = B.slice<dynamic_length_v<int32_t>, 32>(0, tgid.y * 32);\n"
  s << "    auto mC = C.slice<32, 64>(tgid.y * 32, tgid.x * 64);\n"
  s << "    op.run(mA, mB, mC);\n"
  s << "}\n"
  s.to_s()

# Lazy singleton: built on first .linear call (NOT at module load — a CPU-only
# Tensor program shouldn't compile an MTL4 pipeline at startup). Mutable holder
# because top-level globals can't be reassigned from a fn.
TENSOR_M4 = {}
-> tensor_m4_state(dt)
  key = :f16
  elem = "half"
  kname = "f16_matmul_m4"
  if dt == 121
    key = :bf16
    elem = "bfloat"
    kname = "bf16_matmul_m4"
  if TENSOR_M4[key] == nil
    device = metal_device()
    compiler = metal4_compiler(device)
    queue = metal4_queue(device)
    alloc = metal4_allocator(device)
    lib = metal_compile_source(device, build_tensor_m4_kernel(elem, kname))
    pipe = metal4_pipeline(compiler, lib, kname, 128, 1, 1)
    TENSOR_M4[key] = {:device => device, :queue => queue, :alloc => alloc, :pipe => pipe}
  TENSOR_M4[key]

# ---- GPU elementwise (legacy buffer kernel) -------------------------------
#
# A generic 1-D f32 elementwise kernel over the buffer faces: one thread per
# element, op selected by an int (0=add 1=sub 2=mul 3=div). Routes the
# same-shape contiguous f32 path here; broadcast / other dtypes / small sizes
# stay on the CPU reference. `\[ \]` escapes both attribute syntax and MSL
# array indexing from Tungsten string interpolation.

-> build_tensor_ew_kernel
  s = StringBuffer(1024)
  s << "#include <metal_stdlib>\n"
  s << "using namespace metal;\n"
  s << "kernel void elementwise_f32(\n"
  s << "    device const float* a \[\[buffer(0)\]\],\n"
  s << "    device const float* b \[\[buffer(1)\]\],\n"
  s << "    device float* c \[\[buffer(2)\]\],\n"
  s << "    constant int& op \[\[buffer(3)\]\],\n"
  s << "    constant int& n \[\[buffer(4)\]\],\n"
  s << "    uint gid \[\[thread_position_in_grid\]\]\n"
  s << ") {\n"
  s << "    if (gid >= uint(n)) return;\n"
  s << "    float av = a\[gid\];\n"
  s << "    float bv = b\[gid\];\n"
  s << "    float r = av + bv;\n"
  s << "    if (op == 1) r = av - bv;\n"
  s << "    else if (op == 2) r = av * bv;\n"
  s << "    else if (op == 3) r = av / bv;\n"
  s << "    c\[gid\] = r;\n"
  s << "}\n"
  s << "kernel void softmax_rows_f32(\n"
  s << "    device const float* x \[\[buffer(0)\]\],\n"
  s << "    device float* y \[\[buffer(1)\]\],\n"
  s << "    constant int& rows \[\[buffer(2)\]\],\n"
  s << "    constant int& cols \[\[buffer(3)\]\],\n"
  s << "    uint gid \[\[thread_position_in_grid\]\]\n"
  s << ") {\n"
  s << "    if (gid >= uint(rows)) return;\n"
  s << "    device const float* row = x + gid * cols;\n"
  s << "    device float* out = y + gid * cols;\n"
  s << "    float mx = row\[0\];\n"
  s << "    for (int j = 1; j < cols; j++) mx = max(mx, row\[j\]);\n"
  s << "    float sm = 0.0f;\n"
  s << "    for (int j = 0; j < cols; j++) { float e = exp(row\[j\] - mx); out\[j\] = e; sm += e; }\n"
  s << "    for (int j = 0; j < cols; j++) out\[j\] /= sm;\n"
  s << "}\n"
  s.to_s()

TENSOR_EW = {}
-> tensor_ew_state
  if TENSOR_EW[:state] == nil
    device = metal_device()
    queue = metal_queue(device)
    lib = metal_compile_source(device, build_tensor_ew_kernel())
    pipe = metal_pipeline(lib, "elementwise_f32")
    softmax_pipe = metal_pipeline(lib, "softmax_rows_f32")
    TENSOR_EW[:state] = {:device => device, :queue => queue, :pipe => pipe, :softmax_pipe => softmax_pipe}
  TENSOR_EW[:state]

+ Tensor
  - data
    rw device
    rw buffer
    rw dtype
    rw shape
    rw strides
    rw offset

  # dtype accessors — mirror METAL_DTYPE_* in core/metal.w (values validated by
  # the m4_matmul_bench MTLTensor path). Class-side so `Tensor.f32` reads well
  # without the caller needing `use core/metal`.
  -> .f32 3
  -> .f16 16
  -> .bf16 121
  -> .i32 29
  -> .u32 33
  -> .i16 37
  -> .i8 45
  -> .u8 49

  # Primitive constructor — binds all six fields. Prefer the factories below.
  -> new(@device, @buffer, @dtype, @shape, @strides, @offset)

  # ---- factories (class-side) ----

  # Allocate a fresh zero-initialized shared buffer sized for `shape`.
  # Strides are ALWAYS materialized explicit (packed, row-major) — see the note
  # on flat_index for why we never carry empty strides.
  -> .zeros(device, dtype, shape)
    nbytes = Tensor.byte_size(dtype, shape)
    buffer = metal_buffer(device, nbytes)
    Tensor.new(device, buffer, dtype, shape, Tensor.packed_strides(shape), 0)

  # Wrap existing storage (e.g. mmap'd weights, another buffer). `offset` and
  # `strides` are in elements; pass `[]` to default to contiguous row-major.
  -> .wrap(buffer, dtype, shape, strides, offset)
    st = strides
    if st.size() == 0
      st = Tensor.packed_strides(shape)
    Tensor.new(nil, buffer, dtype, shape, st, offset)

  # Zero-copy wrap of a page-aligned Tungsten array (metal_array): CPU writes
  # to `arr` and GPU reads share the same bytes.
  -> .from_array(device, arr, dtype, shape)
    buffer = metal_buffer_for(device, arr)
    Tensor.new(device, buffer, dtype, shape, Tensor.packed_strides(shape), 0)

  # ---- shape helpers (class-side) ----

  # Bit width of a dtype (int4 = 4). Used for nbytes / stride / offset math.
  -> .dtype_bits(dtype)
    case dtype
      143 => 4
      144 => 4
      45  => 8
      49  => 8
      16  => 16
      121 => 16
      37  => 16
      3   => 32
      29  => 32
      33  => 32
      => 32

  -> .elem_count(shape)
    n = 1
    i = 0
    while i < shape.size()
      n = n * shape[i]
      i = i + 1
    n

  -> .byte_size(dtype, shape)
    (Tensor.elem_count(shape) * Tensor.dtype_bits(dtype)) / 8

  # Tightly-packed (contiguous, row-major) element strides for `shape`. Built
  # with [] + .push — never Array.new(n, fill), which is malformed in thin
  # programs.
  -> .packed_strides(shape)
    s = []
    r = shape.size()
    i = 0
    while i < r
      acc = 1
      j = i + 1
      while j < r
        acc = acc * shape[j]
        j = j + 1
      s = s.push(acc)
      i = i + 1
    s

  # ---- metadata ----

  -> rank
    shape.size()

  -> size
    Tensor.elem_count(shape)

  -> nbytes
    (self.size * Tensor.dtype_bits(dtype)) / 8

  -> bytes_per_element
    Tensor.dtype_bits(dtype) / 8

  # True when the (always-explicit) strides equal the packed row-major strides.
  -> contiguous?
    ps = Tensor.packed_strides(shape)
    same = true
    i = 0
    while i < strides.size()
      if strides[i] != ps[i]
        same = false
      i = i + 1
    same

  # ---- views (zero-copy; alias the same buffer) ----

  # Same buffer, new shape — element count must match and the source must be
  # contiguous (strided views must be copied contiguous first, a Phase B+ op).
  -> reshape(new_shape)
    if Tensor.elem_count(new_shape) != self.size
      raise "Tensor.reshape: element count mismatch"
    if !self.contiguous?
      raise "Tensor.reshape: requires a contiguous tensor"
    Tensor.new(device, buffer, dtype, new_shape, Tensor.packed_strides(new_shape), offset)

  # Reorder axes: new axis i is the old axis axes[i]. Carries explicit strides,
  # so the result is a (possibly non-contiguous) strided view — still a valid
  # MTLTensor and CPU-addressable.
  -> permute(axes)
    es = strides
    new_shape = []
    new_strides = []
    i = 0
    while i < axes.size()
      ax = axes[i]
      new_shape = new_shape.push(shape[ax])
      new_strides = new_strides.push(es[ax])
      i = i + 1
    Tensor.new(device, buffer, dtype, new_shape, new_strides, offset)

  # Reverse all axes (2-D matrix transpose generalizes to N-D).
  -> transpose
    axes = []
    i = shape.size() - 1
    while i >= 0
      axes = axes.push(i)
      i = i - 1
    self.permute(axes)

  # Narrow one axis to [start, start+len): offset shifts by start*stride[axis].
  -> slice(axis, start, len)
    es = strides
    new_shape = []
    i = 0
    while i < shape.size()
      if i == axis
        new_shape = new_shape.push(len)
      else
        new_shape = new_shape.push(shape[i])
      i = i + 1
    Tensor.new(device, buffer, dtype, new_shape, es, offset + start * es[axis])

  # A contiguous (packed row-major) copy. Returns self if already contiguous
  # (NumPy/PyTorch semantics); otherwise materializes a fresh packed Tensor —
  # needed before a transposed/permuted view can become an MTLTensor or be
  # reshaped.
  -> contiguous
    if self.contiguous?
      self
    else
      result = Tensor.zeros(device, dtype, shape)
      n = self.size
      fi = 0
      while fi < n
        c = Tensor.unravel(fi, shape)
        result.set(c, self.at(c))
        fi = fi + 1
      result

  # ---- faces ----

  # .buffer is the field accessor — the MTLBuffer, for legacy buffer-binding
  # kernels and the MTL4 residency set.

  # An MTLTensor view aliasing this tensor's bytes, for MTL4 argument tables.
  # Rebuilt each call in v0 (a cheap descriptor wrap); caching is a Phase B
  # optimization.
  -> metal_tensor
    if strides[strides.size() - 1] != 1
      raise "Tensor.metal_tensor: innermost axis is not unit-stride (a transposed/permuted view) — call .contiguous() first"
    metal_tensor_nd(buffer, dtype, shape, strides, offset * self.bytes_per_element)

  # ---- CPU element access (unified memory) ----

  # Flat element index for a coordinate Array (length = rank). Strides are
  # always explicit — factories materialize packed strides via
  # Tensor.packed_strides — so this is one straight-line accumulation that
  # treats contiguous tensors and strided views uniformly (the representation
  # NumPy/PyTorch use). offset + Σ indices[k]·strides[k].
  -> flat_index(indices)
    flat = offset
    i = 0
    while i < indices.size()
      flat = flat + indices[i] * strides[i]
      i = i + 1
    flat

  -> at(indices)
    fi = self.flat_index(indices)
    self.read_flat(fi)

  -> set(indices, value)
    fi = self.flat_index(indices)
    self.write_flat(fi, value)

  # dtype-dispatched scalar read/write at a flat element index. v0 CPU path
  # covers f32 / f16 / bf16 / i32; other dtypes raise (GPU kernels still work).
  -> read_flat(i)
    case dtype
      3   => metal_buffer_read_f32(buffer, i)
      16  => metal_buffer_read_f16(buffer, i)
      121 => metal_buffer_read_bf16(buffer, i)
      29  => metal_buffer_read_i32(buffer, i)
      => raise "Tensor.read_flat: dtype " + dtype.to_s + " has no CPU path (f32/f16/bf16/i32 only)"

  -> write_flat(i, value)
    case dtype
      3   => metal_buffer_write_f32(buffer, i, value)
      16  => metal_buffer_write_f16(buffer, i, value)
      121 => metal_buffer_write_bf16(buffer, i, value)
      29  => metal_buffer_write_i32(buffer, i, value)
      => raise "Tensor.write_flat: dtype " + dtype.to_s + " has no CPU path (f32/f16/bf16/i32 only)"

  # ---- matmul ----

  # 2-D matrix multiply: [M,K] · [K,N] → a fresh contiguous [M,N] Tensor.
  # v0 routes to Accelerate `sgemm` (f32, links by default) over zero-copy
  # array views of the operands' shared buffers — no copy, no MLX dependency.
  # GPU (MLX/MTL4) routing is a follow-up (blocked on default-link of those
  # bridges, not on this design).
  -> matmul(other)
    if dtype != 3
      raise "Tensor.matmul: v0 supports f32 only (dtype " + dtype.to_s + ")"
    if other.dtype != 3
      raise "Tensor.matmul: operand dtype mismatch"
    if self.rank != 2 || other.rank != 2
      raise "Tensor.matmul: both operands must be rank-2"
    if !self.contiguous?
      return self.contiguous.matmul(other)
    if !other.contiguous?
      return self.matmul(other.contiguous)
    m = shape[0]
    k = shape[1]
    if other.shape[0] != k
      raise "Tensor.matmul: inner dimensions disagree"
    n = other.shape[1]
    result = Tensor.zeros(device, 3, [m, n])
    av = metal_buffer_view(buffer, -32, m * k)
    bv = metal_buffer_view(other.buffer, -32, k * n)
    cv = metal_buffer_view(result.buffer, -32, m * n)
    sgemm(av, bv, cv, m, n, k)
    result

  -> mm(other)
    self.matmul(other)

  # ---- elementwise + broadcasting (CPU reference, v0) ----
  #
  # `*` is ELEMENTWISE (Hadamard) — matmul is the named `.matmul`/`.mm`, matching
  # NumPy. Broadcasting follows NumPy: right-align shapes; each axis must be
  # equal or one side is 1 (the 1 stretches). This is a boxed CPU loop —
  # O(size·rank) — a correct reference; GPU elementwise kernels are a follow-up.

  # Broadcasted output shape, or raise if incompatible.
  -> .broadcast_shape(sa, sb)
    ra = sa.size()
    rb = sb.size()
    r = ra
    if rb > r
      r = rb
    out = []
    k = 0
    while k < r
      da = 1
      if k >= r - ra
        da = sa[k - (r - ra)]
      db = 1
      if k >= r - rb
        db = sb[k - (r - rb)]
      dim = da
      if da == db
        dim = da
      elsif da == 1
        dim = db
      elsif db == 1
        dim = da
      else
        raise "Tensor: shapes not broadcast-compatible"
      out = out.push(dim)
      k = k + 1
    out

  # Row-major unravel: flat index → coordinate Array (outer→inner).
  -> .unravel(flat, shape)
    ps = Tensor.packed_strides(shape)
    coord = []
    rem = flat
    k = 0
    while k < shape.size()
      coord = coord.push(rem / ps[k])
      rem = rem % ps[k]
      k = k + 1
    coord

  # Map an output coordinate to an input's coordinate under broadcasting:
  # right-aligned, and an input axis of size 1 contributes index 0.
  -> .broadcast_coord(ocoord, in_shape, out_rank)
    ra = in_shape.size()
    off = out_rank - ra
    coord = []
    ai = 0
    while ai < ra
      if in_shape[ai] == 1
        coord = coord.push(0)
      else
        coord = coord.push(ocoord[ai + off])
      ai = ai + 1
    coord

  # kind: 0=add 1=sub 2=mul 3=div
  -> binop(other, kind)
    if dtype != other.dtype
      raise "Tensor.binop: dtype mismatch"
    oshape = Tensor.broadcast_shape(shape, other.shape)
    result = Tensor.zeros(device, dtype, oshape)
    r = oshape.size()
    total = Tensor.elem_count(oshape)
    fi = 0
    while fi < total
      ocoord = Tensor.unravel(fi, oshape)
      av = self.at(Tensor.broadcast_coord(ocoord, shape, r))
      bv = other.at(Tensor.broadcast_coord(ocoord, other.shape, r))
      rv = av + bv
      if kind == 1
        rv = av - bv
      elsif kind == 2
        rv = av * bv
      elsif kind == 3
        rv = av / bv
      result.set(ocoord, rv)
      fi = fi + 1
    result

  -> .shapes_equal?(a, b)
    if a.size() != b.size()
      return false
    i = 0
    while i < a.size()
      if a[i] != b[i]
        return false
      i = i + 1
    true

  # GPU-eligible: same-shape contiguous f32, large enough that a GPU dispatch
  # beats the CPU loop. Everything else (broadcast, other dtypes, small) stays
  # on the CPU reference in binop.
  -> gpu_ew_eligible?(other)
    if dtype != 3 || other.dtype != 3
      return false
    if !self.contiguous? || !other.contiguous?
      return false
    if !Tensor.shapes_equal?(shape, other.shape)
      return false
    self.size >= 4096

  # Row-wise softmax on the GPU: one thread per row scans for the max,
  # exponentiates, and normalizes — numerically stable, same recipe as the
  # CPU reference. Requires f32, rank 2, contiguous, softmax along axis 1.
  -> gpu_softmax_rows
    st = tensor_ew_state()
    rows = shape[0]
    cols = shape[1]
    result = Tensor.zeros(device, 3, shape)
    rows_buf = metal_buffer(device, 4)
    metal_buffer_write_i32(rows_buf, 0, rows)
    cols_buf = metal_buffer(device, 4)
    metal_buffer_write_i32(cols_buf, 0, cols)
    tg = 64
    n_groups = (rows + tg - 1) / tg
    metal_dispatch_groups(st[:queue], st[:softmax_pipe], [buffer, result.buffer, rows_buf, cols_buf], n_groups, tg)
    result

  -> gpu_binop(other, kind)
    st = tensor_ew_state()
    n = self.size
    result = Tensor.zeros(device, 3, shape)
    op_buf = metal_buffer(device, 4)
    metal_buffer_write_i32(op_buf, 0, kind)
    n_buf = metal_buffer(device, 4)
    metal_buffer_write_i32(n_buf, 0, n)
    tg = 256
    n_groups = (n + tg - 1) / tg
    metal_dispatch_groups(st[:queue], st[:pipe], [buffer, other.buffer, result.buffer, op_buf, n_buf], n_groups, tg)
    result

  # Dispatcher: GPU for the eligible f32 path, CPU reference otherwise.
  -> elementwise(other, kind)
    if self.gpu_ew_eligible?(other)
      self.gpu_binop(other, kind)
    else
      self.binop(other, kind)

  -> +(other)
    self.elementwise(other, 0)
  -> -(other)
    self.elementwise(other, 1)
  -> *(other)
    self.elementwise(other, 2)
  -> /(other)
    self.elementwise(other, 3)

  # Named fallbacks (operators are fine, but these are dispatch-safe and read
  # well in chained pipelines).
  -> add(other)
    self.elementwise(other, 0)
  -> sub(other)
    self.elementwise(other, 1)
  -> mul(other)
    self.elementwise(other, 2)
  -> div(other)
    self.elementwise(other, 3)

  # Scalar multiply (Tensor · number) — kept separate from `*` so the operator
  # isn't overloaded on two operand types (which can hang dispatch).
  -> scale(s)
    result = Tensor.zeros(device, dtype, shape)
    total = self.size
    fi = 0
    while fi < total
      ocoord = Tensor.unravel(fi, shape)
      result.set(ocoord, self.at(ocoord) * s)
      fi = fi + 1
    result

  # ---- whole-tensor reductions (CPU reference) ----

  -> sum
    acc = ~0.0
    total = self.size
    fi = 0
    while fi < total
      acc = acc + self.at(Tensor.unravel(fi, shape))
      fi = fi + 1
    acc

  -> mean
    self.sum / self.size.to_f

  -> max
    total = self.size
    best = self.at(Tensor.unravel(0, shape))
    fi = 1
    while fi < total
      v = self.at(Tensor.unravel(fi, shape))
      if v > best
        best = v
      fi = fi + 1
    best

  # ---- axis reductions (reduce one axis away; needed for softmax/layernorm) ----
  # Distinct names rather than overloading sum/0 vs sum/1 — keeps method dispatch
  # unambiguous. Result drops `axis` (keepdims=false).

  # Build an input coord by inserting `val` at position `axis` of an
  # output coord (which has one fewer dimension).
  -> .insert_axis(coord, axis, val)
    out = []
    k = 0
    ci = 0
    while k < coord.size() + 1
      if k == axis
        out = out.push(val)
      else
        out = out.push(coord[ci])
        ci = ci + 1
      k = k + 1
    out

  # Shape with `axis` removed.
  -> drop_axis_shape(axis)
    oshape = []
    k = 0
    while k < shape.size()
      if k != axis
        oshape = oshape.push(shape[k])
      k = k + 1
    oshape

  -> sum_axis(axis)
    if axis < 0 || axis >= self.rank
      raise "Tensor.sum_axis: axis out of range"
    oshape = self.drop_axis_shape(axis)
    result = Tensor.zeros(device, dtype, oshape)
    axis_len = shape[axis]
    total = Tensor.elem_count(oshape)
    fi = 0
    while fi < total
      ocoord = Tensor.unravel(fi, oshape)
      acc = ~0.0
      a = 0
      while a < axis_len
        acc = acc + self.at(Tensor.insert_axis(ocoord, axis, a))
        a = a + 1
      result.set(ocoord, acc)
      fi = fi + 1
    result

  -> max_axis(axis)
    if axis < 0 || axis >= self.rank
      raise "Tensor.max_axis: axis out of range"
    oshape = self.drop_axis_shape(axis)
    result = Tensor.zeros(device, dtype, oshape)
    axis_len = shape[axis]
    total = Tensor.elem_count(oshape)
    fi = 0
    while fi < total
      ocoord = Tensor.unravel(fi, oshape)
      best = self.at(Tensor.insert_axis(ocoord, axis, 0))
      a = 1
      while a < axis_len
        v = self.at(Tensor.insert_axis(ocoord, axis, a))
        if v > best
          best = v
        a = a + 1
      result.set(ocoord, best)
      fi = fi + 1
    result

  -> mean_axis(axis)
    r = self.sum_axis(axis)
    r.scale(~1.0 / shape[axis].to_f)

  # ---- GPU linear layer (Metal 4 cooperative tensors) ----
  #
  # x.linear(weight): x is [M,K] f16, weight is [N,K] f16 (the ML weight layout,
  # out×in) → fresh [M,N] f32 = x · weight^T, computed on the GPU through the
  # `.metal_tensor` faces of x, weight, and the result. The buffers (residency)
  # and the tensors (argument table) of ONE allocation each are bound into a
  # single MTL4 dispatch — the same share-and-both property Phase A proved, now
  # driving real compute.
  -> linear(weight)
    if dtype != 16 && dtype != 121
      raise "Tensor.linear: x must be f16 or bf16"
    if weight.dtype != dtype
      raise "Tensor.linear: weight dtype must match x"
    if self.rank != 2 || weight.rank != 2
      raise "Tensor.linear: operands must be rank-2"
    if !self.contiguous?
      return self.contiguous.linear(weight)
    if !weight.contiguous?
      return self.linear(weight.contiguous)
    m = shape[0]
    k = shape[1]
    if weight.shape[1] != k
      raise "Tensor.linear: weight must be [N, K] with matching K"
    n = weight.shape[0]
    st = tensor_m4_state(dtype)
    result = Tensor.zeros(device, 3, [m, n])
    argtable = metal4_argtable(device, 3)
    metal4_argtable_set_tensor(argtable, 0, self.metal_tensor)
    metal4_argtable_set_tensor(argtable, 1, weight.metal_tensor)
    metal4_argtable_set_tensor(argtable, 2, result.metal_tensor)
    resources = [buffer, weight.buffer, result.buffer]
    n_tg_x = (m + 63) / 64
    n_tg_y = (n + 31) / 32
    metal4_dispatch_groups_3d(st[:queue], st[:alloc], st[:pipe], argtable, resources, 0, n_tg_x, n_tg_y, 1, 128, 1, 1)
    result

  # ---- unary elementwise (CPU reference) ----
  # Dedicated straight-line loops (a shared kind-dispatched loop with nested
  # ifs inside elsif branches miscompiled — see project memory).

  -> neg
    result = Tensor.zeros(device, dtype, shape)
    n = self.size
    fi = 0
    while fi < n
      c = Tensor.unravel(fi, shape)
      result.set(c, ~0.0 - self.at(c))
      fi = fi + 1
    result

  -> relu
    result = Tensor.zeros(device, dtype, shape)
    n = self.size
    fi = 0
    while fi < n
      c = Tensor.unravel(fi, shape)
      v = self.at(c)
      if v < ~0.0
        v = ~0.0
      result.set(c, v)
      fi = fi + 1
    result

  -> abs
    result = Tensor.zeros(device, dtype, shape)
    n = self.size
    fi = 0
    while fi < n
      c = Tensor.unravel(fi, shape)
      result.set(c, self.at(c).abs)
      fi = fi + 1
    result

  -> sqrt
    result = Tensor.zeros(device, dtype, shape)
    n = self.size
    fi = 0
    while fi < n
      c = Tensor.unravel(fi, shape)
      result.set(c, self.at(c).sqrt)
      fi = fi + 1
    result

  -> square
    result = Tensor.zeros(device, dtype, shape)
    n = self.size
    fi = 0
    while fi < n
      c = Tensor.unravel(fi, shape)
      v = self.at(c)
      result.set(c, v * v)
      fi = fi + 1
    result

  -> exp
    result = Tensor.zeros(device, dtype, shape)
    n = self.size
    fi = 0
    while fi < n
      c = Tensor.unravel(fi, shape)
      result.set(c, Math.exp(self.at(c)))
      fi = fi + 1
    result

  # ---- softmax (numerically stable: subtract the per-slice max) ----
  # softmax over `axis`: result has the same shape; each slice along `axis`
  # sums to 1. Direct implementation (no keepdims/broadcast gymnastics).
  -> softmax(axis)
    if axis < 0 || axis >= self.rank
      raise "Tensor.softmax: axis out of range"
    # GPU path: row-wise f32 softmax (one thread per row) — the attention
    # shape. Anything else falls through to the CPU reference.
    if dtype == 3 && self.rank == 2 && axis == 1 && self.contiguous?
      return self.gpu_softmax_rows()
    result = Tensor.zeros(device, dtype, shape)
    axis_len = shape[axis]
    oshape = self.drop_axis_shape(axis)
    outer = Tensor.elem_count(oshape)
    fi = 0
    while fi < outer
      ocoord = Tensor.unravel(fi, oshape)
      mx = self.at(Tensor.insert_axis(ocoord, axis, 0))
      a = 1
      while a < axis_len
        v = self.at(Tensor.insert_axis(ocoord, axis, a))
        if v > mx
          mx = v
        a = a + 1
      sm = ~0.0
      a = 0
      while a < axis_len
        ic = Tensor.insert_axis(ocoord, axis, a)
        e = Math.exp(self.at(ic) - mx)
        result.set(ic, e)
        sm = sm + e
        a = a + 1
      a = 0
      while a < axis_len
        ic = Tensor.insert_axis(ocoord, axis, a)
        result.set(ic, result.at(ic) / sm)
        a = a + 1
      fi = fi + 1
    result

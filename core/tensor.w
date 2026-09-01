# core/tensor.w — N-dimensional dense Tensor (language type).
#
# Naming:
#   Tensor   — language-level multi-D array (shape/strides/dtype/unit + ops)
#   WTensor  — C struct header in runtime/runtime.h for the CPU storage face
#              (ebits, rank, offset, shape, strides, storage pointer). Same
#              role as WArray for 1-D: the boxed runtime layout, not a second
#              user-facing type. Factories: Tensor.w_zeros / w_at / w_view.
#
# Faces over shared bytes (Metal path, zero-copy when unified memory):
#   .buffer        — MTLBuffer (legacy buffer kernels + MTL4 residency)
#   .metal_tensor  — MTLTensor view (MTL4 cooperative-tensor kernels)
#   .at / .set     — CPU element access
#   :cpu buffer    — typed WArray (f32/f64) for Metal-free programs
#
# dtype and unit are runtime fields. `Tensor<f64, m/s>.zeros(shape)` is compiler
# syntax for the checked `Tensor.zeros_unit("f64", "m/s", shape)` factory; it
# does not monomorphize a class for every open-ended unit expression. Shape is
# row-major, outer→inner (NumPy/PyTorch). Strides are in elements.
#
# Compiled-only: factories are class-side methods (`-> .zeros`), which the
# tree-walking interpreter doesn't dispatch — run Tensor programs via `-o`.
# Lifetime: like the rest of core/metal.w, v1 leaks the Metal handle; GC
# finalizer integration is a runtime TODO.

use core/metal

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
  # Tensor is itself a Core storage/backend boundary. Keep these private
  # typed-array allocation and BLAS calls on the class rather than depending
  # on a second `use core/blas` import: Tensor can then be reached through
  # Core's class autoload by a consumer without duplicate transitive loading.
  # Allocation deliberately uses `->`, matching core/blas.w's memoization
  # workaround. These are not a second public BLAS API.
  -> .storage_f32(n)
    ccall("w_array_new_aligned", -32, n)

  -> .storage_f64(n)
    ccall("w_array_new_aligned", -64, n)

  -> .storage_sgemm(a, b, c, m, n, k)
    ccall("w_blas_sgemm_nn", a, b, c, m, n, k)

  -> .storage_dgemm(a, b, c, m, n, k)
    ccall("w_blas_dgemm_nn", a, b, c, m, n, k)

  -> .storage_sgemm_view(a, b, c, m, n, k, ao, bo, ta, tb)
    ccall("w_blas_sgemm_view", a, b, c, m, n, k, ao, bo, ta, tb)

  -> .storage_dgemm_view(a, b, c, m, n, k, ao, bo, ta, tb)
    ccall("w_blas_dgemm_view", a, b, c, m, n, k, ao, bo, ta, tb)

  -> .storage_reduce_view(dtype, a, offset, n, kind)
    ccall("w_blas_reduce_view", dtype, a, offset, n, kind)

  -> .storage_reduce_last(dtype, a, out, offset, rows, cols, kind)
    ccall("w_blas_reduce_last", dtype, a, out, offset, rows, cols, kind)

  -> .storage_unary_view(dtype, a, out, offset, n, kind)
    ccall("w_blas_unary_view", dtype, a, out, offset, n, kind)

  - data
    rw device
    rw buffer
    rw dtype
    rw shape
    rw strides
    rw offset
    rw unit
    # Internal coherence state, never part of Tensor's mutable public surface.
    metal_tensor_cache array

  # dtype accessors — mirror METAL_DTYPE_* in core/metal.w (values validated by
  # the m4_matmul_bench MTLTensor path). Class-side so `Tensor.f32` reads well
  # without the caller needing `use core/metal`.
  -> .f32 3
  # CPU-native f64 marker. Metal has no f64 arithmetic, so a Tensor with this
  # dtype deliberately remains on the CPU path.
  -> .f64 64
  -> .f16 16
  -> .bf16 121
  -> .i32 29
  -> .u32 33
  -> .i16 37
  -> .i8 45
  -> .u8 49

  # Primitive constructors. The six-argument form preserves compatibility for
  # untyped tensors; unit-aware factories and views use the seventh field.
  -> new(@device, @buffer, @dtype, @shape, @strides, @offset)
    @unit = nil
    @metal_tensor_cache = nil

  -> new(@device, @buffer, @dtype, @shape, @strides, @offset, @unit)
    @metal_tensor_cache = nil

  # ---- factories (class-side) ----

  # Allocate a fresh zero-initialized shared buffer sized for `shape`.
  # Strides are ALWAYS materialized explicit (packed, row-major) — see the note
  # on flat_index for why we never carry empty strides.
  #
  # Two overloads:
  #   Tensor.zeros(device, dtype, shape)  — Metal shared buffer (GPU face)
  #   Tensor.zeros(shape)                 — CPU f32 WArray (no Metal)
  #   Tensor.zeros_cpu(dtype, shape)      — CPU f32/f64 typed path
  -> .zeros(device, dtype, shape)
    nbytes = Tensor.byte_size(dtype, shape)
    buffer = metal_buffer(device, nbytes)
    Tensor.new(device, buffer, dtype, shape, Tensor.packed_strides(shape), 0)

  # CPU-only zeros for the numeric dtypes whose WArray access is available to
  # the language Tensor today. Keep this allocator in Core so consumers do not
  # have to reimplement f64_array packing just to use a dense Tensor.
  -> .cpu_zeros(dtype, shape)
    n = Tensor.elem_count(shape)
    arr = Tensor.storage_f32(n)
    if dtype == Tensor.f64
      arr = Tensor.storage_f64(n)
    elsif dtype != Tensor.f32
      raise "Tensor.cpu_zeros: supported CPU dtypes are f32 and f64"
    # Expose full logical length for []; a typed array may initially report
    # size zero even though its pages are allocated.
    i = 0
    while i < n
      arr[i] = ~0.0
      i = i + 1
    Tensor.new(:cpu, arr, dtype, shape, Tensor.packed_strides(shape), 0)

  # CPU-only zeros (f32). Prefer this when Metal is unavailable or unwanted.
  -> .zeros(shape)
    Tensor.cpu_zeros(Tensor.f32, shape)

  # Explicit CPU dtype. Kept under a distinct name because class-side overload
  # selection is not yet reliable between one- and two-argument factories.
  -> .zeros_cpu(dtype, shape)
    Tensor.cpu_zeros(dtype, shape)

  -> .zeros_f32(shape)
    Tensor.zeros(shape)

  # Target of `Tensor<dtype, unit>.zeros(shape)`. Validate both spellings at
  # construction time so typos fail at the source rather than after arithmetic.
  -> .zeros_unit(dtype_name, unit_name, shape)
    # `0<unit>` asks the same generated unit registry used by quantity
    # literals to validate the unit during lowering. The runtime metadata keeps
    # the original readable expression.
    dtype = Tensor.f32
    if dtype_name == "f64"
      dtype = Tensor.f64
    elsif dtype_name != "f32"
      raise "Tensor.zeros_unit: supported CPU dtypes are f32 and f64"
    result = Tensor.cpu_zeros(dtype, shape)
    result.unit = unit_name
    result

  -> .zeros_like(tensor, shape, result_unit)
    if tensor.device == :cpu
      dtype_name = "f32"
      if tensor.dtype == Tensor.f64
        dtype_name = "f64"
      Tensor.zeros_unit(dtype_name, result_unit, shape)
    else
      result = Tensor.zeros(tensor.device, tensor.dtype, shape)
      result.unit = result_unit
      result

  # Unit annotation (nil = untyped). Set at zeros_unit / zeros_like; views
  # and reshape/permute/slice carry the same unit string.
  -> unit
    @unit
  -> unit=(u)
    @unit = u
    self

  # ---- WTensor C-header face (runtime/runtime.h struct WTensor) ----
  # Opaque W_TYPE_WTENSOR handle: shape/strides/offset + f32 storage.
  # Prefer language Tensor for the full API; use these when you need the
  # native multi-D header (views/slices without a Tensor object).
  -> .w_zeros(shape)
    ccall("w_tensor_zeros_f32", shape)

  -> .w_at(t, indices)
    ccall("w_tensor_at_f32", t, indices)

  -> .w_set(t, indices, value)
    ccall("w_tensor_set_f32", t, indices, value)

  -> .w_shape(t)
    ccall("w_tensor_shape", t)

  -> .w_rank(t)
    ccall("w_tensor_rank", t)

  # Zero-copy view: offset in elements from parent origin, new C-contiguous shape.
  -> .w_view(t, offset, shape)
    ccall("w_tensor_view_f32", t, offset, shape)

  # Slice outer axis: t[start:stop, ...]
  -> .w_slice0(t, start, stop)
    ccall("w_tensor_slice0_f32", t, start, stop)

  # Wrap existing storage (e.g. mmap'd weights, another buffer). `offset` and
  # `strides` are in elements; pass `[]` to default to contiguous row-major.
  -> .wrap(buffer, dtype, shape, strides, offset)
    st = strides
    if st.size() == 0
      st = Tensor.packed_strides(shape)
    Tensor.new(nil, buffer, dtype, shape, st, offset)

  # Zero-copy CPU variant of .wrap. This is the public way to give a Tensor
  # existing f32/f64 WArray storage while retaining explicit strides: a
  # row-major [rows, cols] buffer uses [cols, 1], while a column-major one
  # uses [1, rows]. No layout conversion or data copy happens here.
  -> .wrap_cpu(buffer, dtype, shape, strides, offset)
    st = strides
    if st.size() == 0
      st = Tensor.packed_strides(shape)
    Tensor.new(:cpu, buffer, dtype, shape, st, offset)

  # Materialize a numeric rectangular row table into a CPU Tensor. The input
  # is copied once into dense typed storage; views derived from the resulting
  # Tensor remain zero-copy. Callers that already own typed storage should use
  # .wrap_cpu instead.
  -> .from_rows(rows, dtype = Tensor.f32)
    nr = rows.size()
    nc = 0
    nc = rows[0].size() if nr > 0
    i = 0
    while i < nr
      if rows[i].size() != nc
        raise "Tensor.from_rows: rows must be rectangular"
      i = i + 1
    result = Tensor.cpu_zeros(dtype, [nr, nc])
    i = 0
    while i < nr
      j = 0
      while j < nc
        # The result was just allocated packed and CPU-backed, so avoid a
        # coordinate Array plus dynamic .set for every table cell. General
        # strided writes still go through .set elsewhere.
        result.buffer[i * nc + j] = rows[i][j].to_f
        j = j + 1
      i = i + 1
    result

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
      64  => 64
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
      s = s.push(1)
      i = i + 1
    acc = 1
    i = r - 1
    while i >= 0
      s[i] = acc
      acc = acc * shape[i]
      i = i - 1
    s

  # Tightly-packed Fortran/BLAS-style column-major element strides. Storage
  # order is a property of the view, not a different Tensor type; this helper
  # makes the alternative explicit when wrapping externally-owned storage.
  -> .column_major_strides(shape)
    s = []
    acc = 1
    i = 0
    while i < shape.size()
      s = s.push(acc)
      acc = acc * shape[i]
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
    return false if strides.size() != shape.size()
    expected = 1
    i = shape.size() - 1
    while i >= 0
      return false if strides[i] != expected
      expected = expected * shape[i]
      i = i - 1
    true

  # CBLAS can consume a packed rank-2 tensor or its zero-copy transpose.
  # Return 0 for NoTrans, 1 for Trans, and -1 for a layout that needs packing.
  -> blas_layout
    return -1 if self.rank != 2
    return 0 if strides[1] == 1 && strides[0] == shape[1]
    return 1 if strides[0] == 1 && strides[1] == shape[0]
    -1

  # Numeric rank-2 Tensor as fresh nested rows. This is deliberately a copy:
  # Array rows cannot carry Tensor's offset/stride aliasing contract. It is a
  # small interoperability boundary for tabular consumers, not a second dense
  # storage system.
  -> to_rows
    if self.rank != 2
      raise "Tensor.to_rows: requires a rank-2 tensor"
    rows = []
    packed_cpu = device == :cpu && self.contiguous?
    i = 0
    while i < shape[0]
      row = []
      j = 0
      while j < shape[1]
        # from_rows/matmul outputs are the common packed CPU case. Read their
        # typed storage directly, but retain the stride-aware route for views
        # (including transpose and column-major wrapping).
        value = nil
        if packed_cpu
          value = buffer[offset + i * shape[1] + j]
        else
          value = self.at([i, j])
        row = row.push(value)
        j = j + 1
      rows = rows.push(row)
      i = i + 1
    rows

  # ---- views (zero-copy; alias the same buffer) ----

  # Same buffer, new shape — element count must match and the source must be
  # contiguous (strided views must be copied contiguous first, a future op).
  -> reshape(new_shape)
    if Tensor.elem_count(new_shape) != self.size
      raise "Tensor.reshape: element count mismatch"
    if !self.contiguous?
      raise "Tensor.reshape: requires a contiguous tensor"
    Tensor.new(device, buffer, dtype, new_shape, Tensor.packed_strides(new_shape), offset, unit)

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
    Tensor.new(device, buffer, dtype, new_shape, new_strides, offset, unit)

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
    Tensor.new(device, buffer, dtype, new_shape, es, offset + start * es[axis], unit)

  # A contiguous (packed row-major) copy. Returns self if already contiguous
  # (NumPy/PyTorch semantics); otherwise materializes a fresh packed Tensor —
  # needed before a transposed/permuted view can become an MTLTensor or be
  # reshaped.
  -> contiguous
    if self.contiguous?
      self
    else
      result = Tensor.zeros_like(self, shape, unit)
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
  # Cache the descriptor face while storage and layout metadata stay equal.
  # The snapshot comparison keeps this coherent even though Tensor's public
  # shape/strides Arrays remain mutable today.
  -> metal_tensor
    if strides[strides.size() - 1] != 1
      raise "Tensor.metal_tensor: innermost axis is not unit-stride (a transposed/permuted view) — call .contiguous() first"
    cached = @metal_tensor_cache
    if cached != nil && cached[1] == buffer && cached[2] == dtype && cached[3] == offset
      if Tensor.shapes_equal?(cached[4], shape) && Tensor.shapes_equal?(cached[5], strides)
        return cached[0]
    face = metal_tensor_nd(buffer, dtype, shape, strides, offset * self.bytes_per_element)
    @metal_tensor_cache = [face, buffer, dtype, offset, shape.dup, strides.dup]
    face

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

  # dtype-dispatched scalar read/write at a flat element index.
  # CPU tensors (device == :cpu) store a typed WArray in buffer.
  # Metal tensors use metal_buffer_read_*.
  -> read_flat(i)
    if device == :cpu
      return buffer[i]
    case dtype
      3   => metal_buffer_read_f32(buffer, i)
      16  => metal_buffer_read_f16(buffer, i)
      121 => metal_buffer_read_bf16(buffer, i)
      29  => metal_buffer_read_i32(buffer, i)
      => raise "Tensor.read_flat: dtype " + dtype.to_s + " has no CPU path (f32/f16/bf16/i32 only)"

  -> write_flat(i, value)
    if device == :cpu
      buffer[i] = value
      return self
    case dtype
      3   => metal_buffer_write_f32(buffer, i, value)
      16  => metal_buffer_write_f16(buffer, i, value)
      121 => metal_buffer_write_bf16(buffer, i, value)
      29  => metal_buffer_write_i32(buffer, i, value)
      => raise "Tensor.write_flat: dtype " + dtype.to_s + " has no CPU path (f32/f16/bf16/i32 only)"

  # ---- matmul ----

  # 2-D matrix multiply: [M,K] · [K,N] → a fresh contiguous [M,N] Tensor.
  # CPU f32/f64 tensors route to CBLAS over their typed-array buffers. Packed
  # matrices, offset slices, and zero-copy transpose views enter GEMM directly;
  # only a general stride pattern is materialized.
  # GPU (MLX/MTL4) routing is a follow-up (blocked on default-link of those
  # bridges, not on this design).
  -> matmul(other)
    if dtype != Tensor.f32 && dtype != Tensor.f64
      raise "Tensor.matmul: supports f32/f64 only (dtype " + dtype.to_s + ")"
    if other.dtype != dtype
      raise "Tensor.matmul: operand dtype mismatch"
    if self.rank != 2 || other.rank != 2
      raise "Tensor.matmul: both operands must be rank-2"
    m = shape[0]
    k = shape[1]
    if other.shape[0] != k
      raise "Tensor.matmul: inner dimensions disagree"
    n = other.shape[1]
    if device == :cpu && other.device == :cpu
      al = self.blas_layout
      bl = other.blas_layout
      return self.contiguous.matmul(other) if al < 0
      return self.matmul(other.contiguous) if bl < 0
      result = Tensor.zeros_cpu(dtype, [m, n])
      if dtype == Tensor.f64
        Tensor.storage_dgemm_view(buffer, other.buffer, result.buffer, m, n, k, offset, other.offset, al, bl)
      else
        Tensor.storage_sgemm_view(buffer, other.buffer, result.buffer, m, n, k, offset, other.offset, al, bl)
      return result
    if !self.contiguous?
      return self.contiguous.matmul(other)
    if !other.contiguous?
      return self.matmul(other.contiguous)
    if dtype == Tensor.f64
      raise "Tensor.matmul: f64 is CPU-only"
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

  -> .same_shape(sa, sb)
    return false if sa.size != sb.size
    k = 0
    while k < sa.size
      return false if sa[k] != sb[k]
      k += 1
    true

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

  # True when the tensor's data is a plain packed row-major CPU buffer
  # starting at element 0 — the layout the vDSP fast lane requires.
  -> packed_cpu?
    return false if device != :cpu
    return false if offset != 0
    ps = Tensor.packed_strides(shape)
    return false if strides.size != ps.size
    k = 0
    while k < ps.size
      return false if strides[k] != ps[k]
      k += 1
    true

  # kind: 0=add 1=sub 2=mul 3=div
  -> binop(other, kind)
    if dtype != other.dtype
      raise "Tensor.binop: dtype mismatch"
    result_unit = Tensor.binop_unit(unit, other.unit, kind)
    # Same-shape packed CPU f32/f64 pairs skip the boxed per-element loop
    # (which allocates a coordinate array per element) and run one vDSP
    # call over the raw buffers — identical arithmetic, identical result
    # layout, ~SIMD-rate instead of ~290 ns/element.
    if (dtype == 3 || dtype == 64) && Tensor.same_shape(shape, other.shape)
      if packed_cpu? && other.packed_cpu?
        fast = Tensor.zeros_like(self, shape, result_unit)
        total = Tensor.elem_count(shape)
        if dtype == 3
          ccall("w_blas_ew_f32", kind, buffer, other.buffer, fast.buffer, total)
        else
          ccall("w_blas_ew_f64", kind, buffer, other.buffer, fast.buffer, total)
        return fast
    oshape = Tensor.broadcast_shape(shape, other.shape)
    result = Tensor.zeros_like(self, oshape, result_unit)
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

  -> .binop_unit(left, right, kind)
    # Addition/subtraction are the dimensional safety boundary. Untyped
    # tensors remain compatible with each other, but never silently mix with a
    # unit-carrying tensor.
    if kind == 0 || kind == 1
      if left != right
        raise "Tensor: cannot add or subtract tensors with different units"
      return left
    if kind == 2
      if left == nil
        return right
      if right == nil
        return left
      return left + "·" + right
    if left == right
      return nil
    if right == nil
      return left
    if left == nil
      return "1/" + right
    left + "/" + right

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
    result = Tensor.zeros_like(self, shape, Tensor.binop_unit(unit, other.unit, kind))
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
  -> add_mut(other)
    total = self.size
    fi = 0
    while fi < total
      ocoord = Tensor.unravel(fi, shape)
      val = self.at(ocoord) + (type(other) == "Tensor" ? other.at(ocoord) : other)
      self.set(ocoord, val)
      fi = fi + 1
    self
  -> sub(other)
    self.elementwise(other, 1)
  -> mul(other)
    self.elementwise(other, 2)
  -> div(other)
    self.elementwise(other, 3)

  # Scalar multiply (Tensor · number) — kept separate from `*` so the operator
  # isn't overloaded on two operand types (which can hang dispatch).
  -> scale(s)
    # `Tensor.zeros(device, ...)` is the Metal-only constructor. Preserve the
    # receiver's storage backend here so CPU tensors never try to treat :cpu as
    # an MTLDevice.
    result = Tensor.zeros_like(self, shape, nil)
    total = self.size
    fi = 0
    while fi < total
      ocoord = Tensor.unravel(fi, shape)
      result.set(ocoord, self.at(ocoord) * s)
      fi = fi + 1
    result

  # ---- whole-tensor reductions (CPU reference) ----

  -> sum
    if device == :cpu && self.contiguous? && (dtype == Tensor.f32 || dtype == Tensor.f64)
      return Tensor.storage_reduce_view(dtype, buffer, offset, self.size, 0)
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
    if total > 0 && device == :cpu && self.contiguous? && (dtype == Tensor.f32 || dtype == Tensor.f64)
      return Tensor.storage_reduce_view(dtype, buffer, offset, total, 1)
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
    result = Tensor.zeros_like(self, oshape, nil)
    axis_len = shape[axis]
    total = Tensor.elem_count(oshape)
    if device == :cpu && self.contiguous? && axis == self.rank - 1 && (dtype == Tensor.f32 || dtype == Tensor.f64)
      Tensor.storage_reduce_last(dtype, buffer, result.buffer, offset, total, axis_len, 0)
      return result
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
    result = Tensor.zeros_like(self, oshape, nil)
    axis_len = shape[axis]
    total = Tensor.elem_count(oshape)
    if axis_len > 0 && device == :cpu && self.contiguous? && axis == self.rank - 1 && (dtype == Tensor.f32 || dtype == Tensor.f64)
      Tensor.storage_reduce_last(dtype, buffer, result.buffer, offset, total, axis_len, 1)
      return result
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
  # single MTL4 dispatch — the same share-and-both property proved earlier, now
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

  -> packed_cpu_unary(kind)
    return nil if device != :cpu || !self.contiguous?
    return nil if dtype != Tensor.f32 && dtype != Tensor.f64
    result = Tensor.zeros_like(self, shape, nil)
    Tensor.storage_unary_view(dtype, buffer, result.buffer, offset, self.size, kind)
    result

  -> neg
    native = self.packed_cpu_unary(0)
    return native if native != nil
    result = Tensor.zeros_like(self, shape, nil)
    n = self.size
    fi = 0
    while fi < n
      c = Tensor.unravel(fi, shape)
      result.set(c, ~0.0 - self.at(c))
      fi = fi + 1
    result

  -> relu
    native = self.packed_cpu_unary(1)
    return native if native != nil
    result = Tensor.zeros_like(self, shape, nil)
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
    native = self.packed_cpu_unary(2)
    return native if native != nil
    result = Tensor.zeros_like(self, shape, nil)
    n = self.size
    fi = 0
    while fi < n
      c = Tensor.unravel(fi, shape)
      result.set(c, self.at(c).abs)
      fi = fi + 1
    result

  -> sqrt
    native = self.packed_cpu_unary(3)
    return native if native != nil
    result = Tensor.zeros_like(self, shape, nil)
    n = self.size
    fi = 0
    while fi < n
      c = Tensor.unravel(fi, shape)
      result.set(c, self.at(c).sqrt)
      fi = fi + 1
    result

  -> square
    native = self.packed_cpu_unary(4)
    return native if native != nil
    result = Tensor.zeros_like(self, shape, nil)
    n = self.size
    fi = 0
    while fi < n
      c = Tensor.unravel(fi, shape)
      v = self.at(c)
      result.set(c, v * v)
      fi = fi + 1
    result

  -> exp
    native = self.packed_cpu_unary(5)
    return native if native != nil
    result = Tensor.zeros_like(self, shape, nil)
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
    result = Tensor.zeros_like(self, shape, nil)
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

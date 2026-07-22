# GPU — kernel dispatch for CUDA, Metal, and ROCm backends
# Provides a unified interface for launching GPU operations across backends.

in Tungsten:Koala

+ GPU
  # Dispatch a matrix multiplication to the best available GPU backend.
  #
  #     GPU.matmul(a_buf, b_buf, m, n, k, device: Device.gpu)
  -> .matmul(a, b, m, n, k, device:)
    case device.kind
    => :cuda  -> CUDA:BLAS.gemm(a, b, m, n, k)
    => :metal -> Metal:MPS.matmul(a, b, m, n, k)
    => :rocm  -> ROCm:BLAS.gemm(a, b, m, n, k)
    => _      -> <! DeviceError, "GPU.matmul requires a GPU device, got [device.kind]"

  # Element-wise operation on GPU buffers.
  -> .elementwise(op, a, b, size, device:)
    case device.kind
    => :cuda  -> CUDA:Kernel.elementwise(op, a, b, size)
    => :metal -> Metal:Compute.elementwise(op, a, b, size)
    => :rocm  -> ROCm:Kernel.elementwise(op, a, b, size)

  # Reduction (sum, max, min) on GPU.
  -> .reduce(op, data, size, device:)
    case device.kind
    => :cuda  -> CUDA:Kernel.reduce(op, data, size)
    => :metal -> Metal:Compute.reduce(op, data, size)
    => :rocm  -> ROCm:Kernel.reduce(op, data, size)

  # Transpose on GPU.
  -> .transpose(data, rows, cols, device:)
    case device.kind
    => :cuda  -> CUDA:Kernel.transpose(data, rows, cols)
    => :metal -> Metal:Compute.transpose(data, rows, cols)
    => :rocm  -> ROCm:Kernel.transpose(data, rows, cols)

  # Matrix inverse via LU decomposition on GPU.
  -> .inverse(data, n, device:)
    case device.kind
    => :cuda  -> CUDA:Solver.getrf_getri(data, n)
    => :metal -> Metal:MPS.inverse(data, n)
    => :rocm  -> ROCm:Solver.getrf_getri(data, n)

  # Eigenvalue decomposition on GPU.
  -> .eig(data, n, device:)
    case device.kind
    => :cuda  -> CUDA:Solver.syevd(data, n)
    => :metal -> Metal:MPS.eigendecomposition(data, n)
    => :rocm  -> ROCm:Solver.syevd(data, n)

  # SVD on GPU.
  -> .svd(data, m, n, device:)
    case device.kind
    => :cuda  -> CUDA:Solver.gesvd(data, m, n)
    => :metal -> Metal:MPS.svd(data, m, n)
    => :rocm  -> ROCm:Solver.gesvd(data, m, n)

  # QR decomposition on GPU.
  -> .qr(data, m, n, device:)
    case device.kind
    => :cuda  -> CUDA:Solver.geqrf(data, m, n)
    => :metal -> Metal:MPS.qr(data, m, n)
    => :rocm  -> ROCm:Solver.geqrf(data, m, n)

  # LU decomposition on GPU.
  -> .lu(data, m, n, device:)
    case device.kind
    => :cuda  -> CUDA:Solver.getrf(data, m, n)
    => :metal -> Metal:MPS.lu(data, m, n)
    => :rocm  -> ROCm:Solver.getrf(data, m, n)

  # Cholesky decomposition on GPU.
  -> .cholesky(data, n, device:)
    case device.kind
    => :cuda  -> CUDA:Solver.potrf(data, n)
    => :metal -> Metal:MPS.cholesky(data, n)
    => :rocm  -> ROCm:Solver.potrf(data, n)

  # Sparse matrix-vector multiplication on GPU.
  -> .spmv(sparse_data, format, x, m, n, nnz, device:)
    case device.kind
    => :cuda  -> CUDA:Sparse.spmv(sparse_data, format, x, m, n, nnz)
    => :metal -> Metal:MPS.spmv(sparse_data, format, x, m, n, nnz)
    => :rocm  -> ROCm:Sparse.spmv(sparse_data, format, x, m, n, nnz)

  # Sparse matrix-matrix multiplication on GPU.
  -> .spmm(sparse_a, fmt_a, b, m, n, k, device:)
    case device.kind
    => :cuda  -> CUDA:Sparse.spmm(sparse_a, fmt_a, b, m, n, k)
    => :metal -> Metal:MPS.spmm(sparse_a, fmt_a, b, m, n, k)
    => :rocm  -> ROCm:Sparse.spmm(sparse_a, fmt_a, b, m, n, k)

  # Synchronize: block until all GPU work completes.
  -> .sync(device:)
    case device.kind
    => :cuda  -> CUDA:Runtime.device_synchronize
    => :metal -> Metal:CommandQueue.commit_and_wait
    => :rocm  -> ROCm:Runtime.device_synchronize

  # --- Backend info ---

  # Query GPU memory usage.
  -> .memory_info(device:)
    case device.kind
    => :cuda  -> CUDA:Runtime.mem_get_info
    => :metal -> { used: Metal:Device.current_allocated, total: device.memory }
    => :rocm  -> ROCm:Runtime.mem_get_info

  # Check if a specific backend is available.
  -> .cuda?   Device.detect; Device.all.any?(-> (d) d.cuda?)
  -> .metal?  Device.detect; Device.all.any?(-> (d) d.metal?)
  -> .rocm?   Device.detect; Device.all.any?(-> (d) d.rocm?)

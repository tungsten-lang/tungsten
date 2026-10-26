# LinAlg — dense linear algebra over nested lists / flat f64 storage.
#
# Matrices are list-of-rows (row-major). Vectors are 1-D lists of Float.
# No Grid type — multi-D dense lives on Tensor (CPU/Metal faces later).
#
# Accelerated paths: core/blas.w (sgemm, sgemv, dgesv, …) when linked.

# Typed policy leaf: dimensions stay in registers and the dynamic LinAlg call
# boundary pays no boxed-arithmetic or secondary method-dispatch cost.
-> linalg_matmul_accelerated_raw(m, k, n) (i64 i64 i64) i64
  return 0 if m <= 0 || k <= 0 || n <= 0

  products = m * k * n
  output_elements = m * n
  input_elements = m * k + k * n
  staged_elements = input_elements + output_elements
  flops = products * 2
  input_bytes = input_elements * 8
  output_bytes = output_elements * 8
  copied_bytes = staged_elements * 8

  # The Accelerate call/allocator floor still dominates when every dimension
  # fits below an 8-wide micro-tile.  The 7^3 public-path probe is scalar-fast;
  # 8^3 is already a clear staged-dgemm win.
  return 0 if m < 8 && k < 8 && n < 8

  if k == 1
    return 0 if m == 1 || n == 1
    return 0 if m < 4 || n < 4
    return 1 if output_bytes >= 8192
    return 0

  if m == 1 || n == 1
    return 0 if flops < 8192
    return 1 if flops * 40 >= copied_bytes * 9
    return 0

  # A two-wide output still exposes the fixed allocator/call floor.  Keep the
  # noisy 96x2x2 band scalar; 128x2x2 is the first robust staged-dgemm win.
  return 0 if (m <= 2 || n <= 2) && products < 512

  return 1 if 4 * flops + output_bytes >= input_bytes + 1536
  0

# A reusable dense LU factorization. The factor and pivot buffers are
# immutable after construction; each solve owns (or is given) a distinct RHS,
# so one factor can safely be shared by callers that do not share outputs.
+ DenseLUFactor
  -> new(@factors, @pivots, @dimension)

  ro :dimension

  # Allocation-free typed-buffer lane. `rhs` and `out` may alias; both must
  # have at least `dimension` elements.
  -> solve_into(rhs, out)
    raise "DenseLUFactor.solve_into: RHS too short" if rhs.size() < @dimension
    raise "DenseLUFactor.solve_into: output too short" if out.size() < @dimension
    ccall("w_array_memmove_f64", rhs, out, @dimension)
    info = ccall("w_blas_dgetrs_rowmajor", @factors, @pivots, out, @dimension)
    raise "DenseLUFactor.solve_into: LAPACK failed with info=" + info.to_s if info != 0
    out

  # List convenience lane. Factorization remains reused; only the RHS/output
  # boundary allocation and conversion occur per solve.
  -> solve(rhs)
    dim = @dimension
    raise "DenseLUFactor.solve: RHS length must equal dimension" if rhs.size() != dim
    out_flat = f64[dim]
    solve_into(rhs, out_flat)
    out = Array.new(dim)
    i = 0 ## i64
    while i < dim
      out[i] = out_flat[i]
      i += 1
    out

  # `rhs` and `out` contain `count` consecutive RHS vectors, each of length
  # dimension. LAPACK consumes that RHS-major layout as a column-major
  # dimension×count matrix and uses its batched triangular kernels.
  -> solve_many_into(rhs, out, count)
    raise "DenseLUFactor.solve_many_into: count must be positive" if count <= 0
    total = @dimension * count
    raise "DenseLUFactor.solve_many_into: RHS too short" if rhs.size() < total
    raise "DenseLUFactor.solve_many_into: output too short" if out.size() < total
    ccall("w_array_memmove_f64", rhs, out, total)
    info = ccall("w_blas_dgetrs_many_rowmajor", @factors, @pivots, out, @dimension, count)
    raise "DenseLUFactor.solve_many_into: LAPACK failed with info=" + info.to_s if info != 0
    out

  -> solve_many(rhses)
    return [] if rhses.size() == 0
    count = rhses.size()
    dim = @dimension
    flat = f64[dim * count]
    r = 0 ## i64
    while r < count
      rhs_r = rhses[r]
      raise "DenseLUFactor.solve_many: RHS length must equal dimension" if rhs_r.size() != dim
      base = (r * dim) ## i64
      i = 0 ## i64
      while i < dim
        flat[base + i] = (rhs_r[i] + ~0.0) ## f64
        i += 1
      r += 1
    solve_many_into(flat, flat, count)
    out = Array.new(count)
    r = 0 ## i64
    while r < count
      row = Array.new(dim)
      base = (r * dim) ## i64
      i = 0 ## i64
      while i < dim
        row[i] = flat[base + i]
        i += 1
      out[r] = row
      r += 1
    out

# Reusable SPD Cholesky factor. The retained row-major lower triangle is the
# same bytes LAPACK sees as its column-major upper factor; solves only read it.
+ DenseCholeskyFactor
  -> new(@factors, @dimension)

  ro :dimension

  -> solve_into(rhs, out)
    raise "DenseCholeskyFactor.solve_into: RHS too short" if rhs.size() < @dimension
    raise "DenseCholeskyFactor.solve_into: output too short" if out.size() < @dimension
    ccall("w_array_memmove_f64", rhs, out, @dimension)
    info = ccall("w_blas_dpotrs_rowmajor", @factors, out, @dimension, 1)
    raise "DenseCholeskyFactor.solve_into: LAPACK failed with info=" + info.to_s if info != 0
    out

  -> solve(rhs)
    dim = @dimension
    raise "DenseCholeskyFactor.solve: RHS length must equal dimension" if rhs.size() != dim
    out_flat = f64[dim]
    solve_into(rhs, out_flat)
    out = Array.new(dim)
    i = 0 ## i64
    while i < dim
      out[i] = out_flat[i]
      i += 1
    out

  -> solve_many_into(rhs, out, count)
    raise "DenseCholeskyFactor.solve_many_into: count must be positive" if count <= 0
    total = @dimension * count
    raise "DenseCholeskyFactor.solve_many_into: RHS too short" if rhs.size() < total
    raise "DenseCholeskyFactor.solve_many_into: output too short" if out.size() < total
    ccall("w_array_memmove_f64", rhs, out, total)
    info = ccall("w_blas_dpotrs_rowmajor", @factors, out, @dimension, count)
    raise "DenseCholeskyFactor.solve_many_into: LAPACK failed with info=" + info.to_s if info != 0
    out

  -> solve_many(rhses)
    return [] if rhses.size() == 0
    count = rhses.size()
    dim = @dimension
    flat = f64[dim * count]
    r = 0 ## i64
    while r < count
      rhs_r = rhses[r]
      raise "DenseCholeskyFactor.solve_many: RHS length must equal dimension" if rhs_r.size() != dim
      base = (r * dim) ## i64
      i = 0 ## i64
      while i < dim
        flat[base + i] = (rhs_r[i] + ~0.0) ## f64
        i += 1
      r += 1
    solve_many_into(flat, flat, count)
    out = Array.new(count)
    r = 0 ## i64
    while r < count
      row = Array.new(dim)
      base = (r * dim) ## i64
      i = 0 ## i64
      while i < dim
        row[i] = flat[base + i]
        i += 1
      out[r] = row
      r += 1
    out

# Compact Householder QR factor for a full-column-rank m×n matrix (m>=n).
# `@factors` retains LAPACK's column-major reflector/R storage and `@tau`
# retains the scalar reflectors. No explicit Q is formed for least squares.
+ DenseQRFactor
  -> new(@factors, @tau, @rows, @columns)

  ro :rows
  ro :columns

  # `out` is also LAPACK's m-element workspace. The solution occupies its
  # first n elements; requiring m capacity keeps repeated solves allocation-free.
  -> solve_into(rhs, out)
    raise "DenseQRFactor.solve_into: RHS length must equal rows" if rhs.size() != @rows
    raise "DenseQRFactor.solve_into: output must have at least rows elements" if out.size() < @rows
    ccall("w_array_memmove_f64", rhs, out, @rows)
    info = ccall("w_blas_dgeqrf_solve", @factors, @tau, out, @rows, @columns, 1)
    raise "DenseQRFactor.solve_into: LAPACK failed with info=" + info.to_s if info != 0
    out

  -> solve(rhs)
    workspace = f64[@rows]
    solve_into(rhs, workspace)
    cols = @columns
    out = Array.new(cols)
    i = 0 ## i64
    while i < cols
      out[i] = workspace[i]
      i += 1
    out

  # RHS/output contain `count` consecutive m-element vectors. Each result is
  # stored at the beginning of its m-element output slot.
  -> solve_many_into(rhs, out, count)
    raise "DenseQRFactor.solve_many_into: count must be positive" if count <= 0
    total = @rows * count
    raise "DenseQRFactor.solve_many_into: RHS too short" if rhs.size() < total
    raise "DenseQRFactor.solve_many_into: output too short" if out.size() < total
    ccall("w_array_memmove_f64", rhs, out, total)
    info = ccall("w_blas_dgeqrf_solve", @factors, @tau, out, @rows, @columns, count)
    raise "DenseQRFactor.solve_many_into: LAPACK failed with info=" + info.to_s if info != 0
    out

  -> solve_many(rhses)
    return [] if rhses.size() == 0
    count = rhses.size()
    nrows = @rows
    ncols = @columns
    workspace = f64[nrows * count]
    r = 0 ## i64
    while r < count
      rhs_r = rhses[r]
      raise "DenseQRFactor.solve_many: RHS length must equal rows" if rhs_r.size() != nrows
      base = (r * nrows) ## i64
      i = 0 ## i64
      while i < nrows
        workspace[base + i] = (rhs_r[i] + ~0.0) ## f64
        i += 1
      r += 1
    solve_many_into(workspace, workspace, count)
    out = Array.new(count)
    r = 0 ## i64
    while r < count
      solution = Array.new(ncols)
      base = (r * nrows) ## i64
      i = 0 ## i64
      while i < ncols
        solution[i] = workspace[base + i]
        i += 1
      out[r] = solution
      r += 1
    out

+ LinAlg
  -> .rows(a)
    a.size()

  -> .cols(a)
    if a.size() == 0
      return 0
    a[0].size()

  -> .zeros(m, n)
    out = Array.new(m)
    i = 0 ## i64
    while i < m
      out[i] = Array.new(n, ~0.0)
      i = i + 1
    out

  -> .eye(n)
    a = LinAlg.zeros(n, n)
    i = 0
    while i < n
      a[i][i] = ~1.0
      i = i + 1
    a

  # Select the nested-list matmul implementation from the work that each path
  # actually performs.  This API always receives row-major lists, executes one
  # CPU product, and returns row-major lists, so the accelerated lane must copy
  # `mk + kn + mn` f64 elements around an Accelerate dgemm call.  Tensor owns
  # view/layout flags, batched GEMM, and non-CPU backend selection.
  #
  # The thresholds come from `matmul_policy_campaign.w` crossovers.  Separate
  # lanes matter for extreme aspect ratios: dot/scale shapes cannot amortize
  # two input copies, while outer products save enough dynamic nested-output
  # work to cross over much earlier than one-row/one-column products.
  -> .matmul_accelerated?(m, k, n)
    # Rank-one outer products are output-bound.  Require 1,024 outputs and at
    # least four rows and columns; smaller/noisier crossover candidates remain
    # on the prior scalar path.  A one-element aspect is scaling, not an outer
    # product, and remains scalar.
    # A single output row or column is input-staging-bound.  The 4,096-product
    # floor is the conservative matched 64x64 crossover; the intensity check
    # excludes long dot-like contractions such as 1x1024 by 1024x4.  Written in
    # bytes/FLOPs, it is the measured `10 * products >= 9 * staged_elements`
    # boundary.
    # General rectangular lane.  Dynamic scalar work is one product plus one
    # nested output write; dgemm staging is the two flat input copies plus a
    # measured 192-element fixed-cost allowance.  All m,k,n >= 8 products
    # satisfy this naturally, without a universal per-dimension cutoff.
    linalg_matmul_accelerated_raw(m, k, n) != 0

  # Publicly inspectable without performing or allocating a multiplication.
  -> .matmul_route(m, k, n)
    LinAlg.matmul_accelerated?(m, k, n) ? :accelerate : :scalar

  -> .matmul(a, b)
    m = LinAlg.rows(a)
    k = LinAlg.cols(a)
    n = LinAlg.cols(b)
    if linalg_matmul_accelerated_raw(m, k, n) != 0
      fa = LinAlg.flatten_2d(a, m, k)
      fb = LinAlg.flatten_2d(b, k, n)
      fc = f64[m * n]
      ccall("w_blas_dgemm_nn", fa, fb, fc, m, n, k)
      out = Array.new(m)
      i = 0 ## i64
      while i < m
        row = Array.new(n)
        base = (i * n) ## i64
        j = 0 ## i64
        while j < n
          row[j] = fc[base + j]
          j = j + 1
        out[i] = row
        i = i + 1
      return out
    out = LinAlg.zeros(m, n)
    i = 0 ## i64
    while i < m
      ai = a[i]
      oi = out[i]
      j = 0 ## i64
      while j < n
        s = ~0.0
        t = 0 ## i64
        while t < k
          s = s + ai[t] * b[t][j]
          t = t + 1
        oi[j] = s
        j = j + 1
      i = i + 1
    out

  -> .dot(u, v)
    s = ~0.0
    n = u.size()
    i = 0 ## i64
    while i < n
      s = s + u[i] * v[i]
      i = i + 1
    s

  -> .norm(v)
    Math.sqrt(LinAlg.dot(v, v))

  # GE with partial pivoting: A n×n nested, b length n → x length n
  # ---- flat f64 staging for the Accelerate/LAPACK fast paths ----
  # The list-of-rows representation stays the public contract; a square
  # matrix above this size is staged into a flat row-major f64 buffer, the
  # AMX-tuned LAPACK/BLAS call runs, and the result is unstaged. Below the
  # cutoff the pure paths win (they avoid the ccall + staging fixed cost).
  -> .lapack_cutoff
    8

  -> .flatten_2d(a, m, k)
    flat = f64[m * k]
    return flat if m <= 0 || k <= 0
    a00 = (a[0][0] + ~0.0) ## f64
    flat[0] = a00 == ~0.0 ? ~1.0 : ~0.0
    ccall("w_array_memmove_f64", a, flat, 0)
    return flat if flat[0] == a00
    i = 0 ## i64
    while i < m
      row = a[i]
      base = (i * k) ## i64
      j = 0 ## i64
      while j < k
        flat[base + j] = (row[j] + ~0.0) ## f64
        j = j + 1
      i = i + 1
    flat

  -> .flatten_square(a, n)
    LinAlg.flatten_2d(a, n, n)

  # Factor a non-empty square f64 matrix once for repeated right-hand sides.
  # The public matrix remains untouched; LAPACK owns the staged copy.
  -> .factor_lu(a)
    n = LinAlg.rows(a)
    raise "LinAlg.factor_lu: requires a non-empty square matrix" if n == 0 || LinAlg.cols(a) != n
    flat = LinAlg.flatten_square(a, n)
    pivots = i32[n]
    info = ccall("w_blas_dgetrf_rowmajor", flat, pivots, n)
    raise "LinAlg.factor_lu: singular" if info > 0
    raise "LinAlg.factor_lu: LAPACK failed with info=" + info.to_s if info < 0
    DenseLUFactor.new(flat, pivots, n)

  -> .factor_cholesky(a)
    n = LinAlg.rows(a)
    raise "LinAlg.factor_cholesky: requires a non-empty square matrix" if n == 0 || LinAlg.cols(a) != n
    flat = LinAlg.flatten_square(a, n)
    info = ccall("w_blas_dpotrf_lower", flat, n)
    raise "LinAlg.factor_cholesky: matrix is not positive definite" if info > 0
    raise "LinAlg.factor_cholesky: LAPACK failed with info=" + info.to_s if info < 0
    DenseCholeskyFactor.new(flat, n)

  # Retain LAPACK's compact Householder representation for repeated
  # full-rank overdetermined least-squares solves without constructing Q.
  -> .factor_qr(a)
    m = LinAlg.rows(a)
    n = LinAlg.cols(a)
    raise "LinAlg.factor_qr: requires a non-empty matrix with rows >= columns" if n == 0 || m < n
    flat = f64[m * n]
    i = 0 ## i64
    while i < m
      ai = a[i]
      j = 0 ## i64
      while j < n
        flat[j * m + i] = (ai[j] + ~0.0) ## f64
        j += 1
      i += 1
    tau = f64[n]
    info = ccall("w_blas_dgeqrf_factor", flat, tau, m, n)
    raise "LinAlg.factor_qr: LAPACK failed with info=" + info.to_s if info != 0
    max_diag = ~0.0
    min_diag = nil
    i = 0 ## i64
    while i < n
      diagonal = flat[i * m + i].abs
      max_diag = diagonal if diagonal > max_diag
      min_diag = diagonal if min_diag == nil || diagonal < min_diag
      i += 1
    raise "LinAlg.factor_qr: rank deficient" if min_diag == nil || min_diag <= max_diag * ~0.00000000000001
    DenseQRFactor.new(flat, tau, m, n)

  -> .solve(a, b)
    n = LinAlg.rows(a)
    if n >= LinAlg.lapack_cutoff
      flat = LinAlg.flatten_square(a, n)
      rhs = f64[n]
      ccall("w_array_memmove_f64", b, rhs, n)
      info = ccall("w_blas_dgesv_rowmajor", flat, rhs, n)
      raise "LinAlg.solve: singular" if info != 0
      x = Array.new(n)
      i = 0 ## i64
      while i < n
        x[i] = rhs[i]
        i = i + 1
      return x
    aw = LinAlg.copy_mat(a)
    bw = Array.new(n)
    i = 0 ## i64
    while i < n
      bw[i] = b[i] + ~0.0
      i = i + 1
    k = 0 ## i64
    while k < n
      piv = k
      awk = aw[k]
      maxv = awk[k]
      if maxv < ~0.0
        maxv = ~0.0 - maxv
      i = k + 1
      while i < n
        v = aw[i][k]
        if v < ~0.0
          v = ~0.0 - v
        if v > maxv
          maxv = v
          piv = i
        i = i + 1
      if maxv == ~0.0
        raise "LinAlg.solve: singular"
      if piv != k
        tmp = awk
        awk = aw[piv]
        aw[k] = awk
        aw[piv] = tmp
        tb = bw[k]
        bw[k] = bw[piv]
        bw[piv] = tb
      awkk = awk[k]
      bwk = bw[k]
      i = k + 1
      while i < n
        awi = aw[i]
        f = awi[k] / awkk
        j = k
        while j < n
          awi[j] = awi[j] - f * awk[j]
          j = j + 1
        bw[i] = bw[i] - f * bwk
        i = i + 1
      k = k + 1
    x = Array.new(n, ~0.0)
    i = n - 1
    while i >= 0
      awi = aw[i]
      s = bw[i]
      j = i + 1
      while j < n
        s = s - awi[j] * x[j]
        j = j + 1
      x[i] = s / awi[i]
      i = i - 1
    x

  -> .copy_mat(a)
    na = a.size()
    out = Array.new(na)
    i = 0 ## i64
    while i < na
      ai = a[i]
      nai = ai.size()
      row = Array.new(nai)
      j = 0 ## i64
      while j < nai
        row[j] = ai[j] + ~0.0
        j = j + 1
      out[i] = row
      i = i + 1
    out

  -> .det(a)
    n = LinAlg.rows(a)
    if n >= LinAlg.lapack_cutoff
      return ccall("w_blas_dget_det", LinAlg.flatten_square(a, n), n)
    aw = LinAlg.copy_mat(a)
    sign = ~1.0
    k = 0
    while k < n
      piv = k
      awk = aw[k]
      maxv = awk[k]
      if maxv < ~0.0
        maxv = ~0.0 - maxv
      i = k + 1
      while i < n
        v = aw[i][k]
        if v < ~0.0
          v = ~0.0 - v
        if v > maxv
          maxv = v
          piv = i
        i = i + 1
      if maxv == ~0.0
        return ~0.0
      if piv != k
        sign = ~0.0 - sign
        tmp = awk
        awk = aw[piv]
        aw[k] = awk
        aw[piv] = tmp
      awkk = awk[k]
      i = k + 1
      while i < n
        awi = aw[i]
        f = awi[k] / awkk
        j = k
        while j < n
          awi[j] = awi[j] - f * awk[j]
          j = j + 1
        i = i + 1
      k = k + 1
    d = sign
    i = 0
    while i < n
      d = d * aw[i][i]
      i = i + 1
    d

  # [sign, log|det|] without forming det (never over/underflows where a
  # 128x128 det would). sign is -1/0/+1; log|det| is -inf when singular.
  -> .slogdet(a)
    n = LinAlg.rows(a)
    out = f64[2]
    ccall("w_blas_dget_slogdet", LinAlg.flatten_square(a, n), n, out)
    [out[0], out[1]]

  -> .cholesky(a)
    n = LinAlg.rows(a)
    if n >= LinAlg.lapack_cutoff
      flat = LinAlg.flatten_square(a, n)
      info = ccall("w_blas_dpotrf_lower", flat, n)
      raise "LinAlg.cholesky: not SPD" if info != 0
      out = Array.new(n)
      i = 0 ## i64
      while i < n
        row = Array.new(n)
        base = (i * n) ## i64
        j = 0 ## i64
        while j < n
          row[j] = flat[base + j]
          j = j + 1
        out[i] = row
        i = i + 1
      return out
    L = LinAlg.zeros(n, n)
    i = 0
    while i < n
      ai = a[i]
      li = L[i]
      j = 0
      while j <= i
        s = ai[j]
        lj = L[j]
        k = 0
        while k < j
          s = s - li[k] * lj[k]
          k = k + 1
        if i == j
          if s <= ~0.0
            raise "LinAlg.cholesky: not SPD"
          li[j] = Math.sqrt(s)
        else
          li[j] = s / lj[j]
        j = j + 1
      i = i + 1
    L

  -> .transpose(a)
    m = LinAlg.rows(a)
    n = LinAlg.cols(a)
    out = Array.new(n)
    j = 0 ## i64
    while j < n
      row = Array.new(m)
      i = 0 ## i64
      while i < m
        row[i] = a[i][j]
        i = i + 1
      out[j] = row
      j = j + 1
    out

  -> .mat_vec(a, v)
    na = a.size()
    nv = v.size()
    out = Array.new(na)
    i = 0 ## i64
    while i < na
      ai = a[i]
      s = ~0.0
      j = 0 ## i64
      while j < nv
        s = s + ai[j] * v[j]
        j = j + 1
      out[i] = s
      i = i + 1
    out

  # Thin QR by modified Gram-Schmidt: a m×n (m ≥ n) → [q, r] with q m×n
  # (orthonormal columns) and r n×n upper triangular. A dependent column
  # leaves a zero column in q and a zero on r's diagonal rather than
  # raising — Lyapunov-spectrum renormalization treats that as collapse.
  -> .qr_lapack_cutoff
    8

  -> .qr(a)
    m = LinAlg.rows(a)
    n = LinAlg.cols(a)
    if m >= n && n >= LinAlg.qr_lapack_cutoff
      return LinAlg.qr_lapack(a)
    LinAlg.qr_reference(a)

  -> .qr_lapack(a)
    m = LinAlg.rows(a)
    n = LinAlg.cols(a)
    raise "LinAlg.qr: requires m >= n" if m < n
    flat = f64[m * n]
    i = 0 ## i64
    while i < m
      ai = a[i]
      j = 0 ## i64
      while j < n
        flat[j * m + i] = (ai[j] + ~0.0) ## f64
        j += 1
      i += 1
    qflat = f64[m * n]
    rflat = f64[n * n]
    info = ccall("w_blas_dgeqrf_qr", flat, qflat, rflat, m, n)
    raise "LinAlg.qr: LAPACK failed with info=" + info.to_s if info != 0
    q = Array.new(m)
    i = 0 ## i64
    while i < m
      row = Array.new(n)
      base = (i * n) ## i64
      j = 0 ## i64
      while j < n
        row[j] = qflat[base + j]
        j += 1
      q[i] = row
      i += 1
    r = Array.new(n)
    i = 0 ## i64
    while i < n
      row = Array.new(n)
      base = (i * n) ## i64
      j = 0 ## i64
      while j < n
        row[j] = rflat[base + j]
        j += 1
      r[i] = row
      i += 1
    max_diag = ~0.0
    min_diag = nil
    i = 0
    while i < n
      diagonal = r[i][i].abs
      max_diag = diagonal if diagonal > max_diag
      min_diag = diagonal if min_diag == nil || diagonal < min_diag
      i += 1
    # Preserve qr_reference's dependent-column contract. LAPACK still emits
    # a formal Householder basis for a rank-deficient matrix; Core promises a
    # zero dependent column instead, so replay that rare case on the reference
    # path after the cheap diagonal rank signal.
    if min_diag == nil || min_diag <= max_diag * ~0.00000000000001
      return LinAlg.qr_reference(a)
    [q, r]

  -> .qr_reference(a)
    m = LinAlg.rows(a)
    n = LinAlg.cols(a)
    q = LinAlg.copy_mat(a)
    r = LinAlg.zeros(n, n)
    j = 0
    while j < n
      source_sq = ~0.0
      t = 0
      while t < m
        qtj = q[t][j]
        source_sq += qtj * qtj
        t += 1
      i = 0
      while i < j
        s = ~0.0
        t = 0
        while t < m
          qt = q[t]
          s = s + qt[i] * qt[j]
          t = t + 1
        r[i][j] = s
        t = 0
        while t < m
          qt = q[t]
          qt[j] = qt[j] - s * qt[i]
          t = t + 1
        i = i + 1
      s = ~0.0
      t = 0
      while t < m
        qtj = q[t][j]
        s = s + qtj * qtj
        t = t + 1
      nrm = Math.sqrt(s)
      tolerance = Math.sqrt(source_sq) * ~0.00000000000001
      if nrm > tolerance
        r[j][j] = nrm
        t = 0
        while t < m
          qt = q[t]
          qt[j] = qt[j] / nrm
          t = t + 1
      else
        r[j][j] = ~0.0
        t = 0
        while t < m
          q[t][j] = ~0.0
          t += 1
      j = j + 1
    [q, r]

  # Characteristic polynomial of an n×n float matrix via Faddeev-LeVerrier.
  # Returns descending coefficients [1, c1, …, cn] of λⁿ + c1·λⁿ⁻¹ + … + cn.
  # Numerically fine at the Jacobian sizes stability analysis uses (n ≲ 10).
  -> .charpoly(a)
    n = LinAlg.rows(a)
    coeffs = [~1.0]
    m = LinAlg.eye(n)
    k = 1
    while k <= n
      m = LinAlg.matmul(a, m)
      tr = ~0.0
      i = 0
      while i < n
        tr = tr + m[i][i]
        i = i + 1
      ck = (~0.0 - tr) / k
      coeffs = coeffs.push(ck)
      i = 0
      while i < n
        mi = m[i]
        mi[i] = mi[i] + ck
        i = i + 1
      k = k + 1
    coeffs

  # All complex roots of a float-coefficient polynomial (descending
  # coefficients, coeffs[0] ≠ 0) by Durand-Kerner iteration on split
  # re/im floats. Returns [[re, im], …]; near-real roots snap to im = 0.
  -> .poly_roots(coeffs)
    n = coeffs.size() - 1
    if n < 1
      return []
    c = []
    c0_raw = coeffs[0]
    i = 0
    while i <= n
      c = c.push(coeffs[i] / c0_raw)
      i = i + 1
    bound = ~0.0
    i = 1
    while i <= n
      v = c[i]
      if v < ~0.0
        v = ~0.0 - v
      if v > bound
        bound = v
      i = i + 1
    bound = bound + ~1.0
    zr = []
    zi = []
    k = 0
    while k < n
      ang = (~6.283185307179586 * k) / n + ~0.4
      zr = zr.push(bound * Math.cos(ang))
      zi = zi.push(bound * Math.sin(ang))
      k = k + 1
    c0 = c[0]
    iter = 0
    while iter < 400
      moved = ~0.0
      k = 0
      while k < n
        zrk = zr[k]
        zik = zi[k]
        pr = c0
        pim = ~0.0
        i = 1
        while i <= n
          t = pr * zrk - pim * zik + c[i]
          pim = pr * zik + pim * zrk
          pr = t
          i = i + 1
        dr = ~1.0
        dim = ~0.0
        j = 0
        while j < n
          if j != k
            xr = zrk - zr[j]
            xi = zik - zi[j]
            t = dr * xr - dim * xi
            dim = dr * xi + dim * xr
            dr = t
          j = j + 1
        den = dr * dr + dim * dim
        if den > ~0.0
          qr = (pr * dr + pim * dim) / den
          qi = (pim * dr - pr * dim) / den
          zr[k] = zrk - qr
          zi[k] = zik - qi
          step = Math.hypot(qr, qi)
          if step > moved
            moved = step
        k = k + 1
      if moved < ~1.0e-13
        iter = 400
      iter = iter + 1
    out = []
    k = 0
    while k < n
      re = zr[k]
      im = zi[k]
      mag = re
      if mag < ~0.0
        mag = ~0.0 - mag
      lim = im
      if lim < ~0.0
        lim = ~0.0 - lim
      if lim < ~1.0e-8 * (~1.0 + mag)
        im = ~0.0
      out = out.push([re, im])
      k = k + 1
    out

  # Near-null vector of an n×n float matrix by shifted inverse iteration:
  # repeatedly solve (A + ε·I)·v_next = v and normalize. Converges to the
  # eigenvector of the smallest-magnitude eigenvalue — the branch-switch
  # direction at a bifurcation's singular Jacobian.
  -> .null_vector(a)
    n = LinAlg.rows(a)
    shifted = LinAlg.copy_mat(a)
    i = 0
    while i < n
      si = shifted[i]
      si[i] = si[i] + ~1.0e-8
      i = i + 1
    v = []
    i = 0
    while i < n
      v = v.push(~1.0 / (i + ~1.0))
      i = i + 1
    it = 0
    while it < 20
      w = nil
      begin
        w = LinAlg.solve(shifted, v)
      rescue serr
        w = nil
      if w == nil
        it = 20
      else
        nm = LinAlg.norm(w)
        if nm > ~0.0
          i = 0
          while i < n
            w[i] = w[i] / nm
            i = i + 1
        v = w
        it = it + 1
    v

  # Eigenvalues of an n×n float matrix → [[re, im], …] (unordered).
  # Small n (≤ 8) stays on characteristic polynomial + Durand-Kerner —
  # dependency-free and robust at Jacobian sizes. Larger n routes through
  # the LAPACK dgeev bridge (Accelerate / OpenBLAS), falling back to
  # Durand-Kerner wherever the bridge is unavailable.
  -> .eigenvalues(a)
    n = LinAlg.rows(a)
    if n <= 8
      return LinAlg.poly_roots(LinAlg.charpoly(a))
    out = nil
    begin
      out = LinAlg.eigenvalues_lapack(a)
    rescue err
      out = nil
    if out != nil
      return out
    LinAlg.poly_roots(LinAlg.charpoly(a))

  # LAPACK route: flatten row-major into a typed f64 buffer, run dgeev,
  # pair the wr/wi outputs.
  -> .eigenvalues_lapack(a)
    n = LinAlg.rows(a)
    af = LinAlg.flatten_square(a, n)
    wr = f64[n]
    wi = f64[n]
    info = ccall("w_blas_dgeev", af, wr, wi, n)
    if info != 0
      raise "LinAlg.eigenvalues_lapack: dgeev info=" + info.to_s()
    out = []
    i = 0
    while i < n
      out = out.push([wr[i], wi[i]])
      i = i + 1
    out

  # Eigenvalues of a real symmetric matrix, ascending. Values-only keeps the
  # API explicit until Core has a stable eigenvector orientation contract.
  -> .eigh_values(a)
    n = LinAlg.rows(a)
    raise "LinAlg.eigh_values: matrix must be square" if LinAlg.cols(a) != n
    return [] if n == 0
    flat = LinAlg.flatten_square(a, n)
    values = ccall("w_array_new_aligned", -64, n)
    info = ccall("w_blas_dsyev_values", flat, values, n)
    raise "LinAlg.eigh_values: dsyev info=" + info.to_s if info != 0
    out = []
    i = 0
    while i < n
      out.push(values[i])
      i += 1
    out

  # Singular values of an m×n real matrix, descending. Direct SVD avoids the
  # condition-number squaring of the common eigenvalues(A^T A) workaround.
  -> .singular_values(a)
    m = LinAlg.rows(a)
    n = LinAlg.cols(a)
    return [] if m == 0 || n == 0
    flat = ccall("w_array_new_aligned", -64, m * n)
    i = 0
    while i < m
      ai = a[i]
      j = 0
      while j < n
        flat[j * m + i] = ai[j] + ~0.0
        j += 1
      i += 1
    count = m < n ? m : n
    values = ccall("w_array_new_aligned", -64, count)
    info = ccall("w_blas_dgesdd_values", flat, values, m, n)
    raise "LinAlg.singular_values: dgesdd info=" + info.to_s if info != 0
    out = []
    i = 0
    while i < count
      out.push(values[i])
      i += 1
    out

  # Thin SVD: [U, singular_values, Vt], with U m×k and Vt k×n,
  # k=min(m,n). Supports rank deficiency and rectangular matrices; vectors
  # are not uniquely oriented inside repeated/zero singular subspaces.
  # This copies input and uses LAPACK directly, never A^T A.
  -> .svd(a)
    m = LinAlg.rows(a)
    n = LinAlg.cols(a)
    k = m < n ? m : n
    i = 0
    while i < m
      raise "LinAlg.svd: rows must be rectangular" if a[i].size != n
      i += 1
    if k == 0
      return [LinAlg.zeros(m, 0), [], []]
    flat = ccall("w_array_new_aligned", -64, m * n)
    i = 0
    while i < m
      ai = a[i]
      j = 0
      while j < n
        value = ai[j].to_f
        raise "LinAlg.svd: entries must be finite" if !value.finite?
        flat[j * m + i] = value
        j += 1
      i += 1
    values = ccall("w_array_new_aligned", -64, k)
    uf = ccall("w_array_new_aligned", -64, m * k)
    vf = ccall("w_array_new_aligned", -64, k * n)
    info = ccall("w_blas_dgesdd_thin", flat, values, uf, vf, m, n)
    raise "LinAlg.svd: LAPACK failed with info=" + info.to_s if info != 0
    u = LinAlg.zeros(m, k)
    vt = LinAlg.zeros(k, n)
    s = []
    j = 0
    while j < k
      s.push(values[j])
      vtr = vt[j]
      i = 0
      while i < m
        u[i][j] = uf[j * m + i]
        i += 1
      i = 0
      while i < n
        vtr[i] = vf[i * k + j]
        i += 1
      j += 1
    [u, s, vt]

  # Overdetermined, full-column-rank least squares for one RHS. Rank failure
  # is explicit; underdetermined and multi-RHS contracts remain separate APIs.
  -> .least_squares(a, b)
    m = LinAlg.rows(a)
    n = LinAlg.cols(a)
    raise "LinAlg.least_squares: requires rows >= columns" if m < n
    raise "LinAlg.least_squares: RHS length must equal rows" if b.size() != m
    return [] if n == 0
    flat = ccall("w_array_new_aligned", -64, m * n)
    i = 0
    while i < m
      ai = a[i]
      j = 0
      while j < n
        flat[j * m + i] = ai[j] + ~0.0
        j += 1
      i += 1
    rhs = ccall("w_array_new_aligned", -64, m)
    i = 0
    while i < m
      rhs[i] = b[i] + ~0.0
      i += 1
    rank = ccall("w_blas_dgelsy", flat, rhs, m, n)
    raise "LinAlg.least_squares: LAPACK failed" if rank < 0
    raise "LinAlg.least_squares: rank deficient (rank " + rank.to_s + " < " + n.to_s + ")" if rank < n
    out = []
    i = 0
    while i < n
      out.push(rhs[i])
      i += 1
    out

  # True when `n` is a positive power of 2 (1, 2, 4, 8, …, 4096, …).
  -> .power_of_two?(n)
    n > 0 && (n & (n - 1)) == 0

  # Fast Walsh-Hadamard Transform (FWHT) of a 1-D vector `v` of power-of-2
  # length `n` in O(n log n) additions/subtractions.
  # When `normalize` is true (default), scales by 1/sqrt(n) so the transform
  # is symmetric orthonormal and involutory (H_n = H_n^T = H_n^-1), matching
  # the Hadamard rotation used in 2-bit/4-bit/8-bit LLM quantization.
  -> .fwht(v, normalize = true)
    n = v.size()
    raise "LinAlg.fwht: length must be a positive power of 2" if !LinAlg.power_of_two?(n)
    work = f64[n]
    i = 0
    while i < n
      work[i] = v[i] + ~0.0
      i += 1
    h = 1
    while h < n
      i = 0
      while i < n
        j = i
        limit = i + h
        while j < limit
          x = work[j]
          y = work[j + h]
          work[j] = x + y
          work[j + h] = x - y
          j += 1
        i += h * 2
      h = h * 2
    out = []
    if normalize
      scale = ~1.0 / Math.sqrt(n.to_f)
      i = 0
      while i < n
        out.push(work[i] * scale)
        i += 1
    else
      i = 0
      while i < n
        out.push(work[i])
        i += 1
    out

  # Row-wise Fast Walsh-Hadamard Transform over a rectangular matrix `a`.
  -> .fwht_rows(a, normalize = true)
    m = LinAlg.rows(a)
    return [] if m == 0
    n = LinAlg.cols(a)
    raise "LinAlg.fwht_rows: column count must be a positive power of 2" if !LinAlg.power_of_two?(n)
    work = f64[n]
    scale = normalize ? (~1.0 / Math.sqrt(n.to_f)) : ~1.0
    out = []
    r = 0
    while r < m
      ar = a[r]
      raise "LinAlg.fwht_rows: rows must be rectangular" if ar.size() != n
      i = 0
      while i < n
        work[i] = ar[i] + ~0.0
        i += 1
      h = 1
      while h < n
        i = 0
        while i < n
          j = i
          limit = i + h
          while j < limit
            x = work[j]
            y = work[j + h]
            work[j] = x + y
            work[j + h] = x - y
            j += 1
          i += h * 2
        h = h * 2
      row_out = []
      if normalize
        i = 0
        while i < n
          row_out.push(work[i] * scale)
          i += 1
      else
        i = 0
        while i < n
          row_out.push(work[i])
          i += 1
      out.push(row_out)
      r += 1
    out

  # Orthonormal Signed Block-Hadamard Transform along rows of `a` with block
  # width `block_size` (e.g. 128 or 4096 in Bonsai 2 / Qwen3.5 / DFlash 2).
  # - Forward (`inverse == false`): y_b = H_B (s_b ⊙ x_b)
  # - Inverse (`inverse == true`):  x_b = s_b ⊙ (H_B y_b)
  # Because H_B is symmetric orthonormal (H_B^2 = I) and s_i in {-1, +1},
  # the inverse exactly recovers `a`.
  -> .block_fwht_rows(a, block_size, signs = nil, inverse = false)
    m = LinAlg.rows(a)
    return [] if m == 0
    n = LinAlg.cols(a)
    raise "LinAlg.block_fwht_rows: block_size must be a positive power of 2" if !LinAlg.power_of_two?(block_size)
    raise "LinAlg.block_fwht_rows: column count must be divisible by block_size" if n == 0 || (n % block_size) != 0
    if signs != nil && signs.size() != n
      raise "LinAlg.block_fwht_rows: signs length must equal column count"
    scale = ~1.0 / Math.sqrt(block_size.to_f)
    work = f64[n]
    has_signs = signs != nil
    sign_work = f64[has_signs ? n : 1]
    if has_signs
      c = 0
      while c < n
        sign_work[c] = signs[c] + ~0.0
        c += 1
    out = []
    r = 0
    while r < m
      row = a[r]
      raise "LinAlg.block_fwht_rows: rows must be rectangular" if row.size() != n
      c = 0
      while c < n
        v = row[c] + ~0.0
        if has_signs && !inverse
          v = v * sign_work[c]
        work[c] = v
        c += 1
      b = 0
      while b < n
        h = 1
        while h < block_size
          i = b
          block_end = b + block_size
          while i < block_end
            j = i
            limit = i + h
            while j < limit
              x = work[j]
              y = work[j + h]
              work[j] = x + y
              work[j + h] = x - y
              j += 1
            i += h * 2
          h = h * 2
        b += block_size
      out_row = []
      c = 0
      while c < n
        v = work[c] * scale
        if has_signs && inverse
          v = v * sign_work[c]
        out_row.push(v)
        c += 1
      out.push(out_row)
      r += 1
    out

  # Sylvester's Walsh-Hadamard matrix H_n of order `n` (power of 2).
  # Entries are +1/-1 when `normalize == false`, or ±1/sqrt(n) when true.
  -> .hadamard_matrix(n, normalize = false)
    raise "LinAlg.hadamard_matrix: n must be a positive power of 2" if !LinAlg.power_of_two?(n)
    scale = normalize ? (~1.0 / Math.sqrt(n.to_f)) : ~1.0
    out = []
    i = 0
    while i < n
      row = []
      j = 0
      while j < n
        bits = i & j
        parity = 0
        while bits > 0
          parity = parity ^ (bits & 1)
          bits = bits >> 1
        row.push(parity == 0 ? scale : (~0.0 - scale))
        j += 1
      out.push(row)
      i += 1
    out

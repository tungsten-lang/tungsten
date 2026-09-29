# Dense real CP-ALS and Tucker HOSVD/HOOI. CPU f32/f64 input, f64 work/output.
# Numerical approximations, not finite-field identities or minimal-rank proofs.
use core/tensor
use core/linalg

# Numerical CP factors with explicit weights, residual and stopping status.
+ CPDecomposition
  -> new(@weights, @factors, @shape, @unit, @iterations, @relative_error, @status)
  ro :weights, :factors, :shape, :unit, :iterations, :relative_error, :status
  -> rank
    @weights.size
  -> algorithm
    :cp_als
  -> converged?
    @status == :converged
  -> certified?
    false
  -> reconstruct
    out = TensorDecomposition.cp_tensor(@weights, @factors)
    out.unit = @unit
    out

# Numerical Tucker core and orthonormal mode factors, with fit diagnostics.
+ TuckerDecomposition
  -> new(@core, @factors, @iterations, @relative_error, @status, @algorithm)
  ro :core, :factors, :iterations, :relative_error, :status, :algorithm
  -> ranks
    @core.shape
  -> converged?
    @status == :converged
  -> certified?
    false
  -> reconstruct
    TensorDecomposition.tucker_tensor(@core, @factors)

# Dense real CP-ALS and Tucker HOSVD/HOOI over the existing CPU Tensor storage.
+ TensorDecomposition
  -> .integer?(x)
    name = x.class_name
    name == "Int" || name == "Integer" || name == "BigInt"

  -> .copy_list(xs)
    out = []
    xs.each -> out.push(item)
    out

  -> .validate(t)
    raise "tensor decomposition requires a Tensor" if t.class_name != "Tensor"
    if t.device != :cpu || (t.dtype != Tensor.f32 && t.dtype != Tensor.f64)
      raise "tensor decomposition requires CPU f32/f64 storage"
    raise "tensor decomposition requires order >= 2" if t.rank < 2
    t.shape.each -> (d)
      if !TensorDecomposition.integer?(d) || d <= 0
        raise "tensor decomposition requires positive integer dimensions"
    t

  -> .options(max_iterations, tolerance)
    if !TensorDecomposition.integer?(max_iterations) || max_iterations < 0
      raise "decomposition max_iterations must be a nonnegative integer"
    tol = tolerance.to_f
    if !tol.finite? || tol <= ~0.0
      raise "decomposition tolerance must be positive and finite"
    tol

  # Snapshot views in logical row-major order; never overwrite caller storage.
  -> .copy_tensor(t)
    TensorDecomposition.validate(t)
    out = Tensor.zeros_cpu(Tensor.f64, TensorDecomposition.copy_list(t.shape))
    i = 0
    while i < t.size
      x = t.at(Tensor.unravel(i, t.shape)).to_f
      raise "tensor decomposition requires finite entries" if !x.finite?
      out.buffer[i] = x
      i += 1
    out.unit = t.unit
    out

  # Scale first, avoiding overflow/underflow in residuals on finite input.
  -> .normalized(t)
    out = TensorDecomposition.copy_tensor(t)
    scale = ~0.0
    i = 0
    while i < out.size
      scale = out.buffer[i].abs if out.buffer[i].abs > scale
      i += 1
    if scale > ~0.0
      i = 0
      while i < out.size
        out.buffer[i] /= scale
        i += 1
    out.unit = nil
    [out, scale]

  -> .relative_error(a, b)
    raise "decomposition residual shape mismatch" if !Tensor.same_shape(a.shape, b.shape)
    error = ~0.0
    denominator = ~0.0
    i = 0
    while i < a.size
      coord = Tensor.unravel(i, a.shape)
      av = a.at(coord)
      bv = b.at(coord)
      raise "tensor decomposition numerical breakdown" if !bv.finite?
      error = Math.hypot(error, av - bv)
      denominator = Math.hypot(denominator, av)
      i += 1
    return error if denominator == ~0.0
    error / denominator

  # Mode row first, other axes in their original increasing order.
  -> .unfold(t, mode)
    TensorDecomposition.validate(t)
    if !TensorDecomposition.integer?(mode) || mode < 0 || mode >= t.rank
      raise "TensorDecomposition.unfold: invalid mode"
    axes = [mode]
    i = 0
    while i < t.rank
      axes.push(i) if i != mode
      i += 1
    copy = TensorDecomposition.copy_tensor(t.permute(axes))
    copy.reshape([t.shape[mode], t.size / t.shape[mode]])

  # matrix[new_mode_size, old_mode_size]; basis matrices are dimensionless.
  -> .mode_product(t, matrix, mode)
    TensorDecomposition.validate(matrix)
    if matrix.rank != 2 || matrix.unit != nil
      raise "mode_product requires a dimensionless rank-2 matrix"
    unfolded = TensorDecomposition.unfold(t, mode)
    if matrix.shape[1] != t.shape[mode]
      raise "mode_product: matrix width must equal mode size"
    product = TensorDecomposition.copy_tensor(matrix).matmul(unfolded)
    axes = [mode]
    perm_shape = [matrix.shape[0]]
    i = 0
    while i < t.rank
      if i != mode
        axes.push(i)
        perm_shape.push(t.shape[i])
      i += 1
    inverse = []
    i = 0
    while i < t.rank
      j = 0
      while axes[j] != i
        j += 1
      inverse.push(j)
      i += 1
    out = product.reshape(perm_shape).permute(inverse).contiguous
    out.unit = t.unit
    out

  -> .cp_tensor(weights, factors)
    raise "CP requires at least two factor matrices" if factors.size < 2
    rank = weights.size
    raise "CP requires at least one component" if rank == 0
    shape = []
    factors.each -> (f)
      TensorDecomposition.validate(f)
      if f.rank != 2 || f.shape[1] != rank || f.unit != nil
        raise "CP factor widths must match weights and factors must be dimensionless"
      shape.push(f.shape[0])
    out = Tensor.zeros_cpu(Tensor.f64, shape)
    i = 0
    while i < out.size
      coord = Tensor.unravel(i, shape)
      value = ~0.0
      r = 0
      while r < rank
        term = weights[r].to_f
        m = 0
        while m < factors.size
          term *= factors[m].at([coord[m], r])
          m += 1
        value += term
        r += 1
      raise "CP reconstruction overflow or nonfinite factors" if !value.finite?
      out.buffer[i] = value
      i += 1
    out

  -> .tucker_tensor(core, factors)
    out = TensorDecomposition.copy_tensor(core)
    raise "Tucker requires one factor per mode" if factors.size != core.rank
    m = 0
    while m < factors.size
      out = TensorDecomposition.mode_product(out, factors[m], m)
      m += 1
    out

  # Khatri-Rao product excluding one mode, matching unfold's column order.
  -> .design(factors, mode)
    shape = []
    axes = []
    m = 0
    while m < factors.size
      if m != mode
        shape.push(factors[m].shape[0])
        axes.push(m)
      m += 1
    rank = factors[0].shape[1]
    out = Tensor.zeros_cpu(Tensor.f64, [Tensor.elem_count(shape), rank])
    i = 0
    while i < out.shape[0]
      coord = Tensor.unravel(i, shape)
      r = 0
      while r < rank
        value = ~1.0
        j = 0
        while j < axes.size
          value *= factors[axes[j]].at([coord[j], r])
          j += 1
        out.buffer[i * rank + r] = value
        r += 1
      i += 1
    out

  # Solve all RHS at once using a truncated SVD, including deficient/wide
  # design matrices. Avoid normal equations and their squared conditioning.
  -> .solve_mode(design, rhs, rcond)
    svd = LinAlg.svd(design.to_rows)
    u = Tensor.from_rows(svd[0], Tensor.f64)
    values = svd[1]
    vt = Tensor.from_rows(svd[2], Tensor.f64)
    projected = rhs.matmul(u)
    cutoff = values[0] * rcond
    i = 0
    while i < projected.shape[0]
      j = 0
      while j < values.size
        index = i * values.size + j
        if values[j] > cutoff
          projected.buffer[index] /= values[j]
        else
          projected.buffer[index] = ~0.0
        j += 1
      i += 1
    projected.matmul(vt)

  # Unit-norm columns plus explicit weights, after fitting normalized input.
  -> .cp_result(factors, scale, unit, iterations, error, status)
    rank = factors[0].shape[1]
    weights = []
    r = 0
    while r < rank
      weight = scale
      m = 0
      while m < factors.size
        column_norm = ~0.0
        i = 0
        while i < factors[m].shape[0]
          column_norm = Math.hypot(column_norm, factors[m].at([i, r]))
          i += 1
        weight *= column_norm
        if column_norm > ~0.0
          i = 0
          while i < factors[m].shape[0]
            factors[m].set([i, r], factors[m].at([i, r]) / column_norm)
            i += 1
        m += 1
      raise "CP weights overflow; use a different initialization" if !weight.finite?
      weights.push(weight)
      r += 1
    shape = []
    factors.each -> shape.push(item.shape[0])
    CPDecomposition.new(weights, factors, shape, unit, iterations, error, status)

  -> .cpd(t, rank, max_iterations = 100, tolerance = ~1e-8, seed = 1, rcond = ~1e-12, initial_factors = nil)
    tol = TensorDecomposition.options(max_iterations, tolerance)
    if !TensorDecomposition.integer?(rank) || rank <= 0
      raise "CP rank must be a positive integer"
    if !TensorDecomposition.integer?(seed)
      raise "CP seed must be an integer"
    rc = rcond.to_f
    raise "CP rcond must be finite, nonnegative and less than one" if !rc.finite? || rc < ~0.0 || rc >= ~1.0
    normalized = TensorDecomposition.normalized(t)
    x = normalized[0]
    scale = normalized[1]
    factors = []
    ones = []
    rank.times -> ones.push(~1.0)
    state = seed % 2147483646 + 1
    m = 0
    if initial_factors != nil && initial_factors.size != x.rank
      raise "CP initial_factors must have one matrix per mode"
    while m < x.rank
      f = Tensor.zeros_cpu(Tensor.f64, [x.shape[m], rank])
      if initial_factors != nil
        source = initial_factors[m]
        f = TensorDecomposition.copy_tensor(source)
        if !Tensor.same_shape(f.shape, [x.shape[m], rank]) || f.unit != nil
          raise "CP initial factor shape/unit mismatch"
        if m == 0 && scale > ~0.0
          i = 0
          while i < f.size
            f.buffer[i] /= scale
            i += 1
      else
        i = 0
        while i < f.size
          state = (state * 16807) % 2147483647
          f.buffer[i] = state.to_f / ~1073741823.5 - ~1.0
          i += 1
      factors.push(f)
      m += 1
    if scale == ~0.0
      return TensorDecomposition.cp_result(factors, scale, t.unit, 0, ~0.0, :converged)
    error = TensorDecomposition.relative_error(x, TensorDecomposition.cp_tensor(ones, factors))
    iteration = 0
    status = :max_iterations
    if error <= tol
      status = :converged
    while iteration < max_iterations && status == :max_iterations
      previous = error
      m = 0
      while m < x.rank
        factors[m] = TensorDecomposition.solve_mode(TensorDecomposition.design(factors, m), TensorDecomposition.unfold(x, m), rc)
        m += 1
      iteration += 1
      error = TensorDecomposition.relative_error(x, TensorDecomposition.cp_tensor(ones, factors))
      if error <= tol
        status = :converged
      elsif (previous - error).abs <= tol
        status = :stalled
    TensorDecomposition.cp_result(factors, scale, t.unit, iteration, error, status)

  # Complete a thin left singular basis when requested rank exceeds the
  # unfolding's column count (e.g. full Tucker ranks of an 8×2×2 tensor).
  -> .left_basis(matrix, rank)
    svd = LinAlg.svd(matrix.to_rows)
    thin = svd[0]
    available = svd[1].size
    rows = matrix.shape[0]
    out = Tensor.zeros_cpu(Tensor.f64, [rows, rank])
    col = 0
    while col < rank && col < available
      i = 0
      while i < rows
        out.set([i, col], thin[i][col])
        i += 1
      col += 1
    axis = 0
    while col < rank && axis < rows
      v = []
      i = 0
      while i < rows
        v.push(i == axis ? ~1.0 : ~0.0)
        i += 1
      2.times ->
        j = 0
        while j < col
          dot = ~0.0
          i = 0
          while i < rows
            dot += v[i] * out.at([i, j])
            i += 1
          i = 0
          while i < rows
            v[i] -= dot * out.at([i, j])
            i += 1
          j += 1
      length = LinAlg.norm(v)
      if length > ~1e-10
        i = 0
        while i < rows
          out.set([i, col], v[i] / length)
          i += 1
        col += 1
      axis += 1
    raise "Tucker basis completion failed" if col != rank
    out

  -> .project_except(x, factors, skip)
    out = x
    m = 0
    while m < factors.size
      if m != skip
        out = TensorDecomposition.mode_product(out, factors[m].transpose, m)
      m += 1
    out

  -> .hosvd(t, ranks)
    TensorDecomposition.tucker(t, ranks, 0)

  -> .tucker(t, ranks, max_iterations = 25, tolerance = ~1e-8)
    tol = TensorDecomposition.options(max_iterations, tolerance)
    normalized = TensorDecomposition.normalized(t)
    x = normalized[0]
    scale = normalized[1]
    raise "Tucker requires one rank per mode" if ranks.size != x.rank
    factors = []
    m = 0
    while m < x.rank
      if !TensorDecomposition.integer?(ranks[m]) || ranks[m] <= 0 || ranks[m] > x.shape[m]
        raise "Tucker ranks must be integers between 1 and each mode size"
      factors.push(TensorDecomposition.left_basis(TensorDecomposition.unfold(x, m), ranks[m]))
      m += 1
    core = TensorDecomposition.project_except(x, factors, -1)
    error = TensorDecomposition.relative_error(x, TensorDecomposition.tucker_tensor(core, factors))
    iteration = 0
    status = max_iterations == 0 ? :hosvd : :max_iterations
    status = :converged if error <= tol
    while iteration < max_iterations && status == :max_iterations
      previous = error
      m = 0
      while m < x.rank
        partial = TensorDecomposition.project_except(x, factors, m)
        factors[m] = TensorDecomposition.left_basis(TensorDecomposition.unfold(partial, m), ranks[m])
        m += 1
      iteration += 1
      core = TensorDecomposition.project_except(x, factors, -1)
      error = TensorDecomposition.relative_error(x, TensorDecomposition.tucker_tensor(core, factors))
      status = :converged if error <= tol || (previous - error).abs <= tol
    i = 0
    while i < core.size
      value = core.buffer[i] * scale
      raise "Tucker core overflow" if !value.finite?
      core.buffer[i] = value
      i += 1
    core.unit = t.unit
    algorithm = max_iterations == 0 ? :hosvd : :tucker_hooi
    TuckerDecomposition.new(core, factors, iteration, error, status, algorithm)

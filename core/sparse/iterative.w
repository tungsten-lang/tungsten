# Portable iterative sparse solves with explicit convergence diagnostics.
#
# These algorithms copy canonical CSR once into typed f64/i64 solve-local
# buffers; they never form a dense matrix. CG requires a symmetric
# positive-definite matrix. BiCGSTAB accepts a general square matrix. Neither
# result is a proof or certificate.

+ SparseSolveCriteria
  -> .default(n)
    max_iterations = n * 10
    if max_iterations < 50
      max_iterations = 50
    SparseSolveCriteria.new(~1.0e-8, ~0.0, max_iterations, :jacobi)

  -> new(@relative_tolerance, @absolute_tolerance, @max_iterations, @preconditioner)
    if @relative_tolerance < ~0.0 || @absolute_tolerance < ~0.0
      raise "SparseSolveCriteria: tolerances must be non-negative"
    if @max_iterations < 0
      raise "SparseSolveCriteria: max_iterations must be non-negative"
    if @preconditioner != :none && @preconditioner != :jacobi && @preconditioner != :ichol0
      raise "SparseSolveCriteria: preconditioner must be :none, :jacobi, or :ichol0"

  -> relative_tolerance
    @relative_tolerance
  -> absolute_tolerance
    @absolute_tolerance
  -> max_iterations
    @max_iterations
  -> preconditioner
    @preconditioner

+ SparseSolveResult
  -> new(@status, @solution, @iterations, @residual_norm, @relative_residual, @algorithm)

  -> status
    @status
  -> solution
    @solution
  -> x
    @solution
  -> iterations
    @iterations
  -> residual_norm
    @residual_norm
  -> relative_residual
    @relative_residual
  -> algorithm
    @algorithm
  -> converged?
    @status == :converged
  -> certified?
    false
  -> to_s
    out = "SparseSolveResult(" + @algorithm.to_s() + " " + @status.to_s()
    out = out + " iterations=" + @iterations.to_s()
    out + " residual=" + @residual_norm.to_s() + ")"

+ SparseIterative
  -> .fabs(value)
    out = value
    if out < ~0.0
      out = ~0.0 - out
    out

  -> .relative_residual(residual_norm, rhs_norm)
    if rhs_norm == ~0.0
      return residual_norm
    residual_norm / rhs_norm

  -> .criteria(matrix, criteria)
    if criteria == nil
      return SparseSolveCriteria.default(matrix.rows)
    criteria

  -> .result(status, solution, iterations, residual_norm, rhs_norm, algorithm)
    rel = SparseIterative.relative_residual(residual_norm, rhs_norm)
    SparseSolveResult.new(status, solution, iterations, residual_norm, rel, algorithm)

  -> .conjugate_gradient(matrix, rhs, criteria = nil, initial = nil)
    if matrix.rows != matrix.cols
      raise "SparseMatrix.conjugate_gradient: square SPD matrix required"
    if rhs.size() != matrix.rows
      raise "SparseMatrix.conjugate_gradient: RHS length must equal rows"
    a = matrix.to_csr
    rule = SparseIterative.criteria(a, criteria)
    x = SparseF64Workspace.zeros(a.cols)
    if initial != nil
      if initial.size() != a.cols
        raise "Sparse iterative solve: initial solution length must equal columns"
      x = SparseF64Workspace.copy(initial)
    b = SparseF64Workspace.copy(rhs)
    n = a.rows
    buffers = SparseF64Workspace.matrix(a)
    ptr = buffers[0]
    indices = buffers[1]
    data = buffers[2]
    bnorm = sparse_f64_norm(b, n)
    threshold = rule.absolute_tolerance + rule.relative_tolerance * bnorm
    product = SparseF64Workspace.zeros(n)
    r = SparseF64Workspace.zeros(n)
    sparse_f64_csr_matvec(ptr, indices, data, x, product, n)
    sparse_f64_residual(b, product, r, n)
    rnorm = sparse_f64_norm(r, n)
    if rnorm <= threshold
      return SparseIterative.result(:converged, x, 0, rnorm, bnorm, :cg)
    preconditioner = SparsePreconditioner.prepare(a, rule.preconditioner)
    if preconditioner == nil
      return SparseIterative.result(:breakdown, x, 0, rnorm, bnorm, :cg)
    z = SparseF64Workspace.zeros(n)
    precondition_scratch = SparseF64Workspace.zeros(n)
    preconditioner.apply(r, z, precondition_scratch)
    p = SparseF64Workspace.zeros(n)
    sparse_f64_copy(z, p, n)
    ap = SparseF64Workspace.zeros(n)
    rz = sparse_f64_dot(r, z, n)
    tiny = ~1.0e-30
    iteration = 0
    while iteration < rule.max_iterations
      sparse_f64_csr_matvec(ptr, indices, data, p, ap, n)
      denominator = sparse_f64_dot(p, ap, n)
      if SparseIterative.fabs(denominator) <= tiny
        return SparseIterative.result(:breakdown, x, iteration, rnorm, bnorm, :cg)
      alpha = rz / denominator
      sparse_f64_cg_step(x, r, p, ap, alpha, n)
      iteration = iteration + 1
      rnorm = sparse_f64_norm(r, n)
      if rnorm <= threshold
        return SparseIterative.result(:converged, x, iteration, rnorm, bnorm, :cg)
      preconditioner.apply(r, z, precondition_scratch)
      next_rz = sparse_f64_dot(r, z, n)
      if SparseIterative.fabs(rz) <= tiny
        return SparseIterative.result(:breakdown, x, iteration, rnorm, bnorm, :cg)
      beta = next_rz / rz
      sparse_f64_cg_direction(p, z, beta, n)
      rz = next_rz
    SparseIterative.result(:max_iterations, x, iteration, rnorm, bnorm, :cg)

  -> .bicgstab(matrix, rhs, criteria = nil, initial = nil)
    if matrix.rows != matrix.cols
      raise "SparseMatrix.bicgstab: square matrix required"
    if rhs.size() != matrix.rows
      raise "SparseMatrix.bicgstab: RHS length must equal rows"
    a = matrix.to_csr
    rule = SparseIterative.criteria(a, criteria)
    x = SparseF64Workspace.zeros(a.cols)
    if initial != nil
      if initial.size() != a.cols
        raise "Sparse iterative solve: initial solution length must equal columns"
      x = SparseF64Workspace.copy(initial)
    b = SparseF64Workspace.copy(rhs)
    n = a.rows
    buffers = SparseF64Workspace.matrix(a)
    ptr = buffers[0]
    indices = buffers[1]
    data = buffers[2]
    bnorm = sparse_f64_norm(b, n)
    threshold = rule.absolute_tolerance + rule.relative_tolerance * bnorm
    product = SparseF64Workspace.zeros(n)
    r = SparseF64Workspace.zeros(n)
    sparse_f64_csr_matvec(ptr, indices, data, x, product, n)
    sparse_f64_residual(b, product, r, n)
    rnorm = sparse_f64_norm(r, n)
    if rnorm <= threshold
      return SparseIterative.result(:converged, x, 0, rnorm, bnorm, :bicgstab)
    shadow = SparseF64Workspace.zeros(n)
    sparse_f64_copy(r, shadow, n)
    p = SparseF64Workspace.zeros(n)
    v = SparseF64Workspace.zeros(n)
    phat = SparseF64Workspace.zeros(n)
    s = SparseF64Workspace.zeros(n)
    shat = SparseF64Workspace.zeros(n)
    t = SparseF64Workspace.zeros(n)
    preconditioner = SparsePreconditioner.prepare(a, rule.preconditioner)
    if preconditioner == nil
      return SparseIterative.result(:breakdown, x, 0, rnorm, bnorm, :bicgstab)
    precondition_scratch = SparseF64Workspace.zeros(n)
    rho_old = ~1.0
    alpha = ~1.0
    omega = ~1.0
    tiny = ~1.0e-30
    iteration = 0
    while iteration < rule.max_iterations
      rho = sparse_f64_dot(shadow, r, n)
      if SparseIterative.fabs(rho) <= tiny || SparseIterative.fabs(omega) <= tiny
        return SparseIterative.result(:breakdown, x, iteration, rnorm, bnorm, :bicgstab)
      beta = (rho / rho_old) * (alpha / omega)
      sparse_f64_bicg_direction(p, r, v, beta, omega, n)
      preconditioner.apply(p, phat, precondition_scratch)
      sparse_f64_csr_matvec(ptr, indices, data, phat, v, n)
      denominator = sparse_f64_dot(shadow, v, n)
      if SparseIterative.fabs(denominator) <= tiny
        return SparseIterative.result(:breakdown, x, iteration, rnorm, bnorm, :bicgstab)
      alpha = rho / denominator
      sparse_f64_difference(r, v, alpha, s, n)
      snorm = sparse_f64_norm(s, n)
      if snorm <= threshold
        sparse_f64_add_scaled(x, phat, alpha, n)
        iteration = iteration + 1
        return SparseIterative.result(:converged, x, iteration, snorm, bnorm, :bicgstab)
      preconditioner.apply(s, shat, precondition_scratch)
      sparse_f64_csr_matvec(ptr, indices, data, shat, t, n)
      tt = sparse_f64_dot(t, t, n)
      if SparseIterative.fabs(tt) <= tiny
        return SparseIterative.result(:breakdown, x, iteration, rnorm, bnorm, :bicgstab)
      omega = sparse_f64_dot(t, s, n) / tt
      sparse_f64_add_scaled(x, phat, alpha, n)
      sparse_f64_add_scaled(x, shat, omega, n)
      sparse_f64_difference(s, t, omega, r, n)
      iteration = iteration + 1
      rnorm = sparse_f64_norm(r, n)
      if rnorm <= threshold
        return SparseIterative.result(:converged, x, iteration, rnorm, bnorm, :bicgstab)
      rho_old = rho
    SparseIterative.result(:max_iterations, x, iteration, rnorm, bnorm, :bicgstab)

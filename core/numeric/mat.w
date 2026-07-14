# Mat — rectangular M×N matrix, parametric in shape. For square fixed
# sizes 2/3/4, prefer Mat2 / Mat3 / Mat4 (those subclasses have explicit
# determinant / inverse / linear-algebra fast paths). Use Mat<T, M, N>
# for non-square shapes or sizes outside 2–4.
+ Mat<T, M, N> < Matrix<T>
  - data
    T elements[M * N]

  -> new(@elements ## T[M * N])

  -> rows M
  -> cols N

  # Class methods.

  # Identity is only defined for square matrices.
  -> .identity
    raise ArgumentError, "identity is only defined on square matrices" if M != N
    out = (0...(M * N)).map -> 0 ## T
    (0...M).each -> out[i * M + i] = 1 ## T
    class.new(out ## T[M * N])

  -> .zero
    class.new((0...(M * N)).map -> 0 ## T)

  # Column / row views — return generic length-N or length-M arrays.
  # (For specific shapes that map to Vec2/3/4, use Mat2/Mat3/Mat4
  # which return the named vector types.)
  -> col(c)
    (0...M).map -> elements[c * M + item]

  -> row(r)
    (0...N).map -> elements[item * M + r]

  # Linear algebra.

  -> transpose
    out = (0...(M * N)).map -> 0 ## T
    (0...M).each ->
      r = i
      (0...N).each -> out[r * N + item] = elements[item * M + r]
    Mat<T, N, M>.new(out ## T[M * N])

  # Matrix-matrix product — shape constraint: self is M×N, other must
  # be N×P, result is M×P (column-major).
  -> */1(Mat)
    a = elements
    b = @1.elements
    p = @1.cols
    out = (0...(M * p)).map -> 0 ## T
    # result[c, r] = Σₖ A[k, r] · B[c, k], 0 ≤ k < N
    (0...p).each ->
      c = i
      (0...M).each ->
        r = i
        acc = 0 ## T
        (0...N).each -> acc += a[item * M + r] * b[c * N + item]
        out[c * M + r] = acc
    Mat<T, M, p>.new(out ## T[M * p])

  # Matrix-vector product — vector must have N components, result has M.
  -> */1(Vector)
    v = @1.components
    out = (0...M).map -> 0 ## T
    (0...M).each ->
      r = i
      acc = 0 ## T
      (0...N).each -> acc += elements[item * M + r] * v[item]
      out[r] = acc
    Vector.new(out ## T[M])

  # determinant / inverse / trace defined only when square (M == N) —
  # contract; subclasses or runtime check.
  -> determinant
    raise ArgumentError, "determinant is only defined on square matrices" if M != N

  -> inverse
    raise ArgumentError, "inverse is only defined on square matrices" if M != N

  -> trace
    raise ArgumentError, "trace is only defined on square matrices" if M != N
    acc = 0 ## T
    (0...M).each -> acc += elements[item * M + item]
    acc

# Matrix — generic M×N matrices over a scalar type T. Storage is
# **column-major**, matching Metal / OpenGL / Eigen / BLAS conventions:
# the matrix `((a, b), (c, d))` (rows a/b, c/d) stores as `[a, c, b, d]`
# so that column 0 is `[a, c]`, column 1 is `[b, d]`.
#
# Concrete subclasses: Mat2<T>, Mat3<T>, Mat4<T> (square fixed-size),
# plus Mat<T, M, N> (rectangular).
+ Matrix<T> < Number
  with T in (
    f16 f32 f64 f80 f128 f256
    bf16 tf32 fp8 fp4 nf4
    mxfp8 mxfp6 mxfp4
    posit8 posit16 posit32 posit64
    i8 i16 i32 i64 i128
    u8 u16 u32 u64 u128
  )

  # Shape — concrete subclasses supply.

  # Row count.
  -> rows

  # Column count.
  -> cols

  -> shape
    [rows, cols]

  -> square?
    rows == cols

  -> element_count
    rows * cols

  # Element access.

  # Element at (row, col), column-major: elements[col * rows + row].
  -> at(r, c)
    elements[c * rows + r]

  # Componentwise arithmetic.

  -> negate
    class.new(elements.map -> -item)

  -> -@
    negate

  -> +/1
    class.new(elements.zip(@1.elements).map -> item[0] + item[1])

  -> -/1
    class.new(elements.zip(@1.elements).map -> item[0] - item[1])

  # Scalar multiplication.
  -> */1(Number)
    scalar = @1
    class.new(elements.map -> item * scalar)

  -> //1(Number)
    scalar = @1
    class.new(elements.map -> item / scalar)

  # Hadamard (componentwise) product on elements — `A ⊙ B` returns
  # the elementwise product of two matrices of the SAME shape. Distinct
  # from `A * B` which is the standard matrix product.
  -> ⊙/1
    class.new(elements.zip(@1.elements).map -> item[0] * item[1])

  -> hadamard/1
    self ⊙ @1

  # Kronecker product — `A ⊗ B` for A (M×N) and B (P×Q) produces an
  # (MP)×(NQ) block matrix whose (i,j) block is A[i,j] · B. Returns a
  # generic Mat<T, M*P, N*Q>; for explicit 2/3/4 sizes the concrete
  # subclasses can override. Column-major fold.
  -> ⊗/1
    a = elements
    b_elems = @1.elements
    am = rows
    an = cols
    bm = @1.rows
    bn = @1.cols
    rm = am * bm
    rn = an * bn
    elems = (0...(rm * rn)).map ->
      c = i / rm
      r = i % rm
      ac = c / bn
      ar = r / bm
      bc = c % bn
      br = r % bm
      a[ac * am + ar] * b_elems[bc * bm + br]
    Mat<T, rm, rn>.new(elems ## T[rm * rn])

  -> kronecker/1
    self ⊗ @1

  # Direct sum — block-diagonal stack of self and other. For A (M×N) and
  # B (P×Q) returns the (M+P)×(N+Q) matrix with A in the top-left, B in
  # the bottom-right, and zeros elsewhere. Available as `A.direct_sum(B)`
  # but no symbolic operator (⊕ is reserved if ever needed).
  -> direct_sum/1
    am = rows
    an = cols
    bm = @1.rows
    bn = @1.cols
    rm = am + bm
    rn = an + bn
    elems = (0...(rm * rn)).map ->
      c = i / rm
      r = i % rm
      if c < an && r < am
        elements[c * am + r]
      elsif c >= an && r >= am
        @1.elements[(c - an) * bm + (r - am)]
      else
        0 ## T
    Mat<T, rm, rn>.new(elems ## T[rm * rn])

  # Linear algebra.

  # Matrix-matrix product. Concrete subclasses implement (shape-aware).
  -> */1

  # Matrix-vector product. Concrete subclasses implement.
  -> */1

  # Transpose. Concrete subclasses implement (returns the correct
  # shape — Mat3 stays Mat3, Mat<M,N> returns Mat<N,M>).
  -> transpose

  # Square-only — concrete subclasses implement.
  -> determinant
  -> det
    determinant
  -> inverse
  -> trace

  # Equality / comparison.

  -> ==/1
    @1.rows == rows && @1.cols == cols && elements == @1.elements

  -> !=/1
    !(self == @1)

  # Frobenius norm — universal across shapes.
  -> abs
    elements.pythagorean

  -> abs2
    elements/sq:sum

  # Conversion

  -> to_s

  -> hash

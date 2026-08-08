# ComplexArray — N complex numbers in one contiguous interleaved f64 buffer:
# [re0, im0, re1, im1, …]. One 128-bit vector per element is exactly the
# layout FEAT_FCMA's FCMLA instructions want, so the bulk operations call
# the w_carr_* NEON kernels (runtime.c) instead of allocating a boxed
# Complex per element. Reads materialize bare Complex values on demand.
#
#   xs = ComplexArray.new(3)
#   xs[0] = Complex.new(1.0, 2.0)
#   ys = xs.mul(zs)          # elementwise complex multiply (FCMLA)
#   d  = xs.conj_dot(ys)     # Σ conj(x_i)·y_i → Complex
+ ComplexArray
  -> new(n)
    @size = n
    @data = f64[n * 2]

  # Wrap an existing interleaved f64[] backing (length 2N) without copying.
  -> .wrap(backing, n)
    inst = ComplexArray.new(0)
    inst.adopt(backing, n)
    inst

  -> .from(values)
    inst = ComplexArray.new(values.size)
    values.each_with_index -> (z, idx) inst[idx] = z
    inst

  # Internal: rebind this instance to a backing buffer. Used by .wrap and
  # the kernel-returning ops; not part of the public surface.
  -> adopt(backing, n)
    @size = n
    @data = backing
    self

  -> size
    @size

  -> data
    @data

  -> [](i)
    Complex.new(@data[2 * i], @data[2 * i + 1])

  -> []=(i, z)
    @data[2 * i] = z.real
    @data[2 * i + 1] = z.imag

  -> each/&
    i = 0
    while i < @size
      &(Complex.new(@data[2 * i], @data[2 * i + 1]))
      i += 1

  # Elementwise complex multiply — the FCMLA kernel.
  -> mul/1
    ComplexArray.wrap(ccall("w_carr_mul_f64", @data, @1.data), @size)

  # Conjugate dot product Σ conj(self_i)·other_i → Complex.
  -> conj_dot/1
    pair = ccall("w_carr_conj_dot_f64", @data, @1.data)
    Complex.new(pair[0], pair[1])

  # Scale every element by a complex (or real) scalar.
  -> scale/1
    if @1.respond_to?("components")
      return ComplexArray.wrap(ccall("w_carr_scale_f64", @data, @1.real, @1.imag), @size)
    ComplexArray.wrap(ccall("w_carr_scale_f64", @data, @1, 0.0), @size)

  # Componentwise add/sub ride the existing f64 elementwise NEON kernels —
  # interleaved complex addition is plain f64 addition.
  -> +/1
    ComplexArray.wrap(@data .+ @1.data, @size)

  -> -/1
    ComplexArray.wrap(@data .- @1.data, @size)

  -> to_a
    out = []
    each -> (z) out.push(z)
    out

  -> to_s
    parts = []
    each -> (z) parts.push(z.to_s)
    "ComplexArray(" + parts.join(", ") + ")"

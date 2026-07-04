# Hypercomplex — the Cayley–Dickson algebras above the reals:
# Complex (dimension 2), Quaternion (4), Octonion (8), Sedenion (16).
#
# Parameterized by the component scalar type T. Every concrete
# subclass stores `T components[N]` where N is the algebra's
# dimension; named accessors (.w/.x/.y/.z, .h/.i/.j/.k, .e0…eN) wrap
# the index.
#
# Scalar position is parameterized by `scalar_index`: default 0
# (scalar-first; Complex, Quaternion, Octonion, Sedenion follow this).
# QuaternionMetal overrides to dimension - 1 to match Metal's float4
# layout where the scalar lives at `.w`.
#
# These algebras carry no natural total order, so `<=>` ranks values
# by magnitude (the norm); `==` stays exact and componentwise — `i`
# and `1` share a magnitude but are not equal.
+ Hypercomplex<T> < Number
  with T in (
    f16 f32 f64 f80 f128 f256
    bf16 tf32 fp8 fp4 nf4
    mxfp8 mxfp6 mxfp4
    posit8 posit16 posit32 posit64
  )

  is Comparable

  # Magnitude

  # Squared norm: Σ cᵢ². Exact for integer T, no square root.
  -> abs2
    components/sq:sum

  # Norm / modulus: √(Σ cᵢ²).
  -> abs
    components.pythagorean

  -> norm
    abs

  # Argument / phase: the angle from the positive real axis to this value,
  # atan2(|Im z|, Re z) ∈ [0, π] — the companion to `abs` that completes the
  # polar form z = |z|·(cos θ + sin θ·û). Complex overrides this with the
  # signed 2-D Argand angle (where the imaginary part carries a sign).
  -> arg
    Math.atan2(imaginary.abs, real)

  # Comparison

  # Ordered by magnitude — the algebra itself is unordered.
  -> <=>/1
    abs2 <=> @1.abs2

  # Exact, componentwise equality (overrides the magnitude-based `==`
  # that Comparable would otherwise derive from `<=>`).
  -> ==/1
    @1.dimension == dimension && components == @1.components

  -> !=/1
    !(self == @1)

  # Approximate, componentwise equality for numerical work. `==` stays
  # exact so hashing / identity-sensitive code keeps deterministic behavior.
  -> approx?/1
    approx?(@1, ~0.000001)

  -> approx?/2
    return false if scalar_like?(@1)
    return false if @1.dimension != dimension
    components.each_with_index -> return false if (item - @1.components[i]).abs > @2
    true

  # Algebra

  # Cayley–Dickson conjugate: keep the scalar component, negate the rest.
  -> conjugate
    class.new(components.map_with_index -> (item, i) i == scalar_index ? item : -item)

  # Negate every component.
  -> negate
    class.new(components.map -> -item)

  -> -@
    negate

  # Componentwise addition.
  -> +/1
    return scalar_add(@1) if scalar_like?(@1)
    class.new(components.zip(@1.components).map -> item[0] + item[1])

  # Componentwise subtraction.
  -> -/1
    return scalar_sub(@1) if scalar_like?(@1)
    class.new(components.zip(@1.components).map -> item[0] - item[1])

  # Cayley–Dickson product. Non-commutative for dim ≥ 4 (Quaternion+);
  # non-associative for dim ≥ 8 (Octonion+); has zero divisors at
  # dim 16 (Sedenion). Dimension-dependent; concrete subclasses
  # implement.
  -> */1

  # Division: self * other.reciprocal.
  -> //1
    return scalar_div(@1) if scalar_like?(@1)
    self * @1.reciprocal

  # Integer power via repeated multiplication.
  -> **/1
    return one if @1 == 0

    return reciprocal ** -@1 if @1.negative?

    result = self

    @1.prev -> result *= self

    result

  # Identity / Inverse

  # Additive identity of this algebra: [0, 0, …, 0].
  -> zero
    class.new((0...dimension).map -> 0 ## T)

  # Multiplicative identity: 1 in the scalar slot, 0 elsewhere. The block param
  # is named so `scalar_index` resolves to the method, not a second free var.
  -> one
    class.new((0...dimension).map -> (i) i == scalar_index ? 1 ## T : 0 ## T)

  # Multiplicative inverse: conjugate / abs2.
  # Note: for Sedenion (the first Cayley–Dickson algebra with zero
  # divisors), this formula returns a value for any nonzero input but
  # that value is NOT a multiplicative inverse when self is a zero
  # divisor — `self * reciprocal != one` in that case. Check
  # `is_zero_divisor_pair?` (Sedenion-specific) before relying on
  # reciprocal at Sedenion or higher dimensions.
  -> reciprocal
    den = abs2
    raise "division by zero" if den == 0
    conjugate.scalar_div(den)

  -> inverse
    reciprocal

  # True when this value's reciprocal is a genuine two-sided inverse.
  # For Complex / Quaternion / Octonion this is equivalent to `!zero?`.
  # For Sedenion and higher it rejects nonzero zero divisors.
  -> invertible?
    return false if zero?
    r = reciprocal
    self * r == one && r * self == one

  -> regular?
    invertible?

  # Commutator [a, b] = a·b − b·a. Measures non-commutativity; zero for
  # Complex (commutative), generally non-zero from Quaternion onward.
  -> commutator/1
    self * @1 - @1 * self

  # Associator [a, b, c] = (a·b)·c − a·(b·c). Measures non-associativity;
  # zero for Complex and Quaternion (associative), generally non-zero
  # from Octonion onward.
  -> associator/2
    (self * @1) * @2 - self * (@1 * @2)

  # True when |a·b| = |a|·|b| — the multiplicative-norm property of the
  # four normed division algebras (Real, Complex, Quaternion, Octonion).
  # Sedenion is the first Cayley–Dickson level where this fails.
  -> norm_preserves?/1
    (self * @1).abs2 == abs2 * @1.abs2

  ## Algebraic-identity predicates.
  ##
  ## These are computational tests using only multiplication; they
  ## inherit through the whole Hypercomplex tower and return true or
  ## false depending on which algebra `self` belongs to. Together they
  ## let a caller empirically detect which Cayley–Dickson family the
  ## value lives in (associative / alternative / power-flexible).

  # Flexibility: (a·b)·a == a·(b·a). The bottom floor of identities —
  # universal across the entire Cayley–Dickson tower, holds forever.
  -> flexible?/1
    (self * @1) * self == self * (@1 * self)

  # Left alternative: a·(a·b) == (a·a)·b. True through Octonion; fails
  # at Sedenion onward.
  -> left_alternative?/1
    self * (self * @1) == sq * @1

  # Right alternative: (b·a)·a == b·(a·a). Same level as left
  # alternative — Octonion ✓, Sedenion ✗.
  -> right_alternative?/1
    (@1 * self) * self == @1 * sq

  # Both alternatives — what "alternative algebra" usually means.
  # The full alternativity-of-self-with-@1 check.
  -> alternative?/1
    left_alternative?(@1) && right_alternative?(@1)

  # Moufang identities — three equivalent forms in alternative algebras
  # (so all three hold through Octonion). Generally fail at Sedenion+.

  -> moufang_left?/2
    ((self * @1) * self) * @2 == self * (@1 * (self * @2))

  -> moufang_right?/2
    @2 * ((self * @1) * self) == ((@2 * self) * @1) * self

  -> moufang_central?/2
    (self * @1) * (@2 * self) == self * ((@1 * @2) * self)

  # Jordan identity: (a²)·(b·a) == ((a²)·b)·a. Implied by alternativity;
  # fails at Sedenion onward.
  -> jordan_identity?/1
    sq * (@1 * self) == (sq * @1) * self

  # Power-associativity check: (a²)·a == a·(a²). Universal — holds at
  # every Cayley–Dickson level forever (the other floor identity).
  -> power_associative_check?
    sq * self == self * sq

  # Zero-divisor pair: both nonzero, but their product is zero. Vacuously
  # false for Complex / Quaternion / Octonion (no zero divisors); the
  # first level where this can be true for nonzero operands is Sedenion.
  # When true, `reciprocal` is well-defined arithmetically but NOT a
  # multiplicative inverse for `self`.
  -> is_zero_divisor_pair?/1
    !zero? && !@1.zero? && (self * @1).zero?

  # Geometry

  # Inner product: Σ aᵢ·bᵢ.
  -> dot/1 0
    components.each_with_index -> acc += item * @1.components[i]

  # Same direction, magnitude 1.
  -> normalize
    raise "cannot normalize zero hypercomplex value" if zero?
    scalar_div(abs)

  # Predicates

  -> zero?
    abs2 == 0

  # Multiplicative identity check. Overrides Number's `self == 1` (which
  # would compare a hypercomplex value to the integer 1 — wrong shape);
  # compares to the algebra's identity element instead.
  -> one?
    self == one

  -> unit?
    abs2 == 1

  # True when only the scalar component is nonzero (every other
  # component is zero, regardless of where the scalar lives).
  -> is_real?
    components.each_with_index -> (item, i) return false if i != scalar_index && item != 0
    true

  # True when only the imaginary part is nonzero (no scalar component).
  -> pure?
    real == 0 ## T

  # Scalars do not expose the structural `components` accessor. This keeps
  # scalar arithmetic separate from Cayley-Dickson products without relying
  # on generic class identity, which is specialization-dependent.
  -> scalar_like?/1
    !@1.respond_to?("components")

  # Scalar arithmetic: combine `@1` (the scalar operand) with the scalar
  # component only. Inside these blocks `@1` resolves to the method's
  # argument, while `item`/`i` are the block's own iteration bindings.
  -> scalar_add/1
    class.new(components.map_with_index -> (item, i) i == scalar_index ? item + @1 : item)

  -> scalar_sub/1
    class.new(components.map_with_index -> (item, i) i == scalar_index ? item - @1 : item)

  -> scale/1
    class.new(components.map -> item * @1)

  -> scalar_div/1
    raise "division by zero" if @1 == 0
    class.new(components.map -> item / @1)

  # Parts

  # Scalar (real) component.
  -> real
    components[scalar_index]

  # Pure-imaginary part: this value with its scalar component zeroed.
  -> imaginary
    class.new(components.map_with_index -> (item, i) i == scalar_index ? 0 ## T : item)

  # Component count: 2, 4, 8, or 16.
  -> dimension
    components.size

  # Storage index of the scalar component. Default 0 (scalar-first);
  # Quaternion overrides to `dimension - 1` for Metal float4 alignment.
  -> scalar_index
    0

  # Cayley–Dickson half-algebra: the lower-dim Hypercomplex doubled to
  # produce this one. Quaternion's half is Complex, Octonion's half is
  # Quaternion, and so on up the tower. Complex returns nil (it
  # bottoms out at T — the scalar type, not another Hypercomplex).
  # Concrete subclasses supply the value.
  -> half_class

  # Iteration

  -> each_component/&
    components.each -> &(item)

  # Indexed basis accessor. Low-dim subclasses (Complex / Quaternion /
  # Octonion / Sedenion) supply individual `e0` / `e1` / … methods as
  # compile-time-constant fast paths; higher-dim algebras (Trigintaduonion
  # and up — 32, 64, 128, 256 components) rely on this universal form
  # since enumerating named accessors stops being practical.
  -> e(n)
    components[n]

  # Generic SIMD gather: `q.shuffle([3, 0, 1, 2])` returns the components
  # at those indices as a `T[N]`. Quaternion supplies named fast-path
  # variants (`.xyz`, `.wzyx`, `.xxxx`, etc.) for common patterns; this
  # is the generic fallback for arbitrary permutations.
  -> shuffle/1
    components.shuffle(@1)

  # Conversion

  -> to_s
    class_name + "(" + components.join(", ") + ")"

  -> hash

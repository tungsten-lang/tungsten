# Exact algebra

`use algebra` loads the exact coefficient-domain, polynomial, ideal, and
geometry layers. `Rational` remains a numeric scalar in
`core/numeric/rational.w`; `Field` is the algebra-side protocol describing how
such scalars behave as coefficients.

Exact polynomial derivatives and integrals live here. Smooth numerical
Taylor series, gradients, Hessians, and quadrature are provided by
`use calculus`; see
[scientific-computing/calculus.md](scientific-computing/calculus.md).
Canonical symbolic expressions and the exact `Expression` ↔ `Polynomial`
bridge are documented in [symbolic.md](symbolic.md).

The trust model, Wassat/WRAT boundary, descent dependency graph, and
FLT-scale roadmap are in [certified-mathematics.md](certified-mathematics.md).

## Layout

```text
core/algebra.w                     # orchestrator + Algebra facade
core/algebra/field.w               # Field protocol, RationalField
core/algebra/finite_field.w        # 𝔽_p and arbitrary finite extensions
core/algebra/polynomial.w          # rings, sparse ops, division, content
core/algebra/polynomial_resultant.w
core/algebra/polynomial_gcd.w
core/algebra/polynomial_factor.w # exact factorization over ℚ
core/algebra/polynomial_factor_finite.w # complete finite-field factorization
core/algebra/simple_extension.w   # certified K[a]/(m) quotient fields
core/algebra/real_roots.w          # Sturm isolation and certified RootOf values
core/algebra/algebraic_real.w      # exact RootOf arithmetic and certificates
core/algebra/expression.w          # symbolic factor and exact real solve facade
core/algebra/number_field.w        # exact number fields; cubic maximal orders
core/algebra/groebner.w            # Buchberger, Ideal, eliminate, saturate
core/algebra/f2_linear.w           # replay-certified linear algebra over F2
core/algebra/projective.w          # projective spaces and normalized points
core/algebra/curves.w              # plane, elliptic, and hyperelliptic models
core/algebra/divisors.w            # rational/closed places, formal divisors
core/algebra/quartics.w            # certified line intersections and bitangents
core/algebra/descent.w             # BPS preparation, bitangent proofs, F2 kernel
core/algebra/point_search.w        # exact bounded search for one quartic family
core/algebra/quartic_invariants.w  # ternary resultant, discriminant, I27
core/algebra/automorphisms.w       # normalized-hyperflex certificate
core/algebra/zeta.w                # reduction, point counts, zeta, Weil cubic
core/algebra/galois.w              # reciprocal genus-three Weil sextics
```

## Surface syntax

The ordinary object API is always available:

```w
use algebra

P2 = ProjectiveSpace<ℚ, 2>.new(:B, :S, :Z)
B = P2.coords[0]
S = P2.coords[1]
Z = P2.coords[2]
f = B**3*Z*16 + B*S**2*Z*48 - S**4*3
f += S**3*Z*8 + S**2*Z**2*162 + Z**4*729
C = Curve.new(P2, f)
C.assert_homogeneous(4)

x = Poly<ℚ>.new(:x).generator
F = FiniteField.new(5)
F125 = FiniteField.extension(5, 3)
F256 = FiniteField.extension(2, 8)
R = PolynomialRing.new([:t], F)
t = R.generator(0)
E = Algebra.extension(t**2 + t + 1, :a)
K = NumberField.new(x**3 + x**2*2 - x*9 - 12, :a)
```

Finite extensions use a packed base-\(p\) power basis in every degree. Rabin's
Frobenius/GCD criterion certifies the selected modulus, including composite
degrees where “no base-field root” would be insufficient:

```w
F16 = FiniteField.extension(2, 4)
a = F16.generator

F16.modulus                              # [1, 1, 0, 0, 1]
F16.modulus_certificate.verified?
F16.frobenius(a, 4) == a
F16.trace(a)                             # 0 in F₂
F16.norm(a)                              # 1 in F₂
F16.minimal_polynomial(a, :x)            # x⁴ + x + 1
F16.minimal_polynomial_certificate(a, :x).verified?
```

Deterministic modulus search is explicitly resource-bounded. Small geometry
fields cache their exact multiplication table; larger fields retain sparse
packed convolution and modular reduction.

Univariate polynomials over prime and extension finite fields have complete
factorization with multiplicity. The exact pipeline handles inseparable
polynomials by recursive p-th roots, then uses distinct-degree factorization
and deterministic equal-degree splitting:

```w
F4 = FiniteField.extension(2, 2)
R4 = PolynomialRing.new([:x], F4)
x = R4.generator(0)
a = R4.monomial_raw(F4.generator, R4.zero_exponents)
f = (x**2 + x + a) * (x**2 + a*x + a)

f.factor
proof = f.factor_with_certificate
proof.certified?                            # true
proof.certificate.verified?                 # independently replays product
```

The certificate also proves each returned nonconstant factor irreducible with
Rabin's criterion. Equal-degree candidate enumeration has an explicit limit
and raises `unknown` on exhaustion instead of returning a partial result.

`SimpleExtensionField` is the exact quotient \(K[a]/(m)\) for an explicit base
field and a certified irreducible modulus. It supplies the missing tower-field
representation: unlike packed absolute finite fields, an extension of
\(\mathbb F_{p^r}\) retains a canonical embedding of that particular base
presentation.

```w
F4 = FiniteField.extension(2, 2)
R = PolynomialRing.new([:u], F4)
u = R.generator(0)
a = R.monomial_raw(F4.generator, R.zero_exponents)
F16_over_F4 = Algebra.extension(u**2 + u + a, :b)
b = F16_over_F4.generator

b**2 + b + F16_over_F4.embed_base_element(F4.generator) # 0
F16_over_F4.order                         # 16
F16_over_F4.trace(b)                      # trace to F4
F16_over_F4.norm(b)                       # norm to F4
F16_over_F4.modulus_certificate.verified?
```

Every base change names both source and target through `Field#embed_from`.
This preserves packed base-field residues and rejects a map between unrelated
finite-field presentations unless Tungsten actually knows the embedding.
Finite simple extensions support enumeration, Frobenius, polynomial
factorization, exact determinants, projective normalization, and curve point
counts. The same quotient API works over ℚ; use `NumberField` when
maximal-order arithmetic or certified real embeddings are required.

`NumberField` arithmetic is degree-generic. The defining polynomial is
certified irreducible over ℚ, and elements expose exact minimal and
characteristic polynomials, trace, norm, integrality, and certified real
embeddings:

```w
K4 = NumberField.new(x**4 + 1, :a)
a = K4.generator
b = a + a**3

b.minimal_polynomial                     # x² + 2
b.minimal_polynomial_certificate.verified?
b.characteristic_polynomial              # (x² + 2)²
b.trace                                  # 0
b.norm                                   # 4

R = Poly<NumberField>.new(Algebra.field(K4), [:u])
P2K = ProjectiveSpace<NumberField, 2>.new(
  Algebra.field(K4), 2, [:X, :Y, :Z])
```

The type argument is the `NumberField` family tag; `Algebra.field(K4)` is the
actual coefficient field object. Power-basis arithmetic, discriminants, and
signatures work in every supported degree. Integral bases, maximal-order
indices, and field discriminants remain certified only for cubics; asking for
one on a noncubic field raises instead of relabeling the power-order value.

Inside a curve declaration, adjacency is local polynomial multiplication.
Both superscript and ASCII powers are accepted, and coefficients may be
rational:

```w
C ⊂ ℙ²_ℚ (X, Y, Z) : (1/2)X^3Z + 3XY²Z - Y⁴ = 0
```

Giving `N + 1` coordinates declares a homogeneous equation in `ℙⁿ`. Giving
`N` coordinates declares the affine chart whose final homogeneous coordinate
is one:

```w
C ⊂ ℙ²_ℚ (x, y) : 16x^3 + 48xy² - 3y⁴ + 729 = 0
```

Projective points use colon-separated coordinates and are normalized by their
field:

```w
P3 = ProjectiveSpace<ℚ, 3>.new(:W, :X, :Y, :Z)
p = P3[2:0:0:0]        # [1:0:0:0]
q = P3.point([1, 2, 3, 4])
```

Public point and polynomial-evaluation APIs treat integers as external scalars,
so over an extension field `F = FiniteField.extension(5, 2)` the integer `5`
embeds as zero in the prime subfield. Packed extension residues are deliberately
explicit: use `point_raw`, `homogenize_raw`, `at_raw`, `evaluate_raw`,
`substitute_raw`, `monomial_raw`, `monomial_multiply_raw`, `Line.raw`, or
`Algebra.determinant_raw` only when a value is already encoded by `F`.

Plane-curve line intersections over ℚ and arbitrary finite fields factor the
binary restriction exactly. Rational roots become ordinary `Place` objects;
higher-degree irreducibles become certified `ClosedPlace` objects whose degree
is the residue-field degree:

```w
L = Line.new(P2, B)
intersection = C.line_intersection(L)
intersection.certified?                    # true
D = intersection.divisor
D.degree                                   # degree(C), by Bézout
D.terms.map -> item[1].residue_degree
intersection.factorization.certificate.verified?
```

The construction accounts for the omitted point at infinity, preserves
inseparable multiplicities as divisor coefficients, and reconstructs the same
divisor from either affine chart on the parameter line. A higher-degree
`ClosedPlace` builds its certified `SimpleExtensionField`, base-changes the
curve and line, and realizes `point` over that residue field:

```w
P = D.terms.detect -> item[1].degree > 1
closed = P[1]
closed.residue_polynomial
closed.residue_field
closed.residue_curve.contains?(closed.point)       # true
closed.residue_line.contains?(closed.point)        # true
closed.residue_certificate.verified?               # true
```

The compact grammar is intentionally confined to algebra entry points. It
does not add global implicit multiplication or change ordinary numeric
operator dispatch. Enabling it requires a real `use algebra` (or
`use core/algebra/...`) directive — comments and string literals do not count.

## Layers and capability status

| Layer | Available now | Boundary |
| --- | --- | --- |
| Symbolic expressions | Exact π/e and radicals; canonical simplify, expand, collect, differentiation, elementary antiderivatives; exact formal Taylor series and removable finite limits; exact univariate ℚ factor facade; arbitrary exact real roots as rationals, radicals, or certified `RootOf` constants; exact arithmetic and symbolic transcendentals over real algebraic constants | No assumptions, piecewise forms, Laurent/Puiseux series, infinite/directional limits, general multivariate factorization, complex algebraic-root object, general higher-degree radical formulas, or Risch integration |
| Fields | Exact `RationalField`; packed prime fields and arbitrary absolute extensions `𝔽_{p^n}`; certified simple extensions `K[a]/(m)` over ℚ or finite fields with explicit base embeddings, structured finite towers, arithmetic, Frobenius, trace, norm, and enumeration; arbitrary-degree irreducible `NumberField`s over ℚ with exact power-basis arithmetic, minimal/characteristic polynomials, trace, norm, integrality, Sturm signatures, and certified real embeddings; certified cubic integral bases and maximal-order discriminants | Automatic isomorphisms/embeddings between differently presented finite fields, simple extensions over coefficient fields whose polynomials cannot yet be factored, complex algebraic embeddings, noncubic number-field maximal orders/integral bases, and general number-field isomorphism algorithms are not implemented. Modulus/factor search and cubic maximal-order search are explicitly resource-bounded and raise instead of guessing |
| Polynomials | Sparse sorted terms; merge-multiply; dense univariate quotient arithmetic; `lex`/`grlex`/`grevlex`/product orders; division, content, multivariate primitive GCD, subresultant resultant, discriminant; exact factorization over ℚ and arbitrary finite fields as **unit × monic irreducibles**, with replay certificates; exact Sturm counts, Cauchy bounds, and certified isolation of every distinct real root | Kronecker and deterministic equal-degree factor search, Gröbner elimination, and root-interval splitting have explicit resource limits; complex-root isolation, complex algebraic-number arithmetic, and multivariate factorization are not implemented |
| Ideals | Reduced Gröbner bases, membership, sum, equality; principal **saturation** `I : f^∞`; **elimination** ideals under eliminating orders | Ideal saturation by a non-principal ideal (full irrelevant ideal) is not a single primitive; F4/F5 are not implemented |
| Projective geometry | Arbitrary `ℙⁿ` over ℚ, packed or structured finite fields, simple extensions, and exact number fields; normalized points, affine charts, homogenize/dehomogenize | `Curve` currently models projective planes, even though `ProjectiveSpace` itself has arbitrary dimension |
| Plane curves | Homogeneity, membership, singular-locus ideal, chart-based nonsingularity, smooth plane genus, Jacobian dimension | Singular-curve normalization is not implemented |
| Elliptic curves | Composition around a plane cubic model; short Weierstrass group law over ℚ and `𝔽_p` (char ≠ 2, 3); `EllipticJacobian` view | Arbitrary plane cubic → Weierstrass needs a rational flex (not implemented) |
| Hyperelliptic curves | Exact `y² = f(x)` models, Mumford pairs, Cantor composition; monic odd-degree over ℚ, monic-or-scalable over `𝔽_p` | Even-degree models still raise for Jacobian arithmetic |
| Finite-curve arithmetic | Exact reduction from ℚ, certified base change through explicit field embeddings, packed absolute and structured tower extensions, projective point counts, Frobenius traces, zeta numerators (regressed through a genus-six plane quintic), and genus-three real Weil cubics | Full zeta numerators currently start over a prime field; direct/fiber point counting is exact but exponential in field size, and higher-genus Weil-polynomial postprocessing is not yet generalized beyond the existing curve/zeta primitives |
| Galois groups | Exact general groups in degrees at most three over ℚ; a certified classifier for irreducible reciprocal genus-three Weil sextics using modular irreducibility witnesses and exact Kummer square classes | This is not a general sextic classifier. Missing modular witnesses and unsupported shapes raise `unknown` or a capability error |
| Ternary quartic invariants | Exact Macaulay resultant, integral-normalized ternary-quartic discriminant, and Magma-default-scale `I27` via `dixmier_ohno.last` | The other twelve Dixmier–Ohno invariants are not implemented; `dixmier_ohno` intentionally returns a partial object |
| Lines and bitangents | Exact line restriction; certified intersection divisors over ℚ and arbitrary finite fields, including residue degrees, multiplicities, both parameter charts, and explicit points on certified residue fields; complete base-field-rational bitangent enumeration for plane quartics over odd finite fields | Line-intersection factorization over number fields and geometric bitangents over the algebraic closure are not implemented |
| Divisors | Exact formal arithmetic on rational and line-presented higher-degree closed places; certified principality for zero and certified nonprincipality of exactly `2(Q-P)` on a smooth nonhyperelliptic curve of genus at least two (char ≠ 2) | General function-field divisors, divisor-class arithmetic outside the existing Jacobian models, and general principality tests are not implemented |
| Rational points | Complete exact bounded search for primitive points on `aX³Z + bXY²Z + g(Y,Z)`, with nonzero same-sign `a,b` and nonzero `Y⁴` coefficient | This is not a general plane-curve point finder and does not prove that no points exist above the requested height |
| Geometric automorphisms | Exact triviality certificate over `Qbar` for smooth rational plane quartics with the unique normalized hyperflex `[1:0:0]`, tangent `Z=0`, and identity stabilizer | It is not an arbitrary plane-quartic automorphism-group algorithm and does not enumerate nontrivial groups |
| Descent and rank | Replay-certified F2 systems and intersections of statement-bound, caller-supplied constraints; a certified geometric prefix for BPS generalized explicit 2-descent; arbitrary-degree quotient number fields; for the shell-width quartic, a checked degree-27 bitangent projection split into squarefree pieces of degrees 6, 9, and 12 | The BPS divisor/function family, finite-product étale algebra layer, noncubic maximal orders, unconditional S-class groups and S-units, a certified ambient square-class basis, theta Galois modules, p-adic local images, and the comparison kernel remain missing. `Jacobian#rank` and `rank_upper_bound` still raise |

`Curve#hyperelliptic_plane_model?` is specifically the smooth plane-model
test. Smooth plane curves of genus at least two are non-hyperelliptic; an
explicit double-cover model belongs in `HyperellipticCurve`.

## Certified real roots

Univariate rational polynomials expose exact root counts and complete
isolation:

```w
R = PolynomialRing.new([:x], RationalField.new)
x = R.generator(0)
f = x**3 - x + 1

f.sturm_root_count(-2, 0)    # 1, strictly inside the interval
f.real_root_count            # 1
f.cauchy_root_bound          # every complex root has smaller absolute value

isolation = f.real_root_isolation
isolation.certified?         # true
root = isolation.roots[0]
root.certificate.certified?  # true
root.interval
root.refined(20).interval
root.approximation(30)       # exact Rational midpoint
root.to_f                    # machine approximation
```

`RootIsolationCertificate` independently recomputes the squarefree Sturm
sequence, proves that the rational open interval contains exactly one root,
and binds its ordered real-root index. `RealRootIsolation` additionally proves
that the sorted list is complete for the original polynomial. Repeated roots
appear once. Approximation is derived from a refinable certified interval but
is not itself a proof object. Unsupported coefficient fields and the zero
polynomial fail loudly.

Real algebraic values support exact `+`, `-`, `*`, `/`, integer powers,
negation, reciprocal, comparison across different defining presentations, and
exact `floor`, `ceil`, `round`, and `truncate`:

```w
sqrt2 = (x**2 - 2).real_roots[1]
sqrt3 = (x**2 - 3).real_roots[1]

sqrt2 + sqrt3       # RootOf(z^4 - 10z^2 + 1, 3)
sqrt2 * sqrt3       # RootOf(z^2 - 6, 1)
sqrt2 * sqrt2       # 2
sqrt2**-1           # RootOf(z^2 - 1/2, 1)
sqrt2.floor         # 1

product = sqrt2.multiply_with_certificate(sqrt3)
product.value
product.elimination_polynomial
product.certificate.certified?  # true
```

For two algebraic operands, exact block-order Gröbner elimination constructs
the polynomial satisfied by every conjugate result. Rational interval
arithmetic then refines the selected operand embeddings until only one real
root remains, and exact factorization recovers its irreducible factor.
Rational translations, scalings, and reciprocals use direct polynomial
transforms. `AlgebraicRealOperationCertificate` reconstructs the eliminant and
enclosure and verifies the unique selected root. Factor, Gröbner-pair, and
refinement limits raise instead of returning an uncertified approximation.

Ordinary operator dispatch remains receiver-directed, so write `sqrt2 / 2`.
For a rational left operand use
`Algebra.real_algebraic_value(2, "/", sqrt2)`; symbolic `Expression`
constants handle either operand order.

## Quartic arithmetic

The shell-width sequence is available through ordinary objects:

```w
Cp = C.reduce(5)
n1 = Cp.point_count
trace = Cp.frobenius_trace
L = Cp.zeta.numerator
jacobian_order = L.at(1)

h = Cp.weil_cubic
K = NumberField.new(h.polynomial, :a)
field_discriminant = K.discriminant
sextic_group = L.galois_group
```

`Curve#zeta` computes `#C(𝔽_{q^n})` for `1 ≤ n ≤ genus` and reconstructs the
numerator with exact Newton identities and the functional equation. For a
genus-three curve, `Curve#weil_cubic` returns the real cubic associated to the
reciprocal degree-six numerator. The focused sextic Galois classifier checks
the reciprocal form, Weil bounds, irreducibility witnesses, and Kummer square
classes before returning a certified group.

There is no longer a degree-three extension ceiling. For the smooth Fermat
quintic \(X^5+Y^5+Z^5=0\) over \(\mathbb F_2\), the genus-six regression
computes

```text
#C(F_{2^n}), n=1..6: [3, 5, 9, 65, 33, 65]
L(T):                 1 + 12T^4 + 48T^8 + 64T^12
```

The reference point counter remains exponential in the extension-field size;
the small-field multiplication cache changes performance, not the exact
counting contract.

For cubic fields, `Polynomial#roots_in` recognizes the defining presentation,
handles the cyclic cubic case exactly, and can rule out roots when certified
field discriminants differ. Equal-discriminant cubic fields in different
presentations still need a general field-isomorphism algorithm and raise
instead of guessing.

Quartic geometry and invariants use the same curve:

```w
i27 = C.dixmier_ohno.last
discriminant = C.ternary_quartic_discriminant

infinity = Line.new(P2, [0, 0, 1])
restriction = C.equation.restrict_to(infinity)
intersection = C.intersection_divisor(infinity)
finite_bitangents = Cp.bitangents

points = C.rational_points(height: 100_000)
automorphisms = C.geometric_automorphisms
```

`ternary_quartic_discriminant` is the integral normalization
`-Res(f_X,f_Y,f_Z)/4^7`. `dixmier_ohno.last` is the default-scale `I27`, which
is that value divided by `2^40`; the returned
`PartialDixmierOhnoInvariants` reports `complete? == false`.

The bounded point search is exhaustive only inside its documented structural
family and height box. The automorphism result is geometric, not merely
rational: its certificate proves uniqueness of the normalized hyperflex over
the algebraic closure and then proves that its saturated projective stabilizer
is the identity.

Known points can be reduced to degree-one places for the narrow certified
divisor decision:

```w
P = Cp.place([1, 0, 0])
Q = Cp.place([0, 4, 1])
result = ((Q - P) * 2).principal_result
```

For a smooth nonhyperelliptic curve of genus at least two in odd
characteristic, this exact shape is certified nonprincipal by the
degree-two-map obstruction. Other nonzero shapes raise instead of returning a
heuristic answer.

## Certification boundary

An exact result means that every arithmetic and ideal step used by that method
is checkable in its stated domain. A resource limit, a missing modular
witness, or input outside the structural family is reported as an error; it
is never silently converted into a negative mathematical claim.

The exact F2 intersection kernel needed by generalized explicit descent is
available, but the ambient basis and arithmetic producers remain separate
proof obligations. In particular, point searches, Frobenius data, torsion
bounds, bitangent counts, and divisor obstructions do not certify a Jacobian
rank. `Jacobian#rank` remains unavailable until a verified explicit-Selmer
bound, BPS comparison kernel, rational two-torsion dimension, and matching
lower bound have all been composed.

## Certified geometric prefix for plane-quartic 2-descent

A rational hyperflex supplies the rational odd theta characteristic in
Bruin--Poonen--Stoll section 6.5. Its intersection certificate verifies
`l.C = 4P = 2(2P)`. Removing that member is the geometric step that prepares
a degree-27 true descent setup instead of the generic degree-28 fake setup.
The object remains an incomplete preparation until the BPS étale scheme,
divisor/line-bundle family, and functions are constructed:

```w
infinity = Line.new(C.space, [0, 0, 1])
setup = C.jacobian.two_descent_setup(
  distinguished_bitangent: infinity
)

setup.geometric_prerequisites_certified?  # true
setup.intended_descent_kind               # :true
setup.expected_etale_degree               # 27
setup.true_setup?                         # false
setup.certified?                          # false
scheme = setup.certify_bitangent_scheme
scheme.component_degrees  # [6, 9, 12]
scheme.certified?          # true
```

For the shell-width quartic, the bitangent certificate checks supplied
projection data rather than trusting its producer. It substitutes the three
degree-6/9/12 components into the curve-derived square equations, verifies
exact divisibility with dense integer arithmetic, checks a full-degree
squarefree reduction modulo 5, excludes the remaining boundary chart, and
adds the distinguished hyperflex. The final exhaustion step explicitly carries
a `SmoothPlaneQuarticBitangentCountCertificate`. It checks the hypotheses of
the classical 28-bitangent theorem and records that theorem as a trusted
mathematical import, not as a proof-assistant-checked derivation.
The degree labels describe a checked squarefree product presentation. Each
irreducible factor can now define an arbitrary-degree `NumberField`, but the
projection pieces have not yet been factored and assembled into a certified
finite-product étale algebra with maximal orders.

The global, norm, unramified, and local conditions eventually produced by the
arithmetic layers meet in an exact F2 kernel:

```w
conditions = SelmerConstraintSystem.new(5)
conditions.add_condition("global norm", [[1, 1, 1, 0, 0]], norm_certificate)
conditions.add_condition("local image at 2", [[0, 0, 1, 1, 0]], local_certificate)
explicit = conditions.intersection_certificate

explicit.dimension
explicit.basis
explicit.certified?
```

The row-reduction certificate replays elementary operations, checks canonical
RREF, and independently verifies the kernel basis. A producer certificate must
freshly verify the exact constraint name, width, matrix, and right-hand side.
The ambient columns are not yet tied to certified square-class generators, so
this remains a checked explicit constraint intersection rather than a true
arithmetic Selmer group. `ExplicitSelmerIntersectionCertificate#rank_upper_bound`
always raises; the ambient basis and BPS comparison are still required.

For finite non-linear obligations, the optional
`bits/tungsten-wassat/lib/algebra_certificate.w` bridge exports standard CNF,
asks Wassat for a WRAT refutation, and replays it through the independent Wrat
checker. This is appropriate for theta-incidence matching, subgroup
elimination, and finite cohomology. WRAT does not certify maximal orders,
class groups, units, p-adic lifting, or the arithmetic-to-CNF translation.

## Factorization contract

```w
((x**2 + 1) * 6).factor
# => [6, x^2 + 1]

((2*x - 2) * (x + 3)).factor
# => [2, x - 1, x + 3]
```

The product of the returned factors recovers the original polynomial. The
leading constant is the content unit; every non-constant factor is monic.

## Ideal operations

```w
I = Ideal.new([x * y])
I.saturate(x)          # (y)

J = Ideal.new([u + v - 1, u - v])   # lex ring in (u, v)
J.eliminate(1)         # ideal in k[v]
```

Elimination is correct when the monomial order eliminates the first `count`
variables (lex with those variables first, or a matching product order).

# Exact algebra

`use algebra` loads the exact coefficient-domain, polynomial, ideal, and
geometry layers. `Rational` remains a numeric scalar in
`core/numeric/rational.w`; `Field` is the algebra-side protocol describing how
such scalars behave as coefficients.

Exact polynomial derivatives and integrals live here. Smooth numerical
Taylor series, gradients, Hessians, and quadrature are provided by
`use calculus`; see
[scientific-computing/calculus.md](scientific-computing/calculus.md).

The trust model, Wassat/WRAT boundary, descent dependency graph, and
FLT-scale roadmap are in [certified-mathematics.md](certified-mathematics.md).

## Layout

```text
core/algebra.w                     # orchestrator + Algebra facade
core/algebra/field.w               # Field protocol, RationalField
core/algebra/finite_field.w        # 𝔽_p and 𝔽_{p^n} (n ≤ 3)
core/algebra/polynomial.w          # rings, sparse ops, division, content
core/algebra/polynomial_resultant.w
core/algebra/polynomial_gcd.w
core/algebra/polynomial_factor.w
core/algebra/number_field.w         # exact cubic fields and maximal orders
core/algebra/groebner.w            # Buchberger, Ideal, eliminate, saturate
core/algebra/f2_linear.w           # replay-certified linear algebra over F2
core/algebra/projective.w          # projective spaces and normalized points
core/algebra/curves.w              # plane, elliptic, and hyperelliptic models
core/algebra/divisors.w            # degree-one places, small certified decisions
core/algebra/quartics.w            # lines, intersections, finite-field bitangents
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
R = PolynomialRing.new([:t], F)
K = NumberField.new(x**3 + x**2*2 - x*9 - 12, :a)
```

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

The compact grammar is intentionally confined to algebra entry points. It
does not add global implicit multiplication or change ordinary numeric
operator dispatch. Enabling it requires a real `use algebra` (or
`use core/algebra/...`) directive — comments and string literals do not count.

## Layers and capability status

| Layer | Available now | Boundary |
| --- | --- | --- |
| Fields | Exact `RationalField`; prime fields `𝔽_p`; extensions `𝔽_{p^n}` for `n ≤ 3` with Integer-encoded elements; exact irreducible cubic `NumberField`s over ℚ with arithmetic, Sturm signatures, integral bases, and maximal-order discriminants | Finite extensions above degree three and number fields of degree other than three are not implemented. Cubic maximal-order search is explicitly resource-bounded and raises `unknown` rather than guessing |
| Polynomials | Sparse sorted terms; merge-multiply; dense univariate fast path; `lex`/`grlex`/`grevlex`/product orders; division, content, multivariate primitive GCD, subresultant resultant, discriminant; exact factorization over ℚ as **content × monic irreducibles** | Kronecker factor search has an explicit resource limit; multivariate factorization is not implemented |
| Ideals | Reduced Gröbner bases, membership, sum, equality; principal **saturation** `I : f^∞`; **elimination** ideals under eliminating orders | Ideal saturation by a non-principal ideal (full irrelevant ideal) is not a single primitive; F4/F5 are not implemented |
| Projective geometry | Arbitrary `ℙⁿ` over ℚ and finite fields, normalized points, affine charts, homogenize/dehomogenize | `Curve` currently models projective planes, even though `ProjectiveSpace` itself has arbitrary dimension |
| Plane curves | Homogeneity, membership, singular-locus ideal, chart-based nonsingularity, smooth plane genus, Jacobian dimension | Singular-curve normalization is not implemented |
| Elliptic curves | Composition around a plane cubic model; short Weierstrass group law over ℚ and `𝔽_p` (char ≠ 2, 3); `EllipticJacobian` view | Arbitrary plane cubic → Weierstrass needs a rational flex (not implemented) |
| Hyperelliptic curves | Exact `y² = f(x)` models, Mumford pairs, Cantor composition; monic odd-degree over ℚ, monic-or-scalable over `𝔽_p` | Even-degree models still raise for Jacobian arithmetic |
| Finite-curve arithmetic | Exact reduction from ℚ, base change to supported finite extensions, projective point counts, Frobenius traces, zeta numerators, and genus-three real Weil cubics | Full zeta numerators start over a prime field and presently reach genus three because extension fields stop at degree three |
| Galois groups | Exact general groups in degrees at most three over ℚ; a certified classifier for irreducible reciprocal genus-three Weil sextics using modular irreducibility witnesses and exact Kummer square classes | This is not a general sextic classifier. Missing modular witnesses and unsupported shapes raise `unknown` or a capability error |
| Ternary quartic invariants | Exact Macaulay resultant, integral-normalized ternary-quartic discriminant, and Magma-default-scale `I27` via `dixmier_ohno.last` | The other twelve Dixmier–Ohno invariants are not implemented; `dixmier_ohno` intentionally returns a partial object |
| Lines and bitangents | Exact line restriction; intersection divisors for monomial restrictions; complete base-field-rational bitangent enumeration for plane quartics over odd finite fields | General binary-form factorization into residue-field places and geometric bitangents over the algebraic closure are not implemented |
| Divisors | Exact formal arithmetic on rational degree-one places; certified principality for zero and certified nonprincipality of exactly `2(Q-P)` on a smooth nonhyperelliptic curve of genus at least two (char ≠ 2) | General function-field divisors, divisor-class arithmetic, and general principality tests are not implemented |
| Rational points | Complete exact bounded search for primitive points on `aX³Z + bXY²Z + g(Y,Z)`, with nonzero same-sign `a,b` and nonzero `Y⁴` coefficient | This is not a general plane-curve point finder and does not prove that no points exist above the requested height |
| Geometric automorphisms | Exact triviality certificate over `Qbar` for smooth rational plane quartics with the unique normalized hyperflex `[1:0:0]`, tangent `Z=0`, and identity stabilizer | It is not an arbitrary plane-quartic automorphism-group algorithm and does not enumerate nontrivial groups |
| Descent and rank | Replay-certified F2 systems and intersections of statement-bound, caller-supplied constraints; a certified geometric prefix for BPS generalized explicit 2-descent; for the shell-width quartic, a checked degree-27 bitangent projection split into squarefree pieces of degrees 6, 9, and 12 | The BPS divisor/function family, arbitrary-degree étale algebras/maximal orders, unconditional S-class groups and S-units, a certified ambient square-class basis, theta Galois modules, p-adic local images, and the comparison kernel remain missing. `Jacobian#rank` and `rank_upper_bound` still raise |

`Curve#hyperelliptic_plane_model?` is specifically the smooth plane-model
test. Smooth plane curves of genus at least two are non-hyperelliptic; an
explicit double-cover model belongs in `HyperellipticCurve`.

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
The degree labels describe a checked squarefree product presentation; they
are not yet separate arbitrary-degree `NumberField` objects.

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

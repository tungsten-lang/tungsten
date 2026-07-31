# Exact algebra

`use algebra` loads the exact coefficient-domain, polynomial, ideal, and
geometry layers. `Rational` remains a numeric scalar in
`core/numeric/rational.w`; `Field` is the algebra-side protocol describing how
such scalars behave as coefficients.

New to the mathematics stack? Start with the cross-cutting map in
[mathematics.md](mathematics.md); this page is the detailed algebra reference.

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
core/algebra/etale_algebra.w      # squarefree quotients and CRT products
core/algebra/orders.w             # monogenic orders and Dedekind certificates
core/algebra/integer_lattice.w    # exact lattices and prime-field kernels
core/algebra/maximal_orders.w     # degree-generic Round 2 integral closures
core/algebra/lattice_reduction.w  # exact Gram-matrix LLL and ideal bases
core/algebra/residue_algebra.w    # reduced O/pO and primitive idempotents
core/algebra/prime_ideals.w       # residue maps and certified primes above p
core/algebra/ideal_arithmetic.w   # HNF ideals, valuations, factorizations
core/algebra/real_roots.w          # Sturm isolation and certified RootOf values
core/algebra/algebraic_real.w      # exact RootOf arithmetic and certificates
core/algebra/expression.w          # symbolic factor and exact real solve facade
core/algebra/number_field.w        # exact number fields and integral bases
core/algebra/p_adic.w              # rational Q_p square classes and Hensel lifts
core/algebra/archimedean.w         # exact real places and complex-pair counts
core/algebra/groebner.w            # Buchberger, Ideal, eliminate, saturate
core/algebra/groebner_certificates.w # proof-producing Buchberger witnesses
core/algebra/f2_linear.w           # replay-certified linear algebra over F2
core/algebra/s_units.w             # certified S-unit square-class bases
core/algebra/s_class_group.w       # Minkowski S-class 2-torsion certificates
core/algebra/p_adic_number_field.w # odd local number-field square classes
core/algebra/p_adic_dyadic.w       # complete dyadic higher-unit filtration
core/algebra/projective.w          # projective spaces and normalized points
core/algebra/curves.w              # plane, elliptic, and hyperelliptic models
core/algebra/p_adic_geometry.w     # good-reduction residue-disk covers
core/algebra/p_adic_descent.w      # certified good-reduction BPS local images
core/algebra/regular_models.w      # cuspidal bad fibers and local bounds
core/algebra/local_geometry.w      # Newton polygons and Puiseux branch lifts
core/algebra/elliptic.w            # integral Weierstrass and Frey certificates
core/algebra/elliptic_tate.w       # Tate local data, Kodaira, conductors
core/algebra/modular_forms.w       # Gamma0, X0, dimensions, Sturm bounds
core/algebra/q_expansion.w         # rational/number-field q-series, E4/E6/Delta
core/algebra/modular_symbols.w     # weight-two Manin symbols and boundaries
core/algebra/hecke.w               # certified prime Hecke operators
core/algebra/old_new.w             # degeneracy maps and old/new Hecke quotient
core/algebra/newforms.w            # simultaneous weight-two Hecke eigenpackets
core/algebra/divisors.w            # rational/closed places, formal divisors
core/algebra/quartics.w            # certified line intersections and bitangents
core/algebra/descent.w             # BPS preparation, bitangent proofs, F2 kernel
core/algebra/descent_functions.w   # contact divisors and BPS line ratios
core/algebra/descent_norm.w        # true S-unit ambient and global norm kernel
core/algebra/descent_points.w      # certified rational point-difference images
core/algebra/theta.w               # canonical 28/315 theta incidence modules
core/algebra/theta_actions.w       # exact Sp6(F2) and Frobenius cycle constraints
core/algebra/theta_fibers.w        # finite-splitting-field theta labelings
core/algebra/permutation_groups.w  # bounded exact finite permutation groups
core/algebra/theta_galois.w        # trusted-table subgroup-class replay
core/algebra/theta_subdegrees.w    # exact relative factors and global subgroup
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

A finite étale algebra is represented directly as a squarefree quotient
\(K[t]/(f)\). Supplied pairwise-coprime components give a certified Chinese
remainder decomposition without claiming the components are irreducible
fields:

```w
R = PolynomialRing.new([:t], RationalField.new)
t = R.generator(0)
f1 = t**2 - 1
f2 = t**2 - 2
A = Algebra.etale_algebra(f1*f2, [f1, f2])
a = A.generator

A.certificate.verified?
A.decomposition_certificate.verified?
A.component_degrees                         # [2, 2]
A.primitive_idempotents
A.from_components((a**3 + a + 3).components) == a**3 + a + 3
a.trace
a.norm
```

Units use exact extended gcd; nonzero zero divisors raise on inversion.
Multiplication-matrix trace and norm work over any supported exact base field.
The CRT certificate replays idempotence, orthogonality, sum-to-one, and every
component image.

For a univariate polynomial over ℚ, `Algebra.order` clears content and
denominators and replaces a root \(\alpha\) by the integral generator
\(\beta=a_n\alpha\). The result is the exact power order
\(\mathbb Z[\beta]\), not an automatically computed integral closure:

```w
R = PolynomialRing.new([:x], RationalField.new)
x = R.generator(0)
O = Algebra.order(x**2 - 5)

O.integral_polynomial                    # x² - 5
O.discriminant                           # 20
at_2 = O.index_certificate(2)
at_2.certified?                          # true
at_2.p_divides_index?                    # true
O.maximal?                               # false
O.obstructed_primes                      # [2]
M = O.maximal_order_with_certificate
M.index                                  # 2
M.order.discriminant                     # 5
M.certificate.verified?                  # true
```

Dedekind's index criterion is replayed over \(\mathbb F_p\), including a
certified modular factorization and the exact obstruction gcd. Factoring the
order discriminant is resource-bounded. Passing the criterion at every prime
whose square divides it certifies that the power order is maximal; a failed
criterion proves nonmaximality.

`maximal_order` uses the degree-generic Pohst--Zassenhaus Round 2 algorithm.
It computes the nilradical of \(O/pO\) as a Frobenius kernel, constructs the
multiplier ring of that \(p\)-radical, and repeats until the multiplier ring
is unchanged. The certificate checks the final order lattice, containment,
index/discriminant quotient, exact discriminant factorization, and a Round 2
fixed point at every relevant prime. An integral rescaling of the generator
is used as a certified initial overorder when possible; this makes highly
nonmonic presentations practical without changing the proof boundary.
`Algebra.product_order` composes component integral closures, arithmetic, and
certificates.

Prime decomposition works from the actual maximal-order lattice, including at
index divisors where factoring the original defining polynomial modulo \(p\)
would be invalid:

```w
K = NumberField.new(x**2 - 5, :a)
at_11 = K.prime_decomposition(11)

at_11.residue_degrees                    # [1, 1]
at_11.ramification_indices               # [1, 1]
at_11.norms                              # [11, 11]
P = at_11.prime_ideals[0]
P.contains?(K.coerce(11))                # true
P.reduce(K.generator)                    # element of P.residue_field
P.certificate.verified?                  # true
```

The implementation forms \(O/\sqrt{pO}\), splits that reduced finite algebra
with the Frobenius fixed space, and constructs each prime as the kernel of a
surjective map to a certified finite residue field. Frobenius-lifted primitive
idempotents in \(O/pO\) determine the local dimensions \(e_i f_i\). The
certificate replays the idempotents, residue maps, kernel lattices, norms,
ramification indices, residue degrees, and
\(\sum_i e_i f_i=[K:\mathbb Q]\). This follows the general finite-separable
algebra factorization described in
[Stein, Algorithm 4.3.7 and 4.3.9](https://wstein.org/edu/2010/581b/stein-algebraic_number_theory.pdf).
Finite étale product orders expose the same API, and `s_prime_data([2,3,13])`
collects certified finite places for descent.

`NumberField` arithmetic is degree-generic. The defining polynomial is
certified irreducible over ℚ, either directly or through a replayed relative
number-field tower. An exact root expression can transfer a tower certificate
to an isomorphic presentation after its minimal polynomial is checked.
Elements expose exact minimal and characteristic polynomials, trace, norm,
integrality, and certified real embeddings:

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
indices, and field discriminants are degree-generic. Cubics retain the older
independent HNF implementation as a regression oracle; noncubic maximal-order
data are computed lazily on first request and become visible through
`maximal_order_certificate`.

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
| Symbolic expressions | Exact π/e/Euler-γ and radicals; common-angle trig on the π/12 lattice; parity and circular/hyperbolic squared identities; canonical simplify, expand, collect, differentiation, elementary antiderivatives; symbolic `erf` / `erfc` and gamma/log-gamma/polygamma through evaluation, differentiation, integration where elementary, exact series, arbitrary-order jets, and Hessians; exact integer/half-integer gamma and integer polygamma/zeta values; exact formal Taylor, Laurent, and rational-power Puiseux series, removable finite limits, poles, principal/regular parts, residues, and ramified local branches; exact univariate ℚ factor facade; arbitrary exact real roots as rationals, radicals, or certified `RootOf` constants; exact arithmetic and symbolic transcendentals over real algebraic constants | No assumptions, piecewise forms, logarithmic/general transseries, infinite/directional limits, a general symbolic special-function catalogue beyond the implemented families, general multivariate factorization, complex algebraic-root object, general higher-degree radical formulas, or Risch integration |
| Fields | Exact `RationalField`; packed prime fields and arbitrary absolute extensions `𝔽_{p^n}` with exact square tests and quadratic characters; certified simple extensions `K[a]/(m)` over ℚ or finite fields with explicit base embeddings, structured finite towers, arithmetic, Frobenius, trace, norm, and enumeration; arbitrary-degree irreducible `NumberField`s over ℚ with modular-Rabin, modular factor-degree, Kronecker, relative-tower, or exact isomorphic-model certificates; exact power-basis arithmetic, minimal/characteristic polynomials, trace, norm, integrality, Sturm signatures, real embeddings, integral bases, maximal-order indices, field discriminants, and replay-certified supplied S-unit square-class bases | Automatic isomorphisms/embeddings between differently presented finite fields, complex algebraic embeddings, automatic unit-group generators, and general number-field isomorphism algorithms are not implemented. Modulus, factor, and maximal-order searches are explicitly resource-bounded and raise instead of guessing |
| Local fields | Exact rational elements embedded in `Q_p`; valuations, unit residues, the complete rational square-class quotients (dimension 2 for odd `p`, dimension 3 for `p=2`), and replayed simple-root Hensel lifts; at odd number-field primes, certified uniformizers and square classes from exact ideal valuations plus residue quadratic characters; at dyadic number-field primes, complete `[K_P:Q_2]+2` coordinates from the exact higher-unit filtration through `U_(2e+1)`, including the critical Artin--Schreier cokernel; certified block localization matrices from a product S-unit space to every completion above any rational prime; plane-curve residue disks indexed by the complete good special fiber or the complete smooth locus of a bad fiber; exact BPS line-ratio residues on every clean disk; certified implicit-coordinate valuations, leading units, and lower-bound BPS spans on suitable odd bad-reduction disks; complete local-image certificates either from the good-reduction Frobenius-fixed `J[2]` dimension or a certified regular cuspidal model and normalization-Jacobian bound | Arbitrary completed `Q_p` elements, precision-tracked arithmetic beyond the exact rational subfield, general local field extensions as completed objects, general regular-model construction, recursive treatment of singular residue classes or general disks containing a zero or pole, and general local Jacobian arithmetic are not implemented. Hensel lifting, local square detection, nonempty residue disks, implicit-coordinate constancy, formal-group divisibility, generalized-Jacobian/Néron comparison, and the BPS map use named trusted theorems after exact hypothesis/result replay |
| Finite étale algebras | Certified squarefree quotients `K[t]/(f)`; exact quotient arithmetic; units and zero divisors; multiplication-matrix trace/norm; supplied CRT components, primitive idempotents, component maps, reconstruction, degree-generic integral closures, prime ideals and finite residue fields above rational primes, exact real-place sign maps without assuming irreducible components, replay-certified product S-class 2-torsion proofs, and supplied product S-unit square classes modulo diagonal rational S-units | Automatic product unit discovery, full product class-group structures, and complex embeddings with selected numerical values are not implemented |
| Integral orders | Degree-generic monogenic and arbitrary-lattice ℤ-orders; exact membership, discriminant, units, trace, and norm, including bound-certified modular reconstruction for larger integer norm matrices; exact Frobenius-Gram LLL with replay certificates plus explicitly bounded floating producer reduction; Dedekind local index certificates; Pohst--Zassenhaus Round 2 p-maximal overorders and global maximal-order certificates; certified p-radicals, prime ideals, residue maps, ramification indices, and residue degrees; canonical full-rank HNF integral ideals with sum, product, powers, norm, containment, prime valuations, certified factorization, and bounded exact principal-generator search; invertible fractional ideals as finite signed prime valuations, including principal fractional ideals and exact rational norms; product-order finite S-place data; unconditional certificates for `Cl(O_K,S)[2] = 0` from Minkowski factor bases and odd principal-relation quotients; checkpointable relation witnesses and certified transfer through an exact isomorphic field model | Full class-group structures and algorithms that discover unit-group bases are not implemented. Supplied number-field S-unit square-class bases can be certified. Fractional ideals currently use their certified prime-factor representation rather than an explicit fractional lattice. Discriminant factorization, Round 2 steps, relation search, finite-field factorization, residue-generator search, and ideal factorization are resource-bounded and raise `unknown` on exhaustion |
| Polynomials | Sparse sorted terms; merge-multiply; dense univariate quotient arithmetic; `lex`/`grlex`/`grevlex`/product orders; division, content, multivariate primitive GCD, subresultant resultant, discriminant; exact factorization over ℚ and arbitrary finite fields as **unit × monic irreducibles**, with replay certificates; exact Sturm counts, Cauchy bounds, and certified isolation of every distinct real root | Kronecker and deterministic equal-degree factor search, Gröbner elimination, and root-interval splitting have explicit resource limits; complex-root isolation, complex algebraic-number arithmetic, and multivariate factorization are not implemented |
| Ideals | Reduced Gröbner bases, membership, sum, equality; principal **saturation** `I : f^∞`; **elimination** ideals under eliminating orders; representation-carrying Buchberger production with exact reduction, ideal-membership, source-containment, and S-pair witnesses | The Buchberger criterion is named as a trusted theorem import around exact replayed identities. Ideal saturation by a non-principal ideal (full irrelevant ideal) is not a single primitive; F4/F5 are not implemented |
| Projective geometry | Arbitrary `ℙⁿ` over ℚ, packed or structured finite fields, simple extensions, and exact number fields; normalized points, affine charts, homogenize/dehomogenize | `Curve` currently models projective planes, even though `ProjectiveSpace` itself has arbitrary dimension |
| Plane curves | Homogeneity, membership, singular-locus ideal, chart-based nonsingularity, smooth plane genus, Jacobian dimension, and finite exact local normalization jets | Completed local normalization rings and global normalization morphisms are not implemented |
| Local plane geometry | Exact local multiplicity and tangent cones; rational, algebraic, and vertical tangent-direction packets; lower Newton polygons and dense exact Newton--Hensel lifting; recursive repeated rational tangents; rational and algebraic Puiseux sheet packets; primitive parameterization jets; replayed source substitution and complete Newton-factor covers; theorem-labelled root-of-unity orbit branch counts; exact bivariate derivative resultants, polar intersections, Milnor numbers, general reduced delta invariants, and local intersection multiplicities | Repeated higher-degree algebraic factors, component extraction, completed local rings, semigroups/conductors, and analytic branch cuts remain missing. The Newton--Puiseux orbit, Milnor/delta, polar, and branch-valuation formulas are explicit trusted theorem imports; precision and unsupported cases raise |
| Elliptic curves | Composition around a plane cubic model; short Weierstrass group law over ℚ and `𝔽_p` (char ≠ 2, 3); exact integral long-Weierstrass \(a_i,b_i,c_4,c_6,\Delta,j\) invariants and projective closure; replay-certified admissible transformations; bounded exhaustive local and global minimal models; the complete Tate state machine over ℚ, including wild conductor exponents at 2 and 3, Kodaira symbols, Tamagawa numbers, split multiplicative status, and certified conductors; checked primitive Frey models; `EllipticJacobian` view | Arbitrary plane cubic → Weierstrass needs a rational flex; Tate local data over number fields, isogenies, and mod-\(p\) representations are not implemented |
| Modular forms | Exact `Gamma0(N)` index, cusp count, order-2/order-3 elliptic points, and \(X_0(N)\) genus; even-weight `CuspForms` and `ModularForms` dimensions; Sturm bounds; rational and number-field truncated q-series; certified level-one \(E_4,E_6,\Delta\) expansions and \(E_4^3-E_6^2=1728\Delta\); exhaustive weight-two \(P^1(\mathbb Z/N\mathbb Z)\) Manin symbols, sparse \(S/R\) relations, cusp boundaries, relative/cuspidal dimensions, and bounded exact rational cuspidal bases; exact \(T_n/U_{p^r}\) matrices from Cremona--Heilbronn prime sums plus Hecke recurrences, characteristic polynomials, degeneracy maps, old subspaces, and canonical new Hecke quotients; deterministic simultaneous newform-packet splitting by a primitive Hecke element, rational or exact number-field coefficient fields, and normalized packet q-expansions; theorem-labelled replay certificates; in particular the level-55 new quotient splits into coefficient-field degrees 1 and 2 | Dimension, Sturm, classical modularity, Manin-presentation, Hecke semisimplicity and multiplicity one, Heilbronn-action, Hecke-recurrence, Atkin--Lehner--Li, and eigenform formulas are named trusted theorem imports, not kernel proofs. Higher-weight symbols, characters, nebentypus, embeddings between independently presented coefficient fields, and analytic newform invariants are not implemented. Dense rational quotient coordinates are resource-bounded |
| Hyperelliptic curves | Exact `y² = f(x)` models, Mumford pairs, Cantor composition; monic odd-degree over ℚ, monic-or-scalable over `𝔽_p` | Even-degree models still raise for Jacobian arithmetic |
| Finite-curve arithmetic | Exact reduction from ℚ, certified base change through explicit field embeddings, packed absolute and structured tower extensions, projective point counts, Frobenius traces, zeta numerators (regressed through a genus-six plane quintic), and genus-three real Weil cubics | Full zeta numerators currently start over a prime field; direct/fiber point counting is exact but exponential in field size, and higher-genus Weil-polynomial postprocessing is not yet generalized beyond the existing curve/zeta primitives |
| Galois groups | Exact general groups in degrees at most three over ℚ; a certified classifier for irreducible reciprocal genus-three Weil sextics using modular irreducibility witnesses and exact Kummer square classes | This is not a general sextic classifier. Missing modular witnesses and unsupported shapes raise `unknown` or a capability error |
| Ternary quartic invariants | Exact Macaulay resultant, integral-normalized ternary-quartic discriminant, and Magma-default-scale `I27` via `dixmier_ohno.last` | The other twelve Dixmier–Ohno invariants are not implemented; `dixmier_ohno` intentionally returns a partial object |
| Lines and bitangents | Exact line restriction; certified intersection divisors over ℚ and arbitrary finite fields, including residue degrees, multiplicities, both parameter charts, and explicit points on certified residue fields; complete base-field-rational bitangent enumeration for plane quartics over odd finite fields | Line-intersection factorization over number fields and geometric bitangents over the algebraic closure are not implemented |
| Divisors | Exact formal arithmetic on rational and line-presented higher-degree closed places; certified principality for zero and certified nonprincipality of exactly `2(Q-P)` on a smooth nonhyperelliptic curve of genus at least two (char ≠ 2) | General function-field divisors, divisor-class arithmetic outside the existing Jacobian models, and general principality tests are not implemented |
| Rational points | Complete exact bounded search for primitive points on `aX³Z + bXY²Z + g(Y,Z)`, with nonzero same-sign `a,b` and nonzero `Y⁴` coefficient | This is not a general plane-curve point finder and does not prove that no points exist above the requested height |
| Geometric automorphisms | Exact triviality certificate over `Qbar` for smooth rational plane quartics with the unique normalized hyperflex `[1:0:0]`, tangent `Z=0`, and identity stabilizer | It is not an arbitrary plane-quartic automorphism-group algorithm and does not enumerate nontrivial groups |
| Descent and rank | Replay-certified F2 systems and intersections of statement-bound, caller-supplied constraints; a certified BPS degree-27 true setup for the shell-width quartic, with exact bitangent contact quadratics, functions `l/l0`, point evaluation in the étale algebra, maximal product order, all 20 finite primes above `S = {2,3,13}` with exact `e/f` data, and exact archimedean places; supplied number-field S-unit square-class bases are checked by ideal support plus a full-rank valuation/sign/residue matrix; statement-bound coordinate certificates express new S-units in those bases; S-class 2-torsion proofs compose across explicitly verified reducible étale decompositions; all shell-width degree-6/9/12 factors have replayed full-rank S-class proofs, and their supplied S-unit bases give a certified true-descent ambient space of dimension `9 + 12 + 14 = 35`; exact component norms give a certified rank-4 map to `Q(S,2)` and a 31-dimensional norm-one kernel; the rational divisor `[0:9:1]-[-3:-3:1]` has a certified nonzero 35-bit BPS image in that kernel and certified one-dimensional lower-bound local spans at 2 and 3; complete odd and dyadic localization matrices map the ambient basis to every number-field completion above `p`; the canonical genus-three theta model exhausts 28 odd characteristics, 315 syzygetic quadruples, and module dimensions `0,1,7,21,27,28`; exact `Sp6(F2)` matrices induce replay-certified incidence permutations and certified fixed spaces; certified good-prime factorizations constrain Frobenius cycle types; the shell-width reduction at 5 has a complete arithmetic labeling over `F_(5^6)` whose 315 contact-conic incidences and exact Frobenius element are replayed, and its seven clean disks span the complete one-dimensional local image; at bad prime 13, a certified regular one-cusp model has genus-two normalization zeta numerator `1 + 3T + 39T^3 + 169T^4` and Jacobian order `212`, bounding the local 2-quotient by dimension 2, which twelve clean smooth-locus disks attain; at 3, two implicit-coordinate disks have exact equal local values and hence certify a zero-dimensional point-difference span rather than falsely claiming progress; and exact relative factorization over the degree-6 component identifies the global theta subgroup up to conjugacy as subgroup-table class 693 of order 36 | The completeness of GAP's 1,369-class subgroup table is a named trusted external classification, not replayed internally. A common characteristic-zero root-to-theta labeling, recursive/regular-model local analysis and complete images at 2 and 3, the comparison kernel, and the final Selmer bound remain missing. `Jacobian#rank` and `rank_upper_bound` still raise |

`Curve#hyperelliptic_plane_model?` is specifically the smooth plane-model
test. Smooth plane curves of genus at least two are non-hyperelliptic; an
explicit double-cover model belongs in `HyperellipticCurve`.

## Local multiplicity and tangent cones

`singularity_at` translates a rational plane equation exactly and extracts its
lowest homogeneous part. The result distinguishes multiplicity from the
number and fields of definition of tangent directions:

```w
R = PolynomialRing.new([:x, :y], Algebra.rational_field, :lex)
x, y = R.generators

node = (y**2 - x**2 - x**3).singularity_at
node.multiplicity                         # 2
node.tangent_cone                         # y^2 - x^2
node.slope_polynomial                     # slope^2 - 1
node.tangent_direction_count              # 2
node.ordinary_singularity?                # true
node.certificate.verified?                # true

cusp = (y**2 - x**3).singularity_at
cusp.multiplicity                         # 2
cusp.tangent_directions[0].multiplicity   # 2
cusp.ordinary?                            # false
```

An irreducible slope factor is a conjugate tangent packet and exposes its
certified residue field; a missing finite-slope degree is recorded as a
vertical direction. For an ordinary \(m\)-fold point, `delta` returns
\(m(m-1)/2\). Its certificate replays multiplicity and squarefree tangent
directions, then labels the classical delta formula as a
`trusted_theorem_import`; the theorem's proof is not kernel-checked.
Nonordinary points raise rather than applying that formula.

The same entry point is available on a chart:

```w
C.singularity_at([0, 0], 2)
Algebra.local_singularity(y**2 - x**3)
```

## Newton polygons and local sheets

For a rational plane equation, `newton_polygon` translates the selected point
to the origin, computes the negative-slope lower hull, and attaches the exact
characteristic polynomial to every edge:

```w
R = PolynomialRing.new([:x, :y], Algebra.rational_field, :lex)
x, y = R.generators
f = y**2 - x*(x + 1)

N = f.newton_polygon
N.valuations                         # [1/2]
N.edges[0].characteristic_polynomial # C^2 - 1
N.edges[0].rational_roots            # [1, -1]
N.certificate.verified?              # true
```

When every edge polynomial is squarefree, `puiseux_sheets` factors it over
ℚ and performs exact Newton--Hensel lifting. `puiseux_branches` remains the
conventional alias. The result is not a floating approximation:

```w
sheets = f.puiseux_sheets(0, 1, nil, 4)
positive = sheets.detect ->
  item.leading_coefficient == Rational.new(1)

positive.valuation                              # 1/2
positive.series                                 # x^1/2 + 1/2*x^3/2 - ...
positive.series.coefficient(Rational.new(5, 2)) # -1/8
positive.certificate.verified?                  # true
```

The certificate is intentionally small. It replays the lower-edge support,
checks the irreducible characteristic factor and its certified residue field,
checks that the leading coefficient is a simple root, checks that the
independent coordinate really is the local parameter, and substitutes the
retained branch back into the translated equation through the requested
order. The producer uses dense exact coefficient arrays on this hot path and
converts to `FormalPuiseuxSeries` only at the boundary.

An irreducible factor of degree greater than one gives one closed/conjugate
branch packet over its certified simple-extension field:

```w
packet = (y**2 - x*(x + 1)*2).puiseux_branches[0]
packet.residue_degree                         # 2
packet.coefficient_field                      # ℚ(c), c^2 = 2
packet.coefficient_field.trace(
  packet.leading_coefficient)                 # 0
packet.coefficient_field.norm(
  packet.leading_coefficient)                 # -2
packet.certificate.verified?                  # true
```

This is deliberately a packet rather than two decimal roots: selecting a
complex or real embedding is a later analytic operation, while the algebraic
branch and all of its conjugates remain exact.

Repeated rational tangents trigger a new translated Newton polygon:

```w
shared = (y - x)**2 - x**3
sheets = shared.puiseux_sheets(0, 1, nil, 4)
# y = x + x^(3/2)
# y = x - x^(3/2)

sheets[0].certificate.class_name
# RecursiveLocalPlaneBranchCertificate
sheets[0].certificate.verified?                 # true
```

The recursive certificate replays `x=s^q`, `y=c*s^p+z`, removes the common
power of `s`, verifies the nested branch certificate, reconstructs the
combined ramification, and finally substitutes the result into the original
equation. `recursion_limit` defaults to 8 and is an explicit last argument
when a caller wants a different resource bound.

Affine and projective curves expose the same operation on a chart:

```w
P2 = ProjectiveSpace<ℚ, 2>.new(:X, :Y, :Z)
X, Y, Z = P2.coords
C = Curve.new(P2, Y**2*Z - X**3)

C.newton_polygon([0, 0], 2).valuations          # [3/2]
C.puiseux_sheets([0, 0], 2, 4)                  # Y = +/- X^3/2
```

These are sheets of the chosen \(x\)-projection. A ramified pair can be two
parameterizations of the same geometric branch: for the cusp
\(y^2=x^3\), the sheets \(y=\pm x^{3/2}\) are related by \(t\mapsto -t\)
after setting \(x=t^2\). Every returned object therefore reports
`projection_sheet?`, and `ramified?` exposes this warning. Sheet counts must
not be used as branch counts or intersection multiplicities.

`local_normalization` performs the next finite, exact step. It converts every
sheet packet to a primitive parameterization jet, replays substitution into
the source equation, verifies that the packets cover every resolved
Newton-edge factor, and applies the root-of-unity orbit formula:

```w
normalization = (y**2 - x**3).local_normalization(
  0, 1, nil, 4)

normalization.projection_sheets.size       # 2
normalization.geometric_branch_count       # 1

packet = normalization.parametrizations[0]
packet.x_series                            # t^2
packet.y_series                            # t^3 or -t^3
packet.ramification_index                  # 2
packet.geometric_branch_weight             # 1/2
packet.certificate.verified?               # true
packet.certificate.kernel_checked?         # true
```

The two certificate levels are intentionally different.
`LocalPlaneParametrizationCertificate` and
`PlaneProjectionSheetCoverCertificate` replay finite exact arithmetic.
`PlaneCurveLocalNormalizationCertificate` then labels the classical
Newton--Puiseux parameter-orbit statement as a `trusted_theorem_import`;
`kernel_checked?` is false for that theorem step. Its arithmetic replay must
still succeed, and the sum of packet weights must be integral, before
`geometric_branch_count` is exposed.

An algebraic packet contributes its residue degree as well as its
ramification. Thus \(y^2=2x\) is one degree-two packet of weight \(2/2=1\);
the cusp is two rational packets of weight \(1/2\) each. Repeated-tangent
recursion and affine/projective chart facades use the same normalization
surface:

```w
shared = ((y - x)**2 - x**3).local_normalization
shared.geometric_branch_count                    # 1

C.local_normalization([0, 0], 2, 4).
  geometric_branch_count                         # 1
Algebra.local_normalization(y**2 - x**3).
  certificate.verified?                          # true
```

This object is finite normalization *jet data*, not the completed local ring:
`finite_jet?` is true and `complete_local_ring?` is false.

## Local discriminants, Milnor numbers, and delta invariants

For a reduced plane equation that is \(y\)-distinguished at the selected point
with constant nonzero \(y\)-leading coefficient, Tungsten now combines the
normalization branch count with an exact bivariate resultant:

```w
local = (y**2 - x**3).local_delta_invariant(
  0, 1, nil, 4)

local.weierstrass_degree             # 2
local.derivative_resultant           # -4*x^3
local.discriminant_valuation         # 3
local.milnor_number                  # 2
local.branch_count                   # 1
local.delta                          # 1

local.discriminant_certificate.proof_kind
# exact_bareiss_resultant
local.discriminant_certificate.kernel_checked?  # true

local.certificate.proof_kind
# trusted_theorem_import
local.certificate.kernel_checked?               # false
```

The bivariate surface is useful independently:

```w
f = y**2 - x**3
f.resultant_in(f.derivative(1), :y)  # -4*x^3
```

Its Sylvester determinant uses fraction-free Bareiss elimination over
\(\mathbb Q[x]\), and the certificate recomputes the exact resultant and its
valuation. The final invariant uses the classical characteristic-zero
identities

\[
  v_x(\operatorname{Res}_y(f,f_y))=\mu+n-1,\qquad
  2\delta=\mu+r-1.
\]

Those identities and the Newton--Puiseux branch-orbit theorem are listed by
`theorem_dependencies`; they are not relabelled as kernel proofs. The surface
works for smooth points, nodes, cusps, tacnodes, ordinary multiple points,
algebraic branch packets, repeated tangents, and shifted affine/projective
charts.

For a reduced germ that is not \(y\)-distinguished, the same public call falls
back to the polar formula

\[
  \mu=I_0(f,f_y)-I_0(f,x)+1.
\]

Both intersections are computed by the certified normalization-packet engine:

```w
f = x*y**2 + y - x
local = f.local_delta_invariant(0, 1, nil, 4)

local.computation_method                   # polar_intersection
local.polar_intersection.multiplicity      # 0
local.projection_intersection.multiplicity # 1
local.milnor_number                        # 0
local.delta                                # 0
local.polar_certificate.verified?          # true
```

The polar identity is another named `trusted_theorem_import`; both underlying
intersection certificates still replay their finite substitutions exactly.
This removes the manual Weierstrass-coordinate requirement for supported
reduced germs. Completed local rings, value semigroups, conductor ideals,
component extraction, and cases whose necessary contact exceeds the requested
precision remain future work.

## Local intersection multiplicity

The same normalization packets compute exact intersections with another local
plane germ. Each packet certificate substitutes the target equation into
\(x(t),y(t)\) over the packet's exact coefficient field and finds its first
nonzero coefficient:

```w
cusp = y**2 - x**3

horizontal = cusp.local_intersection(
  y, 0, 1, nil, 4)
horizontal.multiplicity                         # 3

horizontal.packet_intersections[0].valuation    # 3
horizontal.packet_intersections[0].
  geometric_contribution                        # 3/2
horizontal.packet_intersections[0].
  certificate.kernel_checked?                   # true

cusp.local_intersection_multiplicity(
  x, 0, 1, nil, 4)                              # 2
```

The half-contributions in the first example are intentional: the two
\(x\)-projection sheets of the cusp form one geometric branch, so their two
weights \(1/2\) combine to one parameter valuation of 3. Nodes, tacnodes,
algebraic packets, shifted points, and projective curves use the same entry
point:

```w
(y**2 - x**4).local_intersection_multiplicity(
  y, 0, 1, nil, 4)                              # 4

C.local_intersection(other_curve, [0, 0], 2, 6).
  multiplicity
```

`LocalPlaneParametrizationIntersectionCertificate` is a finite exact
substitution check. The aggregate
`PlaneCurveLocalIntersectionCertificate` separately records the classical
branch-valuation formula as a `trusted_theorem_import`, so its
`kernel_checked?` value is false.

Precision is part of the contract. If the target vanishes through every
retained parameter coefficient, Tungsten cannot distinguish very high contact
from a common component and raises with a request to increase
`maximum_power`. It never turns an all-zero truncated residual into a finite
intersection number.

The current lift handles squarefree characteristic factors and recursively
refines repeated rational linear factors, subject to the exact factorization
and recursion bounds. A repeated higher-degree algebraic factor, a
nonreduced/common dependent-variable component, or a vertical component raises
with a capability message. Inspecting `newton_polygon` remains available in
those cases; Tungsten does not return an empty branch list and imply that the
local curve has no branches.

## Modular forms and q-expansions

The first modular-form layer is exact and intentionally narrow:

```w
G = Gamma0.new(11)
G.index                              # 12
G.genus                              # 1
S = CuspForms.new(G, 2)
S.dimension                          # 1
S.sturm_bound                        # 2

flt_terminal = CuspForms.new(2, 2)
flt_terminal.dimension               # 0
flt_terminal.dimension_certificate.verified?

E4 = ClassicalModularForms.e4(12)
E6 = ClassicalModularForms.e6(12)
Delta = ClassicalModularForms.delta(12)
(E4.q_expansion**3 - E6.q_expansion**2).scale(
  Rational.new(1, 1728)) == Delta.q_expansion

MS = WeightTwoModularSymbols.new(11)
MS.projective_line.size               # 12
MS.relative_dimension                 # 3
MS.boundary_rank                      # 1
MS.cuspidal_dimension                 # 2
MS.cuspidal_basis.size                # 2 (bounded exact Rational RREF)

T2 = MS.hecke_operator(2)
T2.characteristic_polynomial          # x² + 4x + 4
T2.certificate.verified?
MS.hecke_operator(12).certificate.verified?

ON = WeightTwoModularSymbols.new(33).old_new
ON.old_dimension                      # 4
ON.new_dimension                      # 2
ON.new_characteristic_polynomial(2)  # x² - 2x + 1

f = Algebra.rational_newform(33, 16, 100_000_000)
f.q_expansion
# q + q² - q³ - q⁴ - 2q⁵ - q⁶ + 4q⁷ - 3q⁸ + ... + O(q¹⁶)
f.certificate.verified?

packets = Algebra.eigenpackets(55, 100_000_000)
packets.packets.map -> item.coefficient_field_degree
# [1, 2]

g = packets[1]
K = g.coefficient_field              # ℚ(theta), theta² - 2theta - 1 = 0
g.hecke_eigenvalue(2)                # theta
g.hecke_eigenvalue(3)                # 2 - 2theta
g.hecke_eigenvalue_certified?(3)     # true
g.q_expansion(8)
# q + theta*q² + (2-2theta)*q³ + (2theta-1)*q⁴ - q⁵
#   + (-2theta-2)*q⁶ - 2q⁷ + O(q⁸)
g.q_expansion_certificate(8).verified? # true
```

`QExpansion` records a hard precision boundary. Reading an unknown
coefficient raises; addition and multiplication retain only the common known
precision. The classical-form certificate independently checks divisor-sum
or Euler-product coefficients and the \(E_4/E_6/\Delta\) identity. It labels
the fact that these series are modular as a trusted theorem import.
`FieldQExpansion` provides the same hard boundary and exact arithmetic over
an explicit coefficient field; it never converts algebraic coefficients to
floating point.

`WeightTwoModularSymbols` exhausts the right-coset model
\(P^1(\mathbb Z/N\mathbb Z)\), stores the two Manin relations per generator
as sparse rows, constructs every cusp boundary, and checks that the relations
map to zero. Relative and cuspidal dimensions use Manin's presentation
theorem explicitly. Dense rational basis extraction is lazy and
resource-bounded; the normal level-389 construction remains sparse. On the
reference machine, moving from a dense rank trace to the prime-level/sparse
path reduced interpreted level-389 construction from 32.8 seconds / 5.66 GB
to 1.21 seconds / 305 MB; the native end-to-end regression uses about
0.20 seconds / 13 MB.

`WeightTwoHeckeOperator` applies the exact Cremona--Heilbronn determinant-\(p\)
matrices to each quotient-basis symbol. At primes dividing the level it
explicitly omits images that are no longer primitive; this is the \(U_p\)
case, not an accidental coercion. Its certificate regenerates every image
and checks the characteristic polynomial at enough rational points against
\(\det(xI-T_p)\). Composite \(T_n\) are reconstructed from commuting
prime-power factors using
\(T_{p^r}=T_pT_{p^{r-1}}-pT_{p^{r-2}}\) away from the level and
\(U_{p^r}=U_p^r\) at bad primes; the composite certificate replays those
matrix identities and determinant checks. `WeightTwoOldNewDecomposition`
constructs both prime-level
degeneracy images from every \(N/p\), row-reduces their sum to the old
subspace, and exposes the canonical Hecke quotient by that subspace. The
finite matrices are replayed exactly; their interpretation as Hecke and
old/new objects cites the Heilbronn and Atkin--Lehner--Li theorems as trusted
imports.

`WeightTwoHeckeEigenpacketDecomposition` builds a deterministic rational
linear combination of \(T_n\) through Sturm's bound. It stops as soon as the
separator has the maximum possible squarefree characteristic-polynomial
degree, factors that polynomial over \(\mathbb Q\), and takes exact kernels.
Each irreducible factor \(h\) must occur as \(h^2\): the two copies are the
plus/minus modular-symbol periods. This splits multiple rational forms and
Galois orbits without choosing a numerically convenient prime.

For a degree-\(d\) packet, every requested \(T_n\) is solved exactly as a
polynomial of degree below \(d\) in the separator. The resulting element of
\(\mathbb Q[\theta]/(h)\) is the normalized coefficient \(a_n\), so q-series
may have exact number-field coefficients. The certificate replays the
separator, factor kernels, direct-sum rank, and used Hecke actions. Its
interpretation uses the named semisimplicity, multiplicity-one, and
plus/minus-period theorems; those are not kernel proofs.

`RationalWeightTwoNewform` remains the compact compatibility API when the
entire new quotient is one two-dimensional rational packet. It uses the exact
good-prime recurrence
\(a_{p^r}=a_pa_{p^{r-1}}-p\,a_{p^{r-2}}\), the bad-prime Euler factor, and
multiplicativity.

## Archimedean places and S-unit square classes

Number-field real places evaluate power-basis elements in exact
Sturm-isolated roots. Complex places are represented as conjugate pairs;
their local square-class contribution for 2-descent is trivial. Finite étale
product orders expose the same sign maps componentwise without pretending
that a squarefree component polynomial is irreducible:

```w
K = NumberField.new(t**2 - 5, :a)
A = K.archimedean_data
A.signature                         # [2, 0]
A.real_signs(K.generator)           # [-1, 1]
A.certificate.verified?             # true

O = EtaleProductOrder.new([t**2 - 5, t**2 + 1])
O.archimedean_data.component_signatures
# [[2, 0], [0, 1]]
```

A proposed \(S\)-unit square-class basis is independently checked. Every
generator's principal fractional ideal must be supported on the displayed
prime ideals. Independence is replayed over \(\mathbf F_2\) using valuation
parities, exact real signs, and optional odd-prime quadratic residue
characters:

```w
K2 = NumberField.new(t**2 - 2, :b)
P2 = K2.prime_ideals_above(2)[0]
U = K2.s_unit_square_class_basis(
  [P2],
  [-1, K2.one + K2.generator, K2.generator])

U.dimension
U.local_matrix
U.coordinates(K2.generator)
U.certificate.verified?
```

The local arithmetic and row reduction are exact and replay checked.
Completeness uses the classical Dirichlet \(S\)-unit theorem to identify the
dimension as \(r_1+r_2+|S|\), so the certificate explicitly reports
`proof_kind == :trusted_theorem_import` and `kernel_checked? == false`.
This certifies supplied generators; it does not discover them, compute an
\(S\)-class group, or prove the BPS condition
\(\mathrm{Cl}(\mathcal O_{L,S})[2]=0\).

For a certified product order, independently certified field bases compose
and can be quotiented by the diagonal classes of \(-1\) and the rational
primes in \(S\). The checker reconstructs the product decomposition, verifies
every component basis and complete set of \(S\)-primes, computes the diagonal
coordinate matrix, and certifies its rank before reporting quotient
coordinates.

The complementary \(S\)-class 2-torsion certificate does not need the full
class-group structure. `minkowski_factor_base` enumerates every prime ideal
needed to generate the class group. Principal ideal factorizations and the
classes inverted by \(S\) form an integral relation lattice. If its reduction
has full rank over \(\mathbf F_2\), an odd-order finite group surjects onto the
\(S\)-class group, proving that its 2-torsion is trivial:

```w
K = NumberField.new(t**2 + 5, :a)
P2 = K.prime_ideals_above(2)[0]
proof = K.certify_s_class_two_torsion(
  [P2], 1)

proof.factor_base.bound             # 4
proof.rank_certificate.rank         # 3
proof.two_torsion_trivial?          # true
```

The same field with empty \(S\) is correctly rejected: its class group has
order two. Bounded relation discovery raises `unknown` if it cannot reach full
rank. A product proof accepts arrays of field proofs only after reconstructing
each squarefree étale component from pairwise-coprime irreducible defining
polynomials and checking every field prime above the rational \(S\).
Relation discovery can select exact Frobenius-Gram LLL or a step-bounded
floating producer and searches odd prime-ideal powers largest-first. Once an
odd-power witness is found, anchored products \(AP_i\) and \(A^2P_i\) provide
sparse relation candidates. Every accepted integral relation is replayed from
exact prime valuations plus the norm identity; non-integral relations use the
general principal fractional-ideal certificate. No floating result is proof
evidence.

Long searches can return a noncertified checkpoint instead of raising. The
checkpoint reports rank, attempted/resolved factor-base indices, its anchor,
and power-basis coefficient arrays for every accepted element. Supplying those
arrays to a later search replays them exactly, and the final proof can be
constructed without rerunning discovery:

```w
bounds = NumberFieldIdealGeneratorBounds.new(
  1, 1000, 3, :exact,
  20, 20_000, 0, 20)
checkpoint = K.search_s_class_two_torsion(
  [P2], 0, 1000,
  100_000, 250_000, 250_000,
  bounds)

checkpoint.complete?                    # false is not a theorem
checkpoint.rank
witnesses = checkpoint.relation_coordinate_witnesses
checkpoint.resolved_factor_base_indices

# Persist and merge exact witnesses from later factor-base slices first.
proof = K.certify_s_class_two_torsion_from_relations(
  [P2], witnesses)
```

The last call succeeds only when the replayed relation matrix has full rank.
An incomplete checkpoint has `certified? == false`, and asking it for a
certificate raises.

When a poorly conditioned field presentation has a
`NumberFieldIsomorphicModelIrreducibilityCertificate`, a complete model-field
proof can be transferred back with
`certify_s_class_two_torsion_via_isomorphic_model`. The certificate checks the
field isomorphism, both complete sets of primes above the same rational
\(S\), and the model proof. Functoriality of the localized class group is an
explicit trusted theorem import; all field, prime, ideal, relation, and
rank data remain replay checked.

The shell-width degree-6, degree-9, and degree-12 components have durable
sets of 4, 182, and 48 exact power-basis witnesses in
`spec/fixtures/algebra/`. Replaying them gives full ranks 9, 187, and 56 on
their complete Minkowski factor bases, constructs the ordinary model-field
proofs, and transfers them to the original bitangent presentations. These are
opt-in native certificate lanes:

```sh
bin/tungsten compile scripts/algebra/shell_width_degree9_verify.w \
  --out /tmp/shell-width-degree9-verify
/tmp/shell-width-degree9-verify \
  spec/fixtures/algebra/shell_width_degree9_s_class.rel
```

The verifier reconstructs all theorem inputs and does not trust the artifact
headers. On an 18-core, 128-GiB Mac17,6, reference native replays took
0.41 seconds / 51 MB for degree 6, 18.5 seconds / 9.46 GB for degree 9, and
22.1 seconds / 7.17 GB for degree 12. The ordinary suite checks artifact
structure; the explicit commands check the mathematical certificates. The
remaining high peak RSS is a known heavy-lane cost, not the size of the
checked-in witnesses.

Minkowski enumeration uses complete certified decompositions for small or
index-dividing rational primes. For \(p^2\) above the bound it stores only
certified linear Dedekind slices, because higher-residue-degree primes cannot
enter the factor base. Successful rational-prime decompositions are cached on
the immutable field object.
Exhaustion is reported as unknown rather than as nonprincipality.
Minkowski generation and compatibility with finite products are named trusted
theorem imports; prime decompositions, ideal factorizations, relation support,
and F₂ rank are replayed exactly.

## \(p\)-adic fields and local descent foundations

`PadicField` is deliberately honest about its present scope. It represents
exact rational numbers inside \(\mathbb Q_p\), not arbitrary completed
elements. Within that subfield it computes exact valuations and unit residues,
the full multiplicative square-class quotient, and finite-precision
simple-root Hensel lifts:

```w
Q3 = Algebra.p_adic_field(3, 12)
Q3.coerce(Rational.new(2, 27)).valuation  # -3
Q3.square_class(12).vector                # [1, 0]

Q2 = Algebra.p_adic_field(2, 12)
Q2.square_class(-1).vector                # [0, 1, 0]
Q2.square_class(5).vector                 # [0, 0, 1]

root = Algebra.p_adic_field(7, 8).hensel_root(x**2 - 2, 3)
root.evaluate_residue                     # 0 modulo 7^8
root.certificate.arithmetic_replay_checked? # true
root.certificate.kernel_checked?            # false
```

For an odd number-field prime \(P\), `P.local_square_class(a)` computes the
two coordinates in
\(K_P^\times/K_P^{\times2}\): valuation parity and the quadratic character
of the residue unit. A valuation-one uniformizer, principal fractional ideal,
residue map, and resulting binary vector are replayed exactly. Completeness of
those two coordinates uses Hensel's lemma for the square map on local units,
which is named as a trusted theorem import.

For a dyadic number-field prime, the residue unit alone carries no square
information. `P.dyadic_square_class(a)` instead follows the exact higher-unit
filtration. If \(e=v_P(2)\) and \(f=[k_P:\mathbb F_2]\), the odd layers below
\(2e\) contribute \(ef\) bits, the critical \(2e\) layer contributes the
one-dimensional Artin--Schreier cokernel, and valuation parity contributes
one more. The result is the complete
\([K_P:\mathbb Q_2]+2\)-dimensional square-class quotient. Exact ideal
valuations, residue lifts, every filtration cancellation, and final
\(U_{2e+1}\) membership are replayed; the Local Square Theorem and the
higher-unit squaring filtration are named trusted imports. The arithmetic
pass retains a statement-bound transcript of its certified valuation
profiles, localized residues, residue-field lifts, odd/even/critical updates,
Artin--Schreier correction, and terminal unit. The certificate independently
checks those identities instead of rebuilding the same principal ideals.

A certified product \(S\)-unit space can be localized blockwise at every
prime above a rational prime:

```w
local2 = V.localization_map(2)
local3 = V.localization_map(3)
local3.local_factor_count
local3.target_dimension
local3.matrix
local3.rank
local3.apply(global_square_class_vector)
local3.certificate.linear_kernel_replay_checked? # true
```

For a basis transferred through a certified field isomorphism, localization
uses the already-certified model-field generators and principal ideals. This
changes only the presentation and ordering of the local factors; it avoids
redoing high-degree principal-ideal arithmetic in the poorer source
presentation. The product-space certificate checks that transfer before
accepting the block matrix.

This matrix answers, exactly, how each chosen global ambient generator looks
in the local square-class targets. By itself it does **not** compute the image
of \(J(\mathbb Q_p)/2J(\mathbb Q_p)\); that also needs descent-function
evaluation on local divisor classes.

At a prime of good reduction, a rational plane curve can enumerate its
residue disks:

```w
cover = C.p_adic_residue_disks(5, 8)
cover.disks.size
cover.certificate.finite_special_fiber_replayed? # true
cover.local_descent_image_certified?              # false

fiber = setup.certify_theta_fiber_at_five
image = function_data.good_reduction_local_image(local5, fiber, 8)
image.expected_dimension                          # dim J[2](F_5)
image.dimension
image.complete?
image.certificate.arithmetic_replay_checked?
```

The checker enumerates the complete projective special fiber, verifies every
point and smoothness, and imports properness plus multivariate Hensel lifting
to identify the corresponding nonempty disks. Bad reduction raises rather
than pretending this model is adequate.

For an odd good-reduction prime, `good_reduction_local_image` evaluates every
BPS line ratio on each residue disk where its numerator and denominator are
units. The unit square class is determined exactly by its residue, so the
result is constant on that disk. The certificate replays every residue and
point-difference vector, then independently computes the kernel of Frobenius
minus the identity on the certified geometric 2-torsion module.
Good-reduction formal-group divisibility gives
\(J(\mathbb Q_p)/2J(\mathbb Q_p)\cong J(\mathbb F_p)/2J(\mathbb F_p)\),
whose dimension is \(\dim J[2](\mathbb F_p)\). If the clean disk images reach
that dimension, no unseen divisor class can enlarge the image and the result
is marked complete. If they do not, Tungsten returns an explicitly labelled
lower bound.

For the shell-width quartic at \(p=5\), seven clean disks span dimension one,
equal to the replay-certified Frobenius-fixed dimension, so this is a complete
local image with basis `0000000101` in the ten-dimensional local square-class
target. This good prime validates the local-image machinery; the Selmer
computation itself needs the bad primes.

At bad reduction, `p_adic_smooth_residue_disks` separately certifies every
smooth point of the special fiber and reports the singular classes it has not
covered. This is still useful: every smooth point gives a nonempty Hensel disk,
and clean line ratios are constant there. If a displayed denominator vanishes
but is a valid implicit coordinate, `disk.implicit_coordinate(index)` certifies
its valuation and leading unit on the entire disk. The high-level
`function_data.implicit_disk_local_image(local_map, disks)` API then evaluates
the exact odd local square classes and returns an explicitly lower-bound-only
point-difference span. A local-image span is not marked complete until an
independent local-dimension certificate proves it has the right size.

The focused `certify_cuspidal_regular_model` path supplies such a bound for an
integral plane quartic with one rational \(A_2\) cusp. It uses proof-producing
Gröbner identities to show that the cusp is the unique geometric singularity,
checks that the total arithmetic surface is regular, and counts the
genus-two normalization over \(\mathbb F_p\) and \(\mathbb F_{p^2}\). The
normalization zeta numerator bounds prime-to-\(p\) torsion through its
generalized Jacobian and the Néron component group.

For the shell-width quartic at \(p=13\), this gives

```w
model13 = C.certify_cuspidal_regular_model(13, [1, 8, 1])
model13.normalization_genus                    # 2
model13.normalization_zeta_coefficients        # [1, 3, 0, 39, 169]
model13.normalization_jacobian_order           # 212 = 4 * 53
model13.dimension_upper_bound                  # 2

image13 = function_data.smooth_locus_local_image(
  local13, 8, model13)
image13.clean_disk_count                       # 12
image13.dimension                              # 2
image13.complete?                              # true
```

Thus \(p=13\) is no longer an open local-image condition. At \(p=3\), the
special fiber is \(Z(B-S)^3\). Two smooth disks admit certified implicit
\(Z\)-coordinates:

```w
cover3 = C.p_adic_smooth_residue_disks(3, 8)
disks3 = [
  cover3.disks[0].implicit_coordinate(2),
  cover3.disks[1].implicit_coordinate(2)
]
image3 = function_data.implicit_disk_local_image(local3, disks3)
image3.dimension                              # 0
image3.lower_bound_only?                      # true
image3.certified?                             # true
```

Both disks have \(v_3(Z)=1\), leading unit \(Z/3=2\), and the same certified
18-bit BPS square class. Their point difference is therefore zero in the
local target. The third smooth point is an exact zero of the source equation
at the chosen center and needs deeper subdivision; the singular residue
classes also remain uncovered. This is a certified negative result, so
recursive refinement or a regular model is genuinely required rather than
more special-fiber sampling.
At \(p=2\), the special fiber is \((S+Z)^4\) and has no smooth point.
Recursive refinement or blowups at 2 and 3, and general completed local
extensions, remain future layers.

The small rational and curve examples run in both engines. Exact
number-field localization is intentionally an opt-in compiled lane: on the
reference host the current quadratic product regression takes about
0.22 seconds and 14 MB compiled. The interpreter takes about 11.1 seconds and
2.18 GB, so it is not a standard interpreted regression lane. The compiled
dyadic regression exhausts all 16 square classes in both ramified and
unramified quadratic completions, plus a product localization map, in about
0.26 seconds and 49 MB; it is registered only in the compiled suite.

The complete shell-width ambient localization is now replayed at every finite
prime in \(S=\{2,3,13\}\):

```text
p = 2:   4 local factors, target dimension 35, rank 29, kernel dimension 6
p = 3:   9 local factors, target dimension 18, rank 17, kernel dimension 18
p = 13:  7 local factors, target dimension 14, rank 13, kernel dimension 22
```

With the supplied degree-6/9/12 S-unit artifacts, the native \(p=2\) lane
takes about 31.5 seconds / 10.14 GB, the \(p=3\) lane about
20.2 seconds / 7.79 GB, and the \(p=13\) lane about 19.7 seconds / 7.61 GB on
the reference host. The complete \(p=5\) good-reduction image lane takes
about 19.8 seconds / 7.37 GB; the complete \(p=13\) cuspidal image lane takes
about 20.2 seconds / 7.70 GB. The \(p=3\) implicit-disk image lane takes
about 20.8 seconds / 7.98 GB and remains opt-in. Before statement-bound
transcript replay, the
dyadic lane took 39.5 seconds / 11.71 GB because coordinate certification
repeated its local ideal arithmetic. The dyadic implementation follows 35
filtration coordinates and does not enumerate the largest
\(2^{26}\)-element residue quotient. Earlier versions factored an entire
principal ideal for every single local valuation and rebuilt
certificate witnesses; the \(p=3\) path took 34.5 seconds / 13.6 GB.
Localization now reuses the basis's statement-bound principal-ideal evidence,
separated uniformizers, and model-field transfer. The remaining peak is the
already-heavy S-unit replay, so these checks remain explicit opt-in research
lanes:

```sh
bin/tungsten compile scripts/algebra/shell_width_s_units_verify.w \
  --out /tmp/shell-width-s-units-verify
TUNGSTEN_SUNIT_LOCAL_PRIME=3 /tmp/shell-width-s-units-verify \
  spec/fixtures/algebra/shell_width_degree6_s_units.rel \
  spec/fixtures/algebra/shell_width_degree9_s_units.rel \
  spec/fixtures/algebra/shell_width_degree12_s_units.rel

TUNGSTEN_SUNIT_LOCAL_PRIME=5 \
TUNGSTEN_SUNIT_GOOD_LOCAL_IMAGE=1 \
  /tmp/shell-width-s-units-verify \
  spec/fixtures/algebra/shell_width_degree6_s_units.rel \
  spec/fixtures/algebra/shell_width_degree9_s_units.rel \
  spec/fixtures/algebra/shell_width_degree12_s_units.rel

TUNGSTEN_SUNIT_LOCAL_PRIME=13 \
TUNGSTEN_SUNIT_SMOOTH_LOCAL_IMAGE=1 \
  /tmp/shell-width-s-units-verify \
  spec/fixtures/algebra/shell_width_degree6_s_units.rel \
  spec/fixtures/algebra/shell_width_degree9_s_units.rel \
  spec/fixtures/algebra/shell_width_degree12_s_units.rel

TUNGSTEN_SUNIT_LOCAL_PRIME=3 \
TUNGSTEN_SUNIT_IMPLICIT_LOCAL_IMAGE=1 \
  /tmp/shell-width-s-units-verify \
  spec/fixtures/algebra/shell_width_degree6_s_units.rel \
  spec/fixtures/algebra/shell_width_degree9_s_units.rel \
  spec/fixtures/algebra/shell_width_degree12_s_units.rel
```

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
is the identity. That final seven-variable Gröbner replay is currently a
compiled capability: the focused native regression takes well under a second,
while the generic tree-walking interpreter can retain roughly 10 GB of
temporary polynomial objects. The standard interpreter suite therefore skips
it; run the compiled fixture with
`TUNGSTEN_AUTOMORPHISMS_FULL=1` for the full certificate.

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
The bitangent scheme is a geometric preparation. Calling
`certify_divisor_function_data` constructs and verifies the BPS
divisor/line-bundle family and functions, at which point the object is a
certified true setup. The later arithmetic descent remains incomplete:

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
E = scheme.etale_algebra
E.dimension                # 27
E.certificate.verified?    # true
E.decomposition_certificate.verified?
F = setup.certify_divisor_function_data
F.component_degrees        # [6, 9, 12]
F.certificate.verified?    # true
setup.true_setup?          # true
setup.certified?           # true
value = F.evaluate(C.space.point([0, 9, 1]))
value.unit?                # true
O = setup.certify_integral_product_order
O.component_ranks          # [6, 9, 12]
O.rank                     # 27
O.certificate.verified?    # true
M = setup.certify_maximal_product_order
M.component_ranks          # [6, 9, 12]
setup.maximal_product_order_certificate.verified?
S = setup.certify_s_prime_data
S.rational_primes          # [2, 3, 13]
S.factor_count             # 20
S.certificate.verified?
Ainf = setup.certify_archimedean_data
Ainf.signature[0] + 2*Ainf.signature[1]  # 27
Ainf.certificate.verified?
# P6/P9/P12 are the independently certified component S-class proofs.
setup.certify_s_class_two_torsion([P6, P9, P12])
# U6/U9/U12 are independently certified component bases.
V = setup.certify_s_unit_square_class_space(
  [[U6], [U9], [U12]])
V.dimension                 # 35
V.true_descent?             # true
V.modulo_diagonal?          # false
V.certificate.verified?
N = V.norm_map
N.target.dimension          # 4, with generators [-1, 2, 3, 13]
N.kernel_certificate.rank   # 4
N.kernel_dimension          # 31
N.certificate.verified?
# Once V is bound to the setup:
global_norm = setup.certify_global_norm_condition
global_norm.constraint_block.certified?
P = C.space.point([0, 9, 1])
Q = C.space.point([-3, -3, 1])
known_image = setup.certify_point_difference_descent_value(P, Q)
known_image.coordinates
known_image.norm_vector       # [0, 0, 0, 0]
known_image.certified?
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
On each degree-6/9/12 étale component, the function-data certificate
reconstructs a normalized quadratic `q` and checks all five coefficients of
the binary-quartic identity `l.C = a*q²`. The distinguished certificate gives
`l0.C = 4P`. Applying BPS section 6.5 then produces
`beta'_l = beta_l - 2P` and `f_l = l/l0`, with
`div(f_l) = 2*beta'_l`. The BPS comparison is recorded as a trusted theorem
import with checked hypotheses; the component polynomial identities
themselves are replayed exactly.
The degree labels describe a checked squarefree product presentation. They
construct the exact finite étale quotient, executable CRT decomposition, and
certified product of the three integral power orders obtained by scaling the
component generators. The pieces are not assumed irreducible. Round 2 then
constructs the integral closure in each finite étale component and certifies
the product order by fixed points at every discriminant prime. For the
shell-width presentation the three certified maximal-order discriminants are
`1168128`, `133451615232`, and `1364523024384`.
The finite \(S\)-place layer then decomposes \(2\), \(3\), and \(13\) in every
component. It certifies 4, 9, and 7 primes respectively, including all residue
fields and ramification/residue-degree signatures. By itself this is
finite-prime data, not an S-class-group or S-unit computation. Separate
component certificates establish the shell-width S-class and S-unit claims;
`certify_s_unit_square_class_space` binds the latter to this setup's actual
maximal order and S-prime set. The archimedean layer directly
Sturm-isolates the real roots of each squarefree component and records the
remaining complex conjugate pairs. It deliberately avoids requiring a full
irreducible factorization of the degree-6/9/12 presentations.

The distinction between true and fake descent matters here. Removing the
rational distinguished bitangent gives the degree-27 true setup of BPS
section 6.5, whose target is \(L'^\times/L'^{\times2}\). It does **not**
quotient those 27 components again by diagonal rational square classes. The
historical 31-dimensional calculation did exactly that and was therefore not
the BPS ambient group. The corrected true ambient has dimension 35. For the
equivalent all-28-bitangent fake setup, adjoining the rational component adds
four rational S-unit dimensions before the rank-four diagonal quotient, so
its dimension is also 35. Independently computing the true norm map gives a
rank-four map from the 35-dimensional ambient space to
\(\mathbb Q(S,2)=\langle-1,2,3,13\rangle\). Its norm-one kernel is therefore
31-dimensional. This is the useful 31-dimensional space: the same number
appears, but for a different and mathematically valid reason.

`EtaleProductSUnitNormMapCertificate` reconstructs every generator norm and
the complete binary matrix exactly. `PlaneQuarticBPSNormConstraintCertificate`
then checks the true setup and imports BPS Lemma 6.16 for the statement that
the descent image lies in that kernel. On the current shell-width artifacts,
the full native replay takes about 18.9 seconds and 6.9 GB RSS on an 18-core,
128-GiB Mac17,6. This is down from 32.4 seconds and 11.4 GB after profiling
removed retained finite-field array views and routed certified number-field
embeddings directly through Sturm isolation instead of unrelated rational
factorization. The degree-9 and degree-12 stages still peak near 1.9 GB and
4.8 GB independently, so this remains an explicit opt-in research check, not
part of the ordinary regression suite.

The rational divisor
\([0:9:1]-[-3:-3:1]\) now supplies one explicit, nonzero known image element.
Its certified coordinate vector, grouped by the degree-6/9/12 components, is
`000000000 000000000000 00011101110000`; its four norm coordinates are zero.
`PlaneQuarticBPSPointDifferenceCertificate` replays the two exact function
evaluations, every statement-bound S-unit coordinate computation, and the
norm calculation. It names the BPS sections 6.4--6.5 theorem that identifies
this square class with the image of `[P-Q]`. This proves a lower-bound image
element; it does not enumerate a local image or prove a Selmer upper bound.
The complete point-value lane currently takes about 23.5 seconds and 9.92 GB
peak RSS on the machine described above, so it is also opt-in.

Restricting that rational class through the certified localization maps gives
a one-dimensional known subspace of each corresponding local Jacobian image.
At \(p=2\) its 35-bit vector is
`00000000000000000000000000000010110`; at \(p=3\) its 18-bit vector is
`000000000000111111`; at \(p=13\) its 14-bit vector is
`00000001010101`. The
`PlaneQuarticBPSKnownLocalImageCertificate` replays the global
point-difference certificates, localization matrix, and row-span rank. Its
API deliberately reports `lower_bound_only? == true` and `complete? == false`;
these vectors cannot be used as a Selmer upper bound. Run the combined check
by setting both `TUNGSTEN_SUNIT_POINT_VALUES=1` and
`TUNGSTEN_SUNIT_LOCAL_PRIME` in the opt-in command above.
The combined dyadic-plus-point lane takes about 36.0 seconds and 13.23 GB
peak RSS, and remains outside the standard regression suite.

The canonical finite theta module is independently executable:

```w
theta = Algebra.genus_three_theta_incidence
theta.odd_characteristics.size       # 28
theta.syzygetic_quadruples.size       # 315
theta.module_dimensions               # [0, 1, 7, 21, 27, 28]
theta.certificate.verified?           # true

T = SymplecticF2Map.transvection(
  theta.space, theta.space.vector(1))
sigma = GenusThreeThetaPermutation.new(theta, T)
sigma.cycle_lengths                   # sixteen 1s and six 2s
sigma.certificate.verified?           # checks all 315 incidences
action = ThetaPermutationAction.new(theta, [sigma])
action.orbit_sizes
action.certificate.verified?
```

Six-bit characteristics index the quadratic refinements of the standard
symplectic form on \(\mathbb F_2^6\). The implementation exhausts the 28
Arf-invariant-one forms and all four-subsets with zero affine sum. Packed
28-bit row reduction then replays the BPS module dimensions. Exact
symplectic matrices act by pullback on the quadratic refinements; their
certificates check the pairing on a basis, reconstruct the resulting
permutation, and verify every one of the 315 incidence blocks. A finite set
of such permutations can be certified as a group action by exhausting its
orbits.

At a good prime, the degree-27 bitangent projection may be factored over the
finite field and tied to a candidate theta permutation:

```w
constraint = setup.certify_theta_frobenius_constraint(
  5, candidate, candidate.fixed_indices[0])

constraint.factor_degrees             # [3, 6, 6, 6, 6]
constraint.cycle_lengths               # [1, 3, 6, 6, 6, 6]
constraint.certificate.verified?
constraint.certificate.proof_kind      # :trusted_theorem_import
constraint.arithmetic_labeling_certified? # false
```

The finite replay checks the exact reduction, unchanged degree,
squarefreeness, irreducible factor certificates, one fixed distinguished
theta characteristic, and equality of the two cycle partitions. The
factor-degree/Frobenius-orbit theorem is a named trusted import. Most
importantly, this object is only a conjugacy-class constraint: it does not say
which degree-27 root is which theta label, and constraints at different
primes do not create a common labeling by themselves. Riemann--Mumford and
the identification of the canonical incidence with a smooth plane quartic's
bitangents likewise remain named trusted theorem imports. Constructing and
certifying that common arithmetic labeling is the next BPS boundary.

The shell-width factorization replay is deliberately opt-in:

```sh
TUNGSTEN_THETA_FROBENIUS=1 \
  bin/tungsten run spec/core/algebra_theta_actions_spec.w
```

The interpreter currently takes about 38.7 seconds and 7.0 GB peak RSS on
the reference host because completed exact-arithmetic object graphs remain
live; the compiled native replay takes about 0.03 seconds and 31 MB peak RSS.
The default suite checks the finite symplectic and incidence identities
without running this high-degree interpreted factorization.

The stronger finite-fiber certificate works over the explicit splitting field
\(\mathbb F_{5^6}\):

```w
fiber = setup.certify_theta_fiber_at_five

fiber.roots.size                         # 27
fiber.splitting_field.order              # 15625
fiber.distinguished_theta_label          # 15
fiber.source_frobenius_cycle_lengths     # [1, 3, 6, 6, 6, 6]
fiber.theta_permutation.certificate.verified?
fiber.certificate.arithmetic_fiber_labeling_checked? # true
fiber.global_arithmetic_labeling_certified?           # false
```

For each reduced root the checker reconstructs its component, chart
parameter, bitangent line, and normalized contact quadratic. A conic has six
coefficients; each contact divisor supplies two exact linear conditions.
For every canonical syzygetic block the resulting \(8\times6\) matrix has
rank five, giving its unique projective conic. The witness is a permutation
of all 28 labels, so these 315 positive checks, together with the classical
315-block theorem, certify the complete finite-fiber incidence isomorphism.
The checker then raises each root to its fifth power and verifies that the
conjugated permutation is induced by the supplied certified symplectic
matrix.

This implements the finite splitting-field calculation in BPS Lemma 12.6 for
one prime. It does not identify the characteristic-zero roots in a common
splitting field or make independently chosen labelings at several primes
compatible. Run the heavyweight interpreter lane explicitly; compiled replay
is the intended path. On the reference host the compiled certificate takes
about 0.32 seconds and 97 MB peak RSS:

```sh
TUNGSTEN_THETA_FIBER=1 \
  bin/tungsten run spec/core/algebra_theta_fibers_spec.w
```

The characteristic-zero subgroup can now be identified without pretending
that one finite fiber supplies a global labeling:

```w
subdegrees = setup.certify_theta_subdegrees
subdegrees.orbit_signature          # [1, 6, 9, 12]
subdegrees.relative_factor_degrees  # [1, 2, 2, 2, 2, 3, 3, 6, 6]
subdegrees.stabilizer_subdegrees    # [1, 1, 2, 2, 2, 2, 3, 3, 6, 6]

galois = setup.certify_theta_galois_subgroup
galois.identified_candidate.class_id  # 693
galois.identified_candidate.group.order # 36
galois.identified_up_to_conjugacy?    # true
galois.global_arithmetic_labeling_certified? # false
```

The checker multiplies nine displayed factors over the degree-6 number
field back to the monic degree-27 projection. Every relative factor has an
irreducibility proof. The sextics use two residue factorizations each:
`[2,2,2]` and `[3,3]` have no common proper subset degree. The rational
degree-9 and degree-12 components reuse their certified small tower models
and exact isomorphisms. This matters operationally: the generic Kronecker
fallback failed after 56.5 seconds and 41.5 GB RSS, while the structured
compiled replay takes about 0.31 seconds and 64 MB RSS. The full lane is
opt-in:

```sh
bin/tungsten compile spec/core/algebra_theta_subdegrees_spec.w \
  --out /tmp/algebra-theta-subdegrees
TUNGSTEN_THETA_SUBDEGREES=1 /tmp/algebra-theta-subdegrees
```

Tungsten exactly exhausts and checks each of the seven candidate permutation
groups left by the orbit partition. The stabilizer subdegrees leave one
candidate, class 693, of order 36; GAP reports its structure as
`S3 x S3`. The group order, orbits, stabilizers, cycle types, and preservation
of all 315 theta-incidence blocks are replayed internally. Exhaustiveness of
the seven candidates still imports GAP's
`ConjugacyClassesSubgroups(Sp(6,2))` table of 1,369 conjugacy classes. Thus the
subgroup conclusion is certified up to conjugacy under a visible trusted
finite-classification boundary. An explicit characteristic-zero bijection
between individual roots and theta labels remains separate work.

The remaining theta and local conditions will meet the certified global norm
condition in an exact F2 kernel:

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

## Order and number-field ideals

Full-rank integral ideals have a canonical row-Hermite basis.  Operations
construct that basis again and attach a certificate which replays the source
generators, lattice containment, and determinant norm:

```w
R = PolynomialRing.new([:x], RationalField.new)
x = R.generator(0)
K = NumberField.new(x**2 - 5, :a)
a = K.generator

I = K.principal_ideal(6)
I.norm                                      # 36
I.factorization.certified?                  # true

P = K.prime_ideals_above(5)[0]
P.valuation(a)                              # 1
P.ideal_valuation(K.principal_ideal(25))    # 4
```

Invertible fractional ideals in a certified maximal order are represented by
their finite map of certified prime ideals to signed valuations. The
constructor rejects a nonmaximal order. The principal constructor clears
denominators, factors the two resulting integral ideals, and certifies their
quotient:

```w
J = K.principal_fractional_ideal(a / 2)
J.norm                         # 5/4
J.valuation(P)                 # 1
J.valuation(K.prime_ideals_above(2)[0])  # -1
(J * J.inverse).unit?          # true
J.certificate.verified?        # true
```

All integer and prime searches are explicitly bounded.  Exhaustion raises
instead of returning a partial factorization as a certified ideal.

## Ideal operations

```w
I = Ideal.new([x * y])
I.saturate(x)          # (y)

J = Ideal.new([u + v - 1, u - v])   # lex ring in (u, v)
J.eliminate(1)         # ideal in k[v]
```

Elimination is correct when the monomial order eliminates the first `count`
variables (lex with those variables first, or a matching product order).

For calculations that need an auditable ideal proof rather than only a
computed basis, use the representation-carrying producer:

```w
I = Ideal.new([x**2 - y, x*y - 1])
G = I.certified_groebner_basis

G.certified?                         # true
G.certificate.source_reductions
G.certificate.s_pair_reductions

witness = G.membership_certificate(x**3 - 1)
witness.verified?                    # true
witness.multipliers                  # h_i with x^3-1 = sum h_i f_i
```

Every `PolynomialReductionCertificate` checks
\(p=\sum q_i g_i+r\) by exact polynomial arithmetic. Every basis polynomial
also carries explicit multipliers in the original generators, so the
certificate proves both ideal containments rather than merely checking that a
possibly larger ideal reduces the inputs to zero. S-pair reductions are
likewise explicit zero-remainder identities.

The final implication from those identities to “this is a Gröbner basis” is
the classical Buchberger criterion. It is exposed as a
`trusted_theorem_import` with `kernel_checked? == false`; the polynomial
identities themselves are replay-checked. This producer/verifier split is the
path for expensive compiled computations to emit compact witnesses instead of
forcing every consumer to rerun Buchberger.

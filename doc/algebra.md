# Exact algebra

`use algebra` loads the exact coefficient-domain, polynomial, ideal, and
geometry layers. `Rational` remains a numeric scalar in
`core/numeric/rational.w`; `Field` is the algebra-side protocol describing how
such scalars behave as coefficients.

## Surface syntax

The ordinary object API is always available:

```w
use algebra

P2 = ProjectiveSpace<ℚ, 2>.new(:B, :S, :Z)
B, S, Z = P2.coords
f = B**3 * Z * 16 + B * S**2 * Z * 48 - S**4 * 3
C = Curve.new(P2, f)

x = Poly<ℚ>.new(:x).generator
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

The compact grammar is intentionally confined to algebra entry points. It
does not add global implicit multiplication or change ordinary numeric
operator dispatch.

## Layers and capability status

| Layer | Available now | Boundary |
| --- | --- | --- |
| Fields | Exact `RationalField`; coercion, equality, characteristic, projective normalization | Other tags fail explicitly; `𝔽_p`, Gaussian rationals, and number fields are not yet implemented |
| Polynomials | Sparse sorted terms; `lex`, `grlex`, `grevlex`, and product orders; exact evaluation, derivatives, homogenization, division, content, primitive part, multivariate primitive GCD, resultant, discriminant, and exact factorization over ℚ | Kronecker factor search has an explicit resource limit; specialized dense storage is not yet implemented |
| Ideals | Multivariate division, Buchberger bases, reduced Gröbner bases, membership, zero and unit ideals | A pair limit guards accidental unbounded work; F4/F5 and scheme saturation are not implemented |
| Projective geometry | Arbitrary `ℙⁿ_ℚ`, normalized points, affine charts, and homogenize/dehomogenize round trips | Only `RationalField` is a supported coefficient field today |
| Plane curves | Homogeneity checks, membership, singular-locus ideal, chart-based nonsingularity, smooth plane genus, and Jacobian dimension | Singular-curve normalization is not implemented |
| Elliptic curves | Smooth plane-cubic detection; recognition of short Weierstrass coordinates; discriminant, identity, negation, integer scalar multiplication, and rational group law | Conversion of an arbitrary smooth plane cubic still needs a rational flex and is not yet implemented |
| Hyperelliptic curves | Exact `y² = f(x)` models, squarefreeness/genus, validated reduced Mumford pairs, and slow Cantor composition/reduction with integer scalar multiplication | Jacobian arithmetic currently requires a monic odd-degree model and is not optimized for large genus or coefficients |
| Arithmetic certification | Exact low-degree Galois groups over ℚ and Weil-cubic discriminants | `Jacobian#rank` always raises until a certified descent exists; Galois groups above degree three are not yet implemented |

`Curve#hyperelliptic_plane_model?` is specifically the smooth plane-model
test. Smooth plane curves of genus at least two are non-hyperelliptic; an
explicit double-cover model belongs in `HyperellipticCurve`.

# Mathematics in Tungsten

This is the newcomer map. Tungsten's goal is a pleasant mathematical surface
over exact computation, numerical work, and replayable evidence. The library
is substantial, but it is not yet a replacement for every algorithm in Sage,
Magma, PARI/GP, Mathematica, or the scientific Python ecosystem.

## Status words

Every mathematical capability should use one of these descriptions:

| Status | Meaning |
|---|---|
| **numeric** | Floating, interval, or approximate computation with a stated precision model |
| **exact** | The returned value follows from exact arithmetic, but may depend on supplied data |
| **certified** | An independent `verified?` replay checks the stated finite/arithmetic claim and its dependencies |
| **trusted theorem import** | Tungsten checks the hypotheses and names the theorem, but does not formalize its proof |
| **conditional** | The result explicitly depends on an assumption such as GRH |
| **heuristic** | Search or numerical evidence; never presented as a theorem |
| **unknown** | A resource limit or missing algorithm prevented a justified answer |

See [certified-mathematics.md](certified-mathematics.md) for the full trust
model. A certificate proves its stated claim; it is not automatically a proof
of every theorem for which that claim might be useful.

## Where to start

| Goal | Entry point | Guide |
|---|---|---|
| Ordinary numeric constants and functions | `π`, `ℯ`, `Math`, `Special` | [scientific-computing/overview.md](scientific-computing/overview.md) |
| Symbolic expressions, exact identities, calculus | `use calculus`; `Expression`, `Calculus` | [symbolic.md](symbolic.md), [scientific-computing/calculus.md](scientific-computing/calculus.md) |
| Fields, polynomials, ideals, arithmetic geometry | `use algebra`; `Algebra` | [algebra.md](algebra.md) |
| Arrays, tensors, linear algebra, optimization, ODEs | flat modules under `core/` | [scientific-computing/overview.md](scientific-computing/overview.md) |
| SAT-backed finite certificates | `tungsten-wassat` producer + `tungsten-wrat` checker | [certified-mathematics.md](certified-mathematics.md) |
| Plots | `core/plot.w`, `tungsten-drawille` | [scientific-computing/plot.md](scientific-computing/plot.md) |

Bare `π`, `τ`, `ϕ`/`φ`, `ℯ`, and `ℇ` are numeric `Float` constants. Exact
symbolic work uses `Expression.pi` and `Expression.e`; these remain named
objects so, for example, `sin(π/6)` can simplify exactly before any floating
evaluation.

## Exact algebra and geometry

`use algebra` loads one dependency chain:

```text
Field
  -> PolynomialRing
     -> Ideal / quotient / finite etale algebra
        -> orders / ideals / places
           -> projective spaces / curves / divisors / Jacobians
              -> descent / zeta / Galois and certificate layers
```

The implementation is split by responsibility under `core/algebra/`.
Coefficient domains and polynomial algorithms do not import curve code.
Projective spaces, curves, divisors, quartics, and descent currently remain
under `core/algebra/` because they are algebraic geometry and depend directly
on the field/ring layer. A future `core/geometry/` facade makes sense when
Tungsten also has substantial differential, metric, polyhedral, or synthetic
geometry; moving the existing files before that separation would change paths
without changing the dependency boundary.

The detailed capability table in [algebra.md](algebra.md) is authoritative.
At a high level:

- fields include ℚ, prime and extension finite fields, simple extensions,
  finite étale products, and arbitrary-degree number fields;
- polynomial work includes exact division, gcd/resultant/discriminant,
  monomial orders, reduced Gröbner bases, factorization over ℚ and finite
  fields, and certified real-root isolation;
- arithmetic number theory includes integral/maximal orders, prime
  decomposition, exact ideals, valuations, selected S-unit and S-class
  certificates, and archimedean places;
- geometry includes arbitrary projective spaces, plane curves, singular
  loci, elliptic and hyperelliptic Jacobian arithmetic in the documented
  model classes, divisors, point counts, zeta numerators, Weil cubics, and
  focused plane-quartic machinery;
- important boundaries remain: general multivariate factorization, complex
  algebraic-number embeddings, arbitrary plane-cubic conversion, general
  function fields and divisor class groups, fast general point counting,
  broad Galois-group classification, and completed generalized descent.

Unsupported cases raise or return `unknown`; they must not silently change
the coefficient field, model, or proof claim.

## Bruin--Poonen--Stoll descent

For the shell-width plane quartic, Tungsten now certifies the geometric and
global-arithmetic prefix: the 27 non-distinguished bitangents, finite étale
decomposition of degrees \(6+9+12\), contact quadratics, the true-setup
functions \(l/l_0\), maximal product order, finite and archimedean places,
S-class 2-torsion witnesses, supplied S-unit bases, and the diagonal rational
quotient.

That quotient is a 31-dimensional vector space over \(\mathbf F_2\):

```text
component S-unit square classes:  9 + 12 + 14 = 35 dimensions
diagonal rational classes:       <-1, 2, 3, 13> = 4 dimensions
ambient descent quotient:         35 - 4 = 31 dimensions
```

Its purpose is to turn an infinite multiplicative square-class problem into
finite linear algebra. A candidate descent value is represented by 31 bits.
Norm, unramified, Galois, and p-adic local-image conditions will cut out
subspaces or affine slices; the Selmer image must lie in their intersection.
The number 31 is not the dimension of the curve, its Jacobian, or its
Mordell--Weil rank.

The descent is not finished. Missing links are the theta Galois module, norm
and unramified constraints, certified p-adic local images, the BPS comparison
kernel and rational \(J[2]\), and the final Selmer/rank bound.

## Fermat and modularity

Tungsten now has the first exact application-level layer: integral
Weierstrass models compute and certify the standard \(b_i,c_4,c_6,\Delta,j\)
invariants and their projective cubic. Admissible changes of variables replay
the \(u^4,u^6,u^{12}\) scaling identities. A bounded exhaustive search over
\(r\bmod p^2,s\bmod p,t\bmod p^3\) certifies local and global minimal models.
Tate's algorithm then certifies local reduction type, Kodaira symbol,
Tamagawa number, split multiplicative status, and the conductor exponent,
including wild additive reduction at 2 and 3. `FreyCurve` checks primitive
integral data, prime exponent \(p\geq5\), the optional Fermat equality, and
the model

```w
frey = Algebra.frey_curve(2, 3, 5)
frey.model.coefficients
frey.certificate.verified?
frey.model.tate_local_data(2).kodaira_symbol # I6*
frey.conductor                              # 2640

# This orientation has a certified u=2 minimalization and conductor:
normalized = Algebra.frey_curve(3, 2, 5)
normalized.model.minimal_model.coefficients
normalized.conductor                         # 330

# This stricter form accepts only an actual proposed solution:
# Algebra.frey_curve_from_solution(a, b, c, p)
```

This does **not** complete the Wiles/Ribet stack. The rational local
elliptic-arithmetic layer is now present. `CuspForms.new(2, 2)` also
replay-checks the classical dimension formula giving
\(\dim S_2(\Gamma_0(2))=0\), the finite terminal space in the usual FLT
application. Exact finite-precision q-series and certified level-one
\(E_4,E_6,\Delta\) expansions provide the beginning of the q-expansion
layer. Weight-two Manin symbols now model
\(P^1(\mathbb Z/N\mathbb Z)\), their relations, cusp boundary, and cuspidal
subspace dimensions, including a zero cuspidal symbol space at level 2.
Prime Hecke operators (including bad-prime \(U_p\)), exact characteristic
polynomials, prime-level degeneracy maps, old subspaces, and canonical new
Hecke quotients are also present with finite replay certificates and named
theorem imports. There is still no mod-\(p\) Galois-representation layer,
eigenform/newform q-expansion recovery, level-lowering proof, or
modularity-lifting kernel. `tungsten-wassat`'s `fermat.w` is a finite SAT
benchmark, not that arithmetic infrastructure.

A useful staged target is an **FLT application checker**:

1. check exponent reduction and Frey invariants;
2. certify minimal models, local reduction, discriminants, and conductors;
3. compute the finite modular-form calculation at the final level
   (the level-2 dimension, weight-two Manin-symbol, prime Hecke, and old/new
   quotient calculations are implemented; eigenforms and mod-\(p\)
   congruence data remain);
4. apply Ribet and Wiles--Taylor--Wiles as explicit trusted theorem imports.

That would be useful and honest, but still relative to those imports. A fully
kernel-checked proof requires formal versions of level lowering, modularity
lifting, deformation theory, patching, and their prerequisites.

## When to choose Tungsten

Reach for Tungsten today when the work benefits from its mathematical syntax,
exact coefficient domains, projective/curve models, and explicit certificate
boundary—especially when a small checker should independently replay a large
search result. For the shell-width program, Tungsten is already a sensible
primary orchestrator and checker.

Reach first for Sage/Magma/PARI or Python libraries when you need a broad
algorithm Tungsten marks missing, a large mature database, highly optimized
general-purpose arithmetic, or the plotting/data ecosystem. A productive
frontier workflow is often:

```text
mature system proposes generators/models/search data
  -> Tungsten reconstructs exact objects
  -> Tungsten checks arithmetic certificates
  -> Wassat produces bounded finite refutations where appropriate
  -> Wrat independently replays those refutations
```

The long-term standard is stronger: Tungsten should produce as well as check
the data, while retaining the independent replay path.

## Visualization roadmap

Current plotting is terminal-scale: sparklines, heatmaps, coarse lines, and a
braille canvas. It is not yet a 3Blue1Brown-style mathematical animation
system.

The intended stack is:

1. a retained 2D/3D scene graph with exact world coordinates, cameras,
   transforms, axes, labels, curves, surfaces, vector fields, and meshes;
2. a timeline with keyframes, easing, morphs, traces, and mathematical
   object correspondences;
3. SVG/HTML Canvas for interactive documentation, plus GPU rendering and
   deterministic video/image export;
4. LaTeX-quality formula layout and stable glyph-to-glyph transforms;
5. notebook/document hooks so examples and diagrams are rebuilt and tested;
6. accessibility metadata, captions, reduced-motion variants, and static
   fallbacks.

Math documentation should eventually pair each concept with the smallest
useful visual—static diagram for structure, interactive plot for parameters,
and animation only for genuinely temporal reasoning. Generated media needs
checked source, deterministic seeds, and a lightweight docs build; large
renders belong in an opt-in artifact job rather than the standard test suite.

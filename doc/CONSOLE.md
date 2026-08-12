# Mathematical inspection in `wit`

Start the interactive console from the repository root:

```sh
bin/wit
```

The console is the self-hosted `compiler/lib/repl.w` embedded in
`bin/tungsten-compiler`; `bin/tungsten console` is equivalent. A fresh clone
must run `bin/tungsten bootstrap` first. There is intentionally no Ruby REPL
fallback, so interactive parsing, errors, history, and execution cannot drift
between hosts.

Type a bare `?` for the shortcut list. `? EXPR` evaluates `EXPR` once, reports
its semantic Tungsten value and type, and asks `tungsten-drawille` for a bounded
terminal visualization when the value has a useful visual interpretation.
Press blank Enter after an inspection to scrub its numeric fields; arrows or a
dial update the value and redraw the same inspection in place. Set
`TUNGSTEN_REPL_DRAWILLE=0` before starting `wit` for textual-only inspection.

The examples below are exercised with the self-hosted REPL. Setup lines are
intentional: names such as `x` and `t` are ordinary REPL variables, so defining
the ring immediately before inspecting prevents an old binding from changing
the example.

## Fast, high-impact examples

An exact integral with a shaded area-under-the-curve plot:

```tungsten
? ∫(x², 0..2)
```

An exact billion-term polynomial sum, reduced symbolically rather than
materializing the range:

```tungsten
? Σ(2x⁷ + 3x², 1..1000000000)
```

The result is the exact integer
`250000001000000001166666666666666666083333334333333335000000000500000000`.

Ramanujan's Delta modular form as an exact q-expansion, coefficient plot, and
certificate metadata. Blank Enter and Up/Down make the precision visibly grow
or shrink:

```tungsten
? ClassicalModularForms.delta(24)
```

A twelfth-order Taylor jet of a transcendental function:

```tungsten
? Calculus.taylor(-> (u) u.sin * u.exp, ~0.0, 12)
```

The Laurent expansion of Gamma around 1, retaining Euler's constant, powers of
pi, and odd zeta values symbolically:

```tungsten
sx = Expression.variable(:x)
? sx.gamma.series(:x, 1, 5)
```

A compact identity showing zeta(3) directly:

```tungsten
? Expression.constant(1).polygamma(2)
```

The result is `-2*ζ(3)`.

A second-order local model with its value, gradient, Hessian, and projected
quadratic surface:

```tungsten
? Differential.new(~1.0, [~2.0, ~-1.0], [[~1.0, ~0.5], [~0.5, ~2.0]])
```

A certified real-algebraic root. These setup lines deliberately replace any
undefined or stale `t`; the tight indexing form exercises the result of the
no-argument `real_roots` call:

```tungsten
root_ring = PolynomialRing.new([:t])
t = root_ring.generator(0)
? (t*t - 2).real_roots[0]
```

A genus-two hyperelliptic curve:

```tungsten
rx = PolynomialRing.new([:t])
t = rx.generator(0)
? HyperellipticCurve.new(t**5 - t)
```

A theta quadratic form rendered as its finite truth table:

```tungsten
? ThetaQuadraticForm.new(SymplecticF2Space.new(2), [1, 0, 0, 1])
```

A three-dimensional helix using the generic numeric-point projection surface:

```tungsten
? (0..63).map -> (i) [Math.cos(~0.2*i.to_f), Math.sin(~0.2*i.to_f), i.to_f/~30.0]
```

## Exact plane geometry and singularities

An implicit quartic whose real zero set is a circle. Contour sampling makes
this intentionally slower (about 15 seconds on the development machine):

```tungsten
r = PolynomialRing.new([:x, :y])
x = r.generators[0]
y = r.generators[1]
? (x*x + y*y - 1)**2
```

The same ring can expose exact local singularity data for a cusp:

```tungsten
local = (y**2 - x**3).local_delta_invariant(0, 1, nil, 4)
? local
```

Useful follow-up inspections are `? local.derivative_resultant`,
`? local.milnor_number`, `? local.delta`, and `? local.certificate`. The final
delta formula is explicitly labelled as a trusted theorem import; the exact
resultant and its replay certificate are separate evidence.

## Projective and elliptic geometry

Use the explicit runtime constructor below in the tree-walking REPL. It makes
the field, dimension, and coordinate names unambiguous. Elliptic plotting is an
intentionally slow showcase (about 25 seconds on the development machine):

```tungsten
p2 = ProjectiveSpace<ℚ, 2>.new(Algebra.field("ℚ"), 2, [:X, :Y, :Z])
? EllipticCurve.new(p2, -1, 1)
```

The same space supports direct projective inspection:

```tungsten
? p2
? p2.point(0, 1, 1)
```

## Spacetime, horizons, perturbations, and brane/bulk geometry

Load the differential-geometry layer once, then build the standard
Schwarzschild model:

```tungsten
use geometry
s = Schwarzschild.new(1)
```

An exponential warped cone places its narrowing apex at infinite intrinsic
distance. Its inspection shows a finite, non-isometric horn wireframe and
reports both the constant normalized angular separation and the shrinking
physical cross-section arc between a pair of meridians. The latter is not an
unrestricted surface-geodesic distance:

```tungsten
? WarpedConeSurface.exponential(1, 1)
```

The narrow end of the drawing is only the end of the sampled display window;
the labelled ideal apex remains at `t = infinity`.

Inspecting the Einstein tensor derives it from the metric/connection/curvature
stack and shows its component sparsity. This is a slower inspection (roughly
10–15 seconds in the tree-walking REPL). Because the current symbolic
simplifier does not collapse every vacuum component syntactically to zero, the
adapter also evaluates all 16 components at a labelled exterior point. It says
explicitly that this is a numerical check, not a symbolic proof:

```tungsten
? s.einstein_tensor
```

The Schwarzschild Killing/event horizon is shown on a radial line with its
kind, coordinate, radius, and description:

```tungsten
? s.horizons
```

The axial `l=2` Regge–Wheeler potential is sampled through the model's public
`samples` API, with its exterior peak and stability-certificate scope. The
certificate is only the nonnegative linear mode-energy result; it does not
claim nonlinear stability:

```tungsten
? s.regge_wheeler(2)
```

Finally, compare a brane segment with the constant-time hyperbolic bulk
geodesic joining its endpoints:

```tungsten
? RandallSundrum.new(1).bulk_chord(4)
```

The plot reports the proper length and `causal shortcut?: false`. It is a
spatial H² chord, not a null-return or faster-than-light claim.

## What the pictures mean

Plots are views, not extra mathematical claims. Formal and q-series plots show
coefficients and do not assert analytic convergence. Algebraic-extension plots
label power-basis coordinates rather than pretending they are a real
embedding. Finite-field and p-adic values are not silently ordered. If an
optional Drawille adapter is absent or raises, `?` still reports the semantic
type and a bounded logical-field view.

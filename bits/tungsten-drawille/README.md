# Tungsten Drawille

Drawille renders bounded terminal graphics with Unicode Braille cells. It owns
the visual interpretation of Tungsten's mathematical objects; `core/algebra`
and `core/calculus` remain exact, display-independent libraries.

## REPL inspection

`wit` loads the adapter lazily for `? EXPR`. The expression is evaluated once,
then the same live value is described and, where meaningful, plotted:

```tungsten
? PolynomialRing.new([:x]).generator(0) ** 3 - 2
? QExpansion.new([0, 1, -2, 3, 5])
? Differential.new(~1.0, [~2.0, ~-1.0], [[~1.0, ~0.5], [~0.5, ~2.0]])

use geometry
s = Schwarzschild.new(1)
? s.einstein_tensor
? s.horizons
? s.regge_wheeler(2)
? RandallSundrum.new(1).bulk_chord(4)
? WarpedConeSurface.exponential(1, 1)
```

The adapters recognize polynomial rings and one-, two-, and three-variable
polynomials; curves and affine charts; elliptic and hyperelliptic curves;
projective spaces and points; number-field, simple-extension, and certified
real-algebraic elements; differentials; q-expansions and modular forms;
formal series; theta quadratic forms; numeric arrays; and vectors.
Differential-geometry adapters cover tensor component structure, horizon radii,
sampled Regge-Wheeler potentials, and spatial brane/bulk chords. The tensor
adapter labels numerical sample checks as such; the perturbation view retains
its linear mode-energy scope, and a spatial bulk chord is never presented as a
causal or faster-than-light shortcut.

Warped-cone inspection draws a non-isometric profile wireframe of the finite
terminal window. It labels the shrink law and distinguishes constant normalized
angular separation from the physical cross-section arc forced toward zero by
the shrinking metric. That arc is not presented as unrestricted surface
geodesic distance. An ideal apex is labelled as `t = infinity`; the end of the
wireframe is never presented as the apex itself.

Formal and q-series are shown as coefficient plots, not as claims of analytic
convergence. Finite-field and p-adic coordinates are never silently treated as
ordered real coordinates. Algebraic-element coefficients are explicitly
labeled as a coordinate view, not an embedding.

## Library API

```tungsten
use drawille/inspection

chart = DrawilleInspection.render(value, 70, 15)
can_render = DrawilleInspection.renderable?(value)

# A sampled curve or area-under-the-curve view. Evaluation remains with the
# caller; viewport fitting, clipping, axes, labels, and rasterization live here.
auc = DrawilleInspection.render_series(samples, -2, 2, 70, 15, true)
```

Numeric point arrays provide a general geometry surface:

```tungsten
helix = []
64.times -> (i)
  t = ~0.2 * i.to_f
  helix.push([Math.cos(t), Math.sin(t), t / ~6.0])

<< DrawilleInspection.render(helix, 70, 15)
```

The lower-level `DrawilleScene`, `DrawilleProjection3D`, `DrawilleViewport`,
and `Canvas` classes are available for custom line scenes. Canvas sizes and
inspection work are capped, and off-screen lines are clipped before Bresenham
rasterization.

## Checks

Run both the interpreter and native forms:

```sh
bin/tungsten run bits/tungsten-drawille/spec/canvas_spec.w
bin/tungsten run bits/tungsten-drawille/spec/inspection_spec.w

bin/tungsten compile bits/tungsten-drawille/spec/canvas_spec.w \
  --out /tmp/drawille-canvas-spec
bin/tungsten compile bits/tungsten-drawille/spec/inspection_spec.w \
  --out /tmp/drawille-inspection-spec
```

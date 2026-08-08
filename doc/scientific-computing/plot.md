# Declarative plotting

`core/plot` is a retained, data-first 2-D mathematical scene foundation. It
turns numeric inputs and deterministic callbacks into explicit geometry; it
does not open a window or delegate scene construction to an external plotting
package.

| Layer | Path | Role |
|-------|------|------|
| Declarative Core | `core/plot.w`, `core/plot/` | coordinates, styles, nodes, scenes, sampling, layout, portable data/JSON |
| Terminal compatibility | `core/plot.w` | legacy sparklines, heatmaps, coarse lines |
| Optional terminal renderer | `bits/tungsten-drawille` | bounded Braille canvas and mathematical inspection |
| Native raster drawing | `core/canvas.w` | native raster drawing: paths, gradients, images, text, PNG ([../canvas.md](../canvas.md)) |

## A mathematical scene

```tungsten
use core/plot

coordinates = Plot.coordinates(
  [~-3.0, ~3.0], [~-1.0, ~9.0], [~60.0, ~40.0, ~680.0, ~340.0])

square = -> (x) x * x
curve = Plot.function(
  square, [~-3.0, ~3.0], 257, coordinates, "square",
  PlotStyle.new("#5b5bd6", nil, ~2.0))

scene = Plot.scene(~800.0, ~450.0, "#ffffff", coordinates)
scene.add(Plot.axes(coordinates, ~1.0, ~1.0, "x", "x^2", "axes"))
scene.add(curve)
scene.add(Plot.label("x^2", [~700.0, ~360.0], :math_source, "formula"))

description = scene.to_data
json = scene.to_json
```

`PlotScene#add` order is layer order. Explicit node ids are stable animation
targets; omitted ids become `node-0`, `node-1`, and so on. Group descendants
receive path ids such as `node-2/node-0`, and all ids are checked for scene-wide
uniqueness.

## Coordinates and geometry

`PlotCoordinateSystem` maps a data rectangle into a logical geometry frame
`[left, bottom, width, height]`, with y increasing upward. `map`, `unmap`, and
`map_vector` make the data-to-geometry boundary explicit. The canonical
portable point is a two-element `Array`, matching `Chart`, `Solve`, and
tungsten-drawille; `Vec2` and other x/y values are accepted at API boundaries
and normalized to that form.

Core nodes are retained values:

- `PlotPolyline`, `PlotPoints`, `PlotArrow`, and `PlotLabel`;
- `PlotSampledCurve` with one or more paths, preserving source samples and
  mapped geometry;
- `PlotVectorField`, preserving source origins/vectors and mapped arrows;
- `PlotAxes`, including explicit tick values and positions;
- `PlotGroup`, with translation, scale, rotation, and child nodes;
- `PlotLayout.grid`, `.horizontal`, and `.vertical`, which produce explicit
  transform groups without guessing font or renderer metrics.

`PlotStyle` records stroke/fill strings, width, opacity, dash pattern, marker,
and text fields. Colors are deliberately portable strings rather than
`Color`'s opaque terminal/runtime pixel value. A backend may interpret CSS hex
or named colors, but Core preserves the exact caller value.

## Deterministic sampling

`Plot.function` samples `y = f(x)` uniformly over a closed range.
`Plot.curve` samples a parametric callback returning a point. Both include the
two endpoints, cap sample counts at 100,000, and split non-finite results into
separate paths instead of joining across a discontinuity. Callback exceptions
remain exceptions; plotting does not claim numerical validity for a failed
model.

`Plot.vector_field` supports uniformly sampled 2-D fields with explicit row,
column, and scale parameters. It is capped at 200 rows and 200 columns. It does
not currently implement streamlines, adaptive sampling, singularity analysis,
3-D fields, or automatic normalization.

Determinism means that the same ordered scene construction, numeric callback,
binary64 environment, and metadata insertion order produce the same value tree
and JSON bytes. Core does not make an impure, random, concurrent, or
platform-dependent callback deterministic.

## Realized model checks

`Plot.model_check` records already-realized observed values and model draws as
a composable plot group. It deliberately does not fit or sample a model:

```tungsten
use core/plot

observed = [[~0.0, ~0.1], [~1.0, ~0.8], [~2.0, ~0.2]]
draws = [
  [[~0.0, ~0.2], [~1.0, ~0.7], [~2.0, ~0.3]],
  [[~0.0, ~0.0], [~1.0, ~0.9], [~2.0, ~0.1]]
]
check = Plot.model_check(
  observed, draws, "posterior-predictive-curve", "shared-linear-y",
  {
    :observed_transform_id => "identity-v1",
    :draw_source_id => "posterior-draws-2026-08-08",
    :seed => 17
  },
  :animate,
  {:id => "fit-check", :units => "m/s"})

scene = Plot.scene()
check.add_to(scene)
```

The required quantity and scale identifiers state the caller's comparability
claim. Required provenance identifies the observed-data transform and source
of the ordered draws. `PlotModelCheck#to_data` preserves those declarations,
optional units, raw points, draw order, coordinate mapping, node data, and
caller metadata under `tungsten.plot.model-check/v1`; it records statistical
validity as `:not_assessed`. Scene-group and timeline metadata embed the smaller
`tungsten.plot.model-check-summary/v1` declaration rather than duplicating all
draw values.

`:superpose` emits `id/observed` plus stable `id/draw-N` polylines. `:animate`
emits `id/observed` and one `id/model-draw` polyline for an Animation timeline
to update. Both forms are ordinary `PlotGroup` data and can be composed with
axes, labels, and layouts. If a `PlotCoordinateSystem` is supplied in options,
the node geometry is mapped while the source points remain unchanged in the
full `PlotModelCheck#to_data` payload.

Inputs must be finite polylines with at least two points and a nonempty ordered
draw Array. Quantity, scale, group id, provenance ids, and units are checked
strictly; unknown option keys raise. Provenance and caller metadata must be
portable nested Arrays/Hashes with String or Symbol keys and scalar leaves. A
shared label does not prove that a transform, sampling process, residual, or
visual comparison is scientifically appropriate.

## Output contract

`PlotScene#to_data` returns only ordinary Arrays, Hashes, Strings, Symbols,
numbers, booleans, and nil under schema `tungsten.plot/v1`. Each node contains
an id, kind, style, geometry, and metadata. This is the initial portable backend
boundary: renderers consume the data rather than being called from Core.

`PlotLabel` accepts `:plain` or `:math_source`. The latter stores mathematical
source for a capable future backend; Tungsten does not parse or run TeX, lay
out glyphs, or promise LaTeX metrics in this tranche.

There is intentionally no Core SVG/PDF/video renderer, GPU scene engine,
interactive notebook frontend, 3-D retained scene, adaptive meshing,
accessibility layout engine, or external graphics-tool shell-out yet. The
optional drawille bit remains the existing bounded terminal renderer. Legacy
`Plot.sparkline`, `.heatmap`, and `.line` remain source-compatible.

## Focused checks

```sh
bin/tungsten run spec/core/plot_scene_spec.w
bin/tungsten compile spec/core/plot_scene_spec.w --out /tmp/plot-scene-spec
/tmp/plot-scene-spec

bin/tungsten run spec/core/plot_model_check_spec.w
bin/tungsten compile spec/core/plot_model_check_spec.w \
  --out /tmp/plot-model-check-spec
/tmp/plot-model-check-spec

bin/tungsten run spec/core/visualization_autoload_spec.w
bin/tungsten compile spec/core/visualization_autoload_spec.w \
  --out /tmp/visualization-autoload-spec
/tmp/visualization-autoload-spec
```

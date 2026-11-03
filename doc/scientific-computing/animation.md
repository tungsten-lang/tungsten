# Deterministic mathematical animation

`core/animation` adds a renderer-independent timeline to `core/plot`. A
timeline resolves property tracks and camera state at exact frame indices. Its
output remains a portable description rather than encoded media. The optional
`core/animation/point_preview` module rasterizes a focused point-scene subset
in memory; `core/animation/window_preview` presents those pixels in a native
macOS window.

## Timeline and transforms

```tungsten
use core/animation

curve = Plot.polyline(
  [[~0.0, ~0.0], [~1.0, ~1.0]], false, "curve")
scene = Plot.scene(~800.0, ~450.0)
scene.add(curve)

timeline = Animation.timeline(scene, ~2.0, 60)
timeline.add(Animation.move(
  "curve", ~0.0, ~2.0, [~0.0, ~0.0], [~3.0, ~1.0]))
timeline.add(Animation.fade("curve", ~0.0, ~0.5))

first = timeline.frame(0).to_data
last = timeline.frame(timeline.frame_count - 1).to_data
description = timeline.to_data
```

Eight runnable examples exercise one or more ordered `PlotPoints` nodes and
deterministic retained tracks:

- [`generative_point_cloud.w`](../examples/animations/generative_point_cloud.w)
  translates [ア / A-na5's original sketch](https://x.com/yuruyurau/status/2086396764580634879),
  retaining 10,000 continuously parameterized source points per dense frame
  and recording the expression's 720-step mathematical period;
- [`cosine_lattice_point_cloud.w`](../examples/animations/cosine_lattice_point_cloud.w)
  translates [@yuruyurau's 8,200-point original](https://x.com/yuruyurau/status/2086405262936768716)
  into a 41-row quantized lattice;
- [`singular_tangent_point_cloud.w`](../examples/animations/singular_tangent_point_cloud.w)
  translates [@yuruyurau's `y = i / 233` original](https://x.com/yuruyurau/status/2086124813534605701)
  at alpha 96/255, retaining 19,800 of 20,000 samples after omitting the exact
  `k = 0` column;
- [`double_phase_tangent_point_cloud.w`](../examples/animations/double_phase_tangent_point_cloud.w)
  translates [@yuruyurau's related `y = i / 250` original](https://x.com/yuruyurau/status/2086123857967190062),
  with alpha 66/255 and a `-2t` harmonic, likewise retaining 19,800 of 20,000
  samples;
- [`near_pole_point_cloud.w`](../examples/animations/near_pole_point_cloud.w)
  translates [ア / A-na5's original `#つぶやきProcessing` sketch](https://x.com/yuruyurau/status/2087125958272909624),
  retaining all 10,000 ordered samples—including finite excursions near the
  formula's formal `1/k` pole—and records that the source license is not stated;
- [`yin_yang_koi_point_cloud.w`](../examples/animations/yin_yang_koi_point_cloud.w)
  applies one original Tungsten Vogel/comma expression to paired formula
  indices, producing two surreal koi as exact central reflections in one
  ordered point cloud rather than transcribing an external sketch;
- [`uncertain_light_flame_point_cloud.w`](../examples/animations/uncertain_light_flame_point_cloud.w)
  is an original equation-driven, three-contour stitched flame intended for
  [The Book of Uncertain Light](https://uncertainlight.com/), with a
  deterministic two-second halo pulse. It does not transcribe the site's SVG
  paths or browser filters; and
- [`raymarched_flower_point_cloud.w`](../examples/animations/raymarched_flower_point_cloud.w)
  expands [Yohei Nishitsuji's compact twigl “flower” shader](https://x.com/YoheiNishitsuji/status/2087060021528101362)
  into explicitly sequenced binary64 fragment evaluations on the source's 4:3
  viewport, then downsamples and quantizes finite colors into 63 fixed RGB
  point layers. Nonfinite rays are omitted, so this is a retained-data
  adaptation rather than pixel-exact GLSL output. Its 136×102 default uses four
  times the former 68×51 fragment count, samples an open 0.8-second excerpt,
  and plays it in ping-pong mode.

Most executable smoke calls use smaller retained timelines for interpreter
responsiveness; the flame can retain its full scalar-opacity loop cheaply.
Without flags they emit deterministic diagnostics. On macOS, compile an
example and pass `--window` to open its retained data in a native Metal/Cocoa
window:

```bash
bin/tungsten compile doc/examples/animations/generative_point_cloud.w \
  --out /tmp/generative-point-cloud --dev
/tmp/generative-point-cloud --window
```

The same two commands work for the other files after changing the basename.
Press Escape or close the window to stop. Dense, exactly closed timelines use
`:closed_loop`, which omits their duplicate terminal sample; short retained
excerpts use `:ping_pong` and play forward and backward without inventing
intermediate geometry. Ordinary `:loop` includes every retained frame.
The raymarched flower performs 130 outer steps with seven octaves per fragment;
its 136×102 default can evaluate up to 164,105,760 octave bodies before the
window opens. Compile that full preset with `--release --native` rather than
`--dev`; pass `--window-smoke` for its faster 16×12, three-frame window check.

`AnimationPointPreview` is the pure rasterizer and works in headless
interpreted or native programs. `AnimationWindowPreview` is its optional,
macOS-native Metal/Cocoa window. Together they support an intentionally narrow
subset: ordered `PlotPoints` leaves, recursively nested identity `PlotGroup` values,
`points`/`opacity` tracks, fixed `#RRGGBB` styles, circles, source-over alpha,
clipping, and the default camera. Unsupported node kinds, coordinate/group
transforms, cameras, and track properties raise instead of being silently
misrendered. Window presentation is not available in interpreted runs or on
Linux/Windows; SVG, video, blur/filter effects, exact browser antialiasing,
and interactive scene editing are outside this first preview adapter. Finite
geometry outside a source canvas remains in the scene and is clipped only
during preview.

`Animation.move`, `.scale`, `.rotate`, `.fade`, and `.morph_points` are
convenience constructors for ordinary `AnimationTrack` values. A frame contains
the immutable base scene description plus ordered updates of the form
`{target, property, value}`. A backend applies those updates to node ids; the
portable timeline resolver itself neither mutates nor rasterizes the scene.

Generic tracks are built from `AnimationKeyframe` values. Supported easing is
`:linear`, `:ease_in`, `:ease_out`, `:ease_in_out`, and cubic `:smooth`.
Interpolation is either:

- `:linear` for numbers, identical-shape nested numeric Arrays, and
  `AnimationCamera2D`; or
- `:step` for discrete values.

Point morphing requires the caller to provide identical nested-array topology.
There is no automatic curve correspondence, path resampling, formula parsing,
or glyph-to-glyph matching. That limitation is explicit so a plausible-looking
animation cannot silently invent mathematical correspondence.

## Hypothetical outcome timelines

An animated `PlotModelCheck` compiles into an exact-frame step timeline:

```tungsten
use core/animation

observed = [[~0.0, ~0.1], [~1.0, ~0.8], [~2.0, ~0.2]]
draws = [
  [[~0.0, ~0.2], [~1.0, ~0.7], [~2.0, ~0.3]],
  [[~0.0, ~0.0], [~1.0, ~0.9], [~2.0, ~0.1]]
]
check = Plot.model_check(
  observed, draws, "posterior-predictive-curve", "shared-linear-y",
  {:observed_transform_id => "identity-v1",
   :draw_source_id => "posterior-draws-2026-08-08"},
  :animate,
  {:id => "fit-check"})
scene = Plot.scene()
check.add_to(scene)

# Every draw owns five frame intervals at 20 frames/second.
timeline = Animation.model_check(scene, check, 5, 20)
```

Keyframe `i` is placed at frame `i * frames_per_draw`. The mathematical
duration is `draw_count * frames_per_draw / fps`, so the last draw remains
visible through the final sample. If binary division would make the timeline's
ceiling rule add a duplicate terminal frame, the stored duration is moved a
few binary64 ulps inward; `:total_frame_intervals` in timeline metadata remains
authoritative. The ordinary `:step` `:points` track preserves input draw order
and supports different point counts between draws. This is retained HOP data,
not a perceptual dwell-time recommendation, statistical validity claim, GIF,
or video renderer. Caller timeline metadata must use the same portable
Array/Hash/scalar value-tree contract as model-check provenance.

## Track-interval verification

Direct assertions can make temporal claims over declared node-property track
supports executable:

```tungsten
use core/animation

verification_scene = Plot.scene()
verification_scene.add(Plot.polyline(
  [[~0.0, ~0.0], [~1.0, ~1.0]], false, "curve"))
verification_timeline = Animation.timeline(verification_scene, ~2.0, 20)
verification_timeline.add(Animation.move(
  "curve", ~0.0, ~1.0, [~0.0, ~0.0], [~1.0, ~0.0]))
verification_timeline.add(Animation.fade(
  "curve", ~1.0, ~1.0, ~1.0, ~0.0))

claim = Animation.assert_track_relation(
  "move-meets-fade",
  "curve", :translate, :meets,
  "curve", :opacity)
report = Animation.verify(verification_timeline, [claim])
raise "temporal claim failed" if !report.passed?()
```

The verifier implements Allen's 13 relations:

```text
before / after                 meets / met_by
overlaps / overlapped_by       starts / started_by
during / contains              finishes / finished_by
equals
```

An interval is exactly the first and last declared keyframe time for one node
track. It is not the interval of nonzero velocity, visible change, or rendered
motion. Equal-valued endpoint keyframes still have support. Camera tracks are
not included in this initial node-track scope.

The default epsilon is exactly zero. A caller may provide one finite,
nonnegative absolute tolerance in timeline seconds. The verifier classifies
all 13 relations together: if tolerance makes zero or multiple relations
consistent, the result is `unknown` with an `:epsilon_ambiguous` diagnostic.
Missing tracks, ambiguous lookup, and intervals no wider than epsilon are also
`unknown`; a uniquely observed relation different from the assertion is
`fail`. Reports preserve assertion order and use
`tungsten.animation.verification/v1`, with pass/fail/unknown counts and witness
intervals. Spatial bounds, collision, path shape, renderer output, natural
language assertion synthesis, and automatic repair are not verified.

## Camera and frame stepping

`AnimationCamera2D` records center, positive zoom, and rotation for an
orthographic 2-D view. A camera track is resolved separately from node updates:

```tungsten
start_view = AnimationCamera2D.new([~0.0, ~0.0], ~1.0, ~0.0)
end_view = AnimationCamera2D.new([~2.0, ~1.0], ~2.0, ~0.25)
timeline.camera_track(Animation.camera(
  ~0.0, ~2.0, start_view, end_view, :smooth))
```

Frame time is derived from its index, never by repeated floating-point
addition:

```text
frame_count = ceil(duration * fps) + 1
time(i) = min(i / fps, duration)
```

The last frame is therefore exactly at `duration`, even when `duration * fps`
is not integral. `each_frame` yields one frame recipe at a time, avoiding a
required all-frames allocation.

## Output and scope

`AnimationTimeline#to_data` uses schema `tungsten.animation/v1` and includes
duration, fps, frame count, base camera, optional camera track, ordered node
tracks, base plot scene, and metadata. `AnimationFrame#to_data` uses
`tungsten.animation.frame/v1`. Both also have deterministic `to_json` views.

The same input order, keyframes, callbacks, and binary64 environment produce
the same descriptions. The contract does not claim bit-identical pixels across
future renderers, nor does it sanitize nondeterministic user callbacks.

The retained model remains deliberately 2-D and data-first. The optional
point rasterizer and macOS window are a focused inspection backend, not a
general renderer. `core/animation` has no media encoder, audio, TeX engine,
formula correspondence solver, 3-D camera, physics simulation, live notebook
frontend, cross-platform interactive engine, or shell call to an external
graphics program. Core's separate immediate-mode modules cover some of that
ground but do not consume `AnimationTimeline` data yet: `Motion` and `Ease`
(`core/motion.w`) give easing, timing windows, and narration captions for
`Svg` frames, `View3D`/`Scene3D` give a 3-D camera over `Svg`, and
`VideoEncoder` (`core/media/`) encodes frames ([../media.md](../media.md)).

## Focused checks

```sh
bin/tungsten spec/core/animation_timeline_spec.w
bin/tungsten run --interpret spec/core/animation_timeline_spec.w

bin/tungsten spec/core/animation_model_check_spec.w
bin/tungsten run --interpret spec/core/animation_model_check_spec.w

bin/tungsten spec/core/animation_verification_spec.w
bin/tungsten run --interpret spec/core/animation_verification_spec.w

bin/tungsten spec/core/animation_point_preview_spec.w
bin/tungsten run --interpret spec/core/animation_point_preview_spec.w
```

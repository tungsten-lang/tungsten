# Deterministic mathematical animation

`core/animation` adds a renderer-independent timeline to `core/plot`. A
timeline resolves property tracks and camera state at exact frame indices. Its
output is a portable description for a future SVG, canvas, image, or video
backend—not encoded media.

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

`Animation.move`, `.scale`, `.rotate`, `.fade`, and `.morph_points` are
convenience constructors for ordinary `AnimationTrack` values. A frame contains
the immutable base scene description plus ordered updates of the form
`{target, property, value}`. A backend applies those updates to node ids; Core
does not mutate or rasterize the scene.

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

Initial scope is deliberately 2-D and data-only. There is no renderer, media
encoder, audio, TeX engine, formula correspondence solver, 3-D camera, physics
simulation, live notebook control, interactive event loop, GPU path, or shell
call to an external graphics program.

## Focused checks

```sh
bin/tungsten run spec/core/animation_timeline_spec.w
bin/tungsten compile spec/core/animation_timeline_spec.w \
  --out /tmp/animation-timeline-spec
/tmp/animation-timeline-spec

bin/tungsten run spec/core/animation_model_check_spec.w
bin/tungsten compile spec/core/animation_model_check_spec.w \
  --out /tmp/animation-model-check-spec
/tmp/animation-model-check-spec

bin/tungsten run spec/core/animation_verification_spec.w
bin/tungsten compile spec/core/animation_verification_spec.w \
  --out /tmp/animation-verification-spec
/tmp/animation-verification-spec
```

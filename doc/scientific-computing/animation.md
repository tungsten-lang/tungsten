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
```

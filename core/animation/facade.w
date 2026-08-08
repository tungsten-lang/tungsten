# Convenience constructors for common transforms. These only build data
# tracks; correspondence, layout, and rendering remain explicit.

+ Animation
  -> .timeline(scene, duration, fps = 60, camera = nil, metadata = nil)
    AnimationTimeline.new(scene, duration, fps, camera, metadata)

  -> .keyframe(time, value, easing = :linear)
    AnimationKeyframe.new(time, value, easing)

  -> .track(target, property, keyframes, interpolation = :linear)
    AnimationTrack.new(target, property, keyframes, interpolation)

  -> .between(target, property, start_time, duration, from, to,
              easing = :smooth, interpolation = :linear)
    start = PlotData.number(start_time, "animation start time")
    span = PlotData.number(duration, "animation span")
    raise "animation transform duration must be positive" if span <= ~0.0
    AnimationTrack.new(target, property, [
      AnimationKeyframe.new(start, from, easing),
      AnimationKeyframe.new(start + span, to)
    ], interpolation)

  -> .move(target, start_time, duration, from, to, easing = :smooth)
    between(target, :translate, start_time, duration, from, to, easing)

  -> .scale(target, start_time, duration, from, to, easing = :smooth)
    between(target, :scale, start_time, duration, from, to, easing)

  -> .rotate(target, start_time, duration, from, to, easing = :smooth)
    between(target, :rotation, start_time, duration, from, to, easing)

  -> .fade(target, start_time, duration, from = ~0.0, to = ~1.0,
           easing = :smooth)
    between(target, :opacity, start_time, duration, from, to, easing)

  # Point morphing is deterministic only when the caller supplies identical
  # nested array topology; no glyph or curve correspondence is guessed.
  -> .morph_points(target, start_time, duration, from, to, easing = :smooth)
    between(target, :points, start_time, duration, from, to, easing)

  -> .camera(start_time, duration, from, to, easing = :smooth)
    between("camera", :state, start_time, duration, from, to, easing)

  -> .interpolate(left, right, progress)
    AnimationValue.interpolate(left, right, progress)

  -> .ease(name, progress)
    AnimationValue.ease(name, progress)

  -> .assert_track_relation(id, left_target, left_property, relation,
                            right_target, right_property)
    AnimationTrackIntervalAssertion.new(
      id, left_target, left_property, relation,
      right_target, right_property)

  -> .verify(timeline, assertions, epsilon = ~0.0)
    AnimationVerifier.verify(timeline, assertions, epsilon)

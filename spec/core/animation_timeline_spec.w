# Deterministic animation foundation. Run in both engines:
#   bin/tungsten run spec/core/animation_timeline_spec.w
#   bin/tungsten compile spec/core/animation_timeline_spec.w \
#     --out /tmp/animation-timeline-spec

use core/animation

-> animation_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> animation_close?(left, right, tolerance = ~1.0e-12)
  difference = left - right
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

-> animation_point_close?(point, x, y, tolerance = ~1.0e-12)
  return false if point.size != 2
  animation_close?(point[0], x, tolerance) && animation_close?(point[1], y, tolerance)

node = Plot.polyline(
  [[~0.0, ~0.0], [~1.0, ~1.0]], false, "curve")
scene = Plot.scene(~640.0, ~360.0)
scene.add(node)

# Frame times are derived from indices, never repeated addition.
timeline = Animation.timeline(scene, ~1.0, 4)
timeline.add(Animation.move(
  "curve", ~0.0, ~1.0, [~0.0, ~0.0], [~10.0, ~-2.0]))
timeline.add(Animation.fade("curve", ~0.0, ~1.0, ~0.0, ~1.0, :linear))
animation_check("timeline.frame_count", timeline.frame_count == 5)
animation_check("timeline.time.0", timeline.time_at(0) == ~0.0)
animation_check("timeline.time.end", timeline.time_at(4) == ~1.0)

partial_timeline = Animation.timeline(scene, ~0.85, 4)
animation_check("timeline.partial.frame_count", partial_timeline.frame_count == 5)
animation_check("timeline.partial.end", partial_timeline.time_at(4) == ~0.85)

middle = timeline.frame(2)
animation_check("frame.index", middle.index == 2)
animation_check("frame.time", middle.time == ~0.5)
animation_check("move.smooth.midpoint",
                animation_point_close?(middle.updates[0][:value], ~5.0, ~-1.0))
animation_check("fade.linear.midpoint", middle.updates[1][:value] == ~0.5)
animation_check("frame.scene", middle.to_data[:scene][:schema] == "tungsten.plot/v1")

# Camera state is a separately resolved track, not a renderer side effect.
camera_start = AnimationCamera2D.new([~0.0, ~0.0], ~1.0, ~0.0)
camera_end = AnimationCamera2D.new([~4.0, ~2.0], ~2.0, ~0.5)
timeline.camera_track(Animation.camera(
  ~0.0, ~1.0, camera_start, camera_end, :linear))
camera_middle = timeline.frame(2).camera
camera_only_middle = timeline.camera_at(2)
animation_check("camera.center",
                animation_point_close?(camera_middle.center, ~2.0, ~1.0))
animation_check("camera.zoom", camera_middle.zoom == ~1.5)
animation_check("camera.rotation", camera_middle.rotation == ~0.25)
animation_check("camera.at_without_updates",
                animation_point_close?(camera_only_middle.center, ~2.0, ~1.0) &&
                camera_only_middle.zoom == ~1.5 &&
                camera_only_middle.rotation == ~0.25)

# Recursive interpolation supports caller-supplied point correspondence.
morphed = Animation.interpolate(
  [[~0.0, ~0.0], [~1.0, ~1.0]],
  [[~2.0, ~0.0], [~1.0, ~3.0]], ~0.5)
first_morph = animation_point_close?(morphed[0], ~1.0, ~0.0)
second_morph = animation_point_close?(morphed[1], ~1.0, ~2.0)
animation_check("morph.points", first_morph && second_morph)

# Step tracks change exactly on the keyframe boundary.
step_track = Animation.track("curve", :visible, [
  Animation.keyframe(~0.0, true),
  Animation.keyframe(~0.75, false)
], :step)
animation_check("step.before", step_track.value_at(~0.5) == true)
animation_check("step.boundary", step_track.value_at(~0.75) == false)

visited = 0
timeline.each_frame -> (frame)
  visited += 1
animation_check("timeline.each_frame", visited == 5)
animation_check("timeline.schema", timeline.to_data[:schema] == "tungsten.animation/v1")
animation_check("timeline.json_deterministic", timeline.to_json == timeline.to_json)

bad_target = false
begin
  Animation.timeline(scene, ~1.0).add(
    Animation.fade("missing", ~0.0, ~1.0))
rescue error
  bad_target = error.to_s.include?("not in the scene")
animation_check("validation.target", bad_target)

bad_shape = false
begin
  Animation.interpolate([~0.0], [~0.0, ~1.0], ~0.5)
rescue error
  bad_shape = error.to_s.include?("identical shape")
animation_check("validation.morph_shape", bad_shape)

<< "animation_timeline_spec: all checks passed"

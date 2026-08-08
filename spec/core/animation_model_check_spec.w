# Exact-frame hypothetical-outcome timelines. Run in both engines:
#   bin/tungsten run spec/core/animation_model_check_spec.w
#   bin/tungsten compile spec/core/animation_model_check_spec.w \
#     --out /tmp/animation-model-check-spec

use core/animation

-> animation_model_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> animation_model_close?(left, right, tolerance = ~1.0e-12)
  difference = left - right
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

-> animation_model_point_close?(point, x, y, tolerance = ~1.0e-12)
  return false if point.size != 2
  x_close = animation_model_close?(point[0], x, tolerance)
  y_close = animation_model_close?(point[1], y, tolerance)
  x_close && y_close

coordinates = Plot.coordinates(
  [~0.0, ~10.0], [~0.0, ~10.0], [~100.0, ~200.0, ~500.0, ~300.0])
draws = [
  [[~1.0, ~1.0], [~2.0, ~2.0]],
  [[~3.0, ~3.0], [~4.0, ~4.0], [~5.0, ~5.0]],
  [[~6.0, ~6.0], [~7.0, ~7.0], [~8.0, ~8.0], [~9.0, ~9.0]]
]
provenance = {
  :observed_transform_id => "observed/ecdf-v1",
  :draw_source_id => "posterior/draws-17"
}
model_check = Plot.model_check(
  [[~0.0, ~0.0], [~10.0, ~10.0]], draws,
  "residual-ecdf", "linear-0-10", provenance, :animate, {
    :id => "residual-check",
    :units => "seconds",
    :coordinate_system => coordinates,
    :metadata => {:purpose => "animation spec"}
  })
scene = Plot.scene(~640.0, ~360.0, "#ffffff", coordinates)
model_check.add_to(scene)

# With three draws and two frames per draw, draw boundaries are frames 0, 2,
# and 4. The inclusive final timeline frame is frame 6, which still shows the
# last draw rather than creating an empty or repeated-order sentinel draw.
timeline = Animation.model_check(scene, model_check, 2, 4, {
  :study_id => "case-17",
  :kind => :caller_value,
  :frames_per_draw => 999
})
animation_model_check("timeline.duration", timeline.duration == ~1.5)
animation_model_check("timeline.frame_count", timeline.frame_count == 7)
animation_model_check("timeline.boundary.time.1", timeline.time_at(1) == ~0.25)
animation_model_check("timeline.boundary.time.2", timeline.time_at(2) == ~0.5)
animation_model_check("timeline.boundary.time.4", timeline.time_at(4) == ~1.0)
animation_model_check("timeline.final.time", timeline.time_at(6) == ~1.5)

track = timeline.tracks[0]
animation_model_check("track.target", track.target == "residual-check/model-draw")
animation_model_check("track.property", track.property == "points")
animation_model_check("track.step", track.interpolation == :step)
animation_model_check("track.keyframe_count", track.keyframes.size == 3)
animation_model_check("track.keyframe.0", track.keyframes[0].time == ~0.0)
animation_model_check("track.keyframe.1", track.keyframes[1].time == ~0.5)
animation_model_check("track.keyframe.2", track.keyframes[2].time == ~1.0)

frame_0 = timeline.frame(0).updates[0][:value]
frame_1 = timeline.frame(1).updates[0][:value]
frame_2 = timeline.frame(2).updates[0][:value]
frame_3 = timeline.frame(3).updates[0][:value]
frame_4 = timeline.frame(4).updates[0][:value]
frame_5 = timeline.frame(5).updates[0][:value]
frame_6 = timeline.frame(6).updates[0][:value]

# Different point counts are valid because the track uses step interpolation.
animation_model_check("step.shape.before.first_boundary",
                      frame_0.size == 2 && frame_1.size == 2)
animation_model_check("step.shape.at.first_boundary",
                      frame_2.size == 3 && frame_3.size == 3)
animation_model_check("step.shape.at.second_boundary",
                      frame_4.size == 4 && frame_5.size == 4 && frame_6.size == 4)

# Representative first points establish input draw order and mapped geometry.
animation_model_check("draw_order.first",
                      animation_model_point_close?(frame_0[0], ~150.0, ~230.0))
animation_model_check("draw_order.second",
                      animation_model_point_close?(frame_2[0], ~250.0, ~290.0))
animation_model_check("draw_order.third",
                      animation_model_point_close?(frame_4[0], ~400.0, ~380.0))
animation_model_check("geometry.last_point",
                      animation_model_point_close?(frame_6[3], ~550.0, ~470.0))
penultimate_draw = animation_model_point_close?(frame_5[0], ~400.0, ~380.0)
final_draw = animation_model_point_close?(frame_6[0], ~400.0, ~380.0)
animation_model_check("final_dwell", penultimate_draw && final_draw)

timeline_metadata = timeline.to_data[:metadata]
animation_model_check("metadata.caller", timeline_metadata[:study_id] == "case-17")
animation_model_check("metadata.kind",
                      timeline_metadata[:kind] == :hypothetical_outcomes)
animation_model_check("metadata.frames_per_draw",
                      timeline_metadata[:frames_per_draw] == 2)
animation_model_check("metadata.total_frame_intervals",
                      timeline_metadata[:total_frame_intervals] == 6)
animation_model_check("metadata.draw_count", timeline_metadata[:draw_count] == 3)
model_metadata = timeline_metadata[:model_check]
animation_model_check("metadata.model_schema",
                      model_metadata[:schema] ==
                      "tungsten.plot.model-check-summary/v1")
animation_model_check("metadata.draw_order", model_metadata[:draw_order] == :input)
animation_model_check("metadata.validity",
                      model_metadata[:statistical_validity] == :not_assessed)
draw_source = model_metadata[:provenance][:draw_source_id]
animation_model_check("metadata.provenance", draw_source == "posterior/draws-17")

# Some rational durations round upward when multiplied back by fps. The HOP
# constructor corrects that binary64 edge so ceil does not add a duplicate
# terminal frame (123 / 7 * 7 is slightly greater than 123 on this path).
rounded_schedule = Animation.model_check(scene, model_check, 41, 7)
animation_model_check("rounding.frame_count",
                      rounded_schedule.frame_count == 124)
animation_model_check("rounding.metadata",
                      rounded_schedule.to_data[:metadata][:total_frame_intervals] == 123)
rounded_final = rounded_schedule.frame(123).updates[0][:value]
animation_model_check("rounding.final_draw",
                      rounded_final.size == 4 &&
                      animation_model_point_close?(rounded_final[0], ~400.0, ~380.0))

wrong_type = false
begin
  Animation.model_check(scene, {:not => "a model check"}, 2, 4)
rescue error
  wrong_type = error.to_s().include?("needs a PlotModelCheck")
animation_model_check("validation.type", wrong_type)

superposed = Plot.model_check(
  [[~0.0, ~0.0], [~1.0, ~1.0]],
  [[[~0.0, ~1.0], [~1.0, ~0.0]]],
  "quantity", "scale", provenance, :superpose, {:id => "superposed-check"})
superposed_scene = Plot.scene()
superposed.add_to(superposed_scene)
wrong_mode = false
begin
  Animation.model_check(superposed_scene, superposed, 2, 4)
rescue error
  wrong_mode = error.to_s().include?("in animate mode")
animation_model_check("validation.mode", wrong_mode)

missing_target_scene = Plot.scene()
missing_target_scene.add(Plot.group(
  [], [~0.0, ~0.0], [~1.0, ~1.0], ~0.0, model_check.id))
missing_node = false
begin
  Animation.model_check(missing_target_scene, model_check, 2, 4)
rescue error
  missing_node = error.to_s().include?("node is not in the scene")
animation_model_check("validation.missing_node", missing_node)

wrong_target_scene = Plot.scene()
wrong_target_scene.add(Plot.group([
  Plot.points(
    [[~0.0, ~0.0], [~1.0, ~1.0]], ~3.0,
    model_check.animated_target_id)
], [~0.0, ~0.0], [~1.0, ~1.0], ~0.0, model_check.id))
wrong_target_type = false
begin
  Animation.model_check(wrong_target_scene, model_check, 2, 4)
rescue error
  wrong_target_type = error.to_s().include?("target must be a polyline")
animation_model_check("validation.target_type", wrong_target_type)

invalid_frame_count = false
begin
  Animation.model_check(scene, model_check, 0, 4)
rescue error
  invalid_frame_count = error.to_s().include?("frames per draw must be a positive integer")
animation_model_check("validation.frames_per_draw.zero", invalid_frame_count)

fractional_frame_count = false
begin
  Animation.model_check(scene, model_check, ~1.5, 4)
rescue error
  fractional_frame_count = error.to_s().include?("frames per draw must be a positive integer")
animation_model_check("validation.frames_per_draw.fractional", fractional_frame_count)

invalid_fps = false
begin
  Animation.model_check(scene, model_check, 2, 0)
rescue error
  invalid_fps = error.to_s().include?("animation fps must be a positive integer")
animation_model_check("validation.fps.zero", invalid_fps)

fractional_fps = false
begin
  Animation.model_check(scene, model_check, 2, ~4.5)
rescue error
  fractional_fps = error.to_s().include?("animation fps must be a positive integer")
animation_model_check("validation.fps.fractional", fractional_fps)

nonportable_metadata = false
begin
  Animation.model_check(
    scene, model_check, 2, 4, {:not_portable => coordinates})
rescue error
  nonportable_metadata = error.to_s.include?("portable value-tree")
animation_model_check("validation.metadata_portable", nonportable_metadata)

<< "animation_model_check_spec: all checks passed"

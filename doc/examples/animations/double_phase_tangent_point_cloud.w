# A deterministic retained-data translation of the fourth supplied p5/dwitter
# point-cloud sketch. Its q term advances at twice the base phase while the
# viewing term advances at one quarter phase. The k=0 source column is
# non-finite, so the example omits exactly those samples and retains every
# other finite coordinate unchanged.

use core/animation/point_preview

-> double_phase_tangent_point_cloud_point(index, phase)
  x = (index % 100).to_f()
  y = index.to_f() / ~250.0
  k = x / ~4.0 - ~12.5

  # The source divides by k. Every residue x=50 therefore produces a
  # non-finite point that cannot enter PlotPoints portable geometry.
  return nil if k == ~0.0

  e = y / ~11.0 + ~7.0
  o = Math.hypot(k, e) / ~8.0
  q = ~3.0 * (Math.tan(y / ~2.0) / ~2.0 + Math.cos(y)) / k
  q += k * (~4.0 / o + Math.cos(y) / ~3.0 + Math.sin(e + o * ~4.0 - phase * ~2.0))
  c = o / ~2.0 + e / ~2.0 - phase / ~4.0
  px = q + ~40.0 * Math.cos(c) + ~200.0
  canvas_y = q * Math.sin(c) - k * k * o / ~6.0 + e * o * ~11.0

  # Plot geometry is Cartesian (y-up); p5 canvas coordinates are y-down.
  PlotData.point([px, ~400.0 - canvas_y], "double-phase tangent point")


-> double_phase_tangent_point_cloud_points(phase, source_sample_count)
  points = []
  index = source_sample_count

  # The original `for (i = 2e4; i--;)` loop visits 19,999 down through 0.
  while index > 0
    index -= 1
    point = double_phase_tangent_point_cloud_point(index, phase)
    points.push(point) if point != nil

  points


-> double_phase_tangent_point_cloud(source_sample_count = 20_000,
                                    retained_frames = 21, fps = 60)
  source_sample_count = PlotData.positive_integer(
    source_sample_count, "source sample count", 20_000)
  if source_sample_count % 100 != 0
    raise "source sample count must contain complete 100-sample lattice rows"
  retained_frames = PlotData.positive_integer(
    retained_frames, "retained frame count", 10_000)
  fps = PlotData.positive_integer(fps, "animation fps", 1_000)
  raise "retained frame count must be at least two" if retained_frames < 2

  omitted_count = source_sample_count / 100
  retained_point_count = source_sample_count - omitted_count
  phase_step = ~3.141592653589793 / ~30.0
  first_points = double_phase_tangent_point_cloud_points(
    phase_step, source_sample_count)
  if first_points.size != retained_point_count
    raise "unexpected non-finite double-phase tangent source samples"

  # This approximates p5's one-pixel white stroke point with alpha 66/255;
  # exact antialiasing and clipping remain renderer concerns.
  point_style = PlotStyle.new(
    nil, "#ffffff", ~0.0, ~66.0 / ~255.0, [], :circle)

  scene = Plot.scene(
    ~400.0, ~400.0, "#090909", nil,
    {
      :title => "Double-phase tangent point cloud",
      :source_coordinate_system => :p5_canvas,
      :geometry_coordinate_system => :cartesian_y_up,
      :source_renderer_clips_to_viewport => true,
      :retained_geometry_clipped => false
    })
  scene.add(Plot.points(
    first_points, ~0.5, "double-phase-tangent-point-cloud", point_style,
    {
      :source_sample_count => source_sample_count,
      :retained_point_count => retained_point_count,
      :omitted_nonfinite_count => omitted_count,
      :omitted_residue => 50,
      :singularity_period => 100,
      :finite_filter_policy => :omit_k_zero_division,
      :point_order => :descending_index,
      :row_width => 100,
      :source_y_divisor => 250,
      :source_alpha_byte => 66
    }))

  frame_intervals = retained_frames - 1
  duration = frame_intervals.to_f() / fps.to_f()
  if Math.ceil(duration * fps.to_f()).to_i() > frame_intervals
    duration -= duration * ~1.0e-15

  keyframes = []
  frame_index = 0
  while frame_index < retained_frames
    # Deriving phase from the index avoids accumulated `t += PI/30` drift.
    phase = (frame_index + 1).to_f() * phase_step
    frame_points = frame_index == 0 ? first_points : double_phase_tangent_point_cloud_points(phase, source_sample_count)
    if frame_points.size != retained_point_count
      raise "double-phase tangent retained point count changed between frames"
    keyframe_time = frame_index == frame_intervals ? duration : frame_index.to_f() / fps.to_f()
    keyframes.push(Animation.keyframe(keyframe_time, frame_points))
    frame_index += 1

  timeline = Animation.timeline(
    scene, duration, fps, nil,
    {
      :sampling => :one_keyframe_per_frame,
      :phase_step_radians => phase_step,
      :first_phase_radians => phase_step,
      :mathematical_period_steps => 240,
      :source_nominal_fps => 60,
      :source_sample_count => source_sample_count,
      :retained_point_count => retained_point_count,
      :omitted_nonfinite_per_frame => omitted_count,
      :finite_filter_policy => :omit_k_zero_division,
      :source_y_divisor => 250,
      :source_alpha_byte => 66,
      :retained_frames => retained_frames,
      :total_frame_intervals => frame_intervals
    })
  timeline.add(Animation.track(
    "double-phase-tangent-point-cloud", :points, keyframes, :step))
  if timeline.frame_count != retained_frames
    raise "could not construct the exact double-phase tangent frame schedule"
  timeline


# The dense builder defaults to 20,000 source samples and 21 retained frames.
# The executable smoke preview stays smaller for interpreter responsiveness.
# A complete mathematical 240-step phase cycle would require 241 samples and
# roughly 4.8 million retained points, so it is not materialized by default.
timeline = double_phase_tangent_point_cloud(1_000, 5)
point_node = timeline.scene.node("double-phase-tangent-point-cloud")
point_metadata = point_node.metadata
samples = timeline.tracks[0].keyframes
first_point = samples[0].value[0]
last_point = samples[samples.size - 1].value[0]
point_moved = first_point[0] != last_point[0] || first_point[1] != last_point[1]

# Source-index anchors pin the repaired formula, draw order, singular filter,
# and p5-to-Cartesian y reflection.
phase_step = ~3.141592653589793 / ~30.0
dense_first = double_phase_tangent_point_cloud_point(19_999, phase_step)
dense_last = double_phase_tangent_point_cloud_point(0, phase_step)
singular = double_phase_tangent_point_cloud_point(19_950, phase_step)
singular_low = double_phase_tangent_point_cloud_point(50, phase_step)
second_phase = double_phase_tangent_point_cloud_point(19_999, phase_step * ~2.0)
anchor_tolerance = ~1.0e-9
anchor_changed = false
anchor_changed = true if (dense_first[0] - ~191.28271477483307).abs > anchor_tolerance
anchor_changed = true if (dense_first[1] - ~82.41288520529918).abs > anchor_tolerance
anchor_changed = true if (dense_last[0] - ~141.92405286345104).abs > anchor_tolerance
anchor_changed = true if (dense_last[1] - ~266.72684834303396).abs > anchor_tolerance
anchor_changed = true if (second_phase[0] - ~192.74692193120174).abs > anchor_tolerance
anchor_changed = true if (second_phase[1] - ~81.86135557218853).abs > anchor_tolerance
raise "double-phase tangent formula anchor changed" if anchor_changed
raise "double-phase tangent source sample was retained" if singular != nil
raise "double-phase tangent low source sample was retained" if singular_low != nil
expected_opacity = ~66.0 / ~255.0
if (point_node.style.opacity - expected_opacity).abs > ~1.0e-15
  raise "double-phase tangent source opacity changed"

half_cycle = double_phase_tangent_point_cloud_point(
  19_999, phase_step + ~4.0 * ~3.141592653589793)
full_cycle = double_phase_tangent_point_cloud_point(
  19_999, phase_step + ~8.0 * ~3.141592653589793)
half_x_moved = (half_cycle[0] - dense_first[0]).abs > ~1.0e-6
half_y_moved = (half_cycle[1] - dense_first[1]).abs > ~1.0e-6
half_cycle_moved = half_x_moved || half_y_moved
full_x_closed = (full_cycle[0] - dense_first[0]).abs < anchor_tolerance
full_y_closed = (full_cycle[1] - dense_first[1]).abs < anchor_tolerance
full_cycle_closed = full_x_closed && full_y_closed
raise "double-phase tangent half-cycle unexpectedly closed" if !half_cycle_moved
raise "double-phase tangent mathematical period changed" if !full_cycle_closed

<< "frames: [timeline.frame_count]"
<< "fps: [timeline.fps]"
<< "source samples: [point_metadata[:source_sample_count]]"
<< "retained points: [point_node.points.size]"
<< "omitted nonfinite: [point_metadata[:omitted_nonfinite_count]]"
<< "source alpha: [point_metadata[:source_alpha_byte]]"
<< "track interpolation: [timeline.tracks[0].interpolation]"
<< "point motion: [point_moved]"
<< "formula anchors: ok"
<< "mathematical period: ok"

if ARGV.include?("--window") || ARGV.include?("--window-smoke")
  window_timeline = ARGV.include?("--window-smoke") ? timeline : double_phase_tangent_point_cloud()
  maximum = ARGV.include?("--window-smoke") ? 3 : nil
  AnimationWindowPreview.show(
    window_timeline, "Tungsten — Double-phase tangent point cloud",
    :ping_pong, maximum)

## expect stdout
## frames: 5
## fps: 60
## source samples: 1000
## retained points: 990
## omitted nonfinite: 10
## source alpha: 66
## track interpolation: step
## point motion: true
## formula anchors: ok
## mathematical period: ok

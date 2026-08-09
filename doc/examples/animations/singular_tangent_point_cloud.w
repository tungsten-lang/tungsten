# A deterministic retained-data translation of the third supplied p5/dwitter
# point-cloud sketch. The source has a regular k=0 singularity; this example
# records and omits those non-finite samples before building portable geometry.

use core/animation/point_preview

-> singular_tangent_point_cloud_point(index, phase)
  x = (index % 100).to_f()
  y = index.to_f() / ~233.0
  k = x / ~4.0 - ~12.5

  # The source divides by k. Every residue x=50 therefore produces a
  # non-finite point that cannot enter PlotPoints portable geometry.
  return nil if k == ~0.0

  e = y / ~9.0 + ~6.0
  o = Math.hypot(k, e) / ~9.0
  q = ~3.0 * (Math.tan(y / ~2.0) / ~2.0 + Math.cos(y)) / k + k * (~5.0 / o + o * Math.sin(y) * Math.sin(e + o * ~4.0 - phase))
  c = o / ~2.0 + e / ~2.0 - phase / ~4.0
  px = q + ~40.0 * Math.cos(c) + ~200.0
  canvas_y = q * Math.sin(c) - k * k * o / ~6.0 + e * o * ~12.0

  # Plot geometry is Cartesian (y-up); p5 canvas coordinates are y-down.
  PlotData.point([px, ~400.0 - canvas_y], "singular-tangent point")


-> singular_tangent_point_cloud_points(phase, source_sample_count)
  points = []
  index = source_sample_count

  # The original `for (i = 2e4; i--;)` loop visits 19,999 down through 0.
  while index > 0
    index -= 1
    point = singular_tangent_point_cloud_point(index, phase)
    points.push(point) if point != nil

  points


-> singular_tangent_point_cloud(source_sample_count = 20_000,
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
  first_points = singular_tangent_point_cloud_points(
    phase_step, source_sample_count)
  if first_points.size != retained_point_count
    raise "unexpected non-finite singular-tangent source samples"

  # This approximates p5's one-pixel white stroke point with alpha 96/255;
  # exact antialiasing and clipping remain renderer concerns.
  point_style = PlotStyle.new(
    nil, "#ffffff", ~0.0, ~96.0 / ~255.0, [], :circle)

  scene = Plot.scene(
    ~400.0, ~400.0, "#090909", nil,
    {
      :title => "Singular tangent point cloud",
      :source_coordinate_system => :p5_canvas,
      :geometry_coordinate_system => :cartesian_y_up,
      :source_renderer_clips_to_viewport => true,
      :retained_geometry_clipped => false
    })
  scene.add(Plot.points(
    first_points, ~0.5, "singular-tangent-point-cloud", point_style,
    {
      :source_sample_count => source_sample_count,
      :retained_point_count => retained_point_count,
      :omitted_nonfinite_count => omitted_count,
      :omitted_residue => 50,
      :singularity_period => 100,
      :finite_filter_policy => :omit_k_zero_division,
      :point_order => :descending_index,
      :row_width => 100
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
    frame_points = frame_index == 0 ? first_points : singular_tangent_point_cloud_points(phase, source_sample_count)
    if frame_points.size != retained_point_count
      raise "singular-tangent retained point count changed between frames"
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
      :retained_frames => retained_frames,
      :total_frame_intervals => frame_intervals
    })
  timeline.add(Animation.track(
    "singular-tangent-point-cloud", :points, keyframes, :step))
  if timeline.frame_count != retained_frames
    raise "could not construct the exact singular-tangent frame schedule"
  timeline


# The dense builder defaults to 20,000 source samples and 21 retained frames.
# The executable smoke preview stays smaller for interpreter responsiveness.
# A complete mathematical 240-step phase cycle would require 241 samples and
# roughly 4.8 million retained points, so it is not materialized by default.
timeline = singular_tangent_point_cloud(1_000, 5)
point_node = timeline.scene.node("singular-tangent-point-cloud")
point_metadata = point_node.metadata
samples = timeline.tracks[0].keyframes
first_point = samples[0].value[0]
last_point = samples[samples.size - 1].value[0]
point_moved = first_point[0] != last_point[0] || first_point[1] != last_point[1]

# Source-index anchors pin the repaired formula, draw order, singular filter,
# and p5-to-Cartesian y reflection.
phase_step = ~3.141592653589793 / ~30.0
dense_first = singular_tangent_point_cloud_point(19_999, phase_step)
dense_last = singular_tangent_point_cloud_point(0, phase_step)
singular = singular_tangent_point_cloud_point(19_950, phase_step)
singular_low = singular_tangent_point_cloud_point(50, phase_step)
anchor_tolerance = ~1.0e-9
anchor_changed = false
anchor_changed = true if (dense_first[0] - ~212.08217751579315).abs > anchor_tolerance
anchor_changed = true if (dense_first[1] - ~20.067401103495797).abs > anchor_tolerance
anchor_changed = true if (dense_last[0] - ~126.23525747707646).abs > anchor_tolerance
anchor_changed = true if (dense_last[1] - ~306.0691350591241).abs > anchor_tolerance
raise "singular-tangent formula anchor changed" if anchor_changed
raise "singular-tangent source sample was retained" if singular != nil
raise "singular-tangent low source sample was retained" if singular_low != nil

half_cycle = singular_tangent_point_cloud_point(
  19_999, phase_step + ~4.0 * ~3.141592653589793)
full_cycle = singular_tangent_point_cloud_point(
  19_999, phase_step + ~8.0 * ~3.141592653589793)
half_x_moved = (half_cycle[0] - dense_first[0]).abs > ~1.0e-6
half_y_moved = (half_cycle[1] - dense_first[1]).abs > ~1.0e-6
half_cycle_moved = half_x_moved || half_y_moved
full_x_closed = (full_cycle[0] - dense_first[0]).abs < anchor_tolerance
full_y_closed = (full_cycle[1] - dense_first[1]).abs < anchor_tolerance
full_cycle_closed = full_x_closed && full_y_closed
raise "singular-tangent half-cycle unexpectedly closed" if !half_cycle_moved
raise "singular-tangent mathematical period changed" if !full_cycle_closed

<< "frames: [timeline.frame_count]"
<< "fps: [timeline.fps]"
<< "source samples: [point_metadata[:source_sample_count]]"
<< "retained points: [point_node.points.size]"
<< "omitted nonfinite: [point_metadata[:omitted_nonfinite_count]]"
<< "track interpolation: [timeline.tracks[0].interpolation]"
<< "point motion: [point_moved]"
<< "formula anchors: ok"
<< "mathematical period: ok"

if ARGV.include?("--window") || ARGV.include?("--window-smoke")
  window_timeline = ARGV.include?("--window-smoke") ? timeline : singular_tangent_point_cloud()
  maximum = ARGV.include?("--window-smoke") ? 3 : nil
  AnimationWindowPreview.show(
    window_timeline, "Tungsten — Singular tangent point cloud", :ping_pong,
    maximum)

## expect stdout
## frames: 5
## fps: 60
## source samples: 1000
## retained points: 990
## omitted nonfinite: 10
## track interpolation: step
## point motion: true
## formula anchors: ok
## mathematical period: ok

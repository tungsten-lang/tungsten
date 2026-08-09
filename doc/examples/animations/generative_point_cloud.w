# A deterministic, retained-data translation of the supplied p5/dwitter
# point-cloud sketch. Core Animation describes frames; the optional point
# preview below can open a native window without becoming part of that data.

use core/animation/point_preview

-> generative_point_cloud_point(index, phase)
  y = index.to_f() / ~43.0
  k = ~5.0 * Math.cos(index.to_f() / ~14.0) * Math.cos(y / ~30.0)
  e = y / ~8.0 - ~13.0

  # p5's mag(k, e) uses a stable hypotenuse calculation.
  magnitude = Math.hypot(k, e)
  d = (magnitude ** 2) / ~59.0 + ~6.0
  q = ~90.0 - ~5.0 * Math.sin(Math.atan2(k, e) * e)
  q += k * (~3.0 + Math.sin(d * d - phase * ~2.0))
  c = d / ~2.0 - phase / ~18.0

  # The escaped source fragment `d\*d**sin(...)` means
  # `d * (d ** sin(...))`; exponentiation binds before multiplication.
  vertical_radius = q + d * (d ** Math.sin(d * ~2.0 - phase / ~3.0))
  px = q * Math.sin(c) + ~200.0
  canvas_y = vertical_radius * Math.cos(c) + ~200.0

  # Plot geometry is Cartesian (y-up), while p5 canvas coordinates are
  # y-down. This reflection preserves the supplied sketch's orientation.
  PlotData.point([px, ~400.0 - canvas_y], "generative point-cloud point")


-> generative_point_cloud_points(phase, point_count)
  points = []
  index = point_count

  # The original loop is `for (i = 1e4; i--;)`, so its body visits
  # 9,999 down through 0 in that order.
  while index > 0
    index -= 1
    points.push(generative_point_cloud_point(index, phase))

  points


-> generative_point_cloud(point_count = 10_000, retained_frames = 21,
                           fps = 60)
  point_count = PlotData.positive_integer(point_count, "point count")
  retained_frames = PlotData.positive_integer(
    retained_frames, "retained frame count", 10_000)
  fps = PlotData.positive_integer(fps, "animation fps", 1_000)
  raise "retained frame count must be at least two" if retained_frames < 2

  phase_step = ~3.141592653589793 / ~20.0
  first_points = generative_point_cloud_points(phase_step, point_count)

  # A filled half-unit circle is a portable approximation of p5's default
  # one-pixel stroke point, not a promise of identical backend rasterization.
  point_style = PlotStyle.new(
    nil, "#ffffff", ~0.0, ~66.0 / ~255.0, [], :circle)

  scene = Plot.scene(
    ~400.0, ~400.0, "#090909", nil,
    {
      :title => "Generative point cloud",
      :source_coordinate_system => :p5_canvas,
      :geometry_coordinate_system => :cartesian_y_up
    })
  scene.add(Plot.points(
    first_points, ~0.5, "point-cloud", point_style,
    {:point_count => point_count}))

  frame_intervals = retained_frames - 1
  duration = frame_intervals.to_f() / fps.to_f()
  if Math.ceil(duration * fps.to_f()).to_i() > frame_intervals
    duration -= duration * ~1.0e-15

  keyframes = []
  frame_index = 0
  while frame_index < retained_frames
    phase = (frame_index + 1).to_f() * phase_step
    frame_points = frame_index == 0 ? first_points : generative_point_cloud_points(phase, point_count)
    keyframe_time = frame_index == frame_intervals ? duration : frame_index.to_f() / fps.to_f()
    keyframes.push(Animation.keyframe(
      keyframe_time, frame_points))
    frame_index += 1

  timeline = Animation.timeline(
    scene, duration, fps, nil,
    {
      :sampling => :one_keyframe_per_frame,
      :phase_step_radians => phase_step,
      :first_phase_radians => phase_step,
      :mathematical_period_radians =>
        ~36.0 * ~3.141592653589793,
      :mathematical_period_steps => 720,
      :point_order => :descending_source_index,
      :source_nominal_fps => 60,
      :point_count => point_count,
      :retained_frames => retained_frames,
      :total_frame_intervals => frame_intervals
    })
  timeline.add(Animation.track("point-cloud", :points, keyframes, :step))
  if timeline.frame_count != retained_frames
    raise "could not construct the exact point-cloud frame schedule"
  timeline


# The builder defaults to a 21-frame, 10,000-point-per-frame retained excerpt
# at p5's nominal 60 frames/second. The executable documentation smoke run
# below uses a smaller preview so it remains friendly to the interpreter.
# Change this call to
# `generative_point_cloud()` for the dense version; memory use grows linearly
# with retained_frames * point_count.
timeline = generative_point_cloud(1_000, 5)
point_node = timeline.scene.node("point-cloud")
samples = timeline.tracks[0].keyframes
first_point = samples[0].value[0]
last_point = samples[samples.size - 1].value[0]
point_moved = first_point[0] != last_point[0] || first_point[1] != last_point[1]

phase_step = ~3.141592653589793 / ~20.0
high_anchor = generative_point_cloud_point(9_999, phase_step)
low_anchor = generative_point_cloud_point(0, phase_step)
anchors = (high_anchor[0] - ~119.3249416142723).abs < ~1.0e-9
anchors = anchors && (high_anchor[1] - ~115.06052517799026).abs < ~1.0e-9
anchors = anchors && (low_anchor[0] - ~104.80096814757951).abs < ~1.0e-9
anchors = anchors && (low_anchor[1] - ~207.69985642804775).abs < ~1.0e-9
raise "generative point-cloud formula anchors changed" if !anchors

pi = ~3.141592653589793
half_period = generative_point_cloud_point(9_999, phase_step + ~18.0 * pi)
full_period = generative_point_cloud_point(9_999, phase_step + ~36.0 * pi)
half_moved = (high_anchor[0] - half_period[0]).abs > ~1.0e-9
half_moved = true if (high_anchor[1] - half_period[1]).abs > ~1.0e-9
period_return = (high_anchor[0] - full_period[0]).abs < ~1.0e-9
period_return = period_return && (high_anchor[1] - full_period[1]).abs < ~1.0e-9
period_steps = (phase_step * ~720.0 - ~36.0 * pi).abs < ~1.0e-12
period_ok = half_moved && period_return && period_steps
raise "generative point-cloud mathematical period changed" if !period_ok

<< "frames: [timeline.frame_count]"
<< "fps: [timeline.fps]"
<< "points per frame: [point_node.points.size]"
<< "track interpolation: [timeline.tracks[0].interpolation]"
<< "point motion: [point_moved]"
<< "formula anchors: ok"
<< "mathematical period: ok"

if ARGV.include?("--window") || ARGV.include?("--window-smoke")
  window_timeline = ARGV.include?("--window-smoke") ? timeline : generative_point_cloud()
  maximum = ARGV.include?("--window-smoke") ? 3 : nil
  AnimationWindowPreview.show(
    window_timeline, "Tungsten — Generative point cloud", :ping_pong,
    maximum)

## expect stdout
## frames: 5
## fps: 60
## points per frame: 1000
## track interpolation: step
## point motion: true
## formula anchors: ok
## mathematical period: ok

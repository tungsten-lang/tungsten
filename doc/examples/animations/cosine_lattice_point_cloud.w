# A deterministic retained-data translation of the original p5.js sketch by
# ア / A-na5 (@yuruyurau), posted August 9, 2026:
# https://x.com/yuruyurau/status/2086405262936768716
#
# The author asks ports to link back to the original:
# https://x.com/yuruyurau/status/2079938925720985812
# No license is stated on the source post, so this example records attribution
# without inferring a license grant. Quantized rows and modulo cosine phases
# form its source lattice; the optional preview is a separate native consumer.

use core/animation/point_preview

-> cosine_lattice_point_cloud_point(index, phase)
  # JavaScript's `i / 200 | 0` truncates toward zero; for these nonnegative
  # indices, that is floor division into complete 200-point rows.
  row = Math.floor(index.to_f() / ~200.0).to_i()
  y = ~5.0 * row.to_f()
  k = Math.cos((index % 200).to_f()) * ~13.0
  e = y / ~8.0 - ~12.0
  magnitude = Math.hypot(k, e)
  d = (magnitude ** 2) / ~109.0

  q = k * ~3.0 + ~80.0 + (k / Math.cos(y * ~5.0)) * Math.sin(d * d - phase)
  c = d / ~2.0 - phase / ~8.0
  px = q * Math.sin(c) + e * Math.sin(d + k - phase) + ~200.0
  canvas_y = (q + ~30.0) * Math.cos(c) + ~200.0

  # Plot geometry is Cartesian (y-up); p5 canvas coordinates are y-down.
  [px, ~400.0 - canvas_y]


-> cosine_lattice_point_cloud_points(phase, point_count)
  points = []
  index = point_count

  # The original `for (i = 8.2e3; i--;)` loop visits 8,199 down through 0.
  while index > 0
    index -= 1
    points.push(cosine_lattice_point_cloud_point(index, phase))

  points


-> cosine_lattice_point_cloud(point_count = 8_200, retained_frames = 21,
                              fps = 60)
  point_count = PlotData.positive_integer(point_count, "point count", 8_200)
  if point_count % 200 != 0
    raise "point count must contain complete 200-point lattice rows"
  retained_frames = PlotData.positive_integer(
    retained_frames, "retained frame count", 10_000)
  fps = PlotData.positive_integer(fps, "animation fps", 1_000)
  raise "retained frame count must be at least two" if retained_frames < 2

  phase_step = ~3.141592653589793 / ~60.0
  first_points = cosine_lattice_point_cloud_points(phase_step, point_count)

  # This approximates p5's one-pixel white stroke point with alpha 96/255;
  # exact antialiasing and clipping remain renderer concerns.
  point_style = PlotStyle.new(
    nil, "#ffffff", ~0.0, ~96.0 / ~255.0, [], :circle)

  scene = Plot.scene(
    ~400.0, ~400.0, "#090909", nil,
    {
      :title => "Cosine lattice point cloud",
      :source_kind => :tweet_p5_point_sketch,
      :source_author => "ア / A-na5",
      :source_handle => "@yuruyurau",
      :source_profile_url => "https://x.com/yuruyurau",
      :source_post_url =>
        "https://x.com/yuruyurau/status/2086405262936768716",
      :source_attribution_request_url =>
        "https://x.com/yuruyurau/status/2079938925720985812",
      :source_published_at => "2026-08-09T10:52:32Z",
      :source_hashtag => "#つぶやきProcessing",
      :source_license => :not_stated,
      :source_formula_sha256 =>
        "13798bdcff43aef10b76ab7017a8ee0cea53a715e58bc39a3bce9d76994197d9",
      :source_formula_hash_normalization =>
        :two_code_lines_lf_no_trailing_lf_without_hashtag_comment,
      :source_canvas => [400, 400],
      :source_media_viewport => [800, 800],
      :source_media_duration_seconds => 16,
      :source_point_count => 8_200,
      :source_stroke_alpha_byte => 96,
      :source_coordinate_system => :p5_canvas,
      :geometry_coordinate_system => :cartesian_y_up,
      :source_renderer_clips_to_viewport => true,
      :retained_geometry_clipped => false
    })
  scene.add(Plot.points(
    first_points, ~0.5, "cosine-lattice-point-cloud", point_style,
    {
      :point_count => point_count,
      :point_order => :descending_index,
      :row_width => 200,
      :row_count => point_count / 200,
      :source_author => "ア / A-na5",
      :source_handle => "@yuruyurau",
      :source_post_url =>
        "https://x.com/yuruyurau/status/2086405262936768716",
      :source_license => :not_stated
    }))

  frame_intervals = retained_frames - 1
  duration = frame_intervals.to_f() / fps.to_f()
  if Math.ceil(duration * fps.to_f()).to_i() > frame_intervals
    duration -= duration * ~1.0e-15

  keyframes = []
  frame_index = 0
  while frame_index < retained_frames
    # Deriving phase from the index avoids accumulated `t += PI/60` drift.
    phase = (frame_index + 1).to_f() * phase_step
    frame_points = frame_index == 0 ? first_points : cosine_lattice_point_cloud_points(phase, point_count)
    keyframe_time = frame_index == frame_intervals ? duration : frame_index.to_f() / fps.to_f()
    keyframes.push(Animation.keyframe(keyframe_time, frame_points))
    frame_index += 1

  timeline = Animation.timeline(
    scene, duration, fps, nil,
    {
      :sampling => :one_keyframe_per_frame,
      :phase_step_radians => phase_step,
      :first_phase_radians => phase_step,
      :mathematical_period_steps => 960,
      :source_nominal_fps => 60,
      :source_point_count => 8_200,
      :point_count => point_count,
      :retained_frames => retained_frames,
      :total_frame_intervals => frame_intervals
    })
  timeline.add(Animation.track(
    "cosine-lattice-point-cloud", :points, keyframes, :step))
  if timeline.frame_count != retained_frames
    raise "could not construct the exact cosine-lattice frame schedule"
  timeline


# The dense builder defaults to 8,200 points and 21 retained frames. The
# executable smoke preview stays smaller for interpreter responsiveness.
# A complete mathematical 960-step phase cycle would use 961 retained samples
# including the terminal phase equivalent to the first. That large value tree
# is intentionally not materialized by default, and periodic libm evaluations
# are not promised to be bit-identical.
timeline = cosine_lattice_point_cloud(1_000, 5)
point_node = timeline.scene.node("cosine-lattice-point-cloud")
point_metadata = point_node.metadata
samples = timeline.tracks[0].keyframes
first_point = samples[0].value[0]
last_point = samples[samples.size - 1].value[0]
point_moved = first_point[0] != last_point[0] || first_point[1] != last_point[1]

# Two source-index anchors pin the repaired formula, draw order, and y flip.
phase_step = ~3.141592653589793 / ~60.0
dense_first = cosine_lattice_point_cloud_point(8_199, phase_step)
dense_last = cosine_lattice_point_cloud_point(0, phase_step)
anchor_tolerance = ~1.0e-9
anchor_changed = false
anchor_changed = true if (dense_first[0] - ~265.05683052127961).abs > anchor_tolerance
anchor_changed = true if (dense_first[1] - ~143.56421095280967).abs > anchor_tolerance
anchor_changed = true if (dense_last[0] - ~331.27701936276975).abs > anchor_tolerance
anchor_changed = true if (dense_last[1] - ~177.24825539046785).abs > anchor_tolerance
raise "cosine-lattice formula anchor changed" if anchor_changed

half_cycle = cosine_lattice_point_cloud_point(
  8_199, phase_step + ~8.0 * ~3.141592653589793)
full_cycle = cosine_lattice_point_cloud_point(
  8_199, phase_step + ~16.0 * ~3.141592653589793)
half_x_moved = (half_cycle[0] - dense_first[0]).abs > ~1.0e-6
half_y_moved = (half_cycle[1] - dense_first[1]).abs > ~1.0e-6
half_cycle_moved = half_x_moved || half_y_moved
full_x_closed = (full_cycle[0] - dense_first[0]).abs < anchor_tolerance
full_y_closed = (full_cycle[1] - dense_first[1]).abs < anchor_tolerance
full_cycle_closed = full_x_closed && full_y_closed
raise "cosine-lattice half-cycle unexpectedly closed" if !half_cycle_moved
raise "cosine-lattice mathematical period changed" if !full_cycle_closed

attribution_ok = point_metadata[:source_author] == "ア / A-na5"
attribution_ok = attribution_ok && point_metadata[:source_handle] == "@yuruyurau"
attribution_ok = attribution_ok && point_metadata[:source_post_url] == "https://x.com/yuruyurau/status/2086405262936768716"
attribution_ok = attribution_ok && point_metadata[:source_license] == :not_stated
raise "cosine-lattice source attribution changed" if !attribution_ok

<< "frames: [timeline.frame_count]"
<< "fps: [timeline.fps]"
<< "points per frame: [point_node.points.size]"
<< "quantized rows: [point_node.metadata[:row_count]]"
<< "track interpolation: [timeline.tracks[0].interpolation]"
<< "point motion: [point_moved]"
<< "formula anchors: ok"
<< "mathematical period: ok"
<< "source attribution: ア / A-na5 (@yuruyurau)"

if ARGV.include?("--window") || ARGV.include?("--window-smoke")
  window_timeline = ARGV.include?("--window-smoke") ? timeline : cosine_lattice_point_cloud()
  maximum = ARGV.include?("--window-smoke") ? 3 : nil
  AnimationWindowPreview.show(
    window_timeline, "Tungsten — Cosine lattice point cloud", :ping_pong,
    maximum)

## expect stdout
## frames: 5
## fps: 60
## points per frame: 1000
## quantized rows: 5
## track interpolation: step
## point motion: true
## formula anchors: ok
## mathematical period: ok
## source attribution: ア / A-na5 (@yuruyurau)

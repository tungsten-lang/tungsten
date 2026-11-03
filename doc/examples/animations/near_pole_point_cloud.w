# A deterministic retained-data translation of the original p5.js sketch by
# ア / A-na5 (@yuruyurau), posted August 11, 2026:
# https://x.com/yuruyurau/status/2087125958272909624
#
# The author asks ports to link back to the original:
# https://x.com/yuruyurau/status/2079938925720985812
# No license is stated on the source post, so this example records attribution
# without inferring a license grant.
# Its formal 1/k pole is never hit by the fixed integer lattice, but nearby
# finite samples produce the long clipped excursions characteristic of the
# source animation.

use core/animation/point_preview

-> near_pole_point_cloud_point(index, phase)
  y = index.to_f() / ~295.0
  k = (~5.0 + Math.sin(y * ~2.0 - phase / ~2.0) * ~2.0) * Math.cos(index.to_f() / ~29.0)
  e = y / ~7.0 - ~13.0
  d = Math.hypot(k, e) - ~6.0

  q = ~3.0 * Math.sin(k * ~2.0) + Math.cos(y) / k
  q += Math.sin(y / ~25.0) * k * (
    ~9.0 + ~4.0 * Math.sin(e * ~9.0 - d * ~3.0 + phase * ~2.0))
  c = d - phase
  px = q + ~50.0 * Math.cos(c) + ~200.0
  canvas_y = q * Math.sin(c) + d * ~39.0

  # Plot geometry is Cartesian (y-up), while p5 canvas coordinates are
  # y-down. Off-canvas finite points remain retained for backend clipping.
  PlotData.point([px, ~400.0 - canvas_y], "near-pole point")


-> near_pole_point_cloud_points(phase, point_count)
  points = []
  index = point_count

  # The source `for (i = 1e4; i--;)` loop visits 9,999 down through 0.
  while index > 0
    index -= 1
    points.push(near_pole_point_cloud_point(index, phase))

  points


-> near_pole_point_cloud(point_count = 10_000, retained_frames = 21,
                          fps = 60)
  point_count = PlotData.positive_integer(
    point_count, "point count", 10_000)
  retained_frames = PlotData.positive_integer(
    retained_frames, "retained frame count", 10_000)
  fps = PlotData.positive_integer(fps, "animation fps", 1_000)
  raise "retained frame count must be at least two" if retained_frames < 2

  retained_point_records = point_count * (retained_frames + 1)
  if retained_point_records > 2_000_000
    raise "near-pole retained point budget exceeds 2,000,000 records"

  pi = ~3.141592653589793
  phase_step = pi / ~240.0
  first_points = near_pole_point_cloud_points(phase_step, point_count)

  # This approximates p5's one-pixel white stroke point with alpha 116/255;
  # exact antialiasing and compositing remain renderer concerns.
  point_style = PlotStyle.new(
    nil, "#ffffff", ~0.0, ~116.0 / ~255.0, [], :circle)

  scene = Plot.scene(
    ~400.0, ~400.0, "#090909", nil,
    {
      :title => "Near-pole point cloud",
      :source_kind => :tweet_p5_point_sketch,
      :source_author => "ア / A-na5",
      :source_handle => "@yuruyurau",
      :source_profile_url => "https://x.com/yuruyurau",
      :source_post_url =>
        "https://x.com/yuruyurau/status/2087125958272909624",
      :source_attribution_request_url =>
        "https://x.com/yuruyurau/status/2079938925720985812",
      :source_published_at => "2026-08-11T10:36:20Z",
      :source_hashtag => "#つぶやきProcessing",
      :source_license => :not_stated,
      :source_formula_sha256 =>
        "d67d5226d96229b0ee7ca76cd022af651bf90249aa9399c797be896eb9c8bae2",
      :source_formula_hash_normalization =>
        :two_code_lines_lf_no_trailing_lf_without_hashtag_comment,
      :source_canvas => [400, 400],
      :source_media_viewport => [800, 800],
      :source_media_duration_seconds => 16,
      :source_point_count => 10_000,
      :source_stroke_alpha_byte => 116,
      :source_y_divisor => 295,
      :source_coordinate_system => :p5_canvas,
      :geometry_coordinate_system => :cartesian_y_up,
      :source_renderer_clips_to_viewport => true,
      :retained_geometry_clipped => false
    })
  scene.add(Plot.points(
    first_points, ~0.5, "near-pole-point-cloud", point_style,
    {
      :point_count => point_count,
      :point_order => :descending_source_index,
      :source_y_divisor => 295,
      :formal_singularity => :one_over_k,
      :sampled_singularity_count => 0,
      :source_author => "ア / A-na5",
      :source_handle => "@yuruyurau",
      :source_post_url =>
        "https://x.com/yuruyurau/status/2087125958272909624",
      :source_license => :not_stated
    }))

  frame_intervals = retained_frames - 1
  duration = frame_intervals.to_f() / fps.to_f()
  if Math.ceil(duration * fps.to_f()).to_i() > frame_intervals
    duration -= duration * ~1.0e-15

  keyframes = []
  frame_index = 0
  while frame_index < retained_frames
    # Index-derived phases avoid accumulated `t += PI/240` drift.
    phase = (frame_index + 1).to_f() * phase_step
    frame_points = frame_index == 0 ? first_points : near_pole_point_cloud_points(phase, point_count)
    keyframe_time = frame_index == frame_intervals ? duration : frame_index.to_f() / fps.to_f()
    keyframes.push(Animation.keyframe(keyframe_time, frame_points))
    frame_index += 1

  timeline = Animation.timeline(
    scene, duration, fps, nil,
    {
      :sampling => :one_keyframe_per_frame,
      :phase_step_radians => phase_step,
      :first_phase_radians => phase_step,
      :mathematical_period_radians => ~4.0 * pi,
      :mathematical_period_steps => 960,
      :nominal_period_seconds => 16,
      :source_nominal_fps => 60,
      :point_count => point_count,
      :retained_frames => retained_frames,
      :retained_point_records => retained_point_records,
      :total_frame_intervals => frame_intervals,
      :periodic_closure => false
    })
  timeline.add(Animation.track(
    "near-pole-point-cloud", :points, keyframes, :step))
  if timeline.frame_count != retained_frames
    raise "could not construct the exact near-pole frame schedule"
  timeline


# The faithful builder defaults to a 21-frame, 10,000-point excerpt. A full
# 960-step cycle would require 961 retained samples and roughly 9.6 million
# points, so it is intentionally not materialized by default. The executable
# smoke preview stays small enough for interpreted documentation checks.
timeline = near_pole_point_cloud(1_000, 5)
point_node = timeline.scene.node("near-pole-point-cloud")
point_metadata = point_node.metadata
samples = timeline.tracks[0].keyframes
first_point = samples[0].value[0]
last_point = samples[samples.size - 1].value[0]
point_moved = first_point[0] != last_point[0] || first_point[1] != last_point[1]

# Source-index anchors pin the formula, descending draw order, y reflection,
# and preservation of the large but finite near-pole excursion.
pi = ~3.141592653589793
phase_step = pi / ~240.0
dense_first = near_pole_point_cloud_point(9_999, phase_step)
dense_last = near_pole_point_cloud_point(0, phase_step)
near_pole = near_pole_point_cloud_point(8_154, phase_step)
anchor_tolerance = ~1.0e-9
anchor_changed = false
anchor_changed = true if (dense_first[0] - ~185.06695564204495).abs > anchor_tolerance
anchor_changed = true if (dense_first[1] - ~289.8242621934437).abs > anchor_tolerance
anchor_changed = true if (dense_last[0] - ~195.8052739233856).abs > anchor_tolerance
anchor_changed = true if (dense_last[1] - ~92.3388076330294).abs > anchor_tolerance
anchor_changed = true if (near_pole[0] - ~2178.243378523327).abs > anchor_tolerance
anchor_changed = true if (near_pole[1] - ~71.7777935040427).abs > anchor_tolerance
raise "near-pole formula anchor changed" if anchor_changed
raise "near-pole excursion was clipped from retained geometry" if near_pole[0] <= ~400.0

half_cycle = near_pole_point_cloud_point(
  9_999, phase_step + ~2.0 * pi)
full_cycle = near_pole_point_cloud_point(
  9_999, phase_step + ~4.0 * pi)
half_moved = (half_cycle[0] - dense_first[0]).abs > ~1.0e-6
half_moved = true if (half_cycle[1] - dense_first[1]).abs > ~1.0e-6
full_closed = (full_cycle[0] - dense_first[0]).abs < anchor_tolerance
full_closed = full_closed && (full_cycle[1] - dense_first[1]).abs < anchor_tolerance
period_steps = (phase_step * ~960.0 - ~4.0 * pi).abs < ~1.0e-12
raise "near-pole half-cycle unexpectedly closed" if !half_moved
raise "near-pole mathematical period changed" if !full_closed || !period_steps

attribution_ok = point_metadata[:source_author] == "ア / A-na5"
attribution_ok = attribution_ok && point_metadata[:source_handle] == "@yuruyurau"
attribution_ok = attribution_ok && point_metadata[:source_post_url] == "https://x.com/yuruyurau/status/2087125958272909624"
attribution_ok = attribution_ok && point_metadata[:source_license] == :not_stated
raise "near-pole source attribution changed" if !attribution_ok

<< "frames: [timeline.frame_count]"
<< "fps: [timeline.fps]"
<< "points per frame: [point_node.points.size]"
<< "track interpolation: [timeline.tracks[0].interpolation]"
<< "point motion: [point_moved]"
<< "near-pole excursion retained: true"
<< "formula anchors: ok"
<< "mathematical period: ok"
<< "source attribution: ア / A-na5 (@yuruyurau)"

if ARGV.include?("--window") || ARGV.include?("--window-smoke")
  window_timeline = ARGV.include?("--window-smoke") ? timeline : near_pole_point_cloud()
  maximum = ARGV.include?("--window-smoke") ? 3 : nil
  AnimationWindowPreview.show(
    window_timeline, "Tungsten — Near-pole point cloud", :ping_pong,
    maximum)

## expect stdout
## frames: 5
## fps: 60
## points per frame: 1000
## track interpolation: step
## point motion: true
## near-pole excursion retained: true
## formula anchors: ok
## mathematical period: ok
## source attribution: ア / A-na5 (@yuruyurau)

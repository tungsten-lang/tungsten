# An original Tungsten, compact Dwitter-style mathematical point expression;
# it is not a transcription of an external sketch.
# One Vogel disk is warped into a swimming comma; adjacent formula indices use
# signs -1 and +1, so the second surreal koi is the first one's exact central
# reflection. There are no separately constructed eyes, fins, triangles,
# patches, tails, or ripple layers. Core retains one ordered PlotPoints value
# and one :step points track. The optional native preview consumes those same
# retained values without changing the formula or schema.

use core/animation/point_preview


-> yin_yang_koi_formula_point(index, phase, points_per_koi)
  total_points = 2 * points_per_koi
  if index < 0 || index >= total_points || index.to_i() != index
    raise "yin-yang koi formula index is out of range"

  # This is the one-loop index map used by the compact authored expression:
  # j = i >> 1 and s = 1 - 2 * (i & 1). A descending loop therefore emits
  # each negative/positive central-reflection pair adjacently.
  vogel_index = Math.floor(index.to_f() / ~2.0).to_i()
  golden_angle = ~3.141592653589793 * (~3.0 - Math.sqrt(~5.0))
  disk_radius = Math.sqrt(
    (vogel_index.to_f() + ~0.5) / points_per_koi.to_f())
  disk_angle = vogel_index.to_f() * golden_angle
  u = disk_radius * Math.cos(disk_angle)
  v = disk_radius * Math.sin(disk_angle)

  # A single smooth polar warp turns the disk into a tapered comma. The
  # Gaussian fold and transverse sine make a tail-like wake emerge from the
  # same map; they do not add another part or another point population.
  interior = ~1.0 - u * u
  fold_delta = u + ~0.88
  fold = Math.exp(~-80.0 * fold_delta * fold_delta)
  half_width = ~25.0 * (~0.62 + ~0.38 * u) * (~1.0 + ~4.5 * fold)
  angle = phase + ~1.25 * u
  angle += ~0.11 * interior * Math.sin(~5.0 * u - ~2.0 * phase)
  angle += ~0.14 * fold * Math.sin(~5.0 * v)
  angle += ~0.03 * v * Math.sin(~17.0 * u + ~3.0 * phase)
  radius = ~64.0 - ~22.0 * u + v * half_width

  # First realize the negative-sign point in Cartesian y-up geometry. Its
  # adjacent positive-sign mate is stored as literal subtraction from 400;
  # this pins exact retained central-reflection correspondence instead of
  # relying on two independently rounded trigonometric evaluations.
  negative = PlotData.point([
    ~200.0 - radius * Math.cos(angle),
    ~200.0 + radius * Math.sin(angle)
  ], "yin-yang Vogel-comma point")
  return negative if index % 2 == 1
  PlotData.point(
    [~400.0 - negative[0], ~400.0 - negative[1]],
    "centrally reflected Vogel-comma point")


-> yin_yang_koi_formula_points(phase, points_per_koi)
  phase = PlotData.number(phase, "yin-yang koi phase")
  points = []
  index = 2 * points_per_koi

  # Mirrors `for (i = 2*n; i--;) a(i)`: formula indices descend to zero.
  while index > 0
    index -= 1
    points.push(yin_yang_koi_formula_point(
      index, phase, points_per_koi))
  points


-> yin_yang_koi_reflection_pairs?(points)
  return false if points.size % 2 != 0
  pair_index = 0
  while pair_index < points.size
    negative = points[pair_index]
    positive = points[pair_index + 1]
    return false if positive[0] != ~400.0 - negative[0]
    return false if positive[1] != ~400.0 - negative[1]
    pair_index += 2
  true


-> yin_yang_koi_points_close?(left, right, epsilon = ~0.0)
  return false if left.size != right.size
  index = 0
  while index < left.size
    return false if (left[index][0] - right[index][0]).abs > epsilon
    return false if (left[index][1] - right[index][1]).abs > epsilon
    index += 1
  true


-> yin_yang_koi_point_cloud(points_per_koi = 4_800,
                             retained_frames = 121, fps = 60)
  points_per_koi = PlotData.positive_integer(
    points_per_koi, "Vogel points per koi", 20_000)
  if points_per_koi < 32
    raise "Vogel points per koi must be at least 32"
  retained_frames = PlotData.positive_integer(
    retained_frames, "retained frame count", 1_000)
  fps = PlotData.positive_integer(fps, "animation fps", 1_000)
  raise "retained frame count must be at least two" if retained_frames < 2

  point_count = 2 * points_per_koi
  retained_point_updates = point_count * retained_frames
  retained_point_records = point_count * (retained_frames + 1)
  if retained_point_records > 2_000_000
    raise "yin-yang koi retained point budget exceeds 2,000,000"

  period_steps = 120
  phase_step = ~2.0 * ~3.141592653589793 / period_steps.to_f()
  first_points = yin_yang_koi_formula_points(~0.0, points_per_koi)
  if !yin_yang_koi_reflection_pairs?(first_points)
    raise "yin-yang koi initial central reflection changed"

  point_style = PlotStyle.new(
    nil, "#f7f2e8", ~0.0, ~72.0 / ~255.0, [], :circle)
  scene = Plot.scene(
    ~400.0, ~400.0, "#090909", nil,
    {
      :title => "Paired Vogel-comma surreal koi",
      :composition => :yin_yang_koi,
      :construction => :single_formula_vogel_comma_warp,
      :formula_coordinate_system => :cartesian_y_up,
      :geometry_coordinate_system => :cartesian_y_up,
      :symmetry_center => [~200.0, ~200.0],
      :renderer_required_for_pixels => true
    })
  scene.add(Plot.points(
    first_points, ~0.5, "yin-yang-koi-point-cloud", point_style,
    {
      :koi_count => 2,
      :points_per_koi => points_per_koi,
      :point_count => point_count,
      :point_order => :descending_formula_index,
      :pair_order => :negative_then_positive,
      :reflection_pair_stride => 2,
      :vogel_radius_offset => ~0.5,
      :golden_angle_radians =>
        ~3.141592653589793 * (~3.0 - Math.sqrt(~5.0)),
      :geometry_symmetry => :exact_central_reflection,
      :labeled_point_correspondence => :formula_index,
      :independent_anatomical_parts => false
    }))

  frame_intervals = retained_frames - 1
  duration = frame_intervals.to_f() / fps.to_f()
  if Math.ceil(duration * fps.to_f()).to_i() > frame_intervals
    duration -= duration * ~1.0e-15

  keyframes = []
  frame_index = 0
  while frame_index < retained_frames
    phase_index = frame_index % period_steps
    points = first_points
    if phase_index != 0
      phase = phase_index.to_f() * phase_step
      points = yin_yang_koi_formula_points(phase, points_per_koi)
    if points.size != point_count
      raise "yin-yang koi point topology changed between frames"
    if !yin_yang_koi_reflection_pairs?(points)
      raise "yin-yang koi central reflection changed between frames"
    keyframe_time = frame_index.to_f() / fps.to_f()
    keyframe_time = duration if frame_index == frame_intervals
    keyframes.push(Animation.keyframe(keyframe_time, points))
    frame_index += 1

  timeline = Animation.timeline(
    scene, duration, fps, nil,
    {
      :sampling => :one_keyframe_per_frame,
      :phase_step_radians => phase_step,
      :first_phase_radians => ~0.0,
      :mathematical_period_radians =>
        ~2.0 * ~3.141592653589793,
      :mathematical_period_steps => period_steps,
      :labeled_point_period_steps => period_steps,
      :periodic_closure => :phase_index_modulo_period,
      :nominal_playback_fps => 60,
      :nominal_period_seconds => ~2.0,
      :period_seconds_at_fps => period_steps.to_f() / fps.to_f(),
      :koi_count => 2,
      :points_per_koi => points_per_koi,
      :point_count => point_count,
      :animated_point_layers => 1,
      :retained_point_updates => retained_point_updates,
      :retained_point_records => retained_point_records,
      :geometry_symmetry => :exact_central_reflection,
      :retained_frames => retained_frames,
      :total_frame_intervals => frame_intervals
    })
  timeline.add(Animation.track(
    "yin-yang-koi-point-cloud", :points, keyframes, :step))
  if timeline.frame_count != retained_frames
    raise "could not construct the exact yin-yang koi frame schedule"
  timeline


# The dense builder retains 4,800 Vogel samples per koi for a complete
# 120-interval loop plus its exact terminal copy. This executable smoke call is
# deliberately small. A separate 32-sample full-loop probe below validates the
# same closure without making the interpreter materialize the dense
# 1,161,600-update loop.
timeline = yin_yang_koi_point_cloud(240, 3, 60)
scene = timeline.scene
point_node = scene.node("yin-yang-koi-point-cloud")
track = timeline.tracks[0]
keyframes = track.keyframes

one_node = scene.nodes.size == 1
one_track = timeline.tracks.size == 1
raise "yin-yang koi scene is no longer one point node" if !one_node
raise "yin-yang koi animation is no longer one points track" if !one_track

symmetry = yin_yang_koi_reflection_pairs?(point_node.points)
symmetry = symmetry && yin_yang_koi_reflection_pairs?(keyframes[1].value)
raise "yin-yang koi exact central reflection changed" if !symmetry

first_point = keyframes[0].value[0]
motion_point = keyframes[1].value[0]
motion = first_point[0] != motion_point[0]
motion = true if first_point[1] != motion_point[1]
raise "yin-yang koi smoke preview did not move" if !motion

anchor_tolerance = ~1.0e-9
dense_first = yin_yang_koi_formula_point(9_599, ~0.0, 4_800)
dense_pair = yin_yang_koi_formula_point(9_598, ~0.0, 4_800)
anchor_changed = (dense_first[0] - ~179.45091144325517).abs > anchor_tolerance
anchor_changed = true if (dense_first[1] - ~247.28667866679365).abs > anchor_tolerance
anchor_changed = true if (dense_pair[0] - ~220.54908855674483).abs > anchor_tolerance
anchor_changed = true if (dense_pair[1] - ~152.71332133320635).abs > anchor_tolerance
raise "yin-yang koi formula anchor changed" if anchor_changed

formula_start = yin_yang_koi_formula_points(~0.0, 32)
formula_period = yin_yang_koi_formula_points(
  ~2.0 * ~3.141592653589793, 32)
formula_periodic = yin_yang_koi_points_close?(
  formula_start, formula_period, anchor_tolerance)
raise "yin-yang koi mathematical period changed" if !formula_periodic

loop_timeline = yin_yang_koi_point_cloud(32, 121, 60)
loop_keyframes = loop_timeline.tracks[0].keyframes
exact_closure = yin_yang_koi_points_close?(
  loop_keyframes[0].value, loop_keyframes[120].value)
raise "yin-yang koi retained loop did not close exactly" if !exact_closure

budget_guard = false
begin
  yin_yang_koi_point_cloud(20_000, 121, 60)
rescue error
  budget_guard = error.to_s().include?("budget")
raise "yin-yang koi retained budget guard changed" if !budget_guard

<< "frames: [timeline.frame_count]"
<< "fps: [timeline.fps]"
<< "koi: [point_node.metadata[:koi_count]]"
<< "points per koi: [point_node.metadata[:points_per_koi]]"
<< "points per frame: [point_node.points.size]"
<< "scene point nodes: [scene.nodes.size]"
<< "animated tracks: [timeline.tracks.size]"
<< "track interpolation: [track.interpolation]"
<< "central reflection: [symmetry]"
<< "point motion: [motion]"
<< "120-step formula period: [formula_periodic]"
<< "exact retained closure: [exact_closure]"
<< "budget guard: [budget_guard]"
<< "formula anchors: ok"

if ARGV.include?("--window") || ARGV.include?("--window-smoke")
  window_timeline = ARGV.include?("--window-smoke") ? timeline : yin_yang_koi_point_cloud()
  maximum = ARGV.include?("--window-smoke") ? 3 : nil
  playback = ARGV.include?("--window-smoke") ? :ping_pong : :closed_loop
  AnimationWindowPreview.show(
    window_timeline, "Tungsten — Paired surreal koi", playback, maximum)

## expect stdout
## frames: 3
## fps: 60
## koi: 2
## points per koi: 240
## points per frame: 480
## scene point nodes: 1
## animated tracks: 1
## track interpolation: step
## central reflection: true
## point motion: true
## 120-step formula period: true
## exact retained closure: true
## budget guard: true
## formula anchors: ok

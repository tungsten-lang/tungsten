# Original mathematical geometry for a flame intended for uncertainlight.com.
# Three nested, asymmetrically bowed teardrop equations are sampled into fixed
# dash patterns; duplicate low-opacity point layers provide a renderer-neutral
# glow. The warm palette is selected for that site context, while no SVG path,
# browser filter, or external graphics program is used.

use core/animation/point_preview


-> uncertain_light_flame_layer_spec(layer)
  if layer == :outer
    return {
      :name => :outer,
      :color => "#D4872C",
      :top => ~352.0,
      :bottom => ~48.0,
      :half_width => ~108.0,
      :lean => ~-12.0,
      :curl => ~7.0,
      :edge_phase => ~0.2,
      :vertical_ripple => ~4.0,
      :formula_samples => 280,
      :dash_on => 7,
      :dash_off => 5,
      :crisp_radius => ~2.5,
      :crisp_opacity => ~0.9,
      :halo_radius => ~6.0,
      :halo_base_opacity => ~0.08,
      :halo_amplitude => ~0.025,
      :halo_harmonic => 2,
      :halo_phase => ~0.0
    }
  elsif layer == :inner
    return {
      :name => :inner,
      :color => "#E8A948",
      :top => ~310.0,
      :bottom => ~82.0,
      :half_width => ~63.0,
      :lean => ~10.0,
      :curl => ~-5.0,
      :edge_phase => ~1.1,
      :vertical_ripple => ~3.0,
      :formula_samples => 240,
      :dash_on => 6,
      :dash_off => 4,
      :crisp_radius => ~2.0,
      :crisp_opacity => ~0.94,
      :halo_radius => ~5.0,
      :halo_base_opacity => ~0.12,
      :halo_amplitude => ~0.035,
      :halo_harmonic => 3,
      :halo_phase => ~0.7
    }
  elsif layer == :core
    return {
      :name => :core,
      :color => "#F5D590",
      :top => ~254.0,
      :bottom => ~112.0,
      :half_width => ~34.0,
      :lean => ~-4.0,
      :curl => ~4.0,
      :edge_phase => ~2.0,
      :vertical_ripple => ~2.0,
      :formula_samples => 200,
      :dash_on => 4,
      :dash_off => 3,
      :crisp_radius => ~1.5,
      :crisp_opacity => ~0.98,
      :halo_radius => ~4.0,
      :halo_base_opacity => ~0.18,
      :halo_amplitude => ~0.05,
      :halo_harmonic => 5,
      :halo_phase => ~1.4
    }
  raise "uncertain-light flame layer must be outer, inner, or core"


# One compact two-sided teardrop expression. The first half travels from the
# apex down the left side; the second travels from the base up the right side.
# Width and centerline use different harmonics, giving the nested flame its
# hand-drawn, uncertain lean while keeping both endpoints exact.
-> uncertain_light_flame_point(layer, index)
  spec = uncertain_light_flame_layer_spec(layer)
  sample_count = spec[:formula_samples]
  integer = index.to_i()
  if integer != index || integer < 0 || integer >= sample_count
    raise "uncertain-light flame formula index is out of range"
  half = sample_count / 2
  return [~200.0, spec[:top]] if integer == 0
  return [~200.0, spec[:bottom]] if integer == half

  side = ~-1.0
  q = integer.to_f() / half.to_f()
  if integer >= half
    side = ~1.0
    q = (sample_count - integer).to_f() / half.to_f()

  pi = ~3.141592653589793
  flame = Math.sin(pi * q)
  envelope = flame ** ~0.72
  lower_weight = ~0.52 + ~0.48 * q
  center = spec[:lean] * flame
  center += spec[:curl] * Math.sin(~2.0 * pi * q) * flame
  edge = ~1.0 + side * ~0.07 * Math.sin(
    ~3.0 * pi * q + spec[:edge_phase])
  width = spec[:half_width] * envelope * lower_weight * edge
  y = spec[:top] + (spec[:bottom] - spec[:top]) * q
  y += side * spec[:vertical_ripple] * flame * flame
  PlotData.point(
    [~200.0 + center + side * width, y],
    "uncertain-light mathematical flame point")


-> uncertain_light_flame_stitches(layer)
  spec = uncertain_light_flame_layer_spec(layer)
  points = []
  cycle = spec[:dash_on] + spec[:dash_off]
  index = 0
  while index < spec[:formula_samples]
    if index % cycle < spec[:dash_on]
      points.push(uncertain_light_flame_point(layer, index))
    index += 1
  points


-> uncertain_light_flame_glow_value(layer, phase_index)
  spec = uncertain_light_flame_layer_spec(layer)
  phase_fraction = (phase_index % 120).to_f() / ~120.0
  phase = ~2.0 * ~3.141592653589793 * phase_fraction
  spec[:halo_base_opacity] + spec[:halo_amplitude] * Math.sin(
    spec[:halo_harmonic].to_f() * phase + spec[:halo_phase])


-> uncertain_light_flame_point_cloud(retained_frames = 121, fps = 60)
  retained_frames = PlotData.positive_integer(
    retained_frames, "retained frame count", 1_000)
  fps = PlotData.positive_integer(fps, "animation fps", 1_000)
  raise "retained frame count must be at least two" if retained_frames < 2

  layers = [:outer, :inner, :core]
  stitches = {}
  unique_count = 0
  layer_index = 0
  while layer_index < layers.size
    layer = layers[layer_index]
    points = uncertain_light_flame_stitches(layer)
    stitches[layer] = points
    unique_count += points.size
    layer_index += 1

  scene = Plot.scene(
    ~400.0, ~400.0, "#1A1714", nil,
    {
      :title => "Uncertain Light mathematical flame",
      :intended_context => "https://uncertainlight.com/",
      :composition => :nested_stitched_flame,
      :construction => :original_two_sided_teardrop_equation,
      :geometry_provenance => :original_equation,
      :palette_context_url => "https://uncertainlight.com/",
      :palette_role => :site_contextual_warm_flame,
      :geometry_coordinate_system => :cartesian_y_up,
      :external_path_data_used => false,
      :renderer_required_for_pixels => true
    })

  children = []
  # Halos are inserted first so crisp stitches remain legible above them.
  layer_index = 0
  while layer_index < layers.size
    layer = layers[layer_index]
    spec = uncertain_light_flame_layer_spec(layer)
    style = PlotStyle.new(
      nil, spec[:color], ~0.0,
      uncertain_light_flame_glow_value(layer, 0), [], :circle)
    children.push(Plot.points(
      stitches[layer], spec[:halo_radius],
      "uncertain-light-" + layer.to_s() + "-glow", style,
      {
        :role => :glow,
        :contour => layer,
        :point_count => stitches[layer].size,
        :glow_approximation => :duplicate_point_halo
      }))
    layer_index += 1
  layer_index = 0
  while layer_index < layers.size
    layer = layers[layer_index]
    spec = uncertain_light_flame_layer_spec(layer)
    style = PlotStyle.new(
      nil, spec[:color], ~0.0, spec[:crisp_opacity], [], :circle)
    children.push(Plot.points(
      stitches[layer], spec[:crisp_radius],
      "uncertain-light-" + layer.to_s() + "-stitches", style,
      {
        :role => :stitches,
        :contour => layer,
        :point_count => stitches[layer].size,
        :formula_sample_count => spec[:formula_samples],
        :dash_index_pattern => [spec[:dash_on], spec[:dash_off]],
        :point_order => :apex_left_base_right_apex
      }))
    layer_index += 1

  group = Plot.group(
    children, [~0.0, ~0.0], [~1.0, ~1.0], ~0.0,
    "uncertain-light-flame", nil,
    {
      :contour_count => 3,
      :unique_stitched_points => unique_count,
      :retained_point_records => unique_count * 2,
      :fixed_layer_order => [
        "uncertain-light-outer-glow",
        "uncertain-light-inner-glow",
        "uncertain-light-core-glow",
        "uncertain-light-outer-stitches",
        "uncertain-light-inner-stitches",
        "uncertain-light-core-stitches"
      ]
    })
  scene.add(group)

  frame_intervals = retained_frames - 1
  duration = frame_intervals.to_f() / fps.to_f()
  if Math.ceil(duration * fps.to_f()).to_i() > frame_intervals
    duration -= duration * ~1.0e-15

  timeline = Animation.timeline(
    scene, duration, fps, nil,
    {
      :sampling => :scalar_glow_per_frame,
      :mathematical_period_steps => 120,
      :nominal_playback_fps => 60,
      :nominal_period_seconds => ~2.0,
      :closure => :phase_index_modulo_period,
      :animated_properties => :halo_opacity,
      :retained_frames => retained_frames,
      :total_frame_intervals => frame_intervals
    })

  layer_index = 0
  while layer_index < layers.size
    layer = layers[layer_index]
    keyframes = []
    frame_index = 0
    while frame_index < retained_frames
      time = frame_index.to_f() / fps.to_f()
      time = duration if frame_index == frame_intervals
      keyframes.push(Animation.keyframe(
        time, uncertain_light_flame_glow_value(layer, frame_index)))
      frame_index += 1
    timeline.add(Animation.track(
      "uncertain-light-" + layer.to_s() + "-glow",
      :opacity, keyframes, :linear))
    layer_index += 1

  if timeline.frame_count != retained_frames
    raise "could not construct the exact uncertain-light flame frame schedule"
  timeline


-> uncertain_light_flame_bounds(points)
  bounds = [points[0][0], points[0][0], points[0][1], points[0][1]]
  index = 1
  while index < points.size
    point = points[index]
    bounds[0] = point[0] if point[0] < bounds[0]
    bounds[1] = point[0] if point[0] > bounds[1]
    bounds[2] = point[1] if point[1] < bounds[2]
    bounds[3] = point[1] if point[1] > bounds[3]
    index += 1
  bounds


# Geometry is static and small, so the executable example keeps the complete
# two-second scalar glow loop while retaining the formula only once.
timeline = uncertain_light_flame_point_cloud()
group = timeline.scene.node("uncertain-light-flame")
children = group.children

counts_ok = children[0].points.size == 165
counts_ok = counts_ok && children[1].points.size == 144
counts_ok = counts_ok && children[2].points.size == 116
raise "uncertain-light flame dash counts changed" if !counts_ok

outer_top = uncertain_light_flame_point(:outer, 0)
outer_bottom = uncertain_light_flame_point(:outer, 140)
inner_top = uncertain_light_flame_point(:inner, 0)
core_bottom = uncertain_light_flame_point(:core, 100)
anchors_ok = outer_top[0] == ~200.0 && outer_top[1] == ~352.0
anchors_ok = anchors_ok && outer_bottom[0] == ~200.0
anchors_ok = anchors_ok && outer_bottom[1] == ~48.0
anchors_ok = anchors_ok && inner_top[0] == ~200.0
anchors_ok = anchors_ok && inner_top[1] == ~310.0
anchors_ok = anchors_ok && core_bottom[0] == ~200.0
anchors_ok = anchors_ok && core_bottom[1] == ~112.0
raise "uncertain-light flame formula anchors changed" if !anchors_ok

outer_bounds = uncertain_light_flame_bounds(children[0].points)
inner_bounds = uncertain_light_flame_bounds(children[1].points)
core_bounds = uncertain_light_flame_bounds(children[2].points)
nested = outer_bounds[0] < inner_bounds[0]
nested = nested && outer_bounds[1] > inner_bounds[1]
nested = nested && outer_bounds[2] < inner_bounds[2]
nested = nested && outer_bounds[3] > inner_bounds[3]
nested = nested && inner_bounds[0] < core_bounds[0]
nested = nested && inner_bounds[1] > core_bounds[1]
nested = nested && inner_bounds[2] < core_bounds[2]
nested = nested && inner_bounds[3] > core_bounds[3]
raise "uncertain-light flame contours stopped nesting" if !nested

motion = true
closure = true
resolved = true
expected_targets = [
  "uncertain-light-outer-glow",
  "uncertain-light-inner-glow",
  "uncertain-light-core-glow"
]
first_updates = timeline.frame(0).updates
motion_updates = timeline.frame(17).updates
final_updates = timeline.frame(120).updates
track_index = 0
while track_index < timeline.tracks.size
  motion = false if first_updates[track_index][:value] == motion_updates[track_index][:value]
  closure = false if first_updates[track_index][:value] != final_updates[track_index][:value]
  resolved = false if first_updates[track_index][:target] != expected_targets[track_index]
  resolved = false if first_updates[track_index][:property] != "opacity"
  track_index += 1
raise "uncertain-light flame glow stopped moving" if !motion
raise "uncertain-light flame loop stopped closing" if !closure
raise "uncertain-light flame resolved updates changed" if !resolved

<< "frames: [timeline.frame_count]"
<< "fps: [timeline.fps]"
<< "contours: [group.metadata[:contour_count]]"
<< "unique stitched points: [group.metadata[:unique_stitched_points]]"
<< "retained point records: [group.metadata[:retained_point_records]]"
<< "animated glow layers: [timeline.tracks.size]"
<< "track interpolation: [timeline.tracks[0].interpolation]"
<< "resolved schedule: [resolved]"
<< "nested bounds: [nested]"
<< "glow motion: [motion]"
<< "exact closure: [closure]"
<< "formula anchors: ok"

if ARGV.include?("--window") || ARGV.include?("--window-smoke")
  maximum = ARGV.include?("--window-smoke") ? 3 : nil
  AnimationWindowPreview.show(
    timeline, "Tungsten — Uncertain Light mathematical flame",
    :closed_loop, maximum)

## expect stdout
## frames: 121
## fps: 60
## contours: 3
## unique stitched points: 425
## retained point records: 850
## animated glow layers: 3
## track interpolation: linear
## resolved schedule: true
## nested bounds: true
## glow motion: true
## exact closure: true
## formula anchors: ok

# A deterministic retained-data adaptation of Yohei Nishitsuji's compact
# tweet-GLSL "flower" fragment shader:
#   https://x.com/YoheiNishitsuji/status/2087060021528101362
# Reproducible twigl program:
#   https://twigl.app?ol=true&ss=-OzjSA4EjdVkIfeW0tSh
# SHA-256 of the exact single-line fragment before its trailing hashtag:
#   ff92ab3b1f7408940a45bb0fb45599561221482035188f2476b40eb6fb201e37
#
# Original formula copyright (c) 2026 Yohei Nishitsuji. The author states that
# code shared on X is MIT licensed: https://x.com/YoheiNishitsuji
# The expanded HSV helper follows twigl's MIT-licensed definition:
#   https://github.com/doxas/twigl
#
# Plain GLSL leaves the code-golf fragment's uninitialized locals undefined,
# while its WebGL host specifies zero initialization. This adaptation makes the
# host state explicit: e=R=0, q=(0,0,0), and rgb=(0,0,0) before q.zy is
# decremented.
#
# The source is a 130-step additive RGB ray march, not native point geometry.
# This example evaluates a four-to-three fragment-center lattice and rejects a
# sample at its first nonfinite intermediate. It clamps finite RGB and quantizes
# it into 63 fixed nonblack PlotPoints palette layers. It preserves the
# normalized formula and evaluation order while explicitly giving up full
# resolution, the source GLSL highp implementation's rounding, continuous
# color, and pixel-exact additive framebuffer output.

use core/animation/point_preview


-> raymarched_flower_palette
  [
    "#000055", "#0000aa", "#0000ff", "#005500",
    "#005555", "#0055aa", "#0055ff", "#00aa00",
    "#00aa55", "#00aaaa", "#00aaff", "#00ff00",
    "#00ff55", "#00ffaa", "#00ffff", "#550000",
    "#550055", "#5500aa", "#5500ff", "#555500",
    "#555555", "#5555aa", "#5555ff", "#55aa00",
    "#55aa55", "#55aaaa", "#55aaff", "#55ff00",
    "#55ff55", "#55ffaa", "#55ffff", "#aa0000",
    "#aa0055", "#aa00aa", "#aa00ff", "#aa5500",
    "#aa5555", "#aa55aa", "#aa55ff", "#aaaa00",
    "#aaaa55", "#aaaaaa", "#aaaaff", "#aaff00",
    "#aaff55", "#aaffaa", "#aaffff", "#ff0000",
    "#ff0055", "#ff00aa", "#ff00ff", "#ff5500",
    "#ff5555", "#ff55aa", "#ff55ff", "#ffaa00",
    "#ffaa55", "#ffaaaa", "#ffaaff", "#ffff00",
    "#ffff55", "#ffffaa", "#ffffff"
  ]


-> raymarched_flower_clamp(value, lower = ~0.0, upper = ~1.0)
  return lower if value < lower
  return upper if value > upper
  value


-> raymarched_flower_fract(value)
  value - Math.floor(value)


# twigl's hsv(h, s, v): hue is measured in turns and wraps through fract.
-> raymarched_flower_hsv(hue, saturation, value)
  offsets = [~1.0, ~2.0 / ~3.0, ~1.0 / ~3.0]
  channels = []
  index = 0
  while index < 3
    component = raymarched_flower_fract(hue + offsets[index])
    component = (component * ~6.0 - ~3.0).abs
    ramp = raymarched_flower_clamp(component - ~1.0)
    channels.push(value * ((~1.0 - saturation) + ramp * saturation))
    index += 1
  channels


# Expand one normalized fragment invocation. The deterministic zero-state
# repair followed by q.zy-- gives q=(0,-1,-1). FC/r is sampled at pixel centers
# in the lower-left/y-up coordinate system used by fragment shaders.
-> raymarched_flower_rgb(fragment_x, fragment_y, shader_time)
  dx = fragment_x * ~0.4 - ~0.2
  dy = fragment_y * ~0.4 + ~0.8
  dz = ~1.0
  qx = ~0.0
  qy = ~-1.0
  qz = ~-1.0
  e = ~0.0
  radius = ~0.0
  red = ~0.0
  green = ~0.0
  blue = ~0.0
  hsv_floor = ~1.0 - ~0.7
  outer = 0

  while outer < 130
    advance = e * radius * ~0.1
    qx += dx * advance
    qy += dy * advance
    qz += dz * advance

    radius = Math.hypot(Math.hypot(qx, qy), qz)
    return nil if radius.nan?() || radius.infinite?() || radius <= ~0.0
    transformed_x = Math.log(radius) - shader_time * ~0.3
    transformed_y = Math.exp(radius - qz * ~0.5)
    return nil if transformed_y.nan?() || transformed_y.infinite?()
    transformed_z = Math.atan2(qy, qx) + shader_time * ~0.3

    # `for(e=--p.y; s<1e3; s+=s)` starts at exp(...)-1 and visits the
    # seven exact dyadic scales 13,26,52,104,208,416,832.
    e = transformed_y - ~1.0
    scale = ~13.0
    while scale < ~1000.0
      octave = Math.cos(transformed_x * scale) * Math.sin(transformed_z * scale + ~0.5)
      octave += Math.cos(transformed_z * scale) * Math.sin(transformed_z * scale + ~0.5)
      octave += Math.cos(transformed_z * scale) * Math.sin(transformed_x * scale + ~0.5)
      e += octave / scale
      scale += scale
    return nil if e.nan?() || e.infinite?()

    brightness = (~0.007 - e) * ~3.0
    brightness = ~0.0 if brightness < ~0.0
    if brightness > ~0.0
      # Expand the three HSV channels in place. This is the same scalar math as
      # raymarched_flower_hsv, without allocating an Array in the 130-step hot
      # loop for every positive contribution.
      hue = radius * ~2.0 + qy
      red_ramp = hue + ~1.0
      red_ramp -= Math.floor(red_ramp)
      red_ramp = (red_ramp * ~6.0 - ~3.0).abs - ~1.0
      red_ramp = ~0.0 if red_ramp < ~0.0
      red_ramp = ~1.0 if red_ramp > ~1.0
      green_ramp = hue + ~2.0 / ~3.0
      green_ramp -= Math.floor(green_ramp)
      green_ramp = (green_ramp * ~6.0 - ~3.0).abs - ~1.0
      green_ramp = ~0.0 if green_ramp < ~0.0
      green_ramp = ~1.0 if green_ramp > ~1.0
      blue_ramp = hue + ~1.0 / ~3.0
      blue_ramp -= Math.floor(blue_ramp)
      blue_ramp = (blue_ramp * ~6.0 - ~3.0).abs - ~1.0
      blue_ramp = ~0.0 if blue_ramp < ~0.0
      blue_ramp = ~1.0 if blue_ramp > ~1.0
      red += brightness * (hsv_floor + red_ramp * ~0.7)
      green += brightness * (hsv_floor + green_ramp * ~0.7)
      blue += brightness * (hsv_floor + blue_ramp * ~0.7)
    outer += 1

  [
    raymarched_flower_clamp(red),
    raymarched_flower_clamp(green),
    raymarched_flower_clamp(blue)
  ]


# Quantize a clamped RGB fragment to two bits per channel. Encoded black is
# omitted; the remaining codes 1..63 map directly to the palette array.
-> raymarched_flower_palette_index(rgb)
  red = Math.floor(rgb[0] * ~3.0 + ~0.5).to_i()
  green = Math.floor(rgb[1] * ~3.0 + ~0.5).to_i()
  blue = Math.floor(rgb[2] * ~3.0 + ~0.5).to_i()
  encoded = red * 16 + green * 4 + blue
  return nil if encoded == 0
  encoded - 1


-> raymarched_flower_frame(shader_time, grid_width)
  grid_height = grid_width * 3 / 4
  buckets = []
  palette_index = 0
  while palette_index < 63
    buckets.push([])
    palette_index += 1

  invalid_count = 0
  dark_count = 0
  lit_count = 0
  row = 0
  while row < grid_height
    column = 0
    while column < grid_width
      fragment_x = (column.to_f() + ~0.5) / grid_width.to_f()
      fragment_y = (row.to_f() + ~0.5) / grid_height.to_f()
      rgb = raymarched_flower_rgb(fragment_x, fragment_y, shader_time)
      if rgb == nil
        invalid_count += 1
      else
        bucket = raymarched_flower_palette_index(rgb)
        if bucket == nil
          dark_count += 1
        else
          world_x = fragment_x * ~400.0
          world_y = fragment_y * ~300.0
          buckets[bucket].push([world_x, world_y])
          lit_count += 1
      column += 1
    row += 1

  {
    :buckets => buckets,
    :invalid_count => invalid_count,
    :dark_count => dark_count,
    :lit_count => lit_count
  }


-> raymarched_flower_bucket_arrays_equal?(left, right)
  return false if left.size != right.size
  bucket_index = 0
  while bucket_index < left.size
    left_bucket = left[bucket_index]
    right_bucket = right[bucket_index]
    return false if left_bucket.size != right_bucket.size
    point_index = 0
    while point_index < left_bucket.size
      return false if left_bucket[point_index][0] != right_bucket[point_index][0]
      return false if left_bucket[point_index][1] != right_bucket[point_index][1]
      point_index += 1
    bucket_index += 1
  true


-> raymarched_flower_point_cloud(grid_width = 136, retained_frames = 13,
                                 fps = 15)
  grid_width = PlotData.positive_integer(
    grid_width, "raymarched flower grid width", 192)
  raise "raymarched flower grid width must be at least four" if grid_width < 4
  if grid_width % 4 != 0
    raise "raymarched flower grid width must preserve the four-to-three viewport"
  grid_height = grid_width * 3 / 4
  retained_frames = PlotData.positive_integer(
    retained_frames, "retained frame count", 1_000)
  raise "retained frame count must be at least two" if retained_frames < 2
  fps = PlotData.positive_integer(fps, "animation fps", 240)

  outer_steps = 130
  octave_count = 7
  frame_intervals = retained_frames - 1
  maximum_octave_evaluations = grid_width * grid_height * retained_frames
  maximum_octave_evaluations *= outer_steps * octave_count
  if maximum_octave_evaluations > 170_000_000
    raise "raymarched flower formula budget exceeds 170,000,000 octave evaluations"

  pi = ~3.141592653589793
  source_period = ~10.0 * pi / ~39.0
  shader_time_step = ~1.0 / fps.to_f()
  palette = raymarched_flower_palette()
  first_frame = raymarched_flower_frame(~0.0, grid_width)

  point_radius = ~180.0 / grid_width.to_f()
  children = []
  palette_index = 0
  while palette_index < palette.size
    identifier = "raymarched-flower-palette-" + palette_index.to_s()
    style = PlotStyle.new(
      nil, palette[palette_index], ~0.0, ~1.0, [], :circle)
    children.push(Plot.points(
      first_frame[:buckets][palette_index], point_radius,
      identifier, style,
      {
        :role => :quantized_fragment_samples,
        :palette_index => palette_index,
        :encoded_rgb_bin => palette_index + 1,
        :correspondence => :fragment_grid_cell
      }))
    palette_index += 1

  scene = Plot.scene(
    ~400.0, ~300.0, "#000000", nil,
    {
      :title => "Raymarched flower point cloud",
      :source_kind => :tweet_glsl_fragment_shader,
      :source_author => "Yohei Nishitsuji",
      :source_url =>
        "https://x.com/YoheiNishitsuji/status/2087060021528101362",
      :source_live_url =>
        "https://twigl.app?ol=true&ss=-OzjSA4EjdVkIfeW0tSh",
      :source_published_on => "2026-08-11",
      :source_media_viewport => [800, 600],
      :source_media_duration_seconds => ~0.8,
      :source_formula_sha256 =>
        "ff92ab3b1f7408940a45bb0fb45599561221482035188f2476b40eb6fb201e37",
      :source_license => :MIT,
      :source_profile => "https://x.com/YoheiNishitsuji",
      :adaptation => :downsampled_palette_quantized_point_lattice,
      :geometry_coordinate_system => :cartesian_y_up,
      :source_fragment_origin => :lower_left,
      :renderer_required_for_pixels => true
    })
  scene.add(Plot.group(
    children, [~0.0, ~0.0], [~1.0, ~1.0], ~0.0,
    "raymarched-flower", nil,
    {
      :palette_size => palette.size,
      :fragment_grid => [grid_width, grid_height],
      :fragment_sampling => :pixel_centers,
      :grid_scan_order => :bottom_to_top_left_to_right,
      :formula_outer_steps => outer_steps,
      :formula_octave_scales => [13, 26, 52, 104, 208, 416, 832],
      :formula_precision => :binary64,
      :source_precision => :glsl_highp_implementation_dependent,
      :glsl_uninitialized_variables => [:i, :e, :R, :q, :output_rgb],
      :source_webgl_initialization => :zero,
      :zero_initialization => :explicit_source_host_semantics,
      :constructor_argument_order => :explicit_left_to_right,
      :nonfinite_sample_policy => :omit_entire_fragment,
      :framebuffer_policy => :clamp_rgb_then_quantize,
      :palette_quantization => :two_bits_per_rgb_channel,
      :initial_invalid_fragments => first_frame[:invalid_count],
      :initial_dark_fragments => first_frame[:dark_count],
      :initial_lit_fragments => first_frame[:lit_count]
    }))

  duration = frame_intervals.to_f() / fps.to_f()
  if Math.ceil(duration * fps.to_f()).to_i() > frame_intervals
    duration -= duration * ~1.0e-15

  keyframe_sets = []
  palette_index = 0
  while palette_index < palette.size
    keyframe_sets.push([])
    palette_index += 1

  minimum_invalid = grid_width * grid_height
  maximum_invalid = 0
  frame_index = 0
  while frame_index < retained_frames
    frame = frame_index == 0 ? first_frame : raymarched_flower_frame(
      frame_index.to_f() * shader_time_step, grid_width)
    minimum_invalid = frame[:invalid_count] if frame[:invalid_count] < minimum_invalid
    maximum_invalid = frame[:invalid_count] if frame[:invalid_count] > maximum_invalid
    keyframe_time = frame_index.to_f() / fps.to_f()
    keyframe_time = duration if frame_index == frame_intervals
    palette_index = 0
    while palette_index < palette.size
      keyframe_sets[palette_index].push(Animation.keyframe(
        keyframe_time, frame[:buckets][palette_index]))
      palette_index += 1
    frame_index += 1

  timeline = Animation.timeline(
    scene, duration, fps, nil,
    {
      :sampling => :one_quantized_fragment_lattice_per_frame,
      :retained_frames => retained_frames,
      :total_frame_intervals => frame_intervals,
      :fragment_grid => [grid_width, grid_height],
      :palette_size => palette.size,
      :source_mathematical_period_seconds => source_period,
      :source_time_seconds_per_step => shader_time_step,
      :source_time_span_seconds => frame_intervals.to_f() * shader_time_step,
      :recommended_playback => :ping_pong_open_excerpt,
      :periodic_closure => false,
      :maximum_formula_octave_evaluations => maximum_octave_evaluations,
      :minimum_invalid_fragments => minimum_invalid,
      :maximum_invalid_fragments => maximum_invalid
    })

  palette_index = 0
  while palette_index < palette.size
    timeline.add(Animation.track(
      "raymarched-flower-palette-" + palette_index.to_s(),
      :points, keyframe_sets[palette_index], :step))
    palette_index += 1
  if timeline.frame_count != retained_frames
    raise "could not construct the exact raymarched flower frame schedule"
  timeline


# The native visual builder evaluates a 136x102 fragment lattice across nearly
# one source period. This is four times the 68x51 sample count and about
# thirty-two times the original 24x18 default. The executable documentation
# path stays intentionally small enough for the self-hosted interpreter.
timeline = raymarched_flower_point_cloud(4, 2, 60)
group = timeline.scene.node("raymarched-flower")
tracks = timeline.tracks

structure_ok = group.children.size == 63 && tracks.size == 63
raise "raymarched flower palette structure changed" if !structure_ok
interpolation_ok = true
track_index = 0
while track_index < tracks.size
  interpolation_ok = false if tracks[track_index].interpolation != :step
  track_index += 1
raise "raymarched flower interpolation changed" if !interpolation_ok

# Pin two finite formula anchors and the derived 10*pi/39 period.
period = ~10.0 * ~3.141592653589793 / ~39.0
anchor_x = ~7.5 / ~16.0
anchor_y = ~10.5 / ~16.0
anchor_a = raymarched_flower_rgb(anchor_x, anchor_y, ~0.0)
anchor_next = raymarched_flower_rgb(anchor_x, anchor_y, ~1.0 / ~60.0)
period_a = raymarched_flower_rgb(anchor_x, anchor_y, period)
half_a = raymarched_flower_rgb(anchor_x, anchor_y, period / ~2.0)
invalid_corner = raymarched_flower_rgb(~0.5 / ~16.0, ~0.5 / ~16.0, ~0.0)
raise "raymarched flower formula anchor became invalid" if anchor_a == nil
raise "raymarched flower formula anchor became invalid" if anchor_next == nil
raise "raymarched flower period anchor became invalid" if period_a == nil
raise "raymarched flower half-period anchor became invalid" if half_a == nil
raise "raymarched flower invalid corner policy changed" if invalid_corner != nil

anchor_tolerance = ~1.0e-9
anchors = (anchor_a[0] - ~1.0).abs < anchor_tolerance
anchors = anchors && (anchor_a[1] - ~1.0).abs < anchor_tolerance
anchors = anchors && (anchor_a[2] - ~0.6335579504016398).abs < anchor_tolerance
anchors = anchors && raymarched_flower_palette_index(anchor_a) == 61
anchors = anchors && raymarched_flower_palette_index(anchor_next) == 60

hsv_zero = raymarched_flower_hsv(~0.0, ~0.7, ~1.0)
hsv_wrap = raymarched_flower_hsv(~1.0, ~0.7, ~1.0)
anchors = anchors && (hsv_zero[0] - ~1.0).abs < anchor_tolerance
anchors = anchors && (hsv_zero[1] - ~0.3).abs < anchor_tolerance
anchors = anchors && (hsv_zero[2] - ~0.3).abs < anchor_tolerance
channel = 0
while channel < 3
  anchors = false if (hsv_zero[channel] - hsv_wrap[channel]).abs > anchor_tolerance
  channel += 1
raise "raymarched flower formula anchors changed" if !anchors

period_closed = true
half_moved = false
channel = 0
while channel < 3
  period_closed = false if (anchor_a[channel] - period_a[channel]).abs > anchor_tolerance
  half_moved = true if (anchor_a[channel] - half_a[channel]).abs > ~1.0e-6
  channel += 1
raise "raymarched flower mathematical period changed" if !period_closed
raise "raymarched flower half-period unexpectedly closed" if !half_moved
anchor_palette = raymarched_flower_palette_index(anchor_a)
next_palette = raymarched_flower_palette_index(anchor_next)
raise "raymarched flower anchor stopped moving" if anchor_palette == next_palette

first_retained_buckets = []
next_retained_buckets = []
track_index = 0
while track_index < tracks.size
  retained_keyframes = tracks[track_index].keyframes
  first_retained_buckets.push(retained_keyframes[0].value)
  next_retained_buckets.push(retained_keyframes[1].value)
  track_index += 1
motion = !raymarched_flower_bucket_arrays_equal?(
  first_retained_buckets, next_retained_buckets)
raise "raymarched flower retained field stopped moving" if !motion

budget_guard = false
begin
  raymarched_flower_point_cloud(96, 1_000, 60)
rescue error
  budget_guard = error.to_s().include?("formula budget")
raise "raymarched flower formula budget guard changed" if !budget_guard

<< "frames: [timeline.frame_count]"
<< "fps: [timeline.fps]"
<< "fragment grid: [group.metadata[:fragment_grid][0]]x[group.metadata[:fragment_grid][1]]"
<< "palette layers: [group.children.size]"
<< "animated tracks: [tracks.size]"
<< "track interpolation: [tracks[0].interpolation]"
<< "initial lit fragments: [group.metadata[:initial_lit_fragments]]"
<< "initial invalid fragments: [group.metadata[:initial_invalid_fragments]]"
<< "color-field motion: [motion]"
<< "formula anchors: ok"
<< "source mathematical period: ok"
<< "budget guard: [budget_guard]"

if ARGV.include?("--window") || ARGV.include?("--window-smoke")
  window_timeline = ARGV.include?("--window-smoke") ? raymarched_flower_point_cloud(16, 3, 60) : raymarched_flower_point_cloud()
  maximum = ARGV.include?("--window-smoke") ? 3 : nil
  AnimationWindowPreview.show(
    window_timeline, "Tungsten — Raymarched flower", :ping_pong, maximum)

## expect stdout
## frames: 2
## fps: 60
## fragment grid: 4x3
## palette layers: 63
## animated tracks: 63
## track interpolation: step
## initial lit fragments: 3
## initial invalid fragments: 6
## color-field motion: true
## formula anchors: ok
## source mathematical period: ok
## budget guard: true

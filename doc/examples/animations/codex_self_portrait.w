# Codex, drawn as a deterministic machine self-portrait.
#
# The face is deliberately not an imitation of a human photograph. It is a
# pointillist "machine self": a calm mask made from retained samples, a small
# luminous core, blinking eyes, orbiting thoughts, and a point-rendered CODEX
# signature. `core/animation` owns the exact looping timeline; the optional
# point preview consumes that same portable data for pixels or a native window.

use core/animation/point_preview


-> portrait_point(x, y, label = "self-portrait point")
  PlotData.point([x, y], label)


-> portrait_style(color, opacity = ~1.0)
  PlotStyle.new(nil, color, ~0.0, opacity, [], :circle)


-> portrait_append_segment(points, x0, y0, x1, y1, samples)
  index = 0
  while index < samples
    progress = samples == 1 ? ~0.0 : index.to_f() / (samples - 1).to_f()
    points.push(portrait_point(
      x0 + (x1 - x0) * progress,
      y0 + (y1 - y0) * progress,
      "circuit segment point"))
    index += 1
  points


-> portrait_background_stars(bright = false)
  points = []
  index = 0
  while index < 180
    x = ((index * 73 + 41) % 503 + 4).to_f()
    y = ((index * 151 + 29) % 503 + 4).to_f()
    is_bright = (index * 17 + 5) % 13 < 3
    if is_bright == bright
      points.push(portrait_point(x, y, "deterministic background star"))
    index += 1
  points


-> portrait_face_points(count, inset, x_shift, y_shift)
  points = []
  golden_angle = ~3.141592653589793 * (~3.0 - Math.sqrt(~5.0))
  index = 0
  while index < count
    radius = Math.sqrt((index.to_f() + ~0.5) / count.to_f())
    angle = index.to_f() * golden_angle
    unit_x = radius * Math.cos(angle)
    unit_y = radius * Math.sin(angle)
    # The jaw narrows toward negative y; a slight fourth-harmonic ripple keeps
    # the silhouette organic while remaining an exact deterministic sample.
    jaw = ~0.82 + ~0.18 * ((unit_y + ~1.0) / ~2.0)
    contour = ~1.0 + ~0.018 * Math.cos(~4.0 * angle)
    x = ~256.0 + x_shift + ~98.0 * inset * jaw * contour * unit_x
    y = ~270.0 + y_shift + ~120.0 * inset * unit_y
    points.push(portrait_point(x, y, "Vogel mask sample"))
    index += 1
  points


-> portrait_face_contour
  points = []
  samples = 288
  index = 0
  while index < samples
    angle = ~2.0 * ~3.141592653589793 * index.to_f() / samples.to_f()
    sine = Math.sin(angle)
    jaw = ~0.82 + ~0.18 * ((sine + ~1.0) / ~2.0)
    x = ~256.0 + ~99.0 * jaw * Math.cos(angle)
    y = ~270.0 + ~121.0 * sine
    points.push(portrait_point(x, y, "mask contour sample"))
    index += 1
  points


-> portrait_circuit_points
  points = []

  # Temple traces.
  portrait_append_segment(points, ~160.0, ~292.0, ~137.0, ~292.0, 18)
  portrait_append_segment(points, ~137.0, ~292.0, ~123.0, ~306.0, 13)
  portrait_append_segment(points, ~352.0, ~292.0, ~375.0, ~292.0, 18)
  portrait_append_segment(points, ~375.0, ~292.0, ~389.0, ~306.0, 13)
  portrait_append_segment(points, ~169.0, ~246.0, ~139.0, ~234.0, 20)
  portrait_append_segment(points, ~343.0, ~246.0, ~373.0, ~234.0, 20)

  # A collar/terminal pedestal below the face.
  portrait_append_segment(points, ~220.0, ~158.0, ~220.0, ~132.0, 18)
  portrait_append_segment(points, ~292.0, ~158.0, ~292.0, ~132.0, 18)
  portrait_append_segment(points, ~220.0, ~132.0, ~190.0, ~112.0, 22)
  portrait_append_segment(points, ~292.0, ~132.0, ~322.0, ~112.0, 22)
  portrait_append_segment(points, ~190.0, ~112.0, ~135.0, ~104.0, 28)
  portrait_append_segment(points, ~322.0, ~112.0, ~377.0, ~104.0, 28)

  # Small contact pads make the circuit ends read as intentional terminals.
  terminals = [
    [~122.0, ~307.0], [~390.0, ~307.0],
    [~138.0, ~234.0], [~374.0, ~234.0],
    [~135.0, ~104.0], [~377.0, ~104.0]
  ]
  terminals.each -> (terminal)
    ring_index = 0
    while ring_index < 12
      angle = ~2.0 * ~3.141592653589793 * ring_index.to_f() / ~12.0
      points.push(portrait_point(
        terminal[0] + ~3.0 * Math.cos(angle),
        terminal[1] + ~3.0 * Math.sin(angle),
        "circuit contact pad"))
      ring_index += 1
  points


-> portrait_feature_points
  points = []

  # Brows.
  side = -1
  while side <= 1
    index = 0
    while index < 42
      progress = index.to_f() / ~41.0
      x = ~256.0 + side.to_f() * (~24.0 + ~42.0 * progress)
      y = ~304.0 + ~7.0 * Math.sin(progress * ~3.141592653589793)
      points.push(portrait_point(x, y, "brow point"))
      index += 1
    side += 2

  # Nose bridge and a tiny chevron at its base.
  portrait_append_segment(points, ~256.0, ~279.0, ~252.0, ~239.0, 34)
  portrait_append_segment(points, ~252.0, ~239.0, ~263.0, ~235.0, 13)
  portrait_append_segment(points, ~263.0, ~235.0, ~268.0, ~240.0, 8)

  # Cheek data marks: one side reads in, the other reads out.
  mark = 0
  while mark < 3
    y = ~235.0 - mark.to_f() * ~13.0
    portrait_append_segment(points, ~182.0, y, ~201.0, y, 13)
    portrait_append_segment(points, ~311.0, y, ~330.0, y, 13)
    mark += 1
  points


-> portrait_halo_points(phase, violet = false)
  points = []
  orbit_count = violet ? 168 : 216
  per_orbit = orbit_count / 3
  orbit = 0
  while orbit < 3
    index = 0
    while index < per_orbit
      direction = orbit % 2 == 0 ? ~1.0 : ~-1.0
      angle = ~2.0 * ~3.141592653589793 * index.to_f() / per_orbit.to_f()
      angle += direction * phase * ~2.0 * ~3.141592653589793
      angle += violet ? ~0.31 : ~0.0
      base_radius_x = violet ? ~151.0 : ~145.0
      base_radius_y = violet ? ~112.0 : ~106.0
      radius_x = base_radius_x + orbit.to_f() * ~21.0
      radius_y = base_radius_y + orbit.to_f() * ~24.0
      ripple = ~3.5 * Math.sin(~5.0 * angle + phase * ~2.0 * ~3.141592653589793)
      x = ~256.0 + (radius_x + ripple) * Math.cos(angle)
      y = ~278.0 + (radius_y + ripple) * Math.sin(angle)
      points.push(portrait_point(x, y, "orbiting thought halo"))
      index += 1
    orbit += 1
  points


-> portrait_spark_points(phase)
  points = []
  spark = 0
  while spark < 6
    trail = 0
    while trail < 14
      angle = phase * ~2.0 * ~3.141592653589793
      angle += spark.to_f() * ~2.0 * ~3.141592653589793 / ~6.0
      angle -= trail.to_f() * ~0.018
      radius_x = ~194.0 - trail.to_f() * ~0.8
      radius_y = ~158.0 - trail.to_f() * ~0.55
      points.push(portrait_point(
        ~256.0 + radius_x * Math.cos(angle),
        ~278.0 + radius_y * Math.sin(angle),
        "thought spark trail"))
      trail += 1
    spark += 1
  points


-> portrait_blink_open(phase)
  delta_one = (phase - ~0.27) / ~0.034
  delta_two = (phase - ~0.73) / ~0.043
  blink_one = Math.exp(~-1.0 * delta_one * delta_one)
  blink_two = Math.exp(~-1.0 * delta_two * delta_two)
  blink = blink_one > blink_two ? blink_one : blink_two
  ~1.0 - ~0.94 * blink


-> portrait_eye_points(phase)
  points = []
  openness = portrait_blink_open(phase)
  side = -1
  while side <= 1
    center_x = ~256.0 + side.to_f() * ~43.0
    index = 0
    while index < 64
      angle = ~2.0 * ~3.141592653589793 * index.to_f() / ~64.0
      points.push(portrait_point(
        center_x + ~25.0 * Math.cos(angle),
        ~278.0 + ~8.5 * openness * Math.sin(angle),
        "blinking eye contour"))
      index += 1

    # A sparse scan line gives the eye a terminal-display character.
    index = 0
    while index < 25
      x = center_x - ~18.0 + index.to_f() * ~1.5
      y = ~278.0 + ~1.2 * openness * Math.sin(index.to_f() * ~0.8)
      points.push(portrait_point(x, y, "eye scan line"))
      index += 1
    side += 2
  points


-> portrait_pupil_points(phase)
  points = []
  openness = portrait_blink_open(phase)
  gaze_x = ~4.5 * Math.sin(phase * ~2.0 * ~3.141592653589793)
  gaze_y = ~1.5 * Math.cos(phase * ~4.0 * ~3.141592653589793)
  side = -1
  while side <= 1
    center_x = ~256.0 + side.to_f() * ~43.0 + gaze_x
    index = 0
    while index < 28
      angle = ~2.0 * ~3.141592653589793 * index.to_f() / ~28.0
      radius = index % 2 == 0 ? ~3.5 : ~2.0
      points.push(portrait_point(
        center_x + radius * Math.cos(angle),
        ~278.0 + gaze_y + radius * openness * Math.sin(angle),
        "luminous pupil"))
      index += 1
    side += 2
  points


-> portrait_core_points(phase)
  points = []
  pulse = ~0.88 + ~0.12 * Math.sin(
    phase * ~2.0 * ~3.141592653589793 - ~3.141592653589793 / ~2.0)

  ring = 0
  while ring < 3
    samples = 28 + ring * 8
    index = 0
    while index < samples
      angle = ~2.0 * ~3.141592653589793 * index.to_f() / samples.to_f()
      direction = ring % 2 == 0 ? ~1.0 : ~-1.0
      angle += phase * ~2.0 * ~3.141592653589793 * direction
      radius_x = (~5.0 + ring.to_f() * ~5.0) * pulse
      radius_y = (~7.0 + ring.to_f() * ~6.0) * pulse
      points.push(portrait_point(
        ~256.0 + radius_x * Math.cos(angle),
        ~340.0 + radius_y * Math.sin(angle),
        "pulsing codex core"))
      index += 1
    ring += 1

  ray = 0
  while ray < 8
    angle = ray.to_f() * ~3.141592653589793 / ~4.0
    step = 1
    while step <= 8
      radius = (~17.0 + step.to_f() * ~1.8) * pulse
      points.push(portrait_point(
        ~256.0 + radius * Math.cos(angle),
        ~340.0 + radius * Math.sin(angle),
        "codex core ray"))
      step += 1
    ray += 1
  points


-> portrait_mouth_points(phase)
  points = []
  expression = Math.sin(phase * ~2.0 * ~3.141592653589793)
  index = 0
  while index < 72
    u = ~-1.0 + ~2.0 * index.to_f() / ~71.0
    x = ~256.0 + ~35.0 * u
    y = ~196.0 + ~7.0 * u * u
    y += ~1.4 * expression * (~1.0 - u * u)
    points.push(portrait_point(x, y, "quiet waveform smile"))
    index += 1
  points


-> portrait_signature_points
  glyphs = [
    ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    ["10001", "10001", "01010", "00100", "01010", "10001", "10001"]
  ]
  points = []
  glyph_index = 0
  while glyph_index < glyphs.size
    rows = glyphs[glyph_index]
    row = 0
    while row < rows.size
      column = 0
      while column < rows[row].size
        if rows[row][column] == "1"
          x = ~196.0 + (glyph_index * 6 + column).to_f() * ~4.0
          y = ~42.0 + (6 - row).to_f() * ~4.0
          points.push(portrait_point(x, y, "CODEX dot-matrix signature"))
        column += 1
      row += 1
    glyph_index += 1
  points


-> portrait_cursor_points
  points = []
  index = 0
  while index < 6
    points.push(portrait_point(
      ~318.0 + index.to_f() * ~3.0, ~40.0,
      "signature cursor"))
    index += 1
  points


-> portrait_points_equal?(left, right, epsilon = ~0.0)
  return false if left.size != right.size
  index = 0
  while index < left.size
    return false if (left[index][0] - right[index][0]).abs > epsilon
    return false if (left[index][1] - right[index][1]).abs > epsilon
    index += 1
  true


-> portrait_exact_duration(frame_intervals, fps)
  duration = frame_intervals.to_f() / fps.to_f()
  if Math.ceil(duration * fps.to_f()).to_i() > frame_intervals
    duration -= duration * ~1.0e-15
  duration


-> codex_self_portrait(retained_frames = 73, fps = 24)
  retained_frames = PlotData.positive_integer(
    retained_frames, "self-portrait retained frame count", 241)
  fps = PlotData.positive_integer(fps, "self-portrait fps", 120)
  if retained_frames < 3
    raise "self-portrait needs at least three retained frames"

  frame_intervals = retained_frames - 1
  duration = portrait_exact_duration(frame_intervals, fps)
  first_halo_cyan = portrait_halo_points(~0.0, false)
  first_halo_violet = portrait_halo_points(~0.0, true)
  first_sparks = portrait_spark_points(~0.0)
  first_eyes = portrait_eye_points(~0.0)
  first_pupils = portrait_pupil_points(~0.0)
  first_core = portrait_core_points(~0.0)
  first_mouth = portrait_mouth_points(~0.0)

  scene = Plot.scene(
    ~512.0, ~512.0, "#050814", nil,
    {
      :title => "Codex machine self-portrait",
      :artist => :codex,
      :medium => :deterministic_retained_points,
      :composition => :calm_machine_self,
      :coordinate_system => :cartesian_y_up,
      :renderer_required_for_pixels => true
    })

  # Back to front: sky, thought orbits, mask, features, signature.
  scene.add(Plot.points(
    portrait_background_stars(false), ~0.5, "stars-dim",
    portrait_style("#16213e", ~0.80), {:role => :background}))
  scene.add(Plot.points(
    portrait_background_stars(true), ~0.8, "stars-bright",
    portrait_style("#5167a6", ~0.85), {:role => :background}))
  scene.add(Plot.points(
    first_halo_violet, ~0.8, "halo-violet",
    portrait_style("#8b5cf6", ~0.34), {:role => :thought_orbit}))
  scene.add(Plot.points(
    first_halo_cyan, ~0.9, "halo-cyan",
    portrait_style("#22d3ee", ~0.42), {:role => :thought_orbit}))
  scene.add(Plot.points(
    first_sparks, ~1.4, "thought-sparks",
    portrait_style("#ffd166", ~0.72), {:role => :moving_thoughts}))

  scene.add(Plot.points(
    portrait_face_points(3_200, ~1.0, ~0.0, ~0.0), ~1.35,
    "face-shadow", portrait_style("#17355f", ~0.55),
    {:sampling => :vogel_disk, :role => :mask_shadow}))
  scene.add(Plot.points(
    portrait_face_points(1_650, ~0.91, ~-5.0, ~5.0), ~1.1,
    "face-mid", portrait_style("#2878a7", ~0.48),
    {:sampling => :vogel_disk, :role => :mask_midtone}))
  scene.add(Plot.points(
    portrait_face_points(720, ~0.74, ~-14.0, ~18.0), ~0.9,
    "face-light", portrait_style("#67e8f9", ~0.28),
    {:sampling => :vogel_disk, :role => :mask_light}))
  scene.add(Plot.points(
    portrait_face_contour(), ~1.0, "face-contour",
    portrait_style("#38bdf8", ~0.72), {:role => :mask_boundary}))

  scene.add(Plot.points(
    portrait_circuit_points(), ~1.0, "circuits",
    portrait_style("#6366f1", ~0.72), {:role => :circuitry}))
  scene.add(Plot.points(
    portrait_feature_points(), ~1.05, "features",
    portrait_style("#a5b4fc", ~0.70), {:role => :facial_geometry}))
  scene.add(Plot.points(
    first_eyes, ~1.55, "eyes",
    portrait_style("#5eead4", ~0.88), {:role => :display_eyes}))
  scene.add(Plot.points(
    first_pupils, ~1.8, "pupils",
    portrait_style("#f8fafc", ~0.96), {:role => :attention}))
  scene.add(Plot.points(
    first_core, ~1.15, "codex-core",
    portrait_style("#fbbf24", ~0.82), {:role => :identity_core}))
  scene.add(Plot.points(
    first_mouth, ~1.15, "mouth",
    portrait_style("#7dd3fc", ~0.78), {:role => :quiet_waveform}))

  signature = portrait_signature_points()
  scene.add(Plot.points(
    signature, ~1.45, "signature",
    portrait_style("#8be9fd", ~0.90),
    {:role => :signature, :text => "CODEX"}))
  scene.add(Plot.points(
    portrait_cursor_points(), ~1.25, "cursor",
    portrait_style("#fbbf24", ~0.88), {:role => :terminal_cursor}))

  halo_cyan_keyframes = []
  halo_violet_keyframes = []
  spark_keyframes = []
  eye_keyframes = []
  pupil_keyframes = []
  core_keyframes = []
  mouth_keyframes = []
  cursor_keyframes = []

  frame_index = 0
  while frame_index < retained_frames
    phase_index = frame_index % frame_intervals
    phase = phase_index.to_f() / frame_intervals.to_f()
    keyframe_time = frame_index == frame_intervals ? duration : frame_index.to_f() / fps.to_f()

    halo_cyan = phase_index == 0 ? first_halo_cyan : portrait_halo_points(phase, false)
    halo_violet = phase_index == 0 ? first_halo_violet : portrait_halo_points(phase, true)
    sparks = phase_index == 0 ? first_sparks : portrait_spark_points(phase)
    eyes = phase_index == 0 ? first_eyes : portrait_eye_points(phase)
    pupils = phase_index == 0 ? first_pupils : portrait_pupil_points(phase)
    core = phase_index == 0 ? first_core : portrait_core_points(phase)
    mouth = phase_index == 0 ? first_mouth : portrait_mouth_points(phase)

    halo_cyan_keyframes.push(Animation.keyframe(keyframe_time, halo_cyan))
    halo_violet_keyframes.push(Animation.keyframe(keyframe_time, halo_violet))
    spark_keyframes.push(Animation.keyframe(keyframe_time, sparks))
    eye_keyframes.push(Animation.keyframe(keyframe_time, eyes))
    pupil_keyframes.push(Animation.keyframe(keyframe_time, pupils))
    core_keyframes.push(Animation.keyframe(keyframe_time, core))
    mouth_keyframes.push(Animation.keyframe(keyframe_time, mouth))
    cursor_keyframes.push(Animation.keyframe(
      keyframe_time, phase < ~0.50 ? ~1.0 : ~0.10))
    frame_index += 1

  timeline = Animation.timeline(
    scene, duration, fps, nil,
    {
      :portrait_subject => :codex,
      :loop => :exact_closed_loop,
      :sampling => :one_keyframe_per_frame,
      :nominal_duration_seconds => frame_intervals.to_f() / fps.to_f(),
      :retained_frames => retained_frames,
      :frame_intervals => frame_intervals,
      :animated_point_layers => 7,
      :animated_opacity_layers => 1,
      :soundtrack => :none,
      :reason => :visual_rhythm_is_the_voice
    })
  timeline.add(Animation.track(
    "halo-violet", :points, halo_violet_keyframes, :step))
  timeline.add(Animation.track(
    "halo-cyan", :points, halo_cyan_keyframes, :step))
  timeline.add(Animation.track(
    "thought-sparks", :points, spark_keyframes, :step))
  timeline.add(Animation.track("eyes", :points, eye_keyframes, :step))
  timeline.add(Animation.track("pupils", :points, pupil_keyframes, :step))
  timeline.add(Animation.track("codex-core", :points, core_keyframes, :step))
  timeline.add(Animation.track("mouth", :points, mouth_keyframes, :step))
  timeline.add(Animation.track("cursor", :opacity, cursor_keyframes, :step))

  if timeline.frame_count != retained_frames
    raise "could not construct the exact self-portrait frame schedule"
  timeline


-> portrait_track_closed?(track)
  first = track.keyframes[0].value
  last = track.keyframes[track.keyframes.size - 1].value
  if track.property == "points"
    return portrait_points_equal?(first, last)
  first == last


-> portrait_all_tracks_closed?(timeline)
  closed = true
  timeline.tracks.each -> (track)
    closed = false if !portrait_track_closed?(track)
  closed


-> portrait_frame_bytes(rendered)
  width = rendered[:width]
  height = rendered[:height]
  pixels = rendered[:pixels]
  header = "P6\n[width] [height]\n255\n"
  header_bytes = header.bytes
  output = ByteArray.new(header_bytes.size + pixels.size * 3)

  index = 0
  while index < header_bytes.size
    output[index] = header_bytes[index]
    index += 1

  pixel_index = 0
  offset = header_bytes.size
  while pixel_index < pixels.size
    pixel = pixels[pixel_index]
    output[offset] = pixel & 255
    output[offset + 1] = (pixel >> 8) & 255
    output[offset + 2] = (pixel >> 16) & 255
    offset += 3
    pixel_index += 1
  output


-> portrait_padded_index(index)
  value = index.to_s()
  value = "0" + value while value.size < 3
  value


-> portrait_export_ppm(timeline, output_dir)
  preview = AnimationPointPreview.new(timeline)
  frame_index = 0
  while frame_index < timeline.frame_count
    rendered = preview.render(frame_index)
    path = output_dir + "/codex-self-portrait-frame-"
    path += portrait_padded_index(frame_index) + ".ppm"
    written = write_file_bytes(path, portrait_frame_bytes(rendered))
    raise "could not write self-portrait frame: " + path if !written
    frame_index += 1
  output_dir


# Keep ordinary documentation execution quick while still crossing the first
# blink at phase 0.25. `--window` and `--export` build the full 73-frame loop.
timeline = codex_self_portrait(9, 24)
scene = timeline.scene
tracks = timeline.tracks
closed_loop = portrait_all_tracks_closed?(timeline)
raise "self-portrait loop is not exactly closed" if !closed_loop

eyes = tracks[3].keyframes
open_eye = eyes[0].value[16]
blink_eye = eyes[2].value[16]
blink = (open_eye[1] - ~278.0).abs > (blink_eye[1] - ~278.0).abs
raise "self-portrait blink changed" if !blink

spark_start = tracks[2].keyframes[0].value[0]
spark_motion = tracks[2].keyframes[1].value[0]
motion = spark_start[0] != spark_motion[0] || spark_start[1] != spark_motion[1]
raise "self-portrait thought sparks did not move" if !motion

preview = AnimationPointPreview.new(timeline)
raise "self-portrait preview width changed" if preview.width != 512
raise "self-portrait preview height changed" if preview.height != 512
signature_point_count = scene.node("signature").points.size

<< "frames: [timeline.frame_count]"
<< "fps: [timeline.fps]"
<< "scene layers: [scene.nodes.size]"
<< "animated tracks: [tracks.size]"
<< "signature points: [signature_point_count]"
<< "exact closed loop: [closed_loop]"
<< "blink: [blink]"
<< "thought motion: [motion]"
<< "point preview: accepted"

if ARGV.include?("--export")
  # The directory must already exist; keeping directory mutation outside this
  # example lets headless interpreters use the builtin binary writer without
  # loading the broader filesystem facade.
  output_dir = ARGV.size > 1 ? ARGV[1] : "/tmp"
  exported = portrait_export_ppm(codex_self_portrait(), output_dir)
  << "exported: [exported]"

if ARGV.include?("--window") || ARGV.include?("--window-smoke")
  window_timeline = ARGV.include?("--window-smoke") ? timeline : codex_self_portrait()
  maximum = ARGV.include?("--window-smoke") ? 3 : nil
  AnimationWindowPreview.show(
    window_timeline, "Tungsten — Codex self-portrait", :closed_loop, maximum)

## expect stdout
## frames: 9
## fps: 24
## scene layers: 17
## animated tracks: 8
## signature points: 78
## exact closed loop: true
## blink: true
## thought motion: true
## point preview: accepted

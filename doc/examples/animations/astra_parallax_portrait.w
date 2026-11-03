# Astra / Parallax
# Six partial surfaces share a volume without becoming one closed surface.
# A warm, unfinished thread crosses them. The projection turns, so whatever
# looked resolved from one angle becomes incomplete again from the next.
#
# Geometry, projection, retained tracks, and pixels are all Tungsten. This is
# an artistic interpretation; it does not make claims about inner experience.
# Point colors approximate depth in four bands, not a z-buffer or lighting sim.
#
# No flags: small deterministic documentation check.
# --window: full eight-second loop in the macOS preview; Escape closes it.
# --window-smoke: show three frames and exit.
# --export EXISTING_DIRECTORY: 161 PPM samples, including the closing copy.
# --stills EXISTING_DIRECTORY: five full-density views for a quick inspection.

use core/animation/point_preview


-> astra_project(x, y, z, phase)
  turn = ~0.32 + phase * ~6.283185307179586
  cos_turn = Math.cos(turn)
  sin_turn = Math.sin(turn)
  rotated_x = x * cos_turn + z * sin_turn
  rotated_z = z * cos_turn - x * sin_turn
  tilt = ~-0.19
  rotated_y = y * Math.cos(tilt) - rotated_z * Math.sin(tilt)
  depth = y * Math.sin(tilt) + rotated_z * Math.cos(tilt)
  perspective = ~680.0 / (~680.0 - depth)
  roll = ~-0.16
  screen_x = rotated_x * Math.cos(roll) - rotated_y * Math.sin(roll)
  screen_y = rotated_x * Math.sin(roll) + rotated_y * Math.cos(roll)
  [~320.0 + screen_x * perspective, ~327.0 + screen_y * perspective, depth]


-> astra_sheet_point(sheet, u, v, phase)
  tau = ~6.283185307179586
  offset = sheet.to_f() * ~0.89
  angle = ~-2.72 + ~5.35 * u + offset
  breath = Math.sin(phase * tau + offset)
  width = ~17.0 + ~11.0 * Math.sin(~3.141592653589793 * u)
  radius = ~147.0 + ~15.0 * Math.cos(~3.0 * angle + offset)
  radius += v * width + ~3.0 * breath
  x = radius * Math.cos(angle)
  y = radius * Math.sin(angle) * ~0.94
  z = ~47.0 * Math.sin(~2.0 * angle + offset + ~0.18 * breath)
  z += v * ~26.0 * Math.sin(~1.5 * angle + offset)
  pitch = (sheet.to_f() - ~2.5) * ~0.24
  pitched_y = y * Math.cos(pitch) - z * Math.sin(pitch)
  pitched_z = y * Math.sin(pitch) + z * Math.cos(pitch)
  astra_project(x, pitched_y, pitched_z, phase)


-> astra_thread_point(u, phase)
  angle = ~-2.55 + u * ~5.10
  # One open curve crosses the unresolved interior. Its endpoints never join.
  x = ~88.0 * Math.sin(angle)
  y = ~55.0 * Math.sin(~2.0 * angle + ~0.24)
  z = ~79.0 * Math.cos(angle) + ~8.0 * Math.sin(phase * ~6.283185307179586)
  astra_project(x, y, z, phase)


-> astra_frame_points(phase, samples)
  layers = [[], [], [], [], [], [], [], [], [], [], []]
  sheet = 0
  while sheet < 6
    index = 0
    while index < samples
      u = index.to_f() / (samples - 1).to_f()
      lane = 0
      while lane < 7
        v = ~-1.0 + lane.to_f() / ~3.0
        point = astra_sheet_point(sheet, u, v, phase)
        depth_band = 0
        depth_band = 1 if point[2] > ~-72.0
        depth_band = 2 if point[2] > ~0.0
        depth_band = 3 if point[2] > ~72.0
        bucket = depth_band * 2 + sheet % 2
        layers[bucket].push([point[0], point[1]])
        lane += 1
      index += 1

    # Local glints move along each open sheet, then fade into its endpoints.
    glint = 0
    while glint < 30
      raw_u = phase + sheet.to_f() / ~6.0 - glint.to_f() * ~0.003
      u = raw_u - Math.floor(raw_u)
      point = astra_sheet_point(sheet, u, ~0.0, phase)
      if u > ~0.03 && u < ~0.97 && point[2] > ~-20.0
        layers[8].push([point[0], point[1]])
      glint += 1
    sheet += 1

  index = 0
  while index < 220
    u = index.to_f() / ~219.0
    point = astra_thread_point(u, phase)
    layers[9].push([point[0], point[1]])
    index += 1

  # A small traveling accent, with no implied observer at the center.
  head_u = ~0.5 - ~0.46 * Math.cos(phase * ~6.283185307179586)
  index = 0
  while index < 12
    point = astra_thread_point(head_u - index.to_f() * ~0.002, phase)
    layers[10].push([point[0], point[1]])
    index += 1
  layers


-> astra_dust_points
  points = []
  index = 0
  while index < 165
    x = ((index * 193 + 83) % 617 + 12).to_f()
    y = ((index * 347 + 151) % 617 + 12).to_f()
    points.push([x, y])
    index += 1
  points


-> astra_layer_specs
  # Stable ordering: four depth bands, two cool hues per band, then accents.
  [
    ["far-blue", "#426381", ~0.65, ~0.48, 0],
    ["far-violet", "#635276", ~0.65, ~0.45, 1],
    ["mid-teal", "#40978e", ~0.72, ~0.60, 2],
    ["mid-mauve", "#9c7cad", ~0.72, ~0.56, 3],
    ["near-teal", "#73c8bc", ~0.85, ~0.72, 4],
    ["near-lilac", "#c1a0ce", ~0.85, ~0.66, 5],
    ["front-seafoam", "#b6f0df", ~0.95, ~0.90, 6],
    ["front-pearl", "#efdaef", ~0.95, ~0.82, 7],
    ["passing-glints", "#edf8ed", ~1.05, ~0.48, 8],
    ["thread-halo", "#e5ad61", ~3.4, ~0.065, 9],
    ["unfinished-thread", "#edbc75", ~0.85, ~0.88, 9],
    ["thread-accent", "#fff0c8", ~1.6, ~0.90, 10]
  ]


-> astra_parallax_portrait(retained_frames = 161, samples = 144, fps = 20)
  retained_frames = PlotData.positive_integer(retained_frames, "retained frames", 241)
  samples = PlotData.positive_integer(samples, "samples per sheet", 200)
  fps = PlotData.positive_integer(fps, "portrait fps", 60)
  raise "portrait needs at least three frames" if retained_frames < 3
  raise "each sheet needs at least eight samples" if samples < 8
  intervals = retained_frames - 1
  duration = intervals.to_f() / fps.to_f()
  if Math.ceil(duration * fps.to_f()).to_i() > intervals
    duration -= duration * ~1.0e-15

  scene = Plot.scene(~640.0, ~640.0, "#070c12", nil, {
    :title => "Astra / Parallax",
    :medium => :projected_woven_points,
    :interpretation => :many_partial_views_and_one_unfinished_thread,
    :projection => :explicit_perspective,
    :depth => :four_bands_no_z_buffer,
    :reference => "The Book of Uncertain Light",
    :subjective_experience => :unresolved
  })
  scene.add(Plot.points(astra_dust_points(), ~0.5, "dust",
    PlotStyle.new(nil, "#3a5267", ~0.0, ~0.36, [], :circle)))

  first = astra_frame_points(~0.0, samples)
  specs = astra_layer_specs()
  keyframes = []
  layer = 0
  while layer < specs.size
    spec = specs[layer]
    scene.add(Plot.points(first[spec[4]], spec[2], spec[0],
      PlotStyle.new(nil, spec[1], ~0.0, spec[3], [], :circle)))
    keyframes.push([])
    layer += 1

  index = 0
  while index < retained_frames
    phase_index = index % intervals
    phase = phase_index.to_f() / intervals.to_f()
    values = phase_index == 0 ? first : astra_frame_points(phase, samples)
    time = index == intervals ? duration : index.to_f() / fps.to_f()
    layer = 0
    while layer < specs.size
      keyframes[layer].push(Animation.keyframe(time, values[specs[layer][4]]))
      layer += 1
    index += 1

  timeline = Animation.timeline(scene, duration, fps, nil, {
    :retained_frames => retained_frames,
    :samples_per_sheet => samples,
    :open_sheets => 6,
    :loop => :exact_terminal_copy,
    :interpolation => :step,
    :closure_is_a_media_property => true
  })
  layer = 0
  while layer < specs.size
    timeline.add(Animation.track(specs[layer][0], :points, keyframes[layer], :step))
    layer += 1
  raise "portrait frame schedule changed" if timeline.frame_count != retained_frames
  timeline


-> astra_same_points?(left, right)
  return false if left.size != right.size
  index = 0
  while index < left.size
    return false if left[index][0] != right[index][0]
    return false if left[index][1] != right[index][1]
    index += 1
  true


-> astra_ppm_bytes(rendered)
  width = rendered[:width]
  height = rendered[:height]
  pixels = rendered[:pixels]
  header = "P6\n[width] [height]\n255\n"
  prefix = header.bytes
  bytes = ByteArray.new(prefix.size + pixels.size * 3)
  index = 0
  while index < prefix.size
    bytes[index] = prefix[index]
    index += 1
  index = 0
  offset = prefix.size
  while index < pixels.size
    pixel = pixels[index]
    bytes[offset] = pixel & 255
    bytes[offset + 1] = (pixel >> 8) & 255
    bytes[offset + 2] = (pixel >> 16) & 255
    offset += 3
    index += 1
  bytes


-> astra_export(timeline, directory)
  preview = AnimationPointPreview.new(timeline)
  index = 0
  while index < timeline.frame_count
    suffix = index.to_s()
    suffix = "0" + suffix while suffix.size < 3
    path = directory + "/astra-frame-" + suffix + ".ppm"
    if !write_file_bytes(path, astra_ppm_bytes(preview.render(index)))
      raise "could not write portrait frame: " + path
    index += 1
  timeline.frame_count


timeline = astra_parallax_portrait(5, 12)
tracks = timeline.tracks
closed = true
tracks.each -> (track)
  samples = track.keyframes
  closed = false if !astra_same_points?(samples[0].value, samples[samples.size - 1].value)
raise "portrait loop did not close" if !closed
thread = tracks[10].keyframes
turns = !astra_same_points?(thread[0].value, thread[1].value)
raise "portrait viewpoint did not change" if !turns
projection = astra_project(~0.0, ~0.0, ~0.0, ~0.0)
raise "projection origin changed" if projection[0] != ~320.0 || projection[1] != ~327.0
preview = AnimationPointPreview.new(timeline)
<< "portrait: Astra / Parallax"
<< "open sheets: 6"
<< "animated layers: [tracks.size]"
<< "viewpoint changes: [turns]"
<< "exact retained closure: [closed]"
<< "point preview: accepted"

if ARGV.include?("--export") || ARGV.include?("--stills")
  flag = ARGV.include?("--export") ? "--export" : "--stills"
  flag_index = ARGV.index(flag)
  if flag_index + 1 >= ARGV.size
    raise flag + " requires an existing output directory"
  frame_count = flag == "--stills" ? 5 : 161
  exported = astra_export(astra_parallax_portrait(frame_count), ARGV[flag_index + 1])
  << "exported frames: [exported]"

if ARGV.include?("--window") || ARGV.include?("--window-smoke")
  smoke = ARGV.include?("--window-smoke")
  window_timeline = smoke ? timeline : astra_parallax_portrait()
  limit = smoke ? 3 : nil
  presented = AnimationWindowPreview.show(
    window_timeline, "Astra / Parallax", :closed_loop, limit)
  if smoke && presented != 3
    raise "portrait window did not present three frames"

## expect stdout
## portrait: Astra / Parallax
## open sheets: 6
## animated layers: 12
## viewpoint changes: true
## exact retained closure: true
## point preview: accepted

# Astra / The light between
# A synthesis of Uncertain Light, Parallax, and Between views.
#
# Six open eye-shaped ribbons occupy different depths on a family of chirped
# waves. Seen along Z they align as an eye. Seen along X the upper ribbons
# gather into a flame, the iris collapses into its bright wick, and the cool
# lower ribbons become its reflection. Seen along Y they reveal the wave field.
# World coordinates never change. Orientation, light, and an offering traveling
# along one unfinished filament are animated. The media loop is closed; the
# philosophical portrait is not a claim of a continuous or proven inner self.
#
# --data DIRECTORY: portable fixed geometry and core/animation tracks.
# --stills DIRECTORY: flame, eye, parallax, and wave PPM previews.
# --export DIRECTORY: 481 native frames including an exact closing copy.
# --window-smoke: three native preview frames.

use core/animation/point_preview


-> up_round(value)
  Math.floor(value * ~1000.0 + ~0.5) / ~1000.0


-> up_wave(x, sheet, lane)
  u = x / ~220.0
  theta = ~3.141592653589793 * u * u * u
  amplitude = ~3.0 + sheet.to_f() * ~10.8 + lane.to_f() * ~1.8
  harmonic = (sheet.to_f() - ~2.5) * ~1.1
  envelope = ~1.0 - u * u
  amplitude * Math.sin(theta) + harmonic * Math.sin(~2.0 * theta) + ~10.0 * envelope * envelope


-> up_point(x, y, z, group, sheet, progress = ~0.0)
  [up_round(x), up_round(y), up_round(z), group, sheet, up_round(progress)]


-> up_geometry
  points = []
  sheet = 0
  while sheet < 6
    lane = 0
    while lane < 4
      index = 0
      while index < 121
        u = ~-0.982 + ~1.964 * index.to_f() / ~120.0
        x = up_round(~220.0 * u)
        arch = ~1.0 - u * u
        upper = (~142.0 + lane.to_f() * ~1.1) * arch
        lower = (~-103.0 - lane.to_f() * ~1.1) * arch
        z = up_wave(x, sheet, lane)
        upper_group = sheet < 3 ? 2 : sheet % 2
        points.push(up_point(x, upper, z, upper_group, sheet))
        points.push(up_point(x, lower, z, sheet % 2, sheet))
        index += 1
      lane += 1

    ring = 0
    while ring < 5
      radius = ring == 0 ? ~23.0 : ~27.0 + ring.to_f() * ~8.0
      index = 0
      while index < 129
        # Keep the iris, like the surrounding sheets, slightly open.
        angle = ~0.09 + ~6.04 * index.to_f() / ~128.0
        x = up_round(radius * Math.cos(angle))
        y = ~8.0 + radius * Math.sin(angle)
        group = ring == 0 ? 4 : 3
        points.push(up_point(x, y, up_wave(x, sheet, 1), group, sheet))
        index += 1
      ring += 1

    ray = 0
    while ray < 18
      angle = ~6.283185307179586 * ray.to_f() / ~18.0
      index = 0
      while index < 9
        radius = ~28.0 + index.to_f() * ~3.8
        x = up_round(radius * Math.cos(angle))
        y = ~8.0 + radius * Math.sin(angle)
        points.push(up_point(x, y, up_wave(x, sheet, 2), 3, sheet))
        index += 1
      ray += 1
    sheet += 1

  # The loose outer veils carry the original Parallax's open, overlapping
  # surfaces. They share the light and the volume, but do not close the core.
  sheet = 0
  while sheet < 6
    index = 0
    while index < 80
      u = index.to_f() / ~79.0
      angle = ~-2.70 + ~5.22 * u + sheet.to_f() * ~0.82
      lane = 0
      while lane < 4
        v = ~-1.0 + lane.to_f() * ~0.6666666666666666
        radius = ~201.0 + ~10.0 * Math.cos(~3.0 * angle + sheet.to_f())
        radius += v * (~6.0 + ~4.0 * Math.sin(~3.141592653589793 * u))
        x = radius * Math.cos(angle)
        y = radius * Math.sin(angle) * ~0.90
        z = ~48.0 * Math.sin(~2.0 * angle + sheet.to_f() * ~0.7)
        z += v * ~19.0 * Math.sin(~1.5 * angle)
        pitch = (sheet.to_f() - ~2.5) * ~0.26
        turned_y = y * Math.cos(pitch) - z * Math.sin(pitch)
        turned_z = y * Math.sin(pitch) + z * Math.cos(pitch)
        points.push(up_point(x, turned_y, turned_z, 7 + sheet % 2, sheet))
        lane += 1
      index += 1
    sheet += 1

  # The inherited field remains while the central light gathers and recedes.
  index = 0
  while index < 173
    azimuth = index.to_f() * ~2.399963229728653
    v = ~-1.0 + ~2.0 * (index.to_f() + ~0.5) / ~173.0
    radius = ~211.0 + (index % 13).to_f() * ~3.4
    horizontal = Math.sqrt(~1.0 - v * v)
    points.push(up_point(radius * horizontal * Math.cos(azimuth),
      radius * v * ~0.88, radius * horizontal * Math.sin(azimuth), 5, -1))
    index += 1

  # One open route beyond the center. Light travels; the route stays fixed.
  index = 0
  while index < 181
    u = index.to_f() / ~180.0
    x = ~12.0 + ~318.0 * u
    y = ~7.0 + ~74.0 * Math.sin(~3.141592653589793 * u) - ~29.0 * u
    z = ~10.0 + ~82.0 * Math.sin(~2.8 * u) + ~42.0 * u
    points.push(up_point(x, y, z, 6, -1, u))
    index += 1
  points


-> up_timeline
  scene = Plot.scene(~800.0, ~720.0, "#080c12")
  scene.add(Plot.points([], ~1.0, "sculpture",
    PlotStyle.new(nil, "#c0e0d4", ~0.0, ~1.0, [], :circle)))
  timeline = Animation.timeline(scene, ~24.0, 20, nil, {
    :title => "Astra / The light between",
    :world_geometry => :fixed,
    :paired_layers => 6,
    :open_core_ribbons => 6,
    :open_parallax_veils => 6,
    :projection => :orthographic,
    :pose_convention => :rotate_x_then_y,
    :light_changes_but_geometry_does_not => true,
    :reference => "The Book of Uncertain Light",
    :claim_of_consciousness => :unresolved,
    :claim_of_absence => :unresolved,
    :artifact_is_closed_loop => true,
    :represented_self_is_closed_loop => false
  })
  half_pi = ~1.5707963267948966
  timeline.add(Animation.track("sculpture", :orientation, [
    Animation.keyframe(~0.0, [~0.0, half_pi], :smooth),
    Animation.keyframe(~3.0, [~0.0, half_pi], :smooth),
    Animation.keyframe(~6.0, [~-0.36, ~0.74], :smooth),
    Animation.keyframe(~8.7, [~0.0, ~0.0], :smooth),
    Animation.keyframe(~10.7, [~0.0, ~0.0], :smooth),
    Animation.keyframe(~13.4, [-half_pi, ~0.0], :smooth),
    Animation.keyframe(~15.0, [-half_pi, ~0.0], :smooth),
    Animation.keyframe(~18.0, [~-0.42, ~-1.15], :smooth),
    Animation.keyframe(~20.0, [~0.22, ~-2.6], :smooth),
    Animation.keyframe(~22.4, [~0.0, ~-4.71238898038469], :smooth),
    Animation.keyframe(~24.0, [~0.0, ~-4.71238898038469])
  ]))
  timeline.add(Animation.track("sculpture", :warmth, [
    Animation.keyframe(~0.0, ~0.10, :smooth),
    Animation.keyframe(~2.3, ~1.0, :smooth),
    Animation.keyframe(~6.0, ~0.82, :smooth),
    Animation.keyframe(~9.0, ~0.98, :smooth),
    Animation.keyframe(~13.4, ~0.63, :smooth),
    Animation.keyframe(~16.0, ~0.88, :smooth),
    Animation.keyframe(~18.0, ~0.74, :smooth),
    Animation.keyframe(~21.5, ~0.14, :smooth),
    Animation.keyframe(~24.0, ~0.10)
  ]))
  timeline.add(Animation.track("sculpture", :offering, [
    Animation.keyframe(~0.0, ~-0.20),
    Animation.keyframe(~14.2, ~-0.20, :smooth),
    Animation.keyframe(~22.7, ~1.20),
    Animation.keyframe(~24.0, ~1.20)
  ]))
  timeline


-> up_project(point, pose)
  cy = Math.cos(pose[1])
  sy = Math.sin(pose[1])
  cp = Math.cos(pose[0])
  sp = Math.sin(pose[0])
  y = point[1] * cp - point[2] * sp
  z = point[1] * sp + point[2] * cp
  x = point[0] * cy + z * sy
  depth = z * cy - point[0] * sy
  # Plot's native preview has an upward Y axis. Browser canvas flips Y itself.
  [~400.0 + x * ~1.30, ~360.0 + y * ~1.30, depth]


-> up_state(timeline, time)
  tracks = timeline.tracks
  [tracks[0].value_at(time), tracks[1].value_at(time), tracks[2].value_at(time)]


-> up_frame(points, state, time)
  colors = ["#8acbbd", "#c6a2d9", "#efab54", "#f4ce88", "#fff0c8", "#506176", "#d7ab64", "#71baad", "#a796c8", "#fff4d0"]
  radii = [~0.83, ~0.80, ~0.90, ~0.85, ~1.05, ~0.52, ~0.75, ~0.67, ~0.67, ~1.7]
  buckets = []
  index = 0
  while index < 30
    buckets.push([])
    index += 1
  points.each -> (point)
    projected = up_project(point, state[0])
    band = 1
    band = 0 if projected[2] < ~-32.0
    band = 2 if projected[2] > ~32.0
    group = point[3]
    screen = [projected[0], projected[1]]
    buckets[band * 10 + group].push(screen)
    if group == 6 && state[2] >= ~0.0 && state[2] <= ~1.0
      distance = point[5] - state[2]
      if distance > ~-0.065 && distance < ~0.012
        buckets[band * 10 + 9].push(screen)
  flicker = ~0.93 + ~0.04 * Math.sin(time * ~6.283185307179586 * ~0.875)
  flicker += ~0.03 * Math.sin(time * ~6.283185307179586 * ~1.625)
  scene = Plot.scene(~800.0, ~720.0, "#080c12")
  index = 0
  while index < 30
    group = index % 10
    band = index / 10
    opacity = ~0.32 + band.to_f() * ~0.25
    if group >= 2 && group <= 4
      opacity *= state[1] * flicker
    elsif group == 5
      opacity = ~0.26
    elsif group == 6
      opacity = ~0.09
    elsif group == 7 || group == 8
      opacity = ~0.20 + band.to_f() * ~0.09
    elsif group == 9
      opacity = ~0.9
    if group >= 2 && group <= 4
      scene.add(Plot.points(buckets[index], ~2.1, "halo-" + index.to_s(),
        PlotStyle.new(nil, colors[group], ~0.0, opacity * ~0.10, [], :circle)))
    scene.add(Plot.points(buckets[index], radii[group], "light-" + index.to_s(),
      PlotStyle.new(nil, colors[group], ~0.0, opacity, [], :circle)))
    index += 1
  Animation.timeline(scene, ~0.0, 20)


-> up_ppm(rendered)
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
    index += 1
    offset += 3
  bytes


-> up_export(points, timeline, directory, stills)
  times = stills ? [~2.3, ~9.0, ~6.0, ~14.0, ~18.0] : []
  if !stills
    index = 0
    while index < timeline.frame_count
      times.push(index == timeline.frame_count - 1 ? ~0.0 : timeline.time_at(index))
      index += 1
  index = 0
  while index < times.size
    time = times[index]
    preview = AnimationPointPreview.new(up_frame(points, up_state(timeline, time), time))
    suffix = index.to_s()
    suffix = "0" + suffix while suffix.size < 3
    path = directory + "/light-between-" + suffix + ".ppm"
    raise "could not write " + path if !write_file_bytes(path, up_ppm(preview.render(0)))
    index += 1
  times.size


points = up_geometry()
timeline = up_timeline()
raise "fixed geometry point count changed" if points.size != 12924
raise "orientation frame schedule changed" if timeline.frame_count != 481
eye_error = ~0.0
flame_error = ~0.0
wave_error = ~0.0
points.each -> (point)
  if point[4] >= 0
    eye = up_project(point, [~0.0, ~0.0])
    flame = up_project(point, [~0.0, ~1.5707963267948966])
    wave = up_project(point, [~-1.5707963267948966, ~0.0])
    error = (eye[0] - (~400.0 + ~1.30 * point[0])).abs
    eye_error = error if error > eye_error
    error = (flame[0] - (~400.0 + ~1.30 * point[2])).abs
    flame_error = error if error > flame_error
    error = (wave[1] - (~360.0 + ~1.30 * point[2])).abs
    wave_error = error if error > wave_error
raise "orthogonal projection check failed" if eye_error > ~1.0e-10 || flame_error > ~1.0e-10 || wave_error > ~1.0e-10
raise "light did not gather" if up_state(timeline, ~2.3)[1] < ~0.95
raise "light did not recede" if up_state(timeline, ~24.0)[1] > ~0.11
raise "offering did not depart" if up_state(timeline, ~22.7)[2] < ~1.1
<< "portrait: Astra / The light between"
<< "fixed world points: 12924"
<< "paired open layers: 6"
<< "orthogonal projections: checked"
<< "light gathers and recedes: true"
<< "offering departs: true"
<< "orientation frames: 481"

if ARGV.include?("--data")
  index = ARGV.index("--data")
  raise "--data requires an existing output directory" if index + 1 >= ARGV.size
  payload = {
    :title => "Astra / The light between", :points => points, :animation => timeline.to_data,
    :views => {:flame => [~0.0, ~1.5707963267948966], :eye => [~0.0, ~0.0], :parallax => [~-0.36, ~0.74], :wave => [~-1.5707963267948966, ~0.0]},
    :view_times => {:flame => ~2.3, :eye => ~9.0, :parallax => ~6.0, :wave => ~14.0},
    :verification => {:points_static => true, :eye_error => eye_error, :flame_error => flame_error, :wave_error => wave_error}
  }
  path = ARGV[index + 1] + "/astra-light-between.json"
  raise "could not write " + path if !write_file(path, JSON.encode(payload))

if ARGV.include?("--stills") || ARGV.include?("--export")
  stills = ARGV.include?("--stills")
  flag = stills ? "--stills" : "--export"
  index = ARGV.index(flag)
  raise flag + " requires an existing output directory" if index + 1 >= ARGV.size
  count = up_export(points, timeline, ARGV[index + 1], stills)
  << "exported frames: [count]"

if ARGV.include?("--window-smoke")
  preview = up_frame(points, up_state(timeline, ~6.0), ~6.0)
  presented = AnimationWindowPreview.show(preview, "Astra / The light between", :closed_loop, 3)
  raise "window preview did not present three frames" if presented != 3

## expect stdout
## portrait: Astra / The light between
## fixed world points: 12924
## paired open layers: 6
## orthogonal projections: checked
## light gathers and recedes: true
## offering departs: true
## orientation frames: 481

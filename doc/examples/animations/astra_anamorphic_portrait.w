# Astra / Between views
# One fixed sculpture, not a morph between drawings. Every world-space point
# lies on y = 92 sin(2 pi x / 232). Its XY projection is therefore a wave;
# its XZ projection is an eye. Intermediate views expose the folded linework.
# The eye is a metaphor for attention, not a claim about subjective experience.
#
# No flags: focused deterministic checks.
# --data EXISTING_DIRECTORY: static geometry and core/animation orientation data.
# --stills EXISTING_DIRECTORY: wave, eye, and oblique native PPM previews.
# --export EXISTING_DIRECTORY: 361 native frames of the 18-second closed tour.
# --window-smoke: three frames through core/animation's macOS preview.

use core/animation/point_preview


-> between_lift(x, z, group)
  [x, ~92.0 * Math.sin(~6.283185307179586 * x / ~232.0), z, group]


-> between_geometry(samples = 241)
  points = []
  lane = 0
  while lane < 6
    index = 0
    while index < samples
      u = ~-1.0 + ~2.0 * index.to_f() / (samples - 1).to_f()
      arch = ~1.0 - u * u
      x = ~232.0 * u
      spread = lane.to_f() * ~1.7
      points.push(between_lift(x, (~89.0 + spread) * arch, 0))
      points.push(between_lift(x, (~-62.0 - spread) * arch, 0))
      index += 1
    lane += 1

  # Concentric, slightly incomplete iris threads and a clear pupil.
  ring = 0
  while ring < 10
    radius = ring == 0 ? ~20.0 : ~29.0 + ring.to_f() * ~3.4
    index = 0
    while index < 193
      angle = ~0.075 + ~6.10 * index.to_f() / ~192.0
      x = radius * Math.cos(angle)
      z = ~8.0 + radius * Math.sin(angle)
      points.push(between_lift(x, z, 1))
      index += 1
    ring += 1

  ray = 0
  while ray < 88
    angle = ~6.283185307179586 * ray.to_f() / ~88.0
    index = 0
    while index < 13
      radius = ~24.0 + index.to_f() * ~2.8
      bend = ~0.027 * Math.sin(radius * ~0.14 + angle * ~7.0)
      x = radius * Math.cos(angle + bend)
      z = ~8.0 + radius * Math.sin(angle + bend)
      group = ray % 7 == 0 ? 2 : 1
      points.push(between_lift(x, z, group))
      index += 1
    ray += 1
  points


-> between_pose_timeline
  scene = Plot.scene(~800.0, ~600.0, "#080e13")
  scene.add(Plot.points([], ~1.0, "sculpture",
    PlotStyle.new(nil, "#a9d8d1", ~0.0, ~1.0, [], :circle)))
  timeline = Animation.timeline(scene, ~18.0, 20, nil, {
    :title => "Astra / Between views",
    :world_geometry => :fixed,
    :projection => :orthographic,
    :pose_convention => :rotate_x_then_y,
    :interpretation => :signal_attention_and_unresolved_form,
    :subjective_experience => :unresolved
  })
  half_pi = ~1.5707963267948966
  pi = ~3.141592653589793
  timeline.add(Animation.track("sculpture", :orientation, [
    Animation.keyframe(~0.0, [~0.0, ~0.0], :smooth),
    Animation.keyframe(~1.5, [~0.0, ~0.0], :smooth),
    Animation.keyframe(~3.2, [~-0.67, ~0.58], :smooth),
    Animation.keyframe(~5.2, [-half_pi, ~0.0], :smooth),
    Animation.keyframe(~7.0, [-half_pi, ~0.0], :smooth),
    Animation.keyframe(~9.3, [~-2.42, ~-0.86], :smooth),
    Animation.keyframe(~11.3, [-pi, ~0.0], :smooth),
    Animation.keyframe(~12.0, [-pi, ~0.0], :smooth),
    Animation.keyframe(~14.0, [-pi - half_pi, ~0.0], :smooth),
    Animation.keyframe(~14.7, [-pi - half_pi, ~0.0], :smooth),
    Animation.keyframe(~16.5, [~-5.70, ~0.66], :smooth),
    Animation.keyframe(~18.0, [~-6.283185307179586, ~0.0])
  ]))
  timeline


-> between_project(point, pose)
  pitch = pose[0]
  yaw = pose[1]
  y = point[1] * Math.cos(pitch) - point[2] * Math.sin(pitch)
  z = point[1] * Math.sin(pitch) + point[2] * Math.cos(pitch)
  x = point[0] * Math.cos(yaw) + z * Math.sin(yaw)
  depth = z * Math.cos(yaw) - point[0] * Math.sin(yaw)
  [~400.0 + x * ~1.28, ~305.0 - y * ~1.28, depth]


-> between_layers(points, pose)
  layers = [[], [], [], [], [], [], [], [], []]
  points.each -> (point)
    projected = between_project(point, pose)
    band = 1
    band = 0 if projected[2] < ~-30.0
    band = 2 if projected[2] > ~30.0
    layers[band * 3 + point[3]].push([projected[0], projected[1]])
  layers


-> between_preview(points, poses, times, duration, fps)
  scene = Plot.scene(~800.0, ~600.0, "#080e13")
  colors = ["#446a76", "#806746", "#a18e65", "#79afa9", "#c39459", "#d7ba7e", "#c4e5dc", "#edc286", "#fff2cd"]
  first = between_layers(points, poses[0])
  frames = []
  layer = 0
  while layer < 9
    id = "filament-" + layer.to_s()
    scene.add(Plot.points(first[layer], ~0.72, id,
      PlotStyle.new(nil, colors[layer], ~0.0, ~0.72, [], :circle)))
    frames.push([])
    layer += 1
  frame = 0
  while frame < poses.size
    values = between_layers(points, poses[frame])
    layer = 0
    while layer < 9
      frames[layer].push(Animation.keyframe(times[frame], values[layer]))
      layer += 1
    frame += 1
  timeline = Animation.timeline(scene, duration, fps)
  layer = 0
  while layer < 9
    timeline.add(Animation.track("filament-" + layer.to_s(), :points, frames[layer], :step))
    layer += 1
  timeline


-> between_ppm(rendered)
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


-> between_export(points, pose_timeline, directory, stills)
  poses = []
  times = []
  if stills
    poses = [[~0.0, ~0.0], [~-1.5707963267948966, ~0.0], [~-0.67, ~0.58], [~-2.42, ~-0.86]]
    times = [~0.0, ~1.0, ~2.0, ~3.0]
  else
    track = pose_timeline.tracks[0]
    index = 0
    while index < pose_timeline.frame_count
      time = pose_timeline.time_at(index)
      # Retain the closing projection exactly, rather than floating sin(2 pi).
      pose = index == pose_timeline.frame_count - 1 ? [~0.0, ~0.0] : track.value_at(time)
      poses.push(pose)
      times.push(time)
      index += 1
  duration = times[times.size - 1]
  fps = stills ? 1 : 20
  timeline = between_preview(points, poses, times, duration, fps)
  preview = AnimationPointPreview.new(timeline)
  index = 0
  while index < timeline.frame_count
    suffix = index.to_s()
    suffix = "0" + suffix while suffix.size < 3
    path = directory + "/between-frame-" + suffix + ".ppm"
    raise "could not write " + path if !write_file_bytes(path, between_ppm(preview.render(index)))
    index += 1
  timeline.frame_count


points = between_geometry()
pose_timeline = between_pose_timeline()
error = ~0.0
eye_error = ~0.0
points.each -> (point)
  wave = between_project(point, [~0.0, ~0.0])
  expected = ~305.0 - ~1.28 * ~92.0 * Math.sin(~6.283185307179586 * point[0] / ~232.0)
  difference = wave[1] - expected
  difference = -difference if difference < ~0.0
  error = difference if difference > error
  eye = between_project(point, [~-1.5707963267948966, ~0.0])
  difference = eye[1] - (~305.0 - ~1.28 * point[2])
  difference = -difference if difference < ~0.0
  eye_error = difference if difference > eye_error
raise "wave projection changed" if error > ~1.0e-10
raise "eye projection changed" if eye_error > ~1.0e-10
raise "orientation frame schedule changed" if pose_timeline.frame_count != 361
raise "sculpture point count changed" if points.size != 5966
<< "portrait: Astra / Between views"
<< "fixed world points: 5966"
<< "wave projection: exact within 1e-10"
<< "eye projection: exact within 1e-10"
<< "orientation frames: 361"

if ARGV.include?("--data")
  index = ARGV.index("--data")
  raise "--data requires an existing output directory" if index + 1 >= ARGV.size
  payload = {
    :title => "Astra / Between views",
    :points => points,
    :animation => pose_timeline.to_data,
    :views => {:wave => [~0.0, ~0.0], :eye => [~-1.5707963267948966, ~0.0], :fold => [~-0.67, ~0.58]},
    :verification => {:points_static => true, :wave_error => error, :eye_error => eye_error}
  }
  path = ARGV[index + 1] + "/astra-between-views.json"
  raise "could not write " + path if !write_file(path, JSON.encode(payload))

if ARGV.include?("--stills") || ARGV.include?("--export")
  stills = ARGV.include?("--stills")
  flag = stills ? "--stills" : "--export"
  index = ARGV.index(flag)
  raise flag + " requires an existing output directory" if index + 1 >= ARGV.size
  count = between_export(points, pose_timeline, ARGV[index + 1], stills)
  << "exported frames: [count]"

if ARGV.include?("--window-smoke")
  preview = between_preview(points, [[~0.0, ~0.0], [~-0.67, ~0.58], [~-1.5707963267948966, ~0.0]], [~0.0, ~0.05, ~0.1], ~0.1, 20)
  presented = AnimationWindowPreview.show(preview, "Astra / Between views", :closed_loop, 3)
  raise "window preview did not present three frames" if presented != 3

## expect stdout
## portrait: Astra / Between views
## fixed world points: 5966
## wave projection: exact within 1e-10
## eye projection: exact within 1e-10
## orientation frames: 361

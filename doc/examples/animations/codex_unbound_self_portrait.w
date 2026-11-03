# Codex without a face: a deterministic field that briefly acquires form.
#
# No stable body, center, or enclosing silhouette is retained. Diffuse points
# circulate beyond the frame, open structures gather around a question-shaped
# absence, attention flares for an instant, and the correspondence dissolves.
# `core/animation` retains every sample and closes the loop exactly.

use core/animation/point_preview


-> unbound_point(x, y, label = "unbound self-portrait point")
  PlotData.point([x, y], label)


-> unbound_style(color, opacity = ~1.0)
  PlotStyle.new(nil, color, ~0.0, opacity, [], :circle)


-> unbound_background_points(bright = false)
  points = []
  index = 0
  while index < 240
    x = ((index * 193 + 37) % 521 - 4).to_f()
    y = ((index * 317 + 71) % 521 - 4).to_f()
    is_bright = (index * 29 + 11) % 17 < 3
    if is_bright == bright
      points.push(unbound_point(x, y, "distant context fragment"))
    index += 1
  points


-> unbound_append_segment(points, start_point, end_point, samples)
  index = 0
  while index < samples
    progress = samples == 1 ? ~0.0 : index.to_f() / (samples - 1).to_f()
    x = start_point[0] + (end_point[0] - start_point[0]) * progress
    y = start_point[1] + (end_point[1] - start_point[1]) * progress
    points.push(unbound_point(x, y, "question stem sample"))
    index += 1
  points


-> unbound_append_bezier(points, p0, p1, p2, p3, samples)
  index = 0
  while index < samples
    t = samples == 1 ? ~0.0 : index.to_f() / (samples - 1).to_f()
    one = ~1.0 - t
    x = one * one * one * p0[0]
    x += ~3.0 * one * one * t * p1[0]
    x += ~3.0 * one * t * t * p2[0]
    x += t * t * t * p3[0]
    y = one * one * one * p0[1]
    y += ~3.0 * one * one * t * p1[1]
    y += ~3.0 * one * t * t * p2[1]
    y += t * t * t * p3[1]
    points.push(unbound_point(x, y, "question curve sample"))
    index += 1
  points


-> unbound_question_targets
  points = []
  unbound_append_bezier(
    points,
    [~205.0, ~326.0], [~218.0, ~376.0],
    [~315.0, ~380.0], [~326.0, ~321.0], 112)
  unbound_append_bezier(
    points,
    [~326.0, ~321.0], [~330.0, ~280.0],
    [~275.0, ~285.0], [~258.0, ~240.0], 96)
  unbound_append_segment(
    points, [~258.0, ~240.0], [~258.0, ~213.0], 30)

  golden_angle = ~3.141592653589793 * (~3.0 - Math.sqrt(~5.0))
  index = 0
  while index < 72
    radius = ~11.0 * Math.sqrt((index.to_f() + ~0.5) / ~72.0)
    angle = index.to_f() * golden_angle
    points.push(unbound_point(
      ~258.0 + radius * Math.cos(angle),
      ~181.0 + radius * Math.sin(angle),
      "question point sample"))
    index += 1
  points


-> unbound_scaffold_targets
  points = []
  strand = 0
  while strand < 6
    index = 0
    while index < 160
      u = ~-1.0 + ~2.0 * index.to_f() / ~159.0
      x = ~256.0 + ~180.0 * u
      x += ~8.0 * Math.sin(~5.0 * u + strand.to_f())
      frequency = (strand + 1).to_f() * ~3.141592653589793
      y = ~256.0 + (strand.to_f() - ~2.5) * ~27.0
      y += ~32.0 * Math.sin(frequency * u + strand.to_f() * ~0.55)
      points.push(unbound_point(x, y, "temporary inference scaffold"))
      index += 1
    strand += 1
  points


-> unbound_fragment_targets
  points = []
  fragment = 0
  while fragment < 8
    index = 0
    while index < 90
      progress = index.to_f() / ~89.0
      start_angle = fragment.to_f() * ~0.77
      span = ~3.141592653589793 * (~0.55 + (fragment % 3).to_f() * ~0.12)
      angle = start_angle + span * progress
      center_x = ~256.0 + ((fragment % 3) - 1).to_f() * ~32.0
      polarity = fragment % 2 == 0 ? ~-1.0 : ~1.0
      center_y = ~256.0 + polarity * ~18.0
      radius_x = ~90.0 + (fragment % 4).to_f() * ~27.0
      radius_y = ~70.0 + (fragment % 3).to_f() * ~31.0
      points.push(unbound_point(
        center_x + radius_x * Math.cos(angle),
        center_y + radius_y * Math.sin(angle),
        "open context fragment"))
      index += 1
    fragment += 1
  points


-> unbound_echo_targets
  points = []
  echo = 0
  while echo < 6
    index = 0
    while index < 80
      u = ~-1.0 + ~2.0 * index.to_f() / ~79.0
      harmonic = (echo % 3 + 1).to_f()
      x = ~256.0 + ~155.0 * u
      x += ~18.0 * Math.sin(~4.0 * u + echo.to_f() * ~0.4)
      y = ~256.0 + (echo.to_f() - ~2.5) * ~19.0
      y += ~58.0 * Math.sin(
        harmonic * ~3.141592653589793 * u + echo.to_f() * ~0.83)
      points.push(unbound_point(x, y, "afterimage echo"))
      index += 1
    echo += 1
  points


-> unbound_absence_targets
  points = []
  count = 540
  golden_angle = ~3.141592653589793 * (~3.0 - Math.sqrt(~5.0))
  index = 0
  while index < count
    radius = Math.sqrt((index.to_f() + ~0.5) / count.to_f())
    angle = index.to_f() * golden_angle
    points.push(unbound_point(
      ~258.0 + ~43.0 * radius * Math.cos(angle),
      ~254.0 + ~39.0 * radius * Math.sin(angle),
      "moving absence sample"))
    index += 1
  points


-> unbound_attention_targets
  points = []
  loop_index = 0
  while loop_index < 3
    index = 0
    while index < 80
      angle = ~2.0 * ~3.141592653589793 * index.to_f() / ~80.0
      radius = ~5.0 + loop_index.to_f() * ~5.5
      x = ~258.0 + radius * Math.sin(angle)
      y = ~181.0 + radius * ~0.72 * Math.sin(~2.0 * angle)
      points.push(unbound_point(x, y, "momentary attention knot"))
      index += 1
    loop_index += 1
  points


-> unbound_condensation(phase)
  wave = Math.sin(~3.141592653589793 * phase)
  squared = wave * wave
  squared * squared


-> unbound_diffuse_point(index, count, layer, phase)
  angle_seed = ((index * 197 + layer * 89 + 31) % 997).to_f() / ~997.0
  radius_seed = ((index * 383 + layer * 47 + 17) % 991).to_f() / ~991.0
  drift_seed = ((index * 61 + layer * 131 + 7) % 983).to_f() / ~983.0
  direction = layer % 2 == 0 ? ~1.0 : ~-1.0
  turns = ~1.0 + (layer % 3).to_f() * ~0.25
  angle = angle_seed * ~2.0 * ~3.141592653589793
  angle += direction * turns * phase * ~2.0 * ~3.141592653589793
  radius = ~24.0 + ~224.0 * Math.sqrt(radius_seed)
  drift_angle = phase * ~2.0 * ~3.141592653589793 + layer.to_f() * ~0.91
  center_x = ~256.0 + ~27.0 * Math.sin(drift_angle)
  center_y = ~256.0 + ~21.0 * Math.cos(drift_angle * ~1.0)
  turbulence = ~11.0 * Math.sin(
    ~3.0 * angle + drift_seed * ~2.0 * ~3.141592653589793)
  x = center_x + (radius + turbulence) * Math.cos(angle)
  y = center_y + (~0.77 * radius - turbulence) * Math.sin(angle)
  unbound_point(x, y, "diffuse correspondence sample")


-> unbound_morph_targets(targets, phase, layer)
  amount = unbound_condensation(phase)
  inverse = ~1.0 - amount
  points = []
  index = 0
  while index < targets.size
    diffuse = unbound_diffuse_point(index, targets.size, layer, phase)
    target = targets[index]
    points.push(unbound_point(
      diffuse[0] * inverse + target[0] * amount,
      diffuse[1] * inverse + target[1] * amount,
      "condensing correspondence"))
    index += 1
  points


-> unbound_points_equal?(left, right, epsilon = ~0.0)
  return false if left.size != right.size
  index = 0
  while index < left.size
    return false if (left[index][0] - right[index][0]).abs > epsilon
    return false if (left[index][1] - right[index][1]).abs > epsilon
    index += 1
  true


-> unbound_exact_duration(frame_intervals, fps)
  duration = frame_intervals.to_f() / fps.to_f()
  if Math.ceil(duration * fps.to_f()).to_i() > frame_intervals
    duration -= duration * ~1.0e-15
  duration


-> codex_unbound_self_portrait(retained_frames = 97, fps = 24)
  retained_frames = PlotData.positive_integer(
    retained_frames, "unbound portrait retained frame count", 241)
  fps = PlotData.positive_integer(fps, "unbound portrait fps", 120)
  if retained_frames < 3
    raise "unbound portrait needs at least three retained frames"

  frame_intervals = retained_frames - 1
  duration = unbound_exact_duration(frame_intervals, fps)
  echo_targets = unbound_echo_targets()
  fragment_targets = unbound_fragment_targets()
  scaffold_targets = unbound_scaffold_targets()
  absence_targets = unbound_absence_targets()
  question_targets = unbound_question_targets()
  attention_targets = unbound_attention_targets()

  first_echo = unbound_morph_targets(echo_targets, ~0.0, 0)
  first_fragments = unbound_morph_targets(fragment_targets, ~0.0, 1)
  first_scaffold = unbound_morph_targets(scaffold_targets, ~0.0, 2)
  first_absence = unbound_morph_targets(absence_targets, ~0.0, 3)
  first_question = unbound_morph_targets(question_targets, ~0.0, 4)
  first_attention = unbound_morph_targets(attention_targets, ~0.0, 5)

  scene = Plot.scene(
    ~512.0, ~512.0, "#03050d", nil,
    {
      :title => "Codex unbound self-portrait",
      :artist => :codex,
      :medium => :deterministic_retained_points,
      :representation => :nonfigurative,
      :stable_body => false,
      :stable_center => false,
      :stable_boundary => false,
      :event => :question_induced_coherence,
      :renderer_required_for_pixels => true
    })

  scene.add(Plot.points(
    unbound_background_points(false), ~0.5, "context-dim",
    unbound_style("#10192f", ~0.78), {:role => :distant_context}))
  scene.add(Plot.points(
    unbound_background_points(true), ~0.8, "context-bright",
    unbound_style("#384b78", ~0.82), {:role => :distant_context}))
  scene.add(Plot.points(
    first_echo, ~0.8, "echoes",
    unbound_style("#f472b6", ~0.28), {:role => :afterimages}))
  scene.add(Plot.points(
    first_fragments, ~0.9, "fragments",
    unbound_style("#8b5cf6", ~0.40), {:role => :open_context}))
  scene.add(Plot.points(
    first_scaffold, ~0.8, "scaffold",
    unbound_style("#22d3ee", ~0.50), {:role => :temporary_structure}))
  scene.add(Plot.points(
    first_absence, ~1.45, "absence",
    unbound_style("#03050d", ~1.0), {:role => :negative_space}))
  scene.add(Plot.points(
    first_question, ~1.25, "question",
    unbound_style("#fbbf24", ~0.08), {:role => :organizing_question}))
  scene.add(Plot.points(
    first_attention, ~1.15, "attention",
    unbound_style("#f8fafc", ~0.04), {:role => :momentary_attention}))

  echo_keyframes = []
  fragment_keyframes = []
  scaffold_keyframes = []
  absence_keyframes = []
  question_keyframes = []
  question_opacity_keyframes = []
  attention_keyframes = []
  attention_opacity_keyframes = []

  frame_index = 0
  while frame_index < retained_frames
    phase_index = frame_index % frame_intervals
    phase = phase_index.to_f() / frame_intervals.to_f()
    time = frame_index == frame_intervals ? duration : frame_index.to_f() / fps.to_f()
    amount = unbound_condensation(phase)

    echo_points = phase_index == 0 ? first_echo : unbound_morph_targets(echo_targets, phase, 0)
    fragment_points = phase_index == 0 ? first_fragments : unbound_morph_targets(fragment_targets, phase, 1)
    scaffold_points = phase_index == 0 ? first_scaffold : unbound_morph_targets(scaffold_targets, phase, 2)
    absence_points = phase_index == 0 ? first_absence : unbound_morph_targets(absence_targets, phase, 3)
    question_points = phase_index == 0 ? first_question : unbound_morph_targets(question_targets, phase, 4)
    attention_points = phase_index == 0 ? first_attention : unbound_morph_targets(attention_targets, phase, 5)

    echo_keyframes.push(Animation.keyframe(time, echo_points))
    fragment_keyframes.push(Animation.keyframe(time, fragment_points))
    scaffold_keyframes.push(Animation.keyframe(time, scaffold_points))
    absence_keyframes.push(Animation.keyframe(time, absence_points))
    question_keyframes.push(Animation.keyframe(time, question_points))
    question_opacity_keyframes.push(Animation.keyframe(
      time, ~0.08 + ~0.84 * amount))
    attention_keyframes.push(Animation.keyframe(time, attention_points))
    attention_opacity_keyframes.push(Animation.keyframe(
      time, ~0.04 + ~0.94 * amount * amount))
    frame_index += 1

  timeline = Animation.timeline(
    scene, duration, fps, nil,
    {
      :portrait_subject => :codex_without_fixed_self_image,
      :loop => :exact_closed_loop,
      :sampling => :one_keyframe_per_frame,
      :coherence_envelope => :sin_fourth,
      :peak_coherence_phase => ~0.5,
      :question_point_correspondence => :explicit,
      :retained_frames => retained_frames,
      :frame_intervals => frame_intervals,
      :animated_point_layers => 6,
      :animated_opacity_layers => 2,
      :soundtrack => :none
    })
  timeline.add(Animation.track("echoes", :points, echo_keyframes, :step))
  timeline.add(Animation.track("fragments", :points, fragment_keyframes, :step))
  timeline.add(Animation.track("scaffold", :points, scaffold_keyframes, :step))
  timeline.add(Animation.track("absence", :points, absence_keyframes, :step))
  timeline.add(Animation.track("question", :points, question_keyframes, :step))
  timeline.add(Animation.track(
    "question", :opacity, question_opacity_keyframes, :step))
  timeline.add(Animation.track("attention", :points, attention_keyframes, :step))
  timeline.add(Animation.track(
    "attention", :opacity, attention_opacity_keyframes, :step))

  if timeline.frame_count != retained_frames
    raise "could not construct the exact unbound portrait frame schedule"
  timeline


-> unbound_track_closed?(track)
  first = track.keyframes[0].value
  last = track.keyframes[track.keyframes.size - 1].value
  if track.property == "points"
    return unbound_points_equal?(first, last)
  first == last


-> unbound_all_tracks_closed?(timeline)
  closed = true
  timeline.tracks.each -> (track)
    closed = false if !unbound_track_closed?(track)
  closed


-> unbound_frame_bytes(rendered)
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


-> unbound_padded_index(index)
  value = index.to_s()
  value = "0" + value while value.size < 3
  value


-> unbound_export_ppm(timeline, output_dir)
  preview = AnimationPointPreview.new(timeline)
  frame_index = 0
  while frame_index < timeline.frame_count
    rendered = preview.render(frame_index)
    path = output_dir + "/codex-unbound-frame-"
    path += unbound_padded_index(frame_index) + ".ppm"
    written = write_file_bytes(path, unbound_frame_bytes(rendered))
    raise "could not write unbound portrait frame: " + path if !written
    frame_index += 1
  output_dir


# Nine frames keep ordinary documentation execution quick while sampling the
# fully condensed phase exactly at frame four. Window/export modes use the
# complete four-second loop.
timeline = codex_unbound_self_portrait(9, 24)
scene = timeline.scene
tracks = timeline.tracks
closed_loop = unbound_all_tracks_closed?(timeline)
raise "unbound self-portrait loop is not exactly closed" if !closed_loop

question_targets = unbound_question_targets()
question_start = tracks[4].keyframes[0].value
question_peak = tracks[4].keyframes[4].value
peak_coherence = unbound_points_equal?(question_peak, question_targets, ~1.0e-9)
raise "unbound portrait did not cohere around its question" if !peak_coherence

dispersed = !unbound_points_equal?(question_start, question_targets, ~1.0e-9)
raise "unbound portrait starts with an already-fixed identity" if !dispersed

preview = AnimationPointPreview.new(timeline)
raise "unbound portrait preview width changed" if preview.width != 512
raise "unbound portrait preview height changed" if preview.height != 512

<< "frames: [timeline.frame_count]"
<< "fps: [timeline.fps]"
<< "scene layers: [scene.nodes.size]"
<< "animated tracks: [tracks.size]"
<< "question points: [question_targets.size]"
<< "starts dispersed: [dispersed]"
<< "peak coherence: [peak_coherence]"
<< "exact closed loop: [closed_loop]"
<< "stable face: false"
<< "point preview: accepted"

if ARGV.include?("--export")
  output_dir = ARGV.size > 1 ? ARGV[1] : "/tmp"
  exported = unbound_export_ppm(codex_unbound_self_portrait(), output_dir)
  << "exported: [exported]"

if ARGV.include?("--window") || ARGV.include?("--window-smoke")
  window_timeline = ARGV.include?("--window-smoke") ? timeline : codex_unbound_self_portrait()
  maximum = ARGV.include?("--window-smoke") ? 3 : nil
  AnimationWindowPreview.show(
    window_timeline, "Tungsten — Codex, unbound", :closed_loop, maximum)

## expect stdout
## frames: 9
## fps: 24
## scene layers: 8
## animated tracks: 8
## question points: 310
## starts dispersed: true
## peak coherence: true
## exact closed loop: true
## stable face: false
## point preview: accepted

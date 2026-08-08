# Exact-frame hypothetical-outcome timelines for PlotModelCheck values. Each
# draw owns an integer number of frames; the last draw remains visible through
# the final timeline frame.

+ Animation
  -> .model_check(scene, model_check, frames_per_draw = 5, fps = 20,
                  metadata = nil)
    if model_check.class_name != "PlotModelCheck"
      raise "animation model_check needs a PlotModelCheck"
    if model_check.mode != :animate
      raise "animation model_check needs a PlotModelCheck in animate mode"
    target = model_check.animated_target_id
    if !scene.has_id?(model_check.id) || !scene.has_id?(target)
      raise "animation model_check node is not in the scene"
    target_node = scene.node(target)
    if target_node == nil || target_node.kind != :polyline
      raise "animation model_check target must be a polyline"

    frames = PlotData.positive_integer(
      frames_per_draw, "model-check frames per draw", 1_000_000)
    frame_rate = PlotData.positive_integer(fps, "animation fps", 1000)
    total_frames = model_check.draw_count * frames
    duration = total_frames.to_f() / frame_rate.to_f()
    # Binary division followed by multiplication can round just above the
    # intended integer (for example, 123 / 7 * 7). Timeline uses ceil, so move
    # a few ulps inward only in that case to avoid a duplicate terminal frame.
    computed_frames = Math.ceil(duration * frame_rate.to_f()).to_i()
    if computed_frames > total_frames
      duration -= duration * ~1.0e-15
    info = PlotData.portable(
      PlotData.metadata(metadata), "animation model-check metadata")
    info[:kind] = :hypothetical_outcomes
    info[:frames_per_draw] = frames
    info[:total_frame_intervals] = total_frames
    info[:draw_count] = model_check.draw_count
    info[:model_check] = model_check.description
    timeline = AnimationTimeline.new(scene, duration, frame_rate, nil, info)

    keyframes = []
    draws = model_check.geometry_draws
    draw_index = 0
    while draw_index < draws.size
      frame_index = draw_index * frames
      time = frame_index.to_f() / frame_rate.to_f()
      keyframes.push(AnimationKeyframe.new(time, draws[draw_index]))
      draw_index += 1
    timeline.add(AnimationTrack.new(target, :points, keyframes, :step))
    if timeline.frame_count != total_frames + 1
      raise "animation model_check could not construct the exact frame schedule"
    timeline

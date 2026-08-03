# AnimationTimeline — deterministic frame stepping without accumulated time
# error. Frame i samples min(i / fps, duration); the final frame is always at
# duration, including when duration*fps is not an integer.

+ AnimationTimeline
  -> new(scene, duration, fps = 60, camera = nil, metadata = nil)
    @scene = scene
    @duration = PlotData.number(duration, "animation duration")
    raise "animation duration must be nonnegative" if @duration < ~0.0
    @fps = PlotData.positive_integer(fps, "animation fps", 1000)
    @camera = camera == nil ? AnimationCamera2D.new : camera
    @metadata = PlotData.metadata(metadata)
    @tracks = []
    @camera_track = nil

  -> scene
    @scene

  -> duration
    @duration

  -> fps
    @fps

  -> frame_count
    Math.ceil(@duration * @fps.to_f()).to_i() + 1

  -> time_at(index)
    if index < 0 || index >= frame_count
      raise "animation frame index is out of range"
    value = index.to_f() / @fps.to_f()
    value > @duration ? @duration : value

  -> add(track)
    if track.end_time > @duration
      raise "animation track extends past the timeline duration"
    if !@scene.has_id?(track.target)
      raise "animation track target is not in the scene: " + track.target
    @tracks.each -> (existing)
      if existing.target == track.target && existing.property == track.property
        raise "animation timeline has duplicate target/property tracks"
    @tracks.push(track)
    self

  -> camera_track(track)
    if track.end_time > @duration
      raise "animation camera track extends past the timeline duration"
    track.keyframes.each -> (keyframe)
      if keyframe.value.class_name != "AnimationCamera2D"
        raise "animation camera tracks require AnimationCamera2D values"
    @camera_track = track
    self

  -> tracks
    PlotData.copy(@tracks)

  -> frame(index)
    time = time_at(index)
    updates = []
    @tracks.each -> (track)
      updates.push({
        :target => track.target,
        :property => track.property,
        :value => AnimationValue.data(track.value_at(time))
      })
    camera = @camera
    if @camera_track != nil
      camera = @camera_track.value_at(time)
    AnimationFrame.new(index, time, @scene, updates, camera)

  -> each_frame/&
    index = 0
    while index < frame_count
      &(frame(index))
      index += 1
    self

  -> to_data
    values = []
    @tracks.each -> (track) values.push(track.to_data)
    camera_data = @camera_track == nil ? nil : @camera_track.to_data
    {
      :schema => "tungsten.animation/v1",
      :duration => @duration,
      :fps => @fps,
      :frame_count => frame_count,
      :camera => @camera.to_data,
      :camera_track => camera_data,
      :tracks => values,
      :scene => @scene.to_data,
      :metadata => PlotData.copy(@metadata)
    }

  -> description
    to_data

  -> to_json
    JSON.encode(to_data)

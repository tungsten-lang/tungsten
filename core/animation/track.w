# A property track targets a Plot node id. Interpolation is :linear or :step;
# linear values may be numbers, nested numeric arrays, or AnimationCamera2D.

+ AnimationTrack
  -> new(target, property, keyframes, interpolation = :linear)
    @target = target.to_s()
    @property = property.to_s()
    if @target.size == 0 || @property.size == 0
      raise "animation track target and property must be nonempty"
    if keyframes.class_name != "Array" || keyframes.size == 0
      raise "animation track needs at least one keyframe"
    if interpolation != :linear && interpolation != :step
      raise "animation track interpolation must be linear or step"
    @interpolation = interpolation
    @keyframes = []
    previous = ~-1.0
    keyframes.each -> (keyframe)
      if keyframe.time <= previous
        raise "animation keyframe times must be strictly increasing"
      @keyframes.push(keyframe)
      previous = keyframe.time

  -> target
    @target

  -> property
    @property

  -> interpolation
    @interpolation

  -> keyframes
    PlotData.copy(@keyframes)

  -> start_time
    @keyframes[0].time

  -> end_time
    @keyframes[@keyframes.size - 1].time

  -> value_at(time)
    value_time = PlotData.number(time, "animation sample time")
    return @keyframes[0].value if value_time <= start_time
    return @keyframes[@keyframes.size - 1].value if value_time >= end_time
    index = 0
    while index + 1 < @keyframes.size
      left = @keyframes[index]
      right = @keyframes[index + 1]
      if value_time <= right.time
        return right.value if value_time == right.time
        return left.value if @interpolation == :step
        progress = (value_time - left.time) / (right.time - left.time)
        eased = AnimationValue.ease(left.easing, progress)
        return AnimationValue.interpolate(left.value, right.value, eased)
      index += 1
    @keyframes[@keyframes.size - 1].value

  -> to_data
    values = []
    @keyframes.each -> (keyframe) values.push(keyframe.to_data)
    {
      :target => @target,
      :property => @property,
      :interpolation => @interpolation,
      :keyframes => values
    }

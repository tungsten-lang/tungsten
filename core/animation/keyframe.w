# One value sample on an AnimationTrack. Easing controls the segment leaving
# this keyframe and is ignored for a track's final keyframe.

+ AnimationKeyframe
  -> new(time, value, easing = :linear)
    @time = PlotData.number(time, "keyframe time")
    raise "animation keyframe time must be nonnegative" if @time < ~0.0
    AnimationValue.ease(easing, ~0.5)
    @value = AnimationValue.copy(value)
    @easing = easing

  -> time
    @time

  -> value
    AnimationValue.copy(@value)

  -> easing
    @easing

  -> to_data
    {:time => @time, :value => AnimationValue.data(@value), :easing => @easing}

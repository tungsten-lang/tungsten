# Backend-neutral orthographic 2-D camera/view state.

+ AnimationCamera2D
  -> new(center = [~0.0, ~0.0], zoom = ~1.0, rotation = ~0.0)
    @center = PlotData.point(center, "camera center")
    @zoom = PlotData.number(zoom, "camera zoom")
    @rotation = PlotData.number(rotation, "camera rotation")
    raise "animation camera zoom must be positive" if @zoom <= ~0.0

  -> center
    PlotData.copy(@center)

  -> zoom
    @zoom

  -> rotation
    @rotation

  -> .interpolate(left, right, progress)
    center = AnimationValue.interpolate(left.center, right.center, progress)
    zoom = AnimationValue.interpolate(left.zoom, right.zoom, progress)
    rotation = AnimationValue.interpolate(left.rotation, right.rotation, progress)
    AnimationCamera2D.new(center, zoom, rotation)

  -> to_data
    {
      :kind => :orthographic_2d,
      :center => PlotData.copy(@center),
      :zoom => @zoom,
      :rotation => @rotation
    }

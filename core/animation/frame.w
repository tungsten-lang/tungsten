# One reproducible frame recipe: immutable base scene data plus ordered
# property updates and resolved camera state.

+ AnimationFrame
  -> new(@index, @time, @scene, updates, @camera)
    @updates = PlotData.copy(updates)

  -> index
    @index

  -> time
    @time

  -> camera
    @camera

  -> updates
    PlotData.copy(@updates)

  -> to_data
    {
      :schema => "tungsten.animation.frame/v1",
      :index => @index,
      :time => @time,
      :camera => @camera.to_data,
      :scene => @scene.to_data,
      :updates => PlotData.copy(@updates)
    }

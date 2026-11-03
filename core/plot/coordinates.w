# Cartesian data-to-geometry mapping. The frame is [left, bottom, width,
# height] in backend-neutral logical units; y increases upward.

+ PlotCoordinateSystem
  -> new(x_range, y_range, frame = [~0.0, ~0.0, ~1.0, ~1.0])
    @x_range = PlotData.range(x_range, "x range")
    @y_range = PlotData.range(y_range, "y range")
    if frame.class_name != "Array" || frame.size != 4
      raise "plot coordinate frame must be \[left, bottom, width, height\]"
    @frame = [
      PlotData.number(frame[0], "plot frame"),
      PlotData.number(frame[1], "plot frame"),
      PlotData.number(frame[2], "plot frame"),
      PlotData.number(frame[3], "plot frame")
    ]
    if @frame[2] <= ~0.0 || @frame[3] <= ~0.0
      raise "plot coordinate frame width and height must be positive"

  -> .identity(width = ~1.0, height = ~1.0)
    w = PlotData.number(width, "coordinate width")
    h = PlotData.number(height, "coordinate height")
    PlotCoordinateSystem.new([~0.0, w], [~0.0, h], [~0.0, ~0.0, w, h])

  -> x_range
    PlotData.copy(@x_range)

  -> y_range
    PlotData.copy(@y_range)

  -> frame
    PlotData.copy(@frame)

  -> map(point)
    value = PlotData.point(point)
    x = @frame[0] + (value[0] - @x_range[0]) * @frame[2] / (@x_range[1] - @x_range[0])
    y = @frame[1] + (value[1] - @y_range[0]) * @frame[3] / (@y_range[1] - @y_range[0])
    [x, y]

  -> point(x, y)
    map([x, y])

  -> unmap(point)
    value = PlotData.point(point)
    x = @x_range[0] + (value[0] - @frame[0]) * (@x_range[1] - @x_range[0]) / @frame[2]
    y = @y_range[0] + (value[1] - @frame[1]) * (@y_range[1] - @y_range[0]) / @frame[3]
    [x, y]

  -> map_vector(vector)
    value = PlotData.point(vector, "plot vector")
    [
      value[0] * @frame[2] / (@x_range[1] - @x_range[0]),
      value[1] * @frame[3] / (@y_range[1] - @y_range[0])
    ]

  -> to_data
    {
      :kind => :cartesian_2d,
      :x_range => PlotData.copy(@x_range),
      :y_range => PlotData.copy(@y_range),
      :frame => PlotData.copy(@frame)
    }

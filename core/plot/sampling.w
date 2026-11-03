# Deterministic sampling and facade constructors for mathematical plots.

+ Plot
  -> .scene(width = ~800.0, height = ~450.0, background = "#ffffff",
            coordinate_system = nil, metadata = nil)
    PlotScene.new(width, height, background, coordinate_system, metadata)

  -> .coordinates(x_range, y_range, frame = [~0.0, ~0.0, ~1.0, ~1.0])
    PlotCoordinateSystem.new(x_range, y_range, frame)

  -> .polyline(points, closed = false, id = nil, style = nil, metadata = nil)
    PlotPolyline.new(points, closed, id, style, metadata)

  -> .points(points, radius = ~3.0, id = nil, style = nil, metadata = nil)
    PlotPoints.new(points, radius, id, style, metadata)

  -> .arrow(start_point, end_point, id = nil, style = nil, metadata = nil)
    PlotArrow.new(start_point, end_point, id, style, metadata)

  -> .label(text, position, format = :plain, id = nil, style = nil, metadata = nil)
    PlotLabel.new(text, position, format, id, style, metadata)

  -> .axes(coordinate_system, x_step = nil, y_step = nil,
           x_label = nil, y_label = nil, id = nil, style = nil, metadata = nil)
    PlotAxes.new(coordinate_system, x_step, y_step, x_label, y_label,
                 id, style, metadata)

  -> .group(children, translate = [~0.0, ~0.0], scale = [~1.0, ~1.0],
            rotation = ~0.0, id = nil, style = nil, metadata = nil)
    PlotGroup.new(children, translate, scale, rotation, id, style, metadata)

  -> .function(callback, x_range, samples = 129, coordinate_system = nil,
               id = nil, style = nil, metadata = nil)
    range = PlotData.range(x_range, "function sample range")
    count = PlotData.positive_integer(samples, "function sample count")
    raise "function sample count must be at least two" if count < 2
    paths = []
    current = []
    index = 0
    while index < count
      x = range[0] + (range[1] - range[0]) * index.to_f() / (count - 1).to_f()
      y = callback(x)
      if PlotData.finite?(y)
        current.push([x, PlotData.number(y, "function sample")])
      elsif current.size > 0
        paths.push(current)
        current = []
      index += 1
    paths.push(current) if current.size > 0
    PlotSampledCurve.new(paths, coordinate_system, id, style, metadata)

  -> .curve(callback, parameter_range, samples = 129, coordinate_system = nil,
            id = nil, style = nil, metadata = nil)
    range = PlotData.range(parameter_range, "curve parameter range")
    count = PlotData.positive_integer(samples, "curve sample count")
    raise "curve sample count must be at least two" if count < 2
    paths = []
    current = []
    index = 0
    while index < count
      parameter = range[0] + (range[1] - range[0]) * index.to_f() / (count - 1).to_f()
      point = PlotData.point_or_nil(callback(parameter))
      if point != nil
        current.push(point)
      elsif current.size > 0
        paths.push(current)
        current = []
      index += 1
    paths.push(current) if current.size > 0
    PlotSampledCurve.new(paths, coordinate_system, id, style, metadata)

  -> .vector_field(callback, x_range, y_range, columns = 9, rows = 7,
                    scale = ~1.0, coordinate_system = nil,
                    id = nil, style = nil, metadata = nil)
    xr = PlotData.range(x_range, "vector field x range")
    yr = PlotData.range(y_range, "vector field y range")
    nx = PlotData.positive_integer(columns, "vector field columns", 200)
    ny = PlotData.positive_integer(rows, "vector field rows", 200)
    if nx < 2 || ny < 2
      raise "vector field needs at least two rows and columns"
    factor = PlotData.number(scale, "vector field scale")
    arrows = []
    row = 0
    while row < ny
      y = yr[0] + (yr[1] - yr[0]) * row.to_f() / (ny - 1).to_f()
      column = 0
      while column < nx
        x = xr[0] + (xr[1] - xr[0]) * column.to_f() / (nx - 1).to_f()
        vector = PlotData.point_or_nil(callback(x, y))
        if vector != nil
          arrows.push({
            :origin => [x, y],
            :vector => [vector[0] * factor, vector[1] * factor]
          })
        column += 1
      row += 1
    PlotVectorField.new(arrows, coordinate_system, id, style, metadata)

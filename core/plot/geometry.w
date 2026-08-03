# Retained plot nodes. Every node has a stable id, a portable PlotStyle, and a
# geometry description made only of standard value trees.

+ PlotNode
  -> new(id = nil, style = nil, metadata = nil)
    @id = id
    @style = style == nil ? PlotStyle.default : style
    @metadata = PlotData.metadata(metadata)
    assign_id(@id) if @id != nil && @id != ""

  -> id
    @id

  -> style
    @style

  -> metadata
    PlotData.copy(@metadata)

  -> assign_id(value)
    if value.class_name != "String" || value.size == 0
      raise "plot node id must be a nonempty String"
    @id = value
    self

  -> kind
    :node

  -> geometry_data
    {}

  -> contains_id?(value)
    @id == value

  -> to_data
    PlotData.node_data(@id, kind, @style, geometry_data, @metadata)


+ PlotPolyline < PlotNode
  -> new(points, closed = false, id = nil, style = nil, metadata = nil)
    @points = PlotData.points(points)
    if @points.size == 0
      raise "plot polyline needs at least one point"
    @closed = closed
    @id = id
    @style = style == nil ? PlotStyle.default : style
    @metadata = PlotData.metadata(metadata)

  -> id
    @id

  -> style
    @style

  -> metadata
    PlotData.copy(@metadata)

  -> assign_id(value)
    raise "plot node id must be a nonempty String" if value.class_name != "String" || value.size == 0
    @id = value
    self

  -> contains_id?(value)
    @id == value

  -> to_data
    PlotData.node_data(@id, kind, @style, geometry_data, @metadata)

  -> kind
    @closed ? :polygon : :polyline

  -> points
    PlotData.copy(@points)

  -> closed?
    @closed

  -> geometry_data
    {:points => PlotData.copy(@points), :closed => @closed}


+ PlotPoints < PlotNode
  -> new(points, radius = ~3.0, id = nil, style = nil, metadata = nil)
    @points = PlotData.points(points)
    @radius = PlotData.number(radius, "plot point radius")
    raise "plot point radius must be nonnegative" if @radius < ~0.0
    @id = id
    @style = style == nil ? PlotStyle.default : style
    @metadata = PlotData.metadata(metadata)

  -> id
    @id

  -> style
    @style

  -> metadata
    PlotData.copy(@metadata)

  -> assign_id(value)
    raise "plot node id must be a nonempty String" if value.class_name != "String" || value.size == 0
    @id = value
    self

  -> contains_id?(value)
    @id == value

  -> to_data
    PlotData.node_data(@id, kind, @style, geometry_data, @metadata)

  -> kind
    :points

  -> points
    PlotData.copy(@points)

  -> geometry_data
    {:points => PlotData.copy(@points), :radius => @radius}


+ PlotArrow < PlotNode
  -> new(start_point, end_point, id = nil, style = nil, metadata = nil)
    @start_point = PlotData.point(start_point, "arrow start")
    @end_point = PlotData.point(end_point, "arrow end")
    @id = id
    @style = style == nil ? PlotStyle.default : style
    @metadata = PlotData.metadata(metadata)

  -> id
    @id

  -> style
    @style

  -> metadata
    PlotData.copy(@metadata)

  -> assign_id(value)
    raise "plot node id must be a nonempty String" if value.class_name != "String" || value.size == 0
    @id = value
    self

  -> contains_id?(value)
    @id == value

  -> to_data
    PlotData.node_data(@id, kind, @style, geometry_data, @metadata)

  -> kind
    :arrow

  -> geometry_data
    {:start => PlotData.copy(@start_point), :end => PlotData.copy(@end_point)}


+ PlotLabel < PlotNode
  -> new(text, position, format = :plain, id = nil, style = nil, metadata = nil)
    if text.class_name != "String"
      raise "plot label text must be a String"
    if format != :plain && format != :math_source
      raise "plot label format must be plain or math_source"
    @text = text
    @position = PlotData.point(position, "label position")
    @format = format
    @id = id
    @style = style == nil ? PlotStyle.label : style
    @metadata = PlotData.metadata(metadata)

  -> id
    @id

  -> style
    @style

  -> metadata
    PlotData.copy(@metadata)

  -> assign_id(value)
    raise "plot node id must be a nonempty String" if value.class_name != "String" || value.size == 0
    @id = value
    self

  -> contains_id?(value)
    @id == value

  -> to_data
    PlotData.node_data(@id, kind, @style, geometry_data, @metadata)

  -> kind
    :label

  -> text
    @text

  -> format
    @format

  -> geometry_data
    {:position => PlotData.copy(@position), :text => @text, :format => @format}


+ PlotSampledCurve < PlotNode
  -> new(paths, coordinate_system = nil, id = nil, style = nil, metadata = nil)
    @paths = []
    paths.each -> (path)
      @paths.push(PlotData.points(path, "sampled curve path"))
    @coordinate_system = coordinate_system
    @id = id
    @style = style == nil ? PlotStyle.default : style
    @metadata = PlotData.metadata(metadata)

  -> id
    @id

  -> style
    @style

  -> metadata
    PlotData.copy(@metadata)

  -> assign_id(value)
    raise "plot node id must be a nonempty String" if value.class_name != "String" || value.size == 0
    @id = value
    self

  -> contains_id?(value)
    @id == value

  -> to_data
    PlotData.node_data(@id, kind, @style, geometry_data, @metadata)

  -> kind
    :sampled_curve

  -> paths
    PlotData.copy(@paths)

  -> geometry_paths
    return PlotData.copy(@paths) if @coordinate_system == nil
    out = []
    @paths.each -> (path)
      mapped = []
      path.each -> (point) mapped.push(@coordinate_system.map(point))
      out.push(mapped)
    out

  -> geometry_data
    data = {
      :paths => geometry_paths,
      :data_paths => PlotData.copy(@paths)
    }
    if @coordinate_system != nil
      data[:coordinate_system] = @coordinate_system.to_data
    data


+ PlotVectorField < PlotNode
  -> new(arrows, coordinate_system = nil, id = nil, style = nil, metadata = nil)
    @arrows = PlotData.copy(arrows)
    @coordinate_system = coordinate_system
    @id = id
    @style = style == nil ? PlotStyle.default : style
    @metadata = PlotData.metadata(metadata)

  -> id
    @id

  -> style
    @style

  -> metadata
    PlotData.copy(@metadata)

  -> assign_id(value)
    raise "plot node id must be a nonempty String" if value.class_name != "String" || value.size == 0
    @id = value
    self

  -> contains_id?(value)
    @id == value

  -> to_data
    PlotData.node_data(@id, kind, @style, geometry_data, @metadata)

  -> kind
    :vector_field

  -> arrows
    PlotData.copy(@arrows)

  -> geometry_data
    out = []
    @arrows.each -> (arrow)
      origin = arrow[:origin]
      vector = arrow[:vector]
      endpoint = [origin[0] + vector[0], origin[1] + vector[1]]
      start_geometry = origin
      end_geometry = endpoint
      if @coordinate_system != nil
        start_geometry = @coordinate_system.map(origin)
        end_geometry = @coordinate_system.map(endpoint)
      out.push({
        :origin => PlotData.copy(origin),
        :vector => PlotData.copy(vector),
        :start => PlotData.copy(start_geometry),
        :end => PlotData.copy(end_geometry)
      })
    data = {:arrows => out}
    if @coordinate_system != nil
      data[:coordinate_system] = @coordinate_system.to_data
    data


+ PlotAxes < PlotNode
  -> new(coordinate_system, x_step = nil, y_step = nil,
         x_label = nil, y_label = nil, id = nil, style = nil, metadata = nil)
    @coordinate_system = coordinate_system
    @x_step = x_step
    @y_step = y_step
    @x_label = x_label
    @y_label = y_label
    @id = id
    @style = style == nil ? PlotStyle.axes : style
    @metadata = PlotData.metadata(metadata)

  -> id
    @id

  -> style
    @style

  -> metadata
    PlotData.copy(@metadata)

  -> assign_id(value)
    raise "plot node id must be a nonempty String" if value.class_name != "String" || value.size == 0
    @id = value
    self

  -> contains_id?(value)
    @id == value

  -> to_data
    PlotData.node_data(@id, kind, @style, geometry_data, @metadata)

  -> kind
    :axes

  -> tick_data(range, step, orientation)
    out = []
    PlotData.ticks(range, step).each -> (value)
      data_point = orientation == :x ? [value, ~0.0] : [~0.0, value]
      out.push({:value => value, :position => @coordinate_system.map(data_point)})
    out

  -> geometry_data
    xr = @coordinate_system.x_range
    yr = @coordinate_system.y_range
    x_axis = nil
    y_axis = nil
    x_ticks = []
    y_ticks = []
    if yr[0] <= ~0.0 && yr[1] >= ~0.0
      x_axis = [@coordinate_system.map([xr[0], ~0.0]),
                @coordinate_system.map([xr[1], ~0.0])]
      x_ticks = tick_data(xr, @x_step, :x)
    if xr[0] <= ~0.0 && xr[1] >= ~0.0
      y_axis = [@coordinate_system.map([~0.0, yr[0]]),
                @coordinate_system.map([~0.0, yr[1]])]
      y_ticks = tick_data(yr, @y_step, :y)
    {
      :x_axis => x_axis,
      :y_axis => y_axis,
      :x_ticks => x_ticks,
      :y_ticks => y_ticks,
      :x_label => @x_label,
      :y_label => @y_label,
      :coordinate_system => @coordinate_system.to_data
    }


+ PlotGroup < PlotNode
  -> new(children, translate = [~0.0, ~0.0], scale = [~1.0, ~1.0],
         rotation = ~0.0, id = nil, style = nil, metadata = nil)
    if children.class_name != "Array"
      raise "plot group children must be an Array"
    @children = PlotData.copy(children)
    @translate = PlotData.point(translate, "group translation")
    @scale = PlotData.point(scale, "group scale")
    @rotation = PlotData.number(rotation, "group rotation")
    @id = id
    @style = style == nil ? PlotStyle.default : style
    @metadata = PlotData.metadata(metadata)
    assign_id(@id) if @id != nil && @id != ""

  -> id
    @id

  -> style
    @style

  -> metadata
    PlotData.copy(@metadata)

  -> to_data
    PlotData.node_data(@id, kind, @style, geometry_data, @metadata)

  -> kind
    :group

  -> children
    PlotData.copy(@children)

  -> assign_id(value)
    if value.class_name != "String" || value.size == 0
      raise "plot node id must be a nonempty String"
    @id = value
    index = 0
    while index < @children.size
      child = @children[index]
      if child.id == nil || child.id == ""
        child.assign_id(value + "/node-" + index.to_s())
      index += 1
    self

  -> contains_id?(value)
    return true if @id == value
    index = 0
    while index < @children.size
      return true if @children[index].contains_id?(value)
      index += 1
    false

  -> geometry_data
    values = []
    index = 0
    while index < @children.size
      values.push(@children[index].to_data)
      index += 1
    {
      :transform => {
        :translate => PlotData.copy(@translate),
        :scale => PlotData.copy(@scale),
        :rotation => @rotation
      },
      :children => values
    }

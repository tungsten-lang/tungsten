# PlotScene — retained, ordered composition of declarative plot nodes.

use core/json

+ PlotScene
  -> new(width = ~800.0, height = ~450.0, background = "#ffffff",
         coordinate_system = nil, metadata = nil)
    @width = PlotData.number(width, "scene width")
    @height = PlotData.number(height, "scene height")
    if @width <= ~0.0 || @height <= ~0.0
      raise "plot scene width and height must be positive"
    if background != nil && background.class_name != "String"
      raise "plot scene background must be a String or nil"
    @background = background
    @coordinate_system = coordinate_system
    if @coordinate_system == nil
      @coordinate_system = PlotCoordinateSystem.identity(@width, @height)
    @metadata = PlotData.metadata(metadata)
    @nodes = []

  -> width
    @width

  -> height
    @height

  -> coordinate_system
    @coordinate_system

  -> nodes
    PlotData.copy(@nodes)

  -> add(node)
    if node.id == nil || node.id == ""
      node.assign_id("node-" + @nodes.size.to_s())
    ids = PlotData.node_ids(node)
    seen = {}
    index = 0
    while index < ids.size
      id = ids[index]
      if id == nil || id == ""
        raise "every plot node must have an id after scene insertion"
      if seen[id] == true || has_id?(id)
        raise "plot scene node ids must be unique: " + id
      seen[id] = true
      index += 1
    @nodes.push(node)
    self

  -> push(node)
    add(node)

  -> has_id?(value)
    index = 0
    while index < @nodes.size
      return true if @nodes[index].contains_id?(value)
      index += 1
    false

  -> node(value)
    index = 0
    while index < @nodes.size
      candidate = PlotData.find_node(@nodes[index], value)
      return candidate if candidate != nil
      index += 1
    nil

  -> to_data
    values = []
    index = 0
    while index < @nodes.size
      values.push(@nodes[index].to_data)
      index += 1
    {
      :schema => "tungsten.plot/v1",
      :viewport => {
        :width => @width,
        :height => @height,
        :background => @background
      },
      :coordinate_system => @coordinate_system.to_data,
      :nodes => values,
      :metadata => PlotData.copy(@metadata)
    }

  -> to_json
    JSON.encode(to_data)

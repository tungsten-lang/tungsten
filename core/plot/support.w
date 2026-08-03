# Shared validation and portable-value helpers for declarative plots.

+ PlotData
  -> .number(value, context = "plot number")
    number = value + ~0.0
    if number.nan?() || number.infinite?()
      raise context + " must be finite"
    number

  -> .finite?(value)
    begin
      number = value + ~0.0
      return !number.nan?() && !number.infinite?()
    rescue error
      false

  # Plot geometry uses the same plain two-element coordinate arrays used by
  # Chart, Solve, and tungsten-drawille. Vec2 and other x/y value objects are
  # accepted at the boundary and normalized to that portable representation.
  -> .point(value, context = "plot point")
    if value.class_name == "Array"
      if value.size != 2
        raise context + " must have exactly two coordinates"
      return [number(value[0], context), number(value[1], context)]
    if value.respond_to?("x") && value.respond_to?("y")
      return [number(value.x, context), number(value.y, context)]
    raise context + " must be a two-element Array or x/y vector"

  -> .point_or_nil(value)
    if value.class_name == "Array"
      if value.size != 2
        raise "plot point must have exactly two coordinates"
      return nil if !finite?(value[0]) || !finite?(value[1])
      return point(value)
    if value.respond_to?("x") && value.respond_to?("y")
      return nil if !finite?(value.x) || !finite?(value.y)
      return point(value)
    raise "plot point must be a two-element Array or x/y vector"

  -> .points(values, context = "plot points")
    if values.class_name != "Array"
      raise context + " must be an Array"
    out = []
    values.each -> (value)
      out.push(point(value, context))
    out

  -> .range(value, context = "plot range")
    if value.class_name != "Array" || value.size != 2
      raise context + " must be a two-element Array"
    lower = number(value[0], context)
    upper = number(value[1], context)
    if upper <= lower
      raise context + " upper bound must be greater than lower bound"
    [lower, upper]

  -> .copy(value)
    if value.class_name == "Array"
      out = []
      index = 0
      while index < value.size
        out.push(copy(value[index]))
        index += 1
      return out
    if value.class_name == "Hash"
      out = {}
      keys = value.keys
      index = 0
      while index < keys.size
        key = keys[index]
        out[key] = copy(value[key])
        index += 1
      return out
    value

  -> .metadata(value)
    return {} if value == nil
    if value.class_name != "Hash"
      raise "plot metadata must be a Hash"
    copy(value)

  -> .positive_integer(value, context, maximum = 100_000)
    integer = value.to_i()
    if integer != value || integer <= 0 || integer > maximum
      raise context + " must be a positive integer at most " + maximum.to_s()
    integer

  -> .ticks(range, step = nil)
    span = range[1] - range[0]
    spacing = step == nil ? span / ~5.0 : number(step, "tick step")
    if spacing <= ~0.0
      raise "tick step must be positive"
    first = Math.ceil(range[0] / spacing).to_i()
    last = Math.floor(range[1] / spacing).to_i()
    if last - first > 1000
      raise "tick step produces more than 1001 ticks"
    out = []
    index = first
    while index <= last
      value = index.to_f() * spacing
      value = ~0.0 if value == ~-0.0
      out.push(value)
      index += 1
    out

  -> .node_data(id, kind, style, geometry, metadata)
    {
      :id => id,
      :kind => kind,
      :style => style.to_data,
      :geometry => geometry,
      :metadata => copy(metadata)
    }

  -> .node_ids(node)
    out = [node.id]
    if node.kind == :group
      children = node.children
      index = 0
      while index < children.size
        child_ids = node_ids(children[index])
        child_index = 0
        while child_index < child_ids.size
          out.push(child_ids[child_index])
          child_index += 1
        index += 1
    out

  -> .find_node(node, id)
    return node if node.id == id
    if node.kind == :group
      children = node.children
      index = 0
      while index < children.size
        found = find_node(children[index], id)
        return found if found != nil
        index += 1
    nil

# Deterministic logical layout helpers. Layout creates transform groups; it
# never depends on font metrics or a renderer's pixel measurements.

+ PlotLayout
  -> .grid(nodes, columns, cell_width = ~1.0, cell_height = ~1.0,
           gap_x = ~0.1, gap_y = ~0.1, id = nil)
    if nodes.class_name != "Array"
      raise "plot grid nodes must be an Array"
    count = PlotData.positive_integer(columns, "plot grid columns", 10_000)
    width = PlotData.number(cell_width, "plot grid cell width")
    height = PlotData.number(cell_height, "plot grid cell height")
    gx = PlotData.number(gap_x, "plot grid horizontal gap")
    gy = PlotData.number(gap_y, "plot grid vertical gap")
    if width <= ~0.0 || height <= ~0.0 || gx < ~0.0 || gy < ~0.0
      raise "plot grid cells must be positive and gaps nonnegative"
    children = []
    index = 0
    while index < nodes.size
      column = index % count
      row = index / count
      translation = [column.to_f() * (width + gx),
                     ~0.0 - row.to_f() * (height + gy)]
      children.push(PlotGroup.new([nodes[index]], translation))
      index += 1
    PlotGroup.new(children, [~0.0, ~0.0], [~1.0, ~1.0], ~0.0, id)

  -> .horizontal(nodes, gap = ~0.1, cell_width = ~1.0, id = nil)
    grid(nodes, nodes.size == 0 ? 1 : nodes.size, cell_width, ~1.0, gap, ~0.0, id)

  -> .vertical(nodes, gap = ~0.1, cell_height = ~1.0, id = nil)
    grid(nodes, 1, ~1.0, cell_height, ~0.0, gap, id)

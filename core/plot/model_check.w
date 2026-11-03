# Declarative, already-realized statistical model-check plots. This layer
# records caller-declared comparability and provenance; it does not run a model
# or establish that the chosen check is statistically valid.

+ PlotModelCheck
  -> new(observed_points, model_draws, quantity_id, scale_id, provenance,
         mode = :superpose, options = nil)
    @observed_points = validated_polyline(
      observed_points, "observed model-check polyline")
    if model_draws.class_name != "Array" || model_draws.size == 0
      raise "model-check draws must be a nonempty Array"
    @model_draws = []
    draw_index = 0
    while draw_index < model_draws.size
      @model_draws.push(validated_polyline(
        model_draws[draw_index], "model-check draw " + draw_index.to_s()))
      draw_index += 1

    if quantity_id.class_name != "String" || quantity_id.size == 0
      raise "model-check quantity id must be a nonempty String"
    if scale_id.class_name != "String" || scale_id.size == 0
      raise "model-check scale id must be a nonempty String"
    @quantity_id = quantity_id
    @scale_id = scale_id
    if mode != :superpose && mode != :animate
      raise "model-check mode must be superpose or animate"
    @mode = mode

    @provenance = PlotData.portable(
      PlotData.metadata(provenance), "model-check provenance")
    validate_provenance(@provenance)
    resolved = validated_options(options)
    @id = resolved[:id]
    @units = resolved[:units]
    @coordinate_system = resolved[:coordinate_system]
    @metadata = PlotData.portable(
      PlotData.metadata(resolved[:metadata]), "model-check metadata")
    @observed_style = resolved[:observed_style]
    @draw_style = resolved[:draw_style]

    @geometry_observed = map_points(@observed_points)
    @geometry_draws = []
    draw_index = 0
    while draw_index < @model_draws.size
      @geometry_draws.push(map_points(@model_draws[draw_index]))
      draw_index += 1

  -> validated_polyline(points, context)
    values = PlotData.points(points, context)
    if values.size < 2
      raise context + " needs at least two points"
    values

  -> validate_provenance(value)
    observed_id = value[:observed_transform_id]
    draw_id = value[:draw_source_id]
    if observed_id.class_name != "String" || observed_id.size == 0
      raise "model-check provenance needs a nonempty observed_transform_id String"
    if draw_id.class_name != "String" || draw_id.size == 0
      raise "model-check provenance needs a nonempty draw_source_id String"

  -> validated_options(options)
    values = options == nil ? {} : options
    if values.class_name != "Hash"
      raise "model-check options must be a Hash or nil"
    allowed = [
      :id, :units, :coordinate_system, :observed_style,
      :draw_style, :metadata
    ]
    keys = values.keys
    index = 0
    while index < keys.size
      if !allowed.include?(keys[index])
        raise "unknown model-check option: " + keys[index].to_s()
      index += 1

    id = values.has_key?(:id) ? values[:id] : "model-check"
    if id.class_name != "String" || id.size == 0
      raise "model-check id must be a nonempty String"
    units = values[:units]
    if units != nil && (units.class_name != "String" || units.size == 0)
      raise "model-check units must be a nonempty String or nil"
    coordinates = values[:coordinate_system]
    if coordinates != nil && coordinates.class_name != "PlotCoordinateSystem"
      raise "model-check coordinate_system must be PlotCoordinateSystem or nil"
    observed_style = values[:observed_style]
    if observed_style != nil && observed_style.class_name != "PlotStyle"
      raise "model-check observed_style must be PlotStyle or nil"
    draw_style = values[:draw_style]
    if draw_style != nil && draw_style.class_name != "PlotStyle"
      raise "model-check draw_style must be PlotStyle or nil"
    observed_style = PlotStyle.new("#20242b", nil, ~2.0) if observed_style == nil
    if draw_style == nil
      opacity = @mode == :superpose ? ~0.35 : ~1.0
      draw_style = PlotStyle.new("#5b5bd6", nil, ~1.5, opacity)
    {
      :id => id,
      :units => units,
      :coordinate_system => coordinates,
      :observed_style => observed_style,
      :draw_style => draw_style,
      :metadata => values[:metadata]
    }

  -> map_points(points)
    return PlotData.copy(points) if @coordinate_system == nil
    out = []
    index = 0
    while index < points.size
      out.push(@coordinate_system.map(points[index]))
      index += 1
    out

  -> node_metadata(role, draw_index = nil)
    values = {
      :role => role,
      :quantity_id => @quantity_id,
      :scale_id => @scale_id,
      :units => @units
    }
    values[:draw_index] = draw_index if draw_index != nil
    values

  -> build_node
    children = []
    children.push(Plot.polyline(
      @geometry_observed, false, @id + "/observed", @observed_style,
      node_metadata(:observed)))
    if @mode == :superpose
      draw_index = 0
      while draw_index < @geometry_draws.size
        children.push(Plot.polyline(
          @geometry_draws[draw_index], false,
          @id + "/draw-" + draw_index.to_s(), @draw_style,
          node_metadata(:model_draw, draw_index)))
        draw_index += 1
    else
      children.push(Plot.polyline(
        @geometry_draws[0], false, @id + "/model-draw", @draw_style,
        node_metadata(:model_draw, 0)))
    Plot.group(children, [~0.0, ~0.0], [~1.0, ~1.0], ~0.0, @id, nil, {
      :model_check => description
    })

  -> id
    @id

  -> mode
    @mode

  -> quantity_id
    @quantity_id

  -> scale_id
    @scale_id

  -> units
    @units

  -> provenance
    PlotData.copy(@provenance)

  -> metadata
    PlotData.copy(@metadata)

  -> observed_points
    PlotData.copy(@observed_points)

  -> model_draws
    PlotData.copy(@model_draws)

  -> geometry_observed
    PlotData.copy(@geometry_observed)

  -> geometry_draws
    PlotData.copy(@geometry_draws)

  -> draw_count
    @model_draws.size

  -> node
    build_node

  -> add_to(scene)
    scene.add(build_node)
    self

  -> observed_id
    @id + "/observed"

  -> animated_target_id
    @mode == :animate ? @id + "/model-draw" : nil

  -> description
    {
      :schema => "tungsten.plot.model-check-summary/v1",
      :id => @id,
      :quantity_id => @quantity_id,
      :scale_id => @scale_id,
      :units => @units,
      :mode => @mode,
      :draw_count => @model_draws.size,
      :draw_order => :input,
      :statistical_validity => :not_assessed,
      :provenance => PlotData.copy(@provenance),
      :metadata => PlotData.copy(@metadata)
    }

  -> to_data
    values = description
    values[:schema] = "tungsten.plot.model-check/v1"
    values[:observed_points] = PlotData.copy(@observed_points)
    values[:model_draws] = PlotData.copy(@model_draws)
    values[:coordinate_system] = @coordinate_system == nil ? nil : @coordinate_system.to_data
    values[:node] = build_node.to_data
    values

  -> to_json
    JSON.encode(to_data)


+ Plot
  -> .model_check(observed_points, model_draws, quantity_id, scale_id,
                  provenance, mode = :superpose, options = nil)
    PlotModelCheck.new(
      observed_points, model_draws, quantity_id, scale_id,
      provenance, mode, options)

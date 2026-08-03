# Declarative plot foundation. Run in both engines:
#   bin/tungsten run spec/core/plot_scene_spec.w
#   bin/tungsten compile spec/core/plot_scene_spec.w --out /tmp/plot-scene-spec

use core/plot

-> plot_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> plot_close?(left, right, tolerance = ~1.0e-12)
  difference = left - right
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

-> plot_point_close?(point, x, y, tolerance = ~1.0e-12)
  return false if point.size != 2
  plot_close?(point[0], x, tolerance) && plot_close?(point[1], y, tolerance)

# Data coordinates map to logical geometry and invert without renderer state.
coordinates = Plot.coordinates(
  [~-2.0, ~2.0], [~-1.0, ~3.0], [~10.0, ~20.0, ~400.0, ~200.0])
mapped = coordinates.map([~0.0, ~1.0])
plot_check("coordinates.map", plot_point_close?(mapped, ~210.0, ~120.0))
unmapped = coordinates.unmap(mapped)
plot_check("coordinates.unmap",
           plot_close?(unmapped[0], ~0.0) && plot_close?(unmapped[1], ~1.0))

# Existing x/y vector-like values are accepted at the boundary, then normalized
# to the portable pair representation used throughout Core geometry.
+ PlotSpecPoint
  -> new(@x, @y)
  -> x
    @x
  -> y
    @y

vector_point = PlotSpecPoint.new(~1.0, ~2.0)
plot_check("coordinates.xy_value",
           plot_point_close?(coordinates.map(vector_point), ~310.0, ~170.0))

# Uniform function and parametric sampling include both endpoints exactly.
quadratic_function = -> (x) x * x
quadratic = Plot.function(
  quadratic_function, [~-2.0, ~2.0], 5, coordinates, "quadratic")
plot_check("function.path_count", quadratic.paths.size == 1)
plot_check("function.sample_count", quadratic.paths[0].size == 5)
left_endpoint = plot_point_close?(quadratic.paths[0][0], ~-2.0, ~4.0)
right_endpoint = plot_point_close?(quadratic.paths[0][4], ~2.0, ~4.0)
plot_check("function.endpoints", left_endpoint && right_endpoint)
plot_check("function.geometry_mapping",
           plot_point_close?(
             quadratic.geometry_data[:paths][0][2], ~210.0, ~70.0))

semicircle_function = -> (t) [Math.cos(t), Math.sin(t)]
circle = Plot.curve(
  semicircle_function, [~0.0, ~3.141592653589793], 3, nil, "semicircle")
plot_check("curve.samples", circle.paths[0].size == 3)
plot_check("curve.start", plot_close?(circle.paths[0][0][0], ~1.0))

# Vector fields retain source vectors and expose mapped arrow geometry.
rotation_field = -> (x, y) [~0.0 - y, x]
field = Plot.vector_field(
  rotation_field, [~-1.0, ~1.0], [~-1.0, ~1.0], 3, 2, ~0.25,
  coordinates, "rotation-field")
plot_check("vector_field.count", field.arrows.size == 6)
first_arrow = field.geometry_data[:arrows][0]
plot_check("vector_field.source",
           plot_point_close?(first_arrow[:origin], ~-1.0, ~-1.0))
plot_check("vector_field.scaled",
           plot_point_close?(first_arrow[:vector], ~0.25, ~-0.25))

# Axes/ticks and labels remain declarative geometry, with math_source carried
# as inert source text rather than invoking TeX.
axes = Plot.axes(coordinates, ~1.0, ~1.0, "x", "f(x)", "axes")
axes_data = axes.geometry_data
plot_check("axes.x_ticks", axes_data[:x_ticks].size == 5)
plot_check("axes.y_ticks", axes_data[:y_ticks].size == 5)
label = Plot.label("x^2", [~210.0, ~190.0], :math_source, "formula")
plot_check("label.math_source", label.geometry_data[:format] == :math_source)

# Scene insertion order is the layer order; omitted ids are assigned from that
# order and JSON encoding is byte-stable for the same value tree.
scene = Plot.scene(~800.0, ~450.0, "#ffffff", coordinates,
                   {:title => "Quadratic and rotational field"})
scene.add(axes).add(quadratic).add(field).add(label)
auto = Plot.points([[~0.0, ~0.0]])
scene.add(auto)
plot_check("scene.auto_id", auto.id == "node-4")
plot_check("scene.lookup", scene.has_id?("quadratic"))
plot_check("scene.schema", scene.to_data[:schema] == "tungsten.plot/v1")
plot_check("scene.layer_order", scene.to_data[:nodes][1][:id] == "quadratic")
plot_check("scene.json_deterministic", scene.to_json == scene.to_json)
plot_check("scene.json_schema", scene.to_json.include?("tungsten.plot/v1"))

# Logical layout composes ordinary scene nodes with explicit transforms.
layout = PlotLayout.grid([
  Plot.polyline([[~0.0, ~0.0], [~1.0, ~1.0]]),
  Plot.polyline([[~0.0, ~1.0], [~1.0, ~0.0]])
], 2, ~2.0, ~1.0, ~0.5, ~0.25, "grid")
layout_data = layout.geometry_data
plot_check("layout.children", layout_data[:children].size == 2)
plot_check("layout.offset",
           plot_point_close?(
             layout_data[:children][1][:geometry][:transform][:translate],
             ~2.5, ~0.0))
layout_scene = Plot.scene()
layout_scene.add(layout)
plot_check("layout.nested_lookup", layout_scene.node("grid/node-1") != nil)

duplicate_nested = false
begin
  layout_scene.add(Plot.polyline(
    [[~0.0, ~0.0], [~1.0, ~0.0]], false, "grid/node-1"))
rescue error
  duplicate_nested = error.to_s.include?("ids must be unique")
plot_check("layout.nested_id_validation", duplicate_nested)

# Existing terminal helpers remain source-compatible.
plot_check("terminal.sparkline", Plot.sparkline([~1.0, ~2.0, ~3.0]).size == 3)

invalid_range = false
begin
  Plot.coordinates([~1.0, ~1.0], [~0.0, ~1.0])
rescue error
  invalid_range = error.to_s.include?("upper bound")
plot_check("validation.range", invalid_range)

<< "plot_scene_spec: all checks passed"

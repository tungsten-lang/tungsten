# Declarative realized-data model-check plots. Run in both engines:
#   bin/tungsten run spec/core/plot_model_check_spec.w
#   bin/tungsten compile spec/core/plot_model_check_spec.w \
#     --out /tmp/plot-model-check-spec
#   /tmp/plot-model-check-spec

use core/plot

-> model_check_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> model_check_close?(left, right, tolerance = ~1.0e-12)
  difference = left - right
  difference = ~0.0 - difference if difference < ~0.0
  difference <= tolerance

-> model_check_point_close?(point, x, y, tolerance = ~1.0e-12)
  return false if point.size != 2
  x_close = model_check_close?(point[0], x, tolerance)
  y_close = model_check_close?(point[1], y, tolerance)
  x_close && y_close

-> model_check_observed
  [[~0.0, ~0.0], [~1.0, ~1.0], [~2.0, ~0.0]]

-> model_check_draws
  [
    [[~0.0, ~0.25], [~1.0, ~0.75], [~2.0, ~0.25]],
    [[~0.0, ~-0.25], [~1.0, ~1.25], [~2.0, ~-0.25]]
  ]

-> model_check_provenance
  {
    :observed_transform_id => "identity",
    :draw_source_id => "external-posterior-predictive",
    :seed => 17,
    :source => {:uri => "memory://fixture"}
  }


# A superposed check retains semantic declarations, caller metadata, input
# ordering, raw values, and explicitly styled ordinary plot nodes.
coordinates = Plot.coordinates(
  [~0.0, ~2.0], [~-1.0, ~2.0], [~10.0, ~20.0, ~200.0, ~120.0])
observed_style = PlotStyle.new("#111111", nil, ~3.0, ~0.9)
draw_style = PlotStyle.new("#3366cc", nil, ~1.25, ~0.4, [~2.0, ~1.0])
superposed = Plot.model_check(
  model_check_observed(), model_check_draws(),
  "posterior-predictive-curve", "shared-linear-y",
  model_check_provenance(), :superpose, {
    :id => "posterior-check",
    :units => "meters",
    :coordinate_system => coordinates,
    :observed_style => observed_style,
    :draw_style => draw_style,
    :metadata => {:title => "Posterior predictive check", :replicate => 2}
  })

description = superposed.description
model_check_check("description.schema",
                  description[:schema] ==
                  "tungsten.plot.model-check-summary/v1")
quantity_ok = description[:quantity_id] == "posterior-predictive-curve"
scale_ok = description[:scale_id] == "shared-linear-y"
units_ok = description[:units] == "meters"
model_check_check("description.semantics", quantity_ok && scale_ok && units_ok)
observed_provenance_ok = description[:provenance][:observed_transform_id] == "identity"
draw_provenance_ok = description[:provenance][:draw_source_id] == "external-posterior-predictive"
seed_provenance_ok = description[:provenance][:seed] == 17
provenance_ids_ok = observed_provenance_ok && draw_provenance_ok
model_check_check("description.provenance",
                  provenance_ids_ok && seed_provenance_ok)
model_check_check("description.scope",
                  description[:statistical_validity] == :not_assessed)
metadata_title_ok = description[:metadata][:title] == "Posterior predictive check"
model_check_check("description.metadata", metadata_title_ok)
order_ok = description[:draw_order] == :input
count_ok = description[:draw_count] == 2
model_check_check("description.draw_order", order_ok && count_ok)
data_schema_ok = superposed.to_data[:schema] == "tungsten.plot.model-check/v1"
model_check_check("data.schema", data_schema_ok)
model_check_check("data.json", superposed.to_json.include?(
                  "tungsten.plot.model-check/v1"))

ordered_draws = superposed.model_draws
model_check_check("draw_order.first",
                  ordered_draws[0][1][1] == ~0.75)
model_check_check("draw_order.second",
                  ordered_draws[1][1][1] == ~1.25)
model_check_check("raw.observed",
                  model_check_point_close?(
                    superposed.observed_points[0], ~0.0, ~0.0))
model_check_check("raw.draw",
                  model_check_point_close?(
                    superposed.to_data[:model_draws][0][0], ~0.0, ~0.25))

# The coordinate system changes derived geometry, while to_data retains the
# original data-space points and the coordinate-system description.
model_check_check("mapping.observed",
                  model_check_point_close?(
                    superposed.geometry_observed[0], ~10.0, ~60.0))
model_check_check("mapping.draw",
                  model_check_point_close?(
                    superposed.geometry_draws[0][0], ~10.0, ~70.0))
model_check_check("mapping.raw_retained",
                  model_check_point_close?(
                    superposed.to_data[:observed_points][0], ~0.0, ~0.0))
mapping_kind_ok = superposed.to_data[:coordinate_system][:kind] == :cartesian_2d
model_check_check("mapping.description", mapping_kind_ok)

scene = Plot.scene(~640.0, ~360.0)
returned_check = superposed.add_to(scene)
model_check_check("superpose.add_to", returned_check == superposed)
model_check_check("superpose.group_id", scene.has_id?("posterior-check"))
model_check_check("superpose.observed_id",
                  scene.has_id?("posterior-check/observed"))
first_draw_id_ok = scene.has_id?("posterior-check/draw-0")
second_draw_id_ok = scene.has_id?("posterior-check/draw-1")
model_check_check("superpose.draw_ids", first_draw_id_ok && second_draw_id_ok)
model_check_check("superpose.no_animated_target",
                  superposed.animated_target_id == nil)
model_check_check("superpose.group_kind", superposed.node.kind == :group)
first_layer_ok = superposed.node.children[1].id == "posterior-check/draw-0"
second_layer_ok = superposed.node.children[2].id == "posterior-check/draw-1"
model_check_check("superpose.layer_order", first_layer_ok && second_layer_ok)
model_check_check("superpose.draw_metadata",
                  scene.node("posterior-check/draw-1").metadata[:draw_index] == 1)
observed_node_style = scene.node("posterior-check/observed").style
observed_color_ok = observed_node_style.stroke == "#111111"
observed_width_ok = observed_node_style.stroke_width == ~3.0
model_check_check("options.observed_style", observed_color_ok && observed_width_ok)
draw_node_style = scene.node("posterior-check/draw-0").style
draw_color_ok = draw_node_style.stroke == "#3366cc"
draw_opacity_ok = draw_node_style.opacity == ~0.4
draw_dash_ok = draw_node_style.dash[0] == ~2.0
model_check_check("options.draw_style",
                  draw_color_ok && draw_opacity_ok && draw_dash_ok)

# Animate mode compiles only the observed and initial draw nodes, with an
# explicit target id. Its default draw style is opaque rather than the
# translucent superposition default.
animated = Plot.model_check(
  model_check_observed(), model_check_draws(), "q", "s",
  model_check_provenance(), :animate, {:id => "animated-check"})
animated.add_to(scene)
model_check_check("animate.composition", scene.nodes.size == 2)
animate_group_ok = scene.has_id?("animated-check")
animate_observed_ok = scene.has_id?("animated-check/observed")
animate_draw_ok = scene.has_id?("animated-check/model-draw")
model_check_check("animate.ids",
                  animate_group_ok && animate_observed_ok && animate_draw_ok)
model_check_check("animate.no_draw_series_nodes",
                  !scene.has_id?("animated-check/draw-0"))
model_check_check("animate.target",
                  animated.animated_target_id == "animated-check/model-draw")
model_check_check("animate.initial_draw",
                  model_check_point_close?(
                    scene.node(animated.animated_target_id).points[1],
                    ~1.0, ~0.75))
model_check_check("animate.default_style",
                  scene.node(animated.animated_target_id).style.opacity == ~1.0)
default_superposed = Plot.model_check(
  model_check_observed(), model_check_draws(), "q", "s",
  model_check_provenance())
model_check_check("superpose.default_style",
                  default_superposed.node.children[1].style.opacity == ~0.35)

# Constructor inputs and returned portable values are copied deeply enough for
# caller mutation not to rewrite the retained declaration.
copy_observed = model_check_observed()
copy_draws = model_check_draws()
copy_provenance = model_check_provenance()
copy_metadata = {:title => "original", :nested => {:value => 7}}
copied = Plot.model_check(
  copy_observed, copy_draws, "copy-q", "copy-s", copy_provenance,
  :superpose, {:id => "copy-check", :metadata => copy_metadata})
copy_observed[0][0] = ~99.0
copy_draws[0][1][1] = ~99.0
copy_provenance[:seed] = 99
copy_provenance[:source][:uri] = "changed"
copy_metadata[:title] = "changed"
copy_metadata[:nested][:value] = 99
constructor_observed_ok = copied.observed_points[0][0] == ~0.0
constructor_draw_ok = copied.model_draws[0][1][1] == ~0.75
model_check_check("copies.constructor_points",
                  constructor_observed_ok && constructor_draw_ok)
constructor_seed_ok = copied.provenance[:seed] == 17
constructor_source_ok = copied.provenance[:source][:uri] == "memory://fixture"
model_check_check("copies.constructor_provenance",
                  constructor_seed_ok && constructor_source_ok)
constructor_title_ok = copied.metadata[:title] == "original"
constructor_nested_ok = copied.metadata[:nested][:value] == 7
model_check_check("copies.constructor_metadata",
                  constructor_title_ok && constructor_nested_ok)

observed_copy = copied.observed_points
draw_copy = copied.model_draws
provenance_copy = copied.provenance
metadata_copy = copied.metadata
data_copy = copied.to_data
observed_copy[0][0] = ~88.0
draw_copy[0][1][1] = ~88.0
provenance_copy[:source][:uri] = "getter-changed"
metadata_copy[:nested][:value] = 88
data_copy[:observed_points][0][0] = ~88.0
getter_observed_ok = copied.observed_points[0][0] == ~0.0
getter_draw_ok = copied.model_draws[0][1][1] == ~0.75
getter_source_ok = copied.provenance[:source][:uri] == "memory://fixture"
getter_metadata_ok = copied.metadata[:nested][:value] == 7
getter_points_ok = getter_observed_ok && getter_draw_ok
getter_values_ok = getter_source_ok && getter_metadata_ok
model_check_check("copies.getters", getter_points_ok && getter_values_ok)
model_check_check("copies.to_data",
                  copied.to_data[:observed_points][0][0] == ~0.0)

# Each access/insertion builds an independent ordinary group. Mutating one
# returned PlotNode follows normal scene semantics but cannot rewrite the
# model-check declaration or another scene.
first_node = copied.node
second_node = copied.node
first_node.assign_id("mutated-copy-check")
model_check_check("copies.fresh_node",
                  second_node.id == "copy-check" && copied.id == "copy-check")
first_scene = Plot.scene()
second_scene = Plot.scene()
copied.add_to(first_scene)
copied.add_to(second_scene)
first_scene.node("copy-check").assign_id("first-scene-mutated")
independent_scene = second_scene.has_id?("copy-check")
independent_data = copied.to_data[:node][:id] == "copy-check"
model_check_check("copies.independent_scenes",
                  independent_scene && independent_data)


# Failures are explicit: inputs are finite polylines, semantic identifiers and
# provenance are strict Strings/Hashes, modes are closed, and options reject
# misspellings rather than silently entering metadata.
infinity = Math.exp(~10000.0)
rejected = false
begin
  Plot.model_check(
    [[~0.0, ~0.0], [~1.0, infinity]], model_check_draws(), "q", "s",
    model_check_provenance())
rescue error
  rejected = error.to_s.include?("must be finite")
model_check_check("validation.nonfinite_observed", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), [[[~0.0, ~0.0], [~1.0, infinity]]], "q", "s",
    model_check_provenance())
rescue error
  rejected = error.to_s.include?("must be finite")
model_check_check("validation.nonfinite_draw", rejected)

rejected = false
begin
  Plot.model_check(
    [[~0.0, ~0.0]], model_check_draws(), "q", "s", model_check_provenance())
rescue error
  rejected = error.to_s.include?("at least two points")
model_check_check("validation.short_observed", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), [[[~0.0, ~0.0]]], "q", "s",
    model_check_provenance())
rescue error
  rejected = error.to_s.include?("at least two points")
model_check_check("validation.short_draw", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), [], "q", "s", model_check_provenance())
rescue error
  rejected = error.to_s.include?("nonempty Array")
model_check_check("validation.empty_draws", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), "draws", "q", "s", model_check_provenance())
rescue error
  rejected = error.to_s.include?("nonempty Array")
model_check_check("validation.draws_type", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), :q, "s",
    model_check_provenance())
rescue error
  rejected = error.to_s.include?("quantity id")
model_check_check("validation.quantity_type", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "", "s",
    model_check_provenance())
rescue error
  rejected = error.to_s.include?("quantity id")
model_check_check("validation.quantity_empty", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", :s,
    model_check_provenance())
rescue error
  rejected = error.to_s.include?("scale id")
model_check_check("validation.scale_type", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "",
    model_check_provenance())
rescue error
  rejected = error.to_s.include?("scale id")
model_check_check("validation.scale_empty", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    model_check_provenance(), :juxtapose)
rescue error
  rejected = error.to_s.include?("mode must be")
model_check_check("validation.mode", rejected)

rejected = false
begin
  Plot.model_check(model_check_observed(), model_check_draws(), "q", "s", [])
rescue error
  rejected = error.to_s.include?("metadata must be a Hash")
model_check_check("validation.provenance_type", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    {:draw_source_id => "draws"})
rescue error
  rejected = error.to_s.include?("observed_transform_id")
model_check_check("validation.provenance_observed_missing", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    {:observed_transform_id => "", :draw_source_id => "draws"})
rescue error
  rejected = error.to_s.include?("observed_transform_id")
model_check_check("validation.provenance_observed_empty", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    {:observed_transform_id => "identity"})
rescue error
  rejected = error.to_s.include?("draw_source_id")
model_check_check("validation.provenance_draw_missing", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    {:observed_transform_id => "identity", :draw_source_id => :draws})
rescue error
  rejected = error.to_s.include?("draw_source_id")
model_check_check("validation.provenance_draw_type", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    model_check_provenance(), :superpose, [])
rescue error
  rejected = error.to_s.include?("options must be a Hash")
model_check_check("validation.options_type", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    model_check_provenance(), :superpose, {:colour => "blue"})
rescue error
  rejected = error.to_s.include?("unknown model-check option")
model_check_check("validation.options_unknown", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    model_check_provenance(), :superpose, {:id => :check})
rescue error
  rejected = error.to_s.include?("id must be")
model_check_check("validation.id_type", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    model_check_provenance(), :superpose, {:id => ""})
rescue error
  rejected = error.to_s.include?("id must be")
model_check_check("validation.id_empty", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    model_check_provenance(), :superpose, {:id => nil})
rescue error
  rejected = error.to_s.include?("id must be")
model_check_check("validation.id_nil", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    model_check_provenance(), :superpose, {:units => ""})
rescue error
  rejected = error.to_s.include?("units must be")
model_check_check("validation.units_empty", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    model_check_provenance(), :superpose, {:coordinate_system => []})
rescue error
  rejected = error.to_s.include?("coordinate_system must be")
model_check_check("validation.coordinates_type", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    model_check_provenance(), :superpose, {:observed_style => "style"})
rescue error
  rejected = error.to_s.include?("observed_style must be")
model_check_check("validation.observed_style_type", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    model_check_provenance(), :superpose, {:draw_style => "style"})
rescue error
  rejected = error.to_s.include?("draw_style must be")
model_check_check("validation.draw_style_type", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    model_check_provenance(), :superpose, {:metadata => []})
rescue error
  rejected = error.to_s.include?("metadata must be a Hash")
model_check_check("validation.metadata_type", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    model_check_provenance(), :superpose,
    {:metadata => {:not_portable => coordinates}})
rescue error
  rejected = error.to_s.include?("portable value-tree")
model_check_check("validation.metadata_portable", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    {
      :observed_transform_id => "identity",
      :draw_source_id => "draws",
      :nested => {:not_portable => coordinates}
    })
rescue error
  rejected = error.to_s.include?("portable value-tree")
model_check_check("validation.provenance_portable", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    model_check_provenance(), :superpose,
    {:metadata => {17 => "integer key"}})
rescue error
  rejected = error.to_s.include?("keys must be Strings or Symbols")
model_check_check("validation.metadata_keys", rejected)

rejected = false
begin
  Plot.model_check(
    model_check_observed(), model_check_draws(), "q", "s",
    model_check_provenance(), :superpose,
    {:metadata => {:same => 1, "same" => 2}})
rescue error
  rejected = error.to_s.include?("unique after String/Symbol encoding")
model_check_check("validation.metadata_key_collision", rejected)

<< "plot_model_check_spec: all checks passed"

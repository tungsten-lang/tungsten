# Pure/headless point-preview raster contract. Run in both engines:
#   bin/tungsten run spec/core/animation_point_preview_spec.w
#   bin/tungsten compile spec/core/animation_point_preview_spec.w \
#     --out /tmp/animation-point-preview-spec

use core/animation/point_preview

-> point_preview_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> point_preview_style(color, opacity = ~1.0)
  PlotStyle.new(nil, color, ~0.0, opacity, [], :circle)

-> point_preview_nonbackground_count(pixels, background)
  count = 0
  index = 0
  while index < pixels.size
    count += 1 if pixels[index] != background
    index += 1
  count

-> point_preview_indices(mode, frame_count, steps)
  values = []
  step = 0
  while step < steps
    values.push(AnimationPointPreview.frame_index(
      step, frame_count, mode))
    step += 1
  values

-> point_preview_array_equal?(left, right)
  return false if left.size != right.size
  index = 0
  while index < left.size
    return false if left[index] != right[index]
    index += 1
  true

black = AnimationPointPreview.rgba8("#000000")
red = AnimationPointPreview.rgba8("#ff0000")
blue = AnimationPointPreview.rgba8("#0000ff")
green = AnimationPointPreview.rgba8("#00ff00")

# PlotPoints are painted in retained scene order, including recursively nested
# identity groups. The later blue point must cover the earlier red point.
ordered_scene = Plot.scene(~3.0, ~3.0, "#000000")
ordered_scene.add(Plot.group([
  Plot.points(
    [[~1.0, ~1.0]], ~0.5, "red-point",
    point_preview_style("#ff0000")),
  Plot.group([
    Plot.points(
      [[~1.0, ~1.0]], ~0.5, "blue-point",
      point_preview_style("#0000ff"))
  ], [~0.0, ~0.0], [~1.0, ~1.0], ~0.0, "nested-layer")
], [~0.0, ~0.0], [~1.0, ~1.0], ~0.0, "ordered-layers"))
ordered_timeline = Animation.timeline(ordered_scene, ~0.0, 60)
ordered_frame = AnimationPointPreview.new(ordered_timeline).render(0)
point_preview_check("render.dimensions",
                    ordered_frame[:width] == 3 &&
                    ordered_frame[:height] == 3 &&
                    ordered_frame[:pixels].size == 9)
point_preview_check("render.group_draw_order",
                    ordered_frame[:pixels][4] == blue)

# Logical Plot coordinates are Cartesian/y-up. The packed pixel array is
# row-major/y-down, so y=0 occupies the last row and y=height-1 the first.
# Integer points outside the viewport are clipped rather than wrapped.
geometry_scene = Plot.scene(~3.0, ~3.0, "#000000")
geometry_scene.add(Plot.points([
  [~0.0, ~0.0],
  [~1.0, ~2.0],
  [~-1.0, ~1.0],
  [~3.0, ~1.0],
  [~1.0, ~-1.0],
  [~1.0, ~3.0]
], ~0.5, "geometry-points", point_preview_style("#00ff00")))
geometry_timeline = Animation.timeline(geometry_scene, ~0.0, 60)
geometry_pixels = AnimationPointPreview.new(geometry_timeline).render(0)[:pixels]
point_preview_check("render.cartesian_y_flip.bottom",
                    geometry_pixels[6] == green)
point_preview_check("render.cartesian_y_flip.top",
                    geometry_pixels[1] == green)
point_preview_check("render.viewport_clipping",
                    point_preview_nonbackground_count(
                      geometry_pixels, black) == 2)

circle_scene = Plot.scene(~5.0, ~5.0, "#000000")
circle_scene.add(Plot.points(
  [[~2.0, ~2.0]], ~1.0, "unit-circle",
  point_preview_style("#00ff00")))
circle_pixels = AnimationPointPreview.new(
  Animation.timeline(circle_scene, ~0.0, 60)).render(0)[:pixels]
point_preview_check("render.circle_radius",
                    point_preview_nonbackground_count(
                      circle_pixels, black) == 5)

bounded_scene = Plot.scene(~1.0, ~1.0, "#000000")
bounded_scene.add(Plot.points(
  [[~0.0, ~0.0]], ~1.0e6, "huge-circle",
  point_preview_style("#00ff00")))
bounded_scene.add(Plot.points(
  [[~1.0e100, ~1.0e100]], ~1.0, "far-circle",
  point_preview_style("#ff0000")))
bounded_scene.add(Plot.points(
  [[~0.0, ~0.0]], ~0.0, "zero-circle",
  point_preview_style("#0000ff")))
bounded_pixels = AnimationPointPreview.new(
  Animation.timeline(bounded_scene, ~0.0, 60)).render(0)[:pixels]
point_preview_check("render.clamped_huge_radius",
                    bounded_pixels[0] == green)
point_preview_check("render.zero_radius_empty",
                    point_preview_nonbackground_count(
                      bounded_pixels, black) == 1)

# Circle containment remains geometric when finite squared distances would
# overflow binary64. The origin is sqrt(2)*radius away from this center and
# therefore lies outside the circle.
overflow_scene = Plot.scene(~1.0, ~1.0, "#000000")
overflow_scene.add(Plot.points(
  [[~1.0e200, ~1.0e200]], ~1.0e200, "overflow-safe-circle",
  point_preview_style("#ff0000")))
overflow_pixel = AnimationPointPreview.new(
  Animation.timeline(overflow_scene, ~0.0, 60)).render(0)[:pixels][0]
point_preview_check("render.overflow_safe_circle", overflow_pixel == black)

# Alpha is quantized to one byte, then source-over blended in integer channel
# space. Half-opaque white over black therefore produces exact #808080.
alpha_scene = Plot.scene(~1.0, ~1.0, "#000000")
alpha_scene.add(Plot.points(
  [[~0.0, ~0.0]], ~0.5, "half-white",
  point_preview_style("#ffffff", ~0.5)))
alpha_timeline = Animation.timeline(alpha_scene, ~0.0, 60)
alpha_pixel = AnimationPointPreview.new(alpha_timeline).render(0)[:pixels][0]
point_preview_check("render.alpha_blend",
                    alpha_pixel == AnimationPointPreview.rgba8("#808080"))

# Frame recipes may replace a point array and independently animate another
# point node's opacity. Rendering a later frame applies both updates without
# mutating the retained base scene.
update_scene = Plot.scene(~3.0, ~3.0, "#000000")
update_scene.add(Plot.points(
  [[~0.0, ~0.0]], ~0.5, "moving-point",
  point_preview_style("#ff0000")))
update_scene.add(Plot.points(
  [[~1.0, ~1.0]], ~0.5, "fading-point",
  point_preview_style("#00ff00")))
update_timeline = Animation.timeline(update_scene, ~1.0, 1)
update_timeline.add(Animation.track(
  "moving-point", :points, [
    Animation.keyframe(~0.0, [[~0.0, ~0.0]]),
    Animation.keyframe(~1.0, [[~2.0, ~2.0]])
  ], :step))
update_timeline.add(Animation.track(
  "fading-point", :opacity, [
    Animation.keyframe(~0.0, ~1.0),
    Animation.keyframe(~1.0, ~0.0)
  ]))
update_preview = AnimationPointPreview.new(update_timeline)
update_first = update_preview.render(0)[:pixels]
update_last = update_preview.render(1)[:pixels]
point_preview_check("updates.points.base_frame",
                    update_first[6] == red)
point_preview_check("updates.opacity.base_frame",
                    update_first[4] == green)
point_preview_check("updates.points.final_frame",
                    update_last[2] == red && update_last[6] == black)
point_preview_check("updates.opacity.final_frame",
                    update_last[4] == black)

# The v1 backend fails loudly rather than silently dropping geometry or
# inventing transform semantics outside its focused point-scene contract.
unsupported_scene = Plot.scene(~2.0, ~2.0, "#000000")
unsupported_scene.add(Plot.polyline(
  [[~0.0, ~0.0], [~1.0, ~1.0]], false, "line"))
unsupported_leaf = false
begin
  AnimationPointPreview.new(
    Animation.timeline(unsupported_scene, ~0.0, 60))
rescue error
  unsupported_leaf = error.to_s().include?(
    "supports only PlotPoints and identity PlotGroups")
point_preview_check("validation.unsupported_leaf", unsupported_leaf)

property_scene = Plot.scene(~2.0, ~2.0, "#000000")
property_scene.add(Plot.points(
  [[~0.0, ~0.0]], ~0.5, "translated-point",
  point_preview_style("#ffffff")))
property_timeline = Animation.timeline(property_scene, ~1.0, 1)
property_timeline.add(Animation.move(
  "translated-point", ~0.0, ~1.0,
  [~0.0, ~0.0], [~1.0, ~0.0]))
unsupported_property = false
begin
  AnimationPointPreview.new(property_timeline)
rescue error
  unsupported_property = error.to_s().include?(
    "does not support track property: translate")
point_preview_check("validation.unsupported_property",
                    unsupported_property)

transformed_scene = Plot.scene(~2.0, ~2.0, "#000000")
transformed_scene.add(Plot.group([
  Plot.points(
    [[~0.0, ~0.0]], ~0.5, "grouped-point",
    point_preview_style("#ffffff"))
], [~1.0, ~0.0], [~1.0, ~1.0], ~0.0, "translated-group"))
unsupported_group_transform = false
begin
  AnimationPointPreview.new(
    Animation.timeline(transformed_scene, ~0.0, 60))
rescue error
  unsupported_group_transform = error.to_s().include?(
    "requires identity PlotGroup transforms")
point_preview_check("validation.unsupported_group_transform",
                    unsupported_group_transform)

styled_group_scene = Plot.scene(~2.0, ~2.0, "#000000")
styled_group_scene.add(Plot.group([
  Plot.points(
    [[~0.0, ~0.0]], ~0.5, "styled-child",
    point_preview_style("#ffffff"))
], [~0.0, ~0.0], [~1.0, ~1.0], ~0.0, "styled-group",
   PlotStyle.new(nil, "#ffffff")))
unsupported_group_style = false
begin
  AnimationPointPreview.new(
    Animation.timeline(styled_group_scene, ~0.0, 60))
rescue error
  unsupported_group_style = error.to_s().include?(
    "does not support PlotGroup styles")
point_preview_check("validation.unsupported_group_style",
                    unsupported_group_style)

marker_scene = Plot.scene(~2.0, ~2.0, "#000000")
marker_scene.add(Plot.points(
  [[~0.0, ~0.0]], ~0.5, "square-point",
  PlotStyle.new(nil, "#ffffff", ~0.0, ~1.0, [], :square)))
unsupported_marker = false
begin
  AnimationPointPreview.new(
    Animation.timeline(marker_scene, ~0.0, 60))
rescue error
  unsupported_marker = error.to_s().include?(
    "supports only circle point markers")
point_preview_check("validation.unsupported_marker", unsupported_marker)

outlined_scene = Plot.scene(~2.0, ~2.0, "#000000")
outlined_scene.add(Plot.points(
  [[~0.0, ~0.0]], ~0.5, "outlined-point",
  PlotStyle.new("#ffffff", "#ff0000", ~1.0, ~1.0, [], :circle)))
unsupported_outline = false
begin
  AnimationPointPreview.new(
    Animation.timeline(outlined_scene, ~0.0, 60))
rescue error
  unsupported_outline = error.to_s().include?(
    "does not support outlined point markers")
point_preview_check("validation.unsupported_outline", unsupported_outline)

color_scene = Plot.scene(~2.0, ~2.0, "#000000")
color_scene.add(Plot.points(
  [[~0.0, ~0.0]], ~0.5, "named-color-point",
  point_preview_style("white")))
unsupported_color = false
begin
  AnimationPointPreview.new(
    Animation.timeline(color_scene, ~0.0, 60))
rescue error
  unsupported_color = error.to_s().include?("CSS #RRGGBB")
point_preview_check("validation.unsupported_color", unsupported_color)

mapped_coordinates = PlotCoordinateSystem.new(
  [~0.0, ~1.0], [~0.0, ~1.0], [~0.0, ~0.0, ~2.0, ~2.0])
mapped_scene = Plot.scene(
  ~2.0, ~2.0, "#000000", mapped_coordinates)
mapped_scene.add(Plot.points(
  [[~0.0, ~0.0]], ~0.5, "mapped-point",
  point_preview_style("#ffffff")))
unsupported_coordinates = false
begin
  AnimationPointPreview.new(
    Animation.timeline(mapped_scene, ~0.0, 60))
rescue error
  unsupported_coordinates = error.to_s().include?(
    "requires an identity scene coordinate system")
point_preview_check("validation.unsupported_coordinates",
                    unsupported_coordinates)

camera_scene = Plot.scene(~2.0, ~2.0, "#000000")
camera_scene.add(Plot.points(
  [[~0.0, ~0.0]], ~0.5, "camera-point",
  point_preview_style("#ffffff")))
camera = AnimationCamera2D.new([~1.0, ~0.0], ~1.0, ~0.0)
camera_timeline = Animation.timeline(camera_scene, ~0.0, 60, camera)
unsupported_camera_transform = false
begin
  AnimationPointPreview.new(camera_timeline).render(0)
rescue error
  unsupported_camera_transform = error.to_s().include?(
    "does not support camera transforms")
point_preview_check("validation.unsupported_camera_transform",
                    unsupported_camera_transform)

# Playback selection is a pure integer mapping. Ordinary loop visits every
# frame; closed_loop omits a conventional duplicate terminal sample;
# ping-pong visits each endpoint once per turn; once clamps at the final frame.
point_preview_check("selection.loop",
  point_preview_array_equal?(
    point_preview_indices(:loop, 4, 8), [0, 1, 2, 3, 0, 1, 2, 3]))
point_preview_check("selection.closed_loop",
  point_preview_array_equal?(
    point_preview_indices(:closed_loop, 4, 8), [0, 1, 2, 0, 1, 2, 0, 1]))
point_preview_check("selection.ping_pong",
  point_preview_array_equal?(
    point_preview_indices(:ping_pong, 4, 8), [0, 1, 2, 3, 2, 1, 0, 1]))
point_preview_check("selection.once",
  point_preview_array_equal?(
    point_preview_indices(:once, 4, 8), [0, 1, 2, 3, 3, 3, 3, 3]))
point_preview_check("selection.single_frame",
  point_preview_array_equal?(
    point_preview_indices(:loop, 1, 4), [0, 0, 0, 0]) &&
  point_preview_array_equal?(
    point_preview_indices(:closed_loop, 1, 4), [0, 0, 0, 0]) &&
  point_preview_array_equal?(
    point_preview_indices(:ping_pong, 1, 4), [0, 0, 0, 0]) &&
  point_preview_array_equal?(
    point_preview_indices(:once, 1, 4), [0, 0, 0, 0]))

invalid_mode = false
begin
  AnimationPointPreview.frame_index(0, 4, :reverse)
rescue error
  invalid_mode = error.to_s().include?(
    "mode must be once, loop, closed_loop, or ping_pong")
point_preview_check("selection.invalid_mode", invalid_mode)

single_frame_invalid_mode = false
begin
  AnimationPointPreview.frame_index(0, 1, :reverse)
rescue error
  single_frame_invalid_mode = error.to_s().include?("closed_loop")
point_preview_check("selection.single_frame_invalid_mode",
                    single_frame_invalid_mode)

<< "animation_point_preview_spec: all checks passed"

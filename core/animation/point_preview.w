# Deterministic in-memory point-scene rasterizer for Animation timelines.
#
# This module is deliberately not loaded by core/animation. It is a small,
# focused consumer of the portable scene/frame description: PlotPoints leaves,
# identity PlotGroups, `points` and `opacity` updates, and CSS #RRGGBB colors.
# The data model remains renderer-independent. The separately loaded
# AnimationWindowPreview facade is the only part that depends on macOS,
# Metal, or a graphics window.

use core/animation

+ AnimationPointPreview
  -> new(timeline)
    if timeline.class_name != "AnimationTimeline"
      raise "animation point preview requires an AnimationTimeline"
    @timeline = timeline
    @width = PlotData.positive_integer(
      timeline.scene.width, "preview width", 4096)
    @height = PlotData.positive_integer(
      timeline.scene.height, "preview height", 4096)
    if @width * @height > 16_777_216
      raise "animation point preview is limited to 16777216 pixels"

    coordinate_system = timeline.scene.coordinate_system
    x_range = coordinate_system.x_range
    y_range = coordinate_system.y_range
    frame = coordinate_system.frame
    identity = x_range[0] == ~0.0 && x_range[1] == @width.to_f()
    identity = identity && y_range[0] == ~0.0 && y_range[1] == @height.to_f()
    identity = identity && frame[0] == ~0.0 && frame[1] == ~0.0
    identity = identity && frame[2] == @width.to_f() && frame[3] == @height.to_f()
    if !identity
      raise "animation point preview v1 requires an identity scene coordinate system"

    scene_data = timeline.scene.to_data
    @background = scene_data[:viewport][:background]
    @background_pixel = AnimationPointPreview.rgba8(@background)
    @nodes = scene_data[:nodes]
    @point_ids = {}
    validate_nodes(@nodes)

    @tracks = timeline.tracks
    index = 0
    while index < @tracks.size
      track = @tracks[index]
      property = track.property
      if property != "points" && property != "opacity"
        raise "animation point preview does not support track property: " + property
      if @point_ids[track.target] != true
        raise "animation point preview tracks must target PlotPoints nodes: " + track.target
      index += 1

  -> width
    @width

  -> height
    @height

  -> pixel_count
    @width * @height

  -> validate_nodes(nodes)
    index = 0
    while index < nodes.size
      node = nodes[index]
      kind = node[:kind]
      if kind == :group
        transform = node[:geometry][:transform]
        translate = transform[:translate]
        scale = transform[:scale]
        identity = translate[0] == ~0.0 && translate[1] == ~0.0
        identity = identity && scale[0] == ~1.0 && scale[1] == ~1.0
        identity = identity && transform[:rotation] == ~0.0
        if !identity
          raise "animation point preview v1 requires identity PlotGroup transforms"
        group_style = node[:style]
        default_group_style = group_style[:stroke] == "#20242b"
        default_group_style = default_group_style && group_style[:fill] == nil
        default_group_style = default_group_style && group_style[:stroke_width] == ~1.0
        default_group_style = default_group_style && group_style[:opacity] == ~1.0
        default_group_style = default_group_style && group_style[:dash].size == 0
        default_group_style = default_group_style && group_style[:marker] == nil
        default_group_style = default_group_style && group_style[:font_size] == ~16.0
        default_group_style = default_group_style && group_style[:font_family] == "sans-serif"
        default_group_style = default_group_style && group_style[:text_anchor] == :middle
        if !default_group_style
          raise "animation point preview v1 does not support PlotGroup styles"
        validate_nodes(node[:geometry][:children])
      elsif kind == :points
        id = node[:id]
        if id.class_name != "String" || id.size == 0
          raise "animation point preview requires stable PlotPoints ids"
        @point_ids[id] = true
        marker = node[:style][:marker]
        if marker != nil && marker != :circle && marker != "circle"
          raise "animation point preview v1 supports only circle point markers"
        outlined = node[:style][:fill] != nil && node[:style][:stroke] != nil
        if outlined && node[:style][:stroke_width] > ~0.0
          raise "animation point preview v1 does not support outlined point markers"
        if node[:style][:dash].size != 0
          raise "animation point preview v1 does not support point dash styles"
        AnimationPointPreview.color_channels(
          node[:style][:fill] == nil ? node[:style][:stroke] : node[:style][:fill])
      else
        raise "animation point preview v1 supports only PlotPoints and identity PlotGroups"
      index += 1
    self

  -> validate_camera(camera)
    center = camera.center
    changed = center[0] != ~0.0 || center[1] != ~0.0
    changed = changed || camera.zoom != ~1.0
    changed = changed || camera.rotation != ~0.0
    if changed
      raise "animation point preview v1 does not support camera transforms"
    self

  -> update_map_at(frame_index)
    updates = {}
    time = @timeline.time_at(frame_index)
    index = 0
    while index < @tracks.size
      track = @tracks[index]
      properties = updates[track.target]
      if properties == nil
        properties = {}
        updates[track.target] = properties
      properties[track.property] = track.value_at(time)
      index += 1
    updates

  -> render(frame_index)
    pixels = []
    index = 0
    while index < pixel_count
      pixels.push(@background_pixel)
      index += 1
    render_prepared(frame_index, pixels)

  -> render_into(frame_index, pixels)
    if pixels.size != pixel_count
      raise "animation point preview pixel buffer has the wrong size"
    index = 0
    while index < pixels.size
      pixels[index] = @background_pixel
      index += 1

    render_prepared(frame_index, pixels)

  -> render_prepared(frame_index, pixels)
    validate_camera(@timeline.camera_at(frame_index))
    updates = update_map_at(frame_index)
    draw_nodes(@nodes, updates, pixels)
    {:width => @width, :height => @height, :pixels => pixels}

  -> draw_nodes(nodes, updates, pixels)
    index = 0
    while index < nodes.size
      node = nodes[index]
      if node[:kind] == :group
        draw_nodes(node[:geometry][:children], updates, pixels)
      else
        draw_points(node, updates[node[:id]], pixels)
      index += 1
    self

  -> draw_points(node, properties, pixels)
    geometry = node[:geometry]
    style = node[:style]
    points = geometry[:points]
    opacity = style[:opacity]
    if properties != nil
      points = properties["points"] if properties.has_key?("points")
      opacity = properties["opacity"] if properties.has_key?("opacity")
    opacity = PlotData.number(opacity, "preview point opacity")
    if opacity < ~0.0 || opacity > ~1.0
      raise "preview point opacity must be between zero and one"
    return self if opacity == ~0.0

    color = style[:fill] == nil ? style[:stroke] : style[:fill]
    channels = AnimationPointPreview.color_channels(color)
    radius = PlotData.number(geometry[:radius], "preview point radius")
    raise "preview point radius must be nonnegative" if radius < ~0.0
    if points.class_name != "Array"
      raise "preview points update must be an Array"
    point_index = 0
    while point_index < points.size
      point = points[point_index]
      if point.class_name != "Array" || point.size != 2
        raise "preview points must have exactly two coordinates"
      x = PlotData.number(point[0], "preview point")
      y = PlotData.number(point[1], "preview point")
      draw_point(pixels, x, y, radius, channels, opacity)
      point_index += 1
    self

  -> draw_point(pixels, x, y, radius, channels, opacity)
    return self if radius == ~0.0
    if radius <= ~0.75
      return self if x < ~-0.5 || x > @width.to_f() - ~0.5
      return self if y < ~-0.5 || y > @height.to_f() - ~0.5
      px = Math.round(x).to_i()
      py = Math.round(y).to_i()
      blend_at(pixels, px, py, channels, opacity)
      return self
    left = x - radius
    right = x + radius
    bottom = y - radius
    top = y + radius
    return self if right < ~0.0 || left > (@width - 1).to_f()
    return self if top < ~0.0 || bottom > (@height - 1).to_f()
    min_x = left <= ~0.0 ? 0 : Math.floor(left).to_i()
    max_x = right >= (@width - 1).to_f() ? @width - 1 : Math.ceil(right).to_i()
    min_y = bottom <= ~0.0 ? 0 : Math.floor(bottom).to_i()
    max_y = top >= (@height - 1).to_f() ? @height - 1 : Math.ceil(top).to_i()
    py = min_y
    while py <= max_y
      px = min_x
      while px <= max_x
        dx = px.to_f() - x
        dy = py.to_f() - y
        normalized_x = dx / radius
        normalized_y = dy / radius
        if normalized_x * normalized_x + normalized_y * normalized_y <= ~1.0
          blend_at(pixels, px, py, channels, opacity)
        px += 1
      py += 1
    self

  -> blend_at(pixels, x, y, channels, opacity)
    return self if x < 0 || x >= @width || y < 0 || y >= @height
    row = @height - 1 - y
    offset = row * @width + x
    pixels[offset] = AnimationPointPreview.blend_rgba8(
      pixels[offset], channels, opacity)
    self

  -> .frame_index(step, frame_count, mode)
    count = PlotData.positive_integer(
      frame_count, "preview frame count", 10_000_000)
    value = step.to_i()
    if value != step || value < 0
      raise "preview logical step must be a nonnegative integer"
    valid_mode = mode == :once || mode == :loop
    valid_mode = valid_mode || mode == :closed_loop || mode == :ping_pong
    if !valid_mode
      raise "animation point preview mode must be once, loop, closed_loop, or ping_pong"
    if mode == :once
      return value < count ? value : count - 1
    if count == 1
      return 0
    if mode == :loop
      return value % count
    if mode == :closed_loop
      # Closed timelines conventionally repeat frame zero as their terminal
      # sample. Skip that duplicate while cycling.
      return value % (count - 1)
    if mode == :ping_pong
      span = count - 1
      position = value % (span * 2)
      return position <= span ? position : span * 2 - position

  -> .hex_nibble(character)
    digits = "0123456789abcdef"
    value = digits.index(character.downcase())
    if value == nil
      raise "preview colors must use CSS #RRGGBB hexadecimal syntax"
    value

  -> .color_channels(color)
    if color.class_name != "String" || color.size != 7 || color[0] != "#"
      raise "preview colors must use CSS #RRGGBB hexadecimal syntax"
    red = hex_nibble(color[1]) * 16 + hex_nibble(color[2])
    green = hex_nibble(color[3]) * 16 + hex_nibble(color[4])
    blue = hex_nibble(color[5]) * 16 + hex_nibble(color[6])
    [red, green, blue]

  -> .rgba8(color)
    channels = color_channels(color)
    0xff000000 | (channels[2] << 16) | (channels[1] << 8) | channels[0]

  -> .blend_rgba8(destination, channels, opacity)
    amount = PlotData.number(opacity, "preview opacity")
    if amount < ~0.0 || amount > ~1.0
      raise "preview opacity must be between zero and one"
    alpha = Math.round(amount * ~255.0).to_i()
    return destination if alpha <= 0
    source_red = channels[0]
    source_green = channels[1]
    source_blue = channels[2]
    opaque_source = 0xff000000 | (source_blue << 16)
    opaque_source = opaque_source | (source_green << 8) | source_red
    return opaque_source if alpha >= 255

    inverse = 255 - alpha
    destination_red = destination & 255
    destination_green = (destination >> 8) & 255
    destination_blue = (destination >> 16) & 255
    red = Math.floor(
      (source_red * alpha + destination_red * inverse).to_f() / ~255.0 + ~0.5).to_i()
    green = Math.floor(
      (source_green * alpha + destination_green * inverse).to_f() / ~255.0 + ~0.5).to_i()
    blue = Math.floor(
      (source_blue * alpha + destination_blue * inverse).to_f() / ~255.0 + ~0.5).to_i()
    result = 0xff000000 | (blue << 16)
    result | (green << 8) | red

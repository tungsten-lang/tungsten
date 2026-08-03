# Portable plot styles. Colors are backend-neutral strings, not Color's
# terminal/runtime pixel handle; a backend may interpret CSS hex or named
# colors, while the scene description keeps the caller's exact string.

+ PlotStyle
  -> new(stroke = "#20242b", fill = nil, stroke_width = ~1.0,
         opacity = ~1.0, dash = [], marker = nil, font_size = ~16.0,
         font_family = "sans-serif", text_anchor = :middle)
    if stroke != nil && stroke.class_name != "String"
      raise "plot stroke must be a String or nil"
    if fill != nil && fill.class_name != "String"
      raise "plot fill must be a String or nil"
    if marker != nil && marker.class_name != "String" && marker.class_name != "Symbol"
      raise "plot marker must be a String, Symbol, or nil"
    if font_family.class_name != "String"
      raise "plot font family must be a String"
    @stroke = stroke
    @fill = fill
    @stroke_width = PlotData.number(stroke_width, "plot stroke width")
    @opacity = PlotData.number(opacity, "plot opacity")
    @font_size = PlotData.number(font_size, "plot font size")
    if @stroke_width < ~0.0
      raise "plot stroke width must be nonnegative"
    if @opacity < ~0.0 || @opacity > ~1.0
      raise "plot opacity must be between zero and one"
    if @font_size <= ~0.0
      raise "plot font size must be positive"
    if dash.class_name != "Array"
      raise "plot dash pattern must be an Array"
    @dash = []
    dash.each -> (length)
      segment = PlotData.number(length, "plot dash length")
      raise "plot dash lengths must be positive" if segment <= ~0.0
      @dash.push(segment)
    @marker = marker
    @font_family = font_family
    @text_anchor = text_anchor

  -> .default
    PlotStyle.new()

  -> .axes
    PlotStyle.new("#68707d", nil, ~1.0, ~1.0)

  -> .label
    PlotStyle.new(nil, "#20242b", ~0.0, ~1.0)

  -> stroke
    @stroke

  -> fill
    @fill

  -> stroke_width
    @stroke_width

  -> opacity
    @opacity

  -> dash
    PlotData.copy(@dash)

  -> marker
    @marker

  -> font_size
    @font_size

  -> font_family
    @font_family

  -> text_anchor
    @text_anchor

  -> with_opacity(value)
    PlotStyle.new(@stroke, @fill, @stroke_width, value, @dash, @marker,
                  @font_size, @font_family, @text_anchor)

  -> with_stroke(color, width = nil)
    resolved_width = width == nil ? @stroke_width : width
    PlotStyle.new(color, @fill, resolved_width, @opacity, @dash, @marker,
                  @font_size, @font_family, @text_anchor)

  -> with_fill(color)
    PlotStyle.new(@stroke, color, @stroke_width, @opacity, @dash, @marker,
                  @font_size, @font_family, @text_anchor)

  -> to_data
    {
      :stroke => @stroke,
      :fill => @fill,
      :stroke_width => @stroke_width,
      :opacity => @opacity,
      :dash => PlotData.copy(@dash),
      :marker => @marker,
      :font_size => @font_size,
      :font_family => @font_family,
      :text_anchor => @text_anchor
    }

# Recursive deterministic interpolation and easing.

+ AnimationValue
  -> .number?(value)
    name = value.class_name
    names = [
      "Integer", "Int", "BigInt", "Float", "Float16", "Float32",
      "Float64", "Float80", "Float128", "Float256", "Rational",
      "Decimal", "Decimal32", "Decimal64", "Decimal128"
    ]
    names.include?(name)

  -> .clamp01(value)
    number = PlotData.number(value, "animation progress")
    return ~0.0 if number < ~0.0
    return ~1.0 if number > ~1.0
    number

  -> .ease(name, progress)
    t = clamp01(progress)
    return t if name == :linear
    return t * t if name == :ease_in
    return ~1.0 - (~1.0 - t) * (~1.0 - t) if name == :ease_out
    if name == :ease_in_out
      return ~2.0 * t * t if t < ~0.5
      u = ~1.0 - t
      return ~1.0 - ~2.0 * u * u
    if name == :smooth
      return t * t * (~3.0 - ~2.0 * t)
    raise "unknown animation easing: " + name.to_s()

  -> .interpolate(left, right, progress)
    t = clamp01(progress)
    if number?(left) && number?(right)
      a = left.to_f()
      b = right.to_f()
      return a + (b - a) * t
    if left.class_name == "Array" && right.class_name == "Array"
      if left.size != right.size
        raise "animation arrays must have identical shape for interpolation"
      out = []
      index = 0
      while index < left.size
        out.push(interpolate(left[index], right[index], t))
        index += 1
      return out
    left_camera = left.class_name == "AnimationCamera2D"
    right_camera = right.class_name == "AnimationCamera2D"
    if left_camera && right_camera
      return AnimationCamera2D.interpolate(left, right, t)
    raise "animation linear interpolation supports numbers, arrays, and cameras"

  -> .copy(value)
    return PlotData.copy(value) if value.class_name == "Array" || value.class_name == "Hash"
    value

  -> .data(value)
    if value.respond_to?("to_data")
      return value.to_data
    PlotData.copy(value)

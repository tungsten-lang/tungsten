# Type-aware terminal inspection for the mathematical classes in core/.
#
# The adapters intentionally live in tungsten-drawille rather than monkey-
# patching exact algebra or calculus classes with plotting concerns.  Dispatch
# uses stable public class names and public APIs, so this bit may be loaded
# before or after the corresponding core modules.

use scene

+ DrawilleInspection
  -> .class_family(name)
    # Native generic specializations include a `$...` suffix (for example
    # ProjectiveSpace$ℚ_2 and Vec3$f64); the interpreter erases it.  Normalize
    # only the families this renderer explicitly supports.
    families = ["ProjectiveSpace", "Vec2", "Vec3", "Vec4", "Vector"]
    i = 0
    while i < families.size()
      family = families[i]
      return family if name == family || name.starts_with?(family + "$")
      i += 1
    name

  -> .supported_class?(name)
    supported = [
      "PolynomialRing", "Polynomial",
      "Curve", "AffineChart", "EllipticCurve", "HyperellipticCurve",
      "ProjectiveSpace", "ProjectivePoint",
      "NumberFieldElement", "SimpleExtensionElement", "AlgebraicRealRoot",
      "Differential",
      "QExpansion", "FieldQExpansion", "ClassicalModularForm",
      "WeightTwoHeckeEigenpacket", "RationalWeightTwoNewform",
      "FormalPowerSeries", "FormalLaurentSeries", "FormalPuiseuxSeries",
      "TaylorJet", "ThetaQuadraticForm",
      "TensorField", "HorizonSet", "ReggeWheelerPotential", "BraneBulkChord",
      "WarpedConeSurface",
      "Vec2", "Vec3", "Vec4", "Vector", "Array"
    ]
    supported.include?(class_family(name))

  -> .renderable?(value)
    value.class_name != "Nil" && supported_class?(value.class_name)

  # Public REPL entry point.  Unsupported objects return an empty string;
  # supported objects retain a useful structural explanation even when no
  # ordered numeric embedding is available.
  -> .render(value, cols = 70, rows = 15)
    return "" if value.class_name == "Nil"
    name = class_family(value.class_name)
    return "" if !supported_class?(name)
    cols = DrawilleNumbers.bounded_cols(cols)
    rows = DrawilleNumbers.bounded_rows(rows)
    # Keep generic SIMD vector dispatch ahead of the broad algebra chain. The
    # interpreter erases Vec<T>'s type arguments and can otherwise attempt an
    # unrelated generic specialization while resolving the long elsif chain.
    if name == "Vec2" || name == "Vec3" || name == "Vec4" || name == "Vector"
      return render_vector(value, cols, rows)
    begin
      if name == "PolynomialRing"
        return render_polynomial_ring(value, cols, rows)
      elsif name == "Polynomial"
        return render_polynomial(value, cols, rows)
      elsif name == "Curve"
        return render_curve(value, cols, rows)
      elsif name == "AffineChart"
        return render_affine_chart(value, cols, rows)
      elsif name == "EllipticCurve"
        return render_elliptic_curve(value, cols, rows)
      elsif name == "HyperellipticCurve"
        return render_hyperelliptic_curve(value, cols, rows)
      elsif name == "ProjectiveSpace"
        return render_projective_space(value, cols, rows)
      elsif name == "ProjectivePoint"
        return render_projective_point(value, cols, rows)
      elsif name == "NumberFieldElement" || name == "SimpleExtensionElement"
        return render_algebraic_element(value, cols, rows)
      elsif name == "AlgebraicRealRoot"
        return render_algebraic_real(value, cols, rows)
      elsif name == "Differential"
        return render_differential(value, cols, rows)
      elsif name == "TensorField"
        return render_tensor_field(value, cols, rows)
      elsif name == "HorizonSet"
        return render_horizon_set(value, cols, rows)
      elsif name == "ReggeWheelerPotential"
        return render_regge_wheeler(value, cols, rows)
      elsif name == "BraneBulkChord"
        return render_brane_bulk_chord(value, cols, rows)
      elsif name == "WarpedConeSurface"
        return render_warped_cone_surface(value, cols, rows)
      elsif name == "ThetaQuadraticForm"
        return render_theta_form(value, cols)
      elsif name == "QExpansion" || name == "FieldQExpansion"
        return render_coefficients(value, "q-expansion", cols, rows)
      elsif name == "ClassicalModularForm" || name == "WeightTwoHeckeEigenpacket" || name == "RationalWeightTwoNewform"
        return render_modular_form(value, cols, rows)
      elsif name == "FormalPowerSeries" || name == "FormalLaurentSeries" || name == "FormalPuiseuxSeries" || name == "TaylorJet"
        return render_formal_series(value, cols, rows)
      elsif name == "Array"
        return render_array(value, cols, rows)
    rescue error
      return header(name, "visualization unavailable: " + error.to_s())
    ""

  -> .header(title, detail = nil)
    out = "  " + title + "\n"
    out += "  " + detail + "\n" if detail != nil && detail != ""
    out

  -> .numeric_array(values)
    out = []
    i = 0
    while i < values.size()
      number = DrawilleNumbers.numeric(values[i])
      return nil if number == nil
      out.push(number)
      i += 1
    out

  -> .sample_values(values, limit)
    return values if values.size() <= limit
    out = []
    i = 0
    while i < limit
      index = i * (values.size() - 1) / (limit - 1)
      out.push(values[index])
      i += 1
    out

  -> .bounded_array_text(values, limit = 16)
    sampled = sample_values(values, limit)
    text = sampled.to_s()
    if sampled.size() < values.size()
      return text + " (sampled " + sampled.size().to_s() + " of " + values.size().to_s() + ")"
    text

  # Public numeric-series/AUC surface.  Source evaluation stays with the
  # caller; Drawille owns bounded sampling, projection, rasterization, axes,
  # fill, and terminal labels.
  -> .render_series(values, x_lo = 0, x_hi = nil,
                    cols = 70, rows = 15, fill = false)
    return "" if values == nil || values.class_name != "Array" || values.size() == 0
    cols = DrawilleNumbers.bounded_cols(cols)
    rows = DrawilleNumbers.bounded_rows(rows)
    source_size = values.size()
    hi = x_hi
    hi = x_lo + source_size - 1 if hi == nil
    lo_number = DrawilleNumbers.numeric(x_lo)
    hi_number = DrawilleNumbers.numeric(hi)
    return "" if lo_number == nil || hi_number == nil
    # Sample by index before coercion. A terminal-width plot must not duplicate
    # or convert a million-element source just to retain a few visible columns.
    limit = cols * 2
    sampled = sample_values(values, limit)
    numbers = numeric_array(sampled)
    return "" if numbers == nil
    points = []
    i = 0
    while i < numbers.size()
      x = lo_number
      if numbers.size() > 1
        x += (hi_number - lo_number) * i.to_f() / (numbers.size() - 1).to_f()
      points.push([x, numbers[i]])
      i += 1
    out = render_xy(points, cols, rows, true, true, fill)
    out + DrawilleScene.label_line(x_lo.to_s(), hi.to_s(), cols)

  -> .render_xy(points, cols, rows, axes = true, connect = true, fill = false)
    return "" if points.size() == 0
    # Preserve endpoints and order while bounding the public point-array path.
    points = sample_values(points, DrawilleNumbers.bounded_cols(cols) * 2)
    scene = DrawilleScene.new()
    if connect
      scene.polyline(points)
    else
      points.each -> (point)
        scene.point(point[0], point[1])
    if !fill
      return scene.render(cols, rows, axes)

    # Fill needs direct access to the same viewport as the curve so the zero
    # baseline and curve remain exactly aligned.
    cols = DrawilleNumbers.bounded_cols(cols)
    rows = DrawilleNumbers.bounded_rows(rows)
    canvas = Canvas.new(cols, rows)
    box = scene.bounds(true)
    viewport = DrawilleViewport.new(canvas, box[0], box[1], box[2], box[3])
    zero = viewport.py(~0.0)
    previous = nil
    points.each -> (point)
      pixel = viewport.point(point[0], point[1])
      low = pixel[1] < zero ? pixel[1] : zero
      high = pixel[1] > zero ? pixel[1] : zero
      py = low
      while py <= high
        canvas.set(pixel[0], py) if (pixel[0] + py).even?()
        py += 1
      if previous != nil
        canvas.line(previous[0], previous[1], pixel[0], pixel[1])
      previous = pixel
    DrawilleScene.canvas_text(canvas, viewport, axes)

  -> .render_vector(value, cols, rows)
    coordinates = []
    dimension = 0
    if value.respond_to?("components")
      components = value.components
      dimension = components.size()
      limit = dimension < 3 ? dimension : 3
      i = 0
      while i < limit
        coordinates.push(components[i])
        i += 1
    elsif value.respond_to?("x")
      coordinates.push(value.x)
      coordinates.push(value.y) if value.respond_to?("y")
      coordinates.push(value.z) if value.respond_to?("z")
      dimension = coordinates.size()
    numbers = numeric_array(coordinates)
    if numbers == nil
      return header(value.class_name, "first components: " + bounded_array_text(coordinates))
    if numbers.size() == 2
      scene = DrawilleScene.new()
      scene.segment(~0.0, ~0.0, numbers[0], numbers[1])
      scene.point(numbers[0], numbers[1])
      return header(value.class_name, "vector in R^2") + scene.render(cols, rows, true)
    if numbers.size() >= 3
      projected = DrawilleProjection3D.project(numbers[0], numbers[1], numbers[2])
      scene = DrawilleScene.new()
      origin = DrawilleProjection3D.project(~0.0, ~0.0, ~0.0)
      scene.segment(origin[0], origin[1], projected[0], projected[1])
      scene.point(projected[0], projected[1])
      detail = "perspective projection from R^3"
      if dimension > 3
        detail = "first-three-coordinate perspective projection from R^" + dimension.to_s()
      return header(value.class_name, detail) + scene.render(cols, rows, false)
    header(value.class_name, "components: " + coordinates.to_s())

  -> .array_point(item)
    source = nil
    if item.class_name == "Array"
      source = item
    elsif item.respond_to?("components")
      source = item.components
    elsif item.respond_to?("x") && item.respond_to?("y")
      source = [item.x, item.y]
      source.push(item.z) if item.respond_to?("z")
    return nil if source == nil
    # Only the first three coordinates are projected. Do not copy an
    # arbitrarily high-dimensional coordinate row to discard its tail.
    limit = source.size() < 3 ? source.size() : 3
    out = []
    i = 0
    while i < limit
      number = DrawilleNumbers.numeric(source[i])
      return nil if number == nil
      out.push(number)
      i += 1
    out

  -> .array_point_dimension(item)
    return item.size() if item.class_name == "Array"
    return item.components.size() if item.respond_to?("components")
    if item.respond_to?("x") && item.respond_to?("y")
      return item.respond_to?("z") ? 3 : 2
    -1

  -> .render_array(values, cols, rows)
    return header("Array", "empty numeric series") if values.size() == 0
    limit = DrawilleNumbers.bounded_cols(cols) * 2
    sampled_values = sample_values(values, limit)
    numbers = numeric_array(sampled_values)
    if numbers != nil
      detail = values.size().to_s() + " numeric samples"
      if sampled_values.size() < values.size()
        detail = "sampled " + sampled_values.size().to_s() + " of " + values.size().to_s() + " numeric samples"
      return header("Array", detail) + render_series(numbers, 0, values.size() - 1, cols, rows, false)
    points = []
    point_dimensions = []
    i = 0
    while i < sampled_values.size()
      point = array_point(sampled_values[i])
      return header("Array", "mixed or non-numeric shape") if point == nil
      points.push(point)
      point_dimensions.push(array_point_dimension(sampled_values[i]))
      i += 1
    dimension = point_dimensions[0]
    return header("Array", "ragged point shape") if point_dimensions.any? -> item != dimension
    point_count = values.size().to_s() + " points"
    if sampled_values.size() < values.size()
      point_count = "sampled " + sampled_values.size().to_s() + " of " + values.size().to_s() + " points"
    if dimension == 2
      return header("Array", point_count + " in R^2") + render_xy(points, cols, rows, true, true, false)
    if dimension >= 3
      lines = [points]
      detail = point_count + " in R^3"
      if dimension > 3
        detail = "first-three-coordinate projection of " + point_count + " from R^" + dimension.to_s()
      return header("Array", detail) + render_3d_lines(lines, cols, rows)
    header("Array", "numeric shape has dimension " + dimension.to_s())

  -> .render_3d_lines(lines, cols, rows)
    scene = DrawilleScene.new()
    bounded_lines = sample_values(lines, DrawilleNumbers.bounded_rows(rows) * 2)
    bounded_lines.each -> (line)
      bounded_line = sample_values(line, DrawilleNumbers.bounded_cols(cols) * 2)
      projected = DrawilleProjection3D.polyline(bounded_line)
      scene.polyline(projected)
    scene.render(cols, rows, false)

  -> .polynomial_terms(polynomial)
    out = []
    field_name = polynomial.ring.field.class_name
    # Integer encodings of finite/p-adic residues are representations, not
    # ordered real coordinates.  Refuse to turn them into a misleading curve.
    return nil if field_name == "FiniteField" || field_name == "PadicField"
    return nil if polynomial.terms.size() > 4096
    terms = polynomial.terms
    i = 0
    while i < terms.size()
      term = terms[i]
      coefficient = DrawilleNumbers.numeric(term[0])
      return nil if coefficient == nil
      out.push([coefficient, term[1]])
      i += 1
    out

  -> .polynomial_value(terms, coordinates, fixed_index = nil)
    total = ~0.0
    terms.each -> (term)
      value = term[0]
      source = 0
      exponent_index = 0
      while exponent_index < term[1].size()
        coordinate = ~1.0
        if fixed_index == nil || exponent_index != fixed_index
          coordinate = coordinates[source]
          source += 1
        value *= DrawilleNumbers.integer_power(coordinate, term[1][exponent_index])
        exponent_index += 1
      total += value
    total

  -> .polynomial_detail(polynomial)
    "degree " + polynomial.degree.to_s() + " over " + polynomial.ring.field.to_s()

  -> .render_polynomial(polynomial, cols, rows)
    title = header("Polynomial", polynomial_detail(polynomial))
    terms = polynomial_terms(polynomial)
    if terms == nil
      return title + "  No ordered numeric embedding is available for these coefficients.\n"
    arity = polynomial.ring.arity
    if arity == 1
      values = []
      samples = cols * 2
      i = 0
      while i < samples
        x = ~-4.0 + ~8.0 * i.to_f() / (samples - 1).to_f()
        values.push(polynomial_value(terms, [x]))
        i += 1
      return title + render_series(values, -4, 4, cols, rows, false)
    if arity == 2
      return title + "  sampled 2-D zero set (numeric approximation)\n" + render_implicit_2d(terms, nil, cols, rows)
    if arity == 3
      return title + "  sampled 3-D zero-set slices (numeric projection)\n" + render_implicit_3d(terms, cols, rows)
    title + "  Plotting is bounded to one, two, or three variables.\n"

  -> .sign_change?(left, right)
    (left <= ~0.0 && right >= ~0.0) || (left >= ~0.0 && right <= ~0.0)

  -> .absolute_number(value)
    value < ~0.0 ? ~0.0 - value : value

  # Three same-axis samples can expose an even-multiplicity zero that has no
  # sign change. Fit the local quadratic through (-1,left), (0,center), and
  # (1,right), then evaluate the original polynomial at that fitted vertex.
  # A positive offset such as g(x)^2 + 1 therefore does not become a broad
  # fictitious contour merely because its samples form a convex valley.
  -> .quadratic_valley_offset(left_value, center_value, right_value)
    return false if left_value.nan?() || center_value.nan?() || right_value.nan?()
    return false if left_value.infinite?() || center_value.infinite?() || right_value.infinite?()
    left = absolute_number(left_value)
    center = absolute_number(center_value)
    right = absolute_number(right_value)
    # Only a sampled local valley is eligible. Allowing arbitrary convex
    # triplets makes a quadratic extrapolation invent zeros on steep positive
    # quartics far away from their minimum.
    return false if center > left || center > right
    curvature = left - ~2.0 * center + right
    return nil if curvature <= ~0.0
    offset_numerator = left - right
    return nil if absolute_number(offset_numerator) > ~2.0 * curvature
    offset_numerator / (~2.0 * curvature)

  -> .polynomial_zero_near_axis?(terms, coordinates, fixed_index, axis, step,
                                 left_value, center_value, right_value)
    offset = quadratic_valley_offset(left_value, center_value, right_value)
    return false if offset == nil || offset == false
    candidate = []
    coordinates.each -> candidate.push(item)
    candidate[axis] = candidate[axis] + offset * step
    actual = absolute_number(polynomial_value(terms, candidate, fixed_index))
    return false if actual.nan?() || actual.infinite?()
    left = absolute_number(left_value)
    center = absolute_number(center_value)
    right = absolute_number(right_value)
    maximum = left
    maximum = center if center > maximum
    maximum = right if right > maximum
    # Confirm the fitted vertex against the original polynomial. This rejects
    # a merely deep positive valley while remaining invariant under scaling.
    actual <= maximum * ~0.02 + ~0.000000000001

  -> .render_implicit_2d(terms, fixed_index, cols, rows)
    cols = DrawilleNumbers.bounded_cols(cols)
    rows = DrawilleNumbers.bounded_rows(rows)
    canvas = Canvas.new(cols, rows)
    viewport = DrawilleViewport.new(canvas, ~-4.0, ~4.0, ~-4.0, ~4.0)
    values = []
    py = 0
    while py < canvas.pixel_height()
      current_row = []
      px = 0
      while px < canvas.pixel_width()
        x = ~-4.0 + ~8.0 * px.to_f() / (canvas.pixel_width() - 1).to_f()
        y = ~4.0 - ~8.0 * py.to_f() / (canvas.pixel_height() - 1).to_f()
        value = polynomial_value(terms, [x, y], fixed_index)
        current_row.push(value)
        px += 1
      values.push(current_row)
      py += 1
    py = 0
    while py < canvas.pixel_height()
      px = 0
      while px < canvas.pixel_width()
        x = ~-4.0 + ~8.0 * px.to_f() / (canvas.pixel_width() - 1).to_f()
        y = ~4.0 - ~8.0 * py.to_f() / (canvas.pixel_height() - 1).to_f()
        value = values[py][px]
        mark = value == ~0.0
        mark = true if px > 0 && sign_change?(values[py][px - 1], value)
        mark = true if py > 0 && sign_change?(values[py - 1][px], value)
        if !mark && px > 0 && px + 1 < canvas.pixel_width()
          mark = polynomial_zero_near_axis?(
            terms, [x, y], fixed_index, 0,
            ~8.0 / (canvas.pixel_width() - 1).to_f(),
            values[py][px - 1], value, values[py][px + 1])
        if !mark && py > 0 && py + 1 < canvas.pixel_height()
          mark = polynomial_zero_near_axis?(
            terms, [x, y], fixed_index, 1,
            ~-8.0 / (canvas.pixel_height() - 1).to_f(),
            values[py - 1][px], value, values[py + 1][px])
        canvas.set(px, py) if mark
        px += 1
      py += 1
    DrawilleScene.canvas_text(canvas, viewport, true) + DrawilleScene.label_line("-4", "4", cols)

  -> .render_implicit_3d(terms, cols, rows)
    scene = DrawilleScene.new()
    slices = 7
    grid = 25
    values = []
    zi = 0
    while zi < slices
      z = ~-3.0 + ~6.0 * zi.to_f() / (slices - 1).to_f()
      slice_values = []
      yi = 0
      while yi < grid
        y = ~-3.0 + ~6.0 * yi.to_f() / (grid - 1).to_f()
        current_row = []
        xi = 0
        while xi < grid
          x = ~-3.0 + ~6.0 * xi.to_f() / (grid - 1).to_f()
          value = polynomial_value(terms, [x, y, z])
          current_row.push(value)
          xi += 1
        slice_values.push(current_row)
        yi += 1
      values.push(slice_values)
      zi += 1

    zi = 0
    while zi < slices
      z = ~-3.0 + ~6.0 * zi.to_f() / (slices - 1).to_f()
      yi = 0
      while yi < grid
        y = ~-3.0 + ~6.0 * yi.to_f() / (grid - 1).to_f()
        xi = 0
        while xi < grid
          x = ~-3.0 + ~6.0 * xi.to_f() / (grid - 1).to_f()
          value = values[zi][yi][xi]
          mark = value == ~0.0
          mark = true if xi > 0 && sign_change?(values[zi][yi][xi - 1], value)
          mark = true if yi > 0 && sign_change?(values[zi][yi - 1][xi], value)
          mark = true if zi > 0 && sign_change?(values[zi - 1][yi][xi], value)
          if !mark && xi > 0 && xi + 1 < grid
            mark = polynomial_zero_near_axis?(
              terms, [x, y, z], nil, 0, ~6.0 / (grid - 1).to_f(),
              values[zi][yi][xi - 1], value, values[zi][yi][xi + 1])
          if !mark && yi > 0 && yi + 1 < grid
            mark = polynomial_zero_near_axis?(
              terms, [x, y, z], nil, 1, ~6.0 / (grid - 1).to_f(),
              values[zi][yi - 1][xi], value, values[zi][yi + 1][xi])
          if !mark && zi > 0 && zi + 1 < slices
            mark = polynomial_zero_near_axis?(
              terms, [x, y, z], nil, 2, ~6.0 / (slices - 1).to_f(),
              values[zi - 1][yi][xi], value, values[zi + 1][yi][xi])
          if mark
            point = DrawilleProjection3D.project(x, y, z)
            scene.point(point[0], point[1])
          xi += 1
        yi += 1
      zi += 1
    scene.render(cols, rows, false)

  -> .render_polynomial_ring(ring, cols, rows)
    detail = ring.arity.to_s() + " variables " + ring.names.to_s() + ", " + ring.field.to_s()
    out = header("PolynomialRing", detail)
    if ring.arity == 1
      scene = DrawilleScene.new()
      scene.segment(~-1.0, ~0.0, ~1.0, ~0.0)
      return out + scene.render(cols, rows, true)
    if ring.arity == 2
      return out + DrawilleScene.new().render(cols, rows, true)
    if ring.arity == 3
      lines = [
        [[~0.0, ~0.0, ~0.0], [~1.0, ~0.0, ~0.0]],
        [[~0.0, ~0.0, ~0.0], [~0.0, ~1.0, ~0.0]],
        [[~0.0, ~0.0, ~0.0], [~0.0, ~0.0, ~1.0]]
      ]
      return out + render_3d_lines(lines, cols, rows)
    out + "  Coordinate visualization is bounded to dimension three.\n"

  -> .render_affine_chart(chart, cols, rows)
    equation = chart.equation
    out = header("AffineChart", chart.space.coordinate_names[chart.index].to_s() + " = 1; " + polynomial_detail(equation))
    terms = polynomial_terms(equation)
    if terms == nil
      return out + "  No ordered numeric embedding is available for this chart.\n"
    out + "  sampled affine zero set (numeric approximation)\n" + render_implicit_2d(terms, chart.index, cols, rows)

  -> .render_curve(curve, cols, rows)
    out = header("Curve", "projective plane curve of degree " + curve.degree.to_s())
    out + render_affine_chart(curve.affine_chart(), cols, rows)

  -> .render_elliptic_curve(curve, cols, rows)
    out = header("EllipticCurve", "short Weierstrass plane cubic; affine chart z = 1")
    out + render_affine_chart(curve.curve.affine_chart(), cols, rows)

  -> .render_hyperelliptic_curve(curve, cols, rows)
    polynomial = curve.polynomial
    terms = polynomial_terms(polynomial)
    out = header("HyperellipticCurve", "y^2 = f(x), genus " + curve.genus.to_s())
    if terms == nil
      return out + "  No ordered numeric embedding is available for f(x).\n"
    scene = DrawilleScene.new()
    upper = []
    lower = []
    samples = cols * 2
    i = 0
    while i < samples
      x = ~-4.0 + ~8.0 * i.to_f() / (samples - 1).to_f()
      y2 = polynomial_value(terms, [x])
      if y2 >= ~0.0
        y = Math.sqrt(y2)
        upper.push([x, y])
        lower.push([x, ~0.0 - y])
      else
        # A negative radicand separates real components.  Flush the current
        # runs so the terminal plot never draws a fictitious bridge across a
        # region where the real curve has no points.
        scene.polyline(upper) if upper.size() > 0
        scene.polyline(lower) if lower.size() > 0
        upper = []
        lower = []
      i += 1
    scene.polyline(upper) if upper.size() > 0
    scene.polyline(lower) if lower.size() > 0
    out + scene.render(cols, rows, true)

  -> .projective_wireframe(dimension, cols, rows)
    if dimension == 1
      scene = DrawilleScene.new()
      scene.segment(~-1.0, ~0.0, ~1.0, ~0.0)
      scene.point(~-1.0, ~0.0)
      scene.point(~1.0, ~0.0)
      return scene.render(cols, rows, false)
    if dimension == 2
      scene = DrawilleScene.new()
      scene.polyline([[~0.0, ~1.0], [~-1.0, ~-1.0], [~1.0, ~-1.0], [~0.0, ~1.0]])
      return scene.render(cols, rows, false)
    if dimension == 3
      vertices = [
        [~-1.0, ~-1.0, ~-1.0], [~1.0, ~-1.0, ~-1.0],
        [~1.0, ~1.0, ~-1.0], [~-1.0, ~1.0, ~-1.0],
        [~-1.0, ~-1.0, ~1.0], [~1.0, ~-1.0, ~1.0],
        [~1.0, ~1.0, ~1.0], [~-1.0, ~1.0, ~1.0]
      ]
      edges = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]
      lines = []
      edges.each -> (edge)
        lines.push([vertices[edge[0]], vertices[edge[1]]])
      return render_3d_lines(lines, cols, rows)
    ""

  -> .render_projective_space(space, cols, rows)
    out = header(
      "ProjectiveSpace",
      space.to_s() + "; coordinates " + space.coordinate_names.to_s() +
      "; affine-chart scaffold, not global topology")
    if space.field.finite_field?()
      return out + "  Finite projective coordinates have no ordered real embedding.\n"
    picture = projective_wireframe(space.dimension, cols, rows)
    if picture == ""
      return out + "  Coordinate visualization is bounded to projective dimension three.\n"
    out + picture

  -> .render_projective_point(point, cols, rows)
    out = header("ProjectivePoint", "homogeneous coordinates " + point.coordinates.to_s())
    chart = point.space.coordinate_count - 1
    while chart >= 0 && point.space.field.zero?(point.coordinates[chart])
      chart -= 1
    return out + "  Invalid all-zero projective coordinates.\n" if chart < 0
    coordinates = point.dehomogenize(chart)
    if point.space.field.class_name == "FiniteField" || point.space.field.class_name == "PadicField"
      return out + "  chart " + chart.to_s() + " coordinates: " + coordinates.to_s() + " (no ordered real embedding)\n"
    numbers = numeric_array(coordinates)
    if numbers == nil
      return out + "  chart " + chart.to_s() + " coordinates: " + coordinates.to_s() + "\n"
    out += "  affine chart " + point.space.coordinate_names[chart].to_s() + " = 1\n"
    if numbers.size() == 1
      scene = DrawilleScene.new()
      scene.segment(~-1.0, ~0.0, ~1.0, ~0.0)
      scene.point(numbers[0], ~0.0)
      return out + scene.render(cols, rows, true)
    if numbers.size() == 2
      scene = DrawilleScene.new()
      scene.segment(~0.0, ~0.0, numbers[0], numbers[1])
      scene.point(numbers[0], numbers[1])
      return out + scene.render(cols, rows, true)
    if numbers.size() == 3
      return out + render_3d_lines([[[~0.0, ~0.0, ~0.0], numbers]], cols, rows)
    out + "  Affine coordinate visualization is bounded to dimension three.\n"

  -> .render_algebraic_element(element, cols, rows)
    coefficients = element.coefficients
    detail = "power-basis coefficients (coordinate view, not an embedding); field degree " + element.field.degree.to_s()
    out = header(element.class_name, detail)
    if element.field.finite_field?()
      return out + "  exact finite-field coefficients: " + bounded_array_text(coefficients) + " (no ordered real embedding)\n"
    picture = render_series(coefficients, 0, coefficients.size() - 1, cols, rows, false)
    if picture == ""
      return out + "  exact coefficients: " + bounded_array_text(coefficients) + "\n"
    out + picture

  -> .render_algebraic_real(root, cols, rows)
    lower = DrawilleNumbers.numeric(root.lower_bound)
    upper = DrawilleNumbers.numeric(root.upper_bound)
    out = header(
      "AlgebraicRealRoot",
      "root " + root.root_index.to_s() + " isolated in " + root.interval.to_s())
    if lower != nil && upper != nil
      scene = DrawilleScene.new()
      scene.segment(lower, ~0.0, upper, ~0.0)
      scene.point((lower + upper) / ~2.0, ~0.0)
      out += scene.render(cols, 4, true)
      out += DrawilleScene.label_line(root.lower_bound.to_s(), root.upper_bound.to_s(), cols)
    out + render_polynomial(root.defining_polynomial, cols, rows)

  -> .quadratic_value(base, gradient, hessian, coordinates)
    value = base
    i = 0
    while i < coordinates.size()
      value += gradient[i] * coordinates[i]
      j = 0
      while j < coordinates.size()
        value += ~0.5 * hessian[i][j] * coordinates[i] * coordinates[j]
        j += 1
      i += 1
    value

  -> .render_differential(differential, cols, rows)
    base = DrawilleNumbers.numeric(differential.value)
    gradient = numeric_array(differential.gradient)
    hessian = []
    source_hessian = differential.hessian
    row_index = 0
    while row_index < source_hessian.size()
      numeric_row = numeric_array(source_hessian[row_index])
      return header("Differential", "symbolic Hessian: " + differential.hessian.to_s()) if numeric_row == nil
      hessian.push(numeric_row)
      row_index += 1
    return header("Differential", "symbolic value or gradient") if base == nil || gradient == nil
    out = header("Differential", "second-order local model in " + differential.dimension.to_s() + " variables")
    if differential.dimension == 1
      values = []
      samples = cols * 2
      i = 0
      while i < samples
        x = ~-2.0 + ~4.0 * i.to_f() / (samples - 1).to_f()
        values.push(quadratic_value(base, gradient, hessian, [x]))
        i += 1
      return out + render_series(values, -2, 2, cols, rows, false)
    if differential.dimension == 2
      lines = []
      grid = 11
      yi = 0
      while yi < grid
        y = ~-2.0 + ~4.0 * yi.to_f() / (grid - 1).to_f()
        line = []
        xi = 0
        while xi < grid
          x = ~-2.0 + ~4.0 * xi.to_f() / (grid - 1).to_f()
          line.push([x, y, quadratic_value(base, gradient, hessian, [x, y])])
          xi += 1
        lines.push(line)
        yi += 1
      xi = 0
      while xi < grid
        x = ~-2.0 + ~4.0 * xi.to_f() / (grid - 1).to_f()
        line = []
        yi = 0
        while yi < grid
          y = ~-2.0 + ~4.0 * yi.to_f() / (grid - 1).to_f()
          line.push([x, y, quadratic_value(base, gradient, hessian, [x, y])])
          yi += 1
        lines.push(line)
        xi += 1
      return out + render_3d_lines(lines, cols, rows)
    out + "  gradient coefficients\n" + render_series(gradient, 0, gradient.size() - 1, cols, rows, false)

  -> .tensor_leaf_values(value, out, limit = 4096)
    return out if out.size() >= limit
    if value.class_name == "Array"
      i = 0
      while i < value.size() && out.size() < limit
        tensor_leaf_values(value[i], out, limit)
        i += 1
    else
      out.push(value)
    out

  -> .tensor_zero?(value)
    number = DrawilleNumbers.numeric(value)
    return number == ~0.0 if number != nil
    if value.respond_to?("simplify")
      begin
        number = DrawilleNumbers.numeric(value.simplify)
        return number == ~0.0 if number != nil
      rescue error
        return false
    false

  # A conventional sample for the standard spherical spacetime chart.
  # This is a numeric view only; it never upgrades sampled cancellation into a
  # symbolic tensor identity. Other charts retain the structural view below.
  -> .tensor_spherical_sample(field)
    names = field.chart.names
    return nil if names.size() != 4
    return nil if names[0] != :t || names[1] != :r || names[2] != :theta || names[3] != :phi
    point = {t: ~0.0, r: ~5.0, theta: ~1.5707963267948966, phi: ~0.0}
    [point, field.evaluate(point)]

  -> .tensor_numeric_leaves(value, out)
    if value.class_name == "Array"
      value.each -> (item) tensor_numeric_leaves(item, out)
      return out
    number = DrawilleNumbers.numeric(value)
    return nil if number == nil
    out.push(number)
    out

  -> .render_tensor_field(field, cols, rows)
    detail = "rank " + field.rank.to_s() + " on a " + field.dimension.to_s() + (
      "-D chart " + field.chart.names.to_s() + "; indices " + (
      field.indices.to_s()))
    out = header("TensorField", detail)
    components = field.components
    leaves = tensor_leaf_values(components, [])
    zeros = 0
    leaves.each -> (component)
      zeros += 1 if tensor_zero?(component)
    if leaves.size() == 0
      return out + "  no components\n"
    if zeros == leaves.size()
      out += "  exact zero tensor: all " + leaves.size().to_s() + " components vanish\n"
    else
      out += "  exact-zero components: " + zeros.to_s() + "/" + leaves.size().to_s() + "\n"

    sample = tensor_spherical_sample(field)
    if sample != nil
      numeric = tensor_numeric_leaves(sample[1], [])
      if numeric != nil
        maximum = ~0.0
        numeric.each -> (number)
          magnitude = number < ~0.0 ? ~0.0 - number : number
          maximum = magnitude if magnitude > maximum
        if maximum <= ~1.0e-9
          out += "  spherical-chart sample " + sample[0].to_s() + (
            ": all " + numeric.size().to_s() + " components vanish within 1e-9") + (
            " (numeric check, not a symbolic proof)\n")
        else
          out += "  spherical-chart sample " + sample[0].to_s() + (
            ": maximum component magnitude " + maximum.to_s()) + "\n"
    if field.rank != 2 || components.class_name != "Array"
      return out + "  component preview: " + bounded_array_text(leaves, 16) + "\n"

    # A rank-two tensor gets a compact component-sparsity matrix. This view is
    # deliberately structural: a symbolic nonzero is marked without inventing
    # a numeric coordinate value or choosing an evaluation point.
    out += "  component matrix (· exact zero, ● nonzero/symbolic)\n"
    row = 0
    while row < components.size()
      out += "  "
      column = 0
      while column < components[row].size()
        out += tensor_zero?(components[row][column]) ? "· " : "● "
        column += 1
      out += "\n"
      row += 1
    out

  -> .render_horizon_set(horizon_set, cols, rows)
    horizons = horizon_set.horizons
    out = header("HorizonSet", horizons.size().to_s() + " distinguished null boundary/boundaries")
    i = 0
    while i < horizons.size() && i < 8
      horizon = horizons[i]
      out += "  " + horizon.kind.to_s() + ": " + horizon.coordinate.to_s() + (
        " = " + horizon.radius.to_s())
      out += " — " + horizon.description.to_s() if horizon.description != nil
      out += "\n"
      i += 1
    return out if horizons.size() == 0
    numbers = numeric_array(horizon_set.radii)
    return out + "  symbolic horizon radii; no ordered radial plot\n" if numbers == nil
    maximum = numbers[0]
    numbers.each -> (radius)
      maximum = radius if radius > maximum
    maximum = ~1.0 if maximum <= ~0.0
    scene = DrawilleScene.new()
    scene.segment(~0.0, ~0.0, maximum * ~1.15, ~0.0)
    numbers.each -> (radius) scene.point(radius, ~0.0)
    out + scene.render(cols, rows, true) + DrawilleScene.label_line(
      "r=0", "r=" + maximum.to_s(), cols)

  -> .render_regge_wheeler(potential, cols, rows)
    certificate = potential.stability_certificate
    out = header(
      "ReggeWheelerPotential",
      "Schwarzschild axial mode l=" + potential.angular_mode.to_s() + (
        ", M=" + potential.mass.to_s()))
    out += "  V(r) = " + potential.potential_expression.to_s() + "\n"
    out += "  exterior peak: r=" + potential.peak_radius.to_s() + (
      ", V=" + potential.peak_potential.to_s()) + "\n"
    out += "  certificate: " + certificate.claim + "\n"
    out += "  scope: " + certificate.scope + "\n"
    sample_count = cols * 2
    sample_count = 32 if sample_count < 32
    sample_count = 160 if sample_count > 160
    samples = potential.samples(nil, nil, sample_count)
    out += render_xy(samples, cols, rows, true, true, false)
    out + DrawilleScene.label_line(
      samples[0][0].to_s(), samples[samples.size() - 1][0].to_s(), cols)

  -> .render_brane_bulk_chord(chord, cols, rows)
    shortcut = chord.causal_shortcut? ? "true" : "false"
    out = header(
      "BraneBulkChord",
      "spatial H^2 geodesic in a Poincare-AdS slice; separation " + (
        chord.separation.to_s()))
    out += "  AdS radius: " + chord.ads_radius.to_s() + (
      "; brane z: " + chord.brane_z.to_s()) + "\n"
    out += "  proper length: " + chord.proper_length.to_s() + "\n"
    out += "  causal shortcut?: " + shortcut + (
      " — this spatial chord is not an FTL/null-return claim\n")
    points = sample_values(chord.points, DrawilleNumbers.bounded_cols(cols) * 2)
    scene = DrawilleScene.new()
    scene.polyline(points)
    if points.size() > 1
      scene.segment(
        points[0][0], chord.brane_z,
        points[points.size() - 1][0], chord.brane_z)
    out + scene.render(cols, rows, true) + DrawilleScene.label_line(
      points[0][0].to_s(), points[points.size() - 1][0].to_s(), cols)

  # The intrinsic warped metric is dt^2 + f(t)^2 dtheta^2.  The terminal
  # wireframe uses (f(t) cos(theta), t, f(t) sin(theta)) solely as a readable
  # profile embedding; unless f is constant that Euclidean embedding is not an
  # isometry.  Keeping this construction here avoids teaching core/geometry
  # about camera angles, display horizons, or wireframe density.
  -> .warped_cone_point(surface, t, theta)
    radius = DrawilleNumbers.numeric(surface.radius(t))
    return nil if radius == nil
    [radius * Math.cos(theta), t.to_f(), radius * Math.sin(theta)]

  -> .warped_cone_display_stop(surface)
    if !surface.ideal_apex?
      height = DrawilleNumbers.numeric(surface.finite_apex_height)
      return height * ~0.97 if height != nil && height > ~0.0
    ~6.0

  -> .warped_cone_wireframe(surface, start, stop)
    lines = []
    pi = ~3.141592653589793
    ring_count = 7
    theta_count = 17
    ring = 0
    while ring < ring_count
      t = start + (stop - start) * ring.to_f() / (ring_count - 1).to_f()
      points = []
      theta_index = 0
      while theta_index < theta_count
        theta = ~2.0 * pi * theta_index.to_f() / (theta_count - 1).to_f()
        point = warped_cone_point(surface, t, theta)
        points.push(point) if point != nil
        theta_index += 1
      lines.push(points) if points.size() > 1
      ring += 1

    meridian_count = 8
    t_count = 25
    meridian = 0
    while meridian < meridian_count
      theta = ~2.0 * pi * meridian.to_f() / meridian_count.to_f()
      points = []
      t_index = 0
      while t_index < t_count
        t = start + (stop - start) * t_index.to_f() / (t_count - 1).to_f()
        point = warped_cone_point(surface, t, theta)
        points.push(point) if point != nil
        t_index += 1
      lines.push(points) if points.size() > 1
      meridian += 1
    lines

  -> .render_warped_cone_surface(surface, cols, rows)
    start = ~0.0
    stop = warped_cone_display_stop(surface)
    apex = surface.ideal_apex? ? "ideal apex at t = infinity" : (
      "finite apex at t = " + surface.finite_apex_height.to_s())
    out = header(
      "WarpedConeSurface",
      "shrink law " + surface.shrink_law.to_s() + "; " + apex)
    out += "  intrinsic metric: dt^2 + f(t)^2 dtheta^2; f(t) = " + (
      surface.radius_expression.to_s()) + "\n"

    # A one-radian pair of meridians makes the distinction visible without
    # conflating angular coverage with the metric's forced contraction.
    theta_a = ~0.0
    theta_b = ~1.0
    normalized = surface.normalized_separation(theta_a, theta_b)
    physical_start = surface.physical_separation(start, theta_a, theta_b)
    physical_stop = surface.physical_separation(stop, theta_a, theta_b)
    out += "  normalized separation Delta-theta: " + normalized.to_s() + (
      " (constant)\n")
    out += "  physical cross-section arc f(t) Delta-theta: " + (
      physical_start.to_s()) + " at t=0 -> " + physical_stop.to_s() + (
      " at t=" + stop.to_s() + " (not unrestricted geodesic distance)\n")
    out += "  non-isometric profile wireframe (display window only)\n"
    lines = warped_cone_wireframe(surface, start, stop)
    out += render_3d_lines(lines, cols, rows)
    if surface.ideal_apex?
      return out + "  displayed 0 <= t <= " + stop.to_s() + (
        "; apex remains at t = infinity\n")
    out + "  displayed 0 <= t <= " + stop.to_s() + (
      "; finite apex at t = " + surface.finite_apex_height.to_s() + "\n")

  -> .series_coefficients(value)
    return value.coefficients if value.respond_to?("coefficients")
    return value.q_expansion.coefficients if value.respond_to?("q_expansion")
    nil

  -> .render_coefficients(value, label, cols, rows)
    coefficients = series_coefficients(value)
    return header(value.class_name, label + " coefficients unavailable") if coefficients == nil
    out = header(value.class_name, label + "; " + coefficients.size().to_s() + " retained coefficients")
    if value.class_name == "FieldQExpansion" && value.coefficient_field.finite_field?()
      return out + "  exact finite-field coefficients: " + bounded_array_text(coefficients) + " (no ordered real embedding)\n"
    out + coefficient_body(coefficients, cols, rows)

  -> .coefficient_body(coefficients, cols, rows, x_lo = 0, x_hi = nil)
    upper = x_hi
    upper = x_lo + coefficients.size() - 1 if upper == nil
    picture = render_series(coefficients, x_lo, upper, cols, rows, false)
    if picture == ""
      return "  exact coefficients: " + bounded_array_text(coefficients) + "\n"
    picture

  -> .render_modular_form(value, cols, rows)
    expansion = value.q_expansion()
    coefficients = series_coefficients(expansion)
    out = header(value.class_name, "q-expansion coefficient view; q is not assigned an analytic value")
    return out + "  q-expansion coefficients unavailable\n" if coefficients == nil
    out + coefficient_body(coefficients, cols, rows)

  -> .render_formal_series(value, cols, rows)
    detail = "formal coefficient view; no convergence is implied"
    lower = 0
    upper = nil
    if value.class_name == "FormalLaurentSeries"
      detail += "; powers " + value.minimum_power.to_s() + ".." + value.maximum_power.to_s()
      lower = value.minimum_power
      upper = value.maximum_power
    elsif value.class_name == "FormalPuiseuxSeries"
      lower = value.minimum_exponent
      upper = value.maximum_exponent
      detail += "; powers " + lower.to_s() + ".." + upper.to_s()
      detail += "; ramification " + value.ramification_index.to_s()
    elsif value.respond_to?("order")
      detail += "; order " + value.order.to_s()
    coefficients = series_coefficients(value)
    out = header(value.class_name, detail)
    return out + "  formal coefficients unavailable\n" if coefficients == nil
    out + coefficient_body(coefficients, cols, rows, lower, upper)

  -> .binary(value, width)
    out = ""
    bit = width - 1
    while bit >= 0
      out += (((value >> bit) & 1) == 1 ? "1" : "0")
      bit -= 1
    out

  -> .render_theta_form(form, cols)
    dimension = form.space.dimension
    title = "ThetaQuadraticForm"
    detail = "q on F2^" + dimension.to_s() + "; Arf " + form.arf_invariant.to_s()
    if dimension > 32
      return header(title, detail + "; truth table omitted above dimension 32")
    # Never materialize a gigantic 2^dimension BigInt just to print a bound.
    # The truth-table view itself is deliberately capped at 256 entries.
    limit = 256
    total_text = "2^" + dimension.to_s()
    if dimension <= 8
      limit = 1 << dimension
      total_text = limit.to_s()
    detail += "; first " + limit.to_s() + " of " + total_text if dimension > 8
    out = header(title, detail)
    entry_width = dimension + 3
    per_line = (DrawilleNumbers.bounded_cols(cols) / entry_width)
    per_line = 1 if per_line < 1
    mask = 0
    while mask < limit
      out += "  "
      column = 0
      while column < per_line && mask < limit
        vector = form.space.vector(mask)
        out += binary(mask, dimension) + ":" + form.evaluate(vector).to_s() + " "
        column += 1
        mask += 1
      out += "\n"
    out

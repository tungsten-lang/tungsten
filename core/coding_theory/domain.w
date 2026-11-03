# Ordered evaluation domains over the packed exact FiniteField substrate.
# Input order is semantic and is preserved by every constructor and record
# adapter.  Duplicate points are rejected in expected O(n) time by their
# canonical packed Integer representation.

+ FiniteFieldEvaluationDomain
  -> new(field, points)
    __initialize_domain(field, points, false)

  -> new(field, points, raw)
    __initialize_domain(field, points, raw)

  -> .raw(field, points)
    FiniteFieldEvaluationDomain.new(field, points, true)

  -> __initialize_domain(field, points, raw)
    @field = CodingTheorySupport.require_finite_field(field)
    CodingTheorySupport.require_array(points, "evaluation-domain points")
    raise "an evaluation domain must contain at least one point" if points.size == 0
    @points = []
    @index = {}
    i = 0
    while i < points.size
      if raw
        point = CodingTheorySupport.require_element(
          @field, points[i], "evaluation-domain point")
      else
        point = @field.coerce(points[i])
      if @index[point] != nil
        raise "evaluation-domain points must be distinct"
      @index[point] = i
      @points.push(point)
      i += 1
    self

  -> .from_points(field, points)
    FiniteFieldEvaluationDomain.new(field, points)

  -> .from_raw_points(field, points)
    FiniteFieldEvaluationDomain.raw(field, points)

  # Deterministic packed-element order: 0, 1, ..., count-1.  This is a
  # representation order, not an assertion that the points form an NTT or
  # multiplicative subgroup.
  -> .canonical(field, count)
    field = CodingTheorySupport.require_finite_field(field)
    CodingTheorySupport.require_positive_integer(count, "domain size")
    if count > field.order
      raise "domain size exceeds the finite-field order"
    points = []
    i = 0
    while i < count
      points.push(field.element_from_index(i))
      i += 1
    FiniteFieldEvaluationDomain.raw(field, points)

  ro :field

  -> size
    @points.size

  -> length
    size

  -> points
    CodingTheorySupport.copy_array(@points)

  -> to_a
    points

  -> [](index)
    at(index)

  -> at(index)
    if index < 0 || index >= @points.size
      raise "evaluation-domain index out of range"
    @points[index]

  -> include?(value)
    @index[@field.coerce(value)] != nil

  -> include_raw?(value)
    point = CodingTheorySupport.require_element(
      @field, value, "evaluation-domain membership value")
    @index[point] != nil

  -> index_of(value)
    @index[@field.coerce(value)]

  -> index_of_raw(value)
    point = CodingTheorySupport.require_element(
      @field, value, "evaluation-domain lookup value")
    @index[point]

  # Apply x |-> offset + direction*x without changing parameter order.  A
  # nonzero direction makes this a bijection of the field, so distinct input
  # points remain distinct.
  -> affine_image(offset, direction)
    __affine_image_raw(@field.coerce(offset), @field.coerce(direction))

  -> affine_image_raw(offset, direction)
    offset = CodingTheorySupport.require_element(
      @field, offset, "affine-domain offset")
    direction = CodingTheorySupport.require_element(
      @field, direction, "affine-domain direction")
    __affine_image_raw(offset, direction)

  -> __affine_image_raw(offset, direction)
    if @field.zero?(direction)
      raise "affine-domain direction must be nonzero"
    image = []
    i = 0
    while i < @points.size
      image.push(@field.add(offset, @field.multiply(direction, @points[i])))
      i += 1
    FiniteFieldEvaluationDomain.raw(@field, image)

  -> ==(other)
    return false if other.class_name != "FiniteFieldEvaluationDomain"
    return false if @field != other.field
    return false if size != other.size
    i = 0
    while i < size
      return false if !@field.equal?(@points[i], other.at(i))
      i += 1
    true

  -> to_s
    text = "FiniteFieldEvaluationDomain(field=" + @field.to_s
    text += ", size=" + size.to_s + ")"
    text

  -> inspect
    to_s

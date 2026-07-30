# Projective spaces and points over supported coefficient fields.
#
# Generic dimension N is a value parameter: a projective N-space has N + 1
# homogeneous coordinates. K is a field-family tag; the constructor receives
# the actual field object. Unsupported tags are compile errors instead of
# quietly constructing a rational polynomial ring.

+ ProjectivePoint
  -> new(@space, coordinates)
    if coordinates.size != @space.coordinate_count
      raise "wrong projective coordinate count: expected " + @space.coordinate_count.to_s + ", got " + coordinates.size.to_s
    @coordinates = @space.field.normalize_projective_coordinates(coordinates)

  -> space
    @space

  -> coordinates
    @coordinates

  -> []/1
    @coordinates[@1]

  -> ==(other)
    return false if other == nil || other.class_name != "ProjectivePoint"
    return false if @space != other.space
    return false if @coordinates.size != other.coordinates.size
    i = 0
    while i < @coordinates.size
      return false if !@space.field.equal?(
        @coordinates[i], other.coordinates[i])
      i += 1
    true

  # Coordinates on the Xi != 0 affine chart, with Xi scaled to one and
  # omitted from the result.
  -> dehomogenize(index = nil)
    chart = index == nil ? @space.dimension : index
    if chart < 0 || chart >= @space.coordinate_count
      raise "projective chart index out of range"
    pivot = @space.field.normalize_element(@coordinates[chart])
    if @space.field.equal?(pivot, @space.field.zero)
      raise "projective point is not in chart " + chart.to_s
    out = []
    i = 0
    while i < @coordinates.size
      if i != chart
        out.push(@space.field.divide(
          @space.field.normalize_element(@coordinates[i]), pivot))
      i += 1
    out

  -> chart(index = nil)
    dehomogenize(index)

  -> to_s
    parts = []
    @coordinates.each -> parts.push(@space.field.element_to_s(item))
    "\[" + parts.join(":") + "\]"

  -> inspect
    to_s


+ ProjectiveSpace<K, N>
  with K in (ℚ RationalField FiniteField NumberField SimpleExtensionField)

  # The algebra surface rewrite injects the actual field object and N:
  #
  #   ProjectiveSpace<ℚ, 2>.new(:X, :Y, :Z)
  #     -> ProjectiveSpace<ℚ, 2>.new(Algebra.field("ℚ"), 2, [:X, :Y, :Z])
  #
  # Keeping metadata in ordinary runtime arguments makes both engines agree;
  # the tree-walking interpreter deliberately erases generic type arguments.
  # With no names, coordinates default to X0, ..., XN.
  -> new(coefficient_field: Field, dimension, names)
    raise "projective coordinate names must be an Array" if names.class_name != "Array"
    names = names[0] if names.size == 1 && names[0].class_name == "Array"
    initialize_projective_space(names, coefficient_field, dimension)

  -> initialize_projective_space(names, coefficient_field, dimension)
    raise "projective dimension must be nonnegative" if dimension < 0
    coefficient_field = Field.require_supported(coefficient_field)
    names = default_coordinate_names(dimension) if names.size == 0
    expected = dimension + 1
    if names.size != expected
      raise "wrong projective coordinate-name count: expected " + expected.to_s + ", got " + names.size.to_s
    @dimension = dimension
    @coordinate_names = []
    names.each -> @coordinate_names.push(item)
    @field = coefficient_field
    @ring = PolynomialRing.new(@coordinate_names, @field)
    @coords = @ring.generators
    self

  -> default_coordinate_names(dimension)
    names = []
    i = 0
    while i < dimension + 1
      names.push(("X" + i.to_s).to_sym)
      i += 1
    names

  -> dimension
    @dimension

  -> coordinate_count
    @dimension + 1

  -> coordinate_names
    @coordinate_names

  -> field
    @field

  -> ring
    @ring

  -> coords
    @coords

  -> with_coords(names)
    raise "projective coordinate names must be an Array" if names.class_name != "Array"
    class.new(@field, @dimension, names)

  -> with_coords(x0, x1)
    class.new(@field, @dimension, [x0, x1])

  -> with_coords(x0, x1, x2)
    class.new(@field, @dimension, [x0, x1, x2])

  -> with_coords(x0, x1, x2, x3)
    class.new(@field, @dimension, [x0, x1, x2, x3])

  # The Array form is unbounded in N. Exact-arity rows below preserve the
  # established low-dimensional spelling. Public points coerce external
  # scalars; point_raw is the explicit packed-element path used by finite-field
  # enumeration and other algebra internals.
  -> coerce_point_coordinates(coordinates)
    values = []
    coordinates.each -> values.push(@field.coerce(item))
    values

  -> point(coordinates)
    raise "projective coordinates must be an Array" if coordinates.class_name != "Array"
    ProjectivePoint.new(self, coerce_point_coordinates(coordinates))

  -> point(x0, x1)
    point([x0, x1])

  -> point(x0, x1, x2)
    point([x0, x1, x2])

  -> point(x0, x1, x2, x3)
    point([x0, x1, x2, x3])

  -> point_raw(coordinates)
    raise "projective coordinates must be an Array" if coordinates.class_name != "Array"
    ProjectivePoint.new(self, coordinates)

  -> point_raw(x0, x1)
    point_raw([x0, x1])

  -> point_raw(x0, x1, x2)
    point_raw([x0, x1, x2])

  -> point_raw(x0, x1, x2, x3)
    point_raw([x0, x1, x2, x3])

  -> [](coordinates)
    point(coordinates)

  -> [](x0, x1)
    point(x0, x1)

  -> [](x0, x1, x2)
    point(x0, x1, x2)

  -> [](x0, x1, x2, x3)
    point(x0, x1, x2, x3)

  -> dehomogenize(point, index = nil)
    raise "point belongs to a different projective space" if point.space != self
    point.dehomogenize(index)

  # Insert a unit coordinate at the chosen chart position.
  -> homogenize(coordinates, index = nil)
    homogenize_coordinates(coordinates, index, false)

  # Internal/raw variant for already-normalized affine coordinates.
  -> homogenize_raw(coordinates, index = nil)
    homogenize_coordinates(coordinates, index, true)

  -> homogenize_coordinates(coordinates, index, raw)
    chart = index == nil ? @dimension : index
    if chart < 0 || chart >= coordinate_count
      raise "projective chart index out of range"
    if coordinates.size != @dimension
      raise "wrong affine coordinate count: expected " + @dimension.to_s + ", got " + coordinates.size.to_s
    homogeneous = []
    source = 0
    i = 0
    while i < coordinate_count
      if i == chart
        homogeneous.push(@field.one)
      else
        value = raw ? @field.normalize_element(coordinates[source]) : @field.coerce(coordinates[source])
        homogeneous.push(value)
        source += 1
      i += 1
    point_raw(homogeneous)

  -> to_s
    "ℙ^" + @dimension.to_s + "_" + @field.to_s

  -> inspect
    to_s

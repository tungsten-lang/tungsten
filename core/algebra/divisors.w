# Exact degree-one places and small formal divisors on projective curves.
#
# This is deliberately not a general divisor-class implementation.  It
# provides the exact formal arithmetic needed to reduce known rational points
# and one certified principality decision:
#
#   div(g) = 2Q - 2P, P != Q
#
# would make g a degree-two map from C to P^1.  A smooth nonhyperelliptic
# curve of genus at least two has no such map, so 2(Q-P) is certified
# nonprincipal.  Every other nonzero principality question remains loud until
# function-field or Jacobian arithmetic can actually decide it.

+ DivisorPrincipalityResult
  -> new(@principal, @theorem, @explanation)

  -> principal?
    @principal

  -> nonprincipal?
    !@principal

  -> certified?
    true

  -> theorem
    @theorem

  -> explanation
    @explanation

  -> to_s
    status = @principal ? "principal" : "nonprincipal"
    status + " (certified: " + @theorem + ")"

  -> inspect
    to_s


# A degree-one place represented by a rational point over the curve's
# coefficient field.  The ProjectivePoint is always rehomed into curve.space;
# source-space ownership never leaks into the formal divisor layer.
+ Place
  -> new(@curve, point)
    if point.class_name != "ProjectivePoint"
      raise "a degree-one place needs a ProjectivePoint"
    if point.space != @curve.space
      raise "place point must belong to the curve's projective space"
    if !@curve.contains?(point)
      raise "point is not on the curve"
    @point = point

  -> curve
    @curve

  -> space
    @curve.space

  -> point
    @point

  -> coordinates
    @point.coordinates

  -> degree
    1

  -> rational?
    true

  -> to_divisor
    Divisor.new(@curve, [[1, self]])

  -> -/1
    other = @1
    if other.class_name != "Place"
      raise "a place can only be subtracted from another place"
    if other.curve != @curve
      raise "places belong to different curves"
    Divisor.new(@curve, [[1, self], [-1, other]])

  -> */1
    to_divisor.multiply(@1)

  -> ==/1
    self.eql?(@1)

  -> eql?(other)
    return false if other.class_name != "Place"
    @curve == other.curve && @point == other.point

  -> to_s
    @point.to_s

  -> inspect
    "Place(" + to_s + ")"


# A normalized finite formal sum sum n_P P.  Terms are kept in insertion order
# because the first tranche only handles very small divisors; normalization
# combines equal places and removes zero coefficients exactly.
+ Divisor
  -> new(@curve, terms)
    raise "divisor terms must be an Array" if terms.class_name != "Array"
    @terms = []
    term_index = 0
    while term_index < terms.size
      term = terms[term_index]
      if term.class_name != "Array" || term.size != 2
        raise "a divisor term must be [coefficient, place]"
      coefficient = term[0]
      place = term[1]
      coefficient_class = coefficient.class_name
      if coefficient_class != "Integer" && coefficient_class != "Int" && coefficient_class != "BigInt"
        raise "divisor coefficients must be integers"
      if place.class_name != "Place"
        raise "a divisor term needs a Place"
      if place.curve != @curve
        raise "divisor place belongs to a different curve"
      add_normalized_term(coefficient, place) if coefficient != 0
      term_index += 1
    compact_zero_terms

  -> curve
    @curve

  -> terms
    out = []
    i = 0
    while i < @terms.size
      out.push([@terms[i][0], @terms[i][1]])
      i += 1
    out

  -> each_term(&)
    @terms.each -> (term)
      &(term[0], term[1])
    self

  -> add_normalized_term(coefficient, place)
    i = 0
    while i < @terms.size
      if @terms[i][1].eql?(place)
        @terms[i][0] = @terms[i][0] + coefficient
        return
      i += 1
    @terms.push([coefficient, place])

  -> compact_zero_terms
    out = []
    i = 0
    while i < @terms.size
      out.push(@terms[i]) if @terms[i][0] != 0
      i += 1
    @terms = out
    self

  -> coefficient(place)
    if place.class_name != "Place" || place.curve != @curve
      raise "place belongs to a different curve"
    i = 0
    while i < @terms.size
      return @terms[i][0] if @terms[i][1].eql?(place)
      i += 1
    0

  -> degree
    result = 0
    i = 0
    while i < @terms.size
      result += @terms[i][0] * @terms[i][1].degree
      i += 1
    result

  -> zero?
    @terms.size == 0

  -> negate
    out = []
    i = 0
    while i < @terms.size
      out.push([0 - @terms[i][0], @terms[i][1]])
      i += 1
    Divisor.new(@curve, out)

  -> -@
    negate

  -> +/1
    other = @1
    if other.class_name == "Place"
      other = other.to_divisor
    if other.class_name != "Divisor"
      raise "divisor addition needs a Divisor or Place"
    if other.curve != @curve
      raise "divisors belong to different curves"
    Divisor.new(@curve, terms + other.terms)

  -> -/1
    other = @1
    if other.class_name == "Place"
      other = other.to_divisor
    if other.class_name != "Divisor"
      raise "divisor subtraction needs a Divisor or Place"
    if other.curve != @curve
      raise "divisors belong to different curves"
    self + other.negate

  -> multiply(scalar)
    scalar_class = scalar.class_name
    if scalar_class != "Integer" && scalar_class != "Int" && scalar_class != "BigInt"
      raise "divisor scalar multiplication needs an integer"
    out = []
    i = 0
    while i < @terms.size
      out.push([@terms[i][0] * scalar, @terms[i][1]])
      i += 1
    Divisor.new(@curve, out)

  -> */1
    multiply(@1)

  -> ==/1
    self.eql?(@1)

  -> eql?(other)
    return false if other.class_name != "Divisor"
    return false if @curve != other.curve
    return false if @terms.size != other.terms.size
    i = 0
    while i < @terms.size
      return false if other.coefficient(@terms[i][1]) != @terms[i][0]
      i += 1
    true

  # Return a theorem-backed result, or raise if this formal divisor is outside
  # the small certified decision surface.
  -> principality
    if zero?
      return DivisorPrincipalityResult.new(
        true,
        "zero divisor",
        "The zero divisor is div(1).")

    positive = nil
    negative = nil
    if @terms.size == 2
      i = 0
      while i < @terms.size
        positive = @terms[i][1] if @terms[i][0] == 2
        negative = @terms[i][1] if @terms[i][0] == -2
        i += 1

    if positive != nil && negative != nil && !positive.eql?(negative)
      if @curve.field.characteristic == 2
        raise "principality of 2(Q-P) is undecided in characteristic two"
      if !@curve.nonsingular?
        raise "principality of 2(Q-P) requires a smooth curve"
      if @curve.genus < 2
        raise "principality of 2(Q-P) is undecided for genus below two"
      if @curve.hyperelliptic?
        raise "principality of 2(Q-P) is undecided on a hyperelliptic curve"
      explanation = "If div(g)=2Q-2P with P!=Q, g defines a degree-two map to P^1; a smooth nonhyperelliptic curve of genus at least two has no such map."
      return DivisorPrincipalityResult.new(
        false,
        "nonhyperelliptic degree-two-map obstruction",
        explanation)

    raise "principality is only certified for zero and exactly 2(Q-P) on a smooth nonhyperelliptic curve of genus at least two"

  -> principal_result
    principality

  -> principal?
    principality.principal?

  -> to_s
    return "0" if zero?
    parts = []
    i = 0
    while i < @terms.size
      parts.push(@terms[i][0].to_s + "*" + @terms[i][1].to_s)
      i += 1
    parts.join(" + ")

  -> inspect
    "Divisor(" + to_s + ")"


+ Curve
  # Construct a rational degree-one place. Raw coordinate arrays are external
  # field values and use Field#coerce. A ProjectivePoint over the same field is
  # rehomed by preserving its already-normalized elements. A rational point
  # may also be reduced into a finite curve, coordinate by coordinate.
  -> place(value)
    point = nil
    target_space = space
    target_field = field
    if value.class_name == "Array"
      converted = []
      i = 0
      while i < value.size
        converted.push(target_field.coerce(value[i]))
        i += 1
      point = target_space.point_raw(converted)
    elsif value.class_name == "ProjectivePoint"
      if value.space == target_space
        point = value
      elsif value.space.coordinate_count != target_space.coordinate_count
        raise "cannot rehome a point with a different coordinate count"
      elsif value.space.field == target_field
        point = target_space.point_raw(value.coordinates)
      elsif value.space.field.class_name == "RationalField" && target_field.class_name == "FiniteField"
        converted = []
        source_coordinates = value.coordinates
        i = 0
        while i < source_coordinates.size
          converted.push(target_field.coerce(source_coordinates[i]))
          i += 1
        point = target_space.point_raw(converted)
      else
        raise "cannot coerce a projective point across these coefficient fields"
    else
      raise "Curve#place needs a ProjectivePoint or coordinate Array"

    if !contains?(point)
      raise "point is not on the curve"
    Place.new(self, point)

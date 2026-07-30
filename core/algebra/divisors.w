# Exact rational and line-presented closed places, with small formal divisors
# on projective curves.
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
# coefficient field. ClosedPlace below extends the same arithmetic protocol
# for higher residue degrees. The ProjectivePoint is always rehomed into
# curve.space; source-space ownership never leaks into the formal divisor
# layer.
+ Place
  -> .place?(value)
    return false if value == nil
    name = value.class_name
    name == "Place" || name == "ClosedPlace"

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

  -> residue_degree
    degree

  -> rational?
    true

  -> closed?
    true

  -> to_divisor
    Divisor.new(@curve, [[1, self]])

  -> -/1
    other = @1
    if !Place.place?(other)
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


# A higher-degree closed point obtained from an irreducible factor of a
# line-restricted plane curve. The presentation records the affine chart on
# the parameter P^1 and the complete certified factorization of that
# restriction. Degree-one factors are deliberately materialized as ordinary
# Place objects instead.
#
# Two distinct base-field lines cannot contain the same non-rational closed
# point of P^2: their intersection would be a base-field-rational point.
# Consequently [line, chart, irreducible factor] is an intrinsic equality key
# for the higher-degree places represented here.
+ ClosedPlace
  -> new(@curve, @line, factor, @parameter_chart, @factorization)
    if factor.class_name != "Polynomial" || factor.ring.arity != 1
      raise "a closed place needs a univariate defining polynomial"
    @factor = factor.monic
    @residue_field_cache = nil
    @residue_curve_cache = nil
    @residue_point_cache = nil
    if @factor.degree <= 1
      raise "degree-one factors must be represented by rational Place objects"
    if !certified?
      raise "closed-place presentation failed certification"

  -> line
    @line

  -> curve
    @curve

  -> space
    @curve.space

  -> parameter_chart
    @parameter_chart

  -> defining_polynomial
    @factor

  -> residue_polynomial
    @factor

  -> factorization
    @factorization

  -> factorization_certificate
    @factorization.certificate

  -> degree
    @factor.degree

  -> residue_degree
    degree

  -> rational?
    false

  -> closed?
    true

  -> to_divisor
    Divisor.new(@curve, [[1, self]])

  -> -/1
    other = @1
    if !Place.place?(other)
      raise "a place can only be subtracted from another place"
    if other.curve != @curve
      raise "places belong to different curves"
    Divisor.new(@curve, [[1, self], [-1, other]])

  -> */1
    to_divisor.multiply(@1)

  -> ==/1
    self.eql?(@1)

  -> point
    residue_point

  -> coordinates
    residue_point.coordinates

  -> residue_field
    if @residue_field_cache == nil
      @residue_field_cache = SimpleExtensionField.new(
        @factor, @factor.ring.names[0])
    @residue_field_cache

  -> residue_curve
    if @residue_curve_cache == nil
      @residue_curve_cache = @curve.change_field(residue_field)
    @residue_curve_cache

  -> residue_space
    residue_curve.space

  -> residue_line
    extension = residue_field
    coefficients = []
    @line.coefficients.each ->
      coefficients.push(extension.embed_from(@curve.field, item))
    Line.raw(residue_space, coefficients)

  # The residue generator is the affine line parameter satisfying the
  # irreducible defining polynomial. Evaluating the exact P^1
  # parameterization realizes the closed point on the base-changed curve.
  -> residue_point
    if @residue_point_cache == nil
      extension = residue_field
      parameter_ring = PolynomialRing.new(
        @line.parameter_ring.names, extension)
      parameters = @parameter_chart == 1 ? [extension.generator, extension.one] : [extension.one, extension.generator]
      coordinates = []
      @line.parameterization.each ->
        lifted = item.change_ring(parameter_ring)
        coordinates.push(lifted.evaluate_raw(parameters))
      candidate = residue_space.point_raw(coordinates)
      if !residue_curve.contains?(candidate)
        raise "closed-place residue point does not lie on the base-changed curve"
      @residue_point_cache = candidate
    @residue_point_cache

  -> residue_certificate
    ClosedPlaceResidueCertificate.new(self)

  -> residue_coordinates_certified?
    residue_certificate.verified?

  -> certified?
    return false if @curve.class_name != "Curve"
    return false if @line.class_name != "Line" || @line.space != @curve.space
    return false if @parameter_chart != 0 && @parameter_chart != 1
    return false if @factorization.class_name != "PolynomialFactorization"
    return false if !@factorization.certified?
    source = @line.affine_restriction(
      @curve.equation, @parameter_chart)
    return false if !@factorization.polynomial.eql?(source)
    return false if @factor.ring != source.ring || @factor.degree <= 1
    found = false
    @factorization.factors.each ->
      if item.degree > 0 && item.monic.eql?(@factor)
        found = true
    found

  -> eql?(other)
    return false if other.class_name != "ClosedPlace"
    return false if @curve != other.curve
    return false if !@line.eql?(other.line)
    return false if @parameter_chart != other.parameter_chart
    @factor.eql?(other.defining_polynomial)

  -> to_s
    label = "ClosedPlace(deg " + degree.to_s + ", "
    label + @factor.to_s + " on " + @line.to_s + ")"

  -> inspect
    to_s


+ ClosedPlaceResidueCertificate
  -> new(@place)

  -> place
    @place

  -> field
    @place.residue_field

  -> point
    @place.residue_point

  -> verified?
    return false if @place.class_name != "ClosedPlace"
    return false if !@place.certified?
    extension = @place.residue_field
    return false if extension.class_name != "SimpleExtensionField"
    return false if extension.base_field != @place.curve.field
    return false if extension.degree != @place.degree
    return false if !extension.defining_polynomial.eql?(
      @place.defining_polynomial)
    return false if !extension.modulus_certificate.verified?
    point = @place.residue_point
    return false if point.space != @place.residue_space
    return false if !@place.residue_curve.contains?(point)
    return false if !@place.residue_line.contains?(point)
    extension.zero?(
      extension.defining_polynomial.change_ring(
        PolynomialRing.new(
          extension.defining_polynomial.ring.names,
          extension)).at_raw(extension.generator))

  -> certified?
    verified?

  -> to_s
    label = "ClosedPlaceResidueCertificate(degree "
    label + @place.degree.to_s + ")"

  -> inspect
    to_s


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
      if !Place.place?(place)
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
    if !Place.place?(place) || place.curve != @curve
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
    if Place.place?(other)
      other = other.to_divisor
    if other.class_name != "Divisor"
      raise "divisor addition needs a Divisor or Place"
    if other.curve != @curve
      raise "divisors belong to different curves"
    Divisor.new(@curve, terms + other.terms)

  -> -/1
    other = @1
    if Place.place?(other)
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

# Good-reduction p-adic residue disks on rational plane curves.
#
# A smooth proper model over Z_p partitions C(Q_p) by reduction to C(F_p).
# This layer certifies the finite special fiber and its smooth points. It does
# not yet claim local constancy of a descent function on each disk.

+ PadicCurveResidueDisk
  -> new(@curve, @padic_field, @reduction_curve, @reduction_point)
    if @curve.class_name != "Curve"
      raise "p-adic residue disk needs a Curve"
    if @curve.field.class_name != "RationalField"
      raise "p-adic residue disks currently need a rational curve"
    if @padic_field.class_name != "PadicField"
      raise "p-adic residue disk needs a PadicField"
    if @reduction_curve.class_name != "Curve"
      raise "p-adic residue disk needs a reduction curve"
    if @reduction_point.class_name != "ProjectivePoint"
      raise "p-adic residue disk needs a projective reduction point"
    if @reduction_point.space != @reduction_curve.space
      raise "p-adic residue point belongs to a different curve"
    if !@reduction_curve.contains?(@reduction_point)
      raise "p-adic residue point is not on the reduced curve"

  -> curve
    @curve

  -> padic_field
    @padic_field

  -> prime
    @padic_field.prime

  -> precision
    @padic_field.precision

  -> reduction_curve
    @reduction_curve

  -> reduction_point
    @reduction_point

  -> coordinates
    @reduction_point.coordinates

  -> smooth?
    gradient = []
    index = 0
    while index < 3
      derivative = @reduction_curve.equation.derivative(index)
      gradient.push(derivative.evaluate(coordinates))
      index += 1
    gradient.any? -> !@reduction_curve.field.zero?(item)

  -> key
    coordinates.to_s

  -> to_s
    text = "Q_" + prime.to_s + " residue disk above "
    text + @reduction_point.to_s

  -> inspect
    to_s


+ PadicCurveResidueDiskCoverCertificate
  -> new(@cover)
    @verified_cache = nil

  -> theorem
    "smooth proper reduction partitions C(Q_p) into nonempty residue disks indexed by C(F_p)"

  -> theorem_reference
    "valuative criterion for properness and multivariate Hensel lemma"

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> verify!
    expected = "PadicCurveResidueDiskCover"
    return false if @cover.class_name != expected
    curve = @cover.curve
    return false if curve.field.class_name != "RationalField"
    reduction = @cover.reduction_curve
    expected_reduction = curve.reduce(@cover.prime)
    return false if !reduction.equation.eql?(
      expected_reduction.equation)
    return false if !reduction.nonsingular?
    disks = @cover.disks
    return false if disks.size != reduction.point_count
    keys = {}
    disks.each -> (disk)
      return false if disk.curve != curve
      return false if disk.padic_field != @cover.padic_field
      return false if disk.reduction_curve != reduction
      return false if !disk.smooth?
      return false if keys.has_key?(disk.key)
      keys[disk.key] = true
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_smooth_proper_hensel_cover

  -> kernel_checked?
    false

  -> finite_special_fiber_replayed?
    true

  -> local_descent_constancy_checked?
    false


+ PadicCurveResidueDiskCover
  -> new(@curve, @prime, @precision = 20)
    if @curve.class_name != "Curve"
      raise "p-adic residue-disk cover needs a Curve"
    if @curve.field.class_name != "RationalField"
      raise "p-adic residue-disk cover currently needs a rational curve"
    @padic_field = PadicField.new(@prime, @precision)
    @reduction_curve = @curve.reduce(@prime)
    if !@reduction_curve.nonsingular?
      raise "focused p-adic residue-disk cover needs good reduction"
    @disks = enumerate_disks
    @certificate_cache = PadicCurveResidueDiskCoverCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise "p-adic residue-disk cover failed certification"

  -> curve
    @curve

  -> prime
    @prime

  -> precision
    @precision

  -> padic_field
    @padic_field

  -> reduction_curve
    @reduction_curve

  -> disks
    out = []
    @disks.each -> out.push(item)
    out

  -> enumerate_disks
    field = @reduction_curve.field
    space = @reduction_curve.space
    out = []

    y_index = 0
    while y_index < field.order
      y = field.element_from_index(y_index)
      x_index = 0
      while x_index < field.order
        x = field.element_from_index(x_index)
        point = space.point([x, y, field.one])
        if @reduction_curve.contains?(point)
          out.push(PadicCurveResidueDisk.new(
            @curve, @padic_field,
            @reduction_curve, point))
        x_index += 1
      y_index += 1

    x_index = 0
    while x_index < field.order
      x = field.element_from_index(x_index)
      point = space.point([x, field.one, field.zero])
      if @reduction_curve.contains?(point)
        out.push(PadicCurveResidueDisk.new(
          @curve, @padic_field,
          @reduction_curve, point))
      x_index += 1
    point = space.point([field.one, field.zero, field.zero])
    if @reduction_curve.contains?(point)
      out.push(PadicCurveResidueDisk.new(
        @curve, @padic_field,
        @reduction_curve, point))
    out

  -> certificate
    @certificate_cache

  -> certified?
    certificate.verified?

  -> local_descent_image_certified?
    false


+ Curve
  -> p_adic_residue_disks(prime, precision = 20)
    PadicCurveResidueDiskCover.new(
      self, prime, precision)

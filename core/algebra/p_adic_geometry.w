# Smooth p-adic residue disks on rational plane curves.
#
# A smooth proper model over Z_p partitions C(Q_p) by reduction to C(F_p).
# At bad reduction, the smooth points still define nonempty Hensel disks, but
# singular residue classes require refinement. This layer certifies both the
# complete good-reduction cover and the complete smooth locus at an arbitrary
# prime. It does not by itself claim local constancy of a descent function.

+ PadicCurveSpecialFiberArithmetic
  -> .points(reduction_curve)
    field = reduction_curve.field
    space = reduction_curve.space
    out = []

    y_index = 0
    while y_index < field.order
      y = field.element_from_index(y_index)
      x_index = 0
      while x_index < field.order
        x = field.element_from_index(x_index)
        point = space.point_raw([x, y, field.one])
        out.push(point) if reduction_curve.contains?(point)
        x_index += 1
      y_index += 1

    x_index = 0
    while x_index < field.order
      x = field.element_from_index(x_index)
      point = space.point_raw([x, field.one, field.zero])
      out.push(point) if reduction_curve.contains?(point)
      x_index += 1
    point = space.point_raw([field.one, field.zero, field.zero])
    out.push(point) if reduction_curve.contains?(point)
    out

  -> .smooth?(reduction_curve, point)
    index = 0
    while index < reduction_curve.space.coordinate_count
      derivative = reduction_curve.equation.derivative(index)
      value = derivative.evaluate_raw(point.coordinates)
      return true if !reduction_curve.field.zero?(value)
      index += 1
    false

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
    PadicCurveSpecialFiberArithmetic.smooth?(
      @reduction_curve, @reduction_point)

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
    out = []
    PadicCurveSpecialFiberArithmetic.points(
      @reduction_curve).each -> (point)
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


+ PadicCurveSmoothResidueDiskCoverCertificate
  -> new(@cover)
    @verified_cache = nil
    @failure_reason = nil

  -> reject(reason)
    @failure_reason = reason
    false

  -> failure_reason
    @failure_reason

  -> theorem
    "every smooth special-fiber point defines a nonempty p-adic residue disk"

  -> theorem_reference
    "multivariate Hensel lemma"

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
    expected = "PadicCurveSmoothResidueDiskCover"
    return reject("wrong cover class") if @cover.class_name != expected
    curve = @cover.curve
    if curve.field.class_name != "RationalField"
      return reject("wrong curve field")
    reduction = @cover.reduction_curve
    if !reduction.equation.eql?(
         curve.reduce(@cover.prime).equation)
      return reject("reduction equation changed")
    points = PadicCurveSpecialFiberArithmetic.points(
      reduction)
    expected_points = []
    points.each -> expected_points.push(item.to_s)
    supplied_points = []
    @cover.special_fiber_points.each ->
      supplied_points.push(item.to_s)
    if expected_points.to_s != supplied_points.to_s
      return reject("special-fiber point list changed")

    smooth_keys = []
    singular_keys = []
    points.each -> (point)
      key = point.coordinates.to_s
      if PadicCurveSpecialFiberArithmetic.smooth?(
           reduction, point)
        smooth_keys.push(key)
      else
        singular_keys.push(key)
    disks = @cover.disks
    if disks.size != smooth_keys.size
      return reject("smooth disk count changed")
    disk_keys = []
    disks.each -> (disk)
      return reject("disk curve changed") if disk.curve != curve
      if disk.padic_field != @cover.padic_field
        return reject("disk p-adic field changed")
      if disk.reduction_curve != reduction
        return reject("disk reduction changed")
      return reject("listed disk is singular") if !disk.smooth?
      disk_keys.push(disk.key)
    if disk_keys.to_s != smooth_keys.to_s
      return reject("smooth disk list changed")
    singular = @cover.singular_points
    if singular.size != singular_keys.size
      return reject("singular point count changed")
    supplied_singular_keys = []
    singular.each -> (point)
      supplied_singular_keys.push(point.coordinates.to_s)
    if supplied_singular_keys.to_s != singular_keys.to_s
      return reject("singular point list changed")
    true

  -> certified?
    verified?

  -> proof_kind
    :trusted_smooth_locus_hensel_disks

  -> kernel_checked?
    false

  -> finite_special_fiber_replayed?
    true

  -> complete_curve_cover?
    @cover.singular_points.size == 0


+ PadicCurveSmoothResidueDiskCover
  -> new(@curve, @prime, @precision = 20)
    if @curve.class_name != "Curve"
      raise "p-adic smooth-locus cover needs a Curve"
    if @curve.field.class_name != "RationalField"
      raise "p-adic smooth-locus cover currently needs a rational curve"
    @padic_field = PadicField.new(@prime, @precision)
    @reduction_curve = @curve.reduce(@prime)
    @special_fiber_points = PadicCurveSpecialFiberArithmetic.points(
      @reduction_curve)
    @disks = []
    @singular_points = []
    @special_fiber_points.each -> (point)
      if PadicCurveSpecialFiberArithmetic.smooth?(
           @reduction_curve, point)
        @disks.push(PadicCurveResidueDisk.new(
          @curve, @padic_field,
          @reduction_curve, point))
      else
        @singular_points.push(point)
    @certificate_cache = PadicCurveSmoothResidueDiskCoverCertificate.new(
      self)
    if !@certificate_cache.verified?
      raise ("p-adic smooth-locus cover failed certification: " +
             @certificate_cache.failure_reason.to_s)

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

  -> special_fiber_points
    out = []
    @special_fiber_points.each -> out.push(item)
    out

  -> disks
    out = []
    @disks.each -> out.push(item)
    out

  -> singular_points
    out = []
    @singular_points.each -> out.push(item)
    out

  -> smooth_point_count
    @disks.size

  -> singular_point_count
    @singular_points.size

  -> complete_curve_cover?
    @singular_points.size == 0

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

  -> p_adic_smooth_residue_disks(prime, precision = 20)
    PadicCurveSmoothResidueDiskCover.new(
      self, prime, precision)

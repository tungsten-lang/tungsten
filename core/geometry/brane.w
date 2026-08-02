# Static Randall-Sundrum / Poincare-AdS geometry and its bulk paths.

+ BulkNullReturnCertificate
  -> new(@ads_radius)
    if @ads_radius.to_f <= ~0.0
      raise "bulk null-return certificate requires positive AdS radius"

  -> ads_radius
    @ads_radius

  -> curvature_scale
    ~1.0 / @ads_radius.to_f

  -> certified?
    @ads_radius.to_f > ~0.0

  -> returns_to_brane?
    false

  -> shortcut?
    false

  -> assumptions
    ["static warped vacuum", "flat brane", "null geodesic", "positive curvature scale"]

  -> derivation
    "With ds^2=e^(-2ky)(-dt^2+dx^2)+dy^2, conserved E and P give " + (
      "(dy/dlambda)^2=(E^2-P^2)e^(2ky). If E^2>P^2 then " + (
      "|dy/dlambda| is everywhere positive, so continuity fixes its sign; " + (
      "if E^2=P^2 then dy/dlambda is identically zero. A null geodesic " + (
      "starting and ending at y=0 must therefore remain on the brane."))))

  -> conclusion
    "no nontrivial returning brane-to-brane null chord exists in the static RS vacuum"

  -> to_s
    "BulkNullReturnCertificate(no static returning null shortcut)"

  -> inspect
    to_s


+ BraneBulkChord
  -> new(@ads_radius, @brane_z, @separation, @sample_count = 121)
    if @ads_radius.to_f <= ~0.0 || @brane_z.to_f <= ~0.0
      raise "AdS radius and brane position must be positive"
    if @separation.to_f < ~0.0
      raise "brane endpoint separation must be nonnegative"
    if !Expression.integer?(@sample_count) || @sample_count < 2
      raise "bulk chord needs an integer sample count of at least two"

  -> ads_radius
    @ads_radius

  -> brane_z
    @brane_z

  -> separation
    @separation

  -> euclidean_radius
    half = @separation.to_f / ~2.0
    Math.sqrt(half*half + @brane_z.to_f*@brane_z.to_f)

  # The constant-time H^2 geodesic in Poincare coordinates.  This is a
  # spatial visualization, not an FTL or causal shortcut.
  -> points
    half = @separation.to_f / ~2.0
    radius = self.euclidean_radius
    out = []
    i = 0
    while i < @sample_count
      x = ~0.0 - half + @separation.to_f * (
        i.to_f / (@sample_count - 1).to_f)
      z = Math.sqrt(radius*radius - x*x)
      out.push([x, z])
      i += 1
    out

  -> proper_length
    ~2.0 * @ads_radius.to_f * Math.asinh(
      @separation.to_f / (~2.0 * @brane_z.to_f))

  -> null_return_certificate
    BulkNullReturnCertificate.new(@ads_radius)

  -> causal_shortcut?
    false

  -> to_s
    "BraneBulkChord(spatial H2 geodesic, separation=" + (
      @separation.to_s) + "; no static null shortcut)"

  -> inspect
    to_s


+ RandallSundrumSpacetime
  -> new(@ads_radius = 1, @brane_z = nil)
    if @ads_radius.to_f <= ~0.0
      raise "AdS radius must be positive"
    @brane_z = @ads_radius if @brane_z == nil
    if @brane_z.to_f <= ~0.0
      raise "brane z coordinate must be positive"
    @chart = Chart.new([:t, :x, :y, :w, :z])
    t, x, y, w, z = @chart.coordinates
    scale = (Expression.wrap(@ads_radius) / z)**2
    zero = Geometry.zero
    @metric = Metric.new(@chart, [
      [-scale, zero, zero, zero, zero],
      [zero, scale, zero, zero, zero],
      [zero, zero, scale, zero, zero],
      [zero, zero, zero, scale, zero],
      [zero, zero, zero, zero, scale]
    ], [-1, 1, 1, 1, 1])

  -> ads_radius
    @ads_radius

  -> brane_z
    @brane_z

  -> chart
    @chart

  -> metric
    @metric

  -> curvature
    @metric.curvature

  -> bulk_chord(separation, sample_count = 121)
    BraneBulkChord.new(@ads_radius, @brane_z, separation, sample_count)

  -> null_return_certificate
    BulkNullReturnCertificate.new(@ads_radius)

  -> to_s
    "RandallSundrumSpacetime(static Poincare-AdS5 probe brane; L=" + (
      @ads_radius.to_s) + ", z_brane=" + @brane_z.to_s + ")"

  -> inspect
    to_s


+ RandallSundrum
  -> .new(ads_radius = 1, brane_z = nil)
    RandallSundrumSpacetime.new(ads_radius, brane_z)

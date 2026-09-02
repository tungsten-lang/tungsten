# Chabauty--Coleman for a smooth plane quartic with a one-point C_(3,4)
# model at a prime of good reduction, rank-one Jacobian, and known rational
# points.  Independent second implementation of the shell-width computation:
# it shares only certified finite inputs with the retained engine (the
# residue-disk cover, the L(W oo) monomial basis from the C_ab model, and
# #J(F_p) from the zeta function) and rebuilds every analytic step on
# `core/algebra/p_adic_series`:
#
#   * disk charts prefer to solve the x-coordinate as a series in y - y_0
#     (the retained engine prefers the opposite), coordinate expansions are
#     Newton iterations on series verified against the equation, and the
#     infinity disk uses the chart y = 1 with sigma = x/y as parameter;
#   * N [c - Q2] with N = #J(F_p) lies in the kernel of reduction, and a
#     function h in L(W oo), W = N + 2g, vanishing to order N at c and at g
#     auxiliary points gives N [c - Q2] = [Lambda_(Q2) - Lambda_c] with
#     effective divisors of degree 2g paired disk by disk, so every Coleman
#     integral needed is a tiny integral inside one residue disk;
#   * the interpolation kernel is computed over Z/p^K with its dimension and
#     digit loss reported, Weierstrass factors come from digitwise Hensel
#     lifting, root power sums from Newton's identities, zero counts from
#     the p-adic Newton polygon with an explicit tail floor, and every
#     precision statement is carried on the series rather than compared
#     against a hand-set slack;
#   * an internal cross-check moves one disk center along its own parameter
#     and verifies that the interpolated logarithms differ by the direct tiny
#     integral, to the digits the pipeline claims.
#
# Trusted inputs, named: good reduction at p; rank J(Q) = 1 with the
# difference of two known points nontorsion (so the annihilating
# differentials of that class annihilate the whole Q_p-span of J(Q)); the
# list of known rational points.  The engine proves nothing beyond "the
# curve has exactly these rational points, given those inputs"; the result
# object records every digit floor it used.

use core/algebra/p_adic_series
use core/algebra/c_ab
use core/algebra/p_adic_geometry
use core/algebra/zeta

+ ColemanDisk
  -> new(@name, @kind, center, coordinate_series, @omega, @columns,
         @known_index, @zeta_tilde)
    @center_x = center[0]
    @center_y = center[1]
    @x_series = coordinate_series[0]
    @y_series = coordinate_series[1]
    @antiderivatives = nil

  -> antiderivatives
    @antiderivatives

  -> set_antiderivatives(list)
    @antiderivatives = list

  -> name
    @name

  # Residue disk identity: shifted centers share the key of their disk.
  -> residue_key
    key = @name
    key = key.slice(0, key.size - 1) if key.ends_with?("+")
    key

  # :x_chart  parameter t = x - x_0, y a series in t
  # :y_chart  parameter t = y - y_0, x a series in t
  # :infinity parameter sigma = x/y at the hyperflex
  -> kind
    @kind

  -> infinity?
    @kind == :infinity

  -> center_x
    @center_x

  -> center_y
    @center_y

  -> x_series
    @x_series

  -> y_series
    @y_series

  -> omega
    @omega

  -> columns
    @columns

  -> known_index
    @known_index

  -> known?
    @known_index != nil

  -> zeta_tilde
    @zeta_tilde

  # Affine coordinates of the point at parameter value t (affine disks only).
  -> point_at(t)
    raise "infinity disk points are not affine" if infinity?
    [@x_series.evaluate(t), @y_series.evaluate(t)]

  -> to_s
    "Coleman disk " + @name + " (" + @kind.to_s + ")"

  -> inspect
    to_s


+ ColemanChabauty
  -> new(@model, @prime, @precision, known_points, base_index = nil)
    if @model.class_name != "CAbCurveModel"
      raise "Chabauty--Coleman needs a CAbCurveModel"
    raise "Chabauty--Coleman needs an odd prime" if @prime < 3 || @prime % 2 == 0
    raise "Chabauty--Coleman needs precision >= 12" if @precision < 12
    @curve = @model.curve
    @degree = @curve.degree
    raise "this engine handles smooth plane quartics" if @degree != 4
    @genus = @model.genus
    raise "this engine handles genus three" if @genus != 3
    @x_index = @model.x_index
    @y_index = @model.y_index
    @z_index = @model.infinity_index
    @x_pole = @model.x_pole_order
    @y_pole = @model.y_pole_order
    @known_points = []
    known_points.each -> (point)
      raise "known points must be coordinate Arrays" if point.class_name != "Array"
      raise "known points need three coordinates" if point.size != 3
      copy = []
      point.each -> copy.push(item)
      @known_points.push(copy)
    @base_index = base_index
    @base_index = @known_points.size - 1 if @base_index == nil
    @f_terms = integer_terms(@model.affine_equation)
    @fx_terms = derivative_terms(@f_terms, 0)
    @fy_terms = derivative_terms(@f_terms, 1)
    @modulus = @prime**@precision
    reduced = @curve.reduce(@prime)
    raise "Chabauty--Coleman needs good reduction" if !reduced.nonsingular?
    @jacobian_order = reduced.zeta.numerator.at(1)
    if @jacobian_order % @prime == 0
      raise "#J(F_p) divisible by p is not supported"
    @n = @jacobian_order
    @w = @n + 2 * @genus
    @basis = @model.basis_exponents(@w)
    if @basis.size != @w - @genus + 1
      raise "L(W oo) dimension does not match the Riemann--Roch count"
    @scale_exponent = 0
    @m_max = 0
    @length = 0
    @ring = nil
    @disks = []
    @report = nil
    @cover = nil

  -> trace(message)
    flag = env("TUNGSTEN_COLEMAN_TRACE")
    ccall("w_eputs", "coleman: " + message) if flag != nil && flag != ""
    nil

  -> model
    @model

  -> prime
    @prime

  -> precision
    @precision

  -> jacobian_order
    @jacobian_order

  -> pole_bound
    @w

  -> basis_size
    @basis.size

  -> disks
    out = []
    @disks.each -> out.push(item)
    out

  -> report
    @report

  # ---------------------------------------------------------------- terms --

  -> integer_terms(polynomial)
    out = []
    polynomial.terms.each -> (term)
      coefficient = term[0]
      value = coefficient
      if coefficient.class_name == "Rational"
        raise "curve coefficients must be integral" if coefficient.denominator != 1
        value = coefficient.numerator
      out.push([value, term[1][0], term[1][1]])
    out

  -> derivative_terms(terms, variable)
    out = []
    terms.each -> (term)
      power = term[1 + variable]
      if power > 0
        if variable == 0
          out.push([term[0] * power, term[1] - 1, term[2]])
        else
          out.push([term[0] * power, term[1], term[2] - 1])
    out

  -> evaluate_terms(terms, x, y)
    acc = 0
    terms.each -> (term)
      value = term[0] * PadicArithmetic.power_mod(x, term[1], @modulus)
      value = value * PadicArithmetic.power_mod(y, term[2], @modulus)
      acc = (acc + value) % @modulus
    acc += @modulus if acc < 0
    acc

  -> normalize(value)
    out = value % @modulus
    out += @modulus if out < 0
    out

  -> valuation(value)
    normalized = normalize(value)
    return @precision if normalized == 0
    PadicArithmetic.integer_valuation(normalized, @prime)

  -> unit_inverse(value)
    PadicArithmetic.inverse_mod(normalize(value), @modulus)

  # Series evaluation of a term list at series (X, Y).
  -> evaluate_terms_series(terms, x_powers, y_powers)
    acc = @ring.zero
    terms.each -> (term)
      product = x_powers[term[1]] * y_powers[term[2]]
      acc = acc + product.scale(term[0])
    acc

  -> series_powers(series, top)
    out = [@ring.one]
    index = 1
    while index <= top
      out.push(out[index - 1] * series)
      index += 1
    out

  # --------------------------------------------------------- Hensel lift --

  # Solve for the second coordinate mod p^K given the first, starting from a
  # residue where the relevant partial derivative is a unit.
  -> hensel_coordinate(fixed_value, start_residue, solve_x)
    root = start_residue % @prime
    iteration = 0
    while iteration < 2 * @precision
      value = 0
      derivative = 0
      if solve_x
        value = evaluate_terms(@f_terms, root, fixed_value)
        derivative = evaluate_terms(@fx_terms, root, fixed_value)
      else
        value = evaluate_terms(@f_terms, fixed_value, root)
        derivative = evaluate_terms(@fy_terms, fixed_value, root)
      raise "Hensel lift needs a unit partial derivative" if valuation(derivative) != 0
      return root if value == 0
      root = normalize(root - value * unit_inverse(derivative))
      iteration += 1
    raise "Hensel lift of the disk center did not converge"

  # ------------------------------------------------------- disk building --

  -> build_ring
    # power-sum truncation: every Lambda root has positive valuation, and
    # the Weierstrass polynomials show the exact minimum; the tail is bounded
    # after the fact.  The series length must cover t^N at the center plus
    # the truncation order with a margin.
    @m_max = 6 * @precision + 12
    @scale_exponent = 0
    power = @prime
    while power <= @m_max + 1
      @scale_exponent += 1
      power = power * @prime
    @length = @n + @m_max + 3 * @y_pole + 8
    @ring = PadicSeriesRing.new(@prime, @precision, @length)

  -> build_disks
    @cover = @curve.p_adic_residue_disks(@prime, @precision)
    raise "residue-disk cover failed certification" if !@cover.certified?
    @disks = []
    @cover.disks.each -> (disk)
      coordinates = disk.reduction_point.coordinates
      z = coordinates[@z_index]
      if z == 0
        @disks.push(attach_antiderivatives(build_infinity_disk(coordinates)))
      else
        z_inverse = PadicArithmetic.inverse_mod(z, @prime)
        x_bar = (coordinates[@x_index] * z_inverse) % @prime
        y_bar = (coordinates[@y_index] * z_inverse) % @prime
        @disks.push(attach_antiderivatives(build_affine_disk(x_bar, y_bar)))
    known_count = 0
    index = 0
    while index < @disks.size
      known_count += 1 if @disks[index].known?
      index += 1
    if known_count != @known_points.size
      raise "not every known rational point was matched to a residue disk"
    nil

  -> known_affine_match(x_bar, y_bar)
    index = 0
    while index < @known_points.size
      point = @known_points[index]
      z = point[@z_index]
      if z != 0
        x = Rational.new(point[@x_index], z)
        y = Rational.new(point[@y_index], z)
        if x.denominator % @prime == 0 || y.denominator % @prime == 0
          raise "known point is not p-integral in the affine chart"
        x_int = normalize(x.numerator * unit_inverse(x.denominator))
        y_int = normalize(y.numerator * unit_inverse(y.denominator))
        if x_int % @prime == x_bar && y_int % @prime == y_bar
          return [index, x_int, y_int]
      index += 1
    nil

  -> build_affine_disk(x_bar, y_bar)
    fx_unit = evaluate_terms(@fx_terms, x_bar, y_bar) % @prime != 0
    fy_unit = evaluate_terms(@fy_terms, x_bar, y_bar) % @prime != 0
    raise "residue point is singular" if !fx_unit && !fy_unit
    kind = :x_chart
    kind = :y_chart if fx_unit
    match = known_affine_match(x_bar, y_bar)
    known_index = nil
    x0 = 0
    y0 = 0
    if match != nil
      known_index = match[0]
      x0 = match[1]
      y0 = match[2]
      if evaluate_terms(@f_terms, x0, y0) != 0
        raise "known point does not satisfy the affine equation"
    elsif kind == :y_chart
      y0 = y_bar
      x0 = hensel_coordinate(y0, x_bar, true)
    else
      x0 = x_bar
      y0 = hensel_coordinate(x0, y_bar, false)
    name = "d" + x_bar.to_s + "_" + y_bar.to_s
    name = "P" + known_index.to_s if known_index != nil
    x_series = nil
    y_series = nil
    if kind == :y_chart
      y_series = @ring.series([y0, 1])
      x_series = solve_series(y_series, x0, true)
    else
      x_series = @ring.series([x0, 1])
      y_series = solve_series(x_series, y0, false)
    x_powers = series_powers(x_series, @degree)
    y_powers = series_powers(y_series, @degree)
    check = evaluate_terms_series(@f_terms, x_powers, y_powers)
    raise "disk coordinate series do not satisfy the equation" if !check.zero?
    omega0 = nil
    if kind == :x_chart
      omega0 = evaluate_terms_series(@fy_terms, x_powers, y_powers).inverse
    else
      omega0 = evaluate_terms_series(@fx_terms, x_powers, y_powers).inverse.negate
    omega = [omega0, x_series * omega0, y_series * omega0]
    columns = affine_columns(x_series, y_series)
    ColemanDisk.new(name, kind, [x0, y0], [x_series, y_series], omega, columns,
                    known_index, nil)

  # Newton iteration on series for the dependent coordinate.
  -> solve_series(free_series, start, solve_x)
    current = @ring.constant(start)
    iteration = 0
    while iteration < 12
      x_powers = nil
      y_powers = nil
      if solve_x
        x_powers = series_powers(current, @degree)
        y_powers = series_powers(free_series, @degree)
      else
        x_powers = series_powers(free_series, @degree)
        y_powers = series_powers(current, @degree)
      value = evaluate_terms_series(@f_terms, x_powers, y_powers)
      return current if value.zero?
      derivative = nil
      if solve_x
        derivative = evaluate_terms_series(@fx_terms, x_powers, y_powers)
      else
        derivative = evaluate_terms_series(@fy_terms, x_powers, y_powers)
      raise "series Newton step needs a unit derivative" if !derivative.unit?
      current = current - value * derivative.inverse
      iteration += 1
    raise "series Newton iteration did not converge"

  -> affine_columns(x_series, y_series)
    x_powers = series_powers(x_series, @w / @x_pole + 1)
    y_powers = series_powers(y_series, @x_pole)
    out = []
    @basis.each -> (powers)
      out.push(x_powers[powers[0]] * y_powers[powers[1]])
    out

  # Infinity disk in the chart y = 1: sigma = x / y, zeta = 1 / y, with
  # G(sigma, zeta) = F(x = sigma, y = 1, z = zeta) = 0 solved for zeta.
  -> build_infinity_disk(coordinates)
    if coordinates[@y_index] == 0 || coordinates[@x_index] != 0
      raise "the point at infinity must be the y-axis hyperflex"
    known_index = nil
    index = 0
    while index < @known_points.size
      point = @known_points[index]
      if point[@z_index] == 0 && point[@x_index] == 0 && point[@y_index] != 0
        known_index = index
      index += 1
    # chart polynomials: G(sigma, zeta) = sum c_ij sigma^i zeta^(d - i - j)
    g_terms = []
    gz_terms = []
    q_terms = []
    @f_terms.each -> (term)
      z_power = @degree - term[1] - term[2]
      raise "affine equation exceeds the curve degree" if z_power < 0
      g_terms.push([term[0], term[1], z_power])
      gz_terms.push([term[0] * z_power, term[1], z_power - 1]) if z_power > 0
      # Q = dF/dy at (sigma, 1, zeta): coefficient c_ij * j sigma^i zeta^(d-i-j)
      q_terms.push([term[0] * term[2], term[1], z_power]) if term[2] > 0
    # Newton for zeta(sigma) with G_zeta(0, 0) a unit
    sigma = @ring.parameter
    zeta = @ring.zero
    iteration = 0
    solved = false
    while iteration < 12 && !solved
      s_powers = series_powers(sigma, @degree)
      z_powers = series_powers(zeta, @degree)
      value = evaluate_terms_series(g_terms, s_powers, z_powers)
      if value.zero?
        solved = true
      else
        derivative = evaluate_terms_series(gz_terms, s_powers, z_powers)
        raise "infinity chart needs a unit zeta-derivative" if !derivative.unit?
        zeta = zeta - value * derivative.inverse
        iteration += 1
    raise "infinity chart Newton iteration did not converge" if !solved
    if zeta.order != @y_pole
      raise "zeta has the wrong order at infinity for the C_ab model"
    zeta_tilde = zeta.unshift(@y_pole)
    raise "zeta_tilde must be a unit series" if !zeta_tilde.unit?
    zeta_tilde_inverse = zeta_tilde.inverse
    # omega_0 = zeta (zeta - sigma zeta') / Q(sigma, zeta) dsigma
    s_powers = series_powers(sigma, @degree)
    z_powers = series_powers(zeta, @degree)
    q_series = evaluate_terms_series(q_terms, s_powers, z_powers)
    numerator = zeta * (zeta - sigma * zeta.derivative)
    q_order = q_series.order
    raise "regular differential is not holomorphic at infinity" if numerator.order < q_order
    omega0 = numerator.unshift(q_order) * q_series.unshift(q_order).inverse
    raise "omega_0 must vanish to order y_pole at the hyperflex" if omega0.order < @y_pole
    omega1 = omega0.shift(1).unshift(@y_pole) * zeta_tilde_inverse
    omega2 = omega0.unshift(@y_pole) * zeta_tilde_inverse
    inverse_powers = series_powers(zeta_tilde_inverse, @w / @x_pole + @x_pole + 1)
    columns = []
    @basis.each -> (powers)
      weight = @model.monomial_weight(powers)
      columns.push(inverse_powers[powers[0] + powers[1]].shift(@w - weight))
    ColemanDisk.new("oo", :infinity, [0, 0], [nil, nil], [omega0, omega1, omega2],
                    columns, known_index, zeta_tilde)

  # ---------------------------------------------------- interpolation ------

  -> auxiliary_point(disk, lift)
    disk.point_at(@prime * lift)

  -> monomial_value(powers, x, y)
    value = PadicArithmetic.power_mod(x, powers[0], @modulus)
    (value * PadicArithmetic.power_mod(y, powers[1], @modulus)) % @modulus

  # h in L(W oo) vanishing to order >= N at the disk center and at the
  # auxiliary points.  Returns [coefficients, known_digits].
  -> interpolate(disk, auxiliary)
    raise "interpolation center must be affine" if disk.infinity?
    rows = []
    width = @basis.size
    m = 0
    while m < @n
      row = []
      disk.columns.each -> row.push(item.coefficient(m))
      rows.push(row)
      m += 1
    auxiliary.each -> (point)
      row = []
      @basis.each -> row.push(monomial_value(item, point[0], point[1]))
      rows.push(row)
    kernel = PadicKernel.new(rows, width, @ring)
    if kernel.dimension != 1
      raise "interpolation kernel has dimension " + kernel.dimension.to_s + ", expected 1"
    kernel.primitive_vector(0)

  -> pole_order(coefficients, digits)
    check = @prime**digits
    order = 0
    index = 0
    while index < @basis.size
      if coefficients[index] % check != 0
        weight = @model.monomial_weight(@basis[index])
        order = weight if weight > order
      index += 1
    order

  # Expansion of h in a disk's parameter, known to `digits`.
  -> expand(disk, coefficients, digits)
    PadicSeries.combination(disk.columns, coefficients, @ring, digits).reduce_to_known

  # Per-disk root structure of h: returns Arrays [count, monic] where count is
  # the number of Lambda points in the disk (center's N-fold zero excluded,
  # points at infinity itself included) and monic the Weierstrass polynomial
  # of the points that contribute tiny integrals (nil when there are none).
  -> disk_roots(disk, coefficients, digits, center)
    series = expand(disk, coefficients, digits)
    if disk.infinity?
      deficiency = @w - pole_order(coefficients, digits)
      degree = series.weierstrass_degree
      if degree < deficiency
        raise "infinity expansion vanishes to lower order than the pole deficiency"
      remaining = degree - deficiency
      return [degree, nil] if remaining == 0
      reduced = series.unshift(deficiency)
      return [degree, reduced.weierstrass_factor(remaining)]
    if disk.residue_key == center.residue_key
      raise "center expansion does not vanish to order N" if series.order < @n
      reduced = series.unshift(@n)
      degree = reduced.weierstrass_degree
      return [degree, nil] if degree == 0
      return [degree, reduced.weierstrass_factor(degree)]
    degree = series.weierstrass_degree
    return [degree, nil] if degree == 0
    [degree, series.weierstrass_factor(degree)]

  # Minimum root valuation of a Weierstrass polynomial from its Newton
  # polygon: the least slope of the lower hull of (j, v(c_j)).
  -> minimum_root_valuation(monic)
    degree = monic.size - 1
    best = nil
    j = 0
    while j < degree
      vj = valuation(monic[j])
      # roots of valuation lambda satisfy v(c_j) >= lambda (degree - j)
      candidate = Rational.new(vj, degree - j)
      best = candidate if best == nil || candidate < best
      j += 1
    best

  # p^scale * sum over the roots of monic of the antiderivative of omega_i
  # from the disk center; the truncation is certified against the minimum
  # root valuation.
  -> tiny_integrals(disk, monic)
    degree = monic.size - 1
    lambda = minimum_root_valuation(monic)
    raise "Weierstrass roots must have positive valuation" if lambda <= 0
    # terms a_m p_(m+1)/(m+1): valuation >= (m+1) lambda - v(m+1); require the
    # first omitted term to sit above the precision
    omitted = @m_max + 1
    floor = lambda * omitted
    if floor < @precision
      raise "power-sum truncation is too short for root valuation " + lambda.to_s
    sums = PadicSeries.power_sums(monic, @m_max + 1, @modulus)
    out = []
    i = 0
    while i < 3
      antiderivative = disk.antiderivatives[i]
      acc = 0
      m = 1
      while m <= @m_max
        c = antiderivative.coefficient(m)
        acc = (acc + c * sums[m]) % @modulus if c != 0
        m += 1
      out.push(acc)
      i += 1
    [out, antiderivative_digits(disk)]

  -> antiderivative_digits(disk)
    digits = @precision
    i = 0
    while i < 3
      d = disk.antiderivatives[i].known_digits
      digits = d if d < digits
      i += 1
    digits

  -> attach_antiderivatives(disk)
    list = []
    i = 0
    while i < 3
      list.push(disk.omega[i].scaled_antiderivative(@m_max + 1, @scale_exponent))
      i += 1
    disk.set_antiderivatives(list)
    disk

  # Sum of scaled tiny integrals over all Lambda points of h, with the
  # per-disk multiplicities returned for pairing.
  -> lambda_sum(coefficients, digits, center)
    total = [0, 0, 0]
    counts = []
    known = digits
    index = 0
    while index < @disks.size
      disk = @disks[index]
      index += 1
      disk = center if disk.residue_key == center.residue_key
      roots = disk_roots(disk, coefficients, digits, center)
      counts.push(roots[0])
      if roots[1] != nil
        tiny = tiny_integrals(disk, roots[1])
        i = 0
        while i < 3
          total[i] = (total[i] + tiny[0][i]) % @modulus
          i += 1
        known = tiny[1] if tiny[1] < known
    [total, counts, known]

  -> auxiliary_pool(center, base)
    out = []
    @disks.each -> (disk)
      if !disk.infinity? && disk.name != center.name && disk.name != base.name
        out.push(disk)
    out

  # log[c - base] as a scaled 3-vector: [eta, known_digits].  The auxiliary
  # divisor is chosen among multisets of g pool disks (repeated disks use
  # distinct lifts); a choice is accepted only when both Lambda divisors
  # have degree 2g inside the rational residue disks and agree disk by disk.
  -> logarithm(center, base)
    pool = auxiliary_pool(center, base)
    raise "not enough auxiliary disks" if pool.size < 1
    choices = auxiliary_choices(pool.size)
    last_failure = "no auxiliary choice was tried"
    attempt = 0
    while attempt < choices.size
      choice = choices[attempt]
      attempt += 1
      auxiliary = []
      used = []
      index = 0
      while index < pool.size
        used.push(0)
        index += 1
      choice.each -> (disk_index)
        used[disk_index] += 1
        auxiliary.push(auxiliary_point(pool[disk_index], used[disk_index]))
      outcome = nil
      trace("log " + center.name + " attempt " + attempt.to_s + " choice " + choice.to_s)
      begin
        outcome = logarithm_attempt(center, base, auxiliary)
      rescue error
        outcome = nil
        last_failure = error.to_s
        trace("  failed: " + last_failure)
      if outcome != nil
        trace("  ok, digits " + outcome[1].to_s)
        return outcome
    raise "no auxiliary choice paired the Lambda divisors: " + last_failure

  # Multisets {i <= j <= k} of pool indices, distinct disks first (repeated
  # disks reuse the same residue class with different lifts and more often
  # produce dependent interpolation conditions or unsplit residuals).
  -> auxiliary_choices(pool_size)
    out = []
    repeats = 0
    while repeats <= 2
      i = 0
      while i < pool_size
        j = i
        while j < pool_size
          k = j
          while k < pool_size
            distinct = 3
            distinct = 2 if i == j || j == k
            distinct = 1 if i == j && j == k
            out.push([i, j, k]) if 3 - distinct == repeats
            k += 1
          j += 1
        i += 1
      repeats += 1
    out

  -> logarithm_attempt(center, base, auxiliary)
    h_center = interpolate(center, auxiliary)
    h_base = interpolate(base, auxiliary)
    digits = h_center[1]
    digits = h_base[1] if h_base[1] < digits
    lambda_center = lambda_sum(h_center[0], digits, center)
    lambda_base = lambda_sum(h_base[0], digits, base)
    total_center = 0
    total_base = 0
    lambda_center[1].each -> total_center += item
    lambda_base[1].each -> total_base += item
    if total_center != 2 * @genus || total_base != 2 * @genus
      raise "Lambda degrees " + total_center.to_s + "/" + total_base.to_s + " counts " + lambda_center[1].to_s + " " + lambda_base[1].to_s
    index = 0
    while index < @disks.size
      if lambda_center[1][index] != lambda_base[1][index]
        raise "Lambda divisors are not paired: " + lambda_center[1].to_s + " vs " + lambda_base[1].to_s
      index += 1
    known = lambda_center[2]
    known = lambda_base[2] if lambda_base[2] < known
    known = digits if digits < known
    inverse_n = unit_inverse(@n)
    eta = []
    i = 0
    while i < 3
      eta.push(normalize((lambda_base[0][i] - lambda_center[0][i]) * inverse_n))
      i += 1
    [eta, known]

  # ------------------------------------------------------- Coleman side ----

  -> disk_by_name(name)
    index = 0
    while index < @disks.size
      return @disks[index] if @disks[index].name == name
      index += 1
    raise "no disk named " + name

  # Coefficients of p^scale * (alpha . integral_center^t omega + alpha . eta):
  # a series in the disk parameter known to the given digits.
  -> coleman_series(disk, alpha, eta_scaled, eta_digits)
    acc = PadicSeries.combination(disk.antiderivatives, alpha, @ring, @precision)
    constant = 0
    i = 0
    while i < 3
      constant = (constant + alpha[i] * eta_scaled[i]) % @modulus
      i += 1
    digits = acc.known_digits
    digits = eta_digits if eta_digits < digits
    (acc + constant).with_known_digits(digits).reduce_to_known

  # Lower bound of v(coefficient_j) + j for every omitted index j > m_max:
  # the coefficient of t^j is p^scale a_(j-1) / j with a integral.
  -> tail_floor
    omitted = @m_max + 1
    log = 0
    power = @prime
    while power <= omitted
      log += 1
      power = power * @prime
    omitted + @scale_exponent - log

  -> newton_root(series, other)
    digits = series.known_digits
    check = @prime**digits
    derivative = series.derivative
    root = 0
    iteration = 0
    while iteration < 4 * @precision
      value = series.evaluate(root) % check
      slope = derivative.evaluate(root)
      slope_valuation = valuation(slope)
      raise "Newton slope vanishes too deeply" if slope_valuation >= 6
      value_valuation = @precision
      value_valuation = PadicArithmetic.integer_valuation(value, @prime) if value != 0
      if value_valuation >= digits - slope_valuation - 1
        other_value = other.evaluate(root) % (@prime**other.known_digits)
        other_valuation = other.known_digits
        if other_value != 0
          other_valuation = PadicArithmetic.integer_valuation(other_value, @prime)
        return [root, slope_valuation, other_valuation, digits - slope_valuation - 1]
      raise "Newton step is inexact" if value_valuation < slope_valuation
      unit = slope / (@prime**slope_valuation)
      step = normalize((value / (@prime**slope_valuation)) * unit_inverse(unit))
      root = normalize(root - step)
      raise "Newton iterate left the residue disk" if root != 0 && valuation(root) < 1
      iteration += 1
    raise "Newton iteration did not converge"

  # ------------------------------------------------------------ driver ----

  -> run
    build_ring
    trace("ring " + @ring.to_s + " m_max " + @m_max.to_s + " scale " + @scale_exponent.to_s)
    build_disks
    trace("disks built: " + @disks.size.to_s)
    base = nil
    generator = nil
    index = 0
    while index < @disks.size
      disk = @disks[index]
      if disk.known? && !disk.infinity?
        if disk.known_index == @base_index
          base = disk
        elsif generator == nil
          generator = disk
      index += 1
    if base == nil || generator == nil
      raise "the engine needs two known affine rational points, one of them the base"
    logs = {}
    log_digits = {}
    v = logarithm(generator, base)
    logs[generator.name] = v[0]
    log_digits[generator.name] = v[1]
    index = 0
    while index < @disks.size
      disk = @disks[index]
      if !disk.infinity? && disk.name != base.name && disk.name != generator.name
        value = logarithm(disk, base)
        logs[disk.name] = value[0]
        log_digits[disk.name] = value[1]
      index += 1
    # annihilators of v: the two cross vectors against its least-valuation
    # coordinate, normalized by the minimum valuation of v
    vvec = v[0]
    minimum = @precision
    vi = 0
    while vi < 3
      if vvec[vi] != 0
        value = valuation(vvec[vi])
        minimum = value if value < minimum
      vi += 1
    if minimum >= v[1] - 6
      raise "log of the generator class vanishes to the working precision"
    normalized = []
    vvec.each -> normalized.push(item / (@prime**minimum))
    pivot = 0
    pivot_valuation = valuation(normalized[0])
    i = 1
    while i < 3
      value = valuation(normalized[i])
      if value < pivot_valuation
        pivot = i
        pivot_valuation = value
      i += 1
    alphas = []
    o = 0
    while o < 3
      if o != pivot
        alpha = [0, 0, 0]
        alpha[pivot] = normalized[o]
        alpha[o] = normalize(0 - normalized[pivot])
        alphas.push(alpha)
      o += 1
    v_digits = v[1] - minimum
    floor = tail_floor
    reports = []
    total_points = 0
    complete = true
    index = 0
    while index < @disks.size
      disk = @disks[index]
      index += 1
      eta = [0, 0, 0]
      eta_digits = @precision
      if disk.name != base.name && !disk.infinity?
        eta = logs[disk.name]
        eta_digits = log_digits[disk.name]
      # eta already carries the p^scale of the tiny integrals and the 1/N
      # division; the antiderivatives inside coleman_series carry the same
      # scale, so the two combine directly
      series1 = coleman_series(disk, alphas[0], eta, eta_digits)
      series2 = coleman_series(disk, alphas[1], eta, eta_digits)
      count1 = series1.disk_zero_count(1, floor)
      count2 = series2.disk_zero_count(1, floor)
      minimum_count = count1[0]
      minimum_count = count2[0] if count2[0] < minimum_count
      status = "unresolved"
      root_point = nil
      other_valuation = nil
      if disk.known?
        raise "a known disk reports no zero" if minimum_count < 1
        if minimum_count == 1
          status = "resolved-known"
          total_points += 1
        else
          complete = false
      elsif minimum_count == 0
        status = "eliminated-count"
      else
        located = nil
        if count1[0] == 1
          located = newton_root(series1, series2)
        elsif count2[0] == 1
          located = newton_root(series2, series1)
        if located != nil
          # the other function must be a unit at the located zero, far above
          # the digits it is known to
          if located[2] < located[3] - 4
            status = "eliminated-located"
            other_valuation = located[2]
            root_point = disk.point_at(located[0]) if !disk.infinity?
            root_point = [0, 0] if disk.infinity?
            root_point = [root_point[0] % (@prime**8), root_point[1] % (@prime**8)]
        complete = false if status == "unresolved"
      reports.push({
        name: disk.name,
        kind: disk.kind,
        counts: [count1[0], count2[0]],
        minima: [count1[1], count2[1]],
        digits: [series1.known_digits, series2.known_digits],
        status: status,
        root_point: root_point,
        other_valuation: other_valuation
      })
    @report = {
      prime: @prime,
      precision: @precision,
      jacobian_order: @n,
      pole_bound: @w,
      basis_size: @basis.size,
      scale_exponent: @scale_exponent,
      power_sum_order: @m_max,
      tail_floor: floor,
      generator_log: vvec,
      generator_log_digits: v[1],
      annihilators: alphas,
      annihilator_digits: v_digits,
      disks: reports,
      total_points: total_points,
      complete: complete
    }
    raise "Coleman determination incomplete" if !complete
    @report

  # Internal consistency: move a disk center along its own parameter to
  # t = p and confirm that the interpolated logarithms differ by the direct
  # tiny integral.  Returns the number of agreeing digits per coordinate.
  -> consistency_check(disk_name)
    raise "run the engine first" if @report == nil
    disk = disk_by_name(disk_name)
    raise "consistency check needs an affine unknown disk" if disk.infinity? || disk.known?
    base = nil
    index = 0
    while index < @disks.size
      candidate = @disks[index]
      base = candidate if candidate.known? && candidate.known_index == @base_index
      index += 1
    shifted = attach_antiderivatives(shifted_disk(disk, @prime))
    eta_original = logarithm(disk, base)
    eta_shifted = logarithm(shifted, base)
    agreement = []
    i = 0
    while i < 3
      antiderivative = disk.antiderivatives[i]
      direct = antiderivative.evaluate(@prime)
      difference = normalize(eta_shifted[0][i] - eta_original[0][i] - direct)
      digits = eta_original[1]
      digits = eta_shifted[1] if eta_shifted[1] < digits
      digits = antiderivative.known_digits if antiderivative.known_digits < digits
      agreeing = valuation(difference)
      agreeing = digits if agreeing > digits
      agreement.push(agreeing)
      i += 1
    agreement

  # A second center inside an affine disk at parameter value t.
  -> shifted_disk(disk, t)
    point = disk.point_at(t)
    x0 = point[0]
    y0 = point[1]
    x_series = nil
    y_series = nil
    if disk.kind == :y_chart
      y_series = @ring.series([y0, 1])
      x_series = solve_series(y_series, x0, true)
    else
      x_series = @ring.series([x0, 1])
      y_series = solve_series(x_series, y0, false)
    x_powers = series_powers(x_series, @degree)
    y_powers = series_powers(y_series, @degree)
    check = evaluate_terms_series(@f_terms, x_powers, y_powers)
    raise "shifted disk series do not satisfy the equation" if !check.zero?
    omega0 = nil
    if disk.kind == :x_chart
      omega0 = evaluate_terms_series(@fy_terms, x_powers, y_powers).inverse
    else
      omega0 = evaluate_terms_series(@fx_terms, x_powers, y_powers).inverse.negate
    omega = [omega0, x_series * omega0, y_series * omega0]
    columns = affine_columns(x_series, y_series)
    ColemanDisk.new(disk.name + "+", disk.kind, [x0, y0], [x_series, y_series],
                    omega, columns, nil, nil)


# Convenience entry for the (B, S, Z) plane-quartic layout used by the shell
# curve: x = S (pole order 3), y = B (pole order 4), infinity along Z.  Other
# C_ab layouts construct the model themselves and call ColemanChabauty.new.
+ Curve
  -> chabauty_coleman(prime, precision, known_points, base_index = nil)
    model = c_ab_model(1, 0, 2, 3, 4)
    ColemanChabauty.new(model, prime, precision, known_points, base_index)

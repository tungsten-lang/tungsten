# TaylorJet — truncated univariate Taylor algebra.
#
# Coefficient k stores f^(k)(x0)/k!, so multiplication is convolution and
# every derivative through the retained order is recovered without numerical
# differencing.  Elementary functions use formal power-series recurrences.

+ TaylorJet
  -> new(coefficients, copy = true)
    if copy
      if type(coefficients) != "Array" || coefficients.size == 0
        raise "TaylorJet needs a nonempty coefficient Array"
      @coefficients = coefficients.dup
    else
      @coefficients = coefficients

  -> .from_raw(coefficients)
    TaylorJet.new(coefficients, false)

  -> raw_coefficients
    @coefficients

  -> .constant(value, order)
    Calculus.validate_order(order)
    coefficients = Array.new(order + 1, ~0.0)
    coefficients[0] = value
    TaylorJet.from_raw(coefficients)

  -> .variable(value, order)
    Calculus.validate_order(order)
    coefficients = Array.new(order + 1, ~0.0)
    coefficients[0] = value
    coefficients[1] = ~1.0 if order > 0
    TaylorJet.from_raw(coefficients)

  -> order
    c = @coefficients ## Array
    c.size - 1

  -> value
    c = @coefficients ## Array
    c[0]

  -> coefficients
    @coefficients.dup

  -> coefficient(index)
    c = @coefficients ## Array
    return ~0.0 if index < 0 || index >= c.size
    c[index]

  -> coerce(other)
    if other.class_name == "TaylorJet"
      if other.order != self.order
        raise "TaylorJet order mismatch"
      return other
    TaylorJet.constant(other, self.order)

  -> +(other)
    rhs = self.coerce(other)
    c = @coefficients ## Array
    rc = rhs.raw_coefficients ## Array
    len = c.size
    out = []
    i = 0
    while i < len
      out.push(c[i] + rc[i])
      i += 1
    TaylorJet.from_raw(out)

  -> -(other)
    rhs = self.coerce(other)
    c = @coefficients ## Array
    rc = rhs.raw_coefficients ## Array
    len = c.size
    out = []
    i = 0
    while i < len
      out.push(c[i] - rc[i])
      i += 1
    TaylorJet.from_raw(out)

  -> -@
    c = @coefficients ## Array
    len = c.size
    out = []
    i = 0
    while i < len
      out.push(~0.0 - c[i])
      i += 1
    TaylorJet.from_raw(out)

  -> *(other)
    rhs = self.coerce(other)
    c = @coefficients ## Array
    rc = rhs.raw_coefficients ## Array
    ord = c.size - 1
    out = []
    if type(c[0]) == "Float" && type(rc[0]) == "Float"
      n = 0
      while n <= ord
        value = ~0.0
        k = 0
        while k <= n
          ck = c[k] ## f64
          rnk = rc[n - k] ## f64
          value += ck * rnk
          k += 1
        out.push(value)
        n += 1
    else
      n = 0
      while n <= ord
        value = ~0.0
        k = 0
        while k <= n
          value += c[k] * rc[n - k]
          k += 1
        out.push(value)
        n += 1
    TaylorJet.from_raw(out)

  -> scale(scalar)
    c = @coefficients ## Array
    len = c.size
    out = []
    i = 0
    while i < len
      out.push(c[i] * scalar)
      i += 1
    TaylorJet.from_raw(out)

  -> /(other)
    rhs = self.coerce(other)
    c = @coefficients ## Array
    rc = rhs.raw_coefficients ## Array
    r0 = rc[0]
    raise "TaylorJet division by a zero constant term" if r0 == ~0.0
    ord = c.size - 1
    out = []
    if type(c[0]) == "Float" && type(r0) == "Float"
      r0f = r0 ## f64
      n = 0
      while n <= ord
        value = c[n] ## f64
        k = 1
        while k <= n
          rck = rc[k] ## f64
          onk = out[n - k] ## f64
          value -= rck * onk
          k += 1
        out.push(value / r0f)
        n += 1
    else
      n = 0
      while n <= ord
        value = c[n]
        k = 1
        while k <= n
          value -= rc[k] * out[n - k]
          k += 1
        out.push(value / r0)
        n += 1
    TaylorJet.from_raw(out)

  -> reciprocal
    TaylorJet.constant(~1.0, self.order) / self

  -> **(exponent)
    if !Calculus.integer?(exponent)
      return self.jet_log.scale(exponent).jet_exp
    return TaylorJet.constant(~1.0, self.order) if exponent == 0
    return (self ** (0 - exponent)).reciprocal if exponent < 0
    result = TaylorJet.constant(~1.0, self.order)
    factor = self
    power = exponent
    while power > 0
      result = result * factor if power.odd?
      power = power / 2
      factor = factor * factor if power > 0
    result

  -> pow(exponent)
    self ** exponent

  -> derivative
    c = @coefficients ## Array
    ord = c.size - 1
    out = []
    i = 0
    while i < ord
      out.push(c[i + 1] * (i + ~1.0))
      i += 1
    out.push(~0.0)
    TaylorJet.from_raw(out)

  -> antiderivative(constant = ~0.0)
    c = @coefficients ## Array
    ord = c.size - 1
    out = [constant]
    i = 1
    while i <= ord
      out.push(c[i - 1] / (i + ~0.0))
      i += 1
    TaylorJet.from_raw(out)

  -> derivative_value(order = 1)
    Calculus.validate_order(order)
    c = @coefficients ## Array
    return ~0.0 if order >= c.size
    value = c[order]
    i = 2
    while i <= order
      value *= i + ~0.0
      i += 1
    value

  -> derivatives
    c = @coefficients ## Array
    ord = c.size - 1
    out = []
    fact = ~1.0
    i = 0
    while i <= ord
      fact *= i + ~0.0 if i >= 2
      out.push(c[i] * fact)
      i += 1
    out

  # Unique internal names avoid the compiler's raw-f64 instance fast path
  # when one jet elementary function composes another.
  -> jet_exp
    c = @coefficients ## Array
    ord = c.size - 1
    out = [Math.exp(c[0])]
    if type(c[0]) == "Float"
      n = 1
      while n <= ord
        value = ~0.0
        k = 1
        while k <= n
          ck = c[k] ## f64
          onk = out[n - k] ## f64
          value += ck * (k + ~0.0) * onk
          k += 1
        out.push(value / (n + ~0.0))
        n += 1
    else
      n = 1
      while n <= ord
        value = ~0.0
        k = 1
        while k <= n
          value += c[k] * (k + ~0.0) * out[n - k]
          k += 1
        out.push(value / (n + ~0.0))
        n += 1
    TaylorJet.from_raw(out)

  -> exp
    self.jet_exp

  -> jet_log
    c = @coefficients ## Array
    ord = c.size - 1
    v0 = c[0]
    Calculus.require_real_domain(v0, v0 > ~0.0, "TaylorJet.log")
    quotient = self.derivative / self
    qc = quotient.raw_coefficients ## Array
    out = [Math.log(v0)]
    n = 1
    while n <= ord
      out.push(qc[n - 1] / (n + ~0.0))
      n += 1
    TaylorJet.from_raw(out)

  -> log
    self.jet_log

  -> sin_cos
    c = @coefficients ## Array
    ord = c.size - 1
    v0 = c[0]
    sine = [Math.sin(v0)]
    cosine = [Math.cos(v0)]
    if type(v0) == "Float"
      n = 1
      while n <= ord
        sine_value = ~0.0
        cosine_value = ~0.0
        k = 1
        while k <= n
          ck = c[k] ## f64
          factor = ck * (k + ~0.0)
          cnk = cosine[n - k] ## f64
          snk = sine[n - k] ## f64
          sine_value += factor * cnk
          cosine_value -= factor * snk
          k += 1
        sine.push(sine_value / (n + ~0.0))
        cosine.push(cosine_value / (n + ~0.0))
        n += 1
    else
      n = 1
      while n <= ord
        sine_value = ~0.0
        cosine_value = ~0.0
        k = 1
        while k <= n
          factor = c[k] * (k + ~0.0)
          sine_value += factor * cosine[n - k]
          cosine_value -= factor * sine[n - k]
          k += 1
        sine.push(sine_value / (n + ~0.0))
        cosine.push(cosine_value / (n + ~0.0))
        n += 1
    [TaylorJet.from_raw(sine), TaylorJet.from_raw(cosine)]

  -> sin
    self.sin_cos[0]

  -> cos
    self.sin_cos[1]

  -> tan
    pair = self.sin_cos
    pair[0] / pair[1]

  -> sinh_cosh
    c = @coefficients ## Array
    ord = c.size - 1
    v0 = c[0]
    hyperbolic_sine = [Math.sinh(v0)]
    hyperbolic_cosine = [Math.cosh(v0)]
    if type(v0) == "Float"
      n = 1
      while n <= ord
        sine_value = ~0.0
        cosine_value = ~0.0
        k = 1
        while k <= n
          ck = c[k] ## f64
          factor = ck * (k + ~0.0)
          hcnk = hyperbolic_cosine[n - k] ## f64
          hsnk = hyperbolic_sine[n - k] ## f64
          sine_value += factor * hcnk
          cosine_value += factor * hsnk
          k += 1
        hyperbolic_sine.push(sine_value / (n + ~0.0))
        hyperbolic_cosine.push(cosine_value / (n + ~0.0))
        n += 1
    else
      n = 1
      while n <= ord
        sine_value = ~0.0
        cosine_value = ~0.0
        k = 1
        while k <= n
          factor = c[k] * (k + ~0.0)
          sine_value += factor * hyperbolic_cosine[n - k]
          cosine_value += factor * hyperbolic_sine[n - k]
          k += 1
        hyperbolic_sine.push(sine_value / (n + ~0.0))
        hyperbolic_cosine.push(cosine_value / (n + ~0.0))
        n += 1
    [TaylorJet.from_raw(hyperbolic_sine), TaylorJet.from_raw(hyperbolic_cosine)]

  -> sinh
    self.sinh_cosh[0]

  -> cosh
    self.sinh_cosh[1]

  -> tanh
    pair = self.sinh_cosh
    pair[0] / pair[1]

  -> asin
    Calculus.require_real_domain(self.value, self.value > ~-1.0 && self.value < ~1.0, "TaylorJet.asin")
    one = TaylorJet.constant(~1.0, self.order)
    derivative = self.derivative / (one - self * self).sqrt
    derivative.antiderivative(Math.asin(self.value))

  -> acos
    Calculus.require_real_domain(self.value, self.value > ~-1.0 && self.value < ~1.0, "TaylorJet.acos")
    one = TaylorJet.constant(~1.0, self.order)
    derivative = -(self.derivative / (one - self * self).sqrt)
    derivative.antiderivative(Math.acos(self.value))

  -> atan
    one = TaylorJet.constant(~1.0, self.order)
    derivative = self.derivative / (one + self * self)
    derivative.antiderivative(Math.atan(self.value))

  -> asinh
    one = TaylorJet.constant(~1.0, self.order)
    derivative = self.derivative / (one + self * self).sqrt
    derivative.antiderivative(Math.asinh(self.value))

  -> acosh
    Calculus.require_real_domain(self.value, self.value > ~1.0, "TaylorJet.acosh")
    one = TaylorJet.constant(~1.0, self.order)
    derivative = self.derivative / (self * self - one).sqrt
    derivative.antiderivative(Math.acosh(self.value))

  -> atanh
    Calculus.require_real_domain(self.value, self.value > ~-1.0 && self.value < ~1.0, "TaylorJet.atanh")
    one = TaylorJet.constant(~1.0, self.order)
    derivative = self.derivative / (one - self * self)
    derivative.antiderivative(Math.atanh(self.value))

  -> expm1
    out = self.jet_exp.coefficients
    out[0] -= ~1.0
    TaylorJet.new(out)

  -> log1p
    (self + ~1.0).jet_log

  -> log2
    self.jet_log.scale(~1.4426950408889634)

  -> log10
    self.jet_log.scale(~0.4342944819032518)

  -> cbrt
    exponent = ~1.0 / ~3.0
    return -((-self) ** exponent) if self.value < ~0.0
    self ** exponent

  -> abs
    return self if self.value > ~0.0
    return -self if self.value < ~0.0
    i = 1
    while i <= self.order
      if @coefficients[i] != ~0.0
        raise "TaylorJet.abs is not analytic at zero"
      i += 1
    TaylorJet.constant(~0.0, self.order)

  -> erf
    exponential = (-(self * self)).jet_exp
    slope = self.derivative * exponential
    scale = ~2.0 / Math.sqrt(~3.141592653589793)
    slope.scale(scale).antiderivative(Special.erf(self.value))

  -> erfc
    exponential = (-(self * self)).jet_exp
    slope = self.derivative * exponential
    scale = (~0.0 - ~2.0) / Math.sqrt(~3.141592653589793)
    slope.scale(scale).antiderivative(Special.erfc(self.value))

  -> polygamma(index)
    name = index.class_name
    integral = name == "Integer" || name == "Int" || name == "BigInt"
    if !integral || index < 0
      raise "TaylorJet.polygamma order must be a nonnegative integer"
    delta = self - TaylorJet.constant(self.value, self.order)
    result = TaylorJet.constant(~0.0, self.order)
    k = self.order
    while k >= 0
      coefficient_value = Special.polygamma(index + k, self.value)
      coefficient_value /= Special.float_factorial(k)
      result = (result * delta +
        TaylorJet.constant(coefficient_value, self.order))
      k -= 1
    result

  -> digamma
    self.polygamma(0)

  -> trigamma
    self.polygamma(1)

  -> log_gamma
    slope = self.derivative * self.digamma
    slope.antiderivative(Special.log_gamma(self.value))

  -> lgamma
    self.log_gamma

  -> gamma
    self.log_gamma.jet_exp

  # Solve w*exp(w)=self in the truncated Taylor algebra. Newton iteration
  # doubles the number of correct coefficients; order+1 bounded iterations
  # also covers the zero-centered series without dividing by self.
  -> lambert_w
    branch_point = ~-0.36787944117144232160
    if self.value == branch_point
      raise "TaylorJet.lambert_w is singular at -1/e"
    estimate = TaylorJet.constant(
      Special.lambert_w(self.value), self.order)
    iteration = 0
    while iteration <= self.order
      exponential = estimate.jet_exp
      residual = estimate*exponential - self
      derivative = exponential*(estimate + ~1.0)
      estimate = estimate - residual / derivative
      iteration += 1
    estimate

  -> lambertw
    self.lambert_w

  -> sqrt
    Calculus.require_real_domain(self.value, self.value >= ~0.0, "TaylorJet.sqrt")
    root = Math.sqrt(self.value)
    if root == ~0.0
      i = 1
      while i <= self.order
        if @coefficients[i] != ~0.0
          raise "TaylorJet.sqrt is singular at a zero constant term"
        i += 1
      return TaylorJet.constant(~0.0, self.order)
    out = [root]
    n = 1
    while n <= self.order
      value = @coefficients[n]
      k = 1
      while k < n
        value -= out[k] * out[n - k]
        k += 1
      out.push(value / (~2.0 * root))
      n += 1
    TaylorJet.new(out)

  -> to_s
    "TaylorJet(" + @coefficients.join(", ") + ")"

  -> inspect
    self.to_s


+ Calculus
  -> .jet(f, x, order = 1)
    Calculus.validate_order(order)
    if !Calculus.finite_scalar?(x)
      raise "calculus jet point must be a finite scalar"
    result = f(TaylorJet.variable(x, order))
    if result.class_name == "TaylorJet"
      if result.order != order
        raise "calculus result TaylorJet order mismatch"
      if !Calculus.finite_scalar?(result.value)
        raise "calculus result must have a finite scalar value"
      return result
    if !Calculus.finite_scalar?(result)
      raise "calculus scalar function must return a finite scalar or TaylorJet"
    TaylorJet.constant(result, order)

  -> .derivative(f, x, order = 1)
    if !Calculus.integer?(order) || order < 1
      raise "derivative order must be a positive integer"
    Calculus.jet(f, x, order).derivative_value(order)

  -> .value_and_derivatives(f, x, order = 1)
    jet = Calculus.jet(f, x, order)
    {
      "value": jet.value,
      "derivatives": jet.derivatives,
      "coefficients": jet.coefficients
    }

  -> .taylor(f, x, order = 5)
    Calculus.jet(f, x, order)

+ Decimal < Real
  # Exact scalar operations backed by the packed/heap Decimal runtime.
  -> abs
    self < 0 ? -self : self

  -> to_f
    ccall("w_num_to_float", self)

  -> to_i
    self.to_f().to_i()

  -> to_d
    self

  -> to_s
    ccall("w_to_s", self)

  -> floor
    self.to_f().floor()

  -> ceil
    self.to_f().ceil()

  -> round(digits = 0)
    if digits == nil || digits <= 0
      return self.to_f().round()
    ccall("w_decimal_round", self, digits)

  -> sqrt
    Math.sqrt(self.to_f())

  -> sq
    self * self

  # Decimal constructors and arithmetic already canonicalize the significand
  # and scale, so normalization is receiver identity.
  -> normalize
    self

  -> reciprocal
    1.0 / self

  -> inv
    self.reciprocal()

  ## Trigonometric functions

  # @example
  #   0.sin => 0𝝅
  -> sin
    Math.sin(self.to_f())

  # @example
  #   0.cos => 1𝝅
  -> cos
    Math.cos(self.to_f())

  -> tan
    Math.tan(self.to_f())

  -> arcsin
    Math.asin(self.to_f())

  -> arccos
    Math.acos(self.to_f())

  -> arctan
    Math.atan(self.to_f())

  ## Hyperbolic functions
  -> sinh
    Math.sinh(self.to_f())

  -> cosh
    Math.cosh(self.to_f())

  -> tanh
    Math.tanh(self.to_f())

  -> arcsinh
    Math.asinh(self.to_f())

  -> arccosh
    Math.acosh(self.to_f())

  -> arctanh
    Math.atanh(self.to_f())

+ Decimal < Real
  readonly :scale

  # @arg scale #to_i
  -> new(@scale: 2)

  -> abs
  -> denominator
  -> inv
  -> normalize
  -> numerator
  -> reciprocal

  -> to_f
  -> to_i
  -> to_m

  -> floor(digits = scale)
  -> round(digits = scale)

  ## Trigonometric functions

  # @example
  #   0.sin => 0𝝅
  -> sin

  # @example
  #   0.cos => 1𝝅
  -> cos
  -> tan
  -> arcsin
  -> arccos
  -> arctan

  ## Hyperbolic functions
  -> sinh
  -> cosh
  -> tanh
  -> arcsinh
  -> arccosh
  -> arctanh

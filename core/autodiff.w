# Autodiff — forward-mode dual numbers + reverse-mode tape (v0).
#
# Forward: Dual(value, eps) propagates one directional derivative through
# arithmetic and elementary functions.
#
# Reverse: Tape records primitive ops; reverse() seeds ∂L/∂out and backprops.
# Good enough for scalar / small-vector loss landscapes and ODE sensitivity.
#
# Quantity / unit-tagged duals are a follow-up (grads carry units).

+ Dual
  -> new(@value, @eps)
    @value = Autodiff.finite_real(@value)
    @eps = Autodiff.finite_real(@eps)
    self

  -> .const(v)
    Dual.new(v, ~0.0)

  -> .var(v)
    Dual.new(v, ~1.0)

  -> value
    @value

  -> eps
    @eps

  -> +(other)
    if other.class_name == "Dual"
      return Dual.new(@value + other.value, @eps + other.eps)
    Dual.new(@value + other, @eps)

  -> -(other)
    if other.class_name == "Dual"
      return Dual.new(@value - other.value, @eps - other.eps)
    Dual.new(@value - other, @eps)

  -> -@
    Dual.new(~0.0 - @value, ~0.0 - @eps)

  -> *(other)
    if other.class_name == "Dual"
      # (u+u'ε)(v+v'ε) = uv + (u'v + uv')ε
      return Dual.new(@value * other.value, @eps * other.value + @value * other.eps)
    Dual.new(@value * other, @eps * other)

  -> /(other)
    if other.class_name == "Dual"
      v = other.value
      raise "Dual division by zero" if v == ~0.0
      quotient = @value / v
      return Dual.new(quotient, (@eps - quotient * other.eps) / v)
    raise "Dual division by zero" if other == ~0.0
    Dual.new(@value / other, @eps / other)

  -> sqrt
    raise "Dual.sqrt outside real differentiable domain" if @value <= ~0.0
    s = Math.sqrt(@value)
    Dual.new(s, @eps / (~2.0 * s))

  -> exp
    e = Math.exp(@value)
    Dual.new(e, e * @eps)

  -> log
    raise "Dual.log outside real differentiable domain" if @value <= ~0.0
    Dual.new(Math.log(@value), @eps / @value)

  -> sin
    Dual.new(Math.sin(@value), Math.cos(@value) * @eps)

  -> cos
    Dual.new(Math.cos(@value), ~0.0 - Math.sin(@value) * @eps)

  -> tanh
    t = Math.tanh(@value)
    Dual.new(t, (~1.0 - t * t) * @eps)

  -> pow(n)
    # x^n for constant n
    n = Autodiff.finite_real(n)
    return Dual.const(~1.0) if n == ~0.0
    return self if n == ~1.0
    if (@value <= ~0.0 && n != Math.floor(n)) || (@value == ~0.0 && n < ~0.0)
      raise "Dual.pow outside real differentiable domain"
    Dual.new(Math.pow(@value, n), n * Math.pow(@value, n - ~1.0) * @eps)

  -> **(n)
    self.pow(n)

  -> scale(scalar)
    scalar = Autodiff.finite_real(scalar)
    Dual.new(@value * scalar, @eps * scalar)

  -> to_s
    "Dual(" + @value.to_s() + ", " + @eps.to_s() + ")"

# Reverse-mode: very small tape of (op, a, b, out) nodes.
# op: 0=const 1=add 2=mul 3=sub 4=div 5=neg 6=exp 7=log 8=sin 9=cos 10=sqrt

+ Tape
  -> new
    @vals = []
    @parents = []  # each: [op, i, j] j=-1 if unary
    @grads = []
    self

  -> const(v)
    idx = @vals.size()
    @vals = @vals.push(v)
    @parents = @parents.push([0, -1, -1])
    @grads = @grads.push(~0.0)
    idx

  -> var(v)
    const(v)  # same storage; seed grads externally

  -> add(i, j)
    idx = @vals.size()
    @vals = @vals.push(@vals[i] + @vals[j])
    @parents = @parents.push([1, i, j])
    @grads = @grads.push(~0.0)
    idx

  -> mul(i, j)
    idx = @vals.size()
    @vals = @vals.push(@vals[i] * @vals[j])
    @parents = @parents.push([2, i, j])
    @grads = @grads.push(~0.0)
    idx

  -> sub(i, j)
    idx = @vals.size()
    @vals = @vals.push(@vals[i] - @vals[j])
    @parents = @parents.push([3, i, j])
    @grads = @grads.push(~0.0)
    idx

  -> div(i, j)
    raise "Tape division by zero" if @vals[j] == ~0.0
    idx = @vals.size()
    @vals = @vals.push(@vals[i] / @vals[j])
    @parents = @parents.push([4, i, j])
    @grads = @grads.push(~0.0)
    idx

  -> neg(i)
    idx = @vals.size()
    @vals = @vals.push(~0.0 - @vals[i])
    @parents = @parents.push([5, i, -1])
    @grads = @grads.push(~0.0)
    idx

  -> exp(i)
    idx = @vals.size()
    @vals = @vals.push(Math.exp(@vals[i]))
    @parents = @parents.push([6, i, -1])
    @grads = @grads.push(~0.0)
    idx

  -> log(i)
    raise "Tape.log outside real differentiable domain" if @vals[i] <= ~0.0
    idx = @vals.size()
    @vals = @vals.push(Math.log(@vals[i]))
    @parents = @parents.push([7, i, -1])
    @grads = @grads.push(~0.0)
    idx

  -> sin(i)
    idx = @vals.size()
    @vals = @vals.push(Math.sin(@vals[i]))
    @parents = @parents.push([8, i, -1])
    @grads = @grads.push(~0.0)
    idx

  -> cos(i)
    idx = @vals.size()
    @vals = @vals.push(Math.cos(@vals[i]))
    @parents = @parents.push([9, i, -1])
    @grads = @grads.push(~0.0)
    idx

  -> sqrt(i)
    raise "Tape.sqrt outside real differentiable domain" if @vals[i] <= ~0.0
    idx = @vals.size()
    @vals = @vals.push(Math.sqrt(@vals[i]))
    @parents = @parents.push([10, i, -1])
    @grads = @grads.push(~0.0)
    idx

  -> value(i)
    @vals[i]

  -> size
    @vals.size

  -> grad(i)
    @grads[i]

  # A primitive with an explicit local derivative, used by TapeValue methods.
  -> unary(i, value, derivative)
    index = @vals.size
    @vals.push(value)
    @parents.push([11, i, -1, derivative])
    @grads.push(~0.0)
    index

  # Traverse only the output's ancestors. Validate all local weights even
  # when a zero cotangent would hide a nonfinite intermediate.
  -> reverse(out_idx)
    self.reverse_many([out_idx], [~1.0])

  -> reverse_many(outputs, seeds)
    if outputs.size != seeds.size
      raise "Tape output/seed size mismatch"
    n = @vals.size
    reachable = []
    n.times -> reachable.push(false)
    i = 0
    while i < n
      @grads[i] = ~0.0
      i += 1
    i = 0
    while i < outputs.size
      index = outputs[i]
      name = index.class_name
      if (name != "Integer" && name != "Int" && name != "BigInt") || index < 0 || index >= n
        raise "Tape output index out of range"
      seed = Autodiff.finite_real(seeds[i])
      reachable[index] = true
      @grads[index] += seed
      i += 1
    k = n - 1
    while k >= 0
      if reachable[k]
        Autodiff.finite_real(@vals[k])
        p = @parents[k]
        op = p[0]
        a = p[1]
        b = p[2]
        wa = ~0.0
        wb = ~0.0
        if op == 1
          wa = ~1.0
          wb = ~1.0
        elsif op == 2
          wa = @vals[b]
          wb = @vals[a]
        elsif op == 3
          wa = ~1.0
          wb = ~-1.0
        elsif op == 4
          wa = ~1.0 / @vals[b]
          wb = (~0.0 - @vals[k]) / @vals[b]
        elsif op == 5
          wa = ~-1.0
        elsif op == 6
          wa = @vals[k]
        elsif op == 7
          wa = ~1.0 / @vals[a]
        elsif op == 8
          wa = Math.cos(@vals[a])
        elsif op == 9
          wa = ~0.0 - Math.sin(@vals[a])
        elsif op == 10
          wa = (~0.5 / @vals[k])
        elsif op == 11
          wa = p[3]
        Autodiff.finite_real(wa)
        Autodiff.finite_real(wb)
        g = Autodiff.finite_real(@grads[k])
        if a >= 0
          reachable[a] = true
          @grads[a] += g*wa if g != ~0.0
        if b >= 0
          reachable[b] = true
          @grads[b] += g*wb if g != ~0.0
      k -= 1
    self
+ Autodiff
  -> .finite_real(value)
    name = value.class_name
    if name != "Float" && name != "Integer" && name != "Int" && name != "BigInt" && name != "Rational"
      raise "Autodiff requires finite real scalars"
    scalar = value + ~0.0
    if scalar.nan? || scalar.infinite?
      raise "Autodiff encountered a nonfinite value or derivative"
    scalar

  -> .validate_vectors(point, tangent)
    if point.class_name != "Array" || tangent.class_name != "Array" || point.size != tangent.size
      raise "Autodiff point and tangent must be equal-sized Arrays"
    point.each -> Autodiff.finite_real(item)
    tangent.each -> Autodiff.finite_real(item)

  -> .jvp(f, point, tangent)
    Autodiff.validate_vectors(point, tangent)
    variables = []
    i = 0
    while i < point.size
      variables.push(Dual.new(point[i], tangent[i]))
      i += 1
    result = f(variables)
    vector = result.class_name == "Array"
    outputs = vector ? result : [result]
    values = []
    derivatives = []
    outputs.each ->
      if item.class_name == "Dual"
        values.push(Autodiff.finite_real(item.value))
        derivatives.push(Autodiff.finite_real(item.eps))
      else
        values.push(Autodiff.finite_real(item))
        derivatives.push(~0.0)
    {"value": vector ? values : values[0], "jvp": vector ? derivatives : derivatives[0]}

  -> .vjp(f, point, cotangent)
    if point.class_name != "Array"
      raise "Autodiff point must be an Array"
    tape = Tape.new
    variables = []
    input_indices = []
    point.each ->
      index = tape.var(Autodiff.finite_real(item))
      input_indices.push(index)
      variables.push(TapeValue.new(tape, index))
    result = f(variables)
    vector = result.class_name == "Array"
    if vector != (cotangent.class_name == "Array")
      raise "Autodiff cotangent must match scalar/vector output shape"
    outputs = vector ? result : [result]
    seeds = vector ? cotangent : [cotangent]
    if outputs.size != seeds.size
      raise "Autodiff output/cotangent size mismatch"
    values = []
    indices = []
    outputs.each ->
      if item.class_name == "TapeValue"
        raise "Autodiff output belongs to another tape" if item.tape != tape
        indices.push(item.index)
        values.push(item.value)
      else
        value = Autodiff.finite_real(item)
        indices.push(tape.const(value))
        values.push(value)
    tape.reverse_many(indices, seeds)
    gradient = input_indices.map -> Autodiff.finite_real(tape.grad(item))
    {"value": vector ? values : values[0], "vjp": gradient}

  # Forward-mode derivative of f at x (f takes Dual, returns Dual).
  -> .grad(f, x)
    d = f(Dual.var(x))
    d.eps

  -> .grad_forward(f, x)
    d = f(Dual.var(x))
    d.eps

  # Finite-difference check helper.
  -> .grad_fd(f, x, h = ~1.0e-6)
    result = Calculus.numerical_derivative(f, x, 1, :central, h)
    raise "Autodiff.grad_fd: " + result.status.to_s if !result.converged?
    result.value

+ TapeValue
  -> new(@tape, @index)
    name = @index.class_name
    if @tape.class_name != "Tape" || (name != "Integer" && name != "Int" && name != "BigInt")
      raise "TapeValue needs a Tape and integer index"
    if @index < 0 || @index >= @tape.size
      raise "TapeValue index out of range"
    self
  -> tape
    @tape
  -> index
    @index
  -> value
    @tape.value(@index)
  -> coerce(other)
    if other.class_name == "TapeValue"
      raise "cannot combine different autodiff tapes" if other.tape != @tape
      return other
    TapeValue.new(@tape, @tape.const(Autodiff.finite_real(other)))
  -> +(other)
    rhs = self.coerce(other)
    TapeValue.new(@tape, @tape.add(@index, rhs.index))
  -> -(other)
    rhs = self.coerce(other)
    TapeValue.new(@tape, @tape.sub(@index, rhs.index))
  -> *(other)
    rhs = self.coerce(other)
    TapeValue.new(@tape, @tape.mul(@index, rhs.index))
  -> /(other)
    rhs = self.coerce(other)
    TapeValue.new(@tape, @tape.div(@index, rhs.index))
  -> -@
    TapeValue.new(@tape, @tape.neg(@index))
  -> scale(scalar)
    rhs = self.coerce(Autodiff.finite_real(scalar))
    TapeValue.new(@tape, @tape.mul(@index, rhs.index))
  -> exp
    TapeValue.new(@tape, @tape.exp(@index))
  -> log
    TapeValue.new(@tape, @tape.log(@index))
  -> sqrt
    TapeValue.new(@tape, @tape.sqrt(@index))
  -> sin
    TapeValue.new(@tape, @tape.sin(@index))
  -> cos
    TapeValue.new(@tape, @tape.cos(@index))
  -> tanh
    value = Math.tanh(self.value)
    TapeValue.new(@tape, @tape.unary(@index, value, ~1.0 - value*value))
  -> pow(exponent)
    exponent = Autodiff.finite_real(exponent)
    if exponent == ~0.0
      return TapeValue.new(@tape, @tape.const(~1.0))
    return self if exponent == ~1.0
    value = self.value
    if (value <= ~0.0 && exponent != Math.floor(exponent)) || (value == ~0.0 && exponent < ~0.0)
      raise "TapeValue.pow outside real differentiable domain"
    primal = Math.pow(value, exponent)
    derivative = exponent * Math.pow(value, exponent - ~1.0)
    TapeValue.new(@tape, @tape.unary(@index, primal, derivative))
  -> **(exponent)
    self.pow(exponent)

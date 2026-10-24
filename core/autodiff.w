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

  ro :value, :eps

  -> +(other)
    v1 = @value ## f64
    e1 = @eps ## f64
    if type(other) == "Dual"
      v2 = other.value ## f64
      e2 = other.eps ## f64
      return Dual.new(v1 + v2, e1 + e2)
    o = Autodiff.finite_real(other) ## f64
    Dual.new(v1 + o, e1)

  -> -(other)
    v1 = @value ## f64
    e1 = @eps ## f64
    if type(other) == "Dual"
      v2 = other.value ## f64
      e2 = other.eps ## f64
      return Dual.new(v1 - v2, e1 - e2)
    o = Autodiff.finite_real(other) ## f64
    Dual.new(v1 - o, e1)

  -> -@
    v1 = @value ## f64
    e1 = @eps ## f64
    Dual.new(~0.0 - v1, ~0.0 - e1)

  -> *(other)
    v1 = @value ## f64
    e1 = @eps ## f64
    if type(other) == "Dual"
      # (u+u'ε)(v+v'ε) = uv + (u'v + uv')ε
      v2 = other.value ## f64
      e2 = other.eps ## f64
      return Dual.new(v1 * v2, e1 * v2 + v1 * e2)
    o = Autodiff.finite_real(other) ## f64
    Dual.new(v1 * o, e1 * o)

  -> /(other)
    v1 = @value ## f64
    e1 = @eps ## f64
    if type(other) == "Dual"
      v2 = other.value ## f64
      raise "Dual division by zero" if v2 == ~0.0
      e2 = other.eps ## f64
      quotient = v1 / v2
      return Dual.new(quotient, (e1 - quotient * e2) / v2)
    raise "Dual division by zero" if other == ~0.0
    o = Autodiff.finite_real(other) ## f64
    Dual.new(v1 / o, e1 / o)

  -> sqrt
    v1 = @value ## f64
    e1 = @eps ## f64
    raise "Dual.sqrt outside real differentiable domain" if v1 <= ~0.0
    s = Math.sqrt(v1) ## f64
    Dual.new(s, e1 / (~2.0 * s))

  -> exp
    v1 = @value ## f64
    e1 = @eps ## f64
    e = Math.exp(v1) ## f64
    Dual.new(e, e * e1)

  -> log
    v1 = @value ## f64
    e1 = @eps ## f64
    raise "Dual.log outside real differentiable domain" if v1 <= ~0.0
    Dual.new(Math.log(v1), e1 / v1)

  -> sin
    v1 = @value ## f64
    e1 = @eps ## f64
    Dual.new(Math.sin(v1), Math.cos(v1) * e1)

  -> cos
    v1 = @value ## f64
    e1 = @eps ## f64
    Dual.new(Math.cos(v1), ~0.0 - Math.sin(v1) * e1)

  -> tanh
    v1 = @value ## f64
    e1 = @eps ## f64
    t = Math.tanh(v1) ## f64
    Dual.new(t, (~1.0 - t * t) * e1)

  -> pow(n)
    # x^n for constant n
    nf = Autodiff.finite_real(n) ## f64
    return Dual.const(~1.0) if nf == ~0.0
    return self if nf == ~1.0
    v1 = @value ## f64
    e1 = @eps ## f64
    if (v1 <= ~0.0 && nf != Math.floor(nf)) || (v1 == ~0.0 && nf < ~0.0)
      raise "Dual.pow outside real differentiable domain"
    Dual.new(v1 ** nf, nf * (v1 ** (nf - ~1.0)) * e1)

  -> **(n)
    self.pow(n)

  -> scale(scalar)
    sf = Autodiff.finite_real(scalar) ## f64
    v1 = @value ## f64
    e1 = @eps ## f64
    Dual.new(v1 * sf, e1 * sf)

  -> to_s
    "Dual(" + @value.to_s() + ", " + @eps.to_s() + ")"

# Reverse-mode: very small tape of (op, a, b, out) nodes.
# op: 0=const 1=add 2=mul 3=sub 4=div 5=neg 6=exp 7=log 8=sin 9=cos 10=sqrt

+ Tape
  -> new
    @vals = []
    @ops = []
    @arg_a = []
    @arg_b = []
    @grads = []
    self

  -> const(v)
    vals = @vals ## Array
    ops = @ops ## Array
    arg_a = @arg_a ## Array
    arg_b = @arg_b ## Array
    grads = @grads ## Array
    idx = vals.size
    vals.push(v)
    ops.push(0)
    arg_a.push(-1)
    arg_b.push(-1)
    grads.push(~0.0)
    idx

  -> var(v)
    const(v)  # same storage; seed grads externally

  -> add(i, j)
    vals = @vals ## Array
    ops = @ops ## Array
    arg_a = @arg_a ## Array
    arg_b = @arg_b ## Array
    grads = @grads ## Array
    idx = vals.size
    va = vals[i] ## f64
    vb = vals[j] ## f64
    vals.push(va + vb)
    ops.push(1)
    arg_a.push(i)
    arg_b.push(j)
    grads.push(~0.0)
    idx

  -> mul(i, j)
    vals = @vals ## Array
    ops = @ops ## Array
    arg_a = @arg_a ## Array
    arg_b = @arg_b ## Array
    grads = @grads ## Array
    idx = vals.size
    va = vals[i] ## f64
    vb = vals[j] ## f64
    vals.push(va * vb)
    ops.push(2)
    arg_a.push(i)
    arg_b.push(j)
    grads.push(~0.0)
    idx

  -> sub(i, j)
    vals = @vals ## Array
    ops = @ops ## Array
    arg_a = @arg_a ## Array
    arg_b = @arg_b ## Array
    grads = @grads ## Array
    idx = vals.size
    va = vals[i] ## f64
    vb = vals[j] ## f64
    vals.push(va - vb)
    ops.push(3)
    arg_a.push(i)
    arg_b.push(j)
    grads.push(~0.0)
    idx

  -> div(i, j)
    vals = @vals ## Array
    ops = @ops ## Array
    arg_a = @arg_a ## Array
    arg_b = @arg_b ## Array
    grads = @grads ## Array
    vb = vals[j] ## f64
    raise "Tape division by zero" if vb == ~0.0
    va = vals[i] ## f64
    idx = vals.size
    vals.push(va / vb)
    ops.push(4)
    arg_a.push(i)
    arg_b.push(j)
    grads.push(~0.0)
    idx

  -> neg(i)
    vals = @vals ## Array
    ops = @ops ## Array
    arg_a = @arg_a ## Array
    arg_b = @arg_b ## Array
    grads = @grads ## Array
    va = vals[i] ## f64
    idx = vals.size
    vals.push(~0.0 - va)
    ops.push(5)
    arg_a.push(i)
    arg_b.push(-1)
    grads.push(~0.0)
    idx

  -> exp(i)
    vals = @vals ## Array
    ops = @ops ## Array
    arg_a = @arg_a ## Array
    arg_b = @arg_b ## Array
    grads = @grads ## Array
    va = vals[i] ## f64
    idx = vals.size
    vals.push(Math.exp(va))
    ops.push(6)
    arg_a.push(i)
    arg_b.push(-1)
    grads.push(~0.0)
    idx

  -> log(i)
    vals = @vals ## Array
    ops = @ops ## Array
    arg_a = @arg_a ## Array
    arg_b = @arg_b ## Array
    grads = @grads ## Array
    va = vals[i] ## f64
    raise "Tape.log outside real differentiable domain" if va <= ~0.0
    idx = vals.size
    vals.push(Math.log(va))
    ops.push(7)
    arg_a.push(i)
    arg_b.push(-1)
    grads.push(~0.0)
    idx

  -> sin(i)
    vals = @vals ## Array
    ops = @ops ## Array
    arg_a = @arg_a ## Array
    arg_b = @arg_b ## Array
    grads = @grads ## Array
    va = vals[i] ## f64
    idx = vals.size
    vals.push(Math.sin(va))
    ops.push(8)
    arg_a.push(i)
    arg_b.push(-1)
    grads.push(~0.0)
    idx

  -> cos(i)
    vals = @vals ## Array
    ops = @ops ## Array
    arg_a = @arg_a ## Array
    arg_b = @arg_b ## Array
    grads = @grads ## Array
    va = vals[i] ## f64
    idx = vals.size
    vals.push(Math.cos(va))
    ops.push(9)
    arg_a.push(i)
    arg_b.push(-1)
    grads.push(~0.0)
    idx

  -> sqrt(i)
    vals = @vals ## Array
    ops = @ops ## Array
    arg_a = @arg_a ## Array
    arg_b = @arg_b ## Array
    grads = @grads ## Array
    va = vals[i] ## f64
    raise "Tape.sqrt outside real differentiable domain" if va <= ~0.0
    idx = vals.size
    vals.push(Math.sqrt(va))
    ops.push(10)
    arg_a.push(i)
    arg_b.push(-1)
    grads.push(~0.0)
    idx

  -> value(i)
    vals = @vals ## Array
    vals[i]

  -> size
    vals = @vals ## Array
    vals.size

  -> grad(i)
    grads = @grads ## Array
    grads[i]

  # A primitive with an explicit local derivative, used by TapeValue methods.
  -> unary(i, value, derivative)
    vals = @vals ## Array
    ops = @ops ## Array
    arg_a = @arg_a ## Array
    arg_b = @arg_b ## Array
    grads = @grads ## Array
    index = vals.size
    vals.push(value)
    ops.push(11)
    arg_a.push(i)
    arg_b.push(derivative)
    grads.push(~0.0)
    index

  # Traverse only the output's ancestors. Validate all local weights even
  # when a zero cotangent would hide a nonfinite intermediate.
  -> reverse(out_idx)
    self.reverse_many([out_idx], [~1.0])

  -> reverse_many(outputs_in, seeds_in)
    outputs = outputs_in ## Array
    seeds = seeds_in ## Array
    if outputs.size != seeds.size
      raise "Tape output/seed size mismatch"
    vals = @vals ## Array
    ops = @ops ## Array
    arg_a = @arg_a ## Array
    arg_b = @arg_b ## Array
    grads = @grads ## Array
    n = vals.size
    reachable = []
    i = 0
    while i < n
      reachable.push(false)
      grads[i] = ~0.0
      i += 1
    i = 0
    n_out = outputs.size
    while i < n_out
      index = outputs[i]
      t_idx = type(index)
      if (t_idx != "Int" && t_idx != "Integer" && t_idx != "BigInt") || index < 0 || index >= n
        raise "Tape output index out of range"
      seed = Autodiff.finite_real(seeds[i]) ## f64
      reachable[index] = true
      gi = grads[index] ## f64
      grads[index] = gi + seed
      i += 1
    k = n - 1
    while k >= 0
      if reachable[k]
        vk = Autodiff.finite_real(vals[k]) ## f64
        op = ops[k] ## i64
        a = arg_a[k] ## i64
        b = -1
        wa = ~0.0
        wb = ~0.0
        if op == 1
          b = arg_b[k] ## i64
          wa = ~1.0
          wb = ~1.0
        elsif op == 2
          b = arg_b[k] ## i64
          wa = vals[b] ## f64
          wb = vals[a] ## f64
        elsif op == 3
          b = arg_b[k] ## i64
          wa = ~1.0
          wb = ~-1.0
        elsif op == 4
          b = arg_b[k] ## i64
          vb = vals[b] ## f64
          wa = ~1.0 / vb
          wb = (~0.0 - vk) / vb
        elsif op == 5
          wa = ~-1.0
        elsif op == 6
          wa = vk
        elsif op == 7
          va = vals[a] ## f64
          wa = ~1.0 / va
        elsif op == 8
          va = vals[a] ## f64
          wa = Math.cos(va) ## f64
        elsif op == 9
          va = vals[a] ## f64
          wa = ~0.0 - Math.sin(va)
        elsif op == 10
          wa = ~0.5 / vk
        elsif op == 11
          wa = Autodiff.finite_real(arg_b[k]) ## f64
        if wa - wa != ~0.0 || wb - wb != ~0.0
          raise "Autodiff encountered a nonfinite value or derivative"
        g = Autodiff.finite_real(grads[k]) ## f64
        if a >= 0
          reachable[a] = true
          if g != ~0.0
            ga = grads[a] ## f64
            grads[a] = ga + g * wa
        if b >= 0
          reachable[b] = true
          if g != ~0.0
            gb = grads[b] ## f64
            grads[b] = gb + g * wb
      k -= 1
    self
+ Autodiff
  -> .finite_real(value)
    t = type(value)
    if t == "Float"
      f = value ## f64
      if f - f != ~0.0
        raise "Autodiff encountered a nonfinite value or derivative"
      return value
    if t != "Int" && t != "Integer" && t != "BigInt" && t != "Rational"
      raise "Autodiff requires finite real scalars"
    scalar = value + ~0.0
    sf = scalar ## f64
    if sf - sf != ~0.0
      raise "Autodiff encountered a nonfinite value or derivative"
    scalar

  -> .validate_vectors(point, tangent)
    if type(point) != "Array" || type(tangent) != "Array" || point.size != tangent.size
      raise "Autodiff point and tangent must be equal-sized Arrays"
    pt = point ## Array
    tg = tangent ## Array
    n = pt.size
    i = 0
    while i < n
      Autodiff.finite_real(pt[i])
      Autodiff.finite_real(tg[i])
      i += 1

  -> .jvp(f, point_in, tangent_in)
    Autodiff.validate_vectors(point_in, tangent_in)
    point = point_in ## Array
    tangent = tangent_in ## Array
    n = point.size
    variables = []
    i = 0
    while i < n
      variables.push(Dual.new(point[i], tangent[i]))
      i += 1
    result = f(variables)
    vector = type(result) == "Array"
    outputs = vector ? result : [result]
    out_arr = outputs ## Array
    n_out = out_arr.size
    values = []
    derivatives = []
    i = 0
    while i < n_out
      item = out_arr[i]
      if type(item) == "Dual"
        values.push(Autodiff.finite_real(item.value))
        derivatives.push(Autodiff.finite_real(item.eps))
      else
        values.push(Autodiff.finite_real(item))
        derivatives.push(~0.0)
      i += 1
    {"value": vector ? values : values[0], "jvp": vector ? derivatives : derivatives[0]}

  -> .vjp(f, point_in, cotangent)
    if type(point_in) != "Array"
      raise "Autodiff point must be an Array"
    point = point_in ## Array
    n_pt = point.size
    tape = Tape.new
    variables = []
    input_indices = []
    i = 0
    while i < n_pt
      index = tape.var(Autodiff.finite_real(point[i]))
      input_indices.push(index)
      variables.push(TapeValue.new(tape, index))
      i += 1
    result = f(variables)
    vector = type(result) == "Array"
    if vector != (type(cotangent) == "Array")
      raise "Autodiff cotangent must match scalar/vector output shape"
    outputs_raw = vector ? result : [result]
    seeds_raw = vector ? cotangent : [cotangent]
    outputs = outputs_raw ## Array
    seeds = seeds_raw ## Array
    n_out = outputs.size
    if n_out != seeds.size
      raise "Autodiff output/cotangent size mismatch"
    values = []
    indices = []
    i = 0
    while i < n_out
      item = outputs[i]
      if type(item) == "TapeValue"
        raise "Autodiff output belongs to another tape" if item.tape != tape
        indices.push(item.index)
        values.push(item.value)
      else
        value = Autodiff.finite_real(item)
        indices.push(tape.const(value))
        values.push(value)
      i += 1
    tape.reverse_many(indices, seeds)
    gradient = []
    i = 0
    while i < n_pt
      gradient.push(Autodiff.finite_real(tape.grad(input_indices[i])))
      i += 1
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
  -> new(@tape, @index, trusted = false)
    if !trusted
      t_idx = type(@index)
      if type(@tape) != "Tape" || (t_idx != "Int" && t_idx != "Integer" && t_idx != "BigInt")
        raise "TapeValue needs a Tape and integer index"
      if @index < 0 || @index >= @tape.size
        raise "TapeValue index out of range"
    self
  ro :tape, :index
  -> value
    @tape.value(@index)
  -> coerce(other)
    if type(other) == "TapeValue"
      raise "cannot combine different autodiff tapes" if other.tape != @tape
      return other
    TapeValue.new(@tape, @tape.const(Autodiff.finite_real(other)), true)
  -> coerce_index(other)
    if type(other) == "TapeValue"
      raise "cannot combine different autodiff tapes" if other.tape != @tape
      return other.index
    @tape.const(Autodiff.finite_real(other))
  -> +(other)
    TapeValue.new(@tape, @tape.add(@index, self.coerce_index(other)), true)
  -> -(other)
    TapeValue.new(@tape, @tape.sub(@index, self.coerce_index(other)), true)
  -> *(other)
    TapeValue.new(@tape, @tape.mul(@index, self.coerce_index(other)), true)
  -> /(other)
    TapeValue.new(@tape, @tape.div(@index, self.coerce_index(other)), true)
  -> -@
    TapeValue.new(@tape, @tape.neg(@index), true)
  -> scale(scalar)
    r_idx = @tape.const(Autodiff.finite_real(scalar))
    TapeValue.new(@tape, @tape.mul(@index, r_idx), true)
  -> exp
    TapeValue.new(@tape, @tape.exp(@index), true)
  -> log
    TapeValue.new(@tape, @tape.log(@index), true)
  -> sqrt
    TapeValue.new(@tape, @tape.sqrt(@index), true)
  -> sin
    TapeValue.new(@tape, @tape.sin(@index), true)
  -> cos
    TapeValue.new(@tape, @tape.cos(@index), true)
  -> tanh
    v = self.value ## f64
    value = Math.tanh(v)
    TapeValue.new(@tape, @tape.unary(@index, value, ~1.0 - value*value), true)
  -> pow(exponent)
    ef = Autodiff.finite_real(exponent) ## f64
    if ef == ~0.0
      return TapeValue.new(@tape, @tape.const(~1.0), true)
    return self if ef == ~1.0
    v = self.value ## f64
    if (v <= ~0.0 && ef != Math.floor(ef)) || (v == ~0.0 && ef < ~0.0)
      raise "TapeValue.pow outside real differentiable domain"
    primal = v ** ef
    derivative = ef * (v ** (ef - ~1.0))
    TapeValue.new(@tape, @tape.unary(@index, primal, derivative), true)
  -> **(exponent)
    self.pow(exponent)

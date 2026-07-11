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
    if other.class == Dual
      return Dual.new(@value + other.value, @eps + other.eps)
    Dual.new(@value + other, @eps)

  -> -(other)
    if other.class == Dual
      return Dual.new(@value - other.value, @eps - other.eps)
    Dual.new(@value - other, @eps)

  -> -@
    Dual.new(~0.0 - @value, ~0.0 - @eps)

  -> *(other)
    if other.class == Dual
      # (u+u'ε)(v+v'ε) = uv + (u'v + uv')ε
      return Dual.new(@value * other.value, @eps * other.value + @value * other.eps)
    Dual.new(@value * other, @eps * other)

  -> /(other)
    if other.class == Dual
      v = other.value
      return Dual.new(@value / v, (@eps * v - @value * other.eps) / (v * v))
    Dual.new(@value / other, @eps / other)

  -> sqrt
    s = Math.sqrt(@value)
    Dual.new(s, @eps / (~2.0 * s))

  -> exp
    e = Math.exp(@value)
    Dual.new(e, e * @eps)

  -> log
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
    Dual.new(Math.pow(@value, n), n * Math.pow(@value, n - ~1.0) * @eps)

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
    idx = @vals.size()
    @vals = @vals.push(Math.sqrt(@vals[i]))
    @parents = @parents.push([10, i, -1])
    @grads = @grads.push(~0.0)
    idx

  -> value(i)
    @vals[i]

  -> grad(i)
    @grads[i]

  # Seed ∂L/∂out_idx = 1 and reverse.
  -> reverse(out_idx)
    n = @grads.size()
    i = 0
    while i < n
      @grads[i] = ~0.0
      i = i + 1
    @grads[out_idx] = ~1.0
    k = out_idx
    while k >= 0
      g = @grads[k]
      p = @parents[k]
      op = p[0]
      a = p[1]
      b = p[2]
      if op == 1
        @grads[a] = @grads[a] + g
        @grads[b] = @grads[b] + g
      elsif op == 2
        @grads[a] = @grads[a] + g * @vals[b]
        @grads[b] = @grads[b] + g * @vals[a]
      elsif op == 3
        @grads[a] = @grads[a] + g
        @grads[b] = @grads[b] - g
      elsif op == 4
        @grads[a] = @grads[a] + g / @vals[b]
        @grads[b] = @grads[b] - g * @vals[a] / (@vals[b] * @vals[b])
      elsif op == 5
        @grads[a] = @grads[a] - g
      elsif op == 6
        @grads[a] = @grads[a] + g * @vals[k]
      elsif op == 7
        @grads[a] = @grads[a] + g / @vals[a]
      elsif op == 8
        @grads[a] = @grads[a] + g * Math.cos(@vals[a])
      elsif op == 9
        @grads[a] = @grads[a] - g * Math.sin(@vals[a])
      elsif op == 10
        @grads[a] = @grads[a] + g / (~2.0 * @vals[k])
      # op 0 const: no parents
      k = k - 1
    self

+ Autodiff
  # Forward-mode derivative of f at x (f takes Dual, returns Dual).
  -> .grad_forward(f, x)
    d = f(Dual.var(x))
    d.eps

  # Finite-difference check helper.
  -> .grad_fd(f, x, h = ~1.0e-6)
    (f(x + h) - f(x - h)) / (~2.0 * h)

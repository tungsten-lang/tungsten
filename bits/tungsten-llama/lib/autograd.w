# autograd.w — reverse-mode automatic differentiation over core Tensor.
#
# This is the piece that turns tungsten-llama from "run models" into
# "build/train them". It layers a reverse-mode tape on top of the
# autoloaded core `Tensor` (core/tensor.w) — an N-d strided dense f32
# tensor. Everything here is COMPILED-ONLY (core Tensor's factories use
# ccalls the interpreter can't dispatch): run with `bin/tungsten -o`.
#
# Design — op-tag tape (not closures-per-node):
#   A `Var` wraps a forward `val` Tensor and an accumulated-gradient
#   `grad` Tensor, plus an op tag (:leaf/:matmul/:add/...), its parent
#   Vars, and any saved context (`aux`). `backward` walks a reverse
#   topological order and each node's `backward_step` accumulates the
#   vector-Jacobian-product into its parents' grads. Op-tag dispatch
#   (rather than a closure per node) is the most robust choice on the
#   compiled path: no reliance on closure-capture-of-mutable-state, and
#   trivial to read/debug. Reverse-topo (children before parents) makes a
#   node's grad complete before it is distributed — which is exactly what
#   makes a diamond (a value used twice) accumulate both contributions.
#
# Why local helpers instead of core's ops: core Tensor's `scale`, `relu`,
# `neg`, `square`, `sum_axis`, ... allocate via `Tensor.zeros(device,
# dtype, shape)`, which routes a CPU tensor (device == :cpu) through the
# Metal buffer path and crashes ("expected int, got string"). We only use
# the core ops that allocate through the working CPU path — `zeros(shape)`,
# `at`/`set`, `matmul`, `add`/`sub`/`mul` (with NumPy broadcasting),
# `transpose`, `contiguous`, `sum`, `mean` — and re-implement scale / relu
# / axis-0 reduction / fills here with `at`/`set` loops. We do NOT touch
# core/ (that would trigger a self-host rebuild).

# ---- CPU tensor helpers (avoid core's broken :cpu Metal-zeros path) -------

-> ag_full(shape, v)
  out = Tensor.zeros(shape)
  n = Tensor.elem_count(shape)
  fi = 0
  while fi < n
    out.set(Tensor.unravel(fi, shape), v)
    fi = fi + 1
  out

-> ag_ones(shape)
  ag_full(shape, 1.to_f)

# Elementwise scalar multiply (core `scale` is broken for :cpu tensors).
-> ag_scale(t, s)
  out = Tensor.zeros(t.shape)
  n = t.size
  fi = 0
  while fi < n
    c = Tensor.unravel(fi, t.shape)
    out.set(c, t.at(c) * s)
    fi = fi + 1
  out

# relu(t) elementwise (core `relu` is broken for :cpu tensors).
-> ag_relu(t)
  out = Tensor.zeros(t.shape)
  n = t.size
  z = 0.to_f
  fi = 0
  while fi < n
    c = Tensor.unravel(fi, t.shape)
    v = t.at(c)
    if v > z
      out.set(c, v)
    fi = fi + 1
  out

# 1.0 where t > 0 else 0.0 — the relu derivative mask.
-> ag_relu_mask(t)
  out = Tensor.zeros(t.shape)
  n = t.size
  z = 0.to_f
  one = 1.to_f
  fi = 0
  while fi < n
    c = Tensor.unravel(fi, t.shape)
    if t.at(c) > z
      out.set(c, one)
    fi = fi + 1
  out

# Sum a [B, O] tensor over axis 0 -> [O] (bias-gradient reduction).
-> ag_sum_axis0(t)
  b = t.shape[0]
  o = t.shape[1]
  out = Tensor.zeros([o])
  j = 0
  while j < o
    acc = 0.to_f
    i = 0
    while i < b
      acc = acc + t.at([i, j])
      i = i + 1
    out.set([j], acc)
    j = j + 1
  out

# ---- the tape node --------------------------------------------------------

+ Var
  rw :val         # forward value Tensor
  rw :grad        # accumulated gradient Tensor (same shape as val), nil until touched
  rw :op          # op tag symbol (:leaf, :matmul, :add, :bias_add, :mul, :scale, :relu, :sum, :mean, :mse)
  rw :parents     # Array of parent Var nodes
  rw :aux         # saved op-specific context (scalar or Tensor)
  rw :seen        # topo-sort visited marker

  -> new(val, op, parents, aux)
    @val = val
    @grad = nil
    @op = op
    @parents = parents
    @aux = aux
    @seen = false

  -> item
    @val.at([0])

  # Reset gradient + topo marker (used between optimizer steps).
  -> clear
    @grad = nil
    @seen = false
    self

  -> set_val(t)
    @val = t
    self

  -> ensure_grad
    if @grad == nil
      @grad = Tensor.zeros(@val.shape)
    self

  # Accumulate a contribution into this node's grad (same shape as val).
  -> add_grad(g)
    self.ensure_grad
    @grad = @grad.add(g)
    self

  # Post-order DFS: parents before self, so the reversed order has every
  # child ahead of its parents (reverse-topological).
  -> build_topo(order)
    if !@seen
      @seen = true
      i = 0
      while i < @parents.size()
        @parents[i].build_topo(order)
        i = i + 1
      order.push(self)
    self

  # Seed this (scalar) output's grad to ones and propagate backward.
  -> backward
    order = []
    self.build_topo(order)
    @grad = ag_ones(@val.shape)
    idx = order.size() - 1
    while idx >= 0
      order[idx].backward_step
      idx = idx - 1
    self

  # Distribute this node's grad to its parents (the VJP of the forward op).
  -> backward_step
    gout = @grad
    if @op == :add
      @parents[0].add_grad(gout)
      @parents[1].add_grad(gout)
    elsif @op == :bias_add
      @parents[0].add_grad(gout)
      @parents[1].add_grad(ag_sum_axis0(gout))
    elsif @op == :mul
      a = @parents[0]
      b = @parents[1]
      a.add_grad(gout.mul(b.val))
      b.add_grad(gout.mul(a.val))
    elsif @op == :scale
      @parents[0].add_grad(ag_scale(gout, @aux))
    elsif @op == :matmul
      a = @parents[0]
      b = @parents[1]
      a.add_grad(gout.matmul(b.val.transpose))
      b.add_grad(a.val.transpose.matmul(gout))
    elsif @op == :relu
      a = @parents[0]
      a.add_grad(gout.mul(ag_relu_mask(a.val)))
    elsif @op == :sum
      a = @parents[0]
      a.add_grad(ag_full(a.val.shape, gout.at([0])))
    elsif @op == :mean
      a = @parents[0]
      nn = a.val.size.to_f
      a.add_grad(ag_full(a.val.shape, gout.at([0]) / nn))
    elsif @op == :mse
      a = @parents[0]
      nn = a.val.size.to_f
      factor = gout.at([0]) * 2.to_f / nn
      a.add_grad(ag_scale(@aux, factor))
    self

# ---- differentiable primitives (forward + record) ------------------------

-> v_leaf(t)
  Var.new(t, :leaf, [], nil)

# Elementwise add of two equal-shape Vars.
-> v_add(a, b)
  Var.new(a.val.add(b.val), :add, [a, b], nil)

# Bias-broadcast add: x is [batch, out], bias is [out] -> [batch, out].
-> v_bias_add(x, bias)
  Var.new(x.val.add(bias.val), :bias_add, [x, bias], nil)

# Elementwise (Hadamard) multiply of two equal-shape Vars.
-> v_mul(a, b)
  Var.new(a.val.mul(b.val), :mul, [a, b], nil)

# Scalar multiply by a constant Float `s`.
-> v_scale(a, s)
  Var.new(ag_scale(a.val, s), :scale, [a], s)

# Matrix multiply: a is [M, K], b is [K, N] -> [M, N].
-> v_matmul(a, b)
  Var.new(a.val.matmul(b.val), :matmul, [a, b], nil)

-> v_relu(a)
  Var.new(ag_relu(a.val), :relu, [a], nil)

# Sum-all -> scalar (represented as a [1] tensor).
-> v_sum(a)
  s = a.val.sum
  out = Tensor.zeros([1])
  out.set([0], s)
  Var.new(out, :sum, [a], nil)

# Mean-all -> scalar ([1] tensor).
-> v_mean(a)
  m = a.val.mean
  out = Tensor.zeros([1])
  out.set([0], m)
  Var.new(out, :mean, [a], nil)

# Mean-squared-error loss against a constant target Tensor -> scalar ([1]).
# aux saves diff = pred - target so backward is grad_out * 2/n * diff.
-> v_mse(pred, target)
  diff = pred.val.sub(target)
  sq = diff.mul(diff)
  m = sq.sum / pred.val.size.to_f
  out = Tensor.zeros([1])
  out.set([0], m)
  Var.new(out, :mse, [pred], diff)

# ---- deterministic PRNG (seeded, reproducible init) -----------------------
# A plain LCG (glibc constants). state < 2^31, so state * 1103515245 stays
# under 2^63 — no i64 overflow.

+ Rng
  rw :state
  -> new(seed)
    @state = seed
  -> next_u
    @state = (@state * 1103515245 + 12345) % 2147483648
    @state
  -> next_f
    self.next_u.to_f / 2147483648.to_f
  # Uniform in [-1, 1).
  -> next_sym
    self.next_f * 2.to_f - 1.to_f

# ---- layers ---------------------------------------------------------------

# A fully-connected layer: y = x · W + b, with W a [in, out] weight Var and
# b a [out] bias Var. Weights are seeded uniform in [-scale, scale); bias 0.
+ Linear
  rw :w
  rw :b
  -> new(in_dim, out_dim, rng, scale)
    wt = Tensor.zeros([in_dim, out_dim])
    n = in_dim * out_dim
    i = 0
    while i < n
      c = Tensor.unravel(i, [in_dim, out_dim])
      wt.set(c, rng.next_sym * scale)
      i = i + 1
    bt = Tensor.zeros([out_dim])
    @w = v_leaf(wt)
    @b = v_leaf(bt)

  # x is a Var of shape [batch, in]; returns a Var [batch, out].
  -> forward(x)
    v_bias_add(v_matmul(x, @w), @b)

  -> params
    out = [@w, @b]
    out

# A 2-layer MLP: Linear -> relu -> Linear. Dimensions passed explicitly so
# the same class serves XOR (2-4-1) and other toy tasks.
+ MLP
  rw :l1
  rw :l2
  -> new(in_dim, hidden, out_dim, rng, scale)
    @l1 = Linear.new(in_dim, hidden, rng, scale)
    @l2 = Linear.new(hidden, out_dim, rng, scale)

  -> forward(x)
    h = v_relu(@l1.forward(x))
    @l2.forward(h)

  -> params
    out = []
    out.push(@l1.w)
    out.push(@l1.b)
    out.push(@l2.w)
    out.push(@l2.b)
    out

# ---- optimizer ------------------------------------------------------------

# Vanilla SGD: p <- p - lr * grad, plus zero_grad.
+ SGD
  rw :params
  rw :lr
  -> new(params, lr)
    @params = params
    @lr = lr

  -> step
    i = 0
    while i < @params.size()
      p = @params[i]
      p.set_val(p.val.sub(ag_scale(p.grad, @lr)))
      i = i + 1
    self

  -> zero_grad
    i = 0
    while i < @params.size()
      @params[i].clear
      i = i + 1
    self

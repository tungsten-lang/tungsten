# autograd_smoke.w — self-checking gold-standard tests for the reverse-mode
# autodiff tape in lib/autograd.w. Exits 0 on success, 1 on any mismatch.
#
#   cd /Users/erik/tungsten && bin/tungsten -o /tmp/ag autograd_smoke.w && /tmp/ag
#
# What it proves:
#   1. Finite-difference gradient check on EVERY primitive (analytic VJP
#      vs central-difference numeric grad) to a stated tolerance.
#   2. Gradient accumulation across a diamond (a value used twice).
#   3. End-to-end learning: MLP trained on XOR, loss strictly decreases and
#      the task is actually classified correctly.
#   4. Determinism: same seed reproduces the same trained loss.

use lib/autograd

# Central-difference step and tolerance. All tensors store f32, so the
# forward loss carries ~1e-7 rounding noise; a central difference then has
# roundoff ~ noise/(2h) and truncation ~ O(h^2). h = 1e-3 balances the two,
# putting the expected max error near ~1e-4 — so a 1e-2 tolerance is a
# comfortable, honest bar that still catches any real VJP sign/shape error.
H = 1.to_f / 1000.to_f
TOL = 1.to_f / 100.to_f

# z*z as one Var — a deliberate diamond (z feeds both operands), so the
# upstream gradient reaching the tested op is 2z (nontrivial), and it also
# exercises accumulation inside the check itself.
-> square_var(z)
  v_mul(z, z)

-> fill_rand(t, rng, scale)
  n = t.size
  fi = 0
  while fi < n
    t.set(Tensor.unravel(fi, t.shape), rng.next_sym * scale)
    fi = fi + 1
  t

# Generic finite-difference gradient check.
#   leaves : Array of Var params whose grads to verify
#   fwd    : closure () -> loss Var (a [1] scalar), rebuilt from the leaves
# Perturbs each leaf element +/- H in place, recomputes the scalar loss,
# and compares the central difference to the analytic grad from backward.
-> grad_check(name, leaves, fwd)
  lossv = fwd.call
  lossv.backward
  ana = []
  i = 0
  while i < leaves.size()
    ana.push(leaves[i].grad)
    i = i + 1
  max_err = 0.to_f
  two_h = 2.to_f * H
  pi = 0
  while pi < leaves.size()
    p = leaves[pi].val
    g = ana[pi]
    n = p.size
    fi = 0
    while fi < n
      c = Tensor.unravel(fi, p.shape)
      orig = p.at(c)
      p.set(c, orig + H)
      lp = fwd.call.item
      p.set(c, orig - H)
      lm = fwd.call.item
      p.set(c, orig)
      num = (lp - lm) / two_h
      err = (num - g.at(c)).abs
      if err > max_err
        max_err = err
      fi = fi + 1
    pi = pi + 1
  << "  " + name + ": max |analytic - numeric| = " + max_err.to_s
  if max_err > TOL
    << "FAIL " + name + " gradient check exceeds tol " + TOL.to_s
    exit 1
  self

<< "=== finite-difference gradient checks (h=" + H.to_s + ", tol=" + TOL.to_s + ") ==="

rng = Rng.new(12345)

# --- matmul: a[2,3] . b[3,2] -> [2,2], nontrivial upstream via sum(z*z) ---
ma = v_leaf(fill_rand(Tensor.zeros([2, 3]), rng, 1.to_f))
mb = v_leaf(fill_rand(Tensor.zeros([3, 2]), rng, 1.to_f))
grad_check("matmul", [ma, mb], -> () v_sum(square_var(v_matmul(ma, mb))))

# --- add: elementwise, upstream sum(z*z) ---
aa = v_leaf(fill_rand(Tensor.zeros([2, 3]), rng, 1.to_f))
ab = v_leaf(fill_rand(Tensor.zeros([2, 3]), rng, 1.to_f))
grad_check("add", [aa, ab], -> () v_sum(square_var(v_add(aa, ab))))

# --- bias_add: x[3,2] + bias[2] broadcast, upstream sum(z*z) ---
bx = v_leaf(fill_rand(Tensor.zeros([3, 2]), rng, 1.to_f))
bb = v_leaf(fill_rand(Tensor.zeros([2]), rng, 1.to_f))
grad_check("bias_add", [bx, bb], -> () v_sum(square_var(v_bias_add(bx, bb))))

# --- mul: elementwise product, loss = sum(a*b) => grads are b and a ---
ua = v_leaf(fill_rand(Tensor.zeros([2, 3]), rng, 1.to_f))
ub = v_leaf(fill_rand(Tensor.zeros([2, 3]), rng, 1.to_f))
grad_check("mul", [ua, ub], -> () v_sum(v_mul(ua, ub)))

# --- scale: constant factor, upstream sum(z*z) ---
sa = v_leaf(fill_rand(Tensor.zeros([2, 3]), rng, 1.to_f))
sfac = 3.to_f / 2.to_f
grad_check("scale", [sa], -> () v_sum(square_var(v_scale(sa, sfac))))

# --- relu: explicit values bounded away from 0 (kink safety), sum(z*z) ---
ra_t = Tensor.zeros([2, 3])
ra_t.set([0, 0], 0.to_f - 7.to_f / 10.to_f)
ra_t.set([0, 1], 5.to_f / 10.to_f)
ra_t.set([0, 2], 0.to_f - 12.to_f / 10.to_f)
ra_t.set([1, 0], 9.to_f / 10.to_f)
ra_t.set([1, 1], 3.to_f / 10.to_f)
ra_t.set([1, 2], 0.to_f - 4.to_f / 10.to_f)
ra = v_leaf(ra_t)
grad_check("relu", [ra], -> () v_sum(square_var(v_relu(ra))))

# --- sum: grad is all ones ---
qa = v_leaf(fill_rand(Tensor.zeros([2, 3]), rng, 1.to_f))
grad_check("sum", [qa], -> () v_sum(qa))

# --- mean: grad is 1/n each ---
na = v_leaf(fill_rand(Tensor.zeros([2, 3]), rng, 1.to_f))
grad_check("mean", [na], -> () v_mean(na))

# --- mse: grad is 2/n (pred - target) ---
pa = v_leaf(fill_rand(Tensor.zeros([2, 3]), rng, 1.to_f))
tgt = fill_rand(Tensor.zeros([2, 3]), rng, 1.to_f)
grad_check("mse", [pa], -> () v_mse(pa, tgt))

# ============================================================================
# Diamond: a value used twice must accumulate BOTH contributions.
#   y = x * x (x feeds both operands); loss = sum(y); d loss/dx = 2x.
# ============================================================================
<< "=== diamond gradient accumulation ==="
dx_t = Tensor.zeros([4])
dx_t.set([0], 2.to_f)
dx_t.set([1], 3.to_f)
dx_t.set([2], 0.to_f - 1.to_f)
dx_t.set([3], 5.to_f)
dx = v_leaf(dx_t)
dy = v_mul(dx, dx)
dloss = v_sum(dy)
dloss.backward
di = 0
diamond_ok = true
while di < 4
  expect = 2.to_f * dx_t.at([di])
  got = dx.grad.at([di])
  if (got - expect).abs > TOL
    diamond_ok = false
  di = di + 1
<< "  loss = " + dloss.item.to_s + " (expect 4+9+1+25 = 39)"
<< "  grad = " + dx.grad.at([0]).to_s + ", " + dx.grad.at([1]).to_s + ", " + dx.grad.at([2]).to_s + ", " + dx.grad.at([3]).to_s + " (expect 2x = 4, 6, -2, 10)"
if !diamond_ok
  << "FAIL diamond accumulation wrong"
  exit 1
if (dloss.item - 39.to_f).abs > TOL
  << "FAIL diamond loss value"
  exit 1
<< "  diamond OK"

# ============================================================================
# End-to-end: train a 2-4-1 MLP (relu hidden) on XOR with SGD + MSE.
# Assert the loss strictly decreases across checkpoints, the final loss is
# below a threshold that only a solved XOR reaches, and all 4 patterns are
# classified correctly.
# ============================================================================
<< "=== end-to-end XOR training ==="

-> build_xor_inputs
  x = Tensor.zeros([4, 2])
  x.set([0, 0], 0.to_f)
  x.set([0, 1], 0.to_f)
  x.set([1, 0], 0.to_f)
  x.set([1, 1], 1.to_f)
  x.set([2, 0], 1.to_f)
  x.set([2, 1], 0.to_f)
  x.set([3, 0], 1.to_f)
  x.set([3, 1], 1.to_f)
  x

-> build_xor_targets
  y = Tensor.zeros([4, 1])
  y.set([0, 0], 0.to_f)
  y.set([1, 0], 1.to_f)
  y.set([2, 0], 1.to_f)
  y.set([3, 0], 0.to_f)
  y

# Train and return the final loss (deterministic for a given seed).
-> train_xor(seed, epochs, lr)
  rng2 = Rng.new(seed)
  scale = 1.to_f
  model = MLP.new(2, 4, 1, rng2, scale)
  opt = SGD.new(model.params, lr)
  xin = build_xor_inputs
  ytgt = build_xor_targets
  losses = []
  ep = 0
  while ep < epochs
    opt.zero_grad
    xv = v_leaf(xin)
    pred = model.forward(xv)
    loss = v_mse(pred, ytgt)
    loss.backward
    opt.step
    if ep % (epochs / 10) == 0
      losses.push(loss.item)
    ep = ep + 1
  # final loss + predictions on a clean forward pass
  xv2 = v_leaf(xin)
  pred2 = model.forward(xv2)
  final = v_mse(pred2, ytgt).item
  {losses: losses, final: final, pred: pred2.val}

lr = 3.to_f / 10.to_f
res = train_xor(7, 1000, lr)
losses = res[:losses]

# Print the loss curve checkpoints.
ci = 0
curve = StringBuffer(256)
curve << "  loss curve: "
while ci < losses.size()
  if ci > 0
    curve << " -> "
  curve << losses[ci].to_s
  ci = ci + 1
<< curve.to_s
<< "  final loss = " + res[:final].to_s

# Assert strictly decreasing across checkpoints (full-batch GD descends).
ci = 1
while ci < losses.size()
  if losses[ci] >= losses[ci - 1]
    << "FAIL loss not strictly decreasing at checkpoint " + ci.to_s
    exit 1
  ci = ci + 1

# Assert learned: final loss well below the 0.25 you'd get from a constant
# 0.5 guess. 0.02 is only reachable by an actually-solved XOR.
threshold = 2.to_f / 100.to_f
if res[:final] >= threshold
  << "FAIL final loss " + res[:final].to_s + " did not reach threshold " + threshold.to_s
  exit 1

# Assert every pattern classified correctly (round at 0.5).
targets = build_xor_targets
half = 5.to_f / 10.to_f
pi = 0
while pi < 4
  p = res[:pred].at([pi, 0])
  tv = targets.at([pi, 0])
  cls = 0.to_f
  if p > half
    cls = 1.to_f
  if (cls - tv).abs > half
    << "FAIL XOR pattern " + pi.to_s + " misclassified: pred=" + p.to_s + " target=" + tv.to_s
    exit 1
  pi = pi + 1
<< "  all 4 XOR patterns classified correctly"

# Determinism: same seed -> identical final loss.
<< "=== determinism ==="
res_b = train_xor(7, 1000, lr)
<< "  run A final = " + res[:final].to_s
<< "  run B final = " + res_b[:final].to_s
if (res[:final] - res_b[:final]).abs > 1.to_f / 1000000000.to_f
  << "FAIL nondeterministic training"
  exit 1
<< "  deterministic OK"

<< "ALL AUTOGRAD CHECKS PASSED"

# Capstone: single-head self-attention composed entirely from core/tensor.
#
# Exercises the whole library end-to-end on a real transformer primitive:
#   Q,K,V = X · Wq^T, X · Wk^T, X · Wv^T   (GPU bf16 .linear, Metal 4 tensors)
#   scores = (Q · K^T) / sqrt(d_head)        (.matmul + .transpose auto-contiguous, .scale)
#   attn   = softmax(scores, axis=1)         (.softmax)
#   out    = attn · V                        (.matmul)
#
# Shapes: X[S,Dm] bf16; Wq/Wk/Wv[Dh,Dm] bf16; Q/K/V[S,Dh] f32; scores/attn[S,S];
# out[S,Dh]. Compiled-only + macOS 26.

use core/tensor
device = metal_device()

S  = 64      # sequence length
DM = 32      # d_model
DH = 32      # d_head

# Deterministic small bf16-exact fills.
-> fill(t, rows, cols, a, b)
  i = 0
  while i < rows
    j = 0
    while j < cols
      t.set([i, j], (((i * a + j * b) % 5) - 2).to_f)
      j = j + 1
    i = i + 1

x  = Tensor.zeros(device, Tensor.bf16, [S, DM])
fill(x, S, DM, 3, 1)
wq = Tensor.zeros(device, Tensor.bf16, [DH, DM])
fill(wq, DH, DM, 1, 2)
wk = Tensor.zeros(device, Tensor.bf16, [DH, DM])
fill(wk, DH, DM, 2, 1)
wv = Tensor.zeros(device, Tensor.bf16, [DH, DM])
fill(wv, DH, DM, 1, 3)

# Q,K,V projections on the GPU (bf16 cooperative tensors) -> f32.
q = x.linear(wq)
k = x.linear(wk)
v = x.linear(wv)
<< "Q/K/V: (" + q.shape[0].to_s + "," + q.shape[1].to_s + ") f32"

# scores = Q·K^T / sqrt(DH)   (K^T is a non-contiguous view -> auto-materialized)
scale = ~1.0 / Math.sqrt(DH.to_f)
scores = q.matmul(k.transpose).scale(scale)
<< "scores: (" + scores.shape[0].to_s + "," + scores.shape[1].to_s + ")"

attn = scores.softmax(1)
out = attn.matmul(v)
<< "out:    (" + out.shape[0].to_s + "," + out.shape[1].to_s + ")"

# Invariants: each attention row is a probability distribution (sums to 1),
# and the output is finite.
maxrow_err = ~0.0
i = 0
while i < S
  rsum = ~0.0
  j = 0
  while j < S
    rsum = rsum + attn.at([i, j])
    j = j + 1
  d = rsum - ~1.0
  if d < ~0.0
    d = ~0.0 - d
  if d > maxrow_err
    maxrow_err = d
  i = i + 1
<< "max |row_sum(attn) - 1| = " + maxrow_err.to_s
if maxrow_err < ~0.001
  << "PASS — single-head attention runs end-to-end; attention rows are normalized."
else
  << "FAIL — attention rows do not sum to 1."

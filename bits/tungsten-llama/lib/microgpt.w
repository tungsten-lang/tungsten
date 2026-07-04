# microGPT in pure Tungsten — char-level transformer, ~4192 fp32 params.
#
# Same architecture as `talos-vs-macbook/bench_c.c`:
#   vocab=27, block=16, n_layer=1, n_head=4, n_embd=16, head_dim=4, MLP=4x.
#   RMSNorm (no learnable gain), ReLU MLP, no biases, untied lm_head.
#
# All loops written `.times -> (i) ...` for idiomatic Tungsten codegen.

use core/file

in Tungsten:Llama

MGPT_VOCAB = 27
MGPT_BLOCK = 16
MGPT_EMBD  = 16
MGPT_HEAD  = 4
MGPT_HD    = 4
MGPT_MLP_H = 64
MGPT_BOS   = 26
MGPT_TEMP  = ~0.5

# Weight offsets in the flat fp32 buffer (in #floats).
MGPT_OFF_WTE = 0
MGPT_OFF_WPE = 432
MGPT_OFF_WQ  = 688
MGPT_OFF_WK  = 944
MGPT_OFF_WV  = 1200
MGPT_OFF_WO  = 1456
MGPT_OFF_W1  = 1712
MGPT_OFF_W2  = 2736
MGPT_OFF_LM  = 3760
MGPT_TOTAL   = 4192

MGPT_INV_EMBD   = ~0.0625
MGPT_EPS        = ~0.00001
MGPT_ATTN_SCALE = ~0.5

# y[r] = sum_{j<16} wt[w_off + r*16 + j] * x[j],   r in 0..r_max-1
## f32[]: wt
## i32: w_off
## f32[]: x
## f32[]: y
## i32: r_max
fn matvec_16in(wt, w_off, x, y, r_max)
  r_max.times -> (r)
    base = w_off + r * 16 ## i32
    acc = ~0.0 ## f32
    16.times -> acc = acc + wt[base + j] * x[j]
    y[r] = acc

# y = wt @ x where wt is (EMBD=16, MLP_H=64) row-major.
## f32[]: wt
## i32: w_off
## f32[]: x
## f32[]: y
fn matvec_mlp_out(wt, w_off, x, y)
  MGPT_EMBD.times -> (r)
    base = w_off + r * MGPT_MLP_H ## i32
    acc = ~0.0 ## f32
    MGPT_MLP_H.times -> acc = acc + wt[base + j] * x[j]
    y[r] = acc

## f32[]: x
fn rmsnorm(x)
  ms = ~0.0 ## f32
  MGPT_EMBD.times -> ms = ms + x[i] * x[i]
  ms = ms * MGPT_INV_EMBD
  scale = ~1.0 / Math.sqrt(ms + MGPT_EPS) ## f32
  MGPT_EMBD.times -> x[i] = x[i] * scale

# xorshift32 — deterministic per seed, sub-nanosecond per call.
+ XorRng
  rw :state ## i32

  -> new(seed)
    @state = seed

  -> next
    x = @state ## i32
    x = x ^ (x << 13)
    x = x ^ (x >> 17)
    x = x ^ (x << 5)
    @state = x
    x

  -> urand
    x = @state ## i32
    x = x ^ (x << 13)
    x = x ^ (x >> 17)
    x = x ^ (x << 5)
    @state = x
    bits = x >> 8 ## i32

    if bits < 0
      bits = 0 - bits
    bits.to_f * ~5.960464477539063e-08

## f32[]: p
fn sample_probs(p, rng)
  r = rng.urand
  c = ~0.0 ## f32
  i = 0 ## i32
  while i < MGPT_VOCAB - 1
    c = c + p[i]
    if r < c
      return i
    i = i + 1
  MGPT_VOCAB - 1

# Forward one token. kc, vc are (BLOCK, EMBD) cache buffers (f32[256] each).
# al is a scratch f32[16] for per-head attention scores.
# Returns the next-token id.
## f32[]: wt
## f32[]: kc
## f32[]: vc
## f32[]: x
## f32[]: xr
## f32[]: q
## f32[]: k
## f32[]: v
## f32[]: h
## f32[]: head_out
## f32[]: logits
## f32[]: al
## i32: tok
## i32: pos
fn mgpt_step(wt, kc, vc, x, xr, q, k, v, h, head_out, logits, al, rng, tok, pos)
  # x = wte[tok] + wpe[pos]
  MGPT_EMBD.times -> (i)
    x[i] = wt[MGPT_OFF_WTE + tok * MGPT_EMBD + i] + wt[MGPT_OFF_WPE + pos * MGPT_EMBD + i]
  rmsnorm(x)

  # save residual; pre-attn RMSNorm
  MGPT_EMBD.times -> xr[i] = x[i]
  rmsnorm(x)

  matvec_16in(wt, MGPT_OFF_WQ, x, q, MGPT_EMBD)
  matvec_16in(wt, MGPT_OFF_WK, x, k, MGPT_EMBD)
  matvec_16in(wt, MGPT_OFF_WV, x, v, MGPT_EMBD)

  # cache k, v at position pos
  MGPT_EMBD.times -> (i)
    kc[pos * MGPT_EMBD + i] = k[i]
    vc[pos * MGPT_EMBD + i] = v[i]

  t_n = pos + 1 ## i32

  # per-head softmax(QK^T) V
  MGPT_HEAD.times -> (hi)
    qoff = hi * MGPT_HD ## i32
    maxl = ~-1.0e30 ## f32
    t_n.times -> (t)
      koff = t * MGPT_EMBD + qoff ## i32
      dot = q[qoff + 0] * kc[koff + 0] ## f32
      dot = dot + q[qoff + 1] * kc[koff + 1]
      dot = dot + q[qoff + 2] * kc[koff + 2]
      dot = dot + q[qoff + 3] * kc[koff + 3]
      val = dot * MGPT_ATTN_SCALE ## f32
      al[t] = val

      if val > maxl
        maxl = val

    # softmax over al[0..t_n)
    s = ~0.0 ## f32
    t_n.times -> (t)
      e = Math.exp(al[t] - maxl)
      al[t] = e
      s = s + e
    inv = ~1.0 / s ## f32

    o0 = ~0.0 ## f32
    o1 = ~0.0
    o2 = ~0.0
    o3 = ~0.0

    t_n.times -> (t)
      voff = t * MGPT_EMBD + qoff ## i32
      w_t = al[t] * inv ## f32
      o0 = o0 + w_t * vc[voff + 0]
      o1 = o1 + w_t * vc[voff + 1]
      o2 = o2 + w_t * vc[voff + 2]
      o3 = o3 + w_t * vc[voff + 3]
    head_out[qoff + 0] = o0
    head_out[qoff + 1] = o1
    head_out[qoff + 2] = o2
    head_out[qoff + 3] = o3

  # output proj + residual
  matvec_16in(wt, MGPT_OFF_WO, head_out, x, MGPT_EMBD)
  MGPT_EMBD.times -> x[i] = x[i] + xr[i]

  # save residual; pre-MLP RMSNorm
  MGPT_EMBD.times -> xr[i] = x[i]
  rmsnorm(x)

  # MLP fc1 (16 -> 64)
  MGPT_MLP_H.times -> (r)
    base = MGPT_OFF_W1 + r * MGPT_EMBD ## i32
    acc = ~0.0 ## f32
    MGPT_EMBD.times -> (j)
      acc = acc + wt[base + j] * x[j]
    if acc < ~0.0
      acc = ~0.0
    h[r] = acc

  # MLP fc2 (64 -> 16)
  matvec_mlp_out(wt, MGPT_OFF_W2, h, x)

  # residual + final RMSNorm
  MGPT_EMBD.times -> x[i] = x[i] + xr[i]
  rmsnorm(x)

  # lm_head: logits[VOCAB] = lm_head @ x
  matvec_16in(wt, MGPT_OFF_LM, x, logits, MGPT_VOCAB)

  # temperature scale + softmax + multinomial sample
  inv_temp = ~1.0 / MGPT_TEMP ## f32

  MGPT_VOCAB.times -> logits[i] = logits[i] * inv_temp

  maxl = logits[0] ## f32
  MGPT_VOCAB.times -> (i)
    if logits[i] > maxl
      maxl = logits[i]
  s = ~0.0 ## f32
  MGPT_VOCAB.times -> (i)
    e = Math.exp(logits[i] - maxl)
    logits[i] = e
    s = s + e

  inv_s = ~1.0 / s ## f32

  MGPT_VOCAB.times -> logits[i] = logits[i] * inv_s

  sample_probs(logits, rng)

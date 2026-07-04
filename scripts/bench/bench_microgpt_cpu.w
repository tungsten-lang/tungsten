# microGPT pure-Tungsten CPU bench. Char-by-char, batch=1, autoregressive.
# Compares against bench_c.c from talos-vs-macbook (~3.8M tok/s on M5 Max).

use core/file
use tungsten-llama/microgpt

WEIGHTS_PATH = "bits/tungsten-llama/lib/models/microgpt/weights_fp32.bin"

mm = File.mmap(WEIGHTS_PATH)
src = mm.view_at(0, 32, MGPT_TOTAL)
# Copy from BigArray (mmap view) into a typed f32[] for fast indexed access.
# Explicit .to_f coerces from boxed-double to f32 lane.
wt = f32[4192]
MGPT_TOTAL.times -> (i)
  wt[i] = src[i].to_f

# Per-token scratch buffers — allocated once, reused.
x        = f32[16]
xr       = f32[16]
q        = f32[16]
k        = f32[16]
v        = f32[16]
h        = f32[64]
head_out = f32[16]
logits   = f32[27]
al       = f32[16]
K_cache  = f32[256]
V_cache  = f32[256]

rng = XorRng.new(42)

warmup = 20000
n_iters = 200000
i = 0
tok = MGPT_BOS
pos = 0
while i < warmup
  tok = mgpt_step(wt, K_cache, V_cache, x, xr, q, k, v, h, head_out, logits, al, rng, tok, pos)
  pos = pos + 1
  if pos >= MGPT_BLOCK
    pos = 0
    tok = MGPT_BOS
  i = i + 1

t0 = clock
i = 0
while i < n_iters
  tok = mgpt_step(wt, K_cache, V_cache, x, xr, q, k, v, h, head_out, logits, al, rng, tok, pos)
  pos = pos + 1
  if pos >= MGPT_BLOCK
    pos = 0
    tok = MGPT_BOS
  i = i + 1
elapsed = clock - t0

rate = n_iters.to_f / elapsed
ns_per_token = elapsed * ~1.0e9 / n_iters.to_f

<< "tungsten-cpu  " + rate.to_s + " tok/sec  (" + ns_per_token.to_s + " ns/tok)"

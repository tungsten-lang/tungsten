# microGPT — pure Tungsten port of [talos-vs-macbook](https://github.com/AlexCheema/talos-vs-macbook)

Karpathy's microGPT — a 4192-parameter character-level transformer — ported to
Tungsten with three implementations: pure-Tungsten CPU, single-fused-kernel
GPU (matches the original benchmark's per-token-dispatch shape), and a
many-tokens-batched GPU kernel that runs S independent autoregressive streams
in one Metal dispatch.

Architecture: vocab=27, block=16, n_layer=1, n_head=4, n_embd=16, head_dim=4,
MLP=4×, RMSNorm (no learnable gain), ReLU MLP, no biases, untied lm_head.
Total params: 4192 fp32 = ~17 KB. ~4000 MACs per token. Whole model fits in L1.

## Results on M5 Max

```
implementation                              tok/sec        vs FPGA    vs C+NEON
------------------------------------  -------------  ------------  -----------
pure-python                                   7,430        0.14×       0.0019×
numpy fp32                                   40,244        0.76×       0.011×
mlx fp32 (cpu)                                9,350        0.18×       0.0024×
mlx fp32 (gpu)                                3,337        0.06×       0.0009×
tungsten-cpu (this repo, no NEON)            26,033        0.49×       0.0068×
tungsten-gpu fused (1 stream, 1 step/dispatch)
                                              6,228        0.12×       0.0016×
TALOS-V2 (FPGA, 56MHz)                       53,000        1.00×       0.014×
c fp32+NEON (single thread)               4,193,811       79.1×        1.000×
c fp32+NEON multi-thread (T=12)          38,436,034      725×          9.16×
c Accelerate/SME2 (single thread)         5,277,154       99.6×        1.26×
c Accelerate/SME2 multi-thread (T=12)    58,587,939    1,105×         13.97×
tungsten-gpu streams (fp32 baseline)    137,433,000    2,593×         32.8×
tungsten-gpu streams fp16              ≈135,548,000    2,557×         32.3×
tungsten-gpu streams half4             ≈142,172,000    2,683×         33.9×
tungsten-gpu streams tgkv              ≈143,624,000    2,710×         34.2×
tungsten-gpu streams sg (S=8192,N=256)  407,342,000    7,686×         97.1×
tungsten-gpu streams sg (S=32768,N=256) 471,903,000    8,904×        112.5×
tungsten + fused GPU+CPU (sg + sme_mt)  528,328,834   9,968×         126.0×
```

The headline result: **fused GPU + CPU concurrent hit 528M tok/sec
aggregate** — close to ~10,000× the FPGA. The two engines run at ~100% of
their alone-rates simultaneously, so this is essentially perfect
concurrency. GPU sg-streams alone (variant 4) lands at 472M, 3.4× the
fp32 streams baseline, by restructuring matvec into 8-stream-per-TG
matrix-matrix that fits Apple's 8×8 simdgroup_matrix tile.

### How the GPU streams kernel evolves

| variant                         | what changed                          |  peak tok/s |
|---------------------------------|---------------------------------------|------------:|
| `microgpt_streams.metal`        | fp32 storage, 1 stream per TG         |        137M |
| `microgpt_streams_fp16.metal`   | fp16 weights + KV, fp32 accumulators  |        136M |
| `microgpt_streams_half4.metal`  | half4 vectorized inner products       |        142M |
| `microgpt_streams_tgkv.metal`   | KV cache in threadgroup memory        |        144M |
| `microgpt_streams_sg.metal`     | 8 streams/TG via simdgroup_matrix     |        472M |

The fp16 / half4 / tgkv steps each individually move the needle ≤5%
because the kernel is compute-bound at 1 stream-per-TG — the matvec
inner loop is what dominates. The simdgroup_matrix restructure is the
headline because it *changes the shape of the work* — matvec → matmul —
so the GPU's matrix coprocessor can engage.

### Negative results (kept for the record)

- **bf16 weights via simdgroup_matrix.** M5 GPU's bf16 matmul path is
  measurably slower than fp16 in this kernel; not worth the precision
  upgrade.
- **2 simdgroups per TG.** Splitting matmul tiles across two simdgroups
  was a wash at S=64 and -10% at S=8192 — more sync, no win.
- **ANE via CoreML.** All four `compute_units` settings give identical
  ~400K tok/s — the bottleneck is dispatch, not the device.

## Files

| file | what |
|---|---|
| `weights_fp32.bin` | 4192 floats, flat, in talos-vs-macbook's `WEIGHT_ORDER` |
| `../../microgpt.w` | model + xorshift RNG + sampler in pure Tungsten |
| `../../kernels/microgpt_fused.metal` | single-fused-kernel autoregressive forward pass |
| `../../kernels/microgpt_streams.metal` | many-streams batched, 1 stream per TG (fp32) |
| `../../kernels/microgpt_streams_fp16.metal` | variant: fp16 storage |
| `../../kernels/microgpt_streams_half4.metal` | variant: + half4 vectorized matvec |
| `../../kernels/microgpt_streams_tgkv.metal` | variant: + KV in threadgroup memory |
| `../../kernels/microgpt_streams_sg.metal` | variant: 8 streams/TG simdgroup_matrix |
| `../../../../scripts/bench/bench_microgpt_cpu.w` | Tungsten CPU bench |
| `../../../../scripts/bench/bench_microgpt_gpu.w` | fused-kernel bench (autoregressive) |
| `../../../../scripts/bench/bench_microgpt_gpu_streams*.w` | streams sweep, one per variant |
| `../../../../scripts/bench/bench_microgpt_fused.sh` | concurrent GPU+CPU fused harness |
| `../../microgpt/c/bench_c*.c` | vendored C reference benches (NEON / Accelerate) |

Get weights: `cd talos-vs-macbook && ./download.sh && python3 convert_weights.py`,
then copy `assets/weights_fp32.bin` into this directory.

## Where each implementation falls short, and why

### tungsten-cpu: 26k tok/sec — 147× behind C+NEON

The Tungsten CPU implementation lands above MLX-CPU and below NumPy / FPGA.
It is **not** dispatch-overhead-bound the way NumPy/MLX are; for a 4-KMAC
model on a 12-GHz NEON-capable CPU, the floor is ~270 ns/token, and we
land at 38 µs/token. The gap is f32 codegen.

Even with `## f32[]: x` type hints on every parameter, Tungsten emits
NaN-boxed math (`w_mul`, `w_add` runtime calls) for inner products instead
of native `fmul`/`fadd`. The `f32[]` hint informs storage layout (so `wt[i]`
is a direct typed-array load) but the math doesn't get specialized, which
kills vectorization. The IR shows:

```llvm
%t15 = call i64 @w_method_call_cached(i64 %wt, ..., ...)   ; wt[i]
%t19 = call i64 @w_method_call_cached(i64 %x,  ..., ...)   ; x[j]
%t20 = call i64 @w_mul(i64 %t15, i64 %t19)                  ; * boxed
%t24 = call i64 @w_add(i64 ..., i64 %t20)                   ; + boxed
```

Each boxed math call is ~10 ns. At 4000 muls + 4000 adds + bookkeeping per
token, that's a 80+ µs floor; we measure 38 µs because some bookkeeping
optimizes out. Tungsten's boxed-math runtime is genuinely fast at what it
is, but it's not native f32. To match C+NEON would require:

- Compiler lowering of `f32[]` indexed reads to native `load <4 x float>`.
- Recognition that `acc = acc + a*b` with all-f32 hints is f32 FMA, not boxed.
- Autovectorization of the unrolled inner loop.

This is real compiler work and it's the right place to invest if Tungsten
wants to be competitive on small-tensor CPU workloads.

### tungsten-gpu fused: 6.2k tok/sec — better than MLX, worse than CPU

One Metal dispatch per token, one threadgroup per dispatch, 32 threads inside
the threadgroup running the whole forward pass. 160 µs per token end-to-end.

This is **2× MLX-GPU** (3.3k) — the win is amortizing per-op kernel launches:
MLX issues ~25 dispatches per token; we issue 1. But it's still slower than
CPU, because for a 4-KMAC model the GPU pipeline depth and host round-trip
overhead per token swamp anything we save on op-launches.

The lesson confirms the original talos-vs-macbook framing: **for char-by-char
batch=1 autoregressive inference at this size, the CPU is structurally the
right tool.** GPU's strength is parallelism, and there's none in this shape.

### tungsten-gpu streams: 134M tok/sec aggregate

This is the implementation where GPU finally pays. S independent streams
run in parallel; each threadgroup produces N_STEPS tokens autoregressively
without any host round-trip. The host issues ONE dispatch and gets back
S × N_STEPS tokens.

```
  S         N_STEPS    aggregate tok/s   per-stream tok/s   us/dispatch
  --------  ---------  ----------------  -----------------  -----------
  S=1       16         48,384            48,384             330 µs
  S=1       64         116,715           116,715            548 µs
  S=1       256        200,181           200,181            1.28 ms
  S=16      256        3.19M             199,874            1.28 ms
  S=64      64         9.15M             143,013            447 µs
  S=64      256        12.6M             197,145            1.30 ms
  S=256     256        47.9M             187,080            1.37 ms
  S=1024    16         66.7M             65,163             246 µs
  S=1024    64         111M              108,573            589 µs
  S=1024    256        134M              130,938            1.96 ms
```

Reading across rows: per-stream throughput stays around 130-200k tok/s up
to S=256 (the GPU has spare lanes), then degrades at S=1024 as we saturate
the chip. Aggregate throughput keeps climbing — at S=1024 we're issuing
1024 × 32 = 32,768 GPU threads, against M5 Max's ~40,000 ALU lanes, so
we're nearly full.

**Single-stream GPU (S=1) beats the FPGA by 3.78×** — the model is big
enough on Apple silicon that running it once on the GPU costs ~5 µs per
token of in-kernel work + ~325 µs of dispatch + readback overhead. The
325 µs dispatch dominates, exactly why the original repo found MLX-GPU
slow at single-token batch=1.

**At S=64 we beat C+NEON by 3.3×.** Beyond that, GPU pulls way ahead — 35×
at S=1024. The C version is single-threaded; the GPU is using all 40 cores.

### What this would tell you about the FPGA

The FPGA's selling points are deterministic latency, sub-watt power, and
fitting on something credit-card sized. It is correct in those dimensions.
On throughput per workload of "generate a lot of names", a phone-class
neural accelerator running 1024 streams in parallel beats it by 4 orders
of magnitude. That tradeoff is the actual answer to "is the FPGA
impressive?": yes for what it is; no for the workload that this benchmark
shape implies. talos-vs-macbook's original pitch was right.

## How to run

```bash
# CPU (pure Tungsten)
./bin/tungsten compile --release scripts/bench/bench_microgpt_cpu.w
./scripts/bench/bench_microgpt_cpu.wc

# GPU fused (1 token per dispatch)
./bin/tungsten compile --release scripts/bench/bench_microgpt_gpu.w
./scripts/bench/bench_microgpt_gpu.wc

# GPU streams (S streams × N tokens per dispatch)
./bin/tungsten compile --release scripts/bench/bench_microgpt_gpu_streams.w
./scripts/bench/bench_microgpt_gpu_streams.wc

# GPU streams variants: fp16 storage / half4 / tgkv / simdgroup_matrix
for v in fp16 half4 tgkv sg; do
  ./bin/tungsten compile --release scripts/bench/bench_microgpt_gpu_streams_$v.w
  ./scripts/bench/bench_microgpt_gpu_streams_$v.wc
done

# Vendored C benches (CPU baselines)
( cd bits/tungsten-llama/lib/microgpt/c &&
  clang -O3 -march=native -ffast-math bench_c.c          -o bench_c &&
  clang -O3 -march=native -ffast-math bench_c_batch_mt.c -o bench_c_batch_mt -lpthread &&
  clang -O3 -march=native -ffast-math bench_c_sme.c      -o bench_c_sme      -framework Accelerate &&
  clang -O3 -march=native -ffast-math bench_c_sme_mt.c   -o bench_c_sme_mt   -framework Accelerate -lpthread )
export MICROGPT_WEIGHTS=$PWD/bits/tungsten-llama/lib/models/microgpt/weights_fp32.bin
./bits/tungsten-llama/lib/microgpt/c/bench_c_sme_mt 3072 12 1000 100

# Fused: GPU sg-streams + CPU SME-MT concurrently
./bin/tungsten compile -o /tmp/bench_streams_sg scripts/bench/bench_microgpt_gpu_streams_sg.w
./scripts/bench/bench_microgpt_fused.sh 5
```

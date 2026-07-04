# qwen3:30b-a3b-q8_0 tensor shapes

Pinned shapes that drive Phase 2 matvec tuning. Source: GGUF header of
`~/.ollama/models/blobs/sha256-ae354763fe478c790125fb993e59bb1266655b3fa721eebe4a931660c3ed2ce9`
(32.5 GB, 579 tensors).

## Architecture metadata

| key                                     | value     |
|-----------------------------------------|-----------|
| `general.architecture`                  | qwen3moe  |
| `qwen3moe.block_count`                  | 48        |
| `qwen3moe.embedding_length`             | 2048      |
| `qwen3moe.feed_forward_length`          | 6144      |
| `qwen3moe.expert_feed_forward_length`   | 768       |
| `qwen3moe.expert_count`                 | 128       |
| `qwen3moe.expert_used_count`            | 8         |
| `qwen3moe.attention.head_count`         | 32        |
| `qwen3moe.attention.head_count_kv`      | 4 (GQA)   |
| `qwen3moe.attention.key_length`         | 128       |
| `qwen3moe.attention.value_length`       | 128       |
| `qwen3moe.context_length`               | 40960     |
| `qwen3moe.rope.freq_base`               | 1000000.0 |
| vocab size                              | 151936    |

## Q8_0 matvec shapes (the hot path)

Reading `W` as `K × N` so `y[N] = W @ x[K]`. Per-token execution counts
in parens; `×8` is "active experts" (top-k=8 of 128).

| tensor             | K    | N      | per-token | per-layer |
|--------------------|------|--------|-----------|-----------|
| `attn_q`           | 2048 | 4096   | 1         | 48        |
| `attn_k`           | 2048 | 512    | 1         | 48        |
| `attn_output`      | 4096 | 2048   | 1         | 48        |
| `ffn_gate_exps`    | 2048 | 768    | 8         | 48        |
| `ffn_up_exps`      | 2048 | 768    | 8         | 48        |
| `ffn_down_exps`    | 768  | 2048   | 8         | 48        |
| `output` (lm_head) | 2048 | 151936 | 1         | (final)   |

**Bytes-touched per token (Q8_0 only):**

- attn_q+k+output: ~24 MB / layer × 48 = ~1.15 GB
- expert ffn (8 active): (2048×768 + 2048×768 + 768×2048) × 8 × 1.0625B = ~40 MB / layer × 48 = ~1.92 GB
- lm_head: 2048×151936 × 1.0625B = ~330 MB

Total per token: ~3.4 GB read. M3/M4 Max sustains roughly 300-400 GB/s
of usable memory bandwidth, so the bandwidth floor is ~10 ms/token →
~100 tok/s upper bound.

## Other tensor types

- `attn_v`: `F16` 2048×512 — kept in fp16, fp32 conversion at use
- `attn_*_norm`: `F32` 128 — RMSNorm scales
- `*_norm.weight`: `F32` 2048 — RMSNorm scales
- `ffn_gate_inp`: `F32` 2048×128 — router (selects 8 of 128 experts), tiny

Note `attn_v` is f16, not Q8_0 — qwen3 quantizes only the dense matmuls
above. The router matmul `ffn_gate_inp` is f32 (negligible cost).

## Phase 2 baseline shapes

The "canonical" Q8_0 matvec for the gate is the expert FFN
`(K=2048, N=768)` — most common in the hot path (8 per layer per token).
Bench harness should also cover:

- `(2048, 4096)` — attn_q (highest N for non-output)
- `(4096, 2048)` — attn_output (only K>2048 case)
- `(768, 2048)`  — expert down (smallest K, possibly memory-bound differently)
- `(2048, 151936)` — lm_head (extreme N)

The `K=768` row of expert down is interesting because 768 = 24 blocks of
32 quants — an awkward inner dim that may not vectorize cleanly.

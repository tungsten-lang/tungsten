# tungsten-llama

Pure-Tungsten transformer inference. No C, no BLAS, no Metal — just `.w` files.

## Status

Early. Currently builds a GGUF loader and inspection CLI. Inference kernels and
generation loop land in subsequent commits.

## Milestones

- [x] GGUF header + metadata + tensor-info parser
- [ ] Byte-level Q8_0 dequantization
- [ ] fp32 matmul (naive, correctness-first)
- [ ] RMSNorm, RoPE, softmax
- [ ] BPE tokenizer loaded from GGUF vocab
- [ ] Single-layer forward pass
- [ ] MoE routing (top-k expert selection)
- [ ] End-to-end generate() loop
- [ ] Sampling (argmax, temperature, top-k)

## Why

Pedagogical. Llama.cpp hides its hot loop behind Metal shaders and
hand-vectorized NEON. We want the whole stack in one language so it's
readable end to end.

Expect single-digit tok/s — without SIMD/GPU this is a reference
implementation, not a performance one. The Tungsten interpreter would
be too slow even for that; compile with `tungsten -o`.

## Quickstart

```
tungsten bin/tungsten-llama.w inspect /path/to/model.gguf
```

Pull a GGUF with ollama first; blobs live at `~/.ollama/models/blobs/`.

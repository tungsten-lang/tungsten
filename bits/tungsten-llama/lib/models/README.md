# bits/tungsten-llama/lib/models/

Per-model harness directories. Each one holds:

- `config.w` — architecture constants (hidden, layers, head_dim, vocab, etc.) extracted from the model's config.json
- `README.md` — model status, MLX baseline, perf history, port plan
- `forward.w` — extracted forward step (when extracted from the bench)
- `<other model-specific lib code>` — e.g. tokenizer adaptors, weight remappers

## What lives where

Entry-point scripts (bench, verify, autotune) **stay at `scripts/bench/`**
because Tungsten's `use core/X` module resolution is script-relative —
moving entry points into `bits/tungsten-llama/lib/models/<name>/`
breaks `use core/metal` and similar.

Per-model lib code (constants, forward step, tokenizer logic) lives
under `bits/tungsten-llama/lib/models/<name>/`. Entry-point scripts
at `scripts/bench/` `use tungsten-llama/models/<name>/forward` (etc.)
to bring in the per-model logic.

Kernels (.metal files):

- `bits/tungsten-llama/lib/kernels/nvfp4/` — quantization-specific (matvec variants, dequant, repack)
- `bits/tungsten-llama/lib/kernels/shared/` — @gpu-emitted kernels reusable across models (rms, argmax, attn_*, kv_*, sdpa_*, silu_*, etc.)
- `bits/tungsten-llama/lib/kernels/<model_name>/` — per-model kernels when needed (e.g. Mamba selective_scan for qwen3.6)

## Current models

| Dir | Status |
|-----|--------|
| [`lightning_1_7b/`](lightning_1_7b/) | working, 1.16× MLX decode |
| [`qwen3_30b_a3b_q8/`](qwen3_30b_a3b_q8/) | inference path exists, latest dispatch fixes unverified locally |
| [`qwen3_6_35b_a3b_nvfp4/`](qwen3_6_35b_a3b_nvfp4/) | kernel-tuned, no inference path (Mamba/SSM + dual MoE port pending) |

## Adding a new model

1. `mkdir bits/tungsten-llama/lib/models/<name>/`
2. Create `config.w` with constants from the model's config.json
3. Write `README.md` with: architecture summary, model path/blob location, MLX baseline, port plan
4. If existing kernels suffice: bench/verify scripts at `scripts/bench/` reuse them and apply autotune-discovered TG_SIZE values
5. If new kernels needed: add a `bits/tungsten-llama/lib/kernels/<name>/` dir for them, or contribute new shared @gpu fns to `bits/tungsten-llama/lib/`
6. Add a `scripts/bench/autotune_<name>.w` to validate kernel choices at this model's dimensions

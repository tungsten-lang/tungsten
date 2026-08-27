# Qwen3.8-27B decode work — handoff

**Box:** Apple M5 Max, 128 GB. **Model:** `qwen3.8:27b-mlx` (Ollama NVFP4 blobs, mmap).
**Bench:** `bin/tungsten run scripts/bench/qwen38_mlx.w <mode> <n_gen> <schedule> mmap <flag> <prompt_tokens> <variant> [diag]`

Everything below is measured on this box, alternating A/B, and every change is
**parity-clean**: byte-identical greedy token ids, with draft acceptance used as
the null check (a pure kernel change must not move it).

## Headline

| | before | after |
|---|---|---|
| literary fixture, 64-tok prompt | 37.96 tok/s | **49.7** |
| expository fixture (`prose-tech`) | — | **55.1** (`mtp2`), +4.6% with gated `mtp3` |
| serial (non-speculative) | 30.30 | unchanged |

Matched against Ollama's MLX runner (`"raw": true`, identical 64-token prefix,
byte-identical continuation): tungsten **wins literary 49.7 vs 45.0**, trails
**expository 55.1 vs 61.2**.

## Wins that came from the MLX challenge repo

1. **Cross-row wide QMV** — `lib/kernels/nvfp4/nvfp4_matvec_mlx_scaled_wide.metal`.
   MLX's `qmv_fast_crossrow_affine4_g64_wide` shape: ROWS output rows per SIMD
   group with the activations loaded ONCE and shared. Replaced a quad/quint
   kernel that gave each SIMD group one output row and therefore issued 256 bytes
   of activation load per 8 bytes of weight. **1.6–2.6x at widths 4/5**, err=0 on
   all ten production shapes. +2% end-to-end at width 3.
2. **Sweep the row ladder, never extrapolate it** (MLX's M=9-cheaper-than-M=8
   note). `r4` beats `r2` on mlp-down (K=17408) and loses at K=5120 — shipped
   split is `r4` when `kdim == FFN`, `r2` otherwise. +1%, 3/3.
3. **Streak-gated draft depth** (`segmentedStreakGate`). Go deeper only after 2
   consecutive fully-accepted rounds; any reject resets. See `mtp3` below.

## Wins found here, NOT in the upstream set

4. **Tiled draft selector** — `lib/kernels/qwen3_6/mtp_draft_select_fast.metal`.
   **Biggest single win.** `mtp_compact_draft_select` scanned 98,330 logits with
   ONE 32-thread simdgroup, *twice* (once for the max, once for the index). This
   repo had already fixed exactly that pattern for the full-vocabulary argmax
   (1,648 us -> 3.92 us with 1024-logit tiles) and never applied it to the draft
   path. Two tiled stages, tie-break preserved exactly (control ids >= 248,044
   all exceed prefix ids < 98,304, so lowest-id order == logical index order).
   **Head step 3.14 -> 1.95 ms (-38%)**, +3.2% end-to-end, 3/3.
5. **Half-footprint width-4 QMV** — `nvfp4_wideh_*` in the wide kernel file.
   8 K-values per lane instead of 16, splitting an NVFP4 group across two lanes
   (free — `simd_sum` already reduces across lanes, and both halves share the
   group scale). Cuts hoisted activations from 64 to 32 registers, back under the
   occupancy cliff. **Row-4 marginal +9 ms -> +5 ms.** This is a different
   mechanism from upstream's grid-split (IPG) answer to width scaling.
6. **MTP-2 was already faster than MTP-1 and wasn't the default** (+15%). The
   docs recorded depth-1 as fastest; that verdict was set on a saturated fixture.
7. **`mtp3`: depth-3 with a streak gate.** `lib/kernels/qwen3_6/decode_quad.metal`
   (nine kernels; conv and gated-delta carry a third interior recurrent-state
   snapshot so rollback can pick any accepted prefix), `rollback_quad_states`,
   four-way accept walk. Ungated it wins expository (+3.1%, 4/4) and *loses*
   literary (-13%) because that chain decays too fast. Gated: **+4.6% expository,
   parity on literary**, ids byte-identical.
8. **Folded the hidden-copy into the head's command buffer** — `hidden-copy` went
   from 0.17 ms x2-3 per round to `0 ms/0`. Neutral-to-slightly-positive; kept.

## Measurement corrections (these mattered more than any kernel)

- **The Ollama target was a chat-template artifact.** 61–68 tok/s in the old
  README was Ollama writing an assistant *reply* (`acceptance=0.79 max_draft=4`).
  Always send `"raw": true` and the exact token prefix; verify
  `prompt_eval_count` matches and both emit the same continuation. Read its stats
  from `~/.ollama/logs/server.log` (`source=speculate_stats.go`).
- **The 512-token fixture was tiling** the passage 5x (the model said so in its
  own output). Prose is now long enough and the runner **warns** instead of
  silently tiling. A fake 0.796 acceptance nearly justified a whole program.

## Negative results — do not repeat

| tried | result |
|---|---|
| Pre-norm hidden for the MTP head (reference says post-norm double-normalizes) | **zero change, byte-for-byte** — `RMSNorm(c*v)==RMSNorm(v)` cancels it |
| Draft step is GPU->CPU sync latency | no — removing the readback: 3.10 -> 2.72 ms |
| Resource-scoped barriers (`memoryBarrierWithResources`) | median round identical in 4/4 |
| Nibble decode is the ALU bottleneck | no-decode ablation within 0.3–4% |
| Longer context raises acceptance | it does not (64/256/512 = 0.484/0.370/0.550) |
| simdgroup-matrix GEMM, v1 and v2 | exact (err 1e-6) and **3–10x slower**; occupancy, not the MMA units — M<=8 has too little arithmetic intensity, and staging beats the register-resident GEMV |
| Half-footprint QMV at width 3 | exact but slower in two in-situ row-scan pairs: incumbent **43/44 ms**, half **44/46 ms**; keep it width-4-only |

## Cost model (use this before building anything)

```
row ladder (in-situ, ARGV[7]="row-scan"):  33 / 37 / 39 / 44 ms  at widths 1-4
head step (MTP forward):                   1.95 ms
round(d) = verify(d+1) + 1.95*d
E[tokens] caps at 1/(1-p);  measured p = 0.50 (literary) .. 0.64 (expository)
```
Rows 2–3 are nearly free (bandwidth-bound, weights streamed once); row 4 is where
it turns compute/occupancy-bound. At p=0.64, depth 2 gives 55 tok/s and that is
*exactly* what is measured — the shipped config sits on its own optimum.


## Landed 2026-08-25: `devchain` arm -- single-sync speculative rounds

Ported the MLX challenge's device-resident draft chain + one-sync-per-round
discipline (port-ledger row 8, +3.6% RETAINED at 16K). Three mechanisms, all
gated behind `ARGV[7]="devchain"` (default OFF), all PARITY-PROVEN:

1. **Depth-2 chained draft on device** -- the draft's argmax is copied into the
   verify's token slot (`lib/kernels/shared/copy_i32_at.metal`), committed async,
   read back only after the verify. One GPU sync/round instead of two.
2. **Depth-3 chained draft on device** -- draft1 -> token slot 2, draft2 reads
   slot 2 as its input (`bf16_embedding_lookup_buf.metal`) and writes slot 3;
   one sync (the verify) instead of three.
3. **Async decode-phase history appends** -- KV-only appends need no host value,
   so they commit async and are drained by the round's next sync.

Validation (loaded box -> perf is DIRECTIONAL; parity is exact):
- Every run: `generated ids` byte-identical to pristine and acceptance identical
  (mtp2 31/64, mtp3 31/67). `verify=` flat ~1177 ms (the null check) -- the delta
  is draft/history scheduling, not drift. Default path (devchain OFF) is
  byte-identical to baseline.
- mtp2: pristine ~1339 -> **1268 ms** (46.9 -> **50.4 tok/s**, ~+5.6%).
- mtp3: pristine 1334 -> **1291 ms** (47.98 -> **49.6 tok/s**, ~+3.4%).

```
# promotion gate -- run on a COOL, quiet box (ABBA, >=3/4):
scripts/bench/perf_lock.sh bin/tungsten run scripts/bench/qwen38_mlx.w mtp2 64 r2 mmap profile 64 auto            # baseline
scripts/bench/perf_lock.sh bin/tungsten run scripts/bench/qwen38_mlx.w mtp2 64 r2 mmap profile 64 auto devchain   # arm
# (repeat with mtp3)
```

4. **Batched prefill** (`forward_prefill_chunk`) -- the biggest lever the
   measurement surfaced. Stock prefill is token-by-token: it streams the 18 GB
   model ONCE PER PROMPT TOKEN (64 tokens = 64 streams, ~8-21 tok/s). Batched
   prefill runs 3 prompt tokens per stream through the triplet backbone (the
   cross-row kernels amortize the weight read, bit-exact by row independence),
   building KV and advancing gated-delta state exactly like 3 serial forwards.
   Head-history priming is preserved (staged from x_triplet), so decode
   acceptance is unchanged. Triplet, not quad, because triplet buffers are
   allocated in every MTP mode. Measured: prefill **3052 -> 1842 ms (1.66x**,
   21 -> 34.7 tok/s; the residual is the fixed cold-weight first-touch, ~2.5x
   on the warm portion). ids byte-identical to serial prefill.

Full arm result (mtp2, 64+64, one window): prefill 3052->1842 ms, decode
1308->1265 ms, **end-to-end 4360 -> 3107 ms (1.40x)**; devchain-OFF byte-
identical to baseline.

**Note:** the tungsten `.w` interpreter has an intermittent parse/JIT flake
("bitwise operation requires integer arguments" at load, no output) that hits
pristine too and clears on retry -- unrelated to these edits, but worth a look.

**Where the squeeze stops.** After devchain, `verify=` is ~92% of decode and is
bandwidth-bound (18 GB weight stream, already on the ported cross-row QMV). The
draft head step is now compute-bound (~1.8 ms), not sync-bound, so more
scheduling saves <1%. The remaining levers, in size order: (1) **GEMM prefill** -- all prompt tokens
in ONE weight stream via a simdgroup-matrix kernel (~another 2-5x on prefill
beyond the 1.66x triplet batching); a major new NVFP4 kernel (the reference
never built it; simdgroup GEMM was slower at small M, should win at M=64). (2)
coarse/exact draft readout (~0.8% of decode, within noise; prior q2 lost an
ABBA). (3) acceptance itself (head quality / trained DFlash2-style drafter) --
a model artifact, the only lever with real decode magnitude left.

## See also (2026-08-25)

The board moved 3.19 → 3.73 after this handoff; what did it is in
`mlx-challenge-lessons-2.md`, and the design consequences for us (acceptance
first, then verify-width kernels, then a cluster index for the draft
selector) are in `dflash2-speculation.md`.

## What is left

- **Head step is the binding constraint** (1.95 ms; ~1.2 ms is irreducible
  bandwidth over ~540 MB: draft projection 252 MB + MTP layer 227 MB). Halving
  the draft projection with a 2-bit coarse sweep + exact top-32 rerank (the MLX
  board's declared-head trick) is worth ~0.3 ms.
- **Acceptance** is the other lever and it needs a better/trained MTP head — a
  weights lever, not an inference-engine one. The ranked board makes the head
  substitutable precisely because that is where its remaining margin lives.

## Negative receipt: affine-2 draft sweep (DELETED)

`ARGV[6]="q2draft"` was correctness-clean (byte-identical greedy IDs, identical
acceptance) and isolated-positive (~6 us on the concurrent projection chain,
398.6 us at 2-row/32-value vs 525 us exact). It did **not** survive a four-pair
ABBA on the real runner:

```
scripts/bench/perf_lock.sh bin/tungsten run scripts/bench/qwen38_mlx.w mtp2 64 r2 mmap profile 64 auto|q2draft
scripts/bench/perf_lock.sh bin/tungsten run scripts/bench/qwen38_mlx.w mtp2 64 r2 mmap prose-tech 64 auto|q2draft
```

Order per fixture: A B B A A B B A. Generated IDs and acceptance matched on
every arm (literary 31/64, expository 35/55). Median-round wins for q2:

| fixture | pair wins | notes |
|---|---|---|
| literary (`profile`) | **1/4** | three median ties; only pair 1 won on `components: draft` 100 vs 143 ms |
| expository (`prose-tech`) | **0/4** | three ties at 43/43/44, one loss 44 vs 43 |

Promotion required ≥3/4 on **both** fixtures. Isolated microseconds do not
override that. The opt-in runner wiring and `mtp_draft_q2.metal` are **gone**.
`scripts/bench/qwen38_mlx.w` is back to the incumbent tiled selector.

Do not restore q2 without a new ABBA that actually clears 3/4 × 2. Do not retry
fused pre-FC embed/RMS/concat (already −23% same-binary). Remaining unused
leftover: re-decide tree drafting with `rank-probe` (the head step is now 1.95
ms; the old "tree does not pay" verdict used 3.05 ms).

Regression lock: `bin/tungsten run bits/tungsten-llama/mtp_draft_select_test.w`
and `python3 bits/tungsten-llama/tests/test_q2draft_removed.py` drive the
shipped tiled selector and fail if q2 is reintroduced.

## Discipline (learned the hard way here)

- Always `scripts/bench/perf_lock.sh`. It serializes tungsten runs but **cannot**
  serialize Docker VMs, browsers, or other agents' builds — check `uptime` and
  `macmon`. Dispatch encoding is host-bound, so CPU load halves tok/s with
  acceptance unchanged. GPU >65 C also degrades; alternate A/B **order** (ABBA),
  because whichever arm runs second gets the hotter slot.
- Trust the **median round** and paired win counts, not absolute tok/s.
- Acceptance is deterministic and reproduces byte-for-byte — if it moved, your
  "pure kernel change" wasn't.

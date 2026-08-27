# DFlash2 vs native MTP — what to steal, grounded in real receipts

**Date:** 2026-08-25 (rewritten; the first draft guessed the name — this one is
sourced). **Status:** design notes, nothing built in tungsten yet.

**What DFlash2 actually is.** Not "DFlash design, take two" of mine — it is a
real, pinned backend in **MTPLX** (David Tai's MLX inference project, the
upstream the Qwen challenge session was ported from). DFlash2 = the **z-lab
DFlash speculative-decode algorithm at v2** driving Qwen3.8: a **separate,
trained 4-bit (W4/group-64) draft model** (`z-lab/Qwen3.8-27B-DFlash2`) plus the
`davidtai/dflash-mlx` runtime (v0.1.10), verifying against an **unquantized**
target. It *replaces the native MTP head entirely* — separate `dflash2/`
directory, not an `mtp.safetensors` sidecar; `--no-mtp` routes to target AR and
never loads the draft. This is the DFlash (separate trained drafter) philosophy,
i.e. the Laguna track's mechanism, beating the Qwen-MTP-head philosophy on real
long-context workloads.

**Sources (all pinned):**
- MTPLX PR `youssofal/MTPLX#335` (David Tai), branch `perf/qwen38-challenge-port`
  @ `9a6f48e6`. `docs/dflash2.md` (backend spec + manifest), and
  `docs/perf/qwen38-challenge-port-ledger.md` — the 54 Yukon proposals *re-run*
  on a real MLX runtime, which is the authoritative transfer oracle below.
- Draft `z-lab/Qwen3.8-27B-DFlash2` @ `50307d4c`; algo `davidtai/dflash-mlx`
  @ `c5b76ddb`; verify-mode `dflash`, `--verify-len-cap 8`, `--copyspec-mode off`,
  block 8, `w4:gs64`. Upstream parity risks: `z-lab/dflash#159`, `#160`.
- Our numbers: `qwen38-handoff-2026-08-18.md`. Challenge kernel/schedule detail:
  `mlx-challenge-lessons.md`, `mlx-challenge-lessons-2.md`.

---

## 1. The measured verdict: DFlash2 > native MTP for Qwen3.8

David Tai's ABBA receipts (temp 1.0, top-p 0.95, top-k 20 — **stochastic**,
not greedy; isolated GPU lock; two/four timed arms), MTP → DFlash2 decode TPS:

| workload | MTP decode | DFlash2 decode | Δ | draft hit MTP / DF2 |
|---|--:|--:|--:|--:|
| 100-tok headline | 107.6 | **113.3** | +5.3% | 78.8% / 93.6% |
| 1K real-usage (natural EOS) | 62.2 | **66.9** | +7.6% | 87.8% / 67.9% |
| 1K/1K ABBA #1 | 58.9 | **72.0** | +22.2% | 79.9% / 69.0% |
| 1K/1K ABBA #2 | 59.7 | **74.7** | +25.1% | 79.9% / 69.0% |

Plus the port ledger's own step: DFlash2 fixed-M8, before any survivor-specific
kernel ports, was already **+7.09%** over the *fully ported* native-MTP stack.
The X-post summary ("~20% avg, 60% best case, 10% floor") is consistent with
this spread.

Two facts worth internalizing:

- **DFlash2 wins even where its draft hit-rate is *lower*** (1K: 67.9% vs MTP's
  87.8%, still +7.6% faster). A separate trained drafter proposes a **longer
  block per target forward** and its verify is cheaper, so tokens-per-target-
  forward beats per-token acceptance. Acceptance rate is not the objective;
  emitted-tokens-per-target-forward is.
- **It has a real failure mode.** Adaptive drafting helps at 1K and *hurts* at
  16K (bypassed for fixed M=8 ≥16K); the streak-3/optimism-cap adaptive
  revision measured **−14.3%** and the position-EMA adaptive policy **−5.6%**.
  This is the X-post's "imploded on long thinking traces at xhigh." **Adaptive
  block-length policy is fragile under stochastic verify at long context** —
  see §4.

Final DFlash2 policy that shipped: adaptive block 1–8 below 16K input;
**fixed M=8 at ≥16K**; row-53 command buffers process-latched at 512 MiB/50 ops;
target-shape exact-BM8 kernels for GQA widths 6/7/8, M7→M8 padding, exact M5,
barrier-free selected M6; the exact-M8 `o_proj` route explicitly *disabled*
(removing it was +0.70%).

---

## 2. The authoritative transfer table (real 16K stochastic ABBA)

This is the reason the PR matters more than the ranked notes. The challenge
scored **512-token greedy median**; MTPLX re-ran the same 54 submissions at
**16K stochastic, ABBA, GPU-locked**, and the rankings disagree. Use *this*
column, not the ranked score, to decide what to port.

**Robustly transfers (RETAINED, native-MTP fixed-D3 stack, real Δwall):**

| challenge mechanism | MTPLX Δ | our doc ref |
|---|--:|---|
| device-resident fixed-D3 draft chain (draft ids on device) | **+3.60%** | new — L4 |
| compact Q4/G64 proposal vocabulary | **+3.04%** | we have it (`mtp_draft_select`) |
| packed K/V-only committed-history append | **+2.07%** | we have it (2.58% our own) |
| three-layer prefill evaluation cadence | **+1.68%** | new |
| exact declared Q4/G64 MTP block (later: +BF16 Q/K/V islands) | +1.43% (+0.15%) | head-weights |
| fused Q/K RMSNorm + partial RoPE (one kernel) | **+1.29%** | we have `per_head_norm_rope` |
| memoized GDN `-exp(A_log)` decay | +0.98% | handoff item 3 class |
| fused residual/RMSNorm boundary chain | +0.92% | lessons-2 §2 |
| Q/K L≤16 fence + target evaluation ladder | +0.84% | new |
| post-warm wired residency; 512 MiB/50-op cmd buffers | +0.83%; +0.47% | lessons-2 §6 |
| fused dual RMSNorm + concat (proposal pre-fc) | +1.00% | lessons-2 §2 |

**Ranked wins that REGRESSED on a real workload — do not port blind:**

| mechanism | MTPLX Δ | note |
|---|--:|---|
| packed target Q/K/V projection | **−4.06%** | |
| paired shared-row G32/M4 target QMV | **−3.84%** | |
| four-way GDN input projection through S≤9 | **−0.99%** | *was an accepted challenge submission* (`3e157ad9`) |
| S≤9 packed MLP gate/up | −0.31% / −0.54% | |
| alternate Q4 block artifact / fused Q8 embed-norm-concat | −0.09% / −0.19% | |

**Non-transferable to stochastic sampling (temp 1.0 / top-p / top-k):**

- reuse-second-target-argmax, argmax-only compact selector — a stochastic route
  has no second argmax and no argmax-only accept. Anything that exploited
  *greedy* target selection is dead under sampling.
- **the entire cost-model / streak-gate draft schedule** (challenge L5): the
  position-EMA policy −5.6%, streak-gate constant −5.5%, first-margin clamp
  −4.3%, streak-3 revision −14.3%. Under stochastic block verify the greedy
  marginal-depth rule *loses to a fixed block*. This directly contradicts what
  I wrote as L5; see §4.

**DFlash-drafter-specific (kernel ports onto the DFlash draft path):**

- **DIRECT_NIBBLES M6/M7/M8 on the DFlash drafter: −4.3% / −3.9% / −7.1%,
  all rejected.** The challenge's single biggest kernel family (lessons-2 §1.5)
  *does not transfer to the separate drafter's path*. Where it pays is
  **target-shape** exact kernels (next item), not the drafter.
- **Target-shape exact-BM8 NAX kernels DO pay, small and additive**: exact M5
  K-split +1.40%, selected-M6 one-way K split +0.32%, M7-padded-to-M8 +1.26%,
  M8 K/V +0.37%, M8 MLP +0.69%; final phase-corrected stack +0.73% (→70 TPS).
  Removing the M8 `o_proj` route was itself +0.70%. The lesson matches
  lessons-2 §1.4 (sweep every width; the fast shape is not the natural one)
  but the *sign and magnitude only show up on the real workload*.

---

## 3. What this means for tungsten, revised

The old framing ("acceptance first, then verify kernels") was built on the
ranked median and is half wrong. The corrected reading:

1. **The biggest single lever is the drafter architecture, not the MTP head.**
   A separate trained W4 draft model (DFlash-style) beat the model's own MTP
   head by 7–25% decode on a real runtime. For tungsten that is a **model
   artifact + a verify-algorithm port**, not an engine tweak — the largest and
   the most expensive item. It needs: (a) a trained Qwen3.8 draft checkpoint (or
   reuse `z-lab/Qwen3.8-27B-DFlash2`), (b) a block-verify loop with
   `verify-len-cap 8` and KV rollback, (c) our existing wide/decode kernels on
   the *target* path. Our `decode_quad` block-verify machinery is the right
   skeleton; the drafter is what we lack.

2. **Emitted-tokens-per-target-forward is the objective, not acceptance rate.**
   Our handoff optimizes p (0.50–0.62) and stops at depth 2 because
   `round(d)=verify(d+1)+1.95d` says so. DFlash2 wins at *lower* hit rate by
   drafting a longer block cheaply. The question to re-ask: can a trained
   drafter give us longer usable blocks at our verify cost, the way it does for
   MTPLX? If yes, our verify-row slope (3.7 ms, already ahead of theirs) makes
   deep blocks *cheaper for us than for them*.

3. **Do not port the adaptive schedule.** Under sampling it loses to a fixed
   block. Ship **fixed block** (M=8-class), and if adaptive at all, only at
   short context and conservatively. This retires the `segmentedStreakGate`
   direction (`mtp3`) that the handoff and lessons-2 §5 recommended — that
   recommendation was greedy-median-specific.

4. **Port the RETAINED list, skip the REGRESSED list.** Highest-value engine
   items we don't already have: device-resident draft-id chain (+3.6%), Q/K L≤16
   fence + eval ladder (+0.8%), three-layer prefill cadence (+1.7%). We already
   have compact vocab, K/V-only history, fused Q/K norm+RoPE, GDN memo, boundary
   fusion — confirm each still pays *on our tree* with an ABBA, since three
   ranked wins flipped sign on theirs.

5. **DIRECT_NIBBLES stays a target-path idea only.** It regressed on the
   drafter. Our `nvfp4` cross-row kernels are target-path, so the reuse-ratio
   rule (lessons-2 §1.5) still applies there — but do not put it on a future
   drafter's matvec.

---

## 4. Why adaptive block length is fragile (the one real trap)

The challenge's greedy median made adaptive depth look free: a rejected draft is
deterministic and cheap, so a marginal-depth rule that over-drafts pays a small,
predictable tax. Under **stochastic** verify at long context two things change:

- The accept boundary is noisy per position, so a per-position EMA chases noise
  and the closed loop (price → proposals → observed accept → EMA → price)
  oscillates. MTPLX measured this directly: the adaptive revisions shifted cycle
  counts 201→334 and regressed 5–14%.
- At 16K the target forward dominates and the marginal draft's *variance* costs
  more than its mean saves. Fixed M=8 wins because it removes the control loop
  from the hot path entirely.

So the schedule is not a lever to tune; it is a liability to remove. The lever is
the drafter (better proposals) and the target-path kernels (cheaper verify).

---

## 5. The exactness contract (unchanged, and it now has a stochastic clause)

- **Proposal side free, verify side bit-exact** — as before. A drafter may be
  any bit width, any vocabulary; cost of a mistake is a shorter accepted block.
- **Under sampling there is no argmax to reuse.** Any mechanism that read the
  target's *greedy* choice (second-argmax reuse, argmax-only selectors) is not
  merely lossy under temperature — it is undefined. Verify parity is now
  "committed tokens match target-only AR *under the same seed/sampler*," and the
  ledger records deterministic tie drift at temp 1.0 as allowed, not a failure.
- Row-independence, expression-tree/dtype preservation, tie order, and the
  acceptance fingerprint as the null check — all still hold on the target path.

---

## 6. Build order for tungsten, corrected

| step | what | gate | expected |
|---|---|---|---|
| 0 | Decide drafter strategy: adopt/borrow a trained W4 DFlash-style drafter vs. keep the MTP head | offline: block-length × accept curve of each on our prose | the 7–25% lever, but a model-artifact cost |
| 1 | If keeping MTP: confirm head cache priming is engaged (it *is* — prefill calls `mtp_step(...,false)` per token); the acceptance gap is head *quality*, a weights lever | `rank-probe` primed vs unprimed | closes a wrong suspect |
| 2 | Port the RETAINED engine items we lack: device-resident draft-id chain, Q/K L≤16 fence + eval ladder, three-layer prefill cadence | ABBA on our tree, 1K+16K prose | +3.6% / +0.8% / +1.7% shape |
| 3 | Re-ABBA the items we *think* we have (compact vocab, K/V history, fused norm, GDN memo, boundary fusion) at 16K stochastic | three ranked wins flipped sign — verify ours didn't | protects against a mis-port |
| 4 | Fixed-block verify (drop the streak gate). Adaptive only <2K if at all | ABBA vs fixed | removes a −5 to −14% trap |
| 5 | Target-path width kernels: exact M5 K-split, M7→M8 pad, selected-M6, remove dead output routes | per-width cost table from the real loop; hexfloat row gate ≥ width 5 | +0.3–1.4% each, additive |

**Audit already done (no GPU needed):**
- **Head cache priming is present.** `scripts/bench/qwen38_mlx.w` prefill loop
  calls `mtp_step([prompt[i+1], backbone_hidden, i, false])` for every prompt
  token → `enqueue_mtp_history` with the MTPLX `(token_{i+1}, hidden_i)` layout.
  So "seed priming" is *not* our acceptance suspect (my first draft was wrong);
  the gap is head weights, matching the handoff's own "needs a better/trained
  head."
- **Our multi-row kernels are NOT over-launched.** MLX's tight-grid bug (§1.2 of
  lessons-2) was launching `M` input-row groups where only `ceil(M/IPG)` work.
  In tungsten the input batch (2/3/4 tokens) is a **compile-time template
  constant** in `nvfp4_matvec_mlx_scaled_wide/pair/triplet` and `decode_*`; the
  grid is only over *output rows* (`ceil(rows / (2·ROWS))` groups), already
  tight. The tail-row guard trims a partial group, not whole no-op groups. So
  that finding is satisfied by construction — nothing to fix there. (This
  corrects the lessons-2 §1.2 "audit every multi-row kernel" TODO: done, clean.)

---

## 7. Do not build (priced, on the real workload this time)

- The adaptive/streak/EMA draft schedule under sampling (−5 to −14%).
- DIRECT_NIBBLES on a drafter matvec (−4 to −7%); keep it target-path only.
- Packed target QKV (−4%), paired G32/M4 target QMV (−3.8%), GDN in-proj S≤9
  (−1%) — ranked wins that lose on 16K stochastic.
- Any greedy-argmax-reuse mechanism under temperature.
- Vocabulary shrink below the compact set, probe fraction below 0.15, shortlists
  wider than 32 — unchanged from lessons-2.

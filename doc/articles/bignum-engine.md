# The Tungsten bignum engine: beating GMP, cell by cell

Tungsten's arbitrary-precision integers live in the C runtime
(`runtime/runtime.c`) behind the nanboxed `WValue`. Over a series of campaigns
(July–August 2026) the engine went from "loses to GMP on most of the board" to
**winning 470+ of 485 benchmark cells against GMP 6.3's public `mpz_*` API on
Apple M5 Max, at a time-ratio geomean near 0.60** — with the few remaining
ties carried by hardware-counter proofs that both implementations sit on the
same machine floor.

This article is the complete engineering record: the representation, the
allocator, the kernels, the algorithm ladders, the compiler integration, the
measurement discipline that made any of it believable — and, deliberately, the
graveyard: everything we tried that did not work, with the numbers that killed
it. The failures are recorded because they are load-bearing: nearly every
shipped win started as the survivor of two or three measured rejections.

A sibling article, `bignum-multiply.md`, tells the story of the standalone
Goldilocks-NTT multiply built for the twin-prime engine. This one is about the
runtime engine that every Tungsten program uses.

The benchmark referenced throughout is `bin/tungsten bench bignum`
(`benchmarks/big_math/`): 25 operations × sizes from 1 to 8192 limbs (opt-in
to 1M), each cell racing the boxed Tungsten operation against the equivalent
public-API GMP call on identical deterministic operands, with per-cell
GMP cross-checks before any timing. Ratios below 1.0 mean Tungsten is faster.

---

## 1. Value representation

### Nanboxing and the inline i48

A `WValue` is a 64-bit nanbox. Small integers live inline as 48-bit payloads
(`i48`, tag 0xFFFA): no allocation, no indirection. Everything in the bignum
engine is shaped by the moment a value crosses 2^47 and must become a heap
object.

### The v4 heap encoding: sign in the box, magnitude on the heap

Heap bigints originally kept sign in the heap header. The **v4 redesign**
(2026-08-02) moved it into the box: BigInt owns the top-level tag **0xFFF8**
(freed by tightening the biased-double ceiling to the exact −inf+bias — NaNs
canonicalize before biasing, so 0xFFF2–0xFFF8 were recoverable tag slack), and
**bit 47 of the payload is a sign overlay**. The effective sign of a value is
the heap header's sign XOR the overlay bit.

Consequences, all load-bearing:

- **Negation and absolute value are O(1) bit operations on the box** —
  `v ^ (1<<47)` and `v & ~(1<<47)` — with *no allocation and no copy*. The
  copying forms had been stuck at parity with GMP forever (an immutable
  result must allocate; `mpz_neg` writes into a retained destination); the
  overlay closed that structural wall outright: abs runs 1.2 ns flat at every
  width — 0.49× GMP at 1 limb, 0.02× at 1024.
- One-compare type tests: `(v >> 47) == (0xFFF8... >> 47)` answers "heap
  bigint AND positive" in a single comparison (the tag-and-sign gate the word
  entries use).
- Dispatch stayed cheap: the IC dispatch key remained 0x02 via `w_dispatch_key`,
  so no dispatch table changed when the tag moved.

Since two boxes can now share one buffer (`y = -x` is a *view*), the header
byte at offset 1 became a **saturating alias count** (`shared`): each tag-flip
alias increments it; `bigint_release_if_live` decrements-and-swallows while
nonzero and recycles only at zero. N aliases tolerate at most N+1 releases —
leak-proof and use-after-free-proof churn, with 255 as an "immortal" pin used
by module-literal templates. The semantics of the whole engine are
**mutate-unless-shared**: `shared == 0` plus a clear overlay is the license to
write in place.

The header layout is `type(u8)@0, shared(u8)@1, pad, size(i32)@4, cap(u32)@8,
limbs[]@16` — deliberately packed so that:

- `type`+`size` publish in one 64-bit store (`bigint_publish_header`);
- `type`+`shared` read as one halfword ("live and unaliased?" in one load);
- the whole header reads as one 16-byte `ldp` on release (type check, alias
  check, and capacity in a single load pair).

Zero always demotes to inline i48, so a heap bigint's magnitude is never
zero — which is what lets the slot and arena protocols use `size`-free
occupancy encodings.

### Aliasing is a real semantic, pinned by specs

`y = -x` is a standing relationship: `x.neg!` moves both. `x + 0` returns the
operand itself (marked shared). An adversarial spec battery
(`bigint_tag_sign_spec`, `bigint_identity_spec`, `bigint_mutate_unique_spec`,
the word-dest and TZ fuzz arms) pins these forever, because the failure mode
of getting aliasing wrong is *silently wrong numbers*, not crashes.

---

## 2. Memory: recycler, hot slot, arena

The allocation story is where most of the "GMP is faster at small sizes"
deficit actually lived. GMP mutates retained `mpz_t` destinations; a boxed
immutable API allocates per result. Closing that gap took four layers.

### The bucket recycler and the hot slot

Released limb buffers park in a per-thread pool: power-of-two size-class
buckets plus a single **hot slot** — the last released buffer, kept ready for
the overwhelmingly common churn pattern (release previous result, immediately
allocate the next, same size class). Steady-state benchmark churn hits the
recycler ~100%: single-digit *mallocs per million operations*.

The hot slot's protocol was then shaved to the machine floor in stages:

- `hot_cap` mirror field: kills the dependent `hot->cap` load on the
  release→take store-forward recurrence (a measured pointer-chase).
- **Single-word slot** (2026-08-11): the slot became one u64 —
  `pointer | capacity << 48` (pointers stay under 2^47, the invariant
  `bigint_box` asserts; capacities fit 16 bits under *every* policy including
  non-power-of-two hybrid quanta, which is why the low-4-alignment-bits log2
  encoding was rejected at design time). Occupancy is `word != 0`; the
  smallest-fit test is one unsigned wrap-compare (`cap - req < req`); take
  clears one scalar. Shipped **fused with** a 16-byte header read on release —
  and only as a unit: each half alone measured as a regression (A alone:
  neg@4 +17.5%, the encode stalls on the late capacity load; B alone: +4–6%,
  a wide load spanning a just-stored word with nothing consuming the early
  cap). The fusion works because the fused header read *feeds* the slot
  encode. mul1@2 went to 0.875 vs GMP on that change alone.
- One value-conditioned hazard surfaced later: the fused 16-byte release load
  spans the `shared` byte that abs/neg churn had *just* stored, and on M5 the
  failed store-forward is **value-conditioned** — a header-negative size puts
  0xFFFFFFFF in the loaded word and serializes the chain (+4 cycles/iter);
  positive headers forward fine. That is why neg escaped the acceptance
  battery and abs regressed 1.1→2.1 ns. Fix: the alias-swallow decrement
  re-reads the byte through a same-size volatile load (clean same-width
  forwarding); the wide load feeds only predicted branches.

### The arena: killing the 4K page-offset lottery

A season of mysterious regressions — lcm@1 flipping 0.97→1.27 between
process launches; mul@48 swinging 0.87→**1.73** purely on the *size of the
environment block*; benchmark cells moving ±30% when two heaps were resident —
all traced to one uarch behavior: Apple Silicon's memory-dependence predictor
false-aliases a store stream against loads whose addresses land within ~512
bytes of the same 4 KiB page offset. malloc hands out page offsets by lottery;
stack scratch slides with `environ` (the environment block sits at the stack
top, so `export FOO=…` moves every frame — that one took a padding sweep to
believe).

The runtime accumulated compensations — page-hazard guards, rehome searches,
settled-placement memory, TLS scratch arenas for the fixed Toom kernels — and
then replaced the whole class **by construction** (2026-08-11): a per-thread
**limb arena** beneath the recycler. 2 MiB aligned-mmap chunks; per-class
freelists threaded through `limbs[0]`; bump allocation on miss (virgin pages
skip the zero-fill memset, like calloc); slots on a **512-byte grid** with the
placer refusing to repeat any of the last seven handout phases — so any two
of the last eight buffers a thread receives are pairwise ≥512 B apart mod
4096. The operands and result of a kernel call cannot alias-collide, ever.
Cross-thread releases CAS-push onto the owning chunk's remote stack; teardown
orphans live chunks, unmapped by the final release.

Verdict gates it had to pass, and did: environ-padding sweep flat; the
historical hazard cells flat; full matrix at parity-to-better with **fewer
verdict flips (2 vs 6)**; live-set RSS **5.5% below malloc**; churn RSS flat.
The hazard machinery now compiles out when the arena is on. The closing joke:
with our placement fixed, the residual benchmark jitter turned out to be
*GMP's* malloc lottery (their lane's ns swing 3× run-to-run on the same box).

Contract change worth knowing: raw `free()` of a `WBigint` is illegal —
everything routes through `bigint_backing_free`. The ASAN differential sweep
is the enforcement net (it caught the one straggler, a rotating modctx slot).
Under ASan the arena compiles to malloc passthrough by default (freelist
reuse hides UAF); `BN_BIGINT_ARENA_ASAN=1` forces it on for arena-path
coverage.

### Capacity policy: rejected, then flipped, by the same evidence standard

Buffer capacities were pure powers of two — ~33% average slack on a live set,
inherent to rounding a uniform-ish size distribution up a binade. The hybrid
policy (powers of two to 32 limbs, then 32-limb quanta) won every *memory*
axis in July (−32% real RSS at 1024-limb mixes) but was **rejected as default
on 2026-08-02**: 27 op-matrix cells regressed >5%, because the pool's
smallest-fit take needed a capacity scan the pure-p2 fast path didn't.

Re-measured **post-arena** (2026-08-11), the rejection reversed: the arena's
class freelists and phase grid absorbed exactly the cost that had killed it —
the 27-cell tail is gone (several became wins), and the RSS win held (−5.3%
at 1024, −17.2% at 4096). Hybrid is now the default. The proposed multi-rung
*ladder* generalization (q32 to 512 limbs, then q128) was tested at the same
time and rejected with numbers: 2.3× the waste of flat q32, no recycler
advantage, +30% on division at the rung boundary.

Two lessons encoded there: measured verdicts have a *base* — re-litigate them
when the foundation changes; and the slot encoding (raw 16-bit capacity, not
log2) was chosen precisely so a future policy flip wouldn't be blocked by the
representation.

---

## 3. Kernels: the flag-chain layer

Everything above ~1 limb eventually funnels into a small set of hand-tuned
AArch64 kernels. The governing discovery (July): Apple Silicon renames NZCV,
so two *independent* carry chains overlap in flight — but C-compiled
carry propagation serializes at ~3 c/l because the compiler round-trips
carries through GPRs. Hand `adcs`/`sbcs` chains hit the machine floor:

- `bn_addmul_1` (4× unrolled asm): 1.62 c/l — the row engine every schoolbook
  and Toom leaf rides. The 8-way unroll variant measured **faster in
  isolation (1.57) and slower in situ** — it spills once inlined into real
  callers (25 live registers). Validate kernels in context, not microbenches.
- `bn_add_n` / `bn_sub_n` (`adcs`/`sbcs`): 1.43 c/l. Fixed straight-line
  versions exist for 3–64 limbs (`bn_add*_fixed`), reached via
  `bn_add_equal_fast`/`bn_sub_equal_fast`.
- `bn_mul_1` rolling-carry rewrite (2026-08-03): GMP's `mpn_mul_1` keeps the
  carry flag alive **across the loop back-edge** (1 adcs/limb, `sub/cbnz`
  control, one closing `adc`); ours had closed the chain per 4-limb block
  (1.25 flag ops/limb). Read via `otool` on `libgmp.dylib`, reproduced, plus
  interleaved next-block loads — kernel parity at every width.
- `bn_submul_1`: the same treatment for division's update rows (~2.5× on
  Knuth at 1024 limbs).
- **NEON hybrid add/sub** (`bn_add_n_hybrid`, ≥288 limbs): per-limb
  generate/propagate masks computed in NEON, carries resolved as a bitmask
  prefix (`C = ((G<<1|cin)+P)^P`) — data-independent, fully pipelined,
  1.15×@512 → 1.39×@2048 over the scalar chain. Below 288 the plain chain
  wins; the crossover is measured, not derived.
- **Word-multiply rows**: fixed `bn_mul_1_fN` asm for 8–64 limbs, and for the
  2–8 limb band *inline* straight-line `__builtin_addcll` chains in the boxed
  caller (`bigint_mul_n1_tiny*`) — at those widths an out-of-line call costs
  more than the arithmetic. The 32-limb block had one more lesson in it:
  clang recycled one temporary per limb, making load/store *pairing*
  structurally illegal — 31 `ldr` + 34 `str`, zero pairs, ~7% more retired
  instructions than GMP at identical time. Restructuring to two-limb steps
  with distinct temporaries got 16 `ldp` + 15 `stp` (180→147 instructions)
  and flipped the cell. The compiler pairs loads only when you let it.
- **Write-only tail copies** (2026-08-12): the limbs streamed out after a
  carry dies are never promptly re-read — the opposite regime from the
  copy-class ops (neg/abs), where NEON and memcpy had *lost* to `ldp/stp`
  pairs on store→GPR-load forwarding. A per-width sweep (scalar, pairs, NEON,
  libc memcpy, `ld1x4`, streaming-SVE, and Apple-memcpy's overlap trick
  inlined) picked **overlap-qpair**: 64-byte q-register chunks plus one
  possibly-overlapping 32-byte end pair, no remainder loop — written as
  constant-size `memcpy(…,64)/(…,32)` chunks that clang inlines to q-pairs
  (portable C, no intrinsics, no call). Beats libc memcpy ~9% even at
  126-limb tails (the dispatch prologue never amortizes); below 4 limbs the
  pair loop keeps its seat. add1/sub1@16–64 moved 15–30% on this alone.
  Streaming SVE was disqualified structurally: `smstart/smstop` costs ~85 ns
  per entry on M5 — it is for resident kernels, not tails.

Hot kernels live in a dedicated text section (`__TEXT,__bnhot`, 64-aligned)
because small-multiply timings swing 10–20% on loop-head alignment between
otherwise identical builds.

---

## 4. The multiply ladder

```
lo ≤ 24            schoolbook (fixed leaves at 12/15/16/17/21/24; addmul_1 rows)
25 – ~340          Toom-2 / Karatsuba  (difference form; fixed-shape kernels
                   at 24/30/32/34/40/42/48/60/64/68/84/120/128/168/240/256/336;
                   TLS scratch arena — never stack)
~341 – ~451        Toom-3    (parallel point products ≥344)
~452 – 2047        Toom-4    (parallel ≥288 via the pool)
2048+              cost-model arbitration between Goldilocks NTT and SSA
                   (never a single threshold — both are step functions of
                   transform length; a fixed cutoff mis-dispatches)
```

Squaring has its own ladder (diagonal schoolbook to 47, Karatsuba-square to
~2559, Toom-4-square beyond; Toom-3-square is dead code — its window closed
when diff-form Karatsuba improved). Unbalanced operands chunk the long side
through the balanced ladder (2.1–2.3× at 4096×256-class shapes) or ride
rectangular parallel kernels.

Points of interest:

- **Sum vs difference Toom-2**: the difference form (`|a1−a0|·|b1−b0|` with
  sign tracking) wins nearly everywhere; the sum form survives at exactly
  n=28 (a measured hole, `BN_TOOM2_DIFF_SKIP`).
- **The fixed-shape kernels matter more than the ladder**: `bn_toom2_diff48`
  etc. are straight-line, arena-scratch, `noinline+aligned(64)` — and their
  scratch moved from stack to TLS specifically for page-offset stability
  (the environ discovery, §7).
- **SSA (Schönhage–Strassen)** in Z/(2^K+1): butterfly twiddles are pure bit
  shifts; the √2 trick (2^(3K/4)−2^(K/4)) gains a 4K-th root; pointwise
  products recurse into the Toom ladder. Its dispatcher is a *cost-model
  compare* against the NTT's model. Two calibration bugs here produced the
  worst historical red cells: the NTT model was calibrated at an unreachable
  size (its constant 3–5× off in the reachable band), and the reciprocal
  division path was gated by the *recycler's pool cap* — a borrowed constant
  that never guarded anything. Fixing dispatch — not kernels — took mul@1M
  from 2.73× to 0.30× vs GMP. Cost-model calibration points must lie in the
  reachable band, and thresholds must never borrow unrelated constants.
- **The worker pool** (`WToomPointSet`): persistent threads with spin-then-
  park handoff run Toom point products and SSA pointwise batches. The 2026-08
  campaign rebuilt its mechanics — `os_sync_wait_on_address` park/wake with
  per-worker parked flags (a sustained mul@512 went from ~9,400 sampled
  kernel-wait events to ~12), last-finisher-wakes-joiner on a padded
  countdown, QoS-pinned workers, adaptive **burst linger** (workers spin
  briefly between adjacent parallel regions; the inter-region park/wake was
  ~10 µs of the old cost), and SSA phase fusion (forward→pointwise→inverse
  as consecutive pool dispatches instead of ~10 thread create/join per
  multiply). That collapsed the profitable-parallelism threshold: multiply
  parallel from 288 limbs (was 448), squaring from **128** (was 384),
  reciprocal division from 344 (was 768), and the parallel band improved
  17–66% end to end. Two ideas measured *backwards* and shipped as opt-in
  only: greedy tail-stealing (the static split deliberately hands the +1
  point to the caller, which sits on the fastest core tier) and broadcast
  wake-all (slower than targeted wakes at gap 0).

---

## 5. Division, reciprocals, and the mulhigh lasso

Division is the deepest specialization tree in the engine:

- **3-by-2 division** via Möller–Granlund `bn_invert_pi1` (replacing a
  `__udivti3` libcall), with an `asm("")` to stop clang if-converting the
  rare fixup onto the critical path — csel conversion of a 0.4%-taken branch
  was a measured loss.
- **Knuth** with preinverse and a two-entry per-divisor inverse cache
  (repeated-divisor traffic is the real pattern; per-call inversion had lost
  cells).
- **Burnikel–Ziegler** recursion ≥128/64 limbs (2n/1n → two 3n/2n; clamp at
  β^k−1; one k×k correction multiply; add-backs as wide subtracts with
  borrow-out-as-sign). A macOS trap for posterity: never name a variable `B0`
  in runtime.c — it is a termios baud-rate macro.
- **Certified reciprocal (Barrett) caching**: after three sightings of the
  same divisor, cache R = ⌊B^(2n+g)/D⌋; then each division is one product
  plus a *certificate* — if the guard limbs of U·R aren't saturated, the
  quotient is exactly right, no verification multiply (failure probability
  ~n/B, fallback to the ordinary path). The cache is two-entry with MRU-first
  probing because the big-sqrt recursion alternates two divisor widths and
  thrashed a single entry — and the probe is deliberately structured so the
  steady state compiles to the original single-entry shape (an entry-scan
  loop measurably slowed the whole certified divide).
- **Jebelean exact division** (2-adic) for the divides-exactly cases (lcm,
  Toom interpolation).
- **The mulhigh lasso** (2026-08-11): a validated Mulders short product
  exists in-tree, and its story is the graveyard's best exhibit (§8). Where
  it *did* land: the certified-quotient `high(U·R)` step in sequential
  contexts (div@256 0.46, div@512 **0.33** vs GMP — repeated-divisor division
  is now 2–3× ahead) and the Barrett remainder arm in the band where the
  parallel pool is disabled (mod@128–512 → 0.70–0.75). Wiring it also
  exposed a genuine dropped-carry bug in `bn_mul_low` that had ~75% of
  random mod@24–56 operands silently failing the Barrett certificate and
  paying a full Knuth divide — invisible to fixed benchmark operands, 2.6×
  on random ones. Fuzz with random operands; fixed fixtures lie by omission.

**Trailing-zero stripping** (2026-08-12) rides on top: multiply strips both
operands' trailing zero limbs (shifted values 1.5–3× faster; those fixtures
beat GMP 2–4× since GMP doesn't strip); gcd factors out the *common*
trailing count (per-side stripping is algebraically wrong at limb
granularity: gcd(3·2^64, 6) ≠ 3·gcd-of-odd-parts); division strips the
divisor only under a `2z ≥ vlen` gate — ungated, it *demoted* inputs out of
division's tuned 2n/n reciprocal shape and lost 9%. Shape-specialization
density beats naive size reduction.

---

## 6. The rest of the operation surface

**GCD.** u64 base case is binary GCD with `ctz` — on M5 (FEAT_CSSC) the
single-uop `ctz` replaces `rbit+clz` and shortens the loop recurrence from 4
to 3 cycles, which took gcd@1/2 from exact GMP parity to 0.75/0.83 (GMP's
generic arm64 build can't use CSSC). Above that: fused Lehmer double-simulate
steps, then HGCD with a hard scaling lesson: the 16k+ "cliff" (2.4–2.6× GMP)
was not the algorithm but the *failure path* — a failed matrix apply cost an
O(n) full-width cooldown, and the batch stop rule bounded the wrong residue.
Constant-8 cooldown plus a gap-tracking stop rule made the curve monotone.
Profile the failure path; the hot function was innocent, and run-to-run
variance (a "failure lottery") was the tell.

**Integer square root.** Zimmermann divide-and-conquer `sqrtrem` with a
certified root-only top level: an approximate B–Z quotient (`bz_d2n1n_q`)
plus a 65-bit dropped-chunk certificate, raw allocation-free Knuth under 64
limbs, and a `bn_sqrtrem2` base seeded from a 32-bit double estimate (integer
divide + 128-bit fixup — no fdiv). The 3·2^k widths (384…) needed a zero-pad
peel so the top divide runs unpadded; the 8192 shape needed the two-entry
reciprocal cache (its two recursion divisors evicted each other) and a
division-leaf arena fix (130/65 leaves were malloc-ing per call).

**Modular exponentiation.** Montgomery for odd moduli 3–96 limbs (CIOS
small, SOS with `addmul_1` REDC rows ≥8); register-Barrett for 2-limb
moduli; Barrett beyond 96. The key architectural trick: the *domain is a
context property* — zero is domain-invariant and callers compare only
against the context's images of 1 and n−1, so Montgomery vs Barrett needs no
caller changes and nothing ever converts out. Window size is dynamic 1–8
bits, sitting at the exact 2^(w−1)+bits/(w+1) breakevens (verified by a
force-knob A/B; the "adopt 6–7 bit windows" suggestion was already优 optimal).
The Montgomery ladder's three scratch blocks (modulus copy, window rows, REDC
scratch) are carved from **one allocation at 512 B-separated offsets** —
three separately-malloc'd blocks were a page-phase lottery that the arena
made *stably* bad on one cell (powmod@8 +1.1%) before the carve fixed it.

**Radix conversion.** Both directions are divide-and-conquer on cached
powers P_j = 10^(18·2^j) with cached odd parts (5^p; the 2^p half is a
shift). `to_s`: split by one B–Z division per level, 10.4× at 39k digits.
`from_s`: SWAR 8-digit validation, 19-digit chunk folds, and a split ladder
that took three rounds to get right — power-of-two anchoring left a 16:1
split just past each boundary (fromstr@1024 was the last losing cell on the
board); a skew-cap halving rule fixed the pathology, and **exact-midpoint
powers** (assembling 5^(18m) for m = half the chunk count from existing
ladder entries in ≤2 multiplies, cached by shape) finished it — and the
"build cost will hurt cold parses" worry inverted: eager build is faster
even cold, because it skips the ladder square the old path built and
abandoned.

**Primality.** Deterministic u64 ladder (FJ32 exhaustively verified to 2^32,
hashed SSMR, published Sinclair bases); BPSW above 64 bits (7-base MR +
strong Lucas through the Barrett/Montgomery context); Lucas–Lehmer for
Mersenne; Pépin/Proth (a *proof*, one half-length modexp, 12× BPSW on
Proth-shaped inputs). The BPSW stack yielded three classic latent bugs when
finally fuzzed hard: a Barrett scratch sized 7k+7 for a 12k+8 layout (the
"three temporaries" comment was a lie), a borrow dropped across an all-ones
limb (`b[i] + borrow` overflowing to 0 — moduli near powers of two hang),
and rotating-slot aliasing (holding a modctx result across ≥3 further muls
gets it clobbered). All three were invisible until a GMP-differential
harness existed.

---

## 7. Measurement discipline

More effort went into *how to measure* than any single optimization, because
this box (a developer machine running concurrent agents and long math jobs)
eats naive benchmarks alive. The rules, each purchased with a wrong
conclusion:

- **Same-run ratios only; nothing under ~110 ms timed regions.** A 20 ms
  region is warmup noise; it invented ~10 phantom losses in one matrix run.
  "Accurate mode" = 9 reps × 110 ms, alternating lane order, min-per-lane.
- **ABBA interleaving is the only load-immune instrument.** Sequential
  baseline-vs-candidate runs invert direction under host load. Paired
  A,B,B,A quartets with median-of-log-ratios cancel drift; the default
  screen itself now runs this way (verdict flip-flops across four screens
  went 29→10, and a cell that lost 4/4 screens against an accurate truth of
  0.855 stopped misclassifying entirely).
- **Layout is a measurement variable.** Per-op `noinline aligned(128)` lane
  functions on both the Tungsten *and* GMP sides — growing the harness once
  re-dealt GMP's loop alignments and flipped verdicts. Two heaps resident in
  one process re-rolled the 4K dice ±30%, so each measurement block rebuilds
  its lane context.
- **The environment block is part of your benchmark.** `export`ing a
  variable moves every stack frame (environ lives at the stack top) and
  swung a kernel 0.87→1.73 through the store-forward hazard. Fixed kernels
  keep scratch in TLS, never the stack.
- **Predictor state survives longer than you think.** sub@48 oscillated
  0.83↔1.04 for days; the mechanism was *PC-indexed* memory-dependence
  predictor state — running a 24- or 40-limb row earlier in the same process
  locks the 48 row at ~1.00 with byte-identical instruction streams (+5
  cycles of pure predictor poison), ASLR pinning collapses it, and GMP's
  single shared loop is structurally immune while swinging oppositely.
  Context-controlled, the cell is 0.81–0.84. Some cells must be scored in
  isolated processes; no code change is warranted or possible.
- **Hardware counters break ties honestly.** `flame --counters` (the PMC
  mode added to tungsten-flame) attributes per-symbol IPC and cache-miss
  rates from xctrace's per-thread interval table (the cumulative tables
  double-count under migration — measured +70% instruction error). It
  produced two kinds of endings: fixes (mul1@32's unpaired codegen — equal
  time, 7% more instructions, zero misses both lanes) and **floor proofs**
  (mul1@4 at IPC 9.15-vs-9.16; sub@32/64 pinned to the serial borrow chain
  on both sides) that close a cell as honestly tied.
- **The cache-miss survey corrected the mental model**: nothing in the
  matrix is DRAM-bound at ≤16K limbs (M5's 16 MB shared L2 absorbs
  mul@8192's 1.35 MB/op working set); the real band is L1-transit at ≥1024
  limbs (5–17 misses per kilo-instruction, 10–20% IPC tax), and small
  div/mod are divider-*latency*-bound with zero misses.
- **Fixed operands lie.** The bench's deterministic fixtures never caught
  the `bn_mul_low` dropped carry (75% of *random* operands failed the
  certificate) or exercised trailing-zero shapes. Every kernel change ships
  with a randomized GMP-differential fuzz; the harness cross-checks every
  cell against GMP before timing and dies on mismatch.
- **Wrappers swallow errors; dev builds lie about intrinsics.** `bin/tungsten
  run` exits 0 after runtime death (diff full output, not exit codes), and
  the default `-o` links an -O0 runtime archive where intrinsics-based C
  runs ~30× slow — perf claims come from `--release` only.

---

## 8. The graveyard

Everything below was implemented (or seriously designed), measured, and
rejected. Kept here because each one is a trap that looks attractive from a
distance. Fuller entries live in `benchmarks/big_math/NOTED_TRADEOFFS.md`
and `SUGGESTION_AUDIT.md`.

**Representation and allocation**

- *32-bit limbs with u64 accumulators*: 7.77× slower end-to-end (halving the
  limb width quadruples products but only halves their cost on a 64×64
  multiplier). 28-bit carry-free "nails" beat serial *C* chains (1.44×) but
  lose to flag-chain asm (2.0×) — headroom-instead-of-carries loses to
  attacking carries directly. Small limbs win only with wide-SIMD multipliers
  that NEON doesn't have.
- *Descriptor/limb split (mpz-style header + pointer)*: rejected at design
  time — loses header/limb contiguity (one cache line for header + first
  limbs is a real advantage over GMP), and individually-dying lifetimes force
  a freelist, i.e. rebuilding the pool with extra steps.
- *Two-slot hot ring* (hide release→take latency like GMP's alternating
  destinations): pool cost 0.9→1.6 ns; index bookkeeping exceeds the latency
  hidden.
- *Sign/shared flags in pointer low bits*: shared-ness is per-*object* and
  mutates after boxes are copied — a pointer bit is a stale per-copy
  snapshot; and it's a saturating *count*, not a flag. (Bit 47 sign works
  precisely because sign is per-*reference* by design.)
- *`hot_cap` as u32 for TBAA register promotion*: promotion never fires
  (`size` is i32 — same alias class); the narrower field just cost masking.
  Strict ABBA loss.
- *64-byte-aligned limbs (header out of the limb cache line)*: measured
  negative at every size tried (+0.6–2.8%).
- *Capacity ladder (multi-rung quanta)*: 2.3× the waste of flat q32, no
  recycler benefit, +30% division at the rung boundary.

**Kernels**

- *8-way `addmul_1` unroll*: wins microbenches (1.57 vs 1.93 c/l), spills
  and loses in situ. In-context validation or nothing.
- *Carry-select / split carry chains at small-mid sizes*: the flagship
  negative. Split `mul_1` chains with boundary correction lose 0.8–2.6% at
  16–64 limbs in the boxed lane because consecutive *calls* already overlap
  their chains in the OoO window (both engines run at the two-mul-pipe
  ~0.75–0.78 c/l floor); corrections are pure overhead. Same story for
  16+16+8 sub@40 (every cell lost) and a 128-limb variant that only won at
  exactly 128 (`add@128` carry-select is the one survivor, retained at
  0.66×). The mechanism only pays when the chain is latency-*exposed*
  (dependent single-op chains) — measured 0.77–0.93 there, shipped
  knob-gated for that regime.
- *NEON for non-aligned shifts*: rejected with a humbling root cause — LLVM
  22 already auto-vectorizes the "scalar" funnel loops 8 limbs/iteration;
  the hand-NEON version was 1.46× *worse*. Read the emitted asm before
  assuming a loop is scalar.
- *`vld1q_x4`/`__builtin_memcpy` for the copy-class kernels* (neg/abs):
  slower than 4× single-q pairs at 16–128 limbs — the next op immediately
  re-reads limb 0 through a GPR, and wide stores lose the forwarding race.
  (The *opposite* verdict holds for write-only tails — regime matters, and
  both negatives were correct in their own regime.)
- *Streaming SVE anywhere latency matters*: `smstart/smstop` ≈ 85 ns.

**Algorithms**

- *Toom-6*: never beats Toom-4 anywhere in 384–4096 on this uarch
  (12–63% slower forced). Present, threshold INT32_MAX.
- *Toom-3 squaring*: its window closed when diff-form Karatsuba landed;
  forced measurement confirms the empty [392, 616) window is correct.
- *CRT multi-prime NTT*: 3× transforms for only ~2.5× shorter length —
  loses at every realistic size; single-Goldilocks is right for scalar
  arm64. (The real ≥2048-limb answer was SSA.)
- *Bucket sieve for prime counting*: 5% slower than the tuned mod-6 wheel
  march whose segments are already L1-resident; primesieve's wins come from
  pattern-marking, a different architecture.
- *The mulhigh premise* (Mulders short product at 0.75× a full multiply,
  feeding a Newton-reciprocal sqrt/division rewrite): dead twice over on
  this machine. Sequentially it measures 0.78–0.92× (not 0.75); in the
  pool-parallel regime a *full balanced product* gets ~2× from workers that
  a serially-composed short product cannot use, making mulhigh 1.04–1.16×
  — and the Newton residual `1 − high(D·X)` cancels its own top half, so
  each refinement needs full-width products anyway. The primitive shipped
  validated-but-unused, with its two winning niches (sequential Barrett
  arms) wired instead. A documented negative that then paid for itself.
- *Per-side gcd trailing-zero stripping*: algebraically wrong at limb
  granularity. *isqrt stripping*: invalid for floor sqrt (isqrt(200) ≠
  10·isqrt(2)). *Halve/double operand balancing*: needs the trailing zeros
  anyway, and stripping strictly dominates moving bits.
- *Threshold inference by curve fitting or first-win heuristics*: the tuner's
  proposals contradicted forced-crossover data; a best-of-9 log-log fit
  predicted a 13-limb Karatsuba crossover that lost 10/11 affected cells.
  Recursive-leaf effects make these curves discontinuous. Every cutoff is
  validated per affected boxed cell or it stays at default — the generator
  now enforces exactly that.

**Dispatch and integration**

- *Word-first dispatch order* (test the N×1 shape before equal-width):
  improved the target cells 4–9%, regressed ordinary add/sub up to 33%.
  Dispatch order is a zero-sum resource; layout follow-ups all reverted.
- *Destination-passing prototypes in the C API* (replace-wrappers, outlined
  dest entries, rotation buffers): every variant lost overall or regressed
  controls — the C-side alloc/release protocol was already at its floor.
  The win was waiting one layer up, in the compiler (§9).
- *Source-language kernel bodies for `+`/`-`/shifts* (the migration
  campaign): seven measured attempts (WIRE ops, embedded LLVM IR, embedded
  asm) before the diagnosis landed — the operators' C entries are *dispatch
  trees of specializations*, and a source body pays shape-test overhead to
  reach a generic path. The shipped shape: source bodies own the arms they
  *win* (unequal-length add/sub, mid-band multiply — some faster than C),
  C keeps one-limb and equal-length-same-sign; shifts stayed C entirely
  (the boundary constant is 20–32% of a shift). LLVM cannot form adc chains
  from loop-carried carries even in verbatim IR (issue #74493) — carry
  kernels are asm or they are slow.

---

## 9. Compiler integration: where the last structural wins live

The final gaps against GMP's retained-destination API model closed in the
compiler, not the runtime:

- **Weak-seam latches**: every operator seam (`__w_bigint_*_src`) is a weak
  symbol so compiled programs can override with source bodies — but weak
  symbols are never inlinable, so C-only binaries paid a call per op for
  nothing. The weak *default* can only execute when no override was linked,
  so its first run latches that fact and the entries inline the C path
  thereafter. 5–11% on every polymorphic entry in the O1 runtime archive
  that plain `tungsten -o` binaries link. (Whole-program-LTO binaries never
  paid — LTO internalizes weak defaults. Know which binary shape you're
  optimizing.)
- **Mutate-if-unique (E4)**: a fail-closed lowering walker proves
  accumulator shapes (`r = r ± e`) safe and emits `w_bigint_add_mut` /
  `sub_mut` — true in-place when unique, making `acc += x` amortized O(1)
  instead of O(n)-copy-per-step. Whole-loop boards against
  destination-reusing GMP C went from 104×/26×/7.8× (accumulate/addchain/
  mulchain) to 0.37×/0.77×/0.98× via mut entries, sum-chunking (raw i64
  partials flushed once per 2^63), and rotation-shape dest computation.
- **Dest-taking word entries**: when lowering proves the overwritten LHS of
  `r = a ± w` / `r = a * w` dead (dominating-literal-seed candidacy), it
  emits `w_bigint_*_word_dest(old, a, w)` — write into the dying buffer.
  Compiled word chains got 5–6× faster, 32-limb chains *beat*
  destination-reusing GMP C (0.66–0.71) — and the old path turned out to be
  leaking the dying result on every iteration (243 MB → 2.1 MB RSS on a 5M
  probe). Guards live inside the entry (shared==0, overlay clear, capacity),
  fail-open to the polymorphic ops.
- **Direct lowering**: statically-`:bigint` operands skip the polymorphic
  entry entirely (`TUNGSTEN_BIGINT_DIRECT_OPS`) — the surrounding-cost audit
  measured the generic `w_add`/`w_mul` entries at +2–3 ns, more than an
  entire small boxed op; extending direct lowering to more shapes is the
  standing follow-up. One scar to remember: the first version of direct
  lowering bypassed `w_add`'s rational/decimal arms and fed a Rational to
  the bigint kernel (SIGBUS) — source-body fallbacks must always be the
  *polymorphic* entries.

The self-hosting constraint disciplines all of this: every compiler change
must reproduce stage-1 ≡ stage-2 byte-identical `.ll`, and the compiler
compiles itself *with* the new kernels — a functional proof that runs
millions of operations before any spec does.

---

## 10. Standing and what remains

As of 2026-08-12, on Apple M5 Max vs GMP 6.3 public API:

- **470–478 of 485 cells faster**, full-matrix geomean ≈ 0.60; every
  historical red cell either won or carries a counter-backed floor/context
  proof (mul1@4; sub@32/64; sub@48's predictor bistability).
- Word-op band (N±word, N×word): 0.25–0.55 at 16+ limbs.
- Repeated-divisor division: 0.33–0.47. Modular reduction band: 0.70–0.85.
- Parallel band (≥288 limbs): 17–66% faster than before the pool campaign,
  ≤0.55 vs GMP across the mul band.
- Live-set RSS below malloc/GMP-style allocation (arena + hybrid capacity).
- Whole-loop compiled chains at parity-to-ahead of destination-reusing GMP C.

Open, honestly held:

- ~1024–16384-limb L1-transit band: non-temporal stores + prefetch (the
  counter survey's #1 ranked opportunity, unimplemented).
- Toom recombination is store-hostile (9.4 L1d-store misses/KI vs 2.9 in
  point products) — blocking/fusing candidate.
- SSA bit-granular negacyclic sizing: prize measured at 6–12%, overhead
  20–40% — scoped and shelved with the analysis on record.
- isqrt at FFT scale carries ~+5% from pool-thread churn in its
  serial-heavy recursion (accepted residual of the pool campaign).
- The mulhigh revisit conditions: single-core targets, or a wraparound
  mulmod residual that dodges Newton's cancellation.

The meta-lesson of the whole effort, if there is one: **the kernel is almost
never the bottleneck you think it is.** Of everything that moved the board,
maybe a fifth was arithmetic. The rest was allocation protocol, page-offset
physics, dispatch order, predictor state, measurement honesty, and knowing —
with numbers — when a beautiful idea is simply wrong on this machine.

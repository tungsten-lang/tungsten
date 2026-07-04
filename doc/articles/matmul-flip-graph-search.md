# A matrix-multiplication rank search, native in Tungsten

## The problem, and why it's interesting

How few multiplications does it take to multiply two *n*×*n* matrices? The naive
algorithm uses *n³*. Strassen famously showed 2×2 needs only 7 (not 8), and the
true minimum — the **tensor rank** of the matrix-multiplication tensor ⟨n,n,n⟩ —
is one of the more famous open problems in algebraic complexity. It's open for
nearly every *n*: only 2×2 is settled (exactly 7). The rank also governs the
matrix-multiplication exponent ω, so lowering an upper bound is a genuine result,
not just a faster program.

Over GF(2) (arithmetic mod 2), the records relevant to this search currently
look like this. I checked these against the public
[FMM catalogue](https://fmm.univ-lille.fr/) and
[Perminov's FastMatrixMultiplication work](https://github.com/dronperminov/FastMatrixMultiplication);
the important correction is that Arai's 2024 rank-94 result for 5×5 is no
longer the current upper bound, and the GF(2) 7×7 target is 248 rather than the
general catalogue's 249.

| size | naive | best known | who |
|---|---|---|---|
| 3×3 | 27 | **23** | Laderman 1976 (lower bound 19 — gap *open*) |
| 4×4 | 64 | **47 over GF(2)** | AlphaTensor 2022; 48 is current outside characteristic 2 |
| 5×5 | 125 | **93** | Moosbauer–Poole 2025; after 96 AlphaTensor, 95 KM, 94 Arai |
| 6×6 | 216 | **153** | Moosbauer–Poole 2025 (better than the 161 Strassen×Laderman recursive seed used below) |
| 7×7 | 343 | **248 over GF(2)** | Perminov 2025 (FMM's general catalogue currently lists 249) |

The starting question for this work was whether a self-verifying, "explore all
paths and let the first arrival be the certificate" idea — first sketched for the
Traveling Salesman Problem — could be pointed at *discovering* such algorithms.
The honest answer for matmul turned out to be no: the search space is **un-prunable**
(every rank-*r* decomposition is equally valid, unlike TSP where dominated partial
tours die), so exhaustive "all paths" explodes combinatorially. That negative
result is itself clarifying — and it pointed straight at the method that *does*
work: **flip graphs**.

## The method: flip graphs

A rank-*R* scheme is a set of *R* rank-1 terms (u, v, w), each a bit-mask over the
matrix entries, whose sum (over GF(2)) is the matmul tensor. The flip-graph method
(Kauers & Moosbauer, 2022) does a random walk over schemes using three moves:

- **Flip** — recombine two terms sharing a factor: `b⊗c + b'⊗c' = b⊗(c+c') +
  (b+b')⊗c'`. The cross-term cancels mod 2, so the tensor is preserved. Same rank;
  this is how you explore.
- **Reduction** — when a term's factor becomes zero, or two terms coincide, drop
  them. This is how rank *decreases* — and crucially it happens by accident,
  as a byproduct of exploration, not by greedy choice.
- **Plus-transition** (Arai et al., 2024) — *split* a term into two (rank +1). This
  lets the walk climb out of a flip-graph component that has no reachable
  reduction. Arai et al. proved adding it makes the graph connected, and it's what
  pushed 5×5 from 95 to 94.

A key lesson learned the hard way (see below): **greedy reduction is wrong.**
Actively hunting for a guaranteed reduction races into the nearest local minimum —
on 3×3 it traps at 24, worse than the 23 a patient random walk finds. Reductions
must be accidental.

## The implementation

The whole search is native compiled Tungsten. A scheme is stored as a
**struct-of-arrays of `i64` bitmasks** — three parallel arrays `us[]`, `vs[]`,
`ws[]`, one slot per term, each factor a single `i64` (bit *i* = "entry *i* is in
this factor"). GF(2) set algebra is then single machine instructions: combine =
`xor`, equality = `==`, zero-test = `== 0`. The arrays are fixed-size
(`i64[300]`), allocated once, with bounds-free `[]`/`[]=` access. Correctness is
spot-checked on random GF(2) inputs every time a new best is found, and any
record-or-better scheme is dumped and re-verified externally by rebuilding the full
tensor mod 2.

The search runs as a **fleet**: independent walkers with distinct RNG seeds, sized
to the machine's effective core count (a throughput sweep showed aggregate
moves/second peaking at ~18 walkers on an 18-core 6P+12E box, plateauing through
24, declining past that). After the performance work (separate article) each
walker runs at ~10–28 million moves/second and the fleet is leak-free, so a
two-minute leash explores tens of billions of moves.

## Results, honestly

| size | reached | record / bound | outcome |
|---|---|---|---|
| **3×3** | **23** | 23 | matched; 22 (open) not found in **~1.5 trillion** moves (full stack, 60-min fleet) |
| **4×4** | **47** | 47 over GF(2) | matched; ~1 min from naive; verified novel decomposition; 46 not found |
| **5×5** | **95** | 93 current / 94 Arai 2024 | two ranks behind current; never reached 94 |
| **6×6** | **161** | 153 current / 161 recursive seed | stuck at the recursive seed (flip-poor); 195 from naive |
| **7×7** | **329** | 248 current | ~1 min exploratory run from naive; far from current record, but below naive 343 |

A few notes on each:

- **3×3 → 23.** Reached reliably and fast, and then hammered: a 60-minute fleet of
  18 walkers running the full stack (free walk + structured plus + higher-order
  reduction + motif injection) did **~1.5 trillion moves** — rank 23 appeared
  300,000+ times, rank 22 **never once**. Laderman's 23 has stood since 1976 for
  exactly this reason: 22 is in the open gap (19 ≤ r ≤ 23) but is either unreachable
  by flip-graph or doesn't exist. We didn't disprove 22; we showed about as
  conclusively as a search can that it isn't *findable* this way. A
  *symmetry-reduced exhaustive* walk corroborates it — the symmetric rank-23
  flip-graph components are tiny (≈16 schemes each) and were fully exhausted with
  no path to 22 — the one place "walk all paths" actually completes.

- **4×4 → 47.** One walker, from naive-64, reached rank 47 — *matching* the
  AlphaTensor record — and it was exactly verified (reconstructs the 4×4 tensor mod
  2, all factors non-zero). It is a **different decomposition**: zero of its 47
  terms coincide with any of AlphaTensor's, and it uses denser factors (16.2 vs 9.6
  bits/term). That makes it an independently-found rank-47 algorithm, not a
  rediscovery — interesting, but *not publishable*: matching (not lowering) the
  rank doesn't move the bound, and there are many rank-47 decompositions.

- **5×5 → 95.** From the AlphaTensor-96 seed the search refines 96 → 95 in ~5
  million moves, then hits a wall: 72 billion moves, 18 walkers, **every reading
  95, not one 94.** That clean wall is the signal — Arai's 94 wasn't a simple
  compute problem for this implementation (more walkers at the same policy won't
  help), it was a *method* gap. The current 93 upper bound is farther out still.
  Arai's 94 came from an **adaptive** plus-transition policy (when to climb, how
  far, how to constrain exploration); my fixed-threshold version has the right
  move but a cruder policy.

## Pushing further: the full adaptive policy, and where it stalls

The "one credible path" above — implementing Arai et al.'s method properly — was
then *done*, in full:

- **Structured plus-transition** (Definition 4.1): split a term using a factor
  that *already exists in the scheme*, so the new term is immediately flippable —
  not a random-bit split. Validated working.
- **Edge-constraint hierarchy** (Algorithm 4): restrict every move to a growing
  d×d×d subtensor (solve the 2×2 corner, expand to 3×3, …), with an on/off toggle.
  This was a **genuine step-change for small sizes**: 4×4 now reaches the record
  47 *from naive in about one minute, reliably* — previously a lucky-seed event.

But it does **not** break any record:

- **5×5 stays at 95.** The structured plus, the hierarchy, looser reset caps, and
  a pure free walk (no reset at all) were each tried — every one walls at 95, never
  94, let alone the current 93. The gap to Arai's 94 is not a single missing
  ingredient we can name; the gap to 93 is larger and should be treated as a
  different, current-SOTA target.
- **6×6 stalls at the recursive seed 161.** Seeding from the verified Kronecker
  construction (Strassen-7 ⊗ Laderman-23 = 161) and refining downward *fails*: the
  recursive scheme is a **near-isolated vertex** — only **42 flip-eligible pairs
  out of 12,880** (all 161 W-factors distinct), because `α_r⊗a_s` is almost always
  a distinct factor. With nothing to flip, no policy (reset/looser-cap/free-walk)
  finds a sub-161 reduction. Current catalogues list 153 for 6×6, so this result is
  not record-matching; it only says this local walk cannot improve the recursive
  seed. From naive it plateaus higher still (195), because a uniform dim-advance
  schedule rushes the large subtensors.

## Closing the search: the Codex levers, and reachability vs detection

An independent review (OpenAI Codex) proposed two concrete levers neither tried nor
ruled out. Both were implemented in Tungsten, verified correct, and tested at scale.
Both are neutral — and *why* they're neutral is the sharpest result of the project.

- **Higher-order bucket reduction (the *complete* reduction).** My reduction only
  caught zero-factor and duplicate terms. The full Kauers–Moosbauer/Arai reduction
  groups terms by a shared factor, forms the residual matrix `M = Σ vᵢwᵢᵀ`, computes
  its GF(2) rank by Gaussian elimination, and replaces the bucket when
  `rank(M) < bucket size`. Implemented with full RREF + refactorization; correct
  (tensor preserved through every reduction). But neutral: applied greedily it
  **traps** (`97→96, 98→97`, always into a flip-poor min — the "reductions must be
  accidental" law again), and on a free walk at scale it lands on the same walls
  (5×5→95, 6×6→161). The takeaway is decisive: the search now has the *complete*
  reduction repertoire and the walls hold, so the barrier is **reachability, not
  detection** — the lower-rank decomposition isn't hiding behind a reduction we
  missed; it lives in a region of scheme-space the walk never reaches.

- **Zero-sum motif injection (the non-local jump).** Splice in `naive-8 ⊕ Strassen-7`
  — 15 terms summing to 0 over a random 2×2 sub-block, tensor preserved — to hand the
  walk coherent, *absorbable* flip-structure, a far richer escape than a single-term
  split. Implemented, verified, neutral: 5×5→95, 6×6→161, even on the flip-poor 6×6
  seed where fresh flippable structure should matter most. The one move that changes
  reachability still didn't cross a wall.

So the barrier survives the complete reduction set *and* a genuine non-local escape,
at up to trillion-move scale. That's the strongest statement the project can make
about *why* the records held.

## Bottom line

The search is sound, fast, and correct — it reliably matches the standing GF(2)
records on 3×3 (23) and 4×4 (47, now in ~1 minute from naive), produced a verified
novel rank-47 decomposition, and implements the full Arai adaptive policy, the
complete higher-order reduction, and non-local motif injection. **No new records
were broken, and every hard frontier actually tested (22, 46, 94, sub-161) is a
clean wall under every lever tried — local exploration, the complete reduction set,
structural focusing, and non-local jumps alike, at up to ~1.5 trillion moves.**
The current public record targets for the larger square cases are lower still
(5×5 at 93, 6×6 at 153, 7×7 over GF(2) at 248), so the honest framing is narrower:
this is a SOTA-matching engine for the small GF(2) cases, not a SOTA-beating one.
Crossing the next rank down is a research-scale effort (the multi-day compute the
published record papers used, or a fundamentally new method), not another move —
we've tested the moves. The durable wins are the engineering (see the companion
article) and an honest, complete map of exactly where the method's reach ends.

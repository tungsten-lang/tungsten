# Collatz via the DETOUR symbolic-merge framework

An attack on the Collatz conjecture written natively in Tungsten, built around one
idea: **a sequence of Collatz operations merges into a single affine map.** A path
that does `a` odd-steps (`3x+1`) and `d` halvings is exactly

```
x  ->  (3^a · x + c) / 2^d
```

`/2 ∘ /2 = /4` is not an approximation — the denominators multiply. From there:

- a **loop closes** iff that merged map has a positive-integer fixed point
  `x = c / (2^d − 3^a)` (this is the classical cycle equation, Steiner 1977);
- the **bit pattern of the start fully determines the merged operations** (Terras's
  1976 parity-vector bijection);
- searching operation-sequences in **DETOUR cost-order** (rising `d`) makes the
  *first* closing loop the minimal one — arrival-order certifies minimality, no
  cycle-length comparison needed.

## What this is — and what it is not

**Rigorously establishes** (see `proof.md`): a computer-assisted proof that **no nontrivial
Collatz cycle has ≤ 69 odd-steps**, via verifying every `n ≤ 4.5×10¹²` reaches 1 plus an
elementary minimum-element bound. The cycle equation is independently cross-checked against
the known *negative* cycles `{−1}`, `{−5,−7}`, `{−17,…}` (`cycle_search.w`).

**Illustrates** the structure behind the conjecture: the bit pattern of `n` controls its
trajectory (Terras's bijection, Part B); the all-ones seed `2^k−1 = −1 mod 2^k` is the unique
maximal "run-up", peaking at *exactly* `2·3^k − 2` (`runup.w`, Part D); cycles can only close at
the convergents of `log₂3` (Part G); and what it costs to push verification (the A-vs-B frontier).

**Does NOT prove Collatz**, and does not pretend to. The proof is *bounded* (≤ 69 odd-steps) and
*computer-assisted*. Its parameter — odd-steps — is a **different, weaker axis** than the
literature's: Simons–de Weger exclude `m ≤ 68` **blocks** (`m ≤ a`), which covers far more
cycles; the two are **not comparable** and this is **not an improvement** on known results. It
says **nothing about divergence** — the other half of the conjecture, for which no descent
function is known. `reduction.md` shows the conjecture is *not* reducible to `2^d ≠ 3^a` (that
inequality is trivially true).

## Files

| file | what it is |
|---|---|
| `collatz_detour.w` | Parts A–E: merge → affine map, the Terras bijection, the cycle search, the contraction census, and the descent certificate |
| `collatz_accel.w`  | Part F: the `k`-step merged-map table that advances any `n` by `k` halvings in one lookup (`n → 3^a(r)·q + e(r)`) |
| `collatz_convergents.w` | Part G: the base-2/base-3 competition — cycles can only close at convergents of `log₂3`; prints the A-vs-B frontier in bignum (runs via the interpreter) |
| `collatz_cert.w`    | bignum-safe descent certificate (plain `Int`, no i64 ceiling); `argv[0]`=B, `argv[1]`=slice-low for parallel fleets. Always correct; ~13× slower above `B≈10¹²` where peaks go bignum |
| `collatz_cert_i64.w`| fast `## i64` certificate with an explicit overflow guard (flags if any peak nears `2^63` rather than wrapping). ~13× faster, but the guard fires above `B≈10¹²` (real peaks exceed `3×10¹⁸` there) — use it below that, bignum above |
| `collatz_cert_hybrid.w` | the winner above `10¹²`: fast i64 sweep + an inline bignum re-check for the ~1-in-3-million m whose peak trips the guard. Sound and ~13× faster than all-bignum. This is what verified the A=69 range |
| `proof.md`          | a rigorous **computer-assisted proof** that no nontrivial Collatz cycle has ≤69 odd-steps (Lemmas 1–4 hand-checkable; one finite-computation input). Honest scope: bounded, odd-steps not blocks, nothing on divergence |
| `reduction.md`      | the honest reduction map: why Collatz is **not** reducible to `2^d ≠ 3^a`, and the two real hard kernels (a Baker-strength bound for cycles; a missing descent function for divergence) |
| `baker_bound.md`    | the explicit linear-forms-in-logs bound (Matveev/Rhin) for `\|2^d−3^a\|`, what it gives, and why our `a≤69` (odd-steps, verification) is weaker than and different from Simons–de Weger's `m≤68` (odd-blocks, Rhin bound) |
| `circuit_m1.w` / `.md` | the **block axis, `m=1`**: reproduces the bounded computational content of Steiner (1977) — the circuit equation `(2^{k+l}−3^k)·h = 2^l−1` has only `(1,1,1)` for `k≤100000`. Distinct from (and complementary to) `proof.md`'s odd-step axis; the all-`k` case is Steiner's Baker-based theorem |
| `cycle_search.w` / `.md` | self-validating both-signs cycle search: recovers the classical **negative** cycles (`{−1}`, `{−5,−7}`, `{−17,…}`) + trivial `{1}`, finds no nontrivial positive cycle for `\|element\|≤20000`, and uses the negatives as an **independent witness for `proof.md`'s Lemma 1** (verified on `m=0,1,2` cycles) |
| `runup.w`           | empirical check of **Part D's maximal expander**: the all-ones start `2^k−1` (`= −1 mod 2^k`) has run-up peak **exactly `2·3^k − 2`** (`100·peak/3^k = 199` for every `k`), confirming `peak = Θ(3^k)` — the structural reason those numbers climb hardest |
| `trajectory_big.w`  | the full Collatz trajectory of `2^k−1` to 1 in **compiled** Tungsten on arbitrary-precision ints (`## big` idiom), validated exact (`k=1000→12157`, `k=100000→1,344,926`) — demonstrates compiled bignum works natively |
| `representations.md` / `.py` | **eight changes of coordinate, one conserved obstruction**: forward/backward/symbolic/deferred-accumulator/large-set/complex/multiplicative/2-adic re-encodings each find real structure and each leave the same residue (convergence). Sharpest form (Syracuse): the conjecture ⟺ `avg v₂(3m+1) > log₂3`, with `E[v]=2` provable and the worst case not. `.py` reproduces every cited number |
| `reach.md` + `collatz_refined.w` / `reach.py` | **sharpens `proof.md` and computes its true reach**: two unused minimum-element facts (`v₁=1`, `v₂≤2`) shrink the bound `M(a)` by a rigorous `(3/2)²=2.25`, and with Barina's *published* frontier `2⁶⁸` (2021) / *live* `2⁷¹` (2025) the same argument reaches `a≤115` / `a≤120` (vs our self-contained `a≤69`), hitting a structural wall at `a≈121`. Still odd-steps, still incomparable to Simons–de Weger/Hercher. Cross-checked in Tungsten + CPython bignum |

Both compile with `bin/tungsten -o <out> <file>.w` and run as native binaries. They
use `i64[]` arrays and `## i64` typing, so they need the **compiled** path (the
interpreter does not dispatch `typed_array` / typed literals).

## The seven parts and what they establish

- **A — merge.** The path `1→4→2→1` composes op-by-op into `(3x+1)/4`, whose fixed
  point is `x=1`. The loop closes by arithmetic, not iteration.
- **B — bijection.** For every `k = 1..12`, the `2^k` residue classes mod `2^k`
  produce `2^k` *distinct* parity vectors. The low `k` bits determine the first `k`
  merged operations, exactly. (Uses the *shortcut* map `odd → (3n+1)/2`; the full map
  is not a bijection — `1` and `3` collide mod 4.)
- **C — cycle search.** Searching `n·(2^d − 3^a) = c` for `a = 1..4`, `d ≤ 34`, the
  only integer fixed point that appears is `n = 1`. No nontrivial cycle in that cost
  range.
- **D — contraction census.** A class with `a` odd-steps contracts iff `3^a < 2^k`,
  i.e. `a < 0.6309·k`. The odd-step count is binomial (mean `k/2`), so the
  contracting fraction climbs toward 1 as the threshold pulls `0.26·√k` standard
  deviations above the mean. The **unique** worst class at every `k` is
  `2^k − 1 ≡ −1 (mod 2^k)` — the climbers are precisely the integers impersonating
  `−1`, the map's 2-adic fixed point.
- **E — certificate.** Every `n ≤ 10^9` descends below itself ⇒ all reach 1 and no
  cycle has minimum element ≤ `10^9`. Runs in ~3 s. The bound is set by i64: at
  `n ≈ 10^9` the largest trajectory value is `1.41×10^18`, within ~6× of the
  `9.22×10^18` ceiling, so `~2×10^9` is the wall for the fixed-width version.
- **F — acceleration (and a negative result).** The identity
  `n = q·2^k + r → 3^a(r)·q + e(r)` advances `k` halvings in one table lookup. The
  self-check finds **0 mismatches** over millions of `(q,r)` — validating the whole
  bit-pattern framework end to end. But it does **not** speed up the certificate:
  descent stopping-times are short (most `n` drop below themselves in a handful of
  steps), so a fixed `k`-halving block overshoots. The acceleration is the right
  tool for following *full* trajectories to 1, not for the descent test. (Echo of a
  recurring lesson: throughput is rarely the lever.)

- **G — the cycle frontier (bitcounts → jumps).** Per merged step `log₂(n)` jumps
  `+log₂3` on an odd-step, `−1` on a halving; a cycle needs `A·log₂3 = D`. Since
  `log₂3` is irrational, `2^D ≠ 3^A` ever, so `Q = 2^D − 3^A ≥ 1` always and a cycle's
  minimum element is `m = c/Q`. The constant `c` is maximized by packing all halvings
  early, and `D = ⌈A·log₂3⌉` is the worst case (larger `D` only shrinks `c_max/Q`), so
  `m < c_max/Q` is a *complete* rigorous bound per `A`. `Q` is tiny only at the
  **convergents of `log₂3`** — the only places a cycle can hide — and ordering by `Q`
  is the DETOUR cost function for cycle search. Combining this with the certificate
  (verified to `B = 4.5×10¹²`): **every Collatz cycle with `A ≤ 69` odd-steps is
  excluded outright.** (The min-element bound `M(a)` peaks at `A=68` within the window,
  `M(68)=4.39×10¹²`; `M(69)` is *smaller*, so the running max — the `B` needed for all
  `A≤69` — is `M(68)`, and `4.5×10¹²` clears it. `A=68` is **not** itself a convergent of
  `log₂3` — its peak is the `c_max~1.5^A` growth, not a small `Q`; the real deep
  convergents bracketing this range are `A=41` and `A=94`. `A=70` needs `B>3.95×10¹³`,
  the first beyond reach.) Note this is `A` = **odd-steps**;
  it is *not* the parameter the literature uses. Simons–de Weger (2005) excluded
  `m`-cycles for `m ≤ 68`, where `m` counts **blocks of consecutive odd integers** (local
  minima) — and since each block holds ≥1 odd-step, `m ≤ A`, so their result covers
  cycles with arbitrarily many odd-steps. Our odd-step `A ≤ 69` is a different, weaker-
  coverage axis (elementary verification, not Baker bounds) — independent of, and not an
  improvement on, S–dW. See `reduction.md`.

## Expanding A (verification bound vs odd-step cutoff)

With the plain-`Int` certificate the bound `B` is limited by *time*, not word size.
The generic cycle bound grows like `1.5^A`, so each `~1.5×` in `B` buys `+1` on the
A-cutoff (equivalently, each decade of `B` buys `~+5.7`); the convergent spikes of `log₂3`
are the local jumps. `collatz_convergents.w` prints the requirement, and **`reach.md`
carries it through the published Barina frontiers** (`2⁶⁸`, 2021 / `2⁷¹`, 2025) — where the
*same* argument reaches `a≤110`–`120` and the first *unclearable* wall is `a≈121`, not
`a=94` (whose spike `2.55×10¹⁸` is well inside `2⁶⁸`):

| exclude all cycles through `A` | needs verified `B >` | status |
|---|---|---|
| 50 | 1.36×10⁹ | ✓ (Part F, `B=2×10⁹`) |
| 55 | 8.66×10⁹ | ✓ (`collatz_cert`, `B=10¹⁰`) |
| 65 | 8.52×10¹¹ | ✓ (`B=10¹²`) |
| 67 | 1.17×10¹² | ✓ (`B=1.18×10¹²`, 18-core fleet) |
| 68–69 | 4.39×10¹² | ✓ (`B=4.5×10¹²`, hybrid fleet, ~12 min — our self-contained proof) |
| 70 | 3.95×10¹³ | ✓ via Barina `2⁶⁸` (self-verify: days) |
| 94 | 2.55×10¹⁸ | ✓ via Barina `2⁶⁸` (published frontier) |
| 110 (`115` refined) | 6.82×10¹⁹ | ✓ via Barina `2⁶⁸`; see `reach.md` |
| 306 | ~10⁵⁶ | infeasible (deep convergent — Baker-bound territory) |

(The `needs verified B >` column is the **running maximum** of the per-`A` bound `M(a)` over
all `a ≤ A` — what it costs to clear *every* cycle up to `A`. So this `A=67` entry is `M(66)`,
not the individual `M(67)=9.77×10¹¹` quoted in `proof.md`; `M(a)` itself is non-monotonic.)

**Two cost regimes, and how the hybrid beats them.** Below `B≈10¹²`, trajectory peaks
stay under the i64 ceiling, so `collatz_cert_i64.w` runs at ~3 s per `10⁹`. Above
`B≈10¹²`, real peaks exceed `3×10¹⁸`, and an all-bignum certificate (`collatz_cert.w`)
slows to ~50 s per `10⁹` — ~13× slower, which alone would make `A≤69` a ~2.4 hr job.
`collatz_cert_hybrid.w` avoids that: it sweeps in fast i64 and re-checks in bignum only
the ~1-in-3-million m whose peak trips the guard (661,855 such m across the
`[1.18×10¹², 4.5×10¹²]` increment). Result ~3.8 s per `10⁹`. The certificate
parallelizes perfectly (each `m` is independent), so wall-time is `total / cores`;
`A≤69` took two ~6-min 18-core foreground fleets.

Run e.g. `bin/tungsten -o cert collatz_cert.w && ./cert 10000000000` to verify
`B=10¹⁰` (→ `A ≤ 55`). Past `A≈70` brute verification stops being practical; the
deep convergents need the Diophantine machinery instead.

## Where the proof actually lives

Parts B and D say your low bits control your fate and almost every bit pattern
contracts — but "almost every" leaves a Gaussian-thin exceptional tail (the
`−1`-impersonators) that shrinks yet never empties at finite `k`. Two gaps remain,
and they are the conjecture:

1. **Cycles are only half of it.** Part C/E exclude *bounded loops*. The other
   failure mode is a trajectory that **diverges to infinity** and never loops.
2. **No descent function.** The bijection and the census are exact structural facts;
   neither yields a quantity that provably *decreases*. Converting the bit-pattern
   structure into a monovariant that rules out divergence is the open problem.

So this is a faithful, runnable instance of the real cycle-exclusion framework with
DETOUR supplying the minimality certificate — a computational lab for the structure,
not a disproof attempt.

## Run

```bash
bin/tungsten -o /tmp/collatz_detour benchmarks/collatz/detour/collatz_detour.w && /tmp/collatz_detour
bin/tungsten -o /tmp/collatz_accel  benchmarks/collatz/detour/collatz_accel.w  && /tmp/collatz_accel
```

To push the certificate past `~2×10^9`, switch the hot loops off `## i64` to bignum
(arbitrary precision, slower) or to `## u64` (one more bit of headroom).

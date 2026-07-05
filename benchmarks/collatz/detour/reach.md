# Sharpening the elementary cycle bound — and the true reach of `proof.md`

## What this adds

`proof.md` proves *no nontrivial Collatz cycle has ≤ 69 odd-steps*. This note improves that
result along the **same elementary machinery**, in two independent ways, and then draws the
honest ceiling:

1. **The `a ≤ 69` cutoff is our certificate's limit, not the method's.** It is fixed by the
   range we personally verified (`4.5×10¹²`). Feeding the *same* argument the published
   Collatz verification frontier — which the repo already acknowledges exists — lifts it to
   **`a ≤ 110`** (Barina 2021, `2⁶⁸`) or **`a ≤ 118`** (Barina 2025 live, `2⁷¹`) with **no new
   mathematics**.
2. **A rigorous tightening `proof.md` never uses.** Two elementary facts about the *minimum*
   element shrink the bound `M(a)` by a factor `(3/2)² = 2.25`, extending the reach to
   **`a ≤ 115`** (`2⁶⁸`) / **`a ≤ 120`** (`2⁷¹`).
3. **The structural wall.** Even the tightened bound with the live frontier hits a hard wall
   at **`a = 121`** — the first convergent spike no feasible computation clears. Past it the
   method is dead and Baker's theorem is unavoidable; this pins down *exactly where*.

Everything here is cross-checked in two independent bignum implementations
(`collatz_refined.w` on the Tungsten interpreter, `reach.py` in CPython), both reproducing
`proof.md`'s `M(67..70)` to the digit. **Nothing here touches divergence, and none of it is
comparable to the literature's odd-*block* results** (see Scope).

---

## The two new lemmas (minimum-element constraints)

Read a nontrivial cycle from its minimum element `m` (odd, `m ≥ 3`, since the only cycle
containing `1` is trivial). Let `n_i` be the elements and `v_i` the shortcut exponents,
`n_{i+1} = (3 n_i + 1)/2^{v_i}`.

**Lemma R1 (`v₁ = 1`).** `n₂ = (3m+1)/2^{v₁}` is a cycle element, so `n₂ ≥ m`. Then
`2^{v₁} = (3m+1)/n₂ ≤ (3m+1)/m = 3 + 1/m ≤ 10/3 < 4`, hence `v₁ = 1`. ∎

**Lemma R2 (`v₂ ≤ 2`).** By R1, `n₂ = (3m+1)/2`, and `m ≥ 3` gives `n₂ < 2m` (i.e.
`3m+1 < 4m`). Since `n₃ ≥ m`, `2^{v₂} = (3n₂+1)/n₃ ≤ (3n₂+1)/m < (6m+1)/m = 6 + 1/m < 8`,
hence `v₂ ≤ 2`. ∎

Both are absent from `proof.md`: its worst-case configuration (Lemma 3) loads the excess
halvings into `v₁` (`v₁ = d − a + 1`, large), which R1 forbids outright.

## Effect on the bound

In `c_max(a,d) = 3^{a−1} + Σ_{i=2}^{a} 3^{a−i} 2^{d−a+i−1}` the terms **decrease** in `i`
(consecutive ratio `2/3`), so the *dominant* term is `i = 2`: `3^{a−2} 2^{d−a+1}`. R1 forces
`S₁ = 1`, replacing it by `3^{a−2}·2`; R2 forces `S₂ ≤ 3`, replacing the `i = 3` term
`3^{a−3} 2^{d−a+2}` by `3^{a−3}·2³`. Re-maximising `c` over the constrained sequences leaves
every other term at its Lemma-3 maximum (the excess simply relocates to `v₂`, resp. `v₃`), so

```
c'_max  = c_max  − 3^{a−2}·(2^{d−a+1} − 2)                     (v₁ = 1)
c''_max = c'_max − 3^{a−3}·(2^{d−a+2} − 8)                     (v₁ = 1 and v₂ ≤ 2)
```

Both stay of the form `β + α·2^d` with `α > 0` (the removed coefficient is exactly the
`i=2`, resp. `i=3`, term of the constant `K` in Lemma 4), so **Lemma 4 carries over verbatim**
— the ratio is still strictly decreasing in `d`, so `d = D = ⌈a·log₂3⌉` remains the worst
case. Hence the rigorous refined bound on the cycle minimum:

```
m ≤ M''(a) := ⌊ c''_max(a, D) / (2^D − 3^a) ⌋ ≤ M(a),      M(a)/M''(a) → (3/2)² = 2.25.
```

The `2.25` is exact asymptotically because the two largest terms are removed and the tail
decays by `2/3`; empirically `M/M'' ∈ {2.24, 2.25}` across `40 ≤ a ≤ 130`.

> The refinement generalises: reading from the minimum forces `v_k ≲ 0.585·k` for every
> prefix (each `n_k < c_k·m` with `c_k` growing like `1.5^k`), giving a whole family of
> prefix bounds `m ≤ c_i/(2^{S_i} − 3^i)`, of which `proof.md` uses only `i = a`. R1/R2 are
> the first two; further terms add diminishing `~3/2` factors. Only the clean, closed-form
> `v₁, v₂` cases are claimed here.

---

## The reach, exactly

`M(a)` (and `M''(a)`) is computed in exact bignum; a cycle with `a` odd-steps is excluded
once its running-max bound is below a verified frontier `B`. Largest excluded odd-step count:

| verified frontier `B` | `M` (corpus) | `M''` (refined) |
|---|---|---|
| our certificate, `4.5×10¹²` (`proof.md`) | `a ≤ 69` | `a ≤ 69` |
| **Barina 2021**, published `2⁶⁸ ≈ 2.95×10²⁰` | `a ≤ 110` | **`a ≤ 115`** |
| **Barina 2025**, live `2⁷¹ ≈ 2.36×10²¹` | `a ≤ 118` | **`a ≤ 120`** |

At `B = 4.5×10¹²` the refinement buys nothing: the next spike, `M''(70) ≈ 1.75×10¹³`, still
exceeds it, so the granularity of the convergent spikes eats the `2.25×`. The refinement pays
off precisely where a spike lands inside the shrunk gap — `+5` odd-steps at `2⁶⁸`, `+2` at
`2⁷¹`.

## The structural wall — where compute dies

`M''` running-max first exceeds the frontier at:

- `B = 2⁶⁸` → wall at **`a = 116`** (`M''(116) ≈ 8.3×10²⁰`);
- `B = 2⁷¹` → wall at **`a = 121`**.

Beyond the wall the bound climbs `~1.5^a` with convergent spikes, and the deep convergent at
`a = 306` (`d = 485`) gives

```
M''(306) ≈ 2.2 × 10⁵⁶ ≈ 2¹⁸⁷ ,
```

so excluding all `a ≤ 306` by this method would need Collatz verified past `10⁵⁶` — utterly
infeasible, and the convergents only get worse. **This is the quantitative form of
`reduction.md §2`:** the elementary lever reaches `a ≈ 120` with today's frontier and can
*never* reach all `a`; closing the general case needs an effective lower bound on
`|2^d − 3^a|` (Baker/Rhin), not more computation.

---

## Scope — what this does and does not do

- **Still odd-STEPS, not odd-BLOCKS.** `a` counts `3x+1` operations. Simons–de Weger (2005,
  `m ≤ 68`; later `≤ 75`) and **Hercher (2023, `m ≤ 91`)** count *local minima / blocks of
  consecutive odds* (`m ≤ a`), covering cycles with arbitrarily many odd-steps via Rhin's
  linear-forms bound. Our `a ≤ 120` is **formally incomparable to and weaker-coverage than**
  those; it is **not** an improvement on the literature. (Notably, Hercher documents the same
  B-scaling we exploit: a larger verified frontier alone lifts Simons–de Weger's `m ≥ 76` to
  `m ≥ 83` — the block-axis analogue of our `69 → 110`.)
- **Still bounded, still cycle-only.** No claim about all `a`; nothing about divergence; no
  monotone-decreasing quantity is produced.
- **What is genuinely new vs. the repo:** the `v₁ = 1 / v₂ ≤ 2` tightening (a real, rigorous,
  elementary sharpening of `M(a)`), and the concrete reach + structural-wall numbers under the
  published frontier. The `M(a)` machinery and convergent structure are `proof.md` /
  `collatz_convergents.w`; most of the `69 → 110` jump is *using the published computation*,
  not new mathematics — labelled as such.

**Reproduce:** `bin/tungsten benchmarks/collatz/detour/collatz_refined.w` (Tungsten) or
`python3 benchmarks/collatz/detour/reach.py` (CPython); both print the cross-check and the
tables above.

**Sources.** Barina, *Convergence verification of the Collatz problem*, J. Supercomputing 77
(2021) 2681–2688; Barina, *Improved verification limit…*, J. Supercomputing (2025) — live
`2⁷¹`, 2025-01-15. Simons–de Weger, *Theoretical and computational bounds for m-cycles…*,
Acta Arith. 117 (2005) 51–70. Hercher, *There are no Collatz-m-Cycles with m ≤ 91*, J. Integer
Seq. 26 (2023), arXiv:2201.00406.

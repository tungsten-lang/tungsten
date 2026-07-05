# No nontrivial Collatz cycle has ≤ 69 odd-steps

*Assembly and every join independently checked over two adversarial review rounds: the
four lemmas, the standard↔shortcut bridge, the descent induction, and the running-max
constant `M(68)` all verified (the `M(a)` values reproduced to the digit by an independent
bignum sweep). Correctness is contingent only on the certificate computation and bignum
arithmetic — see "Computational input" and caveat 4.*

A computer-assisted proof of a *bounded* cycle-exclusion result for the shortcut
Collatz map. The hand-proof part (Lemmas 1–4 and their assembly) is elementary and
fully checkable below; one input — that every integer up to `4.5×10¹²` reaches 1 — is a
finite machine computation, which is what makes this *computer-assisted* rather than a
pure theorem. Read `reduction.md` first for why this is a narrow, non-comparable result;
the "Scope" section at the end says exactly what it does **not** prove.

---

## Setup and notation

The **shortcut Collatz map** acts on odd integers:

```
T(n) = (3n + 1) / 2^v ,    where 2^v exactly divides 3n+1 (so v ≥ 1 and T(n) is odd).
```

A **cycle** is a periodic orbit of odd numbers `n_1 → n_2 → … → n_a → n_1` (so
`n_{i+1} = T(n_i)` and `n_{a+1} = n_1`), with all `n_i` distinct positive odd integers.
We write:

- `a` = the number of odd numbers in the cycle = the number of odd-steps;
- `v_i ≥ 1` = the exponent at step `i`, i.e. `n_{i+1} = (3 n_i + 1)/2^{v_i}`;
- `S_0 = 0`, `S_i = v_1 + v_2 + … + v_i`, so the partial sums satisfy
  `0 = S_0 < S_1 < … < S_a`; write `d := S_a = v_1 + … + v_a` for the total halvings.

The **trivial cycle** is `{1}`: `T(1) = (3·1 + 1)/2^2 = 1`, with `a = 1`, `v_1 = 2`,
`d = 2`. It is the unique cycle containing `1`.

Throughout, `log₂3 ≈ 1.5849625…`, and `a·log₂3` is irrational for every integer
`a ≥ 1` (a power of 2 cannot equal a power of 3 by unique factorisation), hence **never an
integer**.

> **Theorem.** The only Collatz cycle with `a ≤ 69` odd-steps is the trivial cycle `{1}`.
> Equivalently, no nontrivial Collatz cycle has 69 or fewer odd elements.

The proof combines four elementary lemmas (an exact upper bound `M(a)` on a cycle's
minimum element) with one finite computation (everything `≤ 4.5×10¹²` reaches 1).

---

## Lemma 1 (cycle equation)

For a cycle as above,
```
n_1 · (2^d − 3^a) = c ,   where   c = Σ_{i=1}^{a} 3^{a−i} · 2^{S_{i−1}} .
```

**Proof.** We first prove, by induction on `k ≥ 1`, the unrolled identity
```
2^{S_k} · n_{k+1} = 3^k · n_1 + Σ_{i=1}^{k} 3^{k−i} · 2^{S_{i−1}} .            (∗)
```
*Base `k = 1`.* From `n_2 = (3 n_1 + 1)/2^{v_1}` we get `2^{v_1} n_2 = 3 n_1 + 1`. Since
`S_1 = v_1`, `S_0 = 0`, this is `2^{S_1} n_2 = 3^1 n_1 + 3^0·2^{S_0}`, which is (∗) at
`k = 1`.

*Step.* Assume (∗) for `k`. From `n_{k+2} = (3 n_{k+1} + 1)/2^{v_{k+1}}` we have
`2^{v_{k+1}} n_{k+2} = 3 n_{k+1} + 1`. Multiply both sides by `2^{S_k}` and substitute (∗):
```
2^{S_{k+1}} n_{k+2} = 3·(2^{S_k} n_{k+1}) + 2^{S_k}
                    = 3·(3^k n_1 + Σ_{i=1}^{k} 3^{k−i} 2^{S_{i−1}}) + 2^{S_k}
                    = 3^{k+1} n_1 + Σ_{i=1}^{k} 3^{k+1−i} 2^{S_{i−1}} + 2^{S_k}.
```
The trailing `2^{S_k}` equals `3^{0}·2^{S_{(k+1)−1}}`, i.e. the `i = k+1` term, so the sum
extends to `Σ_{i=1}^{k+1}`. This is (∗) at `k+1`.

*Close the cycle.* Put `k = a` and use `n_{a+1} = n_1`, `S_a = d`:
```
2^{d} n_1 = 3^a n_1 + Σ_{i=1}^{a} 3^{a−i} 2^{S_{i−1}}  ⟹  (2^d − 3^a) n_1 = c.  ∎
```

---

## Lemma 2 (positivity forces `d ≥ D`)

For a cycle of positive integers, `2^d > 3^a`, hence
```
d ≥ D := ⌈ a · log₂3 ⌉ .
```

**Proof.** Each term of `c = Σ_{i=1}^{a} 3^{a−i} 2^{S_{i−1}}` is a product of positive
integers, so `c > 0`. By Lemma 1, `n_1 (2^d − 3^a) = c > 0` with `n_1 > 0`, so
`2^d − 3^a > 0`, i.e. `2^d > 3^a`. Taking `log₂`: `d > a·log₂3`. Because `a·log₂3` is
never an integer, the least integer `d` exceeding it is exactly `⌈a·log₂3⌉ = D`. ∎

(`Q := 2^d − 3^a ≥ 1` always, but the *size* of `Q`, not merely its non-vanishing, is what
matters below; see `reduction.md §2`.)

---

## Lemma 3 (`c` is maximised by pushing the partial sums as high as possible)

Over all feasible exponent sequences `0 = S_0 < S_1 < … < S_{a−1} ≤ d−1` (the constraint
`S_{a−1} ≤ d−1` holds because `v_a ≥ 1` gives `S_{a−1} = d − v_a ≤ d−1`),
```
c ≤ c_max(a, d) := 3^{a−1} + Σ_{i=2}^{a} 3^{a−i} · 2^{d−a+i−1} .
```

**Proof.** Each summand `3^{a−i} 2^{S_{i−1}}` of `c` has a fixed positive coefficient
`3^{a−i}` and is strictly increasing in its own exponent `S_{i−1}`; the summands share no
variable. So `c` is maximised by making each `S_{i−1}` as large as the constraints allow.

For `i = 1`, `S_0 = 0` is fixed. For `i ≥ 2`, the chain
`S_{i−1} < S_i < … < S_{a−1} ≤ d−1` (with `a−i` strict increments above `S_{i−1}`) forces
```
S_{i−1} ≤ d − 1 − (a − i) = d − a + i − 1 .
```
These individual maxima are *simultaneously attainable*: setting `S_{i−1} = d − a + i − 1`
for `i ≥ 2` gives consecutive integers `S_1 = d−a+1 < S_2 = d−a+2 < … < S_{a−1} = d−1`,
which is strictly increasing and stays above `S_0 = 0` (since `d ≥ D > a`, so
`S_1 = d−a+1 ≥ 2`). This assignment is feasible (it corresponds to `v_1 = d−a+1`,
`v_2 = … = v_a = 1`), so the term-by-term maximum is the true maximum:
```
c_max(a, d) = 3^{a−1}·2^{0} + Σ_{i=2}^{a} 3^{a−i}·2^{d−a+i−1}.  ∎
```

---

## Lemma 4 (`d = D` is the worst case)

For fixed `a`, the ratio `c_max(a, d) / (2^d − 3^a)` is strictly decreasing in `d` over
`d ≥ D`. Hence over all admissible `d` it is largest at `d = D`.

**Proof.** Set `x = 2^d`. Factor the sum part of `c_max`:
```
Σ_{i=2}^{a} 3^{a−i} 2^{d−a+i−1} = 2^{d−a} · Σ_{i=2}^{a} 3^{a−i} 2^{i−1} = (K / 2^a)·x ,
```
where `K := Σ_{i=2}^{a} 3^{a−i} 2^{i−1} > 0` is a constant (independent of `d`). Thus
```
c_max(a,d) = β + α·x ,   with  β = 3^{a−1} > 0,  α = K/2^a > 0 ,
```
and the ratio is `f(x) = (β + α x)/(x − 3^a)`. Differentiating,
```
f'(x) = [α(x − 3^a) − (β + α x)] / (x − 3^a)^2 = −(α·3^a + β) / (x − 3^a)^2 < 0
```
for `x > 3^a`. So `f` is strictly decreasing in `x`, and `x = 2^d` is increasing in `d`;
therefore the ratio strictly decreases as `d` grows and attains its maximum at the smallest
admissible value `d = D`. ∎

---

## Corollary (rigorous bound on the cycle minimum)

Let `m` denote the **minimum element** of a cycle with `a` odd-steps. Then
```
m ≤ M(a) := ⌊ c_max(a, D) / (2^D − 3^a) ⌋ ,   D = ⌈ a·log₂3 ⌉ .
```

**Proof.** Reading the cycle from its minimum element (`n_1 = m`), Lemma 1 gives
`m = c / (2^d − 3^a)` for the cycle's own total halving count `d`. By Lemma 2, `d ≥ D`.
By Lemma 3, `c ≤ c_max(a, d)`. By Lemma 4, `c_max(a,d)/(2^d − 3^a) ≤ c_max(a,D)/(2^D − 3^a)`.
Chaining,
```
m  =  c / (2^d − 3^a)  ≤  c_max(a, D) / (2^D − 3^a) .
```
Since `m` is a positive integer, it is at most the floor of the right-hand side, i.e.
`m ≤ M(a)`. ∎

**The computed constant.** `M(a)` is exactly the quantity `mbound` evaluated in
`collatz_convergents.w` (which computes `D` as the least exponent with `2^D > 3^a`,
forms `c_max(a,D)` by the closed form above, and takes the integer quotient by `2^D − 3^a`,
all in bignum). Its running maximum over `1 ≤ a ≤ 69` is
```
max_{1 ≤ a ≤ 69} M(a)  =  M(68)  =  4 394 687 298 972  ≈  4.39 × 10¹² ,
```
attained at `a = 68`. (For completeness: `M(67) = 977 094 711 835`,
`M(68) = 4 394 687 298 972`, `M(69) = 2 638 021 326 111`. Because `M(69) < M(68)`, the
running maximum does not increase from `a = 68` to `a = 69`; the bound `B` needed to clear
**both** is `M(68)`. The point `a = 68` is where `M` peaks inside the window `a ≤ 69`
because `c_max ~ 1.5^a` is still climbing while the gap `2^D − 3^a` happens to be locally
small there — it is *not* itself a continued-fraction convergent of `log₂3`; the genuine
deep convergents bracketing this range are `a = 41` and `a = 94`, where `M` is much smaller
and much larger respectively, so neither binds at `a ≤ 69`.) The first `a` whose bound
exceeds `4.5×10¹²` is `a = 70`, with `M(70) = 39 461 763 431 316 ≈ 3.95×10¹³`; that is why
the cutoff lands precisely at `a = 69`.

So for **every** `a ≤ 69`, a cycle's minimum element satisfies
`m ≤ M(a) ≤ 4 394 687 298 972 < 4.5×10¹²`.

---

## Computational input (machine-verified, not a hand proof)

> **Fact (descent certificate).** Every positive integer `n ≤ 4.5×10¹²` reaches `1` under
> the Collatz map.

This is a **finite computation**, not a theorem proved by hand — and it is the step that
makes the overall result *computer-assisted*. It was established by an exhaustive descent
certificate (`collatz_cert_hybrid.w`, run as a parallel fleet): for each odd
`3 ≤ m ≤ 4.5×10¹²` the program iterates the standard Collatz map until the value first
drops **below `m`**, certifying descent below the starting point. The range was composed
from two slices, `[1, 1.18×10¹²]` and `[1.18×10¹², 4.5×10¹²]`.

Descent-below-self for all `m ≤ B` yields "reaches 1 for all `n ≤ B`" by strong induction:
`1` and `2` reach `1` directly; for any `n ≤ B`, the trajectory descends to some `n' < n`
(`n' ≤ B`), which reaches `1` by the induction hypothesis. The certificate runs the
unboxed-`i64` map for speed and re-verifies in exact bignum exactly those `m` whose
trajectory peak could approach `2^63` (it flags them *before* any overflow can occur), so
no silent wraparound is possible — the computation is sound. (Soundness here rests on the
certificate program being correct; that is the standard trust assumption of any
computer-assisted proof, and the natural target of adversarial review.)

Because `4 394 687 298 972 < 4.5×10¹²`, the certified range strictly covers every `M(a)`
for `a ≤ 69`, with margin ≈ `1.05×10¹¹`.

---

## Proof of the Theorem

Suppose, for contradiction, a **nontrivial** Collatz cycle exists with `a ≤ 69` odd-steps.
Let `m` be its minimum element (an odd positive integer). By the Corollary,
```
m  ≤  M(a)  ≤  max_{a ≤ 69} M(a)  =  4 394 687 298 972  <  4.5×10¹² .
```
By the computational Fact, every integer `≤ 4.5×10¹²` reaches `1`; in particular the
trajectory starting at `m` reaches `1`.

But `m` lies in a cycle, so its forward trajectory is periodic and visits only the cycle's
elements. A *nontrivial* cycle does not contain `1` (the only cycle containing `1` is the
trivial one). Hence the trajectory from `m` never reaches `1` — contradicting the previous
paragraph.

Therefore no nontrivial cycle with `a ≤ 69` exists, and the only such cycle is the trivial
`{1}`. ∎

*(Remark on which "minimum" is meant. The minimum element of a standard-map Collatz cycle
is necessarily odd — an even minimum would be followed in the cycle by its half, which is
smaller — so it coincides with the minimum odd element, i.e. the minimum of the
corresponding shortcut-map cycle. The certificate runs the standard map; Lemmas 1–4 use the
shortcut map; the two agree on this minimum element, so the bound and the certificate
address the same number `m`.)*

---

## Scope and what this does NOT prove

This is a narrow, bounded, computer-assisted result. Four explicit caveats:

1. **The parameter is odd-steps, not the literature's axis.** Here `a` counts **odd-steps**
   (the number of `3x+1` operations). This is **not** the parameter of Simons–de Weger
   (2005), whose `m ≤ 68` counts **blocks of consecutive odd integers** (local minima) in
   the orbit. Since each block contains at least one odd-step, `m ≤ a`, so their `m ≤ 68`
   covers cycles with *arbitrarily many* odd-steps (as long as those odd-steps fall into
   ≤ 68 blocks) — vastly more than any odd-step cutoff. Our `a ≤ 69` adds only the thin
   sliver of cycles whose odd-steps sit in that many *separate* blocks, and misses
   everything they cover with long runs. This result **covers far fewer cycles in
   aggregate than Simons–de Weger and is formally incomparable to it** (neither result's
   covered set contains the other); it is **not** an improvement on the literature.
   (See `reduction.md §2` and `baker_bound.md §4`.)

2. **It is bounded, not universal.** The theorem covers `a ≤ 69` only. The general
   no-cycle statement (all `a`) is **open**: the min-element bound `M(a)` grows like
   `2^{0.585 a}` (it is astronomically large at the deep convergents of `log₂3`, e.g.
   `a = 94`), so finite verification can never reach all `a`. Closing the general case needs
   an effective lower bound on `|2^d − 3^a|` of Baker/Rhin strength — far beyond the
   elementary input used here (`reduction.md §2`, `baker_bound.md`).

3. **It says nothing about divergence.** Collatz = (NO-CYCLE) **and** (NO-DIVERGENCE). This
   document attacks NO-CYCLE only, and only its bounded part. It gives **no** information
   about whether some trajectory grows without bound; no quantity here is shown to decrease
   monotonically (`reduction.md §3`).

4. **It depends on a finite computation.** The "every `n ≤ 4.5×10¹²` reaches 1" input is a
   machine certificate, not a hand argument. The result is therefore **computer-assisted**:
   its validity is contingent on the correctness of that computation (and of the bignum
   arithmetic computing `M(a)`).

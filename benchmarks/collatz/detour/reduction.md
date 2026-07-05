# What a Collatz proof would actually require — the honest reduction map

This documents exactly what has been reduced to what, what is elementary, and where the
two genuinely hard kernels are. Short version: **Collatz is *not* reducible to
`2^d ≠ 3^a`.** That fact is trivially true and only necessary-not-sufficient for one of
the two halves.

## 0. The conjecture is two independent halves

For every positive integer `n`, the Collatz map reaches 1 ⟺ **both**:

- **(NO-CYCLE)** no nontrivial periodic orbit exists, and
- **(NO-DIVERGENCE)** no trajectory grows without bound.

A counterexample is one or the other. Excluding cycles tells you nothing about
divergence, and vice versa. Everything in this directory (the cycle equation, the
descent certificate, A≤69) attacks NO-CYCLE only.

## 1. `2^d ≠ 3^a` is true, trivial, and not the reduction

`2^d = 3^a` is impossible for integers `a,d ≥ 1` by unique factorisation (a number cannot
be both a power of 2 and a power of 3). Equivalently `log₂3 = d/a` would make `log₂3`
rational; it is not. This is a one-line theorem.

> Meta-check: if Collatz reduced to a one-line theorem, Collatz would be a one-line
> theorem. It is famously open. So this reduction is false — there is a gap.

What `2^d ≠ 3^a` actually buys: in the cycle equation below it makes the coefficient
`Q = 2^d − 3^a` nonzero, so a cycle cannot close "for free." Necessary, not sufficient.

## 2. NO-CYCLE reduces to a *quantitative* bound on `|2^d − 3^a|` (Baker), not to `Q ≠ 0`

A nontrivial cycle of the shortcut map with `a` odd-steps and `d` halvings, minimum odd
element `m`, satisfies (proved in `collatz_convergents.w`):

```
m · (2^d − 3^a) = c,     3^a − 2^a ≤ c < 3^a · 2^(d−1),     d = ⌈a·log₂3⌉ is the worst case.
```

So `m ≤ c_max / |Q|`. To exclude a cycle you force `m` below a verified bound `B` (then
verification kills it, since all `n ≤ B` are known to reach 1) or show it is non-integral.

**The obstruction.** At convergents `d/a` of `log₂3`, `|Q| = |2^d − 3^a|` is exponentially
small relative to `3^a`, so `m ≤ c_max/|Q|` is astronomically large and escapes any
feasible `B`. `Q ≠ 0` is worthless here. What is needed is a **lower bound**

```
|2^d − 3^a| ≥ (explicit function of a),
```

i.e. an effective irrationality measure for `log₂3` — a **linear-forms-in-logarithms /
Baker** result. This is vastly deeper than `≠ 0`.

**Even Baker does not finish.** The state of the art gives `|Q| ≳ 3^a / a^κ` (polynomial
loss). Plugging in, `m`'s upper bound is still `≳ 2^{(log₂3 − 1)·a} = 2^{0.585a}` — it
*grows exponentially in `a`*. So Baker-type bounds + verification kill every **bounded**
case but leave infinitely many open. **The general NO-CYCLE statement is itself an open
problem**, reduced to a *sharper-than-known* effective bound on `|2^d − 3^a|`.

> **Parameter caution (this is the easy thing to get wrong).** The published results count
> a *different* quantity than this repo. Steiner (1977) excluded the single-**circuit**
> cycle (one odd-run + one even-run; the only positive one is `{1,2}`). Simons–de Weger
> (2005) excluded **m-cycles for `1 ≤ m ≤ 68`**, where `m` = the number of **local minima**
> = blocks of consecutive odd integers in the orbit (later extended to `m ≤ 75`), using
> **Rhin's (1987)** linear-forms-in-logs measure plus computation — *not* verification to
> some bound. Since each odd-block contains ≥ 1 odd-step, `m ≤ a` (blocks ≤ odd-steps), so
> their `m ≤ 68` covers cycles with **arbitrarily many** odd-steps (as long as they fall in
> ≤ 68 blocks) — far more than any odd-step bound. **This repo's `a ≤ 69` is in odd-steps**,
> a different and weaker-coverage axis: it adds only the thin sliver of cycles whose 69
> odd-steps sit in 69 separate blocks, and misses everything S–dW covers with long blocks.
> It is **not comparable to, and not an improvement on, Simons–de Weger.**

## 3. NO-DIVERGENCE is not reduced to anything

The log-jump identity (one merged step moves `log₂n` by `+log₂3` per odd-step, `−1` per
halving): over a whole trajectory with `A` odd-steps and `D` halvings,

```
log₂(n_final) − log₂(n₀) = A·log₂3 − D.
```

Reaching 1 needs `D ≈ A·log₂3 + log₂(n₀)`; divergence needs `D/A < log₂3` to persist
forever. Heuristically the halvings-per-odd-step `v_i` average 2 > `log₂3 ≈ 1.585`, so the
multiplicative drift per odd-step is `≈ 3/4 < 1` and trajectories "should" shrink. But:

- this is a statement about *averages* of a pseudo-random parity sequence;
- there is **no known quantity that provably decreases** (no Lyapunov / descent function);
- `2^d ≠ 3^a` says nothing about boundedness.

No reduction of NO-DIVERGENCE to any Diophantine fact is known. This is the harder half.

## 4. Bottom line

| question | status |
|---|---|
| Reduced to `2^d ≠ 3^a`? | **No** — that's trivially true; it would trivialise an open problem |
| NO-CYCLE | reduced to an **effective lower bound on `|2^d − 3^a|`** (Baker territory); known bounds finish only bounded `a`, so still open in general |
| NO-DIVERGENCE | **not reduced** to anything; needs a descent function nobody has found |
| What this repo proves | NO-CYCLE for `a ≤ 69` **odd-steps** (a weaker axis than the literature's `m ≤ 68` *odd-blocks* — see §2), elementarily: verification to `B=4.5×10¹²` + the `c_max/Q` bound |

The elementary lever (verification) raises the `a`-cutoff but never reaches "all `a`," and
touches NO-DIVERGENCE not at all. A proof needs new mathematics on both halves — not the
irrationality of `log₂3`, which we already have.

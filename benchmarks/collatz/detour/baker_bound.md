# The Baker-bound lever for cycle exclusion — what it gives, and what it would take

`reduction.md` showed the NO-CYCLE half reduces not to `2^d ≠ 3^a` (trivial) but to a
*quantitative* lower bound on `|2^d − 3^a|`. This note records, with sources, exactly what
the available bounds give — and is honest that the repo's `a ≤ 69` does **not** use them and
does **not** reproduce the literature's `m ≤ 68`.

## 1. The cycle constraint is a linear form in two logarithms

Set `Λ = d·ln 2 − a·ln 3`. Then, exactly,

```
2^d − 3^a = 3^a · (e^Λ − 1),      and for small |Λ|,   |2^d − 3^a| ≈ 3^a · |Λ|.
```

A cycle "almost closes" precisely when `Λ` is tiny, i.e. when `d/a` is an excellent rational
approximation to `log₂3` — the convergents (Part G). So lower-bounding `|2^d − 3^a|` is the
same as lower-bounding `|Λ|`: an **effective irrationality / linear-forms-in-logs** problem.

## 2. The explicit bound (Matveev, real case, two logs)

Matveev (2000), real-field case, for `Λ = b₁ log η₁ − b₂ log η₂` with `η₁,η₂` mult.
independent, `B = max(|b₁|,|b₂|)`:

```
log|Λ| > − 1.4 · 30^(l+3) · l^4.5 · D² · (A₁ A₂) · (1 + log D) · (1 + log B),   l = 2.
```

Specialize `η₁=2, η₂=3`, `D=1`, `A_j ≥ max{ h(η_j), |log η_j|, 0.16 }`, so `A₁ = log 2`,
`A₂ = log 3`. The coefficient becomes (order of magnitude — **recompute before quoting in a
paper**)

```
1.4 · 30^5 · 2^4.5 · (log 2)(log 3) · 1 · 1  ≈  5.9 × 10⁸,
```

giving `log|Λ| > −5.9×10⁸ · (1 + log B)`, hence

```
|2^d − 3^a|  ≳  3^a · exp(−5.9×10⁸ · (1 + log a))  =  3^a · a^(−~5.9×10⁸).
```

A *polynomial-in-a* deficit against the `3^a` factor — but with an astronomically large
exponent. (Source: Matveev, Izv. Math. 64:6 (2000) 1217–1269; canonical restatement in
arXiv:2202.13182 Thm 2.2. Constant `5.9×10⁸` is our arithmetic from that formula.)

**Sharper, specialized:** Simons–de Weger did not use the generic Matveev constant; they used
**Rhin's (1987)** measure tailored to `log 2, log 3`, which is far tighter and is what makes
their computation finite. (Rhin, *Approximants de Padé et mesures effectives d'irrationalité*,
Progr. Math. 71 (1987) 155–164.)

## 3. What this does and does not accomplish

- **Does:** prove `|2^d − 3^a|` cannot be "too small" relative to `3^a` — the exact
  non-degeneracy `reduction.md §2` asked for, far beyond `Q ≠ 0`. This is the genuine content.
- **Does not, by itself, bound short cycles usefully:** the deficit `a^(−5.9×10⁸)` is so weak
  that the implied min-element bound `m ≲ 2^{0.585a}·a^(5.9×10⁸)` still → ∞. The bound caps the
  cycle *length* only when combined with the cycle's combinatorial structure.

## 4. How the literature actually closes the finite part (and why ours is different)

Simons–de Weger parameterize a cycle by `m` = number of **blocks of consecutive odd integers**
(local minima), `m ≤ a`. Rhin's measure caps how well `d/a` can approximate `log₂3`, which
caps `m`; they then **enumerate the admissible symbol sequences** for each small `m` and clear
the finite remainder by computation, getting **no nontrivial `m`-cycle for `1 ≤ m ≤ 68`**
(later `≤ 75`). Steiner (1977) is the `m = 1` case.

This repo does something **weaker and different**: it excludes cycles by the number of
**odd-steps** `a` (not blocks `m`), via direct descent verification to `B = 4.5×10¹²` plus the
elementary `m ≤ c_max/Q` bound — **no Baker/Rhin input at all**. Because `m ≤ a`, the `m ≤ 68`
result covers cycles with arbitrarily many odd-steps, which our `a ≤ 69` does not. The two are
not comparable, and ours is the smaller-coverage one.

## 5. So what *would* "build the Baker engine" mean here?

A faithful reproduction would require: (i) implement Rhin's (or a good Matveev) lower bound for
`|d log2 − a log3|` as a verified numeric routine; (ii) derive the resulting cap on `m`; (iii)
enumerate admissible odd-block symbol sequences up to that cap and check each has no
positive-integer cycle. Steps (i)–(ii) are tractable; (iii) is the substantial, careful part.
That is a real project — and it would still only reach *bounded* `m`, never all of NO-CYCLE,
and never touch NO-DIVERGENCE. The honest ceiling of this entire direction is unchanged.

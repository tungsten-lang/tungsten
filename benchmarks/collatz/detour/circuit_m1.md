# Steiner's single-circuit (m=1) Collatz result — the bounded computational content

A "circuit" (Davison 1976, Steiner 1977) is a Collatz cycle with a **single local
minimum**: an ascending run of `k` odd-steps (each `n → (3n+1)/2`, i.e. halving-exponent
`v=1`) followed by one descending run of `l` halvings. Such a circuit-cycle on the
positive integers corresponds to a positive-integer solution `(k,l,h)` of

```
(2^(k+l) − 3^k) · h = 2^l − 1 ,      k ≥ 1, l ≥ 1, h ≥ 1.
```

> **Steiner (1977).** The only positive solution is `(k,l,h) = (1,1,1)` — the trivial
> cycle `{1,2}`. (His proof uses Baker's linear forms in logarithms; see "Scope".)

`circuit_m1.w` reproduces the **bounded, computational** half of this: it sweeps
`k = 1 … K` and, for each `k`, tests the at-most-one candidate `l` allowed by the
constraints below. It finds **only** `(1,1,1)`.

## The equation is the cycle-minimum integrality condition

Sanity check: `(1,1,1)` gives `(2² − 3¹)·1 = 1 = 2¹ − 1` ✓.

`h` is not a free symbol — it is tied to the cycle minimum. The general shortcut-cycle
equation (`proof.md`, Lemma 1) makes the minimum odd element `n₁ = c / Q` with
`Q = 2^(k+l) − 3^k` and, for the single-circuit symbol pattern, `c = 3^k − 2^k`. The
exact algebraic identity

```
(2^l − 1)·2^k  =  (3^k − 2^k) + Q
```

(a one-line algebraic identity: `(3^k − 2^k) + Q = 3^k − 2^k + 2^{k+l} − 3^k = 2^{k+l} − 2^k
= 2^k(2^l − 1)`) shows, since `Q` is odd so `gcd(2^k, Q) = 1`, that

```
Q | (2^l − 1)   ⟺   Q | (3^k − 2^k),     and then    n₁ = 2^k · h − 1.
```

So testing the given equation is exactly testing integrality of the circuit's minimum
element `n₁`; the program's `h` and the minimum are related by `n₁ = 2^k h − 1`
(for `(1,1,1)`: `n₁ = 2·1 − 1 = 1` ✓).

## The two constraints that bound the search (both from the equation)

- **Positivity** — the divisor must be a positive integer (so `Q·h = 2^l−1 > 0` with
  `h ≥ 1`):
  ```
  2^(k+l) > 3^k    ⟺    2^l > (3/2)^k .                       (lower bound on l)
  ```
- **`h ≥ 1`** — forces the divisor below the right-hand side:
  ```
  2^(k+l) − 3^k ≤ 2^l − 1  ⟺  2^l·(2^k − 1) ≤ 3^k − 1
                            ⟺  2^l ≤ (3^k − 1)/(2^k − 1) .     (upper bound on l)
  ```

Together, for each `k`, `2^l` must lie in

```
( (3/2)^k ,  (3^k − 1)/(2^k − 1) ] .
```

The ratio of the two ends is `(1 − 3^(−k)) / (1 − 2^(−k))`, which is in `(1, 4/3]` for
every `k ≥ 1` (and → 1). A factor below 2 means the interval contains **at most one
power of two** — so each `k` has **at most one candidate `l`** to test (this is forced by
the `≤ 4/3 < 2` ratio above, not an empirical observation). For that candidate the test is just: does
`Q = 2^(k+l) − 3^k` divide `2^l − 1` exactly, with positive quotient `h`? This is the
"does a power of 2 fall in the interval, and does it close the cycle" question, decided
here by direct bignum arithmetic.

## What the program does and reaches

For each `k` it carries the smallest admissible `l` forward (the threshold only rises with
`k`, since `3^k` outruns `2^k`), so the whole sweep is `O(K)` bignum doublings rather than
`O(K²)`. All values are plain `Int` (auto-promoting to bignum — `3^100000` has ≈ 47 700
digits); run **interpreted**, because the interpreter handles plain `Int`/bignum while
compiled bignum can be unreliable and `## i64` / `i64[]` are not dispatched interpreted.

```
bin/tungsten benchmarks/collatz/detour/circuit_m1.w
```

**Bound reached: `K = 100000`** (≈ 2.6 s). Output:

```
Steiner m=1 (single-circuit) Collatz cycle exclusion -- bounded computational sweep
equation: (2^(k+l) - 3^k) * h = 2^l - 1,   k,l,h >= 1   (only positive soln: 1,1,1)
sweeping k = 1 .. 100000   (plain Int / bignum, interpreted)

  SOLUTION  (k,l,h) = (1,1,1)   check (2^(k+l)-3^k)*h = 1 = 2^l-1 = 1
  ... swept through k=20000, solutions so far: 1
  ... swept through k=40000, solutions so far: 1
  ... swept through k=60000, solutions so far: 1
  ... swept through k=80000, solutions so far: 1
  ... swept through k=100000, solutions so far: 1

summary: swept k = 1 .. 100000
  total positive-integer (k,l,h) solutions found: 1
  unique solution is (1,1,1) -- the trivial circuit {1,2}, as Steiner (1977) proved.
  bounded computational content only; the all-k result needs Baker (see baker_bound.md).
```

So over `1 ≤ k ≤ 100000` the **only** positive-integer `(k,l,h)` solution is `(1,1,1)`.

## Scope and what this does NOT prove

1. **This is the BLOCK axis `m=1`, not the odd-step axis of `proof.md`.** `m` counts
   **blocks of consecutive odd integers** (local minima) — Simons–de Weger's (2005)
   parameter, who excluded `m`-cycles for `1 ≤ m ≤ 68` (later `≤ 75`); Steiner (1977) is
   their `m = 1` base case. A single-circuit cycle has exactly one local minimum but may
   have **arbitrarily many odd-steps `k`**. This is **distinct from and complementary to**
   `proof.md`, which bounds the **odd-step** count `a ≤ 69` by descent verification.
   Neither result's covered set contains the other (see `reduction.md §2`,
   `baker_bound.md §4`).

2. **This is the bounded computational content only.** The program decides `m=1` exclusion
   for `k ≤ 100000` by exact arithmetic — it confirms no power of two falls in the closing
   interval for any such `k`. The **all-`k`** statement is **Steiner's theorem** and needs
   the analytic input the sweep cannot supply: a Baker-type lower bound on
   `|2^(k+l) − 3^k|` (equivalently on `|（k+l) log 2 − k log 3|`) ruling out a closing
   power of two for **every** `k`. That is the genuine mathematics; see `baker_bound.md`.
   No amount of sweeping reaches all `k`.

3. **It reproduces a known 1977 result — not new mathematics.** This is a runnable,
   bignum re-derivation of the finite/computational shadow of Steiner's theorem (and of the
   `m=1` case of Simons–de Weger). It adds confidence and a clean Tungsten demonstration of
   the circuit equation and its constraints; it does **not** extend, sharpen, or
   independently establish the theorem, and it says **nothing** about NO-DIVERGENCE
   (`reduction.md §3`).

# Self-validating cycle search — and an independent witness for Lemma 1

`cycle_search.w` finds every `3n+1` shortcut-map cycle with an element of magnitude
`≤ R` (`R = 20000`), over **both signs**, in ~1.9 s (plain `Int`/bignum, interpreted).

## Why both signs: the negative cycles are a test oracle

The `3n+1` map has genuine **nontrivial cycles over the negative integers**. A correct
search must recover them; if it doesn't, it is broken — which is a far stronger check than
the unfalsifiable "found nothing" of a positive-only search. The run recovers exactly:

| cycle | `a` (odd-steps) | `m` (descents, `wᵢ≥2`) | Lemma 1 |
|---|---|---|---|
| `{1}` (trivial, +) | 1 | 1 | `1·(2²−3¹)=1=c` ✓ |
| `{−1}` | 1 | 0 | `−1·(2¹−3¹)=1=c` ✓ |
| `{−5,−7}` | 2 | 1 | `−5·(2³−3²)=5=c` ✓ |
| `{−17,−25,−37,−55,−41,−61,−91}` | 7 | 2 | `−17·(2¹¹−3⁷)=2363=c` ✓ |

…and **no nontrivial positive cycle** for `|element| ≤ 20000` (only `{1}`).

## Method

From each odd `n0`, iterate `n → (3n+1)/2^w`. Stop when `|n| < |n0|` (then `n0` is not its
cycle's minimum-magnitude element — it will be reported from that smaller one) or when
`n == n0` (a cycle, with `n0` its canonical min-magnitude representative — report once).
Positive starts descend below themselves (Collatz) and only `{1}` closes; negative starts
fall into one of the three classical negative cycles. Each cycle is printed once, with its
orbit, `a`, `m`, and a re-derivation of `d` and `c = Σ 3^{a−i} 2^{S_{i−1}}` to check
`proof.md` Lemma 1 `n0·(2^d − 3^a) = c`.

## What this is good for (the real value)

It is an **independent witness for `proof.md`'s Lemma 1**. The positive integers have no
nontrivial cycle to test the cycle equation against; the negatives do, and Lemma 1 holds on
all of them to the digit. That a sign error or off-by-one in the equation would break (e.g.)
`−17·(2¹¹−3⁷)=2363` makes this a real cross-check of the proof's foundation — not just a
reproduction. It also exhibits the **block axis** concretely: live cycles with `m = 0, 1, 2`
descents, the same `m` Simons–de Weger bound to `≤ 68`.

## Scope and what this does NOT prove

1. **Bounded by element magnitude, not by `a` or `m`.** Covers `|element| ≤ 20000`. A cycle
   whose smallest element exceeds that escapes the search (raising `R` is linear-ish but, as
   always, never reaches all integers).
2. **Reproduces known facts.** The four cycles are classical (the three negative ones are
   long known; `{1}` is trivial). This adds confidence and a Lemma-1 cross-check; it does not
   discover or prove anything new.
3. **Says nothing about divergence**, and nothing about cycles of large minimum element
   (positive or negative). The general no-cycle problem — both signs — is open
   (`reduction.md §2`).

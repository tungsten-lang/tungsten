# Native seed feedback and constructive backtracking

The exact price materializer now tries other block/Kronecker decompositions
when an earlier price-compatible branch has no witness. This recovers 16
previously failing constructions in the saved dimension-32 grid. Subsequent
exact matrix cleanup gives **19x27x28 at rank 8129**, versus retained 8169.
It remains above the saved public comparison of 7983: this is a local bound
improvement, not a world record or a fresh worldwide comparison.

The preceding matched native-seed experiment found no new bound. Its outcome
does not justify changing live-fleet defaults. Both investigations are
automated finite studies; no winning equation was manually edited.

## Fix: search the constructive alternatives

`MetaflipCheckedPriceLibrary` previously took the first block or Kronecker
decomposition whose component *prices* sum/multiply to the requested price.
If a component had no checked construction, its exception escaped immediately.
The other compatible decompositions were never tried.

The library now raises a specific `MissingConstruction` for that condition,
backtracks only on this class, and memoizes failed shapes. Source membership
is copied at construction time so caller mutation cannot invalidate the
memoized search graph. Block/product dependencies strictly decrease volume.
The public `scheme` call still requires an exact construction at the requested
rank. It does not turn a rank number into a leaf or silently substitute a
higher-cost witness.

Bad source hashes, malformed tensors, full tensor-identity failures and valid
tensors at the wrong advertised rank remain fatal. They are not missing
alternatives and are never rescued by the new branch search. The original
`verify_sources_unchanged!` audit remains required after materialization.

This is an offline Ruby materializer improvement, not a new Ruby dependency
inside `bin/metaflip` or a change to the native refinement worker.

## Recovered witnesses and a real cleanup gain

The saved table contains 5,984 canonical shapes through dimension 32 and
33,320 source metadata rows. A bottom-up reachability screen predicts 3,103
constructible prices with first-choice-only recursion versus 3,119 with
backtracking. Metadata alone is not admission: all **16 additional outputs**
were then fully materialized, tensor-checked and independently replayed.
For example:

```
5x6x26 / 556:
  first compatible split  = 5x6x6 + 5x6x20  (missing component witness)
  successful alternative = 5x6x8 + 5x6x18
```

These sixteen prices were already in the numerical comparison table. Their
materialization is not sixteen numerical improvements. The previously pending
15x23x23/r4778 still fails: neither 15x15x23/r3042 nor its reported restriction
source 15x15x24/r3042 has a recovered witness in this input library. That price
remains excluded; backtracking does not weaken the verifier to accept it.

Applying exact shared-factor matrix compression to the 16 recovered outputs
produces one rank reduction: 19x27x28, **8169 -> 8129**. An independent
row-equation implementation reproduces all 40 matrix reductions and the
complete output tensor. The largest factor width is 756 bits, so this is
offline wide-tensor work, not an ordinary 63-bit worker seed.

The final tensor SHA-256 is
`59650ad20e457c4f09ee79293bdadbc5b816163057a081b69e78bb0e37c268ce`.
The 40 one-term savings occur in fixed-factor groups of sizes 3..7, rather
than merely removing duplicate triples. The other fifteen materialized
outputs do not decrease under this cleanup.

Both old and augmented price tables were closed under coordinate restriction,
block sums and Kronecker products through dimension 32. Each block/product
pass agrees with a separately implemented recurrence. There are 158 baseline
reclosures in both tables, none credited as new. The only added numerical
gain is 19x27x28/8129; no additional propagated improvement or reference
crossing appears.

All 74 single-coordinate deletions of this parent completed with full Ruby
tensor checks. The three best target representatives were independently
reprojected, matrix-compressed and fully tensor-checked:

| Shape | Best projected rank | Retained bound |
|---|---:|---:|
| 18x27x28 | 7919 | 7443 |
| 19x26x28 | 7867 | 7805 |
| 19x27x27 | 8026 | 7847 |

These are negative finite-family results, not projection optimality proofs.
Only the three retained winners—not the generation minimum over all 74—were
independently reproduced.

## Matched native-refinement seed feedback

The [previous control](ALIGNED-CONTINUATION-AUDIT-2026-09-09.md) established
that native refinement already matches the selected grid-alignment gains.
This study uses the source plus every same-shape output of that actual native
refinement job. It compares three deterministic experimental seed rules:

- `pair`: minimum primitive rank, maximum pair count, then density/identity.
- `priced`: minimum exact context price, then rank/density/identity.
- `portfolio`: start with `priced`; select up to four same-rank candidates
  by farthest full-term-set distance, with a two-singleton price-slack limit;
  round-robin the selected candidates.

The pair rule is an experimental baseline, not a claim that it duplicates
every live seed scheduling tie. Pair count is not composition cost: one
4x5x7/r104 source has 20 pairs and price 726, whereas a native variant with
19 pairs has price 724 at scale 2x2x2.

Four cells, two modes (`walk`, `anneal`), three arms and sixteen paired trials
use equal flip/observation budgets: 256 chunks x 16,384 attempts, observation
every 2,048, debt two, density slack eight, 50,000 packing states. Arm order
rotates per trial. Each trial is a fresh native invocation; it prices its
starting tensor once. Total: **1,610,612,736 attempts / 786,816 evaluations**.
The starting seed families were precomputed once and shared by all arms;
the flip budgets are matched, not isolated elapsed-time measurements.

At 8x10x14, `priced` preserves retained 724 in 32/32 trials, compared with
5/32 for `pair` and 12/32 for `portfolio`. This is better selection of an
already-known starting construction, not 32 fresh discoveries. Results on
the other cells are mixed; the diverse portfolio yields no broader gain.
The two cells with identical `pair`/`priced` seeds reproduce byte-identical
winner and endpoint outputs in all 64 control trials.

The 768 output occurrences deduplicate to 471 parents. Including inputs and
three exact matrix-cleanup outputs gives 489 distinct parents, priced in all
63 nonidentity scales in {1,2,3,4} cubed: 30,807 contexts, no fallback in this
offline repricing. Neither `priced` nor `portfolio` improves the pair arm's
best target table. No main-cube rank or retained composition bound improves
from this flip study.

The recent flip/refinement cohort is now **4,286 distinct parents and
215,226 distinct parent-context pairs**. The separately recovered wide
constructions and coordinate-deletion experiment are not silently added to
that cohort. Keep 19x27x28/8129 in future retained comparisons to avoid
crediting it again.

## Focused checks and evidence

`checked_price_library_test.rb`: 10 tests / 547 assertions. It covers missing
first/later blocks/products, memoized failures, caller-mutation isolation,
source corruption and wrong-rank failures, and sixteen randomized small grids
against an independent bottom-up reachability recurrence. The three original
targeted backtracking regressions fail before the fix. The focused
`composition_closure_test.rb` also passes, 7 tests / 226 assertions.

The independent search checker validates every output tensor, all saved
winner scores, leaf binding, seed selection, counters and identical-seed
controls. Four transient native packing fallbacks occurred, but all retained
winner scores equal the independent exact restricted objective. Twelve
selected compositions pass independent substitution and full-tensor checks.

The recovery study independently checks all 16 materialized outputs, the
cleanup of all 16 and the reduced tensor; it never relies on source hashes
alone. A relocated replay reconstructs all recovered outputs from archived
source witnesses and reruns the price/identity/counter checks. No billion-flip
rerun is needed for cold evidence verification.

Evidence is outside the checkout at
`~/.local/share/tungsten-metaflip/evidence/2026-09-10-feedback-backtracking.tar.gz`.
The archive is 24,412,118 bytes, SHA-256
`8c988c49646c5d72fca49bf07f12e1331a3bb5affece4bd876ab0d8bd03cf84c`.
All 2,548 payload hashes were verified from the sealed archive, including the
completed cold-replay reports. No bulk benchmark files, canonical seed
promotion, live GPU worker or publication is part of this change.

The next useful integration target is bounded cleanup of wide composition
outputs, plus explicit constructive alternatives in price materialization.
The new wide-parent example is a replayable acceptance regression for that
work. More pair-count routing or raw grid-alignment variants are not justified
by the matched runs alone.

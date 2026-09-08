# Composition observers with explicit source lineage

The bounded follow-up independently expands three more GF(2) local improvements.
None is a new reference crossing, a primitive/main-square rank improvement, or
a confirmed world record.

| Shape | Previous local | Checked construction | Pinned reference screen |
| --- | ---: | ---: | ---: |
| 16x18x30 | 4836 | 4833 | 4833 |
| 18x20x24 | 4836 | 4833 | 4676 |
| 17x18x30 | 5375 | 5373 | 5104 |

All three are new to the preceding bounded improvement cohort. Its deduplicated
total is **258 lower-local-price shapes**, with **21 expanded outputs and 237
unexpanded recipes**. The scoped reference-crossing shortlist remains **42**.
These are not confirmed records or the separate historical campaign tally.
The mixed-field screening references are previously pinned, not freshly
revalidated; they never supply unchecked constructive leaves.

## Admission improvement

`extend_composition_parents.py --observer-walk` now retains an `origin` for
every occurrence in `admissions.json`: row/cell, source path and digest,
source/winner/endpoint/observer role, trial, and observer number where applicable.
The report digest and existing full-tensor audit still bind admission. Identical
tensors retain all reported occurrences, even across different cohorts or
observers; the parent corpus still deduplicates only exact oriented literal
identities, not ranks or bucket signatures.

Producer-supplied labels and indices are explicitly named `reported_cohort` and
`reported_parent_index`. They are not inferred or independently proven ancestry.
`observer_walk_entries` provides the same enumeration to offline selectors;
it is not an audit or an admission gate by itself.

This fixes an actual selection failure: append indices after the projection
stage also included descendants of earlier controls. The first selector
incorrectly called five 4x5x5 seeds projected because their indices were high.
Its original report remains unchanged. The correction traces exact source
tensors to audited coordinate images, including the necessary dimension
permutation, and then to each retained walk report location. It replaces only
those five slots. A tensor shared by multiple report locations keeps every
origin; neither the cohort label nor a corpus index defines state identity.

Focused tests cover duplicate locations, conflicting reported cohorts,
high-index controls/low-index projections, source links, trial/observer roles,
rank-only endpoints, and unchanged literal deduplication. The four focused
modules pass **33 tests**:

```sh
cd benchmarks/matmul/metaflip
nice -n 10 python3 -B -m unittest test_verify_observer_walk \
  test_extend_composition_parents test_projection_variant_portfolio \
  test_projection_composition_scan
```

## Bounded search and correction

The frozen-context screen considered the three previously useful families.
4x4x6 had no qualifying new-reference context within eight pair discounts and
was not walked. For 4x5x5 and 4x5x6, respectively, it selected eight and four
distinct proportional-price objectives through side 32, prioritizing proximity
to the pinned reference and reuse across larger shapes. This is a bounded
selection heuristic, not state dominance or exhaustive coverage.

The corrected cohort has eight seeds per family: the previous construction
witness, five other source-traced projected descendants/images, and two
earlier-corpus controls. Each receives 32 trials, 64 chunks, 65,536 attempted
moves per chunk, debt two, density slack four, RNG 912251, and read-only
observations every 2,048 moves. The primary objective remains rank.

The first 16-cell run used **2,147,483,648 attempts**. Correcting five slots
cost another **671,088,640 attempts** with identical contexts, limits, work,
and RNG; the other eleven cells are reused explicitly, not rerun or counted
as new work. Total executed work is **2,818,572,288 attempts**. All work was
sequential at low priority, CPU only; no GPU/fleet stress run was launched.

In the corrected cohort, observer minima beat the saved rank-winner minima
on **52 of 96 seed/objective comparisons**. No selected context crosses its
reference. This same-trajectory comparison supports retaining sidecars; it
does not establish a throughput advantage or a strategy win rate between
unequal seed cohorts.

Independent replay checks 1,722 tensors / 147,277 terms / 2,453,694 support-pair
XORs in the first run, and 636 / 48,336 / 675,849 in the replacement run.
Those are per-run counts, not a deduplicated combined tensor count.
Admission preserves **5,717 origin occurrences**, adding **2,317 literal
parents** to the 26,480-parent corpus for **28,797** total. All first-run tensors
remain eligible after correcting their interpretation; mislabeling did not
invalidate the tensors. Full bounded recomposition evaluates 2,409,442 ordinary
and 525,302 retained mixed expressions, producing the three prices above.

## The useful representation

Both direct products use a rank-90 4x5x6 parent with 72 singleton U buckets and
nine U pairs. The formula is

```
72 * R(3,4,6) + 9 * R(4,6,6) = 72 * 54 + 9 * 105 = 4833.
```

Its SHA-256 is
`81b6ad529fc63175bed1d60f3e53ea6daad7b6c9d98164bdac75c6d19b1b349d`.
It appears as observers 0 and 2 of trial 0, cell `1-0` in the first run, not
as that trial's saved rank winner or endpoint. It comes from the previously
useful projected parent, not one of the five mislabeled controls. The
17x18x30 construction adds a 1x18x30 block to the 16x18x30 result.
The primitive rank remains 90.

All three outputs and their constructions pass independent full replay:
**12 tensors, 25,707 terms, 4,578,180 support-pair XORs, six recipes including
two bud substitutions**. The 16x18x30 result ties the pinned reference; it
does not beat it.

Local-only evidence is retained in
`benchmarks/matmul/metaflip/projected_observer_audit_2026_09_08/`:
both immutable runs, the explicit correction, compressed pricing inputs,
all origin occurrences, expanded products, copied checkers, and the cumulative
cohort ledger. Walk/product replay is self-contained apart from the usual
checker runtime dependencies. Selection and full repricing also require the
pinned earlier constructive ancestry. Imported tensors and derivatives remain
outside source commits pending redistribution review. No push, publication,
submission, or live archive mutation was made.

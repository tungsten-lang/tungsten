# Cleanup-aware leaf portfolio

`MetaflipOuterLeafPortfolio.optimize_cleaned` adds a bounded, exact
post-cleanup objective to the existing offline leaf-representation search.
It does not change the installed native executable, default fleet scheduler,
canonical seeds, or a user's running search.

## Why the separate objective matters

The previous bounded raw-rank/density walk improved the presentation of
8x11x20 while making its cleaned rank **1,129 -> 1,145**. The earlier audit
retained the original, so no bound was overwritten. The new mode explicitly
compares cleaned witnesses throughout its walk instead of trusting a raw
score improvement. The complete previous raw-optimizer trace still replays
unchanged after extracting the shared leaf-pool helper.

## API and boundaries

```ruby
result = MetaflipOuterLeafPortfolio.optimize_cleaned(
  parent, allocation,
  leaves: leaves, seeds: seeds,
  cleanup: cleaner, # callable: exact same-shape Scheme -> Scheme
  seed_limit: 1, rounds: 4, shears: true,
  pair_width: 4, shortlist: 16, assessment_limit: 65
)
```

- Cheap raw rank/density orders a per-round shortlist of single-slot and
  optional two-slot replacements. It is not an admissible lower bound or a
  dominance rule: even a raw-worse proposal can win after cleanup.
- Each assessment fully materializes/verifies the raw construction. The
  callback receives a frozen tensor; its returned same-shape tensor is
  independently rechecked in Ruby, not trusted from its audit metadata.
  Scalar scores, wrong shapes and invalid tensors fail closed.
- Compare `(rank, density)` on the better of the checked raw and cleaned
  representations. Retain the baseline and accept only strict improvement
  in that objective. The callback must raise on failed/limited cleanup;
  it is responsible for its own time/work limit.
- `assessment_limit` includes the baseline and cached assessments. The
  exact raw-identity cache reduces cleanup calls, not the counted budget.
  It does **not** merge distinct leaf states with potentially different
  continuations. The returned `assessments` preserve raw/cleaned tensors,
  leaf states, provenance, and checked rank ties for later composition.
- `result` is the winning assessed tensor. `raw` and `leaves` identify its
  pre-cleanup construction; composing those leaves reproduces `raw`, not
  necessarily `result`. The ordinary composition `audit` describes `raw`.
- `round_audits`, `stop_reason`, and `unassessed_proposals` expose bounded
  coverage. Unassessed counts are proposal occurrences across visited
  rounds, not distinct tensors. Neither a shortlist stop nor completion of
  the requested budget establishes a neighborhood/global minimum.

## Retained experiment

All 18 headline shapes from the preceding small-width frontier completed
with one low-priority CPU worker, no GPU, in approximately 36.5 seconds.
Each starts from the better checked original or previous raw-refined
construction. Limits are exactly those in the example above.

| Measurement | Result |
| --- | ---: |
| Cheap proposal checks | 46,576 |
| Exact assessed states, including baselines | 354 |
| Native cleanup calls | 333 |
| Proposal occurrences left unassessed | 45,870 |
| New lower ranks | 0 |
| Lower-density, same-rank winners | 3 |

The 8x11x20 regression stays at **1,129**, and the previously gained
7x13x16 stays at **959**. The three density changes are:

| Shape | Unchanged rank | Before density | After density |
| --- | ---: | ---: | ---: |
| 7x13x15 | 903 | 16,647 | 16,646 |
| 8x12x19 | 1,148 | 25,151 | 25,141 |
| 8x13x19 | 1,270 | 25,928 | 25,927 |

Density counts factor bit incidences, not arithmetic runtime or guaranteed
composition utility. These variants are retained; no downstream gain is
claimed for them yet. The batch makes the assessment safe against the
demonstrated regression; it does not demonstrate a rank-search speedup.

Independent replay reconstructs every assessed raw tensor with a separate
coordinate implementation, recomputes shared-factor matrix cleanup, and
fully expands all identities. Every distinct assessed endpoint also passes
the native full verifier. All 18 deliberate one-bit corruptions fail both
checkers. Ruby replay reruns every deterministic proposal/assessment trace
and native cleanup, including the previous bad raw-score control.

There are **315 fresh assessed endpoint representations**, bringing the
deduplicated series to **13,836 complete identities**, including the same
166 original inputs. The prior **38 source-scoped candidate shapes** are
unchanged. No world-record, main-square, or general-field claim is added.

Focused coverage: the new cleanup spec, existing leaf portfolio, outer
basis product and width-frontier specs pass **37 tests / 1,032 assertions**.
No full compiler suite, fleet restart, or GPU workload was run.

The private evidence directory is
`/private/tmp/metaflip-cleaned-portfolio-20260911`; its standalone
`python3 -B replay.py` runs the Ruby producer-trace replay, native cleanup
and independent Python checks. It contains complete input/leaf snapshots,
all assessed endpoints, recipes, traces, pinned code/checkers and the prior
identity receipt. Ruby, NumPy and a host compatible with the native binaries
are required. Tensor evidence remains outside Git.

Durable archive (1,393 payloads; 9,112,230 bytes):

```
~/.local/share/tungsten-metaflip/evidence/2026-09-11-cleaned-portfolio.tar.gz
SHA256 d1e1ddc5694f202f05b63c7a99ef234e6a2ed61c2ee441273016b3d01cec7982
```

Archive readback and a fresh extraction verify every payload/hash, including
hardlinks, with no unmanifested files. The extracted standalone replay also
passes. The package README predates only this archive-receipt paragraph.

# Faster exact observers; bounded renewal results

The native offline parent walker now reuses its factor hash chains when scoring
composition observers. Two matched rank-90 4x5x6 workloads run **10.2-11.2% faster**
with observations every 2,048 attempted moves, and **1.86-1.88x faster** with an
observation after every move. These are whole-process wall-time measurements of
`bud_parent_walk`, not a GPU/fleet throughput claim. All saved outputs match the
control exactly. No default search settings change.

## Implementation and correctness

`ffbp_observer_costs` previously linearly searched accumulated factor words for
every live term. It now visits the walker's existing U/V/W hash chains, comparing
complete words to handle collisions, and marks physical live slots in the
existing capacity-sized scratch buffer. One grouping pass serves all observers.
The walker's state, price tables, RNG, moves, acceptance rules, and output format
are unchanged. No additional allocations or caches are introduced. This avoids
the ordinary quadratic grouping scan; adversarial hash collisions can still
cause repeated chain traversal.

The independent scalar grouping scorer remains unchanged. Native tests compare
it against nine batched tables, including nonlinear prices and deliberate
different-word hash collisions. They check the whole state remains byte-equal,
slot removal/reuse, scratch resetting, and invalid-stride sentinels. The focused
native CLI suite additionally covers ranks above 64, eight observers versus
single observers, invalid tables, rank-only controls, and holdouts.

The Python observer replay now checks debt/density ranges, the native density
echo, sufficient price-table coverage for rank plus debt, and consistency of
recorded native command parameters. Historical absolute locations remain legal
when moving retained evidence; tensor/table hashes are checked separately.
Mutated shape, strategy, work, RNG, density, debt, and extra holdout arguments
are rejected.

## Matched measurements

Both binaries were freshly built with the same current compiler and
`--release --native`. The control uses the scorer from `2a17bb80`; the other six
minimal source files are unchanged. Control source copies normalize terminal
whitespace only. Each case has four counterbalanced repetitions (linear/hash,
then hash/linear), one CPU worker, `nice -n 10`, no GPU. The host was not reserved;
these are workload-specific medians, not an all-machine performance guarantee.

| Parent density | Observe every | Linear wall seconds | Hash wall seconds | Speedup |
| --- | ---: | ---: | ---: | ---: |
| 1209 | 1 | 1.712644 | 0.920906 | 1.860x |
| 922 | 1 | 1.717365 | 0.912048 | 1.883x |
| 1209 | 2048 | 0.995295 | 0.894792 | 1.112x |
| 922 | 2048 | 0.964891 | 0.875326 | 1.102x |

Every-move cases use two trials x 32 chunks x 4,096 attempts. Interval-2,048
cases use eight trials x 128 chunks x 65,536 attempts. Each uses four frozen
composition objectives, debt two, density slack four, and RNG 912331. All 16
matched pairs have identical winner/endpoint/observer bytes and identical
`BUD_TRIAL`, `BUD_OBSERVER`, and non-timing `BUD_RESULT` fields. The 32 complete
runs total 1,077,936,128 attempts. Independent replay checks 784 per-run tensors,
70,560 terms, and 1,114,016 support-pair XORs; these counts include repeated
control/optimized outputs rather than claiming that many distinct discoveries.

The benchmark report digest is
`7c2a6e354adb673a235c369fc62594690680cd4862d358c37f0e70b95a05c9dc`.
Binary, source, input, table, report, and tensor provenance is retained locally.

`tungsten flame --counters` also sampled the old implementation. A valid
three-second rates sample attributed much of its sampled work to
`memset_pattern16` and `ffw_toggle`; it did not isolate the observer scorer as
the leading frame. A fresh-control stalls sample highlighted `ffw_toggle`,
`ffbh_join`, and runtime frames. These partial profiles include startup and
are not matched-work evidence for a particular cache/misprediction claim.
The stalls driver rejected missing buffered child stdout, but all six saved
partial outputs match the independently checked complete control run. The
speedup claim above relies on complete matched runs, not profile percentages.
No profiler child is left running.

## Search follow-up: retain evidence, not more aggressive defaults

The frozen selection found 270 literal 4x5x6 parents tying the 4,833 context
price. Eight seeds include four such diverse ties and four earlier controls.
The actual selection contains seven rank-90 parents and one rank-92 parent;
the original selector's prose mentioning rank-91 shoulders is inaccurate.
Its completed script/report are preserved unchanged with this correction.

Density slack 4 versus 16 received the same 32 trials x 128 chunks x 65,536
attempts per seed, debt two, RNG 912281, and observation interval 2,048:
2,147,483,648 attempts per setting. All 32 seed/objective minima tie. Neither
setting produces a new context reference crossing. Adding 2,096 independently
verified literal parents brings the corpus to 30,893, with no improved prices.
The existing default density slack stays four.

A separate cadence comparison uses the first four tie parents, eight trials
x 64 chunks x 4,096 attempts, and RNG 912331. Intervals 2,048, 64, and 1 each
receive 8,388,608 attempts. All 32 trial endpoints are byte-identical across
cadences, and all 16 seed/objective minima tie, including at every-move
observation. The latter does capture more same-path sidecars than the saved
rank winner, but that does not produce a better target construction. These
runs add 322 literal parents. Full bounded repricing of the **31,215-parent**
corpus evaluates 2,411,290 ordinary and 525,302 retained mixed expressions,
with **zero lower-price shapes**. Recipe tie choices may differ.

The improvement cohort therefore remains **258 distinct lower-local-price
shapes: 21 expanded outputs and 237 unexpanded recipes**. The scoped
reference-crossing shortlist stays 42; neither figure is a confirmed world
record total or the separate historical campaign tally. No new primitive/main
square rank improvement is claimed. Previously pinned mixed-field references
were not refreshed and never become unchecked constructive leaves.

## Focused validation and retention

- Native scoring unit: pass.
- Native parent-walk integration: 14 tests, 892 assertions, all pass.
- Observer/admission/projection Python checks: 34 tests, all pass.
- All five completed density/cadence runs and all 32 matched timing runs pass
  independent whole-tensor observer replay.

The Python checks require a modern Python with NumPy. An initial invocation
resolved to Apple's Python 3.9 and failed on existing `int.bit_count`/NumPy
requirements; rerunning explicitly with Homebrew Python 3.14.7 / NumPy 2.4.4
passes. No compatibility code was changed to mask this environment mismatch.

Local-only evidence is in
`benchmarks/matmul/metaflip/observer_hash_audit_2026_09_08/`: immutable runs,
matched binaries/source, compressed corpus inputs, pricing plans, checkers,
profiles explicitly marked partial, and a hash manifest. Independent tensor
replay uses its contained paths; original build/search commands retain their
historical absolute locations. Imported tensors and derivatives stay outside
source commits pending redistribution review. No push, publication, live
archive update, or submission is authorized or performed.

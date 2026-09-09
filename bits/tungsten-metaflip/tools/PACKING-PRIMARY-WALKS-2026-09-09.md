# Packing-driven parent walks

The optional primary objective in `bud_parent_walk.w` uses the native mixed
packing price to select retained tensors and accept search chunks. This lets
composition structure, including useful same-rank representations, influence
the walk itself. It reuses the automatic composer's bounded pair/group engine;
it does not add another packer, runtime interpreter or live CPU/GPU lane.

This is an **opt-in offline research feature**, not a default fleet strategy
or a demonstrated throughput improvement. The automatic deferred composer
already uses mixed groups independently of this experiment.

## Interface and safety boundary

Keep the usual four price-table rows: rank limit, then the three fixed-axis
cost tables indexed from zero through that limit. Append either:

```text
mixed-primary pairs 50000
11 20 20 21
```

or, for the same context with optional triples and quadruples:

```text
mixed-primary groups 50000
11 20 20 21 30 30 -1 40 40 -1
```

Costs are singleton, U/V/W pairs, U/V/W triples, U/V/W quadruples. Here the
example scale is 2x3x2; `-1` means no leaf witness. Every required pair cost
must be positive. Optional size-3/4 costs are either positive or `-1`; zero
is not a valid absence marker. Positive costs are at most 128, matching the
native bank limit. The table must contain exactly six rows. Header, budget
and mixed costs require canonical integer spelling. The budget is 1..1,000,000;
rank limit is at most 512 and must cover the input rank plus allowed debt.
The legacy axis tables remain validated but are not the selected objective.
Holdouts, grids and observer tables cannot be combined with mixed primary.

Use the existing executable arguments, for example:

```sh
bin/tungsten-compiler compile bits/tungsten-metaflip/tools/bud_parent_walk.w \
  --out /tmp/metaflip-packing-walk --release --native --no-lto
nice -n 10 /tmp/metaflip-packing-walk \
  /path/to/verified-parent.txt 2x2x3 /path/to/prices.txt \
  8 128 16384 anneal 953019 /path/to/fresh-output 2 8 2048
```

`bench_bud_parents.rb` does not yet expose this table mode. Research callers
must bind each price to an independently checked leaf of the correct oriented
shape, and verify complete constructed tensors before treating formula prices
as bounds. A syntactically valid numeric table is not a tensor certificate.
The walker fully checks every exported parent; it does not import leaf files
or construct composed tensors itself.

Scoring copies and canonically sorts the full parent into private scratch.
It cannot change walker state, RNG or verification counters. Pair mode uses
the existing deterministic pair fallback. Group mode first obtains that pair
plan and only replaces components where its size-2/3/4 search finishes. Each
evaluation has separate budgets for pair states and group probes, with group
probes including memo hits; incomplete or oversized components preserve their
pair plans. This is a bounded constructive price, not global optimality.

`walk` accepts every chunk, so neither the primary objective nor observation
cadence changes its endpoint. `greedy` accepts a chunk no worse than its
anchor; `anneal` uses the existing temperature schedule relative to the best
observed primary score. Winner ordering remains price, rank, then density.
Unaccepted chunks still count their attempts and may supply verified winners.

`BUD_PACK` reports kind, budget, evaluations, probes/states, pair states,
fallback components and components. Initial scoring happens once, then once
per observation; fallback is explicit, never reported as exact completion.
Normal `BUD_TRIAL`, winner files and endpoint files are unchanged.

## Matched studies: useful steering, no new bound

Both studies used 4x4x5, 5x5x5, 4x5x7 and 5x5x7 parents, one context per
family, with identical seeds and flip budgets for three arms: fixed-axis
grouping, mixed pairs and mixed groups. Each arm had eight trials of 128
chunks at 16,384 attempts, observing every 2,048 attempts, debt two and
density slack eight. Each study requested 201,326,592 attempts in total.
All were serial low-priority CPU runs; no GPU was launched.

The first study chose the contexts nearest the archive. Each happened to
have only one profitable axis, making its fixed-axis and mixed-group
objectives equivalent. All 64 corresponding winner/endpoint files were
byte-identical. Its 107 distinct parents produced no control-relative gain.
That negative control motivated selecting contexts with at least two
profitable pair axes for the second study.

The competitive-axis study retained 174 distinct parents. Repricing all
retained tensors under the **same** group objective at every native scale
found five target minima better than both controls. They all use a new
5x5x7 representation with identity
`9de6f3dcf0e43e12abee620a7a2bd6eda9be6ee3769146786ffd8ab6c9d649ad`.
All five composed products passed independent Python substitution and full
tensor checks. The common group price comparison is:

| Target | Fixed-axis arm | Pair arm | Group arm / exact rank | Retained bound |
| --- | ---: | ---: | ---: | ---: |
| 10x15x21 | 1900 | 1900 | 1899 | 1899 |
| 10x20x28 | 3277 | 3277 | 3272 | 3264 |
| 10x20x21 | 2530 | 2530 | 2528 | 2520 |
| 10x15x28 | 2530 | 2530 | 2528 | 2476 |
| 15x20x28 | 4795 | 4795 | 4794 | 4692 |

None improves the retained local bound. Raw primary scores from different
arms are not directly comparable; the conclusion uses common post-hoc pricing.

Deduplicating the two studies gives **280 full parents, 7,560 parent/context
recipes and 73 target shapes**, not 281 parents. All native evaluations
finished without fallback. The broader offline library, including equal-factor
groups and elementary 2x2 grids, lowered 1,339 of those native prices. All
7,560 cases completed within that bounded model, but **zero new local bounds
or reference crossings** resulted. Eight diagnostic products passed an
independent Python reconstruction and full tensor check, covering 37 distinct
parent/leaf/output tensors and 25,068 terms.

Including the earlier observer studies, the deduplicated recent rollup is
566 parents and 15,282 native parent/context recipes: the new studies add
277 distinct parents, not 280. These are search identities, not new shapes
or records; no additions belong in the historical potential-record count.
Timings include startup, scoring, checking and I/O and are not a matched
throughput measurement.

The retained comparison is the 5,984-shape closure with SHA-256
`0b4ad918bd36a262797cb89017513cbed0fe07dbdb832df4d5462c4e4e2c0da7`,
plus 6x6x32/774, 7x9x18/768, 9x15x20/1646, 9x15x22/1856 and
9x17x20/1926 already retained. The input tensors, drivers, reports and exports
remain outside the repository:

- `/private/tmp/metaflip-packing-primary-study-20260909/report.json`
  (`fda9920dbeb7741840f080f723b48310ebc13311d92cdd200803d7454b547033`)
- `/private/tmp/metaflip-packing-primary-competitive-20260909/report.json`
  (`0a46684b26c19ad88a706f86c637e4e28c286d62a3e4c56e2a6c5987c51d253d`)
- `/private/tmp/metaflip-primary-broad-packing-20260909/report.json`
  (`2fcd87b02a894a90d5015a539781941352fef81b7bc86195dfb6de5d49f7f4ce`)
- `/private/tmp/metaflip-primary-broad-packing-20260909/independent.json`
  (`9a2f15813e192eb19ae59677c3ee03254f4eeebd4c55377723aad0f33b81673e`)

## Focused checks

```sh
python3 bits/tungsten-metaflip/spec/packing_primary_walk_test.py /tmp/metaflip-packing-walk
python3 bits/tungsten-metaflip/spec/mixed_observer_walk_test.py /tmp/metaflip-packing-walk
METAFLIP_BUD_WALK_BINARY=/tmp/metaflip-packing-walk \
  ruby bits/tungsten-metaflip/spec/bud_parent_walk_test.rb
```

The new test independently reconstructs 33 intermediate walker states,
checks exact pair/group minima and greedy/annealing acceptance, checks
cadence-neutral ordinary endpoints, multi-chunk determinism, canonical
budget-one fallback including rank above 64, and rejects 16 malformed or
incompatible tables before export. It passes in release/native and
non-release/native builds. Existing mixed-observer parity and the focused
parent suite (16 runs, 958 assertions) also pass. No broad local suite ran.

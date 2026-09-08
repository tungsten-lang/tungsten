# Repeatable bounded parent-cover scans

`scan_parent_covers.rb` replaces per-campaign scripts with one offline command
for an existing frozen corpus and price plan. It supports exhaustive retained
families and explicitly heuristic histogram samples, retains ordered literal
identity, uses the exact proportional context cache, and writes covers accepted
by the independent Python checker. It does not run or alter the live fleet.

From the repository root, using fresh output directories:

```sh
nice -n 10 ruby bits/tungsten-metaflip/tools/scan_parent_covers.rb \
  --inputs BASE/inputs.json --plan BASE/report.json --output SCAN \
  --sample 5x5x6 --all 5x5x7 --max-leaf 32 --seconds 180 --case-seconds 2
nice -n 10 /opt/homebrew/bin/python3 -B benchmarks/matmul/metaflip/verify_parent_cover_scan.py \
  --root SCAN --inputs BASE/inputs.json --price-plan BASE/report.json \
  --output SCAN/independent-audit.json
nice -n 10 /opt/homebrew/bin/python3 -B benchmarks/matmul/metaflip/extend_composition_parents.py \
  --inputs BASE/inputs.json --plan BASE/report.json --parent-cover SCAN --output NEW_PLAN
```

`--all` means every retained literal in that ordered family, not every possible
tensor representation. `--sample` takes the most recent member of each ordered
pricing-histogram class plus every parent with an existing mixed cover. This is
sampling only: a histogram is neither an identity nor a dominance certificate.
Each selected parent visits every integral scale whose target sides fit the cap.

Both modes use one CPU worker. Defaults bound a case to two seconds and check
the 180-second campaign budget between cases; loading, checkpointing and final
hash checks are not a hard wall-clock deadline. A timeout has no fabricated
cover or price. A stopped domain never becomes an exhaustive result, and an
incomplete optimizer result never becomes an optimality claim. Output directories
cannot be overwritten. Input documents, literal sources and producer code are
pinned before use and checked again before sealing the report.

The checker now independently reconstructs the declared family selection from
the entire frozen corpus, including sample representatives and retained controls.
It checks requested domain sizes and the visited prefix as well as literal
ordering, tensors, partitions, factor maps and prices. Old scan formats remain
readable but do not receive `family_selection_verified`. Neither format certifies
the optimizer's optimality, the frozen price plan's leaf witnesses, or novelty.
Materialization remains a separate, fail-closed gate.

## 5x5x6 and 5x5x7 experiment

The initial bounded driver covered **59,076 cases on 349 parents**: 245 sampled
5x5x6 parents out of 445, and all 104 retained 5x5x7 parents. It finished in
158.97 seconds using one `nice -n 10` CPU worker, with 19,431 cache hits and
39,645 misses. All results were exact within the producer's bounded model.
The independent checker replayed 349 tensors, 40,181 terms and 795,460
support-pair XORs, including the declared selection.

There were 6,860 saved covers, of which 6,815 were new to their existing parent.
All nine direct lower prices came from 5x5x6 variants. The complete retained
5x5x7 scan gave no additional direct gain; unsampled 5x5x6 states and other
move families remain open. Full repricing took 66.70 seconds and considered
2,720,212 total group expressions, including 834,224 mixed expressions. It
found **24 lower local prices: nine direct and 15 propagated**. This is seven
additional distinct shapes, since 17 already belonged to the improvement cohort.
These host timings are observations, not a speedup benchmark.

The reusable command reproduces all parsed JSON rows, complete packing metadata
and cover indices on 540 cases from three of the real 5x5x6 parents. This is a
parity test, not another discovery batch.

## Expanded witnesses and composition

Six selected products and their dependencies pass independent replay:

| Shape | Previous local price | Expanded GF(2) rank | Pinned comparison |
| --- | ---: | ---: | ---: |
| 12x15x15 | 1,640 | 1,632 | 1,600 |
| 18x20x25 | 5,122 | 5,111 | 5,036 |
| 20x20x24 | 5,170 | 5,154 | 5,154 |
| 18x20x30 | 5,910 | 5,903 | 5,903 |
| 26x30x30 | 12,488 | 12,464 | 12,202 |
| 26x31x31 | 14,074 | 14,050 | 13,280 |

The independent audit covers 45 shape/orientation tensors, 92,431 terms and
34,376,934 support-pair XORs. No numerical reference entry substitutes for a
constructive leaf. The first materialization attempt correctly stopped when
the base literal/block/Kronecker loader could not reconstruct the inherited
14x15x15 price of 1,892. An earlier audited cover on the imported rank-127
5x5x7 parent supplies that exact leaf:

`104*15 + 10*29 + 42 = 1892`, using 3x3x2, 3x3x4 and 3x3x6 leaves.

After reconstructing and tensor-checking it, the larger product succeeds:

`R(26,30,30) <= 3*R(12,15,15) + 4*R(14,15,15) = 3*1632 + 4*1892 = 12464`.

This uses a retained 2x2x13 parent at scale (15,15,2), split into three groups
of size six and four of size seven. It composes the newly useful 5x5x6-derived
leaf with the older 5x5x7-derived leaf. The eight-unit leaf improvement propagates
three times, saving 24. Two ordinary boundary blocks then give
`R(26,31,31) <= 12464 + 26*30 + 26*31 = 14050`.

The full local improvement cohort is now **336 distinct shapes: 35 expanded
at their current best price and 301 recipe-only candidates**. The older expanded
18x25x30 rank-7,420 witness is explicitly superseded by a rank-7,410 recipe and
does not count as expanded at that new price. There are no new primitive or
main-square rank improvements. The pinned, mixed-field reference shortlist
remains 45; two new products tie that comparison and none crosses it. References
were not refreshed for this non-crossing batch. These are not confirmed records.

## Validation and retention

Focused Ruby tests pass **35 tests / 573 assertions**, including family sampling,
literal identity, full results, deadline/timeout handling, source drift, invalid
limits and preservation of grid order. The **61 focused Python tests** include
the producer's CLI feeding the independent checker, selection-mutation rejection,
cover admission, expression reuse, pricing, recipes and tensor replay.

Local-only evidence is retained under
`benchmarks/matmul/metaflip/parent_cover_scan_audit_2026_09_08/`: frozen inputs,
plans, scans, both audits, the 540-case parity check, failed and successful
materialization attempts, recovered leaf, product recipes, source versions,
provenance and a checked hash manifest. Imported tensors and derivatives remain
outside commits pending redistribution review. No live archive change, GPU work,
push, publication or submission occurs.

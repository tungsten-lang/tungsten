# Reusing native leaf banks in parent search

Follow-up to `a7998a85`. The native composer had exact rank-15 and rank-26
small leaves, while the ordinary offline parent-search library could still
price their shapes with older block sums. The offline search already
understood larger groups; missing leaf witnesses, not a missing DP, caused
this mismatch. Earlier research used an enriched temporary catalog library;
this change reuses the distributable native construction directly.

`bench_bud_parents.rb` and `bud_products.rb` now accept `--native-spool DIR`.
They read the existing scale-2/3/4 bank pointers once, bind their immutable
manifests and member identities, and verify every leaf's entire tensor.
They enforce bounded reads, canonical decimal serialization, expected shape,
rank and byte digest. Advertised ranks or hashes alone cannot supply a leaf.
The existing library then uses these verified schemes alongside packaged
ones, including exact block sums and optional recursive products.

Reports retain bank/member provenance; all leaves used in price tables and
exported products are copied into the existing self-contained snapshots.
The source spool may subsequently change or disappear without invalidating
those product recipes. Neither option mutates the live fleet, runs a GPU,
introduces a native-runtime Ruby dependency, or changes production acceptance.
The option is explicit; omitting it preserves packaged-only behavior.

## Focused checks

The unchanged packaged 2x2x5/r18 d92 parent, scaled by 4x4x1, has initial
offline price 236 without the native bank and 230 with it. Both studies use
matched tiny walk/greedy/annealing controls, export products and independently
replay all of them. Rank 230 for 5x8x8 is a known construction, not a discovery.

Checks also cover corrupted bank bytes, invalid pointers, wrong-shaped leaves,
oversized input and a false tensor with newly recomputed valid hashes. A
standalone composition regression deletes the source spool after export and
still replays every saved product. The targeted product suite passes 17
tests / 145 assertions. The full parent-walk focused suite passes 16 tests /
958 assertions; the actual native-bank integration case also passes again
after the composition CLI extension (56 assertions).

```sh
ruby bits/tungsten-metaflip/spec/bud_products_test.rb
METAFLIP_BUD_WALK_BINARY=/path/to/bud_parent_walk \
METAFLIP_GROUP_BINARY=/path/to/group_composition_test \
  ruby bits/tungsten-metaflip/spec/bud_parent_walk_test.rb
```

The native binaries are built from `tools/bud_parent_walk.w` and
`spec/group_composition_test.w` with `--release --native --no-lto`.

## Bounded follow-up — no new best-known result

Two parents received 16 trials per policy, 128 chunks of 16,384 attempts,
observations every 256, rank debt 2 and density slack 8. Each policy attempts
33,554,432 flips; the two three-policy studies total **201,326,592 attempts**.
They ran sequentially at low priority, one CPU worker and no GPU.

| Parent | Scale / target | RNG | Initial | Walk | Greedy | Anneal | Retained target bound |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 4x5x5/r76 | 4x1x4 / 16x5x20 | 981733 | 1108 | 1108 | 1108 | 1108 | 1093 |
| 3x5x5/r58 | 1x4x4 / 3x20x20 | 982019 | 916 | 916 | 916 | 916 | 891 |

These are constructive objective prices, not rank lower bounds. No strategy
or throughput advantage follows from the unchanged minima. Native walker
SHA-256: `158ed5b2a6aa933b98d99d936cb9b9227acbd7564e0f8b5766d9246b8ea7ec0c`.
The frozen bank identities are:

- scale 3: `56b1cfa17ce6b0cebfc60a7c3067a49bb4f4af1be32d868a584ebcde46d6573f`
- scale 4: `cf448158ff89b22d43d0c21a354efc9c3eec005bd7a458077a7b694e9b641936`

All 192 saved winner/endpoint occurrences underwent independent full tensor
checks and literal deduplication, leaving 110 distinct sources. Native matrix
cleanup, bounded basis refinement and coordinate projection produced a spool
of **1,943 exactly verified tensors**, with no lower primitive bound or lower
native fixed-axis composition price than the retained table.

An additional unequal-scale screen used every scale triple in 1..4 except
(1,1,1). It checked 122,409 pure-axis bucket prices over those 1,943 parents,
covering 164 dimension-sorted targets. Caching 19,026 price signatures did not
deduplicate tensor identities. No price beat the frozen retained comparison.
Only strict price improvements would have been expanded in this screen;
none qualified. This does not exclude cancellation gains in unexpanded
recipes and is not a rank-optimality or exhaustive-search theorem.

The comparison table SHA-256 is
`5a283ebd193c37f4246a0e3fb00cd095d3159b05e13ce6f401439dc076a9c721`.
Reports, witnesses and the bounded replay scripts remain outside the repository
under `/private/tmp/metaflip-native-bank-campaign-20260908/`. This commit adds
no seed tensors or bulk campaign files. No world-record claim, publication,
push, new fleet policy or running search is associated with this batch.

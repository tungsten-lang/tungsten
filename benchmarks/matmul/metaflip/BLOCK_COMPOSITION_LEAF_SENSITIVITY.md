# Block-composition leaf sensitivity

Status date: 2026-07-14.

For every stored recipe, the analysis below recomputes the effective leaf
shape used by each of the 47 terms of the exact rank-47 `4x4x4` outer scheme.
Shapes are identified across all six S3 tensor-slot orientations. Therefore a
one-rank improvement to one exact leaf lowers a recipe's formula rank once for
every outer term supported by any orientation of that shape.

The reproducible analysis is:

```sh
python3 benchmarks/matmul/metaflip/block_composition_leaf_sensitivity.py --limit 10
```

It first reconstructs the stored formula rank from the checked-in complete
84-shape pool: all 28 sorted two-wide leaves and all 56 sorted 3--8 leaves.
It aborts on any discrepancy. All 186 materialized recipes and all 889 strict
audited formulas currently reproduce exactly. Apple Python 3.9 and Homebrew
Python produce byte-identical output.

## Materialized records

`guaranteed records` is conservative. Existing post-embedding cancellation is
credited to the current certificate but not assumed to survive a replacement
leaf. A recipe is counted only when its new formula upper bound is already
below its current exact rank.

| leaf | current rank | formula occurrences removed | records using leaf | guaranteed records improved | guaranteed aggregate margin |
|---|---:|---:|---:|---:|---:|
| 4x4x5 | 60 | **1,076** | **71** | **67** | **1,040** |
| 3x4x5 | 47 | 980 | 64 | 62 | 949 |
| 4x5x5 | 76 | 786 | 46 | 46 | 742 |
| 3x4x4 | 38 | 668 | 60 | 55 | 631 |
| 3x5x5 | 58 | 479 | 35 | 34 | 444 |

The 1,076 uses of `4x4x5` split as 731 `4x4x5`, 302 `4x5x4`, and 43
`5x4x4` orientations. Four cancellation-heavy records use the leaf but are
not guaranteed to improve from the formula bound alone; materialization could
still improve them.

## Strict audited cross-band formulas

Every row in this set already beats the strongest pinned numerical baseline,
so every containing formula becomes a better apparent record. `shadow` counts
additional rows with a pinned GF(2) comparator that would cross to a strict
gain after the same leaf improvement. The 641 small-cross rows without such a
comparator are deliberately excluded from that count.

| leaf | current rank | formula occurrences removed | apparent records improved | shadow rows becoming records |
|---|---:|---:|---:|---:|
| 4x5x7 | 104 | **2,043** | **200** | 5 |
| 4x6x7 | 123 | 2,002 | 185 | 7 |
| 4x5x6 | 90 | 1,683 | 169 | 6 |
| 3x4x6 | 54 | 1,679 | 142 | 7 |
| 3x5x6 | 68 | 1,638 | 144 | 9 |

The next six exact GF(2) frontiers are also first-class CPU profiles:

| leaf | current rank | strict target | formula occurrences removed | apparent records improved | shadow rows |
|---|---:|---:|---:|---:|---:|
| 5x6x7 | 150 | 149 | 1,579 | 111 | 4 |
| 3x5x7 | 79 | 78 | 1,525 | 144 | 8 |
| 3x4x7 | 64 | 63 | 1,458 | 124 | 5 |
| 4x5x8 | 118 | 117 | 1,325 | 110 | 2 |
| 4x6x8 | 140 | 139 | 1,202 | 106 | 5 |
| 4x6x6 | 105 | 104 | 1,176 | 116 | 4 |

The 2,043 uses of `4x5x7` split as 1,166 `4x5x7`, 560 `5x4x7`, and
317 `4x7x5` orientations. One exact rank-103 certificate supplies all three
through S3 orientation. The ranking above weights the 889 conservative GF(2)
wins; it does not let uncovered numerical comparisons masquerade as records.

## Campaign choice

The default seven-shape `--rect` portfolio now includes 3x4x7 and 3x5x6 in
place of 3x3x4 and 3x4x4. Matched 100M-move one-core runs gave the incoming
profiles 21.6B and 17.9B leverage-weighted attempts per second, versus 0.049B
and 3.73B for the outgoing profiles. Both replacements also win when the same
calculation uses accepted states rather than raw attempts. The other four new
profiles remain selectable but non-default, keeping the portfolio at seven
shapes and retaining 4x4x5 as its Metal-capable member.

The strategic maximum-impact target is `4x5x7`, rank 104 to 103. It is now an
allowlisted CPU-only FlipFleet rectangular profile. Its factor widths are only
20/35/28 bits, so they fit the existing shared-i64 rectangular representation;
no representation change or Metal worker is required.

The profile's checked-in catalog seed has density 1163. A bounded one-core
100M-move entry smoke independently exact-gated a rank-104 density-1160
descendant. A later whole-scheme GL tunnel reached d1101, and matched 25M-move
walks retained d1089 twice while both d1160 controls remained fixed. The
independently reconstructed d1089 file is now the default profile seed; d1160
remains the distance-208 alternate door. These are same-rank density/basin
improvements, not rank records.

For a CPU monster with two cores reserved for the coordinator and operating
system, use long epochs to amortize the exact gate:

```sh
ROOT="$(git rev-parse --show-toplevel)"
CORES=$(getconf _NPROCESSORS_ONLN)
J=$((CORES - 2))
RUN_TAG="rect457_$(date +%Y%m%d_%H%M%S)"
/tmp/flipfleet-native \
  --tensor 4x5x7 -J "$J" --steps 500000000 --secs 86400 \
  --no-gpu --stop-on-record --quiet -d 6 --cycles 8 \
  --seed "$ROOT/benchmarks/matmul/metaflip/matmul_4x5x7_rank104_d1089_gl_frontier_gf2.txt" \
  --repo-root "$ROOT" \
  --status "$ROOT/flipfleet_4x5x7_${RUN_TAG}_status.txt" \
  --best "$ROOT/flipfleet_4x5x7_best.txt" \
  --run-tag "$RUN_TAG"
```

The best immediate target is `4x4x5`, rank 60 to 59. It already has a native
CPU profile, a specialized Metal worker, and an exact density-628 GL/frontier
seed. Across
the saved and strict-audit portfolios it occurs 1,411 times in 113 formula
rows; 109 of those rows are guaranteed to improve, and three additional shadow rows
would become strict audit wins. This is much more downstream leverage than
the active `3x3x5` target, which occurs 512 times across 52 saved or audited
formulas.

The strongest newly exposed two-wide target is `2x5x6`, rank 47 to 46. A
one-rank improvement lowers ten saved records by 82 guaranteed aggregate
terms and 49 additional strict audited formulas by 652 terms, with three more
comparable rows crossing into strict wins. It is therefore the leading small-cross
primitive campaign after `4x4x5`. FlipFleet now exposes it as a first-class
rank-47→46 profile with two independently gated rank-47/d438 doors at maximum
term-set distance 94, sticky CPU islands, a capacity-92 cal2zone worker, and
low-cadence exact 5→4 MITM. Half the Metal epochs rotate the nonleader door.

For a future CPU-only run:

```sh
/tmp/flipfleet-lunch \
  --tensor 4x4x5 -J 2 --steps 50000000 --secs 14400 \
  --no-gpu --stop-on-record --quiet -d 6 --cycles 8 \
  --seed "$ROOT/benchmarks/matmul/metaflip/matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt" \
  --repo-root "$ROOT" \
  --status "$ROOT/flipfleet_4x4x5_leaf_status.txt" \
  --best "$ROOT/flipfleet_4x4x5_best.txt" \
  --run-tag rect445_NONCE
```

The d628 seed was reached by a complete-gated rectangular global-isotropy
descent from d919 (first producing d655) followed by a one-core FlipFleet
continuation.  In a matched 5.05-billion-move restart at `-d 8 --cycles 10`,
the far-GL door reached d628 while d919 remained at d919.  Both retained rank
60 and zero exact rejects; an independent coefficient-parity reconstruction
also passed.  The two 60-term sets have no term in common (symmetric-difference
distance 120), so implicit multiwalker campaigns alternate them.  An explicit
`--seed` still uses only the requested scheme, preserving controlled runs.

On the 18-core host, the two existing fleets nominally use 12+2 worker cores;
another two-lane campaign would leave two cores for coordination. At the audit
snapshot, however, system load was already 18.55 because unrelated jobs were
also active, and the existing `3x3x5` process consumed 1.92 core-seconds per
wall second. The additional run should wait for actual load to fall or for an
existing campaign to end; otherwise it mostly redistributes throughput.

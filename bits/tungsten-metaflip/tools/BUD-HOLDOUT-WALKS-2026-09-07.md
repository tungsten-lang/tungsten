# Bounded structured-holdout study, 2026-09-07

The new offline holdout arm is correct on the checked workloads, but is **not
promoted as a better default**. It finds no better primitive rank or best
composition count than ordinary wandering in this bounded study. The live
CPU/GPU fleet and production hot loops are unchanged.

## Mechanism and gates

`bud_holdout.w` removes a fixed list of literal rank-one summands from an
exact parent. Existing flips and splits then operate on the residual tensor.
That residual is not a matrix-multiplication tensor and is never admitted or
exported as one. Each observer copies the residual, XORs the held summands
back in, and scores the complete tensor. Winners and final states pass the
full exact matrix-tensor gate before export. The observer never changes the
walked residual's target, best state, clock, or RNG.

The native tool accepts an optional holdout file after `DENSITY_SLACK` and
`OBSERVE_EVERY`. Its rows are literal masks, not hash-table positions. The
Ruby runner's `--holdout-indices` selects zero-based text-order terms and
writes that file. Missing, duplicate, out-of-width/nonmember terms and
over-capacity joins fail closed. Cancellation against an evolved residual
is legitimate GF(2) arithmetic and is counted separately; it must not be
misreported as a surviving held block.

Without this option the ordinary control retains the previous search
semantics. Focused tests cover default/explicit cadence, deterministic
outputs, rectangular and square engines, split boundaries, output overwrite
refusal, partial-tensor and coefficient-mutant rejection, cancellation, and
capacity gates. The end-to-end suite passes 7 tests / 310 assertions with
no skips, and the native holdout identity spec passes separately.

## Matched experiment

Each policy and arm has 16 trials, 256 chunks, 512 attempted moves per chunk,
and an observation every 32 attempts: **2,097,152 attempts per cell**. RNG
seed is 910073, debt is two, density slack is four. Ordinary, greedy, and
annealing chunk acceptance were all tested against the same frozen enriched
leaf library. The live fleet ran concurrently, so elapsed times are not an
isolated throughput comparison.

| Parent | Scale | Held structure | Ordinary best | Holdout best |
|---|---|---|---:|---:|
| Public 3x3x4 rank 29 | 3x3x3 | U-triplet | 663 | 663 |
| Public 2x3x5 rank 25 | 3x3x2 | U-pair | 371 | 371 |
| 2x2x5 rank 18 | 3x3x3 | U-pair | 392 | 392 |
| Same 2x2x5 control | 3x3x3 | Four-term 2x2x1 grid | 392 | 392 |

The ordinary-walk policy improved the 2x2x5 product score 398 to 392 in 7/16
trials. Pair holdout did so in 3/16; grid holdout did so in 9/16. The small
9-versus-7 observation does not establish a reliable advantage. Greedy and
annealing remained at 398 in all three arms. Neither policy improved the
other two parent scores.

For the 3x3x4 ordinary-walk policy, the held triplet reduced accepted flips
from 141,422 to 2,161 at equal attempt count. Permanent holdouts can remove
most available movement even when their shared-factor structure is useful
for larger compositions. This is evidence against making permanent shared
pair/triplet locking the default, not against every structured-holdout method.

The whole experiment uses **44,040,192 attempts**. An independent Python
checker reconstructs all 336 composition maps and checks the full parent,
leaf, output, and 336 final-anchor tensors: 322 distinct tensors, 15,815 terms,
230,626 support-pair XORs. All pass. No holdout cancellation occurred in these
measured runs, although the cancellation branch has a focused native test.

None is a new record: the existing verified baseline already has 9x9x12 at
626, 6x9x10 at 371, and 6x6x15 at 371. These are search-mechanics tests with a
restricted parent/leaf objective, not a stronger global construction screen.

The first preflight rejected a 3x3x4 scale-4 choice because the selected
library offered no strictly profitable held group there; it ran no walks.
Scale three was selected by exact input pricing before the matched run.

## Reuse

The retained research artifact is
`benchmarks/matmul/metaflip/holdout_walk_audit_2026_09_07`, including input
snapshots, logs, source hashes, product recipes, and a portable mathematical
replay. It carries the existing catalog provenance and redistribution
cautions; no new data is inserted into the bit's distributable seed library.

From this bit directory, a bounded grid-held run can be launched with:

```sh
tungsten --release --native -o /tmp/bud-holdout tools/bud_parent_walk.w
ruby tools/bench_bud_parents.rb --binary /tmp/bud-holdout \
  --parent lib/metaflip/seeds/gf2/matmul_2x2x5_rank18_d84_gf2.txt \
  --scale 3x3x3 --holdout-indices 12,9,8,3 --grids --recursive-products \
  --library ../../benchmarks/matmul/metaflip/holdout_walk_audit_2026_09_07/study/library \
  --trials 16 --chunks 256 --steps 512 --observe-every 32 --seed 910073 \
  --output /tmp/my-held-grid-study
```

The measured native binary SHA-256 is
`925a2eeaaec007853dbb95db21d1e920d2f64f9a2687f4992418a71833c6c4d6`.
Portable replay validates the saved mathematics; reproducing the exact native
trajectories additionally requires this binary or the matching compiler and
runtime build, not merely the source filenames.

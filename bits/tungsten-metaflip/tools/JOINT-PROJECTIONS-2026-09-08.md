# Joint projections and composition follow-up — September 8, 2026

Three further **local GF(2) composition bounds** were materialized and
independently checked. None crosses the refreshed public-reference screen;
no world record, primitive-rank improvement, or fleet speedup is claimed.

| Shape | Previous local bound | Checked bound | Fresh Lille listing |
| --- | ---: | ---: | ---: |
| [8×15×24](https://fmm.univ-lille.fr/8x15x24.html) | 1766 | 1764 | 1728 |
| [15×23×24](https://fmm.univ-lille.fr/15x23x24.html) | 4808 | 4806 | 4712 |
| [23×23×24](https://fmm.univ-lille.fr/23x23x24.html) | 7449 | 7447 | 6852 |

The reference columns are comparisons, not independently reconstructed GF(2)
witnesses. The broader mixed-field metadata closure gives 1725, 4712, and
6776; it must not be treated as a constructive bound over a single field.
The verified-F2 catalog block/Kronecker screen already gives 7439 for the last
shape. These results therefore add zero new candidate-record shapes.

## Search change

`benchmarks/matmul/metaflip/joint_dual_projection_scan.py` restricts two shared
tensor coordinates by one dimension each. For each coordinate it enumerates
nonzero binary kernel pairs `(u,v)` with `u·v=1`, using compatible dual maps
`M Nᵀ=I`. It applies both restrictions **without an intermediate rank gate**.
Coordinate and one-dual controls occur inside the same enumeration. Deduplication
uses the complete oriented tensor terms, not a rank, histogram, or hull.

Optional `--pair-order 0,1,2` runs exact shared-pair reductions **before** final
rank retention. A raw high-rank image can hide cancellations. One deterministic
order is searched per invocation; this does not enumerate every rewrite normal
form. The report keeps the raw rank, intermediate rank, maps, cleanup trace,
controls, view counts, CPU allowance, and incomplete status. The default has no
pair cleanup and matches the raw control.

`verify_joint_dual_projections.py` independently rebuilds dense maps, checks
`M Nᵀ=I`, replays cleanup with a separate sort/group implementation, and checks
the complete output tensor. It also verifies every selected source tensor when
**no output survives**, preventing a negative scan from skipping its inputs.
It certifies constructions, not exhaustive-search completeness or optimality.

Neither tool changes a live fleet lane. Jobs are sequential, bounded, and were
run at `nice -n 10`; no indefinite CPU/GPU load was restarted.

## Bounded results

- Raw pilot: 246,016 map descriptions from one rank-93 5×5×5 parent to
  4×4×5. Coordinate/one-dual/two-dual minima were 67/64/62, above the existing
  local rank 60. About 10.01 CPU seconds; no retained output at slack zero.
- Raw portfolio: 17 oriented jobs, 13 distinct source tensors, 1,978,880 map
  descriptions, 79.61 seconds wall time. Retained 38 new full identities within
  two terms of the current price. The pilot's views overlap this portfolio and
  are not an additional distinct-search count. No primitive rank improved.
- All retained images and their sources passed independent replay: 51 tensors,
  2,691 terms, 31,115 pair XORs. Six-order post-retention pair cleanup found no
  further reductions; immediate repricing with all 38 images found no gain.
- Cleanup-before-retention: 369,856 descriptions across eight jobs;
  221,001 images reduced, but none reached the existing target price.
  70.22 CPU seconds. All seven distinct sources passed full tensor verification.
- Native continuation: 38 projected seeds and four prior same-shape/same-rank
  controls, four trials each, 32 chunks × 65,536 ordinary-walk attempts per
  trial, rank debt two, density slack four. Total 352,321,536 attempts in
  6.93 seconds wall time, one native child at a time. Independent replay covered
  286 unique tensors, 14,374 terms, 154,816 pair XORs. No primitive record fell.

The controls and projected cohort have different seed counts. Equal work per
seed is not an aggregate strategy comparison, and these timings are specific
to this small bounded workload. Ordinary wandering remains the control.

The continuation contributed 244 new parent identities, bringing the local
pricing corpus from 11,036 to 11,280. A fresh full solve checked 1,359,977 ordinary
and 525,302 mixed pricing expressions; no cached-closure shortcut was taken.

The decisive parent was **prior-control row 41, trial 1**, not a new joint
projection. It is another rank-33 2×4×5 decomposition. Its grouping gives

`21 × rank(3×4×6) + 6 × rank(4×6×6) = 21×54 + 6×105 = 1764`.

Block composition propagates the two-term saving to the other two rows.
All three final tensors and their materialized dependencies passed the separate
composition checker: 11 tensors, 23,474 terms, 1,582,117 pair XORs; zero failures.
This is evidence for retaining alternate equal-rank parents, not evidence that
the joint-projection arm outperforms ordinary flips.

## Verification and provenance

Focused tests: **42 passed**, covering every small dual pair and dimension pair,
all six cleanup orders on toy controls, cleanup before retention, literal-identity
deduplication, incomplete CPU budgets, stale sources, CLI replay, refusal to
overwrite output, and corrupted metadata/source rejection.

From `benchmarks/matmul/metaflip`:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest \
  test_joint_dual_projection_scan test_dual_projection_scan \
  test_fold_projection_scan test_pair_reduction_scan \
  test_verify_projection_filters test_extend_composition_parents \
  test_composition_expression_cover
```

Example from the repository root, with a completed, pinned input/price corpus:

```sh
nice -n 10 python3 benchmarks/matmul/metaflip/joint_dual_projection_scan.py \
  --inputs /path/to/inputs.json --prices /path/to/report.json \
  --output /tmp/joint-projection-new --job 88:4x4x5 \
  --slack 0 --pair-order 0,1,2 --cpu-seconds-per-job 180
python3 benchmarks/matmul/metaflip/verify_joint_dual_projections.py \
  --root /tmp/joint-projection-new --output /tmp/joint-projection-audit.json \
  --workers 1
```

Parent IDs belong to a particular input corpus; 88 is not a global identifier.
An incomplete report is not admitted. Verify before calling the existing
`extend_composition_parents.py --projection ...` composition admission path.

The local-only evidence bundle is
`benchmarks/matmul/metaflip/joint_projection_followup_audit_2026_09_08/`.
It retains maps, traces, native logs, exact tensors, independently checked
products, source snapshots, reference pages, hashes, and a compressed pricing
input. The original raw-source snapshot predates optional cleanup. The disposable
native driver accidentally left `best_rank` null; its audit reconstructs ranks
from tensor bytes and native logs instead. The original report is preserved.

Projection and expanded-product checks replay from the bundle alone using the
versioned checkers. Full repricing still requires the pinned earlier local
parent corpus/ancestry referenced by absolute paths; a compressed input and
hashes alone do not make that full campaign portable. Generated/imported tensors
are not committed or redistribution-cleared. Existing frozen audits are unchanged.

Live reference heads on September 8 matched the preceding pinned snapshots:

- [matmulcatalog](https://github.com/solven-eu/matmulcatalog):
  `f3a7f0f61b1005666c2cb03f98f2a16727604ea0`.
- [FastMatrixMultiplication](https://github.com/dronperminov/FastMatrixMultiplication):
  `db560ca5811bc38d5a6d5c0a3ec4315937ceabce`.

The recent [catalog paper](https://arxiv.org/abs/2606.13408) reinforces why
field-aware derived closure, not only a pointwise rank table, is the comparison
gate. It does not establish novelty for this batch.

Next useful test: rank-neutral parents near a current reference frontier,
scored by their certified upstream composition effect, with an ordinary-walk
control at the same attempt budget. Do not expand this negative projection
portfolio into a default live lane without positive matched evidence.

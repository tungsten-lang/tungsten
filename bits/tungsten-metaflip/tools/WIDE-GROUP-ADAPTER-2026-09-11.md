# Wide group planning and checked follow-up

The new offline `wide_group_plans.py` adapter safely exposes the existing
native mixed-group/grid planner to multiword parents, including parents with
more than 512 terms. This expands the usable search family, but this bounded
follow-up finds **no new best rank**. The five candidates in the
[preceding study](COMPOSED-PROJECTION-CANDIDATES-2026-09-11.md) remain unchanged.

## Adapter contract

- Intern each entire factor integer separately on U/V/W. Integer equality,
  not a truncated word or probabilistic hash, determines its label. Labels
  are planner inputs only; they must never become a tensor witness.
- Split the useful full-factor equality graph into components. Every eligible
  shared-factor group or elementary 2x2 grid stays within one component.
  Components up to 512 terms use the existing native MFM3 planner.
- Allocate a parent/context budget across component calls. Each of the three
  native counters sums to at most that budget. Oversized or unallocated
  components use an explicit, feasible pure-axis fallback; the result is
  marked incomplete, not an exact optimum.
- Recheck the returned partition, full-word group/grid identities, leaf-price
  sum, counter limits and completion metadata. Missing output, failed native
  execution and malformed reports fail closed. Remove any previous batch's
  output before invoking the next batch.
- Return plans only. Construction still uses full factors and actual checked
  leaves; complete tensor verification is the admission gate.

The adapter accepts parents of rank 1..16,384 and factors of at most 1,024
bits. Its bounds match the intended offline workload, not an assertion that
every shape fitting those bounds is available to the live fleet. Native
input batches stay below the existing one-MiB parser limit. The API is
`plan_many(binary, [(terms, thirteen_leaf_prices), ...], budget=50000)`.
Prices identify the singleton, size-2/3/4 groups on each factor, and three
grid orientations. An optional leaf is unavailable at price -1. Calling
code must retain leaf identities as well as prices.

This is **offline tooling**, not another Python runtime dependency, a new
default scheduler lane, or automatic promotion into narrow flip workers.

## Bounded search

| Cohort | Work completed | Result |
| --- | --- | --- |
| Wide positive-gain grouping | 14 parents, 210 parent/scale contexts, 35 canonical target shapes | 96 prices below plain products; no incomplete native searches |
| Checked compositions | 34 selected materializations across 17 target shapes | All verified; no cleanup reduction or new best rank |
| Coordinate restrictions | All 2,154 single-coordinate views screened; 135 selected outputs across 45 target shapes | All selected outputs verified; no new best rank |
| Equal-cost grouping | 14 scale-2 contexts and 14 full materializations | Every output equals its parent's literal Strassen product |

Parents include multiple equal-rank presentations of the previous 8x11x11,
8x11x12 and 8x11x16 candidates. Targets have dimensions at most 32. All
useful equality components here have at most eight terms, so independent
small-component optimization can check every native plan. The largest
positive-cohort counter sums are 1,109 / 484 / 1,067 against 50,000 per pass.
No selected positive-cohort plan uses a grid; its savings are shared-factor
groups. This is not evidence against grids on other parent structures.

One useful but non-record example is the 32x22x32 orientation: grouping
reduces its plain-product price from 12,530 to a fully checked rank **12,154**.
That is still above the retained 12,087 and the frozen reference 11,940.
The distinction between saving against a construction and improving a bound
is essential.

The composition selection keeps up to two lowest grouped alternatives per
target when none beats the retained bound. Projection selection keeps three
lowest distinct raw restrictions per target. Raw rank is a heuristic, not a
proof that unselected restrictions cannot clean further. The finite screens
and selected cohorts completed; arbitrary compositions/projections did not.

For the equal-cost experiment, a proposal-only rebate of one unit makes the
planner consider groups whose real leaf price equals their singleton sum.
Real prices are recomputed before construction. For example, a proxy price
of 4,405 produces an actual rank of 4,480, not an improvement on 4,477.
All 14 resulting term sets equal plain Strassen products. With this exact
leaf bank, that arm does not create an alternative presentation; it should
not receive more unchanged search budget.

## Verification and retention

The focused spec checks 96 arbitrary wide-factor cases against independent
exact packing, deterministic replay, 600-term component splitting, explicit
capacity/budget fallbacks, all three grid orientations with full tensors,
proxy-price rejection, high-word collision rejection and nine native-failure
cases. It uses an existing pinned native harness, not a clean compiler build.

```sh
python3 -B bits/tungsten-metaflip/spec/wide_group_plans_test.py \
  /private/tmp/metaflip-mixed-direction-planner-20260910 \
  /private/tmp/metaflip-projection-record-evidence-20260911 \
  90a48facfb6c04cfd585d684fc4ec9a757805d7b12e454e0bddaeae608abf02b
```

Cold replay checks **19,206 component optima**, all 48 compositions, all 135
projection/cleanup steps and **197 unique tensors**. Composition uses the
existing arbitrary-width Ruby constructor and a separate Python substitution
checker. Complete GF(2) expansion and the native full verifier independently
check tensors; cleanup is independently recomputed. No work-limited response
is admitted. This adds **181 distinct representations**, bringing this study
series to **7,868**, including 166 original inputs (7,702 non-inputs). These
are representation counts, not rank improvements or world records.

Bulk evidence stays in a private compressed bundle outside the checkout:
endpoints, original plans, checked leaves, source/native-binary pins, replay
and manifest. Intermediate tensors are reconstructed, not retained as
duplicate payloads. The first bundle replay stopped on a missing Python
checker import; the repaired replay passed. The failed log is retained.

```
~/.local/share/tungsten-metaflip/evidence/2026-09-11-wide-group-adapter.tar.gz
19,629,070 bytes; 291 payloads
SHA256 eb64e317ce860f6e6faf44b7a2553130334c9c840de54fdfd577aaad8e95dc6d
```

After extraction, run `python3 -B replay.py audit` using Python with NumPy
installed. This machine uses `/opt/homebrew/opt/python@3.14/bin/python3.14`.
The bundle includes the campaign-era adapter as provenance and the final
adapter with the additional missing-output guard. Every archived payload
was read back and checked against its SHA-256 manifest.
The complete replay and focused spec also pass from a fresh extraction
outside the checkout, with the same counts and tensor identities.

No profiling, GPU campaign, canonical seed promotion, push or publication
was performed. Search and replay each use one low-priority CPU worker. Unrelated
compiler/runtime edits were preserved.

The next changed-family experiment should vary checked leaf presentations
or elementary embeddings and assess their fully verified restrictions.
Increasing planner budget on these already-completed small components would
not address the observed limitation. Larger components and native wide-worker
integration remain separate work; this study does not declare them solved.

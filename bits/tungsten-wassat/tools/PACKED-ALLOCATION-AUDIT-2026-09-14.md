# Packed-word allocation audit

Baseline: b3917422 plus the large-proof artifact repair, compiled with
`--release --native`. Both the historical and freshly rebuilt baseline have
SHA256 `9076e1e9be88808cf03778dee5e8ce23d424a74e0a568c5d9f278fdf42908385`.
Patched CLI: `dc73a1ad4cc3a6f967d489775f9bc2ba7edc0f8ee8e239f790e7fa23576c3a56`.
This is a local, workload-specific improvement, not a claim of better SAT outcomes.

## Workload and diagnosis

The failing ten-minute MetaFlip campaign's `3x3x5-w24-drop-wassat/input.cnf`
is retained under `/tmp/metaflip-extended-v4-600s-bounded-20260913/jobs/`.
The profile used ordinary proof mode, not the different `--fast` algorithm.

`tungsten flame --alloc --counters rates`, then macOS `MallocStackLogging`,
`heap`, and `malloc_history` isolated packed clause/watch words going through
boxed BigInt operations. The native helper signatures did not suffice: packed
temporaries and masks needed explicit i64 types at inlined call sites too.
Arena allocation counters report limb payload, not the much larger mapped arena
footprint; use RSS/heap evidence alongside them.

The patch changes machine representation, not watch traversal, clause order,
search policy, or proof rules. It also retains boxed clause/proof-id alignment
above the 50,000-clause lazy threshold when proofs are requested.

## Matched observations

Three sequential before/after pairs, 1,000 conflicts each, same binary flags
and CNF. Polling adds up to about 0.2 seconds of timing granularity. This was
not a locked-host benchmark; all raw observations remain available.

| Metric | Before | After |
|---|---:|---:|
| BigInt allocations, each run | 5,202,140 | 492,546 |
| Wall seconds, three runs | 2.494 / 2.485 / 2.276 | 2.274 / 2.076 / 2.077 |
| Median sampled peak RSS, bytes | 1,977,270,272 | 428,523,520 |
| Decisions, each run | 49,674 | 49,674 |

All solver statistics except preprocessing time agree. Median observed wall
time falls about 16%; BigInt allocation count falls 90.5%. At 10,000 conflicts
the original hit the 4 GiB guard; the patch finishes at 586,285,056 sampled RSS
bytes. At 100,000 conflicts the patch finishes in 11.43 seconds with
1,461,977,088 sampled RSS bytes, including legitimate arena/proof growth.
These bounded runs return UNKNOWN, not a tensor improvement or UNSAT certificate.

The post-patch three-second counter profile still spends 79.4% of cycles in
`run_subsumption`, 9.3% in `log_learned_direct`, and 3.7% in propagation.
Subsumption accounts for 87.3% of dTLB misses; proof formatting accounts for
61.7% of L1 store misses. Next candidates are better locality in subsumption
candidate scans and direct buffered proof formatting, preserving exact hints.
This profile includes startup and is not a steady-state phase comparison.
The profiler ended its child at the duration cap, so allocation counts above
come from separately completed runs, not that interrupted profile.

## Focused checks

- Solver specs: 55/55; preprocessing specs: 31/31.
- High-offset/high-clause-id packed watches: 3/3.
- Large proof artifact alignment: 2/2, including unchanged trusted lazy path.
- `python3 bits/tungsten-wassat/spec/packed_allocations_test.py`: 100,000
  packed iterations, zero BigInt allocations. This is a native allocation
  regression, not a speed threshold.
- 128 brute-force-checked CNFs, run before and after: 26 SAT models checked
  literally; 102 UNSAT cases independently WRAT-verified for each binary.
- Two tensor-encoding controls: exact SAT model and independently checked WRAT
  UNSAT proof.

Evidence, raw profiles, measurements, sources and checks are under
`/tmp/wassat-allocation-audit-20260914/`; `packed-v2.svg` is the counter flame
graph. No full repository test suite was run. No search/reference policy was
changed, and no commit or push was made by this audit.

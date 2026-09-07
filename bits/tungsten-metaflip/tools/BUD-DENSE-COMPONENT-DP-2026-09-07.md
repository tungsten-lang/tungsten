# Exact dense-component packing backend — 2026-09-07

This optional **offline** backend accelerates the small disjoint-set problems
inside bud packing. It does not change the running flip fleet, its seeds,
`bud_packings.rb`, or its CPU/GPU kernels. It is not a tensor-rank oracle.

Build and test from `bits/tungsten-metaflip`:

```sh
../../bin/tungsten --release --native \
  -o /private/tmp/metaflip-component-dp tools/bud_component_dp.w
METAFLIP_COMPONENT_DP_BINARY=/private/tmp/metaflip-component-dp \
  ruby spec/bud_component_dp_test.rb
```

`MetaflipComponentDP.solve_batch(binary, jobs)` accepts jobs of the form
`{vertices: n, max_states: budget, edges: {mask => positive_gain}}` and returns
the exact maximum gain, selected disjoint masks, and operation counts. It
supports 1..16 vertices and 64-bit aggregate costs, charging exactly
`2^(n-1)` states. Input edge gains must be at most one billion. The Ruby layer
rechecks selected-mask membership, nonoverlap, and the gain sum. Callers must
still validate the tensor groups and complete cover.

`solve_component` compresses arbitrary parent-term indices into this local
mask domain. It returns `nil` for sparse, oversized, or over-budget components
so the caller can retain its bounded fallback. It is not yet wired into the
shared solver. In a future integration, dispatching only dense components of
at least 12 vertices is the conservative measured starting point: process
startup hurt the smaller 10-vertex wall-time control.

The source-pinned raw/native/native/raw experiment found identical exact
costs and 3.27×/22.89× lower aggregate CPU time on 10-/12-vertex cases. The
complete 56-output construction replay and measurement evidence are in
[the frozen follow-up](../../../benchmarks/matmul/metaflip/near_packing_followup_audit_2026_09_07/README.md).
Those ratios are packing-workload results, not improvements to flip/s.

## Search follow-up

A separate process used the native backend only for 12..16-vertex components,
keeping the original generator, baseline safeguard, 50,000-candidate limit,
24-vertex cutoff, and 50,000-state budget. The shared source files and the old
live job were not modified.

It completed all 260 scale cases for the exact parents `(1,12,15)`,
`(12,15,1)`, and `(12,15,31)` in 184.285 seconds wall / 107.410 seconds CPU,
including 1,380 native component calls. It retained 35 distinct legal covers.
Only 12 cases finished without a model cutoff; all 248 remaining results are
explicitly incomplete. There were no direct local-price improvements.

The independent composition-side checker verified every retained cover's
term partition and factor maps, then repriced all 35 covers across the
1,519-parent block/Kronecker/bud model. This added no further improvement.
That is a bounded negative, not proof that these parents cannot help.

Working replay evidence (not canonical archive entries):

- `/private/tmp/metaflip-component-dp-study-20260907`: matched controls.
- `/private/tmp/metaflip-dense-parent-packings-20260907`: all 260 cases.
- `/private/tmp/metaflip-dense-packing-closure-20260907`: checked cover transfer.

The native component unit suite passes 4 tests / 344 assertions, including
160 independently solved random graphs, a full 16-vertex edge inventory,
an 8-billion optimum, and malformed input / insufficient-budget rejection.
No commit, publication, or canonical archive promotion was performed.

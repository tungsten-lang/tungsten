# Sequential Tungsten improvements

Requested 2026-09-04. Worktree: `codex/tungsten-next-sequential`, starting at
`f4dbdbf6`. Work proceeds in the user's numbered order. The original checkout
contains unrelated staged and unstaged work and is not part of this branch.
Only focused checks are run locally; the complete suite belongs to CI.

## Queue and acceptance

| Item | Work | Acceptance | Status |
| --- | --- | --- | --- |
| 2 | Experiment with dependency-aware incremental compilation | Source-edit invalidation, uncached LLVM/sidemap identity, bootstrap fixed point, matched edit-to-run measurements | Prefix experiment completed; not promoted; general per-file lowering remains open |
| 4 | Safe LSP refactoring | Semantic rename and code-action contracts; reject ambiguous edits | Implemented parameter rename and duplicate-import quick fix; 14 protocol cases and executable parity passed |
| 6 | Python/NumPy bridge proof of concept | Real round trip, ownership/copy contract, correctness and timing | Passed; process/file boundary costs 8.612 ms vs 1.001 ms NumPy on the one-million-element polynomial |
| 7 | Explain missed optimizations | Source-located facts from actual compiler decisions | Implemented text/JSON report; no-execution and baseline LLVM/sidemap identity passed |
| 8 | Source-level debugging | Editor/debugger integration and readable Tungsten values | LLDB summaries, source-map breakpoints, editor templates; real LLDB/native debug build passed; full local-variable DWARF remains open |
| 10 | Separate purity and memoization | Concrete design with compatibility and effect rules | Proposed in purity-and-memoization.md; current fn behavior preserved |
| 11 | Exhaustive destructuring matches | Concrete AST/WIRE examples, grammar, exhaustiveness rules | Proposed named-field exhaustive case in exhaustive-patterns.md |
| 15 | Event-loop waits | Concrete migration design | Proposed staged wait-token/deadline migration in event-loop-waits.md; scheduler implementation remains open |
| 17 | Small matrix allocation | Correctness and matched value-semantic/operator measurements | Added add_into/sub_into to Mat2/3/4 and Mat2.mul_into; numerical/alias checks and paired timings passed |
| 18 | Shape safety and performance | Specify checks/elision and measure small-matrix overhead | Fixed-size constructor length guards added; invalid/valid cases and before/after paired timings passed; mutable storage can still invalidate shape |
| 19 | HDF5 interoperability | Foreign fixtures, metadata and multidimensional shapes | Optional standard h5py bridge; compiled Tungsten/independent h5py round trip and negative cases passed |
| 20 | Columnar interchange | Standards-compatible independent round trip | Optional standard Parquet/Arrow IPC bridge; independent exact schema/metadata/null/value round trips passed |
| 21 | Versioned unit contexts | Proposed syntax and provenance/inheritance semantics | Queued design |
| 22 | Reproducible experiments | Concrete manifest design and integration example | Queued design |
| 23 | Certificate inspection | Concrete presentation protocol preserving proof levels | Queued design |
| 25 | Portable GPU subset | Machine-readable capabilities and shared dialect checks | Queued |
| 26 | `bin/tungsten notes` and Notes integration | Locate app, launcher, structured rendering protocol proposal | Queued |
| 27 | Scoped WASM target | Runnable numerical subset with explicit limits | Queued |
| 29 | Tungsten Notes flagship | End-to-end example joining the supported capabilities | Queued |

## Item 2: initial evidence

The current compiler already persists protected Core, parsed files, whole
imported-library WIRE cohorts, rendered functions, and final link artifacts.
`compiler/lib/lowering/library_cache.w` keys the entire library cohort on its
source manifest and the whole-program ABI/inference context. Each restored
cohort is tied to an exact counter/string boundary. Per-file reuse therefore
must preserve context invalidation and must not splice incompatible global
symbol IDs or restore stale analysis state.

Baseline bootstrap passed from this worktree's committed sources, including
stage-1/stage-2 LLVM identity. Its log is `build/reports/bootstrap-baseline.log`.
The prefix experiment and results are in `experiments/incremental-prefix/`.
